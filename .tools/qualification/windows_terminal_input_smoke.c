/*
Author: WaterRun
Date: 2026-10-08
File: windows_terminal_input_smoke.c
Description: Tests production raw key repeats, Unicode limits and recovery on an
owned real Windows console, plus injected mode-setting failures and actual
cooked-reader cancellation. No inherited console is modified or model called.
*/

#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0501
#endif
#include <windows.h>
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static HANDLE fixture_input;
static DWORD fixture_original_mode;
static size_t fixture_mode_calls;
static size_t fixture_fail_mode_at;
static size_t fixture_checks;
static size_t fixture_failures;

/* Reject one production mode-setting call while leaving the owned console unchanged.
 * @param input HANDLE Borrowed console input, passed unchanged to the real setter on other calls.
 * @param mode DWORD Requested console flags passed through unchanged unless failure is injected.
 * @return BOOL FALSE with ERROR_ACCESS_DENIED at the selected call, otherwise the actual OS result.
 * @effect Counts production setter attempts; only the successful OS setter changes console mode.
 */
static BOOL WINAPI fixture_set_console_mode(HANDLE input, DWORD mode)
{
  if (++fixture_mode_calls == fixture_fail_mode_at)
  {
    SetLastError(ERROR_ACCESS_DENIED);
    return FALSE;
  }
  return SetConsoleMode(input, mode);
}

#define SetConsoleMode fixture_set_console_mode
#include "../../native/yaca_native.c"
#undef SetConsoleMode

/* Record a behavioral observation without aborting early on an expected broken baseline.
 * @param condition int Nonzero when production matches the required behavior.
 * @param label const_char* Fixed non-secret case label printed only on mismatch.
 * @return void No value; advances check/failure counters.
 * @effect Writes only failing case labels, without dumping input or credentials.
 */
static void fixture_expect(int condition, const char *label)
{
  ++fixture_checks;
  if (!condition)
  {
    ++fixture_failures;
    printf("FAIL %s\n", label);
  }
}

/* Read actual input flags from the console owned by this test process.
 * @param none Uses only fixture_input.
 * @return DWORD Actual current console mode.
 * @error Aborts if the owned console is unavailable.
 */
static DWORD fixture_mode(void)
{
  DWORD mode;
  assert(GetConsoleMode(fixture_input, &mode));
  return mode;
}

/* Start the real native terminal port and retain its userdata for subsequent operations.
 * @param L lua_State* State receiving a terminal request and the protected native results.
 * @param mode const_char* Raw or cooked mode requested against the owned console.
 * @param maximum lua_Integer Positive maximum text byte count for this fixture.
 * @param reference int* Receives a registry reference to successful userdata, or LUA_NOREF on rejection.
 * @return yaca_terminal* Borrowed live owner on success; NULL on a typed start rejection.
 * @effect Invokes production mode changes and may start its actual cooked reader.
 * @error Aborts on an unexpected Lua exception or malformed successful owner.
 */
static yaca_terminal *fixture_start(
  lua_State *L, const char *mode, lua_Integer maximum, int *reference)
{
  yaca_terminal *terminal = NULL;
  lua_settop(L, 0);
  lua_pushcfunction(L, l_terminal_start);
  lua_createtable(L, 0, 2);
  lua_pushstring(L, mode); lua_setfield(L, -2, "mode");
  lua_pushinteger(L, maximum); lua_setfield(L, -2, "maximum_input_bytes");
  assert(lua_pcall(L, 1, 2, 0) == LUA_OK);
  *reference = LUA_NOREF;
  if (lua_toboolean(L, -2))
  {
    terminal = (yaca_terminal *)luaL_checkudata(L, -1, YACA_TERMINAL_METATABLE);
    lua_pushvalue(L, -1); *reference = luaL_ref(L, LUA_REGISTRYINDEX);
  }
  else assert(lua_istable(L, -1));
  lua_settop(L, 0);
  return terminal;
}

/* Invoke one actual terminal operation while retaining its success/error result shape.
 * @param L lua_State* State retaining the terminal by registry reference.
 * @param reference int Live registry reference borrowed for the invocation.
 * @param operation lua_CFunction Production poll/cancel/restore/close/join callback.
 * @return void No value; leaves exactly the two production results on the stack.
 * @effect Poll may consume real console records; other operations manage the actual owner.
 * @error Aborts on unexpected Lua exceptions or a result shape outside the native contract.
 */
