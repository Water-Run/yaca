/*
Author: WaterRun
Date: 2026-10-06
File: process_start_faults.c
Description: Injects persistent Lua allocation and request-getter failures into real supervised process startup, auditing native buffers and OS resource counts and proving repeated same-state recovery plus stable argv capture.
*/

#include "filesystem_fault_tracker.h"

/* @enum start_mode Chooses a fixed shell or the supplied isolated component probe.
 * @field START_COMPONENT Launch the caller-supplied absolute qualification executable with one exact argument and empty stdin.
 * @field START_SHELL Launch only the production allowlisted shell with one fixed print command.
 */
typedef enum start_mode { START_COMPONENT, START_SHELL } start_mode;

static const char *start_executable;
static int start_explode_environment;
static int start_change_arguments;
static int start_transient_executable;
static size_t start_argument_reads;
static size_t start_protocol_failures;

/* Read the saved request, rejecting environment or returning alternating argument maps when configured.
 * @param L lua_State* Arguments are request proxy and key; upvalue 1 holds the valid backing request.
 * @return int One saved field, or a one-entry changed argument table on the second configured argument read.
 * @error Raises the deterministic probe-getter-error for the selected environment lookup.
 * @effect Counts argument reads and optionally forces full GC after a transient executable result; leaves backing data and files unchanged.
 */
static int start_request_getter(lua_State *L)
{
  const char *key = lua_tostring(L, 2);
  if (key != NULL && strcmp(key, "executable") == 0 && start_transient_executable)
  {
    lua_pushlstring(L, start_executable, strlen(start_executable));
    return 1;
  }
  if (key != NULL && strcmp(key, "stdin") == 0 && start_transient_executable)
  {
    lua_gc(L, LUA_GCCOLLECT); lua_gc(L, LUA_GCCOLLECT);
  }
  if (key != NULL && strcmp(key, "environment") == 0 && start_explode_environment)
    return probe_exploding_getter(L);
  if (key != NULL && strcmp(key, "arguments") == 0)
  {
    ++start_argument_reads;
    if (start_change_arguments && start_argument_reads > 1U)
    {
      lua_createtable(L, 1, 0); lua_pushliteral(L, "changed-argument"); lua_rawseti(L, -2, 1);
      return 1;
    }
  }
  lua_pushvalue(L, 2); lua_rawget(L, lua_upvalueindex(1));
  return 1;
}

/* Build one real request and retain it through a counted proxy until the startup call finishes.
 * @param L lua_State* Receives the production start function and one proxy request.
 * @param mode start_mode Selects the component fixture or fixed platform shell.
 * @param numeric int Zero supplies string entries; one adds a numeric key, two a numeric value, three omits environment.
 * @return void No result; leaves exactly function/request ready for lua_pcall with one argument.
 * @effect Creates only Lua data; all child environment values are fixed qualification strings.
 */
