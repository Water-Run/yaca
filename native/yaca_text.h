/*
Author: WaterRun
Date: 2026-09-28
File: yaca_text.h
Description: Legacy text code page facts and strict or lossy conversion between UTF-8 and native code pages.
*/

#ifndef YACA_TEXT_H
#define YACA_TEXT_H

/* Included once by yaca_native.c after push_failure is defined.
** Windows converts through MultiByteToWideChar/WideCharToMultiByte, which are
** available on XP. POSIX converts through the C library iconv and its system
** conversion modules. Both directions verify an exact round trip before a
** conversion is reported as lossless. */

#define YACA_TEXT_MAXIMUM_BYTES ((size_t)64U * 1024U * 1024U)

#if !defined(_WIN32)
#include <iconv.h>
#endif

/* Validate Unicode-scalar UTF-8 without relying on older Windows conversion permissiveness.
 * @param bytes const_char* Exact input bytes, including any embedded NUL.
 * @param length size_t Input byte count.
 * @return int One for strict UTF-8, zero for truncation, overlong forms, surrogates or out-of-range scalars.
 */
static int text_valid_utf8(const char *bytes, size_t length)
{
  size_t position = 0U;
  while (position < length)
  {
    unsigned char first = (unsigned char)bytes[position];
    size_t width;
    size_t index;
    unsigned char second_minimum = 0x80U;
    unsigned char second_maximum = 0xBFU;
    if (first < 0x80U) { ++position; continue; }
    if (first >= 0xC2U && first <= 0xDFU) width = 2U;
    else if (first >= 0xE0U && first <= 0xEFU)
    {
      width = 3U;
      if (first == 0xE0U) second_minimum = 0xA0U;
      if (first == 0xEDU) second_maximum = 0x9FU;
    }
    else if (first >= 0xF0U && first <= 0xF4U)
    {
      width = 4U;
      if (first == 0xF0U) second_minimum = 0x90U;
      if (first == 0xF4U) second_maximum = 0x8FU;
    }
    else return 0;
    if (length - position < width) return 0;
    for (index = 1U; index < width; ++index)
    {
      unsigned char byte = (unsigned char)bytes[position + index];
      unsigned char minimum = index == 1U ? second_minimum : 0x80U;
      unsigned char maximum = index == 1U ? second_maximum : 0xBFU;
      if (byte < minimum || byte > maximum) return 0;
    }
    position += width;
  }
  return 1;
}

/* @struct text_resources Owns native conversion resources across one protected Lua call.
 * @field wide void* Windows UTF-16 allocation, or NULL when not acquired.
 * @field bytes void* Windows encoded/output allocation, or NULL when not acquired.
 * @field allocation_failed int Windows buffer allocation failure recorded until the outer result is returned.
 * @field converter iconv_t POSIX conversion descriptor, or (iconv_t)-1 when closed.
 * @ownership Lives in the outer C frame; cleanup runs directly after lua_pcall, including allocation failures.
 */
typedef struct text_resources {
#if defined(_WIN32)
  void *wide;
  void *bytes;
  int allocation_failed;
#else
  iconv_t converter;
#endif
} text_resources;

/* Releases native resources without invoking Lua, allocating or raising a cleanup error.
 * @param owned text_resources* Owner in the outer protected-call frame.
 * @return void No value; already-released fields remain empty.
 * @effect Frees owned Windows buffers or closes the POSIX descriptor and clears each ownership field.
 */
static void text_release_resources(text_resources *owned)
{
#if defined(_WIN32)
  free(owned->wide);
  free(owned->bytes);
  owned->wide = NULL;
  owned->bytes = NULL;
#else
  if (owned->converter != (iconv_t)-1)
  {
    iconv_close(owned->converter);
    owned->converter = (iconv_t)-1;
  }
#endif
}

#if defined(_WIN32)

/* Allocates a Windows conversion buffer while preserving allocation failure separately from encoding errors.
 * @param owned text_resources* Outer owner retaining the allocation failure flag.
 * @param size size_t Positive allocation size already bounded by the input and conversion API.
 * @return void* New allocation, or NULL after any allocation failure in this call.
 * @effect Sets allocation_failed when malloc fails; subsequent requests fail without retrying.
 * @ownership The caller records the returned buffer in an owner slot or frees it before calling Lua.
 */
