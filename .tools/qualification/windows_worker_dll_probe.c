/*
Author: WaterRun
Date: 2026-10-08
File: windows_worker_dll_probe.c
Description: Builds production native reader/writer functions into a real DLL
with host-gated I/O and resource observations for Lua unload lifetime tests.
Its private Lua exports belong only to this qualification module.
*/

#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0501
#endif
#include <windows.h>
#include <assert.h>
#include <stdlib.h>
#include <string.h>
#include "lua.h"
#include "lauxlib.h"
#include "windows_worker_dll_fixture.h"

/* Lua's imported functions retain LUA_API; the included module's own opener
** must be an export so this qualification opener can call it inside its DLL. */
#undef LUAMOD_API
#define LUAMOD_API __declspec(dllexport)

static worker_dll_fixture *worker_fixture;
static HANDLE worker_observer;

/* Allocate one observed production block without counting Lua/library allocations.
 * @param bytes size_t Requested native allocation size.
 * @return void* Real allocation or NULL on system failure.
 * @effect Atomically increments host-owned native_live after a successful allocation.
 */
static void *worker_malloc(size_t bytes)
{
  void *pointer = malloc(bytes);
  if (pointer != NULL) { assert(worker_fixture != NULL); InterlockedIncrement(&worker_fixture->native_live); }
  return pointer;
}

/* Allocate observed zero-initialized production state.
 * @param count size_t Number of requested elements.
 * @param bytes size_t Byte size per element.
 * @return void* Real zeroed allocation or NULL on failure.
 * @effect Atomically increments the native block count only on success.
 */
static void *worker_calloc(size_t count, size_t bytes)
{
  void *pointer = calloc(count, bytes);
  if (pointer != NULL) { assert(worker_fixture != NULL); InterlockedIncrement(&worker_fixture->native_live); }
  return pointer;
}

/* Release an observed production block on the terminal or worker thread.
 * @param pointer void* Owned allocation, or NULL for a no-op.
 * @return void No value; decrements host-owned resource truth before freeing.
 * @error Aborts if a duplicate/foreign free would make the observed count negative.
 */
static void worker_free(void *pointer)
{
  if (pointer == NULL) return;
  assert(worker_fixture != NULL && InterlockedDecrement(&worker_fixture->native_live) >= 0);
  free(pointer);
}

/* Hold the real production cooked reader in a bounded console I/O double.
 * @param input HANDLE Borrowed fixture sentinel, ignored without touching host console input.
 * @param buffer LPVOID Owned production wide buffer, used only while the worker remains alive.
 * @param requested DWORD Available wide capacity, at least three for this fixture.
 * @param received LPDWORD Receives the exact completed line length.
 * @param control LPVOID Must be NULL as required by the production reader.
 * @return BOOL TRUE after the host explicitly releases the twenty-second bounded gate.
 * @effect Signals worker entry, waits, then writes a fixed non-secret line.
 */
static BOOL WINAPI worker_read_console(HANDLE input, LPVOID buffer,
  DWORD requested, LPDWORD received, LPVOID control)
{
  WCHAR *wide = (WCHAR *)buffer;
  (void)input;
  assert(control == NULL && requested >= 3U && worker_fixture != NULL);
  assert(SetEvent(worker_fixture->entered));
  assert(WaitForSingleObject(worker_fixture->release, 20000U) == WAIT_OBJECT_0);
  wide[0] = L'x'; wide[1] = L'\r'; wide[2] = L'\n';
  *received = 3U;
  return TRUE;
}

/* Reject emergency synthetic Enter while the reader remains in its independent gate.
 * @param input HANDLE Fixture sentinel, never sent to an actual console API.
 * @param records const_INPUT_RECORD* Borrowed production cancellation record.
 * @param count DWORD Single-record cancellation request.
 * @param written LPDWORD Receives zero accepted records.
 * @return BOOL FALSE with ERROR_ACCESS_DENIED.
 * @effect Leaves the actual reader blocked until the host resumes it or ends the isolated baseline process.
 */
static BOOL WINAPI worker_write_console(HANDLE input,
  const INPUT_RECORD *records, DWORD count, LPDWORD written)
{
  (void)input;
  assert(records != NULL && count == 1U);
  *written = 0U;
  SetLastError(ERROR_ACCESS_DENIED);
  return FALSE;
}

/* Hold the production stdin writer before reporting normal peer closure.
 * @param file HANDLE Real fixture pipe owned by the production writer.
 * @param bytes LPCVOID Borrowed non-secret bytes already copied into its native record.
 * @param requested DWORD One-byte write used by this fixture.
 * @param written LPDWORD Receives zero bytes accepted by the simulated closed peer.
 * @param overlapped LPOVERLAPPED Required NULL for synchronous production writes.
 * @return BOOL FALSE with ERROR_BROKEN_PIPE after host release.
 * @effect Gates only this write; production still closes its real owned pipe and releases its record.
 */