static void start_push_request(lua_State *L, start_mode mode, int numeric)
{
  size_t index;
  lua_pushcfunction(L, l_process_start);
  lua_createtable(L, 0, 8);
  lua_pushliteral(L, "."); lua_setfield(L, -2, "cwd");
  lua_pushinteger(L, 0); lua_setfield(L, -2, "started_at");
  if (mode == START_COMPONENT)
  {
    lua_pushliteral(L, "argv"); lua_setfield(L, -2, "mode");
    lua_pushstring(L, start_executable); lua_setfield(L, -2, "executable");
    lua_createtable(L, 1, 0); lua_pushliteral(L, "trusted-argument"); lua_rawseti(L, -2, 1);
    lua_setfield(L, -2, "arguments");
    lua_createtable(L, 0, 3);
    lua_pushliteral(L, "bytes"); lua_setfield(L, -2, "kind");
    lua_pushliteral(L, "anonymous-pipe"); lua_setfield(L, -2, "carrier");
    lua_pushliteral(L, ""); lua_setfield(L, -2, "bytes");
    lua_setfield(L, -2, "stdin");
  }
  else
  {
#if defined(_WIN32)
    lua_pushliteral(L, "echo yaca-start-recovery"); lua_setfield(L, -2, "command");
    lua_createtable(L, 0, 2);
    lua_pushliteral(L, "windows"); lua_setfield(L, -2, "kind");
    lua_pushliteral(L, "native-GetSystemDirectoryW/cmd.exe"); lua_setfield(L, -2, "executable");
#else
    lua_pushliteral(L, "printf yaca-start-recovery"); lua_setfield(L, -2, "command");
    lua_createtable(L, 0, 2);
    lua_pushliteral(L, "linux"); lua_setfield(L, -2, "kind");
    lua_pushliteral(L, "/bin/sh"); lua_setfield(L, -2, "executable");
#endif
    lua_setfield(L, -2, "shell");
  }
  lua_createtable(L, 0, 16);
  for (index = 0U; index < 16U; ++index)
  {
    char key[32];
    snprintf(key, sizeof(key), "YACA_START_PROBE_%zu", index);
    lua_pushstring(L, key); lua_pushliteral(L, "fixed-environment-value"); lua_rawset(L, -3);
  }
  if (numeric == 1)
  {
    lua_pushinteger(L, 123); lua_pushliteral(L, "numeric-key"); lua_rawset(L, -3);
  }
  else if (numeric == 2)
  {
    lua_pushinteger(L, 456); lua_setfield(L, -2, "NUMERIC_VALUE");
  }
  if (numeric == 3) lua_pop(L, 1);
  else lua_setfield(L, -2, "environment");
  lua_createtable(L, 0, 0);
  /* @metatable start_request_proxy Empty request proxy holding the complete backing request in its getter closure.
   * @field __index function Supplies saved fields or the selected deterministic exception/changed argument map.
   */
  lua_createtable(L, 0, 1); lua_pushvalue(L, -3);
  lua_pushcclosure(L, start_request_getter, 1); lua_setfield(L, -2, "__index");
  /* @metatable start_request_proxy Attach the request-read probe declared above.
   * @field __index function Reads the stable backing request; no native resource is acquired here.
   */
  lua_setmetatable(L, -2); lua_remove(L, -2);
}

/* Count all current-process OS descriptors/handles, including uninstrumented pipes and jobs.
 * @param none Uses only the process hosting this qualification probe.
 * @return size_t Total open descriptor/handle count after closing the observation handle itself.
 * @effect Briefly opens /proc/self/fd on Linux; Windows uses GetProcessHandleCount.
 * @error Aborts when the host cannot supply an authoritative resource count.
 */
static size_t start_os_resources(void)
{
#if defined(_WIN32)
  DWORD count;
  if (!GetProcessHandleCount(GetCurrentProcess(), &count)) abort();
  return (size_t)count;
#else
  DIR *directory = opendir("/proc/self/fd");
  struct dirent *entry;
  size_t count = 0U;
  if (directory == NULL) abort();
  while ((entry = readdir(directory)) != NULL)
    if (strcmp(entry->d_name, ".") != 0 && strcmp(entry->d_name, "..") != 0) ++count;
  if (closedir(directory) != 0 || count == 0U) abort();
  return count - 1U;
#endif
}

/* Drain one real process to its proven terminal state and close its owner.
 * @param L lua_State* Contains a successful true/process pair at indices 1/2.
 * @param mode start_mode Selects the expected component or shell stdout bytes.
 * @return int One for exact expected output and successful exit, zero for a changed argument result.
 * @effect Polls only this child, joins its native result and explicitly closes the process owner.
 * @error Aborts if startup, bounded supervision, join or native close is inconsistent.
 */