static void fixture_call(lua_State *L, int reference, lua_CFunction operation)
{
  int arguments = 1;
  lua_settop(L, 0);
  lua_pushcfunction(L, operation);
  lua_rawgeti(L, LUA_REGISTRYINDEX, reference);
  if (operation == l_terminal_poll || operation == l_terminal_cancel)
  {
    lua_pushinteger(L, 0); ++arguments;
  }
  if (operation == l_terminal_poll)
  {
    lua_pushinteger(L, 1); ++arguments;
  }
  assert(lua_pcall(L, arguments, 2, 0) == LUA_OK && lua_gettop(L) == 2);
}

/* Write one real console record with an explicit Unicode unit, repeat count and modifiers.
 * @param character WCHAR Exact UTF-16 code unit supplied to the owned console.
 * @param repeats WORD OS key repeat count, including repeated backspace input.
 * @param key WORD Virtual-key code, zero for ordinary character fixtures.
 * @param modifiers DWORD Actual Win32 control-key flags.
 * @param down BOOL Key-down truth passed unchanged to the OS record.
 * @return void No value; exactly one record must be accepted by WriteConsoleInputW.
 * @effect Writes only to the test's independent console input buffer.
 */
static void fixture_key(WCHAR character, WORD repeats, WORD key, DWORD modifiers, BOOL down)
{
  INPUT_RECORD record;
  DWORD written;
  memset(&record, 0, sizeof(record));
  record.EventType = KEY_EVENT;
  record.Event.KeyEvent.bKeyDown = down;
  record.Event.KeyEvent.wRepeatCount = repeats;
  record.Event.KeyEvent.wVirtualKeyCode = key;
  record.Event.KeyEvent.uChar.UnicodeChar = character;
  record.Event.KeyEvent.dwControlKeyState = modifiers;
  assert(WriteConsoleInputW(fixture_input, &record, 1U, &written) && written == 1U);
}

/* Check exact repeated UTF-8 output from one real production poll.
 * @param L lua_State* State retaining the input terminal.
 * @param reference int Registry reference to its live owner.
 * @param bytes const_char* Expected UTF-8 scalar or bounded line pattern.
 * @param repeats size_t Number of exact pattern repetitions expected in the one action.
 * @param label const_char* Fixed case label used for a failed baseline observation.
 * @return void No value; records shape/content truth and clears the Lua stack.
 */
static void fixture_text(lua_State *L, int reference,
  const char *bytes, size_t repeats, const char *label)
{
  const char *actual;
  size_t length = 0U;
  size_t unit = strlen(bytes);
  size_t index;
  int valid;
  fixture_call(L, reference, l_terminal_poll);
  valid = lua_toboolean(L, 1) && lua_istable(L, 2) && lua_rawlen(L, 2) == 1U;
  if (valid)
  {
    lua_rawgeti(L, 2, 1);
    lua_getfield(L, -1, "intent"); actual = lua_tostring(L, -1);
    valid = actual != NULL && strcmp(actual, "text") == 0;
    lua_pop(L, 1);
    lua_getfield(L, -1, "text"); actual = lua_tolstring(L, -1, &length);
    valid = valid && actual != NULL && length == unit * repeats;
    if (valid)
      for (index = 0U; index < repeats; ++index)
        if (memcmp(actual + index * unit, bytes, unit) != 0) { valid = 0; break; }
  }
  fixture_expect(valid, label);
  lua_settop(L, 0);
}

/* Verify an actual poll returns no semantic action for a retained partial scalar or ignored key.
 * @param L lua_State* State retaining the terminal by reference.
 * @param reference int Live terminal registry reference.
 * @param label const_char* Fixed case label for the empty-poll observation.
 * @return void No value; records the observation and removes poll results.
 */
static void fixture_empty(lua_State *L, int reference, const char *label)
{
  fixture_call(L, reference, l_terminal_poll);
  fixture_expect(lua_toboolean(L, 1) && lua_istable(L, 2) && lua_rawlen(L, 2) == 0U, label);
  lua_settop(L, 0);
}

/* Verify the actual typed poll rejection without substituting a generic success/failure check.
 * @param L lua_State* State retaining the terminal by reference.
 * @param reference int Live terminal registry reference.
 * @param code const_char* Required Limit or InvalidEncoding identifier.
 * @param label const_char* Fixed failure label, never input bytes.
 * @return void No value; records exact native error truth and clears the stack.
 */
