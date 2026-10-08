/*
Author: WaterRun
Date: 2026-10-08
File: windows_worker_fixture.h
Description: Shares host-owned synchronization and native allocation observations between the worker-lifetime DLL and its Lua loadlib probe.
*/

#ifndef YACA_WINDOWS_WORKER_FIXTURE_H
#define YACA_WINDOWS_WORKER_FIXTURE_H
#include <windows.h>

/* @struct yaca_worker_fixture Host-owned observations, kept alive until the actual worker exits.
 * @field entered HANDLE Host-owned event signalled after the worker enters the bounded IO double.
 * @field release HANDLE Host-owned event that completes the blocked IO operation.
 * @field observer HANDLE Independent host-owned duplicate of the actual worker thread handle.
 * @field pipe HANDLE Write handle owned by the host until a writer successfully starts, then by that worker.
 * @field live_blocks volatile_LONG Atomically counted production allocations, excluding the external Lua heap.
 * @field io_completed volatile_LONG Counts completed bounded IO doubles, including configured failures.
 * @field lookup_calls LONG Number of module lookup/retention requests observed before thread startup.
 * @field fail_module int One rejects module lookup; two rejects only reference acquisition; zero allows both.
 * @field fail_thread int Nonzero rejects CreateThread after any module reference acquisition.
 * @field io_error int Nonzero makes the released IO double report the expected native read/write error.
 * @field early_exit int Nonzero joins the worker inside the CreateThread double before returning its handle.
 * @field pipe_transferred int Nonzero records successful transfer of pipe ownership to the production writer.
 * @field setup_error DWORD Actual production startup OS error, captured before Lua result allocation.
 * @field writer_release HANDLE Optional independently owned writer gate for the two-worker scenario.
 * @field entered_count volatile_LONG Counts workers that reached their bounded IO double before owner collection.
 */
typedef struct yaca_worker_fixture
{
  HANDLE entered;
  HANDLE release;
  HANDLE observer;
  HANDLE pipe;
  volatile LONG live_blocks;
  volatile LONG io_completed;
  LONG lookup_calls;
  int fail_module;
  int fail_thread;
  int io_error;
  int early_exit;
  int pipe_transferred;
  DWORD setup_error;
  HANDLE writer_release;
  volatile LONG entered_count;
} yaca_worker_fixture;

#endif
