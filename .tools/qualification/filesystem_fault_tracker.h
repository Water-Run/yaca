/*
Author: WaterRun
Date: 2026-10-06
File: filesystem_fault_tracker.h
Description: Includes production filesystem native ports with bounded allocation/handle observation and persistent Lua allocation/getter fault helpers for isolated qualification probes.
*/

#ifndef YACA_FILESYSTEM_FAULT_TRACKER_H
#define YACA_FILESYSTEM_FAULT_TRACKER_H

#if !defined(_WIN32)
#define _GNU_SOURCE
#define _POSIX_C_SOURCE 200809L
#define _XOPEN_SOURCE 700
#endif
#include <errno.h>
#include <stdint.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#if defined(_WIN32)
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0501
#endif
#include <windows.h>
#else
#include <dirent.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#endif
#include "lua.h"
#include "lauxlib.h"

#define PROBE_CAPACITY 4096U
static void *probe_buffers[PROBE_CAPACITY];
static size_t probe_sizes[PROBE_CAPACITY];
static size_t probe_live;
static size_t probe_ownership_errors;
#if defined(_WIN32)
static HANDLE probe_handles[PROBE_CAPACITY];
static size_t probe_handle_count;
#else
static int probe_descriptors[PROBE_CAPACITY];
static size_t probe_descriptor_count;
#endif

/* Locate a production allocation without dereferencing its contents.
 * @param pointer void* Address being found; NULL is never registered.
 * @return size_t Registered slot, or PROBE_CAPACITY when the pointer is not tracked.
 */
static size_t probe_find(void *pointer)
{
  size_t index;
  for (index = 0U; index < PROBE_CAPACITY; ++index)
    if (probe_buffers[index] == pointer && pointer != NULL) return index;
  return PROBE_CAPACITY;
}

/* Record one successful native allocation, including libc-created strings.
 * @param pointer void* Newly acquired allocation; NULL is a harmless failed allocation.
 * @param bytes size_t Allocation size used for leak diagnostics.
 * @return void No value; updates only the bounded observation arrays.
 * @error Aborts on duplicate acquisition or observation overflow.
 */
static void probe_acquire(void *pointer, size_t bytes)
{
  size_t index;
  if (pointer == NULL) return;
  if (probe_find(pointer) != PROBE_CAPACITY) abort();
  for (index = 0U; index < PROBE_CAPACITY; ++index)
  {
    if (probe_buffers[index] == NULL)
    {
      probe_buffers[index] = pointer;
      probe_sizes[index] = bytes;
      ++probe_live;
      return;
    }
  }
  abort();
}

/* Allocate and register production malloc storage.
 * @param bytes size_t Requested allocation size.
 * @return void* Real allocation or NULL; ownership transfers to production until tracked free.
 */
static void *probe_malloc(size_t bytes)
{
  void *pointer = malloc(bytes);
  probe_acquire(pointer, bytes);
  return pointer;
}

/* Allocate and register zero-initialized production storage.
 * @param count size_t Number of requested items.
 * @param bytes size_t Bytes per item.
 * @return void* Real calloc allocation or NULL; ownership transfers to production.
 */
static void *probe_calloc(size_t count, size_t bytes)
{
  void *pointer = calloc(count, bytes);
  probe_acquire(pointer, count * bytes);
  return pointer;
}

/* Resize a production allocation while retaining its observation on a failed realloc.
 * @param pointer void* Registered allocation or NULL for a new allocation.
 * @param bytes size_t Positive requested size; zero is not used by the production paths tested here.
 * @return void* Resized allocation or NULL for failure, leaving an old allocation owned by production.
 * @error Aborts for a foreign pointer or zero-sized production realloc.
 */
static void *probe_realloc(void *pointer, size_t bytes)
{
  size_t slot = probe_find(pointer);
  void *next;
  if (bytes == 0U || (pointer != NULL && slot == PROBE_CAPACITY)) abort();
  next = realloc(pointer, bytes);
  if (next != NULL)
  {
    if (slot == PROBE_CAPACITY) probe_acquire(next, bytes);
    else { probe_buffers[slot] = next; probe_sizes[slot] = bytes; }
  }
  return next;
}