static void *text_allocate(text_resources *owned, size_t size)
{
  void *buffer;
  if (owned->allocation_failed) return NULL;
  buffer = malloc(size);
  if (buffer == NULL) owned->allocation_failed = 1;
  return buffer;
}

/* Decodes code page bytes into an allocated UTF-16 buffer.
 * @param owned text_resources* Outer owner retaining allocation failures separately from invalid input.
 * @param codepage UINT Windows code page identifier.
 * @param bytes const_char* Input bytes in the selected code page.
 * @param length size_t Number of input bytes; must be positive.
 * @param flags DWORD MultiByteToWideChar flags; GB18030 uses zero for XP compatibility and requires caller round-trip checks.
 * @param count int* Receives the number of UTF-16 units on success.
 * @return WCHAR*|NULL result New buffer that the caller frees, or NULL when conversion fails.
 * @effect May set owned->allocation_failed; no Lua API is called while the allocation is unowned.
 * @ownership Transfers a successful buffer to the caller, otherwise frees it before returning.
 */
static WCHAR *text_codepage_to_wide(
  text_resources *owned,
  UINT codepage,
  const char *bytes,
  size_t length,
  DWORD flags,
  int *count)
{
  int required;
  WCHAR *wide;

  *count = 0;
  if (codepage == 54936U) flags = 0;
  if (length > (size_t)INT_MAX)
  {
    return NULL;
  }
  required = MultiByteToWideChar(codepage, flags, bytes, (int)length, NULL, 0);
  if (required <= 0)
  {
    return NULL;
  }
  wide = (WCHAR *)text_allocate(owned, (size_t)required * sizeof(WCHAR));
  if (wide == NULL)
  {
    return NULL;
  }
  if (MultiByteToWideChar(codepage, flags, bytes, (int)length, wide, required) != required)
  {
    free(wide);
    return NULL;
  }
  *count = required;
  return wide;
}

/* Encodes UTF-16 units into an allocated code page byte buffer.
 * @param owned text_resources* Outer owner retaining allocation failures separately from unmappable input.
 * @param codepage UINT Windows code page identifier.
 * @param wide const_WCHAR* UTF-16 input units.
 * @param count int Number of input units; must be positive.
 * @param strict int Whether unmappable characters must be reported through used_default.
 * @param used_default BOOL* Receives whether the default character replaced input; may be NULL when strict is zero.
 * @param length int* Receives the number of output bytes on success.
 * @return char*|NULL result New buffer that the caller frees, or NULL when conversion fails.
 * @effect May set owned->allocation_failed; no Lua API is called while the allocation is unowned.
 * @ownership Transfers a successful buffer to the caller, otherwise frees it before returning.
 */
static char *text_wide_to_codepage(
  text_resources *owned,
  UINT codepage,
  const WCHAR *wide,
  int count,
  int strict,
  BOOL *used_default,
  int *length)
{
  int required;
  char *bytes;
  DWORD flags;

  *length = 0;
  flags = strict ? WC_NO_BEST_FIT_CHARS : 0;
  if (used_default != NULL)
  {
    *used_default = FALSE;
  }
  required = WideCharToMultiByte(codepage, flags, wide, count, NULL, 0, NULL, used_default);
  if (required <= 0)
  {
    return NULL;
  }
  bytes = (char *)text_allocate(owned, (size_t)required);
  if (bytes == NULL)
  {
    return NULL;
  }
  if (WideCharToMultiByte(codepage, flags, wide, count, bytes, required, NULL, used_default)
      != required)
  {
    free(bytes);
    return NULL;
  }
  *length = required;
  return bytes;
}

/* Pushes UTF-16 units as one UTF-8 Lua string without requiring a terminator.
 * @param L lua_State* Lua state receiving the string.
 * @param owned text_resources* Outer call's owner whose bytes slot receives the temporary UTF-8 buffer.
 * @param wide const_WCHAR* UTF-16 units to convert.
 * @param count int Number of units; zero pushes an empty string.
 * @return int success One when the string was pushed, zero when conversion failed.
 * @effect Pushes one string onto the Lua stack only on success; records native allocation failure in owned.
 * @error Lua allocation failure unwinds to the protected outer call, which retains every native buffer.
 * @ownership The outer call releases the UTF-8 allocation after protected execution ends.
 */
