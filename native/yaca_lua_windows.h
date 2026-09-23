/*
Author: WaterRun
Date: 2026-09-23
File: yaca_lua_windows.h
Description: UTF-8 filenames for the bundled official Lua on Windows XP+.
A build-time platform adapter; Lua's interpreter and VM remain unchanged.
*/

#ifndef YACA_LUA_WINDOWS_H
#define YACA_LUA_WINDOWS_H
#ifdef _WIN32
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <wchar.h>
#include <errno.h>

/* Converts a Lua UTF-8 path to newly allocated UTF-16.
 * @param value const_char* Candidate value being converted or checked.
 * @return WCHAR*|NULL result Caller-owned wide string, or NULL with errno set on failure.
 */
static inline WCHAR *yaca_lua_wide(const char *value)
{
  int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value, -1, NULL, 0);
  WCHAR *wide;
  if (length <= 0 || length > 32768) { errno = EINVAL; return NULL; }
  wide = (WCHAR *)malloc((size_t)length * sizeof(WCHAR));
  if (!wide) { errno = ENOMEM; return NULL; }
  if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value, -1, wide, length))
  { free(wide); errno = EINVAL; return NULL; }
  return wide;
}

/* Opens or reopens a Lua file stream through the wide CRT.
 * @param name const_char* Selected file, module, or resource name.
 * @param mode const_char* Requested terminal or filesystem mode.
 * @param stream FILE* The stream bound to yaca lua open.
 * @param reopen int The reopen bound to yaca lua open.
 * @return FILE*|NULL result Opened stream, or NULL with errno preserved on failure.
 */
static inline FILE *yaca_lua_open(const char *name, const char *mode, FILE *stream, int reopen)
{
  WCHAR *wide = yaca_lua_wide(name);
  WCHAR *wide_mode = yaca_lua_wide(mode);
  FILE *result = NULL;
  int saved_errno;
  if (wide && wide_mode) result = reopen ? _wfreopen(wide, wide_mode, stream) : _wfopen(wide, wide_mode);
  saved_errno = errno;
  free(wide);
  free(wide_mode);
  errno = saved_errno;
  return result;
}

/* Removes a UTF-8 path through the wide CRT.
 * @param path const_char* Filesystem path selected for this operation.
 * @return int result 0 on success, -1 with errno preserved on failure.
 */
static inline int yaca_lua_remove(const char *path)
{
  WCHAR *wide = yaca_lua_wide(path);
  int result, saved_errno;
  if (!wide) return -1;
  result = _wremove(wide);
  saved_errno = errno;
  free(wide);
  errno = saved_errno;
  return result;
}

/* Renames UTF-8 paths through the wide CRT.
 * @param from const_char* The from bound to yaca lua rename.
 * @param to const_char* The to bound to yaca lua rename.
 * @return int result 0 on success, -1 with errno preserved on failure.
 */
static inline int yaca_lua_rename(const char *from, const char *to)
{
  WCHAR *source = yaca_lua_wide(from), *destination = yaca_lua_wide(to);
  int result = -1, saved_errno;
  if (source && destination) result = _wrename(source, destination);
  saved_errno = errno;
  free(source);
  free(destination);
  errno = saved_errno;
  return result;
}

/* Starts a command pipe through the wide CRT.
 * @param command const_char* Executable command or argument vector to launch.
 * @param mode const_char* Requested terminal or filesystem mode.
 * @return FILE*|NULL result Open command pipe, or NULL with errno preserved on failure.
 */
static inline FILE *yaca_lua_popen(const char *command, const char *mode)
{
  WCHAR *wide = yaca_lua_wide(command), *wide_mode = yaca_lua_wide(mode);
  FILE *result = NULL;
  int saved_errno;
  if (wide && wide_mode) result = _wpopen(wide, wide_mode);
  saved_errno = errno;
  free(wide);
  free(wide_mode);
  errno = saved_errno;
  return result;
}

/* Runs a UTF-8 command through the wide CRT.
 * @param command const_char* Executable command or argument vector to launch.
 * @return int result CRT command status, or -1 with errno set on conversion failure.
 */
static inline int yaca_lua_system(const char *command)
{
  WCHAR *wide;
  int result, saved_errno;
  if (!command) return _wsystem(NULL);
  wide = yaca_lua_wide(command);
  if (!wide) return -1;
  result = _wsystem(wide);
  saved_errno = errno;
  free(wide);
  errno = saved_errno;
  return result;
}

