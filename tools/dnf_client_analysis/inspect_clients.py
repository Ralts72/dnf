"""Read-only DNF NPK/PVF inspection. Never imports or launches client code.

Format references inspected, not executed:
https://github.com/NeroBlackstone/dfo-npk-extractor-bun/tree/c727474f7065f3f4513c8005e3f68158efdd7eec/src
https://github.com/onlyGuo/dnf_parser
This is a limited independent inspection implementation, not a game interpreter.
"""
from pathlib import Path
import collections, gzip, hashlib, json, struct, sys, zlib
import numpy as np

BASE = Path('/Users/mac/Downloads')
OUT = Path('/tmp/dnf_client_analysis')
CLIENTS = {'70': BASE/'DNF复古70客户端', '95': BASE/'天堂95起源单机客户端'}

def save(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2))

def decrypt(data, crc):
    assert len(data)%4 == 0
    words=np.frombuffer(data, dtype='<u4') ^ np.uint32(0x81a79011 ^ crc)
    return ((words >> np.uint32(6)) | (words << np.uint32(26))).tobytes()

class PVF:
    def __init__(self, path):
        self.path=Path(path)
        with self.path.open('rb') as f:
            header=f.read(56)
            assert struct.unpack_from('<I',header)[0]==36
            ver,length,crc,count=struct.unpack_from('<4I',header,40)
            tree=decrypt(f.read(length),crc)
        self.base=56+length
        self.entries={}
        pos=0
        invalid=[]
        parse_error=None
        size=self.path.stat().st_size
        for i in range(count):
            number,n=struct.unpack_from('<II',tree,pos);pos+=8
            if not 0<n<=4096:
                parse_error={'entry':i,'tree_offset':pos-8,'path_length':n}
                break
            name=tree[pos:pos+n].rstrip(b'\0').decode('utf-8','replace').lower();pos+=n
            size_f,crc_f,offset=struct.unpack_from('<III',tree,pos);pos+=12
            e={'path':name,'bytes':size_f,'crc':crc_f,'offset':offset,'number':number}
            if self.base+offset+((size_f+3)&~3)>size:invalid.append(name)
            self.entries[name]=e
        self.header={'version_raw':ver,'tree_bytes':length,'file_count':count,'unique_paths':len(self.entries),'tree_consumed':pos,'tree_padding':length-pos,'tree_crc_expected':crc,'tree_crc_actual':zlib.crc32(tree,count)&0xffffffff,'payload_bounds_errors':invalid,'parse_error':parse_error}
        self.strings=None
    def read(self, name, check=False):
        e=self.entries[name.lower()]
        with self.path.open('rb') as f:
            f.seek(self.base+e['offset']);raw=f.read((e['bytes']+3)&~3)
        d=decrypt(raw,e['crc'])
        if check:
            # CRC schemes in modified clients can differ; report without assuming.
            return d[:e['bytes']], {'expected':e['crc'],'actual_seed_file_number':zlib.crc32(d,e['number'])&0xffffffff,'actual_seed_zero':zlib.crc32(d)&0xffffffff}
        return d[:e['bytes']]
    def load_strings(self):
        data=self.read('stringtable.bin')
        n=struct.unpack_from('<I',data)[0]
        offsets=np.frombuffer(data,dtype='<u4',count=n+1,offset=4)
        assert offsets[-1]+4<=len(data)
        self.strings=[data[4+int(offsets[i]):4+int(offsets[i+1])] for i in range(n)]
        return n
    def tokens(self,name,encoding='gb18030'):
        if self.strings is None:self.load_strings()
        data=self.read(name)
        if not data.startswith(b'\xb0\xd0'):return {'format':'binary','bytes':len(data),'prefix':data[:32].hex()}
        out=[]
        for i in range(2,len(data)-4,5):
            t=data[i];v=struct.unpack_from('<i',data,i+1)[0]
            if t in [5,6,7,8,10] and 0<=v<len(self.strings):
                raw=self.strings[v]
                try:s=raw.decode('utf-8')
                except UnicodeDecodeError:s=raw.decode(encoding,'replace')
                out.append({'type':t,'index':v,'text':s})
            elif t==4:out.append({'type':t,'value':struct.unpack_from('<f',data,i+1)[0]})
            else:out.append({'type':t,'value':v})
        return out

