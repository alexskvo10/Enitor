#include "command_pipe.h"

#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <sddl.h>

#include <cstdint>
#include <mutex>
#include <vector>

namespace {

constexpr DWORD kMaxFrame = 64 * 1024;
constexpr DWORD kTimeoutMs = 5000;

// Ответ, который сочиняет сам раннер (Dart не успел или кадр битый). Текст
// по-английски: локализация живёт в Dart, а до него дело не дошло.
std::string ErrorReply(const char* code, const char* message) {
  return std::string("{\"v\":1,\"ok\":false,\"error\":{\"code\":\"") + code +
         "\",\"message\":\"" + message + "\"},\"warnings\":[]}";
}

std::wstring CurrentUserSid() {
  HANDLE token = nullptr;
  if (!::OpenProcessToken(::GetCurrentProcess(), TOKEN_QUERY, &token)) {
    return L"";
  }
  DWORD size = 0;
  ::GetTokenInformation(token, TokenUser, nullptr, 0, &size);
  std::vector<BYTE> buffer(size);
  std::wstring result;
  if (size > 0 &&
      ::GetTokenInformation(token, TokenUser, buffer.data(), size, &size)) {
    LPWSTR sid = nullptr;
    if (::ConvertSidToStringSidW(
            reinterpret_cast<TOKEN_USER*>(buffer.data())->User.Sid, &sid)) {
      result = sid;
      ::LocalFree(sid);
    }
  }
  ::CloseHandle(token);
  return result;
}

// Читает или пишет ровно n байт по перекрытому вводу-выводу. Ждёт не
// дольше timeout_ms и прерывается по stop (если он задан): зависший клиент
// не держит поток канала и не мешает закрыть приложение.
bool IoExact(HANDLE pipe, bool write, char* buffer, DWORD n, HANDLE stop) {
  DWORD done = 0;
  while (done < n) {
    OVERLAPPED ov{};
    ov.hEvent = ::CreateEventW(nullptr, TRUE, FALSE, nullptr);
    if (!ov.hEvent) return false;
    const BOOL started =
        write ? ::WriteFile(pipe, buffer + done, n - done, nullptr, &ov)
              : ::ReadFile(pipe, buffer + done, n - done, nullptr, &ov);
    if (!started && ::GetLastError() != ERROR_IO_PENDING) {
      ::CloseHandle(ov.hEvent);
      return false;
    }
    HANDLE waits[2] = {ov.hEvent, stop};
    const DWORD waited =
        ::WaitForMultipleObjects(stop ? 2 : 1, waits, FALSE, kTimeoutMs);
    DWORD got = 0;
    if (waited != WAIT_OBJECT_0) {
      ::CancelIoEx(pipe, &ov);
      ::GetOverlappedResult(pipe, &ov, &got, TRUE);
      ::CloseHandle(ov.hEvent);
      return false;
    }
    const BOOL ok = ::GetOverlappedResult(pipe, &ov, &got, FALSE);
    ::CloseHandle(ov.hEvent);
    if (!ok || got == 0) return false;
    done += got;
  }
  return true;
}

bool WriteFrame(HANDLE pipe, const std::string& json, HANDLE stop) {
  const auto len = static_cast<uint32_t>(json.size());
  char header[4] = {static_cast<char>(len & 0xFF),
                    static_cast<char>((len >> 8) & 0xFF),
                    static_cast<char>((len >> 16) & 0xFF),
                    static_cast<char>((len >> 24) & 0xFF)};
  return IoExact(pipe, true, header, 4, stop) &&
         IoExact(pipe, true, const_cast<char*>(json.data()), len, stop);
}

// Читает кадр. Пустой и слишком длинный — отказ с ответом об ошибке.
bool ReadFrame(HANDLE pipe, std::string* json, std::string* error,
               HANDLE stop) {
  unsigned char header[4];
  if (!IoExact(pipe, false, reinterpret_cast<char*>(header), 4, stop)) {
    return false;
  }
  const uint32_t len = header[0] | (header[1] << 8) | (header[2] << 16) |
                       (static_cast<uint32_t>(header[3]) << 24);
  if (len == 0 || len > kMaxFrame) {
    *error = ErrorReply("invalid_args", "Frame is empty or larger than 64 KB.");
    return true;
  }
  json->resize(len);
  return IoExact(pipe, false, json->data(), len, stop);
}

}  // namespace

