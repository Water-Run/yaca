/*
Author: WaterRun
Date: 2026-10-08
File: windows_pty_process_faults.c
Description: Executes production PTY stty subprocess ownership against finite
fixture children, observes timeout/termination faults with independent handles,
and optionally checks actual Cygwin mode entry/restore without reading secrets.
*/

#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0501
#endif
#include <windows.h>
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

/* @enum pty_process_fault Selects one deterministic helper API rejection.
 * @field PTY_NO_FAULT Run a successful finite output child.
 * @field PTY_TERMINATE_FAIL Force the initial wait timeout and reject direct TerminateProcess.
 * @field PTY_JOB_CREATE Reject CreateJobObject before any child may start.
 * @field PTY_JOB_LIMIT Reject SetInformationJobObject before child execution.
 * @field PTY_JOB_ASSIGN Reject assignment of the suspended child.
 * @field PTY_RESUME Reject resuming the assigned child.
 */
typedef enum pty_process_fault
{
  PTY_NO_FAULT, PTY_TERMINATE_FAIL, PTY_JOB_CREATE,
  PTY_JOB_LIMIT, PTY_JOB_ASSIGN, PTY_RESUME
} pty_process_fault;

static pty_process_fault pty_fault;
static HANDLE pty_observer;
static HANDLE pty_child;
static int pty_fixture_active;
static size_t pty_cases;
static size_t pty_failures;
static unsigned int pty_live_exit_calls;
static unsigned int pty_live_exit_rejections;

/* Start an actual child and duplicate its handle solely for post-helper observation.
 * @param application LPCWSTR Actual owned fixture executable or validated host stty path.
 * @param command LPWSTR Mutable Windows command line passed unchanged to CreateProcessW.
 * @param process_security LPSECURITY_ATTRIBUTES Optional process attributes passed through unchanged.
 * @param thread_security LPSECURITY_ATTRIBUTES Optional thread attributes passed through unchanged.
 * @param inherit BOOL Production handle-inheritance choice.
 * @param flags DWORD Production creation flags, including any suspended ownership admission.
 * @param environment LPVOID Optional inherited/explicit environment passed through unchanged.
 * @param directory LPCWSTR Optional current directory passed through unchanged.
 * @param startup LPSTARTUPINFOW Actual inherited stdin/stdout/stderr fixture handles.
 * @param child LPPROCESS_INFORMATION Receives real production handles and identities.
 * @return BOOL Actual CreateProcessW result.
 * @effect Retains one independent process handle only for bounded fixture runs, not live Cygwin commands.
 */
static BOOL WINAPI pty_create_process(LPCWSTR application, LPWSTR command,
  LPSECURITY_ATTRIBUTES process_security, LPSECURITY_ATTRIBUTES thread_security,
  BOOL inherit, DWORD flags, LPVOID environment, LPCWSTR directory,
  LPSTARTUPINFOW startup, LPPROCESS_INFORMATION child)
{
  BOOL result = CreateProcessW(application, command, process_security, thread_security,
    inherit, flags, environment, directory, startup, child);
  if (result && pty_fixture_active)
  {
    assert(pty_observer == NULL);
    pty_child = child->hProcess;
    assert(DuplicateHandle(GetCurrentProcess(), child->hProcess, GetCurrentProcess(),
      &pty_observer, 0U, FALSE, DUPLICATE_SAME_ACCESS));
  }
  return result;
}

/* Inject the helper's initial timeout without changing the real child state.
 * @param handle HANDLE Production process or other handle passed to its wait.
 * @param milliseconds DWORD Requested bounded observation/join duration.
 * @return DWORD WAIT_TIMEOUT only for the selected initial three-second fixture wait; otherwise actual OS status.
 */
static DWORD WINAPI pty_wait(HANDLE handle, DWORD milliseconds)
{
  if (pty_fixture_active && pty_fault == PTY_TERMINATE_FAIL
      && handle == pty_child && milliseconds == 3000U) return WAIT_TIMEOUT;
  return WaitForSingleObject(handle, milliseconds);
}