static void fixture_rejection(lua_State *L, int reference, const char *code, const char *label)
{
  int valid;
  const char *actual;
  fixture_call(L, reference, l_terminal_poll);
  valid = !lua_toboolean(L, 1) && lua_istable(L, 2);
  if (valid)
  {
    lua_getfield(L, 2, "code"); actual = lua_tostring(L, -1);
    valid = actual != NULL && strcmp(actual, code) == 0;
  }
  fixture_expect(valid, label);
  lua_settop(L, 0);
}

/* Close the real native port and verify exact restoration of the owned console flags.
 * @param L lua_State* State retaining the terminal by reference.
 * @param reference int Registry reference released only after successful native close.
 * @return void No value; removes the owner and checks original mode restoration.
 * @effect Closes native reader ownership, releases the Lua reference and flushes only fixture input.
 */
static void fixture_close(lua_State *L, int reference)
{
  fixture_call(L, reference, l_terminal_close);
  assert(lua_toboolean(L, 1));
  lua_settop(L, 0);
  luaL_unref(L, LUA_REGISTRYINDEX, reference);
  fixture_expect(fixture_mode() == fixture_original_mode, "original console mode after close");
  assert(FlushConsoleInputBuffer(fixture_input));
}

/* Exercise actual BMP/supplementary repeats, bounds, ignored key-up and shortcut precedence.
 * @param L lua_State* State used for all independent terminal owners.
 * @return void No value; records exact text, rejection, recovery and restored mode observations.
 * @effect Starts raw mode and injects only non-secret records into the owned console.
 */
static void fixture_raw(lua_State *L)
{
  int reference;
  yaca_terminal *terminal;
  terminal = fixture_start(L, "raw", 65536, &reference); assert(terminal != NULL);
  fixture_key(L'x', 5U, 0U, 0U, TRUE);
  fixture_text(L, reference, "x", 5U, "ASCII repeat count");
  fixture_key(0x00E9U, 4U, 0U, 0U, TRUE);
  fixture_text(L, reference, "\xC3\xA9", 4U, "two-byte scalar repeats");
  fixture_key(0x4E2DU, 3U, 0U, 0U, TRUE);
  fixture_text(L, reference, "\xE4\xB8\xAD", 3U, "three-byte scalar repeats");
  fixture_key(0xD83DU, 2U, 0U, 0U, TRUE);
  fixture_empty(L, reference, "repeated high surrogate remains partial");
  fixture_key(0xDE00U, 2U, 0U, 0U, TRUE);
  fixture_text(L, reference, "\xF0\x9F\x98\x80", 2U, "supplementary scalar repeats");
  fixture_key(0x08U, 3U, VK_BACK, 0U, TRUE);
  fixture_text(L, reference, "\x08", 3U, "backspace repeat count");
  fixture_key(L'v', 65535U, 0U, 0U, TRUE);
  fixture_text(L, reference, "v", 65535U, "maximum WORD repeat count");
  fixture_key(L'z', 1U, 0U, 0U, FALSE);
  fixture_empty(L, reference, "key-up does not emit text");
  fixture_key(0U, 1U, VK_SHIFT, SHIFT_PRESSED, TRUE);
  fixture_empty(L, reference, "modifier-only input remains empty");
  fixture_key(L'\r', 3U, VK_RETURN, LEFT_CTRL_PRESSED | SHIFT_PRESSED, TRUE);
  fixture_call(L, reference, l_terminal_poll);
  assert(lua_toboolean(L, 1) && lua_rawlen(L, 2) == 1U);
  lua_rawgeti(L, 2, 1); lua_getfield(L, -1, "intent");
  fixture_expect(strcmp(lua_tostring(L, -1), "steer") == 0, "shortcut remains one action with Ctrl precedence");
  lua_settop(L, 0);
  fixture_key(0xDE00U, 1U, 0U, 0U, TRUE);
  fixture_rejection(L, reference, "InvalidEncoding", "unpaired low surrogate");
  fixture_key(0xD83DU, 1U, 0U, 0U, TRUE);
  fixture_empty(L, reference, "first high surrogate retained");
  fixture_key(0xD834U, 1U, 0U, 0U, TRUE);
  fixture_rejection(L, reference, "InvalidEncoding", "second high surrogate rejects the malformed sequence");
  fixture_key(L'r', 1U, 0U, 0U, TRUE);
  fixture_text(L, reference, "r", 1U, "same-owner recovery after second high surrogate");
  fixture_key(0xD83DU, 2U, 0U, 0U, TRUE);
  fixture_empty(L, reference, "mismatched-count high surrogate retained");
  fixture_key(0xDE00U, 1U, 0U, 0U, TRUE);
  fixture_rejection(L, reference, "InvalidEncoding", "surrogate repeat count mismatch");
  fixture_key(L'r', 1U, 0U, 0U, TRUE);
  fixture_text(L, reference, "r", 1U, "same-owner recovery after repeat count mismatch");
  fixture_close(L, reference);

  terminal = fixture_start(L, "raw", 2, &reference); assert(terminal != NULL);
  fixture_key(0x4E2DU, 1U, 0U, 0U, TRUE);
  fixture_rejection(L, reference, "Limit", "valid scalar above byte limit");
  fixture_close(L, reference);
  terminal = fixture_start(L, "raw", 11, &reference); assert(terminal != NULL);
  fixture_key(0x4E2DU, 4U, 0U, 0U, TRUE);
  fixture_rejection(L, reference, "Limit", "repeated BMP scalar above byte limit");
  fixture_key(0x4E2DU, 3U, 0U, 0U, TRUE);
  fixture_text(L, reference, "\xE4\xB8\xAD", 3U, "bounded repeat recovery on same owner");
  fixture_close(L, reference);
  terminal = fixture_start(L, "raw", 7, &reference); assert(terminal != NULL);
  fixture_key(0xD83DU, 2U, 0U, 0U, TRUE);
  fixture_empty(L, reference, "bounded repeated surrogate remains partial");
  fixture_key(0xDE00U, 2U, 0U, 0U, TRUE);
  fixture_rejection(L, reference, "Limit", "repeated supplementary scalar above byte limit");
  fixture_close(L, reference);
}

