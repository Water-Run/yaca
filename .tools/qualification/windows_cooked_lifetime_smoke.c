/*
Author: WaterRun
Date: 2026-10-08
File: windows_cooked_lifetime_smoke.c
Description: Exercises production cooked-reader ownership using real bounded worker threads and deterministic console/cancellation failures.
*/

#ifndef WINVER
#define WINVER 0x0501
#endif
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0501
#endif
#include <windows.h>
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* @enum cancellation_fixture Selected console-injection or worker-wait failure.
 * @field CANCEL_NORMAL int Synthetic Enter releases the blocked reader.
 * @field CANCEL_WRITE_ERROR int Console injection fails with access denied.
 * @field CANCEL_SHORT_WRITE int Console injection reports no written records.
 * @field CANCEL_TIMEOUT int Console injection succeeds without completing the read.
 * @field CANCEL_WAIT_ERROR int The initial worker wait fails with invalid handle.
 * @field CANCEL_FINISHED_ERROR int The worker finishes before injection reports failure.
 */
typedef enum cancellation_fixture
{
  CANCEL_NORMAL,
  CANCEL_WRITE_ERROR,
  CANCEL_SHORT_WRITE,
  CANCEL_TIMEOUT,
  CANCEL_WAIT_ERROR,
  CANCEL_FINISHED_ERROR
} cancellation_fixture;

static HANDLE fixture_gate;
static HANDLE fixture_entered;
static HANDLE fixture_worker;
static HANDLE fixture_observer;
static cancellation_fixture fixture_cancel;
static volatile LONG fixture_live_blocks;
static size_t fixture_allocation_calls;
static size_t fixture_fail_allocation;
static int fixture_fail_thread;
static int fixture_finish_before_create_returns;

/* Allocate and count production heap blocks, optionally refusing one setup allocation.
 * @param length size_t Number of requested bytes.
 * @return void* Owned block, or NULL at the configured failure or actual exhaustion.
 * @effect Updates allocation attempts and the atomic live-block count.
 */
static void *fixture_malloc(size_t length)
{
  void *pointer;
  ++fixture_allocation_calls;
  if (fixture_allocation_calls == fixture_fail_allocation) return NULL;
  pointer = malloc(length);
  if (pointer != NULL) InterlockedIncrement(&fixture_live_blocks);
  return pointer;
}

/* Allocate zeroed production storage using the same failure and ownership accounting.
 * @param count size_t Number of elements requested.
 * @param length size_t Bytes per element; the production caller supplies bounded sizes.
 * @return void* Zeroed owned block, or NULL on refused or failed allocation.
 * @effect Increments the production live-block count only for successful allocation.
 */
static void *fixture_calloc(size_t count, size_t length)
{
  void *pointer = fixture_malloc(count * length);
  if (pointer != NULL) memset(pointer, 0, count * length);
  return pointer;
}

/* Release one tracked production block on either the terminal or reader thread.
 * @param pointer void* Owned block, or NULL for an empty optional allocation.
 * @return void No value; NULL does not affect accounting.
 * @effect Atomically decrements live blocks and frees non-NULL storage.
 * @error Aborts if production releases more blocks than it acquired.
 */
static void fixture_free(void *pointer)
{
  if (pointer != NULL)
  {
    assert(InterlockedDecrement(&fixture_live_blocks) >= 0);
    free(pointer);
  }
}

/* Supply a bounded console read that stays active until the fixture releases it.
 * @param input HANDLE Borrowed input value; the double does not access a real console.
 * @param buffer LPVOID Production-owned wide buffer receiving four characters.
 * @param requested DWORD Capacity supplied by the production reader, at least four.
 * @param received LPDWORD Output count receiving the exact copied length.
 * @param control LPVOID Reserved console control, required to be NULL.
 * @return BOOL TRUE after copying a line; FALSE if the fixture's bounded wait expires.
 * @effect Signals reader entry and waits at most five seconds on fixture_gate.
 */
static BOOL WINAPI fixture_read_console(
  HANDLE input, LPVOID buffer, DWORD requested, LPDWORD received, LPVOID control)
{
  (void)input;
  assert(control == NULL && requested >= 4U);
  assert(SetEvent(fixture_entered));
  if (WaitForSingleObject(fixture_gate, 5000U) != WAIT_OBJECT_0)
  {
    SetLastError(ERROR_TIMEOUT);
    return FALSE;
  }
  memcpy(buffer, L"ok\r\n", 4U * sizeof(WCHAR));
  *received = 4U;
  return TRUE;
}

