"""Rebuild the owned R0/R1 sample outputs, then complete Godot's real import pass.

Run with the existing numpy/Pillow Python. Stop game playback first.
Do not use this to export a manually modified .blend; export that source separately.
"""
from pathlib import Path
import subprocess,sys,json,hashlib

ROOT=Path(__file__).resolve().parents[2]
state=ROOT/'docs/r1_build_manifest.json'
if state.exists():
    manifest=json.loads(state.read_text())
    previous=next((x for x in manifest['artifacts'] if x['path']=='source_art/r1/west_coast_port.blend'),None)
    source=ROOT/'source_art/r1/west_coast_port.blend'
    if previous and source.exists() and hashlib.sha256(source.read_bytes()).hexdigest()!=previous['sha256']:
        raise SystemExit('The .blend has changed since the last generated build. Preserve/export those edits separately before regenerating.')

godot='/Applications/Godot.app/Contents/MacOS/Godot'
commands=[
    [godot,'--headless','--path',str(ROOT),'--script',
     'res://'+path.relative_to(ROOT).as_posix(),'--check-only']
    for path in sorted((ROOT/'tools/r1').glob('*.gd'))
] + [
    [sys.executable,'tools/dnf_client_analysis/export_audio.py'],
    [sys.executable,'tools/dnf_client_analysis/export_music.py'],
    [sys.executable,'tools/dnf_client_analysis/export_ambience.py'],
    [sys.executable,'tools/r1/compose_billboards.py'],
    [sys.executable,'tools/r1/prepare_facade_reference.py'],
    [sys.executable,'tools/r1/prepare_shore_reference.py'],
    [sys.executable,'tools/r1/prepare_grove_reference.py'],
    [sys.executable,'tools/r1/prepare_mooring_reference.py'],
    [sys.executable,'tools/r1/prepare_lamp_reference.py'],
    [sys.executable,'tools/r1/prepare_water_reference.py'],
    ['/Applications/Blender.app/Contents/MacOS/Blender','--background','--factory-startup','--threads','4','--python','tools/r1/build_port_model.py'],
    [sys.executable,'tools/r1/preserve_overscan_model.py','--capture-generated'],
    [sys.executable,'tools/dnf_client_analysis/build_r0_scene.py'],
    [sys.executable,'tools/r1/build_r1_scene.py'],
    [godot,'--headless','--recovery-mode','--single-threaded-scene','--path',str(ROOT),'--editor','--import','--quit'],
    # Discover the actual PNG paths after GLB import, then configure and import
    # every active model texture before the final stamp.
    [godot,'--headless','--path',str(ROOT),'--script','res://tools/r1/collect_model_imports.gd'],
    [sys.executable,'tools/dnf_client_analysis/pixel_imports.py'],
    [godot,'--headless','--recovery-mode','--single-threaded-scene','--path',str(ROOT),'--editor','--import','--quit'],
    [sys.executable,'tools/r1/stamp_build.py'],
]
log=ROOT/'work/r1_rebuild.log'
log.parent.mkdir(exist_ok=True)
with log.open('w') as out:
    for command in commands:
        print('Running',Path(command[0]).name,command[1],flush=True)
        subprocess.run(command,cwd=ROOT,stdout=out,stderr=subprocess.STDOUT,check=True)
print('Rebuilt and imported. Run scenes/west_coast_r1.tscn from disk; log:',log)
