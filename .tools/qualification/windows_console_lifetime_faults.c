/*
Author: WaterRun
Date: 2026-10-08
File: windows_console_lifetime_faults.c
Description: Exercises the production Windows cooked-reader ownership with real
threads, bounded console/wait fault doubles, native allocation tracking and
actual Lua finalization. This does not qualify real console interaction.
*/

#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0501
#endif
#include <windows.h>
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* @enum console_fault Deterministic failure at one cooked-reader cancellation boundary.
 * @field CONSOLE_OK Let production join a real reader after synthetic Enter.
 * @field CONSOLE_WRITE_FAIL Reject synthetic Enter with ERROR_ACCESS_DENIED.
 * @field CONSOLE_SHORT_WRITE Report success without accepting an input record.
 * @field CONSOLE_JOIN_TIMEOUT Keep the reader blocked and report its bounded join timeout.
 * @field CONSOLE_WAIT_FAIL Reject the initial nonblocking thread observation.
 */
typedef enum console_fault
{
  CONSOLE_OK, CONSOLE_WRITE_FAIL, CONSOLE_SHORT_WRITE,
  CONSOLE_JOIN_TIMEOUT, CONSOLE_WAIT_FAIL
} console_fault;

static CRITICAL_SECTION fixture_lock;
static void *fixture_buffers[8];
static HANDLE fixture_entered;
static HANDLE fixture_release;
static HANDLE fixture_observer;
static HANDLE fixture_production_thread;
static console_fault fixture_fault;
static size_t fixture_allocations;
static size_t fixture_fail_allocation;
static int fixture_fail_thread;
static int fixture_complete_before_return;
static int fixture_thread_closed;
static size_t fixture_cases;
static size_t fixture_leaks;
static size_t fixture_handle_leaks;

/* Register a real native buffer under a lock shared with the reader's final release.
 * @param pointer void* New allocation, or NULL when the system allocation failed.
 * @return void No value; successful allocations occupy one unique observation slot.
 * @error Aborts for duplicate registration or observation overflow.
 */
static void fixture_register(void *pointer)
{
  size_t index;
  if (pointer == NULL) return;
  EnterCriticalSection(&fixture_lock);
  for (index = 0U; index < 8U; ++index) assert(fixture_buffers[index] != pointer);
  for (index = 0U; index < 8U; ++index)
  {
    if (fixture_buffers[index] == NULL)
    {
      fixture_buffers[index] = pointer;
      LeaveCriticalSection(&fixture_lock);
      return;
    }
  }
  abort();
}

/* Allocate tracked production bytes or reject one deterministic startup allocation.
 * @param bytes size_t Requested native byte count.
 * @return void* Owned allocation or NULL at the selected allocation/system failure.
 * @effect Advances the main-thread startup allocation counter and registers successful storage.
 */
static void *fixture_malloc(size_t bytes)
{
  void *pointer;
  if (++fixture_allocations == fixture_fail_allocation) return NULL;
  pointer = malloc(bytes);
  fixture_register(pointer);
  return pointer;
}

/* Allocate tracked zeroed reader state or reject its startup allocation.
 * @param count size_t Number of requested elements.
 * @param bytes size_t Byte size of each element.
 * @return void* Owned zeroed allocation or NULL for the selected/system failure.
 * @effect Advances the startup allocation counter and registers successful storage.
 */
static void *fixture_calloc(size_t count, size_t bytes)
{
  void *pointer;
  if (++fixture_allocations == fixture_fail_allocation) return NULL;
  pointer = calloc(count, bytes);
  fixture_register(pointer);
  return pointer;
}

/* Release only a registered production allocation, on either owner thread.
 * @param pointer void* Registered allocation or NULL for a harmless no-op.
 * @return void No value; removes its observation before freeing it.
 * @error Aborts on a duplicate or foreign free rather than hiding ownership errors.
 */
static void fixture_free(void *pointer)
{
  size_t index;
  if (pointer == NULL) return;
  EnterCriticalSection(&fixture_lock);
  for (index = 0U; index < 8U; ++index)
  {
    if (fixture_buffers[index] == pointer)
    {
      fixture_buffers[index] = NULL;
      LeaveCriticalSection(&fixture_lock);
      free(pointer);
      return;
    }
  }
  abort();
}

/* Count retained native allocations without racing a finishing reader.
 * @param none Uses the locked observation slots for this isolated process.
 * @return size_t Number of currently retained production allocations.
 */
