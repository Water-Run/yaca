/*
Author: WaterRun
Date: 2026-10-11
File: native_basics_faults.c
Description: Injects persistent Lua growth failures into production native
module initialization and SHA-256 finish, verifies same-state metatable repair,
real file-owner finalization and exact digest recovery on all target ABIs.
*/

#if !defined(_WIN32)
#define _POSIX_C_SOURCE 200809L
#define _XOPEN_SOURCE 700
#define _GNU_SOURCE
#endif
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "lua.h"
#include "lauxlib.h"
#if defined(_WIN32)
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0501
#endif
#include <windows.h>
#else
#include <unistd.h>
#endif

static int basics_observe_entropy;
static void *basics_entropy_bytes;
static size_t basics_entropy_length;
static size_t basics_entropy_error_wipes;

#if defined(_WIN32)
/* Observe the actual OS entropy destination while keeping its original API behavior.
 * @param buffer PVOID Borrowed native stack buffer receiving requested random bytes.
 * @param length ULONG Actual requested byte count.
 * @return BOOLEAN Unchanged Advapi32 entropy success.
 * @effect Retains only a temporary borrowed address for the later in-frame error-wipe observation.
 */
BOOLEAN WINAPI basics_entropy(PVOID buffer, ULONG length)
{
  /* Name the real Advapi32 entropy entry before this file renames that symbol.
   * @param buffer PVOID Borrowed destination supplied by the caller.
   * @param length ULONG Requested byte count.
   * @return BOOLEAN The platform entropy result; this declaration does not call it.
   */
  extern BOOLEAN WINAPI SystemFunction036(PVOID buffer, ULONG length);
  if (basics_observe_entropy) { basics_entropy_bytes = buffer; basics_entropy_length = length; }
  return SystemFunction036(buffer, length);
}
#define SystemFunction036 basics_entropy
#else
/* Observe the actual native entropy read destination without changing file-descriptor behavior.
 * @param descriptor int Actual native descriptor passed through to read.
 * @param buffer void* Borrowed native destination valid until the original function leaves its C frame.
 * @param length size_t Actual requested read length.
 * @return ssize_t Unchanged OS read result.
 * @effect Records an entropy destination only while the isolated random profile is armed.
 */
static ssize_t basics_read(int descriptor, void *buffer, size_t length)
{
  if (basics_observe_entropy) { basics_entropy_bytes = buffer; basics_entropy_length = length; }
  return read(descriptor, buffer, length);
}
#define read basics_read
#endif

/* Verify source bytes are zero while their original C frame is still alive, then propagate the actual Lua error.
 * @param L lua_State* State whose top value is the caught allocation error being re-raised by production.
 * @return int No normal return; propagates the same Lua exception.
 * @effect Reads only a currently live observed stack destination; never dereferences it after native return.
 * @error Aborts if protected entropy error propagation happens before native zeroization.
 */
static int basics_error(lua_State *L)
{
  if (basics_observe_entropy && basics_entropy_bytes != NULL)
  {
    size_t index;
    const unsigned char *bytes = (const unsigned char *)basics_entropy_bytes;
    for (index = 0U; index < basics_entropy_length; ++index) assert(bytes[index] == 0U);
    ++basics_entropy_error_wipes;
  }
  return lua_error(L);
}
#define lua_error basics_error
#undef LUAMOD_API
#define LUAMOD_API
#include "../../native/yaca_native.c"
#undef lua_error
#if defined(_WIN32)
#undef SystemFunction036
#else
#undef read
#endif

/* @struct basics_lua_fault Persistent growth rejection control owned outside the tested Lua state.
 * @field calls size_t Number of armed Lua growth requests, including emergency-GC retries.
 * @field fail_at size_t First rejected growth request; SIZE_MAX observes a healthy operation.
 * @field armed int Nonzero only around the protected production call under test.
 */
typedef struct basics_lua_fault
{
  size_t calls;
  size_t fail_at;
  int armed;
} basics_lua_fault;

static size_t basics_bad_metatables;
static size_t basics_bad_finalizers;
static size_t basics_bad_locks;
static size_t basics_resource_leaks;
static size_t basics_lost_digests;
static size_t basics_cases;

/* Implement the real Lua allocator with persistent rejection of the selected growth threshold.
 * @param opaque void* Borrowed basics_lua_fault valid until this state is closed.
 * @param pointer void* Previous Lua allocation, or NULL for a new block.
 * @param previous size_t Previous allocation size, or Lua type tag when pointer is NULL.
 * @param requested size_t Requested size; zero frees the previous block.
 * @return void* Real resized allocation, or NULL for free/injected/system failure.
 */
static void *basics_allocate(void *opaque, void *pointer, size_t previous, size_t requested)
{
  basics_lua_fault *fault = (basics_lua_fault *)opaque;
  if (requested == 0U) { free(pointer); return NULL; }
  if (fault->armed && (pointer == NULL || requested > previous))
  {
    ++fault->calls;
    if (fault->calls >= fault->fail_at) return NULL;
  }
  return realloc(pointer, requested);
}

