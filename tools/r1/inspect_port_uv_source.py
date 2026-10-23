"""Read-only comparison of the owned Blender source to candidate 16."""
import bpy,array,hashlib,json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
def capture():
    meshes={}
    for obj in bpy.context.scene.objects:
        if obj.type!='MESH':continue
        vertices=array.array('f',[0])*(len(obj.data.vertices)*3);obj.data.vertices.foreach_get('co',vertices)
        geometry=vertices.tobytes()+str([list(p.vertices) for p in obj.data.polygons]).encode()+str([list(row) for row in obj.matrix_world]).encode()
        uv={}
        for layer in obj.data.uv_layers:
            values=array.array('f',[0])*(len(layer.data)*2);layer.data.foreach_get('uv',values)
            uv[layer.name]=hashlib.sha256(values.tobytes()).hexdigest()
        meshes[obj.name]={'geometry':hashlib.sha256(geometry).hexdigest(),'uv':uv}
    images={i.name:hashlib.sha256(i.packed_file.data).hexdigest() for i in bpy.data.images if i.source=='FILE'}
    return meshes,images
base=ROOT/'source_art/r1/checkpoints/candidate_16/source_art/r1/west_coast_port.blend'
current=ROOT/'source_art/r1/west_coast_port.blend'
bpy.ops.wm.open_mainfile(filepath=str(base));old,old_images=capture()
bpy.ops.wm.open_mainfile(filepath=str(current));new,new_images=capture()
assert old.keys()==new.keys() and old_images==new_images and len(new)==302 and len(new_images)==27
changed=[]
for name in old:
    assert old[name]['geometry']==new[name]['geometry']
    for layer in old[name]['uv']:
        if old[name]['uv'][layer]!=new[name]['uv'][layer]:
            assert layer=='Source_Facade_Projection' or (name in ['Dock_Mooring_Core','Dock_Mooring_Limestone_Cap'] and layer=='Source_Dock_Masonry')
            assert bpy.data.objects[name].data.uv_layers[layer].active_render
            changed.append({'mesh':name,'layer':layer})
assert len(changed)==78
material=bpy.data.materials['Source_Painted_Facade']
assert material.node_tree.nodes.get('Principled BSDF').inputs['Alpha'].links[0].from_socket.name=='Alpha'
report={'candidate':'R1/17','failed':[],'meshes':len(new),'changed_uv_layers':changed,'geometry_and_world_transforms_unchanged':True,
        'packed_images_unchanged':len(new_images),'facade_pbr_alpha_connected':True,
        'source_sha256':hashlib.sha256(current.read_bytes()).hexdigest(),'qa_source_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'source_modified_by_inspection':False}
(ROOT/'docs/r1_17_blend_source_checks.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({k:v for k,v in report.items() if k!='changed_uv_layers'}))
