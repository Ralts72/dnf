"""Build editable R2 architecture using explicit exported source-pixel textures.

These are adapted spaces, not reconstructed original map geometry. The parent
scene supplies the38-degree camera, lighting, actors, backdrop and travel rules.
"""
from pathlib import Path
import json
import math
import sys

from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/dnf_client_analysis'))
from build_r0_scene import Scene,gd

ANGLE=math.radians(38)
PPM=60
SIN=math.sin(ANGLE)
COS=math.cos(ANGLE)


def vec(values):
    return 'Vector3('+', '.join(f'{value:.8f}' for value in values)+')'


def world(x,y,height=.025):
    return [(x-448)/PPM,height,(y-159)/(PPM*SIN)-1.6]


class World:
    def __init__(self,name):
        self.scene=Scene();self.name=name;self.cache={};self.count=0
        self.scene.node(name,'Node3D',**{'metadata/layout_policy':gd('Adapted R2 route; original source pixels, new3D geometry.')})

    def resource(self,kind,props):
        key=(kind,tuple(sorted(props.items())))
        if key not in self.cache:
            ident='R2_'+str(len(self.cache)+1)
            self.scene.subresources.append('[sub_resource type='+gd(kind)+' id='+gd(ident)+']\n'+
                '\n'.join(name+' = '+value for name,value in props.items()))
            self.cache[key]='SubResource('+gd(ident)+')'
        return self.cache[key]

    def material(self,path,unlit=False,scale=(1,1),offset=(0,0)):
        return self.resource('StandardMaterial3D',{
            'shading_mode':'0' if unlit else '1','albedo_texture':self.scene.resource('res://assets/r2/'+path),
            'roughness':'1.0','texture_filter':'0','uv1_scale':vec([*scale,1]),'uv1_offset':vec([*offset,0])})

    def box(self,name,x,y,width,height,depth,material,bottom=.015,rotation=None):
        mesh=self.resource('BoxMesh',{'material':material,'size':vec([width,height,depth])})
        props={'position':vec(world(x,y,bottom+height/2)),'mesh':mesh}
        if rotation:props['rotation']=vec(rotation)
        self.scene.node(name,'MeshInstance3D','.',**props);self.count+=1

    def cylinder(self,name,x,y,radius,height,material,bottom=.015,top=None):
        mesh=self.resource('CylinderMesh',{'material':material,'bottom_radius':str(radius),
            'top_radius':str(radius if top is None else top),'height':str(height),'radial_segments':'12','rings':'1'})
        self.scene.node(name,'MeshInstance3D','.',position=vec(world(x,y,bottom+height/2)),mesh=mesh)
        self.count+=1

    def floor(self,path,bounds):
        x0,y0,x1,y1=bounds
        image=Image.open(ROOT/'assets/r2'/path)
        material=self.material(path,True,((x1-x0)/image.width,(y1-y0)/image.height))
        mesh=self.resource('PlaneMesh',{'material':material,
            'size':'Vector2('+str((x1-x0)/PPM)+', '+str((y1-y0)/(PPM*SIN))+')'})
        self.scene.node('WalkablePaving','MeshInstance3D','.',position=vec(world((x0+x1)/2,(y0+y1)/2,.015)),mesh=mesh)
        self.count+=1

    def card(self,name,path,x,y,depth=0,right_pad=0):
        image=Image.open(ROOT/'assets/r2'/path)
        texture=self.scene.resource('res://assets/r2/'+path)
        position=world(x,y)
        position[1]+=SIN*depth;position[2]+=COS*depth
        self.scene.node(name,'Sprite3D','.',texture=texture,
            position=vec(position),rotation=vec([-ANGLE,0,0]),pixel_size=str(1/PPM),
            offset='Vector2(0, '+str(image.height/2)+')',billboard='0',alpha_cut='1',
            alpha_scissor_threshold='0.25',texture_filter='0',shaded='false',cast_shadow='0',
            **{'metadata/source_pixel_policy':gd('Original crop at1 source pixel per logical view pixel; only view-ray depth offset.')})
        if right_pad:
            atlas=self.resource('AtlasTexture',{'atlas':texture,
                'region':f'Rect2({image.width-right_pad}, 0, {right_pad}, {image.height})'})
            self.scene.node('RightEdgePad','Sprite3D',name,texture=atlas,
                position=vec([(image.width+right_pad)/2/PPM,0,0]),pixel_size=str(1/PPM),
                offset='Vector2(0, '+str(image.height/2)+')',billboard='0',flip_h='true',alpha_cut='1',
                alpha_scissor_threshold='0.25',texture_filter='0',shaded='false',cast_shadow='0',
                **{'metadata/source_pixel_policy':gd('Interpreted mirrored right-edge overscan; original PNG unchanged.')})

    def save(self,path):
        self.scene.save(path)
        return {'scene':path,'native_mesh_instances':self.count,'subresources':len(self.cache)}