/* Create a real production worker, optionally failing setup or forcing immediate completion.
 * @param attributes LPSECURITY_ATTRIBUTES Production thread security attributes.
 * @param stack SIZE_T Requested stack size, passed to CreateThread unchanged.
 * @param callback LPTHREAD_START_ROUTINE Actual production cooked-reader callback.
 * @param context LPVOID Production heap record supplied to the callback.
 * @param flags DWORD Creation flags supplied by production.
 * @param identifier LPDWORD Optional output thread identifier.
 * @return HANDLE Owned real thread handle; NULL for the configured setup failure.
 * @effect Launches a bounded worker and can join it before returning its handle.
 */
static HANDLE WINAPI fixture_create_thread(
  LPSECURITY_ATTRIBUTES attributes, SIZE_T stack, LPTHREAD_START_ROUTINE callback,
  LPVOID context, DWORD flags, LPDWORD identifier)
{
  if (fixture_fail_thread)
  {
    SetLastError(ERROR_NOT_ENOUGH_MEMORY);
    return NULL;
  }
  fixture_worker = CreateThread(attributes, stack, callback, context, flags, identifier);
  if (fixture_worker != NULL && fixture_finish_before_create_returns)
    assert(WaitForSingleObject(fixture_worker, 5000U) == WAIT_OBJECT_0);
  return fixture_worker;
}

/* Inject a deterministic wait failure or accelerate only the cancelled worker's timeout.
 * @param handle HANDLE Handle supplied by production; unrelated handles use the real wait.
 * @param milliseconds DWORD Production timeout, zero or five seconds for the cooked worker.
 * @return DWORD Real wait result or WAIT_FAILED with a fixed invalid-handle error.
 * @effect A timeout fixture uses a zero-duration worker wait to keep the probe bounded.
 */
static DWORD WINAPI fixture_wait(HANDLE handle, DWORD milliseconds)
{
  if (handle == fixture_worker && fixture_cancel == CANCEL_WAIT_ERROR)
  {
    SetLastError(ERROR_INVALID_HANDLE);
    return WAIT_FAILED;
  }
  if (handle == fixture_worker && milliseconds == 5000U
      && fixture_cancel == CANCEL_TIMEOUT) milliseconds = 0U;
  return WaitForSingleObject(handle, milliseconds);
}

/* Model synthetic-Enter injection, including completion racing with a failed write.
 * @param input HANDLE Borrowed terminal handle, unused by the deterministic double.
 * @param records const_INPUT_RECORD* Production's single synthetic Enter record.
 * @param length DWORD Record count, required to be one.
 * @param written LPDWORD Output record count supplied by production.
 * @return BOOL TRUE for normal, short, or timeout injection; FALSE for configured write errors.
 * @effect Releases the worker only for normal injection or the completion-before-error race.
 */
static BOOL WINAPI fixture_write_console(
  HANDLE input, const INPUT_RECORD *records, DWORD length, LPDWORD written)
{
  (void)input;
  assert(length == 1U && records->EventType == KEY_EVENT);
  assert(records->Event.KeyEvent.wVirtualKeyCode == VK_RETURN);
  if (fixture_cancel == CANCEL_FINISHED_ERROR)
  {
    assert(SetEvent(fixture_gate));
    assert(WaitForSingleObject(fixture_observer, 5000U) == WAIT_OBJECT_0);
  }
  if (fixture_cancel == CANCEL_WRITE_ERROR || fixture_cancel == CANCEL_FINISHED_ERROR)
  {
    SetLastError(ERROR_ACCESS_DENIED);
    return FALSE;
  }
  *written = fixture_cancel == CANCEL_SHORT_WRITE ? 0U : 1U;
  if (fixture_cancel == CANCEL_NORMAL) assert(SetEvent(fixture_gate));
  return TRUE;
}

#define malloc fixture_malloc
#define calloc fixture_calloc
#define free fixture_free
#define ReadConsoleW fixture_read_console
#define WriteConsoleInputW fixture_write_console
#define WaitForSingleObject fixture_wait
#define CreateThread fixture_create_thread
#include "../../native/yaca_native.c"
#undef CreateThread
#undef WaitForSingleObject
#undef WriteConsoleInputW
#undef ReadConsoleW
#undef free
#undef calloc
#undef malloc

/* Read the current process's actual owned OS handle count.
 * @param none No arguments.
 * @return DWORD Number of open handles in this probe process.
 * @error Aborts when the OS refuses the resource query.
 */
static DWORD fixture_handles(void)
{
  DWORD count = 0U;
  assert(GetProcessHandleCount(GetCurrentProcess(), &count));
  return count;
}

/* Reset independent synchronization and controls before a new reader cycle.
 * @param immediate int Nonzero releases the read before CreateThread returns.
 * @return void No value; two fixture events remain owned until fixture_end.
 * @effect Creates synchronization handles and resets fault selectors and counters.
 */
