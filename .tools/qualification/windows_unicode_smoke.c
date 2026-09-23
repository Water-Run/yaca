/*
Author: WaterRun
Date: 2026-09-23
File: windows_unicode_smoke.c
Description: Relocation/argv/file checks through the real onefile executable. XP APIs.
*/

/* Relocation/argv/file checks through the real onefile executable. XP APIs. */
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0501
#endif
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

/* Stops the smoke test when a Win32 operation fails.
 * @param ok int The ok bound to check.
 * @param operation const_char* The operation bound to check.
 * @return void No value; exits the smoke executable on failure.
 */
static void check(int ok, const char *operation)
{
  if (!ok)
  {
    fprintf(stderr, "unicode-smoke: %s failed (Windows error %lu)\n", operation, GetLastError());
    exit(1);
  }
}

/* Joins a Windows root and leaf into a wide destination buffer.
 * @param out WCHAR* Caller-owned output pointer or buffer.
 * @param root const_WCHAR* Admitted workspace or filesystem traversal root.
 * @param leaf const_WCHAR* The leaf bound to path join.
 * @return void No value; writes the bounded joined path into out.
 */
static void path_join(WCHAR *out, const WCHAR *root, const WCHAR *leaf)
{
  check(wcslen(root) + wcslen(leaf) + 2 < 4096, "path bound");
  wcscpy(out, root);
  wcscat(out, L"\\");
  wcscat(out, leaf);
}

/* Writes the selected bytes to a Windows smoke-test file.
 * @param path const_WCHAR* Filesystem path selected for this operation.
 * @param bytes const_char* Raw byte buffer supplied to the native operation.
 * @return void No value; creates and fills the named smoke-test file or exits.
 */
static void write_file(const WCHAR *path, const char *bytes)
{
  HANDLE file = CreateFileW(path, GENERIC_WRITE, 0, NULL, CREATE_NEW, 0, NULL);
  DWORD written, size = (DWORD)strlen(bytes);
  check(file != INVALID_HANDLE_VALUE, "create script");
  check(WriteFile(file, bytes, size, &written, NULL) && written == size, "write script");
  check(CloseHandle(file), "close script");
}

/* Runs the selected Windows child and checks its output marker.
 * @param exe const_WCHAR* The exe bound to run.
 * @param cwd const_WCHAR* Working directory selected for the child process.
 * @param arguments const_WCHAR* Child-process argument vector or owned argument storage.
 * @param log const_WCHAR* The log bound to run.
 * @param marker const_char* The marker bound to run.
 * @return void No value; checks the child exit and output marker, exiting on failure.
 */
static void run(const WCHAR *exe, const WCHAR *cwd, const WCHAR *arguments,
  const WCHAR *log, const char *marker)
{
  SECURITY_ATTRIBUTES security = { sizeof(security), NULL, TRUE };
  STARTUPINFOW startup;
  PROCESS_INFORMATION child;
  HANDLE output = CreateFileW(log, GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ,
    &security, CREATE_NEW, 0, NULL);
  HANDLE input = CreateFileW(L"NUL", GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE,
    &security, OPEN_EXISTING, 0, NULL);
  WCHAR command[8192];
  DWORD code, count;
  char bytes[8192];
  check(output != INVALID_HANDLE_VALUE && input != INVALID_HANDLE_VALUE, "stdio files");
  check(_snwprintf(command, 8192, L"\"%ls\" %ls", exe, arguments) > 0, "command");
  ZeroMemory(&startup, sizeof(startup));
  ZeroMemory(&child, sizeof(child));
  startup.cb = sizeof(startup);
  startup.dwFlags = STARTF_USESTDHANDLES;
  startup.hStdInput = input;
  startup.hStdOutput = startup.hStdError = output;
  check(CreateProcessW(exe, command, NULL, NULL, TRUE, CREATE_NO_WINDOW, NULL,
    cwd, &startup, &child), "start executable");
  CloseHandle(child.hThread);
  if (WaitForSingleObject(child.hProcess, 60000) != WAIT_OBJECT_0)
  {
    TerminateProcess(child.hProcess, 124);
    WaitForSingleObject(child.hProcess, 5000);
    check(0, "bounded completion");
  }
  check(GetExitCodeProcess(child.hProcess, &code), "exit status");
  CloseHandle(child.hProcess);
  CloseHandle(input);
  check(SetFilePointer(output, 0, NULL, FILE_BEGIN) != INVALID_SET_FILE_POINTER, "log seek");
  check(ReadFile(output, bytes, sizeof(bytes) - 1, &count, NULL), "log read");
  bytes[count] = '\0';
  CloseHandle(output);
  if (code != 0 || strstr(bytes, marker) == NULL)
  {
    fprintf(stderr, "unicode-smoke: exit=%lu output=%s\n", code, bytes);
    exit(1);
  }
}

