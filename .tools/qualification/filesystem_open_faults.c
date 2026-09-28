/*
Author: WaterRun
Date: 2026-09-28
File: filesystem_open_faults.c
Description: Injects Lua allocation failures into production fs open/create ports and verifies OS handle ownership through full collection plus same-state recovery.
*/

#if !defined(_WIN32) && !defined(_POSIX_C_SOURCE)
#define _POSIX_C_SOURCE 200809L
#endif
#if !defined(_WIN32) && !defined(_XOPEN_SOURCE)
#define _XOPEN_SOURCE 700
#endif
#if !defined(_WIN32) && !defined(_GNU_SOURCE)
#define _GNU_SOURCE
#endif
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#if defined(_WIN32)
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0501
#endif
/* An empty DECLSPEC_IMPORT lets this probe define local wrappers around
** imported Windows file APIs so handle ownership stays observable on Wine,
** where GetProcessHandleCount is an unimplemented stub. */
#define DECLSPEC_IMPORT
#include <windows.h>
#else
#include <dirent.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#endif
#include "lua.h"
#include "lauxlib.h"
#if defined(_WIN32)
/* Calls through to the real Windows file-creation import for this audit wrapper.
 * @param file_name LPCWSTR Path passed through to the operating system.
 * @param desired_access DWORD Requested access rights passed through unchanged.
 * @param share_mode DWORD Requested sharing rights passed through unchanged.
 * @param security LPSECURITY_ATTRIBUTES Optional security attributes passed through.
 * @param creation DWORD Creation disposition passed through unchanged.
 * @param flags DWORD Flags and attributes passed through unchanged.
 * @param template_file HANDLE Optional template handle passed through unchanged.
 * @return HANDLE result Real operating-system handle for the requested file.
 */
static HANDLE (WINAPI *const probe_real_create_file)(
  LPCWSTR file_name,
  DWORD desired_access,
  DWORD share_mode,
  LPSECURITY_ATTRIBUTES security,
  DWORD creation,
  DWORD flags,
  HANDLE template_file) = CreateFileW;
/* Calls through to the real Windows handle-close import for this audit wrapper.
 * @param object HANDLE Operating-system handle being closed.
 * @return BOOL result Real operating-system close outcome for the handle.
 */
static BOOL (WINAPI *const probe_real_close_handle)(HANDLE object) = CloseHandle;
static HANDLE probe_open_handles[64];
static size_t probe_open_handle_count;
static int observing;

/* Records one successfully opened file handle for the leak audit.
 * @param file_name LPCWSTR Path passed through to the operating system.
 * @param desired_access DWORD Requested access rights passed through unchanged.
 * @param share_mode DWORD Requested sharing rights passed through unchanged.
 * @param security LPSECURITY_ATTRIBUTES Optional security attributes passed through.
 * @param creation DWORD Creation disposition passed through unchanged.
 * @param flags DWORD Flags and attributes passed through unchanged.
 * @param template_file HANDLE Optional template handle passed through unchanged.
 * @return HANDLE result Operating-system handle, or INVALID_HANDLE_VALUE on failure.
 * @effect While armed, records valid handles so later closes can be matched.
 */
static HANDLE WINAPI probe_tracked_create_file(
  LPCWSTR file_name,
  DWORD desired_access,
  DWORD share_mode,
  LPSECURITY_ATTRIBUTES security,
  DWORD creation,
  DWORD flags,
  HANDLE template_file)
{
  HANDLE handle = probe_real_create_file(
    file_name, desired_access, share_mode, security, creation, flags, template_file);

  if (observing && handle != INVALID_HANDLE_VALUE)
  {
    if (probe_open_handle_count >= sizeof(probe_open_handles) / sizeof(probe_open_handles[0]))
    {
      abort();
    }
    probe_open_handles[probe_open_handle_count++] = handle;
  }
  return handle;
}

/* Closes one handle and clears its audit record when present.
 * @param object HANDLE Operating-system handle being closed.
 * @return BOOL result Operating-system close outcome passed through unchanged.
 * @effect Removes the handle from the audit whenever it was recorded.
 */