std::wstring CommandPipeName() {
  return L"\\\\.\\pipe\\Enitor-" + CurrentUserSid();
}

bool SendToRunningInstance(const std::string& json, std::string* reply) {
  const std::wstring name = CommandPipeName();
  // Окно могло только что запуститься и ещё не поднять канал или Dart —
  // пробуем до ~4 с.
  for (int attempt = 0; attempt < 20; ++attempt) {
    if (!::WaitNamedPipeW(name.c_str(), 200)) {
      ::Sleep(200);
      continue;
    }
    // SECURITY_IDENTIFICATION: сервер канала может узнать, кто мы, но не
    // действовать от нашего имени.
    HANDLE pipe = ::CreateFileW(
        name.c_str(), GENERIC_READ | GENERIC_WRITE, 0, nullptr, OPEN_EXISTING,
        FILE_FLAG_OVERLAPPED | SECURITY_SQOS_PRESENT | SECURITY_IDENTIFICATION,
        nullptr);
    if (pipe == INVALID_HANDLE_VALUE) {
      ::Sleep(200);
      continue;
    }
    std::string answer, error;
    if (!WriteFrame(pipe, json, nullptr)) {
      ::CloseHandle(pipe);
      ::Sleep(200);
      continue;
    }
    // Запрос ушёл: без ответа не повторяем — окно могло его уже выполнить,
    // и повтор открыл бы вторую такую же анкету.
    const bool ok = ReadFrame(pipe, &answer, &error, nullptr) && error.empty();
    ::CloseHandle(pipe);
    if (!ok) return false;
    if (answer.find("\"not_ready\"") == std::string::npos) {
      if (reply) *reply = answer;
      return true;
    }
    ::Sleep(200);
  }
  return false;
}

struct CommandPipe::Request {
  Request() : done(::CreateEventW(nullptr, TRUE, FALSE, nullptr)) {}
  ~Request() {
    if (done) ::CloseHandle(done);
  }

  void Finish(std::string value) {
    {
      std::lock_guard<std::mutex> lock(mutex);
      reply = std::move(value);
    }
    ::SetEvent(done);
  }

  std::string json;
  std::string reply;
  std::mutex mutex;
  HANDLE done;
};

CommandPipe::CommandPipe(HWND window, flutter::BinaryMessenger* messenger)
    : window_(window),
      channel_(std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "dev.enitor.app/commands",
          &flutter::StandardMethodCodec::GetInstance())),
      stop_event_(::CreateEventW(nullptr, TRUE, FALSE, nullptr)) {
  // «Dart готов» — на Windows буфера нет (запросы ждут ответа в канале, а
  // ссылка холодного старта приходит аргументом), так что просто «да».
  channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name() == "ready") {
          result->Success();
        } else {
          result->NotImplemented();
        }
      });
}

CommandPipe::~CommandPipe() {
  stopping_ = true;
  if (stop_event_) ::SetEvent(stop_event_);
  if (thread_.joinable()) thread_.join();
  if (stop_event_) ::CloseHandle(stop_event_);
}

void CommandPipe::Start() { thread_ = std::thread([this] { Serve(); }); }

