/*
Author: WaterRun
Date: 2026-10-08
File: terminal_input_faults.c
Description: Injects persistent Lua allocation failures into production terminal text/EOF/cancellation projection, checks native resource ownership and repeated same-owner recovery, and verifies transient startup mode retention.
*/

#include "filesystem_fault_tracker.h"
#if defined(_WIN32)
#include <io.h>
#endif

/* @enum terminal_case Selects one actual redirected input or bounded completed-console fixture.
 * @field TERMINAL_TEXT Read fixed bytes from an owned temporary file through the production redirected port.
 * @field TERMINAL_EOF Read the end of that same file and deliver completed truth.
 * @field TERMINAL_CANCEL Deliver already requested cancellation without reading stdin.
 * @field TERMINAL_COOKED_TEXT Project a completed UTF-16 reader double on Windows.
 * @field TERMINAL_COOKED_EOF Project a completed empty reader double on Windows.
 */
typedef enum terminal_case {
  TERMINAL_TEXT, TERMINAL_EOF, TERMINAL_CANCEL,
  TERMINAL_COOKED_TEXT, TERMINAL_COOKED_EOF
} terminal_case;

static size_t terminal_protocol_failures;
static int terminal_explode_getter;

/* Count current-process OS resources without retaining an observation descriptor.
 * @param none Uses only this owned qualification process.
 * @return size_t All current handles/descriptors after closing the observation directory.
 * @error Aborts when the operating system cannot provide a complete count.
 */
static size_t terminal_os_resources(void)
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

/* Audit native buffers while distinguishing the terminal's retained completed reader from escaped allocations.
 * @param terminal yaca_terminal* Live referenced owner, or NULL after the state is closed.
 * @param site size_t Armed growth threshold used only for the diagnostic label.
 * @return size_t Number of confirmed escaped buffers rescued after recording the failure.
 * @effect Frees only tracked allocations not retained by the current terminal owner; preserves its valid reader.
 */
static size_t terminal_audit(yaca_terminal *terminal, size_t site)
{
  size_t index;
  size_t leaks = 0U;
  (void)terminal;
  for (index = 0U; index < PROBE_CAPACITY; ++index)
  {
    void *pointer = probe_buffers[index];
    if (pointer == NULL) continue;
#if defined(_WIN32)
    if (terminal != NULL && terminal->cooked_read != NULL
        && (pointer == terminal->cooked_read || pointer == terminal->cooked_read->wide)) continue;
#endif
    ++leaks;
    printf("terminal-buffer-leak site=%zu bytes=%zu\n", site, probe_sizes[index]);
    probe_free(pointer);
  }
  return leaks;
}

/* Restore one test profile on the same owner and rewind the same owned input file.
 * @param terminal yaca_terminal* Referenced production owner whose next input profile is prepared.
 * @param input FILE* Owned temporary file; terminal borrows its OS handle without taking ownership.
 * @param kind terminal_case Redirected text/EOF/cancel or a completed-console double.
 * @return void No value; prepares fixed bytes, outcome flags and, on Windows, one signalled reader event.
 * @effect Rewrites only the temporary file, or acquires a completed reader double using tracked production-style storage.
 * @error Aborts for inconsistent fixture setup; no real host console settings are changed.
 */
static void terminal_prepare(yaca_terminal *terminal, FILE *input, terminal_case kind)
{
  char bytes[256];
  memset(bytes, 't', sizeof(bytes));
  terminal->outcome[0] = '\0'; terminal->terminal_emitted = 0;
  terminal->cancelled = kind == TERMINAL_CANCEL;
  terminal->restored = 1;
  terminal->maximum_input_bytes = 8192U;
  rewind(input);
  if (fwrite(bytes, 1U, sizeof(bytes), input) != sizeof(bytes) || fflush(input) != 0) abort();
  if (kind == TERMINAL_EOF) { if (fseek(input, 0L, SEEK_END) != 0) abort(); }
  else rewind(input);
#if defined(_WIN32)
  if (terminal->cooked_read != NULL) free_windows_cooked_read(terminal);
  terminal->input = (HANDLE)_get_osfhandle(_fileno(input));
  terminal->input_type = FILE_TYPE_DISK;
  terminal->has_original_mode = kind >= TERMINAL_COOKED_TEXT;
  terminal->cooked_mode = kind >= TERMINAL_COOKED_TEXT;
  if (terminal->cooked_mode)
  {
    yaca_terminal_read *read = probe_calloc(1U, sizeof(*read));
    size_t index;
    if (read == NULL) abort();
    read->wide = probe_malloc(256U * sizeof(WCHAR));
    if (read->wide == NULL) abort();
    read->capacity = 256U;
    /* This completed-reader double has only the terminal reference. */
    read->references = 1;
    read->received = kind == TERMINAL_COOKED_TEXT ? 256U : 0U;
    for (index = 0U; index < 256U; ++index) read->wide[index] = L't';
    read->thread = CreateEventW(NULL, TRUE, TRUE, NULL);
    if (read->thread == NULL) abort();
    terminal->cooked_read = read;
  }
#else
  terminal->input = fileno(input);
#endif
}

