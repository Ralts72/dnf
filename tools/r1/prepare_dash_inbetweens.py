"""Promote validated native dash bakes without editing source or RGB pixels."""
from pathlib import Path
import hashlib,json,shutil

ROOT=Path(__file__).resolve().parents[2]
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    base=ROOT/'source_art/r1/experiments/dash_cycle_26'
    bake=json.loads((ROOT/'docs/r1_26_bake_checks.json').read_text())
    assert bake['endpoint_full_rgba_exact'] and bake['all_png_roundtrips_exact']
    for name in ['palette','apparel','r1','live_r1','playback','preview']:
        assert not json.loads((ROOT/f'docs/r1_26_{name}_checks.json').read_text())['failed']
    for key,path in [('actor_sha256','actor.gd'),('shader_sha256','dash_skin.gdshader'),('recipe_sha256','dash_recipe.json')]:assert bake[key]==digest(base/path)
    records={(r['frame'],r['subframe']):r for r in bake['records']}
    original=json.loads((ROOT/'data/swordman_r1.json').read_text());frames=original['animations']['dash']['frames']
    assert len(frames)==8 and all(f['duration_ms']==100 for f in frames)
    dest=ROOT/'assets/r1/actors/swordman_dash';dest.mkdir(parents=True,exist_ok=True)
    output=[];sources=[]
    for index,frame in enumerate(frames):
        intermediates=[]
        for sub in [1,2]:
            source=base/f'baked/dash_{index:02d}_{sub}.png';assert digest(source)==records[(index,sub)]['png_sha256']
            target=dest/source.name
            if not target.exists() or target.read_bytes()!=source.read_bytes():shutil.copy2(source,target)
            path='res://'+target.relative_to(ROOT).as_posix();intermediates.append(path)
            sources.append({'path':path,'sha256':digest(target),'source':source.relative_to(ROOT).as_posix(),'bytes':target.stat().st_size})
        output.append({'source':frame['texture'],'intermediates':intermediates})
    data={'schema':1,'action':'dash','source_frame_ms':100,'subframes':3,'cycle_ms':800,'lower_body_sample_rate_hz':30,
          'upper_body_source_rate_hz':10,'canvas_size':original['canvas_size'],'foot_anchor':original['foot_anchor'],'frames':output,
          'notes':['Original ANI clock, source textures and190px/s running speed remain unchanged. R1 lower apparel only.',
                   'Authored source-pixel samples, not recovered original poses. R0 remains raw.']}
    (ROOT/'data/swordman_dash_inbetweens.json').write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
    report={'candidate':'R1/27','source_bake_report':'docs/r1_26_bake_checks.json','source_bake_sha256':digest(ROOT/'docs/r1_26_bake_checks.json'),
            'recipe_sha256':digest(base/'dash_recipe.json'),'actor_script_sha256':digest(base/'actor.gd'),'actor_shader_sha256':digest(base/'dash_skin.gdshader'),
            'source_animation_sha256':digest(ROOT/'data/swordman_r1.json'),'runtime_data_sha256':digest(ROOT/'data/swordman_dash_inbetweens.json'),
            'textures':sources,'qa_source_sha256':digest(Path(__file__)),'derived_texture_count':len(sources)}
    (ROOT/'docs/r1_27_dash_source_reference.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print('Prepared16 native-derived dash textures; source cycle800ms and speed190px/s unchanged.')

if __name__=='__main__':main()
