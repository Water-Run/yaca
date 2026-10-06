/*
Author: WaterRun
Date: 2026-10-06
File: filesystem_publication_faults.c
Description: Exercises real verified delete/rename/replace ports with persistent Lua allocation failures and exceptions at every identity getter, auditing native owners, unchanged rejected fixtures and same-state recovery.
*/

#include "filesystem_fault_tracker.h"

/* @enum publication_operation Selects one production mutation and its exact fixture postcondition.
 * @field PUBLICATION_DELETE Basic verified deletion of the source regular file.
 * @field PUBLICATION_DIRECT_DELETE Direct verified deletion bound to source and parent identities.
 * @field PUBLICATION_RENAME No-replace verified move from source to absent destination.
 * @field PUBLICATION_REPLACE Verified replacement of target with source, preserving behavior metadata.
 */
typedef enum publication_operation
{
  PUBLICATION_DELETE,
  PUBLICATION_DIRECT_DELETE,
  PUBLICATION_RENAME,
  PUBLICATION_REPLACE
} publication_operation;

static char publication_root[4096];
static char publication_source[4096];
static char publication_target[4096];
static char publication_absent[4096];
static size_t publication_getter_reads;
static size_t publication_getter_fail_at;
static const char publication_candidate[] = "candidate-bytes!";
static const char publication_original[] = "original-content";

/* Read one saved identity field or raise at the selected getter ordinal.
 * @param L lua_State* Arguments are identity proxy and key; upvalue 1 is the captured plain identity table.
 * @return int One exact field value, unless the selected read raises probe-getter-error.
 * @effect Increments only the probe read counter; does not mutate identity or filesystem state.
 * @error Raises through the common exceptional getter at the configured field read.
 */
static int publication_identity_getter(lua_State *L)
{
  ++publication_getter_reads;
  if (publication_getter_reads == publication_getter_fail_at)
    return probe_exploding_getter(L);
  lua_pushvalue(L, 2);
  lua_rawget(L, lua_upvalueindex(1));
  return 1;
}

/* Capture one real identity and optionally wrap it in a counted exceptional proxy.
 * @param L lua_State* Receives one identity table above its existing stack.
 * @param path const_char* Existing file or absent child with an existing parent in the owned fixture.
 * @param parent int Nonzero selects parent_identity, zero selects target identity.
 * @param proxy int Nonzero wraps all reads in a proxy, zero retains the plain captured table.
 * @return void No value; exactly one expected-identity argument remains on the stack.
 * @effect Calls production direct inspection before arming allocation faults; releases its native resources normally.
 * @error Aborts if fixture inspection fails or does not return the selected identity table.
 */
static void publication_push_identity(lua_State *L, const char *path, int parent, int proxy)
{
  lua_pushcfunction(L, l_fs_inspect_direct);
  lua_pushstring(L, path);
  if (lua_pcall(L, 1, 2, 0) != LUA_OK || !lua_toboolean(L, -2)) abort();
  lua_getfield(L, -1, parent ? "parent_identity" : "identity");
  if (!lua_istable(L, -1)) abort();
  lua_remove(L, -2); lua_remove(L, -2);
  if (proxy)
  {
    lua_createtable(L, 0, 0);
    /* @metatable publication_identity_proxy Empty read proxy retaining a captured plain identity as a closure upvalue.
     * @field __index function Counts field reads and returns the saved field, or raises at the selected read.
     */
    lua_createtable(L, 0, 1);
    lua_pushvalue(L, -3);
    lua_pushcclosure(L, publication_identity_getter, 1);
    lua_setfield(L, -2, "__index");
    /* @metatable publication_identity_proxy Attach the counted proxy table declared above.
     * @field __index function Reads only its captured identity and never changes directory entries.
     */
    lua_setmetatable(L, -2);
    lua_remove(L, -2);
  }
}

/* Prepare one mutation with real expected identities before arming the fault allocator.
 * @param L lua_State* Receives the production function and its admitted fixture arguments.
 * @param operation publication_operation Selected verified mutation.
 * @param proxy int Nonzero instruments each expected identity getter; zero passes plain captured identities.
 * @return int Number of arguments following the native function on the stack.
 * @effect Reads fixture identities and target behavior metadata; does not publish any filesystem change.
 * @error Aborts if required behavior metadata is unavailable.
 */
