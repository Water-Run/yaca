/*
Author: WaterRun
Date: 2026-10-08
File: windows_worker_dll_fixture.h
Description: Shares host-owned gates and atomic resource observations with an
instrumented native DLL while its production worker outlives a Lua state.
*/

#ifndef YACA_WORKER_DLL_FIXTURE_H
#define YACA_WORKER_DLL_FIXTURE_H

#include <windows.h>

/* @struct worker_dll_fixture Host-owned observations that remain valid until the independent thread join.
 * @field entered HANDLE Borrowed manual-reset gate signalled from the worker's bounded I/O double.
 * @field release HANDLE Borrowed gate allowing the worker to finish after Lua state destruction.
 * @field native_live volatile_LONG Outstanding production malloc/calloc blocks, excluding Lua allocations.
 * @field module_references volatile_LONG Worker-owned DLL references acquired/released by production.
 * @field module_calls LONG Main-thread module-resolution calls counted for deterministic failure injection.
 * @field fail_module_at LONG One-based module API call to reject; zero disables this failure.
 * @field fail_thread int Reject production CreateThread when nonzero.
 * @field startup_error DWORD Actual production startup error retained before fixture cleanup changes last error.
 * @field write_pipe HANDLE Observed real writer pipe, retained only as a non-owning numeric identity.
 * @field pipe_closes volatile_LONG Successful production closes of that write end.
 */
typedef struct worker_dll_fixture
{
  HANDLE entered;
  HANDLE release;
  volatile LONG native_live;
  volatile LONG module_references;
  LONG module_calls;
  LONG fail_module_at;
  int fail_thread;
  DWORD startup_error;
  HANDLE write_pipe;
  volatile LONG pipe_closes;
} worker_dll_fixture;

#endif
