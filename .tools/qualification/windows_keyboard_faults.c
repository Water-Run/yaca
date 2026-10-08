/*
Author: WaterRun
Date: 2026-10-08
File: windows_keyboard_faults.c
Description: Injects persistent Lua growth failures into production repeated-key
projection with bounded console-record doubles, checks native ownership and
two exact recoveries through the same terminal owner. No real console is read.
*/

#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0501
#endif
#include <windows.h>
#include <assert.h>
#include <stdio.h>
#include <string.h>

static INPUT_RECORD keyboard_records[2];
static DWORD keyboard_count;
static DWORD keyboard_offset;
static size_t keyboard_cold_faults;
static size_t keyboard_repeat_faults;
static size_t keyboard_warmed_successes;

/* Report only the bounded fixture records that production has not consumed.
 * @param input HANDLE Borrowed input sentinel, ignored without calling an actual console API.
 * @param available LPDWORD Receives the remaining zero, one or two input records.
 * @return BOOL TRUE; this double introduces no OS error or allocation.
 */
static BOOL WINAPI keyboard_available(HANDLE input, LPDWORD available)
{
  (void)input;
  *available = keyboard_count - keyboard_offset;
  return TRUE;
}

/* Consume exactly one deterministic KEY_EVENT record for the production raw poll.
 * @param input HANDLE Borrowed sentinel, ignored without accessing a host handle.
 * @param records PINPUT_RECORD Caller-owned destination receiving the next record.
 * @param requested DWORD Must be one, as used by the production poll.
 * @param received LPDWORD Receives zero at fixture EOF or one after copying a record.
 * @return BOOL TRUE; assertions reject an unexpected multi-record production request.
 * @effect Advances only keyboard_offset, modeling consumed records without claiming replay after Lua failure.
 */
static BOOL WINAPI keyboard_read(HANDLE input, PINPUT_RECORD records,
  DWORD requested, LPDWORD received)
{
  (void)input;
  assert(requested == 1U);
  *received = 0U;
  if (keyboard_offset < keyboard_count)
  {
    *records = keyboard_records[keyboard_offset++];
    *received = 1U;
  }
  return TRUE;
}

#define GetNumberOfConsoleInputEvents keyboard_available
#define ReadConsoleInputW keyboard_read
#include "filesystem_fault_tracker.h"
#undef GetNumberOfConsoleInputEvents
#undef ReadConsoleInputW

/* Prepare one large ASCII, BMP or supplementary key profile for a fresh poll.
 * @param profile int Zero selects ASCII, one BMP and two a matching surrogate pair.
 * @return void No value; replaces the fixed record sequence and resets its read cursor.
 * @effect Represents a new non-secret input fixture for recovery, not replay of consumed prior bytes.
 */
static void keyboard_prepare(int profile)
{
  DWORD index;
  memset(keyboard_records, 0, sizeof(keyboard_records));
  keyboard_count = profile == 2 ? 2U : 1U;
  keyboard_offset = 0U;
  for (index = 0U; index < keyboard_count; ++index)
  {
    keyboard_records[index].EventType = KEY_EVENT;
    keyboard_records[index].Event.KeyEvent.bKeyDown = TRUE;
    keyboard_records[index].Event.KeyEvent.wRepeatCount = profile == 0 ? 65535U
      : profile == 1 ? 9000U : 8000U;
  }
  keyboard_records[0].Event.KeyEvent.uChar.UnicodeChar = profile == 0 ? L'x'
    : profile == 1 ? 0x4E2DU : 0xD83DU;
  if (profile == 2) keyboard_records[1].Event.KeyEvent.uChar.UnicodeChar = 0xDE00U;
}

/* Poll the real native function under a persistent Lua growth rejection threshold.
 * @param L lua_State* State retaining the same terminal owner in its registry.
 * @param reference int Registry reference to the live owner.
 * @param fault probe_lua_fault* Allocator control armed only around this protected native call.
 * @return int Actual Lua status; leaves two results on success or an exception object on failure.
 * @effect Consumes only the bounded record double and records every armed growth request, including emergency GC retries.
 */
static int keyboard_poll(lua_State *L, int reference, probe_lua_fault *fault)
{
  int status;
  lua_settop(L, 0);
  lua_pushcfunction(L, l_terminal_poll);
  lua_rawgeti(L, LUA_REGISTRYINDEX, reference);
  lua_pushinteger(L, 0); lua_pushinteger(L, 1);
  fault->calls = 0U; fault->armed = 1;
  status = lua_pcall(L, 3, 2, 0);
  fault->armed = 0;
  return status;
}

/* Verify complete repeated UTF-8 bytes rather than merely a successful Lua status.
 * @param L lua_State* Successful true/events poll results at stack indices one and two.
 * @param profile int Expected ASCII/BMP/supplementary text profile.
 * @return void No value; clears the result stack after checking every repeated scalar.
 * @error Aborts for a malformed event, incorrect length or any mismatching byte.
 */