static int start_finish(lua_State *L, start_mode mode)
{
  int reference;
  int terminal = 0;
  int attempt;
  char output[1024];
  size_t output_length = 0U;
  int matches;
  const char *expected;
  if (lua_gettop(L) != 2 || !lua_toboolean(L, 1) || lua_type(L, 2) != LUA_TUSERDATA) abort();
  lua_pushvalue(L, 2); reference = luaL_ref(L, LUA_REGISTRYINDEX); lua_settop(L, 0);
  for (attempt = 0; attempt < 1000 && !terminal; ++attempt)
  {
    lua_Integer index;
    lua_pushcfunction(L, l_process_poll); lua_rawgeti(L, LUA_REGISTRYINDEX, reference);
    lua_pushinteger(L, native_monotonic_milliseconds()); lua_pushinteger(L, 16); lua_pushinteger(L, 4096);
    if (lua_pcall(L, 4, 2, 0) != LUA_OK || !lua_toboolean(L, 1)) abort();
    for (index = 1; index <= (lua_Integer)lua_rawlen(L, 2); ++index)
    {
      const char *kind;
      lua_rawgeti(L, 2, index); lua_getfield(L, -1, "kind"); kind = lua_tostring(L, -1);
      if (kind == NULL) abort();
      if (strcmp(kind, "stdout") == 0)
      {
        size_t length;
        const char *bytes;
        lua_getfield(L, -2, "bytes"); bytes = lua_tolstring(L, -1, &length);
        if (bytes == NULL || length > sizeof(output) - output_length - 1U) abort();
        memcpy(output + output_length, bytes, length); output_length += length;
        lua_pop(L, 1);
      }
      else if (strcmp(kind, "terminal") == 0) terminal = 1;
      lua_pop(L, 2);
    }
    lua_settop(L, 0);
#if defined(_WIN32)
    if (!terminal) Sleep(5);
#else
    if (!terminal) usleep(5000);
#endif
  }
  if (!terminal) abort();
  output[output_length] = '\0';
  lua_pushcfunction(L, l_process_join); lua_rawgeti(L, LUA_REGISTRYINDEX, reference);
  lua_pushinteger(L, native_monotonic_milliseconds());
  if (lua_pcall(L, 2, 2, 0) != LUA_OK || !lua_toboolean(L, 1)) abort();
  lua_getfield(L, 2, "exit_code"); if (lua_tointeger(L, -1) != 0) abort(); lua_pop(L, 1);
  lua_getfield(L, 2, "descendants_proven_stopped"); if (!lua_toboolean(L, -1)) abort(); lua_pop(L, 1);
  lua_settop(L, 0);
  lua_pushcfunction(L, l_process_close); lua_rawgeti(L, LUA_REGISTRYINDEX, reference);
  if (lua_pcall(L, 1, 2, 0) != LUA_OK || !lua_toboolean(L, 1)) abort();
  luaL_unref(L, LUA_REGISTRYINDEX, reference); lua_settop(L, 0);
  if (mode == START_COMPONENT)
    expected = "argc=2\narg1=747275737465642d617267756d656e74\nstdin=\n";
#if defined(_WIN32)
  else expected = "yaca-start-recovery\r\n";
#else
  else expected = "yaca-start-recovery";
#endif
  matches = strcmp(output, expected) == 0;
  return matches;
}

/* Audit tracked native buffers after collection, rescuing only confirmed old-code leaks.
 * @param label const_char* Stable diagnostic label.
 * @param site size_t Armed Lua growth site, or SIZE_MAX for a getter/control case.
 * @return size_t Count of buffers and tracked file handles/descriptors still live.
 * @effect Prints leaking cases, frees/closes observed old-code resources, and resets the bounded tracker.
 */
