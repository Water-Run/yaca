/*
Author: WaterRun
Date: 2026-10-08
File: windows_worker_lifetime_fixture.c
Description: Builds actual production console and stdin workers into a loadlib DLL with bounded IO and setup-failure doubles for module-lifetime qualification.
*/

#ifndef WINVER
#define WINVER 0x0501
#endif
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0501
#endif
#include <windows.h>
#include <assert.h>
#include <stdlib.h>
#include <string.h>
#include "windows_worker_fixture.h"

static yaca_worker_fixture *fixture_context;

/* Allocate a production block while observing ownership from host memory outside this DLL.
 * @param length size_t Number of bytes requested by the production startup path.
 * @return void* Owned allocation, or NULL when the host allocator fails.
 * @effect Atomically counts successful native allocations; Lua heap allocation is not intercepted.
 */
static void *fixture_malloc(size_t length)
{
  void *pointer = malloc(length);
  assert(fixture_context != NULL);
  if (pointer != NULL) InterlockedIncrement(&fixture_context->live_blocks);
  return pointer;
}

/* Allocate zeroed production storage under the same host-owned native accounting.
 * @param count size_t Number of elements requested by production.
 * @param length size_t Bytes per element; production supplies bounded sizes.
 * @return void* Owned zeroed allocation, or NULL on actual allocation failure.
 * @effect Increments the native allocation count only for successful allocation.
 */
static void *fixture_calloc(size_t count, size_t length)
{
  void *pointer = fixture_malloc(count * length);
  if (pointer != NULL) memset(pointer, 0, count * length);
  return pointer;
}

/* Release a production allocation and update observations that survive DLL unload.
 * @param pointer void* Owned native block, or NULL for absent optional storage.
 * @return void No value; NULL requires no work.
 * @effect Atomically removes a live block and frees its bytes.
 * @error Aborts on excess release, detecting duplicate cleanup.
 */
static void fixture_free(void *pointer)
{
  if (pointer != NULL)
  {
    assert(InterlockedDecrement(&fixture_context->live_blocks) >= 0);
    free(pointer);
  }
}

/* Keep actual production IO active until the host observes Lua-driven DLL unloading.
 * @param writer int Nonzero selects the optional separate writer gate; zero selects the reader or shared gate.
 * @return int One when released by the host; zero with ERROR_TIMEOUT after ten seconds.
 * @effect Signals entry and blocks only on the probe's private synchronization event.
 */
static int fixture_wait_for_release(int writer)
{
  HANDLE gate = writer && fixture_context->writer_release != NULL
    ? fixture_context->writer_release : fixture_context->release;
  InterlockedIncrement(&fixture_context->entered_count);
  assert(SetEvent(fixture_context->entered));
  if (WaitForSingleObject(gate, 10000U) != WAIT_OBJECT_0)
  {
    SetLastError(ERROR_TIMEOUT);
    return 0;
  }
  InterlockedIncrement(&fixture_context->io_completed);
  return 1;
}

/* Model cooked input while the real production worker remains active inside the DLL.
 * @param input HANDLE Borrowed production input, not accessed by this double.
 * @param buffer LPVOID Production-owned wide buffer receiving a four-character line.
 * @param requested DWORD Available wide-character capacity, required to hold the fixture line.
 * @param received LPDWORD Output count receiving four characters after release.
 * @param control LPVOID Reserved argument, required to be NULL.
 * @return BOOL TRUE for the fixture line, FALSE for timeout or the configured read error.
 * @effect Waits on a private event and writes only the production-owned buffer.
 */
static BOOL WINAPI fixture_read_console(
  HANDLE input, LPVOID buffer, DWORD requested, LPDWORD received, LPVOID control)
{
  (void)input;
  assert(requested >= 4U && control == NULL);
  if (!fixture_wait_for_release(0)) return FALSE;
  if (fixture_context->io_error)
  {
    SetLastError(ERROR_READ_FAULT);
    return FALSE;
  }
  memcpy(buffer, L"ok\r\n", 4U * sizeof(WCHAR));
  *received = 4U;
  return TRUE;
}

