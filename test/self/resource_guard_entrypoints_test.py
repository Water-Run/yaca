#!/usr/bin/env python3
# Author: WaterRun
# Date: 2026-10-15
# File: resource_guard_entrypoints_test.py
# Description: Exercise actual Bash development/build entrypoints against a nonexecutable guard fixture, stopping before any build to verify Windows-to-WSL checkouts remain runnable.

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


#@class GuardEntrypointTest Actual shell entrypoints copied into an owned no-execute-bit fixture tree.
#@field temporary TemporaryDirectory Owns fixture scripts and automatic cleanup.
#@field root Path Absolute fixture repository root.
#@field environment dict Sanitized child environment that forces guard admission instead of any build body.
@unittest.skipUnless(os.name == 'posix' and shutil.which('bash'), 'Linux or WSL Bash permission regression')
class GuardEntrypointTest(unittest.TestCase):
    # Create a readable, nonexecutable guard that terminates before any compilation or download.
    #@param self GuardEntrypointTest Owns the temporary scripts and child environment.
    #@return None Stores the fixture root and a guard-forcing environment.
    #@effect Writes a small Bash stub with mode 0644 and registers fixture cleanup.
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='yaca-guard-entrypoints-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        guard = self.root / '.tools/run_with_resource_guard.sh'
        guard.parent.mkdir()
        guard.write_text('''#!/usr/bin/env bash
# Author: WaterRun
# Date: 2026-10-15
# File: run_with_resource_guard.sh
# Description: Stop an entrypoint regression fixture before its build or dependency retrieval.
printf 'guard-fixture-reached\\n'
exit 73
''', encoding='utf-8')
        guard.chmod(0o644)
        self.environment = {key: value for key, value in os.environ.items()
                            if not (key.startswith('YACA_') and key.endswith('_GUARD_HELD'))}
        self.environment['YACA_TEST_RESOURCE_GUARD_HELD'] = '0'
        self.environment['YACA_TEST_MIN_AVAILABLE_MIB'] = '5120'

    # Reach the shared guard from every maintained guarded shell entrypoint without its execute bit.
    #@param self GuardEntrypointTest Owns the inert shared guard and all copied scripts.
    #@return None Assertions require each real entrypoint to reach the stub and stop with code 73.
    #@error Child timeout or a missing guard marker fails the current subtest.
    #@effect Runs only Bash preambles and the inert guard; no compiler, VM, dependency fetch or build body runs.
    def test_nonexecutable_guard_is_interpreted_by_all_entrypoints(self):
        checked = 0
        for source in sorted((ROOT / '.tools').rglob('*.sh')):
            text = source.read_text(encoding='utf-8')
            if not any('exec ' in line and 'run_with_resource_guard.sh' in line for line in text.splitlines()):
                continue
            relative = source.relative_to(ROOT)
            target = self.root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text, encoding='utf-8')
            target.chmod(0o644)
            with self.subTest(entrypoint=relative.as_posix()):
                result = subprocess.run(['bash', str(target)], cwd=self.root, env=self.environment,
                                        capture_output=True, text=True, timeout=5)
                self.assertEqual(result.returncode, 73, result.stderr)
                self.assertEqual(result.stdout.strip(), 'guard-fixture-reached')
            checked += 1
        self.assertGreaterEqual(checked, 16)


if __name__ == '__main__':
    unittest.main()
