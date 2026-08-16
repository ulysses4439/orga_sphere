#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>

#include "flutter_window.h"
#include "utils.h"

namespace {

// ---------------------------------------------------------------------------
// Einzelinstanz
//
// Windows startet bei jedem Klick auf Verknuepfung, Kachel oder EXE einen
// neuen Prozess – anders als Android, wo das System die vorhandene Activity
// wiederverwendet. Ohne die Sperre unten laufen dann mehrere OrgaSphere-
// Fenster nebeneinander, jedes mit eigenem Zustand und eigenem Polling.
//
// Der zweite Start erkennt am benannten Mutex, dass bereits eine Instanz
// laeuft, holt deren Fenster in den Vordergrund und beendet sich sofort.
// ---------------------------------------------------------------------------

// "Local\" bedeutet: pro Windows-Sitzung. Ein zweiter angemeldeter Benutzer
// darf OrgaSphere weiterhin starten – sein Fenster liegt auf einem anderen
// Desktop und liesse sich von hier ohnehin nicht in den Vordergrund holen.
constexpr const wchar_t kSingleInstanceMutexName[] =
    L"Local\\OrgaSphere.SingleInstance";

// Fensterklasse des Flutter-Runners. Sie ist bei JEDER Flutter-App gleich,
// taugt also allein nicht zur Identifikation – deshalb wird zusaetzlich der
// Pfad der laufenden EXE verglichen.
constexpr const wchar_t kFlutterWindowClassName[] =
    L"FLUTTER_RUNNER_WIN32_WINDOW";

// So lange wartet der zweite Start auf das Fenster der ersten Instanz. Noetig,
// wenn zweimal kurz hintereinander geklickt wird: Der Mutex existiert dann
// schon, das Fenster aber noch nicht.
constexpr int kFocusRetryCount = 20;
constexpr DWORD kFocusRetryDelayMs = 100;

std::wstring GetOwnImagePath() {
  wchar_t path[MAX_PATH] = {};
  DWORD length = ::GetModuleFileNameW(nullptr, path, MAX_PATH);
  return std::wstring(path, length);
}

std::wstring GetProcessImagePath(DWORD process_id) {
  HANDLE process =
      ::OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, process_id);
  if (process == nullptr) {
    return std::wstring();
  }
  wchar_t path[MAX_PATH] = {};
  DWORD length = MAX_PATH;
  std::wstring result;
  if (::QueryFullProcessImageNameW(process, 0, path, &length)) {
    result.assign(path, length);
  }
  ::CloseHandle(process);
  return result;
}

struct FindWindowContext {
  std::wstring image_path;
  DWORD own_process_id;
  HWND result;
};

BOOL CALLBACK FindExistingWindowProc(HWND window, LPARAM lparam) {
  auto* context = reinterpret_cast<FindWindowContext*>(lparam);

  wchar_t class_name[64] = {};
  ::GetClassNameW(window, class_name, ARRAYSIZE(class_name));
  if (::wcscmp(class_name, kFlutterWindowClassName) != 0) {
    return TRUE;
  }

  DWORD process_id = 0;
  ::GetWindowThreadProcessId(window, &process_id);
  if (process_id == 0 || process_id == context->own_process_id) {
    return TRUE;
  }

  // Nur ein Fenster derselben EXE zaehlt, sonst wuerde eine beliebige andere
  // Flutter-Anwendung in den Vordergrund geholt.
  if (::_wcsicmp(GetProcessImagePath(process_id).c_str(),
                 context->image_path.c_str()) != 0) {
    return TRUE;
  }

  context->result = window;
  return FALSE;  // gefunden – Aufzaehlung beenden
}

HWND FindExistingMainWindow() {
  FindWindowContext context{GetOwnImagePath(), ::GetCurrentProcessId(),
                            nullptr};
  if (context.image_path.empty()) {
    return nullptr;
  }
  ::EnumWindows(FindExistingWindowProc,
                reinterpret_cast<LPARAM>(&context));
  return context.result;
}

void FocusExistingWindow(HWND window) {
  if (::IsIconic(window)) {
    ::ShowWindow(window, SW_RESTORE);
  } else {
    ::ShowWindow(window, SW_SHOW);
  }

  if (::SetForegroundWindow(window)) {
    return;
  }

  // Windows laesst SetForegroundWindow nur vom Vordergrundprozess zu. Beim
  // Doppelklick ist dieser Prozess das normalerweise; falls nicht, blinkt sonst
  // nur die Taskleiste. Das kurzzeitige Verbinden der Eingabewarteschlangen
  // hebt die Beschraenkung auf.
  DWORD target_thread = ::GetWindowThreadProcessId(window, nullptr);
  DWORD own_thread = ::GetCurrentThreadId();
  if (target_thread == 0 || target_thread == own_thread) {
    return;
  }
  if (::AttachThreadInput(own_thread, target_thread, TRUE)) {
    ::SetForegroundWindow(window);
    ::BringWindowToTop(window);
    ::AttachThreadInput(own_thread, target_thread, FALSE);
  }
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Laeuft OrgaSphere schon? Dann nur dessen Fenster nach vorn holen. Der Mutex
  // wird bis zum Prozessende gehalten. Schlaegt CreateMutexW fehl, startet die
  // App normal weiter – lieber zwei Fenster als gar keins.
  HANDLE single_instance_mutex =
      ::CreateMutexW(nullptr, TRUE, kSingleInstanceMutexName);
  if (single_instance_mutex != nullptr &&
      ::GetLastError() == ERROR_ALREADY_EXISTS) {
    for (int attempt = 0; attempt < kFocusRetryCount; ++attempt) {
      HWND existing = FindExistingMainWindow();
      if (existing != nullptr) {
        FocusExistingWindow(existing);
        break;
      }
      ::Sleep(kFocusRetryDelayMs);
    }
    ::CloseHandle(single_instance_mutex);
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
  // Versionsnummer im Fenstertitel (grauer Titelbalken). Bei jeder
  // Versionserhöhung hier mit pubspec.yaml und kAppVersion synchron halten.
  if (!window.Create(L"OrgaSphere 1.0.29", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();

  if (single_instance_mutex != nullptr) {
    ::ReleaseMutex(single_instance_mutex);
    ::CloseHandle(single_instance_mutex);
  }
  return EXIT_SUCCESS;
}
