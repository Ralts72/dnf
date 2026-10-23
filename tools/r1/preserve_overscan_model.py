"""Append R1/29 scenery to the published R1/28 model without re-exporting it.

Run with Python after build_port_model.py. First-run generated GLB/.blend inputs
are retained in work/; reruns use those captures. Pass --capture-generated right
after a fresh builder run to replace the captures. Blender source assembly runs
only in a separate --background --factory-startup process, never the editor.
"""
from pathlib import Path
import copy
import hashlib
import json
import shutil
import struct
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'source_art/r1/checkpoints/candidate_28'
GLB=ROOT/'assets/r1/models/west_coast_port.glb'
BLEND=ROOT/'source_art/r1/west_coast_port.blend'
GENERATED_GLB=ROOT/'work/r1_29_generated.glb'
GENERATED_BLEND=ROOT/'work/r1_29_generated.blend'
AUDIT=ROOT/'docs/r1_29_model_geometry_checks.json'
ARCHIVE=ROOT/'source_art/r1/experiments/framing_29'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def read_glb(path):
    raw=path.read_bytes();cursor=12;document=None;binary=None
    assert struct.unpack_from('<4sI',raw)==(b'glTF',2)
    while cursor<len(raw):
        length,kind=struct.unpack_from('<II',raw,cursor)
        payload=raw[cursor+8:cursor+8+length];cursor+=8+length
        if kind==0x4e4f534a:document=json.loads(payload)
        elif kind==0x004e4942:binary=payload
    assert document is not None and binary is not None
    assert len(document['buffers'])==1 and 'uri' not in document['buffers'][0]
    return document,binary


def write_glb(path,document,binary):
    binary+=b'\0'*((-len(binary))%4)
    payload=json.dumps(document,separators=(',',':')).encode()
    payload+=b' '*((-len(payload))%4)
    chunks=struct.pack('<II',len(payload),0x4e4f534a)+payload
    chunks+=struct.pack('<II',len(binary),0x004e4942)+binary
    path.write_bytes(struct.pack('<4sII',b'glTF',2,12+len(chunks))+chunks)


def merge_glb():
    original,old_binary=read_glb(BASE/'assets/r1/models/west_coast_port.glb')
    generated,new_binary=read_glb(GENERATED_GLB)
    result=copy.deepcopy(original);binary=bytearray(old_binary)
    materials={item['name']:i for i,item in enumerate(original['materials'])}
    accessors={};views={};meshes={}

    def accessor(index):
        if index not in accessors:
            item=copy.deepcopy(generated['accessors'][index]);assert 'sparse' not in item
            view_index=item['bufferView']
            if view_index not in views:
                view=copy.deepcopy(generated['bufferViews'][view_index]);assert view.get('buffer',0)==0
                offset=view.get('byteOffset',0);payload=new_binary[offset:offset+view['byteLength']]
                binary.extend(b'\0'*((-len(binary))%4))
                view['byteOffset']=len(binary);view['buffer']=0;binary.extend(payload)
                views[view_index]=len(result['bufferViews']);result['bufferViews'].append(view)
            item['bufferView']=views[view_index]
            accessors[index]=len(result['accessors']);result['accessors'].append(item)
        return accessors[index]

    for index,source in enumerate(generated['meshes']):
        if not source['name'].startswith('Overscan_'):continue
        item=copy.deepcopy(source)
        for primitive in item['primitives']:
            assert not primitive.get('targets') and not primitive.get('extensions')
            primitive['attributes']={key:accessor(value) for key,value in primitive['attributes'].items()}
            if 'indices' in primitive:primitive['indices']=accessor(primitive['indices'])
            primitive['material']=materials[generated['materials'][primitive['material']]['name']]
        meshes[index]=len(result['meshes']);result['meshes'].append(item)
    assert len(meshes)==14
    added=[]
    for source in generated['nodes']:
        if source.get('mesh') not in meshes:continue
        assert source['name'].startswith('Overscan_') and not source.get('children')
        assert not any(key in source for key in ['skin','camera'])
        item=copy.deepcopy(source);item['mesh']=meshes[source['mesh']]
        added.append(len(result['nodes']));result['nodes'].append(item)
    assert len(added)==14
    result['scenes'][result.get('scene',0)].setdefault('nodes',[]).extend(added)
    result['buffers'][0]['byteLength']=len(binary)
    write_glb(GLB,result,bytes(binary))


