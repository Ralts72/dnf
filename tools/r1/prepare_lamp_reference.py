"""Retain exact lamp swatches and measured stepped profiles for the native props."""
from pathlib import Path
import hashlib,json,sys
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/dnf_client_analysis'))
from pixel_imports import configure


def main():
    source=ROOT/'assets/r0/port/westile02/image/000.png'
    image=Image.open(source).convert('RGBA')
    crops=[]
    for name,rect in [('blue',(179,56,193,64)),('glass',(178,72,193,80)),
                      ('shaft',(182,115,189,143)),('collar',(181,111,192,114))]:
        target=ROOT/f'assets/r1/lamp_{name}.png'
        image.crop(rect).save(target)
        crops.append({'name':name,'rect':rect,'output':target.relative_to(ROOT).as_posix(),
                      'sha256':hashlib.sha256(target.read_bytes()).hexdigest(),
                      'operation':'Exact rectangular RGBA crop; no recoloring or resampling'})
    # Height/radius pairs in source pixels, measured upward from the near lamp's
    # foot. Hidden circular depth and how these profiles are shared are adapted.
    profiles={
        'Base':[[0,4],[3,6],[10,6],[11,9],[16,9],[19,5]],
        'Shaft':[[17,5],[55,5],[62,4],[72,4],[77,1]],
        'Collar':[[55,5],[57,8],[61,8],[63,4]],
        'Glass':[[77,1],[79,4],[84,8],[90,11],[99,11],[101,9]],
        'Glass_Rim':[[99,11],[101,12],[103,11],[105,12],[107,10]],
        'Hood':[[107,10],[111,11],[115,8],[120,3],[123,1]],
        'Spire':[[123,1],[137,.5]]}
    reference={'candidate':'R1/11','source':source.relative_to(ROOT).as_posix(),
        'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
        'source_manifest':'docs/r0_asset_manifest.json','crops':crops,
        'source_profile_height_pixels':137,'radial_segments':20,'depth_to_width_ratio':.7,
        'profiles':profiles,'materials':{'Base':'collar','Shaft':'shaft','Collar':'collar',
            'Glass':'glass','Glass_Rim':'blue','Hood':'blue','Spire':'blue'},
        'notes':['The near lamp supplies source colors and stepped profile proportions; six lamp anchors/top heights retain shore_reference.json.',
                 'Rotational volume, flattened circular depth and cylindrical UV distribution are new interpretation.',
                 'Textures are lit and keep their original pixels; rendered RGB is not claimed identical to unlit source art.']}
    (ROOT/'source_art/r1/lamp_reference.json').write_text(json.dumps(reference,ensure_ascii=False,indent=2)+'\n')
    configure(ROOT)
    print('Retained four exact lamp crops and seven measured native profiles.')


if __name__=='__main__':main()
