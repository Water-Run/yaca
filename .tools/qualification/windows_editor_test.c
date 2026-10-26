/*
Author: WaterRun
Date: 2026-10-26
File: windows_editor_test.c
Description: Verify native editing keys and strict clipboard-text ownership with deterministic doubles that never access the user's clipboard or console.
*/

#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0501
#endif
#include <windows.h>
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static WCHAR clipboard_text[64];
static SIZE_T clipboard_bytes;
static int clipboard_opened;
static int clipboard_locked;
static int clipboard_open_failure;
static int clipboard_lock_failure;
static int clipboard_missing;
static unsigned int clipboard_calls;
static DWORD clipboard_delay_ms;
static DWORD clipboard_thread;
static HANDLE clipboard_entered;
static HANDLE clipboard_release;

/* @struct allocation_fault Controls one protected Lua allocation-failure attempt.
 * @field enabled int Nonzero only while the production paste call is protected by lua_pcall.
 * @field remaining size_t Allowed growth allocations before persistent rejection.
 */
typedef struct allocation_fault
{
  int enabled;
  size_t remaining;
} allocation_fault;

/* Reject Lua growth at a chosen site and forbid allocation on the clipboard-owning thread.
 * @param opaque void* Borrowed allocation_fault retained until the Lua state closes.
 * @param pointer void* Existing Lua allocation, or NULL for a new one.
 * @param old_size size_t Previous size, or a Lua type tag when pointer is NULL.
 * @param new_size size_t Requested size; zero frees the allocation.
 * @return void* Reallocated storage or NULL on injected/actual allocation failure.
 * @effect Allocates/frees only Lua-owned memory and decrements the active fault budget.
 */
static void *fault_allocate(void *opaque, void *pointer, size_t old_size, size_t new_size)
{
  allocation_fault *fault = (allocation_fault *)opaque;
  if (new_size == 0) { free(pointer); return NULL; }
  if (fault->enabled && (pointer == NULL || new_size > old_size))
  {
    assert(GetCurrentThreadId() != clipboard_thread || (!clipboard_opened && !clipboard_locked));
    if (fault->remaining == 0) return NULL;
    fault->remaining--;
  }
  return realloc(pointer, new_size);
}

/* Open only the deterministic clipboard fixture.
 * @param owner HWND Unused owner handle; production passes NULL.
 * @return BOOL FALSE for an injected open failure, otherwise TRUE.
 * @effect Counts calls and marks the fake clipboard open; touches no host clipboard.
 */
static BOOL WINAPI fixture_open_clipboard(HWND owner)
{
  (void)owner;
  clipboard_calls++;
  assert(!clipboard_opened);
  if (clipboard_open_failure) return FALSE;
  clipboard_opened = 1;
  clipboard_thread = GetCurrentThreadId();
  return TRUE;
}

/* Return the one borrowed fixture handle for Unicode text.
 * @param format UINT Must be CF_UNICODETEXT; no other format is available.
 * @return HANDLE Sentinel or NULL for an injected missing format.
 * @effect May delay the fixture response to model a clipboard owner rendering text on demand.
 */
static HANDLE WINAPI fixture_clipboard_data(UINT format)
{
  assert(clipboard_opened && format == CF_UNICODETEXT);
  if (clipboard_entered != NULL)
  {
    assert(SetEvent(clipboard_entered));
    assert(WaitForSingleObject(clipboard_release, 5000U) == WAIT_OBJECT_0);
  }
  if (clipboard_delay_ms != 0) Sleep(clipboard_delay_ms);
  return clipboard_missing ? NULL : (HANDLE)(ULONG_PTR)1;
}

/* Report the exact fixture storage bound, including or omitting a terminator as selected.
 * @param memory HGLOBAL Borrowed fixture sentinel.
 * @return SIZE_T Number of bytes production may inspect.
 */
static SIZE_T WINAPI fixture_global_size(HGLOBAL memory)
{
  assert(clipboard_opened && memory == (HGLOBAL)(ULONG_PTR)1);
  return clipboard_bytes;
}

/* Borrow the fixed Unicode fixture storage without allocating.
 * @param memory HGLOBAL Borrowed fixture sentinel.
 * @return LPVOID Fixture storage or NULL for an injected lock failure.
 * @effect Marks one fake lock on success.
 */
static LPVOID WINAPI fixture_global_lock(HGLOBAL memory)
{
  assert(clipboard_opened && memory == (HGLOBAL)(ULONG_PTR)1 && !clipboard_locked);
  if (clipboard_lock_failure) return NULL;
  clipboard_locked = 1;
  return clipboard_text;
}

