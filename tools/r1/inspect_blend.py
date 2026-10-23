"""Read-only source integrity check inside background Blender."""
import bpy,json,hashlib
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
lamp_volumes=[]
for obj in bpy.context.scene.objects:
    if not obj.name.startswith('Pier_Lamp_'):continue
    obj.data.calc_loop_triangles()
    volume=sum(obj.data.vertices[t.vertices[0]].co.dot(
        obj.data.vertices[t.vertices[1]].co.cross(obj.data.vertices[t.vertices[2]].co))/6
        for t in obj.data.loop_triangles)
    lamp_volumes.append(volume)
images=[]
for image in bpy.data.images:
    if image.source!='FILE':continue
    path=Path(bpy.path.abspath(image.filepath))
    packed=bool(image.packed_file)
    images.append({'name':image.name,'packed':packed,'external_exists':path.exists(),
                   'size':list(image.size),'available':packed or path.exists()})
report={'blender':bpy.app.version_string,'source':bpy.data.filepath,
        'source_blend_sha256':hashlib.sha256(Path(bpy.data.filepath).read_bytes()).hexdigest(),
        'inspection_script_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'scene':bpy.context.scene.name,'mesh_objects':len([o for o in bpy.context.scene.objects if o.type=='MESH']),
        'images':images,'missing_images':[i['name'] for i in images if not i['available']],
        'projected_uv_exists':bool(bpy.data.objects['Curved_Plaster_Facade'].data.uv_layers.get('Source_Facade_Projection')),
        'paving_uv_exists':bool(bpy.data.objects['Terracotta_Diamond_Paving'].data.uv_layers.get('Rectified_Source_Stone')),
        'stall_uv_exists':bool(bpy.data.objects.get('Stall_Canopy') and bpy.data.objects['Stall_Canopy'].data.uv_layers.get('Source_Stall_Projection')),
        'shore_uv_exists':bool(bpy.data.objects.get('Pier_Far_Slab') and bpy.data.objects['Pier_Far_Slab'].data.uv_layers.get('Raw_Source_Pier_Masonry')),
        'near_shore_diagonal_caps':len([o for o in bpy.context.scene.objects if o.name.startswith('Quay_Coping_Diagonal')]),
        'grove_canopy_uv_exists':bool(bpy.data.objects.get('Grove_Source_Canopy') and bpy.data.objects['Grove_Source_Canopy'].data.uv_layers.get('Source_Grove_Canopy_Pixels')),
        'grove_trunk_meshes':len([o for o in bpy.context.scene.objects if o.name.startswith('Grove_Tree_') and '_Trunk_' in o.name]),
        'dock_meshes':len([o for o in bpy.context.scene.objects if o.name.startswith('Dock_')]),
        'dock_wood_uv_exists':bool(bpy.data.objects.get('Dock_Barrel_Left_Body') and bpy.data.objects['Dock_Barrel_Left_Body'].data.uv_layers.get('Source_Dock_Wood_Staves')),
        'lamp_meshes':len([o for o in bpy.context.scene.objects if o.name.startswith('Pier_Lamp_')]),
        'lamp_uv_exists':all(o.data.uv_layers.get('Source_Lamp_Cylindrical') for o in bpy.context.scene.objects if o.name.startswith('Pier_Lamp_')),
        'lamp_positive_signed_volumes':sum(v>0 for v in lamp_volumes),
        'source_modified':False}
(ROOT/'docs/r1_blend_source_check.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(report,ensure_ascii=False))
assert not report['missing_images']
assert report['projected_uv_exists'] and report['paving_uv_exists']
assert report['stall_uv_exists']
assert report['shore_uv_exists'] and report['near_shore_diagonal_caps']>0
assert report['grove_canopy_uv_exists'] and report['grove_trunk_meshes']==9
assert report['dock_meshes']==17 and report['dock_wood_uv_exists']
assert report['lamp_meshes']==42 and report['lamp_uv_exists']
assert report['lamp_positive_signed_volumes']==42