/* Reads a Win32 environment value into a reusable UTF-8 buffer.
 * @param name const_char* Selected file, module, or resource name.
 * @return char*|NULL result Borrowed UTF-8 value valid until the next lookup, or NULL on failure.
 */
static inline char *yaca_lua_getenv(const char *name)
{
  static char *value;
  WCHAR *key = yaca_lua_wide(name);
  WCHAR wide[32768];
  DWORD length;
  int bytes;
  free(value);
  value = NULL;
  if (!key) return NULL;
  SetLastError(ERROR_SUCCESS);
  length = GetEnvironmentVariableW(key, wide, 32768);
  free(key);
  if (length >= 32768 || (length == 0 && GetLastError() != ERROR_SUCCESS)) return NULL;
  if (length == 0) wide[0] = L'\0';
  bytes = WideCharToMultiByte(CP_UTF8, 0, wide, -1, NULL, 0, NULL, NULL);
  if (bytes <= 0) return NULL;
  value = (char *)malloc((size_t)bytes);
  if (value && !WideCharToMultiByte(CP_UTF8, 0, wide, -1, value, bytes, NULL, NULL))
  { free(value); value = NULL; }
  return value;
}

/* Writes the loaded module path as UTF-8 into out.
 * @param module HMODULE The module bound to yaca lua module.
 * @param out char* Caller-owned output pointer or buffer.
 * @param capacity DWORD Maximum elements or bytes the output buffer can hold.
 * @return DWORD result Output byte count excluding NUL, or 0 on Win32 or conversion failure.
 */
static inline DWORD yaca_lua_module(HMODULE module, char *out, DWORD capacity)
{
  WCHAR path[32768];
  DWORD length = GetModuleFileNameW(module, path, 32768);
  int bytes;
  if (!length || length >= 32768) return 0;
  bytes = WideCharToMultiByte(CP_UTF8, 0, path, -1, NULL, 0, NULL, NULL);
  if (bytes <= 0 || (DWORD)bytes > capacity)
  { SetLastError(ERROR_INSUFFICIENT_BUFFER); return 0; }
  if (!WideCharToMultiByte(CP_UTF8, 0, path, -1, out, bytes, NULL, NULL)) return 0;
  return (DWORD)bytes - 1;
}

/* Loads a DLL from a UTF-8 path through LoadLibraryExW.
 * @param path const_char* Filesystem path selected for this operation.
 * @param file HANDLE The file bound to yaca lua loadlib.
 * @param flags DWORD Operating-system mode or control flags.
 * @return HMODULE|NULL result Module handle owned by caller, or NULL with Win32 error state on failure.
 */
static inline HMODULE yaca_lua_loadlib(const char *path, HANDLE file, DWORD flags)
{
  WCHAR *wide = yaca_lua_wide(path);
  HMODULE result;
  DWORD error;
  if (!wide) { SetLastError(ERROR_NO_UNICODE_TRANSLATION); return NULL; }
  result = LoadLibraryExW(wide, file, flags);
  error = GetLastError();
  free(wide);
  SetLastError(error);
  return result;
}

/* Routes Lua's fopen calls through the wide CRT adapter.
 * @param name const_char* UTF-8 file path to open.
 * @param mode const_char* CRT file access mode.
 * @return FILE*|NULL result Opened stream, or NULL with errno set on failure.
 */
#define fopen(name, mode) yaca_lua_open(name, mode, NULL, 0)
/* Routes Lua's freopen calls through the wide CRT adapter.
 * @param name const_char* UTF-8 replacement file path.
 * @param mode const_char* CRT file access mode.
 * @param file FILE* Existing stream to reopen.
 * @return FILE*|NULL result Reopened stream, or NULL with errno set on failure.
 */
#define freopen(name, mode, file) yaca_lua_open(name, mode, file, 1)
#define remove yaca_lua_remove
#define rename yaca_lua_rename
#define _popen yaca_lua_popen
#define system yaca_lua_system
#define getenv yaca_lua_getenv
#define GetModuleFileNameA yaca_lua_module
#define LoadLibraryExA yaca_lua_loadlib
#endif
#endif
