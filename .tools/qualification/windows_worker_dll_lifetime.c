/*
Author: WaterRun
Date: 2026-10-08
File: windows_worker_dll_lifetime.c
Description: Loads an instrumented production native DLL through real Lua
package.loadlib, destroys the Lua state while a reader/writer remains active,
and verifies code mapping, final thread join and native/module resource release.
*/

#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0501
#endif
#include <windows.h>
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#include "windows_worker_dll_fixture.h"

/* Count current process handles without retaining an observation handle.
 * @param none Uses only this isolated qualification process.
 * @return DWORD Exact OS handle count.
 * @error Aborts when the OS cannot supply the count.
 */
static DWORD lifetime_handles(void)
{
  DWORD count;
  assert(GetProcessHandleCount(GetCurrentProcess(), &count));
  return count;
}

/* Use Lua's real library-string ownership rather than a host-owned LoadLibrary reference.
 * @param L lua_State* Fresh state with package.loadlib opened.
 * @param path const_char* Exact probe DLL path supplied by the serial target runner.
 * @return int Registry reference to the opened production/fixture function table.
 * @effect Loads the actual DLL through Lua and invokes its qualification opener.
 * @error Aborts on load/open failure; the caller retains the raw diagnostic transcript.
 */
static int lifetime_load(lua_State *L, const char *path)
{
  int reference;
  lua_getglobal(L, "package"); lua_getfield(L, -1, "loadlib");
  lua_pushstring(L, path); lua_pushliteral(L, "luaopen_worker_dll_probe");
  assert(lua_pcall(L, 2, 1, 0) == LUA_OK && lua_isfunction(L, -1));
  assert(lua_pcall(L, 0, 1, 0) == LUA_OK && lua_istable(L, -1));
  reference = luaL_ref(L, LUA_REGISTRYINDEX);
  lua_settop(L, 0);
  return reference;
}

/* Bind a host fixture whose lifetime deliberately exceeds this Lua state's lifetime.
 * @param L lua_State* State retaining the qualification module table.
 * @param reference int Registry reference to that table.
 * @param fixture worker_dll_fixture* Host-owned gates and atomic counters valid until thread join.
 * @return void No value; clears the protected call's Lua stack.
 * @effect Stores only a borrowed host pointer in the fixture DLL.
 */
static void lifetime_bind(lua_State *L, int reference, worker_dll_fixture *fixture)
{
  lua_rawgeti(L, LUA_REGISTRYINDEX, reference); lua_getfield(L, -1, "_probe_bind");
  lua_pushlightuserdata(L, fixture);
  assert(lua_pcall(L, 1, 0, 0) == LUA_OK);
  lua_settop(L, 0);
}

/* Start a real production worker with finalizable ownership and copy only its independent observer handles.
 * @param L lua_State* State retaining the qualification module.
 * @param reference int Registry reference to its function table.
 * @param profile const_char* Reader or writer fixture selecting the production helper.
 * @param reader HANDLE* Receives the host-owned pipe read end for a writer, otherwise NULL.
 * @return HANDLE Independent real thread observation handle, or NULL after injected setup failure.
 * @effect Keeps the returned owner on the Lua stack until actual state destruction.
 */
static HANDLE lifetime_start(lua_State *L, int reference, const char *profile, HANDLE *reader)
{
  HANDLE observer;
  lua_rawgeti(L, LUA_REGISTRYINDEX, reference);
  lua_getfield(L, -1, strcmp(profile, "reader") == 0 ? "_probe_start_reader" : "_probe_start_writer");
  assert(lua_pcall(L, 0, 3, 0) == LUA_OK && lua_isuserdata(L, -3));
  observer = (HANDLE)lua_touserdata(L, -2);
  *reader = (HANDLE)lua_touserdata(L, -1);
  return observer;
}

/* Determine whether a borrowed code address still belongs to a committed DLL image without executing it.
 * @param address LPCVOID Borrowed opener address obtained while the DLL was loaded.
 * @return int One for a committed image mapping; zero after that image is unmapped.
 * @effect Queries memory state only; does not acquire or release a library reference.
 */
static int lifetime_mapped(LPCVOID address)
{
  MEMORY_BASIC_INFORMATION information;
  assert(VirtualQuery(address, &information, sizeof(information)) == sizeof(information));
  return information.State == MEM_COMMIT && information.Type == MEM_IMAGE;
}

/* Prove actual Lua unload safety for one worker, or fail safely before a broken baseline can resume unmapped code.
 * @param argc int Three arguments for a lifetime run, or four with setup-failure selector one/two/three.
 * @param argv char** Probe DLL path, reader/writer profile and optional deterministic failure selector.
 * @return int Zero after complete lifetime/recovery checks; one for confirmed baseline unload of live worker code; 64 for bad arguments.
 * @effect Owns two gate events and an independent join handle; no console, network or child process is used.
 * @ownership A broken baseline exits its isolated process while the thread is still gated, without executing an unmapped return path.
 * @error Assertions stop unexpected fixture/API failures; raw transcripts preserve their diagnostics.
 */
