#!/usr/bin/env python3
"""Extract the instance-method lists used by the provided 7.20.2 / 7.92.0 analysis indexes.
Not a general Swift/C++ decompiler; rejects unsupported input rather than emitting partial output.
"""
import struct,pathlib,json,sys
if len(sys.argv)!=3: raise SystemExit("usage: extract-objc-metadata.py MACHO OUTPUT.json")
b=pathlib.Path(sys.argv[1]).read_bytes();u32=lambda o:struct.unpack_from('<I',b,o)[0];u64=lambda o:struct.unpack_from('<Q',b,o)[0]
if u32(0)!=0xfeedfacf or u32(4)!=0x100000c: raise SystemExit("expected thin little-endian arm64 Mach-O")
segs=[];sects=[];o=32
for i in range(u32(16)):
 cmd,size=struct.unpack_from('<II',b,o)
 if cmd==0x19:
  name=b[o+8:o+24].split(b'\0')[0].decode();vm,vs,fo,fs=struct.unpack_from('<QQQQ',b,o+24);segs.append((name,vm,vs,fo,fs))
  for j in range(u32(o+64)):
   s=o+72+j*80; sn=b[s:s+16].split(b'\0')[0].decode();a,z,off=struct.unpack_from('<QQI',b,s+32);sects.append((sn,a,z,off))
 o+=size

def offset(p):
 for n,v,s,f,fs in segs:
  if v<=p<v+fs:return f+p-v
 # chained offset pointers
 p=(p&0xfffffffff)+next(v for n,v,s,f,fs in segs if n=="__TEXT")
 for n,v,s,f,fs in segs:
  if v<=p<v+fs:return f+p-v
 raise ValueError(hex(p))
def cs(p):
 o=offset(p);return b[o:b.index(b'\0',o)].decode(errors='replace')
def methods(p):
 if not p:return []
 o=offset(p);flags=u32(o);n=u32(o+4);small=bool(flags&0x80000000);direct=bool(flags&0x40000000);step=flags&0xffff
 out=[]
 for i in range(n):
  x=o+8+i*step
  if small:
   # relative field virtual address = pointer (unencoded) + local delta
   base=next(v+x-f for _,v,s,f,fs in segs if f<=x<f+fs)
   namep=base+struct.unpack_from('<i',b,x)[0];namep=namep if direct else u64(offset(namep))
   typep=base+4+struct.unpack_from('<i',b,x+4)[0]
   imp=base+8+struct.unpack_from('<i',b,x+8)[0]
  else:namep,typep,imp=struct.unpack_from('<QQQ',b,x)
  out.append((cs(namep),cs(typep),hex(imp)))
 return out
out={}
for sn,a,z,off in sects:
 if sn!='__objc_classlist':continue
 for x in range(off,off+z,8):
  try:
   c=offset(u64(x));ro=offset(u64(c+32)&~7);name=cs(u64(ro+24));m=methods(u64(ro+32));out[name]=m
  except Exception as e:raise RuntimeError(f'Cannot parse class at file offset {x:#x}') from e

pathlib.Path(sys.argv[2]).write_text(json.dumps(out,ensure_ascii=False,sort_keys=True,separators=(",",":")))
print(f"classes={len(out)} methods={sum(map(len,out.values()))}")
