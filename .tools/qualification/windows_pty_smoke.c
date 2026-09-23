/*
Author: WaterRun
Date: 2026-09-23
File: windows_pty_smoke.c
Description: Checks PTY recognition and optional live no-echo restoration.
*/

#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0501
#endif
#include <windows.h>
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../../native/yaca_pty.h"

/* Runs the windows pty smoke executable and reports its exit status.
 * @param argc int Number of command-line arguments supplied by the host.
 * @param argv char** Host command-line argument vector.
 * @return int result Process exit status, zero only when all smoke checks pass.
 */
int main(int argc, char **argv)
{
  /* @struct cases Pipe-name fixture paired with expected Cygwin PTY recognition.
   * @field name const_WCHAR* Immutable UTF-16 pipe-name fixture.
   * @field expected int Expected boolean result of the PTY-name parser.
   */
  static const struct { const WCHAR *name; int expected; } cases[] = {
    { L"cygwin-0123456789abcdef-pty9-from-master", 1 },
    { L"cygwin-0123456789abcdef-pty9-to-master", 1 },
    { L"cygwin-0123456789abcdef-pty9-from-master-nat", 1 },
    { L"cygwin-0123456789abcdef-pty9-to-master-nat", 1 },
    { L"cygwin-0123456789abcdeg-pty9-from-master-nat", 0 },
    { L"cygwin-0123456789abcdef-pty-from-master", 0 },
    { L"cygwin-0123456789abcdef-pty9-from-master-extra", 0 },
    { L"ordinary-pty9-from-master", 0 },
    { L"cygwin-", 0 },
  };
  size_t index;

  for (index = 0; index < sizeof(cases) / sizeof(cases[0]); index++)
  {
    WCHAR name[256];
    HANDLE pipe;
    _snwprintf(name, 256, L"\\\\.\\pipe\\%ls", cases[index].name);
    pipe = CreateNamedPipeW(name, PIPE_ACCESS_DUPLEX | FILE_FLAG_FIRST_PIPE_INSTANCE,
      PIPE_TYPE_BYTE | PIPE_WAIT, 1, 4096, 4096, 0, NULL);
    assert(pipe != INVALID_HANDLE_VALUE);
    assert(yaca_is_cygwin_pty(pipe) == cases[index].expected);
    CloseHandle(pipe);
  }
  assert(!yaca_is_cygwin_pty(NULL));
  assert(!yaca_is_cygwin_pty(INVALID_HANDLE_VALUE));
  if (argc == 2 && strcmp(argv[1], "--interactive") == 0)
  {
    yaca_pty_state state;
    char after[1024];
    unsigned int count = 0;
    int complete = 0;
    memset(&state, 0, sizeof(state));
    assert(yaca_is_cygwin_pty(GetStdHandle(STD_INPUT_HANDLE)));
    assert(yaca_pty_start(&state, 0));
    puts("Enter a non-secret test marker (input must be hidden):");
    fflush(stdout);
    while (count < 256)
    {
      char byte;
      DWORD received;
      if (!ReadFile(GetStdHandle(STD_INPUT_HANDLE), &byte, 1, &received, NULL)
          || received == 0) break;
      if (byte == '\r' || byte == '\n') { complete = 1; break; }
      if (byte == 3 || byte == 4) break;
      count++;
    }
    assert(yaca_pty_restore(&state));
    assert(yaca_stty(&state, "-g", after));
    after[strcspn(after, "\r\n")] = '\0';
    assert(strcmp(after, state.saved) == 0);
    if (!complete) return 130;
    printf("hidden-input-bytes=%u terminal-restored=PASS\n", count);
  }
  puts("cygwin-pty=PASS cases=11");
  return 0;
}