static int text_push_wide_utf8(lua_State *L, text_resources *owned, const WCHAR *wide, int count)
{
  int required;
  char *utf8;

  if (count == 0)
  {
    lua_pushliteral(L, "");
    return 1;
  }
  required = WideCharToMultiByte(CP_UTF8, 0, wide, count, NULL, 0, NULL, NULL);
  if (required <= 0)
  {
    return 0;
  }
  owned->bytes = utf8 = (char *)text_allocate(owned, (size_t)required);
  if (utf8 == NULL)
  {
    return 0;
  }
  if (WideCharToMultiByte(CP_UTF8, 0, wide, count, utf8, required, NULL, NULL) != required)
  {
    return 0;
  }
  if (!text_valid_utf8(utf8, (size_t)required)) return 0;
  lua_pushlstring(L, utf8, (size_t)required);
  return 1;
}

/* Implements text_facts for Windows: ANSI, OEM and attached console output code pages.
 * @param L lua_State* Lua state receiving the facts table.
 * @return int result One table with ansi, oem and console_output integer fields.
 * @effect Observes process/system code pages and pushes one Lua table.
 * @error Lua allocation failure propagates to the caller; this function owns no native resources.
 */
static int l_text_facts(lua_State *L)
{
  lua_createtable(L, 0, 4);
  lua_pushliteral(L, "windows-codepage");
  lua_setfield(L, -2, "kind");
  lua_pushinteger(L, (lua_Integer)GetACP());
  lua_setfield(L, -2, "ansi");
  lua_pushinteger(L, (lua_Integer)GetOEMCP());
  lua_setfield(L, -2, "oem");
  /* Zero means no console is attached to this process. */
  lua_pushinteger(L, (lua_Integer)GetConsoleOutputCP());
  lua_setfield(L, -2, "console_output");
  return 1;
}

/* Repairs invalid legacy byte sequences explicitly, including on XP where flag-zero decoding drops bytes.
 * @param L lua_State* Protected conversion state receiving the UTF-8 result.
 * @param codepage UINT Installed single-byte, double-byte or GB18030 code page.
 * @param bytes const_char* Raw input; embedded NUL is treated as an ordinary byte.
 * @param length size_t Positive input byte count within the public conversion bound.
 * @return int Three values (true, repaired UTF-8, false), or two values (false, typed error).
 * @effect Uses fixed native scratch arrays and a Lua-owned output buffer; replaces each undecodable byte with U+FFFD.
 * @error Lua buffer allocation failure unwinds through the outer protected call.
 * @ownership No native allocations escape this function; Lua owns its output buffer throughout.
 */
static int text_decode_lossy_windows(lua_State *L, UINT codepage, const char *bytes, size_t length)
{
  CPINFO info;
  WCHAR wide[128];
  char probe[128];
  char again[64];
  char utf8[64];
  luaL_Buffer output;
  size_t position = 0U;
  int ascii = 1;
  int index;
  DWORD flags = codepage == 54936U ? 0 : MB_ERR_INVALID_CHARS;

  if (!GetCPInfo(codepage, &info) || info.MaxCharSize == 0U || info.MaxCharSize > 4U)
    return push_failure(L, "EncodingUnavailable", "lossy decoding requires a supported stateless code page");
  for (index = 0; index < 128; ++index) probe[index] = (char)index;
  if (MultiByteToWideChar(codepage, flags, probe, 128, wide, 128) != 128)
    ascii = 0;
  else for (index = 0; index < 128; ++index)
    if (wide[index] != (WCHAR)index) { ascii = 0; break; }

  luaL_buffinit(L, &output);
  while (position < length)
  {
    size_t width;
    int accepted = 0;
    if (ascii && (unsigned char)bytes[position] < 0x80U)
    {
      size_t start = position;
      while (position < length && (unsigned char)bytes[position] < 0x80U) ++position;
      luaL_addlstring(&output, bytes + start, position - start);
      continue;
    }
    for (width = 1U; width <= info.MaxCharSize && width <= length - position; ++width)
    {
      int count = MultiByteToWideChar(codepage, flags,
        bytes + position, (int)width, wide, 128);
      int utf8_length;
      if (count == 0)
      {
        if (GetLastError() != ERROR_NO_UNICODE_TRANSLATION)
          return push_failure(L, "NativeFailure", "code page decoder failed during replacement");
        continue;
      }
      if (flags == 0)
      {
        int returned = WideCharToMultiByte(codepage, 0, wide, count, again, (int)sizeof(again), NULL, NULL);
        if (returned == 0)
          return push_failure(L, "NativeFailure", "GB18030 round-trip check failed during replacement");
        if ((size_t)returned != width || memcmp(again, bytes + position, width) != 0) continue;
      }
      utf8_length = WideCharToMultiByte(CP_UTF8, 0, wide, count, utf8, (int)sizeof(utf8), NULL, NULL);
      if (utf8_length == 0)
        return push_failure(L, "NativeFailure", "UTF-8 conversion failed during replacement");
      if (!text_valid_utf8(utf8, (size_t)utf8_length)) continue;
      luaL_addlstring(&output, utf8, (size_t)utf8_length);
      position += width;
      accepted = 1;
      break;
    }
    if (!accepted)
    {
      luaL_addlstring(&output, "\xEF\xBF\xBD", 3U);
      ++position;
    }
  }
  luaL_pushresult(&output);
  lua_pushboolean(L, 1);
  lua_insert(L, -2);
  lua_pushboolean(L, 0);
  return 3;
}