/* Release exactly the fake lock acquired by production.
 * @param memory HGLOBAL Borrowed fixture sentinel.
 * @return BOOL FALSE with NO_ERROR, matching the final successful GlobalUnlock convention.
 * @effect Clears the fixture lock and sets the conventional last-error result.
 */
static BOOL WINAPI fixture_global_unlock(HGLOBAL memory)
{
  assert(memory == (HGLOBAL)(ULONG_PTR)1 && clipboard_locked);
  clipboard_locked = 0;
  SetLastError(NO_ERROR);
  return FALSE;
}

/* Close the fake clipboard only after its borrowed text was unlocked.
 * @param none Uses the fixture's ownership flags.
 * @return BOOL TRUE after closing the fixture.
 * @effect Clears the open flag and asserts no borrowed pointer remains locked.
 */
static BOOL WINAPI fixture_close_clipboard(void)
{
  assert(clipboard_opened && !clipboard_locked);
  clipboard_opened = 0;
  return TRUE;
}

#define OpenClipboard fixture_open_clipboard
#define GetClipboardData fixture_clipboard_data
#define GlobalSize fixture_global_size
#define GlobalLock fixture_global_lock
#define GlobalUnlock fixture_global_unlock
#define CloseClipboard fixture_close_clipboard
#include "../../native/yaca_native.c"
#undef OpenClipboard
#undef GetClipboardData
#undef GlobalSize
#undef GlobalLock
#undef GlobalUnlock
#undef CloseClipboard

/* Reset one small Unicode input and clear fault flags after verifying prior cleanup.
 * @param units size_t Number of wide units visible to production, possibly excluding a NUL.
 * @return void No result; selects fixture storage bounds and resets input/fault counters.
 * @effect Mutates only this test's static storage.
 */
static void prepare_clipboard(size_t units)
{
  assert(!clipboard_opened && !clipboard_locked && units <= 64U);
  memset(clipboard_text, 0, sizeof(clipboard_text));
  clipboard_bytes = units * sizeof(WCHAR);
  clipboard_open_failure = clipboard_lock_failure = clipboard_missing = 0;
  clipboard_calls = 0;
  clipboard_delay_ms = 0;
  clipboard_thread = 0;
}

/* Require an exact native input action and prove clipboard ownership was released before Lua publication.
 * @param L lua_State* Contains one native action table at the stack top.
 * @param intent const_char* Expected canonical input intent.
 * @param expected const_char* Expected UTF-8 body; NULL requires no text field.
 * @return void No value; assertions reject mismatches or leaked clipboard ownership.
 */
static void expect_action(lua_State *L, const char *intent, const char *expected)
{
  assert(!clipboard_opened && !clipboard_locked);
  lua_getfield(L, -1, "intent");
  assert(strcmp(lua_tostring(L, -1), intent) == 0);
  lua_pop(L, 1);
  lua_getfield(L, -1, "text");
  if (expected == NULL) assert(lua_isnil(L, -1));
  else assert(strcmp(lua_tostring(L, -1), expected) == 0);
  lua_settop(L, 0);
}

/* Invoke one bounded production paste inside the caller's protected Lua frame.
 * @param L lua_State* Receives the production action; no arguments are consumed.
 * @return int One action table on success; Lua allocation failure is caught by the caller.
 * @effect Reads only the mocked clipboard through production conversion code.
 */
static int protected_paste(lua_State *L)
{
  luaL_Buffer buffer;
  yaca_clipboard_read read;
  memset(&read, 0, sizeof(read));
  read.limit = 64U;
  read.bytes = luaL_buffinitsize(L, &buffer, read.limit);
  read_windows_clipboard(&read);
  luaL_pushresultsize(&buffer, read.used);
  push_terminal_action(L, read.valid ? "paste" : "paste-rejected",
    read.valid ? lua_tostring(L, -1) : NULL, read.used);
  lua_remove(L, -2);
  return 1;
}

/* Exercise strict conversion directly with a caller-owned bounded destination.
 * @param L lua_State* Receives the exact action after all fake clipboard ownership is released.
 * @param terminal yaca_terminal* Supplies the selected byte limit, at most 64 for this fixture.
 * @return int One action table, matching production publication vocabulary.
 * @effect Reads only the fake clipboard and publishes no invalid/oversized prefix.
 */
static int fixture_paste(lua_State *L, yaca_terminal *terminal)
{
  char bytes[64];
  yaca_clipboard_read read;
  memset(&read, 0, sizeof(read));
  assert(terminal->maximum_input_bytes <= sizeof(bytes));
  read.bytes = bytes; read.limit = terminal->maximum_input_bytes;
  read_windows_clipboard(&read);
  push_terminal_action(L, read.valid ? "paste" : "paste-rejected", read.valid ? bytes : NULL, read.used);
  return 1;
}