/* Invoke one actual zero-argument native operation under the selected persistent growth fault.
 * @param L lua_State* State whose stack already contains any required argument userdata after the pushed function.
 * @param arguments int Exact production argument count, zero for initialization or one for finish.
 * @param fault basics_lua_fault* Actual allocator control armed only during this pcall.
 * @return int Lua status; leaves one real module/digest result on success or one error object on failure.
 * @effect Counts all growth requests during the production call without intercepting the implementation body.
 */
static int basics_call(lua_State *L, int arguments, basics_lua_fault *fault)
{
  int status;
  fault->calls = 0U; fault->armed = 1;
  status = lua_pcall(L, arguments, 1, 0);
  fault->armed = 0;
  return status;
}

/* Count incomplete native finalizer/lock fields after actual module retry in the same state.
 * @param L lua_State* State whose production opener has returned successfully after the injected attempt.
 * @return size_t Number of metatables whose real __gc or locked marker is still incorrect.
 * @effect Reads only the four actual private native metatables without changing them.
 */
static size_t basics_metatables(lua_State *L)
{
  const char *names[] = { YACA_FILE_METATABLE, YACA_PROCESS_METATABLE,
    YACA_TERMINAL_METATABLE, YACA_SHA256_METATABLE };
  lua_CFunction collectors[] = { l_file_gc, l_process_gc, l_terminal_gc, l_sha256_gc };
  size_t index;
  size_t failures = 0U;
  for (index = 0U; index < 4U; ++index)
  {
    const char *marker;
    luaL_getmetatable(L, names[index]); assert(lua_istable(L, -1));
    lua_getfield(L, -1, "__gc");
    if (lua_tocfunction(L, -1) != collectors[index]) { ++failures; ++basics_bad_finalizers; }
    lua_pop(L, 1);
    lua_getfield(L, -1, "__metatable"); marker = lua_tostring(L, -1);
    if (marker == NULL || strcmp(marker, "locked native handle") != 0) { ++failures; ++basics_bad_locks; }
    lua_pop(L, 2);
  }
  return failures;
}

/* Inject initialization, retry the actual opener and prove file-owner GC against a real OS resource.
 * @param site size_t Growth rejection threshold, or SIZE_MAX for a healthy observation.
 * @return size_t Actual first opener growth requests observed at this threshold.
 * @effect Owns a fresh Lua state and one finalizable OS file-port resource; rescues only an observed baseline leak.
 * @error Aborts for unexpected non-memory exceptions or failed fixture acquisition/cleanup.
 */
static size_t basics_initialization(size_t site)
{
  basics_lua_fault fault = { 0U, site, 0 };
  lua_State *L = lua_newstate(basics_allocate, &fault, 0U);
  yaca_file *owner;
  size_t calls;
  int status;
#if defined(_WIN32)
  HANDLE resource;
  DWORD flags;
#else
  int pair[2];
  int resource;
#endif
  assert(L != NULL);
  lua_pushcfunction(L, luaopen_yaca_native);
  status = basics_call(L, 0, &fault); calls = fault.calls;
  assert(status == LUA_OK || status == LUA_ERRMEM);
  lua_settop(L, 0); lua_gc(L, LUA_GCCOLLECT); lua_gc(L, LUA_GCCOLLECT);
  lua_pushcfunction(L, luaopen_yaca_native);
  assert(lua_pcall(L, 0, 1, 0) == LUA_OK);
  basics_bad_metatables += basics_metatables(L);
  lua_settop(L, 0);
  owner = push_file(L);
#if defined(_WIN32)
  resource = CreateEventW(NULL, TRUE, FALSE, NULL); assert(resource != NULL);
  owner->handle = resource;
#else
  assert(pipe(pair) == 0); assert(close(pair[1]) == 0);
  resource = pair[0]; owner->descriptor = resource;
#endif
  lua_settop(L, 0); lua_gc(L, LUA_GCCOLLECT); lua_gc(L, LUA_GCCOLLECT);
  lua_close(L);
#if defined(_WIN32)
  if (GetHandleInformation(resource, &flags))
  {
    ++basics_resource_leaks; assert(CloseHandle(resource));
  }
#else
  if (fcntl(resource, F_GETFD) != -1)
  {
    ++basics_resource_leaks; assert(close(resource) == 0);
  }
#endif
  ++basics_cases;
  return calls;
}

/* Check the exact known SHA-256 abc digest returned by the production finish function.
 * @param L lua_State* State containing a successful digest at stack top.
 * @return void No value; compares every digest byte to the independently published known-answer value.
 * @error Aborts for an incorrect type/length/digest.
 */
static void basics_digest(lua_State *L)
{
  static const unsigned char expected[32] = {
    0xba, 0x78, 0x16, 0xbf, 0x8f, 0x01, 0xcf, 0xea,
    0x41, 0x41, 0x40, 0xde, 0x5d, 0xae, 0x22, 0x23,
    0xb0, 0x03, 0x61, 0xa3, 0x96, 0x17, 0x7a, 0x9c,
    0xb4, 0x10, 0xff, 0x61, 0xf2, 0x00, 0x15, 0xad,
  };
  size_t length;
  const char *actual = lua_tolstring(L, -1, &length);
  assert(actual != NULL && length == sizeof(expected));
  assert(memcmp(actual, expected, sizeof(expected)) == 0);
}

