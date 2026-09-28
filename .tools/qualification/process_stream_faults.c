/*
Author: WaterRun
Date: 2026-09-28
File: process_stream_faults.c
Description: Injects Lua allocation failures into production process stream reads and checks native buffer cleanup plus continued supervision to the terminal event.
*/

#if !defined(_WIN32) && !defined(_POSIX_C_SOURCE)
#define _POSIX_C_SOURCE 200809L
#endif
#if !defined(_WIN32) && !defined(_XOPEN_SOURCE)
#define _XOPEN_SOURCE 700
#endif
#if !defined(_WIN32) && !defined(_GNU_SOURCE)
#define _GNU_SOURCE
#endif
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#if defined(_WIN32)
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0501
#endif
#include <windows.h>
#else
#include <sys/ioctl.h>
#include <sys/types.h>
#include <unistd.h>
#endif
#include "lua.h"
#include "lauxlib.h"

static void *observed_buffer;
static int observing;

/* Observe the single native read buffer acquired during the armed poll call.
 * @param size size_t Native allocation size requested by production code.
 * @return void* Allocated buffer or NULL on host allocation failure.
 * @effect Records an armed allocation; aborts if this narrow probe sees multiple live native buffers.
 * @ownership The production free wrapper normally releases the buffer; the probe cleans confirmed leaks after observation.
 */
static void *tracked_malloc(size_t size)
{
  void *result = malloc(size);
  if (observing && result != NULL)
  {
    if (observed_buffer != NULL) abort();
    observed_buffer = result;
  }
  return result;
}

/* Release a native buffer and clear its observation before deallocation.
 * @param pointer void* Native allocation or NULL.
 * @return void No value.
 * @effect Clears the observation when the production implementation frees its read buffer.
 */
static void tracked_free(void *pointer)
{
  if (pointer == observed_buffer) observed_buffer = NULL;
  free(pointer);
}

#define malloc tracked_malloc
#define free tracked_free
#include "../../native/yaca_native.c"
#undef malloc
#undef free

/* Capacity of the copied terminal outcome label. */
#define PROBE_OUTCOME_CAPACITY 16

/* @struct allocation_fault Tracks persistent Lua growth failures during one native call.
 * @field calls size_t Number of armed growth allocation attempts.
 * @field fail_at size_t First growth allocation to reject, including all later emergency-GC retries.
 * @field armed int Whether allocation failure injection is active.
 */
typedef struct allocation_fault {
  size_t calls;
  size_t fail_at;
  int armed;
} allocation_fault;

/* Allocate Lua memory, persistently rejecting growth at the selected threshold.
 * @param opaque void* Caller-owned allocation_fault for the lifetime of the Lua state.
 * @param pointer void* Previous Lua allocation or NULL.
 * @param previous size_t Previous byte count, or Lua type tag for NULL pointers.
 * @param requested size_t New byte count; zero releases the block.
 * @return void* Resized block or NULL for free/injected/system failure.
 * @effect Counts armed growth requests and changes only Lua-owned allocations.
 */
static void *fault_allocate(void *opaque, void *pointer, size_t previous, size_t requested)
{
  allocation_fault *state = (allocation_fault *)opaque;
  if (requested == 0U) { free(pointer); return NULL; }
  if (state->armed && (pointer == NULL || requested > previous))
  {
    ++state->calls;
    if (state->calls >= state->fail_at) return NULL;
  }
  return realloc(pointer, requested);
}

/* Builds the production process request table for this platform's allowlisted shell.
 * @param L lua_State* Lua state receiving the completed request table.
 * @return void result Pushes one request table accepted by the production process_start port.
 */
