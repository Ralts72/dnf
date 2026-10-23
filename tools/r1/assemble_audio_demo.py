"""Make a stereo audition from live audited cues and unchanged source audio.

This is an offline cue preview, not a microphone or live output recording.
The current Mac output is 7.1; capture produced about four times the expected frame count.
"""
from pathlib import Path
import array
import hashlib
import json
import shutil
import subprocess
import wave

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
RATE = 48000
VOLUME = 0.6


def main():
    ffmpeg = shutil.which('ffmpeg')
    if not ffmpeg:
        raise SystemExit('ffmpeg is required for the optional stereo audition.')
    ffprobe = shutil.which('ffprobe')
    if not ffprobe:
        raise SystemExit('ffprobe is required to preserve mono amplitude in the optional audition.')
    data = json.loads((ROOT / 'data/swordman_audio.json').read_text())
    cues = json.loads((ROOT / 'docs/r1_07_audio_demo_cues.json').read_text())['cues']
    tracks = []
    for cue in cues:
        source = ROOT / data['sounds'][cue['tag']]['path'].removeprefix('res://')
        info = json.loads(subprocess.run([ffprobe, '-v', 'error', '-select_streams', 'a:0',
                          '-show_entries', 'stream=channels', '-of', 'json', str(source)],
                          check=True, capture_output=True).stdout)
        channels = info['streams'][0]['channels']
        assert channels in [1, 2]
        result = subprocess.run([ffmpeg, '-v', 'error', '-i', str(source), '-f', 'f32le',
                                 '-ar', str(RATE), '-'], check=True, capture_output=True)
        decoded = np.frombuffer(result.stdout, dtype='<f4').reshape((-1, channels))
        if channels == 1:
            decoded = np.repeat(decoded, 2, axis=1)
        start = round(cue['scheduled_ms'] * RATE / 1000)
        tracks.append((start, decoded))
    end = max(start + len(track) for start, track in tracks) + round(RATE * .1)
    mix = np.zeros((end, 2), dtype=np.float64)
    for start, track in tracks:
        mix[start:start + len(track)] += track * VOLUME
    peak = float(np.abs(mix).max())
    assert .01 < peak < 1.0
    pcm = np.rint(mix * 32767).astype('<i2')
    target = ROOT / 'docs/previews/r1_07_jump_audio.wav'
    with wave.open(str(target), 'wb') as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())
    with wave.open(str(target), 'rb') as w:
        check = array.array('h', w.readframes(w.getnframes()))
        assert len(check) == len(pcm) * 2 and max(abs(v) for v in check) > 1000
    report = {'candidate': 'R1/07', 'path': target.relative_to(ROOT).as_posix(),
              'source': 'Offline stereo preview: audited live cue choices/times, decoded original OGG audio.',
              'rate': RATE, 'channels': 2, 'sample_width': 2, 'frames': end, 'seconds': end / RATE,
              'peak': peak, 'clipped_samples': int((np.abs(pcm.astype(np.int32)) >= 32767).sum()),
              'cue_count': len(cues), 'volume': VOLUME,
              'sha256': hashlib.sha256(target.read_bytes()).hexdigest(),
              'generator_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              'notes': ['No resynthesis or timbre changes. Decoding and sample-rate conversion only.',
                        'Real Godot mixer checks are recorded separately in r1_07_audio_checks.json.',
                        'This audition is not a certification of speaker hardware or audiovisual sync.']}
    for name in ['r1_07_audio_demo.json', 'r1_07_audio_demo_check.json']:
        (ROOT / 'docs' / name).write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(report, ensure_ascii=False))


if __name__ == '__main__':
    main()