/* Decodes code page bytes to UTF-8, verifying an exact round trip unless lossy output is allowed.
 * @param L lua_State* Lua state receiving the result.
 * @param owned text_resources* Outer call's owner for wide and encoded buffers.
 * @param codepage UINT Validated Windows code page.
 * @param bytes const_char* Input bytes.
 * @param length size_t Positive input length.
 * @param lossy int Whether invalid sequences may be replaced instead of failing.
 * @return int result true, UTF-8 text and exact flag, or false and a typed error.
 * @effect Records native buffers in the outer owner's fields for cleanup after protected execution.
 * @error Lua allocation failure propagates through the protected caller after resource cleanup.
 */
static int text_decode_windows(
  lua_State *L,
  text_resources *owned,
  UINT codepage,
  const char *bytes,
  size_t length,
  int lossy)
{
  WCHAR *wide;
  char *again;
  int count;
  int again_length;
  int exact;

  owned->wide = wide = text_codepage_to_wide(owned, codepage, bytes, length, MB_ERR_INVALID_CHARS, &count);
  exact = wide != NULL;
  if (wide == NULL)
  {
    if (!lossy || owned->allocation_failed)
    {
      return push_failure(L, "InvalidEncoding", "bytes are not valid in the selected code page");
    }
    return text_decode_lossy_windows(L, codepage, bytes, length);
  }
  if (exact)
  {
    /* Some code pages accept undefined bytes silently. Only an exact
    ** re-encoding proves the decoded text represents the original bytes. */
    again = text_wide_to_codepage(owned, codepage, wide, count, 0, NULL, &again_length);
    exact = again != NULL
      && (size_t)again_length == length
      && memcmp(again, bytes, length) == 0;
    free(again);
    if (!exact && (!lossy || owned->allocation_failed))
    {
      return push_failure(L, "InvalidEncoding", "code page decoding does not round-trip");
    }
    if (!exact && codepage == 54936U)
    {
      text_release_resources(owned);
      return text_decode_lossy_windows(L, codepage, bytes, length);
    }
  }
  lua_pushboolean(L, 1);
  if (!text_push_wide_utf8(L, owned, wide, count))
  {
    lua_pop(L, 1);
    if (lossy && !owned->allocation_failed)
    {
      text_release_resources(owned);
      return text_decode_lossy_windows(L, codepage, bytes, length);
    }
    return push_failure(L, "InvalidEncoding", "decoded text cannot be represented as UTF-8");
  }
  lua_pushboolean(L, exact);
  return 3;
}

/* Encodes UTF-8 text into a code page only when every character maps and round-trips exactly.
 * @param L lua_State* Lua state receiving the result.
 * @param owned text_resources* Outer call's owner for wide and encoded buffers.
 * @param codepage UINT Validated Windows code page.
 * @param bytes const_char* Strict UTF-8 input.
 * @param length size_t Positive input length.
 * @return int result Three results (true, encoded bytes, true), or two results (false, typed error).
 * @effect Records native buffers in the outer owner's fields for cleanup after protected execution.
 * @error Lua allocation failure propagates through the protected caller after resource cleanup.
 */