/* Runs the windows unicode smoke executable and reports its exit status.
 * @param argc int Number of command-line arguments supplied by the host.
 * @param argv WCHAR** Host command-line argument vector.
 * @return int result Process exit status, zero only when all smoke checks pass.
 */
int wmain(int argc, WCHAR **argv)
{
  WCHAR source[4096], base[4096], root[4096], temporary[4096], exe[4096], file[4096];
  WCHAR temporary_leaf[57];
  DWORD length;
  static const char script[] =
    "assert(_VERSION == 'Lua 5.5')\n"
    "assert(arg[1] == '中文🙂' and arg[2] == '')\n"
    "local p, q = '文件🙂.bin', '改名🙂.bin'\n"
    "local f = assert(io.open(p, 'wb')); assert(f:write('A\\0B')); assert(f:close())\n"
    "assert(os.rename(p, q)); f = assert(io.open(q, 'rb'))\n"
    "assert(f:read('a') == 'A\\0B'); assert(f:close()); assert(os.remove(q))\n"
    "f = assert(io.open('模块🙂.lua', 'wb')); assert(f:write('return 42')); assert(f:close())\n"
    "assert(assert(loadfile('模块🙂.lua'))() == 42); assert(os.remove('模块🙂.lua'))\n"
    "assert(os.execute('echo ok > \"命令.txt\"')); f = assert(io.open('命令.txt', 'rb'))\n"
    "assert(f:read('a'):match('ok')); assert(f:close()); assert(os.remove('命令.txt'))\n"
    "print('unicode-lua=PASS')\n";
  check(argc == 3, "usage: windows_unicode_smoke.exe YACA EXISTING_SCRATCH_PARENT");
  length = GetFullPathNameW(argv[1], 4096, source, NULL);
  check(length > 0 && length < 4096, "source path");
  length = GetFullPathNameW(argv[2], 4096, base, NULL);
  check(length > 0 && length < 4096, "scratch path");
  path_join(root, base, L"\u4fbf\u643a \xD83D\xDE42");
  check(CreateDirectoryW(root, NULL), "new isolated Unicode directory");
  /* Stay below the old 260 UTF-16 path limit, while making the embedded
  ** interpreter's UTF-8 module path exceed 260 bytes. */
  for (int index = 0; index < 56; index++) temporary_leaf[index] = 0x4e34;
  temporary_leaf[56] = 0;
  path_join(temporary, root, temporary_leaf);
  check(CreateDirectoryW(temporary, NULL), "Unicode temporary directory");
  check(SetEnvironmentVariableW(L"TEMP", temporary) && SetEnvironmentVariableW(L"TMP", temporary),
    "child temporary environment");
  path_join(exe, root, L"yaca.exe");
  check(CopyFileW(source, exe, TRUE), "relocate executable");
  path_join(file, root, L"version.log");
  run(exe, root, L"--version", file, "yaca 0.1.0");
  path_join(file, root, L"\u811a\u672c.lua");
  write_file(file, script);
  path_join(file, root, L"lua.log");
  run(exe, root, L"--lua -E \"\u811a\u672c.lua\" \"\u4e2d\u6587\xD83D\xDE42\" \"\"",
    file, "unicode-lua=PASS");
  puts("windows-unicode=PASS installation=temp=script=file=argv=non-BMP");
  return 0;
}
