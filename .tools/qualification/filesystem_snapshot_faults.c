/*
Author: WaterRun
Date: 2026-10-06
File: filesystem_snapshot_faults.c
Description: Injects persistent Lua allocation failures and exceptional identity getters into production filesystem snapshots/walks, auditing native buffers and handles after full collection and same-state recovery.
*/

#include "filesystem_fault_tracker.h"

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
