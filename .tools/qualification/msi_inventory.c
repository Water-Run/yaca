/*
Author: WaterRun
Date: 2026-09-23
File: msi_inventory.c
Description: Exports MSI file layout read-only for portable Python assembly.
This build-host helper never installs a product or executes installer actions.
*/

#define _WIN32_WINNT 0x0501
#include <windows.h>
#include <msi.h>
#include <msiquery.h>
#include <stdio.h>
#include <wchar.h>

/* Enumerates MSI database rows for the selected inventory query.
 * @param database MSIHANDLE The database bound to rows.
 * @param kind const_char* Selected error, stream, or operation category.
 * @param query const_WCHAR* The query bound to rows.
 * @return int result 1 after all query rows are written, 0 on MSI query failure.
 */
static int rows(MSIHANDLE database, const char *kind, const WCHAR *query)
{
  MSIHANDLE view = 0;
  MSIHANDLE record = 0;
  UINT status;
  unsigned int column;
  int ok = 0;

  if (MsiDatabaseOpenViewW(database, query, &view) != ERROR_SUCCESS) return 0;
  if (MsiViewExecute(view, 0) != ERROR_SUCCESS) goto done;
  while ((status = MsiViewFetch(view, &record)) == ERROR_SUCCESS)
  {
    fputs(kind, stdout);
    for (column = 1; column <= 3; column++)
    {
      WCHAR value[4096];
      char encoded[16384];
      DWORD capacity = 4096;
      if (MsiRecordGetStringW(record, column, value, &capacity) != ERROR_SUCCESS
          || wcspbrk(value, L"\t\r\n") != NULL
          || !WideCharToMultiByte(CP_UTF8, 0, value, -1, encoded,
            sizeof(encoded), NULL, NULL)) goto done;
      fputc('\t', stdout);
      fputs(encoded, stdout);
    }
    fputc('\n', stdout);
    MsiCloseHandle(record);
    record = 0;
  }
  ok = status == ERROR_NO_MORE_ITEMS && !ferror(stdout);
done:
  if (record != 0) MsiCloseHandle(record);
  MsiViewClose(view);
  MsiCloseHandle(view);
  return ok;
}

/* Runs the msi inventory executable and reports its exit status.
 * @param argc int Number of command-line arguments supplied by the host.
 * @param argv WCHAR** Host command-line argument vector.
 * @return int result Process exit status, zero only when all smoke checks pass.
 */
int wmain(int argc, WCHAR **argv)
{
  MSIHANDLE database = 0;
  int ok;

  if (argc != 2) return 2;
  if (MsiOpenDatabaseW(argv[1], MSIDBOPEN_READONLY, &database) != ERROR_SUCCESS) return 1;
  ok = rows(database, "Directory",
    L"SELECT `Directory`,`Directory_Parent`,`DefaultDir` FROM `Directory`")
    && rows(database, "Component",
      L"SELECT `Component`,`Directory_`,`KeyPath` FROM `Component`")
    && rows(database, "File",
      L"SELECT `File`,`Component_`,`FileName` FROM `File`");
  MsiCloseHandle(database);
  return ok ? 0 : 1;
}
