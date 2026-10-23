"""Check mapped music bytes, Vorbis packets, page CRCs and decoded PCM."""
from pathlib import Path
import hashlib,json,struct,subprocess,sys,xml.etree.ElementTree as ET
import numpy as np

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/dnf_client_analysis'))
from export_audio import packets,normalize_comments,ogg_crc

reference=json.loads((ROOT/'docs/r1_music_source_reference.json').read_text())
source=Path(reference['client'])/reference['source']
raw=source.read_bytes();original=(ROOT/reference['original']).read_bytes();runtime=(ROOT/reference['runtime']).read_bytes()
assert raw==original and hashlib.sha256(raw).hexdigest()==reference['source_sha256']
assert hashlib.sha256(runtime).hexdigest()==reference['runtime_sha256']
expected,proof=normalize_comments(raw);assert expected==runtime
left,right=packets(raw),packets(runtime)
assert len(left)==len(right) and all(a==b for i,(a,b) in enumerate(zip(left,right)) if i!=1)
pages=0;cursor=0
while cursor<len(runtime):
    count=runtime[cursor+26];size=27+count+sum(runtime[cursor+27:cursor+27+count])
    page=bytearray(runtime[cursor:cursor+size]);stored=struct.unpack_from('<I',page,22)[0]
    page[22:26]=b'\0'*4;assert ogg_crc(page)==stored
    pages+=1;cursor+=size
xml=(Path(reference['client'])/'audio.xml').read_bytes();assert hashlib.sha256(xml).hexdigest()==reference['audio_xml_sha256']
tag=next(n for n in ET.fromstring(xml) if n.attrib.get('ID')==reference['tag'])
assert dict(tag.attrib)==reference['xml_attributes']
assert tag.attrib['FILE'].replace('\\','/').lower()==reference['source'].lower()
assert reference['map']['crc']['expected']==reference['map']['crc']['actual_seed_file_number']
assert reference['tag'] in reference['map']['sound_tags']
def decode(path):
    return subprocess.check_output(['ffmpeg','-nostdin','-v','error','-i',str(path),'-f','f32le','-acodec','pcm_f32le','pipe:1'])
source_pcm=decode(source);runtime_pcm=decode(ROOT/reference['runtime']);assert source_pcm==runtime_pcm
audio=np.frombuffer(runtime_pcm,dtype='<f4').reshape(-1,2)
assert np.isfinite(audio).all() and np.max(np.abs(audio))>0.01
report={'candidate':'R1/13','failed':[],'tag':reference['tag'],'source_bytes':len(raw),'runtime_bytes':len(runtime),
    'original_retained_exactly':True,'all_noncomment_packets_identical':True,'ogg_pages_crc_checked':pages,
    'comments_fixed':proof['comments_fixed'],'audio_packet_sha256':proof['audio_packet_sha256'],
    'decoded_pcm_identical':True,'decoded_pcm_sha256':hashlib.sha256(runtime_pcm).hexdigest(),
    'decoded_frames':len(audio),'channels':2,'sample_rate':reference['sample_rate'],
    'rms':float(np.sqrt(np.mean(audio*audio))),'peak':float(np.max(np.abs(audio))),
    'loop_endpoint_sample_difference':float(np.max(np.abs(audio[0]-audio[-1]))),
    'duration_seconds':reference['duration_seconds'],
    'source_script_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    'note':'Track and samples are source-backed; loop, fades, levels and controls are new sample behavior.'}
(ROOT/'docs/r1_13_music_source_checks.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({k:report[k] for k in ['tag','original_retained_exactly','decoded_pcm_identical','ogg_pages_crc_checked','rms','peak','loop_endpoint_sample_difference']}))
