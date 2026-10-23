"""Assemble native capture frames into a lossless animated WebP and verify it."""
from pathlib import Path
import argparse
import hashlib
import json
import re

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate', default='R1/06')
    args = parser.parse_args()
    prefix = args.candidate.lower().replace('/', '_')
    assert re.fullmatch(r'r\d+_\d+', prefix), args.candidate
    capture_path = ROOT / f'docs/{prefix}_motion_capture.json'
    capture = json.loads(capture_path.read_text())
    directory = ROOT / f'work/{prefix}_motion_frames'
    frames = [Image.open(directory / f'{row["frame"]:03d}.png').convert('RGB') for row in capture['frames']]
    durations = [row['duration_ms'] for row in capture['frames']]
    assert frames and all(frame.size == frames[0].size for frame in frames)
    output = ROOT / f'docs/previews/{prefix}_jump.webp'
    frames[0].save(output, save_all=True, append_images=frames[1:], duration=durations,
                   loop=0, lossless=True, quality=100, method=4)
    decoded = Image.open(output)
    assert decoded.n_frames == len(frames)
    decoded_duration = 0
    for index, reference in enumerate(frames):
        decoded.seek(index)
        decoded.load()
        assert decoded.convert('RGB').tobytes() == reference.tobytes(), index
        decoded_duration += decoded.info['duration']
    assert decoded_duration == sum(durations)
    report = {'file': output.relative_to(ROOT).as_posix(), 'format': 'animated WebP',
              'lossless': True, 'frames': len(frames), 'duration_ms': decoded_duration,
              'size': list(frames[0].size), 'exact_rgb_frames': len(frames),
              'sha256': hashlib.sha256(output.read_bytes()).hexdigest(),
              'qa_source_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              'capture_report': capture_path.relative_to(ROOT).as_posix(),
              'notes': 'Actor/prop fixed-step Godot render; shader TIME remains wall time. Not a desktop-performance recording.'}
    (ROOT / f'docs/{prefix}_animation_check.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(report, ensure_ascii=False))


if __name__ == '__main__':
    main()