static size_t fixture_live(void)
{
  size_t index;
  size_t count = 0U;
  EnterCriticalSection(&fixture_lock);
  for (index = 0U; index < 8U; ++index)
    if (fixture_buffers[index] != NULL) ++count;
  LeaveCriticalSection(&fixture_lock);
  return count;
}

/* Hold a real production worker until the test explicitly permits its final write.
 * @param input HANDLE Borrowed fixture input sentinel; no host console is read.
 * @param buffer LPVOID Production-owned wide buffer that must outlive Lua finalization.
 * @param requested DWORD Available wide-character capacity, at least three for this fixture.
 * @param received LPDWORD Receives the exact three-character completed line length.
 * @param control LPVOID Unused console control, required to be NULL by production.
 * @return BOOL TRUE after writing one line; asserts if the bounded fixture wait fails.
 * @effect Signals worker entry and waits at most twenty seconds on the owned release event.
 */
static BOOL WINAPI fixture_read_console(
  HANDLE input, LPVOID buffer, DWORD requested, LPDWORD received, LPVOID control)
{
  WCHAR *wide = (WCHAR *)buffer;
  assert(input == fixture_entered && control == NULL && requested >= 3U);
  assert(SetEvent(fixture_entered));
  assert(WaitForSingleObject(fixture_release, 20000U) == WAIT_OBJECT_0);
  wide[0] = L'x'; wide[1] = L'\r'; wide[2] = L'\n';
  *received = 3U;
  return TRUE;
}

/* Create the real production reader while retaining an independent test join handle.
 * @param security LPSECURITY_ATTRIBUTES Borrowed thread security passed through unchanged.
 * @param stack_size SIZE_T Requested stack size passed through unchanged.
 * @param entry LPTHREAD_START_ROUTINE Production reader callback passed through unchanged.
 * @param opaque LPVOID Production heap reader record, never retained by the Lua fixture.
 * @param flags DWORD Creation flags passed through unchanged.
 * @param identifier LPDWORD Optional thread identifier destination passed through unchanged.
 * @return HANDLE Owned production handle, or NULL for an injected/system startup failure.
 * @effect Duplicates a successful handle for observation; optionally joins before returning to test early completion.
 */
static HANDLE WINAPI fixture_create_thread(LPSECURITY_ATTRIBUTES security,
  SIZE_T stack_size, LPTHREAD_START_ROUTINE entry, LPVOID opaque,
  DWORD flags, LPDWORD identifier)
{
  HANDLE thread;
  if (fixture_fail_thread) { SetLastError(ERROR_NOT_ENOUGH_MEMORY); return NULL; }
  thread = CreateThread(security, stack_size, entry, opaque, flags, identifier);
  if (thread == NULL) return NULL;
  fixture_production_thread = thread;
  assert(fixture_observer == NULL);
  assert(DuplicateHandle(GetCurrentProcess(), thread, GetCurrentProcess(),
    &fixture_observer, 0U, FALSE, DUPLICATE_SAME_ACCESS));
  if (fixture_complete_before_return)
  {
    assert(SetEvent(fixture_release));
    assert(WaitForSingleObject(fixture_observer, 20000U) == WAIT_OBJECT_0);
  }
  return thread;
}

/* Observe production thread waits while injecting only the selected cancellation failure.
 * @param handle HANDLE Production thread handle; other native waits pass through unchanged.
 * @param duration DWORD Zero for observation or five seconds for the cancellation join.
 * @return DWORD Real wait status, or WAIT_FAILED/WAIT_TIMEOUT at the selected boundary.
 * @effect Records ERROR_INVALID_HANDLE for the injected wait failure without closing the real handle.
 */
static DWORD WINAPI fixture_wait(HANDLE handle, DWORD duration)
{
  if (handle == fixture_production_thread)
  {
    if (fixture_fault == CONSOLE_WAIT_FAIL)
    {
      SetLastError(ERROR_INVALID_HANDLE);
      return WAIT_FAILED;
    }
    if (fixture_fault == CONSOLE_JOIN_TIMEOUT && duration != 0U) return WAIT_TIMEOUT;
  }
  return WaitForSingleObject(handle, duration);
}

