/*
Author: WaterRun
Date: 2026-09-23
File: yaca_onefile_windows.h
Description: UTF-8 path adapters for the locked Windows onefile extractor.
Included after the platform headers. No ANSI path conversion is permitted.
*/

#ifndef YACA_ONEFILE_WINDOWS_H
#define YACA_ONEFILE_WINDOWS_H

/* Converts an extractor UTF-8 path to a newly allocated UTF-16 string.
 * @param text const_char* The text bound to yaca onefile wide.
 * @return WCHAR*|NULL result Caller-owned UTF-16 path, or NULL on invalid input or allocation failure.
 */
static WCHAR *yaca_onefile_wide(const char *text)
{
  int length;
  WCHAR *wide;
  if (text == NULL) return NULL;
  length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, -1, NULL, 0);
  if (length <= 0 || length > 32768) return NULL;
  wide = (WCHAR *)malloc((size_t)length * sizeof(WCHAR));
  if (wide == NULL) { SetLastError(ERROR_NOT_ENOUGH_MEMORY); return NULL; }
  if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, -1, wide, length))
  { free(wide); return NULL; }
  return wide;
}

/* Converts a UTF-16 path into the caller-provided UTF-8 buffer.
 * @param wide const_WCHAR* Windows wide-character input or output buffer.
 * @param out char* Caller-owned output pointer or buffer.
 * @param capacity DWORD Maximum elements or bytes the output buffer can hold.
 * @return DWORD result UTF-8 byte count excluding NUL, or 0 on conversion or capacity failure.
 */
static DWORD yaca_onefile_utf8(const WCHAR *wide, char *out, DWORD capacity)
{
  int length = WideCharToMultiByte(CP_UTF8, 0, wide, -1, NULL, 0, NULL, NULL);
  if (length <= 0 || (DWORD)length > capacity)
  { SetLastError(ERROR_INSUFFICIENT_BUFFER); return 0; }
  if (!WideCharToMultiByte(CP_UTF8, 0, wide, -1, out, length, NULL, NULL)) return 0;
  return (DWORD)length - 1;
}

/* Extracted files contain only the embedded public program. FAT volumes have
** no persistent ACLs: rely there on the extractor's exact byte comparison and
** retained handles denying write/delete, not a fabricated private owner/DACL.
** Keep ordinary ACL hardening for NTFS and every unrecognized filesystem. */
/* Checks whether a pinned file belongs to a removable or fixed FAT volume without persistent ACLs.
 * @param handle HANDLE Operating-system handle being inspected or closed.
 * @param path const_char* Filesystem path selected for this operation.
 * @return int result 1 for an admitted FAT, FAT32, or exFAT volume, otherwise 0.
 */
static int yaca_onefile_public_fat_volume(HANDLE handle, const char *path)
{
  WCHAR *wide = yaca_onefile_wide(path);
  WCHAR root[32768], filesystem[32];
  BY_HANDLE_FILE_INFORMATION information;
  DWORD serial, flags;
  UINT type;
  int admitted = 0;
  if (wide == NULL) return 0;
  if (!GetFileInformationByHandle(handle, &information)
      || !GetVolumePathNameW(wide, root, 32768)) goto done;
  type = GetDriveTypeW(root);
  if ((type != DRIVE_FIXED && type != DRIVE_REMOVABLE)
      || !GetVolumeInformationW(root, NULL, 0, &serial, NULL, &flags,
        filesystem, 32)
      || serial != information.dwVolumeSerialNumber
      || (flags & FILE_PERSISTENT_ACLS) != 0) goto done;
  admitted = wcscmp(filesystem, L"FAT") == 0
    || wcscmp(filesystem, L"FAT32") == 0 || wcscmp(filesystem, L"exFAT") == 0;
done:
  free(wide);
  return admitted;
}

/* Creates a directory through the wide Win32 API.
 * @param path const_char* Filesystem path selected for this operation.
 * @return int result 0 on success, -1 on failure with errno set.
 */
static int yaca_onefile_mkdir(const char *path)
{
  WCHAR *wide = yaca_onefile_wide(path);
  BOOL ok;
  DWORD error;
  if (wide == NULL) { errno = EINVAL; return -1; }
  ok = CreateDirectoryW(wide, NULL);
  error = GetLastError();
  free(wide);
  if (ok) return 0;
  errno = error == ERROR_ALREADY_EXISTS ? EEXIST : EACCES;
  SetLastError(error);
  return -1;
}

