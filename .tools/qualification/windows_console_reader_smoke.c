/*
** File: windows_console_reader_smoke.c
** Date: 2026-09-14
** Author: WaterRun
** Description: Checks the production cooked reader against a bounded console
** double, including UTF-16 fragments and failures. Run on Windows; this is a
** deterministic reader check, not a substitute for real console interaction.
*/
#define WINVER 0x0501
#define _WIN32_WINNT 0x0501
#include <windows.h>
#include <assert.h>
#include <stdlib.h>
#include <string.h>

static WCHAR fixture_source[9000];
static DWORD fixture_length;
static DWORD fixture_offset;
static DWORD fixture_calls;
static DWORD fixture_fail_call;
static int fixture_overreport;

static BOOL WINAPI fixture_read_console(
  HANDLE input, LPVOID buffer, DWORD requested, LPDWORD received, LPVOID control)
{
  DWORD count;

  (void)input;
  assert(control == NULL);
  fixture_calls++;
  /* The real Server 2008 probe rejects 32768 and 65538 character requests. */
  if (requested >= 32768U || fixture_calls == fixture_fail_call)
  {
    SetLastError(requested >= 32768U ? ERROR_NOT_ENOUGH_MEMORY : ERROR_READ_FAULT);
    return FALSE;
  }
  if (fixture_overreport)
  {
    *received = requested + 1U;
    return TRUE;
  }
  count = fixture_length - fixture_offset;
  if (count > requested)
  {
    count = requested;
  }
  memcpy(buffer, fixture_source + fixture_offset, count * sizeof(WCHAR));
  fixture_offset += count;
  *received = count;
  return TRUE;
}

#define ReadConsoleW fixture_read_console
#include "../../native/yaca_native.c"
#undef ReadConsoleW

static void prepare(yaca_terminal_read *read, DWORD length)
{
  DWORD index;

  memset(read, 0, sizeof(*read));
  read->capacity = 65538U;
  read->wide = (WCHAR *)calloc(read->capacity + 1U, sizeof(WCHAR));
  assert(read->wide != NULL);
  fixture_length = length;
  fixture_offset = 0;
  fixture_calls = 0;
  fixture_fail_call = 0;
  fixture_overreport = 0;
  for (index = 0; index < length; index++)
  {
    fixture_source[index] = L'x';
  }
  if (length >= 2U)
  {
    fixture_source[length - 2U] = L'\r';
    fixture_source[length - 1U] = L'\n';
  }
}

int main(void)
{
  yaca_terminal_read read;
  yaca_terminal terminal;
  lua_State *L;
  const char *bytes;
  size_t byte_length;

  prepare(&read, 8200U);
  fixture_source[4095] = 0xD83D;
  fixture_source[4096] = 0xDE00;
  windows_cooked_reader(&read);
  assert(read.error_value == ERROR_SUCCESS && read.received == 8200U);
  assert(fixture_calls > 1U && fixture_offset == fixture_length);
  assert(memcmp(read.wide, fixture_source, fixture_length * sizeof(WCHAR)) == 0);
  memset(&terminal, 0, sizeof(terminal));
  terminal.maximum_input_bytes = 65536U;
  terminal.cooked_read = &read;
  L = luaL_newstate();
  assert(L != NULL);
  assert(push_windows_cooked_line(L, &terminal) == 1);
  lua_getfield(L, -1, "text");
  bytes = lua_tolstring(L, -1, &byte_length);
  assert(bytes != NULL && byte_length == 8202U);
  assert(memcmp(bytes + 4095, "\xF0\x9F\x98\x80", 4) == 0);
  assert(memcmp(bytes + byte_length - 2U, "\r\n", 2) == 0);
  lua_close(L);
  free(read.wide);

  prepare(&read, 4096U);
  windows_cooked_reader(&read);
  assert(read.error_value == ERROR_SUCCESS && read.received == 4096U);
  assert(fixture_calls == 1U); /* A full chunk ending in LF must not block again. */
  free(read.wide);

  prepare(&read, 3U);
  windows_cooked_reader(&read);
  assert(read.error_value == ERROR_SUCCESS && read.received == 3U && fixture_calls == 1U);
  free(read.wide);

  prepare(&read, 0U);
  windows_cooked_reader(&read);
  assert(read.error_value == ERROR_SUCCESS && read.received == 0U && fixture_calls == 1U);
  free(read.wide);

  prepare(&read, 8200U);
  fixture_fail_call = 2U;
  windows_cooked_reader(&read);
  assert(read.error_value == ERROR_READ_FAULT && read.received < fixture_length);
  free(read.wide);

  prepare(&read, 3U);
  fixture_overreport = 1;
  windows_cooked_reader(&read);
  assert(read.error_value == ERROR_INVALID_DATA && read.received == 0U);
  free(read.wide);
  puts("windows-console-reader-unit=PASS");
  return 0;
}
