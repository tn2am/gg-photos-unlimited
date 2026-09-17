#!/usr/bin/env python3
"""macOS integration test: create only our disposable LaunchDaemon, then remove it."""
import getpass
import pathlib
import plistlib
import subprocess
import sys
import tempfile

binary = pathlib.Path(sys.argv[1]).resolve(strict=True)
label = 'dev.tqmane.gunshot.discovery.test'
with tempfile.TemporaryDirectory(prefix='gunshot-launchd-') as tmp:
    path = pathlib.Path(tmp) / (label + '.plist')
    path.write_bytes(plistlib.dumps({
        'Label': label,
        'ProgramArguments': [str(binary), '--serve'],
        'UserName': getpass.getuser(),
        'MachServices': {'dev.tqmane.gunshot.discovery': True},
        'RunAtLoad': True,
    }))
    # launchd requires a root-owned system-domain configuration. The daemon
    # itself runs as the normal CI user, matching gotohpd's UserName model.
    subprocess.run(['sudo', 'chown', 'root:wheel', str(path)], check=True)
    subprocess.run(['sudo', 'chmod', '644', str(path)], check=True)
    loaded = False
    try:
        subprocess.run(['sudo', 'launchctl', 'bootstrap', 'system', str(path)], check=True, timeout=15)
        loaded = True
        subprocess.run([str(binary)], check=True, timeout=20)
    except Exception:
        if loaded:
            subprocess.run(['sudo', 'launchctl', 'print', 'system/' + label], timeout=10)
        raise
    finally:
        if loaded:
            subprocess.run(['sudo', 'launchctl', 'bootout', 'system/' + label], check=True, timeout=15)
