"""Record exact source palette samples and the adapted water animation mapping."""
from pathlib import Path
import hashlib,json
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]


def main():
    shore=json.loads((ROOT/'source_art/r1/shore_reference.json').read_text())['measurements']
    samples=[]
    for name,image_name,point in [
        ('deep','westile03',(6,60)),('shade','westile03',(6,61)),
        ('blue','westile03',(6,62)),('body_dark','westile03',(6,63)),
        ('body','westile03',(6,64)),('cyan','westile02',(164,126)),
        ('ripple','westile02',(153,124)),('glint','westile02',(157,123)),
        ('foam','westile02',(155,122))]:
        source=ROOT/f'assets/r0/port/{image_name}/image/000.png'
        image=Image.open(source).convert('RGBA')
        samples.append({'name':name,'source':source.relative_to(ROOT).as_posix(),
            'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
            'point':point,'rgba':list(image.getpixel(point))})
    reference={'candidate':'R1/12','source_manifest':'docs/r0_asset_manifest.json','palette':samples,
        'mapping':{'pixels_per_meter':60,'camera_elevation_degrees':38,'source_origin':[448,159],
            'source_depth_origin':-1.6,'ground_height':.025,'animation_steps_per_second':8,
            'near_shore_points':shore['near_shore_outer_pixels'],
            'far_pier_bounds':shore['far_piers'][0]['bounds'],'middle_pier_bounds':shore['far_piers'][1]['bounds']},
        'notes':['Nine color values are unchanged source RGBA samples, not a recovered original water shader.',
                 'World-position pixel quantization, glint placement, shoreline bands and animation are adapted.',
                 'The native surface is unlit to keep the selected palette; no water mesh, navigation or ship animation changes.',
                 'Each water node owns its material and clock. Pause freezes it; F4 retains its phase.']}
    (ROOT/'source_art/r1/water_reference.json').write_text(json.dumps(reference,ensure_ascii=False,indent=2)+'\n')
    print('Recorded nine exact source water colors and an explicit animation mapping.')


if __name__=='__main__':main()