/* Reject direct process termination only for the selected finite fixture child.
 * @param process HANDLE Actual production child handle.
 * @param code UINT Requested termination exit code passed through on non-injected calls.
 * @return BOOL FALSE with ERROR_ACCESS_DENIED for the selected fault; otherwise actual OS result.
 */
static BOOL WINAPI pty_terminate(HANDLE process, UINT code)
{
  if (pty_fixture_active && pty_fault == PTY_TERMINATE_FAIL && process == pty_child)
  {
    SetLastError(ERROR_ACCESS_DENIED);
    return FALSE;
  }
  return TerminateProcess(process, code);
}

/* Observe/reject private job creation before the helper starts its child.
 * @param security LPSECURITY_ATTRIBUTES Production job security attributes.
 * @param name LPCWSTR Optional production job name.
 * @return HANDLE NULL with ERROR_NOT_ENOUGH_MEMORY at the selected rejection; otherwise actual OS job.
 */
HANDLE WINAPI pty_create_job(LPSECURITY_ATTRIBUTES security, LPCWSTR name)
{
  if (pty_fixture_active && pty_fault == PTY_JOB_CREATE)
  {
    SetLastError(ERROR_NOT_ENOUGH_MEMORY);
    return NULL;
  }
  return CreateJobObjectW(security, name);
}

/* Reject one job limit setup before any stty code executes.
 * @param job HANDLE Production private job handle.
 * @param kind JOBOBJECTINFOCLASS Actual limit information selector.
 * @param information LPVOID Production-owned limit data passed through unchanged.
 * @param length DWORD Actual limit structure size.
 * @return BOOL FALSE with ERROR_ACCESS_DENIED for the selected fault; otherwise actual OS result.
 */
BOOL WINAPI pty_set_job(HANDLE job, JOBOBJECTINFOCLASS kind, LPVOID information, DWORD length)
{
  if (pty_fixture_active && pty_fault == PTY_JOB_LIMIT)
  {
    SetLastError(ERROR_ACCESS_DENIED);
    return FALSE;
  }
  return SetInformationJobObject(job, kind, information, length);
}

/* Reject assignment while the newly created fixture child is still suspended.
 * @param job HANDLE Production private job.
 * @param process HANDLE Actual suspended child being admitted.
 * @return BOOL FALSE with ERROR_ACCESS_DENIED for the selected fault; otherwise actual OS result.
 */
BOOL WINAPI pty_assign_job(HANDLE job, HANDLE process)
{
  if (pty_fixture_active && pty_fault == PTY_JOB_ASSIGN)
  {
    SetLastError(ERROR_ACCESS_DENIED);
    return FALSE;
  }
  return AssignProcessToJobObject(job, process);
}

/* Reject resuming the already owned child without changing its real OS thread.
 * @param thread HANDLE Production primary child thread.
 * @return DWORD Minus one with ERROR_ACCESS_DENIED for the selected fault; otherwise actual OS suspend count.
 */
DWORD WINAPI pty_resume(HANDLE thread)
{
  if (pty_fixture_active && pty_fault == PTY_RESUME)
  {
    SetLastError(ERROR_ACCESS_DENIED);
    return (DWORD)-1;
  }
  return ResumeThread(thread);
}

/* Report the real stty exit except for explicitly selected live apply/rollback rejection controls.
 * @param process HANDLE Actual completed production child handle.
 * @param code LPDWORD Receives the actual exit code or the selected nonzero failure report.
 * @return BOOL Unchanged OS query success.
 * @effect The live control changes only reported acknowledgment; actual host stty mode changes are measured independently afterward.
 */
static BOOL WINAPI pty_exit_code(HANDLE process, LPDWORD code)
{
  BOOL result = GetExitCodeProcess(process, code);
  if (result && pty_live_exit_rejections > 0U)
  {
    ++pty_live_exit_calls;
    if (pty_live_exit_calls >= 2U
        && pty_live_exit_calls < 2U + pty_live_exit_rejections) *code = 1U;
  }
  return result;
}

