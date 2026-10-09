import sys, struct, zlib, os
def up(x): return (x+2047)&~2047
def load(path):
    d=open(path,'rb').read()
    u=lambda o: struct.unpack_from('>I',d,o)[0]
    assert u(0)==0x51890ACE and u(4)==3, "not a packfile"
    comp=d[0x14F]&1; cond=d[0x14F]&2
    n=u(0x154); names=up(0x800+u(0x15C)); data=up(names+u(0x160))
    ents=[]; stored=data
    for i in range(n):
        e=0x800+i*28; na=names+u(e); end=d.index(b'\0',na)
        name=d[na:end].decode('latin1'); size=u(e+16); ss=u(e+20); at=u(e+8)
        if comp and not cond: at=stored; stored=up(stored+ss)
        ents.append((name,at,size,ss))
    blob=None
    if cond:
        bs=u(0x164)
        blob = zlib.decompressobj(-15).decompress(d[data+2:data+u(0x168)]) if comp else d[data:data+bs]
    def read(e):
        name,at,size,ss=e
        if cond: return blob[at:at+size]
        if comp: return zlib.decompressobj(-15).decompress(d[at+2:at+ss])
        return d[data+at:data+at+size]
    return ents,read
if __name__=='__main__':
    ents,read=load(sys.argv[1])
    if len(sys.argv)>2:
        out=sys.argv[2]; os.makedirs(out,exist_ok=True)
        for e in ents: open(os.path.join(out,e[0]),'wb').write(read(e))
        print("extracted",len(ents))
    else:
        for e in ents: print(e[2],e[0])
