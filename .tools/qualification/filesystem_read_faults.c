/*
Author: WaterRun
Date: 2026-09-28
File: filesystem_read_faults.c
Description: Injects Lua allocation failures into production fs_read and checks native buffer cleanup plus same-handle recovery.
*/

#define _GNU_SOURCE
#define _POSIX_C_SOURCE 200809L
#define _XOPEN_SOURCE 700
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#if defined(_WIN32)
#include <io.h>
#else
#include <unistd.h>
#endif
#include "lua.h"
#include "lauxlib.h"

static void *observed_buffer;
static int observing;

/* Observe the single native read buffer acquired during the armed call.
 * @param size size_t Native allocation size requested by production code.
 * @return void* Allocated buffer or NULL on host allocation failure.
 * @effect Records an armed allocation; aborts if this narrow probe sees multiple live native buffers.
 * @ownership The production free wrapper normally releases the buffer; the probe cleans confirmed leaks after observation.
 */
static void *tracked_malloc(size_t size)
{
  void *result = malloc(size);
  if (observing && result != NULL)
  {
    if (observed_buffer != NULL) abort();
    observed_buffer = result;
  }
  return result;
}

/* Release a native buffer and clear its observation before deallocation.
 * @param pointer void* Native allocation or NULL.
 * @return void No value.
 * @effect Clears the observation when the production implementation frees its read buffer.
 */
static void tracked_free(void *pointer)
{
  if (pointer == observed_buffer) observed_buffer = NULL;
  free(pointer);
}

#define malloc tracked_malloc
#define free tracked_free
#include "../../native/yaca_native.c"
#undef malloc
#undef free

/* @struct allocation_fault Tracks persistent Lua growth failures during one native call.
 * @field calls size_t Number of armed growth allocation attempts.
 * @field fail_at size_t First growth allocation to reject, including all later emergency-GC retries.
 * @field armed int Whether allocation failure injection is active.
 */
typedef struct allocation_fault {
  size_t calls;
  size_t fail_at;
  int armed;
} allocation_fault;

/* Allocate Lua memory, persistently rejecting growth at the selected threshold.
 * @param opaque void* Caller-owned allocation_fault for the lifetime of the Lua state.
 * @param pointer void* Previous Lua allocation or NULL.
 * @param previous size_t Previous byte count, or Lua type tag for NULL pointers.
 * @param requested size_t New byte count; zero releases the block.
 * @return void* Resized block or NULL for free/injected/system failure.
 * @effect Counts armed growth requests and changes only Lua-owned allocations.
 */
static void *fault_allocate(void *opaque, void *pointer, size_t previous, size_t requested)
{
  allocation_fault *state = (allocation_fault *)opaque;
  if (requested == 0U) { free(pointer); return NULL; }
  if (state->armed && (pointer == NULL || requested > previous))
  {
    ++state->calls;
    if (state->calls >= state->fail_at) return NULL;
  }
  return realloc(pointer, requested);
}

/* Execute the real read port with a temporary file and one allocation threshold.
 * @param fail_at size_t First Lua growth allocation to reject, or SIZE_MAX for baseline observation.
 * @param leaks size_t* Receives an increment when a native buffer remains after the protected call.
 * @return size_t Number of observed Lua growth requests.
 * @effect Creates/closes a Lua state and temporary file; observes cleanup, rewinds and rereads the same handle after every call.
 * @error Aborts when setup, seek or output validation fails; confirmed leaked native buffers are cleaned after recording them.
 */
