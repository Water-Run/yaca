/*
Author: WaterRun
Date: 2026-09-28
File: text_codec_faults.c
Description: Injects Lua and Windows buffer allocation failures into the production text converter and checks errors, cleanup and recovery.
*/

#include <errno.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "lua.h"
#include "lauxlib.h"
#if defined(_WIN32)
#include <windows.h>
#else
#include <iconv.h>
#endif

/* @struct fault_allocator Tracks allocation attempts made inside one protected conversion.
 * @field calls size_t Growing Lua allocations or native buffer requests observed since arming.
 * @field fail_at size_t First allocation attempt to reject, including emergency-GC retries.
 * @field armed int Nonzero only while the protected conversion is running.
 */
typedef struct fault_allocator {
  size_t calls;
  size_t fail_at;
  int armed;
} fault_allocator;

static size_t live_resources;
static size_t ownership_errors;
static size_t failures;
static void *resources[32];

/* Retains one native allocation or descriptor so failed old implementations can be cleaned between cases.
 * @param pointer void* Successfully acquired native resource, never NULL.
 * @return void No value; adds the resource to the observation set.
 * @effect Updates the observation set and live count.
 * @error Aborts the probe if a conversion exceeds the observation capacity.
 */
static void observe_acquire(void *pointer)
{
  size_t index;
  for (index = 0; index < 32U; ++index)
  {
    if (resources[index] == NULL)
    {
      resources[index] = pointer;
      ++live_resources;
      return;
    }
  }
  abort();
}

/* Removes a released resource and records attempts to free an unowned value.
 * @param pointer void* Native resource being released; NULL is a harmless no-op.
 * @return int One for an owned resource or NULL, zero for a duplicate/foreign release.
 * @effect Updates resource counts and the ownership error counter.
 */
static int observe_release(void *pointer)
{
  size_t index;
  if (pointer == NULL) return 1;
  for (index = 0; index < 32U; ++index)
  {
    if (resources[index] == pointer)
    {
      resources[index] = NULL;
      --live_resources;
      return 1;
    }
  }
  ++ownership_errors;
  return 0;
}

#if defined(_WIN32)
static fault_allocator native_allocator = { 0U, SIZE_MAX, 0 };

/* Records Windows conversion buffers and rejects requests at the armed native failure threshold.
 * @param size size_t Requested buffer bytes.
 * @return void* Allocated buffer, or NULL on injected/system allocation failure.
 * @effect Counts armed requests and sets errno to ENOMEM for injected failure.
 * @ownership Transfers allocation ownership to the converter; tracked_free observes its release.
 */
static void *tracked_malloc(size_t size)
{
  void *pointer;
  if (native_allocator.armed)
  {
    ++native_allocator.calls;
    if (native_allocator.calls >= native_allocator.fail_at)
    {
      errno = ENOMEM;
      return NULL;
    }
  }
  pointer = malloc(size);
  if (pointer != NULL) observe_acquire(pointer);
  return pointer;
}

/* Releases a Windows conversion buffer while detecting duplicate frees.
 * @param pointer void* Buffer acquired through tracked_malloc, or NULL.
 * @return void No value; releases the owned allocation.
 * @effect Updates ownership observations and frees an owned buffer.
 */
static void tracked_free(void *pointer)
{
  if (observe_release(pointer)) free(pointer);
}
#define malloc tracked_malloc
#define free tracked_free
#else
/* Records real iconv descriptors opened by the production POSIX converter.
 * @param destination const_char* Output charset accepted by iconv.
 * @param source const_char* Input charset accepted by iconv.
 * @return iconv_t Real descriptor, or the iconv failure sentinel.
 * @ownership Transfers a successful descriptor to the converter until tracked_iconv_close.
 */
static iconv_t tracked_iconv_open(const char *destination, const char *source)
{
  iconv_t converter = iconv_open(destination, source);
  if (converter != (iconv_t)-1) observe_acquire((void *)converter);
  return converter;
}

/* Closes an observed iconv descriptor and detects duplicate releases.
 * @param converter iconv_t Descriptor opened through tracked_iconv_open.
 * @return int Native close result, or -1 for an unowned descriptor.
 * @effect Updates observations and closes an owned descriptor.
 */
static int tracked_iconv_close(iconv_t converter)
{
  if (!observe_release((void *)converter)) return -1;
  return iconv_close(converter);
}
#define iconv_open tracked_iconv_open
#define iconv_close tracked_iconv_close
#endif