/* Release one registered native allocation without hiding duplicate or foreign frees.
 * @param pointer void* Registered production allocation, or NULL for a no-op.
 * @return void No result; frees registered storage and increments ownership errors for other values.
 */
static void probe_free(void *pointer)
{
  size_t slot;
  if (pointer == NULL) return;
  slot = probe_find(pointer);
  if (slot == PROBE_CAPACITY) { ++probe_ownership_errors; return; }
  probe_buffers[slot] = NULL;
  probe_sizes[slot] = 0U;
  --probe_live;
  free(pointer);
}

/* Duplicate and register a production path or attribute name on either platform.
 * @param value const_char* NUL-terminated string borrowed from the caller.
 * @return char* Newly owned duplicate, or NULL for allocation failure.
 */
static char *probe_strdup(const char *value)
{
  char *pointer = strdup(value);
  probe_acquire(pointer, strlen(value) + 1U);
  return pointer;
}

#if !defined(_WIN32)
/* Register libc-allocated realpath results while preserving caller-supplied output storage.
 * @param path const_char* Borrowed path selected by production inspection.
 * @param output char* Caller-owned buffer, or NULL to request a new libc allocation.
 * @return char* Canonical path or NULL; newly allocated output is tracked until production frees it.
 */
static char *probe_realpath(const char *path, char *output)
{
  char *pointer = realpath(path, output);
  if (pointer != NULL && output == NULL) probe_acquire(pointer, strlen(pointer) + 1U);
  return pointer;
}

/* Observe an absolute POSIX open, preserving an optional creation mode.
 * @param path const_char* Borrowed path passed through unchanged.
 * @param flags int Requested flags; O_CREAT means the optional mode is present.
 * @param ... mode_t One promoted creation mode only when O_CREAT is set.
 * @return int Real descriptor or -1; successful descriptors remain owned by production.
 * @error Aborts if descriptor observation capacity is exhausted.
 */
static int probe_open(const char *path, int flags, ...)
{
  int descriptor;
  if (flags & O_CREAT)
  {
    va_list args;
    mode_t mode;
    va_start(args, flags); mode = va_arg(args, mode_t); va_end(args);
    descriptor = open(path, flags, mode);
  }
  else descriptor = open(path, flags);
  if (descriptor >= 0)
  {
    if (probe_descriptor_count == PROBE_CAPACITY) abort();
    probe_descriptors[probe_descriptor_count++] = descriptor;
  }
  return descriptor;
}

/* Observe a parent-relative POSIX open, preserving its optional creation mode.
 * @param parent int Borrowed directory descriptor passed through unchanged.
 * @param path const_char* Borrowed child path passed through unchanged.
 * @param flags int Requested flags; O_CREAT means the optional mode is present.
 * @param ... mode_t One promoted creation mode only when O_CREAT is set.
 * @return int Real descriptor or -1; successful descriptors remain owned by production.
 * @error Aborts if descriptor observation capacity is exhausted.
 */
static int probe_openat(int parent, const char *path, int flags, ...)
{
  int descriptor;
  if (flags & O_CREAT)
  {
    va_list args;
    mode_t mode;
    va_start(args, flags); mode = va_arg(args, mode_t); va_end(args);
    descriptor = openat(parent, path, flags, mode);
  }
  else descriptor = openat(parent, path, flags);
  if (descriptor >= 0)
  {
    if (probe_descriptor_count == PROBE_CAPACITY) abort();
    probe_descriptors[probe_descriptor_count++] = descriptor;
  }
  return descriptor;
}

/* Remove and close a production POSIX descriptor without affecting other observations.
 * @param descriptor int Descriptor whose production owner requests close.
 * @return int Unchanged operating-system close result.
 */