static size_t check_read(size_t fail_at, size_t *leaks)
{
  allocation_fault fault = { 0U, fail_at, 0 };
  lua_State *L = lua_newstate(fault_allocate, &fault, 0U);
  FILE *input = tmpfile();
  yaca_file *file;
  char bytes[8192];
  int status;
  int file_reference;
  if (L == NULL || input == NULL) abort();
  memset(bytes, 'x', sizeof(bytes));
  if (fwrite(bytes, 1U, sizeof(bytes), input) != sizeof(bytes)) abort();
  rewind(input);
  create_handle_metatable(L, YACA_FILE_METATABLE, l_file_gc);
  lua_pushcfunction(L, l_fs_read);
  file = push_file(L);
#if defined(_WIN32)
  if (!DuplicateHandle(GetCurrentProcess(), (HANDLE)_get_osfhandle(_fileno(input)),
      GetCurrentProcess(), &file->handle, 0U, FALSE, DUPLICATE_SAME_ACCESS)) abort();
#else
  file->descriptor = dup(fileno(input));
  if (file->descriptor < 0) abort();
#endif
  lua_pushvalue(L, -1);
  file_reference = luaL_ref(L, LUA_REGISTRYINDEX);
  lua_pushinteger(L, (lua_Integer)sizeof(bytes));
  fault.armed = 1;
  observing = 1;
  status = lua_pcall(L, 2, LUA_MULTRET, 0);
  observing = 0;
  fault.armed = 0;
  if (observed_buffer != NULL)
  {
    ++*leaks;
    printf("native-buffer-leak fail_at=%zu lua_status=%d bytes=%zu\n", fail_at, status, sizeof(bytes));
    free(observed_buffer);
    observed_buffer = NULL;
  }
  if (status != LUA_OK && status != LUA_ERRMEM) abort();
  lua_settop(L, 0);
  lua_pushcfunction(L, l_fs_seek);
  lua_rawgeti(L, LUA_REGISTRYINDEX, file_reference);
  lua_pushinteger(L, 0);
  if (lua_pcall(L, 2, LUA_MULTRET, 0) != LUA_OK || !lua_toboolean(L, 1)
      || lua_tointeger(L, 2) != 0) abort();
  lua_settop(L, 0);
  lua_pushcfunction(L, l_fs_read);
  lua_rawgeti(L, LUA_REGISTRYINDEX, file_reference);
  lua_pushinteger(L, (lua_Integer)sizeof(bytes));
  status = lua_pcall(L, 2, LUA_MULTRET, 0);
  {
    size_t length;
    const char *actual;
    if (status != LUA_OK || !lua_toboolean(L, 1)) abort();
    lua_getfield(L, 2, "bytes");
    actual = lua_tolstring(L, -1, &length);
    if (actual == NULL || length != sizeof(bytes) || memcmp(actual, bytes, length) != 0) abort();
  }
  lua_close(L);
  fclose(input);
  return fault.calls;
}

/* Observe an ordinary call, every Lua failure position and a native read-error cleanup path.
 * @param none No arguments; all fixtures are isolated and ephemeral.
 * @return int Zero only if no native read buffer escapes the protected call.
 * @effect Prints the allocation-site and confirmed-leak counts; every fixture is closed before exit.
 */
int main(void)
{
  size_t leaks = 0U;
  size_t sites = check_read(SIZE_MAX, &leaks);
  size_t index;
  for (index = 1U; index <= sites + 1U; ++index) check_read(index, &leaks);
  {
    lua_State *L = luaL_newstate();
    int status;
    if (L == NULL) abort();
    create_handle_metatable(L, YACA_FILE_METATABLE, l_file_gc);
    lua_pushcfunction(L, l_fs_read);
    push_file(L); /* A live owner containing the invalid native sentinel triggers the OS error path. */
    lua_pushinteger(L, 8192);
    observing = 1;
    status = lua_pcall(L, 2, LUA_MULTRET, 0);
    observing = 0;
    if (status != LUA_OK || lua_gettop(L) != 2 || lua_toboolean(L, 1)
        || !lua_istable(L, 2) || observed_buffer != NULL) abort();
    lua_getfield(L, 2, "code");
    if (lua_type(L, -1) != LUA_TSTRING) abort();
    lua_close(L);
  }
  printf("fs-read-faults allocation_sites=%zu native_leaks=%zu same_handle_recovery=PASS read_error=PASS\n", sites, leaks);
  return leaks == 0U ? 0 : 1;
}
