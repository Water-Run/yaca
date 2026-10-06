/*
Author: WaterRun
Date: 2026-10-05
File: filesystem_snapshot_faults.c
Description: Injects persistent Lua allocation failures and exceptional identity getters into production filesystem snapshots/walks, auditing native buffers and handles after full collection and same-state recovery.
*/

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

/* @enum probe_operation Distinguishes filesystem projections and verified identity paths.
 * @field PROBE_FILE Inspect the existing regular fixture including real behavior metadata.
 * @field PROBE_DIRECTORY Inspect the owned directory and its ancestry.
 * @field PROBE_WALK Enumerate bounded entries and project their snapshots.
 * @field PROBE_OPEN Read-open the fixture using an exceptional identity proxy or valid captured identity.
 * @field PROBE_CREATE Create an absent child using an exceptional parent proxy or valid captured identity.
 */
typedef enum probe_operation { PROBE_FILE, PROBE_DIRECTORY, PROBE_WALK, PROBE_OPEN, PROBE_CREATE } probe_operation;

static char probe_root[4096];
static char probe_file[4096];
static char probe_absent[4096];

/* Set up one protected call without performing its filesystem work yet.
 * @param L lua_State* State receiving the production C function and literal arguments.
 * @param operation probe_operation Selected projection or verified port.
 * @param exploding int Nonzero to supply an __index proxy that raises; zero captures a valid identity first.
 * @return int Number of arguments pushed after the production function.
 * @effect A non-exploding verified case briefly calls production inspection and retains only its Lua identity value.
 * @error Aborts when valid fixture identity capture fails.
 */
static int probe_push_call(lua_State *L, probe_operation operation, int exploding)
{
  if (operation == PROBE_WALK)
  {
    lua_pushcfunction(L, l_fs_walk_direct); lua_pushstring(L, probe_root);
    lua_pushinteger(L, 2); lua_pushinteger(L, 32); lua_pushliteral(L, "git-compatible-v1");
    return 4;
  }
  if (operation == PROBE_FILE || operation == PROBE_DIRECTORY)
  {
    lua_pushcfunction(L, l_fs_inspect_direct);
    lua_pushstring(L, operation == PROBE_FILE ? probe_file : probe_root);
    return 1;
  }
  lua_pushcfunction(L, operation == PROBE_OPEN ? l_fs_open_read_verified : l_fs_create_new_verified);
  lua_pushstring(L, operation == PROBE_OPEN ? probe_file : probe_absent);
  if (exploding)
  {
    lua_createtable(L, 0, 0);
    /* @metatable probe_identity_proxy Empty expected-identity table with an error-raising __index.
     * @field __index function Raises instead of returning any identity component; used only under lua_pcall.
     */
    lua_createtable(L, 0, 1);
    lua_pushcfunction(L, probe_exploding_getter); lua_setfield(L, -2, "__index");
    /* @metatable probe_identity_proxy Attach the error-raising expected-identity proxy declared above.
     * @field __index function Always raises probe-getter-error on any missing identity field.
     */
    lua_setmetatable(L, -2);
  }
  else
  {
    lua_pushcfunction(L, l_fs_inspect_direct);
    lua_pushstring(L, operation == PROBE_OPEN ? probe_file : probe_absent);
    if (lua_pcall(L, 1, 2, 0) != LUA_OK || !lua_toboolean(L, -2)) abort();
    lua_getfield(L, -1, operation == PROBE_OPEN ? "identity" : "parent_identity");
    lua_remove(L, -2); lua_remove(L, -2);
  }
  if (operation == PROBE_CREATE) { lua_pushinteger(L, 0600); return 3; }
  return 2;
}

/* Inspect tracked resources after full Lua collection, then clean confirmed old-code leaks for the next case.
 * @param label const_char* Stable operation name without user data.
 * @param threshold size_t Armed failure site, or SIZE_MAX for a non-failing baseline.
 * @return size_t Number of live native buffers and OS handles/descriptors recorded as leaks.
 * @effect Prints each leaking case, explicitly frees/closes observed leaks, and resets observations.
 */
