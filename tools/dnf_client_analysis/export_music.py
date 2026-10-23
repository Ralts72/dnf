"""Resolve the selected port map's music tag and retain its original OGG."""
from pathlib import Path
import argparse,hashlib,json,subprocess,xml.etree.ElementTree as ET
from inspect_clients import PVF
from export_audio import normalize_comments,packets

ROOT=Path(__file__).resolve().parents[2]


def sha(data):return hashlib.sha256(data).hexdigest()


def file_sha(path):
    digest=hashlib.sha256()
    with path.open('rb') as handle:
        for block in iter(lambda:handle.read(1024*1024),b''):digest.update(block)
    return digest.hexdigest()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--client',type=Path,default=Path('/Users/mac/Downloads/天堂95起源单机客户端'))
    args=parser.parse_args();client=args.client
    map_reference=json.loads((ROOT/'docs/source_port_map.json').read_text())
    pvf=PVF(client/'Script.pvf');pvf.load_strings()
    map_raw,crc=pvf.read(map_reference['source_pvf'],True)
    assert sha(map_raw)==map_reference['sha256']
    assert crc['expected']==crc['actual_seed_file_number']
    tokens=pvf.tokens(map_reference['source_pvf'],'big5')
    sound_section=False;sound_tags=[]
    for token in tokens:
        if token.get('text')=='[sound]':sound_section=True;continue
        if token.get('text')=='[/sound]':sound_section=False
        if sound_section and token['type']==7:sound_tags.append(token['text'])
    xml_raw=(client/'audio.xml').read_bytes()
    tags={node.attrib['ID']:node for node in ET.fromstring(xml_raw) if 'ID' in node.attrib}
    music_tags=[tag for tag in sound_tags if tag in tags and tags[tag].tag=='MUSIC']
    assert music_tags==['M_WESTCOAST'],music_tags
    tag=music_tags[0];attributes=dict(tags[tag].attrib)
    relative=Path(attributes['FILE'].replace('\\','/'))
    source=(client/relative).resolve();source.relative_to(client.resolve())
    raw=source.read_bytes();assert raw.startswith(b'OggS')
    original=ROOT/'source_art/music/westcoast_old.ogg'
    runtime=ROOT/'assets/r0/music/westcoast_old.ogg'
    original.parent.mkdir(parents=True,exist_ok=True);runtime.parent.mkdir(parents=True,exist_ok=True)
    original.write_bytes(raw)
    normalized,metadata=normalize_comments(raw);runtime.write_bytes(normalized)
    probe=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_entries',
        'format=duration:stream=sample_rate,channels,codec_name','-of','json',str(source)]))
    stream=probe['streams'][0]
    assert stream['codec_name']=='vorbis' and stream['channels']==2
    settings={'schema':1,'tag':tag,'path':'res://'+runtime.relative_to(ROOT).as_posix(),
        'loop':True,'loop_offset_seconds':0.0,'default_volume':.2,'volume_levels':[0.0,.1,.2,.4],
        'intro_fade_seconds':.6,'volume_fade_seconds':.15,
        'source_reference':'docs/r1_music_source_reference.json',
        'notes':['Music continues during pose/water pause and retains one player across R0/R1.',
                 'F9 mutes with a short fade, then pauses the stream at its current position.',
                 'Source tag/track selection is verified; gain, fades and UI behavior are sample choices.']}
    reference={'candidate':'R1/13','client':str(client),'source':relative.as_posix(),
        'source_bytes':len(raw),'source_sha256':sha(raw),'source_pvf_sha256':file_sha(client/'Script.pvf'),
        'map':{'path':map_reference['source_pvf'],'sha256':sha(map_raw),'crc':crc,'sound_tags':sound_tags},
        'audio_xml_sha256':sha(xml_raw),'tag':tag,'xml_attributes':attributes,
        'original':original.relative_to(ROOT).as_posix(),'runtime':runtime.relative_to(ROOT).as_posix(),
        'runtime_bytes':len(normalized),'runtime_sha256':sha(normalized),'metadata_fix':metadata,
        'duration_seconds':float(probe['format']['duration']),'channels':stream['channels'],
        'sample_rate':int(stream['sample_rate']),'noncomment_packets':len(packets(raw))-1,
        'settings':settings,'notes':['Only the selected music whitelist is exported here; ambience mapping and export are recorded separately in docs/r1_ambience_source_reference.json.',
                                   'Original bytes stay unchanged. The runtime copy only repairs one bare Vorbis comment.']}
    (ROOT/'data/port_music.json').write_text(json.dumps(settings,ensure_ascii=False,indent=2)+'\n')
    (ROOT/'docs/r1_music_source_reference.json').write_text(json.dumps(reference,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'tag':tag,'source':relative.as_posix(),'bytes':len(raw),'duration':reference['duration_seconds'],
                      'all_noncomment_packets_identical':metadata['all_noncomment_packets_identical']}))


if __name__=='__main__':main()