static int publication_push_call(lua_State *L, publication_operation operation, int proxy)
{
  if (operation == PUBLICATION_DELETE || operation == PUBLICATION_DIRECT_DELETE)
  {
    lua_pushcfunction(L, operation == PUBLICATION_DELETE ? l_fs_delete_verified : l_fs_delete_direct_verified);
    lua_pushstring(L, publication_source);
    publication_push_identity(L, publication_source, 0, proxy);
    if (operation == PUBLICATION_DELETE) return 2;
    publication_push_identity(L, publication_source, 1, proxy);
    return 3;
  }
  lua_pushcfunction(L, operation == PUBLICATION_RENAME ? l_fs_rename_no_replace_verified : l_fs_replace_verified);
  lua_pushstring(L, publication_source);
  lua_pushstring(L, operation == PUBLICATION_RENAME ? publication_absent : publication_target);
  publication_push_identity(L, publication_source, 0, proxy);
  if (operation == PUBLICATION_RENAME)
  {
    publication_push_identity(L, publication_source, 1, proxy);
    publication_push_identity(L, publication_absent, 1, proxy);
    return 5;
  }
  publication_push_identity(L, publication_target, 0, proxy);
  publication_push_identity(L, publication_target, 1, proxy);
  lua_pushcfunction(L, l_fs_inspect_direct); lua_pushstring(L, publication_target);
  if (lua_pcall(L, 1, 2, 0) != LUA_OK || !lua_toboolean(L, -2)) abort();
  lua_getfield(L, -1, "metadata"); lua_getfield(L, -1, "behavior_digest");
  if (lua_type(L, -1) != LUA_TSTRING) abort();
  lua_remove(L, -2); lua_remove(L, -2); lua_remove(L, -2);
  return 6;
}

/* Remove an owned fixture entry, accepting only a genuinely absent entry as an alternative.
 * @param path const_char* Exact file path inside the uniquely reserved probe root.
 * @return void No value; the selected entry is absent afterward.
 * @effect Deletes only the named probe entry; aborts rather than ignoring handle or permission failures.
 * @error Aborts on any deletion failure other than an already absent file.
 */
static void publication_remove(const char *path)
{
#if defined(_WIN32)
  if (!DeleteFileA(path) && GetLastError() != ERROR_FILE_NOT_FOUND) abort();
#else
  if (unlink(path) != 0 && errno != ENOENT) abort();
#endif
}

/* Create the exact initial bytes of one owned regular fixture.
 * @param path const_char* Absent file in the uniquely reserved root.
 * @param bytes const_char* NUL-terminated fixture payload whose length is written exactly.
 * @return void No value; the fixture is closed with the expected bytes on success.
 * @effect Creates/truncates only the selected owned fixture, using untracked harness stdio.
 * @error Aborts on open, short write or close failure.
 */
static void publication_write(const char *path, const char *bytes)
{
  FILE *file = fopen(path, "wb");
  size_t length = strlen(bytes);
  if (file == NULL || fwrite(bytes, 1U, length, file) != length || fclose(file) != 0) abort();
}

/* Restore owned initial files after an audited case, including any native recovery names.
 * @param recreate int Nonzero creates the source/target payloads; zero leaves the root empty for final removal.
 * @return void No value; no file owner is held across the next production call.
 * @effect Removes only nine known owned fixture names and optionally recreates two regular files.
 * @error Aborts on an unexpected residual handle or failure to restore the fixture.
 */
static void publication_reset(int recreate)
{
  char recovery[8192];
  const char *paths[] = { publication_source, publication_target, publication_absent };
  size_t index;
  for (index = 0U; index < sizeof(paths) / sizeof(paths[0]); ++index)
  {
    publication_remove(paths[index]);
    strcpy(recovery, paths[index]); strcat(recovery, ".yaca-previous"); publication_remove(recovery);
    strcpy(recovery, paths[index]); strcat(recovery, ".yaca-delete"); publication_remove(recovery);
  }
  if (recreate)
  {
    publication_write(publication_source, publication_candidate);
    publication_write(publication_target, publication_original);
  }
}

/* Match one fixture's exact bytes or exact absence without retaining an OS handle.
 * @param path const_char* Owned file being observed.
 * @param expected const_char* Expected NUL-terminated bytes, or NULL for an absent file.
 * @return int One for an exact match/absence, zero for a different length, content or state.
 * @effect Opens and closes an untracked harness stream when a file is expected.
 * @error Aborts on unexpected access/close errors rather than treating them as absence.
 */