/* Reject one finish allocation and retry the same actual hash owner without rehashing its input.
 * @param site size_t Persistent growth rejection threshold, or SIZE_MAX for healthy observation.
 * @return size_t Actual first finish growth requests observed at this threshold.
 * @effect Creates/closes one isolated Lua state; records a closed-before-result baseline as a lost digest.
 * @error Aborts for unexpected Lua statuses or incorrect successful recovery bytes.
 */
static size_t basics_finish(size_t site)
{
  basics_lua_fault fault = { 0U, site, 0 };
  lua_State *L = lua_newstate(basics_allocate, &fault, 0U);
  yaca_sha256 *owner;
  int reference;
  int status;
  size_t calls;
  assert(L != NULL);
  lua_pushcfunction(L, luaopen_yaca_native); assert(lua_pcall(L, 0, 1, 0) == LUA_OK);
  lua_settop(L, 0);
  lua_pushcfunction(L, l_sha256_start); assert(lua_pcall(L, 0, 1, 0) == LUA_OK);
  owner = (yaca_sha256 *)lua_touserdata(L, -1); assert(owner != NULL);
  assert(sha256_append(owner, (const unsigned char *)"abc", 3U));
  reference = luaL_ref(L, LUA_REGISTRYINDEX);
  lua_pushcfunction(L, l_sha256_finish); lua_rawgeti(L, LUA_REGISTRYINDEX, reference);
  status = basics_call(L, 1, &fault); calls = fault.calls;
  assert(status == LUA_OK || status == LUA_ERRMEM);
  if (status == LUA_OK) basics_digest(L);
  else
  {
    lua_settop(L, 0); lua_gc(L, LUA_GCCOLLECT); lua_gc(L, LUA_GCCOLLECT);
    if (owner->closed) ++basics_lost_digests;
    else
    {
      lua_pushcfunction(L, l_sha256_finish); lua_rawgeti(L, LUA_REGISTRYINDEX, reference);
      assert(lua_pcall(L, 1, 1, 0) == LUA_OK);
      basics_digest(L);
    }
  }
  lua_close(L);
  ++basics_cases;
  return calls;
}

/* Inject random-result allocation while observing real OS entropy and its in-frame exception zeroization.
 * @param site size_t Actual growth threshold, or SIZE_MAX for healthy observation.
 * @return size_t Actual growth requests observed during the random-byte operation.
 * @effect Reads only bounded OS random data; never prints it or retains a stack address beyond the native call.
 * @error Aborts for a non-memory exception, wrong result length or failed observed zeroization.
 */
static size_t basics_random(size_t site)
{
  basics_lua_fault fault = { 0U, site, 0 };
  lua_State *L = lua_newstate(basics_allocate, &fault, 0U);
  int status;
  size_t calls;
  size_t length;
  assert(L != NULL);
  lua_pushcfunction(L, l_secure_random); lua_pushinteger(L, 64);
  basics_entropy_bytes = NULL; basics_entropy_length = 0U; basics_observe_entropy = 1;
  status = basics_call(L, 1, &fault); calls = fault.calls;
  basics_observe_entropy = 0;
  basics_entropy_bytes = NULL;
  assert(status == LUA_OK || status == LUA_ERRMEM);
  if (status == LUA_OK) assert(lua_tolstring(L, -1, &length) != NULL && length == 64U);
  lua_close(L);
  ++basics_cases;
  return calls;
}

/* Enumerate actual initialization/finish growth thresholds and report genuine baseline failures.
 * @param none Accepts no paths, model configuration or external user resources.
 * @return int Zero after all real recovery/finalization checks pass; one for observed incomplete state or leaked owner.
 * @effect Runs only isolated Lua states and owned OS resources; no subprocess or network is used.
 */
int main(void)
{
  size_t initialization = basics_initialization(SIZE_MAX);
  size_t finish = basics_finish(SIZE_MAX);
  size_t random = basics_random(SIZE_MAX);
  size_t site;
  for (site = 1U; site <= initialization; ++site) basics_initialization(site);
  for (site = 1U; site <= finish; ++site) basics_finish(site);
  for (site = 1U; site <= random; ++site) basics_random(site);
  printf("native-basics initialization-sites=%zu finish-sites=%zu random-sites=%zu cases=%zu bad-metatables=%zu bad-finalizers=%zu bad-locks=%zu resource-leaks=%zu lost-digests=%zu entropy-error-wipes=%zu\n",
    initialization, finish, random, basics_cases, basics_bad_metatables, basics_bad_finalizers,
    basics_bad_locks, basics_resource_leaks, basics_lost_digests, basics_entropy_error_wipes);
  return basics_bad_metatables == 0U && basics_resource_leaks == 0U && basics_lost_digests == 0U ? 0 : 1;
}