def append_blend():
    import bpy
    bpy.ops.wm.open_mainfile(filepath=str(BASE/'source_art/r1/west_coast_port.blend'))
    old_objects={obj.name:obj for obj in bpy.data.objects}
    old_materials={mat.name:mat for mat in bpy.data.materials}
    old_images=set(bpy.data.images)
    with bpy.data.libraries.load(str(GENERATED_BLEND),link=False) as (source,destination):
        destination.objects=[name for name in source.objects if name.startswith('Overscan_')]
    assert len(destination.objects)==14
    for obj in destination.objects:
        assert obj is not None and obj.type=='MESH'
        bpy.context.scene.collection.objects.link(obj)
        source_name=obj.name.removeprefix('Overscan_Left_').removeprefix('Overscan_Right_')
        # Evaluated source materials may serialize as empty slots. The mirrored
        # polygons retain the source slot indices, so recover the exact slot list
        # from that original object rather than guessing loaded .001 names.
        source=old_objects[source_name]
        obj.data.materials.clear()
        for material in source.data.materials:
            assert material is not None and material.name in old_materials
            obj.data.materials.append(old_materials[material.name])
    for mat in list(bpy.data.materials):
        if mat not in old_materials.values() and mat.users==0:bpy.data.materials.remove(mat)
    for image in list(bpy.data.images):
        if image not in old_images and image.users==0:bpy.data.images.remove(image)
    assert all(bpy.data.objects.get(name)==obj for name,obj in old_objects.items())
    bpy.context.view_layer.update();bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
    manifest=json.loads((ROOT/'source_art/r1/model_manifest.json').read_text())
    manifest.update(objects=len(bpy.context.scene.objects),
                    mesh_faces_before_modifiers=sum(len(obj.data.polygons) for obj in bpy.context.scene.objects if obj.type=='MESH'),
                    blender=bpy.app.version_string,
                    overscan_preservation={'baseline':'source_art/r1/checkpoints/candidate_28',
                        'generator':'tools/r1/preserve_overscan_model.py',
                        'assembly':'Original source objects/materials retained; only14 Overscan objects appended from captured generated source.',
                        'glb_policy':'Original GLB JSON arrays and binary content retained; only new geometry buffers/mesh nodes appended.',
                        'generated_glb_sha256':sha(GENERATED_GLB.read_bytes()),
                        'generated_blend_sha256':sha(GENERATED_BLEND.read_bytes()),
                        'baseline_glb_sha256':sha((BASE/'assets/r1/models/west_coast_port.glb').read_bytes()),
                        'baseline_blend_sha256':sha((BASE/'source_art/r1/west_coast_port.blend').read_bytes()),
                        'glb_sha256':sha(GLB.read_bytes()),'blend_sha256':sha(BLEND.read_bytes())})
    (ROOT/'source_art/r1/model_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')


