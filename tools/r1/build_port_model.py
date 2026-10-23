"""Run in a NEW background Blender process; never edits the interactive scene.

Blender --background --factory-startup --python tools/r1/build_port_model.py
Coordinates below are Godot coordinates: X horizontal, Y up, Z towards camera.
"""
import bpy
import math
import random
import json
import struct
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'source_art/r1'
EXPORT = ROOT / 'assets/r1/models'
OUT.mkdir(parents=True, exist_ok=True)
EXPORT.mkdir(parents=True, exist_ok=True)
rng = random.Random(231023)
reference = json.loads((OUT/'facade_reference.json').read_text())
shore_reference = json.loads((OUT/'shore_reference.json').read_text())
grove_reference = json.loads((OUT/'grove_reference.json').read_text())
mooring_reference = json.loads((OUT/'mooring_reference.json').read_text())
lamp_reference = json.loads((OUT/'lamp_reference.json').read_text())
SHORE_SIN = 60 * math.sin(math.radians(38))
SHORE_COS = 60 * math.cos(math.radians(38))
shore_x0 = (449 - 448) / 60
shore_x1 = (673 - 448) / 60
shore_width = shore_reference['measurements']['coping_width_source_pixels'] / SHORE_SIN


def shore_source_point(x, y, height=.025):
    return ((x-448)/60, height, (y-159+(height-.025)*SHORE_COS)/SHORE_SIN-1.6)


def near_edge_z(x, inner=True):
    t=max(0,min(1,(x-shore_x0)/(shore_x1-shore_x0)))
    return shore_source_point(448,190+64*t)[2]+(shore_width if inner else 0)

# This factory-startup process owns its scene. The user's unsaved Blender scene is untouched.
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
bpy.context.scene.name = 'WestCoast_R1_Architecture'
bpy.context.scene.unit_settings.system = 'METRIC'


def point(p):
    return p[0], -p[2], p[1]


def linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + .055) / 1.055) ** 2.4


def material(name, color, roughness=.9, metallic=0):
    m = bpy.data.materials.new(name)
    rgb = tuple(linear(int(color[i:i+2], 16)/255) for i in (1, 3, 5))
    m.diffuse_color = (*rgb, 1)
    m.use_nodes = True
    node = m.node_tree.nodes.get('Principled BSDF')
    node.inputs['Base Color'].default_value = (*rgb, 1)
    node.inputs['Roughness'].default_value = roughness
    node.inputs['Metallic'].default_value = metallic
    return m


plaster = material('Plaster_Ivory', '#e1d9b8')
plaster_light = material('Plaster_Highlight', '#eee5c9')
stone = material('Sandstone_Edges', '#c8b58c')
stone_light = material('Sandstone_Coping', '#dfcda6')
stone_dark = material('Sandstone_Crevice', '#9e9478')
blue = [material('Door_Blue_%d' % i, c) for i, c in enumerate(['#3a7793','#49869f','#427d96','#578ca2'])]
wood_dark = material('Door_Wood_Dark', '#31586a')
iron = material('Aged_Bronze', '#9d916b', .62, .3)
iron_dark = material('Iron_Dark', '#3a5359', .7, .3)
terracotta = [material('Paving_Clay_%d' % i, c) for i,c in enumerate(
    ['#c89c7c','#d6a985','#e0b58b','#d0a17c','#d9ad88','#c79b78','#dfb38e','#d4a681'])]
mortar = material('Paving_Grout', '#a6886b')
quay = material('Quay_Limestone', '#dbd4ba')
rope = material('Harbour_Rope', '#bda77c')
leaves = [material('Leaf_%d'%i,c) for i,c in enumerate(['#52744a','#698750','#839b5b'])]


def shore_material(name,path):
    mat=material(name,'#ffffff',.95)
    tex=mat.node_tree.nodes.new('ShaderNodeTexImage')
    tex.image=bpy.data.images.load(str(ROOT/path));tex.interpolation='Closest'
    mat.node_tree.links.new(tex.outputs['Color'],mat.node_tree.nodes.get('Principled BSDF').inputs['Base Color'])
    return mat


coping_mat=shore_material('Source_Quay_Coping','assets/r1/quay_coping.png')
pier_top_mat=shore_material('Source_Pier_Top','assets/r1/pier_top.png')
pier_face_mat=shore_material('Source_Pier_Face','assets/r1/pier_face.png')
lamp_materials={name:shore_material('Source_Lamp_'+name.title(),'assets/r1/lamp_'+name+'.png')
                for name in ['blue','glass','shaft','collar']}
painted = material('Source_Painted_Facade', '#ffffff', .95)
image_node = painted.node_tree.nodes.new('ShaderNodeTexImage')
image_node.image = bpy.data.images.load(str(ROOT/reference['source_texture']))
image_node.interpolation = 'Closest'
image_node.extension = 'EXTEND'
painted.node_tree.links.new(image_node.outputs['Color'],painted.node_tree.nodes.get('Principled BSDF').inputs['Base Color'])
painted.node_tree.links.new(image_node.outputs['Alpha'],painted.node_tree.nodes.get('Principled BSDF').inputs['Alpha'])
painted.surface_render_method='DITHERED'
painted.node_tree.links.new(image_node.outputs['Color'],painted.node_tree.nodes.get('Principled BSDF').inputs['Emission Color'])
painted.node_tree.nodes.get('Principled BSDF').inputs['Emission Strength'].default_value=.15
for mat,item in zip(terracotta,reference['paving_rectification']):
    node=mat.node_tree.nodes.new('ShaderNodeTexImage')
    node.image=bpy.data.images.load(str(ROOT/item['output']))
    node.interpolation='Closest'
    mat.node_tree.links.new(node.outputs['Color'],mat.node_tree.nodes.get('Principled BSDF').inputs['Base Color'])