/* Invoke the production poll with the supplied persistent allocation threshold.
 * @param L lua_State* State retaining the same terminal owner by reference.
 * @param reference int Registry reference to the live terminal owner.
 * @param fault probe_lua_fault* Allocator state armed only for this protected port invocation.
 * @return int Lua status; success leaves true/events, failure leaves its error object.
 * @effect Reads only the owned input fixture or completed reader double.
 */
static int terminal_poll(lua_State *L, int reference, probe_lua_fault *fault)
{
  int status;
  lua_pushcfunction(L, l_terminal_poll); lua_rawgeti(L, LUA_REGISTRYINDEX, reference);
  lua_pushinteger(L, 0); lua_pushinteger(L, 1);
  fault->calls = 0U; fault->armed = 1;
  status = lua_pcall(L, 3, 2, 0);
  fault->armed = 0;
  return status;
}

/* Verify the actual returned event, including exact text bytes or the expected terminal truth.
 * @param L lua_State* Successful protected poll results true/events at indices 1/2.
 * @param kind terminal_case Expected text, completed EOF or cancelled profile.
 * @return int One for one exact event, zero for an absent terminal event on the faulty baseline.
 * @error Aborts for malformed result shape or unexpected event content.
 */
static int terminal_result(lua_State *L, terminal_case kind)
{
  const char *actual;
  if (lua_gettop(L) != 2 || !lua_toboolean(L, 1) || !lua_istable(L, 2)) abort();
  if (lua_rawlen(L, 2) == 0U) return 0;
  if (lua_rawlen(L, 2) != 1U) abort();
  lua_rawgeti(L, 2, 1); lua_getfield(L, -1, "kind"); actual = lua_tostring(L, -1);
  if (kind == TERMINAL_TEXT || kind == TERMINAL_COOKED_TEXT)
  {
    size_t length;
    size_t index;
    if (actual == NULL || strcmp(actual, "action") != 0) abort();
    lua_getfield(L, -2, "text"); actual = lua_tolstring(L, -1, &length);
    if (actual == NULL || length != 256U) abort();
    for (index = 0U; index < length; ++index) if (actual[index] != 't') abort();
  }
  else
  {
    const char *expected = kind == TERMINAL_CANCEL ? "cancelled" : "completed";
    if (actual == NULL || strcmp(actual, "terminal") != 0) abort();
    lua_getfield(L, -2, "outcome"); actual = lua_tostring(L, -1);
    if (actual == NULL || strcmp(actual, expected) != 0) abort();
  }
  lua_settop(L, 0);
  return 1;
}

/* Run two faults and two exact recoveries through one terminal owner, then finalize all resources.
 * @param kind terminal_case Input profile retained for both cycles.
 * @param site size_t First persistent Lua growth rejection, or SIZE_MAX for observation.
 * @param leaks size_t* Accumulates confirmed escaped native buffers.
 * @return size_t Observed first-poll growth count.
 * @effect Creates one isolated Lua state and input file; verifies event retry, join and no duplicate terminal delivery.
 * @error Aborts for unexpected Lua statuses or OS resource growth after state/file cleanup.
 */