static BOOL WINAPI probe_tracked_close_handle(HANDLE object)
{
  size_t index;

  for (index = 0U; index < probe_open_handle_count; ++index)
  {
    if (probe_open_handles[index] == object)
    {
      probe_open_handles[index] = probe_open_handles[--probe_open_handle_count];
      break;
    }
  }
  return probe_real_close_handle(object);
}

#define CreateFileW probe_tracked_create_file
#define CloseHandle probe_tracked_close_handle
#endif
#include "../../native/yaca_native.c"
#if defined(_WIN32)
#undef CreateFileW
#undef CloseHandle
#endif

/* Largest descriptor or fixture-path buffer this probe tracks in one call. */
#define PROBE_MAX_DESCRIPTORS 512
/* Fixed fixture payload used for usability reads after every armed call. */
#define PROBE_FIXTURE_BYTES 16
/* Shared capacity for native fixture paths on both platform families. */
#define PROBE_PATH_CAPACITY 4096

static unsigned long fixture_serial;

/* Fixed fixture payload used for usability reads after every armed call. */
static const char fixture_payload[PROBE_FIXTURE_BYTES] = "open-faults-16";

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

#if defined(_WIN32)

#else

/* Counts open descriptors through the proc descriptor directory.
 * @param descriptors int* Array receiving every open descriptor number.
 * @param capacity int Maximum descriptor numbers the array can hold.
 * @return int result Number of open descriptors recorded in the array.
 * @error Aborts when the descriptor directory cannot be read or overflows the array.
 */
static int probe_collect_descriptors(int *descriptors, int capacity)
{
  DIR *directory;
  struct dirent *entry;
  int count = 0;
  int self;

  directory = opendir("/proc/self/fd");
  if (directory == NULL)
  {
    abort();
  }
  self = dirfd(directory);
  while ((entry = readdir(directory)) != NULL)
  {
    char *end = NULL;
    long value;

    if (entry->d_name[0] == '.')
    {
      continue;
    }
    value = strtol(entry->d_name, &end, 10);
    if (end == NULL || *end != '\0' || value < 0 || (int)value == self)
    {
      continue;
    }
    if (count >= capacity)
    {
      closedir(directory);
      abort();
    }
    descriptors[count++] = (int)value;
  }
  closedir(directory);
  return count;
}

/* Reports whether one descriptor number appears in the earlier snapshot.
 * @param descriptors const_int* Earlier descriptor snapshot being searched.
 * @param count int Number of descriptor numbers in the snapshot.
 * @param value int Descriptor number being located.
 * @return int result 1 when the descriptor existed before; 0 when it is new.
 */
static int probe_descriptor_known(const int *descriptors, int count, int value)
{
  int index;

  for (index = 0; index < count; ++index)
  {
    if (descriptors[index] == value)
    {
      return 1;
    }
  }
  return 0;
}

/* Closes descriptors opened during the armed call so later iterations stay clean.
 * @param before const_int* Descriptor snapshot taken before the armed call.
 * @param before_count int Number of descriptors in the earlier snapshot.
 * @param after const_int* Descriptor snapshot taken after collection.
 * @param after_count int Number of descriptors in the later snapshot.
 * @return int result Number of newly observed descriptors this probe closed.
 * @effect Confirmed leaked descriptors are closed; owned descriptors are left untouched.
 */
static int probe_close_new_descriptors(
  const int *before,
  int before_count,
  const int *after,
  int after_count)
{
  int closed = 0;
  int index;

  for (index = 0; index < after_count; ++index)
  {
    if (!probe_descriptor_known(before, before_count, after[index]))
    {
      close(after[index]);
      ++closed;
    }
  }
  return closed;
}
#endif

/* Builds the next unique fixture path for one armed iteration.
 * @param buffer char* Storage for the completed native path.
 * @param capacity size_t Byte capacity of the path buffer.
 * @return void result Writes one absolute not-yet-existing target path.
 * @effect Advances the fixture serial so create ports never observe a stale target.
 */
