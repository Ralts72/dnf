from inspect_clients import *
import posixpath

p=PVF(CLIENTS['95']/'Script.pvf');p.load_strings()
images={}
for k in CLIENTS:
    es=json.loads((OUT/k/'npk_index.json').read_text())
    images[k]={e['path']:e for e in es if e['pack'].startswith('sprite_') or e['pack']=='sprite.NPK'}
trans={}
lst=p.tokens('n_string.lst','big5')
for a,b in zip(lst[::2],lst[1::2]):
    file=b.get('text','').lower()
    if file in p.entries:
        text=p.read(file).decode('big5','replace')
        trans[a['value']]={line.split('>',1)[0]:line.split('>',1)[1] for line in text.splitlines() if '>' in line and not line.startswith('//')}

def resolved(tokens):
    out=[];listid=None
    for t in tokens:
        x=t.copy()
        if t['type']==9:listid=t['value']
        if t['type']==10:x['resolved']=trans.get(listid,{}).get(t.get('text',''))
        out.append(x)
    return out

names=[
 'town/westcoast.twn',
 'map/hendonmyre/(f)westcoast.map','map/hendonmyre/(r)westcoast.map',
 'map/hendonmyre/(f)westcoast_magic.map','map/hendonmyre/(r)westcoast_magic.map',
 'map/hendonmyre/(f)gate_west.map','map/hendonmyre/(r)gate_west.map',
 'map/hendonmyre/d_westcoast.map','map/hendonmyre/d_westcoast2.map',
 'map/hendonmyre/sky_westcoast.map','map/hendonmyre/sky_westcoast2.map',
 'map/hendonmyre/west2death.map','map/hendonmyre/west2fallen.map','map/hendonmyre/west2stranger.map','map/hendonmyre/west_ura.map',
 'dungeon/act2/draconiantower.dgn','dungeon/act2/hallofdoll.dgn','dungeon/act2/golemtower.dgn','dungeon/act2/darkentrance.dgn','dungeon/act2/palaceofload.dgn','dungeon/act2/floatingcastle.dgn',
 'skill/swordman/hopsmash.skl','skill/swordman/tripleslash.skl','skill/swordman/upperslash.skl',
 'n_quest/westcost/draconiantower/epic_16_draconiantower_skycastle_1.qst',
 'n_quest/westcost/draconiantower/epic_16_draconiantower_skycastle_2.qst',
 'monster/newmonsters/draconian/magneus/ai/action.ai',
 'character/swordman/swordman.chr',
]
names += ['npc/'+n+'.npc' for n in ['seria','sharan','lorian','kagon','roger','daphne','iris','ophelia','marlene_arad']]
checks=[];all_tokens={}
for name in names:
    if name not in p.entries:
        checks.append({'path':name,'exists':False});continue
    data,crc=p.read(name,True)
    tokens=p.tokens(name,'big5')
    if isinstance(tokens,list):tokens=resolved(tokens)
    all_tokens[name]=tokens
    result={'path':name,'exists':True,'bytes':len(data),'crc_matches':crc['expected']==crc['actual_seed_file_number'],'crc':crc,'decoded_kind':'tokens' if isinstance(tokens,list) else 'binary','token_count':len(tokens) if isinstance(tokens,list) else None}
    checks.append(result)
    save(OUT/'95'/'samples'/(name.replace('/','__')+'.json'),{**result,'tokens':tokens})

ani_names=['character/swordman/animation/'+n+'.ani' for n in ['stay','attack1','attack2','dash','hopsmash']]
ani_names+=['npc/animation/npc_'+n+'.ani' for n in ['sr','lo','kg','rg','dp','ir','op']]
ani_checks=[]
for name in ani_names:
    try:
        data,crc=p.read(name,True);a=binary_ani(data)
        save(OUT/'95'/'samples'/(name.replace('/','__')+'.decoded.json'),a)
        paths=[r.replace('%04d','0000') for r in a['resources']]
        ac={'path':name,'success':True,'frames':a['frames_count'],'resources':paths,'total_boxes':sum(len(f['boxes']) for f in a['frames']),'frame_delays':[next((z['value'] for z in f['properties'] if z['type']==12),None) for f in a['frames']],'crc_matches':crc['expected']==crc['actual_seed_file_number'],'images_in_70':all('sprite/'+r in images['70'] for r in paths),'images_in_95':all('sprite/'+r in images['95'] for r in paths)}
    except Exception as ex:ac={'path':name,'success':False,'error':str(ex)}
    ani_checks.append(ac)