def mesh(name, verts, faces, mats, indices=None, bevel=0):
    data = bpy.data.meshes.new(name)
    data.from_pydata([point(v) for v in verts], [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    for mat in mats:
        data.materials.append(mat)
    if indices:
        for polygon, index in zip(data.polygons, indices):
            polygon.material_index = index
    if bevel:
        mod = obj.modifiers.new('Soft worn corners', 'BEVEL')
        mod.width = bevel
        mod.segments = 2
    return obj


BOX_FACES = [(0,1,2,3),(4,7,6,5),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)]


def box(name, center, size, mat, bevel=.015):
    x,y,z = center
    a,b,c = [v/2 for v in size]
    verts = [(x-a,y-b,z-c),(x+a,y-b,z-c),(x+a,y-b,z+c),(x-a,y-b,z+c),
             (x-a,y+b,z-c),(x+a,y+b,z-c),(x+a,y+b,z+c),(x-a,y+b,z+c)]
    return mesh(name, verts, BOX_FACES, [mat], bevel=bevel)


def extruded_outline(name, outline, zfront, depth, mat, bevel=.01):
    n=len(outline)
    verts=[(x,y,z) for z in (zfront-depth,zfront) for x,y in outline]
    faces=[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]
    faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    return mesh(name,verts,faces,[mat],bevel=bevel)


def arch_outline(cx, radius, spring, bottom=0, segments=28):
    outline=[(cx-radius,bottom),(cx+radius,bottom),(cx+radius,spring)]
    outline += [(cx+radius*math.cos(t),spring+radius*math.sin(t))
                for t in [math.pi*i/segments for i in range(1,segments+1)]]
    return outline


def arch_frame(name,cx,r,spring,width,z,depth,mat,bottom=0):
    # Individual voussoirs keep the arch readable at the fixed game camera.
    for i in range(17):
        a=math.pi*i/17+.006
        b=math.pi*(i+1)/17-.006
        outline=[(cx+r*math.cos(a),spring+r*math.sin(a)),
                 (cx+(r+width)*math.cos(a),spring+(r+width)*math.sin(a)),
                 (cx+(r+width)*math.cos(b),spring+(r+width)*math.sin(b)),
                 (cx+r*math.cos(b),spring+r*math.sin(b))]
        extruded_outline(name+'_keystone_%02d'%i,outline,z,depth,mat,.012)
    for side in [-1,1]:
        for i in range(7):
            box(name+'_jamb_%d_%d'%(side,i),(cx+side*(r+width/2),bottom+(i+.5)*(spring-bottom)/7,z-depth/2),
                (width,(spring-bottom)/7-.008,depth),mat,.015)


# A softly curved plaster facade, based on westtile00's large blue gate and flowing parapet.
door_x=-6.25
radius=.46
spring=2.0
front=-.42
left=-7.45
right=-3.7166667
def roof(x):
    pixel=max(0,min(223,x*60+447));a=int(pixel);b=min(a+1,223)
    value=reference['profile_smoothed_pixels'][a]*(1-(pixel-a))+reference['profile_smoothed_pixels'][b]*(pixel-a)
    return (227.59-value)/47.2806452164

# Build facade strips above the arch without boolean scars.
xs=sorted(set([left,right,door_x-radius,door_x+radius]+[left+(right-left)*i/80 for i in range(81)]))
verts=[];faces=[]
for x1,x2 in zip(xs,xs[1:]):
    def lower(x):
        return spring+math.sqrt(max(0,radius*radius-(x-door_x)**2)) if abs(x-door_x)<radius else 0.0
    # Separate strips avoid a horizontal seam crossing the top of the arch.
    low1=lower(x1+1e-7);low2=lower(x2-1e-7)
    n=len(verts)
    verts += [(x1,low1,front),(x2,low2,front),(x2,roof(x2),front),(x1,roof(x1),front),
              (x1,low1,front-.38),(x2,low2,front-.38),(x2,roof(x2),front-.38),(x1,roof(x1),front-.38)]
    faces += [tuple(n+j for j in f) for f in [(0,1,2,3),(7,6,5,4),(0,4,5,1),(3,2,6,7)]]
facade=mesh('Curved_Plaster_Facade',verts,faces,[plaster],bevel=0)
box('Facade_Left_Return',(-7.41,1.95,-1.6),(.25,3.9,2.7),plaster,.04)
box('Facade_Right_Return',(-3.76,1.35,-1.45),(.25,2.7,2.1),plaster,.04)

# Curved coping as a continuous strip (no generic pitched roof).
verts=[];faces=[]
for i in range(81):
    x=left+(right-left)*i/80;y=roof(x)
    verts.extend([(x,y-.03,front+.055),(x,y+.10,front+.055),
                  (x,y-.03,front-.15),(x,y+.10,front-.15)])
    if i:
        a=(i-1)*4;b=i*4
        faces.extend([(a,b,b+1,a+1),(a+1,b+1,b+3,a+3),(a+2,a+3,b+3,b+2)])
coping=mesh('Worn_Curved_Coping',verts,faces,[plaster_light])
for polygon in coping.data.polygons:polygon.use_smooth=True

extruded_outline('Gate_Dark_Recess',arch_outline(door_x,radius+.015,spring),front-.055,.08,wood_dark)
# Individually fitted blue planks follow the arch profile.
for i in range(10):
    x1=door_x-radius+i*(2*radius/10)+.006
    x2=x1+2*radius/10-.012
    y1=spring+math.sqrt(max(0,radius**2-(x1-door_x)**2))
    y2=spring+math.sqrt(max(0,radius**2-(x2-door_x)**2))
    extruded_outline('Blue_Gate_Plank_%02d'%i,[(x1,.035),(x2,.035),(x2,y2-.02),(x1,y1-.02)],
                      front-.025,.06,blue[i%4],.009)
arch_frame('Gate_Stone_Arch',door_x,radius+.015,spring,.09,front+.055,.16,plaster_light)
for x in [door_x-.12,door_x+.12]:
    box('Gate_Handle_Plate',(x,1.18,front+.04),(.055,.17,.025),iron,.008)

# Window with a deep opening and a rounded rim.
wx=-4.95
extruded_outline('Small_Arch_Window_Shadow',arch_outline(wx,.22,1.7,.95),front+.009,.015,wood_dark)
arch_frame('Small_Window_Stone',wx,.22,1.7,.075,front+.08,.11,stone_light,bottom=.95)
for i in range(3):
    box('Window_Bar_%d'%i,(wx-.14+i*.14,1.35,front+.10),(.025,.65,.025),iron_dark,.005)
box('Window_Sill',(wx,.95,front+.10),(.68,.10,.23),stone_light,.028)

# Foundation courses, irregular exposed stones and door step.
for i in range(18):
    x=left+(i+.5)*(right-left)/18
    if abs(x-door_x)<radius+.18:continue
    box('Foundation_%02d'%i,(x,.095,front+.025),(.34,.19,.09),stone if i%3 else stone_light,.018)
for i in range(7):
    x=rng.uniform(-4.4,-3.9);y=rng.uniform(.35,1.05)
    box('Exposed_Plaster_Stone_%02d'%i,(x,y,front+.012),(rng.uniform(.12,.25),.08,.016),stone_light,.014)
box('Blue_Gate_Threshold',(door_x,.025,front+.16),(1.15,.05,.32),quay,.025)

# UV projection preserves the painted facade on the new, editable geometry.
prefixes=('Curved_Plaster','Gate_Stone_Arch','Blue_Gate_Plank','Gate_Dark_Recess',
          'Small_Window','Small_Arch_Window','Window_Sill')
for obj in list(bpy.context.scene.objects):
    if obj.type!='MESH' or not obj.name.startswith(prefixes):continue
    obj.data.materials.clear();obj.data.materials.append(painted)
    uv=obj.data.uv_layers.new(name='Source_Facade_Projection')
    uv.active_render=True
    bpy.context.view_layer.update()
    for loop in obj.data.loops:
        p=obj.matrix_world@obj.data.vertices[loop.vertex_index].co
        # Blender coordinates are (world X, -world Z, world Y).
        px=p.x*60+447;py=227.59-p.z*SHORE_COS+(-p.y-front)*SHORE_SIN
        uv.data[loop.index].uv=(px/224,1-py/386)
    obj['reference_png']=reference['source_texture']
    obj['uv_rule']='Source image projected at fixed R0 camera scale; depth is new geometry'

# Paving is a single mesh with many lightly bevelled clay tiles (few draw calls).
verts=[];faces=[];indices=[];vertex_uv=[]
tile=.50
angle=math.pi/4
co=math.cos(angle);si=math.sin(angle)
def clip_polygon(poly,axis,value,greater):
    result=[]
    for a,b in zip(poly,poly[1:]+poly[:1]):
        ia=a[axis]>=value if greater else a[axis]<=value
        ib=b[axis]>=value if greater else b[axis]<=value
        if ia:result.append(a)
        if ia!=ib:
            t=(value-a[axis])/(b[axis]-a[axis])
            result.append((a[0]+t*(b[0]-a[0]),a[1]+t*(b[1]-a[1])))
    return result


def clip_shore(poly):
    result=[]
    for a,b in zip(poly,poly[1:]+poly[:1]):
        da=a[1]-near_edge_z(a[0]);db=b[1]-near_edge_z(b[0])
        if da>=-1e-9:result.append(a)
        if (da>=0)!=(db>=0):
            t=da/(da-db)
            result.append((a[0]+t*(b[0]-a[0]),a[1]+t*(b[1]-a[1])))
    return result
for ix in range(-28,29):
    for iz in range(-28,29):
        cx=(ix+iz)*tile*co;cz=(iz-ix)*tile*si*.74+1.1
        if not (-8.5<cx<8.5 and -2.2<cz<5.7):continue
        half=(tile-.023)/2
        corners=[]
        for dx,dz in [(-half,-half),(half,-half),(half,half),(-half,half)]:
            corners.append((cx+dx*co-dz*si,cz+(dx*si+dz*co)*.74))
        mat_index=rng.randrange(len(terracotta));height=rng.uniform(.002,.012)
        for xmin,xmax,zmin,zmax in [(-8.5,shore_x0,-2.2,5.7),(shore_x0,shore_x1,-2.2,5.7),(shore_x1,8.5,-2.2,5.7)]:
            poly=corners[:]
            for axis,value,greater in [(0,xmin,True),(0,xmax,False),(1,zmin,True),(1,zmax,False)]:
                if poly:poly=clip_polygon(poly,axis,value,greater)
            if poly:poly=clip_shore(poly)
            if len(poly)<3:continue
            n=len(verts);count=len(poly)
            verts += [(x,y,z) for y in (-.085,height) for x,z in poly]
            for _ in range(2):
                for x,z in poly:
                    dx=x-cx;dz=(z-cz)/.74
                    u=((dx*co+dz*si)+half)/(2*half)
                    v=1-((-dx*si+dz*co)+half)/(2*half)
                    vertex_uv.append((u,v))
            faces += [tuple(n+i for i in range(count)),tuple(n+count+i for i in reversed(range(count)))]
            faces += [(n+i,n+count+i,n+count+(i+1)%count,n+(i+1)%count) for i in range(count)]
            indices += [mat_index]*(2+count)
paving=mesh('Terracotta_Diamond_Paving',verts,faces,terracotta,indices,bevel=.006)
uv=paving.data.uv_layers.new(name='Rectified_Source_Stone')
for loop in paving.data.loops:
    uv.data[loop.index].uv=vertex_uv[loop.vertex_index]
bed_outline=[(-8.5,near_edge_z(-8.5)),(shore_x0,near_edge_z(shore_x0)),
             (shore_x1,near_edge_z(shore_x1)),(8.5,near_edge_z(8.5)),(8.5,5.7),(-8.5,5.7)]
n=len(bed_outline)
bed_verts=[(x,y,z) for y in (-.15,-.055) for x,z in bed_outline]
bed_faces=[tuple(range(n)),tuple(range(n,2*n))[::-1]]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
mesh('Mortar_Bed_Shore_Polygon',bed_verts,bed_faces,[mortar])

# Measured diagonal near shore. Caps occupy nonoverlapping x intervals and a
# fourteen-source-pixel strip; their textures exclude baked foreground props.
for name,start,end in [('Left',-8.5,shore_x0),('Diagonal',shore_x0,shore_x1),('Front',shore_x1,8.5)]:
    count=math.ceil(math.hypot(end-start,near_edge_z(end)-near_edge_z(start))/.48)
    for i in range(count):
        x0=start+(end-start)*i/count+.006
        x1=start+(end-start)*(i+1)/count-.006
        outline=[(x0,near_edge_z(x0,False)),(x1,near_edge_z(x1,False)),
                 (x1,near_edge_z(x1)),(x0,near_edge_z(x0))]
        vertices=[(x,y,z) for y in (-.035,.065) for x,z in outline]
        cap=mesh('Quay_Coping_%s_%02d'%(name,i),vertices,BOX_FACES,[coping_mat],bevel=.009)
        uv=cap.data.uv_layers.new(name='Raw_Source_Coping')
        for loop in cap.data.loops:
            p=vertices[loop.vertex_index]
            uv.data[loop.index].uv=(p[0]*60/94,1-(p[2]-near_edge_z(p[0],False))/shore_width)
    # Water-facing support extends below the water plane, without a floating lip.
    outline=[(start,near_edge_z(start,False)),(end,near_edge_z(end,False)),
             (end,near_edge_z(end,False)+.08),(start,near_edge_z(start,False)+.08)]
    mesh('Quay_Retaining_Wall_'+name,[(x,y,z) for y in (-.58,-.035) for x,z in outline],BOX_FACES,[stone])


def pier_slab(name,outline):
    n=len(outline)
    vertices=[(x,y,z) for y in (-.58,.025) for x,z in outline]
    faces=[tuple(range(n)),tuple(range(n,2*n))[::-1]]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    obj=mesh(name,vertices,faces,[pier_top_mat,pier_face_mat],[1,0]+[1]*n,bevel=.008)
    uv=obj.data.uv_layers.new(name='Raw_Source_Pier_Masonry')
    for polygon in obj.data.polygons:
        for loop_index in polygon.loop_indices:
            x,y,z=vertices[obj.data.loops[loop_index].vertex_index]
            uv.data[loop_index].uv=(x*60/100,1-z*SHORE_SIN/7 if polygon.index==1 else 1-(.025-y)*SHORE_COS/17)
    return obj


for pier in shore_reference['measurements']['far_piers']:
    x0,y0,x1,y1=pier['bounds']
    p0=shore_source_point(x0,y0);p1=shore_source_point(x1,y1)
    pier_slab('Pier_'+pier['name']+'_Slab',[(p0[0],p0[2]),(p1[0],p0[2]),(p1[0],p1[2]),(p0[0],p1[2])])
connector=[shore_source_point(449,135),shore_source_point(510,135),
           shore_source_point(510,190+(510-449)*64/224),shore_source_point(449,190)]
pier_slab('Pier_Connecting_Spine',[(p[0],p[2]) for p in connector])

# The source's low wall closes the landward end of the two piers. Preserve its
# painted front and cutout rocks; hidden thickness uses the native stone material.
backwall_mat=shore_material('Source_Painted_Pier_Backwall','assets/r0/port/westile02/image/000.png')
backwall_tex=next(n for n in backwall_mat.node_tree.nodes if n.type=='TEX_IMAGE')
backwall_mat.node_tree.links.new(backwall_tex.outputs['Alpha'],backwall_mat.node_tree.nodes.get('Principled BSDF').inputs['Alpha'])
backwall_mat.surface_render_method='DITHERED'
wall_outline=[(449,135),(565,135),(528,123),(528,87),(523,84),(449,84)]
wall_front=shore_source_point(449,135)[2]
outline=[((x-448)/60,.025+(135-y)/SHORE_COS) for x,y in wall_outline]
backwall=extruded_outline('Pier_Landward_Backwall',outline,wall_front,.20,backwall_mat,0)
backwall.data.materials.append(stone)
uv=backwall.data.uv_layers.new(name='Source_Pier_Backwall_Projection')
for polygon in backwall.data.polygons:
    polygon.material_index=0 if polygon.index==1 else 1
    for loop_index in polygon.loop_indices:
        p=backwall.data.vertices[backwall.data.loops[loop_index].vertex_index].co
        sx=p.x*60+448;sy=159+(-p.y+1.6)*SHORE_SIN-(p.z-.025)*SHORE_COS
        uv.data[loop_index].uv=((sx-449)/224,1-(sy-84)/277)


def cylinder(name,center,radius,depth,mat,vertices=16):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=radius,depth=depth,location=point(center))
    obj=bpy.context.object;obj.name=name;obj.data.materials.append(mat)
    bevel=obj.modifiers.new('Soft rim','BEVEL');bevel.width=.015;bevel.segments=2
    return obj