static size_t start_audit(const char *label, size_t site)
{
  size_t index;
  size_t leaks = probe_live;
#if defined(_WIN32)
  leaks += probe_handle_count;
#else
  leaks += probe_descriptor_count;
#endif
  if (leaks != 0U) printf("LEAK %s site=%zu buffers=%zu resources=%zu\n", label, site, probe_live, leaks);
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

/* Run two startup faults and two genuine recoveries in one Lua state while proving no OS resource growth.
 * @param mode start_mode Real component or fixed shell startup profile.
 * @param site size_t First persistently rejected Lua growth request, or SIZE_MAX for observation.
 * @param getter int Nonzero raises from the environment getter instead of rejecting Lua allocation.
 * @param leaks size_t* Accumulates native resources surviving full collection.
 * @return size_t Armed Lua growth count observed during the first startup call.
 * @effect Spawns only fixed shell commands or the supplied owned probe; every recovery reaches proven termination.
 * @error Aborts for an unexpected failure or any increase in all-process OS descriptors/handles.
 */
static size_t start_check(start_mode mode, size_t site, int getter, size_t *leaks)
{
  probe_lua_fault fault = { 0U, site, 0 };
  lua_State *L = lua_newstate(probe_lua_allocate, &fault, 0U);
  size_t baseline;
  size_t observed = 0U;
  size_t cycle;
  if (L == NULL) abort();
  create_handle_metatable(L, YACA_PROCESS_METATABLE, l_process_gc);
  start_explode_environment = 0; start_change_arguments = 0;
  start_push_request(L, mode, 0);
  if (lua_pcall(L, 1, 2, 0) != LUA_OK || !start_finish(L, mode)) abort();
  lua_gc(L, LUA_GCCOLLECT); lua_gc(L, LUA_GCCOLLECT);
  *leaks += start_audit("warmup", site);
  baseline = start_os_resources();
  for (cycle = 0U; cycle < 2U; ++cycle)
  {
    int status;
    start_explode_environment = getter;
    start_push_request(L, mode, 0);
    fault.calls = 0U; fault.armed = !getter;
    status = lua_pcall(L, 1, LUA_MULTRET, 0);
    fault.armed = 0; start_explode_environment = 0;
    if (cycle == 0U) observed = fault.calls;
    if (getter)
    {
      const char *message = lua_tostring(L, -1);
      if (status != LUA_ERRRUN || message == NULL || strstr(message, "probe-getter-error") == NULL) abort();
    }
    else if (status == LUA_OK)
    {
      if (!start_finish(L, mode)) abort();
    }
    else if (status != LUA_ERRMEM) abort();
    lua_settop(L, 0); lua_gc(L, LUA_GCCOLLECT); lua_gc(L, LUA_GCCOLLECT);
    *leaks += start_audit(mode == START_COMPONENT ? "component" : "shell", site);
    if (start_os_resources() != baseline) abort();
    start_push_request(L, mode, 0);
    if (lua_pcall(L, 1, 2, 0) != LUA_OK || !start_finish(L, mode)) abort();
    lua_gc(L, LUA_GCCOLLECT); lua_gc(L, LUA_GCCOLLECT);
    *leaks += start_audit("recovery", site);
    if (start_os_resources() != baseline) abort();
  }
  lua_close(L);
  *leaks += start_audit("state-close", site);
  if (start_os_resources() != baseline) abort();
  return observed;
}

/* Prove argv uses one admitted argument field and both invocation modes reject malformed or absent environments.
 * @param none Uses only the supplied component executable and fixed qualification data.
 * @return size_t Native resources leaked by stable-argv and malformed-environment controls after collection.
 * @effect Starts/joins/closes any successfully launched owned probe and collects all state owners.
 * @error Aborts if a control cannot be observed safely or leaves OS resources open.
 */
static size_t start_protocol_controls(void)
{
  lua_State *L = luaL_newstate();
  int numeric;
  int status;
  size_t total = 0U;
  size_t mode;
  size_t baseline;
  if (L == NULL) abort();
  create_handle_metatable(L, YACA_PROCESS_METATABLE, l_process_gc);
  start_change_arguments = 1; start_argument_reads = 0U;
  start_push_request(L, START_COMPONENT, 0);
  if (lua_pcall(L, 1, 2, 0) != LUA_OK) abort();
  if (!start_finish(L, START_COMPONENT) || start_argument_reads != 1U) ++start_protocol_failures;
  printf("stable-argv reads=%zu result=%s\n", start_argument_reads, start_protocol_failures == 0U ? "PASS" : "FAIL");
  start_change_arguments = 0;
  lua_gc(L, LUA_GCCOLLECT); lua_gc(L, LUA_GCCOLLECT);
  total += start_audit("stable-argv", SIZE_MAX);
  baseline = start_os_resources();
  for (mode = 0U; mode < 2U; ++mode)
  {
    for (numeric = 1; numeric <= 3; ++numeric)
    {
      int accepted = 0;
      start_push_request(L, (start_mode)mode, numeric);
      status = lua_pcall(L, 1, 2, 0);
      if (status == LUA_OK && !lua_toboolean(L, 1) && lua_istable(L, 2))
      {
        const char *code;
        lua_getfield(L, 2, "code"); code = lua_tostring(L, -1);
        accepted = code != NULL && strcmp(code, "InvalidEnvironment") == 0;
      }
      else if (status == LUA_OK && lua_toboolean(L, 1)) start_finish(L, (start_mode)mode);
      if (!accepted) ++start_protocol_failures;
      lua_settop(L, 0); lua_gc(L, LUA_GCCOLLECT); lua_gc(L, LUA_GCCOLLECT);
      total += start_audit("invalid-environment", SIZE_MAX);
      if (start_os_resources() != baseline) abort();
      printf("invalid-environment mode=%zu case=%d typed-rejection=%s\n", mode, numeric, accepted ? "PASS" : "FAIL");
    }
  }
  lua_close(L);
  total += start_audit("protocol-state-close", SIZE_MAX);
  if (start_os_resources() != baseline) abort();
  return total;
}

/* Force collection after a getter returns a transient executable string, then verify exact supervised argv output.
 * @param none Uses the supplied long absolute component path; only the returned transient Lua string owns its new allocation.
 * @return int Zero for exact launch/termination and one for a typed rejection or changed result.
 * @effect Forces full collection from the next caller getter before startup uses the executable bytes.
 * @error AddressSanitizer may terminate a baseline containing a dangling borrowed executable pointer.
 */
static int start_transient_control(void)
{
  lua_State *L = luaL_newstate();
  int status;
  int success = 0;
  if (L == NULL || strlen(start_executable) <= 40U) abort();
  create_handle_metatable(L, YACA_PROCESS_METATABLE, l_process_gc);
  start_transient_executable = 1;
  start_push_request(L, START_COMPONENT, 0);
  status = lua_pcall(L, 1, 2, 0);
  if (status == LUA_OK && lua_toboolean(L, 1)) success = start_finish(L, START_COMPONENT);
  lua_settop(L, 0); lua_gc(L, LUA_GCCOLLECT); lua_gc(L, LUA_GCCOLLECT);
  if (start_audit("transient-executable", SIZE_MAX) != 0U) success = 0;
  lua_close(L);
  printf("transient-executable result=%s\n", success ? "PASS" : "FAIL");
  return success ? 0 : 1;
}

/* Exercise persistent startup allocation faults and caller getter exceptions in both real invocation modes.
 * @param argc int Two for the complete probe, or three for the optional transient-only sanitizer case.
 * @param argv char** argv[1] is the absolute owned component probe; optional argv[2] must be --transient-only.
 * @return int Zero only for zero resource/ownership/protocol failures; one for confirmed baseline failures, 64 for usage.
 * @effect Launches only the fixed allowlisted shell and supplied qualification fixture and prints byte-bound observations.
 * @error Aborts on inconsistent supervision or incomplete resource recovery.
 */
int main(int argc, char **argv)
{
  size_t total = 0U;
  size_t mode;
  setbuf(stdout, NULL);
  if (argc != 2 && (argc != 3 || strcmp(argv[2], "--transient-only") != 0)) return 64;
  start_executable = argv[1];
  if (argc == 3) return start_transient_control();
  for (mode = 0U; mode < 2U; ++mode)
  {
    size_t leaks = 0U;
    size_t site;
    size_t allocations = start_check((start_mode)mode, SIZE_MAX, 0, &leaks);
    for (site = 1U; site <= allocations; ++site) start_check((start_mode)mode, site, 0, &leaks);
    start_check((start_mode)mode, SIZE_MAX, 1, &leaks);
    printf("%s allocation_sites=%zu native_leaks=%zu os_resources=stable recovery=PASS\n", mode == START_COMPONENT ? "component-start" : "shell-start", allocations, leaks);
    total += leaks;
  }
  total += start_protocol_controls();
  printf("process-start-faults native_leaks=%zu ownership_errors=%zu protocol_failures=%zu\n", total, probe_ownership_errors, start_protocol_failures);
  return total == 0U && probe_ownership_errors == 0U && start_protocol_failures == 0U ? 0 : 1;
}