#define CreateProcessW pty_create_process
#define WaitForSingleObject pty_wait
#define TerminateProcess pty_terminate
#define CreateJobObjectW pty_create_job
#define SetInformationJobObject pty_set_job
#define AssignProcessToJobObject pty_assign_job
#define ResumeThread pty_resume
#define GetExitCodeProcess pty_exit_code
#include "../../native/yaca_pty.h"
#undef CreateProcessW
#undef WaitForSingleObject
#undef TerminateProcess
#undef CreateJobObjectW
#undef SetInformationJobObject
#undef AssignProcessToJobObject
#undef ResumeThread
#undef GetExitCodeProcess

/* Count actual current-process handles without acquiring an observation object.
 * @param none Uses this owned qualification process.
 * @return DWORD Exact current handle count.
 * @error Aborts when the OS cannot report handle truth.
 */
static DWORD pty_handles(void)
{
  DWORD count;
  assert(GetProcessHandleCount(GetCurrentProcess(), &count));
  return count;
}

/* Execute one actual production helper invocation and record a surviving child before baseline rescue.
 * @param fault pty_process_fault Normal operation or one selected startup/timeout rejection.
 * @param executable const_WCHAR* Absolute path of this owned fixture executable.
 * @return void No value; updates case/failure observations after genuine OS checks.
 * @effect Joins every observed child; rescues only a proven baseline survivor after recording it.
 * @error Aborts for malformed normal output or OS handle growth after complete fixture cleanup.
 */
static void pty_check(pty_process_fault fault, const WCHAR *executable)
{
  yaca_pty_state state;
  char output[1024];
  DWORD baseline = pty_handles();
  int result;
  int alive = 0;
  memset(&state, 0, sizeof(state));
  assert(wcslen(executable) < 4096U);
  wcscpy(state.stty, executable);
  pty_fault = fault;
  pty_fixture_active = 1;
  pty_observer = NULL;
  pty_child = NULL;
  result = yaca_stty(&state, fault == PTY_TERMINATE_FAIL ? "--fixture-hang" : "--fixture-output", output);
  pty_fixture_active = 0;
  if (pty_observer != NULL)
  {
    alive = WaitForSingleObject(pty_observer, 0U) == WAIT_TIMEOUT;
    if (alive)
    {
      ++pty_failures;
      printf("pty-child-survived fault=%d helper-result=%d\n", (int)fault, result);
      assert(TerminateProcess(pty_observer, 1U));
    }
    assert(WaitForSingleObject(pty_observer, 5000U) == WAIT_OBJECT_0);
    assert(CloseHandle(pty_observer));
    pty_observer = NULL;
  }
  if (fault == PTY_NO_FAULT)
    assert(result == 1 && (strcmp(output, "1:2:3\n") == 0 || strcmp(output, "1:2:3\r\n") == 0));
  else if (result != 0) ++pty_failures;
  printf("pty-process-handles fault=%d before=%lu after=%lu\n",
    (int)fault, (unsigned long)baseline, (unsigned long)pty_handles());
  fflush(stdout);
  assert(pty_handles() == baseline);
  ++pty_cases;
  printf("pty-process fault=%d child-live-after-return=%d handles-stable=1\n", (int)fault, alive);
}

/* Verify actual host Cygwin raw/cooked transitions and exact serialized mode restoration.
 * @param none Uses only the assigned live PTY and its validated host stty executable.
 * @return void No value; successful checks print actual mode restoration truth.
 * @effect Changes only this test session's terminal, restores it after each successful entry and consumes no user input.
 * @error Aborts for failed host capability, startup or mode mismatch.
 */