static void probe_next_target(char *buffer, size_t capacity)
{
  ++fixture_serial;
#if defined(_WIN32)
  {
    char directory[MAX_PATH];
    char name[MAX_PATH];

    if (GetTempPathA((DWORD)sizeof(directory), directory) == 0
        || GetTempFileNameA(directory, "yof", 0U, name) == 0)
    {
      abort();
    }
    if (strlen(name) + 1U > capacity)
    {
      abort();
    }
    strcpy(buffer, name);
    /* GetTempFileNameA reserves the name by creating an empty file; the caller prepares state. */
    if (!DeleteFileA(name))
    {
      abort();
    }
  }
#else
  {
    int written = snprintf(
      buffer,
      capacity,
      "/tmp/yaca-open-faults-%lu-%lu.tmp",
      (unsigned long)getpid(),
      fixture_serial);

    if (written <= 0 || (size_t)written >= capacity)
    {
      abort();
    }
    unlink(buffer);
  }
#endif
}

/* Writes the fixed fixture payload so read ports observe a stable regular file.
 * @param path const_char* Absolute fixture path to create or overwrite.
 * @return void result Leaves a PROBE_FIXTURE_BYTES-byte regular file on disk.
 * @error Aborts when the fixture cannot be written or closed.
 */
static void probe_write_fixture(const char *path)
{
#if defined(_WIN32)
  {
    WCHAR *wide = utf8_to_wide(path, strlen(path));
    HANDLE handle;
    DWORD written = 0UL;

    if (wide == NULL)
    {
      abort();
    }
    handle = CreateFileW(
      wide,
      GENERIC_WRITE,
      0U,
      NULL,
      CREATE_ALWAYS,
      FILE_ATTRIBUTE_NORMAL,
      NULL);
    free(wide);
    if (handle == INVALID_HANDLE_VALUE
        || !WriteFile(handle, fixture_payload, (DWORD)sizeof(fixture_payload), &written, NULL)
        || written != (DWORD)sizeof(fixture_payload)
        || !CloseHandle(handle))
    {
      abort();
    }
  }
#else
  {
    int descriptor = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    ssize_t written;

    if (descriptor < 0)
    {
      abort();
    }
    written = write(descriptor, fixture_payload, sizeof(fixture_payload));
    if (written != (ssize_t)sizeof(fixture_payload) || close(descriptor) != 0)
    {
      abort();
    }
  }
#endif
}

/* Removes one fixture path when present so create ports start from absence.
 * @param path const_char* Absolute fixture path to remove.
 * @return void result The path is absent once this helper returns.
 */
static void probe_remove_fixture(const char *path)
{
#if defined(_WIN32)
  {
    WCHAR *wide = utf8_to_wide(path, strlen(path));

    if (wide != NULL)
    {
      DeleteFileW(wide);
      free(wide);
    }
  }
#else
  unlink(path);
#endif
}

/* Pushes the production identity of one existing filesystem path.
 * @param L lua_State* Lua state receiving the identity table.
 * @param path const_char* Absolute existing path whose identity is captured.
 * @param directory int Nonzero to inspect a directory, zero for a regular file.
 * @return void result Pushes one identity table matching the production identity ports.
 * @error Aborts when the path cannot be opened or produces no stable identity.
 */
static void probe_push_identity(lua_State *L, const char *path, int directory)
{
  yaca_identity identity;

  memset(&identity, 0, sizeof(identity));
#if defined(_WIN32)
  {
    WCHAR *wide = utf8_to_wide(path, strlen(path));
    HANDLE handle;

    (void)directory;

    if (wide == NULL)
    {
      abort();
    }
    handle = CreateFileW(
      wide,
      GENERIC_READ,
      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
      NULL,
      OPEN_EXISTING,
      directory ? FILE_FLAG_BACKUP_SEMANTICS : FILE_ATTRIBUTE_NORMAL,
      NULL);
    free(wide);
    if (handle == INVALID_HANDLE_VALUE
        || !identity_from_handle(handle, &identity)
        || !CloseHandle(handle))
    {
      abort();
    }
  }
#else
  {
    struct stat information;

    (void)directory;
    if (stat(path, &information) != 0
        || !identity_from_stat(&information, &identity))
    {
      abort();
    }
  }
#endif
  push_identity(L, &identity);
}

