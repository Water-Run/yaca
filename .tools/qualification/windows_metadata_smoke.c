/*
** File: windows_metadata_smoke.c
** Date: 2026-09-14
** Author: WaterRun
** Description: Windows fixture for the strict legacy metadata restoration predicate.
** Build against the same Lua import library as yaca_native; run on Windows
** with an ordinary test file path. This does not modify the test file. */
#include "../../native/yaca_native.c"
#include <assert.h>

int main(int argc, char **argv)
{
  yaca_windows_snapshot snapshot;
  yaca_windows_metadata_state original;
  yaca_windows_metadata_state converted;
  const char *code = "Storage";
  const char *message = "metadata fixture inspection failed";
  PACL original_dacl;
  PACL converted_dacl;
  ACE_HEADER *first;
  BOOL present;
  BOOL defaulted;
  WORD index;
  unsigned char saved;

  assert(argc == 2);
  assert(inspect_windows_path(argv[1], strlen(argv[1]), &snapshot, &code, &message));
  assert(snapshot.exists && snapshot.metadata.proven);
  original = snapshot.metadata;
  original.security_descriptor = (unsigned char *)malloc(original.security_descriptor_length);
  assert(original.security_descriptor != NULL);
  memcpy(original.security_descriptor, snapshot.metadata.security_descriptor, original.security_descriptor_length);
  assert(SetSecurityDescriptorControl(original.security_descriptor, SE_DACL_AUTO_INHERITED, 0));
  assert(GetSecurityDescriptorDacl(original.security_descriptor, &present, &original_dacl, &defaulted));
  assert(present && original_dacl != NULL && original_dacl->AceCount > 0);
  for (index = 0; index < original_dacl->AceCount; ++index)
  {
    ACE_HEADER *ace;
    assert(GetAce(original_dacl, index, (LPVOID *)&ace));
    ace->AceFlags &= ~INHERITED_ACE;
  }
  converted = original;
  converted.security_descriptor = (unsigned char *)malloc(converted.security_descriptor_length);
  assert(converted.security_descriptor != NULL);
  memcpy(converted.security_descriptor, original.security_descriptor, converted.security_descriptor_length);
  assert(SetSecurityDescriptorControl(converted.security_descriptor,
    SE_DACL_AUTO_INHERITED, SE_DACL_AUTO_INHERITED));
  assert(GetSecurityDescriptorDacl(converted.security_descriptor, &present, &converted_dacl, &defaulted));
  for (index = 0; index < converted_dacl->AceCount; ++index)
  {
    ACE_HEADER *ace;
    assert(GetAce(converted_dacl, index, (LPVOID *)&ace));
    ace->AceFlags |= INHERITED_ACE;
  }
  assert(windows_metadata_added_auto_inheritance(&original, &converted));
  assert(!windows_metadata_added_auto_inheritance(&original, &original));
  converted.attributes ^= FILE_ATTRIBUTE_HIDDEN;
  assert(!windows_metadata_added_auto_inheritance(&original, &converted));
  converted.attributes ^= FILE_ATTRIBUTE_HIDDEN;
  assert(GetAce(converted_dacl, 0, (LPVOID *)&first));
  first->AceFlags ^= NO_PROPAGATE_INHERIT_ACE;
  assert(!windows_metadata_added_auto_inheritance(&original, &converted));
  first->AceFlags ^= NO_PROPAGATE_INHERIT_ACE;
  assert(first->AceSize > sizeof(ACE_HEADER) + sizeof(DWORD));
  /* A changed access mask and a changed SID byte must both remain refused. */
  ((unsigned char *)first)[sizeof(ACE_HEADER)] ^= 1U;
  assert(!windows_metadata_added_auto_inheritance(&original, &converted));
  ((unsigned char *)first)[sizeof(ACE_HEADER)] ^= 1U;
  saved = ((unsigned char *)first)[first->AceSize - 1U];
  ((unsigned char *)first)[first->AceSize - 1U] ^= 1U;
  assert(!windows_metadata_added_auto_inheritance(&original, &converted));
  ((unsigned char *)first)[first->AceSize - 1U] = saved;
  assert(windows_metadata_added_auto_inheritance(&original, &converted));
  free_windows_metadata_state(&original);
  free_windows_metadata_state(&converted);
  free_windows_snapshot(&snapshot);
  puts("windows-metadata-restoration-predicate=PASS");
  return 0;
}
