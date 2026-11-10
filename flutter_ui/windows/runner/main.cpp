#include <dwmapi.h>
#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <algorithm>

#include "flutter_window.h"
#include "utils.h"

#pragma comment(lib, "dwmapi.lib")

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
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

  const bool start_hidden =
      std::find(command_line_arguments.begin(), command_line_arguments.end(),
                "--startup") != command_line_arguments.end();

  // Only one instance can own the SMC device. If macndowsfan is already
  // running (possibly in the tray), bring its window back instead of starting
  // a second copy.
  ::SetLastError(0);
  HANDLE instance_mutex =
      ::CreateMutexW(nullptr, TRUE, L"Local\\macndowsfan_single_instance");
  if (instance_mutex != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    HWND existing =
        ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"macndowsfan");
    if (existing != nullptr) {
      ::ShowWindow(existing, SW_RESTORE);
      ::SetForegroundWindow(existing);
    }
    return EXIT_SUCCESS;
  }

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  window.SetStartHidden(start_hidden);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1180, 880);
  if (!window.Create(L"macndowsfan", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  // Dark title bar (Windows 10 2004+).
  BOOL dark_titlebar = TRUE;
  DwmSetWindowAttribute(window.GetHandle(), 20, &dark_titlebar,
                        sizeof(dark_titlebar));

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}

