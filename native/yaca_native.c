/*
** File: yaca_native.c
** Date: 2026-08-29
** Author: WaterRun
** Description: Portable narrow native ports for filesystem, process, terminal, clocks, and SHA-256.
*/

#if !defined(_WIN32) && !defined(_POSIX_C_SOURCE)
#define _POSIX_C_SOURCE 200809L
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

#else

#include <fcntl.h>
#include <signal.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>

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

typedef struct yaca_terminal
{
#if defined(_WIN32)
  HANDLE input;
  DWORD original_mode;
  DWORD input_type;
  WCHAR pending_high_surrogate;
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

static int push_windows_failure(lua_State *L, DWORD value, const char *message)
{
  return push_failure(L, windows_error_code(value), message);
}

#endif

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
    "%lld",
    (long long)information->st_mtime);
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
      if (strcmp(mode, "cooked") != 0)
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

static int l_utc_now(lua_State *L)
{
  char value[64];

#if defined(_WIN32)
  SYSTEMTIME current;

  GetSystemTime(&current);
  snprintf(
    value,
    sizeof(value),
    "%04u-%02u-%02uT%02u:%02u:%02u.%03uZ",
    (unsigned int)current.wYear,
    (unsigned int)current.wMonth,
    (unsigned int)current.wDay,
    (unsigned int)current.wHour,
    (unsigned int)current.wMinute,
    (unsigned int)current.wSecond,
    (unsigned int)current.wMilliseconds);
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
  { "monotonic_now", l_monotonic_now },
  { "utc_now", l_utc_now },
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