static size_t terminal_check(terminal_case kind, size_t site, size_t *leaks)
{
  probe_lua_fault fault = { 0U, site, 0 };
  lua_State *L = lua_newstate(probe_lua_allocate, &fault, 0U);
  FILE *input = tmpfile();
  yaca_terminal *terminal;
  size_t baseline;
  size_t observed = 0U;
  size_t cycle;
  int reference;
  if (L == NULL || input == NULL) abort();
  baseline = terminal_os_resources();
  create_handle_metatable(L, YACA_TERMINAL_METATABLE, l_terminal_gc);
  terminal = push_terminal(L); lua_pushvalue(L, -1); reference = luaL_ref(L, LUA_REGISTRYINDEX); lua_settop(L, 0);
  for (cycle = 0U; cycle < 2U; ++cycle)
  {
    int status;
    int first_delivered = 0;
    probe_lua_fault passive = { 0U, SIZE_MAX, 0 };
    terminal_prepare(terminal, input, kind);
    status = terminal_poll(L, reference, &fault);
    if (cycle == 0U) observed = fault.calls;
    if (status == LUA_OK) { first_delivered = terminal_result(L, kind); if (!first_delivered) abort(); }
    else if (status != LUA_ERRMEM) abort();
    lua_settop(L, 0); lua_gc(L, LUA_GCCOLLECT); lua_gc(L, LUA_GCCOLLECT);
    *leaks += terminal_audit(terminal, site);
    if (!first_delivered && kind != TERMINAL_TEXT && kind != TERMINAL_COOKED_TEXT)
    {
      if (terminal_poll(L, reference, &passive) != LUA_OK) abort();
      if (!terminal_result(L, kind)) ++terminal_protocol_failures;
      lua_settop(L, 0);
    }
    terminal_prepare(terminal, input, kind);
    if (terminal_poll(L, reference, &passive) != LUA_OK || !terminal_result(L, kind)) abort();
    if (kind != TERMINAL_TEXT && kind != TERMINAL_COOKED_TEXT)
    {
      lua_pushcfunction(L, l_terminal_join); lua_rawgeti(L, LUA_REGISTRYINDEX, reference);
      if (lua_pcall(L, 1, 2, 0) != LUA_OK || !lua_toboolean(L, 1)) abort();
      lua_settop(L, 0);
      if (terminal_poll(L, reference, &passive) != LUA_OK || lua_rawlen(L, 2) != 0U) abort();
      lua_settop(L, 0);
    }
    lua_gc(L, LUA_GCCOLLECT); lua_gc(L, LUA_GCCOLLECT);
    *leaks += terminal_audit(terminal, site);
  }
  lua_close(L);
  *leaks += terminal_audit(NULL, site);
  if (terminal_os_resources() != baseline) abort();
  if (fclose(input) != 0) abort();
  return observed;
}

/* Supply a transient mode, then collect it from the next getter or raise a deterministic request exception.
 * @param L lua_State* Arguments are the request proxy and fixed field key.
 * @return int One fresh mode or input bound; no normal return for the configured maximum getter error.
 * @error Raises probe-getter-error only when terminal_explode_getter is set.
 * @effect Forces full collection from the maximum getter before production uses the borrowed mode again.
 */
static int terminal_request_getter(lua_State *L)
{
  const char *key = lua_tostring(L, 2);
  if (key != NULL && strcmp(key, "mode") == 0) { lua_pushstring(L, "auto"); return 1; }
  if (key != NULL && strcmp(key, "maximum_input_bytes") == 0)
  {
    if (terminal_explode_getter) return probe_exploding_getter(L);
    lua_gc(L, LUA_GCCOLLECT); lua_gc(L, LUA_GCCOLLECT);
    lua_pushinteger(L, 8192); return 1;
  }
  lua_pushnil(L); return 1;
}

/* Verify actual startup getter failure or transient mode startup and explicit restoration.
 * @param explode int Nonzero selects the deterministic maximum getter error; zero selects transient mode collection.
 * @return int Zero for the expected failure or successful startup/restoration, one for a typed unexpected rejection.
 * @effect Changes only this probe's borrowed stdin mode during a successful startup, then restores it before state close.
 * @error Aborts if restoration/close is inconsistent; sanitizer may diagnose the unfixed transient mode path.
 */