/* Force emergency reader detach without writing into a user console.
 * @param input HANDLE Borrowed input, unused by this deterministic cancellation double.
 * @param records const_INPUT_RECORD* Production cancellation record, required to be a key event.
 * @param count DWORD Number of records requested, required to be one.
 * @param written LPDWORD Output count set to zero on this failure.
 * @return BOOL Always FALSE with ERROR_ACCESS_DENIED.
 * @effect Preserves the live reader so Lua GC must release its owner independently.
 */
static BOOL WINAPI fixture_write_console(
  HANDLE input, const INPUT_RECORD *records, DWORD count, LPDWORD written)
{
  (void)input;
  assert(count == 1U && records->EventType == KEY_EVENT);
  *written = 0U;
  SetLastError(ERROR_ACCESS_DENIED);
  return FALSE;
}

/* Model blocked stdin writing on the actual pipe owned by the production worker.
 * @param pipe HANDLE Actual transferred write handle, checked against the fixture input.
 * @param bytes LPCVOID Exact three-byte payload supplied to the writer.
 * @param length DWORD Requested byte count, required to be three.
 * @param written LPDWORD Output receiving the exact accepted byte count.
 * @param overlapped LPOVERLAPPED Optional asynchronous state, required to be NULL.
 * @return BOOL TRUE after release, FALSE on timeout or the configured write error.
 * @effect Waits on private synchronization; production still closes its real pipe handle afterward.
 */
static BOOL WINAPI fixture_write_file(
  HANDLE pipe, LPCVOID bytes, DWORD length, LPDWORD written, LPOVERLAPPED overlapped)
{
  assert(pipe == fixture_context->pipe && length == 3U && overlapped == NULL);
  assert(memcmp(bytes, "abc", 3U) == 0);
  if (!fixture_wait_for_release(1)) return FALSE;
  if (fixture_context->io_error)
  {
    SetLastError(ERROR_WRITE_FAULT);
    return FALSE;
  }
  *written = length;
  return TRUE;
}

/* Acquire a real module reference, optionally refusing lookup or retention before thread startup.
 * @param flags DWORD Production GetModuleHandleEx flags, passed through unchanged.
 * @param address LPCWSTR Native module name or code/data address selected by production.
 * @param module HMODULE* Output module reference, cleared on the configured failure.
 * @return BOOL Actual lookup result, or FALSE with ERROR_MOD_NOT_FOUND for the selected control.
 * @effect Counts module API calls; successful retention changes the real loader reference count.
 */
static BOOL WINAPI fixture_get_module(DWORD flags, LPCWSTR address, HMODULE *module)
{
  if (fixture_context != NULL)
  {
    ++fixture_context->lookup_calls;
    if (fixture_context->fail_module == 1
        || (fixture_context->fail_module == 2
            && (flags & GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT) == 0U))
    {
      *module = NULL;
      SetLastError(ERROR_MOD_NOT_FOUND);
      return FALSE;
    }
  }
  return GetModuleHandleExW(flags, address, module);
}

/* Start an actual worker, optionally failing creation or joining it before the caller receives its handle.
 * @param attributes LPSECURITY_ATTRIBUTES Production security attributes.
 * @param stack SIZE_T Requested stack size, passed unchanged to CreateThread.
 * @param callback LPTHREAD_START_ROUTINE Actual production reader or writer callback.
 * @param context LPVOID Independently allocated production worker record.
 * @param flags DWORD Production creation flags.
 * @param identifier LPDWORD Optional thread identifier output.
 * @return HANDLE Real owned thread handle, or NULL with ERROR_NOT_ENOUGH_MEMORY for the setup control.
 * @effect Creates only bounded fixture workers and may wait for their early completion.
 */
