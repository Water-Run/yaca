/*
Author: WaterRun
Date: 2026-09-23
File: windows_filesystem_identity_smoke.c
Description: Check how held Windows handles follow rename/replace on the actual volume.
*/

/* Check how held Windows handles follow rename/replace on the actual volume.
** All paths are newly created beneath a caller-owned empty scratch directory. */
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0501
#endif
#include <windows.h>
#include <stdio.h>
#include <wchar.h>

/* Creates a file with exact bytes and reopens an attribute-only identity handle.
 * @param path const_WCHAR* Filesystem path selected for this operation.
 * @param bytes const_char* Raw byte buffer supplied to the native operation.
 * @param size DWORD The size bound to create.
 * @return HANDLE result Caller-owned attribute handle, or INVALID_HANDLE_VALUE on failure.
 */
static HANDLE create(const WCHAR *path, const char *bytes, DWORD size)
{
  DWORD written;
  HANDLE h = CreateFileW(path, GENERIC_READ | GENERIC_WRITE,
    FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, CREATE_NEW, 0, NULL);
  if (h == INVALID_HANDLE_VALUE || !WriteFile(h, bytes, size, &written, NULL)
      || written != size || !FlushFileBuffers(h)) return INVALID_HANDLE_VALUE;
  CloseHandle(h);
  /* ReplaceFile opens its candidate with no sharing. Attribute-only handles
  ** do not request data access; test whether these can anchor object identity. */
  return CreateFileW(path, FILE_READ_ATTRIBUTES,
    FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_EXISTING, 0, NULL);
}

/* Checks whether a file handle still names the selected path.
 * @param h HANDLE The h bound to same path.
 * @param path const_WCHAR* Filesystem path selected for this operation.
 * @return int result 1 if the handle and path still identify the same file, otherwise 0.
 */
static int same_path(HANDLE h, const WCHAR *path)
{
  BY_HANDLE_FILE_INFORMATION before, current;
  HANDLE other = CreateFileW(path, GENERIC_READ,
    FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_EXISTING, 0, NULL);
  int ok = other != INVALID_HANDLE_VALUE && GetFileInformationByHandle(h, &before)
    && GetFileInformationByHandle(other, &current)
    && before.dwVolumeSerialNumber == current.dwVolumeSerialNumber
    && before.nFileIndexHigh == current.nFileIndexHigh
    && before.nFileIndexLow == current.nFileIndexLow;
  if (other != INVALID_HANDLE_VALUE) CloseHandle(other);
  return ok;
}

/* Prints stable file identity fields for the Windows smoke test.
 * @param label const_char* The label bound to identity.
 * @param h HANDLE The h bound to identity.
 * @return void No value; writes file identity or Win32 error fields to stdout.
 */
static void identity(const char *label, HANDLE h)
{
  BY_HANDLE_FILE_INFORMATION i;
  if (GetFileInformationByHandle(h, &i))
    printf("%s volume=%08lx id=%08lx%08lx size=%lu\n", label,
      i.dwVolumeSerialNumber, i.nFileIndexHigh, i.nFileIndexLow, i.nFileSizeLow);
  else printf("%s error=%lu\n", label, GetLastError());
}

/* Runs the windows filesystem identity smoke executable and reports its exit status.
 * @param argc int Number of command-line arguments supplied by the host.
 * @param argv WCHAR** Host command-line argument vector.
 * @return int result Process exit status, zero only when all smoke checks pass.
 */
int wmain(int argc, WCHAR **argv)
{
  WCHAR old[4096], replacement[4096], backup[4096], renamed[4096];
  HANDLE a, b;
  int ok;
  DWORD error;
  if (argc != 2 || wcslen(argv[1]) > 4000) return 64;
  _snwprintf(old, 4096, L"%ls\\old.txt", argv[1]);
  _snwprintf(replacement, 4096, L"%ls\\new.txt", argv[1]);
  _snwprintf(backup, 4096, L"%ls\\backup.txt", argv[1]);
  _snwprintf(renamed, 4096, L"%ls\\renamed-with-long-name.txt", argv[1]);
  a = create(old, "old", 3);
  b = create(replacement, "new contents", 12);
  if (a == INVALID_HANDLE_VALUE || b == INVALID_HANDLE_VALUE) return 1;
  identity("old-before", a); identity("new-before", b);
  SetLastError(0);
  ok = ReplaceFileW(old, replacement, backup, 0, NULL, NULL);
  error = GetLastError();
  printf("replace-with-held-handles=%d error=%lu\n", ok, error);
  identity("old-after", a); identity("new-after", b);
  if (ok) {
    ok = same_path(a, backup) && same_path(b, old);
    printf("replace-held-identity=%s\n", ok ? "PASS" : "FAIL");
    if (ok) {
      SetLastError(0);
      ok = MoveFileExW(old, renamed, MOVEFILE_WRITE_THROUGH);
      error = GetLastError();
      printf("rename-with-held-handle=%d error=%lu\n", ok, error);
      identity("new-renamed", b);
      ok = ok && same_path(b, renamed);
      printf("rename-held-identity=%s\n", ok ? "PASS" : "FAIL");
    }
  }
  CloseHandle(a); CloseHandle(b);
  return ok ? 0 : 1;
}