static int publication_matches(const char *path, const char *expected)
{
  FILE *file = fopen(path, "rb");
  char bytes[128];
  size_t count;
  if (file == NULL)
  {
    if (errno != ENOENT) abort();
    return expected == NULL;
  }
  count = fread(bytes, 1U, sizeof(bytes), file);
  if (ferror(file) || fclose(file) != 0) abort();
  return expected != NULL && count == strlen(expected) && memcmp(bytes, expected, count) == 0;
}

/* Verify a complete pre-publication or successful post-publication state and no recovery residue.
 * @param operation publication_operation Mutation whose expected postcondition is selected.
 * @param unchanged int Nonzero requires the original state; zero requires the completed mutation state.
 * @return void No value; all file contents, absences and recovery names are checked.
 * @error Aborts on any partial publication, modified rejected fixture or left-over recovery entry.
 */
static void publication_verify(publication_operation operation, int unchanged)
{
  char recovery[8192];
  const char *paths[] = { publication_source, publication_target, publication_absent };
  size_t index;
  if (!publication_matches(publication_source, unchanged ? publication_candidate : NULL)
      || !publication_matches(publication_target, !unchanged && operation == PUBLICATION_REPLACE ? publication_candidate : publication_original)
      || !publication_matches(publication_absent, !unchanged && operation == PUBLICATION_RENAME ? publication_candidate : NULL)) abort();
  for (index = 0U; index < sizeof(paths) / sizeof(paths[0]); ++index)
  {
    strcpy(recovery, paths[index]); strcat(recovery, ".yaca-previous");
    if (!publication_matches(recovery, NULL)) abort();
    strcpy(recovery, paths[index]); strcat(recovery, ".yaca-delete");
    if (!publication_matches(recovery, NULL)) abort();
  }
}

/* Audit collected production owners and rescue only confirmed baseline leaks for independent subsequent cases.
 * @param label const_char* Stable port name or recovery label without private user data.
 * @param fault size_t Selected allocation/getter ordinal, or SIZE_MAX for observation.
 * @return size_t Count of leaked native buffers plus OS handles/descriptors.
 * @effect Prints leaking cases, frees/closes observed baseline leaks and resets bounded tracking arrays.
 */