/* Derives the parent directory path of one absolute fixture target.
 * @param target const_char* Absolute path whose parent directory is needed.
 * @param buffer char* Storage for the completed parent path.
 * @param capacity size_t Byte capacity of the parent path buffer.
 * @return void result Writes the absolute parent directory path.
 * @error Aborts when the target carries no separable parent component.
 */
static void probe_parent_directory(const char *target, char *buffer, size_t capacity)
{
  size_t length = strlen(target);
  size_t cut = 0U;
  size_t index;

  for (index = 0; index < length; ++index)
  {
#if defined(_WIN32)
    if (target[index] == '\\' || target[index] == '/')
#else
    if (target[index] == '/')
#endif
    {
      cut = index;
    }
  }
  if (cut == 0U || cut + 2U > capacity)
  {
    abort();
  }
  memcpy(buffer, target, cut);
  buffer[cut] = '\0';
#if defined(_WIN32)
  /* A drive-letter root parent must keep its trailing separator to stay absolute. */
  if (cut == 2U && buffer[1] == ':')
  {
    buffer[cut] = '\\';
    buffer[cut + 1U] = '\0';
  }
#endif
}

/* @enum probe_port Selects which production open or create port one iteration exercises.
 * @field PORT_OPEN_READ value for the plain fs_open_read port.
 * @field PORT_CREATE_NEW value for the plain fs_create_new port.
 * @field PORT_OPEN_READ_VERIFIED value for the identity-checked open port.
 * @field PORT_CREATE_NEW_VERIFIED value for the identity-checked create port.
 */
typedef enum probe_port {
  PORT_OPEN_READ,
  PORT_CREATE_NEW,
  PORT_OPEN_READ_VERIFIED,
  PORT_CREATE_NEW_VERIFIED
} probe_port;

/* Reports the registered port name used in evidence lines.
 * @param port probe_port Port selection for one iteration.
 * @return const_char* result Stable evidence name of the exercised port.
 */
static const char *probe_port_name(probe_port port)
{
  switch (port)
  {
    case PORT_OPEN_READ:
      return "fs_open_read";
    case PORT_CREATE_NEW:
      return "fs_create_new";
    case PORT_OPEN_READ_VERIFIED:
      return "fs_open_read_verified";
    default:
      return "fs_create_new_verified";
  }
}

/* Pushes the production port and its arguments for one armed call.
 * @param L lua_State* Lua state receiving the function and its arguments.
 * @param port probe_port Port selection for one iteration.
 * @param target const_char* Absolute fixture path bound to this iteration.
 * @return int result Number of arguments pushed after the port function.
 */
static int probe_push_port_call(lua_State *L, probe_port port, const char *target)
{
  switch (port)
  {
    case PORT_OPEN_READ:
      lua_pushcfunction(L, l_fs_open_read);
      lua_pushstring(L, target);
      return 1;
    case PORT_CREATE_NEW:
      lua_pushcfunction(L, l_fs_create_new);
      lua_pushstring(L, target);
      lua_pushinteger(L, 0600);
      return 2;
    case PORT_OPEN_READ_VERIFIED:
      lua_pushcfunction(L, l_fs_open_read_verified);
      lua_pushstring(L, target);
      probe_push_identity(L, target, 0);
      return 2;
    default:
    {
      char parent[PROBE_PATH_CAPACITY];

      lua_pushcfunction(L, l_fs_create_new_verified);
      lua_pushstring(L, target);
      probe_parent_directory(target, parent, sizeof(parent));
      probe_push_identity(L, parent, 1);
      lua_pushinteger(L, 0600);
      return 3;
    }
  }
}

/* Runs one armed iteration of a port and audits handle ownership around it.
 * @param port probe_port Port selection for one iteration.
 * @param fail_at size_t First Lua growth allocation to reject, or SIZE_MAX for the baseline.
 * @param leaks size_t* Incremented once for every escaping operating-system handle.
 * @return size_t Number of observed Lua growth requests during the protected call.
 * @effect Creates and closes one Lua state and one fixture; verifies full-collection ownership
 *   and a same-state recovery call including a real read on the recovered handle.
 * @error Aborts on structural failures such as unexpected error kinds or unusable recovery results.
 */
