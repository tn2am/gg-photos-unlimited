#!/usr/bin/env python3
"""Collect license notices shipped with the statically linked Go dependencies."""
import json, pathlib, subprocess
raw=subprocess.check_output(['go','list','-deps','-tags','cli','-json','./cmd/bridge'],text=True)
modules={};decoder=json.JSONDecoder()
while raw.strip():
    package,n=decoder.raw_decode(raw.lstrip());raw=raw.lstrip()[n:]
    if 'Module' in package:
        m=package['Module'];modules[m['Path']]=m
parts=['GoToHP / Gunshot third-party notices\nSource: https://github.com/tqmane/gunshot\n']
parts.extend(['Gunshot — Copyright (C) 2026 tqmane', pathlib.Path('LICENSE').read_text()])
parts.extend(['gotohp upstream — MIT License', pathlib.Path('GotohpCore/upstream/LICENSE').read_text()])
goroot=pathlib.Path(subprocess.check_output(['go','env','GOROOT'],text=True).strip())
parts.extend(['Go runtime / standard library', (goroot/'LICENSE').read_text()])
for m in modules.values():
    if m.get('Main'): continue
    directory=pathlib.Path(m.get('Replace',m)['Dir'])
    notices=sorted(p for p in directory.iterdir() if p.is_file() and p.name.upper().startswith(('LICENSE','COPYING','NOTICE')))
    if not notices: raise RuntimeError('Missing license: '+m['Path'])
    parts.append(m['Path']+' '+m.get('Version',''))
    parts.extend(p.name+'\n'+p.read_text() for p in notices)
out=pathlib.Path('.build/ThirdPartyNotices.txt');out.parent.mkdir(exist_ok=True);out.write_text('\n\n'.join(parts))