/* Verify cancellation/timeout and the admission bound while a real worker is blocked in the fake renderer.
 * @param L lua_State* Fresh fixture state reused only on the main thread.
 * @param timeout int Nonzero tests deadline rejection; zero tests explicit discard.
 * @return void No result; assertions require immediate owner release and suppression of late text.
 * @effect Starts one real thread and two private events, releases the renderer and joins its duplicated observer handle.
 */
static void fixture_blocked_paste(lua_State *L, int timeout)
{
  yaca_terminal terminal, second;
  HANDLE observer;
  DWORD started;
  memset(&terminal, 0, sizeof(terminal)); terminal.maximum_input_bytes = 64;
  memset(&second, 0, sizeof(second)); second.maximum_input_bytes = 64;
  prepare_clipboard(2); clipboard_text[0] = L'x';
  clipboard_entered = CreateEventW(NULL, TRUE, FALSE, NULL);
  clipboard_release = CreateEventW(NULL, TRUE, FALSE, NULL);
  assert(clipboard_entered != NULL && clipboard_release != NULL);
  assert(push_windows_paste(L, &terminal) == 1);
  lua_getfield(L, -1, "intent"); assert(strcmp(lua_tostring(L, -1), "paste-start") == 0);
  lua_settop(L, 0); acknowledge_windows_paste(&terminal, 1);
  assert(DuplicateHandle(GetCurrentProcess(), terminal.clipboard_read->thread,
    GetCurrentProcess(), &observer, SYNCHRONIZE, FALSE, 0));
  assert(WaitForSingleObject(clipboard_entered, 5000U) == WAIT_OBJECT_0);
  started = GetTickCount();
  assert(push_windows_paste_observation(L, &terminal) == 0);
  if (timeout)
  {
    terminal.clipboard_read->started = GetTickCount() - 2000U;
    assert(push_windows_paste_observation(L, &terminal) == 2);
    lua_getfield(L, -1, "intent"); assert(strcmp(lua_tostring(L, -1), "paste-rejected") == 0);
    lua_settop(L, 0); acknowledge_windows_paste(&terminal, 2);
  }
  else discard_windows_clipboard_read(&terminal.clipboard_read);
  assert(GetTickCount() - started < 100U && terminal.clipboard_read == NULL);
  assert(push_windows_paste(L, &second) == 1 && second.clipboard_read == NULL);
  lua_getfield(L, -1, "intent"); assert(strcmp(lua_tostring(L, -1), "paste-rejected") == 0);
  lua_settop(L, 0);
  assert(InterlockedCompareExchange(&windows_clipboard_busy, 0, 0) == 1);
  assert(SetEvent(clipboard_release));
  assert(WaitForSingleObject(observer, 5000U) == WAIT_OBJECT_0);
  assert(push_windows_paste_observation(L, &terminal) == 0);
  assert(!clipboard_opened && !clipboard_locked && windows_clipboard_busy == 0);
  CloseHandle(observer); CloseHandle(clipboard_entered); CloseHandle(clipboard_release);
  clipboard_entered = clipboard_release = NULL;
}

/* Invoke asynchronous start/result publication through the caller's protected Lua allocation boundary.
 * @param L lua_State* Upvalue one borrows the caller-owned terminal; upvalue two selects result publication.
 * @return int Production action count; Lua memory failure is caught by the fixture's pcall.
 * @effect Starts a worker or projects its retained observation without acknowledging delivery.
 */
static int protected_async_paste(lua_State *L)
{
  yaca_terminal *terminal = (yaca_terminal *)lua_touserdata(L, lua_upvalueindex(1));
  return lua_toboolean(L, lua_upvalueindex(2))
    ? push_windows_paste_observation(L, terminal) : push_windows_paste(L, terminal);
}

/* Inject each Lua publication failure and retry through the same independently owned clipboard request.
 * @param result int Zero exercises start publication; nonzero exercises settled result publication.
 * @return size_t Number of distinct growth-failure thresholds recovered before the first success.
 * @effect Creates/closes isolated Lua states and joins each private worker; no host clipboard is accessed.
 */
