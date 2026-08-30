/*
** File: yaca_native.c
** Date: 2026-08-30
** Author: WaterRun
** Description: Portable narrow native ports for filesystem, process, terminal, system identity, clocks, and SHA-256.
*/

#if !defined(_WIN32) && !defined(_POSIX_C_SOURCE)
#define _POSIX_C_SOURCE 200809L
#endif
#if !defined(_WIN32) && !defined(_XOPEN_SOURCE)
#define _XOPEN_SOURCE 700
#endif
#if !defined(_WIN32) && !defined(_GNU_SOURCE)
#define _GNU_SOURCE
#endif

#include <errno.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "lua.h"
#include "lauxlib.h"

#if defined(_WIN32)

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0501
#endif

#include <windows.h>
#include <winioctl.h>

/* SystemFunction036 is the XP-compatible Advapi32 export commonly exposed as
** RtlGenRandom.  Keep the import explicit so random bytes never fall back to
** process, clock, or C-library pseudo-random state. */
extern BOOLEAN WINAPI SystemFunction036(PVOID buffer, ULONG length);

#else

#include <fcntl.h>
#include <dirent.h>
#include <signal.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>
#if defined(__linux__)
#include <linux/fs.h>
#include <sys/ioctl.h>
#include <sys/xattr.h>
#endif

#endif

#define YACA_ABI_VERSION "yaca-native-v0.1.0"
#define YACA_FILE_METATABLE "yaca.native.file"
#define YACA_PROCESS_METATABLE "yaca.native.process"
#define YACA_TERMINAL_METATABLE "yaca.native.terminal"
#define YACA_SHA256_METATABLE "yaca.native.sha256"

#if defined(_WIN32)
#define YACA_PATH_SEPARATOR L'\\'
#else
#ifndef O_DIRECTORY
#define O_DIRECTORY 0
#endif
#endif

typedef struct yaca_identity
{
  char kind[16];
  char volume[32];
  char object[64];
  char modified[64];
  lua_Integer size;
} yaca_identity;

typedef struct yaca_file
{
#if defined(_WIN32)
  HANDLE handle;
#else
  int descriptor;
#endif
  int closed;
} yaca_file;

typedef struct yaca_process
{
#if defined(_WIN32)
  HANDLE process;
  HANDLE job;
  HANDLE stdout_read;
  HANDLE stderr_read;
  DWORD process_id;
  DWORD exit_code;
#else
  pid_t process_id;
  int stdout_read;
  int stderr_read;
  int wait_status;
#endif
  lua_Integer started_at;
  lua_Integer finished_at;
  int reaped;
  int cancel_requested;
  int terminal_emitted;
  int descendants_proven_stopped;
  int closed;
  char outcome[16];
  char exit_kind[24];
  char signal_or_exception[32];
} yaca_process;

#if defined(_WIN32)
typedef struct yaca_terminal_read
{
  HANDLE input;
  HANDLE thread;
  WCHAR *wide;
  DWORD capacity;
  volatile DWORD received;
  volatile DWORD error_value;
} yaca_terminal_read;
#endif

typedef struct yaca_terminal
{
#if defined(_WIN32)
  HANDLE input;
  DWORD original_mode;
  DWORD input_type;
  WCHAR pending_high_surrogate;
  int cooked_mode;
  yaca_terminal_read *cooked_read;
#else
  int input;
  int original_flags;
  struct termios original_mode;
#endif
  size_t maximum_input_bytes;
  int has_original_mode;
  int has_original_flags;
  int restored;
  int cancelled;
  int terminal_emitted;
  int closed;
  char outcome[16];
} yaca_terminal;

typedef struct yaca_sha256
{
  uint32_t state[8];
  uint64_t byte_count;
  unsigned char buffer[64];
  size_t buffer_length;
  int closed;
} yaca_sha256;

static void sha256_initialize(yaca_sha256 *context);
static int sha256_append(
  yaca_sha256 *context,
  const unsigned char *bytes,
  size_t length);
static void sha256_finalize(yaca_sha256 *context, unsigned char digest[32]);
#if !defined(_WIN32)
static void digest_hex(const unsigned char digest[32], char output[65]);
#endif

/*
** Pushes the common false, structured-error return shape.
*/
static int push_failure(lua_State *L, const char *code, const char *message)
{
  lua_pushboolean(L, 0);
  lua_createtable(L, 0, 2);
  lua_pushstring(L, code);
  lua_setfield(L, -2, "code");
  lua_pushstring(L, message);
  lua_setfield(L, -2, "message");
  return 2;
}

/*
** Pushes true before one result already on the stack.
*/
static int return_success(lua_State *L)
{
  lua_pushboolean(L, 1);
  lua_insert(L, -2);
  return 2;
}

static int push_true_result(lua_State *L)
{
  lua_pushboolean(L, 1);
  lua_pushboolean(L, 1);
  return 2;
}

static int checked_byte_string(
  lua_State *L,
  int index,
  const char **bytes,
  size_t *length,
  const char *code,
  const char *message)
{
  *bytes = luaL_checklstring(L, index, length);
  if (*length == 0 || memchr(*bytes, '\0', *length) != NULL)
  {
    push_failure(L, code, message);
    return 0;
  }
  return 1;
}

#if !defined(_WIN32)
static const char *errno_code(int value)
{
  switch (value)
  {
    case ENOENT:
      return "NotFound";
    case EEXIST:
      return "DestinationExists";
    case EACCES:
    case EPERM:
      return "AccessDenied";
#if defined(ENOTEMPTY)
    case ENOTEMPTY:
      return "DirectoryNotEmpty";
#endif
#if defined(ELOOP)
    case ELOOP:
      return "LinkDenied";
#endif
#if defined(EXDEV)
    case EXDEV:
      return "CrossDevice";
#endif
    default:
      return "Storage";
  }
}
#endif

#if defined(_WIN32)

static const char *windows_error_code(DWORD value)
{
  switch (value)
  {
    case ERROR_FILE_NOT_FOUND:
    case ERROR_PATH_NOT_FOUND:
      return "NotFound";
    case ERROR_FILE_EXISTS:
    case ERROR_ALREADY_EXISTS:
      return "DestinationExists";
    case ERROR_ACCESS_DENIED:
    case ERROR_SHARING_VIOLATION:
      return "AccessDenied";
    case ERROR_DIR_NOT_EMPTY:
      return "DirectoryNotEmpty";
    case ERROR_NOT_SAME_DEVICE:
      return "CrossDevice";
    default:
      return "Storage";
  }
}

/*
** Converts one strict UTF-8 string to an allocated Windows wide string.
*/
static WCHAR *utf8_to_wide(const char *bytes, size_t length)
{
  int required;
  WCHAR *result;

  if (length > (size_t)INT_MAX)
  {
    return NULL;
  }
  required = MultiByteToWideChar(
    CP_UTF8,
    MB_ERR_INVALID_CHARS,
    bytes,
    (int)length,
    NULL,
    0);
  if (required <= 0)
  {
    return NULL;
  }
  result = (WCHAR *)malloc(((size_t)required + 1U) * sizeof(WCHAR));
  if (result == NULL)
  {
    return NULL;
  }
  if (MultiByteToWideChar(
      CP_UTF8,
      MB_ERR_INVALID_CHARS,
      bytes,
      (int)length,
      result,
      required) != required)
  {
    free(result);
    return NULL;
  }
  result[required] = L'\0';
  return result;
}

static char *wide_to_utf8(const WCHAR *value)
{
  size_t wide_length;
  size_t index;
  int required;
  char *result;

  wide_length = wcslen(value);
  if (wide_length > (size_t)INT_MAX)
  {
    return NULL;
  }
  for (index = 0; index < wide_length; ++index)
  {
    unsigned int unit = (unsigned int)value[index];
    if (unit >= 0xD800U && unit <= 0xDBFFU)
    {
      if (index + 1U >= wide_length
          || (unsigned int)value[index + 1U] < 0xDC00U
          || (unsigned int)value[index + 1U] > 0xDFFFU)
      {
        return NULL;
      }
      ++index;
    }
    else if (unit >= 0xDC00U && unit <= 0xDFFFU)
    {
      return NULL;
    }
  }
  required = WideCharToMultiByte(
    CP_UTF8,
    0,
    value,
    (int)wide_length,
    NULL,
    0,
    NULL,
    NULL);
  if (required <= 0)
  {
    return NULL;
  }
  result = (char *)malloc((size_t)required + 1U);
  if (result == NULL)
  {
    return NULL;
  }
  if (WideCharToMultiByte(
      CP_UTF8,
      0,
      value,
      (int)wide_length,
      result,
      required,
      NULL,
      NULL) != required)
  {
    free(result);
    return NULL;
  }
  result[required] = '\0';
  return result;
}

static WCHAR *duplicate_wide(const WCHAR *value)
{
  size_t length = wcslen(value);
  WCHAR *copy = (WCHAR *)malloc((length + 1U) * sizeof(WCHAR));
  if (copy != NULL)
  {
    memcpy(copy, value, (length + 1U) * sizeof(WCHAR));
  }
  return copy;
}

#define YACA_WINDOWS_LONG_PATH_UNITS 32768U

static WCHAR *windows_full_path(const WCHAR *value)
{
  WCHAR *result;
  DWORD length;

  result = (WCHAR *)malloc(YACA_WINDOWS_LONG_PATH_UNITS * sizeof(WCHAR));
  if (result == NULL)
  {
    return NULL;
  }
  length = GetFullPathNameW(
    value,
    (DWORD)YACA_WINDOWS_LONG_PATH_UNITS,
    result,
    NULL);
  if (length == 0 || length >= (DWORD)YACA_WINDOWS_LONG_PATH_UNITS)
  {
    free(result);
    return NULL;
  }
  return result;
}

static WCHAR *windows_search_application(const WCHAR *value)
{
  WCHAR *searched;
  WCHAR *absolute;
  DWORD length;

  searched = (WCHAR *)malloc(YACA_WINDOWS_LONG_PATH_UNITS * sizeof(WCHAR));
  if (searched == NULL)
  {
    return NULL;
  }
  length = SearchPathW(
    NULL,
    value,
    L".exe",
    (DWORD)YACA_WINDOWS_LONG_PATH_UNITS,
    searched,
    NULL);
  if (length == 0 || length >= (DWORD)YACA_WINDOWS_LONG_PATH_UNITS)
  {
    free(searched);
    return NULL;
  }
  absolute = windows_full_path(searched);
  free(searched);
  return absolute;
}

static WCHAR *windows_module_path(void)
{
  DWORD capacity = MAX_PATH;

  while (capacity <= (DWORD)YACA_WINDOWS_LONG_PATH_UNITS)
  {
    WCHAR *result = (WCHAR *)malloc((size_t)capacity * sizeof(WCHAR));
    DWORD length;
    if (result == NULL)
    {
      return NULL;
    }
    result[capacity - 1U] = L'\0';
    SetLastError(ERROR_SUCCESS);
    length = GetModuleFileNameW(NULL, result, capacity);
    if (length > 0 && length < capacity && result[length] == L'\0')
    {
      return result;
    }
    free(result);
    if (capacity == (DWORD)YACA_WINDOWS_LONG_PATH_UNITS)
    {
      break;
    }
    capacity *= 2U;
    if (capacity > (DWORD)YACA_WINDOWS_LONG_PATH_UNITS)
    {
      capacity = (DWORD)YACA_WINDOWS_LONG_PATH_UNITS;
    }
  }
  return NULL;
}

static WCHAR *windows_strip_device_prefix(const WCHAR *value)
{
  static const WCHAR unc_prefix[] = L"\\\\?\\UNC\\";
  static const WCHAR device_prefix[] = L"\\\\?\\";
  size_t length;
  WCHAR *result;

  if (wcsncmp(value, unc_prefix, 8U) == 0)
  {
    length = wcslen(value + 8U);
    result = (WCHAR *)malloc((length + 3U) * sizeof(WCHAR));
    if (result == NULL)
    {
      return NULL;
    }
    result[0] = L'\\';
    result[1] = L'\\';
    memcpy(result + 2U, value + 8U, (length + 1U) * sizeof(WCHAR));
    return result;
  }
  if (wcsncmp(value, device_prefix, 4U) == 0)
  {
    return duplicate_wide(value + 4U);
  }
  return duplicate_wide(value);
}

static WCHAR *windows_final_path(HANDLE handle, const WCHAR *fallback)
{
  typedef DWORD (WINAPI *yaca_get_final_path)(HANDLE, LPWSTR, DWORD, DWORD);
  HMODULE kernel;
  FARPROC procedure;
  yaca_get_final_path get_final_path;
  WCHAR *buffer;
  WCHAR *result;
  DWORD length;

  kernel = GetModuleHandleW(L"kernel32.dll");
  if (kernel == NULL)
  {
    return duplicate_wide(fallback);
  }
  procedure = GetProcAddress(kernel, "GetFinalPathNameByHandleW");
  if (procedure == NULL)
  {
    return duplicate_wide(fallback);
  }
  memcpy(&get_final_path, &procedure, sizeof(get_final_path));
  buffer = (WCHAR *)malloc(YACA_WINDOWS_LONG_PATH_UNITS * sizeof(WCHAR));
  if (buffer == NULL)
  {
    return NULL;
  }
  length = get_final_path(
    handle,
    buffer,
    (DWORD)YACA_WINDOWS_LONG_PATH_UNITS,
    0);
  if (length == 0 || length >= (DWORD)YACA_WINDOWS_LONG_PATH_UNITS)
  {
    free(buffer);
    return duplicate_wide(fallback);
  }
  result = windows_strip_device_prefix(buffer);
  free(buffer);
  return result;
}