static void keyboard_result(lua_State *L, int profile)
{
  const char *unit = profile == 0 ? "x" : profile == 1 ? "\xE4\xB8\xAD" : "\xF0\x9F\x98\x80";
  size_t repeats = profile == 0 ? 65535U : profile == 1 ? 9000U : 8000U;
  size_t width = strlen(unit);
  size_t length;
  size_t index;
  const char *actual;
  assert(lua_toboolean(L, 1) && lua_istable(L, 2) && lua_rawlen(L, 2) == 1U);
  lua_rawgeti(L, 2, 1); lua_getfield(L, -1, "text");
  actual = lua_tolstring(L, -1, &length);
  assert(actual != NULL && length == width * repeats);
  for (index = 0U; index < repeats; ++index)
    assert(memcmp(actual + index * width, unit, width) == 0);
  lua_settop(L, 0);
}

/* Attempt one observed growth threshold twice and recover on the same owner after each invocation.
 * @param profile int ASCII/BMP/supplementary input profile used in both cycles.
 * @param site size_t First rejected growth request, or SIZE_MAX for an observation run.
 * @return size_t Growth requests observed during the first poll, including rejection retries when armed.
 * @effect Counts actual cold/repeated memory exceptions separately from successful warmed polls; collects before ownership checks and supplies fresh recovery records.
 * @error Aborts for non-memory exceptions, leaked native allocations or incorrect recovery bytes.
 */
static size_t keyboard_check(int profile, size_t site)
{
  probe_lua_fault fault = { 0U, site, 0 };
  probe_lua_fault passive = { 0U, SIZE_MAX, 0 };
  lua_State *L = lua_newstate(probe_lua_allocate, &fault, 0U);
  yaca_terminal *terminal;
  size_t observed = 0U;
  size_t cycle;
  int reference;
  assert(L != NULL);
  create_handle_metatable(L, YACA_TERMINAL_METATABLE, l_terminal_gc);
  terminal = push_terminal(L);
  terminal->maximum_input_bytes = 65536U;
  terminal->has_original_mode = 1;
  terminal->restored = 1;
  reference = luaL_ref(L, LUA_REGISTRYINDEX);
  for (cycle = 0U; cycle < 2U; ++cycle)
  {
    int status;
    keyboard_prepare(profile);
    status = keyboard_poll(L, reference, &fault);
    if (cycle == 0U) observed = fault.calls;
    assert(status == LUA_OK || status == LUA_ERRMEM);
    if (site != SIZE_MAX)
    {
      if (cycle == 0U)
      {
        assert(status == LUA_ERRMEM);
        ++keyboard_cold_faults;
      }
      else if (status == LUA_ERRMEM) ++keyboard_repeat_faults;
      else
      {
        assert(fault.calls < site);
        ++keyboard_warmed_successes;
      }
    }
    if (status == LUA_OK) keyboard_result(L, profile);
    lua_settop(L, 0); lua_gc(L, LUA_GCCOLLECT); lua_gc(L, LUA_GCCOLLECT);
    assert(probe_live == 0U && probe_ownership_errors == 0U);
    assert(terminal->pending_high_surrogate == 0U && terminal->pending_high_repeat_count == 0U);
    keyboard_prepare(profile);
    assert(keyboard_poll(L, reference, &passive) == LUA_OK);
    keyboard_result(L, profile);
  }
  lua_close(L);
  assert(probe_live == 0U && probe_ownership_errors == 0U);
  return observed;
}

/* Run every observed persistent Lua allocation threshold for all three repeated scalar profiles.
 * @param none Accepts no paths, external console handles or model configuration.
 * @return int Zero after all exceptions and exact same-owner recoveries pass.
 * @effect Reports actual allocation-site counts; OS input is replaced only inside this qualification translation unit.
 * @error Assertions terminate for ownership, result or unexpected-exception failures.
 */
int main(void)
{
  int profile;
  size_t cases = 0U;
  /* The shared tracker also supplies a getter fault for filesystem probes.
  ** Reference it without running that unrelated control in this key probe. */
  (void)probe_exploding_getter;
  for (profile = 0; profile < 3; ++profile)
  {
    size_t observed = keyboard_check(profile, SIZE_MAX);
    size_t site;
    for (site = 1U; site <= observed; ++site) { keyboard_check(profile, site); ++cases; }
    printf("windows-keyboard profile=%d allocation-sites=%zu same-owner-recovery=PASS\n", profile, observed);
  }
  assert(keyboard_cold_faults == cases);
  assert(keyboard_repeat_faults + keyboard_warmed_successes == cases);
  printf("windows-keyboard-faults cases=%zu cold-faults=%zu repeat-faults=%zu warmed-successes=%zu native-leaks=%zu ownership-errors=%zu\n",
    cases, keyboard_cold_faults, keyboard_repeat_faults, keyboard_warmed_successes,
    probe_live, probe_ownership_errors);
  return 0;
}