static size_t probe_check_port(probe_port port, size_t fail_at, size_t *leaks)
{
  allocation_fault fault = { 0U, fail_at, 0 };
  lua_State *L = lua_newstate(fault_allocate, &fault, 0U);
  char target[PROBE_PATH_CAPACITY];
  int arguments;
  int status;
  int reference = LUA_NOREF;
  int succeeded;
#if defined(_WIN32)
  size_t expected_leftover;
#else
  int before[PROBE_MAX_DESCRIPTORS];
  int after[PROBE_MAX_DESCRIPTORS];
  int before_count;
  int after_count;
#endif

  if (L == NULL)
  {
    abort();
  }
  create_handle_metatable(L, YACA_FILE_METATABLE, l_file_gc);
  probe_next_target(target, sizeof(target));
  if (port == PORT_OPEN_READ || port == PORT_OPEN_READ_VERIFIED)
  {
    probe_write_fixture(target);
  }
  else
  {
    probe_remove_fixture(target);
  }
#if !defined(_WIN32)
  before_count = probe_collect_descriptors(before, PROBE_MAX_DESCRIPTORS);
#endif
  arguments = probe_push_port_call(L, port, target);
  fault.armed = 1;
#if defined(_WIN32)
  observing = 1;
#endif
  status = lua_pcall(L, arguments, LUA_MULTRET, 0);
#if defined(_WIN32)
  observing = 0;
#endif
  fault.armed = 0;
  succeeded = status == LUA_OK;
  if (!succeeded && status != LUA_ERRMEM)
  {
    abort();
  }
  if (succeeded)
  {
    if (lua_gettop(L) != 2 || !lua_toboolean(L, 1)
        || lua_type(L, 2) != LUA_TUSERDATA)
    {
      abort();
    }
    lua_remove(L, 1);
    reference = luaL_ref(L, LUA_REGISTRYINDEX);
  }
  else
  {
    lua_settop(L, 0);
  }
  /* Unwound userdata is collectable; a full collection must close everything it owns. */
  lua_gc(L, LUA_GCCOLLECT);
  lua_gc(L, LUA_GCCOLLECT);
#if defined(_WIN32)
  expected_leftover = succeeded ? 1U : 0U;
  if (probe_open_handle_count > expected_leftover)
  {
    ++*leaks;
    printf(
      "handle-leak port=%s fail_at=%zu closed=%lu\n",
      probe_port_name(port),
      fail_at,
      (unsigned long)(probe_open_handle_count - expected_leftover));
    while (probe_open_handle_count > expected_leftover)
    {
      HANDLE escaped = probe_open_handles[--probe_open_handle_count];

      probe_real_close_handle(escaped);
    }
  }
#else
  after_count = probe_collect_descriptors(after, PROBE_MAX_DESCRIPTORS);
  if (after_count > before_count + (succeeded ? 1 : 0))
  {
    ++*leaks;
    printf(
      "descriptor-leak port=%s fail_at=%zu closed=%d\n",
      probe_port_name(port),
      fail_at,
      probe_close_new_descriptors(before, before_count, after, after_count));
  }
#endif
  /* Release the armed owner before removing a create target: on Windows the
  ** created file cannot be deleted while its handle stays open. */
  if (reference != LUA_NOREF)
  {
    luaL_unref(L, LUA_REGISTRYINDEX, reference);
    reference = LUA_NOREF;
  }
  lua_gc(L, LUA_GCCOLLECT);
  lua_gc(L, LUA_GCCOLLECT);
  if (port == PORT_CREATE_NEW || port == PORT_CREATE_NEW_VERIFIED)
  {
    probe_remove_fixture(target);
  }
  /* Same-state recovery: the identical port must succeed again and stay readable. */
  arguments = probe_push_port_call(L, port, target);
  status = lua_pcall(L, arguments, LUA_MULTRET, 0);
  if (status != LUA_OK || lua_gettop(L) != 2 || !lua_toboolean(L, 1)
      || lua_type(L, 2) != LUA_TUSERDATA)
  {
    abort();
  }
  if (port == PORT_CREATE_NEW || port == PORT_CREATE_NEW_VERIFIED)
  {
    /* Created handles are empty and writable; prove usability by writing, rewinding and reading back. */
    lua_pushcfunction(L, l_fs_write);
    lua_pushvalue(L, 2);
    lua_pushlstring(L, fixture_payload, (size_t)PROBE_FIXTURE_BYTES);
    if (lua_pcall(L, 2, LUA_MULTRET, 0) != LUA_OK || !lua_toboolean(L, -2))
    {
      abort();
    }
    lua_settop(L, 2);
    lua_pushcfunction(L, l_fs_seek);
    lua_pushvalue(L, 2);
    lua_pushinteger(L, 0);
    if (lua_pcall(L, 2, LUA_MULTRET, 0) != LUA_OK || !lua_toboolean(L, -2))
    {
      abort();
    }
    lua_settop(L, 2);
  }
  lua_pushcfunction(L, l_fs_read);
  lua_pushvalue(L, 2);
  lua_pushinteger(L, (lua_Integer)PROBE_FIXTURE_BYTES);
  status = lua_pcall(L, 2, LUA_MULTRET, 0);
  if (status != LUA_OK || !lua_toboolean(L, -2))
  {
    abort();
  }
  lua_getfield(L, -1, "bytes");
  {
    size_t length = 0U;
    const char *bytes = lua_tolstring(L, -1, &length);

    if (bytes == NULL || length != (size_t)PROBE_FIXTURE_BYTES
        || memcmp(bytes, fixture_payload, length) != 0)
    {
      abort();
    }
  }
  lua_settop(L, 0);
  /* Collect the recovery owner: the process must return to its ownership baseline. */
  lua_gc(L, LUA_GCCOLLECT);
  lua_gc(L, LUA_GCCOLLECT);
#if defined(_WIN32)
  if (probe_open_handle_count != 0U)
  {
    ++*leaks;
    printf(
      "recovery-leak port=%s fail_at=%zu residual=%lu\n",
      probe_port_name(port),
      fail_at,
      (unsigned long)probe_open_handle_count);
    while (probe_open_handle_count != 0U)
    {
      HANDLE escaped = probe_open_handles[--probe_open_handle_count];

      probe_real_close_handle(escaped);
    }
  }
#else
  after_count = probe_collect_descriptors(after, PROBE_MAX_DESCRIPTORS);
  if (after_count > before_count)
  {
    ++*leaks;
    printf(
      "recovery-leak port=%s fail_at=%zu residual=%d\n",
      probe_port_name(port),
      fail_at,
      after_count - before_count);
  }
#endif
  lua_close(L);
  return fault.calls;
}

