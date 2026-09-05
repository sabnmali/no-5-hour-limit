"""Exercise cron quoting with legal but shell-sensitive directory names."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from test_keepalive import BASH, ROOT


@unittest.skipUnless(BASH, 'Bash unavailable')
class UnixInstallerTests(unittest.TestCase):
    def test_cron_path_is_literal(self):
        with tempfile.TemporaryDirectory(prefix='keepalive installer ') as temp:
            base = Path(temp)
            repo = base / "repo ' `touch INJECTED` & %"
            shutil.copytree(ROOT / 'bin', repo / 'bin')
            shutil.copytree(ROOT / 'install', repo / 'install')
            (repo / 'config.env').write_text('CLAUDE_ENABLED=false\nCODEX_ENABLED=false\n', newline='\n')
            mockbin = base / 'mockbin'
            mockbin.mkdir()
            fakehome = base / 'home'
            fakehome.mkdir()
            scripts = {
                'uname': 'echo Linux',
                'claude': "echo '{\"loggedIn\":true}'",
                'codex': 'exit 0',
                'crontab': '[ "$1" != -l ] || exit 0\ncat > "$CRON_CAPTURE"',
            }
            for name, body in scripts.items():
                file = mockbin / name
                file.write_text('#!/usr/bin/env bash\n' + body + '\n', newline='\n')
                file.chmod(0o755)
            env = os.environ.copy()
            env['PATH'] = str(mockbin) + os.pathsep + env['PATH']
            env['HOME'] = fakehome.as_posix()
            env['CRON_CAPTURE'] = (base / 'cron.txt').as_posix()
            result = subprocess.run([BASH, str(repo / 'install/install-unix.sh')], cwd=base, env=env, capture_output=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertTrue((repo / 'logs').is_dir())
            line = (base / 'cron.txt').read_text()
            command = line.split(' * * * * ', 1)[1].replace('\\%', '%')
            result = subprocess.run([BASH, '-c', command], cwd=base, env=env, capture_output=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertFalse((base / 'INJECTED').exists())
