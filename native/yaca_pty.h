/*
Author: WaterRun
Date: 2026-09-23
File: yaca_pty.h
Description: Recognizes Cygwin PTYs on XP APIs and delegates termios to host stty.
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
/* Checks is cygwin pty against the admitted native state.
 * @param handle HANDLE Operating-system handle being inspected or closed.
 * @return int result 1 for a valid Cygwin PTY pipe, otherwise 0.
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
   * @param arg2 PVOID Caller-owned information buffer.
   * @param arg3 PVOID Caller-owned I/O status block.
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
/* Locates host Cygwin stty beside cygwin1.dll.
 * @param state yaca_pty_state* Captured native state updated or compared by the operation.
 * @return int result 1 when a compatible stty path is stored in state, otherwise 0.
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
 * @param state yaca_pty_state* Captured native state updated or compared by the operation.
 * @param options const_char* The options bound to yaca stty.
 * @param output char* Caller-provided output buffer or result destination.
 * @return int result 1 when stty exits successfully and optional output is captured, otherwise 0.
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
  WCHAR command[6144];
  WCHAR wide_options[1024];
  DWORD exit_code;
  DWORD available;
  DWORD received;
  int ok = 0;

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
  memset(&startup, 0, sizeof(startup));
  memset(&child, 0, sizeof(child));
  startup.cb = sizeof(startup);
  startup.dwFlags = STARTF_USESTDHANDLES;
  startup.hStdInput = input;
  startup.hStdOutput = write_pipe;
  startup.hStdError = null_handle;
  if (!CreateProcessW(state->stty, command, NULL, NULL, TRUE, 0, NULL, NULL,
      &startup, &child)) goto done;
  CloseHandle(child.hThread);
  if (WaitForSingleObject(child.hProcess, 3000) != WAIT_OBJECT_0)
  {
    TerminateProcess(child.hProcess, 1);
    WaitForSingleObject(child.hProcess, 1000);
    CloseHandle(child.hProcess);
    goto done;
  }
  ok = GetExitCodeProcess(child.hProcess, &exit_code) && exit_code == 0;
  CloseHandle(child.hProcess);
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
  if (input != INVALID_HANDLE_VALUE) CloseHandle(input);
  if (read_pipe != NULL) CloseHandle(read_pipe);
  if (write_pipe != NULL) CloseHandle(write_pipe);
  if (null_handle != INVALID_HANDLE_VALUE) CloseHandle(null_handle);
  return ok;
}

/* Restores saved Cygwin PTY settings when they were changed.
 * @param state yaca_pty_state* Captured native state updated or compared by the operation.
 * @return int result 1 after restoration or when inactive, otherwise 0.
 */
static int yaca_pty_restore(yaca_pty_state *state)
{
  if (!state->active) return 1;
  if (!yaca_stty(state, state->saved, NULL)) return 0;
  state->active = 0;
  return 1;
}

/* Captures Cygwin PTY settings and applies cooked or raw mode.
 * @param state yaca_pty_state* Captured native state updated or compared by the operation.
 * @param cooked int The cooked bound to yaca pty start.
 * @return int result 1 when the requested mode is active, otherwise 0.
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