def post(w,name,x,y,material,height=.86):
    w.box(name+'_Foot',x,y,.34,.10,.34,material)
    w.cylinder(name+'_Plinth',x,y,.145,.14,material,bottom=.115)
    w.cylinder(name+'_Shaft',x,y,.072,height-.39,material,bottom=.255,top=.062)
    w.cylinder(name+'_Collar',x,y,.105,.07,material,bottom=height-.135)
    w.box(name+'_Cap',x,y,.27,.08,.27,material,bottom=height-.065)


def approach():
    w=World('TowerApproachWorld')
    # The fully opaque source subrectangle supplies carved pale-stone variation.
    stone=w.material('approach/bridge_0.png',scale=(64/224,32/306),offset=(24/224,80/306))
    paving=w.material('approach/paving.png',scale=(1.8,1.0))
    w.box('CausewayStoneFoundation',445,340,20.5,.20,220/(PPM*SIN),stone,bottom=-.19)
    w.floor('approach/paving.png',[-170,230,1060,450])
    for side,x0,x1 in [('Left',-170,350),('Right',510,1060)]:
        center=(x0+x1)/2
        w.box('FarBalustrade_'+side,center,226,(x1-x0)/PPM,.29,.24,stone)
        w.box('FarCoping_'+side,center,226,(x1-x0)/PPM,.065,.34,stone,bottom=.305)
    # Keep tall posts behind the navigation strip and leave the tower door clear.
    for i,x in enumerate([-112,0,112,224,336,560,672,784,896,1008]):
        post(w,'FarCarvedPost_'+str(i),x,226,stone)
    # A low foreground edge is below the legal foot range, keeping the main route open.
    w.box('NearBalustrade',445,400,20.5,.22,.24,stone)
    w.box('NearCoping',445,400,20.5,.06,.34,stone,bottom=.235)
    for i,x in enumerate(range(-112,1061,112)):
        post(w,'NearCarvedPost_'+str(i),x,405,stone,.53)
    # A faintly raised stone cadence connects the sea route to the pointed door.
    for i,y in enumerate([241,246,251]):
        w.box('DoorApproachStep_'+str(i),430,y,2.50,.025,.10,paving,bottom=.016)
    w.card('TowerGalleryLandmark','entrance/tower.png',448,236,-1.7,right_pad=180)
    w.card('PointedTowerDoor','entrance/gate.png',430,236,-.10)
    for side,x in [('Left',372),('Right',488)]:
        w.box('GatePier_'+side,x,230,.20,3.35,.32,stone)
        w.box('GatePierBase_'+side,x,230,.37,.18,.43,stone)
        w.box('GatePierCapital_'+side,x,230,.37,.16,.43,stone,bottom=3.25)
    return w.save('scenes/tower_approach_world.tscn')