def lamp_profile(name,profile,center,scale,mat):
    segments=lamp_reference['radial_segments'];vertices=[];faces=[]
    for height,radius in profile:
        for i in range(segments):
            angle=2*math.pi*i/segments
            vertices.append((radius*scale*math.cos(angle)/60,height*scale/SHORE_COS-.06,
                             radius*scale*math.sin(angle)*lamp_reference['depth_to_width_ratio']/60))
    for ring in range(len(profile)-1):
        for i in range(segments):
            j=(i+1)%segments
            faces.append((ring*segments+i,(ring+1)*segments+i,(ring+1)*segments+j,ring*segments+j))
    faces.extend([tuple(range(segments)),tuple((len(profile)-1)*segments+i for i in reversed(range(segments)))])
    obj=mesh(name,vertices,faces,[mat]);obj.location=point(center)
    uv=obj.data.uv_layers.new(name='Source_Lamp_Cylindrical')
    for polygon in obj.data.polygons:
        polygon.use_smooth=polygon.index<(len(profile)-1)*segments
        seam=any(obj.data.loops[k].vertex_index%segments==0 for k in polygon.loop_indices) and any(obj.data.loops[k].vertex_index%segments==segments-1 for k in polygon.loop_indices)
        for k in polygon.loop_indices:
            index=obj.data.loops[k].vertex_index;ring,index_in_ring=divmod(index,segments)
            u=index_in_ring/segments
            if seam and index_in_ring==0:u=1
            v=(profile[ring][0]-profile[0][0])/(profile[-1][0]-profile[0][0])
            uv.data[k].uv=(u,v)
    return obj