static void probe_push_request(lua_State *L)
{
#if defined(_WIN32)
  static const char *const command = "echo yaca-open-out-123& echo yaca-open-err-456 1>&2";
  static const char *const kind = "windows";
  static const char *const executable = "native-GetSystemDirectoryW/cmd.exe";
#else
  static const char *const command = "printf yaca-open-out-123; printf yaca-open-err-456 1>&2";
  static const char *const kind = "linux";
  static const char *const executable = "/bin/sh";
#endif

  lua_createtable(L, 0, 5);
  lua_pushstring(L, ".");
  lua_setfield(L, -2, "cwd");
  lua_pushstring(L, command);
  lua_setfield(L, -2, "command");
  lua_pushinteger(L, 0);
  lua_setfield(L, -2, "started_at");
  lua_createtable(L, 0, 0);
  lua_setfield(L, -2, "environment");
  lua_createtable(L, 0, 2);
  lua_pushstring(L, kind);
  lua_setfield(L, -2, "kind");
  lua_pushstring(L, executable);
  lua_setfield(L, -2, "executable");
  lua_setfield(L, -2, "shell");
}

/* Starts one real supervised process and keeps its owner referenced.
 * @param L lua_State* Lua state hosting the process owner userdata.
 * @return int result Registry reference holding the live process userdata.
 * @error Aborts when the production process_start port rejects the request.
 * @effect Spawns one allowlisted shell child writing fixed bytes to both streams.
 */
static int probe_make_process(lua_State *L)
{
  probe_push_request(L);
  lua_pushcfunction(L, l_process_start);
  lua_insert(L, -2);
  if (lua_pcall(L, 1, LUA_MULTRET, 0) != LUA_OK
      || lua_gettop(L) != 2
      || !lua_toboolean(L, 1)
      || lua_type(L, 2) != LUA_TUSERDATA)
  {
    abort();
  }
  lua_remove(L, 1);
  return luaL_ref(L, LUA_REGISTRYINDEX);
}

/* Reads the process owner behind one registry reference.
 * @param L lua_State* Lua state owning the referenced process userdata.
 * @param reference int Registry reference created for this process owner.
 * @return yaca_process* result Live process owner pointer; the Lua state keeps it alive.
 */
static yaca_process *probe_process(lua_State *L, int reference)
{
  yaca_process *process;

  lua_rawgeti(L, LUA_REGISTRYINDEX, reference);
  process = (yaca_process *)lua_touserdata(L, -1);
  lua_pop(L, 1);
  return process;
}

/* Reports pending bytes on one process stream without consuming them.
 * @param process yaca_process* Process owner whose streams are inspected.
 * @param stdout_bytes size_t* Receives pending standard-output bytes.
 * @param stderr_bytes size_t* Receives pending standard-error bytes.
 * @return void result Writes the current pending byte counts of both streams.
 */
static void probe_pending_bytes(
  const yaca_process *process,
  size_t *stdout_bytes,
  size_t *stderr_bytes)
{
#if defined(_WIN32)
  DWORD available = 0UL;

  *stdout_bytes = 0U;
  *stderr_bytes = 0U;
  if (PeekNamedPipe(process->stdout_read, NULL, 0U, NULL, &available, NULL))
  {
    *stdout_bytes = (size_t)available;
  }
  available = 0UL;
  if (PeekNamedPipe(process->stderr_read, NULL, 0U, NULL, &available, NULL))
  {
    *stderr_bytes = (size_t)available;
  }
#else
  int pending = 0;

  *stdout_bytes = 0U;
  *stderr_bytes = 0U;
  if (ioctl(process->stdout_read, FIONREAD, &pending) == 0 && pending > 0)
  {
    *stdout_bytes = (size_t)pending;
  }
  pending = 0;
  if (ioctl(process->stderr_read, FIONREAD, &pending) == 0 && pending > 0)
  {
    *stderr_bytes = (size_t)pending;
  }
#endif
}

/* Sleeps briefly between poll attempts while draining a process.
 * @param milliseconds int Approximate delay before the next poll attempt.
 * @return void result No value; the calling thread pauses.
 */
static void probe_sleep(int milliseconds)
{
#if defined(_WIN32)
  Sleep((DWORD)milliseconds);
#else
  usleep((useconds_t)milliseconds * 1000U);
#endif
}

/* Waits until both process streams hold bytes so the armed poll always reads a chunk.
 * @param L lua_State* Lua state owning the referenced process userdata.
 * @param reference int Registry reference created for this process owner.
 * @return void result Returns once both streams hold at least one byte.
 * @error Aborts when no output appears within the bounded wait window.
 */