/* Accept or reject production's synthetic Enter without changing any host console.
 * @param input HANDLE Borrowed fixture input sentinel.
 * @param records const_INPUT_RECORD* Exactly one key-down Enter supplied by production.
 * @param count DWORD Required single-record count.
 * @param written LPDWORD Receives one for accepted Enter or zero for a short write.
 * @return BOOL FALSE for injected access denial; otherwise TRUE with the selected written count.
 * @effect Releases the real reader only after an accepted non-timeout cancellation.
 */
static BOOL WINAPI fixture_write_console(
  HANDLE input, const INPUT_RECORD *records, DWORD count, LPDWORD written)
{
  assert(input == fixture_entered && count == 1U);
  assert(records[0].EventType == KEY_EVENT && records[0].Event.KeyEvent.bKeyDown);
  assert(records[0].Event.KeyEvent.wVirtualKeyCode == VK_RETURN);
  assert(records[0].Event.KeyEvent.uChar.UnicodeChar == L'\r');
  if (fixture_fault == CONSOLE_WRITE_FAIL)
  {
    SetLastError(ERROR_ACCESS_DENIED);
    return FALSE;
  }
  *written = fixture_fault == CONSOLE_SHORT_WRITE ? 0U : 1U;
  if (*written == 1U && fixture_fault != CONSOLE_JOIN_TIMEOUT)
    assert(SetEvent(fixture_release));
  return TRUE;
}

/* Close the actual production handle while detecting duplicate thread closes.
 * @param handle HANDLE Owned native handle supplied by production cleanup.
 * @return BOOL Unchanged OS close result; asserts if production closes its thread twice.
 * @effect Records the reader-handle release separately from buffer finalization.
 */
static BOOL WINAPI fixture_close_handle(HANDLE handle)
{
  if (handle == fixture_production_thread)
  {
    assert(!fixture_thread_closed);
    fixture_thread_closed = 1;
  }
  return CloseHandle(handle);
}

#define malloc fixture_malloc
#define calloc fixture_calloc
#define free fixture_free
#define ReadConsoleW fixture_read_console
#define CreateThread fixture_create_thread
#define WaitForSingleObject fixture_wait
#define WriteConsoleInputW fixture_write_console
#define CloseHandle fixture_close_handle
#include "../../native/yaca_native.c"
#undef malloc
#undef calloc
#undef free
#undef ReadConsoleW
#undef CreateThread
#undef WaitForSingleObject
#undef WriteConsoleInputW
#undef CloseHandle

/* Count process handles without acquiring an extra observation handle.
 * @param none Uses the current isolated qualification process.
 * @return DWORD Exact process handle count.
 * @error Aborts when the OS cannot provide the count.
 */
static DWORD fixture_handle_count(void)
{
  DWORD count;
  assert(GetProcessHandleCount(GetCurrentProcess(), &count));
  return count;
}

/* Reset one fixture only after its previous worker and all observations have been released.
 * @param none Uses persistent gate events and observation state owned by main.
 * @return void No value; resets failure controls and both worker gates.
 * @error Aborts if a prior allocation or independent join handle remains.
 */
static void fixture_reset(void)
{
  assert(fixture_live() == 0U && fixture_observer == NULL);
  assert(ResetEvent(fixture_entered) && ResetEvent(fixture_release));
  fixture_production_thread = NULL;
  fixture_fault = CONSOLE_OK;
  fixture_allocations = 0U;
  fixture_fail_allocation = 0U;
  fixture_fail_thread = 0;
  fixture_complete_before_return = 0;
  fixture_thread_closed = 0;
}

/* Create a genuinely finalizable Lua terminal owner that borrows only the fixture sentinel.
 * @param L lua_State* Fresh state retaining the terminal at stack top.
 * @return yaca_terminal* Borrowed userdata owning a reader after successful production start.
 * @effect Installs the real terminal finalizer and marks terminal mode as already restored.
 */
static yaca_terminal *fixture_terminal(lua_State *L)
{
  yaca_terminal *terminal;
  create_handle_metatable(L, YACA_TERMINAL_METATABLE, l_terminal_gc);
  terminal = push_terminal(L);
  terminal->input = fixture_entered;
  terminal->maximum_input_bytes = 32U;
  terminal->cooked_mode = 1;
  terminal->restored = 1;
  return terminal;
}

/* Invoke an actual explicit terminal operation and check its public success/error shape.
 * @param L lua_State* State holding a registry reference to the live terminal.
 * @param reference int Registry reference kept throughout failure and retry.
 * @param operation lua_CFunction Actual cancel, restore or close production port.
 * @param accepted int Expected first result truth; a rejection must retain a structured error.
 * @return void No value; removes the operation's results from the stack.
 * @error Aborts on thrown errors or malformed/incorrect result truth.
 */