# Resolve a representative old street's actual ANI/TIL -> IMG references.
closure={}
for mapname in ['map/hendonmyre/(f)westcoast.map','map/hendonmyre/(f)westcoast_magic.map']:
    todo=[mapname];seen=set();missing=[];fail=[];imgrefs=set();crc_bad=[]
    while todo:
        name=todo.pop()
        if name in seen:continue
        seen.add(name)
        if name not in p.entries:missing.append(name);continue
        data,crc=p.read(name,True)
        if crc['expected']!=crc['actual_seed_file_number']:crc_bad.append(name)
        if name.endswith('.ani'):
            try:refs=binary_ani(data)['resources']
            except Exception as ex:fail.append({'path':name,'error':str(ex)});continue
        else:
            toks=p.tokens(name,'big5')
            refs=[t.get('text','').lower() for t in toks if t['type']==7 and any(t.get('text','').lower().endswith(s) for s in ['.til','.ani','.img'])] if isinstance(toks,list) else []
        for ref in refs:
            if ref.endswith('.img'):
                imgrefs.add(ref if ref.startswith('sprite/') else 'sprite/'+ref)
            else:todo.append(posixpath.normpath(posixpath.join(posixpath.dirname(name),ref.lower())))
    closure[mapname]={'visited_script_count':len(seen),'missing_pvf':sorted(set(missing)),'parse_failures':fail,'crc_failures':crc_bad,'image_reference_count':len(imgrefs),'missing_images_70':sorted(imgrefs-images['70'].keys()),'missing_images_95':sorted(imgrefs-images['95'].keys()),'image_references':sorted(imgrefs)}

# Check audio payload signatures without playing files.
audio=[]
for k,root in CLIENTS.items():
    music=[f for f in (root/'Music').iterdir() if f.is_file() and any(s in f.name.lower() for s in ['west','hendon','sky','town'])]
    sound_packs=sorted((root/'SoundPacks').glob('*.npk'))
    sounds=[];sound_errors=[]
    for f in sound_packs:
        try:sounds.extend(npk_entries(f,False))
        except Exception as ex:sound_errors.append({'pack':f.name,'error':str(ex)})
    examples=[]
    for s in sounds[:3]:
        f=root/'SoundPacks'/s['pack']
        with f.open('rb') as h:h.seek(s['offset']);sig=h.read(8)
        examples.append({'pack':s['pack'],'path':s['path'],'signature_hex':sig.hex()})
    audio.append({'client':k,'music_candidates':[f.name for f in music],'sound_packs':len(sound_packs),'sound_entries':len(sounds),'errors':sound_errors,'header_samples':examples})

out={'sample_scripts':checks,'animation_probes':ani_checks,'map_dependency_probes':closure,'audio':audio,'translation_encoding':'Big5 for inspected 95 PVF string dictionaries','notes':['CRC verifies bytes, not gameplay correctness or historical version.','Map filename (f)/(r) selection rules not executed or confirmed.','NPK mod precedence not reproduced; image samples use explicit canonical packs.']}
save(OUT/'content_probe.json',out)
print('sample scripts',len(checks),'present',sum(e.get('exists',False) for e in checks),'crc pass',sum(e.get('crc_matches',False) for e in checks))
print('ANI',json.dumps(ani_checks,ensure_ascii=False))
print('dependency',json.dumps(closure,ensure_ascii=False))
print('audio',json.dumps(audio,ensure_ascii=False))
