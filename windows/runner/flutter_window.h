#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>

#include "command_pipe.h"
#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  // |start_minimized| — запуск из enitor-cli для ассистента: окно появляется
  // свёрнутым и не отнимает фокус.
  FlutterWindow(const flutter::DartProject& project, bool start_minimized);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Канал команд для enitor-cli, MCP и ссылок со второго экземпляра.
  std::unique_ptr<CommandPipe> command_pipe_;

  bool start_minimized_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