KEY=bytearray(256)
HEAD=b'puchikon@neople dungeon and fighter '
KEY[:len(HEAD)]=HEAD
for _i in range(len(HEAD),255):KEY[_i]=b'DNF'[_i%3]

def npk_entries(path, inspect_headers=True):
    path=Path(path)
    entries=[]
    with path.open('rb') as f:
        h=f.read(20)
        assert h[:16].rstrip(b'\0')==b'NeoplePack_Bill',repr(h)
        n=struct.unpack_from('<I',h,16)[0]
        assert n<100000
        table=f.read(n*264)
        assert len(table)==n*264
        for i in range(n):
            offset,length=struct.unpack_from('<II',table,i*264)
            raw=table[i*264+8:i*264+264]
            name=bytes(a^b for a,b in zip(raw,KEY)).split(b'\0')[0].decode('utf-8','replace').lower()
            assert offset>=20+n*264 and offset+length<=path.stat().st_size
            e={'pack':path.name,'path':name,'offset':offset,'bytes':length}
            if inspect_headers:
                f.seek(offset);b=f.read(min(length,36))
                if b.startswith(b'Neople Img File\0'):
                    index_length,version,count=struct.unpack_from('<QII',b,16)
                    e.update(version=version,frames=count,index_bytes=index_length)
                else:e['signature']=b[:20].hex()
            entries.append(e)
    return entries

def read_album(root, entry):
    with (Path(root)/'ImagePacks2'/entry['pack']).open('rb') as f:
        f.seek(entry['offset']);return f.read(entry['bytes'])

def img_frames(data):
    assert data.startswith(b'Neople Img File\0')
    idx,ver,count=struct.unpack_from('<QII',data,16)
    assert ver in [2,4],ver
    pal=None
    p=32
    if ver==4:
        colors=struct.unpack_from('<I',data,p)[0];p+=4
        assert 0<colors<=65536
        pal=np.frombuffer(data[p:p+colors*4],dtype=np.uint8).reshape(-1,4);p+=colors*4
    index_start=p
    data_pos=p+idx
    frames=[]
    for i in range(count):
        typ=struct.unpack_from('<I',data,p)[0]
        if typ==17:
            target=struct.unpack_from('<I',data,p+4)[0];p+=8
            assert target<count
            frames.append({'link':target});continue
        typ,mode,w,h,length,x,y,fw,fh=struct.unpack_from('<9i',data,p);p+=36
        assert 0<=w<=16384 and 0<=h<=16384
        n=(w*h*(4 if typ==16 else 2)) if mode==5 else length
        assert data_pos+n<=len(data)
        frames.append({'type':typ,'mode':mode,'width':w,'height':h,'x':x,'y':y,'canvas_width':fw,'canvas_height':fh,'data_offset':data_pos,'data_bytes':n,'version':ver})
        data_pos+=n
    assert p==index_start+idx,(p,index_start+idx)
    return frames,pal

def decode_frame(data,index):
    from PIL import Image
    frames,pal=img_frames(data)
    seen=set()
    while 'link' in frames[index]:
        assert index not in seen
        seen.add(index);index=frames[index]['link']
    f=frames[index];n=f['width']*f['height']
    raw=data[f['data_offset']:f['data_offset']+f['data_bytes']]
    if f['mode'] in [6,7]:
        dec=zlib.decompressobj();raw=dec.decompress(raw,max(1,n*4+148))
        assert not dec.unconsumed_tail
    if f['type']==16:
        assert len(raw)==n*4,(len(raw),n)
        rgba=np.frombuffer(raw,dtype=np.uint8).reshape(n,4)[:,[2,1,0,3]].copy()
    elif f['version']==4 and pal is not None and len(raw)==n:
        bgra=pal[np.frombuffer(raw,dtype=np.uint8)];rgba=bgra[:,[2,1,0,3]].copy()
    elif f['type'] in [14,15]:
        v=np.frombuffer(raw,dtype='<u2').astype(np.uint32)
        assert len(v)==n
        if f['type']==14:
            rgba=np.column_stack([np.rint(((v>>10)&31)*255/31),np.rint(((v>>5)&31)*255/31),np.rint((v&31)*255/31),(v>>15)*255]).astype(np.uint8)
        else:
            rgba=np.column_stack([((v>>8)&15)*17,((v>>4)&15)*17,(v&15)*17,((v>>12)&15)*17]).astype(np.uint8)
    else:raise ValueError('Unsupported pixel encoding: '+str(f))
    return Image.fromarray(rgba.reshape(f['height'],f['width'],4),'RGBA'),f