static WCHAR *windows_existing_file_path(const WCHAR *value)
{
  HANDLE handle;
  BY_HANDLE_FILE_INFORMATION information;
  WCHAR *result;

  handle = CreateFileW(
    value,
    FILE_READ_ATTRIBUTES,
    FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
    NULL,
    OPEN_EXISTING,
    FILE_ATTRIBUTE_NORMAL,
    NULL);
  if (handle == INVALID_HANDLE_VALUE)
  {
    return NULL;
  }
  if (!GetFileInformationByHandle(handle, &information)
      || (information.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0)
  {
    CloseHandle(handle);
    return NULL;
  }
  result = windows_final_path(handle, value);
  CloseHandle(handle);
  return result;
}

static WCHAR *windows_application_path(const WCHAR *argv0)
{
  WCHAR *absolute;
  WCHAR *result;

  if (wcschr(argv0, L'\\') == NULL
      && wcschr(argv0, L'/') == NULL
      && wcschr(argv0, L':') == NULL)
  {
    absolute = windows_search_application(argv0);
  }
  else
  {
    absolute = windows_full_path(argv0);
  }
  if (absolute == NULL)
  {
    return NULL;
  }
  result = windows_existing_file_path(absolute);
  free(absolute);
  return result;
}

static int push_windows_failure(lua_State *L, DWORD value, const char *message)
{
  return push_failure(L, windows_error_code(value), message);
}

#endif

#if !defined(_WIN32)

static char *posix_existing_executable(const char *candidate)
{
  char *resolved;
  struct stat information;

  resolved = realpath(candidate, NULL);
  if (resolved == NULL)
  {
    return NULL;
  }
  if (stat(resolved, &information) != 0
      || !S_ISREG(information.st_mode)
      || access(resolved, X_OK) != 0)
  {
    free(resolved);
    return NULL;
  }
  return resolved;
}

static char *posix_application_path(const char *argv0)
{
  const char *path;
  const char *cursor;
  size_t argument_length;

  if (strchr(argv0, '/') != NULL)
  {
    return posix_existing_executable(argv0);
  }
  path = getenv("PATH");
  if (path == NULL)
  {
    path = "/bin:/usr/bin";
  }
  argument_length = strlen(argv0);
  cursor = path;
  for (;;)
  {
    const char *separator = strchr(cursor, ':');
    size_t directory_length = separator == NULL
      ? strlen(cursor)
      : (size_t)(separator - cursor);
    const char *directory = cursor;
    char *candidate;
    char *resolved;
    size_t candidate_length;

    if (directory_length == 0)
    {
      directory = ".";
      directory_length = 1U;
    }
    if (directory_length > SIZE_MAX - argument_length - 2U)
    {
      return NULL;
    }
    candidate_length = directory_length + 1U + argument_length;
    candidate = (char *)malloc(candidate_length + 1U);
    if (candidate == NULL)
    {
      return NULL;
    }
    memcpy(candidate, directory, directory_length);
    candidate[directory_length] = '/';
    memcpy(candidate + directory_length + 1U, argv0, argument_length + 1U);
    resolved = posix_existing_executable(candidate);
    free(candidate);
    if (resolved != NULL)
    {
      return resolved;
    }
    if (separator == NULL)
    {
      break;
    }
    cursor = separator + 1;
  }
  return NULL;
}

static char *posix_runtime_path(void)
{
  return posix_existing_executable("/proc/self/exe");
}

#endif

/*
** Lua:
**   paths = module.executable_paths(original_argv0)
*/
static int l_executable_paths(lua_State *L)
{
  const char *argv0;
  size_t argv0_length;

  argv0 = luaL_checklstring(L, 1, &argv0_length);
  if (argv0_length == 0 || memchr(argv0, '\0', argv0_length) != NULL)
  {
    return luaL_error(L, "original argv[0] is invalid");
  }
#if defined(_WIN32)
  {
    WCHAR *wide_argv0 = utf8_to_wide(argv0, argv0_length);
    WCHAR *application;
    WCHAR *runtime_module;
    WCHAR *runtime;
    char *application_utf8;
    char *runtime_utf8;
    if (wide_argv0 == NULL)
    {
      return luaL_error(L, "original argv[0] is not strict UTF-8");
    }
    application = windows_application_path(wide_argv0);
    free(wide_argv0);
    runtime_module = windows_module_path();
    runtime = runtime_module == NULL
      ? NULL
      : windows_existing_file_path(runtime_module);
    free(runtime_module);
    if (application == NULL || runtime == NULL)
    {
      free(application);
      free(runtime);
      return luaL_error(L, "executable paths could not be resolved");
    }
    application_utf8 = wide_to_utf8(application);
    runtime_utf8 = wide_to_utf8(runtime);
    free(application);
    free(runtime);
    if (application_utf8 == NULL || runtime_utf8 == NULL)
    {
      free(application_utf8);
      free(runtime_utf8);
      return luaL_error(L, "executable paths could not be encoded as UTF-8");
    }
    lua_createtable(L, 0, 2);
    lua_pushstring(L, application_utf8);
    lua_setfield(L, -2, "application");
    lua_pushstring(L, runtime_utf8);
    lua_setfield(L, -2, "runtime");
    free(application_utf8);
    free(runtime_utf8);
  }
#else
  {
    char *argument = (char *)malloc(argv0_length + 1U);
    char *application;
    char *runtime;
    if (argument == NULL)
    {
      return luaL_error(L, "executable path allocation failed");
    }
    memcpy(argument, argv0, argv0_length);
    argument[argv0_length] = '\0';
    application = posix_application_path(argument);
    free(argument);
    runtime = posix_runtime_path();
    if (application == NULL || runtime == NULL)
    {
      free(application);
      free(runtime);
      return luaL_error(L, "executable paths could not be resolved");
    }
    lua_createtable(L, 0, 2);
    lua_pushstring(L, application);
    lua_setfield(L, -2, "application");
    lua_pushstring(L, runtime);
    lua_setfield(L, -2, "runtime");
    free(application);
    free(runtime);
  }
#endif
  return 1;
}

/*
** Lua:
**   facts = module.stdio_facts()
*/
static int l_stdio_facts(lua_State *L)
{
  int input_is_tty;
  int output_is_tty;
  int error_is_tty;

#if defined(_WIN32)
  DWORD mode;
  HANDLE input = GetStdHandle(STD_INPUT_HANDLE);
  HANDLE output = GetStdHandle(STD_OUTPUT_HANDLE);
  HANDLE error_output = GetStdHandle(STD_ERROR_HANDLE);
  input_is_tty = input != NULL
    && input != INVALID_HANDLE_VALUE
    && GetConsoleMode(input, &mode) != 0;
  output_is_tty = output != NULL
    && output != INVALID_HANDLE_VALUE
    && GetConsoleMode(output, &mode) != 0;
  error_is_tty = error_output != NULL
    && error_output != INVALID_HANDLE_VALUE
    && GetConsoleMode(error_output, &mode) != 0;
#else
  input_is_tty = isatty(STDIN_FILENO) != 0;
  output_is_tty = isatty(STDOUT_FILENO) != 0;
  error_is_tty = isatty(STDERR_FILENO) != 0;
#endif
  lua_createtable(L, 0, 3);
  lua_pushboolean(L, input_is_tty);
  lua_setfield(L, -2, "stdin_is_tty");
  lua_pushboolean(L, output_is_tty);
  lua_setfield(L, -2, "stdout_is_tty");
  lua_pushboolean(L, error_is_tty);
  lua_setfield(L, -2, "stderr_is_tty");
  return 1;
}

static yaca_file *check_file(lua_State *L, int index)
{
  yaca_file *file;

  file = (yaca_file *)luaL_checkudata(L, index, YACA_FILE_METATABLE);
  if (file->closed)
  {
    luaL_error(L, "native file handle is closed");
  }
  return file;
}

static void close_file(yaca_file *file)
{
  if (file->closed)
  {
    return;
  }
#if defined(_WIN32)
  if (file->handle != INVALID_HANDLE_VALUE)
  {
    CloseHandle(file->handle);
    file->handle = INVALID_HANDLE_VALUE;
  }
#else
  if (file->descriptor >= 0)
  {
    close(file->descriptor);
    file->descriptor = -1;
  }
#endif
  file->closed = 1;
}

static int l_file_gc(lua_State *L)
{
  yaca_file *file;

  file = (yaca_file *)luaL_testudata(L, 1, YACA_FILE_METATABLE);
  if (file != NULL)
  {
    close_file(file);
  }
  return 0;
}

static yaca_file *push_file(lua_State *L)
{
  yaca_file *file;

  file = (yaca_file *)lua_newuserdatauv(L, sizeof(yaca_file), 0);
  memset(file, 0, sizeof(*file));
#if defined(_WIN32)
  file->handle = INVALID_HANDLE_VALUE;
#else
  file->descriptor = -1;
#endif
  luaL_setmetatable(L, YACA_FILE_METATABLE);
  return file;
}

static void push_identity(lua_State *L, const yaca_identity *identity)
{
  lua_createtable(L, 0, 5);
  lua_pushstring(L, identity->kind);
  lua_setfield(L, -2, "kind");
  lua_pushstring(L, identity->volume);
  lua_setfield(L, -2, "volume");
  lua_pushstring(L, identity->object);
  lua_setfield(L, -2, "object");
  lua_pushinteger(L, identity->size);
  lua_setfield(L, -2, "size");
  lua_pushstring(L, identity->modified);
  lua_setfield(L, -2, "modified");
}

static int identity_matches_lua(lua_State *L, int index, const yaca_identity *identity)
{
  int matches;
  const char *text;

  if (!lua_istable(L, index))
  {
    return 0;
  }
  matches = 1;
  lua_getfield(L, index, "kind");
  text = lua_tostring(L, -1);
  matches = matches && text != NULL && strcmp(text, identity->kind) == 0;
  lua_pop(L, 1);
  lua_getfield(L, index, "volume");
  text = lua_tostring(L, -1);
  matches = matches && text != NULL && strcmp(text, identity->volume) == 0;
  lua_pop(L, 1);
  lua_getfield(L, index, "object");
  text = lua_tostring(L, -1);
  matches = matches && text != NULL && strcmp(text, identity->object) == 0;
  lua_pop(L, 1);
  lua_getfield(L, index, "size");
  matches = matches
    && lua_isinteger(L, -1)
    && lua_tointeger(L, -1) == identity->size;
  lua_pop(L, 1);
  lua_getfield(L, index, "modified");
  text = lua_tostring(L, -1);
  matches = matches && text != NULL && strcmp(text, identity->modified) == 0;
  lua_pop(L, 1);
  return matches;
}

#if defined(_WIN32)

static int identity_from_handle(HANDLE handle, yaca_identity *identity)
{
  BY_HANDLE_FILE_INFORMATION information;
  unsigned long long size;

  if (!GetFileInformationByHandle(handle, &information))
  {
    return 0;
  }
  strcpy(
    identity->kind,
    (information.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0
      ? "directory"
      : "file");
  snprintf(
    identity->volume,
    sizeof(identity->volume),
    "%lu",
    (unsigned long)information.dwVolumeSerialNumber);
  snprintf(
    identity->object,
    sizeof(identity->object),
    "%08lX%08lX",
    (unsigned long)information.nFileIndexHigh,
    (unsigned long)information.nFileIndexLow);
  size = ((unsigned long long)information.nFileSizeHigh << 32)
    | (unsigned long long)information.nFileSizeLow;
  if (size > (unsigned long long)LUA_MAXINTEGER)
  {
    SetLastError(ERROR_FILE_TOO_LARGE);
    return 0;
  }
  identity->size = (lua_Integer)size;
  snprintf(
    identity->modified,
    sizeof(identity->modified),
    "%08lX%08lX",
    (unsigned long)information.ftLastWriteTime.dwHighDateTime,
    (unsigned long)information.ftLastWriteTime.dwLowDateTime);
  return 1;
}

static HANDLE open_identity_path(const WCHAR *path)
{
  return CreateFileW(
    path,
    FILE_READ_ATTRIBUTES,
    FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
    NULL,
    OPEN_EXISTING,
    FILE_FLAG_BACKUP_SEMANTICS,
    NULL);
}

#else

static int identity_from_stat(const struct stat *information, yaca_identity *identity)
{
  unsigned long long size;

  if (S_ISREG(information->st_mode))
  {
    strcpy(identity->kind, "file");
  }
  else if (S_ISDIR(information->st_mode))
  {
    strcpy(identity->kind, "directory");
  }
  else
  {
    strcpy(identity->kind, "other");
  }
  snprintf(
    identity->volume,
    sizeof(identity->volume),
    "%llu",
    (unsigned long long)information->st_dev);
  snprintf(
    identity->object,
    sizeof(identity->object),
    "%llu",
    (unsigned long long)information->st_ino);
  if (information->st_size < 0)
  {
    errno = EOVERFLOW;
    return 0;
  }
  size = (unsigned long long)information->st_size;
  if (size > (unsigned long long)LUA_MAXINTEGER)
  {
    errno = EOVERFLOW;
    return 0;
  }
  identity->size = (lua_Integer)size;
  snprintf(
    identity->modified,
    sizeof(identity->modified),
    "%lld:%09ld:%lld:%09ld",
    (long long)information->st_mtim.tv_sec,
    information->st_mtim.tv_nsec,
    (long long)information->st_ctim.tv_sec,
    information->st_ctim.tv_nsec);
  return 1;
}

static int identity_from_descriptor(int descriptor, yaca_identity *identity)
{
  struct stat information;

  if (fstat(descriptor, &information) != 0)
  {
    return 0;
  }
  return identity_from_stat(&information, identity);
}

#endif

/*
** Lua:
**   workspace = module.workspace_inspect(requested_path)
*/
static int l_workspace_inspect(lua_State *L)
{
  const char *path;
  size_t length;
  yaca_identity identity;

  path = luaL_checklstring(L, 1, &length);
  if (length == 0 || memchr(path, '\0', length) != NULL)
  {
    return luaL_error(L, "workspace path is invalid");
  }
#if defined(_WIN32)
  {
    WCHAR *wide_path = utf8_to_wide(path, length);
    WCHAR *absolute;
    WCHAR *canonical;
    char *utf8;
    HANDLE handle;
    if (wide_path == NULL)
    {
      return luaL_error(L, "workspace path is not strict UTF-8");
    }
    absolute = windows_full_path(wide_path);
    free(wide_path);
    if (absolute == NULL)
    {
      return luaL_error(L, "workspace path could not be made absolute");
    }
    handle = CreateFileW(
      absolute,
      FILE_READ_ATTRIBUTES,
      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
      NULL,
      OPEN_EXISTING,
      FILE_FLAG_BACKUP_SEMANTICS,
      NULL);
    if (handle == INVALID_HANDLE_VALUE
        || !identity_from_handle(handle, &identity)
        || strcmp(identity.kind, "directory") != 0)
    {
      if (handle != INVALID_HANDLE_VALUE)
      {
        CloseHandle(handle);
      }
      free(absolute);
      return luaL_error(L, "workspace is not an enterable directory");
    }
    canonical = windows_final_path(handle, absolute);
    CloseHandle(handle);
    free(absolute);
    if (canonical == NULL)
    {
      return luaL_error(L, "workspace canonical path is unavailable");
    }
    utf8 = wide_to_utf8(canonical);
    free(canonical);
    if (utf8 == NULL)
    {
      return luaL_error(L, "workspace path could not be encoded as UTF-8");
    }
    lua_createtable(L, 0, 3);
    lua_pushstring(L, utf8);
    lua_setfield(L, -2, "path");
    free(utf8);
  }
#else
  {
    char *argument = (char *)malloc(length + 1U);
    char *canonical;
    struct stat information;
    if (argument == NULL)
    {
      return luaL_error(L, "workspace path allocation failed");
    }
    memcpy(argument, path, length);
    argument[length] = '\0';
    canonical = realpath(argument, NULL);
    free(argument);
    if (canonical == NULL
        || stat(canonical, &information) != 0
        || !S_ISDIR(information.st_mode)
        || access(canonical, X_OK) != 0
        || !identity_from_stat(&information, &identity))
    {
      free(canonical);
      return luaL_error(L, "workspace is not an enterable directory");
    }
    lua_createtable(L, 0, 3);
    lua_pushstring(L, canonical);
    lua_setfield(L, -2, "path");
    free(canonical);
  }
#endif
  lua_pushboolean(L, 1);
  lua_setfield(L, -2, "enterable");
  push_identity(L, &identity);
  lua_setfield(L, -2, "identity");
  return 1;
}

/*
** Lua:
**   ok, value_or_error = module.fs_make_directory(absolute_path, permissions)
*/
static int l_fs_make_directory(lua_State *L)
{
  const char *path;
  size_t length;
  lua_Integer permissions;

  if (!checked_byte_string(
      L,
      1,
      &path,
      &length,
      "InvalidPath",
      "directory path is invalid"))
  {
    return 2;
  }
  permissions = luaL_checkinteger(L, 2);
  if (permissions < 0 || permissions > 511)
  {
    return push_failure(L, "InvalidPermissions", "directory permissions are invalid");
  }
#if defined(_WIN32)
  {
    WCHAR *wide_path;
    DWORD error_value;
    if (!(length >= 3U
        && ((path[0] >= 'A' && path[0] <= 'Z')
          || (path[0] >= 'a' && path[0] <= 'z'))
        && path[1] == ':'
        && (path[2] == '\\' || path[2] == '/'))
        && !(length >= 5U
          && (path[0] == '\\' || path[0] == '/')
          && (path[1] == '\\' || path[1] == '/')))
    {
      return push_failure(L, "InvalidPath", "directory path must be absolute");
    }
    wide_path = utf8_to_wide(path, length);
    if (wide_path == NULL)
    {
      return push_failure(L, "InvalidPath", "directory path is not strict UTF-8");
    }
    if (!CreateDirectoryW(wide_path, NULL))
    {
      error_value = GetLastError();
      free(wide_path);
      return push_windows_failure(L, error_value, "directory creation failed");
    }
    free(wide_path);
  }
#else
  {
    char *terminated;
    int result;
    int error_value;
    if (path[0] != '/')
    {
      return push_failure(L, "InvalidPath", "directory path must be absolute");
    }
    terminated = (char *)malloc(length + 1U);
    if (terminated == NULL)
    {
      return push_failure(L, "Storage", "directory path allocation failed");
    }
    memcpy(terminated, path, length);
    terminated[length] = '\0';
    result = mkdir(terminated, (mode_t)permissions);
    error_value = errno;
    free(terminated);
    if (result != 0)
    {
      return push_failure(L, errno_code(error_value), "directory creation failed");
    }
  }
#endif
  return push_true_result(L);
}

/*
** Lua:
**   ok, handle_or_error = module.fs_open_read(absolute_path)
*/
static int l_fs_open_read(lua_State *L)
{
  const char *path;
  size_t length;
  yaca_file *file;

  if (!checked_byte_string(
      L,
      1,
      &path,
      &length,
      "InvalidPath",
      "filesystem path is invalid"))
  {
    return 2;
  }
#if defined(_WIN32)
  {
    WCHAR *wide_path;
    HANDLE handle;
    DWORD error_value;

    wide_path = utf8_to_wide(path, length);
    if (wide_path == NULL)
    {
      return push_failure(L, "InvalidEncoding", "filesystem path is not strict UTF-8");
    }
    handle = CreateFileW(
      wide_path,
      GENERIC_READ,
      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
      NULL,
      OPEN_EXISTING,
      FILE_FLAG_SEQUENTIAL_SCAN,
      NULL);
    error_value = GetLastError();
    free(wide_path);
    if (handle == INVALID_HANDLE_VALUE)
    {
      return push_windows_failure(L, error_value, "cannot open file for reading");
    }
    file = push_file(L);
    file->handle = handle;
  }
#else
  {
    int descriptor;
    int error_value;

    descriptor = open(path, O_RDONLY);
    error_value = errno;
    if (descriptor < 0)
    {
      return push_failure(L, errno_code(error_value), "cannot open file for reading");
    }
    file = push_file(L);
    file->descriptor = descriptor;
  }
#endif
  return return_success(L);
}

/*
** Lua:
**   ok, handle_or_error = module.fs_create_new(absolute_path, permissions)
*/
static int l_fs_create_new(lua_State *L)
{
  const char *path;
  size_t length;
  lua_Integer permissions;
  yaca_file *file;

  if (!checked_byte_string(
      L,
      1,
      &path,
      &length,
      "InvalidPath",
      "filesystem path is invalid"))
  {
    return 2;
  }
  permissions = luaL_checkinteger(L, 2);
  if (permissions < 0 || permissions > 0777)
  {
    return push_failure(L, "InvalidPermissions", "filesystem permissions are invalid");
  }
#if defined(_WIN32)
  {
    WCHAR *wide_path;
    HANDLE handle;
    DWORD error_value;

    wide_path = utf8_to_wide(path, length);
    if (wide_path == NULL)
    {
      return push_failure(L, "InvalidEncoding", "filesystem path is not strict UTF-8");
    }
    handle = CreateFileW(
      wide_path,
      GENERIC_READ | GENERIC_WRITE,
      FILE_SHARE_READ,
      NULL,
      CREATE_NEW,
      FILE_ATTRIBUTE_NORMAL,
      NULL);
    error_value = GetLastError();
    free(wide_path);
    if (handle == INVALID_HANDLE_VALUE)
    {
      return push_windows_failure(L, error_value, "cannot create new file");
    }
    file = push_file(L);
    file->handle = handle;
  }
#else
  {
    int descriptor;
    int error_value;

    descriptor = open(path, O_CREAT | O_EXCL | O_RDWR, (mode_t)permissions);
    error_value = errno;
    if (descriptor < 0)
    {
      return push_failure(L, errno_code(error_value), "cannot create new file");
    }
    file = push_file(L);
    file->descriptor = descriptor;
  }
#endif
  return return_success(L);
}

/*
** Lua:
**   ok, identity_or_error = module.fs_stat_identity(handle_or_path)
*/
static int l_fs_stat_identity(lua_State *L)
{
  yaca_identity identity;
  yaca_file *file;

  memset(&identity, 0, sizeof(identity));
  file = (yaca_file *)luaL_testudata(L, 1, YACA_FILE_METATABLE);
  if (file != NULL)
  {
    if (file->closed)
    {
      return push_failure(L, "Closed", "filesystem handle is closed");
    }
#if defined(_WIN32)
    if (!identity_from_handle(file->handle, &identity))
    {
      return push_windows_failure(L, GetLastError(), "cannot read filesystem identity");
    }
#else
    if (!identity_from_descriptor(file->descriptor, &identity))
    {
      return push_failure(L, errno_code(errno), "cannot read filesystem identity");
    }
#endif
  }
  else
  {
    const char *path;
    size_t length;

    if (!checked_byte_string(
        L,
        1,
        &path,
        &length,
        "InvalidPath",
        "filesystem path is invalid"))
    {
      return 2;
    }
#if defined(_WIN32)
    {
      WCHAR *wide_path;
      HANDLE handle;
      DWORD error_value;

      wide_path = utf8_to_wide(path, length);
      if (wide_path == NULL)
      {
        return push_failure(L, "InvalidEncoding", "filesystem path is not strict UTF-8");
      }
      handle = open_identity_path(wide_path);
      error_value = GetLastError();
      free(wide_path);
      if (handle == INVALID_HANDLE_VALUE)
      {
        return push_windows_failure(L, error_value, "cannot open filesystem identity");
      }
      if (!identity_from_handle(handle, &identity))
      {
        error_value = GetLastError();
        CloseHandle(handle);
        return push_windows_failure(L, error_value, "cannot read filesystem identity");
      }
      CloseHandle(handle);
    }
#else
    {
      struct stat information;

      if (stat(path, &information) != 0 || !identity_from_stat(&information, &identity))
      {
        return push_failure(L, errno_code(errno), "cannot read filesystem identity");
      }
    }
#endif
  }
  push_identity(L, &identity);
  return return_success(L);
}

/*
** Lua:
**   ok, { bytes = string, eof = boolean } = module.fs_read(handle, maximum)
*/
static int l_fs_read(lua_State *L)
{
  yaca_file *file;
  lua_Integer requested;
  char *buffer;
  size_t received;

  file = check_file(L, 1);
  requested = luaL_checkinteger(L, 2);
  if (requested <= 0 || (lua_Unsigned)requested > (lua_Unsigned)SIZE_MAX)
  {
    return push_failure(L, "Limit", "filesystem read size is invalid");
  }
  buffer = (char *)malloc((size_t)requested);
  if (buffer == NULL)
  {
    return push_failure(L, "Limit", "filesystem read buffer allocation failed");
  }
#if defined(_WIN32)
  {
    DWORD count;
    DWORD maximum;

    maximum = requested > (lua_Integer)0x7fffffff
      ? (DWORD)0x7fffffff
      : (DWORD)requested;
    if (!ReadFile(file->handle, buffer, maximum, &count, NULL))
    {
      DWORD error_value;

      error_value = GetLastError();
      free(buffer);
      return push_windows_failure(L, error_value, "filesystem read failed");
    }
    received = (size_t)count;
  }
#else
  {
    ssize_t count;

    do
    {
      count = read(file->descriptor, buffer, (size_t)requested);
    }
    while (count < 0 && errno == EINTR);
    if (count < 0)
    {
      int error_value;

      error_value = errno;
      free(buffer);
      return push_failure(L, errno_code(error_value), "filesystem read failed");
    }
    received = (size_t)count;
  }
#endif
  lua_createtable(L, 0, 2);
  lua_pushlstring(L, buffer, received);
  lua_setfield(L, -2, "bytes");
  lua_pushboolean(L, received == 0);
  lua_setfield(L, -2, "eof");
  free(buffer);
  return return_success(L);
}

/*
** Lua:
**   ok, byte_count_or_error = module.fs_write(handle, bytes)
*/
static int l_fs_write(lua_State *L)
{
  yaca_file *file;
  const char *bytes;
  size_t length;
  size_t offset;

  file = check_file(L, 1);
  bytes = luaL_checklstring(L, 2, &length);
  offset = 0;
  while (offset < length)
  {
#if defined(_WIN32)
    DWORD count;
    DWORD chunk;

    chunk = length - offset > 0x7fffffffU
      ? (DWORD)0x7fffffff
      : (DWORD)(length - offset);
    if (!WriteFile(file->handle, bytes + offset, chunk, &count, NULL) || count == 0)
    {
      return push_windows_failure(L, GetLastError(), "filesystem write failed");
    }
    offset += (size_t)count;
#else
    ssize_t count;

    do
    {
      count = write(file->descriptor, bytes + offset, length - offset);
    }
    while (count < 0 && errno == EINTR);
    if (count <= 0)
    {
      return push_failure(L, errno_code(errno), "filesystem write failed");
    }
    offset += (size_t)count;
#endif
  }
  lua_pushinteger(L, (lua_Integer)length);
  return return_success(L);
}

static int l_fs_flush_file(lua_State *L)
{
  yaca_file *file;

  file = check_file(L, 1);
#if defined(_WIN32)
  if (!FlushFileBuffers(file->handle))
  {
    return push_windows_failure(L, GetLastError(), "filesystem file flush failed");
  }
#else
  if (fsync(file->descriptor) != 0)
  {
    return push_failure(L, errno_code(errno), "filesystem file flush failed");
  }
#endif
  return push_true_result(L);
}

static int l_fs_flush_directory(lua_State *L)
{
  const char *path;
  size_t length;

  if (!checked_byte_string(
      L,
      1,
      &path,
      &length,
      "InvalidPath",
      "filesystem directory path is invalid"))
  {
    return 2;
  }
#if defined(_WIN32)
  {
    WCHAR *wide_path;
    HANDLE handle;
    DWORD error_value;

    wide_path = utf8_to_wide(path, length);
    if (wide_path == NULL)
    {
      return push_failure(L, "InvalidEncoding", "filesystem path is not strict UTF-8");
    }
    handle = CreateFileW(
      wide_path,
      GENERIC_READ,
      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
      NULL,
      OPEN_EXISTING,
      FILE_FLAG_BACKUP_SEMANTICS,
      NULL);
    error_value = GetLastError();
    free(wide_path);
    if (handle == INVALID_HANDLE_VALUE)
    {
      return push_windows_failure(L, error_value, "cannot open directory for flush");
    }
    if (!FlushFileBuffers(handle))
    {
      error_value = GetLastError();
      CloseHandle(handle);
      return push_windows_failure(L, error_value, "filesystem directory flush failed");
    }
    CloseHandle(handle);
  }
#else
  {
    int descriptor;
    int error_value;

    descriptor = open(path, O_RDONLY | O_DIRECTORY);
    error_value = errno;
    if (descriptor < 0)
    {
      return push_failure(L, errno_code(error_value), "cannot open directory for flush");
    }
    if (fsync(descriptor) != 0)
    {
      error_value = errno;
      close(descriptor);
      return push_failure(L, errno_code(error_value), "filesystem directory flush failed");
    }
    close(descriptor);
  }
#endif
  return push_true_result(L);
}

static int l_fs_replace(lua_State *L)
{
  const char *temporary_path;
  const char *target_path;
  size_t temporary_length;
  size_t target_length;

  if (!checked_byte_string(
      L,
      1,
      &temporary_path,
      &temporary_length,
      "InvalidPath",
      "temporary filesystem path is invalid"))
  {
    return 2;
  }
  if (!checked_byte_string(
      L,
      2,
      &target_path,
      &target_length,
      "InvalidPath",
      "target filesystem path is invalid"))
  {
    return 2;
  }
#if defined(_WIN32)
  {
    WCHAR *wide_temporary;
    WCHAR *wide_target;
    DWORD error_value;

    wide_temporary = utf8_to_wide(temporary_path, temporary_length);
    wide_target = utf8_to_wide(target_path, target_length);
    if (wide_temporary == NULL || wide_target == NULL)
    {
      free(wide_temporary);
      free(wide_target);
      return push_failure(L, "InvalidEncoding", "filesystem path is not strict UTF-8");
    }
    if (!ReplaceFileW(
        wide_target,
        wide_temporary,
        NULL,
        REPLACEFILE_WRITE_THROUGH,
        NULL,
        NULL))
    {
      error_value = GetLastError();
      free(wide_temporary);
      free(wide_target);
      return push_windows_failure(L, error_value, "filesystem replacement failed");
    }
    free(wide_temporary);
    free(wide_target);
  }
#else
  {
    struct stat target_information;

    if (lstat(target_path, &target_information) != 0)
    {
      return push_failure(L, errno_code(errno), "replacement target does not exist");
    }
    if (rename(temporary_path, target_path) != 0)
    {
      return push_failure(L, errno_code(errno), "filesystem replacement failed");
    }
  }
#endif
  return push_true_result(L);
}

static int l_fs_rename_no_replace(lua_State *L)
{
  const char *source_path;
  const char *target_path;
  size_t source_length;
  size_t target_length;

  if (!checked_byte_string(
      L,
      1,
      &source_path,
      &source_length,
      "InvalidPath",
      "source filesystem path is invalid"))
  {
    return 2;
  }
  if (!checked_byte_string(
      L,
      2,
      &target_path,
      &target_length,
      "InvalidPath",
      "target filesystem path is invalid"))
  {
    return 2;
  }
#if defined(_WIN32)
  {
    WCHAR *wide_source;
    WCHAR *wide_target;
    DWORD error_value;

    wide_source = utf8_to_wide(source_path, source_length);
    wide_target = utf8_to_wide(target_path, target_length);
    if (wide_source == NULL || wide_target == NULL)
    {
      free(wide_source);
      free(wide_target);
      return push_failure(L, "InvalidEncoding", "filesystem path is not strict UTF-8");
    }
    if (!MoveFileExW(wide_source, wide_target, MOVEFILE_WRITE_THROUGH))
    {
      error_value = GetLastError();
      free(wide_source);
      free(wide_target);
      return push_windows_failure(L, error_value, "filesystem no-replace move failed");
    }
    free(wide_source);
    free(wide_target);
  }
#else
  if (link(source_path, target_path) != 0)
  {
    return push_failure(L, errno_code(errno), "filesystem no-replace link failed");
  }
  if (unlink(source_path) != 0)
  {
    int error_value;

    error_value = errno;
    if (unlink(target_path) != 0)
    {
      return push_failure(L, "Unknown", "filesystem no-replace move outcome is unknown");
    }
    return push_failure(L, errno_code(error_value), "filesystem no-replace unlink failed");
  }
#endif
  return push_true_result(L);
}

static int l_fs_delete_verified(lua_State *L)
{
  const char *path;
  size_t length;
  yaca_identity identity;

  if (!checked_byte_string(
      L,
      1,
      &path,
      &length,
      "InvalidPath",
      "filesystem delete path is invalid"))
  {
    return 2;
  }
  luaL_checktype(L, 2, LUA_TTABLE);
  memset(&identity, 0, sizeof(identity));
#if defined(_WIN32)
  {
    WCHAR *wide_path;
    HANDLE handle;
    DWORD error_value;
    int is_directory;

    wide_path = utf8_to_wide(path, length);
    if (wide_path == NULL)
    {
      return push_failure(L, "InvalidEncoding", "filesystem path is not strict UTF-8");
    }
    handle = open_identity_path(wide_path);
    if (handle == INVALID_HANDLE_VALUE)
    {
      error_value = GetLastError();
      free(wide_path);
      return push_windows_failure(L, error_value, "cannot open verified delete target");
    }
    if (!identity_from_handle(handle, &identity))
    {
      error_value = GetLastError();
      CloseHandle(handle);
      free(wide_path);
      return push_windows_failure(L, error_value, "cannot identify delete target");
    }
    if (!identity_matches_lua(L, 2, &identity))
    {
      CloseHandle(handle);
      free(wide_path);
      return push_failure(L, "TargetChanged", "verified delete target changed");
    }
    is_directory = strcmp(identity.kind, "directory") == 0;
    CloseHandle(handle);
    if ((is_directory && !RemoveDirectoryW(wide_path))
        || (!is_directory && !DeleteFileW(wide_path)))
    {
      error_value = GetLastError();
      free(wide_path);
      return push_windows_failure(L, error_value, "verified delete failed");
    }
    free(wide_path);
  }
#else
  {
    struct stat information;

    if (stat(path, &information) != 0 || !identity_from_stat(&information, &identity))
    {
      return push_failure(L, errno_code(errno), "cannot identify delete target");
    }
    if (!identity_matches_lua(L, 2, &identity))
    {
      return push_failure(L, "TargetChanged", "verified delete target changed");
    }
    if ((S_ISDIR(information.st_mode) ? rmdir(path) : unlink(path)) != 0)
    {
      return push_failure(L, errno_code(errno), "verified delete failed");
    }
  }
#endif
  return push_true_result(L);
}

static int l_fs_close(lua_State *L)
{
  yaca_file *file;

  file = (yaca_file *)luaL_checkudata(L, 1, YACA_FILE_METATABLE);
  if (file->closed)
  {
    return push_failure(L, "Closed", "filesystem handle is already closed");
  }
  close_file(file);
  return push_true_result(L);
}

#if defined(_WIN32)

#define YACA_WINDOWS_METADATA_MAX_BYTES (1024U * 1024U)
#define YACA_WINDOWS_MAX_ANCESTORS 1024U
#define YACA_WINDOWS_MAX_STREAMS 1024U

typedef struct yaca_windows_metadata_state
{
  DWORD attributes;
  unsigned char *security_descriptor;
  DWORD security_descriptor_length;
  int proven;
} yaca_windows_metadata_state;

typedef struct yaca_windows_ancestor
{
  WCHAR *path;
  yaca_identity identity;
} yaca_windows_ancestor;

typedef struct yaca_windows_snapshot
{
  WCHAR *canonical_path;
  WCHAR *parent_path;
  HANDLE target_handle;
  HANDLE parent_handle;
  BY_HANDLE_FILE_INFORMATION target_information;
  BY_HANDLE_FILE_INFORMATION parent_information;
  yaca_windows_ancestor *ancestors;
  size_t ancestor_count;
  int exists;
  int reparse;
  char *link_target;
  yaca_windows_metadata_state metadata;
} yaca_windows_snapshot;

typedef struct yaca_windows_path_vector
{
  char **items;
  size_t count;
  size_t capacity;
  size_t maximum;
  int truncated;
  int conservative_ignore;
} yaca_windows_path_vector;

static void free_windows_metadata_state(yaca_windows_metadata_state *state)
{
  free(state->security_descriptor);
  memset(state, 0, sizeof(*state));
}

static int windows_streams_are_plain(HANDLE handle)
{
  LPVOID context = NULL;
  WIN32_STREAM_ID stream;
  DWORD received = 0;
  size_t count = 0U;
  int default_data_seen = 0;
  int result = 1;

  memset(&stream, 0, sizeof(stream));
  for (;;)
  {
    DWORD header_bytes = (DWORD)FIELD_OFFSET(WIN32_STREAM_ID, cStreamName);
    if (++count > YACA_WINDOWS_MAX_STREAMS)
    {
      result = 0;
      break;
    }
    if (!BackupRead(
        handle,
        (LPBYTE)&stream,
        header_bytes,
        &received,
        FALSE,
        FALSE,
        &context))
    {
      result = -1;
      break;
    }
    if (received == 0)
    {
      break;
    }
    if (received != header_bytes
        || stream.Size.QuadPart < 0
        || stream.dwStreamNameSize > 65536U
        || (stream.dwStreamNameSize % sizeof(WCHAR)) != 0U)
    {
      result = -1;
      break;
    }
    if (stream.dwStreamNameSize > 0U)
    {
      BYTE *name = (BYTE *)malloc(stream.dwStreamNameSize);
      if (name == NULL)
      {
        SetLastError(ERROR_NOT_ENOUGH_MEMORY);
        result = -1;
        break;
      }
      if (!BackupRead(
          handle,
          name,
          stream.dwStreamNameSize,
          &received,
          FALSE,
          FALSE,
          &context)
          || received != stream.dwStreamNameSize)
      {
        free(name);
        result = -1;
        break;
      }
      free(name);
    }
    if (stream.dwStreamId == BACKUP_DATA
        && stream.dwStreamNameSize == 0U
        && !default_data_seen)
    {
      default_data_seen = 1;
    }
    else if (stream.dwStreamId != BACKUP_SECURITY_DATA)
    {
      result = 0;
      break;
    }
    if (stream.Size.QuadPart > 0)
    {
      DWORD sought_low = 0;
      DWORD sought_high = 0;
      if (!BackupSeek(
          handle,
          stream.Size.LowPart,
          (DWORD)stream.Size.HighPart,
          &sought_low,
          &sought_high,
          &context)
          || sought_low != stream.Size.LowPart
          || sought_high != (DWORD)stream.Size.HighPart)
      {
        result = -1;
        break;
      }
    }
    memset(&stream, 0, sizeof(stream));
  }
  BackupRead(handle, NULL, 0, &received, TRUE, FALSE, &context);
  return result;
}

typedef struct yaca_windows_stream_data
{
  LARGE_INTEGER size;
  WCHAR name[MAX_PATH + 36];
} yaca_windows_stream_data;

static int windows_streams_are_plain_by_path(const WCHAR *path)
{
  typedef HANDLE (WINAPI *yaca_find_first_stream)(
    LPCWSTR, int, LPVOID, DWORD);
  typedef BOOL (WINAPI *yaca_find_next_stream)(HANDLE, LPVOID);
  HMODULE kernel = GetModuleHandleW(L"kernel32.dll");
  FARPROC first_procedure;
  FARPROC next_procedure;
  yaca_find_first_stream first;
  yaca_find_next_stream next;
  yaca_windows_stream_data data;
  HANDLE search;
  DWORD error_value;
  size_t count = 0U;
  int result = 1;

  if (kernel == NULL)
  {
    return 0;
  }
  first_procedure = GetProcAddress(kernel, "FindFirstStreamW");
  next_procedure = GetProcAddress(kernel, "FindNextStreamW");
  if (first_procedure == NULL || next_procedure == NULL)
  {
    return 0;
  }
  memcpy(&first, &first_procedure, sizeof(first));
  memcpy(&next, &next_procedure, sizeof(next));
  memset(&data, 0, sizeof(data));
  search = first(path, 0, &data, 0U);
  if (search == INVALID_HANDLE_VALUE)
  {
    error_value = GetLastError();
    return (error_value == ERROR_HANDLE_EOF
      || error_value == ERROR_FILE_NOT_FOUND) ? 1 : 0;
  }
  do
  {
    if (++count > YACA_WINDOWS_MAX_STREAMS
        || wcscmp(data.name, L"::$DATA") != 0)
    {
      result = 0;
      break;
    }
  }
  while (next(search, &data));
  error_value = GetLastError();
  FindClose(search);
  if (result && error_value != ERROR_HANDLE_EOF)
  {
    result = 0;
  }
  return result;
}

static int capture_windows_metadata(
  HANDLE handle,
  const BY_HANDLE_FILE_INFORMATION *information,
  const WCHAR *path,
  int require_plain_streams,
  yaca_windows_metadata_state *state)
{
  SECURITY_INFORMATION requested = OWNER_SECURITY_INFORMATION
    | GROUP_SECURITY_INFORMATION
    | DACL_SECURITY_INFORMATION;
  DWORD required = 0;
  int streams;

  memset(state, 0, sizeof(*state));
  state->attributes = information->dwFileAttributes;
  SetLastError(ERROR_SUCCESS);
  if (GetKernelObjectSecurity(handle, requested, NULL, 0, &required)
      || GetLastError() != ERROR_INSUFFICIENT_BUFFER
      || required == 0U
      || required > YACA_WINDOWS_METADATA_MAX_BYTES)
  {
    return 0;
  }
  state->security_descriptor = (unsigned char *)malloc(required);
  if (state->security_descriptor == NULL)
  {
    SetLastError(ERROR_NOT_ENOUGH_MEMORY);
    return -1;
  }
  if (!GetKernelObjectSecurity(
      handle,
      requested,
      state->security_descriptor,
      required,
      &state->security_descriptor_length)
      || state->security_descriptor_length == 0U
      || state->security_descriptor_length > required)
  {
    free_windows_metadata_state(state);
    return 0;
  }
  if (require_plain_streams)
  {
    streams = windows_streams_are_plain(handle);
    if (streams < 0)
    {
      streams = windows_streams_are_plain_by_path(path);
    }
    if (streams != 1)
    {
      free_windows_metadata_state(state);
      return streams;
    }
  }
  state->proven = 1;
  return 1;
}

static int windows_metadata_states_equal(
  const yaca_windows_metadata_state *left,
  const yaca_windows_metadata_state *right)
{
  return left->proven && right->proven
    && left->attributes == right->attributes
    && left->security_descriptor_length == right->security_descriptor_length
    && memcmp(
      left->security_descriptor,
      right->security_descriptor,
      left->security_descriptor_length) == 0;
}

static int windows_behavior_digest(
  const yaca_windows_metadata_state *state,
  char output[96])
{
  yaca_sha256 hash;
  unsigned char digest[32];
  static const char hexadecimal[] = "0123456789abcdef";
  char scalar[64];
  char encoded[65];
  int written;
  size_t index;
  const char *availability = state->proven ? "proven" : "unsupported";

  sha256_initialize(&hash);
  written = snprintf(scalar, sizeof(scalar), "%lu", (unsigned long)state->attributes);
  if (written <= 0 || (size_t)written >= sizeof(scalar)
      || !sha256_append(
        &hash,
        (const unsigned char *)"yaca-windows-behavior-v2",
        24U)
      || !sha256_append(
        &hash,
        (const unsigned char *)availability,
        strlen(availability))
      || !sha256_append(
        &hash,
        (const unsigned char *)scalar,
        (size_t)written)
      || !sha256_append(
        &hash,
        state->security_descriptor,
        state->security_descriptor_length))
  {
    return 0;
  }
  sha256_finalize(&hash, digest);
  for (index = 0U; index < 32U; ++index)
  {
    encoded[index * 2U] = hexadecimal[digest[index] >> 4U];
    encoded[index * 2U + 1U] = hexadecimal[digest[index] & 0x0FU];
  }
  encoded[64] = '\0';
  written = snprintf(output, 96U, "windows-v2-%s", encoded);
  return written > 0 && written < 96;
}

static WCHAR *windows_join_path(const WCHAR *parent, const WCHAR *name)
{
  size_t parent_length = wcslen(parent);
  size_t name_length = wcslen(name);
  int separated = parent_length > 0U
    && (parent[parent_length - 1U] == L'\\'
      || parent[parent_length - 1U] == L'/');
  WCHAR *result;
  if (parent_length > SIZE_MAX / sizeof(WCHAR) - name_length - 2U)
  {
    return NULL;
  }
  result = (WCHAR *)malloc(
    (parent_length + name_length + (separated ? 1U : 2U)) * sizeof(WCHAR));
  if (result == NULL)
  {
    return NULL;
  }
  memcpy(result, parent, parent_length * sizeof(WCHAR));
  if (!separated)
  {
    result[parent_length++] = L'\\';
  }
  memcpy(
    result + parent_length,
    name,
    (name_length + 1U) * sizeof(WCHAR));
  return result;
}

static int windows_reserved_component(const WCHAR *component, size_t length)
{
  WCHAR folded[16];
  size_t base_length = 0U;
  size_t index;
  while (base_length < length && component[base_length] != L'.')
  {
    ++base_length;
  }
  if (base_length == 0U || base_length >= sizeof(folded) / sizeof(folded[0]))
  {
    return 0;
  }
  for (index = 0U; index < base_length; ++index)
  {
    WCHAR value = component[index];
    folded[index] = value >= L'a' && value <= L'z'
      ? (WCHAR)(value - (L'a' - L'A'))
      : value;
  }
  folded[base_length] = L'\0';
  if (wcscmp(folded, L"CON") == 0
      || wcscmp(folded, L"PRN") == 0
      || wcscmp(folded, L"AUX") == 0
      || wcscmp(folded, L"NUL") == 0
      || wcscmp(folded, L"CLOCK$") == 0)
  {
    return 1;
  }
  return base_length == 4U
    && ((wcsncmp(folded, L"COM", 3U) == 0)
      || (wcsncmp(folded, L"LPT", 3U) == 0))
    && folded[3] >= L'1'
    && folded[3] <= L'9';
}

static size_t windows_path_root_length(const WCHAR *path)
{
  size_t length = wcslen(path);
  size_t index;
  int separators = 0;
  if (length >= 3U
      && ((path[0] >= L'A' && path[0] <= L'Z')
        || (path[0] >= L'a' && path[0] <= L'z'))
      && path[1] == L':'
      && path[2] == L'\\')
  {
    return 3U;
  }
  if (length < 5U || path[0] != L'\\' || path[1] != L'\\')
  {
    return 0U;
  }
  for (index = 2U; index < length; ++index)
  {
    if (path[index] == L'\\')
    {
      ++separators;
      if (separators == 2)
      {
        return index + 1U;
      }
    }
  }
  return separators == 1 ? length : 0U;
}

static int validate_windows_direct_wide_path(WCHAR *path)
{
  size_t length = wcslen(path);
  size_t root_length;
  size_t segment_start;
  size_t index;

  for (index = 0U; index < length; ++index)
  {
    if (path[index] == L'/')
    {
      path[index] = L'\\';
    }
  }
  if (length >= 4U
      && path[0] == L'\\'
      && path[1] == L'\\'
      && (path[2] == L'?' || path[2] == L'.')
      && path[3] == L'\\')
  {
    return 0;
  }
  root_length = windows_path_root_length(path);
  if (root_length == 0U)
  {
    return 0;
  }
  segment_start = root_length;
  for (index = root_length; index <= length; ++index)
  {
    WCHAR value = index < length ? path[index] : L'\\';
    if (value < 0x20 || value == L'"' || value == L'<' || value == L'>'
        || value == L'|' || value == L'*' || value == L'?'
        || value == L':')
    {
      return 0;
    }
    if (value == L'\\')
    {
      size_t segment_length = index - segment_start;
      if (segment_length == 0U)
      {
        if (index != length || length != root_length)
        {
          return 0;
        }
      }
      else
      {
        WCHAR last = path[index - 1U];
        if ((segment_length == 1U && path[segment_start] == L'.')
            || (segment_length == 2U
              && path[segment_start] == L'.'
              && path[segment_start + 1U] == L'.')
            || last == L'.'
            || last == L' '
            || windows_reserved_component(
              path + segment_start,
              segment_length))
        {
          return 0;
        }
      }
      segment_start = index + 1U;
    }
  }
  return 1;
}

static WCHAR *windows_long_path(const WCHAR *value)
{
  DWORD required = GetLongPathNameW(value, NULL, 0);
  WCHAR *result;
  DWORD written;
  if (required == 0U || required > (DWORD)YACA_WINDOWS_LONG_PATH_UNITS)
  {
    return NULL;
  }
  result = (WCHAR *)malloc((size_t)required * sizeof(WCHAR));
  if (result == NULL)
  {
    return NULL;
  }
  written = GetLongPathNameW(value, result, required);
  if (written == 0U || written >= required)
  {
    free(result);
    return NULL;
  }
  return result;
}

static int windows_parent_and_name(
  const WCHAR *path,
  WCHAR **parent,
  WCHAR **name)
{
  size_t length = wcslen(path);
  size_t root_length = windows_path_root_length(path);
  const WCHAR *separator;
  size_t parent_length;
  if (root_length == 0U || length <= root_length)
  {
    return 0;
  }
  separator = wcsrchr(path, L'\\');
  if (separator == NULL || separator[1] == L'\0')
  {
    return 0;
  }
  parent_length = separator < path + root_length
    ? root_length
    : (size_t)(separator - path);
  *parent = (WCHAR *)malloc((parent_length + 1U) * sizeof(WCHAR));
  *name = duplicate_wide(separator + 1U);
  if (*parent == NULL || *name == NULL)
  {
    free(*parent);
    free(*name);
    *parent = NULL;
    *name = NULL;
    return 0;
  }
  memcpy(*parent, path, parent_length * sizeof(WCHAR));
  (*parent)[parent_length] = L'\0';
  return 1;
}

static HANDLE open_windows_direct_path(const WCHAR *path, DWORD access)
{
  const WCHAR *opened_path = path;
  WCHAR *trimmed = NULL;
  size_t length = wcslen(path);
  size_t root_length = windows_path_root_length(path);
  HANDLE handle;
  if (length > 3U
      && length == root_length
      && path[0] == L'\\'
      && path[1] == L'\\'
      && path[length - 1U] == L'\\')
  {
    trimmed = duplicate_wide(path);
    if (trimmed == NULL)
    {
      SetLastError(ERROR_NOT_ENOUGH_MEMORY);
      return INVALID_HANDLE_VALUE;
    }
    trimmed[length - 1U] = L'\0';
    opened_path = trimmed;
  }
  handle = CreateFileW(
    opened_path,
    access,
    FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
    NULL,
    OPEN_EXISTING,
    FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT,
    NULL);
  {
    DWORD error_value = GetLastError();
    free(trimmed);
    SetLastError(error_value);
  }
  return handle;
}

static int windows_same_object(
  const BY_HANDLE_FILE_INFORMATION *left,
  const BY_HANDLE_FILE_INFORMATION *right)
{
  return left->dwVolumeSerialNumber == right->dwVolumeSerialNumber
    && left->nFileIndexHigh == right->nFileIndexHigh
    && left->nFileIndexLow == right->nFileIndexLow
    && ((left->dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0)
      == ((right->dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0);
}

static void free_windows_snapshot(yaca_windows_snapshot *snapshot)
{
  size_t index;
  free(snapshot->canonical_path);
  free(snapshot->parent_path);
  free(snapshot->link_target);
  if (snapshot->target_handle != NULL
      && snapshot->target_handle != INVALID_HANDLE_VALUE)
  {
    CloseHandle(snapshot->target_handle);
  }
  if (snapshot->parent_handle != NULL
      && snapshot->parent_handle != INVALID_HANDLE_VALUE)
  {
    CloseHandle(snapshot->parent_handle);
  }
  for (index = 0U; index < snapshot->ancestor_count; ++index)
  {
    free(snapshot->ancestors[index].path);
  }
  free(snapshot->ancestors);
  free_windows_metadata_state(&snapshot->metadata);
  memset(snapshot, 0, sizeof(*snapshot));
  snapshot->target_handle = INVALID_HANDLE_VALUE;
  snapshot->parent_handle = INVALID_HANDLE_VALUE;
}

static void close_windows_snapshot_handles(yaca_windows_snapshot *snapshot)
{
  if (snapshot->target_handle != NULL
      && snapshot->target_handle != INVALID_HANDLE_VALUE)
  {
    CloseHandle(snapshot->target_handle);
    snapshot->target_handle = INVALID_HANDLE_VALUE;
  }
  if (snapshot->parent_handle != NULL
      && snapshot->parent_handle != INVALID_HANDLE_VALUE)
  {
    CloseHandle(snapshot->parent_handle);
    snapshot->parent_handle = INVALID_HANDLE_VALUE;
  }
}

static int append_windows_ancestor(
  yaca_windows_snapshot *snapshot,
  const WCHAR *path,
  HANDLE handle)
{
  yaca_windows_ancestor *next;
  yaca_windows_ancestor *ancestor;
  if (snapshot->ancestor_count >= YACA_WINDOWS_MAX_ANCESTORS)
  {
    SetLastError(ERROR_BUFFER_OVERFLOW);
    return 0;
  }
  next = (yaca_windows_ancestor *)realloc(
    snapshot->ancestors,
    (snapshot->ancestor_count + 1U) * sizeof(yaca_windows_ancestor));
  if (next == NULL)
  {
    SetLastError(ERROR_NOT_ENOUGH_MEMORY);
    return 0;
  }
  snapshot->ancestors = next;
  ancestor = &snapshot->ancestors[snapshot->ancestor_count];
  memset(ancestor, 0, sizeof(*ancestor));
  ancestor->path = duplicate_wide(path);
  if (ancestor->path == NULL
      || !identity_from_handle(handle, &ancestor->identity)
      || strcmp(ancestor->identity.kind, "directory") != 0)
  {
    free(ancestor->path);
    memset(ancestor, 0, sizeof(*ancestor));
    if (GetLastError() == ERROR_SUCCESS)
    {
      SetLastError(ERROR_DIRECTORY);
    }
    return 0;
  }
  ++snapshot->ancestor_count;
  return 1;
}

static int build_windows_ancestry(
  yaca_windows_snapshot *snapshot,
  const WCHAR *parent)
{
  size_t length = wcslen(parent);
  size_t root_length = windows_path_root_length(parent);
  WCHAR *prefix;
  size_t index;
  if (root_length == 0U)
  {
    SetLastError(ERROR_BAD_PATHNAME);
    return 0;
  }
  prefix = duplicate_wide(parent);
  if (prefix == NULL)
  {
    SetLastError(ERROR_NOT_ENOUGH_MEMORY);
    return 0;
  }
  for (index = root_length; index <= length; ++index)
  {
    if (index == root_length || index == length || parent[index] == L'\\')
    {
      size_t prefix_length = index == root_length ? root_length : index;
      WCHAR saved = prefix[prefix_length];
      HANDLE handle;
      BY_HANDLE_FILE_INFORMATION information;
      prefix[prefix_length] = L'\0';
      handle = open_windows_direct_path(
        prefix,
        FILE_READ_ATTRIBUTES | READ_CONTROL);
      if (handle == INVALID_HANDLE_VALUE
          || !GetFileInformationByHandle(handle, &information)
          || (information.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) == 0
          || (information.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0
          || !append_windows_ancestor(snapshot, prefix, handle))
      {
        DWORD error_value = GetLastError();
        if (handle != INVALID_HANDLE_VALUE) CloseHandle(handle);
        prefix[prefix_length] = saved;
        free(prefix);
        SetLastError(error_value == ERROR_SUCCESS ? ERROR_CANT_RESOLVE_FILENAME : error_value);
        return 0;
      }
      CloseHandle(handle);
      prefix[prefix_length] = saved;
      if (index == root_length)
      {
        while (index < length && parent[index] == L'\\') ++index;
      }
    }
  }
  free(prefix);
  return snapshot->ancestor_count > 0U;
}

#ifndef IO_REPARSE_TAG_SYMLINK
#define IO_REPARSE_TAG_SYMLINK (0xA000000CUL)
#endif
#ifndef IO_REPARSE_TAG_MOUNT_POINT
#define IO_REPARSE_TAG_MOUNT_POINT (0xA0000003UL)
#endif
#ifndef SYMLINK_FLAG_RELATIVE
#define SYMLINK_FLAG_RELATIVE 1UL
#endif

typedef struct yaca_reparse_buffer
{
  DWORD tag;
  WORD data_length;
  WORD reserved;
  union
  {
    struct
    {
      WORD substitute_offset;
      WORD substitute_length;
      WORD print_offset;
      WORD print_length;
      DWORD flags;
      WCHAR path[1];
    } symbolic_link;
    struct
    {
      WORD substitute_offset;
      WORD substitute_length;
      WORD print_offset;
      WORD print_length;
      WCHAR path[1];
    } mount_point;
  } value;
} yaca_reparse_buffer;

static WCHAR *normalize_windows_reparse_target(
  const WCHAR *parent,
  const WCHAR *target,
  int relative)
{
  WCHAR *candidate;
  WCHAR *absolute;
  if (relative)
  {
    candidate = windows_join_path(parent, target);
  }
  else if (wcsncmp(target, L"\\??\\UNC\\", 8U) == 0)
  {
    size_t length = wcslen(target + 8U);
    candidate = (WCHAR *)malloc((length + 3U) * sizeof(WCHAR));
    if (candidate != NULL)
    {
      candidate[0] = L'\\';
      candidate[1] = L'\\';
      memcpy(candidate + 2U, target + 8U, (length + 1U) * sizeof(WCHAR));
    }
  }
  else if (wcsncmp(target, L"\\??\\", 4U) == 0)
  {
    candidate = duplicate_wide(target + 4U);
  }
  else
  {
    candidate = duplicate_wide(target);
  }
  if (candidate == NULL)
  {
    return NULL;
  }
  absolute = windows_full_path(candidate);
  free(candidate);
  return absolute;
}

static char *windows_reparse_target(
  HANDLE handle,
  const WCHAR *parent)
{
  BYTE bytes[MAXIMUM_REPARSE_DATA_BUFFER_SIZE];
  DWORD received = 0;
  yaca_reparse_buffer *buffer = (yaca_reparse_buffer *)bytes;
  const WCHAR *source = NULL;
  size_t source_units = 0U;
  int relative = 0;
  WCHAR *copy;
  WCHAR *absolute;
  char *utf8;
  size_t path_offset;
  size_t available;
  WORD offset;
  WORD length;

  if (!DeviceIoControl(
      handle,
      FSCTL_GET_REPARSE_POINT,
      NULL,
      0,
      bytes,
      sizeof(bytes),
      &received,
      NULL)
      || received < 8U
      || (size_t)buffer->data_length + 8U > (size_t)received)
  {
    return NULL;
  }
  if (buffer->tag == IO_REPARSE_TAG_SYMLINK)
  {
    path_offset = FIELD_OFFSET(yaca_reparse_buffer, value.symbolic_link.path);
    offset = buffer->value.symbolic_link.print_length > 0U
      ? buffer->value.symbolic_link.print_offset
      : buffer->value.symbolic_link.substitute_offset;
    length = buffer->value.symbolic_link.print_length > 0U
      ? buffer->value.symbolic_link.print_length
      : buffer->value.symbolic_link.substitute_length;
    relative = (buffer->value.symbolic_link.flags & SYMLINK_FLAG_RELATIVE) != 0;
    available = (size_t)received > path_offset ? (size_t)received - path_offset : 0U;
    if ((size_t)offset + (size_t)length > available || (length % sizeof(WCHAR)) != 0U)
    {
      SetLastError(ERROR_INVALID_REPARSE_DATA);
      return NULL;
    }
    source = (const WCHAR *)((const BYTE *)buffer->value.symbolic_link.path + offset);
    source_units = length / sizeof(WCHAR);
  }
  else if (buffer->tag == IO_REPARSE_TAG_MOUNT_POINT)
  {
    path_offset = FIELD_OFFSET(yaca_reparse_buffer, value.mount_point.path);
    offset = buffer->value.mount_point.print_length > 0U
      ? buffer->value.mount_point.print_offset
      : buffer->value.mount_point.substitute_offset;
    length = buffer->value.mount_point.print_length > 0U
      ? buffer->value.mount_point.print_length
      : buffer->value.mount_point.substitute_length;
    available = (size_t)received > path_offset ? (size_t)received - path_offset : 0U;
    if ((size_t)offset + (size_t)length > available || (length % sizeof(WCHAR)) != 0U)
    {
      SetLastError(ERROR_INVALID_REPARSE_DATA);
      return NULL;
    }
    source = (const WCHAR *)((const BYTE *)buffer->value.mount_point.path + offset);
    source_units = length / sizeof(WCHAR);
  }
  else
  {
    SetLastError(ERROR_REPARSE_TAG_INVALID);
    return NULL;
  }
  copy = (WCHAR *)malloc((source_units + 1U) * sizeof(WCHAR));
  if (copy == NULL)
  {
    SetLastError(ERROR_NOT_ENOUGH_MEMORY);
    return NULL;
  }
  memcpy(copy, source, source_units * sizeof(WCHAR));
  copy[source_units] = L'\0';
  absolute = normalize_windows_reparse_target(parent, copy, relative);
  free(copy);
  if (absolute == NULL)
  {
    return NULL;
  }
  utf8 = wide_to_utf8(absolute);
  free(absolute);
  return utf8;
}

static int inspect_windows_path(
  const char *requested,
  size_t requested_length,
  yaca_windows_snapshot *snapshot,
  const char **code,
  const char **message)
{
  WCHAR *wide = NULL;
  WCHAR *absolute = NULL;
  WCHAR *raw_parent = NULL;
  WCHAR *name = NULL;
  WCHAR *canonical_parent = NULL;
  WCHAR *canonical_target = NULL;
  WIN32_FIND_DATAW found;
  HANDLE finder = INVALID_HANDLE_VALUE;
  DWORD error_value;
  int metadata_result;

  memset(snapshot, 0, sizeof(*snapshot));
  snapshot->target_handle = INVALID_HANDLE_VALUE;
  snapshot->parent_handle = INVALID_HANDLE_VALUE;
  wide = utf8_to_wide(requested, requested_length);
  if (wide == NULL || !validate_windows_direct_wide_path(wide))
  {
    *code = "InvalidPath";
    *message = "direct Windows path is invalid or ambiguous";
    goto fail;
  }
  absolute = windows_full_path(wide);
  free(wide);
  wide = NULL;
  if (absolute == NULL || !validate_windows_direct_wide_path(absolute))
  {
    *code = "InvalidPath";
    *message = "direct Windows path cannot be canonicalized";
    goto fail;
  }
  if (wcslen(absolute) == windows_path_root_length(absolute))
  {
    raw_parent = duplicate_wide(absolute);
    name = duplicate_wide(L"");
  }
  else if (!windows_parent_and_name(absolute, &raw_parent, &name))
  {
    *code = "InvalidPath";
    *message = "direct Windows path has no valid parent";
    goto fail;
  }
  canonical_parent = windows_long_path(raw_parent);
  if (canonical_parent == NULL)
  {
    *code = windows_error_code(GetLastError());
    *message = "direct Windows parent cannot be canonicalized";
    goto fail;
  }
  if (name[0] == L'\0')
  {
    canonical_target = duplicate_wide(canonical_parent);
  }
  else
  {
    WCHAR *candidate = windows_join_path(canonical_parent, name);
    if (candidate == NULL)
    {
      *code = "Storage";
      *message = "direct Windows target allocation failed";
      goto fail;
    }
    finder = FindFirstFileW(candidate, &found);
    if (finder != INVALID_HANDLE_VALUE)
    {
      FindClose(finder);
      finder = INVALID_HANDLE_VALUE;
      canonical_target = windows_join_path(canonical_parent, found.cFileName);
    }
    else
    {
      error_value = GetLastError();
      if (error_value != ERROR_FILE_NOT_FOUND
          && error_value != ERROR_PATH_NOT_FOUND)
      {
        free(candidate);
        *code = windows_error_code(error_value);
        *message = "direct Windows target lookup failed";
        goto fail;
      }
      canonical_target = candidate;
      candidate = NULL;
    }
    free(candidate);
  }
  if (canonical_target == NULL || !build_windows_ancestry(snapshot, canonical_parent))
  {
    *code = GetLastError() == ERROR_CANT_RESOLVE_FILENAME
      ? "LinkDenied"
      : windows_error_code(GetLastError());
    *message = "direct Windows physical ancestry is unavailable";
    goto fail;
  }
  snapshot->parent_handle = open_windows_direct_path(
    canonical_parent,
    FILE_READ_ATTRIBUTES | READ_CONTROL);
  if (snapshot->parent_handle == INVALID_HANDLE_VALUE
      || !GetFileInformationByHandle(
        snapshot->parent_handle,
        &snapshot->parent_information)
      || snapshot->ancestor_count == 0U)
  {
    *code = windows_error_code(GetLastError());
    *message = "direct Windows parent identity is unavailable";
    goto fail;
  }
  {
    yaca_identity parent_identity;
    memset(&parent_identity, 0, sizeof(parent_identity));
    if (!identity_from_handle(snapshot->parent_handle, &parent_identity)
        || strcmp(parent_identity.volume,
          snapshot->ancestors[snapshot->ancestor_count - 1U].identity.volume) != 0
        || strcmp(parent_identity.object,
          snapshot->ancestors[snapshot->ancestor_count - 1U].identity.object) != 0)
    {
      *code = "TargetChanged";
      *message = "direct Windows parent changed during inspection";
      goto fail;
    }
  }
  snapshot->target_handle = open_windows_direct_path(
    canonical_target,
    GENERIC_READ | FILE_READ_ATTRIBUTES | READ_CONTROL);
  if (snapshot->target_handle == INVALID_HANDLE_VALUE)
  {
    error_value = GetLastError();
    if (error_value == ERROR_FILE_NOT_FOUND || error_value == ERROR_PATH_NOT_FOUND)
    {
      snapshot->exists = 0;
    }
    else
    {
      *code = windows_error_code(error_value);
      *message = "direct Windows target open failed";
      goto fail;
    }
  }
  else
  {
    snapshot->exists = 1;
    if (!GetFileInformationByHandle(
        snapshot->target_handle,
        &snapshot->target_information))
    {
      *code = windows_error_code(GetLastError());
      *message = "direct Windows target identity failed";
      goto fail;
    }
    snapshot->reparse =
      (snapshot->target_information.dwFileAttributes
        & FILE_ATTRIBUTE_REPARSE_POINT) != 0;
    if (snapshot->reparse)
    {
      snapshot->link_target = windows_reparse_target(
        snapshot->target_handle,
        canonical_parent);
      if (snapshot->link_target == NULL)
      {
        *code = "Unsupported";
        *message = "direct Windows reparse target is unsupported";
        goto fail;
      }
      snapshot->metadata.attributes =
        snapshot->target_information.dwFileAttributes;
    }
    else
    {
      metadata_result = capture_windows_metadata(
        snapshot->target_handle,
        &snapshot->target_information,
        canonical_target,
        (snapshot->target_information.dwFileAttributes
          & FILE_ATTRIBUTE_DIRECTORY) == 0,
        &snapshot->metadata);
      if (metadata_result < 0)
      {
        *code = "Storage";
        *message = "direct Windows metadata inspection failed";
        goto fail;
      }
      if (metadata_result == 0)
      {
        snapshot->metadata.attributes =
          snapshot->target_information.dwFileAttributes;
      }
    }
  }
  snapshot->canonical_path = canonical_target;
  canonical_target = NULL;
  snapshot->parent_path = canonical_parent;
  canonical_parent = NULL;
  free(absolute);
  free(raw_parent);
  free(name);
  return 1;

fail:
  if (finder != INVALID_HANDLE_VALUE) FindClose(finder);
  free(wide);
  free(absolute);
  free(raw_parent);
  free(name);
  free(canonical_parent);
  free(canonical_target);
  free_windows_snapshot(snapshot);
  return 0;
}

static int push_windows_direct_snapshot(
  lua_State *L,
  const char *requested,
  size_t requested_length,
  const char **code,
  const char **message)
{
  yaca_windows_snapshot snapshot;
  yaca_identity identity;
  char *canonical = NULL;
  char *ancestor_path = NULL;
  char behavior[96];
  size_t index;
  int initial_top = lua_gettop(L);

  if (!inspect_windows_path(
      requested,
      requested_length,
      &snapshot,
      code,
      message))
  {
    return 0;
  }
  canonical = wide_to_utf8(snapshot.canonical_path);
  if (canonical == NULL)
  {
    *code = "InvalidEncoding";
    *message = "direct Windows canonical path is not strict UTF-8";
    goto fail;
  }
  lua_createtable(L, 0, 8);
  lua_pushlstring(L, requested, requested_length);
  lua_setfield(L, -2, "requested_path");
  lua_pushstring(L, canonical);
  lua_setfield(L, -2, "canonical_path");
  lua_pushboolean(L, snapshot.exists);
  lua_setfield(L, -2, "exists");
  if (snapshot.exists)
  {
    memset(&identity, 0, sizeof(identity));
    if (!identity_from_handle(snapshot.target_handle, &identity))
    {
      *code = windows_error_code(GetLastError());
      *message = "direct Windows target identity failed";
      goto fail;
    }
    if (snapshot.reparse)
    {
      strcpy(identity.kind, "link");
    }
    push_identity(L, &identity);
    lua_setfield(L, -2, "identity");
    if (!windows_behavior_digest(&snapshot.metadata, behavior))
    {
      *code = "Storage";
      *message = "direct Windows behavior metadata is unavailable";
      goto fail;
    }
    lua_createtable(L, 0, 4);
    lua_pushinteger(
      L,
      (lua_Integer)snapshot.target_information.nNumberOfLinks);
    lua_setfield(L, -2, "link_count");
    lua_pushstring(L, behavior);
    lua_setfield(L, -2, "behavior_digest");
    lua_pushstring(
      L,
      snapshot.metadata.proven && !snapshot.reparse
        ? "proven"
        : "unsupported");
    lua_setfield(L, -2, "preservation");
    if (snapshot.reparse)
    {
      lua_pushstring(L, snapshot.link_target);
    }
    else
    {
      lua_pushboolean(L, 0);
    }
    lua_setfield(L, -2, "link_target");
    lua_setfield(L, -2, "metadata");
  }
  else
  {
    lua_pushboolean(L, 0);
    lua_setfield(L, -2, "identity");
    lua_pushboolean(L, 0);
    lua_setfield(L, -2, "metadata");
  }
  memset(&identity, 0, sizeof(identity));
  if (!identity_from_handle(snapshot.parent_handle, &identity))
  {
    *code = windows_error_code(GetLastError());
    *message = "direct Windows parent identity failed";
    goto fail;
  }
  push_identity(L, &identity);
  lua_setfield(L, -2, "parent_identity");
  lua_createtable(
    L,
    (int)(snapshot.ancestor_count > (size_t)INT_MAX
      ? INT_MAX
      : snapshot.ancestor_count),
    0);
  for (index = 0U; index < snapshot.ancestor_count; ++index)
  {
    ancestor_path = wide_to_utf8(snapshot.ancestors[index].path);
    if (ancestor_path == NULL)
    {
      *code = "InvalidEncoding";
      *message = "direct Windows ancestor is not strict UTF-8";
      goto fail;
    }
    lua_createtable(L, 0, 2);
    lua_pushstring(L, ancestor_path);
    lua_setfield(L, -2, "path");
    push_identity(L, &snapshot.ancestors[index].identity);
    lua_setfield(L, -2, "identity");
    lua_seti(L, -2, (lua_Integer)index + 1);
    free(ancestor_path);
    ancestor_path = NULL;
  }
  lua_setfield(L, -2, "ancestors");
  lua_pushboolean(L, 1);
  lua_setfield(L, -2, "ancestry_complete");
  free(canonical);
  free_windows_snapshot(&snapshot);
  return 1;

fail:
  free(canonical);
  free(ancestor_path);
  lua_settop(L, initial_top);
  free_windows_snapshot(&snapshot);
  return 0;
}

static int l_fs_inspect_direct(lua_State *L)
{
  const char *path;
  size_t length;
  const char *code = "Storage";
  const char *message = "direct Windows filesystem inspection failed";
  if (!checked_byte_string(
      L,
      1,
      &path,
      &length,
      "InvalidPath",
      "direct Windows filesystem path is invalid"))
  {
    return 2;
  }
  if (!push_windows_direct_snapshot(L, path, length, &code, &message))
  {
    return push_failure(L, code, message);
  }
  return return_success(L);
}

static int windows_handle_matches_lua(lua_State *L, int index, HANDLE handle)
{
  yaca_identity identity;
  memset(&identity, 0, sizeof(identity));
  return identity_from_handle(handle, &identity)
    && identity_matches_lua(L, index, &identity);
}

static int l_fs_open_read_verified(lua_State *L)
{
  const char *path;
  size_t length;
  yaca_windows_snapshot snapshot;
  const char *code = "Storage";
  const char *message = "direct Windows read failed";
  yaca_file *file;
  if (!checked_byte_string(
      L, 1, &path, &length, "InvalidPath", "direct Windows read path is invalid"))
  {
    return 2;
  }
  luaL_checktype(L, 2, LUA_TTABLE);
  if (!inspect_windows_path(path, length, &snapshot, &code, &message))
  {
    return push_failure(L, code, message);
  }
  if (!snapshot.exists
      || snapshot.reparse
      || (snapshot.target_information.dwFileAttributes
        & FILE_ATTRIBUTE_DIRECTORY) != 0
      || !windows_handle_matches_lua(L, 2, snapshot.target_handle))
  {
    free_windows_snapshot(&snapshot);
    return push_failure(L, "TargetChanged", "direct Windows read target changed");
  }
  file = push_file(L);
  file->handle = snapshot.target_handle;
  snapshot.target_handle = INVALID_HANDLE_VALUE;
  free_windows_snapshot(&snapshot);
  return return_success(L);
}

static int l_fs_create_new_verified(lua_State *L)
{
  const char *path;
  size_t length;
  lua_Integer permissions;
  yaca_windows_snapshot snapshot;
  const char *code = "Storage";
  const char *message = "direct Windows create failed";
  HANDLE handle;
  DWORD error_value;
  yaca_file *file;
  if (!checked_byte_string(
      L, 1, &path, &length, "InvalidPath", "direct Windows create path is invalid"))
  {
    return 2;
  }
  luaL_checktype(L, 2, LUA_TTABLE);
  permissions = luaL_checkinteger(L, 3);
  if (permissions < 0 || permissions > 0777)
  {
    return push_failure(L, "InvalidPermissions", "direct create permissions are invalid");
  }
  if (!inspect_windows_path(path, length, &snapshot, &code, &message))
  {
    return push_failure(L, code, message);
  }
  if (snapshot.exists
      || !windows_handle_matches_lua(L, 2, snapshot.parent_handle))
  {
    int existed = snapshot.exists;
    free_windows_snapshot(&snapshot);
    return push_failure(
      L,
      existed ? "DestinationExists" : "TargetChanged",
      "direct Windows create binding changed");
  }
  handle = CreateFileW(
    snapshot.canonical_path,
    GENERIC_READ | GENERIC_WRITE,
    FILE_SHARE_READ,
    NULL,
    CREATE_NEW,
    FILE_ATTRIBUTE_NORMAL,
    NULL);
  error_value = GetLastError();
  free_windows_snapshot(&snapshot);
  if (handle == INVALID_HANDLE_VALUE)
  {
    return push_windows_failure(L, error_value, "direct Windows create failed");
  }
  file = push_file(L);
  file->handle = handle;
  return return_success(L);
}

static int synchronize_windows_candidate_metadata(
  const WCHAR *path,
  HANDLE handle,
  const yaca_windows_metadata_state *current,
  const yaca_windows_metadata_state *required)
{
  const DWORD settable = FILE_ATTRIBUTE_READONLY
    | FILE_ATTRIBUTE_HIDDEN
    | FILE_ATTRIBUTE_SYSTEM
    | FILE_ATTRIBUTE_ARCHIVE
    | FILE_ATTRIBUTE_TEMPORARY
    | FILE_ATTRIBUTE_OFFLINE
    | FILE_ATTRIBUTE_NOT_CONTENT_INDEXED;
  DWORD attributes;
  SECURITY_INFORMATION security = OWNER_SECURITY_INFORMATION
    | GROUP_SECURITY_INFORMATION
    | DACL_SECURITY_INFORMATION;

  if ((current->attributes & ~settable)
      != (required->attributes & ~settable))
  {
    SetLastError(ERROR_NOT_SUPPORTED);
    return 0;
  }
  if (current->security_descriptor_length
      != required->security_descriptor_length
      || memcmp(
        current->security_descriptor,
        required->security_descriptor,
        required->security_descriptor_length) != 0)
  {
    if (!SetKernelObjectSecurity(
        handle,
        security,
        required->security_descriptor))
    {
      return 0;
    }
  }
  attributes = required->attributes & settable;
  if (attributes == 0U)
  {
    attributes = FILE_ATTRIBUTE_NORMAL;
  }
  if ((current->attributes & settable) != (required->attributes & settable)
      && !SetFileAttributesW(path, attributes))
  {
    return 0;
  }
  return 1;
}

static WCHAR *windows_replacement_backup_path(const WCHAR *temporary)
{
  static const WCHAR suffix[] = L".yaca-previous";
  size_t length = wcslen(temporary);
  size_t suffix_length = wcslen(suffix);
  WCHAR *result;
  if (length > YACA_WINDOWS_LONG_PATH_UNITS - suffix_length - 1U)
  {
    SetLastError(ERROR_FILENAME_EXCED_RANGE);
    return NULL;
  }
  result = (WCHAR *)malloc((length + suffix_length + 1U) * sizeof(WCHAR));
  if (result == NULL)
  {
    SetLastError(ERROR_NOT_ENOUGH_MEMORY);
    return NULL;
  }
  memcpy(result, temporary, length * sizeof(WCHAR));
  memcpy(
    result + length,
    suffix,
    (suffix_length + 1U) * sizeof(WCHAR));
  return result;
}

static int windows_snapshot_matches_lua(
  lua_State *L,
  int index,
  const yaca_windows_snapshot *snapshot)
{
  return snapshot->exists
    && windows_handle_matches_lua(L, index, snapshot->target_handle);
}

static int l_fs_replace_verified(lua_State *L)
{
  const char *temporary_path;
  const char *target_path;
  const char *expected_behavior;
  size_t temporary_length;
  size_t target_length;
  size_t expected_behavior_length;
  yaca_windows_snapshot temporary;
  yaca_windows_snapshot target;
  yaca_windows_snapshot published;
  yaca_windows_snapshot displaced;
  yaca_windows_snapshot restored;
  const char *code = "Storage";
  const char *message = "direct Windows replacement failed";
  HANDLE candidate_handle = INVALID_HANDLE_VALUE;
  BY_HANDLE_FILE_INFORMATION candidate_information;
  yaca_windows_metadata_state candidate_metadata;
  WCHAR *backup_path = NULL;
  char *backup_utf8 = NULL;
  char behavior[96];
  DWORD error_value;
  int rollback_succeeded = 0;

  memset(&temporary, 0, sizeof(temporary));
  memset(&target, 0, sizeof(target));
  memset(&published, 0, sizeof(published));
  memset(&displaced, 0, sizeof(displaced));
  memset(&restored, 0, sizeof(restored));
  temporary.target_handle = temporary.parent_handle = INVALID_HANDLE_VALUE;
  target.target_handle = target.parent_handle = INVALID_HANDLE_VALUE;
  published.target_handle = published.parent_handle = INVALID_HANDLE_VALUE;
  displaced.target_handle = displaced.parent_handle = INVALID_HANDLE_VALUE;
  restored.target_handle = restored.parent_handle = INVALID_HANDLE_VALUE;
  memset(&candidate_metadata, 0, sizeof(candidate_metadata));

  if (!checked_byte_string(
      L, 1, &temporary_path, &temporary_length,
      "InvalidPath", "direct Windows temporary path is invalid"))
  {
    return 2;
  }
  if (!checked_byte_string(
      L, 2, &target_path, &target_length,
      "InvalidPath", "direct Windows target path is invalid"))
  {
    return 2;
  }
  luaL_checktype(L, 3, LUA_TTABLE);
  luaL_checktype(L, 4, LUA_TTABLE);
  luaL_checktype(L, 5, LUA_TTABLE);
  if (!checked_byte_string(
      L, 6, &expected_behavior, &expected_behavior_length,
      "InvalidMetadata", "direct Windows behavior digest is invalid"))
  {
    return 2;
  }
  if (!inspect_windows_path(
      temporary_path,
      temporary_length,
      &temporary,
      &code,
      &message)
      || !inspect_windows_path(
        target_path,
        target_length,
        &target,
        &code,
        &message))
  {
    goto failed;
  }
  if (!windows_snapshot_matches_lua(L, 3, &temporary)
      || !windows_snapshot_matches_lua(L, 4, &target)
      || !windows_handle_matches_lua(L, 5, target.parent_handle)
      || !windows_same_object(
        &temporary.parent_information,
        &target.parent_information)
      || temporary.reparse
      || target.reparse
      || (temporary.target_information.dwFileAttributes
        & FILE_ATTRIBUTE_DIRECTORY) != 0
      || (target.target_information.dwFileAttributes
        & FILE_ATTRIBUTE_DIRECTORY) != 0
      || temporary.target_information.nNumberOfLinks != 1U
      || target.target_information.nNumberOfLinks != 1U)
  {
    code = "TargetChanged";
    message = "direct Windows replacement binding changed";
    goto failed;
  }
  if (!target.metadata.proven
      || !temporary.metadata.proven
      || !windows_behavior_digest(&target.metadata, behavior)
      || strlen(behavior) != expected_behavior_length
      || memcmp(behavior, expected_behavior, expected_behavior_length) != 0)
  {
    code = "MetadataPreservationUnsupported";
    message = "direct Windows target metadata is unavailable or stale";
    goto failed;
  }
  candidate_handle = CreateFileW(
    temporary.canonical_path,
    GENERIC_READ | GENERIC_WRITE | READ_CONTROL | WRITE_DAC | WRITE_OWNER,
    FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
    NULL,
    OPEN_EXISTING,
    FILE_FLAG_OPEN_REPARSE_POINT,
    NULL);
  if (candidate_handle == INVALID_HANDLE_VALUE
      || !GetFileInformationByHandle(
        candidate_handle,
        &candidate_information)
      || !windows_same_object(
        &candidate_information,
        &temporary.target_information))
  {
    code = "TargetChanged";
    message = "direct Windows replacement candidate changed";
    goto failed;
  }
  if (!synchronize_windows_candidate_metadata(
      temporary.canonical_path,
      candidate_handle,
      &temporary.metadata,
      &target.metadata)
      || !FlushFileBuffers(candidate_handle))
  {
    code = windows_error_code(GetLastError());
    message = "direct Windows replacement metadata preservation failed";
    goto failed;
  }
  if (!GetFileInformationByHandle(
      candidate_handle,
      &candidate_information))
  {
    code = windows_error_code(GetLastError());
    message = "direct Windows replacement candidate identity is unavailable";
    goto failed;
  }
  if (capture_windows_metadata(
      candidate_handle,
      &candidate_information,
      temporary.canonical_path,
      1,
      &candidate_metadata) != 1
      || !windows_metadata_states_equal(
        &candidate_metadata,
        &target.metadata))
  {
    code = "MetadataPreservationUnsupported";
    message = "direct Windows replacement metadata verification failed";
    goto failed;
  }
  backup_path = windows_replacement_backup_path(temporary.canonical_path);
  if (backup_path == NULL)
  {
    code = windows_error_code(GetLastError());
    message = "direct Windows recovery path allocation failed";
    goto failed;
  }
  if (GetFileAttributesW(backup_path) != INVALID_FILE_ATTRIBUTES
      || GetLastError() != ERROR_FILE_NOT_FOUND)
  {
    code = "TemporaryConflict";
    message = "direct Windows recovery path is occupied or unverifiable";
    goto failed;
  }
  backup_utf8 = wide_to_utf8(backup_path);
  if (backup_utf8 == NULL)
  {
    code = "InvalidEncoding";
    message = "direct Windows recovery path is not strict UTF-8";
    goto failed;
  }
  CloseHandle(candidate_handle);
  candidate_handle = INVALID_HANDLE_VALUE;
  close_windows_snapshot_handles(&temporary);
  close_windows_snapshot_handles(&target);
  if (!ReplaceFileW(
      target.canonical_path,
      temporary.canonical_path,
      backup_path,
      0,
      NULL,
      NULL))
  {
    error_value = GetLastError();
    code = (error_value == ERROR_UNABLE_TO_MOVE_REPLACEMENT
        || error_value == ERROR_UNABLE_TO_MOVE_REPLACEMENT_2
        || error_value == ERROR_UNABLE_TO_REMOVE_REPLACED)
      ? "Unknown"
      : windows_error_code(error_value);
    message = "direct Windows replacement failed";
    goto failed;
  }
  if (!inspect_windows_path(
      target_path,
      target_length,
      &published,
      &code,
      &message)
      || !inspect_windows_path(
        backup_utf8,
        strlen(backup_utf8),
        &displaced,
        &code,
        &message))
  {
    code = "Unknown";
    message = "direct Windows replacement postcondition is unknown";
    goto failed;
  }
  if (windows_snapshot_matches_lua(L, 3, &published)
      && published.metadata.proven
      && windows_behavior_digest(&published.metadata, behavior)
      && strlen(behavior) == expected_behavior_length
      && memcmp(behavior, expected_behavior, expected_behavior_length) == 0
      && windows_snapshot_matches_lua(L, 4, &displaced)
      && displaced.metadata.proven
      && windows_behavior_digest(&displaced.metadata, behavior)
      && strlen(behavior) == expected_behavior_length
      && memcmp(behavior, expected_behavior, expected_behavior_length) == 0)
  {
    DWORD attributes = displaced.target_information.dwFileAttributes;
    free_windows_snapshot(&published);
    free_windows_snapshot(&displaced);
    if ((attributes & FILE_ATTRIBUTE_READONLY) != 0
        && !SetFileAttributesW(
          backup_path,
          (attributes & ~FILE_ATTRIBUTE_READONLY) == 0U
            ? FILE_ATTRIBUTE_NORMAL
            : attributes & ~FILE_ATTRIBUTE_READONLY))
    {
      code = "Unknown";
      message = "direct Windows replacement recovery cleanup is unknown";
      goto failed;
    }
    if (!DeleteFileW(backup_path))
    {
      code = "Unknown";
      message = "direct Windows replacement recovery cleanup is unknown";
      goto failed;
    }
    free_windows_metadata_state(&candidate_metadata);
    free_windows_snapshot(&temporary);
    free_windows_snapshot(&target);
    free(backup_utf8);
    free(backup_path);
    return push_true_result(L);
  }
  if (windows_snapshot_matches_lua(L, 3, &published)
      && displaced.exists)
  {
    free_windows_snapshot(&published);
    free_windows_snapshot(&displaced);
    if (ReplaceFileW(
        target.canonical_path,
        backup_path,
        NULL,
        0,
        NULL,
        NULL)
        && inspect_windows_path(
          target_path,
          target_length,
          &restored,
          &code,
          &message)
        && windows_snapshot_matches_lua(L, 4, &restored))
    {
      rollback_succeeded = 1;
    }
  }
  code = rollback_succeeded ? "TargetChanged" : "Unknown";
  message = rollback_succeeded
    ? "direct Windows replacement target raced publication"
    : "direct Windows replacement race recovery is unknown";

failed:
  if (candidate_handle != INVALID_HANDLE_VALUE) CloseHandle(candidate_handle);
  free_windows_metadata_state(&candidate_metadata);
  free_windows_snapshot(&temporary);
  free_windows_snapshot(&target);
  free_windows_snapshot(&published);
  free_windows_snapshot(&displaced);
  free_windows_snapshot(&restored);
  free(backup_utf8);
  free(backup_path);
  return push_failure(L, code, message);
}

static int l_fs_rename_no_replace_verified(lua_State *L)
{
  const char *source_path;
  const char *target_path;
  size_t source_length;
  size_t target_length;
  yaca_windows_snapshot source;
  yaca_windows_snapshot target;
  yaca_windows_snapshot moved;
  yaca_windows_snapshot source_after;
  const char *code = "Storage";
  const char *message = "direct Windows rename failed";
  DWORD error_value;
  int rolled_back = 0;

  memset(&source, 0, sizeof(source));
  memset(&target, 0, sizeof(target));
  memset(&moved, 0, sizeof(moved));
  memset(&source_after, 0, sizeof(source_after));
  source.target_handle = source.parent_handle = INVALID_HANDLE_VALUE;
  target.target_handle = target.parent_handle = INVALID_HANDLE_VALUE;
  moved.target_handle = moved.parent_handle = INVALID_HANDLE_VALUE;
  source_after.target_handle = source_after.parent_handle = INVALID_HANDLE_VALUE;

  if (!checked_byte_string(
      L, 1, &source_path, &source_length,
      "InvalidPath", "direct Windows rename source is invalid"))
  {
    return 2;
  }
  if (!checked_byte_string(
      L, 2, &target_path, &target_length,
      "InvalidPath", "direct Windows rename target is invalid"))
  {
    return 2;
  }
  luaL_checktype(L, 3, LUA_TTABLE);
  luaL_checktype(L, 4, LUA_TTABLE);
  luaL_checktype(L, 5, LUA_TTABLE);
  if (!inspect_windows_path(
      source_path,
      source_length,
      &source,
      &code,
      &message)
      || !inspect_windows_path(
        target_path,
        target_length,
        &target,
        &code,
        &message))
  {
    goto failed;
  }
  if (!windows_snapshot_matches_lua(L, 3, &source)
      || !windows_handle_matches_lua(L, 4, source.parent_handle)
      || !windows_handle_matches_lua(L, 5, target.parent_handle)
      || target.exists
      || source.reparse
      || ((source.target_information.dwFileAttributes
        & FILE_ATTRIBUTE_DIRECTORY) == 0
        && source.target_information.nNumberOfLinks != 1U))
  {
    code = target.exists ? "DestinationExists" : "TargetChanged";
    message = "direct Windows rename binding changed";
    goto failed;
  }
  close_windows_snapshot_handles(&source);
  close_windows_snapshot_handles(&target);
  if (!MoveFileExW(
      source.canonical_path,
      target.canonical_path,
      MOVEFILE_WRITE_THROUGH))
  {
    error_value = GetLastError();
    code = windows_error_code(error_value);
    message = "direct Windows no-replace rename failed";
    goto failed;
  }
  if (!inspect_windows_path(
      target_path,
      target_length,
      &moved,
      &code,
      &message)
      || !inspect_windows_path(
        source_path,
        source_length,
        &source_after,
        &code,
        &message))
  {
    code = "Unknown";
    message = "direct Windows rename postcondition is unknown";
    goto failed;
  }
  if (windows_snapshot_matches_lua(L, 3, &moved) && !source_after.exists)
  {
    free_windows_snapshot(&source);
    free_windows_snapshot(&target);
    free_windows_snapshot(&moved);
    free_windows_snapshot(&source_after);
    return push_true_result(L);
  }
  if (moved.exists && !source_after.exists)
  {
    BY_HANDLE_FILE_INFORMATION moved_information = moved.target_information;
    free_windows_snapshot(&moved);
    free_windows_snapshot(&source_after);
    if (MoveFileExW(
        target.canonical_path,
        source.canonical_path,
        MOVEFILE_WRITE_THROUGH)
        && inspect_windows_path(
          source_path,
          source_length,
          &source_after,
          &code,
          &message)
        && source_after.exists
        && windows_same_object(
          &moved_information,
          &source_after.target_information))
    {
      rolled_back = 1;
    }
  }
  code = rolled_back ? "TargetChanged" : "Unknown";
  message = rolled_back
    ? "direct Windows rename source raced publication"
    : "direct Windows rename recovery is unknown";

failed:
  free_windows_snapshot(&source);
  free_windows_snapshot(&target);
  free_windows_snapshot(&moved);
  free_windows_snapshot(&source_after);
  return push_failure(L, code, message);
}

static WCHAR *windows_delete_recovery_path(const WCHAR *path)
{
  static const WCHAR suffix[] = L".yaca-delete";
  size_t length = wcslen(path);
  size_t suffix_length = wcslen(suffix);
  WCHAR *result;
  if (length > YACA_WINDOWS_LONG_PATH_UNITS - suffix_length - 1U)
  {
    SetLastError(ERROR_FILENAME_EXCED_RANGE);
    return NULL;
  }
  result = (WCHAR *)malloc((length + suffix_length + 1U) * sizeof(WCHAR));
  if (result == NULL)
  {
    SetLastError(ERROR_NOT_ENOUGH_MEMORY);
    return NULL;
  }
  memcpy(result, path, length * sizeof(WCHAR));
  memcpy(
    result + length,
    suffix,
    (suffix_length + 1U) * sizeof(WCHAR));
  return result;
}

static int l_fs_delete_direct_verified(lua_State *L)
{
  const char *path;
  size_t length;
  yaca_windows_snapshot target;
  yaca_windows_snapshot moved;
  const char *code = "Storage";
  const char *message = "direct Windows delete failed";
  WCHAR *recovery = NULL;
  char *recovery_utf8 = NULL;
  DWORD error_value;
  int is_directory;
  int rollback_succeeded = 0;

  memset(&target, 0, sizeof(target));
  memset(&moved, 0, sizeof(moved));
  target.target_handle = target.parent_handle = INVALID_HANDLE_VALUE;
  moved.target_handle = moved.parent_handle = INVALID_HANDLE_VALUE;
  if (!checked_byte_string(
      L, 1, &path, &length,
      "InvalidPath", "direct Windows delete path is invalid"))
  {
    return 2;
  }
  luaL_checktype(L, 2, LUA_TTABLE);
  luaL_checktype(L, 3, LUA_TTABLE);
  if (!inspect_windows_path(path, length, &target, &code, &message))
  {
    goto failed;
  }
  if (!windows_snapshot_matches_lua(L, 2, &target)
      || !windows_handle_matches_lua(L, 3, target.parent_handle)
      || target.reparse)
  {
    code = "TargetChanged";
    message = "direct Windows delete binding changed";
    goto failed;
  }
  is_directory = (target.target_information.dwFileAttributes
    & FILE_ATTRIBUTE_DIRECTORY) != 0;
  if (!is_directory && target.target_information.nNumberOfLinks != 1U)
  {
    code = "TargetChanged";
    message = "direct Windows delete target became hardlinked";
    goto failed;
  }
  recovery = windows_delete_recovery_path(target.canonical_path);
  if (recovery == NULL)
  {
    code = windows_error_code(GetLastError());
    message = "direct Windows delete recovery path allocation failed";
    goto failed;
  }
  if (GetFileAttributesW(recovery) != INVALID_FILE_ATTRIBUTES
      || GetLastError() != ERROR_FILE_NOT_FOUND)
  {
    code = "TemporaryConflict";
    message = "direct Windows delete recovery path is occupied or unverifiable";
    goto failed;
  }
  recovery_utf8 = wide_to_utf8(recovery);
  if (recovery_utf8 == NULL)
  {
    code = "InvalidEncoding";
    message = "direct Windows delete recovery path is not strict UTF-8";
    goto failed;
  }
  close_windows_snapshot_handles(&target);
  if (!MoveFileExW(
      target.canonical_path,
      recovery,
      MOVEFILE_WRITE_THROUGH))
  {
    error_value = GetLastError();
    code = windows_error_code(error_value);
    message = "direct Windows delete isolation failed";
    goto failed;
  }
  if (!inspect_windows_path(
      recovery_utf8,
      strlen(recovery_utf8),
      &moved,
      &code,
      &message))
  {
    code = "Unknown";
    message = "direct Windows delete isolation is unknown";
    goto failed;
  }
  if (!windows_snapshot_matches_lua(L, 2, &moved))
  {
    BY_HANDLE_FILE_INFORMATION moved_information = moved.target_information;
    free_windows_snapshot(&moved);
    if (MoveFileExW(recovery, target.canonical_path, MOVEFILE_WRITE_THROUGH)
        && inspect_windows_path(
          path,
          length,
          &moved,
          &code,
          &message)
        && moved.exists
        && windows_same_object(
          &moved_information,
          &moved.target_information))
    {
      rollback_succeeded = 1;
    }
    code = rollback_succeeded ? "TargetChanged" : "Unknown";
    message = rollback_succeeded
      ? "direct Windows delete target raced isolation"
      : "direct Windows delete race recovery is unknown";
    goto failed;
  }
  free_windows_snapshot(&moved);
  if ((is_directory && !RemoveDirectoryW(recovery))
      || (!is_directory && !DeleteFileW(recovery)))
  {
    error_value = GetLastError();
    if (MoveFileExW(recovery, target.canonical_path, MOVEFILE_WRITE_THROUGH))
    {
      code = windows_error_code(error_value);
      message = "direct Windows delete failed without publication";
    }
    else
    {
      code = "Unknown";
      message = "direct Windows delete rollback is unknown";
    }
    goto failed;
  }
  free_windows_snapshot(&target);
  free(recovery_utf8);
  free(recovery);
  return push_true_result(L);

failed:
  free_windows_snapshot(&target);
  free_windows_snapshot(&moved);
  free(recovery_utf8);
  free(recovery);
  return push_failure(L, code, message);
}

static void free_windows_path_vector(yaca_windows_path_vector *vector)
{
  size_t index;
  for (index = 0U; index < vector->count; ++index)
  {
    free(vector->items[index]);
  }
  free(vector->items);
  memset(vector, 0, sizeof(*vector));
}

static int append_windows_path(
  yaca_windows_path_vector *vector,
  const char *path)
{
  char **next;
  size_t capacity;
  if (vector->count >= vector->maximum)
  {
    vector->truncated = 1;
    return 1;
  }
  if (vector->count == vector->capacity)
  {
    capacity = vector->capacity == 0U ? 32U : vector->capacity * 2U;
    if (capacity < vector->capacity || capacity > vector->maximum)
    {
      capacity = vector->maximum;
    }
    next = (char **)realloc(vector->items, capacity * sizeof(char *));
    if (next == NULL)
    {
      return 0;
    }
    vector->items = next;
    vector->capacity = capacity;
  }
  vector->items[vector->count] = strdup(path);
  if (vector->items[vector->count] == NULL)
  {
    return 0;
  }
  ++vector->count;
  return 1;
}

static int compare_windows_paths(const void *left, const void *right)
{
  const char *const *left_path = (const char *const *)left;
  const char *const *right_path = (const char *const *)right;
  return strcmp(*left_path, *right_path);
}

static char *windows_relative_join(const char *parent, const char *name)
{
  size_t parent_length = strlen(parent);
  size_t name_length = strlen(name);
  char *result;
  if (parent_length > SIZE_MAX - name_length - 2U)
  {
    return NULL;
  }
  result = (char *)malloc(parent_length + name_length + 2U);
  if (result == NULL)
  {
    return NULL;
  }
  if (parent_length > 0U)
  {
    memcpy(result, parent, parent_length);
    result[parent_length++] = '/';
  }
  memcpy(result + parent_length, name, name_length + 1U);
  return result;
}

static WCHAR *windows_path_from_relative(
  const WCHAR *root,
  const char *relative)
{
  WCHAR *wide_relative;
  WCHAR *result;
  size_t length = strlen(relative);
  size_t index;
  if (length == 0U)
  {
    return duplicate_wide(root);
  }
  wide_relative = utf8_to_wide(relative, length);
  if (wide_relative == NULL)
  {
    return NULL;
  }
  for (index = 0U; wide_relative[index] != L'\0'; ++index)
  {
    if (wide_relative[index] == L'/') wide_relative[index] = L'\\';
  }
  result = windows_join_path(root, wide_relative);
  free(wide_relative);
  return result;
}

static int walk_windows_directory(
  const WCHAR *root,
  const char *relative,
  lua_Integer level,
  lua_Integer maximum_level,
  yaca_windows_path_vector *vector,
  const char **code,
  const char **message)
{
  WCHAR *directory_path = windows_path_from_relative(root, relative);
  WCHAR *pattern = NULL;
  HANDLE guard = INVALID_HANDLE_VALUE;
  HANDLE finder = INVALID_HANDLE_VALUE;
  WIN32_FIND_DATAW entry;
  BY_HANDLE_FILE_INFORMATION information;
  int has_ignore = 0;
  DWORD error_value;

  if (directory_path == NULL)
  {
    *code = "Storage";
    *message = "direct Windows walk path allocation failed";
    goto fail;
  }
  guard = CreateFileW(
    directory_path,
    FILE_LIST_DIRECTORY | FILE_READ_ATTRIBUTES | READ_CONTROL,
    FILE_SHARE_READ | FILE_SHARE_WRITE,
    NULL,
    OPEN_EXISTING,
    FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT,
    NULL);
  if (guard == INVALID_HANDLE_VALUE
      || !GetFileInformationByHandle(guard, &information)
      || (information.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) == 0
      || (information.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0)
  {
    *code = windows_error_code(GetLastError());
    *message = "direct Windows walk directory changed";
    goto fail;
  }
  pattern = windows_join_path(directory_path, L"*");
  if (pattern == NULL)
  {
    *code = "Storage";
    *message = "direct Windows walk pattern allocation failed";
    goto fail;
  }
  finder = FindFirstFileW(pattern, &entry);
  if (finder == INVALID_HANDLE_VALUE)
  {
    error_value = GetLastError();
    if (error_value == ERROR_FILE_NOT_FOUND)
    {
      CloseHandle(guard);
      free(pattern);
      free(directory_path);
      return 1;
    }
    *code = windows_error_code(error_value);
    *message = "direct Windows walk enumeration failed";
    goto fail;
  }
  do
  {
    if (_wcsicmp(entry.cFileName, L".gitignore") == 0)
    {
      has_ignore = 1;
      break;
    }
  }
  while (FindNextFileW(finder, &entry));
  error_value = GetLastError();
  FindClose(finder);
  finder = INVALID_HANDLE_VALUE;
  if (!has_ignore && error_value != ERROR_NO_MORE_FILES)
  {
    *code = windows_error_code(error_value);
    *message = "direct Windows walk enumeration failed";
    goto fail;
  }
  if (has_ignore)
  {
    char *name = wide_to_utf8(entry.cFileName);
    char *child = name == NULL ? NULL : windows_relative_join(relative, name);
    vector->conservative_ignore = 1;
    free(name);
    if (child == NULL || !append_windows_path(vector, child))
    {
      free(child);
      *code = "Storage";
      *message = "direct Windows walk entry allocation failed";
      goto fail;
    }
    free(child);
    CloseHandle(guard);
    free(pattern);
    free(directory_path);
    return 1;
  }
  finder = FindFirstFileW(pattern, &entry);
  if (finder == INVALID_HANDLE_VALUE)
  {
    error_value = GetLastError();
    if (error_value == ERROR_FILE_NOT_FOUND)
    {
      CloseHandle(guard);
      free(pattern);
      free(directory_path);
      return 1;
    }
    *code = windows_error_code(error_value);
    *message = "direct Windows walk enumeration failed";
    goto fail;
  }
  do
  {
    char *name;
    char *child;
    int recurse;
    if (wcscmp(entry.cFileName, L".") == 0
        || wcscmp(entry.cFileName, L"..") == 0
        || _wcsicmp(entry.cFileName, L".git") == 0)
    {
      continue;
    }
    name = wide_to_utf8(entry.cFileName);
    child = name == NULL ? NULL : windows_relative_join(relative, name);
    free(name);
    if (child == NULL || !append_windows_path(vector, child))
    {
      free(child);
      *code = "Storage";
      *message = "direct Windows walk entry allocation failed";
      goto fail;
    }
    if (vector->truncated)
    {
      free(child);
      break;
    }
    recurse = (entry.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0
      && (entry.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) == 0
      && level < maximum_level;
    if (recurse && !walk_windows_directory(
        root,
        child,
        level + 1,
        maximum_level,
        vector,
        code,
        message))
    {
      free(child);
      goto fail;
    }
    free(child);
    if (vector->truncated) break;
  }
  while (FindNextFileW(finder, &entry));
  error_value = GetLastError();
  if (!vector->truncated && error_value != ERROR_NO_MORE_FILES)
  {
    *code = windows_error_code(error_value);
    *message = "direct Windows walk enumeration failed";
    goto fail;
  }
  FindClose(finder);
  CloseHandle(guard);
  free(pattern);
  free(directory_path);
  return 1;

fail:
  if (finder != INVALID_HANDLE_VALUE) FindClose(finder);
  if (guard != INVALID_HANDLE_VALUE) CloseHandle(guard);
  free(pattern);
  free(directory_path);
  return 0;
}

static int append_windows_walk_generation_from_lua(
  lua_State *L,
  int snapshot_index,
  const char *relative,
  yaca_sha256 *hash)
{
  char header[96];
  int written;
  const char *fields[5];
  size_t lengths[5];
  lua_Integer size;
  size_t index;

  snapshot_index = lua_absindex(L, snapshot_index);
  lua_getfield(L, snapshot_index, "identity");
  if (!lua_istable(L, -1))
  {
    lua_pop(L, 1);
    return 0;
  }
  fields[0] = relative;
  lengths[0] = strlen(relative);
  lua_getfield(L, -1, "kind");
  fields[1] = lua_tolstring(L, -1, &lengths[1]);
  lua_getfield(L, -2, "volume");
  fields[2] = lua_tolstring(L, -1, &lengths[2]);
  lua_getfield(L, -3, "object");
  fields[3] = lua_tolstring(L, -1, &lengths[3]);
  lua_getfield(L, -4, "modified");
  fields[4] = lua_tolstring(L, -1, &lengths[4]);
  lua_getfield(L, -5, "size");
  if (fields[1] == NULL || fields[2] == NULL
      || fields[3] == NULL || fields[4] == NULL
      || !lua_isinteger(L, -1))
  {
    lua_pop(L, 6);
    return 0;
  }
  size = lua_tointeger(L, -1);
  for (index = 0U; index < 4U; ++index)
  {
    written = snprintf(header, sizeof(header), "%zu:", lengths[index]);
    if (written <= 0 || (size_t)written >= sizeof(header)
        || !sha256_append(hash, (const unsigned char *)header, (size_t)written)
        || !sha256_append(
          hash,
          (const unsigned char *)fields[index],
          lengths[index]))
    {
      lua_pop(L, 6);
      return 0;
    }
  }
  written = snprintf(header, sizeof(header), "%lld:", (long long)size);
  if (written <= 0 || (size_t)written >= sizeof(header)
      || !sha256_append(hash, (const unsigned char *)header, (size_t)written))
  {
    lua_pop(L, 6);
    return 0;
  }
  written = snprintf(header, sizeof(header), "%zu:", lengths[4]);
  if (written <= 0 || (size_t)written >= sizeof(header)
      || !sha256_append(hash, (const unsigned char *)header, (size_t)written)
      || !sha256_append(
        hash,
        (const unsigned char *)fields[4],
        lengths[4])
      || !sha256_append(hash, (const unsigned char *)"\n", 1U))
  {
    lua_pop(L, 6);
    return 0;
  }
  lua_pop(L, 6);
  return 1;
}

static int l_fs_walk_direct(lua_State *L)
{
  const char *root;
  const char *policy;
  size_t root_length;
  size_t policy_length;
  lua_Integer depth;
  lua_Integer maximum;
  yaca_windows_snapshot root_snapshot;
  yaca_windows_path_vector vector;
  const char *code = "Storage";
  const char *message = "direct Windows walk failed";
  size_t index;
  yaca_sha256 hash;
  unsigned char digest[32];
  char generation[73];
  static const char hexadecimal[] = "0123456789abcdef";

  memset(&root_snapshot, 0, sizeof(root_snapshot));
  root_snapshot.target_handle = root_snapshot.parent_handle = INVALID_HANDLE_VALUE;
  memset(&vector, 0, sizeof(vector));
  if (!checked_byte_string(
      L, 1, &root, &root_length,
      "InvalidPath", "direct Windows walk root is invalid"))
  {
    return 2;
  }
  depth = luaL_checkinteger(L, 2);
  maximum = luaL_checkinteger(L, 3);
  policy = luaL_checklstring(L, 4, &policy_length);
  if (depth < 0 || maximum <= 0
      || (lua_Unsigned)maximum > (lua_Unsigned)SIZE_MAX
      || policy_length != strlen("git-compatible-v1")
      || memcmp(policy, "git-compatible-v1", policy_length) != 0)
  {
    return push_failure(L, "InvalidWalk", "direct Windows walk bounds are invalid");
  }
  if (!inspect_windows_path(
      root,
      root_length,
      &root_snapshot,
      &code,
      &message))
  {
    return push_failure(L, code, message);
  }
  if (!root_snapshot.exists
      || root_snapshot.reparse
      || (root_snapshot.target_information.dwFileAttributes
        & FILE_ATTRIBUTE_DIRECTORY) == 0)
  {
    free_windows_snapshot(&root_snapshot);
    return push_failure(L, "InvalidTargetType", "direct walk root must be a directory");
  }
  vector.maximum = (size_t)maximum;
  if (!walk_windows_directory(
      root_snapshot.canonical_path,
      "",
      1,
      depth + 1,
      &vector,
      &code,
      &message))
  {
    free_windows_snapshot(&root_snapshot);
    free_windows_path_vector(&vector);
    return push_failure(L, code, message);
  }
  if (vector.count > 1U)
  {
    qsort(vector.items, vector.count, sizeof(char *), compare_windows_paths);
  }
  sha256_initialize(&hash);
  lua_createtable(L, 0, 4);
  lua_createtable(
    L,
    (int)(vector.count > (size_t)INT_MAX ? INT_MAX : vector.count),
    0);
  for (index = 0U; index < vector.count; ++index)
  {
    WCHAR *wide_path = windows_path_from_relative(
      root_snapshot.canonical_path,
      vector.items[index]);
    char *full_path = wide_path == NULL ? NULL : wide_to_utf8(wide_path);
    free(wide_path);
    if (full_path == NULL)
    {
      lua_settop(L, 0);
      free_windows_snapshot(&root_snapshot);
      free_windows_path_vector(&vector);
      return push_failure(L, "InvalidEncoding", "direct Windows walk path is invalid");
    }
    lua_createtable(L, 0, 2);
    lua_pushstring(L, vector.items[index]);
    lua_setfield(L, -2, "relative_path");
    if (!push_windows_direct_snapshot(
        L,
        full_path,
        strlen(full_path),
        &code,
        &message)
        || !append_windows_walk_generation_from_lua(
          L,
          -1,
          vector.items[index],
          &hash))
    {
      free(full_path);
      lua_settop(L, 0);
      free_windows_snapshot(&root_snapshot);
      free_windows_path_vector(&vector);
      return push_failure(L, code, message);
    }
    lua_setfield(L, -2, "snapshot");
    lua_seti(L, -2, (lua_Integer)index + 1);
    free(full_path);
  }
  lua_setfield(L, -2, "entries");
  sha256_finalize(&hash, digest);
  memcpy(generation, "walk-v1-", 8U);
  for (index = 0U; index < 32U; ++index)
  {
    generation[8U + index * 2U] = hexadecimal[digest[index] >> 4U];
    generation[9U + index * 2U] = hexadecimal[digest[index] & 0x0FU];
  }
  generation[72] = '\0';
  lua_pushstring(L, generation);
  lua_setfield(L, -2, "generation");
  lua_pushboolean(L, !vector.truncated && !vector.conservative_ignore);
  lua_setfield(L, -2, "complete");
  if (vector.truncated)
  {
    lua_pushstring(L, "entry-limit");
  }
  else if (vector.conservative_ignore)
  {
    lua_pushstring(L, "git-ignore-policy-conservative");
  }
  else
  {
    lua_pushboolean(L, 0);
  }
  lua_setfield(L, -2, "partial_reason");
  free_windows_snapshot(&root_snapshot);
  free_windows_path_vector(&vector);
  return return_success(L);
}

#endif

#if !defined(_WIN32)

typedef struct yaca_posix_snapshot
{
  char *canonical_path;
  char *parent_path;
  int exists;
  struct stat target;
  struct stat parent;
} yaca_posix_snapshot;

typedef struct yaca_path_vector
{
  char **items;
  size_t count;
  size_t capacity;
  size_t maximum;
  int truncated;
  int conservative_ignore;
} yaca_path_vector;

#define YACA_XATTR_MAX_COUNT 1024U
#define YACA_XATTR_MAX_BYTES (1024U * 1024U)
#define YACA_LINK_TARGET_MAX_BYTES (1024U * 1024U)

typedef struct yaca_xattr
{
  char *name;
  unsigned char *value;
  size_t length;
} yaca_xattr;

typedef struct yaca_xattr_set
{
  yaca_xattr *items;
  size_t count;
  size_t total_bytes;
} yaca_xattr_set;

typedef struct yaca_posix_metadata_state
{
  mode_t mode;
  uid_t uid;
  gid_t gid;
  unsigned int filesystem_flags;
  yaca_xattr_set xattrs;
  int proven;
} yaca_posix_metadata_state;

enum yaca_metadata_capture
{
  YACA_METADATA_ERROR = -1,
  YACA_METADATA_UNSUPPORTED = 0,
  YACA_METADATA_PROVEN = 1
};

static void free_xattr_set(yaca_xattr_set *set)
{
  size_t index;
  for (index = 0U; index < set->count; ++index)
  {
    free(set->items[index].name);
    free(set->items[index].value);
  }
  free(set->items);
  memset(set, 0, sizeof(*set));
}

static void free_posix_metadata_state(yaca_posix_metadata_state *state)
{
  free_xattr_set(&state->xattrs);
  memset(state, 0, sizeof(*state));
}

static int compare_xattrs(const void *left, const void *right)
{
  const yaca_xattr *left_attribute = (const yaca_xattr *)left;
  const yaca_xattr *right_attribute = (const yaca_xattr *)right;
  return strcmp(left_attribute->name, right_attribute->name);
}

static int same_stat_observation(
  const struct stat *left,
  const struct stat *right)
{
  return left->st_dev == right->st_dev
    && left->st_ino == right->st_ino
    && (left->st_mode & S_IFMT) == (right->st_mode & S_IFMT)
    && left->st_size == right->st_size
    && left->st_nlink == right->st_nlink
    && left->st_mtim.tv_sec == right->st_mtim.tv_sec
    && left->st_mtim.tv_nsec == right->st_mtim.tv_nsec
    && left->st_ctim.tv_sec == right->st_ctim.tv_sec
    && left->st_ctim.tv_nsec == right->st_ctim.tv_nsec;
}

#if defined(__linux__)

static int load_descriptor_xattrs(int descriptor, yaca_xattr_set *set)
{
  ssize_t listed;
  ssize_t confirmed;
  char *names = NULL;
  size_t offset = 0U;
  size_t count = 0U;
  size_t index;

  memset(set, 0, sizeof(*set));
  listed = flistxattr(descriptor, NULL, 0U);
  if (listed < 0)
  {
    if (errno == ENOTSUP || errno == EOPNOTSUPP
        || errno == EACCES || errno == EPERM)
    {
      return YACA_METADATA_UNSUPPORTED;
    }
    return YACA_METADATA_ERROR;
  }
  if ((size_t)listed > YACA_XATTR_MAX_BYTES)
  {
    errno = E2BIG;
    return YACA_METADATA_UNSUPPORTED;
  }
  if (listed == 0)
  {
    return YACA_METADATA_PROVEN;
  }
  names = (char *)malloc((size_t)listed);
  if (names == NULL)
  {
    errno = ENOMEM;
    return YACA_METADATA_ERROR;
  }
  confirmed = flistxattr(descriptor, names, (size_t)listed);
  if (confirmed != listed)
  {
    int error_value = confirmed < 0 ? errno : EAGAIN;
    free(names);
    errno = error_value;
    return YACA_METADATA_ERROR;
  }
  while (offset < (size_t)listed)
  {
    size_t remaining = (size_t)listed - offset;
    char *terminator = (char *)memchr(names + offset, '\0', remaining);
    size_t name_length;
    if (terminator == NULL || terminator == names + offset)
    {
      free(names);
      errno = EIO;
      return YACA_METADATA_ERROR;
    }
    name_length = (size_t)(terminator - (names + offset));
    if (name_length > YACA_XATTR_MAX_BYTES - 1U - set->total_bytes
        || count >= YACA_XATTR_MAX_COUNT)
    {
      free(names);
      errno = E2BIG;
      return YACA_METADATA_UNSUPPORTED;
    }
    set->total_bytes += name_length + 1U;
    ++count;
    offset += name_length + 1U;
  }
  set->items = (yaca_xattr *)calloc(count, sizeof(yaca_xattr));
  if (set->items == NULL)
  {
    free(names);
    errno = ENOMEM;
    return YACA_METADATA_ERROR;
  }
  set->count = count;
  offset = 0U;
  for (index = 0U; index < count; ++index)
  {
    size_t name_length = strlen(names + offset);
    set->items[index].name = strdup(names + offset);
    if (set->items[index].name == NULL)
    {
      free(names);
      free_xattr_set(set);
      errno = ENOMEM;
      return YACA_METADATA_ERROR;
    }
    offset += name_length + 1U;
  }
  free(names);
  if (set->count > 1U)
  {
    qsort(set->items, set->count, sizeof(yaca_xattr), compare_xattrs);
  }
  for (index = 0U; index < set->count; ++index)
  {
    ssize_t value_length = fgetxattr(
      descriptor, set->items[index].name, NULL, 0U);
    ssize_t value_confirmed;
    if (value_length < 0)
    {
      int error_value = errno;
      free_xattr_set(set);
      errno = error_value;
      return (error_value == EACCES || error_value == EPERM)
        ? YACA_METADATA_UNSUPPORTED
        : YACA_METADATA_ERROR;
    }
    if ((size_t)value_length > YACA_XATTR_MAX_BYTES - set->total_bytes)
    {
      free_xattr_set(set);
      errno = E2BIG;
      return YACA_METADATA_UNSUPPORTED;
    }
    if (value_length > 0)
    {
      set->items[index].value = (unsigned char *)malloc((size_t)value_length);
      if (set->items[index].value == NULL)
      {
        free_xattr_set(set);
        errno = ENOMEM;
        return YACA_METADATA_ERROR;
      }
    }
    value_confirmed = fgetxattr(
      descriptor,
      set->items[index].name,
      set->items[index].value,
      (size_t)value_length);
    if (value_confirmed != value_length)
    {
      int error_value = value_confirmed < 0 ? errno : EAGAIN;
      free_xattr_set(set);
      errno = error_value;
      return (error_value == EACCES || error_value == EPERM)
        ? YACA_METADATA_UNSUPPORTED
        : YACA_METADATA_ERROR;
    }
    set->items[index].length = (size_t)value_length;
    set->total_bytes += (size_t)value_length;
  }
  return YACA_METADATA_PROVEN;
}

#endif

static int capture_posix_metadata(
  int descriptor,
  const struct stat *information,
  yaca_posix_metadata_state *state)
{
  memset(state, 0, sizeof(*state));
  state->mode = information->st_mode & 07777;
  state->uid = information->st_uid;
  state->gid = information->st_gid;
#if defined(__linux__)
  {
    int flags = 0;
    int captured;
    if (ioctl(descriptor, FS_IOC_GETFLAGS, &flags) != 0)
    {
      if (errno == ENOTTY || errno == ENOTSUP || errno == EOPNOTSUPP
          || errno == EACCES || errno == EPERM)
      {
        return YACA_METADATA_UNSUPPORTED;
      }
      return YACA_METADATA_ERROR;
    }
    state->filesystem_flags = (unsigned int)flags;
    captured = load_descriptor_xattrs(descriptor, &state->xattrs);
    if (captured != YACA_METADATA_PROVEN)
    {
      return captured;
    }
  }
  state->proven = 1;
  return YACA_METADATA_PROVEN;
#else
  (void)descriptor;
  return YACA_METADATA_UNSUPPORTED;
#endif
}

static int append_digest_field(
  yaca_sha256 *hash,
  const void *bytes,
  size_t length)
{
  char header[64];
  int written = snprintf(header, sizeof(header), "%zu:", length);
  return written > 0
    && (size_t)written < sizeof(header)
    && sha256_append(hash, (const unsigned char *)header, (size_t)written)
    && sha256_append(hash, (const unsigned char *)bytes, length);
}

static int posix_behavior_digest(
  const yaca_posix_metadata_state *state,
  char output[96])
{
  yaca_sha256 hash;
  unsigned char digest[32];
  char hexadecimal[65];
  char scalar[96];
  int written;
  size_t index;
  const char *availability = state->proven ? "proven" : "unsupported";

  sha256_initialize(&hash);
  if (!append_digest_field(&hash, "yaca-posix-behavior-v2", 22U)
      || !append_digest_field(&hash, availability, strlen(availability)))
  {
    return 0;
  }
  written = snprintf(
    scalar,
    sizeof(scalar),
    "%llo:%llu:%llu:%u",
    (unsigned long long)state->mode,
    (unsigned long long)state->uid,
    (unsigned long long)state->gid,
    state->filesystem_flags);
  if (written <= 0 || (size_t)written >= sizeof(scalar)
      || !append_digest_field(&hash, scalar, (size_t)written))
  {
    return 0;
  }
  for (index = 0U; index < state->xattrs.count; ++index)
  {
    if (!append_digest_field(
        &hash,
        state->xattrs.items[index].name,
        strlen(state->xattrs.items[index].name))
        || !append_digest_field(
          &hash,
          state->xattrs.items[index].value,
          state->xattrs.items[index].length))
    {
      return 0;
    }
  }
  sha256_finalize(&hash, digest);
  digest_hex(digest, hexadecimal);
  written = snprintf(
    output,
    96U,
    "posix-v2-%s",
    hexadecimal);
  return written > 0 && written < 96;
}

static int xattr_sets_equal(
  const yaca_xattr_set *left,
  const yaca_xattr_set *right)
{
  size_t index;
  if (left->count != right->count)
  {
    return 0;
  }
  for (index = 0U; index < left->count; ++index)
  {
    if (strcmp(left->items[index].name, right->items[index].name) != 0
        || left->items[index].length != right->items[index].length
        || (left->items[index].length > 0U
          && memcmp(
            left->items[index].value,
            right->items[index].value,
            left->items[index].length) != 0))
    {
      return 0;
    }
  }
  return 1;
}

static int posix_metadata_states_equal(
  const yaca_posix_metadata_state *left,
  const yaca_posix_metadata_state *right)
{
  return left->proven && right->proven
    && left->mode == right->mode
    && left->uid == right->uid
    && left->gid == right->gid
    && left->filesystem_flags == right->filesystem_flags
    && xattr_sets_equal(&left->xattrs, &right->xattrs);
}

#if defined(__linux__)
static int synchronize_descriptor_xattrs(
  int descriptor,
  const yaca_xattr_set *current,
  const yaca_xattr_set *required)
{
  size_t current_index = 0U;
  size_t required_index = 0U;
  while (current_index < current->count || required_index < required->count)
  {
    int comparison;
    if (current_index >= current->count)
    {
      comparison = 1;
    }
    else if (required_index >= required->count)
    {
      comparison = -1;
    }
    else
    {
      comparison = strcmp(
        current->items[current_index].name,
        required->items[required_index].name);
    }
    if (comparison < 0)
    {
      if (fremovexattr(descriptor, current->items[current_index].name) != 0)
      {
        return 0;
      }
      ++current_index;
    }
    else if (comparison > 0)
    {
      if (fsetxattr(
          descriptor,
          required->items[required_index].name,
          required->items[required_index].value,
          required->items[required_index].length,
          0) != 0)
      {
        return 0;
      }
      ++required_index;
    }
    else
    {
      const yaca_xattr *present = &current->items[current_index];
      const yaca_xattr *wanted = &required->items[required_index];
      if (present->length != wanted->length
          || (present->length > 0U
            && memcmp(present->value, wanted->value, present->length) != 0))
      {
        if (fsetxattr(
            descriptor,
            wanted->name,
            wanted->value,
            wanted->length,
            0) != 0)
        {
          return 0;
        }
      }
      ++current_index;
      ++required_index;
    }
  }
  return 1;
}
#endif

static void direct_error(
  const char **code,
  const char **message,
  const char *next_code,
  const char *next_message)
{
  *code = next_code;
  *message = next_message;
}

static char *posix_join_path(const char *parent, const char *name)
{
  size_t parent_length = strlen(parent);
  size_t name_length = strlen(name);
  int root = parent_length == 1U && parent[0] == '/';
  size_t length;
  char *result;

  if (parent_length > SIZE_MAX - name_length - (root ? 1U : 2U))
  {
    return NULL;
  }
  length = parent_length + name_length + (root ? 0U : 1U);
  result = (char *)malloc(length + 1U);
  if (result == NULL)
  {
    return NULL;
  }
  memcpy(result, parent, parent_length);
  if (!root)
  {
    result[parent_length] = '/';
    ++parent_length;
  }
  memcpy(result + parent_length, name, name_length + 1U);
  return result;
}

static int posix_parent_and_name(
  const char *path,
  char **parent,
  char **name,
  const char **code,
  const char **message)
{
  const char *separator;
  size_t parent_length;

  if (path[0] != '/' || path[1] == '\0' || path[strlen(path) - 1U] == '/')
  {
    direct_error(code, message, "InvalidPath", "direct path must name an absolute entry");
    return 0;
  }
  separator = strrchr(path, '/');
  if (separator == NULL || separator[1] == '\0'
      || strcmp(separator + 1, ".") == 0
      || strcmp(separator + 1, "..") == 0)
  {
    direct_error(code, message, "InvalidPath", "direct path basename is invalid");
    return 0;
  }
  parent_length = separator == path ? 1U : (size_t)(separator - path);
  *parent = (char *)malloc(parent_length + 1U);
  *name = strdup(separator + 1);
  if (*parent == NULL || *name == NULL)
  {
    free(*parent);
    free(*name);
    *parent = NULL;
    *name = NULL;
    direct_error(code, message, "Storage", "direct path allocation failed");
    return 0;
  }
  memcpy(*parent, path, parent_length);
  (*parent)[parent_length] = '\0';
  return 1;
}

static void free_posix_snapshot(yaca_posix_snapshot *snapshot)
{
  free(snapshot->canonical_path);
  free(snapshot->parent_path);
  memset(snapshot, 0, sizeof(*snapshot));
}

static int inspect_posix_path(
  const char *path,
  yaca_posix_snapshot *snapshot,
  const char **code,
  const char **message)
{
  char *raw_parent = NULL;
  char *name = NULL;
  int error_value;

  memset(snapshot, 0, sizeof(*snapshot));
  if (path[0] != '/')
  {
    direct_error(code, message, "InvalidPath", "direct path must be absolute");
    return 0;
  }
  if (strcmp(path, "/") == 0)
  {
    snapshot->canonical_path = strdup("/");
    snapshot->parent_path = strdup("/");
    if (snapshot->canonical_path == NULL || snapshot->parent_path == NULL)
    {
      free_posix_snapshot(snapshot);
      direct_error(code, message, "Storage", "direct path allocation failed");
      return 0;
    }
    if (lstat("/", &snapshot->target) != 0
        || stat("/", &snapshot->parent) != 0)
    {
      error_value = errno;
      free_posix_snapshot(snapshot);
      direct_error(code, message, errno_code(error_value), "direct root inspection failed");
      return 0;
    }
    snapshot->exists = 1;
    return 1;
  }
  if (!posix_parent_and_name(path, &raw_parent, &name, code, message))
  {
    return 0;
  }
  snapshot->parent_path = realpath(raw_parent, NULL);
  free(raw_parent);
  if (snapshot->parent_path == NULL)
  {
    error_value = errno;
    free(name);
    direct_error(code, message, errno_code(error_value), "direct parent inspection failed");
    return 0;
  }
  snapshot->canonical_path = posix_join_path(snapshot->parent_path, name);
  free(name);
  if (snapshot->canonical_path == NULL)
  {
    free_posix_snapshot(snapshot);
    direct_error(code, message, "Storage", "direct canonical path allocation failed");
    return 0;
  }
  if (stat(snapshot->parent_path, &snapshot->parent) != 0
      || !S_ISDIR(snapshot->parent.st_mode))
  {
    error_value = errno == 0 ? ENOTDIR : errno;
    free_posix_snapshot(snapshot);
    direct_error(code, message, errno_code(error_value), "direct parent is unavailable");
    return 0;
  }
  if (lstat(snapshot->canonical_path, &snapshot->target) == 0)
  {
    snapshot->exists = 1;
  }
  else if (errno == ENOENT)
  {
    snapshot->exists = 0;
    memset(&snapshot->target, 0, sizeof(snapshot->target));
  }
  else
  {
    error_value = errno;
    free_posix_snapshot(snapshot);
    direct_error(code, message, errno_code(error_value), "direct target inspection failed");
    return 0;
  }
  return 1;
}

static int push_posix_ancestor(
  lua_State *L,
  const char *path,
  const struct stat *information,
  lua_Integer index)
{
  yaca_identity identity;

  memset(&identity, 0, sizeof(identity));
  if (!identity_from_stat(information, &identity))
  {
    return 0;
  }
  lua_createtable(L, 0, 2);
  lua_pushstring(L, path);
  lua_setfield(L, -2, "path");
  push_identity(L, &identity);
  lua_setfield(L, -2, "identity");
  lua_seti(L, -2, index);
  return 1;
}

static int push_posix_ancestors(
  lua_State *L,
  const char *parent_path,
  const char **code,
  const char **message)
{
  struct stat information;
  char *prefix;
  size_t length;
  size_t index;
  lua_Integer output_index = 1;

  length = strlen(parent_path);
  prefix = (char *)malloc(length + 1U);
  if (prefix == NULL)
  {
    direct_error(code, message, "Storage", "direct ancestry allocation failed");
    return 0;
  }
  lua_createtable(L, 4, 0);
  if (stat("/", &information) != 0
      || !push_posix_ancestor(L, "/", &information, output_index++))
  {
    free(prefix);
    direct_error(code, message, errno_code(errno), "direct root ancestry failed");
    return 0;
  }
  if (strcmp(parent_path, "/") != 0)
  {
    for (index = 1U; index <= length; ++index)
    {
      if (index == length || parent_path[index] == '/')
      {
        memcpy(prefix, parent_path, index);
        prefix[index] = '\0';
        if (stat(prefix, &information) != 0
            || !S_ISDIR(information.st_mode)
            || !push_posix_ancestor(L, prefix, &information, output_index++))
        {
          free(prefix);
          direct_error(code, message, errno_code(errno), "direct physical ancestry failed");
          return 0;
        }
      }
    }
  }
  free(prefix);
  return 1;
}

static int push_posix_metadata(
  lua_State *L,
  const yaca_posix_snapshot *snapshot,
  const char **code,
  const char **message)
{
  char behavior[96];
  yaca_posix_metadata_state metadata;
  int capture = YACA_METADATA_UNSUPPORTED;
  int descriptor = -1;

  if ((uintmax_t)snapshot->target.st_nlink > (uintmax_t)LUA_MAXINTEGER)
  {
    direct_error(code, message, "Storage", "direct link count exceeds Lua integer range");
    return 0;
  }
  memset(&metadata, 0, sizeof(metadata));
  metadata.mode = snapshot->target.st_mode & 07777;
  metadata.uid = snapshot->target.st_uid;
  metadata.gid = snapshot->target.st_gid;
  if (S_ISREG(snapshot->target.st_mode) || S_ISDIR(snapshot->target.st_mode))
  {
    struct stat opened_information;
    int flags = O_RDONLY | O_NOFOLLOW | O_CLOEXEC;
    if (S_ISDIR(snapshot->target.st_mode))
    {
      flags |= O_DIRECTORY;
    }
    descriptor = open(snapshot->canonical_path, flags);
    if (descriptor >= 0)
    {
      if (fstat(descriptor, &opened_information) != 0
          || !same_stat_observation(&snapshot->target, &opened_information))
      {
        int error_value = errno == 0 ? EAGAIN : errno;
        close(descriptor);
        direct_error(code, message, errno_code(error_value), "direct metadata target changed");
        return 0;
      }
      capture = capture_posix_metadata(
        descriptor, &opened_information, &metadata);
      close(descriptor);
      descriptor = -1;
      if (capture == YACA_METADATA_ERROR)
      {
        int error_value = errno;
        free_posix_metadata_state(&metadata);
        direct_error(
          code,
          message,
          error_value == ENOMEM ? "Storage" : "TargetChanged",
          "direct behavior metadata changed during inspection");
        return 0;
      }
    }
    else if (errno != EACCES && errno != EPERM)
    {
      int error_value = errno;
      direct_error(code, message, errno_code(error_value), "direct metadata open failed");
      return 0;
    }
  }
  if (!posix_behavior_digest(&metadata, behavior))
  {
    free_posix_metadata_state(&metadata);
    direct_error(code, message, "Storage", "direct behavior metadata is unavailable");
    return 0;
  }
  lua_createtable(L, 0, 4);
  lua_pushinteger(L, (lua_Integer)snapshot->target.st_nlink);
  lua_setfield(L, -2, "link_count");
  lua_pushstring(L, behavior);
  lua_setfield(L, -2, "behavior_digest");
  lua_pushstring(
    L,
    capture == YACA_METADATA_PROVEN
      ? "proven"
      : "unsupported");
  lua_setfield(L, -2, "preservation");
  if (S_ISLNK(snapshot->target.st_mode))
  {
    size_t capacity;
    char *target;
    ssize_t count;
    char *absolute;

    if (snapshot->target.st_size > 0)
    {
      if ((uintmax_t)snapshot->target.st_size
          >= (uintmax_t)YACA_LINK_TARGET_MAX_BYTES)
      {
        free_posix_metadata_state(&metadata);
        direct_error(code, message, "Storage", "direct link target exceeds its hard limit");
        return 0;
      }
      capacity = (size_t)snapshot->target.st_size + 1U;
    }
    else
    {
      capacity = 4096U;
    }
    target = (char *)malloc(capacity + 1U);

    if (target == NULL)
    {
      free_posix_metadata_state(&metadata);
      direct_error(code, message, "Storage", "direct link target allocation failed");
      return 0;
    }
    count = readlink(snapshot->canonical_path, target, capacity);
    if (count < 0 || (size_t)count >= capacity)
    {
      free(target);
      free_posix_metadata_state(&metadata);
      direct_error(code, message, "Storage", "direct link target is unavailable");
      return 0;
    }
    target[count] = '\0';
    absolute = target[0] == '/'
      ? strdup(target)
      : posix_join_path(snapshot->parent_path, target);
    free(target);
    if (absolute == NULL)
    {
      free_posix_metadata_state(&metadata);
      direct_error(code, message, "Storage", "direct link target allocation failed");
      return 0;
    }
    lua_pushstring(L, absolute);
    lua_setfield(L, -2, "link_target");
    free(absolute);
  }
  else
  {
    lua_pushboolean(L, 0);
    lua_setfield(L, -2, "link_target");
  }
  free_posix_metadata_state(&metadata);
  return 1;
}

static int push_posix_direct_snapshot(
  lua_State *L,
  const char *requested_path,
  const char **code,
  const char **message)
{
  yaca_posix_snapshot snapshot;
  yaca_identity identity;
  int initial_top = lua_gettop(L);

  if (!inspect_posix_path(requested_path, &snapshot, code, message))
  {
    return 0;
  }
  memset(&identity, 0, sizeof(identity));
  lua_createtable(L, 0, 8);
  lua_pushstring(L, requested_path);
  lua_setfield(L, -2, "requested_path");
  lua_pushstring(L, snapshot.canonical_path);
  lua_setfield(L, -2, "canonical_path");
  lua_pushboolean(L, snapshot.exists);
  lua_setfield(L, -2, "exists");
  if (snapshot.exists)
  {
    if (!identity_from_stat(&snapshot.target, &identity))
    {
      direct_error(code, message, errno_code(errno), "direct target identity failed");
      goto fail;
    }
    push_identity(L, &identity);
    lua_setfield(L, -2, "identity");
    if (!push_posix_metadata(L, &snapshot, code, message))
    {
      goto fail;
    }
    lua_setfield(L, -2, "metadata");
  }
  else
  {
    lua_pushboolean(L, 0);
    lua_setfield(L, -2, "identity");
    lua_pushboolean(L, 0);
    lua_setfield(L, -2, "metadata");
  }
  memset(&identity, 0, sizeof(identity));
  if (!identity_from_stat(&snapshot.parent, &identity))
  {
    direct_error(code, message, errno_code(errno), "direct parent identity failed");
    goto fail;
  }
  push_identity(L, &identity);
  lua_setfield(L, -2, "parent_identity");
  if (!push_posix_ancestors(L, snapshot.parent_path, code, message))
  {
    goto fail;
  }
  lua_setfield(L, -2, "ancestors");
  lua_pushboolean(L, 1);
  lua_setfield(L, -2, "ancestry_complete");
  free_posix_snapshot(&snapshot);
  return 1;

fail:
  lua_settop(L, initial_top);
  free_posix_snapshot(&snapshot);
  return 0;
}

static int l_fs_inspect_direct(lua_State *L)
{
  const char *path;
  size_t length;
  const char *code = "Storage";
  const char *message = "direct filesystem inspection failed";

  if (!checked_byte_string(
      L, 1, &path, &length, "InvalidPath", "direct filesystem path is invalid"))
  {
    return 2;
  }
  (void)length;
  if (!push_posix_direct_snapshot(L, path, &code, &message))
  {
    return push_failure(L, code, message);
  }
  return return_success(L);
}

static void free_path_vector(yaca_path_vector *vector)
{
  size_t index;
  for (index = 0U; index < vector->count; ++index)
  {
    free(vector->items[index]);
  }
  free(vector->items);
  memset(vector, 0, sizeof(*vector));
}

static int append_path(yaca_path_vector *vector, const char *path)
{
  char **next;
  size_t capacity;

  if (vector->count >= vector->maximum)
  {
    vector->truncated = 1;
    return 1;
  }
  if (vector->count == vector->capacity)
  {
    capacity = vector->capacity == 0U ? 32U : vector->capacity * 2U;
    if (capacity > vector->maximum)
    {
      capacity = vector->maximum;
    }
    next = (char **)realloc(vector->items, capacity * sizeof(char *));
    if (next == NULL)
    {
      return 0;
    }
    vector->items = next;
    vector->capacity = capacity;
  }
  vector->items[vector->count] = strdup(path);
  if (vector->items[vector->count] == NULL)
  {
    return 0;
  }
  ++vector->count;
  return 1;
}

static int compare_paths(const void *left, const void *right)
{
  const char *const *left_path = (const char *const *)left;
  const char *const *right_path = (const char *const *)right;
  return strcmp(*left_path, *right_path);
}

static char *relative_join(const char *parent, const char *name)
{
  size_t parent_length = strlen(parent);
  size_t name_length = strlen(name);
  char *result;

  if (parent_length == 0U)
  {
    return strdup(name);
  }
  if (parent_length > SIZE_MAX - name_length - 2U)
  {
    return NULL;
  }
  result = (char *)malloc(parent_length + name_length + 2U);
  if (result == NULL)
  {
    return NULL;
  }
  memcpy(result, parent, parent_length);
  result[parent_length] = '/';
  memcpy(result + parent_length + 1U, name, name_length + 1U);
  return result;
}

static int walk_posix_directory(
  const char *root,
  const char *relative,
  lua_Integer level,
  lua_Integer maximum_level,
  yaca_path_vector *vector,
  const char **code,
  const char **message)
{
  char *directory_path = relative[0] == '\0'
    ? strdup(root)
    : posix_join_path(root, relative);
  DIR *directory;
  struct dirent *entry;
  int has_ignore = 0;

  if (directory_path == NULL)
  {
    direct_error(code, message, "Storage", "direct walk path allocation failed");
    return 0;
  }
  directory = opendir(directory_path);
  if (directory == NULL)
  {
    int error_value = errno;
    free(directory_path);
    direct_error(code, message, errno_code(error_value), "direct walk directory failed");
    return 0;
  }
  errno = 0;
  while ((entry = readdir(directory)) != NULL)
  {
    if (strcmp(entry->d_name, ".gitignore") == 0)
    {
      has_ignore = 1;
      break;
    }
  }
  if (entry == NULL && errno != 0)
  {
    int error_value = errno;
    closedir(directory);
    free(directory_path);
    direct_error(code, message, errno_code(error_value), "direct walk enumeration failed");
    return 0;
  }
  rewinddir(directory);
  if (has_ignore)
  {
    char *ignore_relative = relative_join(relative, ".gitignore");
    vector->conservative_ignore = 1;
    if (ignore_relative == NULL || !append_path(vector, ignore_relative))
    {
      free(ignore_relative);
      closedir(directory);
      free(directory_path);
      direct_error(code, message, "Storage", "direct walk entry allocation failed");
      return 0;
    }
    free(ignore_relative);
    closedir(directory);
    free(directory_path);
    return 1;
  }
  errno = 0;
  while (!vector->truncated && (entry = readdir(directory)) != NULL)
  {
    char *child_relative;
    char *child_path;
    struct stat information;
    int recurse;

    if (strcmp(entry->d_name, ".") == 0
        || strcmp(entry->d_name, "..") == 0
        || strcmp(entry->d_name, ".git") == 0)
    {
      continue;
    }
    child_relative = relative_join(relative, entry->d_name);
    child_path = child_relative == NULL ? NULL : posix_join_path(root, child_relative);
    if (child_relative == NULL || child_path == NULL)
    {
      free(child_relative);
      free(child_path);
      closedir(directory);
      free(directory_path);
      direct_error(code, message, "Storage", "direct walk entry allocation failed");
      return 0;
    }
    if (lstat(child_path, &information) != 0)
    {
      int error_value = errno;
      free(child_relative);
      free(child_path);
      closedir(directory);
      free(directory_path);
      direct_error(code, message, errno_code(error_value), "direct walk entry changed");
      return 0;
    }
    if (!append_path(vector, child_relative))
    {
      free(child_relative);
      free(child_path);
      closedir(directory);
      free(directory_path);
      direct_error(code, message, "Storage", "direct walk entry allocation failed");
      return 0;
    }
    recurse = S_ISDIR(information.st_mode) && level < maximum_level;
    if (recurse && !walk_posix_directory(
        root,
        child_relative,
        level + 1,
        maximum_level,
        vector,
        code,
        message))
    {
      free(child_relative);
      free(child_path);
      closedir(directory);
      free(directory_path);
      return 0;
    }
    free(child_relative);
    free(child_path);
  }
  if (entry == NULL && errno != 0)
  {
    int error_value = errno;
    closedir(directory);
    free(directory_path);
    direct_error(code, message, errno_code(error_value), "direct walk enumeration failed");
    return 0;
  }
  closedir(directory);
  free(directory_path);
  return 1;
}

static int append_walk_generation(
  yaca_sha256 *hash,
  const char *relative,
  const struct stat *information)
{
  yaca_identity identity;
  char header[96];
  int length;

#define APPEND_WALK_FIELD(value) do { \
    size_t field_length__ = strlen(value); \
    length = snprintf(header, sizeof(header), "%zu:", field_length__); \
    if (length <= 0 || (size_t)length >= sizeof(header) \
        || !sha256_append(hash, (const unsigned char *)header, (size_t)length) \
        || !sha256_append(hash, (const unsigned char *)(value), field_length__)) \
    { \
      return 0; \
    } \
  } while (0)

  memset(&identity, 0, sizeof(identity));
  if (!identity_from_stat(information, &identity))
  {
    return 0;
  }
  APPEND_WALK_FIELD(relative);
  APPEND_WALK_FIELD(identity.kind);
  APPEND_WALK_FIELD(identity.volume);
  APPEND_WALK_FIELD(identity.object);
  length = snprintf(header, sizeof(header), "%lld:", (long long)identity.size);
  if (length <= 0 || (size_t)length >= sizeof(header)
      || !sha256_append(hash, (const unsigned char *)header, (size_t)length))
  {
    return 0;
  }
  APPEND_WALK_FIELD(identity.modified);
  if (!sha256_append(hash, (const unsigned char *)"\n", 1U))
  {
    return 0;
  }
#undef APPEND_WALK_FIELD
  return 1;
}

static void digest_hex(const unsigned char digest[32], char output[65])
{
  static const char hexadecimal[] = "0123456789abcdef";
  size_t index;
  for (index = 0U; index < 32U; ++index)
  {
    output[index * 2U] = hexadecimal[digest[index] >> 4U];
    output[index * 2U + 1U] = hexadecimal[digest[index] & 0x0FU];
  }
  output[64] = '\0';
}

static int l_fs_walk_direct(lua_State *L)
{
  const char *root;
  const char *policy;
  size_t root_length;
  size_t policy_length;
  lua_Integer depth;
  lua_Integer maximum;
  yaca_posix_snapshot root_snapshot;
  yaca_path_vector vector;
  const char *code = "Storage";
  const char *message = "direct walk failed";
  size_t index;
  yaca_sha256 hash;
  unsigned char digest[32];
  char generation[73];

  if (!checked_byte_string(L, 1, &root, &root_length, "InvalidPath", "walk root is invalid"))
  {
    return 2;
  }
  depth = luaL_checkinteger(L, 2);
  maximum = luaL_checkinteger(L, 3);
  policy = luaL_checklstring(L, 4, &policy_length);
  if (root[0] != '/' || depth < 0 || maximum <= 0
      || (lua_Unsigned)maximum > (lua_Unsigned)SIZE_MAX
      || policy_length != strlen("git-compatible-v1")
      || memcmp(policy, "git-compatible-v1", policy_length) != 0)
  {
    return push_failure(L, "InvalidWalk", "direct walk bounds or policy are invalid");
  }
  (void)root_length;
  if (!inspect_posix_path(root, &root_snapshot, &code, &message))
  {
    return push_failure(L, code, message);
  }
  if (!root_snapshot.exists || !S_ISDIR(root_snapshot.target.st_mode))
  {
    free_posix_snapshot(&root_snapshot);
    return push_failure(L, "InvalidTargetType", "direct walk root must be a directory");
  }
  memset(&vector, 0, sizeof(vector));
  vector.maximum = (size_t)maximum;
  if (!walk_posix_directory(
      root_snapshot.canonical_path,
      "",
      1,
      depth + 1,
      &vector,
      &code,
      &message))
  {
    free_posix_snapshot(&root_snapshot);
    free_path_vector(&vector);
    return push_failure(L, code, message);
  }
  if (vector.count > 1U)
  {
    qsort(vector.items, vector.count, sizeof(char *), compare_paths);
  }
  sha256_initialize(&hash);
  lua_createtable(L, 0, 4);
  lua_createtable(L, (int)(vector.count > (size_t)INT_MAX ? INT_MAX : vector.count), 0);
  for (index = 0U; index < vector.count; ++index)
  {
    char *full_path = posix_join_path(root_snapshot.canonical_path, vector.items[index]);
    struct stat information;
    if (full_path == NULL
        || lstat(full_path, &information) != 0
        || !append_walk_generation(&hash, vector.items[index], &information))
    {
      free(full_path);
      lua_settop(L, 0);
      free_posix_snapshot(&root_snapshot);
      free_path_vector(&vector);
      return push_failure(L, "TargetChanged", "direct walk entry changed during inspection");
    }
    lua_createtable(L, 0, 2);
    lua_pushstring(L, vector.items[index]);
    lua_setfield(L, -2, "relative_path");
    if (!push_posix_direct_snapshot(L, full_path, &code, &message))
    {
      free(full_path);
      lua_settop(L, 0);
      free_posix_snapshot(&root_snapshot);
      free_path_vector(&vector);
      return push_failure(L, code, message);
    }
    lua_setfield(L, -2, "snapshot");
    lua_seti(L, -2, (lua_Integer)index + 1);
    free(full_path);
  }
  lua_setfield(L, -2, "entries");
  sha256_finalize(&hash, digest);
  memcpy(generation, "walk-v1-", 8U);
  digest_hex(digest, generation + 8U);
  lua_pushstring(L, generation);
  lua_setfield(L, -2, "generation");
  lua_pushboolean(L, !vector.truncated && !vector.conservative_ignore);
  lua_setfield(L, -2, "complete");
  if (vector.truncated)
  {
    lua_pushstring(L, "entry-limit");
  }
  else if (vector.conservative_ignore)
  {
    lua_pushstring(L, "git-ignore-policy-conservative");
  }
  else
  {
    lua_pushboolean(L, 0);
  }
  lua_setfield(L, -2, "partial_reason");
  free_posix_snapshot(&root_snapshot);
  free_path_vector(&vector);
  return return_success(L);
}

static int open_posix_parent(
  const char *path,
  int *descriptor,
  char **parent,
  char **name,
  const char **code,
  const char **message)
{
  if (!posix_parent_and_name(path, parent, name, code, message))
  {
    return 0;
  }
  *descriptor = open(*parent, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
  if (*descriptor < 0)
  {
    int error_value = errno;
    free(*parent);
    free(*name);
    *parent = NULL;
    *name = NULL;
    direct_error(code, message, errno_code(error_value), "direct parent open failed");
    return 0;
  }
  return 1;
}

static int descriptor_matches_lua(lua_State *L, int index, int descriptor)
{
  struct stat information;
  yaca_identity identity;
  memset(&identity, 0, sizeof(identity));
  return fstat(descriptor, &information) == 0
    && identity_from_stat(&information, &identity)
    && identity_matches_lua(L, index, &identity);
}

static int stat_at_matches_lua(
  lua_State *L,
  int index,
  int parent,
  const char *name,
  struct stat *information)
{
  yaca_identity identity;
  memset(&identity, 0, sizeof(identity));
  return fstatat(parent, name, information, AT_SYMLINK_NOFOLLOW) == 0
    && identity_from_stat(information, &identity)
    && identity_matches_lua(L, index, &identity);
}

static int l_fs_open_read_verified(lua_State *L)
{
  const char *path;
  size_t length;
  int descriptor;
  struct stat information;
  yaca_identity identity;
  yaca_file *file;

  if (!checked_byte_string(L, 1, &path, &length, "InvalidPath", "direct read path is invalid"))
  {
    return 2;
  }
  luaL_checktype(L, 2, LUA_TTABLE);
  if (path[0] != '/')
  {
    return push_failure(L, "InvalidPath", "direct read path must be absolute");
  }
  (void)length;
  descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
  if (descriptor < 0)
  {
    return push_failure(L, errno_code(errno), "direct read open failed");
  }
  memset(&identity, 0, sizeof(identity));
  if (fstat(descriptor, &information) != 0
      || !S_ISREG(information.st_mode)
      || !identity_from_stat(&information, &identity)
      || !identity_matches_lua(L, 2, &identity))
  {
    close(descriptor);
    return push_failure(L, "TargetChanged", "direct read target changed");
  }
  file = push_file(L);
  file->descriptor = descriptor;
  return return_success(L);
}

static int l_fs_create_new_verified(lua_State *L)
{
  const char *path;
  size_t length;
  lua_Integer permissions;
  int parent_descriptor = -1;
  int descriptor;
  char *parent = NULL;
  char *name = NULL;
  const char *code = "Storage";
  const char *message = "direct create failed";
  yaca_file *file;

  if (!checked_byte_string(L, 1, &path, &length, "InvalidPath", "direct create path is invalid"))
  {
    return 2;
  }
  luaL_checktype(L, 2, LUA_TTABLE);
  permissions = luaL_checkinteger(L, 3);
  if (permissions < 0 || permissions > 0777)
  {
    return push_failure(L, "InvalidPermissions", "direct create permissions are invalid");
  }
  (void)length;
  if (!open_posix_parent(
      path, &parent_descriptor, &parent, &name, &code, &message))
  {
    return push_failure(L, code, message);
  }
  if (!descriptor_matches_lua(L, 2, parent_descriptor))
  {
    close(parent_descriptor);
    free(parent);
    free(name);
    return push_failure(L, "TargetChanged", "direct create parent changed");
  }
  descriptor = openat(
    parent_descriptor,
    name,
    O_CREAT | O_EXCL | O_RDWR | O_NOFOLLOW | O_CLOEXEC,
    (mode_t)permissions);
  if (descriptor < 0)
  {
    int error_value = errno;
    close(parent_descriptor);
    free(parent);
    free(name);
    return push_failure(L, errno_code(error_value), "direct create failed");
  }
  close(parent_descriptor);
  free(parent);
  free(name);
  file = push_file(L);
  file->descriptor = descriptor;
  return return_success(L);
}

static int same_posix_object(const struct stat *left, const struct stat *right)
{
  return left->st_dev == right->st_dev
    && left->st_ino == right->st_ino
    && ((left->st_mode & S_IFMT) == (right->st_mode & S_IFMT));
}

static int same_posix_published_facts(
  const struct stat *left,
  const struct stat *right)
{
  return same_posix_object(left, right)
    && left->st_size == right->st_size
    && left->st_nlink == right->st_nlink
    && (left->st_mode & 07777) == (right->st_mode & 07777)
    && left->st_uid == right->st_uid
    && left->st_gid == right->st_gid
    && left->st_mtim.tv_sec == right->st_mtim.tv_sec
    && left->st_mtim.tv_nsec == right->st_mtim.tv_nsec;
}

static int exchange_posix_names(
  int left_parent,
  const char *left_name,
  int right_parent,
  const char *right_name)
{
#if defined(__linux__) && defined(SYS_renameat2) && defined(RENAME_EXCHANGE)
  return (int)syscall(
    SYS_renameat2,
    left_parent,
    left_name,
    right_parent,
    right_name,
    (unsigned int)RENAME_EXCHANGE);
#else
  (void)left_parent;
  (void)left_name;
  (void)right_parent;
  (void)right_name;
  errno = ENOSYS;
  return -1;
#endif
}

static int rename_posix_no_replace(
  int source_parent,
  const char *source_name,
  int target_parent,
  const char *target_name)
{
#if defined(__linux__) && defined(SYS_renameat2) && defined(RENAME_NOREPLACE)
  return (int)syscall(
    SYS_renameat2,
    source_parent,
    source_name,
    target_parent,
    target_name,
    (unsigned int)RENAME_NOREPLACE);
#else
  (void)source_parent;
  (void)source_name;
  (void)target_parent;
  (void)target_name;
  errno = ENOSYS;
  return -1;
#endif
}

static char *posix_delete_recovery_name(const char *name)
{
  static const char suffix[] = ".yaca-delete";
  size_t name_length = strlen(name);
  size_t suffix_length = sizeof(suffix) - 1U;
  char *result;

  if (name_length > SIZE_MAX - suffix_length - 1U)
  {
    errno = ENAMETOOLONG;
    return NULL;
  }
  result = (char *)malloc(name_length + suffix_length + 1U);
  if (result == NULL)
  {
    errno = ENOMEM;
    return NULL;
  }
  memcpy(result, name, name_length);
  memcpy(result + name_length, suffix, suffix_length + 1U);
  return result;
}

static int l_fs_replace_verified(lua_State *L)
{
  const char *temporary_path;
  const char *target_path;
  size_t temporary_length;
  size_t target_length;
  int parent_descriptor = -1;
  int temporary_descriptor = -1;
  int target_descriptor = -1;
  char *temporary_parent = NULL;
  char *temporary_name = NULL;
  char *target_parent = NULL;
  char *target_name = NULL;
  const char *code = "Storage";
  const char *message = "direct replacement failed";
  const char *failure_code = "Storage";
  const char *failure_message = "direct replacement failed";
  const char *expected_behavior;
  size_t expected_behavior_length;
  struct stat temporary_information;
  struct stat temporary_current_information;
  struct stat target_information;
  struct stat target_current_information;
  struct stat published_information;
  struct stat displaced_information;
  yaca_posix_metadata_state target_metadata;
  yaca_posix_metadata_state check_metadata;
  yaca_posix_metadata_state temporary_metadata;
  char behavior[96];
  int displaced_observed = 0;
  int published_observed = 0;
  int result = 0;

#define REPLACE_FAIL(next_code, next_message) do { \
    failure_code = (next_code); \
    failure_message = (next_message); \
    goto cleanup; \
  } while (0)

  memset(&target_metadata, 0, sizeof(target_metadata));
  memset(&check_metadata, 0, sizeof(check_metadata));
  memset(&temporary_metadata, 0, sizeof(temporary_metadata));

  if (!checked_byte_string(
      L, 1, &temporary_path, &temporary_length, "InvalidPath", "direct temporary path is invalid"))
  {
    return 2;
  }
  if (!checked_byte_string(
      L, 2, &target_path, &target_length, "InvalidPath", "direct target path is invalid"))
  {
    return 2;
  }
  luaL_checktype(L, 3, LUA_TTABLE);
  luaL_checktype(L, 4, LUA_TTABLE);
  luaL_checktype(L, 5, LUA_TTABLE);
  if (!checked_byte_string(
      L,
      6,
      &expected_behavior,
      &expected_behavior_length,
      "InvalidMetadata",
      "direct target behavior digest is invalid"))
  {
    return 2;
  }
  if (expected_behavior_length >= sizeof(behavior))
  {
    return push_failure(L, "InvalidMetadata", "direct target behavior digest is invalid");
  }
  (void)temporary_length;
  (void)target_length;
  if (!posix_parent_and_name(
      temporary_path, &temporary_parent, &temporary_name, &code, &message)
      || !posix_parent_and_name(
        target_path, &target_parent, &target_name, &code, &message))
  {
    REPLACE_FAIL(code, message);
  }
  if (strcmp(temporary_parent, target_parent) != 0)
  {
    REPLACE_FAIL(
      "InvalidTargetType",
      "direct replacement must stay in one directory");
  }
  parent_descriptor = open(target_parent, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
  if (parent_descriptor < 0 || !descriptor_matches_lua(L, 5, parent_descriptor))
  {
    REPLACE_FAIL("TargetChanged", "direct replacement parent changed");
  }
  temporary_descriptor = openat(
    parent_descriptor, temporary_name, O_RDWR | O_NOFOLLOW | O_CLOEXEC);
  target_descriptor = openat(
    parent_descriptor, target_name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
  if (temporary_descriptor < 0 || target_descriptor < 0
      || fstat(temporary_descriptor, &temporary_information) != 0
      || fstat(target_descriptor, &target_information) != 0
      || !S_ISREG(temporary_information.st_mode)
      || !S_ISREG(target_information.st_mode)
      || temporary_information.st_nlink != 1
      || target_information.st_nlink != 1)
  {
    REPLACE_FAIL("TargetChanged", "direct replacement entries changed");
  }
  {
    yaca_identity temporary_identity;
    yaca_identity target_identity;
    memset(&temporary_identity, 0, sizeof(temporary_identity));
    memset(&target_identity, 0, sizeof(target_identity));
    if (!identity_from_stat(&temporary_information, &temporary_identity)
        || !identity_from_stat(&target_information, &target_identity)
        || !identity_matches_lua(L, 3, &temporary_identity)
        || !identity_matches_lua(L, 4, &target_identity))
    {
      REPLACE_FAIL("TargetChanged", "direct replacement identity changed");
    }
  }
  if (capture_posix_metadata(
      target_descriptor,
      &target_information,
      &target_metadata) != YACA_METADATA_PROVEN
      || !posix_behavior_digest(&target_metadata, behavior)
      || strlen(behavior) != expected_behavior_length
      || memcmp(behavior, expected_behavior, expected_behavior_length) != 0)
  {
    REPLACE_FAIL(
      "MetadataPreservationUnsupported",
      "direct target behavior metadata is unavailable or stale");
  }
  if ((temporary_information.st_uid != target_information.st_uid
      || temporary_information.st_gid != target_information.st_gid)
      && fchown(
        temporary_descriptor,
        target_information.st_uid,
        target_information.st_gid) != 0)
  {
    REPLACE_FAIL(
      errno_code(errno),
      "direct replacement ownership preservation failed");
  }
  if (fchmod(temporary_descriptor, target_information.st_mode & 07777) != 0)
  {
    REPLACE_FAIL(
      errno_code(errno),
      "direct replacement mode preservation failed");
  }
  if (fstat(target_descriptor, &target_current_information) != 0
      || !same_stat_observation(&target_information, &target_current_information)
      || capture_posix_metadata(
        target_descriptor,
        &target_current_information,
        &check_metadata) != YACA_METADATA_PROVEN
      || !posix_metadata_states_equal(&target_metadata, &check_metadata))
  {
    REPLACE_FAIL("TargetChanged", "direct replacement target metadata changed");
  }
  free_posix_metadata_state(&check_metadata);
  if (fstat(temporary_descriptor, &temporary_current_information) != 0
      || capture_posix_metadata(
        temporary_descriptor,
        &temporary_current_information,
        &temporary_metadata) != YACA_METADATA_PROVEN
      || temporary_metadata.filesystem_flags
        != target_metadata.filesystem_flags)
  {
    REPLACE_FAIL(
      "MetadataPreservationUnsupported",
      "direct replacement cannot preserve filesystem attributes");
  }
#if defined(__linux__)
  if (!synchronize_descriptor_xattrs(
      temporary_descriptor,
      &temporary_metadata.xattrs,
      &target_metadata.xattrs))
  {
    REPLACE_FAIL(
      errno_code(errno),
      "direct replacement xattr preservation failed");
  }
#else
  REPLACE_FAIL(
    "MetadataPreservationUnsupported",
    "direct replacement xattr preservation is unavailable");
#endif
  free_posix_metadata_state(&temporary_metadata);
  if (fsync(temporary_descriptor) != 0)
  {
    REPLACE_FAIL(errno_code(errno), "direct replacement metadata flush failed");
  }
  if (fstat(target_descriptor, &target_current_information) != 0
      || !same_stat_observation(&target_information, &target_current_information)
      || capture_posix_metadata(
        target_descriptor,
        &target_current_information,
        &check_metadata) != YACA_METADATA_PROVEN
      || !posix_metadata_states_equal(&target_metadata, &check_metadata))
  {
    REPLACE_FAIL("TargetChanged", "direct replacement target changed before publication");
  }
  free_posix_metadata_state(&check_metadata);
  if (fstat(temporary_descriptor, &temporary_current_information) != 0
      || capture_posix_metadata(
        temporary_descriptor,
        &temporary_current_information,
        &temporary_metadata) != YACA_METADATA_PROVEN
      || !posix_metadata_states_equal(&target_metadata, &temporary_metadata)
      || !posix_behavior_digest(&temporary_metadata, behavior)
      || strlen(behavior) != expected_behavior_length
      || memcmp(behavior, expected_behavior, expected_behavior_length) != 0)
  {
    REPLACE_FAIL(
      "MetadataPreservationUnsupported",
      "direct replacement metadata verification failed");
  }
  free_posix_metadata_state(&temporary_metadata);
  if (exchange_posix_names(
      parent_descriptor,
      temporary_name,
      parent_descriptor,
      target_name) != 0)
  {
    REPLACE_FAIL(
      (errno == ENOSYS || errno == EINVAL) ? "Unsupported" : errno_code(errno),
      "direct atomic replacement exchange failed");
  }
  displaced_observed = fstatat(
      parent_descriptor,
      temporary_name,
      &displaced_information,
      AT_SYMLINK_NOFOLLOW) == 0;
  published_observed = fstatat(
        parent_descriptor,
        target_name,
        &published_information,
        AT_SYMLINK_NOFOLLOW) == 0;
  if (!displaced_observed
      || !published_observed
      || !same_posix_published_facts(
        &temporary_current_information,
        &published_information)
      || !same_posix_published_facts(
        &target_information,
        &displaced_information))
  {
    struct stat rollback_temporary;
    struct stat rollback_target;
    if (displaced_observed
        && published_observed
        && same_posix_object(&temporary_information, &published_information)
        && exchange_posix_names(
          parent_descriptor,
          temporary_name,
          parent_descriptor,
          target_name) == 0
        && fstatat(
          parent_descriptor,
          temporary_name,
          &rollback_temporary,
          AT_SYMLINK_NOFOLLOW) == 0
        && fstatat(
          parent_descriptor,
          target_name,
          &rollback_target,
          AT_SYMLINK_NOFOLLOW) == 0
        && same_posix_object(&temporary_information, &rollback_temporary)
        && same_posix_object(&displaced_information, &rollback_target))
    {
      REPLACE_FAIL("TargetChanged", "direct replacement target raced publication");
    }
    REPLACE_FAIL("Unknown", "direct replacement race recovery is unknown");
  }
  if (fstat(temporary_descriptor, &temporary_current_information) != 0
      || !same_stat_observation(
        &published_information,
        &temporary_current_information)
      || fstat(target_descriptor, &target_current_information) != 0
      || !same_stat_observation(
        &displaced_information,
        &target_current_information))
  {
    REPLACE_FAIL("Unknown", "direct replacement handle postcondition is unknown");
  }
  if (unlinkat(parent_descriptor, temporary_name, 0) != 0)
  {
    REPLACE_FAIL("Unknown", "direct replacement cleanup is unknown");
  }
  result = 1;

cleanup:
  free_posix_metadata_state(&target_metadata);
  free_posix_metadata_state(&check_metadata);
  free_posix_metadata_state(&temporary_metadata);
  if (temporary_descriptor >= 0) close(temporary_descriptor);
  if (target_descriptor >= 0) close(target_descriptor);
  if (parent_descriptor >= 0) close(parent_descriptor);
  free(temporary_parent);
  free(temporary_name);
  free(target_parent);
  free(target_name);
#undef REPLACE_FAIL
  return result
    ? push_true_result(L)
    : push_failure(L, failure_code, failure_message);
}

static int l_fs_rename_no_replace_verified(lua_State *L)
{
  const char *source_path;
  const char *target_path;
  size_t source_length;
  size_t target_length;
  int source_parent_descriptor = -1;
  int target_parent_descriptor = -1;
  char *source_parent = NULL;
  char *source_name = NULL;
  char *target_parent = NULL;
  char *target_name = NULL;
  const char *code = "Storage";
  const char *message = "direct rename failed";
  const char *failure_code = "Storage";
  const char *failure_message = "direct rename failed";
  struct stat source_information;
  struct stat target_information;
  struct stat moved_information;
  struct stat source_after_information;
  int error_value;
  int target_observed;
  int source_absent;
  int result = 0;

#define RENAME_FAIL(next_code, next_message) do { \
    failure_code = (next_code); \
    failure_message = (next_message); \
    goto cleanup; \
  } while (0)

  if (!checked_byte_string(
      L, 1, &source_path, &source_length, "InvalidPath", "direct source path is invalid"))
  {
    return 2;
  }
  if (!checked_byte_string(
      L, 2, &target_path, &target_length, "InvalidPath", "direct target path is invalid"))
  {
    return 2;
  }
  luaL_checktype(L, 3, LUA_TTABLE);
  luaL_checktype(L, 4, LUA_TTABLE);
  luaL_checktype(L, 5, LUA_TTABLE);
  (void)source_length;
  (void)target_length;
  if (!posix_parent_and_name(
      source_path, &source_parent, &source_name, &code, &message)
      || !posix_parent_and_name(
        target_path, &target_parent, &target_name, &code, &message))
  {
    RENAME_FAIL(code, message);
  }
  source_parent_descriptor = open(source_parent, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
  target_parent_descriptor = open(target_parent, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
  if (source_parent_descriptor < 0 || target_parent_descriptor < 0
      || !descriptor_matches_lua(L, 4, source_parent_descriptor)
      || !descriptor_matches_lua(L, 5, target_parent_descriptor)
      || !stat_at_matches_lua(
        L, 3, source_parent_descriptor, source_name, &source_information))
  {
    RENAME_FAIL("TargetChanged", "direct rename binding changed");
  }
  if (fstatat(
      target_parent_descriptor,
      target_name,
      &target_information,
      AT_SYMLINK_NOFOLLOW) == 0)
  {
    RENAME_FAIL("DestinationExists", "direct rename target exists");
  }
  error_value = errno;
  if (error_value != ENOENT)
  {
    RENAME_FAIL(
      errno_code(error_value),
      "direct rename target inspection failed");
  }
  if ((!S_ISREG(source_information.st_mode)
      && !S_ISDIR(source_information.st_mode))
      || (S_ISREG(source_information.st_mode)
        && source_information.st_nlink != 1))
  {
    RENAME_FAIL(
      "InvalidTargetType",
      "direct rename source type or link count is unsupported");
  }
  if (rename_posix_no_replace(
      source_parent_descriptor,
      source_name,
      target_parent_descriptor,
      target_name) != 0)
  {
    error_value = errno;
    RENAME_FAIL(
      (error_value == ENOSYS || error_value == EINVAL)
        ? "Unsupported"
        : errno_code(error_value),
      "direct atomic no-replace rename failed");
  }
  target_observed = fstatat(
    target_parent_descriptor,
    target_name,
    &moved_information,
    AT_SYMLINK_NOFOLLOW) == 0;
  source_absent = fstatat(
    source_parent_descriptor,
    source_name,
    &source_after_information,
    AT_SYMLINK_NOFOLLOW) != 0
    && errno == ENOENT;
  if (target_observed
      && source_absent
      && same_posix_published_facts(
        &source_information,
        &moved_information))
  {
    result = 1;
    goto cleanup;
  }
  if (target_observed && source_absent)
  {
    struct stat rollback_source;
    struct stat rollback_target;
    if (rename_posix_no_replace(
        target_parent_descriptor,
        target_name,
        source_parent_descriptor,
        source_name) == 0
        && fstatat(
          source_parent_descriptor,
          source_name,
          &rollback_source,
          AT_SYMLINK_NOFOLLOW) == 0
        && same_posix_object(&moved_information, &rollback_source)
        && fstatat(
          target_parent_descriptor,
          target_name,
          &rollback_target,
          AT_SYMLINK_NOFOLLOW) != 0
        && errno == ENOENT)
    {
      RENAME_FAIL("TargetChanged", "direct rename source raced publication");
    }
  }
  RENAME_FAIL("Unknown", "direct rename postcondition is unknown");

cleanup:
  if (source_parent_descriptor >= 0) close(source_parent_descriptor);
  if (target_parent_descriptor >= 0) close(target_parent_descriptor);
  free(source_parent);
  free(source_name);
  free(target_parent);
  free(target_name);
#undef RENAME_FAIL
  return result
    ? push_true_result(L)
    : push_failure(L, failure_code, failure_message);
}

static int l_fs_delete_direct_verified(lua_State *L)
{
  const char *path;
  size_t length;
  int parent_descriptor = -1;
  int target_descriptor = -1;
  char *parent = NULL;
  char *name = NULL;
  char *recovery_name = NULL;
  const char *code = "Storage";
  const char *message = "direct delete failed";
  const char *failure_code = "Storage";
  const char *failure_message = "direct delete failed";
  struct stat information;
  struct stat opened_information;
  struct stat moved_information;
  struct stat source_after_information;
  struct stat recovery_after_information;
  struct stat handle_after_information;
  int flags;
  int error_value;
  int moved_observed;
  int source_absent;
  int result = 0;

#define DELETE_FAIL(next_code, next_message) do { \
    failure_code = (next_code); \
    failure_message = (next_message); \
    goto cleanup; \
  } while (0)

  if (!checked_byte_string(L, 1, &path, &length, "InvalidPath", "direct delete path is invalid"))
  {
    return 2;
  }
  luaL_checktype(L, 2, LUA_TTABLE);
  luaL_checktype(L, 3, LUA_TTABLE);
  (void)length;
  if (!open_posix_parent(path, &parent_descriptor, &parent, &name, &code, &message))
  {
    return push_failure(L, code, message);
  }
  if (!descriptor_matches_lua(L, 3, parent_descriptor)
      || !stat_at_matches_lua(L, 2, parent_descriptor, name, &information))
  {
    DELETE_FAIL("TargetChanged", "direct delete binding changed");
  }
  if (S_ISREG(information.st_mode))
  {
    flags = 0;
    if (information.st_nlink != 1)
    {
      DELETE_FAIL("TargetChanged", "direct delete target became hardlinked");
    }
  }
  else if (S_ISDIR(information.st_mode))
  {
    flags = AT_REMOVEDIR;
  }
  else
  {
    DELETE_FAIL("InvalidTargetType", "direct delete target type is unsupported");
  }
#if defined(__linux__) && defined(O_PATH)
  target_descriptor = openat(
    parent_descriptor,
    name,
    O_PATH | O_NOFOLLOW | O_CLOEXEC);
#else
  target_descriptor = openat(
    parent_descriptor,
    name,
    O_RDONLY | O_NOFOLLOW | O_CLOEXEC
      | (S_ISDIR(information.st_mode) ? O_DIRECTORY : 0));
#endif
  if (target_descriptor < 0
      || fstat(target_descriptor, &opened_information) != 0
      || !same_stat_observation(&information, &opened_information))
  {
    DELETE_FAIL("TargetChanged", "direct delete target changed before isolation");
  }
  recovery_name = posix_delete_recovery_name(name);
  if (recovery_name == NULL)
  {
    DELETE_FAIL(errno_code(errno), "direct delete recovery name allocation failed");
  }
  if (fstatat(
      parent_descriptor,
      recovery_name,
      &recovery_after_information,
      AT_SYMLINK_NOFOLLOW) == 0)
  {
    DELETE_FAIL("TemporaryConflict", "direct delete recovery name is occupied");
  }
  error_value = errno;
  if (error_value != ENOENT)
  {
    DELETE_FAIL(
      errno_code(error_value),
      "direct delete recovery name cannot be inspected");
  }
  if (rename_posix_no_replace(
      parent_descriptor,
      name,
      parent_descriptor,
      recovery_name) != 0)
  {
    error_value = errno;
    DELETE_FAIL(
      (error_value == ENOSYS || error_value == EINVAL)
        ? "Unsupported"
        : errno_code(error_value),
      "direct delete isolation failed");
  }
  moved_observed = fstatat(
    parent_descriptor,
    recovery_name,
    &moved_information,
    AT_SYMLINK_NOFOLLOW) == 0;
  source_absent = fstatat(
    parent_descriptor,
    name,
    &source_after_information,
    AT_SYMLINK_NOFOLLOW) != 0
    && errno == ENOENT;
  if (!moved_observed
      || !source_absent
      || fstat(target_descriptor, &handle_after_information) != 0
      || !same_posix_published_facts(&information, &moved_information)
      || !same_posix_published_facts(
        &moved_information,
        &handle_after_information))
  {
    struct stat rollback_source;
    struct stat rollback_recovery;
    if (moved_observed
        && source_absent
        && rename_posix_no_replace(
          parent_descriptor,
          recovery_name,
          parent_descriptor,
          name) == 0
        && fstatat(
          parent_descriptor,
          name,
          &rollback_source,
          AT_SYMLINK_NOFOLLOW) == 0
        && same_posix_object(&moved_information, &rollback_source)
        && fstatat(
          parent_descriptor,
          recovery_name,
          &rollback_recovery,
          AT_SYMLINK_NOFOLLOW) != 0
        && errno == ENOENT
        && fsync(parent_descriptor) == 0)
    {
      DELETE_FAIL("TargetChanged", "direct delete target raced isolation");
    }
    DELETE_FAIL("Unknown", "direct delete isolation recovery is unknown");
  }
  if (unlinkat(parent_descriptor, recovery_name, flags) != 0)
  {
    struct stat rollback_source;
    struct stat rollback_recovery;
    error_value = errno;
    if (rename_posix_no_replace(
        parent_descriptor,
        recovery_name,
        parent_descriptor,
        name) == 0
        && fstatat(
          parent_descriptor,
          name,
          &rollback_source,
          AT_SYMLINK_NOFOLLOW) == 0
        && same_posix_published_facts(&moved_information, &rollback_source)
        && fstatat(
          parent_descriptor,
          recovery_name,
          &rollback_recovery,
          AT_SYMLINK_NOFOLLOW) != 0
        && errno == ENOENT
        && fsync(parent_descriptor) == 0)
    {
      DELETE_FAIL(
        errno_code(error_value),
        "direct delete failed without publication");
    }
    DELETE_FAIL("Unknown", "direct delete rollback is unknown");
  }
  source_absent = fstatat(
    parent_descriptor,
    name,
    &source_after_information,
    AT_SYMLINK_NOFOLLOW) != 0
    && errno == ENOENT;
  if (!source_absent
      || fstatat(
        parent_descriptor,
        recovery_name,
        &recovery_after_information,
        AT_SYMLINK_NOFOLLOW) == 0
      || errno != ENOENT
      || fstat(target_descriptor, &handle_after_information) != 0
      || !same_posix_object(&information, &handle_after_information)
      || handle_after_information.st_nlink != 0)
  {
    DELETE_FAIL("Unknown", "direct delete postcondition is unknown");
  }
  result = 1;

cleanup:
  if (target_descriptor >= 0) close(target_descriptor);
  if (parent_descriptor >= 0) close(parent_descriptor);
  free(parent);
  free(name);
  free(recovery_name);
#undef DELETE_FAIL
  return result
    ? push_true_result(L)
    : push_failure(L, failure_code, failure_message);
}

#endif

static lua_Integer native_monotonic_milliseconds(void)
{
#if defined(_WIN32)
  LARGE_INTEGER counter;
  LARGE_INTEGER frequency;
  unsigned long long seconds;
  unsigned long long remainder;
  unsigned long long milliseconds;

  if (!QueryPerformanceFrequency(&frequency)
      || frequency.QuadPart <= 0
      || !QueryPerformanceCounter(&counter)
      || counter.QuadPart < 0)
  {
    return -1;
  }
  seconds = (unsigned long long)counter.QuadPart
    / (unsigned long long)frequency.QuadPart;
  remainder = (unsigned long long)counter.QuadPart
    % (unsigned long long)frequency.QuadPart;
  if (seconds > (unsigned long long)LUA_MAXINTEGER / 1000ULL)
  {
    return -1;
  }
  milliseconds = seconds * 1000ULL
    + (remainder * 1000ULL) / (unsigned long long)frequency.QuadPart;
  if (milliseconds > (unsigned long long)LUA_MAXINTEGER)
  {
    return -1;
  }
  return (lua_Integer)milliseconds;
#else
  struct timespec value;
  unsigned long long seconds;
  unsigned long long milliseconds;

  if (clock_gettime(CLOCK_MONOTONIC, &value) != 0 || value.tv_sec < 0)
  {
    return -1;
  }
  seconds = (unsigned long long)value.tv_sec;
  if (seconds > (unsigned long long)LUA_MAXINTEGER / 1000ULL)
  {
    return -1;
  }
  milliseconds = seconds * 1000ULL
    + (unsigned long long)value.tv_nsec / 1000000ULL;
  return (lua_Integer)milliseconds;
#endif
}

static yaca_process *check_process(lua_State *L, int index)
{
  yaca_process *process;

  process = (yaca_process *)luaL_checkudata(L, index, YACA_PROCESS_METATABLE);
  if (process->closed)
  {
    luaL_error(L, "native process handle is closed");
  }
  return process;
}

static void close_process_streams(yaca_process *process)
{
#if defined(_WIN32)
  if (process->stdout_read != NULL && process->stdout_read != INVALID_HANDLE_VALUE)
  {
    CloseHandle(process->stdout_read);
    process->stdout_read = INVALID_HANDLE_VALUE;
  }
  if (process->stderr_read != NULL && process->stderr_read != INVALID_HANDLE_VALUE)
  {
    CloseHandle(process->stderr_read);
    process->stderr_read = INVALID_HANDLE_VALUE;
  }
#else
  if (process->stdout_read >= 0)
  {
    close(process->stdout_read);
    process->stdout_read = -1;
  }
  if (process->stderr_read >= 0)
  {
    close(process->stderr_read);
    process->stderr_read = -1;
  }
#endif
}

static void close_process_handles(yaca_process *process)
{
  close_process_streams(process);
#if defined(_WIN32)
  if (process->process != NULL && process->process != INVALID_HANDLE_VALUE)
  {
    CloseHandle(process->process);
    process->process = INVALID_HANDLE_VALUE;
  }
  if (process->job != NULL && process->job != INVALID_HANDLE_VALUE)
  {
    CloseHandle(process->job);
    process->job = INVALID_HANDLE_VALUE;
  }
#endif
  process->closed = 1;
}

static int l_process_gc(lua_State *L)
{
  yaca_process *process;

  process = (yaca_process *)luaL_testudata(L, 1, YACA_PROCESS_METATABLE);
  if (process == NULL || process->closed)
  {
    return 0;
  }
  if (!process->reaped)
  {
#if defined(_WIN32)
    if (process->job != NULL && process->job != INVALID_HANDLE_VALUE)
    {
      TerminateJobObject(process->job, 0xE0000001UL);
    }
#else
    if (process->process_id > 0)
    {
      kill(-process->process_id, SIGKILL);
      waitpid(process->process_id, NULL, WNOHANG);
    }
#endif
  }
  close_process_handles(process);
  return 0;
}

static yaca_process *push_process(lua_State *L)
{
  yaca_process *process;

  process = (yaca_process *)lua_newuserdatauv(L, sizeof(yaca_process), 0);
  memset(process, 0, sizeof(*process));
#if defined(_WIN32)
  process->process = INVALID_HANDLE_VALUE;
  process->job = INVALID_HANDLE_VALUE;
  process->stdout_read = INVALID_HANDLE_VALUE;
  process->stderr_read = INVALID_HANDLE_VALUE;
#else
  process->process_id = -1;
  process->stdout_read = -1;
  process->stderr_read = -1;
#endif
  luaL_setmetatable(L, YACA_PROCESS_METATABLE);
  return process;
}

static int request_string_field(
  lua_State *L,
  int index,
  const char *field,
  const char **value,
  size_t *length,
  int optional)
{
  int absolute_index;

  absolute_index = lua_absindex(L, index);
  lua_getfield(L, absolute_index, field);
  if (optional && lua_isnil(L, -1))
  {
    *value = NULL;
    *length = 0;
    lua_pop(L, 1);
    return 1;
  }
  if (!lua_isstring(L, -1))
  {
    lua_pop(L, 1);
    return 0;
  }
  *value = lua_tolstring(L, -1, length);
  if (*length == 0 || memchr(*value, '\0', *length) != NULL)
  {
    lua_pop(L, 1);
    return 0;
  }
  lua_pop(L, 1);
  return 1;
}

#if defined(_WIN32)

typedef struct yaca_wide_environment
{
  WCHAR **items;
  size_t count;
  WCHAR *block;
} yaca_wide_environment;

static int compare_wide_environment(const void *left, const void *right)
{
  const WCHAR *left_value;
  const WCHAR *right_value;

  left_value = *(const WCHAR * const *)left;
  right_value = *(const WCHAR * const *)right;
  return _wcsicmp(left_value, right_value);
}

static void free_wide_environment(yaca_wide_environment *environment)
{
  size_t index;

  if (environment->items != NULL)
  {
    for (index = 0; index < environment->count; index++)
    {
      free(environment->items[index]);
    }
  }
  free(environment->items);
  free(environment->block);
  memset(environment, 0, sizeof(*environment));
}

static int build_wide_environment(
  lua_State *L,
  int request_index,
  yaca_wide_environment *environment)
{
  int request_absolute;
  int table_index;
  size_t capacity;
  size_t total;
  size_t index;
  WCHAR *cursor;

  memset(environment, 0, sizeof(*environment));
  request_absolute = lua_absindex(L, request_index);
  lua_getfield(L, request_absolute, "environment");
  if (!lua_istable(L, -1))
  {
    lua_pop(L, 1);
    return 0;
  }
  table_index = lua_gettop(L);
  capacity = 8;
  environment->items = (WCHAR **)calloc(capacity, sizeof(WCHAR *));
  if (environment->items == NULL)
  {
    lua_pop(L, 1);
    return 0;
  }
  lua_pushnil(L);
  while (lua_next(L, table_index) != 0)
  {
    const char *name;
    const char *value;
    size_t name_length;
    size_t value_length;
    char *entry;
    WCHAR *wide_entry;

    if (!lua_isstring(L, -2) || !lua_isstring(L, -1))
    {
      lua_pop(L, 2);
      lua_pop(L, 1);
      free_wide_environment(environment);
      return 0;
    }
    name = lua_tolstring(L, -2, &name_length);
    value = lua_tolstring(L, -1, &value_length);
    if (name_length == 0
        || memchr(name, '\0', name_length) != NULL
        || memchr(name, '=', name_length) != NULL
        || memchr(value, '\0', value_length) != NULL
        || name_length > SIZE_MAX - value_length - 2U)
    {
      lua_pop(L, 2);
      lua_pop(L, 1);
      free_wide_environment(environment);
      return 0;
    }
    entry = (char *)malloc(name_length + value_length + 2U);
    if (entry == NULL)
    {
      lua_pop(L, 2);
      lua_pop(L, 1);
      free_wide_environment(environment);
      return 0;
    }
    memcpy(entry, name, name_length);
    entry[name_length] = '=';
    memcpy(entry + name_length + 1U, value, value_length);
    entry[name_length + value_length + 1U] = '\0';
    wide_entry = utf8_to_wide(entry, name_length + value_length + 1U);
    free(entry);
    if (wide_entry == NULL)
    {
      lua_pop(L, 2);
      lua_pop(L, 1);
      free_wide_environment(environment);
      return 0;
    }
    if (environment->count == capacity)
    {
      WCHAR **expanded;

      if (capacity > SIZE_MAX / 2U / sizeof(WCHAR *))
      {
        free(wide_entry);
        lua_pop(L, 2);
        lua_pop(L, 1);
        free_wide_environment(environment);
        return 0;
      }
      capacity *= 2U;
      expanded = (WCHAR **)realloc(
        environment->items,
        capacity * sizeof(WCHAR *));
      if (expanded == NULL)
      {
        free(wide_entry);
        lua_pop(L, 2);
        lua_pop(L, 1);
        free_wide_environment(environment);
        return 0;
      }
      environment->items = expanded;
    }
    environment->items[environment->count++] = wide_entry;
    lua_pop(L, 1);
  }
  lua_pop(L, 1);
  qsort(
    environment->items,
    environment->count,
    sizeof(WCHAR *),
    compare_wide_environment);
  total = environment->count == 0 ? 2U : 1U;
  for (index = 0; index < environment->count; index++)
  {
    size_t item_length;

    item_length = wcslen(environment->items[index]) + 1U;
    if (total > SIZE_MAX - item_length)
    {
      free_wide_environment(environment);
      return 0;
    }
    total += item_length;
  }
  environment->block = (WCHAR *)calloc(total, sizeof(WCHAR));
  if (environment->block == NULL)
  {
    free_wide_environment(environment);
    return 0;
  }
  cursor = environment->block;
  for (index = 0; index < environment->count; index++)
  {
    size_t item_length;

    item_length = wcslen(environment->items[index]) + 1U;
    memcpy(cursor, environment->items[index], item_length * sizeof(WCHAR));
    cursor += item_length;
  }
  *cursor = L'\0';
  return 1;
}

static int windows_job_is_empty(HANDLE job)
{
  JOBOBJECT_BASIC_ACCOUNTING_INFORMATION information;

  memset(&information, 0, sizeof(information));
  if (!QueryInformationJobObject(
      job,
      JobObjectBasicAccountingInformation,
      &information,
      sizeof(information),
      NULL))
  {
    return 0;
  }
  return information.ActiveProcesses == 0;
}

static void refresh_windows_process(yaca_process *process)
{
  DWORD wait_result;

  if (!process->reaped)
  {
    wait_result = WaitForSingleObject(process->process, 0);
    if (wait_result != WAIT_OBJECT_0)
    {
      return;
    }
    process->reaped = 1;
    if (!GetExitCodeProcess(process->process, &process->exit_code))
    {
      process->exit_code = 0xFFFFFFFFUL;
    }
  }
  if (process->outcome[0] != '\0')
  {
    return;
  }
  process->descendants_proven_stopped = windows_job_is_empty(process->job);
  if (!process->descendants_proven_stopped)
  {
    return;
  }
  process->finished_at = native_monotonic_milliseconds();
  if (process->cancel_requested)
  {
    if (process->exit_code == 0xE0000004UL)
    {
      strcpy(process->outcome, "cancelled");
      strcpy(process->exit_kind, "cancelled");
    }
    else
    {
      strcpy(process->outcome, "unknown");
      strcpy(process->exit_kind, "outcome-unknown");
    }
  }
  else if (process->exit_code == 0)
  {
    strcpy(process->outcome, "completed");
    strcpy(process->exit_kind, "exit-code");
  }
  else
  {
    strcpy(process->outcome, "failed");
    strcpy(process->exit_kind, "exit-code");
  }
}

static int read_windows_process_stream(
  lua_State *L,
  HANDLE *stream,
  const char *kind,
  size_t maximum)
{
  DWORD available;
  DWORD count;
  DWORD requested;
  char *buffer;

  if (*stream == INVALID_HANDLE_VALUE)
  {
    return 0;
  }
  available = 0;
  if (!PeekNamedPipe(*stream, NULL, 0, NULL, &available, NULL))
  {
    DWORD value;

    value = GetLastError();
    if (value == ERROR_BROKEN_PIPE)
    {
      CloseHandle(*stream);
      *stream = INVALID_HANDLE_VALUE;
      return 0;
    }
    return -1;
  }
  if (available == 0)
  {
    return 0;
  }
  requested = available;
  if ((size_t)requested > maximum)
  {
    requested = (DWORD)maximum;
  }
  if (requested > 0x7fffffffUL)
  {
    requested = 0x7fffffffUL;
  }
  buffer = (char *)malloc((size_t)requested);
  if (buffer == NULL)
  {
    SetLastError(ERROR_NOT_ENOUGH_MEMORY);
    return -1;
  }
  if (!ReadFile(*stream, buffer, requested, &count, NULL))
  {
    DWORD value;

    value = GetLastError();
    free(buffer);
    if (value == ERROR_BROKEN_PIPE)
    {
      CloseHandle(*stream);
      *stream = INVALID_HANDLE_VALUE;
      return 0;
    }
    SetLastError(value);
    return -1;
  }
  lua_createtable(L, 0, 2);
  lua_pushstring(L, kind);
  lua_setfield(L, -2, "kind");
  lua_pushlstring(L, buffer, (size_t)count);
  lua_setfield(L, -2, "bytes");
  free(buffer);
  return 1;
}

#else

typedef struct yaca_posix_environment
{
  char **items;
  size_t count;
} yaca_posix_environment;

static void free_posix_environment(yaca_posix_environment *environment)
{
  size_t index;

  if (environment->items != NULL)
  {
    for (index = 0; index < environment->count; index++)
    {
      free(environment->items[index]);
    }
  }
  free(environment->items);
  memset(environment, 0, sizeof(*environment));
}

static int build_posix_environment(
  lua_State *L,
  int request_index,
  yaca_posix_environment *environment)
{
  int request_absolute;
  int table_index;
  size_t capacity;

  memset(environment, 0, sizeof(*environment));
  request_absolute = lua_absindex(L, request_index);
  lua_getfield(L, request_absolute, "environment");
  if (!lua_istable(L, -1))
  {
    lua_pop(L, 1);
    return 0;
  }
  table_index = lua_gettop(L);
  capacity = 8;
  environment->items = (char **)calloc(capacity + 1U, sizeof(char *));
  if (environment->items == NULL)
  {
    lua_pop(L, 1);
    return 0;
  }
  lua_pushnil(L);
  while (lua_next(L, table_index) != 0)
  {
    const char *name;
    const char *value;
    size_t name_length;
    size_t value_length;
    char *entry;

    if (!lua_isstring(L, -2) || !lua_isstring(L, -1))
    {
      lua_pop(L, 2);
      lua_pop(L, 1);
      free_posix_environment(environment);
      return 0;
    }
    name = lua_tolstring(L, -2, &name_length);
    value = lua_tolstring(L, -1, &value_length);
    if (name_length == 0
        || memchr(name, '\0', name_length) != NULL
        || memchr(name, '=', name_length) != NULL
        || memchr(value, '\0', value_length) != NULL
        || name_length > SIZE_MAX - value_length - 2U)
    {
      lua_pop(L, 2);
      lua_pop(L, 1);
      free_posix_environment(environment);
      return 0;
    }
    if (environment->count == capacity)
    {
      char **expanded;

      if (capacity > SIZE_MAX / 2U / sizeof(char *))
      {
        lua_pop(L, 2);
        lua_pop(L, 1);
        free_posix_environment(environment);
        return 0;
      }
      capacity *= 2U;
      expanded = (char **)realloc(
        environment->items,
        (capacity + 1U) * sizeof(char *));
      if (expanded == NULL)
      {
        lua_pop(L, 2);
        lua_pop(L, 1);
        free_posix_environment(environment);
        return 0;
      }
      environment->items = expanded;
    }
    entry = (char *)malloc(name_length + value_length + 2U);
    if (entry == NULL)
    {
      lua_pop(L, 2);
      lua_pop(L, 1);
      free_posix_environment(environment);
      return 0;
    }
    memcpy(entry, name, name_length);
    entry[name_length] = '=';
    memcpy(entry + name_length + 1U, value, value_length);
    entry[name_length + value_length + 1U] = '\0';
    environment->items[environment->count++] = entry;
    environment->items[environment->count] = NULL;
    lua_pop(L, 1);
  }
  lua_pop(L, 1);
  return 1;
}

static int set_descriptor_flags(int descriptor, int command, int flag)
{
  int current;

  current = fcntl(descriptor, command == F_SETFD ? F_GETFD : F_GETFL);
  if (current < 0)
  {
    return 0;
  }
  return fcntl(descriptor, command, current | flag) == 0;
}

static int posix_process_group_stopped(pid_t process_id)
{
  if (kill(-process_id, 0) == 0)
  {
    return 0;
  }
  return errno == ESRCH;
}

static void refresh_posix_process(yaca_process *process)
{
  pid_t result;

  if (!process->reaped)
  {
    do
    {
      result = waitpid(process->process_id, &process->wait_status, WNOHANG);
    }
    while (result < 0 && errno == EINTR);
    if (result != process->process_id)
    {
      return;
    }
    process->reaped = 1;
  }
  if (process->outcome[0] != '\0')
  {
    return;
  }
  process->descendants_proven_stopped = posix_process_group_stopped(
    process->process_id);
  if (!process->descendants_proven_stopped)
  {
    return;
  }
  process->finished_at = native_monotonic_milliseconds();
  if (process->cancel_requested)
  {
    if (WIFSIGNALED(process->wait_status)
        && WTERMSIG(process->wait_status) == SIGKILL)
    {
      strcpy(process->outcome, "cancelled");
      strcpy(process->exit_kind, "cancelled");
    }
    else
    {
      strcpy(process->outcome, "unknown");
      strcpy(process->exit_kind, "outcome-unknown");
    }
  }
  else if (WIFEXITED(process->wait_status))
  {
    strcpy(
      process->outcome,
      WEXITSTATUS(process->wait_status) == 0 ? "completed" : "failed");
    strcpy(process->exit_kind, "exit-code");
  }
  else if (WIFSIGNALED(process->wait_status))
  {
    strcpy(process->outcome, "failed");
    strcpy(process->exit_kind, "signal");
    snprintf(
      process->signal_or_exception,
      sizeof(process->signal_or_exception),
      "%d",
      WTERMSIG(process->wait_status));
  }
  else
  {
    strcpy(process->outcome, "unknown");
    strcpy(process->exit_kind, "outcome-unknown");
  }
}

static int read_posix_process_stream(
  lua_State *L,
  int *stream,
  const char *kind,
  size_t maximum)
{
  char *buffer;
  ssize_t count;

  if (*stream < 0)
  {
    return 0;
  }
  buffer = (char *)malloc(maximum);
  if (buffer == NULL)
  {
    errno = ENOMEM;
    return -1;
  }
  do
  {
    count = read(*stream, buffer, maximum);
  }
  while (count < 0 && errno == EINTR);
  if (count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK))
  {
    free(buffer);
    return 0;
  }
  if (count < 0)
  {
    free(buffer);
    return -1;
  }
  if (count == 0)
  {
    free(buffer);
    close(*stream);
    *stream = -1;
    return 0;
  }
  lua_createtable(L, 0, 2);
  lua_pushstring(L, kind);
  lua_setfield(L, -2, "kind");
  lua_pushlstring(L, buffer, (size_t)count);
  lua_setfield(L, -2, "bytes");
  free(buffer);
  return 1;
}

#endif

/*
** Starts one fixed system shell with closed stdin and separate output pipes.
*/
static int l_process_start(lua_State *L)
{
  const char *command;
  const char *cwd;
  const char *shell_kind;
  const char *shell_executable;
  size_t command_length;
  size_t cwd_length;
  size_t shell_kind_length;
  size_t shell_executable_length;
  lua_Integer started_at;
  yaca_process *process;

  luaL_checktype(L, 1, LUA_TTABLE);
  if (!request_string_field(
      L,
      1,
      "command",
      &command,
      &command_length,
      0)
      || !request_string_field(L, 1, "cwd", &cwd, &cwd_length, 1))
  {
    return push_failure(L, "InvalidCommand", "process command or cwd is invalid");
  }
  lua_getfield(L, 1, "started_at");
  if (!lua_isinteger(L, -1) || lua_tointeger(L, -1) < 0)
  {
    lua_pop(L, 1);
    return push_failure(L, "InvalidClock", "process start time is invalid");
  }
  started_at = lua_tointeger(L, -1);
  lua_pop(L, 1);
  lua_getfield(L, 1, "shell");
  if (!lua_istable(L, -1)
      || !request_string_field(
        L,
        -1,
        "kind",
        &shell_kind,
        &shell_kind_length,
        0)
      || !request_string_field(
        L,
        -1,
        "executable",
        &shell_executable,
        &shell_executable_length,
        0))
  {
    lua_pop(L, 1);
    return push_failure(L, "InvalidShell", "process shell descriptor is invalid");
  }
  lua_pop(L, 1);

#if defined(_WIN32)
  {
    WCHAR system_directory[MAX_PATH + 1];
    UINT system_length;
    WCHAR *wide_command;
    WCHAR *wide_cwd;
    WCHAR *command_line;
    size_t command_line_length;
    SECURITY_ATTRIBUTES security;
    HANDLE stdout_read;
    HANDLE stdout_write;
    HANDLE stderr_read;
    HANDLE stderr_write;
    HANDLE stdin_null;
    HANDLE job;
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION job_limits;
    STARTUPINFOW startup;
    PROCESS_INFORMATION information;
    yaca_wide_environment environment;
    DWORD creation_flags;
    DWORD error_value;
    int created;

    (void)shell_kind_length;
    (void)shell_executable_length;
    if (strcmp(shell_kind, "windows") != 0
        || strcmp(shell_executable, "native-GetSystemDirectoryW/cmd.exe") != 0)
    {
      return push_failure(L, "InvalidShell", "Windows process shell is not allowlisted");
    }
    system_length = GetSystemDirectoryW(system_directory, MAX_PATH);
    if (system_length == 0 || system_length >= MAX_PATH - 8U)
    {
      return push_windows_failure(L, GetLastError(), "cannot resolve system command shell");
    }
    if (system_directory[system_length - 1U] != YACA_PATH_SEPARATOR)
    {
      system_directory[system_length++] = YACA_PATH_SEPARATOR;
    }
    memcpy(
      system_directory + system_length,
      L"cmd.exe",
      8U * sizeof(WCHAR));
    wide_command = utf8_to_wide(command, command_length);
    wide_cwd = cwd == NULL ? NULL : utf8_to_wide(cwd, cwd_length);
    if (wide_command == NULL || (cwd != NULL && wide_cwd == NULL))
    {
      free(wide_command);
      free(wide_cwd);
      return push_failure(L, "InvalidEncoding", "process command or cwd is not strict UTF-8");
    }
    command_line_length = wcslen(system_directory)
      + wcslen(wide_command)
      + 32U;
    command_line = (WCHAR *)malloc(command_line_length * sizeof(WCHAR));
    if (command_line == NULL)
    {
      free(wide_command);
      free(wide_cwd);
      return push_failure(L, "Limit", "process command line allocation failed");
    }
    if (swprintf(
        command_line,
        command_line_length,
        L"\"%ls\" /d /s /c \"%ls\"",
        system_directory,
        wide_command) < 0)
    {
      free(command_line);
      free(wide_command);
      free(wide_cwd);
      return push_failure(L, "Limit", "process command line is too long");
    }
    free(wide_command);
    if (!build_wide_environment(L, 1, &environment))
    {
      free(command_line);
      free(wide_cwd);
      return push_failure(L, "InvalidEnvironment", "process environment is invalid");
    }
    memset(&security, 0, sizeof(security));
    security.nLength = sizeof(security);
    security.bInheritHandle = TRUE;
    stdout_read = INVALID_HANDLE_VALUE;
    stdout_write = INVALID_HANDLE_VALUE;
    stderr_read = INVALID_HANDLE_VALUE;
    stderr_write = INVALID_HANDLE_VALUE;
    stdin_null = INVALID_HANDLE_VALUE;
    job = INVALID_HANDLE_VALUE;
    memset(&information, 0, sizeof(information));
    created = 0;
    if (!CreatePipe(&stdout_read, &stdout_write, &security, 0)
        || !SetHandleInformation(stdout_read, HANDLE_FLAG_INHERIT, 0)
        || !CreatePipe(&stderr_read, &stderr_write, &security, 0)
        || !SetHandleInformation(stderr_read, HANDLE_FLAG_INHERIT, 0))
    {
      error_value = GetLastError();
      goto windows_start_cleanup;
    }
    stdin_null = CreateFileW(
      L"NUL",
      GENERIC_READ,
      FILE_SHARE_READ | FILE_SHARE_WRITE,
      &security,
      OPEN_EXISTING,
      FILE_ATTRIBUTE_NORMAL,
      NULL);
    if (stdin_null == INVALID_HANDLE_VALUE)
    {
      error_value = GetLastError();
      goto windows_start_cleanup;
    }
    job = CreateJobObjectW(NULL, NULL);
    if (job == NULL)
    {
      error_value = GetLastError();
      job = INVALID_HANDLE_VALUE;
      goto windows_start_cleanup;
    }
    memset(&job_limits, 0, sizeof(job_limits));
    job_limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    if (!SetInformationJobObject(
        job,
        JobObjectExtendedLimitInformation,
        &job_limits,
        sizeof(job_limits)))
    {
      error_value = GetLastError();
      goto windows_start_cleanup;
    }
    memset(&startup, 0, sizeof(startup));
    startup.cb = sizeof(startup);
    startup.dwFlags = STARTF_USESTDHANDLES;
    startup.hStdInput = stdin_null;
    startup.hStdOutput = stdout_write;
    startup.hStdError = stderr_write;
    creation_flags = CREATE_SUSPENDED | CREATE_UNICODE_ENVIRONMENT
      | CREATE_NO_WINDOW;
    if (!CreateProcessW(
        system_directory,
        command_line,
        NULL,
        NULL,
        TRUE,
        creation_flags,
        environment.block,
        wide_cwd,
        &startup,
        &information))
    {
      error_value = GetLastError();
      goto windows_start_cleanup;
    }
    if (!AssignProcessToJobObject(job, information.hProcess))
    {
      error_value = GetLastError();
      TerminateProcess(information.hProcess, 0xE0000002UL);
      WaitForSingleObject(information.hProcess, INFINITE);
      goto windows_start_cleanup;
    }
    if (ResumeThread(information.hThread) == (DWORD)-1)
    {
      error_value = GetLastError();
      TerminateJobObject(job, 0xE0000003UL);
      WaitForSingleObject(information.hProcess, INFINITE);
      goto windows_start_cleanup;
    }
    created = 1;
    error_value = ERROR_SUCCESS;

windows_start_cleanup:
    if (information.hThread != NULL)
    {
      CloseHandle(information.hThread);
    }
    if (stdout_write != INVALID_HANDLE_VALUE)
    {
      CloseHandle(stdout_write);
    }
    if (stderr_write != INVALID_HANDLE_VALUE)
    {
      CloseHandle(stderr_write);
    }
    if (stdin_null != INVALID_HANDLE_VALUE)
    {
      CloseHandle(stdin_null);
    }
    free(command_line);
    free(wide_cwd);
    free_wide_environment(&environment);
    if (!created)
    {
      if (stdout_read != INVALID_HANDLE_VALUE)
      {
        CloseHandle(stdout_read);
      }
      if (stderr_read != INVALID_HANDLE_VALUE)
      {
        CloseHandle(stderr_read);
      }
      if (information.hProcess != NULL)
      {
        CloseHandle(information.hProcess);
      }
      if (job != INVALID_HANDLE_VALUE)
      {
        CloseHandle(job);
      }
      return push_windows_failure(L, error_value, "Windows process start failed");
    }
    process = push_process(L);
    process->process = information.hProcess;
    process->job = job;
    process->stdout_read = stdout_read;
    process->stderr_read = stderr_read;
    process->process_id = information.dwProcessId;
  }
#else
  {
    int stdout_pipe[2];
    int stderr_pipe[2];
    int null_input;
    pid_t child;
    yaca_posix_environment environment;
    char *arguments[4];
    int error_value;

    (void)shell_kind_length;
    (void)shell_executable_length;
    if (strcmp(shell_kind, "linux") != 0 || strcmp(shell_executable, "/bin/sh") != 0)
    {
      return push_failure(L, "InvalidShell", "Linux process shell is not allowlisted");
    }
    if (!build_posix_environment(L, 1, &environment))
    {
      return push_failure(L, "InvalidEnvironment", "process environment is invalid");
    }
    stdout_pipe[0] = stdout_pipe[1] = -1;
    stderr_pipe[0] = stderr_pipe[1] = -1;
    null_input = -1;
    if (pipe(stdout_pipe) != 0 || pipe(stderr_pipe) != 0)
    {
      error_value = errno;
      goto posix_start_failure;
    }
    if (!set_descriptor_flags(stdout_pipe[0], F_SETFD, FD_CLOEXEC)
        || !set_descriptor_flags(stdout_pipe[1], F_SETFD, FD_CLOEXEC)
        || !set_descriptor_flags(stderr_pipe[0], F_SETFD, FD_CLOEXEC)
        || !set_descriptor_flags(stderr_pipe[1], F_SETFD, FD_CLOEXEC))
    {
      error_value = errno;
      goto posix_start_failure;
    }
    null_input = open("/dev/null", O_RDONLY);
    if (null_input < 0)
    {
      error_value = errno;
      goto posix_start_failure;
    }
    arguments[0] = (char *)"/bin/sh";
    arguments[1] = (char *)"-c";
    arguments[2] = (char *)command;
    arguments[3] = NULL;
    child = fork();
    if (child < 0)
    {
      error_value = errno;
      goto posix_start_failure;
    }
    if (child == 0)
    {
      if (setpgid(0, 0) != 0
          || (cwd != NULL && chdir(cwd) != 0)
          || dup2(null_input, STDIN_FILENO) < 0
          || dup2(stdout_pipe[1], STDOUT_FILENO) < 0
          || dup2(stderr_pipe[1], STDERR_FILENO) < 0)
      {
        _exit(126);
      }
      close(stdout_pipe[0]);
      close(stdout_pipe[1]);
      close(stderr_pipe[0]);
      close(stderr_pipe[1]);
      close(null_input);
      execve("/bin/sh", arguments, environment.items);
      _exit(127);
    }
    close(stdout_pipe[1]);
    stdout_pipe[1] = -1;
    close(stderr_pipe[1]);
    stderr_pipe[1] = -1;
    close(null_input);
    null_input = -1;
    if (!set_descriptor_flags(stdout_pipe[0], F_SETFL, O_NONBLOCK)
        || !set_descriptor_flags(stderr_pipe[0], F_SETFL, O_NONBLOCK))
    {
      error_value = errno;
      kill(-child, SIGKILL);
      kill(child, SIGKILL);
      waitpid(child, NULL, 0);
      goto posix_start_failure;
    }
    setpgid(child, child);
    free_posix_environment(&environment);
    process = push_process(L);
    process->process_id = child;
    process->stdout_read = stdout_pipe[0];
    process->stderr_read = stderr_pipe[0];
    stdout_pipe[0] = -1;
    stderr_pipe[0] = -1;
    goto posix_start_success;

posix_start_failure:
    if (stdout_pipe[0] >= 0)
    {
      close(stdout_pipe[0]);
    }
    if (stdout_pipe[1] >= 0)
    {
      close(stdout_pipe[1]);
    }
    if (stderr_pipe[0] >= 0)
    {
      close(stderr_pipe[0]);
    }
    if (stderr_pipe[1] >= 0)
    {
      close(stderr_pipe[1]);
    }
    if (null_input >= 0)
    {
      close(null_input);
    }
    free_posix_environment(&environment);
    return push_failure(L, errno_code(error_value), "Linux process start failed");

posix_start_success:
    ;
  }
#endif
  process->started_at = started_at;
  return return_success(L);
}

static int l_process_poll(lua_State *L)
{
  yaca_process *process;
  lua_Integer budget_value;
  lua_Integer maximum_value;
  size_t budget;
  size_t maximum;
  size_t count;
  int read_result;

  process = check_process(L, 1);
  (void)luaL_checkinteger(L, 2);
  budget_value = luaL_checkinteger(L, 3);
  maximum_value = luaL_checkinteger(L, 4);
  if (budget_value < 0
      || maximum_value <= 0
      || (lua_Unsigned)budget_value > (lua_Unsigned)SIZE_MAX
      || (lua_Unsigned)maximum_value > (lua_Unsigned)SIZE_MAX)
  {
    return push_failure(L, "Limit", "process poll limit is invalid");
  }
  budget = (size_t)budget_value;
  maximum = (size_t)maximum_value;
  lua_createtable(L, (int)(budget > INT_MAX ? INT_MAX : budget), 0);
  count = 0;
  if (count < budget)
  {
#if defined(_WIN32)
    read_result = read_windows_process_stream(
      L,
      &process->stdout_read,
      "stdout",
      maximum);
#else
    read_result = read_posix_process_stream(
      L,
      &process->stdout_read,
      "stdout",
      maximum);
#endif
    if (read_result < 0)
    {
      lua_pop(L, 1);
#if defined(_WIN32)
      return push_windows_failure(L, GetLastError(), "process stdout poll failed");
#else
      return push_failure(L, errno_code(errno), "process stdout poll failed");
#endif
    }
    if (read_result > 0)
    {
      lua_seti(L, -2, (lua_Integer)++count);
    }
  }
  if (count < budget)
  {
#if defined(_WIN32)
    read_result = read_windows_process_stream(
      L,
      &process->stderr_read,
      "stderr",
      maximum);
#else
    read_result = read_posix_process_stream(
      L,
      &process->stderr_read,
      "stderr",
      maximum);
#endif
    if (read_result < 0)
    {
      lua_pop(L, 1);
#if defined(_WIN32)
      return push_windows_failure(L, GetLastError(), "process stderr poll failed");
#else
      return push_failure(L, errno_code(errno), "process stderr poll failed");
#endif
    }
    if (read_result > 0)
    {
      lua_seti(L, -2, (lua_Integer)++count);
    }
  }
#if defined(_WIN32)
  refresh_windows_process(process);
  if (process->reaped)
  {
    if (process->stdout_read != INVALID_HANDLE_VALUE && count < budget)
    {
      read_result = read_windows_process_stream(
        L,
        &process->stdout_read,
        "stdout",
        maximum);
      if (read_result > 0)
      {
        lua_seti(L, -2, (lua_Integer)++count);
      }
      else if (read_result < 0)
      {
        lua_pop(L, 1);
        return push_windows_failure(L, GetLastError(), "process stdout drain failed");
      }
    }
    if (process->stderr_read != INVALID_HANDLE_VALUE && count < budget)
    {
      read_result = read_windows_process_stream(
        L,
        &process->stderr_read,
        "stderr",
        maximum);
      if (read_result > 0)
      {
        lua_seti(L, -2, (lua_Integer)++count);
      }
      else if (read_result < 0)
      {
        lua_pop(L, 1);
        return push_windows_failure(L, GetLastError(), "process stderr drain failed");
      }
    }
  }
#else
  refresh_posix_process(process);
  if (process->reaped)
  {
    if (process->stdout_read >= 0 && count < budget)
    {
      read_result = read_posix_process_stream(
        L,
        &process->stdout_read,
        "stdout",
        maximum);
      if (read_result > 0)
      {
        lua_seti(L, -2, (lua_Integer)++count);
      }
      else if (read_result < 0)
      {
        lua_pop(L, 1);
        return push_failure(L, errno_code(errno), "process stdout drain failed");
      }
    }
    if (process->stderr_read >= 0 && count < budget)
    {
      read_result = read_posix_process_stream(
        L,
        &process->stderr_read,
        "stderr",
        maximum);
      if (read_result > 0)
      {
        lua_seti(L, -2, (lua_Integer)++count);
      }
      else if (read_result < 0)
      {
        lua_pop(L, 1);
        return push_failure(L, errno_code(errno), "process stderr drain failed");
      }
    }
  }
#endif
  if (process->reaped
      && process->outcome[0] != '\0'
      && count < budget
#if defined(_WIN32)
      && process->stdout_read == INVALID_HANDLE_VALUE
      && process->stderr_read == INVALID_HANDLE_VALUE
#else
      && process->stdout_read < 0
      && process->stderr_read < 0
#endif
      && !process->terminal_emitted)
  {
    lua_createtable(L, 0, 2);
    lua_pushstring(L, "terminal");
    lua_setfield(L, -2, "kind");
    lua_pushstring(L, process->outcome);
    lua_setfield(L, -2, "outcome");
    lua_seti(L, -2, (lua_Integer)++count);
    process->terminal_emitted = 1;
  }
  return return_success(L);
}

static int l_process_cancel(lua_State *L)
{
  yaca_process *process;

  process = check_process(L, 1);
  (void)luaL_checkinteger(L, 2);
  if (process->reaped)
  {
    lua_pushboolean(L, 0);
    return return_success(L);
  }
#if defined(_WIN32)
  refresh_windows_process(process);
  if (process->reaped || windows_job_is_empty(process->job))
  {
    lua_pushboolean(L, 0);
    return return_success(L);
  }
  if (!TerminateJobObject(process->job, 0xE0000004UL))
  {
    return push_windows_failure(L, GetLastError(), "process cancellation failed");
  }
  process->cancel_requested = 1;
#else
  refresh_posix_process(process);
  if (process->reaped)
  {
    lua_pushboolean(L, 0);
    return return_success(L);
  }
  if (kill(-process->process_id, SIGKILL) != 0)
  {
    if (errno == ESRCH)
    {
      refresh_posix_process(process);
      lua_pushboolean(L, 0);
      return return_success(L);
    }
    return push_failure(L, errno_code(errno), "process cancellation failed");
  }
  process->cancel_requested = 1;
#endif
  lua_pushboolean(L, 1);
  return return_success(L);
}

static void push_process_result(lua_State *L, const yaca_process *process)
{
  lua_Integer duration;

  duration = process->finished_at >= process->started_at
    ? process->finished_at - process->started_at
    : 0;
  lua_createtable(L, 0, 6);
  lua_pushstring(L, process->outcome);
  lua_setfield(L, -2, "outcome");
  lua_pushstring(L, process->exit_kind);
  lua_setfield(L, -2, "exit_kind");
#if defined(_WIN32)
  if (strcmp(process->exit_kind, "exit-code") == 0)
  {
    lua_pushinteger(L, (lua_Integer)process->exit_code);
    lua_setfield(L, -2, "exit_code");
  }
#else
  if (WIFEXITED(process->wait_status))
  {
    lua_pushinteger(L, (lua_Integer)WEXITSTATUS(process->wait_status));
    lua_setfield(L, -2, "exit_code");
  }
#endif
  if (process->signal_or_exception[0] != '\0')
  {
    lua_pushstring(L, process->signal_or_exception);
    lua_setfield(L, -2, "signal_or_exception");
  }
  lua_pushinteger(L, duration);
  lua_setfield(L, -2, "duration_ms");
  lua_pushboolean(L, process->descendants_proven_stopped);
  lua_setfield(L, -2, "descendants_proven_stopped");
}

static int l_process_join(lua_State *L)
{
  yaca_process *process;

  process = check_process(L, 1);
  if (!lua_isnoneornil(L, 2))
  {
    (void)luaL_checkinteger(L, 2);
  }
#if defined(_WIN32)
  refresh_windows_process(process);
#else
  refresh_posix_process(process);
#endif
  if (!process->reaped || process->outcome[0] == '\0')
  {
    return push_failure(L, "WouldBlock", "process has not reached terminal truth");
  }
  push_process_result(L, process);
  return return_success(L);
}

static int l_process_close(lua_State *L)
{
  yaca_process *process;

  process = check_process(L, 1);
  if (!process->reaped || process->outcome[0] == '\0')
  {
    return push_failure(L, "OutcomeUnknown", "process cannot close before terminal truth");
  }
  close_process_handles(process);
  return push_true_result(L);
}

static yaca_terminal *check_terminal(lua_State *L, int index)
{
  yaca_terminal *terminal;

  terminal = (yaca_terminal *)luaL_checkudata(L, index, YACA_TERMINAL_METATABLE);
  if (terminal->closed)
  {
    luaL_error(L, "native terminal handle is closed");
  }
  return terminal;
}

#if defined(_WIN32)
static int cancel_windows_cooked_read(yaca_terminal *terminal);
#endif

static int restore_terminal(yaca_terminal *terminal)
{
  if (terminal->restored)
  {
    return 1;
  }
#if defined(_WIN32)
  if (terminal->has_original_mode
      && !SetConsoleMode(terminal->input, terminal->original_mode))
  {
    return 0;
  }
#else
  if (terminal->has_original_mode
      && tcsetattr(terminal->input, TCSANOW, &terminal->original_mode) != 0)
  {
    return 0;
  }
  if (terminal->has_original_flags
      && fcntl(terminal->input, F_SETFL, terminal->original_flags) != 0)
  {
    return 0;
  }
#endif
  terminal->restored = 1;
  return 1;
}

static int l_terminal_gc(lua_State *L)
{
  yaca_terminal *terminal;

  terminal = (yaca_terminal *)luaL_testudata(L, 1, YACA_TERMINAL_METATABLE);
  if (terminal != NULL && !terminal->closed)
  {
#if defined(_WIN32)
    if (!cancel_windows_cooked_read(terminal))
    {
      /* The worker owns an independent heap record, so a failed emergency
      ** cancellation may be detached without accessing collected userdata. */
      terminal->cooked_read = NULL;
    }
#endif
    restore_terminal(terminal);
    terminal->closed = 1;
  }
  return 0;
}

static yaca_terminal *push_terminal(lua_State *L)
{
  yaca_terminal *terminal;

  terminal = (yaca_terminal *)lua_newuserdatauv(L, sizeof(yaca_terminal), 0);
  memset(terminal, 0, sizeof(*terminal));
#if defined(_WIN32)
  terminal->input = INVALID_HANDLE_VALUE;
#else
  terminal->input = STDIN_FILENO;
  terminal->original_flags = -1;
#endif
  luaL_setmetatable(L, YACA_TERMINAL_METATABLE);
  return terminal;
}

static void push_terminal_action(
  lua_State *L,
  const char *intent,
  const char *bytes,
  size_t length)
{
  lua_createtable(L, 0, bytes == NULL ? 2 : 3);
  lua_pushstring(L, "action");
  lua_setfield(L, -2, "kind");
  lua_pushstring(L, intent);
  lua_setfield(L, -2, "intent");
  if (bytes != NULL)
  {
    lua_pushlstring(L, bytes, length);
    lua_setfield(L, -2, "text");
  }
}

static void push_terminal_fact(lua_State *L, yaca_terminal *terminal)
{
  lua_createtable(L, 0, 2);
  lua_pushstring(L, "terminal");
  lua_setfield(L, -2, "kind");
  lua_pushstring(L, terminal->outcome);
  lua_setfield(L, -2, "outcome");
  terminal->terminal_emitted = 1;
}

#if defined(_WIN32)

static size_t encode_utf8_codepoint(unsigned long codepoint, char output[4])
{
  if (codepoint <= 0x7FUL)
  {
    output[0] = (char)codepoint;
    return 1;
  }
  if (codepoint <= 0x7FFUL)
  {
    output[0] = (char)(0xC0U | (codepoint >> 6));
    output[1] = (char)(0x80U | (codepoint & 0x3FU));
    return 2;
  }
  if (codepoint <= 0xFFFFUL)
  {
    output[0] = (char)(0xE0U | (codepoint >> 12));
    output[1] = (char)(0x80U | ((codepoint >> 6) & 0x3FU));
    output[2] = (char)(0x80U | (codepoint & 0x3FU));
    return 3;
  }
  output[0] = (char)(0xF0U | (codepoint >> 18));
  output[1] = (char)(0x80U | ((codepoint >> 12) & 0x3FU));
  output[2] = (char)(0x80U | ((codepoint >> 6) & 0x3FU));
  output[3] = (char)(0x80U | (codepoint & 0x3FU));
  return 4;
}

static int push_windows_key_action(
  lua_State *L,
  yaca_terminal *terminal,
  const KEY_EVENT_RECORD *key)
{
  DWORD modifiers;
  WCHAR character;
  unsigned long codepoint;
  char bytes[4];
  size_t length;

  if (!key->bKeyDown)
  {
    return 0;
  }
  modifiers = key->dwControlKeyState;
  if (key->wVirtualKeyCode == VK_RETURN)
  {
    if ((modifiers & (LEFT_CTRL_PRESSED | RIGHT_CTRL_PRESSED)) != 0)
    {
      push_terminal_action(L, "steer", NULL, 0);
    }
    else if ((modifiers & SHIFT_PRESSED) != 0)
    {
      push_terminal_action(L, "newline", NULL, 0);
    }
    else if ((modifiers & (LEFT_ALT_PRESSED | RIGHT_ALT_PRESSED)) != 0)
    {
      push_terminal_action(L, "side", NULL, 0);
    }
    else
    {
      push_terminal_action(L, "submit-or-queue", NULL, 0);
    }
    return 1;
  }
  if (key->wVirtualKeyCode == VK_ESCAPE)
  {
    push_terminal_action(L, "cancel", NULL, 0);
    return 1;
  }
  character = key->uChar.UnicodeChar;
  if (character == 0)
  {
    return 0;
  }
  if (character >= 0xD800U && character <= 0xDBFFU)
  {
    terminal->pending_high_surrogate = character;
    return 0;
  }
  if (character >= 0xDC00U && character <= 0xDFFFU)
  {
    if (terminal->pending_high_surrogate == 0)
    {
      return -1;
    }
    codepoint = 0x10000UL
      + (((unsigned long)terminal->pending_high_surrogate - 0xD800UL) << 10)
      + ((unsigned long)character - 0xDC00UL);
    terminal->pending_high_surrogate = 0;
  }
  else
  {
    if (terminal->pending_high_surrogate != 0)
    {
      terminal->pending_high_surrogate = 0;
      return -1;
    }
    codepoint = (unsigned long)character;
  }
  length = encode_utf8_codepoint(codepoint, bytes);
  if (length > terminal->maximum_input_bytes)
  {
    return -1;
  }
  push_terminal_action(L, "text", bytes, length);
  return 1;
}

static DWORD WINAPI windows_cooked_reader(LPVOID opaque)
{
  yaca_terminal_read *read;
  DWORD received;

  read = (yaca_terminal_read *)opaque;
  received = 0;
  if (ReadConsoleW(
      read->input,
      read->wide,
      read->capacity,
      &received,
      NULL))
  {
    read->received = received;
    read->error_value = ERROR_SUCCESS;
  }
  else
  {
    read->received = 0;
    read->error_value = GetLastError();
  }
  return 0;
}

/*
** Starts one real cooked ReadConsoleW operation on a dedicated thread.  This
** preserves the host console's live XP-era echo, backspace, cursor, and IME
** behavior without blocking the Agent event loop while a draft is unfinished.
*/
static int start_windows_cooked_read(yaca_terminal *terminal)
{
  yaca_terminal_read *read;
  size_t capacity;
  DWORD error_value;

  if (terminal->cooked_read != NULL)
  {
    return 1;
  }
  capacity = terminal->maximum_input_bytes;
  if (capacity > 0x7ffffffdU)
  {
    capacity = 0x7ffffffdU;
  }
  capacity += 2U;
  if (capacity > (SIZE_MAX / sizeof(WCHAR)) - 1U)
  {
    SetLastError(ERROR_NOT_ENOUGH_MEMORY);
    return 0;
  }
  read = (yaca_terminal_read *)calloc(1, sizeof(yaca_terminal_read));
  if (read == NULL)
  {
    SetLastError(ERROR_NOT_ENOUGH_MEMORY);
    return 0;
  }
  read->wide = (WCHAR *)malloc((capacity + 1U) * sizeof(WCHAR));
  if (read->wide == NULL)
  {
    free(read);
    SetLastError(ERROR_NOT_ENOUGH_MEMORY);
    return 0;
  }
  read->input = terminal->input;
  read->capacity = (DWORD)capacity;
  read->thread = CreateThread(
    NULL,
    0,
    windows_cooked_reader,
    read,
    0,
    NULL);
  if (read->thread == NULL)
  {
    error_value = GetLastError();
    free(read->wide);
    free(read);
    SetLastError(error_value);
    return 0;
  }
  terminal->cooked_read = read;
  return 1;
}

static void free_windows_cooked_read(yaca_terminal *terminal)
{
  yaca_terminal_read *read;

  read = terminal->cooked_read;
  if (read == NULL)
  {
    return;
  }
  if (read->thread != NULL)
  {
    CloseHandle(read->thread);
  }
  free(read->wide);
  free(read);
  terminal->cooked_read = NULL;
}

/*
** XP lacks the newer per-thread synchronous-I/O cancellation API.  A synthetic
** Enter is written only while cancelling yaca's own active line read, then the
** worker is joined before its storage or the original console mode is released.
*/
static int cancel_windows_cooked_read(yaca_terminal *terminal)
{
  INPUT_RECORD record;
  DWORD written;
  DWORD wait_result;

  if (terminal->cooked_read == NULL)
  {
    return 1;
  }
  wait_result = WaitForSingleObject(terminal->cooked_read->thread, 0);
  if (wait_result == WAIT_TIMEOUT)
  {
    memset(&record, 0, sizeof(record));
    record.EventType = KEY_EVENT;
    record.Event.KeyEvent.bKeyDown = TRUE;
    record.Event.KeyEvent.wRepeatCount = 1;
    record.Event.KeyEvent.wVirtualKeyCode = VK_RETURN;
    record.Event.KeyEvent.uChar.UnicodeChar = L'\r';
    written = 0;
    if (!WriteConsoleInputW(terminal->input, &record, 1, &written))
    {
      return 0;
    }
    if (written != 1)
    {
      SetLastError(ERROR_WRITE_FAULT);
      return 0;
    }
    wait_result = WaitForSingleObject(terminal->cooked_read->thread, 5000);
  }
  if (wait_result != WAIT_OBJECT_0)
  {
    if (wait_result == WAIT_TIMEOUT)
    {
      SetLastError(ERROR_TIMEOUT);
    }
    return 0;
  }
  free_windows_cooked_read(terminal);
  return 1;
}

/*
** Emits one completed wide cooked line as strict UTF-8.
*/
static int push_windows_cooked_line(lua_State *L, yaca_terminal *terminal)
{
  yaca_terminal_read *read;
  char *bytes;
  size_t byte_length;
  size_t index;

  read = terminal->cooked_read;
  if (read == NULL)
  {
    return 0;
  }
  if (read->received == 0)
  {
    strcpy(terminal->outcome, "completed");
    push_terminal_fact(L, terminal);
    return 2;
  }
  if (terminal->maximum_input_bytes == SIZE_MAX)
  {
    return -1;
  }
  bytes = (char *)malloc(terminal->maximum_input_bytes + 1U);
  if (bytes == NULL)
  {
    return -1;
  }
  byte_length = 0;
  index = 0;
  while (index < (size_t)read->received)
  {
    unsigned long codepoint;
    unsigned int unit;
    char encoded[4];
    size_t encoded_length;

    unit = (unsigned int)read->wide[index++];
    if (unit == 0U)
    {
      free(bytes);
      return -2;
    }
    if (unit >= 0xD800U && unit <= 0xDBFFU)
    {
      unsigned int low;

      if (index >= (size_t)read->received)
      {
        free(bytes);
        return -2;
      }
      low = (unsigned int)read->wide[index++];
      if (low < 0xDC00U || low > 0xDFFFU)
      {
        free(bytes);
        return -2;
      }
      codepoint = 0x10000UL
        + (((unsigned long)unit - 0xD800UL) << 10)
        + ((unsigned long)low - 0xDC00UL);
    }
    else if (unit >= 0xDC00U && unit <= 0xDFFFU)
    {
      free(bytes);
      return -2;
    }
    else
    {
      codepoint = (unsigned long)unit;
    }
    encoded_length = encode_utf8_codepoint(codepoint, encoded);
    if (encoded_length > terminal->maximum_input_bytes - byte_length)
    {
      free(bytes);
      return -1;
    }
    memcpy(bytes + byte_length, encoded, encoded_length);
    byte_length += encoded_length;
  }
  push_terminal_action(L, "text", bytes, byte_length);
  free(bytes);
  return 1;
}

#endif

static int l_terminal_start(lua_State *L)
{
  const char *mode;
  size_t mode_length;
  lua_Integer maximum_input_bytes;
  yaca_terminal *terminal;

  luaL_checktype(L, 1, LUA_TTABLE);
  if (!request_string_field(L, 1, "mode", &mode, &mode_length, 0))
  {
    return push_failure(L, "InvalidTerminalMode", "terminal mode is invalid");
  }
  (void)mode_length;
  if (strcmp(mode, "auto") != 0
      && strcmp(mode, "raw") != 0
      && strcmp(mode, "cooked") != 0)
  {
    return push_failure(L, "InvalidTerminalMode", "terminal mode is invalid");
  }
  lua_getfield(L, 1, "maximum_input_bytes");
  if (!lua_isinteger(L, -1) || lua_tointeger(L, -1) <= 0)
  {
    lua_pop(L, 1);
    return push_failure(L, "Limit", "terminal input limit is invalid");
  }
  maximum_input_bytes = lua_tointeger(L, -1);
  lua_pop(L, 1);
  if ((lua_Unsigned)maximum_input_bytes > (lua_Unsigned)SIZE_MAX)
  {
    return push_failure(L, "Limit", "terminal input limit is too large");
  }
  terminal = push_terminal(L);
  terminal->maximum_input_bytes = (size_t)maximum_input_bytes;
#if defined(_WIN32)
  {
    DWORD current_mode;
    DWORD next_mode;

    terminal->input = GetStdHandle(STD_INPUT_HANDLE);
    if (terminal->input == NULL || terminal->input == INVALID_HANDLE_VALUE)
    {
      lua_pop(L, 1);
      return push_failure(L, "TerminalUnavailable", "standard input is unavailable");
    }
    terminal->input_type = GetFileType(terminal->input);
    if (GetConsoleMode(terminal->input, &current_mode))
    {
      terminal->original_mode = current_mode;
      terminal->has_original_mode = 1;
      terminal->cooked_mode = strcmp(mode, "cooked") == 0;
      if (terminal->cooked_mode)
      {
        next_mode = current_mode;
        next_mode |= ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT | ENABLE_PROCESSED_INPUT;
        if (!SetConsoleMode(terminal->input, next_mode))
        {
          lua_pop(L, 1);
          return push_windows_failure(L, GetLastError(), "cannot enter cooked terminal mode");
        }
      }
      else
      {
        next_mode = current_mode;
        next_mode |= ENABLE_EXTENDED_FLAGS | ENABLE_WINDOW_INPUT;
        next_mode &= ~(ENABLE_LINE_INPUT
          | ENABLE_ECHO_INPUT
          | ENABLE_PROCESSED_INPUT
          | ENABLE_QUICK_EDIT_MODE);
        if (!SetConsoleMode(terminal->input, next_mode))
        {
          lua_pop(L, 1);
          return push_windows_failure(L, GetLastError(), "cannot enter terminal input mode");
        }
      }
    }
    else if (strcmp(mode, "raw") == 0)
    {
      lua_pop(L, 1);
      return push_failure(L, "TerminalCapability", "raw input requires a Windows console");
    }
    else if (terminal->input_type == FILE_TYPE_CHAR)
    {
      lua_pop(L, 1);
      return push_failure(L, "TerminalCapability", "unsupported character input handle");
    }
    if (terminal->cooked_mode && !start_windows_cooked_read(terminal))
    {
      DWORD error_value;

      error_value = GetLastError();
      restore_terminal(terminal);
      lua_pop(L, 1);
      return push_windows_failure(L, error_value, "cannot start cooked terminal input");
    }
  }
#else
  {
    struct termios next_mode;

    terminal->input = STDIN_FILENO;
    terminal->original_flags = fcntl(terminal->input, F_GETFL);
    if (terminal->original_flags < 0)
    {
      lua_pop(L, 1);
      return push_failure(L, errno_code(errno), "cannot inspect terminal input flags");
    }
    terminal->has_original_flags = 1;
    if (isatty(terminal->input))
    {
      if (tcgetattr(terminal->input, &terminal->original_mode) != 0
          )
      {
        lua_pop(L, 1);
        return push_failure(L, errno_code(errno), "cannot inspect terminal input mode");
      }
      terminal->has_original_mode = 1;
      if (strcmp(mode, "cooked") != 0)
      {
        next_mode = terminal->original_mode;
        next_mode.c_lflag &= (tcflag_t)~(ICANON | ECHO);
        next_mode.c_cc[VMIN] = 0;
        next_mode.c_cc[VTIME] = 0;
        if (tcsetattr(terminal->input, TCSANOW, &next_mode) != 0
            )
        {
          lua_pop(L, 1);
          return push_failure(L, errno_code(errno), "cannot enter terminal input mode");
        }
      }
    }
    else if (strcmp(mode, "raw") == 0)
    {
      lua_pop(L, 1);
      return push_failure(L, "TerminalCapability", "raw input requires a terminal");
    }
    if (fcntl(
        terminal->input,
        F_SETFL,
        terminal->original_flags | O_NONBLOCK) != 0)
    {
      int error_value;

      error_value = errno;
      restore_terminal(terminal);
      lua_pop(L, 1);
      return push_failure(L, errno_code(error_value), "cannot make terminal input nonblocking");
    }
  }
#endif
  return return_success(L);
}

static int l_terminal_poll(lua_State *L)
{
  yaca_terminal *terminal;
  lua_Integer budget_value;
  size_t budget;
  size_t count;

  terminal = check_terminal(L, 1);
  (void)luaL_checkinteger(L, 2);
  budget_value = luaL_checkinteger(L, 3);
  if (budget_value < 0 || (lua_Unsigned)budget_value > (lua_Unsigned)SIZE_MAX)
  {
    return push_failure(L, "Limit", "terminal poll budget is invalid");
  }
  budget = (size_t)budget_value;
  lua_createtable(L, (int)(budget > INT_MAX ? INT_MAX : budget), 0);
  count = 0;
  if (terminal->cancelled && !terminal->terminal_emitted && count < budget)
  {
    strcpy(terminal->outcome, "cancelled");
    push_terminal_fact(L, terminal);
    lua_seti(L, -2, (lua_Integer)++count);
    return return_success(L);
  }
  if (terminal->terminal_emitted || count >= budget)
  {
    return return_success(L);
  }
#if defined(_WIN32)
  if (terminal->has_original_mode)
  {
    if (terminal->cooked_mode)
    {
      DWORD wait_result;
      DWORD read_error;
      int line_result;

      if (terminal->cooked_read == NULL
          && !start_windows_cooked_read(terminal))
      {
        lua_pop(L, 1);
        return push_windows_failure(L, GetLastError(), "cooked terminal input restart failed");
      }
      wait_result = WaitForSingleObject(terminal->cooked_read->thread, 0);
      if (wait_result == WAIT_TIMEOUT)
      {
        return return_success(L);
      }
      if (wait_result != WAIT_OBJECT_0)
      {
        lua_pop(L, 1);
        return push_windows_failure(L, GetLastError(), "cooked terminal input wait failed");
      }
      read_error = terminal->cooked_read->error_value;
      if (read_error != ERROR_SUCCESS)
      {
        free_windows_cooked_read(terminal);
        lua_pop(L, 1);
        return push_windows_failure(L, read_error, "cooked terminal line read failed");
      }
      line_result = push_windows_cooked_line(L, terminal);
      free_windows_cooked_read(terminal);
      if (line_result == 0)
      {
        lua_pop(L, 1);
        return push_failure(L, "TerminalContract", "cooked terminal line is unavailable");
      }
      if (line_result == -2)
      {
        lua_pop(L, 1);
        return push_failure(L, "InvalidEncoding", "cooked terminal emitted invalid Unicode");
      }
      if (line_result < 0)
      {
        lua_pop(L, 1);
        return push_failure(L, "Limit", "cooked terminal line exceeds its byte limit");
      }
      lua_seti(L, -2, 1);
      return return_success(L);
    }
    else
    {
      DWORD available;

      available = 0;
      if (!GetNumberOfConsoleInputEvents(terminal->input, &available))
      {
        lua_pop(L, 1);
        return push_windows_failure(L, GetLastError(), "terminal input poll failed");
      }
      while (available > 0 && count < budget)
      {
        INPUT_RECORD record;
        DWORD received;
        int action_result;

        if (!ReadConsoleInputW(terminal->input, &record, 1, &received))
        {
          lua_pop(L, 1);
          return push_windows_failure(L, GetLastError(), "terminal input read failed");
        }
        available--;
        if (received == 0 || record.EventType != KEY_EVENT)
        {
          continue;
        }
        action_result = push_windows_key_action(L, terminal, &record.Event.KeyEvent);
        if (action_result < 0)
        {
          lua_pop(L, 1);
          return push_failure(L, "InvalidEncoding", "terminal emitted an invalid Unicode scalar");
        }
        if (action_result > 0)
        {
          lua_seti(L, -2, (lua_Integer)++count);
        }
      }
    }
  }
  else
  {
    char *buffer;
    DWORD received;
    DWORD maximum;
    DWORD available;

    available = 0;
    if (terminal->input_type == FILE_TYPE_PIPE)
    {
      if (!PeekNamedPipe(terminal->input, NULL, 0, NULL, &available, NULL))
      {
        DWORD error_value;

        error_value = GetLastError();
        if (error_value == ERROR_BROKEN_PIPE)
        {
          strcpy(terminal->outcome, "completed");
          push_terminal_fact(L, terminal);
          lua_seti(L, -2, 1);
          return return_success(L);
        }
        lua_pop(L, 1);
        return push_windows_failure(L, error_value, "terminal pipe poll failed");
      }
      if (available == 0)
      {
        return return_success(L);
      }
    }

    maximum = terminal->maximum_input_bytes > 0x7fffffffU
      ? 0x7fffffffUL
      : (DWORD)terminal->maximum_input_bytes;
    if (terminal->input_type == FILE_TYPE_PIPE && available < maximum)
    {
      maximum = available;
    }
    buffer = (char *)malloc((size_t)maximum);
    if (buffer == NULL)
    {
      lua_pop(L, 1);
      return push_failure(L, "Limit", "terminal input allocation failed");
    }
    if (!ReadFile(terminal->input, buffer, maximum, &received, NULL))
    {
      DWORD error_value;

      error_value = GetLastError();
      free(buffer);
      lua_pop(L, 1);
      return push_windows_failure(L, error_value, "terminal redirected input failed");
    }
    if (received == 0)
    {
      strcpy(terminal->outcome, "completed");
      push_terminal_fact(L, terminal);
    }
    else
    {
      push_terminal_action(L, "text", buffer, (size_t)received);
    }
    free(buffer);
    lua_seti(L, -2, 1);
  }
#else
  {
    char *buffer;
    ssize_t received;

    buffer = (char *)malloc(terminal->maximum_input_bytes);
    if (buffer == NULL)
    {
      lua_pop(L, 1);
      return push_failure(L, "Limit", "terminal input allocation failed");
    }
    do
    {
      received = read(terminal->input, buffer, terminal->maximum_input_bytes);
    }
    while (received < 0 && errno == EINTR);
    if (received < 0 && (errno == EAGAIN || errno == EWOULDBLOCK))
    {
      free(buffer);
      return return_success(L);
    }
    if (received < 0)
    {
      int error_value;

      error_value = errno;
      free(buffer);
      lua_pop(L, 1);
      return push_failure(L, errno_code(error_value), "terminal input read failed");
    }
    if (received == 0)
    {
      strcpy(terminal->outcome, "completed");
      push_terminal_fact(L, terminal);
    }
    else if (received == 1 && buffer[0] == 27)
    {
      push_terminal_action(L, "cancel", NULL, 0);
    }
    else if (received == 1 && (buffer[0] == '\r' || buffer[0] == '\n'))
    {
      push_terminal_action(L, "submit-or-queue", NULL, 0);
    }
    else
    {
      push_terminal_action(L, "text", buffer, (size_t)received);
    }
    free(buffer);
    lua_seti(L, -2, 1);
  }
#endif
  return return_success(L);
}

static int l_terminal_cancel(lua_State *L)
{
  yaca_terminal *terminal;

  terminal = check_terminal(L, 1);
  (void)luaL_checkinteger(L, 2);
  if (terminal->terminal_emitted)
  {
    lua_pushboolean(L, 0);
    return return_success(L);
  }
#if defined(_WIN32)
  if (terminal->cooked_mode && !cancel_windows_cooked_read(terminal))
  {
    return push_windows_failure(L, GetLastError(), "cooked terminal cancellation failed");
  }
#endif
  terminal->cancelled = 1;
  lua_pushboolean(L, 1);
  return return_success(L);
}

static int l_terminal_join(lua_State *L)
{
  yaca_terminal *terminal;

  terminal = check_terminal(L, 1);
  if (!lua_isnoneornil(L, 2))
  {
    (void)luaL_checkinteger(L, 2);
  }
  if (!terminal->terminal_emitted || terminal->outcome[0] == '\0')
  {
    return push_failure(L, "WouldBlock", "terminal has not reached terminal truth");
  }
  lua_createtable(L, 0, 1);
  lua_pushstring(L, terminal->outcome);
  lua_setfield(L, -2, "outcome");
  return return_success(L);
}

static int l_terminal_restore(lua_State *L)
{
  yaca_terminal *terminal;

  terminal = check_terminal(L, 1);
#if defined(_WIN32)
  if (terminal->cooked_mode && !cancel_windows_cooked_read(terminal))
  {
    return push_windows_failure(L, GetLastError(), "cooked terminal restoration join failed");
  }
#endif
  if (!restore_terminal(terminal))
  {
#if defined(_WIN32)
    return push_windows_failure(L, GetLastError(), "terminal restoration failed");
#else
    return push_failure(L, errno_code(errno), "terminal restoration failed");
#endif
  }
  return push_true_result(L);
}

static int l_terminal_close(lua_State *L)
{
  yaca_terminal *terminal;

  terminal = check_terminal(L, 1);
#if defined(_WIN32)
  if (terminal->cooked_mode && !cancel_windows_cooked_read(terminal))
  {
    return push_windows_failure(L, GetLastError(), "cooked terminal close join failed");
  }
#endif
  if (!terminal->restored && !restore_terminal(terminal))
  {
#if defined(_WIN32)
    return push_windows_failure(L, GetLastError(), "terminal close restoration failed");
#else
    return push_failure(L, errno_code(errno), "terminal close restoration failed");
#endif
  }
  terminal->closed = 1;
  return push_true_result(L);
}

static const uint32_t yaca_sha256_constants[64] = {
  UINT32_C(0x428a2f98), UINT32_C(0x71374491), UINT32_C(0xb5c0fbcf),
  UINT32_C(0xe9b5dba5), UINT32_C(0x3956c25b), UINT32_C(0x59f111f1),
  UINT32_C(0x923f82a4), UINT32_C(0xab1c5ed5), UINT32_C(0xd807aa98),
  UINT32_C(0x12835b01), UINT32_C(0x243185be), UINT32_C(0x550c7dc3),
  UINT32_C(0x72be5d74), UINT32_C(0x80deb1fe), UINT32_C(0x9bdc06a7),
  UINT32_C(0xc19bf174), UINT32_C(0xe49b69c1), UINT32_C(0xefbe4786),
  UINT32_C(0x0fc19dc6), UINT32_C(0x240ca1cc), UINT32_C(0x2de92c6f),
  UINT32_C(0x4a7484aa), UINT32_C(0x5cb0a9dc), UINT32_C(0x76f988da),
  UINT32_C(0x983e5152), UINT32_C(0xa831c66d), UINT32_C(0xb00327c8),
  UINT32_C(0xbf597fc7), UINT32_C(0xc6e00bf3), UINT32_C(0xd5a79147),
  UINT32_C(0x06ca6351), UINT32_C(0x14292967), UINT32_C(0x27b70a85),
  UINT32_C(0x2e1b2138), UINT32_C(0x4d2c6dfc), UINT32_C(0x53380d13),
  UINT32_C(0x650a7354), UINT32_C(0x766a0abb), UINT32_C(0x81c2c92e),
  UINT32_C(0x92722c85), UINT32_C(0xa2bfe8a1), UINT32_C(0xa81a664b),
  UINT32_C(0xc24b8b70), UINT32_C(0xc76c51a3), UINT32_C(0xd192e819),
  UINT32_C(0xd6990624), UINT32_C(0xf40e3585), UINT32_C(0x106aa070),
  UINT32_C(0x19a4c116), UINT32_C(0x1e376c08), UINT32_C(0x2748774c),
  UINT32_C(0x34b0bcb5), UINT32_C(0x391c0cb3), UINT32_C(0x4ed8aa4a),
  UINT32_C(0x5b9cca4f), UINT32_C(0x682e6ff3), UINT32_C(0x748f82ee),
  UINT32_C(0x78a5636f), UINT32_C(0x84c87814), UINT32_C(0x8cc70208),
  UINT32_C(0x90befffa), UINT32_C(0xa4506ceb), UINT32_C(0xbef9a3f7),
  UINT32_C(0xc67178f2),
};

static uint32_t sha256_rotate_right(uint32_t value, unsigned int count)
{
  return (value >> count) | (value << (32U - count));
}

static void secure_zero(void *memory, size_t length)
{
  volatile unsigned char *bytes;

  bytes = (volatile unsigned char *)memory;
  while (length > 0)
  {
    *bytes++ = 0;
    --length;
  }
}

static int l_secure_random(lua_State *L)
{
  lua_Integer requested;
  unsigned char bytes[64];
  size_t length;

  requested = luaL_checkinteger(L, 1);
  if (requested < 1 || requested > (lua_Integer)sizeof(bytes))
  {
    return luaL_error(L, "secure random byte count must be from 1 through 64");
  }
  length = (size_t)requested;
#if defined(_WIN32)
  if (!SystemFunction036(bytes, (ULONG)length))
  {
    secure_zero(bytes, sizeof(bytes));
    return luaL_error(L, "native secure random source is unavailable");
  }
#else
  {
    int descriptor;
    size_t offset;

    descriptor = open("/dev/urandom", O_RDONLY
#if defined(O_CLOEXEC)
      | O_CLOEXEC
#endif
    );
    if (descriptor < 0)
    {
      secure_zero(bytes, sizeof(bytes));
      return luaL_error(L, "native secure random source is unavailable");
    }
    offset = 0;
    while (offset < length)
    {
      ssize_t count;

      count = read(descriptor, bytes + offset, length - offset);
      if (count < 0 && errno == EINTR) continue;
      if (count <= 0)
      {
        int error_value;

        error_value = count < 0 ? errno : EIO;
        close(descriptor);
        secure_zero(bytes, sizeof(bytes));
        errno = error_value;
        return luaL_error(L, "native secure random source is unavailable");
      }
      offset += (size_t)count;
    }
    if (close(descriptor) != 0)
    {
      secure_zero(bytes, sizeof(bytes));
      return luaL_error(L, "native secure random source could not be closed");
    }
  }
#endif
  lua_pushlstring(L, (const char *)bytes, length);
  secure_zero(bytes, sizeof(bytes));
  return 1;
}

static void sha256_transform(yaca_sha256 *context, const unsigned char block[64])
{
  uint32_t words[64];
  uint32_t a;
  uint32_t b;
  uint32_t c;
  uint32_t d;
  uint32_t e;
  uint32_t f;
  uint32_t g;
  uint32_t h;
  uint32_t first;
  uint32_t second;
  size_t index;

  for (index = 0; index < 16; ++index)
  {
    size_t offset;

    offset = index * 4;
    words[index] = ((uint32_t)block[offset] << 24)
      | ((uint32_t)block[offset + 1] << 16)
      | ((uint32_t)block[offset + 2] << 8)
      | (uint32_t)block[offset + 3];
  }
  for (index = 16; index < 64; ++index)
  {
    uint32_t lower;
    uint32_t upper;

    lower = sha256_rotate_right(words[index - 15], 7)
      ^ sha256_rotate_right(words[index - 15], 18)
      ^ (words[index - 15] >> 3);
    upper = sha256_rotate_right(words[index - 2], 17)
      ^ sha256_rotate_right(words[index - 2], 19)
      ^ (words[index - 2] >> 10);
    words[index] = words[index - 16] + lower + words[index - 7] + upper;
  }

  a = context->state[0];
  b = context->state[1];
  c = context->state[2];
  d = context->state[3];
  e = context->state[4];
  f = context->state[5];
  g = context->state[6];
  h = context->state[7];
  for (index = 0; index < 64; ++index)
  {
    uint32_t choice;
    uint32_t majority;
    uint32_t sum_a;
    uint32_t sum_e;

    sum_e = sha256_rotate_right(e, 6)
      ^ sha256_rotate_right(e, 11)
      ^ sha256_rotate_right(e, 25);
    choice = (e & f) ^ ((~e) & g);
    first = h + sum_e + choice + yaca_sha256_constants[index] + words[index];
    sum_a = sha256_rotate_right(a, 2)
      ^ sha256_rotate_right(a, 13)
      ^ sha256_rotate_right(a, 22);
    majority = (a & b) ^ (a & c) ^ (b & c);
    second = sum_a + majority;
    h = g;
    g = f;
    f = e;
    e = d + first;
    d = c;
    c = b;
    b = a;
    a = first + second;
  }
  context->state[0] += a;
  context->state[1] += b;
  context->state[2] += c;
  context->state[3] += d;
  context->state[4] += e;
  context->state[5] += f;
  context->state[6] += g;
  context->state[7] += h;
  secure_zero(words, sizeof(words));
}

static void sha256_initialize(yaca_sha256 *context)
{
  memset(context, 0, sizeof(*context));
  context->state[0] = UINT32_C(0x6a09e667);
  context->state[1] = UINT32_C(0xbb67ae85);
  context->state[2] = UINT32_C(0x3c6ef372);
  context->state[3] = UINT32_C(0xa54ff53a);
  context->state[4] = UINT32_C(0x510e527f);
  context->state[5] = UINT32_C(0x9b05688c);
  context->state[6] = UINT32_C(0x1f83d9ab);
  context->state[7] = UINT32_C(0x5be0cd19);
}

static int sha256_append(
  yaca_sha256 *context,
  const unsigned char *bytes,
  size_t length)
{
  size_t available;
  size_t copied;

  if ((uint64_t)length > UINT64_MAX / 8U - context->byte_count)
  {
    return 0;
  }
  context->byte_count += (uint64_t)length;
  while (length > 0)
  {
    if (context->buffer_length == 0 && length >= sizeof(context->buffer))
    {
      sha256_transform(context, bytes);
      bytes += sizeof(context->buffer);
      length -= sizeof(context->buffer);
      continue;
    }
    available = sizeof(context->buffer) - context->buffer_length;
    copied = length < available ? length : available;
    memcpy(context->buffer + context->buffer_length, bytes, copied);
    context->buffer_length += copied;
    bytes += copied;
    length -= copied;
    if (context->buffer_length == sizeof(context->buffer))
    {
      sha256_transform(context, context->buffer);
      context->buffer_length = 0;
    }
  }
  return 1;
}

static void sha256_finalize(yaca_sha256 *context, unsigned char digest[32])
{
  uint64_t bit_count;
  size_t index;

  bit_count = context->byte_count * 8U;
  context->buffer[context->buffer_length++] = 0x80;
  if (context->buffer_length > 56)
  {
    memset(
      context->buffer + context->buffer_length,
      0,
      sizeof(context->buffer) - context->buffer_length);
    sha256_transform(context, context->buffer);
    context->buffer_length = 0;
  }
  memset(context->buffer + context->buffer_length, 0, 56 - context->buffer_length);
  for (index = 0; index < 8; ++index)
  {
    context->buffer[63 - index] = (unsigned char)(bit_count >> (index * 8));
  }
  sha256_transform(context, context->buffer);
  for (index = 0; index < 8; ++index)
  {
    digest[index * 4] = (unsigned char)(context->state[index] >> 24);
    digest[index * 4 + 1] = (unsigned char)(context->state[index] >> 16);
    digest[index * 4 + 2] = (unsigned char)(context->state[index] >> 8);
    digest[index * 4 + 3] = (unsigned char)context->state[index];
  }
}

static yaca_sha256 *check_sha256(lua_State *L)
{
  return (yaca_sha256 *)luaL_checkudata(L, 1, YACA_SHA256_METATABLE);
}

static int l_sha256_gc(lua_State *L)
{
  yaca_sha256 *context;

  context = (yaca_sha256 *)luaL_checkudata(L, 1, YACA_SHA256_METATABLE);
  secure_zero(context, sizeof(*context));
  context->closed = 1;
  return 0;
}

static int l_sha256_start(lua_State *L)
{
  yaca_sha256 *context;

  context = (yaca_sha256 *)lua_newuserdatauv(L, sizeof(*context), 0);
  sha256_initialize(context);
  luaL_setmetatable(L, YACA_SHA256_METATABLE);
  return 1;
}

static int l_sha256_update(lua_State *L)
{
  yaca_sha256 *context;
  const char *bytes;
  size_t length;

  context = check_sha256(L);
  if (context->closed)
  {
    return luaL_error(L, "SHA-256 context is closed");
  }
  bytes = luaL_checklstring(L, 2, &length);
  if (!sha256_append(context, (const unsigned char *)bytes, length))
  {
    return luaL_error(L, "SHA-256 input exceeds the algorithm limit");
  }
  lua_pushboolean(L, 1);
  return 1;
}

static int l_sha256_finish(lua_State *L)
{
  yaca_sha256 *context;
  yaca_sha256 copy;
  unsigned char digest[32];

  context = check_sha256(L);
  if (context->closed)
  {
    return luaL_error(L, "SHA-256 context is closed");
  }
  copy = *context;
  sha256_finalize(&copy, digest);
  secure_zero(context, sizeof(*context));
  context->closed = 1;
  lua_pushlstring(L, (const char *)digest, sizeof(digest));
  secure_zero(digest, sizeof(digest));
  secure_zero(&copy, sizeof(copy));
  return 1;
}

static int l_sha256_close(lua_State *L)
{
  yaca_sha256 *context;

  context = check_sha256(L);
  if (!context->closed)
  {
    secure_zero(context, sizeof(*context));
    context->closed = 1;
  }
  lua_pushboolean(L, 1);
  return 1;
}

static int l_abi_version(lua_State *L)
{
  lua_pushliteral(L, YACA_ABI_VERSION);
  return 1;
}

static int l_platform_identity(lua_State *L)
{
  const char *operating_system;
  const char *architecture;

#if defined(_WIN32)
  operating_system = "windows";
#else
  operating_system = "linux";
#endif
#if defined(_M_IX86) || defined(__i386__)
  architecture = "x86";
#elif defined(_M_X64) || defined(__x86_64__)
  architecture = "x86_64";
#else
  architecture = "unknown";
#endif
  lua_createtable(L, 0, 2);
  lua_pushstring(L, operating_system);
  lua_setfield(L, -2, "os");
  lua_pushstring(L, architecture);
  lua_setfield(L, -2, "arch");
  return 1;
}

static int l_monotonic_now(lua_State *L)
{
  lua_Integer value;

  value = native_monotonic_milliseconds();
  if (value < 0)
  {
    return luaL_error(L, "native monotonic clock is unavailable");
  }
  lua_pushinteger(L, value);
  return 1;
}

/*
** Lua:
**   slept = module.sleep_ms(milliseconds)
**
** Waits for a bounded coordinator idle interval.  Windows uses the
** XP-compatible Sleep API; POSIX retries nanosleep only after EINTR.
** No domain state or deadline decision is owned by this primitive.
*/
static int l_sleep_ms(lua_State *L)
{
  lua_Integer milliseconds;

  milliseconds = luaL_checkinteger(L, 1);
  if (milliseconds < 0 || milliseconds > 60000)
  {
    return luaL_error(L, "native sleep interval is invalid");
  }
#if defined(_WIN32)
  Sleep((DWORD)milliseconds);
#else
  {
    struct timespec requested;
    struct timespec remaining;

    requested.tv_sec = (time_t)(milliseconds / 1000);
    requested.tv_nsec = (long)((milliseconds % 1000) * 1000000);
    while (nanosleep(&requested, &remaining) != 0)
    {
      if (errno != EINTR)
      {
        return luaL_error(L, "native sleep failed");
      }
      requested = remaining;
    }
  }
#endif
  lua_pushboolean(L, 1);
  return 1;
}

static int l_current_process_id(lua_State *L)
{
#if defined(_WIN32)
  DWORD process_id;

  process_id = GetCurrentProcessId();
  if (process_id == 0)
  {
    return luaL_error(L, "native process identity is unavailable");
  }
  lua_pushinteger(L, (lua_Integer)process_id);
#else
  pid_t process_id;

  process_id = getpid();
  if (process_id <= 0)
  {
    return luaL_error(L, "native process identity is unavailable");
  }
  lua_pushinteger(L, (lua_Integer)process_id);
#endif
  return 1;
}

static int l_utc_now(lua_State *L)
{
  char value[64];

#if defined(_WIN32)
  SYSTEMTIME current;

  GetSystemTime(&current);
  snprintf(
    value,
    sizeof(value),
    "%04u-%02u-%02uT%02u:%02u:%02uZ",
    (unsigned int)current.wYear,
    (unsigned int)current.wMonth,
    (unsigned int)current.wDay,
    (unsigned int)current.wHour,
    (unsigned int)current.wMinute,
    (unsigned int)current.wSecond);
#else
  time_t raw;
  struct tm current;

  raw = time(NULL);
  if (raw == (time_t)-1 || gmtime_r(&raw, &current) == NULL)
  {
    return luaL_error(L, "native UTC clock is unavailable");
  }
  if (strftime(value, sizeof(value), "%Y-%m-%dT%H:%M:%SZ", &current) == 0)
  {
    return luaL_error(L, "native UTC clock formatting failed");
  }
#endif
  lua_pushstring(L, value);
  return 1;
}

static const luaL_Reg yaca_native_functions[] = {
  { "abi_version", l_abi_version },
  { "platform_identity", l_platform_identity },
  { "executable_paths", l_executable_paths },
  { "stdio_facts", l_stdio_facts },
  { "workspace_inspect", l_workspace_inspect },
  { "fs_make_directory", l_fs_make_directory },
  { "monotonic_now", l_monotonic_now },
  { "sleep_ms", l_sleep_ms },
  { "utc_now", l_utc_now },
  { "secure_random", l_secure_random },
  { "current_process_id", l_current_process_id },
  { "sha256_start", l_sha256_start },
  { "sha256_update", l_sha256_update },
  { "sha256_finish", l_sha256_finish },
  { "sha256_close", l_sha256_close },
  { "fs_open_read", l_fs_open_read },
  { "fs_create_new", l_fs_create_new },
  { "fs_stat_identity", l_fs_stat_identity },
  { "fs_read", l_fs_read },
  { "fs_write", l_fs_write },
  { "fs_flush_file", l_fs_flush_file },
  { "fs_flush_directory", l_fs_flush_directory },
  { "fs_replace", l_fs_replace },
  { "fs_rename_no_replace", l_fs_rename_no_replace },
  { "fs_delete_verified", l_fs_delete_verified },
  { "fs_close", l_fs_close },
  { "fs_inspect_direct", l_fs_inspect_direct },
  { "fs_walk_direct", l_fs_walk_direct },
  { "fs_open_read_verified", l_fs_open_read_verified },
  { "fs_create_new_verified", l_fs_create_new_verified },
  { "fs_replace_verified", l_fs_replace_verified },
  { "fs_rename_no_replace_verified", l_fs_rename_no_replace_verified },
  { "fs_delete_direct_verified", l_fs_delete_direct_verified },
  { "process_start", l_process_start },
  { "process_poll", l_process_poll },
  { "process_cancel", l_process_cancel },
  { "process_join", l_process_join },
  { "process_close", l_process_close },
  { "terminal_start", l_terminal_start },
  { "terminal_poll", l_terminal_poll },
  { "terminal_cancel", l_terminal_cancel },
  { "terminal_join", l_terminal_join },
  { "terminal_close", l_terminal_close },
  { "terminal_restore", l_terminal_restore },
  { NULL, NULL },
};

static void create_handle_metatable(
  lua_State *L,
  const char *name,
  lua_CFunction garbage_collector)
{
  if (luaL_newmetatable(L, name))
  {
    lua_pushcfunction(L, garbage_collector);
    lua_setfield(L, -2, "__gc");
    lua_pushstring(L, "locked native handle");
    lua_setfield(L, -2, "__metatable");
  }
  lua_pop(L, 1);
}

/*
** Lua module entry point. The release loader resolves this symbol only from an
** allowlisted absolute target path.
*/
LUAMOD_API int luaopen_yaca_native(lua_State *L)
{
  create_handle_metatable(L, YACA_FILE_METATABLE, l_file_gc);
  create_handle_metatable(L, YACA_PROCESS_METATABLE, l_process_gc);
  create_handle_metatable(L, YACA_TERMINAL_METATABLE, l_terminal_gc);
  create_handle_metatable(L, YACA_SHA256_METATABLE, l_sha256_gc);
  luaL_newlib(L, yaca_native_functions);
  return 1;
}
