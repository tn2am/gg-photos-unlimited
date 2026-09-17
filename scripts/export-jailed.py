#!/usr/bin/env python3
"""Export the same dylib from the injection deb for LiveContainer's tweak importer."""
from pathlib import Path
import shutil, subprocess, tempfile
source=max(Path('Jailed/packages').glob('*.deb'),key=lambda p:p.stat().st_mtime)
out=Path('packages/jailed');out.mkdir(parents=True,exist_ok=True)
shutil.copyfile(source,out/'gotohp-tweak-jailed.deb')
shutil.copyfile('.build/ThirdPartyNotices.txt',out/'ThirdPartyNotices.txt')
with tempfile.TemporaryDirectory() as d:
    subprocess.run(['dpkg-deb','-x',str(source),d],check=True)
    shutil.copyfile(Path(d)/'Library/MobileSubstrate/DynamicLibraries/GunshotJailed.dylib',out/'GunshotJailed.dylib')