static int text_encode_windows(lua_State *L, text_resources *owned, UINT codepage, const char *bytes, size_t length)
{
  WCHAR *wide;
  WCHAR *again;
  char *encoded;
  int count;
  int encoded_length;
  int again_count;
  BOOL used_default;
  int exact;

  owned->wide = wide = text_codepage_to_wide(owned, CP_UTF8, bytes, length, MB_ERR_INVALID_CHARS, &count);
  if (wide == NULL)
  {
    return push_failure(L, "InvalidEncoding", "text is not strict UTF-8");
  }
  if (codepage == 54936U)
  {
    /* GB18030 rejects WC_NO_BEST_FIT_CHARS and the default-character probe;
    ** it maps all Unicode scalars, and the round trip below stays mandatory. */
    used_default = FALSE;
    owned->bytes = encoded = text_wide_to_codepage(owned, codepage, wide, count, 0, NULL, &encoded_length);
  }
  else
  {
    owned->bytes = encoded = text_wide_to_codepage(owned, codepage, wide, count, 1, &used_default, &encoded_length);
  }
  if (encoded == NULL || used_default)
  {
    return push_failure(L, "EncodingLossy", "text contains characters the code page cannot represent");
  }
  again = text_codepage_to_wide(
    owned,
    codepage,
    encoded,
    (size_t)encoded_length,
    MB_ERR_INVALID_CHARS,
    &again_count);
  exact = again != NULL
    && again_count == count
    && memcmp(again, wide, (size_t)count * sizeof(WCHAR)) == 0;
  free(again);
  if (!exact)
  {
    return push_failure(L, "EncodingLossy", "code page encoding does not round-trip");
  }
  lua_pushboolean(L, 1);
  lua_pushlstring(L, encoded, (size_t)encoded_length);
  lua_pushboolean(L, 1);
  return 3;
}

#else

/* Implements text_facts for POSIX; the locale charset is derived from the environment by Lua.
 * @param L lua_State* Lua state receiving the facts table.
 * @return int result One table whose kind is iconv.
 * @effect Pushes one Lua table describing the conversion backend.
 * @error Lua allocation failure propagates to the caller; this function owns no native resources.
 */
static int l_text_facts(lua_State *L)
{
  lua_createtable(L, 0, 1);
  lua_pushliteral(L, "iconv");
  lua_setfield(L, -2, "kind");
  return 1;
}

/* Converts a byte buffer through iconv into a growing Lua buffer.
 * @param L lua_State* Lua state owning the buffer.
 * @param converter iconv_t Open conversion descriptor.
 * @param bytes const_char* Input bytes.
 * @param length size_t Input length.
 * @param lossy int Whether invalid input bytes are replaced by U+FFFD and skipped.
 * @param buffer luaL_Buffer* Initialized buffer receiving converted bytes.
 * @param replaced size_t* Receives the number of replaced input positions.
 * @param irreversible size_t* Receives the count of non-reversible conversions reported by iconv.
 * @return int status Zero on success, EILSEQ for invalid or unmappable input, or another errno value.
 * @effect Appends converted bytes to buffer and advances the converter shift state.
 * @error Lua allocation failure propagates; the outer protected call must retain ownership of converter.
 */