static BOOL WINAPI worker_write_file(HANDLE file, LPCVOID bytes,
  DWORD requested, LPDWORD written, LPOVERLAPPED overlapped)
{
  assert(file != NULL && file != INVALID_HANDLE_VALUE && bytes != NULL);
  assert(requested == 1U && overlapped == NULL && worker_fixture != NULL);
  assert(SetEvent(worker_fixture->entered));
  assert(WaitForSingleObject(worker_fixture->release, 20000U) == WAIT_OBJECT_0);
  *written = 0U;
  SetLastError(ERROR_BROKEN_PIPE);
  return FALSE;
}

/* Start an actual native worker and retain a separate host observation handle.
 * @param security LPSECURITY_ATTRIBUTES Borrowed thread attributes passed through unchanged.
 * @param stack_size SIZE_T Requested stack size passed through unchanged.
 * @param entry LPTHREAD_START_ROUTINE Actual production reader/writer entry.
 * @param opaque LPVOID Actual production heap record passed through unchanged.
 * @param flags DWORD Thread creation flags passed through unchanged.
 * @param identifier LPDWORD Optional OS identifier destination passed through unchanged.
 * @return HANDLE Real production handle, or NULL for an injected/system startup failure.
 * @effect Duplicates a successful handle for a host join that survives Lua finalization.
 */
static HANDLE WINAPI worker_create_thread(LPSECURITY_ATTRIBUTES security,
  SIZE_T stack_size, LPTHREAD_START_ROUTINE entry, LPVOID opaque,
  DWORD flags, LPDWORD identifier)
{
  HANDLE thread;
  assert(worker_fixture != NULL);
  if (worker_fixture->fail_thread) { SetLastError(ERROR_NOT_ENOUGH_MEMORY); return NULL; }
  thread = CreateThread(security, stack_size, entry, opaque, flags, identifier);
  if (thread != NULL)
  {
    assert(worker_observer == NULL);
    assert(DuplicateHandle(GetCurrentProcess(), thread, GetCurrentProcess(),
      &worker_observer, 0U, FALSE, DUPLICATE_SAME_ACCESS));
  }
  return thread;
}

/* Observe or reject production module resolution without altering Lua's loader reference.
 * @param flags DWORD Original GetModuleHandleExW flags.
 * @param name LPCWSTR Borrowed module name/address passed unchanged to the OS.
 * @param module HMODULE* Receives the actual borrowed/retained module or NULL on rejection.
 * @return BOOL Actual OS result, or FALSE with ERROR_ACCESS_DENIED at the selected call.
 * @effect Counts only references actually acquired by production, excluding unchanged-refcount queries.
 */
BOOL WINAPI worker_get_module_handle(DWORD flags, LPCWSTR name, HMODULE *module)
{
  BOOL result;
  assert(worker_fixture != NULL);
  if (++worker_fixture->module_calls == worker_fixture->fail_module_at)
  {
    *module = NULL;
    SetLastError(ERROR_ACCESS_DENIED);
    return FALSE;
  }
  result = GetModuleHandleExW(flags, name, module);
  if (result && !(flags & GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT))
    InterlockedIncrement(&worker_fixture->module_references);
  return result;
}

/* Observe release of a production module reference when thread creation fails.
 * @param module HMODULE Worker reference acquired by the production module resolver.
 * @return BOOL Actual FreeLibrary result.
 * @effect Decrements the observation before releasing; this wrapper does not observe Lua's independent loader cleanup.
 */
BOOL WINAPI worker_free_library(HMODULE module)
{
  assert(worker_fixture != NULL && InterlockedDecrement(&worker_fixture->module_references) >= 0);
  return FreeLibrary(module);
}

/* Release the worker's code reference using the actual atomic Windows exit operation.
 * @param module HMODULE Owned worker DLL reference passed unchanged to the OS.
 * @param outcome DWORD Actual worker exit code passed through unchanged.
 * @return void Does not return; the calling thread terminates after its module reference is released.
 * @effect Updates the host observation before FreeLibraryAndExitThread can unmap this DLL.
 */
VOID WINAPI worker_free_library_and_exit(HMODULE module, DWORD outcome)
{
  assert(worker_fixture != NULL && InterlockedDecrement(&worker_fixture->module_references) >= 0);
  FreeLibraryAndExitThread(module, outcome);
}