def hall():
    w=World('TowerHallWorld')
    stone=w.material('interior/paving.png',scale=(1.0,1.0))
    gold=w.material('interior/column.png',scale=(11/29,60/93),offset=(9/29,16/93))
    w.box('HallStoneFoundation',445,342.5,20.5,.24,215/(PPM*SIN),stone,bottom=-.23)
    w.floor('interior/paving.png',[-170,235,1060,450])
    # The sunset stays visible through the central rear opening supplied by the parent backdrop.
    for side,x0,x1 in [('Left',-170,302),('Right',594,1060)]:
        center=(x0+x1)/2
        w.box('RearStoneDado_'+side,center,234,(x1-x0)/PPM,.62,.28,stone)
        w.box('RearGildedCoping_'+side,center,234,(x1-x0)/PPM,.08,.35,gold,bottom=.635)
    for i,x in enumerate([140,760]):
        w.card('SourceSpiralColumn_'+str(i),'interior/wall_'+str(3 if i==0 else 4)+'.png',x,245,-.40)
        w.cylinder('NativeColumnFoot_'+str(i),x,239,.46,.18,gold)
        w.cylinder('NativeColumnRing_'+str(i),x,239,.37,.15,gold,bottom=.195)
        w.cylinder('NativeColumnShaft_'+str(i),x,239,.22,3.15,gold,bottom=.345,top=.17)
        w.cylinder('NativeColumnCapital_'+str(i),x,239,.42,.20,gold,bottom=3.495,top=.48)
    w.card('BakalBannerReference','interior/banner.png',448,238,-.85)
    # The return is a bright floor threshold with an open view between physical side supports.
    # Keep those supports in front of the legal y345 edge rather than inside the walking strip.
    for side,x in [('Left',344),('Right',536)]:
        w.box('ReturnArchFoot_'+side,x,366,.50,.17,.48,gold)
        w.box('ReturnArchPier_'+side,x,366,.25,2.25,.30,stone,bottom=.185)
        w.box('ReturnArchCapital_'+side,x,366,.52,.16,.48,gold,bottom=2.435)
    w.box('ReturnThreshold',440,337,1.85,.018,.24,gold,bottom=.016)
    for i,x in enumerate([120,264,616,776]):
        w.box('NearSideDado_'+str(i),x,397,1.80,.24,.28,stone)
        w.box('NearSideCap_'+str(i),x,397,1.88,.06,.36,gold,bottom=.255)
    return w.save('scenes/tower_hall_world.tscn')


def main():
    path=ROOT/'source_art/r2/layout_reference.json'
    outputs=[approach()]
    if '--approach-only' in sys.argv:
        outputs.extend(item for item in json.loads(path.read_text())['outputs']
                       if item['scene']=='scenes/tower_hall_world.tscn')
    else:
        outputs.append(hall())
    reference={'stage':'R2/01 route geometry study','layout_policy':'Adapted harbor-to-tower connection; no claim of recovered original adjacency or3D geometry.',
        'camera':{'elevation_degrees':38,'source_pixels_per_meter':60,'source_center':[448,202],
            'source_y_origin_offset':43,'ground_height':.025,'ground_formula':'X=(sourceX-448)/60; Z=(sourceY-159)/(60*sin38)-1.6; Y=.025'},
        'approach':{'walk_rectangle':[36,236,852,345],'floor_source_bounds':[-170,230,1060,450],
            'tower_door_ground':[430,236],'tower_card_bottom_center':[448,236],
            'return_ground':[846,320],'far_wall_ground_y':226,'front_wall_ground_y':400,
            'tower_right_padding':{'source_texture':'res://assets/r2/entrance/tower.png',
                'source_rect_xyxy':[702,0,882,600],'flip_h':True,'padding_pixels':180,
                'source_x_coverage':[889,1069],
                'policy':'Interpreted mirrored right-edge extension beyond the original crop; shared view rotation and bottom anchor, no PNG edits.'},
            'tower_art':'entrance/tower.png is the explicitly recorded95-client cataclysm/skytower gallery; its top intentionally extends above the view.'},
        'hall':{'walk_rectangle':[120,245,776,345],'floor_source_bounds':[-170,235,1060,450],
            'spiral_column_ground':[[140,245],[760,245]],'banner_ground':[448,238],
            'return_ground':[440,337],'return_side_support_ground':[[344,366],[536,366]]},
        'pixel_policy':['Source PNGs and actor assets are unchanged. Native floors use opaque source subrects, unlit nearest sampling and UV repetition.',
            'Carved stone/column material subrects use UV scale/offset on original source textures; no new bitmap colors are generated.',
            'Architecture uses source textures with native light, so its screenRGB is not claimed to equal sourceRGB.',
            'Source cards retain1source pixel per logical pixel and a38-degree view-facing surface; view-ray depth offsets only set layering.',
            'Geometry has no new collision bodies. Parent travel bounds and scene portals define the initial route; full architectural collision remains a later step.'],
        'material_subrects':{'approach_stone':{'texture':'res://assets/r2/approach/bridge_0.png','rect_xyxy':[24,80,88,112],'alpha_range':[255,255]},
            'hall_gold':{'texture':'res://assets/r2/interior/column.png','rect_xyxy':[9,16,20,76],'alpha_range':[255,255]}},
        'outputs':outputs}
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(reference,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(outputs))


if __name__=='__main__':main()