static int text_iconv_run(
  lua_State *L,
  iconv_t converter,
  const char *bytes,
  size_t length,
  int lossy,
  luaL_Buffer *buffer,
  size_t *replaced,
  size_t *irreversible)
{
  char *input;
  size_t input_left;
  char chunk[4096];

  (void)L;
  input = (char *)bytes;
  input_left = length;
  *replaced = 0U;
  *irreversible = 0U;
  while (input_left > 0U)
  {
    char *output = chunk;
    size_t output_left = sizeof(chunk);
    size_t result = iconv(converter, &input, &input_left, &output, &output_left);
    int conversion_error = result == (size_t)-1 ? errno : 0;

    luaL_addlstring(buffer, chunk, sizeof(chunk) - output_left);
    if (result != (size_t)-1)
    {
      *irreversible += result;
      continue;
    }
    if (conversion_error == E2BIG)
    {
      continue;
    }
    if ((conversion_error == EILSEQ || conversion_error == EINVAL) && lossy)
    {
      luaL_addlstring(buffer, "\xEF\xBF\xBD", 3U);
      ++input;
      --input_left;
      ++*replaced;
      /* Reset any shift state before continuing after the invalid byte. */
      iconv(converter, NULL, NULL, NULL, NULL);
      continue;
    }
    return conversion_error == EINVAL ? EILSEQ : conversion_error;
  }
  {
    char *output = chunk;
    size_t output_left = sizeof(chunk);
    if (iconv(converter, NULL, NULL, &output, &output_left) == (size_t)-1)
    {
      return errno;
    }
    luaL_addlstring(buffer, chunk, sizeof(chunk) - output_left);
  }
  return 0;
}

/* Converts with iconv between UTF-8 and a named charset, verifying exact round trips.
 * @param L lua_State* Lua state receiving the result.
 * @param owned text_resources* Outer call's owner for the currently open iconv descriptor.
 * @param decode int Nonzero converts charset bytes to UTF-8; zero converts UTF-8 to the charset.
 * @param charset const_char* iconv charset name.
 * @param bytes const_char* Input bytes.
 * @param length size_t Input byte count, including zero for an availability-checked empty conversion.
 * @param lossy int Whether decoding may replace invalid bytes.
 * @return int result true, output and exact flag, or false and a typed error.
 * @effect Records forward/reverse descriptors in the outer owner and closes each on ordinary completion.
 * @error Lua allocation failure propagates through the protected caller after descriptor cleanup.
 */
static int text_convert_iconv(
  lua_State *L,
  text_resources *owned,
  int decode,
  const char *charset,
  const char *bytes,
  size_t length,
  int lossy)
{
  iconv_t forward;
  iconv_t backward;
  luaL_Buffer buffer;
  size_t replaced;
  size_t irreversible;
  int status;
  int exact;
  size_t output_length;
  const char *output;

  owned->converter = forward = decode ? iconv_open("UTF-8", charset) : iconv_open(charset, "UTF-8");
  if (forward == (iconv_t)-1)
  {
    return push_failure(L, "EncodingUnavailable", "the system has no converter for this charset");
  }
  luaL_buffinit(L, &buffer);
  status = text_iconv_run(L, forward, bytes, length, decode && lossy, &buffer, &replaced, &irreversible);
  iconv_close(forward);
  owned->converter = (iconv_t)-1;
  if (status != 0)
  {
    luaL_pushresult(&buffer);
    lua_pop(L, 1);
    if (decode)
    {
      return push_failure(L, "InvalidEncoding", "bytes are not valid in the selected charset");
    }
    return push_failure(L, "EncodingLossy", "text contains characters the charset cannot represent");
  }
  luaL_pushresult(&buffer);
  output = lua_tolstring(L, -1, &output_length);
  exact = replaced == 0U && irreversible == 0U;
  if (exact && output_length > 0U)
  {
    luaL_Buffer check;
    size_t check_replaced;
    size_t check_irreversible;
    size_t check_length;
    const char *check_bytes;

    owned->converter = backward = decode ? iconv_open(charset, "UTF-8") : iconv_open("UTF-8", charset);
    if (backward == (iconv_t)-1)
    {
      exact = 0;
    }
    else
    {
      luaL_buffinit(L, &check);
      status = text_iconv_run(L, backward, output, output_length, 0, &check, &check_replaced,
        &check_irreversible);
      iconv_close(backward);
      owned->converter = (iconv_t)-1;
      luaL_pushresult(&check);
      check_bytes = lua_tolstring(L, -1, &check_length);
      exact = status == 0
        && check_irreversible == 0U
        && check_length == length
        && memcmp(check_bytes, bytes, length) == 0;
      lua_pop(L, 1);
      output = lua_tolstring(L, -1, &output_length);
    }
  }
  if (!exact && !(decode && lossy))
  {
    lua_pop(L, 1);
    if (decode)
    {
      return push_failure(L, "InvalidEncoding", "charset decoding does not round-trip");
    }
    return push_failure(L, "EncodingLossy", "charset encoding does not round-trip");
  }
  lua_pushboolean(L, 1);
  lua_insert(L, -2);
  lua_pushboolean(L, exact);
  (void)output;
  return 3;
}

