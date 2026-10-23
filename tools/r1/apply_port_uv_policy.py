"""Update existing port UV data and facade cutout without retessellating meshes."""
from pathlib import Path
import math
import json
import struct

SIN=60*math.sin(math.radians(38))
COS=60*math.cos(math.radians(38))


def apply(path):
    raw=path.read_bytes();cursor=12;chunks=[]
    while cursor<len(raw):
        size,kind=struct.unpack_from('<II',raw,cursor);cursor+=8
        payload=raw[cursor:cursor+size];cursor+=size
        if kind==0x4e4f534a:document=json.loads(payload)
        elif kind==0x004e4942:binary=bytearray(payload)
        chunks.append(kind)
    parents={child:i for i,node in enumerate(document['nodes']) for child in node.get('children',[])}
    def world(index,p):
        node=document['nodes'][index]
        # Current owned mesh nodes use translation and scale, with no rotation.
        assert 'matrix' not in node and node.get('rotation',[0,0,0,1])==[0,0,0,1]
        scale=node.get('scale',[1,1,1]);translation=node.get('translation',[0,0,0])
        result=tuple(p[i]*scale[i]+translation[i] for i in range(3))
        return world(parents[index],result) if index in parents else result
    def layout(index,width):
        accessor=document['accessors'][index];assert accessor['componentType']==5126
        view=document['bufferViews'][accessor['bufferView']]
        return accessor,view.get('byteOffset',0)+accessor.get('byteOffset',0),view.get('byteStride',width*4)
    def read(index,width):
        accessor,offset,stride=layout(index,width)
        return [struct.unpack_from('<'+'f'*width,binary,offset+i*stride) for i in range(accessor['count'])]
    edited=set()
    for index,node in enumerate(document['nodes']):
        if 'mesh' not in node:continue
        for primitive in document['meshes'][node['mesh']]['primitives']:
            material=document['materials'][primitive['material']]
            facade=material['name']=='Source_Painted_Facade'
            dock=node['name'] in ['Dock_Mooring_Core','Dock_Mooring_Limestone_Cap']
            if not facade and not dock:continue
            points=[world(index,p) for p in read(primitive['attributes']['POSITION'],3)]
            if facade:
                uv=[((x*60+447)/224,(227.59-y*COS+(z+.42)*SIN)/386) for x,y,z in points]
            else:
                width,height=(13,9) if node['name']=='Dock_Mooring_Core' else (28,7)
                uv=[(x*60/width,1-y*COS/height) for x,y,z in points]
            keys=['TEXCOORD_0'] if facade else ['TEXCOORD_0','TEXCOORD_1']
            for key in keys:
                accessor_index=primitive['attributes'][key]
                if accessor_index in edited:continue
                accessor,offset,stride=layout(accessor_index,2);assert accessor['count']==len(uv)
                for i,value in enumerate(uv):struct.pack_into('<ff',binary,offset+i*stride,*value)
                if 'min' in accessor:accessor['min']=[min(v[i] for v in uv) for i in range(2)]
                if 'max' in accessor:accessor['max']=[max(v[i] for v in uv) for i in range(2)]
                edited.add(accessor_index)
    material=next(m for m in document['materials'] if m['name']=='Source_Painted_Facade')
    material['alphaMode']='MASK';material['alphaCutoff']=.25
    encoded=json.dumps(document,separators=(',',':')).encode();encoded+=b' '*(-len(encoded)%4)
    payload=b''.join(struct.pack('<II',len(value),kind)+value for kind,value in [(0x4e4f534a,encoded),(0x004e4942,bytes(binary))])
    path.write_bytes(struct.pack('<III',0x46546c67,2,12+len(payload))+payload)
    return len(edited)


if __name__=='__main__':
    import argparse
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('path',type=Path)
    print('Updated UV accessors:',apply(parser.parse_args().path))
