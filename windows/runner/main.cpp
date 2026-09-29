#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Только один экземпляр: два процесса пишут одно и то же хранилище и
  // перезаписывают данные друг друга. Повторный запуск поднимает уже
  // открытое окно и выходит. Мьютекс живёт до конца процесса — система
  // освободит его сама, в том числе при аварийном завершении.
  ::CreateMutexW(nullptr, TRUE, L"Local\\Dev.Enitor.App.Desktop.SingleInstance");
  if (::GetLastError() == ERROR_ALREADY_EXISTS) {
    // Класс окна общий у всех Flutter-приложений, поэтому ищем ещё и по
    // заголовку.
    if (HWND existing =
            ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"Enitor")) {
      if (::IsIconic(existing)) ::ShowWindow(existing, SW_RESTORE);
      ::SetForegroundWindow(existing);
    }
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Enitor", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  // Окно открывается во всю высоту рабочей области монитора, а по ширине — под
  // максимальную ширину контента (720 логических px), чтобы по бокам не было
  // пустой «бумаги». Размер задаём до показа окна (Show вызывается на первом
  // кадре), поэтому мелькания нет; Flutter-вью подхватит новый размер по WM_SIZE.
  if (HWND hwnd = window.GetHandle()) {
    RECT work_area;
    if (::SystemParametersInfo(SPI_GETWORKAREA, 0, &work_area, 0)) {
      const UINT dpi = ::GetDpiForWindow(hwnd);
      const int width = ::MulDiv(720, dpi, 96);  // 720 логич. → физич. px
      const int height = work_area.bottom - work_area.top;
      const int x =
          work_area.left + ((work_area.right - work_area.left) - width) / 2;
      ::SetWindowPos(hwnd, nullptr, x, work_area.top, width, height,
                     SWP_NOZORDER | SWP_NOACTIVATE);
    }
  }

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
