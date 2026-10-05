/*
Author: WaterRun
Date: 2026-10-05
File: windows_reparse_smoke.c
Description: Exercises the production Windows reparse decoder with substituted kernel buffers and an optional isolated real junction whose display and actual targets differ.
*/

#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0501
#endif
#include <windows.h>
#include <winioctl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static BYTE probe_bytes[MAXIMUM_REPARSE_DATA_BUFFER_SIZE];
static DWORD probe_received;
static int probe_injected = 1;
static unsigned int probe_cases;
static unsigned int probe_failed;

/* Intercept only the decoder's synchronous get-reparse request, or pass through a real junction query.
 * @param handle HANDLE Caller-owned reparse handle; synthetic cases use a non-dereferenced sentinel.
 * @param control DWORD Must be FSCTL_GET_REPARSE_POINT during injected cases.
 * @param input LPVOID Must be NULL for the injected get request; passed through otherwise.
 * @param input_bytes DWORD Must be zero for the injected get request; passed through otherwise.
 * @param output LPVOID Caller-owned buffer receiving deterministic synthetic bytes or the OS response.
 * @param output_bytes DWORD Capacity of output; must hold the synthetic receive count.
 * @param returned LPDWORD Receives the explicit synthetic count or the actual OS count.
 * @param overlapped LPOVERLAPPED Must be NULL for the synchronous injected request.
 * @return BOOL TRUE after copying a synthetic frame, or the unchanged real DeviceIoControl result.
 * @effect Writes only the supplied output/count; real mode queries the caller-owned junction handle.
 * @error Aborts if the production decoder issues a different request than the fixture admits.
 */
static BOOL WINAPI probe_device_io_control(
  HANDLE handle, DWORD control, LPVOID input, DWORD input_bytes,
  LPVOID output, DWORD output_bytes, LPDWORD returned, LPOVERLAPPED overlapped)
{
  if (!probe_injected)
  {
    return DeviceIoControl(handle, control, input, input_bytes,
      output, output_bytes, returned, overlapped);
  }
  if (control != FSCTL_GET_REPARSE_POINT || input != NULL || input_bytes != 0U
      || overlapped != NULL || output_bytes < sizeof(probe_bytes) || returned == NULL)
  {
    abort();
  }
  /* Bytes beyond returned are deterministic poison/fixtures, not admitted payload. */
  memcpy(output, probe_bytes, sizeof(probe_bytes));
  *returned = probe_received;
  SetLastError(ERROR_SUCCESS);
  return TRUE;
}

#define DeviceIoControl probe_device_io_control
#include "../../native/yaca_native.c"
#undef DeviceIoControl

/* Prepare a bounded symbolic-link or mount-point frame with separate actual and display strings.
 * @param tag DWORD Supported symlink or mount-point tag selected for the fixture.
 * @param substitute const_WCHAR* Actual target string, optionally empty for a rejection case.
 * @param print const_WCHAR* Display string, optionally empty; it must not select the actual target.
 * @param flags DWORD Symbolic-link flags; ignored for mount-point layout.
 * @return void No result; updates only the global injected byte frame and receive count.
 * @error Aborts if either fixture spelling would overflow the fixed test buffer.
 */
static void probe_prepare(DWORD tag, const WCHAR *substitute, const WCHAR *print, DWORD flags)
{
  yaca_reparse_buffer *buffer = (yaca_reparse_buffer *)probe_bytes;
  size_t path_offset = tag == IO_REPARSE_TAG_SYMLINK
    ? FIELD_OFFSET(yaca_reparse_buffer, value.symbolic_link.path)
    : FIELD_OFFSET(yaca_reparse_buffer, value.mount_point.path);
  size_t substitute_bytes = wcslen(substitute) * sizeof(WCHAR);
  size_t print_bytes = wcslen(print) * sizeof(WCHAR);
  size_t print_offset = substitute_bytes + sizeof(WCHAR);
  size_t payload_bytes = print_offset + print_bytes + sizeof(WCHAR);
  if (path_offset + payload_bytes > sizeof(probe_bytes)) abort();
  memset(probe_bytes, 0, sizeof(probe_bytes));
  buffer->tag = tag;
  buffer->data_length = (WORD)(path_offset - 8U + payload_bytes);
  if (tag == IO_REPARSE_TAG_SYMLINK)
  {
    buffer->value.symbolic_link.substitute_length = (WORD)substitute_bytes;
    buffer->value.symbolic_link.print_offset = (WORD)print_offset;
    buffer->value.symbolic_link.print_length = (WORD)print_bytes;
    buffer->value.symbolic_link.flags = flags;
  }
  else
  {
    buffer->value.mount_point.substitute_length = (WORD)substitute_bytes;
    buffer->value.mount_point.print_offset = (WORD)print_offset;
    buffer->value.mount_point.print_length = (WORD)print_bytes;
  }
  memcpy(probe_bytes + path_offset, substitute, substitute_bytes);
  memcpy(probe_bytes + path_offset + print_offset, print, print_bytes);
  probe_received = (DWORD)(8U + buffer->data_length);
}

