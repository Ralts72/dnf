"""Verify retained source OGGs and metadata-only runtime derivatives."""
from pathlib import Path
import hashlib
import json
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/dnf_client_analysis'))
from export_audio import normalize_comments, packets

reference = json.loads((ROOT / 'docs/r1_audio_source_reference.json').read_text())
client = Path(reference['client'])
assert hashlib.sha256((client / 'audio.xml').read_bytes()).hexdigest() == reference['audio_xml_sha256']
for pack, info in reference['packs'].items():
    assert hashlib.sha256((client / 'SoundPacks' / pack).read_bytes()).hexdigest() == info['sha256']
records = []
for tag, info in reference['sounds'].items():
    original = (ROOT / info['retained_original']).read_bytes()
    assert hashlib.sha256(original).hexdigest() == info['sha256']
    with (client / 'SoundPacks' / info['pack']).open('rb') as f:
        f.seek(info['offset'])
        assert f.read(info['bytes']) == original
    runtime = (ROOT / info['path'].removeprefix('res://')).read_bytes()
    expected, proof = normalize_comments(original)
    assert runtime == expected and proof == info['metadata_fix']
    assert hashlib.sha256(runtime).hexdigest() == info['runtime_sha256']
    assert packets(original)[3:] == packets(runtime)[3:]
    records.append({'tag': tag, 'source_matches_npk': True, 'noncomment_packets_identical': True})
report = {'candidate': 'R1/07', 'source_files': len(records), 'runtime_files': len(records),
          'canonical_packs': len(reference['packs']), 'checks': records, 'failed': []}
(ROOT / 'docs/r1_07_audio_source_checks.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print(json.dumps({k: v for k, v in report.items() if k != 'checks'}))