static void fixture_begin(int immediate)
{
  assert(fixture_live_blocks == 0);
  fixture_gate = CreateEventW(NULL, TRUE, immediate, NULL);
  fixture_entered = CreateEventW(NULL, TRUE, FALSE, NULL);
  assert(fixture_gate != NULL && fixture_entered != NULL);
  fixture_worker = NULL;
  fixture_observer = NULL;
  fixture_cancel = CANCEL_NORMAL;
  fixture_allocation_calls = 0U;
  fixture_fail_allocation = 0U;
  fixture_fail_thread = 0;
  fixture_finish_before_create_returns = immediate;
}

/* Release only probe-owned synchronization after production has released its reader.
 * @param none No arguments; uses the current fixture handles.
 * @return void No value; the next cycle may reuse the fixture globals.
 * @effect Closes the observer and synchronization handles.
 * @error Aborts if tracked production allocations remain or a handle close fails.
 */
static void fixture_end(void)
{
  assert(fixture_live_blocks == 0);
  if (fixture_observer != NULL) assert(CloseHandle(fixture_observer));
  assert(CloseHandle(fixture_gate) && CloseHandle(fixture_entered));
  fixture_observer = NULL;
}

/* Retain a separate test handle for observing a worker after terminal ownership ends.
 * @param terminal yaca_terminal* Live production owner with a successfully started reader.
 * @return void No value; fixture_observer independently owns the duplicated handle.
 * @effect Waits for actual worker entry and duplicates its thread handle for bounded final joining.
 */
static void fixture_observe(yaca_terminal *terminal)
{
  assert(WaitForSingleObject(fixture_entered, 5000U) == WAIT_OBJECT_0);
  assert(DuplicateHandle(GetCurrentProcess(), terminal->cooked_read->thread,
    GetCurrentProcess(), &fixture_observer, 0U, FALSE, DUPLICATE_SAME_ACCESS));
}

/* Verify retryable cancellation failures preserve the reader and the original OS error.
 * @param kind cancellation_fixture Injection or wait failure selected for this cycle.
 * @return void No value; successful retry releases all production allocations and handles.
 * @effect Starts, cancels, joins, and closes a real bounded worker without touching a console.
 * @error Aborts for changed error classification, lost owner, or resource growth.
 */
static void fixture_retry(cancellation_fixture kind)
{
  yaca_terminal terminal;
  yaca_terminal_read *saved;
  DWORD baseline;
  DWORD expected = kind == CANCEL_WRITE_ERROR ? ERROR_ACCESS_DENIED
    : kind == CANCEL_SHORT_WRITE ? ERROR_WRITE_FAULT
    : kind == CANCEL_TIMEOUT ? ERROR_TIMEOUT : ERROR_INVALID_HANDLE;
  fixture_begin(0);
  baseline = fixture_handles();
  memset(&terminal, 0, sizeof(terminal));
  terminal.maximum_input_bytes = 8192U;
  assert(start_windows_cooked_read(&terminal));
  fixture_observe(&terminal);
  saved = terminal.cooked_read;
  fixture_cancel = kind;
  assert(!cancel_windows_cooked_read(&terminal) && GetLastError() == expected);
  assert(terminal.cooked_read == saved && fixture_live_blocks == 2);
  fixture_cancel = CANCEL_NORMAL;
  assert(cancel_windows_cooked_read(&terminal));
  assert(terminal.cooked_read == NULL && fixture_live_blocks == 0);
  assert(WaitForSingleObject(fixture_observer, 5000U) == WAIT_OBJECT_0);
  assert(fixture_handles() == baseline + 1U);
  fixture_end();
}

/* Collect an actual terminal userdata while its real worker cannot be cancelled normally.
 * @param kind cancellation_fixture Emergency cancellation failure or completion race.
 * @return size_t Leaked blocks plus leaked thread handles observed after the worker finishes.
 * @effect Closes the Lua state, releases the blocked worker, and rescues only confirmed baseline leaks.
 * @ownership The duplicated observer belongs to the probe; production owns the original worker handle.
 */
