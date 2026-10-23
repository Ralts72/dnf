"""Build the native R1 scene with an independently sized 3D render surface."""
from pathlib import Path
import json
import math
import re
import sys
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/dnf_client_analysis'))
from build_r0_scene import Scene,gd

ELEVATION=math.radians(38)
PPM=60


def vec(v):
    return 'Vector3('+', '.join(f'{n:.8f}' for n in v)+')'


def world(point):
    return [(point[0]-448)/PPM,.025,(point[1]+43-202)/(PPM*math.sin(ELEVATION))-1.6]


def main():
    s=Scene()
    water_reference=json.loads((ROOT/'source_art/r1/water_reference.json').read_text())
    water_uniforms='\n'.join('shader_parameter/'+p['name']+' = Color('+', '.join(str(v/255) for v in p['rgba'])+')'
                             for p in water_reference['palette'])
    mapping=water_reference['mapping']
    for name,point in zip(['shore_start','shore_bend','shore_end'],mapping['near_shore_points']):
        water_uniforms+='\nshader_parameter/'+name+' = Vector2('+', '.join(map(str,point))+')'
    for name in ['far_pier_bounds','middle_pier_bounds']:
        water_uniforms+='\nshader_parameter/'+name+' = Vector4('+', '.join(map(str,mapping[name]))+')'
    water_uniforms+='\nshader_parameter/phase_steps_per_second = '+str(mapping['animation_steps_per_second'])
    root_script=s.resource('res://scripts/west_coast_r1.gd','Script')
    r0=(ROOT/'scenes/west_coast_r0.tscn').read_text()
    s.subresources += re.findall(r'\[sub_resource[^\]]*\][\s\S]*?(?=\n\[|\Z)',r0)
    s.subresources.append('''[sub_resource type="Environment" id="Environment_port"]
background_mode = 0
ambient_light_source = 2
ambient_light_color = Color(0.76, 0.85, 1, 1)
ambient_light_energy = 0.55
reflected_light_source = 1
tonemap_mode = 0
ssao_enabled = true
ssao_radius = 1.2
ssao_intensity = 0.7
ssao_light_affect = 0.08

[sub_resource type="ShaderMaterial" id="Material_water"]
shader = WATER_SHADER
WATER_UNIFORMS

[sub_resource type="PlaneMesh" id="Mesh_water"]
material = SubResource("Material_water")
size = Vector2(18, 4.1)

[sub_resource type="ShaderMaterial" id="Material_contact"]
shader = CONTACT_SHADER

[sub_resource type="PlaneMesh" id="Mesh_contact"]
material = SubResource("Material_contact")
size = Vector2(0.85, 0.48)

[sub_resource type="StandardMaterial3D" id="Material_marker"]
shading_mode = 0
albedo_color = Color(0.05, 0.9, 1, 1)

[sub_resource type="TorusMesh" id="Mesh_marker"]
material = SubResource("Material_marker")
inner_radius = 0.205
outer_radius = 0.23
rings = 24
ring_segments = 6

[sub_resource type="CapsuleShape3D" id="Shape_actor"]
radius = 0.18
height = 1.5

[sub_resource type="BoxShape3D" id="Shape_stones"]
size = Vector3(1.05, 0.42, 0.47)

[sub_resource type="BoxShape3D" id="Shape_stall_sign"]
size = Vector3(0.46, 1.7, 0.14)'''.replace('WATER_SHADER',s.resource('res://shaders/harbor_water.gdshader','Shader'))
        .replace('CONTACT_SHADER',s.resource('res://shaders/contact_shadow.gdshader','Shader'))
        .replace('WATER_UNIFORMS',water_uniforms))
    s.node('WestCoastR1','Node2D',script=root_script)
    s.node('Backdrop','ColorRect','.',offset_right='960.0',offset_bottom='540.0',
           color='Color(0.055, 0.085, 0.12, 1)',mouse_filter='2')
    s.node('PortClip','Control','.',offset_left='32.0',offset_top='62.0',offset_right='928.0',
           offset_bottom='466.0',clip_contents='true',mouse_filter='2')
    s.node('SeaColor','ColorRect','PortClip',offset_right='896.0',offset_bottom='404.0',
           color='Color(0.10, 0.40, 0.60, 1)',mouse_filter='2')
    port=json.loads((ROOT/'data/port_r0.json').read_text())
    mooring=json.loads((ROOT/'source_art/r1/mooring_reference.json').read_text())
    far=port['background'][0]
    s.sprite('Far','PortClip',far['texture'],[0,-37])
    s.subresources.append('''[sub_resource type="ViewportTexture" id="Texture_port"]
resource_local_to_scene = true
viewport_path = NodePath("PortClip/ViewportContainer/Viewport")''')
    s.node('ViewportContainer','TextureRect','PortClip',offset_right='896.0',offset_bottom='404.0',
           texture='SubResource("Texture_port")',expand_mode='1',stretch_mode='0',
           mouse_filter='2',texture_filter='1')
    s.node('Viewport','SubViewport','PortClip/ViewportContainer',size='Vector2i(1792, 808)',
           transparent_bg='true',own_world_3d='true',handle_input_locally='false',
           msaa_3d='2',render_target_update_mode='4')
    base='PortClip/ViewportContainer/Viewport/World'
    s.node('World','Node3D','PortClip/ViewportContainer/Viewport')
    s.node('WorldEnvironment','WorldEnvironment',base,environment='SubResource("Environment_port")')
    camera=[0,.025+math.sin(ELEVATION)*18,-1.6+math.cos(ELEVATION)*18]
    s.node('Camera','Camera3D',base,position=vec(camera),rotation=vec([-ELEVATION,0,0]),
           projection='1',size=str(404/PPM),near='0.05',far='60.0',current='true')
    s.node('Sun','DirectionalLight3D',base,rotation=vec([math.radians(-50),math.radians(-30),0]),
           light_color='Color(1, 0.94, 0.81, 1)',light_energy='0.8',shadow_enabled='true',
           light_angular_distance='1.1',directional_shadow_max_distance='32.0')
    glb=s.resource('res://assets/r1/models/west_coast_port.glb','PackedScene')
    s.nodes.append(f'[node name="PortArchitecture" parent={gd(base)} instance={glb}]')
    s.node('Water','MeshInstance3D',base,position='Vector3(0, -0.30, -0.90)',
           script=s.resource('res://scripts/harbor_water.gd','Script'),
           mesh='SubResource("Mesh_water")',cast_shadow='0')
    s.node('StoneCollision','StaticBody3D',base,position='Vector3(2.99, 0.21, 2.45)')
    s.node('Shape','CollisionShape3D',base+'/StoneCollision',shape='SubResource("Shape_stones")',disabled='true')
    s.node('StallSignCollision','StaticBody3D',base,position='Vector3(-2.42, 0.85, 0.60)')
    s.node('Shape','CollisionShape3D',base+'/StallSignCollision',shape='SubResource("Shape_stall_sign")')
    s.node('SourceProps','Node3D',base)
    foliage={'name':'foliage_top','anchor':[86,-25],
             'sequence':{'frames':[{'duration_ms':1000,'layers':[{
                 'texture':'res://assets/r1/foliage_top.png','offset':[0,0]}]}]}}
    port['objects'].append(foliage)
    for obj in port['objects']:
        if obj['name'] not in ['westnearship','westmmidship','westmid00','foliage_top']:continue
        frame=obj['sequence']['frames'][0]
        image=Image.open(ROOT/frame['layers'][0]['texture'].removeprefix('res://'))
        name=obj['name']
        path=base+'/SourceProps/'+name
        frames=[{'duration_ms':f['duration_ms'],'offset':f['layers'][0]['offset']} for f in obj['sequence']['frames']]
        s.node(name,'Node3D',base+'/SourceProps',
               script=s.resource('res://scripts/billboard_prop.gd','Script'),
               frames='Array[Dictionary]('+gd(frames)+')',
               image_size=f'Vector2({image.width}, {image.height})',
               source_anchor=f'Vector2({obj["anchor"][0]}, {obj["anchor"][1]})',
               view_depth_offset=str(mooring['near_ship_view_depth_offset'] if name=='westnearship' else 0.0),
               position=vec(world(obj['anchor'])))
        offset=frames[0]['offset']
        shift=[offset[0]+image.width/2,-offset[1]-image.height/2]
        pos=[shift[0]/PPM,shift[1]*math.cos(ELEVATION)/PPM,-shift[1]*math.sin(ELEVATION)/PPM]
        s.node('Sprite','Sprite3D',path,texture=s.resource(frame['layers'][0]['texture']),
               position=vec(pos),pixel_size=str(1/PPM),billboard='1',alpha_cut='1',
               alpha_scissor_threshold='0.15',texture_filter='0',shaded='false',cast_shadow='0')
    s.node('Actors','Node3D',base)
    for name,actor,position in [('Sharan','npc_sr',[150,267]),('Lorian','npc_lo',[285,272]),('Swordman','swordman',[440,320])]:
        data=json.loads((ROOT/f'data/{actor}_r1.json').read_text())
        path=base+'/Actors/'+name
        s.node(name,'CharacterBody3D',base+'/Actors',position=vec(world(position)),
               script=s.resource('res://scripts/source_actor_3d.gd','Script'),
               animation_data=gd(f'res://data/{actor}_r1.json'),controllable=str(name=='Swordman').lower(),
               source_position=f'Vector2({position[0]}, {position[1]})')
        frame=data['animations']['stay']['frames'][0]
        shader=s.resource('res://shaders/source_billboard.gdshader','Shader')
        texture=s.resource(frame['texture'])
        s.subresources.append(f'[sub_resource type="ShaderMaterial" id="Material_actor_{name}"]\nshader = {shader}\nshader_parameter/source_texture = {texture}\nshader_parameter/ground_y = 0.025')
        shift=[data['canvas_size'][0]/2-data['foot_anchor'][0],data['foot_anchor'][1]-data['canvas_size'][1]/2]
        s.node('Sprite','Sprite3D',path,position=vec([0,0,0]),offset=f'Vector2({shift[0]}, {shift[1]})',rotation=vec([0,0,0]),
               scale=vec([1,1/math.cos(ELEVATION),1]),texture=texture,
               material_override=f'SubResource("Material_actor_{name}")',
               pixel_size=str(1/PPM),billboard='0',alpha_cut='1',alpha_scissor_threshold='0.25',
               texture_filter='0',cast_shadow='2',shaded='false')
        s.node('Collider','CollisionShape3D',path,position='Vector3(0, 0.75, 0)',shape='SubResource("Shape_actor")')
        s.node('ContactShadow','MeshInstance3D',path,position='Vector3(0, -0.010, 0)',
               mesh='SubResource("Mesh_contact")',cast_shadow='0')
        s.node('FootMarker','MeshInstance3D',path,position='Vector3(0, 0.02, 0)',
               visible='false',mesh='SubResource("Mesh_marker")',cast_shadow='0')
    ui=r0[r0.index('[node name="Interface"'):]
    ui=ui.replace('鬼剑士 · 原图与动作基准','鬼剑士 · 2D 人物 × 3D 港口')
    ui=ui.replace('R0   /   01','R1   /   21').replace('R1 混合 F4','R0 原图 F4')
    s.nodes.append(ui.rstrip())
    s.node('Quality','Button','Interface',text=gd('清晰 F6'),
           offset_left='572.0',offset_top='17.0',offset_right='644.0',offset_bottom='44.0',
           theme='SubResource("Theme_r0")',focus_mode='0')
    s.save('scenes/west_coast_r1.tscn')
    print('Saved scenes/west_coast_r1.tscn; true 3D architecture, source billboards, fixed camera.')


if __name__=='__main__':main()
