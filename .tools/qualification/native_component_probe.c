/*
** File: native_component_probe.c
** Date: 2026-08-30
** Author: WaterRun
** Description: Emits exact argv and stdin bytes for native component qualification.
*/

#include <stdio.h>
#include <string.h>

#if defined(_WIN32)
#include <fcntl.h>
#include <io.h>
#endif

static void write_hex(const unsigned char *bytes, size_t length)
{
  static const char digits[] = "0123456789abcdef";
  size_t index;

  for (index = 0; index < length; index++)
  {
    unsigned char value = bytes[index];
    putchar(digits[value >> 4]);
    putchar(digits[value & 0x0fU]);
  }
}

int main(int argc, char **argv)
{
  unsigned char buffer[257];
  size_t count;
  int index;

#if defined(_WIN32)
  if (_setmode(_fileno(stdin), _O_BINARY) == -1
      || _setmode(_fileno(stdout), _O_BINARY) == -1)
  {
    return 70;
  }
#endif
  printf("argc=%d\n", argc);
  for (index = 1; index < argc; index++)
  {
    printf("arg%d=", index);
    write_hex((const unsigned char *)argv[index], strlen(argv[index]));
    putchar('\n');
  }
  fputs("stdin=", stdout);
  while ((count = fread(buffer, 1U, sizeof(buffer), stdin)) > 0U)
  {
    write_hex(buffer, count);
  }
  putchar('\n');
  if (ferror(stdin) || ferror(stdout) || fflush(stdout) != 0)
  {
    return 71;
  }
  return 0;
}