static size_t fixture_collect(cancellation_fixture kind)
{
  lua_State *L;
  yaca_terminal *terminal;
  yaca_terminal_read *saved;
  DWORD baseline;
  DWORD handles;
  LONG blocks;
  size_t leaks;
  fixture_begin(0);
  baseline = fixture_handles();
  L = luaL_newstate();
  assert(L != NULL);
  create_handle_metatable(L, YACA_TERMINAL_METATABLE, l_terminal_gc);
  terminal = push_terminal(L);
  terminal->maximum_input_bytes = 8192U;
  terminal->cooked_mode = 1;
  assert(start_windows_cooked_read(terminal));
  fixture_observe(terminal);
  saved = terminal->cooked_read;
  fixture_cancel = kind;
  lua_close(L);
  assert(SetEvent(fixture_gate));
  assert(WaitForSingleObject(fixture_observer, 5000U) == WAIT_OBJECT_0);
  blocks = fixture_live_blocks;
  handles = fixture_handles();
  assert(handles >= baseline + 1U);
  leaks = (size_t)blocks + (size_t)(handles - baseline - 1U);
  printf("cooked-detach case=%d blocks=%ld thread_handles=%lu\n",
    (int)kind, (long)blocks, (unsigned long)(handles - baseline - 1U));
  if (blocks != 0)
  {
    /* Baseline rescue runs after the worker stopped, and is excluded from the leak result. */
    assert(blocks == 2 && handles == baseline + 2U);
    assert(CloseHandle(saved->thread));
    fixture_free(saved->wide);
    fixture_free(saved);
  }
  assert(fixture_handles() == baseline + 1U);
  fixture_end();
  return leaks;
}

/* Exercise setup failures on the same owner followed by a successful real read.
 * @param site size_t One or two refuses allocation; three refuses CreateThread.
 * @return void No value; the retry and cancellation leave no resources behind.
 * @effect Refuses one setup operation, then starts and joins a bounded worker.
 */
static void fixture_setup(size_t site)
{
  yaca_terminal terminal;
  DWORD baseline;
  fixture_begin(0);
  baseline = fixture_handles();
  memset(&terminal, 0, sizeof(terminal));
  terminal.maximum_input_bytes = 8192U;
  fixture_fail_allocation = site <= 2U ? site : 0U;
  fixture_fail_thread = site == 3U;
  assert(!start_windows_cooked_read(&terminal));
  assert(GetLastError() == ERROR_NOT_ENOUGH_MEMORY && terminal.cooked_read == NULL);
  assert(fixture_live_blocks == 0 && fixture_handles() == baseline);
  fixture_fail_allocation = 0U;
  fixture_fail_thread = 0;
  assert(start_windows_cooked_read(&terminal));
  fixture_observe(&terminal);
  assert(cancel_windows_cooked_read(&terminal));
  assert(fixture_live_blocks == 0 && fixture_handles() == baseline + 1U);
  fixture_end();
}

/* Verify ownership when the real callback finishes before CreateThread returns its handle.
 * @param none No arguments.
 * @return void No value; the completed line remains readable until the owner releases it.
 * @effect Creates and joins a deliberately immediately completed reader.
 */
static void fixture_creation_race(void)
{
  yaca_terminal terminal;
  DWORD baseline;
  fixture_begin(1);
  baseline = fixture_handles();
  memset(&terminal, 0, sizeof(terminal));
  terminal.maximum_input_bytes = 8192U;
  assert(start_windows_cooked_read(&terminal));
  assert(terminal.cooked_read->received == 4U && fixture_live_blocks == 2);
  assert(memcmp(terminal.cooked_read->wide, L"ok\r\n", 4U * sizeof(WCHAR)) == 0);
  assert(cancel_windows_cooked_read(&terminal));
  assert(fixture_live_blocks == 0 && fixture_handles() == baseline);
  fixture_end();
}

/* Run cancellation, detach, setup, and creation-race controls against production functions.
 * @param none No arguments.
 * @return int Zero only when no production allocation or thread handle escapes any cycle.
 * @effect Starts only bounded probe workers; prints leak observations and the final summary.
 */
int main(void)
{
  size_t cycle;
  size_t site;
  size_t leaks = 0U;
  DWORD baseline = fixture_handles();
  for (cycle = 0U; cycle < 2U; ++cycle)
  {
    for (site = 1U; site <= 3U; ++site) fixture_setup(site);
    for (site = CANCEL_WRITE_ERROR; site <= CANCEL_WAIT_ERROR; ++site)
      fixture_retry((cancellation_fixture)site);
    for (site = CANCEL_WRITE_ERROR; site <= CANCEL_FINISHED_ERROR; ++site)
      leaks += fixture_collect((cancellation_fixture)site);
  }
  for (cycle = 0U; cycle < 32U; ++cycle) fixture_creation_race();
  assert(fixture_handles() == baseline);
  printf("windows-cooked-lifetime=%s setup=6 retries=8 detach=10 creation_races=32 leaks=%zu\n",
    leaks == 0U ? "PASS" : "FAIL", leaks);
  return leaks == 0U ? 0 : 1;
}