def binary_ani(data):
    pos=0
    def read(fmt):
        nonlocal pos
        vals=struct.unpack_from('<'+fmt,data,pos);pos+=struct.calcsize('<'+fmt)
        return vals[0] if len(vals)==1 else list(vals)
    def string():
        nonlocal pos
        n=read('I');assert n<16384
        s=data[pos:pos+n].rstrip(b'\0').decode('ascii').lower();pos+=n
        return s
    count=read('H');res_count=read('H')
    assert count<10000 and res_count<1000
    resources=[string() for _ in range(res_count)]
    def prop():
        typ=read('H')
        if typ in [0,1,10]:val=read('B')
        elif typ in [3,13,24,26,28]:val=read('H')
        elif typ==7:val=read('ff')
        elif typ==8:val=read('f')
        elif typ==9:val=read('4B')
        elif typ==11:
            val={'effect':read('H')}
            if val['effect']==5:val['rgb']=read('3B')
            elif val['effect']==6:val['pos']=read('2h')
        elif typ in [12,23]:val=read('i')
        elif typ==16:val=string()
        elif typ in [17,25]:val=True
        elif typ==18:val=read('Bii4BH')
        elif typ==27:val=read('4h')
        else:raise ValueError(('unknown ANI property',typ,pos))
        return {'type':typ,'value':val}
    globals=[prop() for _ in range(read('H'))]
    frames=[]
    for _ in range(count):
        boxes=[]
        for __ in range(read('H')):boxes.append({'type':read('H'),'xyz_size':read('6i')})
        rid=read('h');image_frame=read('H') if rid>=0 else -1
        x,y=read('ii');properties=[prop() for __ in range(read('H'))]
        frames.append({'resource':resources[rid] if rid>=0 else None,'image_frame':image_frame,'x':x,'y':y,'boxes':boxes,'properties':properties})
    assert pos==len(data),('trailing ANI data',pos,len(data))
    return {'frames_count':count,'resources':resources,'globals':globals,'frames':frames}

def run():
    all_summary={}
    for key,root in CLIENTS.items():
        dst=OUT/key;dst.mkdir(exist_ok=True)
        print('start',key,flush=True)
        pvf=PVF(root/'Script.pvf')
        save(dst/'pvf_header.json',pvf.header)
        save(dst/'pvf_index.json',list(pvf.entries.values()))
        cats=collections.Counter(e['path'].split('/')[0] for e in pvf.entries.values())
        suffix=collections.Counter(Path(e['path']).suffix for e in pvf.entries.values())
        print(key,'pvf',pvf.header,'categories',cats.most_common(20),flush=True)
        candidates=[p for p in pvf.entries if any(s in p for s in ['westcoast','west_coast','skytower','skycastle','behemoth'])]
        save(dst/'pvf_candidates.json',candidates)
        images=[];errors=[]
        packs=sorted(f for f in (root/'ImagePacks2').iterdir() if f.suffix.lower()=='.npk')
        for j,p in enumerate(packs):
            try:images.extend(npk_entries(p))
            except Exception as e:errors.append({'pack':p.name,'error':str(e)})
        save(dst/'npk_index.json',images)
        vers=collections.Counter(str(i.get('version',i.get('signature'))) for i in images)
        summary={'root':str(root),'pvf':pvf.header,'pvf_categories':dict(cats),'pvf_suffixes':dict(suffix),'image_packs':len(packs),'img_entries':len(images),'img_header_versions':dict(vers),'declared_frames':sum(i.get('frames',0) for i in images),'npk_index_errors':errors,'west_related_pvf_paths':candidates}
        all_summary[key]=summary
        print(key,'npk',len(packs),len(images),vers,'errors',len(errors),flush=True)
    save(OUT/'summary.json',all_summary)

if __name__=='__main__':run()
