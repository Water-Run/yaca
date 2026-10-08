/*
Author: WaterRun
Date: 2026-10-08
File: windows_worker_lifetime_smoke.c
Description: Loads a real worker fixture DLL through Lua loadlib, closes the Lua state while workers remain live, and verifies eventual module/resource release and setup cleanup.
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
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#include "windows_worker_fixture.h"

/* Query the current process's actual handle ownership before or after the worker cycle.
 * @param none No arguments.
 * @return DWORD Current owned OS handle count.
 * @error Aborts if the process resource query fails.
 */
static DWORD fixture_handles(void)
{
  DWORD count;
  assert(GetProcessHandleCount(GetCurrentProcess(), &count));
  return count;
}

/* Use actual Lua package.loadlib, then call the DLL's exported fixture module opener.
 * @param L lua_State* Open state with the package standard library available.
 * @param path const_char* ASCII absolute fixture DLL path supplied by the guarded driver.
 * @return void No value; leaves the actual module table on the Lua stack.
 * @effect Loads the native DLL under Lua's own library lifetime bookkeeping.
 * @error Aborts on a loader or module-opening failure.
 */
static void fixture_load(lua_State *L, const char *path)
{
  lua_getglobal(L, "package");
  lua_getfield(L, -1, "loadlib");
  lua_remove(L, -2);
  lua_pushstring(L, path);
  lua_pushstring(L, "luaopen_windows_worker_lifetime_fixture");
  assert(lua_pcall(L, 2, 2, 0) == LUA_OK);
  if (!lua_isfunction(L, -2))
  {
    fprintf(stderr, "loadlib failed: %s\n", lua_tostring(L, -1));
    abort();
  }
  lua_pop(L, 1);
  assert(lua_pcall(L, 0, 1, 0) == LUA_OK && lua_istable(L, -1));
}

/* Close the independent host observations after the worker and its DLL are gone.
 * @param fixture yaca_worker_fixture* Host context whose remaining handles are released.
 * @param read_pipe HANDLE Host-owned reader end, or NULL for the console case.
 * @return void No value; all remaining probe-owned handles are closed.
 * @effect Closes the untransferred write handle, observer and synchronization events.
 */
static void fixture_cleanup(yaca_worker_fixture *fixture, HANDLE read_pipe)
{
  if (fixture->observer != NULL) assert(CloseHandle(fixture->observer));
  if (fixture->writer_release != NULL) assert(CloseHandle(fixture->writer_release));
  if (read_pipe != NULL)
  {
    if (!fixture->pipe_transferred) assert(CloseHandle(fixture->pipe));
    assert(CloseHandle(read_pipe));
  }
  assert(CloseHandle(fixture->entered) && CloseHandle(fixture->release));
}

/* Verify one actual Lua-close boundary without letting an unmapped baseline callback resume.
 * @param argc int Four arguments select executable, DLL path, reader/writer, and fault mode.
 * @param argv char** Process arguments; reader/writer accept normal, io-error, module-query, module-retain, thread-start and early-exit; both accepts normal.
 * @return int Zero after correct module retention/release and resource cleanup; usage errors return 64.
 * @effect Warms Lua/pipe initialization, creates private events and an optional pipe, starts one or two bounded DLL workers, and closes their Lua state.
 * @error Aborts on inconsistent setup/cleanup; an unmapped live baseline worker causes immediate ExitProcess(1).
 */
