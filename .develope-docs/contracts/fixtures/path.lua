return {
  contract_version = "0.1.0-readiness.1",
  hash_vectors = {
    { id = "windows-drive-lower", logical_path = "/C/work/a.xml", full_sha256 = "70d2a834d9b741a726c11ea45746aa1a3fc3ed371c438d25cb103255a79fbdcf", context_hash = "70D2A834D9B741A7" },
    { id = "windows-drive-case-preserved", logical_path = "/C/work/A.xml", full_sha256 = "b9c12387369df206d886bf717c00381870139c57066b985049db025b830f2743", context_hash = "B9C12387369DF206" },
    { id = "posix-root", logical_path = "/home/u/proj/t.xml", full_sha256 = "6317cf575885571df3a8d5c3aa35d1a4c92b5a5e07cdabe11463e6412ceedb27", context_hash = "6317CF575885571D" },
    { id = "windows-unc", logical_path = "/UNC/server/share/t.xml", full_sha256 = "c5e61cdced9333413eb04d800f7101f48b6b06088b598ec3457e4a74d0db5c7c", context_hash = "C5E61CDCED933341" },
    { id = "rename-invalidates-old", logical_path = "/home/u/proj/renamed.xml", full_sha256 = "501aa811e59f4bff24d2eef6d411ab934da04f4896764357d1c0230f484d950b", context_hash = "501AA811E59F4BFF" },
    { id = "rebind-invalidates-old", logical_path = "/D/rebound/t.xml", full_sha256 = "47c96dd14068a6434003bd4f2b8a5831d0bcf2fd0f6c88fb96a0d70784109eae", context_hash = "47C96DD14068A643" },
  },
  codec_cases = {
    { id = "drive", platform_path = "C:\\work\\a.xml", logical_path = "/C/work/a.xml", valid = true },
    { id = "drive-letter-canonicalized", platform_path = "c:\\work\\a.xml", logical_path = "/C/work/a.xml", valid = true },
    { id = "unc", platform_path = "\\\\server\\share\\t.xml", logical_path = "/UNC/server/share/t.xml", valid = true },
    { id = "posix", platform_path = "/home/u/proj/t.xml", logical_path = "/home/u/proj/t.xml", valid = true },
    { id = "separator-collapse", platform_path = "/home//u/./proj/t.xml", logical_path = "/home/u/proj/t.xml", valid = true },
    { id = "case-preserved", platform_path = "C:\\Work\\A.xml", logical_path = "/C/Work/A.xml", valid = true },
    { id = "dotdot-within-root", platform_path = "/home/u/tmp/../proj/t.xml", logical_path = "/home/u/proj/t.xml", valid = true },
    { id = "dotdot-escape", platform_path = "/../../etc/passwd", valid = false, error_id = "PathEscapesWorkspace" },
    { id = "relative", platform_path = "work/a.xml", valid = false, error_id = "UnsupportedPath" },
    { id = "nul", platform_path = "C:\\work\0a.xml", valid = false, error_id = "UnsupportedPath" },
  },
  selector_cases = {
    { token = "70d2a834d9b741a7", kind = "hash", canonical = "70D2A834D9B741A7" },
    { token = "70D2A834D9B741A7", kind = "hash", canonical = "70D2A834D9B741A7" },
    { token = "70D2A834D9B741A", kind = "name", canonical = "70D2A834D9B741A" },
    { token = "70D2A834D9B741AG", kind = "name", canonical = "70D2A834D9B741AG" },
  },
}