static void probe_wait_for_output(lua_State *L, int reference)
{
  int attempt;

  for (attempt = 0; attempt < 1000; ++attempt)
  {
    size_t stdout_bytes = 0U;
    size_t stderr_bytes = 0U;

    probe_pending_bytes(probe_process(L, reference), &stdout_bytes, &stderr_bytes);
    if (stdout_bytes > 0U && stderr_bytes > 0U)
    {
      return;
    }
    probe_sleep(5);
  }
  abort();
}

/* Tallies one delivered poll result array into the running stream totals.
 * @param L lua_State* Lua state whose stack top holds the poll result array.
 * @param stdout_total size_t* Accumulated standard-output bytes across all events.
 * @param stderr_total size_t* Accumulated standard-error bytes across all events.
 * @param outcome char* Destination buffer for the terminal outcome label.
 * @param saw_terminal int* Set once a terminal event is delivered.
 * @return void result Reads every event kind and bytes field without keeping stack references.
 * @effect Copies the terminal outcome label while the event table is still on the stack.
 */
static void probe_tally_events(
  lua_State *L,
  size_t *stdout_total,
  size_t *stderr_total,
  char *outcome,
  int *saw_terminal)
{
  lua_Integer index;

  for (index = 1U; index <= (lua_Integer)lua_rawlen(L, -1); ++index)
  {
    const char *kind;

    lua_rawgeti(L, -1, index);
    lua_getfield(L, -1, "kind");
    kind = lua_tostring(L, -1);
    lua_pop(L, 1);
    if (kind == NULL)
    {
      abort();
    }
    if (strcmp(kind, "stdout") == 0 || strcmp(kind, "stderr") == 0)
    {
      size_t length = 0U;

      lua_getfield(L, -1, "bytes");
      if (lua_tolstring(L, -1, &length) == NULL)
      {
        abort();
      }
      lua_pop(L, 2);
      if (strcmp(kind, "stdout") == 0)
      {
        *stdout_total += length;
      }
      else
      {
        *stderr_total += length;
      }
      continue;
    }
    if (strcmp(kind, "terminal") == 0)
    {
      lua_getfield(L, -1, "outcome");
      kind = lua_tostring(L, -1);
      if (kind == NULL || strlen(kind) + 1U > PROBE_OUTCOME_CAPACITY)
      {
        abort();
      }
      strcpy(outcome, kind);
      lua_pop(L, 2);
      *saw_terminal = 1;
      continue;
    }
    abort();
  }
  lua_pop(L, 1);
}

/* Polls one process once through the production port with the current fault setting.
 * @param L lua_State* Lua state hosting the process owner userdata.
 * @param reference int Registry reference created for this process owner.
 * @param fault allocation_fault* Active failure injector for this Lua state.
 * @param stdout_total size_t* Accumulated standard-output bytes across all events.
 * @param stderr_total size_t* Accumulated standard-error bytes across all events.
 * @param outcome char* Destination buffer for the terminal outcome label.
 * @param saw_terminal int* Set once a terminal event is delivered.
 * @return int result lua_pcall status of the protected poll call.
 * @effect Tallies delivered events, or leaves a raised error object on the Lua stack.
 */
static int probe_poll_once(
  lua_State *L,
  int reference,
  allocation_fault *fault,
  size_t *stdout_total,
  size_t *stderr_total,
  char *outcome,
  int *saw_terminal)
{
  int status;

  lua_pushcfunction(L, l_process_poll);
  lua_rawgeti(L, LUA_REGISTRYINDEX, reference);
  lua_pushinteger(L, 0);
  lua_pushinteger(L, 64);
  lua_pushinteger(L, 4096);
  fault->armed = 1;
  status = lua_pcall(L, 4, LUA_MULTRET, 0);
  fault->armed = 0;
  if (status == LUA_OK)
  {
    if (lua_gettop(L) != 2 || !lua_toboolean(L, 1) || !lua_istable(L, 2))
    {
      abort();
    }
    lua_remove(L, 1);
    probe_tally_events(L, stdout_total, stderr_total, outcome, saw_terminal);
  }
  return status;
}