static size_t fixture_async_allocation(int result)
{
  size_t site;
  for (site = 0; site < 64U; site++)
  {
    allocation_fault fault = { 0, site };
    yaca_terminal terminal;
    lua_State *L;
    int status;
    memset(&terminal, 0, sizeof(terminal)); terminal.maximum_input_bytes = 64;
    prepare_clipboard(2); clipboard_text[0] = L'x';
    L = lua_newstate(fault_allocate, &fault, 0U); assert(L != NULL);
    if (result)
    {
      assert(push_windows_paste(L, &terminal) == 1);
      lua_settop(L, 0); acknowledge_windows_paste(&terminal, 1);
      assert(WaitForSingleObject(terminal.clipboard_read->thread, 5000U) == WAIT_OBJECT_0);
    }
    lua_pushlightuserdata(L, &terminal); lua_pushboolean(L, result);
    lua_pushcclosure(L, protected_async_paste, 2);
    fault.enabled = 1; status = lua_pcall(L, 0, 1, 0); fault.enabled = 0;
    if (terminal.clipboard_read == NULL)
    {
      assert(!result && status == LUA_ERRMEM && windows_clipboard_busy == 0);
      lua_settop(L, 0);
      assert(push_windows_paste(L, &terminal) == 1);
    }
    assert(WaitForSingleObject(terminal.clipboard_read->thread, 5000U) == WAIT_OBJECT_0);
    assert(!clipboard_opened && !clipboard_locked);
    if (status != LUA_OK) assert(status == LUA_ERRMEM);
    lua_settop(L, 0);
    if (!result)
    {
      assert(push_windows_paste_observation(L, &terminal) == 1);
      expect_action(L, "paste-start", NULL); acknowledge_windows_paste(&terminal, 1);
    }
    assert(push_windows_paste_observation(L, &terminal) == 2);
    expect_action(L, "paste", "x"); acknowledge_windows_paste(&terminal, 2);
    lua_close(L);
    if (status == LUA_OK) break;
  }
  assert(site > 0 && site < 64U);
  return site;
}

/* Execute strict paste, shortcut and frame-rejection cases against production code.
 * @param none Consumes no external clipboard, console, credentials or paths.
 * @return int Zero after all assertions pass.
 * @effect Allocates and closes one Lua state and prints a fixed success summary.
 */