/* Observe the actual owned pipe close without replacing Windows handle semantics.
 * @param handle HANDLE Production-owned OS handle passed unchanged to CloseHandle.
 * @return BOOL Actual OS close result.
 * @effect Counts only successful closes of the recorded writer pipe; other handle closes pass through unchanged.
 */
static BOOL WINAPI worker_close_handle(HANDLE handle)
{
  BOOL result = CloseHandle(handle);
  if (result && worker_fixture != NULL && handle == worker_fixture->write_pipe)
    InterlockedIncrement(&worker_fixture->pipe_closes);
  return result;
}

#define malloc worker_malloc
#define calloc worker_calloc
#define free worker_free
#define ReadConsoleW worker_read_console
#define WriteConsoleInputW worker_write_console
#define WriteFile worker_write_file
#define CreateThread worker_create_thread
#define CloseHandle worker_close_handle
#define GetModuleHandleExW worker_get_module_handle
#define FreeLibrary worker_free_library
#define FreeLibraryAndExitThread worker_free_library_and_exit
#include "../../native/yaca_native.c"
#undef malloc
#undef calloc
#undef free
#undef ReadConsoleW
#undef WriteConsoleInputW
#undef WriteFile
#undef CreateThread
#undef CloseHandle
#undef GetModuleHandleExW
#undef FreeLibrary
#undef FreeLibraryAndExitThread

/* Bind host-owned gates and observations before any production resource is acquired.
 * @param L lua_State* Argument one is the host's lightuserdata fixture pointer.
 * @return int Zero Lua results after binding the borrowed fixture.
 * @ownership The host keeps this fixture valid until its independent worker join or isolated process exit.
 */
static int worker_bind(lua_State *L)
{
  worker_fixture = (worker_dll_fixture *)lua_touserdata(L, 1);
  assert(worker_fixture != NULL && worker_fixture->entered != NULL && worker_fixture->release != NULL);
  return 0;
}

/* Start a production cooked reader attached to genuinely finalizable Lua terminal ownership.
 * @param L lua_State* No arguments; uses the previously bound fixture.
 * @return int Three results: actual terminal userdata, observer handle or nil, and nil for no extra pipe.
 * @effect Starts the actual reader helper; records its real setup failure before Lua finalization.
 */
static int worker_start_reader(lua_State *L)
{
  yaca_terminal *terminal = push_terminal(L);
  terminal->maximum_input_bytes = 64U;
  terminal->cooked_mode = 1;
  terminal->restored = 1;
  if (!start_windows_cooked_read(terminal)) worker_fixture->startup_error = GetLastError();
  if (worker_observer != NULL) lua_pushlightuserdata(L, worker_observer);
  else lua_pushnil(L);
  lua_pushnil(L);
  return 3;
}

/* Start the production stdin writer attached to a genuinely finalizable Lua process owner.
 * @param L lua_State* No arguments; uses the previously bound fixture and one owned anonymous pipe.
 * @return int Three results: process userdata, observer handle or nil, and host-owned pipe read handle or nil.
 * @effect Starts only the actual writer helper, without a child process; closes caller-owned pipe ends after setup failure.
 * @ownership A successful writer owns the write end; the host closes the returned read end after join.
 */
static int worker_start_writer(lua_State *L)
{
  HANDLE reader;
  HANDLE writer;
  yaca_process *process = push_process(L);
  strcpy(process->outcome, "completed");
  assert(CreatePipe(&reader, &writer, NULL, 0U));
  worker_fixture->write_pipe = writer;
  process->input_writer = start_process_input(writer, "x", 1U);
  if (process->input_writer == NULL)
  {
    worker_fixture->startup_error = GetLastError();
    assert(CloseHandle(reader) && CloseHandle(writer));
    reader = NULL;
  }
  if (worker_observer != NULL) lua_pushlightuserdata(L, worker_observer);
  else lua_pushnil(L);
  if (reader != NULL) lua_pushlightuserdata(L, reader);
  else lua_pushnil(L);
  return 3;
}

/* Open production native types plus three fixture-only Lua controls in this qualification DLL.
 * @param L lua_State* State whose real package.loadlib loader owns this module reference.
 * @return int One table containing the production functions and fixture bind/start controls.
 * @effect Installs the actual native metatables; adds no fixture export to the product source module.
 */
__declspec(dllexport) int luaopen_worker_dll_probe(lua_State *L)
{
  luaopen_yaca_native(L);
  lua_pushcfunction(L, worker_bind); lua_setfield(L, -2, "_probe_bind");
  lua_pushcfunction(L, worker_start_reader); lua_setfield(L, -2, "_probe_start_reader");
  lua_pushcfunction(L, worker_start_writer); lua_setfield(L, -2, "_probe_start_writer");
  return 1;
}
