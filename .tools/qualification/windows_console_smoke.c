/*
Author: WaterRun
Date: 2026-09-23
File: windows_console_smoke.c
Description: Verify actual console characters at an incompatible OEM code page.
*/

/* Verify actual console characters at an incompatible OEM code page.
** The probe creates and destroys its own console; evidence goes to a file. */
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0501
#endif
#include <windows.h>
#include <stdio.h>
#include <wchar.h>
#include "lua.h"
#include "lauxlib.h"

/* Optional Vista API used by this probe only. Raster-font consoles discard
** characters outside the selected OEM page even through WriteConsoleW. */
/* @struct probe_font_info Win32 console font shape used by the compatibility probe.
 * @field size ULONG Byte size required by SetCurrentConsoleFontEx.
 * @field number DWORD Index of the selected console font.
 * @field dimensions COORD Requested glyph-cell dimensions.
 * @field family UINT Font family flags.
 * @field weight UINT Font weight requested for the console.
 * @field face WCHAR[32] Null-terminated font face name.
 */
typedef struct probe_font_info {
  ULONG size; DWORD number; COORD dimensions; UINT family; UINT weight; WCHAR face[32];
} probe_font_info;
/* Sets a console font through an optional Win32 entry point.
 * @callback probe_set_font Optional console-font setter loaded for the smoke probe.
 * @param arg1 HANDLE Console output handle whose font is set.
 * @param arg2 BOOL Whether the maximum window setting is requested.
 * @param arg3 probe_font_info* Caller-owned font settings structure.
 * @return BOOL changed Whether the console accepted the font change.
 */
typedef BOOL (WINAPI *probe_set_font)(HANDLE, BOOL, probe_font_info *);

/* Runs the windows console smoke executable and reports its exit status.
 * @param argc int Number of command-line arguments supplied by the host.
 * @param argv WCHAR** Host command-line argument vector.
 * @return int result Process exit status, zero only when all smoke checks pass.
 */
int wmain(int argc, WCHAR **argv)
{
  HMODULE module;
  lua_CFunction opener;
  lua_State *L;
  FILE *log;
  HANDLE output = INVALID_HANDLE_VALUE;
  COORD origin = { 0, 0 };
  CONSOLE_SCREEN_BUFFER_INFO screen;
  WCHAR text[16];
  DWORD count;
  int found_first = 0, found_second = 0, ok = 0, native_page;
  /* @struct symbol Interprets the loaded native module symbol as a Lua opener.
   * @field generic FARPROC Untyped GetProcAddress result.
   * @field function lua_CFunction Typed luaopen_yaca_native function pointer.
   */
  union { FARPROC generic; lua_CFunction function; } symbol;
  if (argc != 3 && (argc != 4 || wcscmp(argv[3], L"native") != 0)) return 64;
  native_page = argc == 4;
  log = _wfopen(argv[2], L"wb");
  if (log == NULL) return 1;
  module = LoadLibraryW(argv[1]);
  if (module == NULL) { fprintf(log, "load failed=%lu\n", GetLastError()); fclose(log); return 1; }
  symbol.generic = GetProcAddress(module, "luaopen_yaca_native");
  opener = symbol.function;
  if (opener == NULL) { fclose(log); FreeLibrary(module); return 1; }
  L = luaL_newstate();
  if (L == NULL) { fclose(log); FreeLibrary(module); return 1; }
  FreeConsole();
  if (!AllocConsole()) { fprintf(log, "console failed=%lu\n", GetLastError()); goto done; }
  /* SSH starts us with redirected standard handles; AllocConsole does not
  ** replace those when STARTF_USESTDHANDLES was used by the launcher. */
  output = CreateFileW(L"CONOUT$", GENERIC_READ | GENERIC_WRITE,
    FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, 0, NULL);
  if (output == INVALID_HANDLE_VALUE || !SetStdHandle(STD_OUTPUT_HANDLE, output)) goto done;
  {
    /* @struct setter Interprets an optional console-font symbol as its Win32 signature.
     * @field generic FARPROC Untyped GetProcAddress result.
     * @field function probe_set_font Typed SetCurrentConsoleFontEx function pointer.
     */
    union { FARPROC generic; probe_set_font function; } setter;
    probe_font_info font;
    setter.generic = GetProcAddress(GetModuleHandleW(L"kernel32.dll"), "SetCurrentConsoleFontEx");
    if (!native_page && setter.function != NULL)
    {
      ZeroMemory(&font, sizeof(font)); font.size = sizeof(font);
      font.dimensions.Y = 16; font.weight = 400;
      wcscpy(font.face, L"Lucida Console");
      if (!setter.function(output, FALSE, &font)) goto done;
    }
  }
  if ((!native_page && !SetConsoleOutputCP(437)) || !SetConsoleCursorPosition(output, origin)) goto done;
  fprintf(log, "code_page=%u\n", GetConsoleOutputCP());
  luaL_requiref(L, "native", opener, 0);
  lua_getfield(L, -1, "console_write");
  lua_pushliteral(L, "stdout");
  lua_pushliteral(L, "中文\nX");
  if (lua_pcall(L, 2, 2, 0) != LUA_OK || !lua_toboolean(L, -2))
  { fprintf(log, "console-write failed\n"); goto done; }
  if (!GetConsoleScreenBufferInfo(output, &screen)) goto done;
  fprintf(log, "cursor=%d,%d\n", screen.dwCursorPosition.X, screen.dwCursorPosition.Y);
  if (screen.dwCursorPosition.X != 1 || screen.dwCursorPosition.Y != 1) goto done;
  if (!ReadConsoleOutputCharacterW(output, text, 16, origin, &count)) goto done;
  for (DWORD index = 0; index < count; index++)
  {
    fprintf(log, "%04x ", text[index]);
    if (text[index] == 0x4e2d) found_first = 1;
    if (text[index] == 0x6587) found_second = 1;
  }
  fprintf(log, "\n");
  ok = found_first && found_second;
done:
  fprintf(log, "windows-console=%s Unicode-text %s line-endings\n",
    ok ? "PASS" : "FAIL", native_page ? "native-code-page" : "OEM-437");
  if (!ok) fprintf(log, "last-error=%lu\n", GetLastError());
  if (output != INVALID_HANDLE_VALUE) CloseHandle(output);
  FreeConsole();
  lua_close(L);
  FreeLibrary(module);
  fclose(log);
  return ok ? 0 : 1;
}
