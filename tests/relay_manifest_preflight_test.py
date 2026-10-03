"""Relay builds must reject stale content before downloading or starting Godot."""
from __future__ import annotations

from contextlib import chdir
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import deploy_block_war_relay as deploy


class BuildReached(Exception):
    """Stop immediately after the real manifest check, before any download."""


class RelayManifestPreflightTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="relay-manifest-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "frozen-source"
        self.root.mkdir()
        (self.root / "tools").mkdir()
        shutil.copyfile(ROOT / "tools/build_network_manifest.py", self.root / "tools/build_network_manifest.py")
        self.write("project.godot", b'config/version="1.4.0"\n')
        self.write("scripts/block_war/rules.gd", "extends RefCounted\n# 战斗规则\nconst SPEED := 2.2\n".encode())
        self.write("data/block_war/maps/map.tres", b'[gd_resource type="Resource" format=3]\n')
        self.manifest = self.root / "data/block_war/network_manifest.json"
        subprocess.run([sys.executable, str(self.root / "tools/build_network_manifest.py")],
                       cwd=self.root, check=True, capture_output=True)
        self.original_manifest = self.manifest.read_bytes()
        self.local = Path(self.temporary.name) / "build-output"

    def write(self, relative: str, data: bytes):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)

    def attempt_build(self, fresh: bool):
        with patch.object(deploy, "ROOT", self.root), \
                patch.object(deploy, "LOCAL", self.local), \
                patch.object(deploy, "templates", side_effect=BuildReached) as templates, \
                patch.object(deploy, "runtime") as runtime, \
                patch.object(deploy.urllib.request, "urlopen") as download, \
                patch.object(deploy.subprocess, "Popen", wraps=subprocess.Popen) as processes:
            with self.assertRaises(BuildReached if fresh else subprocess.CalledProcessError):
                deploy.build_relay()
            if fresh:
                templates.assert_called_once_with()
            else:
                templates.assert_not_called()
                self.assertFalse(self.local.exists(), "stale content must fail before staging")
            runtime.assert_not_called()
            download.assert_not_called()
            # The only child is the real Python checker. Godot never starts.
            self.assertEqual(processes.call_count, 1)
            self.assertEqual(processes.call_args.args[0],
                             [sys.executable, str(self.root / "tools/build_network_manifest.py"), "--check"])
            self.assertEqual(processes.call_args.kwargs["cwd"], self.root)
        if self.manifest.exists():
            self.assertEqual(self.manifest.read_bytes(), self.original_manifest,
                             "preflight must never rebuild or rewrite the manifest")

    def test_fresh_frozen_tree_is_checked_independently_of_working_directory(self):
        unrelated = Path(self.temporary.name) / "unrelated-workspace"
        unrelated.mkdir()
        (unrelated / "project.godot").write_text('config/version="0.0.0"\n', encoding="utf-8")
        with chdir(unrelated):
            self.attempt_build(fresh=True)

    def test_rule_change_is_rejected_before_build(self):
        with (self.root / "scripts/block_war/rules.gd").open("ab") as source:
            source.write(b"const DAMAGE := 3.0\n")
        self.attempt_build(fresh=False)

    def test_new_rule_file_is_rejected_before_build(self):
        self.write("scripts/block_war/new_rule.gd", b"extends RefCounted\n")
        self.attempt_build(fresh=False)

    def test_missing_manifest_is_rejected_without_regeneration(self):
        self.manifest.unlink()
        self.attempt_build(fresh=False)
        self.assertFalse(self.manifest.exists())

    def test_release_change_is_rejected_before_build(self):
        self.write("project.godot", b'config/version="1.4.1"\n')
        self.attempt_build(fresh=False)

    def test_windows_line_endings_follow_existing_generator_rules(self):
        path = self.root / "scripts/block_war/rules.gd"
        path.write_bytes(path.read_bytes().replace(b"\n", b"\r\n"))
        self.attempt_build(fresh=True)


if __name__ == "__main__":
    unittest.main()
