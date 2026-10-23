"""Read both saved sources in a separate background Blender, without saving."""
import bpy
import array
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'source_art/r1/checkpoints/candidate_14/source_art/r1/west_coast_port.blend'
CURRENT = ROOT / 'source_art/r1/west_coast_port.blend'


def fingerprint():
    result = {}
    for obj in bpy.context.scene.objects:
        if obj.type != 'MESH': continue
        vertices = array.array('f', [0]) * (len(obj.data.vertices) * 3)
        obj.data.vertices.foreach_get('co', vertices)
        data = vertices.tobytes() + str([list(p.vertices) for p in obj.data.polygons]).encode()
        for layer in obj.data.uv_layers:
            uv = array.array('f', [0]) * (len(layer.data) * 2)
            layer.data.foreach_get('uv', uv)
            data += layer.name.encode() + uv.tobytes()
        data += str([list(row) for row in obj.matrix_world]).encode()
        result[obj.name] = hashlib.sha256(data).hexdigest()
    return result


bpy.ops.wm.open_mainfile(filepath=str(BASE))
before = fingerprint()
bpy.ops.wm.open_mainfile(filepath=str(CURRENT))
after = fingerprint()
assert before == after
material = bpy.data.materials['Source_Painted_Stall']
nodes = material.node_tree.nodes
output = nodes.get('Material Output')
mix = output.inputs['Surface'].links[0].from_node
assert mix.type == 'MIX_SHADER'
assert mix.inputs[0].links[0].from_socket.name == 'Alpha'
assert mix.inputs[1].links[0].from_node.type == 'BSDF_TRANSPARENT'
assert mix.inputs[2].links[0].from_socket.name == 'Color'
image = mix.inputs[2].links[0].from_node.image
assert image.size[:] == (443, 230) and image.packed_file
projected = [o for o in bpy.context.scene.objects if o.type == 'MESH' and o.data.uv_layers.get('Source_Stall_Projection')]
assert len(projected) == 13 and all(o.data.uv_layers['Source_Stall_Projection'].active_render for o in projected)
images = [i for i in bpy.data.images if i.source == 'FILE']
assert len(images) == 27 and all(i.packed_file for i in images)
report = {'candidate': 'R1/15', 'baseline': 'R1/14', 'failed': [],
          'mesh_fingerprints_identical': before == after, 'meshes': len(after),
          'fingerprint_covers': ['vertices', 'polygon_indices', 'all_uv_layers', 'world_transforms'],
          'editable_stall_uses_unlit_alpha_graph': True, 'packed_images': len(images),
          'all_thirteen_meshes_select_projected_uv': True,
          'source_sha256': hashlib.sha256(CURRENT.read_bytes()).hexdigest(),
          'script_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
          'source_modified_by_inspection': False}
(ROOT / 'docs/r1_15_blend_checks.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report))