for lamp in shore_reference['measurements']['lamps']:
    px,py=lamp['foot'];x,ground,z=shore_source_point(px,py)
    scale=(py-lamp['top_y'])/lamp_reference['source_profile_height_pixels']
    for part,profile in lamp_reference['profiles'].items():
        lamp_profile('Pier_Lamp_'+lamp['name']+'_'+part,profile,(x,ground+.06,z),scale,
                     lamp_materials[lamp_reference['materials'][part]])


# The garden and its pale path connect the market's landward edge to the piers.
# Tree crowns retain selected source RGBA on a vertical cutout surface; trunks,
# forks, planting bed and walls are native geometry with original texture crops.
grove_bark=shore_material('Source_Grove_Bark','assets/r1/grove_bark.png')
grove_plaster=shore_material('Source_Grove_Plaster','assets/r1/grove_plaster.png')
grove_path=shore_material('Source_Grove_Path','assets/r1/grove_path.png')
grove_grass=shore_material('Source_Grove_Grass','assets/r1/grove_grass.png')
grove_canopy=shore_material('Source_Grove_Canopy','assets/r1/grove_canopy.png')
canopy_tex=next(n for n in grove_canopy.node_tree.nodes if n.type=='TEX_IMAGE')
grove_canopy.node_tree.links.new(canopy_tex.outputs['Alpha'],grove_canopy.node_tree.nodes.get('Principled BSDF').inputs['Alpha'])
grove_canopy.surface_render_method='DITHERED'
grove_objects=[]


def uv_grove_box(obj,style):
    uv=obj.data.uv_layers.new(name='Source_Grove_'+style)
    for polygon in obj.data.polygons:
        for index in polygon.loop_indices:
            p=obj.matrix_world@obj.data.vertices[obj.data.loops[index].vertex_index].co
            x,y,z=p.x,p.z,-p.y
            if style=='Path':u,v=x*60/40,z*SHORE_SIN/26
            elif style=='Grass':u,v=x*60/24,z*SHORE_SIN/8
            else:u,v=x*60/26,y*SHORE_COS/45
            uv.data[index].uv=(u,v)


def grove_ground_box(name,bounds,top,bottom,mat,style):
    x0,y0,x1,y1=bounds
    a=shore_source_point(x0,y0,top);b=shore_source_point(x1,y1,top)
    obj=box(name,((a[0]+b[0])/2,(top+bottom)/2,(a[2]+b[2])/2),
            (b[0]-a[0],top-bottom,b[2]-a[2]),mat,.008)
    uv_grove_box(obj,style);grove_objects.append(obj)
    return obj


grove_ground_box('Grove_Connecting_Stone_Path',grove_reference['geometry']['connection_source_bounds'],.025,-.58,grove_path,'Path')
grove_ground_box('Grove_Planting_Bed_Base',grove_reference['geometry']['bed_source_bounds'],.085,-.10,coping_mat,'Path')
grove_ground_box('Grove_Planting_Bed_Grass',[292,156,400,169],.11,.085,grove_grass,'Grass')


def projected_at_depth(sx,sy,z):
    return ((sx-448)/60,.025+(159+SHORE_SIN*(z+1.6)-sy)/SHORE_COS,z)