#endif

/* Performs text_convert(direction, target, bytes, lossy) inside an outer protected call.
 * Windows targets are integer code pages; POSIX targets are iconv charset names.
 * @param L lua_State* Lua state receiving arguments/results and the outer owner pointer in upvalue 1.
 * @return int result true, converted bytes and exact flag, or false and a typed error.
 * @effect Acquires conversion resources in the outer owner's fields and pushes the native result.
 * @error Argument/allocation failures unwind to l_text_convert, which owns all native cleanup.
 */
static int text_convert_protected(lua_State *L)
{
  text_resources *owned = (text_resources *)lua_touserdata(L, lua_upvalueindex(1));
  const char *direction;
  const char *bytes;
  size_t length;
  int decode;
  int lossy;

  direction = luaL_checkstring(L, 1);
  bytes = luaL_checklstring(L, 3, &length);
  lossy = lua_toboolean(L, 4);
  if (strcmp(direction, "decode") == 0)
  {
    decode = 1;
  }
  else if (strcmp(direction, "encode") == 0)
  {
    decode = 0;
    lossy = 0;
  }
  else
  {
    return push_failure(L, "InvalidArgument", "text conversion direction is invalid");
  }
  if (length > YACA_TEXT_MAXIMUM_BYTES)
  {
    return push_failure(L, "TextTooLarge", "text conversion input exceeds its bound");
  }
  if (!decode && !text_valid_utf8(bytes, length))
    return push_failure(L, "InvalidEncoding", "text is not strict Unicode-scalar UTF-8");
#if defined(_WIN32)
  {
    lua_Integer codepage = luaL_checkinteger(L, 2);
    if (codepage <= 0 || codepage > 65535 || codepage == CP_UTF8 || codepage == CP_UTF7
        || !IsValidCodePage((UINT)codepage))
    {
      return push_failure(L, "EncodingUnavailable", "the code page is not installed");
    }
    if (length == 0U)
    {
      lua_pushboolean(L, 1);
      lua_pushliteral(L, "");
      lua_pushboolean(L, 1);
      return 3;
    }
    if (decode)
    {
      return text_decode_windows(L, owned, (UINT)codepage, bytes, length, lossy);
    }
    return text_encode_windows(L, owned, (UINT)codepage, bytes, length);
  }
#else
  {
    const char *charset = luaL_checkstring(L, 2);
    if (charset[0] == '\0' || strlen(charset) > 64U)
    {
      return push_failure(L, "EncodingUnavailable", "the charset name is invalid");
    }
    return text_convert_iconv(L, owned, decode, charset, bytes, length, lossy);
  }
#endif
}

/* Runs conversion behind a Lua error barrier and releases resources without relying on a Lua cleanup callback.
 * @param L lua_State* State receiving the public direction, target, bytes and optional lossy arguments.
 * @return int Number of conversion results, preserving true/output/exact or false/error; native allocation failure is OutOfMemory.
 * @effect Executes one protected conversion and unconditionally releases its native allocations/descriptors.
 * @error Re-raises the original Lua argument or memory error only after native cleanup has completed.
 * @ownership The stack-local owner remains alive across lua_pcall; the protected function cannot yield.
 */
static int l_text_convert(lua_State *L)
{
  text_resources owned;
  int arguments = lua_gettop(L);
  int status;
#if defined(_WIN32)
  owned.wide = NULL;
  owned.bytes = NULL;
  owned.allocation_failed = 0;
#else
  owned.converter = (iconv_t)-1;
#endif
  lua_pushlightuserdata(L, &owned);
  lua_pushcclosure(L, text_convert_protected, 1);
  lua_insert(L, 1);
  status = lua_pcall(L, arguments, LUA_MULTRET, 0);
  text_release_resources(&owned);
  if (status != LUA_OK) return lua_error(L);
#if defined(_WIN32)
  if (owned.allocation_failed)
  {
    lua_settop(L, 0);
    return push_failure(L, "OutOfMemory", "text conversion buffer allocation failed");
  }
#endif
  return lua_gettop(L);
}

#endif