static size_t publication_audit(const char *label, size_t fault)
{
  size_t index;
  size_t leaks = probe_live;
#if defined(_WIN32)
  leaks += probe_handle_count;
#else
  leaks += probe_descriptor_count;
#endif
  if (leaks != 0U) printf("LEAK %s fault=%zu buffers=%zu resources=%zu\n", label, fault, probe_live, leaks);
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

/* Run two independent faults and two real recoveries inside one Lua state.
 * @param operation publication_operation Production mutation selected for the fixture.
 * @param label const_char* Stable diagnostic port name.
 * @param threshold size_t Persistent Lua growth failure ordinal, or SIZE_MAX for observation.
 * @param getter size_t Getter read raising an exception, or zero for an allocation fault case.
 * @param leaks size_t* Accumulates resources surviving two complete collections.
 * @param getter_sites size_t* Receives observed getter reads from the first tested operation.
 * @return size_t Observed Lua growth requests during the first armed call.
 * @effect Runs actual filesystem mutations and resets only the owned fixture after each audited call.
 * @error Aborts on wrong error kinds, changed rejected fixtures, incomplete publication or failed same-state recovery.
 */
static size_t publication_check(publication_operation operation, const char *label, size_t threshold, size_t getter, size_t *leaks, size_t *getter_sites)
{
  probe_lua_fault fault = { 0U, threshold, 0 };
  lua_State *L = lua_newstate(probe_lua_allocate, &fault, 0U);
  size_t observed = 0U;
  size_t cycle;
  int arguments;
  int status;
  if (L == NULL) abort();
  for (cycle = 0U; cycle < 2U; ++cycle)
  {
    publication_reset(1);
    publication_getter_reads = 0U; publication_getter_fail_at = getter;
    arguments = publication_push_call(L, operation, 1);
    fault.calls = 0U; fault.armed = getter == 0U;
    status = lua_pcall(L, arguments, LUA_MULTRET, 0);
    fault.armed = 0;
    if (cycle == 0U) { observed = fault.calls; *getter_sites = publication_getter_reads; }
    if (getter != 0U)
    {
      const char *message = lua_tostring(L, -1);
      if (status != LUA_ERRRUN || message == NULL || strstr(message, "probe-getter-error") == NULL) abort();
      publication_verify(operation, 1);
    }
    else
    {
      int unchanged;
      if (status != LUA_OK && status != LUA_ERRMEM) abort();
      if (status == LUA_OK && (lua_gettop(L) != 2 || !lua_toboolean(L, 1))) abort();
      unchanged = publication_matches(publication_source, publication_candidate);
      publication_verify(operation, unchanged);
    }
    lua_settop(L, 0); lua_gc(L, LUA_GCCOLLECT); lua_gc(L, LUA_GCCOLLECT);
    *leaks += publication_audit(label, getter != 0U ? getter : threshold);
    publication_reset(1);
    publication_getter_reads = 0U; publication_getter_fail_at = 0U;
    arguments = publication_push_call(L, operation, 0);
    if (lua_pcall(L, arguments, 2, 0) != LUA_OK || !lua_toboolean(L, 1)) abort();
    publication_verify(operation, 0);
    lua_settop(L, 0); lua_gc(L, LUA_GCCOLLECT); lua_gc(L, LUA_GCCOLLECT);
    *leaks += publication_audit("recovery", threshold);
  }
  lua_close(L);
  *leaks += publication_audit("state-close", threshold);
  return observed;
}

/* Reserve a unique root and derive three bounded fixture names without touching prior files.
 * @param none Uses the process OS temporary directory.
 * @return void No value; the root and exact source/target/absent names are retained in probe storage.
 * @effect Creates one unique directory owned by this probe; the initial files are created separately per case.
 * @error Aborts on reservation, creation or path length failure.
 */
static void publication_setup(void)
{
  size_t length;
#if defined(_WIN32)
  char temporary[MAX_PATH];
  const char *separator = "\\";
  if (GetTempPathA(sizeof(temporary), temporary) == 0U
      || GetTempFileNameA(temporary, "ypf", 0U, publication_root) == 0U
      || !DeleteFileA(publication_root) || !CreateDirectoryA(publication_root, NULL)) abort();
#else
  const char *separator = "/";
  strcpy(publication_root, "/tmp/yaca-publication-faults-XXXXXX");
  if (mkdtemp(publication_root) == NULL) abort();
#endif
  length = strlen(publication_root);
  if (length + 16U > sizeof(publication_source)) abort();
  memcpy(publication_source, publication_root, length); strcpy(publication_source + length, separator); strcat(publication_source, "source.txt");
  memcpy(publication_target, publication_root, length); strcpy(publication_target + length, separator); strcat(publication_target, "target.txt");
  memcpy(publication_absent, publication_root, length); strcpy(publication_absent + length, separator); strcat(publication_absent, "absent.txt");
}

/* Exercise all observed allocation sites and identity fields for each real mutation.
 * @param none No command-line arguments; all paths are uniquely reserved probe fixtures.
 * @return int Zero only for zero native leaks and ownership errors; one for confirmed baseline resource leaks.
 * @effect Prints per-port counts and removes the uniquely owned root after all cases.
 * @error Aborts on a failed probe invariant or incomplete final cleanup.
 */
int main(void)
{
  static const char *labels[] = { "delete-verified", "delete-direct", "rename-verified", "replace-verified" };
  size_t operation;
  size_t total = 0U;
  publication_setup();
  for (operation = 0U; operation < sizeof(labels) / sizeof(labels[0]); ++operation)
  {
    size_t leaks = 0U;
    size_t getter_sites;
    size_t ignored_sites;
    size_t site;
    size_t allocations = publication_check((publication_operation)operation, labels[operation], SIZE_MAX, 0U, &leaks, &getter_sites);
    for (site = 1U; site <= allocations; ++site)
      publication_check((publication_operation)operation, labels[operation], site, 0U, &leaks, &ignored_sites);
    for (site = 1U; site <= getter_sites; ++site)
      publication_check((publication_operation)operation, labels[operation], SIZE_MAX, site, &leaks, &ignored_sites);
    printf("%s allocation_sites=%zu getter_sites=%zu native_leaks=%zu unchanged_rejections=PASS recovery=PASS\n", labels[operation], allocations, getter_sites, leaks);
    total += leaks;
  }
  publication_reset(0);
#if defined(_WIN32)
  if (!RemoveDirectoryA(publication_root)) abort();
#else
  if (rmdir(publication_root) != 0) abort();
#endif
  printf("filesystem-publication-faults native_leaks=%zu ownership_errors=%zu\n", total, probe_ownership_errors);
  return total == 0U && probe_ownership_errors == 0U ? 0 : 1;
}