def garden_wall(name,source_front,z_at_x):
    front_vertices=[projected_at_depth(x,y,z_at_x(x)) for x,y in source_front]
    vertices=front_vertices+[(x,y,z-.17) for x,y,z in front_vertices]
    n=len(front_vertices)
    faces=[tuple(range(n)),tuple(range(n,2*n))[::-1]]+[(i,i+n,(i+1)%n+n,(i+1)%n) for i in range(n)]
    obj=mesh(name,vertices,faces,[grove_plaster],bevel=.008)
    uv_grove_box(obj,'Plaster');grove_objects.append(obj)
    return obj


wall_z=shore_source_point(270,158)[2]
garden_wall('Grove_Boundary_Wall_Front',[(270,158),(411,158),(411,84),(270,84)],lambda x:wall_z)
return_z=shore_source_point(449,130)[2]
garden_wall('Grove_Boundary_Wall_Return',[(411,158),(449,130),(449,84),(411,84)],
            lambda x:wall_z+(return_z-wall_z)*(x-411)/38)


def source_branch(name,start,end,radius,tip_radius):
    a=Vector(point(start));b=Vector(point(end));delta=b-a
    bpy.ops.mesh.primitive_cone_add(vertices=12,radius1=radius,radius2=tip_radius,depth=delta.length,
                                  location=(a+b)/2)
    obj=bpy.context.object;obj.name=name
    obj.rotation_mode='QUATERNION';obj.rotation_quaternion=delta.to_track_quat('Z','Y')
    obj.data.materials.append(grove_bark)
    # Primitive UVs preserve a bark swatch around the tapered native volume.
    if obj.data.uv_layers.active:obj.data.uv_layers.active.name='Source_Grove_Bark'
    grove_objects.append(obj)
    return obj


root_height=grove_reference['geometry']['root_height']
for tree in grove_reference['geometry']['trees']:
    px,py=tree['foot'];root=shore_source_point(px,py,root_height)
    z=root[2];radius=tree['radius'];top_y=tree['top_y']
    def trunk_point(sx,sy,depth=0):return projected_at_depth(sx,sy,z+depth)
    points=[trunk_point(px,py),trunk_point(px-1,py-32,.015),
            trunk_point(px+2,py-60,-.015),trunk_point(px-1,top_y)]
    for i,(a,b) in enumerate(zip(points,points[1:])):
        source_branch('Grove_Tree_'+tree['name']+'_Trunk_'+str(i),a,b,radius*(1-i*.16),radius*(.84-i*.16))
    for side in [-1,1]:
        start=trunk_point(px,top_y+26)
        joint=trunk_point(px+side*12,top_y+17,.02)
        end=trunk_point(px+side*26,top_y+5,.04)
        source_branch('Grove_Tree_'+tree['name']+'_Branch_'+str(side)+'_0',start,joint,radius*.55,radius*.40)
        source_branch('Grove_Tree_'+tree['name']+'_Branch_'+str(side)+'_1',joint,end,radius*.40,radius*.20)

# A fixed-depth vertical surface keeps the crown in front of its trunks and
# behind the market canopy. The front/back ordering follows native depth.
crown_z=shore_source_point(320,167,root_height)[2]+.15
crown_pixels=[(225,-42),(449,-42),(449,98),(225,98)]
vertices=[projected_at_depth(x,y,crown_z) for x,y in crown_pixels]
crown=mesh('Grove_Source_Canopy',vertices,[(3,2,1,0)],[grove_canopy])
uv=crown.data.uv_layers.new(name='Source_Grove_Canopy_Pixels')
source_uv=[(0,1),(1,1),(1,0),(0,0)]
for loop in crown.data.loops:uv.data[loop.index].uv=source_uv[loop.vertex_index]
grove_objects.append(crown)


# Native mooring props use the source's wood/hoop/rope/stone swatches. Elliptic
# depth follows the fixed-view painting while keeping real grounded volumes.
dock_wood=shore_material('Source_Dock_Wood','assets/r1/dock_wood.png')
dock_metal=shore_material('Source_Dock_Metal','assets/r1/dock_metal.png')
dock_rope=shore_material('Source_Dock_Rope','assets/r1/dock_rope.png')
dock_stone=shore_material('Source_Dock_Stone','assets/r1/dock_stone.png')
palette=mooring_reference['interior_palette']['rgba']
dock_dark=material('Dock_Interior_Source_Palette','#%02x%02x%02x'%tuple(palette[:3]))
dock_objects=[]
barrel_profile=[(0,.84),(.07,.93),(.26,1.0),(.74,1.0),(.93,.93),(1,.84)]


def barrel_radius(t):
    for (a,ra),(b,rb) in zip(barrel_profile,barrel_profile[1:]):
        if a<=t<=b:return ra+(rb-ra)*(t-a)/(b-a)
    return .84