void CommandPipe::Serve() {
  const std::wstring name = CommandPipeName();
  const std::wstring sid = CurrentUserSid();
  if (sid.empty()) return;
  // DACL: полный доступ только текущему пользователю, больше никому.
  const std::wstring sddl = L"D:P(A;;GA;;;" + sid + L")";
  PSECURITY_DESCRIPTOR descriptor = nullptr;
  if (!::ConvertStringSecurityDescriptorToSecurityDescriptorW(
          sddl.c_str(), SDDL_REVISION_1, &descriptor, nullptr)) {
    return;
  }
  SECURITY_ATTRIBUTES attributes{sizeof(attributes), descriptor, FALSE};

  while (!stopping_) {
    // FILE_FLAG_FIRST_PIPE_INSTANCE: если имя уже занял кто-то другой, не
    // присоединяемся к его каналу, а ждём и пробуем снова.
    HANDLE pipe = ::CreateNamedPipeW(
        name.c_str(),
        PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED |
            FILE_FLAG_FIRST_PIPE_INSTANCE,
        PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT |
            PIPE_REJECT_REMOTE_CLIENTS,
        1, kMaxFrame + 4, kMaxFrame + 4, 0, &attributes);
    if (pipe == INVALID_HANDLE_VALUE) {
      if (::WaitForSingleObject(stop_event_, 1000) == WAIT_OBJECT_0) break;
      continue;
    }
    OVERLAPPED ov{};
    ov.hEvent = ::CreateEventW(nullptr, TRUE, FALSE, nullptr);
    bool connected = ::ConnectNamedPipe(pipe, &ov) != 0;
    if (!connected) {
      const DWORD error = ::GetLastError();
      if (error == ERROR_PIPE_CONNECTED) {
        connected = true;
      } else if (error == ERROR_IO_PENDING) {
        HANDLE waits[2] = {ov.hEvent, stop_event_};
        if (::WaitForMultipleObjects(2, waits, FALSE, INFINITE) ==
            WAIT_OBJECT_0) {
          DWORD unused = 0;
          connected = ::GetOverlappedResult(pipe, &ov, &unused, FALSE) != 0;
        } else {
          ::CancelIoEx(pipe, &ov);
        }
      }
    }
    if (ov.hEvent) ::CloseHandle(ov.hEvent);
    if (connected && !stopping_) ServeClient(pipe);
    ::DisconnectNamedPipe(pipe);
    ::CloseHandle(pipe);
  }
  ::LocalFree(descriptor);
}

void CommandPipe::ServeClient(HANDLE pipe) {
  std::string json, error;
  if (!ReadFrame(pipe, &json, &error, stop_event_)) return;
  if (!error.empty()) {
    WriteFrame(pipe, error, stop_event_);
    return;
  }
  auto request = std::make_shared<Request>();
  request->json = std::move(json);
  // Указатель на shared_ptr: если Dart ответит позже таймаута, запрос ещё
  // жив, и поток платформы не пишет в освобождённую память.
  auto* holder = new std::shared_ptr<Request>(request);
  if (!::PostMessageW(window_, kCommandPipeMessage, 0,
                      reinterpret_cast<LPARAM>(holder))) {
    delete holder;
    WriteFrame(pipe, ErrorReply("internal", "Enitor window is gone."),
               stop_event_);
    return;
  }
  HANDLE waits[2] = {request->done, stop_event_};
  std::string reply;
  if (::WaitForMultipleObjects(2, waits, FALSE, kTimeoutMs) == WAIT_OBJECT_0) {
    std::lock_guard<std::mutex> lock(request->mutex);
    reply = request->reply;
  } else {
    reply = ErrorReply("internal", "Enitor did not answer in 5 seconds.");
  }
  if (!WriteFrame(pipe, reply, stop_event_)) return;
  // DisconnectNamedPipe выбрасывает непрочитанное: клиент, не успевший
  // прочитать ответ, получал «канал закрыт» (консоль падала, а второй
  // экземпляр слал ссылку повторно — анкета дублировалась). Ждём, пока
  // клиент закроет свой конец (чтение вернёт ошибку), но не дольше таймаута.
  char probe;
  IoExact(pipe, false, &probe, 1, stop_event_);
}

void CommandPipe::HandleWindowMessage(LPARAM lparam) {
  auto* holder = reinterpret_cast<std::shared_ptr<Request>*>(lparam);
  std::shared_ptr<Request> request = *holder;
  delete holder;
  auto result = std::make_unique<
      flutter::MethodResultFunctions<flutter::EncodableValue>>(
      [request](const flutter::EncodableValue* value) {
        const auto* text =
            value ? std::get_if<std::string>(value) : nullptr;
        request->Finish(text ? *text
                             : ErrorReply("internal", "Empty reply."));
      },
      [request](const std::string&, const std::string&,
                const flutter::EncodableValue*) {
        request->Finish(ErrorReply("internal", "Enitor failed to answer."));
      },
      [request]() {
        // Dart ещё не подключил канал (самое начало запуска) — клиент
        // повторит запрос.
        request->Finish(ErrorReply("not_ready", "Enitor is still starting."));
      });
  channel_->InvokeMethod(
      "pipe", std::make_unique<flutter::EncodableValue>(request->json),
      std::move(result));
}
