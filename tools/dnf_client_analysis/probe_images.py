from pathlib import Path
import json,sys,collections,hashlib
from PIL import Image,ImageDraw,ImageFont
from inspect_clients import *

FONT='/System/Library/Fonts/Hiragino Sans GB.ttc'
font=ImageFont.truetype(FONT,18)
small=ImageFont.truetype(FONT,13)
samples=[
 ('港口远景','sprite/map/hendonmyre/westfar00.img',0),
 ('港口中景','sprite/map/hendonmyre/westmid00.img',0),
 ('港口船只','sprite/map/hendonmyre/westnearship.img',0),
 ('西海岸过场图','sprite/map/cutscene/westcoast.img',0),
 ('莎兰','sprite/map/npc/npc_sr.img',0),
 ('萝莉安','sprite/map/npc/npc_lo.img',0),
 ('卡坤','sprite/map/npc/npc_kg.img',0),
 ('达芙妮','sprite/map/npc/npc_dp.img',0),
 ('罗杰','sprite/map/npc/npc_rg.img',0),
 ('奥菲利亚','sprite/map/npc/npc_op.img',0),
 ('艾丽丝','sprite/map/npc/npc_ir.img',0),
 ('萝莉安对话头像','sprite/map/npc/npcface01.img',11),
]
results=[]
canvases={}
for k,root in CLIENTS.items():
    entries=json.loads((OUT/k/'npk_index.json').read_text())
    # Explicit canonical packs, never assume runtime overlay order for mod packs.
    selected={e['path']:e for e in entries if e['pack'].startswith('sprite_') or e['pack']=='sprite.NPK'}
    panels=[]
    for label,path,index in samples:
        panel=Image.new('RGBA',(540,290),(28,34,42,255))
        d=ImageDraw.Draw(panel);d.text((14,10),label,font=font,fill='white')
        e=selected.get(path)
        if not e:d.text((14,48),'此规范包中未找到',font=font,fill='#f1ab8b');panels.append(panel);continue
        try:
            data=read_album(root,e);im,meta=decode_frame(data,index)
            if im.width>510 or im.height>216:im.thumbnail((510,216),Image.Resampling.LANCZOS)
            elif im.width<220 and im.height<108:im=im.resize((im.width*2,im.height*2),Image.Resampling.NEAREST)
            panel.alpha_composite(im,((540-im.width)//2,42+(216-im.height)//2))
            d.text((14,266),f"{meta['width']}×{meta['height']} / frame {index} / offset {meta['x']},{meta['y']}",font=small,fill='#bec8d7')
            results.append({'client':k,'label':label,'path':path,'pack':e['pack'],'frame':index,'metadata':meta,'sha256_img_payload':hashlib.sha256(data).hexdigest(),'success':True})
        except Exception as ex:
            results.append({'client':k,'path':path,'success':False,'error':str(ex)});d.text((14,60),str(ex)[:45],font=small,fill='orange')
        panels.append(panel)
    sheet=Image.new('RGB',(1080,80+len(panels)//2*290),(19,25,33))
    draw=ImageDraw.Draw(sheet);draw.text((20,15),f'{k} 包：实际解码素材抽样（规范 NPK；非游戏运行截图）',font=font,fill='white')
    draw.text((20,44),'保持原图透明度；大图缩小显示，小人物按整数倍显示。',font=small,fill='#b8c2cf')
    for i,panel in enumerate(panels):sheet.paste(panel,((i%2)*540,80+(i//2)*290))
    sheet.save(OUT/f'assets_{k}.png')
    canvases[k]=sheet
    # Compose a fixed starter appearance by matching frame indices and canvas offsets.
    layers=['skin/sm_body0000.img','pants/sm_pants0000a.img','shoes/sm_shoes0000a.img','coat/sm_coat0000a.img','hair/sm_hair0000a.img']
    strip=Image.new('RGBA',(1200,250),(28,34,42,255));dd=ImageDraw.Draw(strip)
    for j,frame in enumerate([0,8,19,25,50,105]):
        ch=Image.new('RGBA',(500,500))
        for layer in layers:
            path='sprite/character/swordman/equipment/avatar/'+layer
            if path not in selected:continue
            e=selected[path]
            try:
                im,meta=decode_frame(read_album(root,e),frame)
                ch.alpha_composite(im,(meta['x'],meta['y']))
                results.append({'client':k,'path':path,'frame':frame,'success':True,'metadata':meta})
            except Exception as ex:results.append({'client':k,'path':path,'frame':frame,'success':False,'error':str(ex)})
        crop=ch.crop((125,170,325,370))
        strip.alpha_composite(crop,(j*200,35));dd.text((j*200+10,8),f'帧 {frame}',font=font,fill='white')
    strip.convert('RGB').save(OUT/f'character_{k}.png')
save(OUT/'image_probe.json',results)
print('decoded',sum(r['success'] for r in results),'failed',[r for r in results if not r['success']])