def make_barrel(item):
    x,_,z=shore_source_point(*item['ground_center'])
    base=item['base_y'];height=item['height'];rx=item['radius_x'];rz=item['radius_z'];n=16
    vertices=[];faces=[];indices=[];uv_coords=[]
    # A dark inner shell remains visible through the narrow stave joints.
    for t,r in barrel_profile:
        for i in range(n):
            a=math.tau*i/n
            vertices.append((x+(rx*r-.007)*math.cos(a),base+t*height,z+(rz*r-.007)*math.sin(a)))
            uv_coords.append((i/n*8,t*3))
    for k in range(len(barrel_profile)-1):
        for i in range(n):
            j=(i+1)%n
            faces.append((k*n+i,(k+1)*n+i,(k+1)*n+j,k*n+j));indices.append(1)
    faces.append(tuple(range(n)));indices.append(1)
    if item['name']!='Upper':
        faces.append(tuple(range((len(barrel_profile)-1)*n,len(barrel_profile)*n))[::-1]);indices.append(0)
    # Sixteen wood staves share a single surface/material draw.
    for i in range(n):
        start=len(vertices)
        for t,r in barrel_profile:
            for side in [0,1]:
                a=math.tau*(i+side)/n+(.009 if side==0 else -.009)
                vertices.append((x+rx*r*math.cos(a),base+t*height,z+rz*r*math.sin(a)))
                uv_coords.append(((i+side)/n*8,t*3))
        for k in range(len(barrel_profile)-1):
            faces.append((start+k*2,start+(k+1)*2,start+(k+1)*2+1,start+k*2+1));indices.append(0)
    body=mesh('Dock_Barrel_'+item['name']+'_Body',vertices,faces,[dock_wood,dock_dark],indices)
    uv=body.data.uv_layers.new(name='Source_Dock_Wood_Staves')
    for loop in body.data.loops:uv.data[loop.index].uv=uv_coords[loop.vertex_index]
    dock_objects.append(body)
    for band,t in enumerate([.06,.50,.94]):
        verts=[]
        for y,extra in [(t*height-.025,.012),(t*height+.025,.012)]:
            r=barrel_radius(y/height)
            for i in range(n):
                a=math.tau*i/n
                verts.append((x+(rx*r+extra)*math.cos(a),base+y,z+(rz*r+extra)*math.sin(a)))
        band_faces=[(i,n+i,n+(i+1)%n,(i+1)%n) for i in range(n)]
        obj=mesh('Dock_Barrel_'+item['name']+'_Hoop_'+str(band),verts,band_faces,[dock_metal])
        uv=obj.data.uv_layers.new(name='Source_Dock_Metal_Hoop')
        for polygon in obj.data.polygons:
            for loop_index in polygon.loop_indices:
                vi=obj.data.loops[loop_index].vertex_index
                angle=vi%n
                if polygon.index==n-1 and angle==0:angle=n
                uv.data[loop_index].uv=(angle/n*6,vi//n)
        dock_objects.append(obj)
    if item['name']=='Upper':
        obj=cylinder('Dock_Barrel_Upper_Dark_Interior',(x,base+height-.055,z),1,.012,dock_dark,16)
        obj.scale=Vector((rx*.82,rz*.82,1));dock_objects.append(obj)


for barrel in mooring_reference['barrels']:make_barrel(barrel)


def dock_uv(obj,width,height):
    uv=obj.data.uv_layers.new(name='Source_Dock_Masonry')
    uv.active_render=True
    bpy.context.view_layer.update()
    for polygon in obj.data.polygons:
        for loop_index in polygon.loop_indices:
            p=obj.matrix_world@obj.data.vertices[obj.data.loops[loop_index].vertex_index].co
            uv.data[loop_index].uv=(p.x*60/width,p.z*SHORE_COS/height)


mooring=mooring_reference['mooring'];mx,_,mz=shore_source_point(*mooring['ground_center'])
core=cylinder('Dock_Mooring_Core',(mx,.1875,mz),1,.325,dock_wood,16)
core.scale=Vector((.23,.11,1));dock_uv(core,13,9);dock_objects.append(core)
cap=cylinder('Dock_Mooring_Limestone_Cap',(mx,mooring['stone_bottom_y']+mooring['stone_height']/2,mz),1,
             mooring['stone_height'],dock_stone,12)
cap.scale=Vector((mooring['stone_radius_x'],mooring['stone_radius_z'],1));dock_uv(cap,28,7);dock_objects.append(cap)


def dock_rope_tube(name,points,radius=.025):
    points=[Vector(p) for p in points];vertices=[];faces=[];uvs=[];sides=8;length=0
    for i,p in enumerate(points):
        if i:length+=(p-points[i-1]).length
        tangent=(points[min(i+1,len(points)-1)]-points[max(0,i-1)]).normalized()
        normal=tangent.cross(Vector((0,1,0)))
        if normal.length<.01:normal=tangent.cross(Vector((1,0,0)))
        normal.normalize();binormal=tangent.cross(normal).normalized()
        for j in range(sides):
            angle=math.tau*j/sides
            v=p+radius*(normal*math.cos(angle)+binormal*math.sin(angle))
            vertices.append(tuple(v));uvs.append((length*60/23,j/sides))
        if i:
            for j in range(sides):
                k=(j+1)%sides
                faces.append(((i-1)*sides+j,(i-1)*sides+k,i*sides+k,i*sides+j))
    obj=mesh(name,vertices,faces,[dock_rope])
    uv=obj.data.uv_layers.new(name='Source_Dock_Rope')
    for loop in obj.data.loops:uv.data[loop.index].uv=uvs[loop.vertex_index]
    dock_objects.append(obj);return obj


coil=[]
for i in range(181):
    t=i/180;angle=math.tau*3*t
    coil.append((mx+.345*math.cos(angle),.07+.23*t,mz+.15*math.sin(angle)))
dock_rope_tube('Dock_Rope_Coil',coil)
tail=[shore_source_point(x,y,.055) for x,y in mooring['rope_tail_source']]
dock_rope_tube('Dock_Rope_Tail',tail)

# Reconstruct the market stall as separate surfaces/volumes, using the original
# westmobj00 painting as a fixed-camera projection. Depth and hidden faces are
# new interpretation; the client does not contain an original 3D model.
stall_source='assets/r0/port/westmobj00/image/000.png'
stall_mat=material('Source_Painted_Stall','#ffffff',.95)
stall_nodes=stall_mat.node_tree.nodes
stall_nodes.remove(stall_nodes.get('Principled BSDF'))
stall_tex=stall_mat.node_tree.nodes.new('ShaderNodeTexImage')
stall_tex.image=bpy.data.images.load(str(ROOT/stall_source))
stall_tex.interpolation='Closest';stall_tex.extension='EXTEND'
# A color socket connected directly to a shader input is shadeless in Blender.
# The bundled glTF exporter recognizes this transparent/color mix as unlit.
# Preserve the painting's baked light in both editable source and runtime.
stall_transparent=stall_nodes.new('ShaderNodeBsdfTransparent')
stall_mix=stall_nodes.new('ShaderNodeMixShader')
stall_mat.node_tree.links.new(stall_tex.outputs['Alpha'],stall_mix.inputs[0])
stall_mat.node_tree.links.new(stall_transparent.outputs[0],stall_mix.inputs[1])
stall_mat.node_tree.links.new(stall_tex.outputs['Color'],stall_mix.inputs[2])
stall_mat.node_tree.links.new(stall_mix.outputs[0],stall_nodes.get('Material Output').inputs['Surface'])
stall_mat.surface_render_method='DITHERED'
stall_wood=material('Stall_Carved_Wood','#705139')
stall_rope=material('Stall_Coral_Rope','#bc3831')
stall_gold=material('Stall_Aged_Gold','#c6a260',.72,.12)
stall_objects=[]
cos_ppm=60*math.cos(math.radians(38))
sin_ppm=60*math.sin(math.radians(38))


def stall_at_depth(px,py,z):
    return ((px-276)/60,.025+(121+sin_ppm*(z+1.6)-py)/cos_ppm,z)


def stall_at_height(px,py,height):
    return ((px-276)/60,height,(py-121+cos_ppm*(height-.025))/sin_ppm-1.6)


def stall_panel(name,pixels,z,thickness=.025):
    outline=[stall_at_depth(x,y,z)[:2] for x,y in pixels]
    if sum(a[0]*b[1]-b[0]*a[1] for a,b in zip(outline,outline[1:]+outline[:1]))<0:
        outline.reverse()
    obj=extruded_outline(name,outline,z,thickness,stall_mat,.003)
    stall_objects.append(obj)
    return obj


def apply_stall_uv(obj):
    obj.data.materials.clear();obj.data.materials.append(stall_mat)
    uv=obj.data.uv_layers.new(name='Source_Stall_Projection')
    uv.active_render=True
    obj.data.uv_layers.active_index=len(obj.data.uv_layers)-1
    bpy.context.view_layer.update()
    for loop in obj.data.loops:
        p=obj.matrix_world @ obj.data.vertices[loop.vertex_index].co
        x,y,z=p.x,p.z,-p.y
        px=x*60+276
        py=121+sin_ppm*(z+1.6)-cos_ppm*(y-.025)
        uv.data[loop.index].uv=(px/443,1-py/230)
    obj['reference_png']=stall_source
    obj['uv_rule']='Camera projection at R0 scale; back/depth construction is adapted'


# A raised roof with four real faces. The alpha cutout preserves the hand-drawn
# scallops rather than adding a rectangular transparent shadow.
roof_pixels=[(115,49),(175,31),(294,59),(218,79)]
roof_corners=[stall_at_height(x,y,2.4) for x,y in roof_pixels]
peak=stall_at_height(179,8,3.33)
roof_obj=mesh('Stall_Canopy',[peak]+roof_corners,
              [(0,(i+1)%4+1,i+1) for i in range(4)],[stall_mat])
stall_objects.append(roof_obj)
 # The source is a parasol over a counter, not a four-corner pavilion.
cylinder('Stall_Central_Parasol_Mast',(peak[0],1.72,peak[2]),.032,3.44,stall_wood,16)
bpy.ops.mesh.primitive_cone_add(vertices=20,radius1=.031,radius2=0,depth=.14,
                              location=point((peak[0],3.45,peak[2])))
obj=bpy.context.object;obj.name='Stall_Parasol_Finial';obj.data.materials.append(stall_gold)

scallops=[(164,59),(294,57),(294,66),(288,71),(282,65),(277,60),
          (271,69),(265,75),(259,73),(253,66),(248,62),(242,70),
          (236,77),(230,77),(224,71),(218,63),(212,69),(206,76),
          (200,76),(193,71),(188,65),(181,71),(175,75),(169,72),(164,66)]
stall_panel('Stall_Canopy_Scalloped_Valance',scallops,-.15,.012)
stall_panel('Stall_Red_Drapery',[(27,61),(159,61),(159,168),(27,168)],.15,.018)
stall_panel('Stall_Carved_Screen_Frame',[(15,49),(22,44),(64,44),(80,31),(110,31),
    (121,44),(158,44),(162,41),(170,43),(175,49),(172,57),(165,60),
    (165,179),(154,185),(23,185),(19,178),(19,58)],.175,.055)

# The painted screen is a separate mesh behind its wooden rim. A small gap in
# depth keeps cloth/frame from z-fighting while retaining the original emblem.
stall_panel('Stall_Screen_Cloth_Inset',[(29,62),(155,62),(155,167),(29,167)],.181,.008)
counter=box('Stall_Counter',(-1.14,.57,-.38),(1.52,1.14,.64),stall_mat,.012)
stall_objects.append(counter)
stall_panel('Stall_Green_Counter_Cloth',[(160,123),(190,124),(181,147),(165,138)],-.045,.012)
stall_panel('Stall_Blue_Counter_Cloth',[(181,123),(246,120),(254,126),(219,154)],.025,.012)

stock1=box('Stall_Upper_Chest',stall_at_depth(200,94,-.23),(.66,.57,.42),stall_mat,.012)
stock2=box('Stall_Lower_Chest',stall_at_depth(202,113,-.10),(.65,.24,.46),stall_mat,.01)
stall_objects.extend([stock1,stock2])
stall_panel('Stall_Stock_Sack',[(221,97),(229,94),(237,102),(241,112),(235,117),(219,116)],-.16,.13)
stall_panel('Stall_Emblem_Post',[(118,111),(143,109),(145,200),(119,200)],.60,.10)
barrel_base=stall_at_depth(14,174,-.13)
barrel=cylinder('Stall_Left_Barrel',(barrel_base[0],.30,-.13),.175,.60,stall_mat,24)
stall_objects.append(barrel)
for obj in stall_objects:apply_stall_uv(obj)


def rope_curve(name,a,b,sag=.20):
    data=bpy.data.curves.new(name,'CURVE');data.dimensions='3D'
    data.bevel_depth=.019;data.bevel_resolution=2
    spline=data.splines.new('POLY');spline.points.add(24)
    for i in range(25):
        t=i/24
        p=[a[j]*(1-t)+b[j]*t for j in range(3)]
        p[1]-=sag*math.sin(math.pi*t)
        spline.points[i].co=(*point(p),1)
    obj=bpy.data.objects.new(name,data);bpy.context.collection.objects.link(obj)
    obj.data.materials.append(stall_rope)
    bpy.ops.object.select_all(action='DESELECT');obj.select_set(True)
    bpy.context.view_layer.objects.active=obj
    bpy.ops.object.convert(target='MESH')
    return bpy.context.object


# Native posts/ropes replace the floor baked into the old single-card stall.
for row,feet,head_y in [('Back',[(215,188),(251,188),(287,188),(323,188),(359,188)],154),
                       ('Front',[(262,226),(305,226),(348,226),(391,226),(434,226)],185)]:
    anchors=[]
    for i,(px,py) in enumerate(feet):
        z=(38+py-159)/sin_ppm-1.6;x=(px-276)/60
        height=(py-head_y)/cos_ppm
        cylinder('Stall_%s_Post_Base_%d'%(row,i),(x,.035,z),.105,.07,stone_light,16)
        cylinder('Stall_%s_Post_Shaft_%d'%(row,i),(x,height/2,z),.026,height-.06,quay,12)
        cylinder('Stall_%s_Post_Collar_%d'%(row,i),(x,height-.09,z),.055,.055,stall_gold,16)
        bpy.ops.mesh.primitive_uv_sphere_add(segments=16,ring_count=8,radius=.065,location=point((x,height-.025,z)))
        obj=bpy.context.object;obj.name='Stall_%s_Post_Finial_%d'%(row,i);obj.data.materials.append(stone_light)
        anchors.append((x,height-.12,z))
    for i,(a,b) in enumerate(zip(anchors,anchors[1:])):
        rope_curve('Stall_%s_Rope_%d'%(row,i),a,b)

# Small pile of limestone blocks makes front/back occlusion measurable without a new game area.
for i in range(3):
    box('Occlusion_Stone_%d'%i,(2.65+i*.34,.20,2.45),(.33,.40,.47),stone_light,.045)

# Reflect only the existing edge strips outside the old model. Reading evaluated
# meshes retains their bevels and source UVs without changing interior meshes or
# consuming the construction RNG. This is visual overscan, not new walkable map.
bpy.context.view_layer.update()
edge_depsgraph=bpy.context.evaluated_depsgraph_get()


def reflected_edge(source,side):
    edge=side*8.5
    width=98/60
    lo,hi=sorted((edge,edge-side*width))
    evaluated=source.evaluated_get(edge_depsgraph)
    original=evaluated.to_mesh(preserve_all_data_layers=True,depsgraph=edge_depsgraph)
    verts=[];faces=[];indices=[];uvs=[];smooth=[]
    source_uv=original.uv_layers.active
    try:
        for polygon in original.polygons:
            poly=[(source.matrix_world@original.vertices[original.loops[i].vertex_index].co,
                   source_uv.data[i].uv.copy() if source_uv else None) for i in polygon.loop_indices]
            if max(p.x for p,uv in poly)<lo or min(p.x for p,uv in poly)>hi:continue
            for boundary,greater in [(lo,True),(hi,False)]:
                clipped=[]
                for (a,ua),(b,ub) in zip(poly,poly[1:]+poly[:1]):
                    inside_a=a.x>=boundary if greater else a.x<=boundary
                    inside_b=b.x>=boundary if greater else b.x<=boundary
                    if inside_a:clipped.append((a,ua))
                    if inside_a!=inside_b:
                        t=(boundary-a.x)/(b.x-a.x)
                        clipped.append((a.lerp(b,t),ua.lerp(ub,t) if ua is not None else None))
                poly=clipped
                if not poly:break
            clean=[]
            for item in poly:
                if not clean or (item[0]-clean[-1][0]).length_squared>1e-18:clean.append(item)
            if len(clean)>1 and (clean[0][0]-clean[-1][0]).length_squared<1e-18:clean.pop()
            poly=clean
            if len(poly)<3:continue
            area=sum(((poly[i][0]-poly[0][0]).cross(poly[i+1][0]-poly[0][0])
                      for i in range(1,len(poly)-1)),Vector((0,0,0)))
            if area.length_squared<1e-18:continue
            # A reflection reverses orientation; reverse loops to retain culling.
            poly.reverse();start=len(verts)
            verts.extend((2*edge-p.x,p.y,p.z) for p,uv in poly)
            uvs.extend(uv for p,uv in poly)
            faces.append(tuple(range(start,len(verts))))
            indices.append(polygon.material_index);smooth.append(polygon.use_smooth)
        if not faces:return
        name='Overscan_'+('Left_' if side<0 else 'Right_')+source.name
        data=bpy.data.meshes.new(name);data.from_pydata(verts,[],faces);data.update()
        for mat in original.materials:data.materials.append(mat)
        for polygon,index,use_smooth in zip(data.polygons,indices,smooth):
            polygon.material_index=index;polygon.use_smooth=use_smooth
        if source_uv:
            layer=data.uv_layers.new(name=source_uv.name);layer.active_render=True
            for loop in data.loops:layer.data[loop.index].uv=uvs[loop.vertex_index]
        obj=bpy.data.objects.new(name,data);bpy.context.collection.objects.link(obj)
        obj['visual_overscan']='Mirrored original edge pixels and geometry; navigation unchanged'
    finally:
        evaluated.to_mesh_clear()


edge_sources=[obj for obj in bpy.context.scene.objects if obj.name in
              ['Terracotta_Diamond_Paving','Mortar_Bed_Shore_Polygon',
               'Quay_Retaining_Wall_Left','Quay_Retaining_Wall_Front'] or
              obj.name.startswith(('Quay_Coping_Left_','Quay_Coping_Front_'))]
for side in [-1,1]:
    for source in edge_sources:reflected_edge(source,side)

# Save editable source before exporting only mesh objects.
bpy.context.view_layer.update()
bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'west_coast_port.blend'))
bpy.ops.object.select_all(action='DESELECT')
for obj in bpy.context.scene.objects:
    if obj.type=='MESH':obj.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(EXPORT/'west_coast_port.glb'),export_format='GLB',
                          use_selection=True,export_apply=True,export_cameras=False,export_lights=False,
                          export_yup=True)