static void pty_live(void)
{
  yaca_pty_state state;
  char after[1024];
  int cooked;
  assert(yaca_is_cygwin_pty(GetStdHandle(STD_INPUT_HANDLE)));
  for (cooked = 0; cooked <= 1; ++cooked)
  {
    memset(&state, 0, sizeof(state));
    assert(yaca_pty_start(&state, cooked));
    assert(state.active);
    assert(yaca_pty_restore(&state));
    assert(!state.active);
    assert(yaca_stty(&state, "-g", after));
    after[strcspn(after, "\r\n")] = '\0';
    assert(strcmp(state.saved, after) == 0);
  }
  puts("pty-live raw-cooked-restored=PASS profiles=2");
  for (pty_live_exit_rejections = 1U; pty_live_exit_rejections <= 2U; ++pty_live_exit_rejections)
  {
    memset(&state, 0, sizeof(state));
    pty_live_exit_calls = 0U;
    assert(!yaca_pty_start(&state, 0));
    assert(state.active == (pty_live_exit_rejections == 2U));
    if (state.active) assert(yaca_pty_restore(&state));
    assert(!state.active);
    assert(yaca_stty(&state, "-g", after));
    after[strcspn(after, "\r\n")] = '\0';
    assert(strcmp(state.saved, after) == 0);
    printf("pty-live rejected-reports=%u rollback-and-retry=PASS\n", pty_live_exit_rejections);
  }
  pty_live_exit_rejections = 0U;
}

/* Run finite subprocess fixtures or the explicitly assigned live Cygwin restoration check.
 * @param argc int Host argument count; fixture modes are private subprocess entry points.
 * @param argv char** Optional --lifetime-only or --live selector; default runs the full fault matrix.
 * @return int Zero for complete ownership agreement; one for genuine baseline survivor/rejection failures; 64 for unknown arguments.
 * @effect Only owned finite children are started or rescued; the default matrix does not change host terminal modes.
 */
int main(int argc, char **argv)
{
  WCHAR executable[4096];
  HANDLE reader;
  HANDLE writer;
  pty_process_fault fault;
  if (argc == 2 && strcmp(argv[1], "--fixture-hang") == 0) { Sleep(8000U); return 0; }
  if (argc == 2 && strcmp(argv[1], "--fixture-output") == 0) { puts("1:2:3"); return 0; }
  if (argc == 2 && strcmp(argv[1], "--live") == 0) { pty_live(); return 0; }
  if (argc > 2 || (argc == 2 && strcmp(argv[1], "--lifetime-only") != 0)) return 64;
  assert(GetModuleFileNameW(NULL, executable, 4096U) > 0U);
  /* Initialize the OS's first-use pipe cache independently of production. */
  assert(CreatePipe(&reader, &writer, NULL, 0U));
  assert(CloseHandle(reader) && CloseHandle(writer));
  {
    DWORD before = pty_handles();
    HANDLE null_handle = CreateFileW(L"NUL", GENERIC_WRITE,
      FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, 0U, NULL);
    STARTUPINFOW startup;
    PROCESS_INFORMATION child;
    WCHAR command[4200];
    assert(null_handle != INVALID_HANDLE_VALUE && CloseHandle(null_handle));
    printf("pty-null-warmup before=%lu after=%lu\n", (unsigned long)before,
      (unsigned long)pty_handles());
    before = pty_handles();
    memset(&startup, 0, sizeof(startup));
    startup.cb = sizeof(startup);
    assert(_snwprintf(command, 4200U, L"\"%ls\" --fixture-output", executable) > 0);
    /* Independently initialize process-creation paths; this control uses the
    ** real APIs and closes every handle it acquires, without production. */
    assert(CreateProcessW(executable, command, NULL, NULL, TRUE, CREATE_NO_WINDOW,
      NULL, NULL, &startup, &child));
    assert(WaitForSingleObject(child.hProcess, 3000U) == WAIT_OBJECT_0);
    assert(CloseHandle(child.hThread) && CloseHandle(child.hProcess));
    printf("pty-create-warmup before=%lu after=%lu\n", (unsigned long)before,
      (unsigned long)pty_handles());
  }
  pty_check(PTY_NO_FAULT, executable);
  pty_check(PTY_TERMINATE_FAIL, executable);
  if (argc == 1)
    for (fault = PTY_JOB_CREATE; fault <= PTY_RESUME; ++fault) pty_check(fault, executable);
  printf("pty-process-faults cases=%zu failures=%zu\n", pty_cases, pty_failures);
  return pty_failures == 0U ? 0 : 1;
}