/* Verifies the baseline stream totals recorded from one fault-free iteration.
 * @param stdout_total size_t Delivered standard-output bytes of the baseline run.
 * @param stderr_total size_t Delivered standard-error bytes of the baseline run.
 * @return int result 1 when the platform's expected marker text reached both channels.
 */
static int probe_baseline_delivered(size_t stdout_total, size_t stderr_total)
{
#if defined(_WIN32)
  return stdout_total >= strlen("yaca-open-out-123")
    && stderr_total >= strlen("yaca-open-err-456");
#else
  return stdout_total == strlen("yaca-open-out-123")
    && stderr_total == strlen("yaca-open-err-456");
#endif
}

/* Runs one armed iteration of the poll port and audits stream-buffer ownership.
 * @param fail_at size_t First Lua growth allocation to reject, or SIZE_MAX for the baseline.
 * @param leaks size_t* Incremented once for every escaping native read buffer.
 * @return size_t Number of observed Lua growth requests during the protected poll.
 * @effect Starts and fully supervises one process; verifies the terminal outcome and, on the
 *   baseline iteration, complete delivery of both stream payloads.
 * @error Aborts on structural failures such as unexpected error kinds or a missing terminal event.
 */
static size_t probe_run_iteration(size_t fail_at, size_t *leaks)
{
  allocation_fault fault = { 0U, fail_at, 0 };
  lua_State *L = lua_newstate(fault_allocate, &fault, 0U);
  size_t stdout_total = 0U;
  size_t stderr_total = 0U;
  char outcome[PROBE_OUTCOME_CAPACITY];
  int saw_terminal = 0;
  int reference;
  int status;
  int attempt;

  outcome[0] = '\0';
  if (L == NULL)
  {
    abort();
  }
  create_handle_metatable(L, YACA_PROCESS_METATABLE, l_process_gc);
  reference = probe_make_process(L);
  probe_wait_for_output(L, reference);
  observing = 1;
  status = probe_poll_once(
    L, reference, &fault, &stdout_total, &stderr_total, outcome, &saw_terminal);
  observing = 0;
  if (status != LUA_OK && status != LUA_ERRMEM)
  {
    abort();
  }
  if (status != LUA_OK)
  {
    lua_settop(L, 0);
  }
  if (observed_buffer != NULL)
  {
    ++*leaks;
    printf("stream-buffer-leak fail_at=%zu lua_status=%d\n", fail_at, status);
    free(observed_buffer);
    observed_buffer = NULL;
  }
  /* The same owner must keep supervising to the terminal event after any injected failure. */
  for (attempt = 0; attempt < 3000 && !saw_terminal; ++attempt)
  {
    allocation_fault passive = { 0U, SIZE_MAX, 0 };

    status = probe_poll_once(
      L, reference, &passive, &stdout_total, &stderr_total, outcome, &saw_terminal);
    if (status != LUA_OK)
    {
      abort();
    }
    probe_sleep(10);
  }
  if (!saw_terminal || strcmp(outcome, "completed") != 0)
  {
    abort();
  }
  if (fail_at == SIZE_MAX && !probe_baseline_delivered(stdout_total, stderr_total))
  {
    abort();
  }
  luaL_unref(L, LUA_REGISTRYINDEX, reference);
  lua_gc(L, LUA_GCCOLLECT);
  lua_gc(L, LUA_GCCOLLECT);
  lua_close(L);
  return fault.calls;
}

/* Exercises the process stream reads across all Lua allocation positions of one poll.
 * @param none No arguments; every iteration spawns and closes its own process.
 * @return int Zero only when no native read buffer escapes any protected poll call.
 * @effect Prints allocation-site and leak counts for the armed stream reads.
 */
int main(void)
{
  size_t leaks = 0U;
  size_t sites;

  setbuf(stdout, NULL);
  sites = probe_run_iteration(SIZE_MAX, &leaks);
  size_t position;

  for (position = 1U; position <= sites + 2U; ++position)
  {
    probe_run_iteration(position, &leaks);
  }
  printf(
    "process-stream-faults allocation_sites=%zu native_leaks=%zu terminal_recovery=PASS\n",
    sites,
    leaks);
  return leaks == 0U ? 0 : 1;
}