static size_t probe_audit(const char *label, size_t threshold)
{
  size_t index;
  size_t bytes = 0U;
  size_t leaks = probe_live;
  for (index = 0U; index < PROBE_CAPACITY; ++index) bytes += probe_sizes[index];
#if defined(_WIN32)
  leaks += probe_handle_count;
#else
  leaks += probe_descriptor_count;
#endif
  if (leaks != 0U)
    printf("LEAK %s fail_at=%zu buffers=%zu bytes=%zu\n", label, threshold, probe_live, bytes);
  for (index = 0U; index < PROBE_CAPACITY; ++index)
  {
    free(probe_buffers[index]); probe_buffers[index] = NULL; probe_sizes[index] = 0U;
  }
  probe_live = 0U;
#if defined(_WIN32)
  while (probe_handle_count != 0U) CloseHandle(probe_handles[--probe_handle_count]);
#else
  while (probe_descriptor_count != 0U) close(probe_descriptors[--probe_descriptor_count]);
#endif
  return leaks;
}

/* Verify recovered projection contents or perform a real read through the recovered userdata.
 * @param L lua_State* Stack holds the successful production true/result pair.
 * @param operation probe_operation Kind of recovered result expected at index two.
 * @return void No result; leaves any referenced file owner on the Lua stack until collection.
 * @effect Reads actual fixture bytes, or writes/rewinds/reads the newly created child; does not close the owner prematurely.
 * @error Aborts if the recovered result is the wrong snapshot, walk entry, userdata or byte sequence.
 */
static void probe_verify_recovery(lua_State *L, probe_operation operation)
{
  if (operation == PROBE_FILE || operation == PROBE_DIRECTORY)
  {
    const char *kind;
    lua_getfield(L, 2, "identity"); lua_getfield(L, -1, "kind");
    kind = lua_tostring(L, -1);
    if (kind == NULL || strcmp(kind, operation == PROBE_FILE ? "file" : "directory") != 0) abort();
    lua_pop(L, 2);
  }
  else if (operation == PROBE_WALK)
  {
    const char *name;
    lua_getfield(L, 2, "entries");
    if (lua_rawlen(L, -1) < 1U) abort();
    lua_rawgeti(L, -1, 1); lua_getfield(L, -1, "relative_path");
    name = lua_tostring(L, -1);
    if (name == NULL || strcmp(name, "fixture.txt") != 0) abort();
    lua_pop(L, 3);
  }
  else
  {
    int reference;
    const char *bytes;
    size_t length;
    lua_pushvalue(L, 2); reference = luaL_ref(L, LUA_REGISTRYINDEX);
    lua_settop(L, 0);
    if (operation == PROBE_CREATE)
    {
      lua_pushcfunction(L, l_fs_write); lua_rawgeti(L, LUA_REGISTRYINDEX, reference);
      lua_pushliteral(L, "snapshot-fixture");
      if (lua_pcall(L, 2, 2, 0) != LUA_OK || !lua_toboolean(L, 1) || lua_tointeger(L, 2) != 16) abort();
      lua_settop(L, 0);
      lua_pushcfunction(L, l_fs_seek); lua_rawgeti(L, LUA_REGISTRYINDEX, reference); lua_pushinteger(L, 0);
      if (lua_pcall(L, 2, 2, 0) != LUA_OK || !lua_toboolean(L, 1)) abort();
      lua_settop(L, 0);
    }
    lua_pushcfunction(L, l_fs_read); lua_rawgeti(L, LUA_REGISTRYINDEX, reference); lua_pushinteger(L, 16);
    if (lua_pcall(L, 2, 2, 0) != LUA_OK || !lua_toboolean(L, 1)) abort();
    lua_getfield(L, 2, "bytes"); bytes = lua_tolstring(L, -1, &length);
    if (bytes == NULL || length != 16U || memcmp(bytes, "snapshot-fixture", 16U) != 0) abort();
    luaL_unref(L, LUA_REGISTRYINDEX, reference);
  }
}