/* Compare one production decode with its expected target or rejection without aborting later cases.
 * @param label const_char* Stable non-secret name identifying this synthetic case.
 * @param expected const_char* Exact canonical UTF-8 target, or NULL when the frame must be rejected.
 * @return void No result; increments case/failure counts and releases any returned target.
 * @effect Calls the production decoder using only the injected frame and prints one finite result line.
 */
static void probe_expect(const char *label, const char *expected)
{
  char *observed = windows_reparse_target((HANDLE)(uintptr_t)1U, L"C:\\fixture\\parent");
  int matches = expected == NULL ? observed == NULL
    : observed != NULL && strcmp(observed, expected) == 0;
  ++probe_cases;
  if (!matches) ++probe_failed;
  printf("%s %s\n", matches ? "PASS" : "FAIL", label);
  free(observed);
}

/* Exercise actual-target selection, namespace conversion and malformed frame boundaries.
 * @param none Uses only local injected buffers; no filesystem or network is accessed.
 * @return void No result; all production outcomes accumulate in the global case counters.
 */
static void probe_synthetic(void)
{
  yaca_reparse_buffer *buffer = (yaca_reparse_buffer *)probe_bytes;
  probe_prepare(IO_REPARSE_TAG_SYMLINK, L"\\??\\C:\\actual\\item", L"C:\\display\\item", 0U);
  probe_expect("symlink-uses-substitute", "C:\\actual\\item");
  probe_prepare(IO_REPARSE_TAG_MOUNT_POINT, L"\\??\\C:\\actual\\junction", L"C:\\display\\junction", 0U);
  probe_expect("junction-uses-substitute", "C:\\actual\\junction");
  probe_prepare(IO_REPARSE_TAG_SYMLINK, L"..\\actual\\item", L"..\\display\\item", SYMLINK_FLAG_RELATIVE);
  probe_expect("relative-substitute", "C:\\fixture\\actual\\item");
  probe_prepare(IO_REPARSE_TAG_SYMLINK, L"\\??\\UNC\\server\\share\\item", L"", 0U);
  probe_expect("unc-substitute", "\\\\server\\share\\item");
  probe_prepare(IO_REPARSE_TAG_SYMLINK, L"\\??\\C:\\actual\\item", L"", 0U);
  probe_expect("empty-display-is-optional", "C:\\actual\\item");
  buffer->data_length = 0U;
  probe_expect("declared-symlink-header-short", NULL);
  probe_prepare(IO_REPARSE_TAG_MOUNT_POINT, L"\\??\\C:\\actual\\item", L"", 0U);
  buffer->data_length = 0U;
  probe_expect("declared-junction-header-short", NULL);
  probe_prepare(IO_REPARSE_TAG_SYMLINK, L"\\??\\C:\\actual\\item", L"", 0U);
  probe_received = 7U;
  probe_expect("common-header-short", NULL);
  probe_prepare(IO_REPARSE_TAG_SYMLINK, L"\\??\\C:\\actual\\item", L"", 0U);
  --probe_received;
  probe_expect("declared-data-exceeds-returned", NULL);
  probe_prepare(IO_REPARSE_TAG_SYMLINK, L"\\??\\C:\\actual\\item", L"", 0U);
  buffer->data_length = 12U;
  probe_expect("name-outside-declared-payload", NULL);
  probe_prepare(IO_REPARSE_TAG_SYMLINK, L"", L"C:\\display\\item", 0U);
  probe_expect("actual-target-missing", NULL);
  probe_prepare(IO_REPARSE_TAG_SYMLINK, L"\\??\\C:\\actual\\item", L"", 2U);
  probe_expect("unknown-symlink-flag", NULL);
  probe_prepare(IO_REPARSE_TAG_SYMLINK, L"\\??\\C:\\actual\\item", L"", 0U);
  buffer->value.symbolic_link.substitute_length = 3U;
  probe_expect("odd-target-length", NULL);
  probe_prepare(IO_REPARSE_TAG_SYMLINK, L"\\??\\C:\\actual\\item", L"", 0U);
  memmove(probe_bytes + FIELD_OFFSET(yaca_reparse_buffer, value.symbolic_link.path) + 1U,
    probe_bytes + FIELD_OFFSET(yaca_reparse_buffer, value.symbolic_link.path),
    buffer->value.symbolic_link.substitute_length);
  buffer->value.symbolic_link.substitute_offset = 1U;
  probe_expect("odd-target-offset", NULL);
  probe_prepare(IO_REPARSE_TAG_SYMLINK, L"C:\\actual\\item", L"", 0U);
  buffer->value.symbolic_link.path[3] = L'\0';
  probe_expect("embedded-target-nul", NULL);
  probe_prepare(IO_REPARSE_TAG_SYMLINK, L"\\??\\C:\\actual\\item", L"", 0U);
  buffer->value.symbolic_link.print_offset = 0xffffU;
  probe_expect("display-range-invalid", NULL);
  probe_prepare(IO_REPARSE_TAG_SYMLINK, L"\\??\\C:\\actual\\item", L"", 0U);
  buffer->tag = 0x80000000UL;
  probe_expect("unknown-tag", NULL);
  probe_prepare(IO_REPARSE_TAG_SYMLINK, L"\\??\\Volume{11111111-1111-1111-1111-111111111111}\\item", L"", 0U);
  probe_expect("unsupported-nt-namespace-is-not-relative", NULL);
  probe_prepare(IO_REPARSE_TAG_SYMLINK, L"C:relative-item", L"", 0U);
  probe_expect("absolute-target-is-not-drive-relative", NULL);
}

