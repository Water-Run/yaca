/*
Author: WaterRun
Date: 2026-10-08
File: yaca_pty.h
Description: Recognizes Cygwin PTYs on XP APIs and contains fixed host stty mode/query subprocesses with bounded restoration and cleanup.
*/

#ifndef YACA_PTY_H
#define YACA_PTY_H

#include <wchar.h>

/* @struct yaca_pty_state Host stty executable and saved Cygwin PTY settings.
 * @field stty WCHAR[4096] Absolute host stty path used to change the PTY mode.
 * @field saved char[1024] Serialized original stty settings for restoration.
 * @field active int Whether the saved settings need to be restored.
 */
typedef struct yaca_pty_state
{
  WCHAR stty[4096];
  char saved[1024];
  int active;
} yaca_pty_state;

/* Cygwin's documented pipe-name convention distinguishes a PTY from an
** ordinary redirected stream. Query the name using the pre-Vista NT API.
** https://cygwin.com/pipermail/cygwin/2015-June/222067.html
*/
/* Recognize only the bounded documented Cygwin PTY pipe-name forms.
 * @param handle HANDLE Borrowed input handle; this function never closes it.
 * @return int One for a pipe whose queried name matches the exact admitted prefix/id/direction; zero for unavailable APIs or any other handle/name.
 * @effect Reads kernel handle type/name and resolves the fixed ntdll query without starting a process or changing modes.
 */
static int yaca_is_cygwin_pty(HANDLE handle)
{
  /* @struct io_status Native I/O status block passed to NtQueryInformationFile.
   * @field value union Completion status or native pointer slot.
   * @field information ULONG_PTR Number of information bytes reported by the query.
   */
  struct
  {
    /* @struct value Native I/O status union used by the query API.
     * @field status LONG NTSTATUS completion code.
     * @field pointer PVOID Native pointer representation of the same status slot.
     */
    union { LONG status; PVOID pointer; } value;
    ULONG_PTR information;
  } io_status;
  /* @struct name Bounded result buffer for the native pipe name.
   * @field length ULONG Number of valid bytes in name.
   * @field name WCHAR[512] UTF-16 pipe name returned by the kernel.
   */
  struct { ULONG length; WCHAR name[512]; } name;
  /* Reads the native name used to identify a Cygwin PTY pipe.
   * @callback query_type Dynamically resolved native pipe-name query.
   * @param arg1 HANDLE Pipe handle whose native name is queried.
   * @param arg2 PVOID Caller-owned I/O status block receiving status/information.
   * @param arg3 PVOID Caller-owned FILE_NAME_INFORMATION buffer receiving the bounded pipe name.
   * @param arg4 ULONG Information-buffer capacity in bytes.
   * @param arg5 int Native information class selector.
   * @return LONG status Native query completion status.
   */
  typedef LONG (NTAPI *query_type)(HANDLE, PVOID, PVOID, ULONG, int);
  /* @struct function Union converting the dynamically loaded symbol to its query signature.
   * @field address FARPROC Untyped GetProcAddress result.
   * @field query query_type Typed NtQueryInformationFile function pointer.
   */
  union { FARPROC address; query_type query; } function;
  const WCHAR *cursor;
  size_t index;

  if (handle == NULL || handle == INVALID_HANDLE_VALUE
      || GetFileType(handle) != FILE_TYPE_PIPE)
  {
    return 0;
  }
  function.address = GetProcAddress(GetModuleHandleW(L"ntdll.dll"),
    "NtQueryInformationFile");
  if (function.address == NULL
      || function.query(handle, &io_status, &name, sizeof(name), 9) < 0
      || name.length < 39 * sizeof(WCHAR)
      || name.length >= sizeof(name.name) || name.length % sizeof(WCHAR) != 0)
  {
    return 0;
  }
  name.name[name.length / sizeof(WCHAR)] = L'\0';
  cursor = name.name;
  if (wcsncmp(cursor, L"\\cygwin-", 8) != 0)
  {
    return 0;
  }
  cursor += 8;
  for (index = 0; index < 16; index++)
  {
    WCHAR value = cursor[index];
    if (!((value >= L'0' && value <= L'9')
        || (value >= L'a' && value <= L'f')
        || (value >= L'A' && value <= L'F')))
    {
      return 0;
    }
  }
  cursor += 16;
  if (wcsncmp(cursor, L"-pty", 4) != 0)
  {
    return 0;
  }
  cursor += 4;
  if (*cursor < L'0' || *cursor > L'9')
  {
    return 0;
  }
  while (*cursor >= L'0' && *cursor <= L'9') cursor++;
  return wcscmp(cursor, L"-from-master") == 0
    || wcscmp(cursor, L"-to-master") == 0
    || wcscmp(cursor, L"-from-master-nat") == 0
    || wcscmp(cursor, L"-to-master-nat") == 0;
}

