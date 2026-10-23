"""Export an explicit, source-backed R2 route whitelist from the 95 client.

Only assets/r2, source_art/r2 and docs/r2_asset_manifest.json are written.
Client programs/scripts are never executed; PVF/IMG data is decoded as data.
"""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import sys

from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/dnf_client_analysis'))
from inspect_clients import PVF,npk_entries,img_frames,decode_frame,binary_ani
from pixel_imports import PROFILE


def digest(data):
    return hashlib.sha256(data).hexdigest()


def file_digest(path):
    value=hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda:stream.read(1024*1024),b''):value.update(chunk)
    return value.hexdigest()


def write_json(path,value):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n')


def write_texture(image,relative):
    path=ROOT/'assets/r2'/relative
    path.parent.mkdir(parents=True,exist_ok=True)
    image.save(path)
    assert Image.open(path).convert('RGBA').tobytes()==image.tobytes()
    # Configure only the new R2 PNGs; the shared configure() scans old manifests.
    sidecar=path.with_suffix('.png.import')
    text='[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[deps]\n\nsource_file="res://'+path.relative_to(ROOT).as_posix()+'"\n\n[params]\n'
    text+='\n'.join(key+'='+value for key,value in PROFILE.items())+'\n'
    sidecar.write_text(text)
    return {'texture':'res://'+path.relative_to(ROOT).as_posix(),
            'width':image.width,'height':image.height,'sha256_png':file_digest(path),
            'sha256_rgba':digest(image.tobytes()),'alpha_range':image.getchannel('A').getextrema()}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--client',type=Path,default=Path('/Users/mac/Downloads/天堂95起源单机客户端'))
    args=parser.parse_args();client=args.client
    pvf=PVF(client/'Script.pvf')
    assert pvf.header['tree_crc_actual']==pvf.header['tree_crc_expected']
    assert not pvf.header['payload_bounds_errors'] and not pvf.header['parse_error']
    specifications=[
        *[('approach/bridge_'+str(i)+'.png','sprite_map_hendonmyre.NPK','sprite/map/hendonmyre/skybridge.img',i) for i in range(4)],
        ('approach/sea.png','sprite_map_hendonmyre.NPK','sprite/map/hendonmyre/skyway.img',9),
        ('approach/wall.png','sprite_map_hendonmyre.NPK','sprite/map/hendonmyre/skyway.img',8),
        ('entrance/tower.png','sprite_map_cataclysm_skytower_towerroad.NPK','sprite/map/cataclysm/skytower/towerroad/tower.img',0),
        ('entrance/gate.png','sprite_map_cataclysm_skytower_towerroad.NPK','sprite/map/cataclysm/skytower/towerroad/pathgatel.img',0),
        ('entrance/far.png','sprite_map_cataclysm_skytower_towerroad.NPK','sprite/map/cataclysm/skytower/towerroad/back_far.img',0),
        ('interior/far.png','sprite_map_act2_amon.NPK','sprite/map/act2/amon/far_dr.img',0),
        *[('interior/wall_'+str(i)+'.png','sprite_map_act2_amon.NPK','sprite/map/act2/amon/200amonnew.img',i) for i in range(6)],
        ('interior/floor.png','sprite_map_act2_amon.NPK','sprite/map/act2/amon/200amonnewex.img',0),
        ('interior/banner.png','sprite_map_act2_amon.NPK','sprite/map/act2/amon/bakalsymbol.img',0),
        ('interior/column.png','sprite_map_act2.NPK','sprite/map/act2/marblestonepillar.img',0),
    ]
    packs={};albums={};frames=[];images={}
    for relative,pack,img,index in specifications:
        if pack not in packs:
            path=client/'ImagePacks2'/pack
            packs[pack]={'path':path,'sha256':file_digest(path),'entries':{item['path']:item for item in npk_entries(path)}}
        key=(pack,img)
        if key not in albums:
            entry=packs[pack]['entries'][img]
            with packs[pack]['path'].open('rb') as stream:
                stream.seek(entry['offset']);raw=stream.read(entry['bytes'])
            albums[key]=(raw,entry)
        raw,entry=albums[key];image,meta=decode_frame(raw,index)
        decoded,_=img_frames(raw);resolved=index;seen=set()
        while 'link' in decoded[resolved]:
            assert resolved not in seen;seen.add(resolved);resolved=decoded[resolved]['link']
        images[relative]=image
        frames.append({**write_texture(image,relative),'role':relative.removesuffix('.png'),
            'original_img_crop':True,'derived_subrect':False,'img_frame':index,'resolved_img_frame':resolved,
            'img_metadata':meta,'source':{'client':'95','npk':pack,'npk_sha256':packs[pack]['sha256'],
                'img':img,'npk_entry_offset':entry['offset'],'payload_bytes':entry['bytes'],'sha256_img_payload':digest(raw)},
            'export':'Exact decoded RGBA crop; no resizing, color/alpha edits or canvas reconstruction.'})
    derived=[]
    for relative,source,rect in [('approach/paving.png','approach/bridge_0.png',(16,120,208,216)),
                                 ('interior/paving.png','interior/floor.png',(16,16,208,112))]:
        image=images[source].crop(rect);assert image.getchannel('A').getextrema()==(255,255)
        item=write_texture(image,relative)
        derived.append({**item,'role':relative.removesuffix('.png'),'original_img_crop':False,'derived_subrect':True,
            'source_texture':'res://assets/r2/'+source,'source_rect_xyxy':rect,
            'export':'Exact RGBA subrectangle of exported source crop; no resampling, rectification or color edits.'})
    references=[
        'dungeon/act2/draconiantower.dgn','map/draconiantower/(2,0)s1601.map',
        'map/draconiantower/tile/skycastledcpoll.til','map/draconiantower/tile/skycastleucpoll.til',
        'map/draconiantower/tile/skycastlepcpoll.til','map/draconiantower/tile/skycastlenpoll.til',
        'map/draconiantower/animation/far1.ani','map/draconiantower/animation/bakalsymbol.ani',
        'map/draconiantower/animation/marblestonepillar.ani','map/hendonmyre/animation/skyfar00.ani',
        'map/hendonmyre/animation/skywall00.ani','map/hendonmyre/animation/skyhouse00.ani',
    ]
    scripts=[]
    for path in references:
        raw,crc=pvf.read(path,True);assert crc['expected']==crc['actual_seed_file_number'],path
        destination=ROOT/'source_art/r2/pvf'/path
        destination.parent.mkdir(parents=True,exist_ok=True);destination.with_suffix(destination.suffix+'.bin').write_bytes(raw)
        item={'path':path,'sha256':digest(raw),'crc':crc,
              'decoded':binary_ani(raw) if path.endswith('.ani') else pvf.tokens(path,'big5')}
        write_json(destination.with_suffix(destination.suffix+'.json'),item);scripts.append(item)
    manifest={'schema':1,'created_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'client':'95','client_directory':str(client),'source_pvf_sha256':file_digest(client/'Script.pvf'),
        'pvf_header':pvf.header,'frames':frames,'derived':derived,
        'roles':{item['role']:item['texture'] for item in frames+derived},'scripts':scripts,'import_profile':PROFILE,
        'notes':['Explicit canonical NPK whitelist; no client code, ACT, SKL or engine behavior executed.',
            'Tower entrance art is explicitly from the95 client cataclysm/skytower namespace; no historical-era identity claim.',
            'Only static frame0 of the tower/gateway is selected; this is not the complete source animation.',
            'Harbor-to-tower route and all new3D depth/navigation are adaptations, not recovered original map layout.',
            'DGN/map scripts supply references only; enemies, damage, quests and full dungeon rules are not implemented.',
            'Source IMG metadata retains crop/canvas offsets. Preview sheets may scale images; exported PNG RGBA is unchanged.']}
    write_json(ROOT/'docs/r2_asset_manifest.json',manifest)
    write_json(ROOT/'source_art/r2/route_asset_reference.json',{'manifest':'docs/r2_asset_manifest.json',
        'manifest_sha256':file_digest(ROOT/'docs/r2_asset_manifest.json'),'source_images':len(frames),'derived_subrects':len(derived),
        'preview_sheets':['work/r2_asset_sheet.png','work/r2_asset_sheet_second.png'],'roles':manifest['roles']})
    print(json.dumps({'source_images':len(frames),'derived_subrects':len(derived),'verified_script_CRCs':len(scripts),
        'rgba_roundtrips':len(frames)+len(derived),'manifest':'docs/r2_asset_manifest.json'}))


if __name__=='__main__':main()