/* Supplies the same false/error-table convention expected by the included production header.
 * @param L lua_State* Protected conversion state receiving results.
 * @param code const_char* Stable failure code.
 * @param message const_char* Safe error description.
 * @return int Two Lua results: false and the structured error.
 * @effect Pushes the error results onto the stack.
 * @error Lua allocation failure unwinds to the probe's protected call.
 */
static int push_failure(lua_State *L, const char *code, const char *message)
{
  lua_pushboolean(L, 0);
  lua_createtable(L, 0, 2);
  lua_pushstring(L, code);
  lua_setfield(L, -2, "code");
  lua_pushstring(L, message);
  lua_setfield(L, -2, "message");
  return 2;
}

#include "../../native/yaca_text.h"

#if defined(_WIN32)
#undef malloc
#undef free
#else
#undef iconv_open
#undef iconv_close
#endif

/* Implements a Lua allocator that keeps rejecting growth after the selected failure point.
 * @param opaque void* The active fault_allocator record.
 * @param pointer void* Previous Lua allocation, or NULL for a fresh allocation.
 * @param previous size_t Previous allocation size; ignored when pointer is NULL.
 * @param requested size_t New allocation size; zero requests release.
 * @return void* Reallocated memory, or NULL on release or injected/system failure.
 * @effect Allocates/frees Lua memory and increments the armed allocation count.
 * A successful allocation deliberately changes errno, which callers of other native APIs must preserve themselves.
 */
static void *fault_allocate(void *opaque, void *pointer, size_t previous, size_t requested)
{
  fault_allocator *state = (fault_allocator *)opaque;
  void *allocated;
  if (requested == 0U) { free(pointer); return NULL; }
  if (state->armed && (pointer == NULL || requested > previous))
  {
    ++state->calls;
    if (state->calls >= state->fail_at) return NULL;
  }
  allocated = realloc(pointer, requested);
  if (allocated != NULL) errno = EINVAL;
  return allocated;
}

/* Checks one conversion under an allocation fault, its immediate cleanup and reuse of the same Lua state.
 * @param direction const_char* Either decode or encode.
 * @param input const_char* Input bytes, which may contain NULs.
 * @param length size_t Input byte count.
 * @param fail_at size_t Allocation failure threshold; SIZE_MAX observes an ordinary call.
 * @param missing int Nonzero requests an unavailable converter.
 * @return size_t Number of armed Lua allocation attempts.
 * @effect Creates/closes a Lua state, runs the production converter and reports failures to stderr.
 * @error Aborts if the probe cannot create its initial unarmed Lua state.
 */
static size_t check_conversion(
  const char *direction, const char *input, size_t length, size_t fail_at, int missing)
{
  fault_allocator allocator = { 0U, fail_at, 0 };
  lua_State *L = lua_newstate(fault_allocate, &allocator, 0U);
  int status;
  size_t calls;
  size_t index;
  if (L == NULL || !lua_checkstack(L, 32)) abort();
  l_text_facts(L);
  lua_pop(L, 1);
  lua_pushcfunction(L, l_text_convert);
  lua_pushstring(L, direction);
#if defined(_WIN32)
  lua_pushinteger(L, missing ? 65534 : 1252);
#else
  lua_pushstring(L, missing ? "YACA-MISSING-CHARSET" : "CP1252");
#endif
  lua_pushlstring(L, input, length);
  lua_pushboolean(L, 0);
  allocator.armed = 1;
  status = lua_pcall(L, 4, LUA_MULTRET, 0);
  allocator.armed = 0;
  calls = allocator.calls;
  if ((status != LUA_OK && status != LUA_ERRMEM) || live_resources != 0U)
  {
    fprintf(stderr, "conversion=%s fail_at=%zu status=%d live=%zu\n",
      direction, fail_at, status, live_resources);
    ++failures;
  }
  if (status == LUA_OK)
  {
    int accepted = lua_toboolean(L, 1);
    if (accepted == missing)
    {
      fprintf(stderr, "conversion=%s missing=%d length=%zu accepted=%d\n",
        direction, missing, length, accepted);
      ++failures;
    }
    if (missing && !accepted)
    {
      if (!lua_istable(L, 2)) ++failures;
      else
      {
        const char *code;
        lua_getfield(L, 2, "code");
        code = lua_tostring(L, -1);
        if (code == NULL || strcmp(code, "EncodingUnavailable") != 0) ++failures;
        lua_pop(L, 1);
      }
    }
    if (!missing && accepted)
    {
      size_t output_length;
      const unsigned char *output = (const unsigned char *)lua_tolstring(L, 2, &output_length);
      int decode = strcmp(direction, "decode") == 0;
      size_t expected = decode ? length * 2U : length / 2U;
      if (output == NULL || output_length != expected || !lua_toboolean(L, 3)) ++failures;
      else for (index = 0; index < output_length; ++index)
      {
        unsigned char wanted = decode ? (index % 2U == 0U ? 0xC3U : 0xA9U) : 0xE9U;
        if (output[index] != wanted) { ++failures; break; }
      }
    }
  }
  if (status == LUA_ERRMEM)
  {
    size_t recovered_length;
    const char *recovered;
    lua_settop(L, 0);
    lua_pushcfunction(L, l_text_convert);
    lua_pushliteral(L, "decode");
#if defined(_WIN32)
    lua_pushinteger(L, 1252);
#else
    lua_pushliteral(L, "CP1252");
#endif
    lua_pushliteral(L, "\xE9");
    lua_pushboolean(L, 0);
    status = lua_pcall(L, 4, LUA_MULTRET, 0);
    recovered = lua_tolstring(L, 2, &recovered_length);
    if (status != LUA_OK || !lua_toboolean(L, 1) || recovered == NULL
        || recovered_length != 2U || memcmp(recovered, "\xC3\xA9", 2U) != 0
        || !lua_toboolean(L, 3) || live_resources != 0U)
    {
      fprintf(stderr, "recovery=%s fail_at=%zu failed\n", direction, fail_at);
      ++failures;
    }
  }
  lua_close(L);
  /* Preserve failed observations above, then clean leaks from the old code so each case starts independently. */
  for (index = 0; index < 32U; ++index)
  {
    if (resources[index] != NULL)
    {
#if defined(_WIN32)
      tracked_free(resources[index]);
#else
      tracked_iconv_close((iconv_t)resources[index]);
#endif
    }
  }
  return calls;
}

