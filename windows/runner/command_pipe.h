#ifndef RUNNER_COMMAND_PIPE_H_
#define RUNNER_COMMAND_PIPE_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <atomic>
#include <memory>
#include <string>
#include <thread>

// Сообщение окну: «в канале пришёл запрос, отдай его Dart». Обрабатывается
// в потоке платформы — MethodChannel можно звать только оттуда.
constexpr UINT kCommandPipeMessage = WM_APP + 0x45;

// Имя канала: \\.\pipe\Enitor-<SID текущего пользователя>. SID в имени —
// у каждого пользователя на машине свой канал, чужой не перепутать.
std::wstring CommandPipeName();

// Отправляет один кадр в уже запущенный Enitor и ждёт ответ (второй
// экземпляр с enitor://-ссылкой). false — Enitor не ответил.
bool SendToRunningInstance(const std::string& json, std::string* reply);

// Сервер именованного канала для enitor-cli, MCP и ссылок со второго
// экземпляра. Доступ — только текущему пользователю, только локально
// (PIPE_REJECT_REMOTE_CLIENTS). Кадр: 4 байта длины (little-endian) +
// UTF-8 JSON, не больше 64 КБ; на каждый запрос — ответ; таймаут 5 с.
// Сам JSON не разбирает: строка уходит в Dart как есть, разбор и все
// проверки — в одном месте, в IntegrationGateway.
class CommandPipe {
 public:
  CommandPipe(HWND window, flutter::BinaryMessenger* messenger);
  ~CommandPipe();

  CommandPipe(const CommandPipe&) = delete;
  CommandPipe& operator=(const CommandPipe&) = delete;

  void Start();

  // Вызывается окном на kCommandPipeMessage (поток платформы).
  void HandleWindowMessage(LPARAM lparam);

 private:
  struct Request;

  void Serve();
  void ServeClient(HANDLE pipe);
  void Reply(HANDLE pipe, const std::string& reply);

  HWND window_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::thread thread_;
  std::atomic<bool> stopping_{false};
  HANDLE stop_event_ = nullptr;
};

#endif  // RUNNER_COMMAND_PIPE_H_