static void fixture_operation(
  lua_State *L, int reference, lua_CFunction operation, int accepted)
{
  int arguments = 1;
  lua_pushcfunction(L, operation);
  lua_rawgeti(L, LUA_REGISTRYINDEX, reference);
  if (operation == l_terminal_cancel) { lua_pushinteger(L, 0); arguments = 2; }
  assert(lua_pcall(L, arguments, 2, 0) == LUA_OK);
  assert(lua_toboolean(L, -2) == accepted);
  if (!accepted)
  {
    assert(lua_istable(L, -1));
    lua_getfield(L, -1, "code");
    assert(lua_type(L, -1) == LUA_TSTRING);
    lua_pop(L, 1);
  }
  lua_pop(L, 2);
}

/* Join the independently observed worker, record genuine leaks and rescue only a faulty baseline.
 * @param baseline DWORD Process handle count before starting this worker.
 * @return void No value; counts escaped buffers/handles before any rescue cleanup.
 * @effect Releases the reader gate and joins before freeing proven leaked baseline allocations.
 * @error Aborts if cleanup changes the process handle count or a test observation survives.
 */
static void fixture_finish(DWORD baseline)
{
  size_t index;
  size_t leaked;
  assert(SetEvent(fixture_release));
  assert(WaitForSingleObject(fixture_observer, 20000U) == WAIT_OBJECT_0);
  leaked = fixture_live();
  fixture_leaks += leaked;
  if (!fixture_thread_closed)
  {
    ++fixture_handle_leaks;
    assert(CloseHandle(fixture_production_thread));
  }
  for (index = 0U; index < 8U; ++index)
    if (fixture_buffers[index] != NULL) fixture_free(fixture_buffers[index]);
  assert(CloseHandle(fixture_observer));
  fixture_observer = NULL;
  assert(fixture_live() == 0U && fixture_handle_count() == baseline);
  ++fixture_cases;
}

/* Verify failed cancellation retains a live owner, then either retry it or finalize Lua first.
 * @param fault console_fault Cancellation boundary to reject while the real reader remains blocked.
 * @param operation lua_CFunction Explicit operation exercised before retry, or NULL for direct finalization.
 * @param close_state int Use lua_close for emergency cleanup instead of two full collections.
 * @return void No value; completes two independent failure/recovery cycles and records any escaped resources.
 * @effect Creates isolated states, invokes production ownership, and lets the reader outlive its Lua state on detach.
 */
static void fixture_cancellation(
  console_fault fault, lua_CFunction operation, int close_state)
{
  size_t cycle;
  for (cycle = 0U; cycle < 2U; ++cycle)
  {
    lua_State *L;
    yaca_terminal *terminal;
    DWORD baseline;
    int reference;
    fixture_reset();
    baseline = fixture_handle_count();
    L = luaL_newstate(); assert(L != NULL);
    terminal = fixture_terminal(L);
    lua_pushvalue(L, -1); reference = luaL_ref(L, LUA_REGISTRYINDEX);
    lua_settop(L, 0);
    assert(start_windows_cooked_read(terminal));
    assert(WaitForSingleObject(fixture_entered, 20000U) == WAIT_OBJECT_0);
    fixture_fault = fault;
    if (operation != NULL)
    {
      if (fault != CONSOLE_OK)
      {
        fixture_operation(L, reference, operation, 0);
        assert(!terminal->closed && !terminal->cancelled && terminal->cooked_read != NULL);
        assert(fixture_live() == 2U && !fixture_thread_closed);
      }
      fixture_fault = CONSOLE_OK;
      fixture_operation(L, reference, operation, 1);
      assert(terminal->cooked_read == NULL && fixture_live() == 0U);
      assert(fixture_thread_closed);
      if (operation == l_terminal_cancel) assert(terminal->cancelled);
      if (operation == l_terminal_close) assert(terminal->closed);
    }
    luaL_unref(L, LUA_REGISTRYINDEX, reference);
    if (!close_state)
    {
      lua_gc(L, LUA_GCCOLLECT);
      lua_gc(L, LUA_GCCOLLECT);
    }
    lua_close(L);
    if (operation == NULL)
    {
      assert(fixture_live() == 2U);
      assert(WaitForSingleObject(fixture_observer, 0U) == WAIT_TIMEOUT);
    }
    fixture_finish(baseline);
  }
}