#if defined(_WIN32)
/* Verifies native allocation error classification, immediate cleanup and reuse after removing the fault.
 * @param direction const_char* Either decode or encode; both use representable CP1252 text.
 * @param lossy int Whether decode may replace invalid bytes; allocation failure must still reject the call.
 * @param fail_at size_t Native malloc failure threshold; SIZE_MAX observes the ordinary call.
 * @return size_t Number of native allocation attempts while the fault was armed.
 * @effect Creates/closes one Lua state, arms the native allocator and reports failures to stderr.
 * @error Aborts if initial unarmed Lua memory cannot be allocated.
 */
static size_t check_native_allocation(const char *direction, int lossy, size_t fail_at)
{
  lua_State *L = luaL_newstate();
  int status;
  int decode = strcmp(direction, "decode") == 0;
  size_t calls;
  size_t index;
  const char *code = NULL;
  if (L == NULL || !lua_checkstack(L, 32)) abort();
  lua_pushcfunction(L, l_text_convert);
  lua_pushstring(L, direction);
  lua_pushinteger(L, 1252);
  lua_pushstring(L, decode ? "\xE9" : "\xC3\xA9");
  lua_pushboolean(L, lossy);
  native_allocator.calls = 0U;
  native_allocator.fail_at = fail_at;
  native_allocator.armed = 1;
  status = lua_pcall(L, 4, LUA_MULTRET, 0);
  native_allocator.armed = 0;
  calls = native_allocator.calls;
  if (calls >= fail_at)
  {
    int results = lua_gettop(L);
    if (lua_istable(L, 2))
    {
      lua_getfield(L, 2, "code");
      code = lua_tostring(L, -1);
    }
    if (status != LUA_OK || results != 2 || lua_toboolean(L, 1)
        || code == NULL || strcmp(code, "OutOfMemory") != 0 || live_resources != 0U)
    {
      fprintf(stderr, "native=%s lossy=%d fail_at=%zu status=%d results=%d code=%s live=%zu\n",
        direction, lossy, fail_at, status, results, code == NULL ? "missing" : code, live_resources);
      ++failures;
    }
  }
  else if (status != LUA_OK || lua_gettop(L) != 3 || !lua_toboolean(L, 1)
      || !lua_toboolean(L, 3) || live_resources != 0U)
  {
    ++failures;
  }
  lua_settop(L, 0);
  lua_pushcfunction(L, l_text_convert);
  lua_pushliteral(L, "decode");
  lua_pushinteger(L, 1252);
  lua_pushliteral(L, "\xE9");
  lua_pushboolean(L, 0);
  status = lua_pcall(L, 4, LUA_MULTRET, 0);
  if (status != LUA_OK || lua_gettop(L) != 3 || !lua_toboolean(L, 1)
      || !lua_isstring(L, 2) || strcmp(lua_tostring(L, 2), "\xC3\xA9") != 0
      || !lua_toboolean(L, 3) || live_resources != 0U)
  {
    fprintf(stderr, "native-recovery=%s lossy=%d fail_at=%zu failed\n", direction, lossy, fail_at);
    ++failures;
  }
  lua_close(L);
  for (index = 0U; index < 32U; ++index)
    if (resources[index] != NULL) tracked_free(resources[index]);
  return calls;
}