# Blender's current dithered alpha exports as BLEND. Use glTF MASK for this
# cutout artwork so transparent pixels neither block depth nor cast solid cards.
glb_path=EXPORT/'west_coast_port.glb'
raw=glb_path.read_bytes();chunks=[];cursor=12
while cursor<len(raw):
    length,kind=struct.unpack_from('<II',raw,cursor);cursor+=8
    payload=raw[cursor:cursor+length];cursor+=length
    if kind==0x4e4f534a:
        document=json.loads(payload)
        # Blender emits nearest-with-mipmaps for Closest image nodes. Use
        # nearest without mipmaps for this fixed-camera source-pixel sample.
        for sampler in document.get('samplers',[]):
            if sampler.get('magFilter')==9728:
                sampler['minFilter']=9728
        for mat in document.get('materials',[]):
            if mat.get('name') in ['Source_Painted_Facade','Source_Painted_Stall','Source_Painted_Pier_Backwall','Source_Grove_Canopy']:
                mat['alphaMode']='MASK';mat['alphaCutoff']=.25
            if mat.get('name') in ['Source_Grove_Canopy','Source_Painted_Stall']:
                mat.setdefault('extensions',{})['KHR_materials_unlit']={}
                if 'KHR_materials_unlit' not in document.setdefault('extensionsUsed',[]):
                    document['extensionsUsed'].append('KHR_materials_unlit')
        payload=json.dumps(document,separators=(',',':')).encode()
        payload+=b' '*((-len(payload))%4)
    chunks.append(struct.pack('<II',len(payload),kind)+payload)