static int probe_close(int descriptor)
{
  size_t index;
  for (index = 0U; index < probe_descriptor_count; ++index)
  {
    if (probe_descriptors[index] == descriptor)
    {
      probe_descriptors[index] = probe_descriptors[--probe_descriptor_count];
      break;
    }
  }
  return close(descriptor);
}
#else
/* Track successful production Win32 file/directory opens while passing all rights through.
 * @param name LPCWSTR Borrowed path passed unchanged to CreateFileW.
 * @param access DWORD Requested access rights.
 * @param sharing DWORD Requested share mask.
 * @param security LPSECURITY_ATTRIBUTES Optional borrowed security attributes.
 * @param creation DWORD Creation disposition.
 * @param flags DWORD Flags and attributes.
 * @param template_file HANDLE Optional borrowed template handle.
 * @return HANDLE Real handle or INVALID_HANDLE_VALUE; valid handles remain owned by production.
 * @error Aborts if observation capacity is exhausted.
 */
static HANDLE WINAPI probe_create_file(LPCWSTR name, DWORD access, DWORD sharing,
  LPSECURITY_ATTRIBUTES security, DWORD creation, DWORD flags, HANDLE template_file)
{
  HANDLE handle = CreateFileW(name, access, sharing, security, creation, flags, template_file);
  if (handle != INVALID_HANDLE_VALUE)
  {
    if (probe_handle_count == PROBE_CAPACITY) abort();
    probe_handles[probe_handle_count++] = handle;
  }
  return handle;
}

/* Match real Win32 closes with observed file/directory handles.
 * @param handle HANDLE Borrowed handle whose production owner is closing it.
 * @return BOOL Unchanged operating-system close outcome.
 */
static BOOL WINAPI probe_close_handle(HANDLE handle)
{
  size_t index;
  for (index = 0U; index < probe_handle_count; ++index)
  {
    if (probe_handles[index] == handle)
    {
      probe_handles[index] = probe_handles[--probe_handle_count];
      break;
    }
  }
  return CloseHandle(handle);
}
#endif

#define malloc probe_malloc
#define calloc probe_calloc
#define realloc probe_realloc
#define free probe_free
#define strdup probe_strdup
#if defined(_WIN32)
#define CreateFileW probe_create_file
#define CloseHandle probe_close_handle
#else
#define realpath probe_realpath
#define open probe_open
#define openat probe_openat
#define close probe_close
#endif
#include "../../native/yaca_native.c"
#undef malloc
#undef calloc
#undef realloc
#undef free
#undef strdup
#if defined(_WIN32)
#undef CreateFileW
#undef CloseHandle
#else
#undef realpath
#undef open
#undef openat
#undef close
#endif

/* @struct probe_lua_fault Persistent growth rejection for one protected native operation.
 * @field calls size_t Armed Lua growth requests, including emergency-GC retries.
 * @field fail_at size_t First request rejected; SIZE_MAX observes successful baseline behavior.
 * @field armed int Nonzero only inside the protected call under test.
 */
typedef struct probe_lua_fault { size_t calls; size_t fail_at; int armed; } probe_lua_fault;

/* Implement the Lua allocator without confusing Lua blocks with tracked native allocations.
 * @param opaque void* Caller-owned probe_lua_fault that outlives the Lua state.
 * @param pointer void* Previous Lua block or NULL.
 * @param previous size_t Previous size, or Lua type tag for a new block.
 * @param requested size_t Requested size; zero frees the Lua block.
 * @return void* Resized Lua block, or NULL for free/injected/system failure.
 */
static void *probe_lua_allocate(void *opaque, void *pointer, size_t previous, size_t requested)
{
  probe_lua_fault *fault = (probe_lua_fault *)opaque;
  if (requested == 0U) { free(pointer); return NULL; }
  if (fault->armed && (pointer == NULL || requested > previous))
  {
    ++fault->calls;
    if (fault->calls >= fault->fail_at) return NULL;
  }
  return realloc(pointer, requested);
}

/* Raise a deterministic Lua error from an expected-identity getter.
 * @param L lua_State* Contains the proxy table and requested key supplied by Lua __index.
 * @return int No normal return; the protected port call receives LUA_ERRRUN.
 * @error Always raises probe-getter-error without changing filesystem state.
 */
static int probe_exploding_getter(lua_State *L)
{
  return luaL_error(L, "probe-getter-error");
}

#endif