/* Use only the host's Cygwin coreutils, from its inherited PATH, with explicit
** application name and fixed arguments. No command shell or tools/ is used.
** The adjacent Cygwin DLL is necessary to manipulate that host's terminal.
*/
/* Locate the host stty from inherited PATH and require its adjacent Cygwin DLL.
 * @param state yaca_pty_state* Caller-owned state receiving the absolute stty path on success.
 * @return int One for a bounded quote-free stty path with an adjacent regular cygwin1.dll; zero for allocation/API/path/attribute failure.
 * @effect Reads PATH and host filesystem attributes; failure may leave an unusable path in state, which callers must ignore.
 * @ownership Frees its temporary PATH allocation on every return; no process or library is loaded here.
 */
static int yaca_find_stty(yaca_pty_state *state)
{
  WCHAR *path;
  WCHAR library[4096];
  WCHAR *leaf;
  DWORD size;
  DWORD result;

  size = GetEnvironmentVariableW(L"PATH", NULL, 0);
  if (size == 0 || size > 32768) return 0;
  path = (WCHAR *)malloc((size_t)size * sizeof(WCHAR));
  if (path == NULL) return 0;
  result = GetEnvironmentVariableW(L"PATH", path, size);
  if (result == 0 || result >= size)
  {
    free(path);
    return 0;
  }
  result = SearchPathW(path, L"stty.exe", NULL, 4096, state->stty, NULL);
  free(path);
  if (result == 0 || result >= 4096 || wcschr(state->stty, L'"') != NULL) return 0;
  wcscpy(library, state->stty);
  leaf = wcsrchr(library, L'\\');
  if (leaf == NULL || (size_t)(leaf - library) + 13 >= 4096) return 0;
  wcscpy(leaf + 1, L"cygwin1.dll");
  result = GetFileAttributesW(library);
  return result != INVALID_FILE_ATTRIBUTES && !(result & FILE_ATTRIBUTE_DIRECTORY);
}

/* stty -g produces less than one KiB. A bounded wait and output pipe keep a
** damaged installation from hanging startup. The exact input handle is
** inherited: stty must recognize that PTY, never a guessed /dev/pty number.
*/
/* Runs host stty against the inherited PTY with a bounded wait.
 * @param state yaca_pty_state* Borrowed validated host stty path; saved mode and active state are not changed here.
 * @param options const_char* Fixed mode/query or validated serialized restore options, encoded as UTF-8.
 * @param output char* Optional caller-owned 1024-byte query destination; NULL for mode changes.
 * @return int One for an observed zero exit and bounded output; zero on setup/wait/exit/output failure.
 * @effect Starts stty suspended, admits it to an independent kill-on-close job, then resumes it with the exact inherited stdin.
 * @ownership Owns temporary pipes, NUL/input duplicates, job and child handles through cleanup; failure never resumes an unassigned child.
 */
