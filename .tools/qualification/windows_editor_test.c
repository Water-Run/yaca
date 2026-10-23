/*
Author: WaterRun
Date: 2026-10-23
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

/* @struct allocation_fault Controls one protected Lua allocation-failure attempt.
 * @field enabled int Nonzero only while the production paste call is protected by lua_pcall.
 * @field remaining size_t Allowed growth allocations before persistent rejection.
 */
typedef struct allocation_fault
{
  int enabled;
  size_t remaining;
} allocation_fault;

/* Reject Lua growth at a chosen site and verify that no clipboard lock surrounds allocation.
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
    assert(!clipboard_opened && !clipboard_locked);
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
  return TRUE;
}

/* Return the one borrowed fixture handle for Unicode text.
 * @param format UINT Must be CF_UNICODETEXT; no other format is available.
 * @return HANDLE Sentinel or NULL for an injected missing format.
 */
static HANDLE WINAPI fixture_clipboard_data(UINT format)
{
  assert(clipboard_opened && format == CF_UNICODETEXT);
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
  yaca_terminal terminal;
  memset(&terminal, 0, sizeof(terminal));
  terminal.maximum_input_bytes = 64;
  return push_windows_paste(L, &terminal);
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
  assert(L != NULL);
  memset(&terminal, 0, sizeof(terminal));
  terminal.editor_mode = 1;
  terminal.maximum_input_bytes = 64;
  prepare_clipboard(7);
  clipboard_text[0] = L'A'; clipboard_text[1] = 0x4E2D; clipboard_text[2] = L'\n';
  clipboard_text[3] = 0xD83D; clipboard_text[4] = 0xDE00;
  assert(push_windows_paste(L, &terminal) == 1);
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
    assert(push_windows_paste(L, &terminal) == 1);
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
  expect_action(L, "paste", "v");
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
  printf("windows-editor-native=PASS paste=strict ownership=released keys=projected frame=validated allocation-failures=%zu\n", allocation_failures);
  return 0;
}
