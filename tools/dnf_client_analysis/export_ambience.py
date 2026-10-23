"""Resolve the port ambient tag and copy its exact canonical NPK payload."""
from pathlib import Path
import argparse,hashlib,json,subprocess,xml.etree.ElementTree as ET
from inspect_clients import PVF,npk_entries
from export_audio import normalize_comments

ROOT=Path(__file__).resolve().parents[2]


def sha(data):return hashlib.sha256(data).hexdigest()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--client',type=Path,default=Path('/Users/mac/Downloads/天堂95起源单机客户端'))
    client=parser.parse_args().client
    map_reference=json.loads((ROOT/'docs/source_port_map.json').read_text())
    pvf=PVF(client/'Script.pvf');raw_map,crc=pvf.read(map_reference['source_pvf'],True)
    assert sha(raw_map)==map_reference['sha256'] and crc['expected']==crc['actual_seed_file_number']
    sound_section=False;tags=[]
    for token in pvf.tokens(map_reference['source_pvf'],'big5'):
        if token.get('text')=='[sound]':sound_section=True;continue
        if token.get('text')=='[/sound]':sound_section=False
        if sound_section and token['type']==7:tags.append(token['text'])
    xml=(client/'audio.xml').read_bytes()
    elements={node.attrib['ID']:node for node in ET.fromstring(xml) if 'ID' in node.attrib}
    ambient_tags=[tag for tag in tags if tag in elements and elements[tag].tag=='AMBIENT']
    assert ambient_tags==['AMB_PORT_01']
    tag=ambient_tags[0];attributes=dict(elements[tag].attrib)
    name=attributes['FILE'].replace('\\','/').lower()
    pack=client/'SoundPacks/sounds_amb.npk'
    entry=next(e for e in npk_entries(pack,False) if e['path']==name)
    with pack.open('rb') as handle:handle.seek(entry['offset']);raw=handle.read(entry['bytes'])
    assert raw.startswith(b'OggS')
    original=ROOT/'source_art/ambience/amb_port_01.ogg';runtime=ROOT/'assets/r0/ambience/amb_port_01.ogg'
    original.parent.mkdir(parents=True,exist_ok=True);runtime.parent.mkdir(parents=True,exist_ok=True)
    original.write_bytes(raw);fixed,proof=normalize_comments(raw);runtime.write_bytes(fixed)
    probe=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_entries','format=duration:stream=sample_rate,channels,codec_name','-of','json',str(runtime)]))
    stream=probe['streams'][0];assert stream['codec_name']=='vorbis' and stream['channels']==2
    shore=json.loads((ROOT/'source_art/r1/shore_reference.json').read_text())
    settings={'schema':1,'tag':tag,'path':'res://'+runtime.relative_to(ROOT).as_posix(),
        'bus_name':'PortAmbience','player_name':'WestCoastAmbience','loop':True,'loop_offset_seconds':0.0,
        'default_volume':.35,'volume_levels':[0.0,.35],'intro_fade_seconds':1.0,'volume_fade_seconds':.15,
        'near_distance_pixels':40,'far_distance_pixels':180,'far_gain_factor':.35,
        'shore_points':shore['measurements']['near_shore_outer_pixels'],
        'source_reference':'docs/r1_ambience_source_reference.json',
        'notes':['The original stereo recording is retained; distance changes gain, not stereo placement.',
                 'Ambience follows the effects volume/F8; music remains independent on F9.',
                 'Ambience continues during pose/water pause, and retains one player across F4.',
                 'Gain, fades and distance mapping are new sample interpretation.']}
    reference={'candidate':'R1/14','client':str(client),'tag':tag,'audio_xml_sha256':sha(xml),'xml_attributes':attributes,
        'map':{'path':map_reference['source_pvf'],'sha256':sha(raw_map),'crc':crc,'sound_tags':tags},
        'pack':{'name':pack.name,'bytes':pack.stat().st_size,'sha256':sha(pack.read_bytes())},'entry':entry,
        'source_bytes':len(raw),'source_sha256':sha(raw),'original':original.relative_to(ROOT).as_posix(),
        'runtime':runtime.relative_to(ROOT).as_posix(),'runtime_bytes':len(fixed),'runtime_sha256':sha(fixed),
        'metadata_fix':proof,'duration_seconds':float(probe['format']['duration']),
        'sample_rate':int(stream['sample_rate']),'channels':stream['channels'],'settings':settings}
    (ROOT/'data/port_ambience.json').write_text(json.dumps(settings,ensure_ascii=False,indent=2)+'\n')
    (ROOT/'docs/r1_ambience_source_reference.json').write_text(json.dumps(reference,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'tag':tag,'bytes':len(raw),'duration_seconds':reference['duration_seconds'],'noncomment_packets_identical':proof['all_noncomment_packets_identical']}))


if __name__=='__main__':main()