/* Checks that ordinary Windows encoding rejection returns exactly false and a typed error.
 * @param input const_char* NUL-terminated UTF-8 or deliberately invalid UTF-8 fixture.
 * @param expected const_char* Required error code for the fixture.
 * @return void No value; increments failures when status, arity, code or cleanup differs.
 * @effect Creates/closes a Lua state and invokes the production CP1252 encoder without injected failures.
 * @error Aborts if the initial Lua state or stack cannot be allocated.
 */
static void check_encoding_rejection(const char *input, const char *expected)
{
  lua_State *L = luaL_newstate();
  int status;
  int results;
  const char *code = NULL;
  if (L == NULL || !lua_checkstack(L, 32)) abort();
  lua_pushcfunction(L, l_text_convert);
  lua_pushliteral(L, "encode");
  lua_pushinteger(L, 1252);
  lua_pushstring(L, input);
  lua_pushboolean(L, 0);
  status = lua_pcall(L, 4, LUA_MULTRET, 0);
  results = lua_gettop(L);
  if (lua_istable(L, 2))
  {
    lua_getfield(L, 2, "code");
    code = lua_tostring(L, -1);
  }
  if (status != LUA_OK || results != 2 || lua_toboolean(L, 1)
      || code == NULL || strcmp(code, expected) != 0 || live_resources != 0U)
  {
    fprintf(stderr, "encoding-rejection expected=%s results=%d code=%s live=%zu\n",
      expected, results, code == NULL ? "missing" : code, live_resources);
    ++failures;
  }
  lua_close(L);
}
#endif

/* Runs ordinary, unavailable-empty-input and every observed Lua/native allocation-failure position.
 * @param none No command-line arguments are consumed.
 * @return int Zero only when conversion, error classification, result arity, resource cleanup and recovery checks all pass.
 * @effect Prints proof counters and failure details; allocates only temporary probe states and buffers.
 * @error Aborts if an initial unarmed Lua state or observation capacity cannot be provided.
 */
int main(void)
{
  char legacy[8192];
  char unicode[16384];
  size_t index;
  size_t decode_calls;
  size_t encode_calls;
  memset(legacy, 0xE9, sizeof(legacy));
  for (index = 0; index < sizeof(unicode); index += 2U)
  {
    unicode[index] = (char)0xC3;
    unicode[index + 1U] = (char)0xA9;
  }
  decode_calls = check_conversion("decode", legacy, sizeof(legacy), SIZE_MAX, 0);
  encode_calls = check_conversion("encode", unicode, sizeof(unicode), SIZE_MAX, 0);
  for (index = 1U; index <= decode_calls + 1U; ++index)
    check_conversion("decode", legacy, sizeof(legacy), index, 0);
  for (index = 1U; index <= encode_calls + 1U; ++index)
    check_conversion("encode", unicode, sizeof(unicode), index, 0);
  check_conversion("decode", "", 0U, SIZE_MAX, 1);
  check_conversion("encode", "", 0U, SIZE_MAX, 1);
  check_conversion("decode", "", 0U, SIZE_MAX, 0);
  check_conversion("encode", "", 0U, SIZE_MAX, 0);
#if defined(_WIN32)
  {
    size_t native_decode = check_native_allocation("decode", 0, SIZE_MAX);
    size_t native_lossy = check_native_allocation("decode", 1, SIZE_MAX);
    size_t native_encode = check_native_allocation("encode", 0, SIZE_MAX);
    for (index = 1U; index <= native_decode + 1U; ++index)
      check_native_allocation("decode", 0, index);
    for (index = 1U; index <= native_lossy + 1U; ++index)
      check_native_allocation("decode", 1, index);
    for (index = 1U; index <= native_encode + 1U; ++index)
      check_native_allocation("encode", 0, index);
    printf("native-allocation-sites decode=%zu lossy=%zu encode=%zu\n",
      native_decode, native_lossy, native_encode);
    check_encoding_rejection("\xFF", "InvalidEncoding");
    check_encoding_rejection("\xE4\xB8\xAD", "EncodingLossy");
  }
#endif
  printf("text-codec-faults decode_sites=%zu encode_sites=%zu failures=%zu ownership_errors=%zu\n",
    decode_calls, encode_calls, failures, ownership_errors);
  return failures == 0U && ownership_errors == 0U ? 0 : 1;
}
