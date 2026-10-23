"""Verify the retained canonical ambient payload and metadata-only runtime copy."""
from pathlib import Path
import hashlib,json,struct,subprocess,sys,xml.etree.ElementTree as ET
import numpy as np

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/dnf_client_analysis'))
from inspect_clients import npk_entries
from export_audio import packets,normalize_comments,ogg_crc

reference=json.loads((ROOT/'docs/r1_ambience_source_reference.json').read_text())
pack=Path(reference['client'])/'SoundPacks'/reference['pack']['name']
assert hashlib.sha256(pack.read_bytes()).hexdigest()==reference['pack']['sha256']
entry=next(e for e in npk_entries(pack,False) if e['path']==reference['entry']['path'])
assert entry==reference['entry']
with pack.open('rb') as handle:handle.seek(entry['offset']);raw=handle.read(entry['bytes'])
original=(ROOT/reference['original']).read_bytes();runtime=(ROOT/reference['runtime']).read_bytes()
assert raw==original and hashlib.sha256(raw).hexdigest()==reference['source_sha256']
fixed,proof=normalize_comments(raw);assert fixed==runtime and hashlib.sha256(runtime).hexdigest()==reference['runtime_sha256']
left,right=packets(raw),packets(runtime)
assert len(left)==len(right) and all(a==b for i,(a,b) in enumerate(zip(left,right)) if i!=1)
cursor=0;pages=0
while cursor<len(runtime):
    count=runtime[cursor+26];size=27+count+sum(runtime[cursor+27:cursor+27+count]);page=bytearray(runtime[cursor:cursor+size])
    expected=struct.unpack_from('<I',page,22)[0];page[22:26]=b'\0'*4;assert ogg_crc(page)==expected
    cursor+=size;pages+=1
xml=(Path(reference['client'])/'audio.xml').read_bytes();assert hashlib.sha256(xml).hexdigest()==reference['audio_xml_sha256']
tag=next(n for n in ET.fromstring(xml) if n.attrib.get('ID')==reference['tag'])
assert tag.tag=='AMBIENT' and dict(tag.attrib)==reference['xml_attributes']
assert reference['tag'] in reference['map']['sound_tags'] and reference['map']['crc']['expected']==reference['map']['crc']['actual_seed_file_number']
def decode(path):return subprocess.check_output(['ffmpeg','-nostdin','-v','error','-i',str(path),'-f','f32le','-acodec','pcm_f32le','pipe:1'])
source_pcm=decode(ROOT/reference['original']);runtime_pcm=decode(ROOT/reference['runtime']);assert source_pcm==runtime_pcm
audio=np.frombuffer(runtime_pcm,dtype='<f4').reshape(-1,2)
assert np.isfinite(audio).all() and np.max(np.abs(audio))>.01
report={'candidate':'R1/14','failed':[],'tag':reference['tag'],'source_bytes':len(raw),'runtime_bytes':len(runtime),
    'original_retained_exactly':True,'all_noncomment_packets_identical':True,'decoded_pcm_identical':True,
    'decoded_pcm_sha256':hashlib.sha256(runtime_pcm).hexdigest(),'ogg_pages_crc_checked':pages,
    'decoded_frames':len(audio),'sample_rate':44100,'channels':2,'duration_seconds':40.0,
    'rms':float(np.sqrt(np.mean(audio*audio))),'peak':float(np.max(np.abs(audio))),
    'source_script_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    'note':'Original mapped stereo recording; runtime only repairs one comment. Distance gain and fades are new interpretation.'}
(ROOT/'docs/r1_14_ambience_source_checks.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({k:report[k] for k in ['tag','source_bytes','decoded_pcm_identical','ogg_pages_crc_checked','rms','peak']}))