/* Reads file attributes through the wide Win32 API.
 * @param path const_char* Filesystem path selected for this operation.
 * @return DWORD result Win32 file attributes, or INVALID_FILE_ATTRIBUTES on failure.
 */
static DWORD yaca_onefile_attributes(const char *path)
{
  WCHAR *wide = yaca_onefile_wide(path);
  DWORD attributes, error;
  if (wide == NULL) return INVALID_FILE_ATTRIBUTES;
  attributes = GetFileAttributesW(wide);
  error = GetLastError();
  free(wide);
  SetLastError(error);
  return attributes;
}

/* Opens a UTF-8 path through CreateFileW while preserving Win32 error state.
 * @param path const_char* Filesystem path selected for this operation.
 * @param access DWORD Requested Win32 handle access rights.
 * @param share DWORD The share bound to yaca onefile file.
 * @param security LPSECURITY_ATTRIBUTES The security bound to yaca onefile file.
 * @param disposition DWORD The disposition bound to yaca onefile file.
 * @param flags DWORD Operating-system mode or control flags.
 * @param template_file HANDLE The template file bound to yaca onefile file.
 * @return HANDLE result Caller-owned file handle, or INVALID_HANDLE_VALUE on failure.
 */
static HANDLE yaca_onefile_file(const char *path, DWORD access, DWORD share,
  LPSECURITY_ATTRIBUTES security, DWORD disposition, DWORD flags, HANDLE template_file)
{
  WCHAR *wide = yaca_onefile_wide(path);
  HANDLE file;
  DWORD error;
  if (wide == NULL) return INVALID_HANDLE_VALUE;
  file = CreateFileW(wide, access, share, security, disposition, flags, template_file);
  error = GetLastError();
  free(wide);
  SetLastError(error);
  return file;
}

/* Computes onefile remove for the native port.
 * @param path const_char* Filesystem path selected for this operation.
 * @param directory int The directory bound to yaca onefile remove.
 * @return BOOL result Operating-system success or comparison result.
 */
static BOOL yaca_onefile_remove(const char *path, int directory)
{
  WCHAR *wide = yaca_onefile_wide(path);
  BOOL ok;
  DWORD error;
  if (wide == NULL) return FALSE;
  ok = directory ? RemoveDirectoryW(wide) : DeleteFileW(wide);
  error = GetLastError();
  free(wide);
  SetLastError(error);
  return ok;
}

/* Computes onefile move for the native port.
 * @param from const_char* The from bound to yaca onefile move.
 * @param to const_char* The to bound to yaca onefile move.
 * @param flags DWORD Operating-system mode or control flags.
 * @return BOOL result Operating-system success or comparison result.
 */
static BOOL yaca_onefile_move(const char *from, const char *to, DWORD flags)
{
  WCHAR *source = yaca_onefile_wide(from);
  WCHAR *destination = yaca_onefile_wide(to);
  BOOL ok = FALSE;
  DWORD error;
  if (source && destination) ok = MoveFileExW(source, destination, flags);
  error = GetLastError();
  free(source);
  free(destination);
  SetLastError(error);
  return ok;
}

/* Only TEMP/TMP are requested by the Windows extractor. Keep one owned result
** until the next lookup, matching the caller's borrowed environment pointer. */
/* Reads a Win32 environment variable as UTF-8.
 * @param name const_char* Selected file, module, or resource name.
 * @return const_char*|NULL result Borrowed UTF-8 value valid until the next lookup, or NULL on failure.
 */
static const char *yaca_onefile_getenv(const char *name)
{
  static char *result;
  WCHAR wide[32768];
  WCHAR *key = yaca_onefile_wide(name);
  DWORD count;
  int bytes;
  free(result);
  result = NULL;
  if (key == NULL) return NULL;
  count = GetEnvironmentVariableW(key, wide, 32768);
  free(key);
  if (count == 0 || count >= 32768) return NULL;
  bytes = WideCharToMultiByte(CP_UTF8, 0, wide, -1, NULL, 0, NULL, NULL);
  if (bytes <= 0) return NULL;
  result = (char *)malloc((size_t)bytes);
  if (result && !yaca_onefile_utf8(wide, result, (DWORD)bytes))
  { free(result); result = NULL; }
  return result;
}

/* Resolves a UTF-8 path to an absolute UTF-8 spelling.
 * @param path const_char* Filesystem path selected for this operation.
 * @param capacity DWORD Maximum elements or bytes the output buffer can hold.
 * @param out char* Caller-owned output pointer or buffer.
 * @param leaf char** The leaf bound to yaca onefile fullpath.
 * @return DWORD result Output byte count excluding NUL, or 0 on invalid leaf, conversion, or capacity failure.
 */
