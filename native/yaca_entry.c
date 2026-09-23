/*
Author: WaterRun
Date: 2026-09-23
File: yaca_entry.c
Description: Selects the embedded Lua interpreter before application startup.
*/

#include <string.h>
#ifdef _WIN32
#include <windows.h>
#include <shellapi.h>
#include <stdlib.h>
#include <stdio.h>
#endif

/* Both entry points link against the exact same Lua runtime. The interpreter
** creates its own state and never loads the application's bootstrap or keys.
*/
/* Runs the yaca entry executable and reports its exit status.
 * @param argc int Number of command-line arguments supplied by the host.
 * @param argv char** Host command-line argument vector.
 * @return int result Process exit status, zero only when all smoke checks pass.
 */
int main(int argc, char **argv)
{
  int result;
#ifdef _WIN32
  int count = 0;
  int index;
  WCHAR **wide = CommandLineToArgvW(GetCommandLineW(), &count);
  char **utf8 = NULL;
  if (wide != NULL && count > 0)
    utf8 = (char **)calloc((size_t)count + 1, sizeof(char *));
  if (utf8 == NULL) goto argv_error;
  for (index = 0; index < count; index++)
  {
    int length = WideCharToMultiByte(CP_UTF8, 0, wide[index], -1, NULL, 0, NULL, NULL);
    if (length == 0) goto argv_error;
    utf8[index] = (char *)malloc((size_t)length);
    if (utf8[index] == NULL
        || WideCharToMultiByte(CP_UTF8, 0, wide[index], -1,
          utf8[index], length, NULL, NULL) != length) goto argv_error;
  }
  LocalFree(wide);
  wide = NULL;
  argc = count;
  argv = utf8;
#endif
  if (argc > 1 && strcmp(argv[1], "--lua") == 0)
  {
    char *entry_option = argv[1];
    argv[1] = argv[0];
    result = yaca_lua_main(argc - 1, argv + 1);
    argv[1] = entry_option;
  }
  else result = yaca_application_main(argc, argv);
#ifdef _WIN32
  for (index = 0; index < count; index++) free(utf8[index]);
  free(utf8);
#endif
  return result;
#ifdef _WIN32
argv_error:
  if (wide != NULL) LocalFree(wide);
  if (utf8 != NULL)
  {
    for (index = 0; index < count; index++) free(utf8[index]);
    free(utf8);
  }
  fputs("yaca: cannot decode Windows command line\n", stderr);
  return 1;
#endif
}