int main(void)
{
  lua_State *L = luaL_newstate();
  yaca_terminal terminal;
  KEY_EVENT_RECORD key;
  unsigned int failure;
  size_t allocation_site, allocation_failures = 0;
  size_t start_faults, result_faults;
  DWORD started, paste_elapsed;
  assert(L != NULL);
  memset(&terminal, 0, sizeof(terminal));
  terminal.editor_mode = 1;
  terminal.maximum_input_bytes = 64;
  prepare_clipboard(7);
  clipboard_text[0] = L'A'; clipboard_text[1] = 0x4E2D; clipboard_text[2] = L'\n';
  clipboard_text[3] = 0xD83D; clipboard_text[4] = 0xDE00;
  assert(fixture_paste(L, &terminal) == 1);
  expect_action(L, "paste", "A\xe4\xb8\xad\n\xf0\x9f\x98\x80");
  for (failure = 0; failure < 6; failure++)
  {
    prepare_clipboard(3);
    clipboard_text[0] = L'A'; clipboard_text[1] = L'B';
    if (failure == 0) clipboard_open_failure = 1;
    if (failure == 1) clipboard_lock_failure = 1;
    if (failure == 2) clipboard_missing = 1;
    if (failure == 3) clipboard_text[2] = L'C';
    if (failure == 4) clipboard_text[1] = 0xD800;
    terminal.maximum_input_bytes = failure == 5 ? 1 : 64;
    assert(fixture_paste(L, &terminal) == 1);
    expect_action(L, "paste-rejected", NULL);
  }
  terminal.maximum_input_bytes = 64;
  prepare_clipboard(2); clipboard_text[0] = L'v';
  memset(&key, 0, sizeof(key));
  key.bKeyDown = TRUE; key.wRepeatCount = 1;
  key.wVirtualKeyCode = 'V'; key.uChar.UnicodeChar = L'v';
  assert(push_windows_key_action(L, &terminal, &key) == 1);
  expect_action(L, "text", "v");
  assert(clipboard_calls == 0);
  key.dwControlKeyState = LEFT_CTRL_PRESSED;
  assert(push_windows_key_action(L, &terminal, &key) == 1);
  lua_getfield(L, -1, "intent"); assert(strcmp(lua_tostring(L, -1), "paste-start") == 0);
  lua_settop(L, 0); acknowledge_windows_paste(&terminal, 1);
  assert(WaitForSingleObject(terminal.clipboard_read->thread, 5000U) == WAIT_OBJECT_0);
  assert(push_windows_paste_observation(L, &terminal) == 2);
  expect_action(L, "paste", "v");
  acknowledge_windows_paste(&terminal, 2);
  assert(clipboard_calls == 1);
  key.wVirtualKeyCode = VK_LEFT; key.dwControlKeyState = 0; key.wRepeatCount = 2;
  key.uChar.UnicodeChar = 0;
  assert(push_windows_key_action(L, &terminal, &key) == 1);
  expect_action(L, "text", "\033[D\033[D");
  key.wVirtualKeyCode = VK_RETURN; key.dwControlKeyState = LEFT_CTRL_PRESSED;
  assert(push_windows_key_action(L, &terminal, &key) == 1);
  expect_action(L, "steer", NULL);
  terminal.pending_high_surrogate = 0xD800;
  terminal.pending_high_repeat_count = 1;
  key.wVirtualKeyCode = 'C'; key.uChar.UnicodeChar = 3; key.wRepeatCount = 1;
  assert(push_windows_key_action(L, &terminal, &key) == 1);
  expect_action(L, "text", "\3");
  assert(terminal.pending_high_surrogate == 0);
  lua_pushcfunction(L, l_console_redraw);
  lua_createtable(L, 0, 4);
  lua_pushboolean(L, 1); lua_setfield(L, -2, "erase_line");
  lua_pushliteral(L, ""); lua_setfield(L, -2, "append");
  lua_pushliteral(L, "\033[2J"); lua_setfield(L, -2, "prefix");
  lua_pushliteral(L, ""); lua_setfield(L, -2, "suffix");
  assert(lua_pcall(L, 1, 2, 0) == LUA_OK && !lua_toboolean(L, -2));
  lua_getfield(L, -1, "code");
  assert(strcmp(lua_tostring(L, -1), "InvalidConsoleFrame") == 0);
  lua_close(L);
  for (allocation_site = 0; allocation_site < 64; allocation_site++)
  {
    allocation_fault fault = { 0, allocation_site };
    int status;
    prepare_clipboard(2); clipboard_text[0] = L'x';
    L = lua_newstate(fault_allocate, &fault, 0U);
    assert(L != NULL);
    lua_pushcfunction(L, protected_paste);
    fault.enabled = 1;
    status = lua_pcall(L, 0, 1, 0);
    fault.enabled = 0;
    assert(!clipboard_opened && !clipboard_locked);
    if (status == LUA_OK)
    {
      expect_action(L, "paste", "x");
      lua_close(L);
      break;
    }
    assert(status == LUA_ERRMEM);
    allocation_failures++;
    lua_close(L);
  }
  assert(allocation_failures > 0 && allocation_site < 64);
  L = luaL_newstate(); assert(L != NULL);
  prepare_clipboard(2); clipboard_text[0] = L'x'; clipboard_delay_ms = 400;
  memset(&terminal, 0, sizeof(terminal));
  terminal.editor_mode = 1; terminal.maximum_input_bytes = 64;
  memset(&key, 0, sizeof(key));
  key.bKeyDown = TRUE; key.wRepeatCount = 1;
  key.wVirtualKeyCode = 'V'; key.dwControlKeyState = LEFT_CTRL_PRESSED;
  started = GetTickCount();
  assert(push_windows_key_action(L, &terminal, &key) == 1);
  paste_elapsed = GetTickCount() - started;
  lua_getfield(L, -1, "intent"); assert(strcmp(lua_tostring(L, -1), "paste-start") == 0);
  lua_settop(L, 0); acknowledge_windows_paste(&terminal, 1);
  assert(WaitForSingleObject(terminal.clipboard_read->thread, 5000U) == WAIT_OBJECT_0);
  assert(push_windows_paste_observation(L, &terminal) == 2);
  expect_action(L, "paste", "x");
  acknowledge_windows_paste(&terminal, 2);
  fixture_blocked_paste(L, 0);
  fixture_blocked_paste(L, 1);
  lua_close(L);
  start_faults = fixture_async_allocation(0);
  result_faults = fixture_async_allocation(1);
  printf("clipboard-dispatch elapsed_ms=%lu nonblocking=%s\n", paste_elapsed,
    paste_elapsed < 100U ? "PASS" : "FAIL");
  printf("windows-editor-native=PASS paste=strict ownership=released keys=projected frame=validated allocation-failures=%zu\n", allocation_failures);
  printf("clipboard-async=PASS cancellation=bounded timeout=bounded late-result=discarded admission=bounded start-faults=%zu result-faults=%zu\n", start_faults, result_faults);
  return paste_elapsed < 100U ? 0 : 1;
}