static int terminal_start_control(int explode)
{
  lua_State *L = luaL_newstate();
  int status;
  int success = 0;
  if (L == NULL) abort();
  create_handle_metatable(L, YACA_TERMINAL_METATABLE, l_terminal_gc);
  terminal_explode_getter = explode;
  lua_pushcfunction(L, l_terminal_start); lua_createtable(L, 0, 0);
  /* @metatable terminal_request_proxy Supplies a transient mode and a deterministic second-field control.
   * @field __index function Reads only the fixed mode/maximum fields without retaining the mode in the caller table.
   */
  lua_createtable(L, 0, 1); lua_pushcfunction(L, terminal_request_getter); lua_setfield(L, -2, "__index");
  /* @metatable terminal_request_proxy Attach the counted request-field control declared above.
   * @field __index function Returns transient values or raises before terminal settings should change.
   */
  lua_setmetatable(L, -2);
  status = lua_pcall(L, 1, 2, 0);
  if (explode)
  {
    const char *message = lua_tostring(L, -1);
    success = status == LUA_ERRRUN && message != NULL && strstr(message, "probe-getter-error") != NULL;
  }
  else if (status == LUA_OK && lua_toboolean(L, 1))
  {
    lua_pushcfunction(L, l_terminal_close); lua_pushvalue(L, 2);
    if (lua_pcall(L, 1, 2, 0) != LUA_OK || !lua_toboolean(L, -2)) abort();
    success = 1;
  }
  lua_close(L);
  if (terminal_audit(NULL, SIZE_MAX) != 0U) success = 0;
  printf("terminal-start-control getter=%d result=%s\n", explode, success ? "PASS" : "FAIL");
  return success ? 0 : 1;
}

/* Verify existing redirected control-byte behavior and binary text preservation without changing terminal settings.
 * @param none Uses an owned input file and production terminal poll on this platform.
 * @return void No value; exact intent/text mismatches abort rather than becoming a skipped check.
 * @effect Reads five fixed byte sequences and closes the Lua state/file with all native resources accounted for.
 */
static void terminal_byte_controls(void)
{
  static const char *const values[] = { "\033", "\n", "\r", "\r\n", "x\0y" };
  static const size_t lengths[] = { 1U, 1U, 1U, 2U, 3U };
  lua_State *L = luaL_newstate();
  FILE *input = tmpfile();
  yaca_terminal *terminal;
  size_t index;
  int reference;
  if (L == NULL || input == NULL) abort();
  create_handle_metatable(L, YACA_TERMINAL_METATABLE, l_terminal_gc);
  terminal = push_terminal(L); reference = luaL_ref(L, LUA_REGISTRYINDEX);
  for (index = 0U; index < sizeof(lengths) / sizeof(lengths[0]); ++index)
  {
    const char *intent;
    const char *expected = "text";
    probe_lua_fault passive = { 0U, SIZE_MAX, 0 };
    terminal_prepare(terminal, input, TERMINAL_TEXT);
    rewind(input);
    if (fwrite(values[index], 1U, lengths[index], input) != lengths[index] || fflush(input) != 0) abort();
#if defined(_WIN32)
    if (_chsize(_fileno(input), (long)lengths[index]) != 0) abort();
#else
    if (ftruncate(fileno(input), (off_t)lengths[index]) != 0) abort();
    if (index == 0U) expected = "cancel";
    else if (index <= 2U) expected = "submit-or-queue";
#endif
    rewind(input);
    if (terminal_poll(L, reference, &passive) != LUA_OK || !lua_toboolean(L, 1) || lua_rawlen(L, 2) != 1U) abort();
    lua_rawgeti(L, 2, 1); lua_getfield(L, -1, "intent"); intent = lua_tostring(L, -1);
    if (intent == NULL || strcmp(intent, expected) != 0) abort();
    lua_getfield(L, -2, "text");
    if (strcmp(expected, "text") == 0)
    {
      size_t length;
      const char *bytes = lua_tolstring(L, -1, &length);
      if (bytes == NULL || length != lengths[index] || memcmp(bytes, values[index], length) != 0) abort();
    }
    else if (!lua_isnil(L, -1)) abort();
    lua_settop(L, 0);
  }
  lua_close(L);
  if (terminal_audit(NULL, SIZE_MAX) != 0U || fclose(input) != 0) abort();
  puts("terminal-byte-controls cases=5 result=PASS");
}

