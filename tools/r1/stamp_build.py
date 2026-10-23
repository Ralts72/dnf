"""Record exact current R1 source/output hashes without changing runtime assets."""
from pathlib import Path
import hashlib,json

ROOT=Path(__file__).resolve().parents[2]
paths=['source_art/r1/west_coast_port.blend','assets/r1/models/west_coast_port.glb',
       'source_art/r1/facade_reference.json','source_art/r1/shore_reference.json','source_art/r1/grove_reference.json','source_art/r1/mooring_reference.json','source_art/r1/lamp_reference.json','source_art/r1/water_reference.json','source_art/r1/model_manifest.json','docs/r1_derivative_manifest.json',
       'scenes/west_coast_r1.tscn','shaders/source_billboard.gdshader',
       'shaders/harbor_water.gdshader','scripts/source_actor_3d.gd',
       'scripts/source_actor.gd','scripts/west_coast_r1.gd','scripts/west_coast_r0.gd',
       'scripts/demo_walk_area.gd','scripts/demo_input.gd','project.godot',
       'tools/r1/build_port_model.py','tools/r1/build_r1_scene.py',
       'assets/r0/port/westmobj00/image/000.png','docs/pixel_import_manifest.json',
       'docs/r1_model_texture_manifest.json',
       'docs/r1_walk_area_reference.json','docs/r1_20_interpolation_reference.json',
       'assets/r1/models/west_coast_port_000_18.png','assets/r1/models/west_coast_port_000_18.png.import',
       'tools/dnf_client_analysis/pixel_imports.py','tools/dnf_client_analysis/export_r0.py',
       'tools/dnf_client_analysis/build_r0_scene.py','tools/dnf_client_analysis/export_motion_reference.py',
       'data/swordman_motion.json','docs/r1_jump_source_reference.json',
       'docs/r1_28_framing_reference.json',
       'docs/r1_29_framing_reference.json',
       'source_art/r1/checkpoints/candidate_28/assets/r1/models/west_coast_port.glb',
       'source_art/r1/checkpoints/candidate_28/source_art/r1/west_coast_port.blend',
       'data/swordman_walk_inbetweens.json','docs/r1_25_walk_source_reference.json',
       'data/swordman_dash_inbetweens.json','docs/r1_27_dash_source_reference.json',
       'source_art/r1/experiments/dash_cycle_26/dash_recipe.json','source_art/r1/experiments/dash_cycle_26/actor.gd',
       'source_art/r1/experiments/dash_cycle_26/dash_skin.gdshader','source_art/r1/experiments/dash_cycle_26/bake.gd',
       'source_art/r1/experiments/walk_cycle_24/walk_recipe.json','source_art/r1/experiments/walk_cycle_24/actor.gd',
       'source_art/r1/experiments/walk_cycle_24/walk_shear.gdshader','source_art/r1/experiments/walk_cycle_24/bake.gd',
       'data/swordman_effects.json','docs/r1_effect_source_reference.json','tools/dnf_client_analysis/export_hopsmash_effects.py',
       'data/swordman_audio.json','docs/r1_audio_source_reference.json','data/port_music.json','docs/r1_music_source_reference.json',
       'data/port_ambience.json','docs/r1_ambience_source_reference.json',
       'tools/dnf_client_analysis/export_audio.py','tools/dnf_client_analysis/export_music.py','tools/dnf_client_analysis/export_ambience.py']
paths=sorted(set(paths+[p.relative_to(ROOT).as_posix() for pattern in
    ['assets/r1/actors/swordman_walk/*.png','assets/r1/actors/swordman_walk/*.png.import','assets/r0/effects/**/*.png','assets/r0/effects/**/*.png.import','source_art/ambience/*.ogg','assets/r0/ambience/*.ogg','source_art/music/*.ogg','assets/r0/music/*.ogg','assets/r1/lamp_*.png','assets/r1/dock_*.png','assets/r1/grove_*.png','assets/r1/quay_coping.png','assets/r1/pier_*.png','source_art/audio/*.ogg','assets/r0/audio/*.ogg','scripts/*.gd','shaders/*.gdshader','scenes/*.tscn','data/*_r0.json','data/*_r1.json',
     'tools/r1/*.gd','tools/r1/*.py']
    for p in ROOT.glob(pattern)] +
    [item['path'].removeprefix('res://')+suffix
     for item in json.loads((ROOT/'docs/r1_model_texture_manifest.json').read_text())['textures']
     for suffix in ['', '.import']]))
paths=sorted(set(paths+[p.relative_to(ROOT).as_posix() for pattern in
    ['assets/r1/actors/swordman_dash/*.png','assets/r1/actors/swordman_dash/*.png.import'] for p in ROOT.glob(pattern)]))
artifacts=[]
for path in paths:
    data=(ROOT/path).read_bytes()
    artifacts.append({'path':path,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()})
manifest={'stage':'R1 visual candidate 29','artifacts':artifacts,
          'source_manifest':'docs/r0_asset_manifest.json',
          'derivative_manifest':'docs/r1_derivative_manifest.json',
          'reference_measurements':'source_art/r1/facade_reference.json',
          'shore_measurements':'source_art/r1/shore_reference.json',
          'grove_measurements':'source_art/r1/grove_reference.json',
          'mooring_measurements':'source_art/r1/mooring_reference.json',
          'lamp_measurements':'source_art/r1/lamp_reference.json',
          'water_measurements':'source_art/r1/water_reference.json',
          'music_source_reference':'docs/r1_music_source_reference.json',
          'ambience_source_reference':'docs/r1_ambience_source_reference.json',
          'model_statistics':json.loads((ROOT/'source_art/r1/model_manifest.json').read_text()),
          'notes':['New 3D geometry referenced from source art; not recovered original meshes.',
                   'The source .blend contains packed reference and paving images.',
                   'R0 preserved for F4 comparison. Visual direction accepted; R1 polish and full acceptance remain pending.',
                   'R1 walking/running lower apparel uses32 native-derived inbetweens at30Hz; F5 selects raw source poses. Upper body and weapon remain10Hz, both source cycles800ms. R0 stays raw.',
                   'Default native scene render 1792x808; F6 selects 896x404 or 1792x808.']}
manifest['notes'].append('R1/28 uses limited vertical framing shared with R0. R0 keeps original character layers; its floor adds a40px mirrored edge outside the old image crop. No horizontal world-edge fix or navigation expansion.')
manifest['notes'].append('R1/29 adds shared horizontal framing with fixed176px pose radius; navigation remains36..852. Appended14 model edge strips retain all302 original meshes/materials byte-for-byte. Off-crop R0 flooring and ship edges reuse mirrored source texels; this padding is interpreted scenery, not recovered map content. Rebuild runs preserve_overscan_model.py after generating edge meshes.')
(ROOT/'docs/r1_build_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
print('Stamped R1 source and runtime artifact hashes.')