static HANDLE WINAPI fixture_create_thread(
  LPSECURITY_ATTRIBUTES attributes, SIZE_T stack, LPTHREAD_START_ROUTINE callback,
  LPVOID context, DWORD flags, LPDWORD identifier)
{
  HANDLE thread;
  if (fixture_context->fail_thread)
  {
    SetLastError(ERROR_NOT_ENOUGH_MEMORY);
    return NULL;
  }
  thread = CreateThread(attributes, stack, callback, context, flags, identifier);
  if (thread != NULL && fixture_context->early_exit)
    assert(WaitForSingleObject(thread, 10000U) == WAIT_OBJECT_0);
  return thread;
}

#define malloc fixture_malloc
#define calloc fixture_calloc
#define free fixture_free
#define ReadConsoleW fixture_read_console
#define WriteConsoleInputW fixture_write_console
#define WriteFile fixture_write_file
#define GetModuleHandleExW fixture_get_module
#define CreateThread fixture_create_thread
#include "../../native/yaca_native.c"
#undef CreateThread
#undef GetModuleHandleExW
#undef WriteFile
#undef WriteConsoleInputW
#undef ReadConsoleW
#undef free
#undef calloc
#undef malloc

/* Launch a production worker whose owner is an actual Lua userdata collected by lua_close.
 * @param L lua_State* Arguments are the host-owned fixture lightuserdata and zero for reader or one for writer.
 * @return int One native owner userdata on success; two values containing false/error on native startup failure.
 * @effect Creates the requested worker and retains a separate host observer handle after successful launch.
 * @ownership The host context outlives the worker; a successful writer exclusively owns the supplied pipe handle.
 */
static int fixture_start(lua_State *L)
{
  int writer;
  HANDLE thread;
  fixture_context = (yaca_worker_fixture *)lua_touserdata(L, 1);
  assert(fixture_context != NULL);
  writer = (int)luaL_checkinteger(L, 2);
  if (writer)
  {
    yaca_process *process = push_process(L);
    strcpy(process->outcome, "completed");
    process->input_writer = start_process_input(fixture_context->pipe, "abc", 3U);
    if (process->input_writer == NULL)
    {
      fixture_context->setup_error = GetLastError();
      return push_windows_failure(L, fixture_context->setup_error, "fixture writer setup failed");
    }
    fixture_context->pipe_transferred = 1;
    thread = process->input_writer->thread;
  }
  else
  {
    yaca_terminal *terminal = push_terminal(L);
    terminal->cooked_mode = 1;
    terminal->maximum_input_bytes = 8192U;
    if (!start_windows_cooked_read(terminal))
    {
      fixture_context->setup_error = GetLastError();
      return push_windows_failure(L, fixture_context->setup_error, "fixture reader setup failed");
    }
    thread = terminal->cooked_read->thread;
  }
  assert(DuplicateHandle(GetCurrentProcess(), thread, GetCurrentProcess(),
    &fixture_context->observer, 0U, FALSE, DUPLICATE_SAME_ACCESS));
  return 1;
}

/* Expose the fixture startup function from the actual DLL loaded by Lua's production loadlib.
 * @param L lua_State* State receiving the fixture module table and production owner metatables.
 * @return int One module table with the start entry point.
 * @effect Registers the real process and terminal finalizers without starting any IO.
 */
int luaopen_windows_worker_lifetime_fixture(lua_State *L)
{
  HMODULE module;
  assert(fixture_get_module(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS
    | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT, (LPCWSTR)&fixture_context, &module));
  create_handle_metatable(L, YACA_PROCESS_METATABLE, l_process_gc);
  create_handle_metatable(L, YACA_TERMINAL_METATABLE, l_terminal_gc);
  lua_createtable(L, 0, 1);
  lua_pushcfunction(L, fixture_start);
  lua_setfield(L, -2, "start");
  return 1;
}