/* Reject raw-mode entry, restore and close setters and verify actual mode plus native-owner retry truth.
 * @param L lua_State* State retaining each live native owner during injected failure/retry.
 * @return void No value; records mode/state behavior without turning a rejection into a successful close.
 * @effect Changes only the test console; resets fault injection before each successful retry/GC restoration.
 */
static void fixture_modes(lua_State *L)
{
  int reference;
  DWORD raw_mode;
  yaca_terminal *terminal;
  fixture_fail_mode_at = fixture_mode_calls + 1U;
  terminal = fixture_start(L, "raw", 64, &reference);
  fixture_expect(terminal == NULL && reference == LUA_NOREF, "raw entry failure is rejected");
  fixture_expect(fixture_mode() == fixture_original_mode, "entry failure leaves original mode");
  fixture_fail_mode_at = 0U;
  lua_gc(L, LUA_GCCOLLECT); lua_gc(L, LUA_GCCOLLECT);
  fixture_expect(fixture_mode() == fixture_original_mode, "failed entry finalization preserves original mode");

  terminal = fixture_start(L, "raw", 64, &reference); assert(terminal != NULL);
  raw_mode = fixture_mode();
  fixture_expect((raw_mode & (ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT | ENABLE_PROCESSED_INPUT)) == 0U,
    "raw console line echo and processed input disabled");
  fixture_fail_mode_at = fixture_mode_calls + 1U;
  fixture_call(L, reference, l_terminal_restore);
  fixture_expect(!lua_toboolean(L, 1) && !terminal->restored && !terminal->closed,
    "restore failure preserves native owner");
  fixture_expect(fixture_mode() == raw_mode, "restore rejection does not fabricate restored mode");
  fixture_fail_mode_at = 0U;
  fixture_call(L, reference, l_terminal_restore);
  fixture_expect(lua_toboolean(L, 1) && terminal->restored,
    "same-owner restoration retry succeeds");
  fixture_close(L, reference);

  terminal = fixture_start(L, "raw", 64, &reference); assert(terminal != NULL);
  fixture_fail_mode_at = fixture_mode_calls + 1U;
  fixture_call(L, reference, l_terminal_close);
  fixture_expect(!lua_toboolean(L, 1) && !terminal->closed, "close failure preserves native owner");
  fixture_fail_mode_at = 0U;
  fixture_close(L, reference);

  terminal = fixture_start(L, "raw", 64, &reference); assert(terminal != NULL);
  luaL_unref(L, LUA_REGISTRYINDEX, reference); lua_settop(L, 0);
  lua_gc(L, LUA_GCCOLLECT); lua_gc(L, LUA_GCCOLLECT);
  fixture_expect(fixture_mode() == fixture_original_mode, "raw GC restores actual original mode");
}