payload=b''.join(chunks)
glb_path.write_bytes(struct.pack('<III',0x46546c67,2,12+len(payload))+payload)
summary={'source':'westile00/01/02/03/04 and westmobj00 images used as references; new 3D geometry, not recovered original meshes',
         'blender':bpy.app.version_string,'objects':len(bpy.context.scene.objects),
         'mesh_faces_before_modifiers':sum(len(o.data.polygons) for o in bpy.context.scene.objects if o.type=='MESH'),
         'coordinates':'Godot X/Y/Z; converted to Blender X/-Z/Y before glTF export',
         'source_blend':'source_art/r1/west_coast_port.blend','export_glb':'assets/r1/models/west_coast_port.glb',
         'stall_reference':stall_source,'stall_projected_meshes':[o.name for o in stall_objects],
         'stall_color_policy':'Original RGB with unlit alpha cutout; active render UV is Source_Stall_Projection',
         'facade_uv_policy':'Full camera projection including depth relative to front=-0.42; source alpha cutout',
         'dock_masonry_uv_policy':'World coordinates after scale update; active Source_Dock_Masonry',
         'stall_lossless_import':'assets/r1/models/west_coast_port_000_18.png.import',
         'alpha_mask_materials':['Source_Painted_Facade','Source_Painted_Stall','Source_Painted_Pier_Backwall','Source_Grove_Canopy'],
         'unlit_materials':['Source_Grove_Canopy','Source_Painted_Stall'],
         'grove_reference':'source_art/r1/grove_reference.json',
         'grove_meshes':[obj.name for obj in grove_objects],
         'mooring_reference':'source_art/r1/mooring_reference.json',
         'lamp_reference':'source_art/r1/lamp_reference.json',
         'lamp_meshes':[o.name for o in bpy.context.scene.objects if o.name.startswith('Pier_Lamp_')],
         'dock_meshes':[obj.name for obj in dock_objects],
         'nearest_without_mipmaps':True,
         'shore_reference':'source_art/r1/shore_reference.json',
         'shore_masonry_uv_meshes':[o.name for o in bpy.context.scene.objects if o.type=='MESH' and any(layer.name.startswith(('Raw_Source_Coping','Raw_Source_Pier','Source_Pier_Backwall')) for layer in o.data.uv_layers)]}
(OUT/'model_manifest.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(summary))