static int yaca_stty(yaca_pty_state *state, const char *options, char *output)
{
  SECURITY_ATTRIBUTES security;
  STARTUPINFOW startup;
  PROCESS_INFORMATION child;
  HANDLE input = INVALID_HANDLE_VALUE;
  HANDLE read_pipe = NULL;
  HANDLE write_pipe = NULL;
  HANDLE null_handle = INVALID_HANDLE_VALUE;
  HANDLE job = NULL;
  JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits;
  WCHAR command[6144];
  WCHAR wide_options[1024];
  DWORD exit_code;
  DWORD available;
  DWORD received;
  DWORD creation_flags;
  int ok = 0;

  memset(&child, 0, sizeof(child));

  if (!MultiByteToWideChar(CP_UTF8, 0, options, -1, wide_options, 1024)) return 0;
  if (_snwprintf(command, 6144, L"\"%ls\" %ls", state->stty, wide_options) < 0) return 0;
  memset(&security, 0, sizeof(security));
  security.nLength = sizeof(security);
  security.bInheritHandle = TRUE;
  if (!DuplicateHandle(GetCurrentProcess(), GetStdHandle(STD_INPUT_HANDLE),
      GetCurrentProcess(), &input, 0, TRUE, DUPLICATE_SAME_ACCESS)) goto done;
  if (!CreatePipe(&read_pipe, &write_pipe, &security, 0)
      || !SetHandleInformation(read_pipe, HANDLE_FLAG_INHERIT, 0)) goto done;
  null_handle = CreateFileW(L"NUL", GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE,
    &security, OPEN_EXISTING, 0, NULL);
  if (null_handle == INVALID_HANDLE_VALUE) goto done;
  job = CreateJobObjectW(NULL, NULL);
  if (job == NULL) goto done;
  memset(&limits, 0, sizeof(limits));
  limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
  if (!SetInformationJobObject(job, JobObjectExtendedLimitInformation,
      &limits, sizeof(limits))) goto done;
  memset(&startup, 0, sizeof(startup));
  startup.cb = sizeof(startup);
  startup.dwFlags = STARTF_USESTDHANDLES;
  startup.hStdInput = input;
  startup.hStdOutput = write_pipe;
  startup.hStdError = null_handle;
  creation_flags = CREATE_SUSPENDED | CREATE_NO_WINDOW;
  memset(&limits, 0, sizeof(limits));
  if (QueryInformationJobObject(NULL, JobObjectExtendedLimitInformation,
      &limits, sizeof(limits), NULL)
      && (limits.BasicLimitInformation.LimitFlags & JOB_OBJECT_LIMIT_BREAKAWAY_OK))
  {
    creation_flags |= CREATE_BREAKAWAY_FROM_JOB;
  }
  if (!CreateProcessW(state->stty, command, NULL, NULL, TRUE, creation_flags, NULL, NULL,
      &startup, &child)) goto done;
  if (!AssignProcessToJobObject(job, child.hProcess)
      || ResumeThread(child.hThread) == (DWORD)-1) goto done;
  CloseHandle(child.hThread);
  child.hThread = NULL;
  if (WaitForSingleObject(child.hProcess, 3000) != WAIT_OBJECT_0)
  {
    goto done;
  }
  ok = GetExitCodeProcess(child.hProcess, &exit_code) && exit_code == 0;
  if (ok && output != NULL)
  {
    ok = PeekNamedPipe(read_pipe, NULL, 0, NULL, &available, NULL)
      && available > 0 && available < 1024;
    if (ok)
    {
      ok = ReadFile(read_pipe, output, available, &received, NULL) && received == available;
      if (ok) output[received] = '\0';
    }
  }
done:
  /* Closing the independent job stops admitted processes even if direct
  ** termination fails. An unassigned child is still suspended and is stopped
  ** here without ever executing stty or modifying the terminal. */
  if (job != NULL) CloseHandle(job);
  if (child.hProcess != NULL)
  {
    if (WaitForSingleObject(child.hProcess, 0U) != WAIT_OBJECT_0)
    {
      TerminateProcess(child.hProcess, 1U);
      if (WaitForSingleObject(child.hProcess, 1000U) != WAIT_OBJECT_0) ok = 0;
    }
    CloseHandle(child.hProcess);
  }
  if (child.hThread != NULL) CloseHandle(child.hThread);
  if (input != INVALID_HANDLE_VALUE) CloseHandle(input);
  if (read_pipe != NULL) CloseHandle(read_pipe);
  if (write_pipe != NULL) CloseHandle(write_pipe);
  if (null_handle != INVALID_HANDLE_VALUE) CloseHandle(null_handle);
  return ok;
}

/* Restore the retained host mode and clear ownership only after acknowledged stty success.
 * @param state yaca_pty_state* Owner retaining the validated saved mode and host executable.
 * @return int One for inactive or successfully restored state; zero when the bounded restore command fails.
 * @effect May change the actual inherited PTY mode; failed restoration keeps active set for another attempt.
 */
static int yaca_pty_restore(yaca_pty_state *state)
{
  if (!state->active) return 1;
  if (!yaca_stty(state, state->saved, NULL)) return 0;
  state->active = 0;
  return 1;
}

/* Capture a validated serialized PTY mode before attempting cooked/raw entry.
 * @param state yaca_pty_state* Fresh caller-owned state receiving host path, saved mode and restoration ownership.
 * @param cooked int Nonzero selects canonical echo/signals; zero selects hidden noncanonical no-signals input with min=1/time=0.
 * @return int One after successful mode entry; zero on lookup/query/format/apply failure, retaining active if attempted rollback also fails.
 * @effect Runs fixed host queries/mode commands; failed apply attempts rollback through the same bounded helper.
 * @ownership Sets active before a mode change; saved mode remains owned until a successful restore clears it.
 */
static int yaca_pty_start(yaca_pty_state *state, int cooked)
{
  size_t length;
  size_t index;
  const char *options;

  if (!yaca_find_stty(state) || !yaca_stty(state, "-g", state->saved)) return 0;
  length = strcspn(state->saved, "\r\n");
  state->saved[length] = '\0';
  if (length == 0) return 0;
  for (index = 0; index < length; index++)
  {
    char value = state->saved[index];
    if (!((value >= '0' && value <= '9') || (value >= 'a' && value <= 'f')
        || (value >= 'A' && value <= 'F') || value == ':')) return 0;
  }
  state->active = 1;
  options = cooked ? "icanon echo isig icrnl" : "-icanon -echo -isig -ixon min 1 time 0";
  if (!yaca_stty(state, options, NULL))
  {
    yaca_pty_restore(state);
    return 0;
  }
  return 1;
}

#endif