/* Cancel a real blocked cooked ReadConsoleW operation and check its acknowledged terminal truth.
 * @param L lua_State* State retaining the actual console reader through cancel/poll/join/close.
 * @return void No value; records real mode flags, cancellation truth and restoration.
 * @effect Starts and joins an actual production worker using only the independent fixture console.
 */
static void fixture_cooked(lua_State *L)
{
  int reference;
  yaca_terminal *terminal = fixture_start(L, "cooked", 64, &reference);
  assert(terminal != NULL);
  fixture_expect((fixture_mode() & (ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT | ENABLE_PROCESSED_INPUT))
    == (ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT | ENABLE_PROCESSED_INPUT), "actual cooked console flags");
  fixture_call(L, reference, l_terminal_cancel);
  fixture_expect(lua_toboolean(L, 1) && lua_toboolean(L, 2)
    && terminal->cooked_read == NULL, "real cooked cancellation joins and releases reader");
  fixture_call(L, reference, l_terminal_poll);
  assert(lua_toboolean(L, 1) && lua_rawlen(L, 2) == 1U);
  lua_rawgeti(L, 2, 1); lua_getfield(L, -1, "outcome");
  fixture_expect(strcmp(lua_tostring(L, -1), "cancelled") == 0, "real cooked cancelled terminal fact");
  fixture_call(L, reference, l_terminal_join);
  assert(lua_toboolean(L, 1)); lua_getfield(L, 2, "outcome");
  fixture_expect(strcmp(lua_tostring(L, -1), "cancelled") == 0, "real cooked join agrees with terminal fact");
  fixture_close(L, reference);
}

/* Run the raw/mode/cooked matrix in an owned console and return all observed baseline failures.
 * @param none No external paths, model credentials or inherited input data are consumed.
 * @return int Zero for complete behavioral agreement; one for recorded baseline mismatches.
 * @effect Creates an independent console, temporarily replaces only this process's stdin, and releases all state/handles.
 * @error Assertions terminate for broken fixture setup or unexpected Lua/OS failures.
 */
int main(void)
{
  HANDLE original_input = GetStdHandle(STD_INPUT_HANDLE);
  HANDLE original_output = GetStdHandle(STD_OUTPUT_HANDLE);
  HANDLE original_error = GetStdHandle(STD_ERROR_HANDLE);
  DWORD baseline_handles;
  DWORD final_handles;
  lua_State *L;
  size_t cycle;
  FreeConsole();
  assert(AllocConsole());
  assert(SetStdHandle(STD_OUTPUT_HANDLE, original_output));
  assert(SetStdHandle(STD_ERROR_HANDLE, original_error));
  fixture_input = CreateFileW(L"CONIN$", GENERIC_READ | GENERIC_WRITE,
    FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, 0U, NULL);
  assert(fixture_input != INVALID_HANDLE_VALUE && SetStdHandle(STD_INPUT_HANDLE, fixture_input));
  fixture_original_mode = fixture_mode();
  assert(GetProcessHandleCount(GetCurrentProcess(), &baseline_handles));
  L = luaL_newstate(); assert(L != NULL);
  create_handle_metatable(L, YACA_TERMINAL_METATABLE, l_terminal_gc);
  for (cycle = 0U; cycle < 2U; ++cycle)
  {
    fixture_raw(L);
    fixture_modes(L);
    fixture_cooked(L);
  }
  lua_close(L);
  fixture_expect(fixture_mode() == fixture_original_mode, "Lua close preserves original mode");
  assert(GetProcessHandleCount(GetCurrentProcess(), &final_handles));
  fixture_expect(final_handles == baseline_handles, "all native terminal/thread handles released");
  assert(SetStdHandle(STD_INPUT_HANDLE, original_input));
  assert(CloseHandle(fixture_input) && FreeConsole());
  printf("windows-terminal-input checks=%zu failures=%zu mode-restored=%d handles-stable=%d\n",
    fixture_checks, fixture_failures, fixture_mode_calls > 0U, final_handles == baseline_handles);
  return fixture_failures == 0U ? 0 : 1;
}