/* Run one armed operation and prove same-state recovery after collection and leak observation.
 * @param operation probe_operation Selected production port and fixture.
 * @param label const_char* Stable diagnostic name for the operation.
 * @param threshold size_t First persistent allocation failure, or SIZE_MAX for successful observation.
 * @param exploding int Nonzero for getter exception, zero for allocation-failure runs.
 * @param leaks size_t* Accumulates observed native resource leaks after collection and recovery.
 * @return size_t Number of armed Lua growth allocations observed during the first tested call.
 * @effect Runs a fault, a real recovery, the same fault again and another recovery in one state; collects owners and removes created children between each call.
 * @error Aborts on unexpected error kinds, invalid recovery results or failed fixture removal.
 */
static size_t probe_check(probe_operation operation, const char *label, size_t threshold, int exploding, size_t *leaks)
{
  probe_lua_fault fault = { 0U, threshold, 0 };
  lua_State *L = lua_newstate(probe_lua_allocate, &fault, 0U);
  int arguments;
  int status;
  size_t observed;
  if (L == NULL) abort();
  create_handle_metatable(L, YACA_FILE_METATABLE, l_file_gc);
  arguments = probe_push_call(L, operation, exploding);
  fault.armed = !exploding;
  status = lua_pcall(L, arguments, LUA_MULTRET, 0);
  fault.armed = 0;
  observed = fault.calls;
  if (exploding ? status != LUA_ERRRUN : (status != LUA_OK && status != LUA_ERRMEM)) abort();
  if (status == LUA_OK && (!lua_toboolean(L, 1) || lua_gettop(L) != 2)) abort();
  lua_settop(L, 0); lua_gc(L, LUA_GCCOLLECT); lua_gc(L, LUA_GCCOLLECT);
  *leaks += probe_audit(label, threshold);
#if defined(_WIN32)
  DeleteFileA(probe_absent);
#else
  unlink(probe_absent);
#endif
  arguments = probe_push_call(L, operation, 0);
  if (lua_pcall(L, arguments, 2, 0) != LUA_OK || !lua_toboolean(L, 1)) abort();
  probe_verify_recovery(L, operation);
  lua_settop(L, 0); lua_gc(L, LUA_GCCOLLECT); lua_gc(L, LUA_GCCOLLECT);
  *leaks += probe_audit("recovery", threshold);
#if defined(_WIN32)
  DeleteFileA(probe_absent);
#else
  unlink(probe_absent);
#endif
  arguments = probe_push_call(L, operation, exploding);
  fault.calls = 0U;
  fault.armed = !exploding;
  status = lua_pcall(L, arguments, LUA_MULTRET, 0);
  fault.armed = 0;
  if (exploding ? status != LUA_ERRRUN : (status != LUA_OK && status != LUA_ERRMEM)) abort();
  if (status == LUA_OK && (!lua_toboolean(L, 1) || lua_gettop(L) != 2)) abort();
  lua_settop(L, 0); lua_gc(L, LUA_GCCOLLECT); lua_gc(L, LUA_GCCOLLECT);
  *leaks += probe_audit("repeat-fault", threshold);
#if defined(_WIN32)
  DeleteFileA(probe_absent);
#else
  unlink(probe_absent);
#endif
  arguments = probe_push_call(L, operation, 0);
  if (lua_pcall(L, arguments, 2, 0) != LUA_OK || !lua_toboolean(L, 1)) abort();
  probe_verify_recovery(L, operation);
  lua_settop(L, 0); lua_gc(L, LUA_GCCOLLECT); lua_gc(L, LUA_GCCOLLECT);
  *leaks += probe_audit("repeat-recovery", threshold);
  lua_close(L);
#if defined(_WIN32)
  DeleteFileA(probe_absent);
#else
  unlink(probe_absent);
#endif
  return observed;
}

