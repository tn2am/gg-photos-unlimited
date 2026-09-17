#!/usr/bin/env python3
"""Search the archived 7.92.0 instance-method metadata without an IPA or extra packages."""
import argparse, gzip, hashlib, json
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--image',choices=['main','framework','all'],default='all')
p.add_argument('--class-name',default='',help='case-insensitive class-name substring')
p.add_argument('--selector',default='',help='case-insensitive selector substring')
p.add_argument('--classes-only',action='store_true')
p.add_argument('--limit',type=int,default=50,help='0 for all rows')
a=p.parse_args()
if a.limit<0:p.error('--limit must be >= 0')
root=Path(__file__).resolve().parents[1]/'docs/analysis/objc'
manifest=json.loads((root/'manifest.json').read_text());shown=0;matches=0
print('image\tclass\t'+('method_count' if a.classes_only else 'selector\tencoding\tstatic_imp'))
for image in manifest['images']:
 if a.image!='all' and image['image']!=a.image:continue
 raw=(root/image['index']).read_bytes()
 if hashlib.sha256(raw).hexdigest()!=image['indexSHA256']:raise SystemExit('Index hash mismatch: '+image['index'])
 data=json.loads(gzip.decompress(raw))
 for name,methods in data.items():
  if a.class_name.casefold() not in name.casefold():continue
  if a.classes_only:
   if a.selector and not any(a.selector.casefold() in m[0].casefold() for m in methods):continue
   rows=[[str(len(methods))]]
  else:rows=[m for m in methods if a.selector.casefold() in m[0].casefold()]
  for row in rows:
   matches+=1
   if a.limit==0 or shown<a.limit:
    print('\t'.join([image['image'],name,*row]));shown+=1
print(f'# matched={matches} shown={shown}; metadata presence is not semantic/runtime verification')
