#!/usr/bin/env python3
"""png_trim_bottom.py <in.png> <out.png> [pad=40] — 下側の白余白をトリム(PIL不要・純python)。"""
import sys, zlib, struct
def load(path):
    d=open(path,'rb').read(); assert d[:8]==b'\x89PNG\r\n\x1a\n'
    pos=8; idat=b''; w=h=0; ct=None
    while pos<len(d):
        ln=struct.unpack('>I',d[pos:pos+4])[0]; typ=d[pos+4:pos+8]; data=d[pos+8:pos+8+ln]; pos+=12+ln
        if typ==b'IHDR': w,h,_bd,ct=struct.unpack('>IIBB',data[:10])
        elif typ==b'IDAT': idat+=data
    raw=zlib.decompress(idat); bpp={2:3,6:4}[ct]; stride=w*bpp+1
    prev=bytearray(w*bpp); rows=[]; i=0
    for _ in range(h):
        f=raw[i]; line=bytearray(raw[i+1:i+stride]); i+=stride
        for x in range(w*bpp):
            a=line[x-bpp] if x>=bpp else 0; b=prev[x]; c=prev[x-bpp] if x>=bpp else 0
            if f==1: line[x]=(line[x]+a)&255
            elif f==2: line[x]=(line[x]+b)&255
            elif f==3: line[x]=(line[x]+((a+b)>>1))&255
            elif f==4:
                p=a+b-c; pa=abs(p-a); pb=abs(p-b); pc=abs(p-c)
                pr=a if pa<=pb and pa<=pc else (b if pb<=pc else c); line[x]=(line[x]+pr)&255
        rows.append(bytes(line)); prev=line
    return w,h,ct,bpp,rows
def save(path,w,h,ct,rows):
    def chunk(t,data): return struct.pack('>I',len(data))+t+data+struct.pack('>I',zlib.crc32(t+data)&0xffffffff)
    out=b''.join(b'\x00'+r for r in rows)
    open(path,'wb').write(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,ct,0,0,0))+chunk(b'IDAT',zlib.compress(out,9))+chunk(b'IEND',b''))
def main():
    src,dst=sys.argv[1],sys.argv[2]; pad=int(sys.argv[3]) if len(sys.argv)>3 else 40
    w,h,ct,bpp,rows=load(src); last=0
    bg=rows[-1][0:3]  # 背景色=最終行左端(白以外の地色にも対応)
    for y,r in enumerate(rows):
        if any(r[x*bpp:x*bpp+3]!=bg for x in range(0,w,4)): last=y
    nh=min(h,last+pad); save(dst,w,nh,ct,rows[:nh]); print(f"trimmed {w}x{h} -> {w}x{nh}")
if __name__=='__main__': main()