/* Create one uniquely owned real junction, compare decoded and kernel-followed targets, then remove it.
 * @param root const_char* Existing caller-owned ASCII/UTF-8 scratch directory on a Windows filesystem.
 * @return void No result; adds one case and removes the completed fixture after either decoder outcome.
 * @effect Creates only a reserved unique child under root, two directories and one junction; queries handles and cleans them.
 * @error Aborts for unusable scratch paths, failed fixture setup or incomplete cleanup; an incomplete owned fixture remains for investigation.
 */
static void probe_real_junction(const char *root)
{
  WCHAR *wide_root = utf8_to_wide(root, strlen(root));
  WCHAR owned[MAX_PATH];
  WCHAR actual[MAX_PATH];
  WCHAR display[MAX_PATH];
  WCHAR link[MAX_PATH];
  WCHAR substitute[MAX_PATH + 4U];
  HANDLE handle;
  HANDLE actual_handle;
  HANDLE followed_handle;
  BY_HANDLE_FILE_INFORMATION actual_information;
  BY_HANDLE_FILE_INFORMATION followed_information;
  char *observed;
  char *expected;
  DWORD returned;
  int matches;
  if (wide_root == NULL || GetTempFileNameW(wide_root, L"yrp", 0U, owned) == 0U) abort();
  free(wide_root);
  if (wcslen(owned) + 16U >= MAX_PATH || !DeleteFileW(owned) || !CreateDirectoryW(owned, NULL)) abort();
  wcscpy(actual, owned); wcscat(actual, L"\\actual");
  wcscpy(display, owned); wcscat(display, L"\\display");
  wcscpy(link, owned); wcscat(link, L"\\link");
  wcscpy(substitute, L"\\??\\"); wcscat(substitute, actual);
  if (!CreateDirectoryW(actual, NULL) || !CreateDirectoryW(display, NULL)
      || !CreateDirectoryW(link, NULL)) abort();
  handle = CreateFileW(link, GENERIC_READ | GENERIC_WRITE, 0U, NULL, OPEN_EXISTING,
    FILE_FLAG_OPEN_REPARSE_POINT | FILE_FLAG_BACKUP_SEMANTICS, NULL);
  if (handle == INVALID_HANDLE_VALUE) abort();
  probe_prepare(IO_REPARSE_TAG_MOUNT_POINT, substitute, display, 0U);
  if (!DeviceIoControl(handle, FSCTL_SET_REPARSE_POINT, probe_bytes, probe_received,
      NULL, 0U, &returned, NULL)) abort();
  probe_injected = 0;
  observed = windows_reparse_target(handle, owned);
  expected = wide_to_utf8(actual);
  matches = observed != NULL && expected != NULL && strcmp(observed, expected) == 0;
  if (!CloseHandle(handle)) abort();
  actual_handle = CreateFileW(actual, FILE_READ_ATTRIBUTES,
    FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_EXISTING,
    FILE_FLAG_BACKUP_SEMANTICS, NULL);
  followed_handle = CreateFileW(link, FILE_READ_ATTRIBUTES,
    FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_EXISTING,
    FILE_FLAG_BACKUP_SEMANTICS, NULL);
  if (actual_handle == INVALID_HANDLE_VALUE || followed_handle == INVALID_HANDLE_VALUE
      || !GetFileInformationByHandle(actual_handle, &actual_information)
      || !GetFileInformationByHandle(followed_handle, &followed_information)) abort();
  matches = matches && windows_same_object(&actual_information, &followed_information);
  if (!CloseHandle(actual_handle) || !CloseHandle(followed_handle)) abort();
  ++probe_cases;
  if (!matches) ++probe_failed;
  printf("%s real-junction-uses-substitute\n", matches ? "PASS" : "FAIL");
  free(observed); free(expected);
  if (!RemoveDirectoryW(link) || !RemoveDirectoryW(actual)
      || !RemoveDirectoryW(display) || !RemoveDirectoryW(owned)) abort();
  probe_injected = 1;
}

/* Run every decoder case, optionally adding a genuine NTFS junction in the supplied scratch root.
 * @param argc int One for synthetic cases, or two with a caller-owned scratch directory.
 * @param argv char** Process arguments; argv[1] is the optional scratch root.
 * @return int Zero only when every case passed; two for invalid arguments, one for decoder failures.
 * @effect Prints individual observations and one total; an optional fixture is completely removed.
 */
int main(int argc, char **argv)
{
  if (argc < 1 || argc > 2) return 2;
  setbuf(stdout, NULL);
  probe_synthetic();
  if (argc == 2) probe_real_junction(argv[1]);
  printf("windows-reparse cases=%u failed=%u\n", probe_cases, probe_failed);
  return probe_failed == 0U ? 0 : 1;
}