/* Create an isolated fixture with a file, directory and bounded ancestry.
 * @param none Uses a reserved unique OS temporary path owned by this process.
 * @return void No value; stores the owned root/file/absent paths for later calls.
 * @effect Creates only the unique temporary directory and one fixture file, optionally setting a POSIX user xattr.
 * @error Aborts on setup failure; an incomplete owned fixture remains for investigation.
 */
static void probe_setup(void)
{
  FILE *file;
  size_t length;
#if defined(_WIN32)
  const char *file_suffix = "\\fixture.txt";
  const char *absent_suffix = "\\absent.txt";
#else
  const char *file_suffix = "/fixture.txt";
  const char *absent_suffix = "/absent.txt";
#endif
#if defined(_WIN32)
  char temporary[MAX_PATH];
  if (GetTempPathA(sizeof(temporary), temporary) == 0U
      || GetTempFileNameA(temporary, "ysf", 0U, probe_root) == 0U
      || !DeleteFileA(probe_root) || !CreateDirectoryA(probe_root, NULL)) abort();
#else
  strcpy(probe_root, "/tmp/yaca-snapshot-faults-XXXXXX");
  if (mkdtemp(probe_root) == NULL) abort();
#endif
  length = strlen(probe_root);
  if (length + strlen(file_suffix) + 1U > sizeof(probe_file)
      || length + strlen(absent_suffix) + 1U > sizeof(probe_absent)) abort();
  memcpy(probe_file, probe_root, length); strcpy(probe_file + length, file_suffix);
  memcpy(probe_absent, probe_root, length); strcpy(probe_absent + length, absent_suffix);
  file = fopen(probe_file, "wb");
  if (file == NULL || fwrite("snapshot-fixture", 1U, 16U, file) != 16U || fclose(file) != 0) abort();
#if !defined(_WIN32)
  if (setxattr(probe_file, "user.yaca-snapshot-probe", "metadata", 8U, 0) != 0
      && errno != ENOTSUP && errno != EOPNOTSUPP) abort();
#endif
}

/* Exercise every observed allocation site and both exceptional verified-identity getters.
 * @param none No arguments; the root is uniquely reserved and removed after all cases.
 * @return int Zero only when no native resources or ownership violations escaped; one for confirmed leaks.
 * @effect Prints per-port counts, removes the owned file/root and leaves earlier user files untouched.
 * @error Aborts on structural test failures or incomplete fixture cleanup.
 */
int main(void)
{
  static const char *labels[] = { "inspect-file", "inspect-directory", "walk", "open-verified", "create-verified" };
  size_t total = 0U;
  size_t operation;
  setbuf(stdout, NULL);
  probe_setup();
  for (operation = 0U; operation <= (size_t)PROBE_CREATE; ++operation)
  {
    size_t leaks = 0U;
    size_t sites = probe_check((probe_operation)operation, labels[operation], SIZE_MAX, 0, &leaks);
    size_t index;
    for (index = 1U; index <= sites + 1U; ++index)
      probe_check((probe_operation)operation, labels[operation], index, 0, &leaks);
    if (operation >= (size_t)PROBE_OPEN)
      probe_check((probe_operation)operation, labels[operation], SIZE_MAX, 1, &leaks);
    printf("%s allocation_sites=%zu native_leaks=%zu recovery=PASS\n", labels[operation], sites, leaks);
    total += leaks;
  }
#if defined(_WIN32)
  if (!DeleteFileA(probe_file) || !RemoveDirectoryA(probe_root)) abort();
#else
  if (unlink(probe_file) != 0 || rmdir(probe_root) != 0) abort();
#endif
  printf("filesystem-snapshot-faults native_leaks=%zu ownership_errors=%zu\n", total, probe_ownership_errors);
  return total == 0U && probe_ownership_errors == 0U ? 0 : 1;
}
