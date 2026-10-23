"""Apply the same UV policy to the owned editable model in background Blender."""
import bpy,math,json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
path=ROOT/'source_art/r1/west_coast_port.blend'
bpy.ops.wm.open_mainfile(filepath=str(path))
sin=60*math.sin(math.radians(38));cos=60*math.cos(math.radians(38))
facade=[];dock=[]
for obj in bpy.context.scene.objects:
    if obj.type!='MESH':continue
    layer=obj.data.uv_layers.get('Source_Facade_Projection')
    if layer:
        for loop in obj.data.loops:
            p=obj.matrix_world@obj.data.vertices[loop.vertex_index].co
            layer.data[loop.index].uv=((p.x*60+447)/224,1-(227.59-p.z*cos+(-p.y+.42)*sin)/386)
        layer.active_render=True;facade.append(obj.name)
    if obj.name in ['Dock_Mooring_Core','Dock_Mooring_Limestone_Cap']:
        layer=obj.data.uv_layers['Source_Dock_Masonry'];width,height=(13,9) if obj.name.endswith('Core') else (28,7)
        for loop in obj.data.loops:
            p=obj.matrix_world@obj.data.vertices[loop.vertex_index].co
            layer.data[loop.index].uv=(p.x*60/width,p.z*cos/height)
        layer.active_render=True;dock.append(obj.name)
material=bpy.data.materials['Source_Painted_Facade']
texture=next(n for n in material.node_tree.nodes if n.type=='TEX_IMAGE')
material.node_tree.links.new(texture.outputs['Alpha'],material.node_tree.nodes.get('Principled BSDF').inputs['Alpha'])
material.surface_render_method='DITHERED'
assert len(facade)==76 and len(dock)==2
bpy.ops.wm.save_as_mainfile(filepath=str(path))
print(json.dumps({'facade_uv_meshes':len(facade),'dock_uv_meshes':dock,'facade_alpha_connected':True}))