/* Exercises every open and create port across all Lua allocation positions.
 * @param none No arguments; all fixtures are isolated and ephemeral.
 * @return int Zero only when no operating-system handle escapes any protected call.
 * @effect Prints per-port allocation-site and leak counts; every fixture is removed before exit.
 */
int main(void)
{
  static const probe_port ports[] = {
    PORT_OPEN_READ,
    PORT_CREATE_NEW,
    PORT_OPEN_READ_VERIFIED,
    PORT_CREATE_NEW_VERIFIED
  };
  size_t total_leaks = 0U;
  size_t port_index;

  setbuf(stdout, NULL);
  for (port_index = 0U; port_index < sizeof(ports) / sizeof(ports[0]); ++port_index)
  {
    probe_port port = ports[port_index];
    size_t leaks = 0U;
    size_t sites = probe_check_port(port, SIZE_MAX, &leaks);
    size_t position;

    for (position = 1U; position <= sites + 1U; ++position)
    {
      probe_check_port(port, position, &leaks);
    }
    printf(
      "%s allocation_sites=%zu handle_leaks=%zu recovery=PASS\n",
      probe_port_name(port),
      sites,
      leaks);
    total_leaks += leaks;
  }
  printf("fs-open-faults total_handle_leaks=%zu\n", total_leaks);
  return total_leaks == 0U ? 0 : 1;
}
