/*
Author: WaterRun
Date: 2026-09-23
File: yaca_onefile_entry.c
Description: Wide CRT entry for the Windows onefile wrapper (link with -municode).
*/

/* Wide CRT entry for the Windows onefile wrapper (link with -municode). */
#undef main
/* Runs the yaca onefile entry executable and reports its exit status.
 * @param argc int Number of command-line arguments supplied by the host.
 * @param wide WCHAR** Windows wide-character input or output buffer.
 * @return int result Process exit status, zero only when all smoke checks pass.
 */
int wmain(int argc, WCHAR **wide)
{
  char **argv = (char **)calloc((size_t)argc + 1, sizeof(char *));
  int index, result = 1;
  if (argv == NULL) return 1;
  for (index = 0; index < argc; index++)
  {
    int size = WideCharToMultiByte(CP_UTF8, 0, wide[index], -1, NULL, 0, NULL, NULL);
    if (size <= 0) goto cleanup;
    argv[index] = (char *)malloc((size_t)size);
    if (argv[index] == NULL) goto cleanup;
    /* An empty argument has a zero-byte payload, which is valid. */
    if (!WideCharToMultiByte(CP_UTF8, 0, wide[index], -1, argv[index], size, NULL, NULL))
      goto cleanup;
  }
  result = yaca_extractor_main(argc, argv);
cleanup:
  for (index = 0; index < argc; index++) free(argv[index]);
  free(argv);
  return result;
}
