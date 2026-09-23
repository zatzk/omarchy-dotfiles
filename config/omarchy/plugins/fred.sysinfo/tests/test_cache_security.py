import importlib.util
import os
from pathlib import Path
import stat
import tempfile
import time
import unittest
from unittest import mock


PROBE = Path(__file__).resolve().parents[1] / "sysinfo-probe.py"
spec = importlib.util.spec_from_file_location("sysinfo_probe", PROBE)
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class CacheSecurityTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.directory = Path(self.tmp.name) / "fred.sysinfo"

    def test_private_modes_and_round_trip(self):
        self.assertTrue(probe.write_private_file("cache.json", b"{}", str(self.directory)))
        self.assertEqual(stat.S_IMODE(self.directory.stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE((self.directory / "cache.json").stat().st_mode), 0o600)
        self.assertEqual(probe.read_private_file("cache.json", cache_dir=str(self.directory)), b"{}")

    def test_preexisting_target_symlink_does_not_modify_victim(self):
        self.directory.mkdir(mode=0o700)
        self.directory.chmod(0o700)
        victim = Path(self.tmp.name) / "victim"
        victim.write_text("untouched")
        (self.directory / "cache.json").symlink_to(victim)
        self.assertTrue(probe.write_private_file("cache.json", b"safe", str(self.directory)))
        self.assertEqual(victim.read_text(), "untouched")
        self.assertEqual((self.directory / "cache.json").read_bytes(), b"safe")

    def test_symlink_directory_refused(self):
        target = Path(self.tmp.name) / "target"
        target.mkdir()
        self.directory.symlink_to(target, target_is_directory=True)
        self.assertFalse(probe.write_private_file("cache.json", b"unsafe", str(self.directory)))
        self.assertFalse((target / "cache.json").exists())

    def test_insecure_directory_and_file_refused(self):
        self.directory.mkdir(mode=0o700)
        self.directory.chmod(0o777)
        self.assertFalse(probe.write_private_file("cache.json", b"unsafe", str(self.directory)))
        self.directory.chmod(0o700)
        entry = self.directory / "cache.json"
        entry.write_bytes(b"private")
        entry.chmod(0o644)
        self.assertIsNone(probe.read_private_file("cache.json", cache_dir=str(self.directory)))

    def test_read_limits_and_symlink_refused(self):
        self.directory.mkdir(mode=0o700)
        entry = self.directory / "cache.json"
        entry.write_bytes(b"12345")
        entry.chmod(0o600)
        self.assertIsNone(probe.read_private_file("cache.json", max_bytes=4, cache_dir=str(self.directory)))
        os.utime(entry, (time.time() - 400, time.time() - 400))
        self.assertIsNone(probe.read_private_file("cache.json", max_age=300, cache_dir=str(self.directory)))
        entry.unlink()
        entry.symlink_to(Path(self.tmp.name) / "victim")
        self.assertIsNone(probe.read_private_file("cache.json", cache_dir=str(self.directory)))

    def test_failed_rename_cleans_up_temporary_file(self):
        with mock.patch.object(probe.os, "rename", side_effect=OSError("injected rename failure")):
            self.assertFalse(probe.write_private_file("cache.json", b"data", str(self.directory)))
        self.assertEqual(list(self.directory.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