static DWORD yaca_onefile_fullpath(const char *path, DWORD capacity, char *out, char **leaf)
{
  WCHAR *wide = yaca_onefile_wide(path);
  WCHAR resolved[32768];
  DWORD length;
  if (leaf != NULL || wide == NULL) return 0;
  length = GetFullPathNameW(wide, 32768, resolved, NULL);
  free(wide);
  if (length == 0 || length >= 32768) return 0;
  return yaca_onefile_utf8(resolved, out, capacity);
}

/* Writes the current module path as UTF-8 into out.
 * @param module HMODULE The module bound to yaca onefile module.
 * @param out char* Caller-owned output pointer or buffer.
 * @param capacity DWORD Maximum elements or bytes the output buffer can hold.
 * @return DWORD result Output byte count excluding NUL, or 0 on Win32 or conversion failure.
 */
static DWORD yaca_onefile_module(HMODULE module, char *out, DWORD capacity)
{
  WCHAR path[32768];
  DWORD length = GetModuleFileNameW(module, path, 32768);
  if (length == 0 || length >= 32768) return 0;
  return yaca_onefile_utf8(path, out, capacity);
}

/* Computes onefile process for the native port.
 * @param path const_char* Filesystem path selected for this operation.
 * @param command char* Executable command or argument vector to launch.
 * @param process_security LPSECURITY_ATTRIBUTES The process security bound to yaca onefile process.
 * @param thread_security LPSECURITY_ATTRIBUTES The thread security bound to yaca onefile process.
 * @param inherit BOOL The inherit bound to yaca onefile process.
 * @param flags DWORD Operating-system mode or control flags.
 * @param environment LPVOID Child-process environment being constructed or released.
 * @param cwd const_char* Working directory selected for the child process.
 * @param startup LPSTARTUPINFOA The startup bound to yaca onefile process.
 * @param information LPPROCESS_INFORMATION Operating-system stat or file-information record.
 * @return BOOL result Operating-system success or comparison result.
 */
static BOOL yaca_onefile_process(const char *path, char *command,
  LPSECURITY_ATTRIBUTES process_security, LPSECURITY_ATTRIBUTES thread_security,
  BOOL inherit, DWORD flags, LPVOID environment, const char *cwd,
  LPSTARTUPINFOA startup, LPPROCESS_INFORMATION information)
{
  WCHAR *wide_path = yaca_onefile_wide(path);
  WCHAR *wide_command = yaca_onefile_wide(command);
  STARTUPINFOW wide_startup;
  BOOL ok = FALSE;
  DWORD error;
  /* The locked extractor uses only cb and otherwise-zero STARTUPINFO. Reject
  ** new narrow string fields if the upstream call contract ever changes. */
  if (environment != NULL || cwd != NULL || startup->dwFlags != 0
      || startup->lpReserved || startup->lpDesktop || startup->lpTitle)
  { SetLastError(ERROR_INVALID_PARAMETER); goto done; }
  ZeroMemory(&wide_startup, sizeof(wide_startup));
  wide_startup.cb = sizeof(wide_startup);
  if (wide_path && wide_command)
    ok = CreateProcessW(wide_path, wide_command, process_security, thread_security,
      inherit, flags, NULL, NULL, &wide_startup, information);
done:
  error = GetLastError();
  free(wide_path);
  free(wide_command);
  SetLastError(error);
  return ok;
}

#define _mkdir yaca_onefile_mkdir
#define GetFileAttributesA yaca_onefile_attributes
#define CreateFileA yaca_onefile_file
/* Routes narrow directory removal through the UTF-8 aware wide adapter.
 * @param path const_char* UTF-8 directory path to remove.
 * @return BOOL result Win32 success flag from yaca_onefile_remove.
 */
#define RemoveDirectoryA(path) yaca_onefile_remove(path, 1)
/* Routes narrow file deletion through the UTF-8 aware wide adapter.
 * @param path const_char* UTF-8 file path to remove.
 * @return BOOL result Win32 success flag from yaca_onefile_remove.
 */
#define DeleteFileA(path) yaca_onefile_remove(path, 0)
#define MoveFileExA yaca_onefile_move
#define getenv yaca_onefile_getenv
#define GetFullPathNameA yaca_onefile_fullpath
#define GetModuleFileNameA yaca_onefile_module
#define CreateProcessA yaca_onefile_process
#define main yaca_extractor_main
#endif