#if defined(_WIN32)
/* Verify malformed UTF-16 and byte-limit failures release their completed reader and temporary projection storage.
 * @param none Uses four bounded completed-console doubles on one terminal owner.
 * @return size_t Escaped native buffers observed across the invalid cooked-line controls.
 * @effect Exercises the production typed rejection path and closes every owned reader event and backing file.
 * @error Aborts for a wrong typed code or any OS handle growth.
 */
static size_t terminal_cooked_controls(void)
{
  lua_State *L = luaL_newstate();
  FILE *input = tmpfile();
  yaca_terminal *terminal;
  size_t baseline;
  size_t total = 0U;
  size_t index;
  int reference;
  if (L == NULL || input == NULL) abort();
  baseline = terminal_os_resources();
  create_handle_metatable(L, YACA_TERMINAL_METATABLE, l_terminal_gc);
  terminal = push_terminal(L); reference = luaL_ref(L, LUA_REGISTRYINDEX);
  for (index = 0U; index < 4U; ++index)
  {
    const char *code;
    const char *expected = index == 3U ? "Limit" : "InvalidEncoding";
    probe_lua_fault passive = { 0U, SIZE_MAX, 0 };
    terminal_prepare(terminal, input, TERMINAL_COOKED_TEXT);
    if (index == 0U) terminal->cooked_read->wide[0] = 0U;
    else if (index == 1U) { terminal->cooked_read->wide[0] = 0xD800U; terminal->cooked_read->received = 1U; }
    else if (index == 2U) terminal->cooked_read->wide[0] = 0xDC00U;
    else terminal->maximum_input_bytes = 2U;
    if (terminal_poll(L, reference, &passive) != LUA_OK || lua_toboolean(L, 1) || !lua_istable(L, 2)) abort();
    lua_getfield(L, 2, "code"); code = lua_tostring(L, -1);
    if (code == NULL || strcmp(code, expected) != 0) abort();
    lua_settop(L, 0); lua_gc(L, LUA_GCCOLLECT); lua_gc(L, LUA_GCCOLLECT);
    total += terminal_audit(terminal, SIZE_MAX);
    if (terminal->cooked_read != NULL || terminal_os_resources() != baseline) abort();
  }
  lua_close(L);
  total += terminal_audit(NULL, SIZE_MAX);
  if (fclose(input) != 0) abort();
  puts("terminal-cooked-controls cases=4 typed-rejection=PASS");
  return total;
}
#endif

/* Exercise each platform's input projection faults and same-owner recovery without using a host console double as real-console qualification.
 * @param argc int One for the full probe; two for the optional transient-only startup control.
 * @param argv char** Optional argv[1] must be --transient-only; no paths or credentials are accepted.
 * @return int Zero for zero leaks/ownership/protocol failures; one for observed baseline failures, 64 for usage.
 * @effect Uses only owned temporary input files, completed-console doubles and this process's stdin restoration state.
 */
int main(int argc, char **argv)
{
  size_t kind;
  size_t total = 0U;
#if defined(_WIN32)
  size_t cases = 5U;
#else
  size_t cases = 3U;
#endif
  setbuf(stdout, NULL);
  if (argc == 2 && strcmp(argv[1], "--transient-only") == 0) return terminal_start_control(0);
  if (argc != 1) return 64;
  for (kind = 0U; kind < cases; ++kind)
  {
    size_t leaks = 0U;
    size_t site;
    size_t sites = terminal_check((terminal_case)kind, SIZE_MAX, &leaks);
    for (site = 1U; site <= sites + 2U; ++site) terminal_check((terminal_case)kind, site, &leaks);
    printf("terminal-input profile=%zu allocation_sites=%zu native_leaks=%zu recovery=PASS\n", kind, sites, leaks);
    total += leaks;
  }
  if (terminal_start_control(1) != 0) ++terminal_protocol_failures;
  terminal_byte_controls();
#if defined(_WIN32)
  total += terminal_cooked_controls();
#endif
  printf("terminal-input-faults native_leaks=%zu ownership_errors=%zu protocol_failures=%zu\n", total, probe_ownership_errors, terminal_protocol_failures);
  return total == 0U && probe_ownership_errors == 0U && terminal_protocol_failures == 0U ? 0 : 1;
}