/* Exercise worker completion both before handle publication and while finalization races its return.
 * @param early int Join inside CreateThread before production publishes its thread handle when nonzero.
 * @return void No value; records complete cleanup for sixty-four independent schedules.
 * @effect Runs real production readers and actual Lua GC with no real console interaction.
 */
static void fixture_completion(int early)
{
  size_t cycle;
  for (cycle = 0U; cycle < 64U; ++cycle)
  {
    lua_State *L;
    yaca_terminal *terminal;
    DWORD baseline;
    fixture_reset();
    fixture_complete_before_return = early;
    baseline = fixture_handle_count();
    L = luaL_newstate(); assert(L != NULL);
    terminal = fixture_terminal(L);
    assert(start_windows_cooked_read(terminal));
    assert(SetEvent(fixture_release));
    fixture_fault = CONSOLE_WRITE_FAIL;
    lua_settop(L, 0);
    lua_gc(L, LUA_GCCOLLECT);
    lua_gc(L, LUA_GCCOLLECT);
    lua_close(L);
    fixture_finish(baseline);
  }
}

/* Reject each native startup acquisition, then start and cancel again on the same Lua owner.
 * @param failure size_t One/two reject the two allocations; three rejects actual thread creation.
 * @return void No value; verifies typed OS failure and full same-owner startup recovery twice.
 * @effect Starts only bounded fixture workers after each failed resource acquisition has been cleaned.
 */
static void fixture_startup(size_t failure)
{
  size_t cycle;
  for (cycle = 0U; cycle < 2U; ++cycle)
  {
    lua_State *L;
    yaca_terminal *terminal;
    DWORD baseline;
    fixture_reset();
    fixture_fail_allocation = failure < 3U ? failure : 0U;
    fixture_fail_thread = failure == 3U;
    baseline = fixture_handle_count();
    L = luaL_newstate(); assert(L != NULL);
    terminal = fixture_terminal(L);
    assert(!start_windows_cooked_read(terminal));
    assert(GetLastError() == ERROR_NOT_ENOUGH_MEMORY);
    assert(terminal->cooked_read == NULL && fixture_live() == 0U);
    assert(fixture_handle_count() == baseline);
    fixture_fail_allocation = 0U; fixture_fail_thread = 0;
    assert(start_windows_cooked_read(terminal));
    assert(cancel_windows_cooked_read(terminal));
    assert(terminal->cooked_read == NULL && fixture_live() == 0U);
    lua_close(L);
    fixture_finish(baseline);
  }
}

/* Run the production ownership fault matrix and report baseline leaks as a nonzero exit.
 * @param none No command-line arguments or external service inputs are accepted.
 * @return int Zero for no escaped native resources; one when the unmodified baseline leaked resources.
 * @effect Owns two gate events and a critical section, all released after every worker is joined.
 * @error Assertions terminate for contract violations, premature free, double close or fixture timeout.
 */
int main(void)
{
  console_fault fault;
  size_t failure;
  InitializeCriticalSection(&fixture_lock);
  fixture_entered = CreateEventW(NULL, TRUE, FALSE, NULL);
  fixture_release = CreateEventW(NULL, TRUE, FALSE, NULL);
  assert(fixture_entered != NULL && fixture_release != NULL);
  for (fault = CONSOLE_WRITE_FAIL; fault <= CONSOLE_WAIT_FAIL; ++fault)
  {
    fixture_cancellation(fault, l_terminal_cancel, 0);
    fixture_cancellation(fault, l_terminal_restore, 0);
    fixture_cancellation(fault, l_terminal_close, 0);
    fixture_cancellation(fault, NULL, 0);
    fixture_cancellation(fault, NULL, 1);
  }
  fixture_cancellation(CONSOLE_OK, l_terminal_cancel, 0);
  fixture_completion(1);
  fixture_completion(0);
  for (failure = 1U; failure <= 3U; ++failure) fixture_startup(failure);
  assert(CloseHandle(fixture_entered) && CloseHandle(fixture_release));
  DeleteCriticalSection(&fixture_lock);
  printf("windows-console-lifetime cases=%zu native-leaks=%zu handle-leaks=%zu\n",
    fixture_cases, fixture_leaks, fixture_handle_leaks);
  return fixture_leaks == 0U && fixture_handle_leaks == 0U ? 0 : 1;
}