int main(int argc, char **argv)
{
  worker_dll_fixture fixture;
  lua_State *L;
  HANDLE observer;
  HANDLE reader;
  HMODULE loaded;
  DWORD baseline;
  int reference;
  int before;
  int after;
  int failure = 0;
  /* @struct opener_address Flat Windows address view used only for non-executing mapping observation.
   * @field function FARPROC Borrowed actual DLL opener returned by GetProcAddress.
   * @field address LPCVOID Same address bits passed to VirtualQuery, never dereferenced by this host.
   */
  union { FARPROC function; LPCVOID address; } opener_address;
  if ((argc != 3 && argc != 4)
      || (strcmp(argv[2], "reader") != 0 && strcmp(argv[2], "writer") != 0)) return 64;
  if (argc == 4)
  {
    failure = atoi(argv[3]);
    if (failure < 1 || failure > 3) return 64;
  }
  memset(&fixture, 0, sizeof(fixture));
  fixture.entered = CreateEventW(NULL, TRUE, FALSE, NULL);
  fixture.release = CreateEventW(NULL, TRUE, FALSE, NULL);
  assert(fixture.entered != NULL && fixture.release != NULL);
  fixture.fail_module_at = failure < 3 ? failure : 0;
  fixture.fail_thread = failure == 3;
  L = luaL_newstate(); assert(L != NULL);
  luaL_openlibs(L);
  if (strcmp(argv[2], "writer") == 0)
  {
    HANDLE warm_reader;
    HANDLE warm_writer;
    DWORD before_warmup = lifetime_handles();
    /* Measure first-use OS pipe initialization independently of the native
    ** DLL; both handles returned by this control are explicitly closed. */
    assert(CreatePipe(&warm_reader, &warm_writer, NULL, 0U));
    assert(CloseHandle(warm_reader) && CloseHandle(warm_writer));
    printf("worker-dll-pipe-warmup before=%lu after=%lu\n",
      (unsigned long)before_warmup, (unsigned long)lifetime_handles());
  }
  baseline = lifetime_handles();
  assert(GetModuleHandleW(L"worker_dll_probe.dll") == NULL);
  reference = lifetime_load(L, argv[1]);
  loaded = GetModuleHandleW(L"worker_dll_probe.dll"); assert(loaded != NULL);
  opener_address.function = GetProcAddress(loaded, "luaopen_worker_dll_probe");
  assert(opener_address.function != NULL);
  before = lifetime_mapped(opener_address.address);
  assert(before);
  lifetime_bind(L, reference, &fixture);
  observer = lifetime_start(L, reference, argv[2], &reader);
  if (failure != 0)
  {
    assert(observer == NULL && reader == NULL);
    assert(fixture.startup_error == (failure == 3 ? ERROR_NOT_ENOUGH_MEMORY : ERROR_ACCESS_DENIED));
    assert(fixture.native_live == 0 && fixture.module_references == 0);
    lua_close(L);
    assert(GetModuleHandleW(L"worker_dll_probe.dll") == NULL);
    assert(lifetime_handles() == baseline);
    assert(CloseHandle(fixture.entered) && CloseHandle(fixture.release));
    printf("worker-dll-startup profile=%s failure=%d native-live=%ld module-references=%ld result=PASS\n",
      argv[2], failure, (long)fixture.native_live, (long)fixture.module_references);
    return 0;
  }
  assert(observer != NULL && fixture.startup_error == 0U);
  assert(WaitForSingleObject(fixture.entered, 20000U) == WAIT_OBJECT_0);
  assert(WaitForSingleObject(observer, 0U) == WAIT_TIMEOUT);
  lua_close(L);
  after = lifetime_mapped(opener_address.address);
  printf("worker-dll profile=%s module-before=%d module-after-state-close=%d thread-live=%d native-live=%ld module-references=%ld\n",
    argv[2], before, after, WaitForSingleObject(observer, 0U) == WAIT_TIMEOUT,
    (long)fixture.native_live, (long)fixture.module_references);
  fflush(stdout);
  if (!after)
  {
    /* Keep the broken thread gated. ExitProcess reclaims this owned fixture
    ** without resuming a DLL frame that has already been unmapped. */
    ExitProcess(1U);
  }
  assert(GetModuleHandleW(L"worker_dll_probe.dll") != NULL);
  assert(fixture.native_live == 2 && fixture.module_references == 1);
  assert(SetEvent(fixture.release));
  assert(WaitForSingleObject(observer, 20000U) == WAIT_OBJECT_0);
  assert(fixture.native_live == 0 && fixture.module_references == 0);
  assert(GetModuleHandleW(L"worker_dll_probe.dll") == NULL);
  assert(!lifetime_mapped(opener_address.address));
  assert(CloseHandle(observer));
  if (reader != NULL) assert(CloseHandle(reader));
  printf("worker-dll-handle-count profile=%s before=%lu after=%lu\n",
    argv[2], (unsigned long)baseline, (unsigned long)lifetime_handles());
  if (strcmp(argv[2], "writer") == 0)
  {
    DWORD flags;
    printf("worker-dll-pipe closes=%ld write-handle-live=%d reader=%p observer=%p writer=%p\n",
      (long)fixture.pipe_closes, GetHandleInformation(fixture.write_pipe, &flags) != 0,
      reader, observer, fixture.write_pipe);
  }
  fflush(stdout);
  assert(lifetime_handles() == baseline);
  assert(CloseHandle(fixture.entered) && CloseHandle(fixture.release));
  printf("worker-dll-final profile=%s native-live=0 module-references=0 module-unmapped=1 handles-stable=1 result=PASS\n", argv[2]);
  return 0;
}