int main(int argc, char **argv)
{
  yaca_worker_fixture fixture;
  lua_State *L;
  HANDLE read_pipe = NULL;
  HANDLE writer_observer = NULL;
  DWORD baseline;
  DWORD exit_code = 0U;
  int writer;
  int expected_failure;
  int started;
  int resident;
  int both;
  if (argc != 4) return 64;
  both = strcmp(argv[2], "both") == 0;
  writer = both || strcmp(argv[2], "writer") == 0;
  if (!writer && strcmp(argv[2], "reader") != 0) return 64;
  memset(&fixture, 0, sizeof(fixture));
  if (strcmp(argv[3], "io-error") == 0) fixture.io_error = 1;
  else if (strcmp(argv[3], "module-query") == 0) fixture.fail_module = 1;
  else if (strcmp(argv[3], "module-retain") == 0) fixture.fail_module = 2;
  else if (strcmp(argv[3], "thread-start") == 0) fixture.fail_thread = 1;
  else if (strcmp(argv[3], "early-exit") == 0) fixture.early_exit = 1;
  else if (strcmp(argv[3], "normal") != 0) return 64;
  if (both && strcmp(argv[3], "normal") != 0) return 64;
  expected_failure = fixture.fail_module != 0 || fixture.fail_thread;
  SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX);
  /* Complete one-time standard-library initialization before measuring worker ownership. */
  L = luaL_newstate();
  assert(L != NULL);
  luaL_openlibs(L);
  lua_close(L);
  if (writer)
  {
    HANDLE warm_read;
    HANDLE warm_write;
    /* Initialize process-global pipe support before counting each worker's owned handles. */
    assert(CreatePipe(&warm_read, &warm_write, NULL, 0U));
    assert(CloseHandle(warm_read) && CloseHandle(warm_write));
  }
  baseline = fixture_handles();
  fixture.entered = CreateEventW(NULL, TRUE, FALSE, NULL);
  fixture.release = CreateEventW(NULL, TRUE, fixture.early_exit, NULL);
  if (both)
  {
    fixture.writer_release = CreateEventW(NULL, TRUE, FALSE, NULL);
    assert(fixture.writer_release != NULL);
  }
  assert(fixture.entered != NULL && fixture.release != NULL);
  if (writer) assert(CreatePipe(&read_pipe, &fixture.pipe, NULL, 0U));
  L = luaL_newstate();
  assert(L != NULL);
  luaL_openlibs(L);
  fixture_load(L, argv[1]);
  assert(GetModuleHandleA("native-worker-fixture.dll") != NULL);
  lua_getfield(L, -1, "start");
  lua_pushlightuserdata(L, &fixture);
  lua_pushinteger(L, writer);
  assert(lua_pcall(L, 2, 2, 0) == LUA_OK);
  started = lua_isuserdata(L, -2);
  assert(started == !expected_failure);
  if (started)
  {
    assert(fixture.observer != NULL);
    assert(WaitForSingleObject(fixture.entered, 10000U) == WAIT_OBJECT_0);
    assert(GetExitCodeThread(fixture.observer, &exit_code));
    assert((exit_code == STILL_ACTIVE) == !fixture.early_exit);
    if (both)
    {
      writer_observer = fixture.observer;
      assert(ResetEvent(fixture.entered));
      lua_getfield(L, 1, "start");
      lua_pushlightuserdata(L, &fixture);
      lua_pushinteger(L, 0);
      assert(lua_pcall(L, 2, 2, 0) == LUA_OK && lua_isuserdata(L, -2));
      assert(WaitForSingleObject(fixture.entered, 10000U) == WAIT_OBJECT_0);
      assert(fixture.entered_count == 2);
      assert(GetExitCodeThread(fixture.observer, &exit_code) && exit_code == STILL_ACTIVE);
    }
  }
  else
  {
    assert(lua_isboolean(L, -2) && !lua_toboolean(L, -2)
      && lua_istable(L, -1) && fixture.observer == NULL);
    assert(fixture.setup_error == (fixture.fail_thread ? ERROR_NOT_ENOUGH_MEMORY : ERROR_MOD_NOT_FOUND));
  }
  lua_close(L);
  resident = GetModuleHandleA("native-worker-fixture.dll") != NULL;
  if (started && !fixture.early_exit && !resident)
  {
    assert(GetExitCodeThread(fixture.observer, &exit_code) && exit_code == STILL_ACTIVE);
    printf("windows-worker-lifetime=FAIL kind=%s control=%s module_resident=0 worker_live=1\n",
      argv[2], argv[3]);
    fflush(stdout);
    /* Do not close a wait handle or resume code already unmapped by Lua. Exit only this probe process. */
    ExitProcess(1U);
  }
  assert(resident == (started && !fixture.early_exit));
  if (started)
  {
    if (both)
    {
      assert(SetEvent(fixture.writer_release));
      assert(WaitForSingleObject(writer_observer, 10000U) == WAIT_OBJECT_0);
      assert(fixture.io_completed == 1 && fixture.live_blocks == 2);
      assert(GetModuleHandleA("native-worker-fixture.dll") != NULL);
      assert(CloseHandle(writer_observer));
    }
    assert(SetEvent(fixture.release));
    assert(WaitForSingleObject(fixture.observer, 10000U) == WAIT_OBJECT_0);
    assert(fixture.io_completed == (both ? 2 : 1));
  }
  assert(GetModuleHandleA("native-worker-fixture.dll") == NULL);
  assert(fixture.live_blocks == 0);
  fixture_cleanup(&fixture, read_pipe);
  {
    DWORD after = fixture_handles();
    printf("worker-resource-check before=%lu after=%lu\n", (unsigned long)baseline, (unsigned long)after);
    assert(after == baseline);
  }
  printf("windows-worker-lifetime=PASS kind=%s control=%s module_resident=%d final_module=0 native_blocks=0\n",
    argv[2], argv[3], resident);
  return 0;
}