def audit_glb():
    baseline=BASE/'assets/r1/models/west_coast_port.glb'
    old,old_binary=read_glb(baseline);new,new_binary=read_glb(GLB)
    widths={5120:1,5121:1,5122:2,5123:2,5125:4,5126:4}
    components={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}

    def payload(document,binary,index):
        item=document['accessors'][index];view=document['bufferViews'][item['bufferView']]
        size=widths[item['componentType']]*components[item['type']]
        start=view.get('byteOffset',0)+item.get('byteOffset',0);stride=view.get('byteStride',size)
        return b''.join(binary[start+i*stride:start+i*stride+size] for i in range(item['count']))

    def triangles(document,mesh):
        return sum(document['accessors'][p['indices']]['count']//3 for p in mesh['primitives'])

    rows=[]
    for i,mesh in enumerate(old['meshes']):
        exact=mesh==new['meshes'][i]
        for primitive in mesh['primitives']:
            indices=list(primitive['attributes'].values())+[primitive['indices']]
            exact=exact and all(old['accessors'][j]==new['accessors'][j] and
                payload(old,old_binary,j)==payload(new,new_binary,j) for j in indices)
        rows.append({'mesh':mesh['name'],'pass':exact,'geometry_and_named_material_assignments_exact':exact,
                     'material_semantics_exact':all(old['materials'][p['material']]==new['materials'][p['material']] for p in mesh['primitives'])})
    added=[]
    for mesh in new['meshes'][len(old['meshes']):]:
        points=[point for primitive in mesh['primitives'] for point in
                struct.iter_unpack('<fff',payload(new,new_binary,primitive['attributes']['POSITION']))]
        added.append({'mesh':mesh['name'],'source_x_min':min(p[0] for p in points)*60+448,
                      'source_x_max':max(p[0] for p in points)*60+448,'triangles':triangles(new,mesh)})
    checks=[{'check':'all_original302_mesh_accessor_payloads_and_material_assignments_exact','pass':all(row['pass'] for row in rows)},
            {'check':'all_original39_material_entries_exact','pass':old['materials']==new['materials']},
            {'check':'all_original_node_transforms_and_hierarchy_exact','pass':old['nodes']==new['nodes'][:len(old['nodes'])]},
            {'check':'all_original_accessor_and_bufferView_definitions_exact','pass':all(old[key]==new[key][:len(old[key])] for key in ['accessors','bufferViews'])},
            {'check':'original_binary_chunk_preserved_byte_for_byte','pass':new_binary[:len(old_binary)]==old_binary},
            {'check':'original27_image_definitions_and_payloads_exact','pass':old['images']==new['images'] and new_binary[:len(old_binary)]==old_binary},
            {'check':'only14_visual_overscan_meshes_added','pass':len(added)==14 and all(row['mesh'].startswith('Overscan_') for row in added)},
            {'check':'overscan_extends_source_x_minus160_to1056','pass':abs(min(row['source_x_min'] for row in added)+160)<.0001 and abs(max(row['source_x_max'] for row in added)-1056)<.0001}]
    result={'study':'R1/29 published model preservation and appended overscan audit',
            'before':{'path':str(baseline.relative_to(ROOT)),'sha256':sha(baseline.read_bytes()),'meshes':len(old['meshes']),'triangles':sum(triangles(old,m) for m in old['meshes'])},
            'after':{'path':str(GLB.relative_to(ROOT)),'sha256':sha(GLB.read_bytes()),'meshes':len(new['meshes']),'triangles':sum(triangles(new,m) for m in new['meshes'])},
            'checks':checks,'failed':[row for row in checks if not row['pass']],
            'original_meshes_exact':sum(row['pass'] for row in rows),'original_meshes_changed':[row for row in rows if not row['pass']],
            'original_mesh_checks':rows,'added_mesh_count':len(added),'added_triangles':sum(row['triangles'] for row in added),'added_meshes':added,
            'first_failed_export_audit':str((ARCHIVE/'r1_29_model_geometry_checks_first_export.json').relative_to(ROOT)),
            'source_assembly':'Original baseline .blend plus the14 captured generated Overscan objects; no GLB re-export of old meshes.',
            'notes':['Original GLB arrays retain their original numeric IDs, definitions and binary payloads.','Audit does not establish native framebuffer coverage or runtime performance.']}
    AUDIT.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    assert not result['failed'],result['failed']
    return result


def main():
    if '--append-blend' in sys.argv:
        append_blend();return
    if '--audit-only' not in sys.argv:
        GENERATED_GLB.parent.mkdir(parents=True,exist_ok=True)
        for source,destination in [(GLB,GENERATED_GLB),(BLEND,GENERATED_BLEND)]:
            if '--capture-generated' in sys.argv or not destination.exists():shutil.copy2(source,destination)
        if AUDIT.exists() and json.loads(AUDIT.read_text()).get('failed'):
            ARCHIVE.mkdir(parents=True,exist_ok=True)
            destination=ARCHIVE/'r1_29_model_geometry_checks_first_export.json'
            if not destination.exists():shutil.copy2(AUDIT,destination)
        merge_glb()
        subprocess.run(['/Applications/Blender.app/Contents/MacOS/Blender','--background','--factory-startup','--python-exit-code','1',
                        '--python',str(Path(__file__).resolve()),'--','--append-blend'],check=True)
    result=audit_glb()
    print(json.dumps({'checks':len(result['checks']),'failed':result['failed'],
        'original_meshes_exact':result['original_meshes_exact'],'added_meshes':result['added_mesh_count'],
        'added_triangles':result['added_triangles'],'glb_sha256':result['after']['sha256']}))


if __name__=='__main__':main()
