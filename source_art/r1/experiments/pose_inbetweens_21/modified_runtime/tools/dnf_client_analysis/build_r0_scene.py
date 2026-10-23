"""Create native, editable Godot scenes from the exported R0 metadata."""
import json
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[2]


def gd(value):
    return json.dumps(value, ensure_ascii=False)


class Scene:
    def __init__(self):
        self.resources = {}
        self.subresources = []
        self.nodes = []

    def resource(self, path, kind='Texture2D'):
        if path not in self.resources:
            self.resources[path] = (str(len(self.resources) + 1), kind)
        return f'ExtResource("{self.resources[path][0]}")'

    def node(self, name, kind, parent=None, **props):
        self.nodes.append(f'[node name={gd(name)} type={gd(kind)}' +
                          (f' parent={gd(parent)}' if parent is not None else '') + ']\n' +
                          '\n'.join(f'{k} = {v}' for k, v in props.items()))

    def sprite(self, name, parent, texture, offset):
        self.node(name, 'Sprite2D', parent, texture=self.resource(texture), centered='false',
                  position=f'Vector2({offset[0]}, {offset[1]})')

    def actor(self, name, parent, data, position, controllable=False, facing=1):
        content = json.loads((PROJECT / data).read_text())
        self.node(name, 'Node2D', parent,
                  script=self.resource('res://scripts/source_actor.gd', 'Script'),
                  animation_data=gd('res://' + data), controllable=str(controllable).lower(),
                  position=f'Vector2({position[0]}, {position[1]})',
                  texture_filter='1')
        path = parent + '/' + name
        self.node('Visual', 'Node2D', path, scale=f'Vector2({facing}, 1)')
        for l in content['animations']['stay']['frames'][0]['layers']:
            self.sprite(l['name'], path + '/Visual', l['texture'], l['offset'])

    def save(self, path):
        resources = '\n'.join(f'[ext_resource type={gd(kind)} path={gd(path)} id={gd(rid)}]'
                              for path, (rid, kind) in self.resources.items())
        (PROJECT / path).write_text('[gd_scene format=3]\n\n' + resources + '\n\n' +
                                    '\n\n'.join(self.subresources + self.nodes) + '\n')


def main():
    s = Scene()
    script = s.resource('res://scripts/west_coast_r0.gd', 'Script')
    s.subresources.append('''[sub_resource type="SystemFont" id="SystemFont_zh"]
font_names = PackedStringArray("PingFang SC", "Microsoft YaHei", "Noto Sans CJK SC")

[sub_resource type="StyleBoxFlat" id="ButtonNormal"]
bg_color = Color(0.12, 0.17, 0.22, 1)
border_width_bottom = 1
border_color = Color(0.36, 0.40, 0.43, 1)
content_margin_left = 11.0
content_margin_right = 11.0
content_margin_top = 5.0
content_margin_bottom = 5.0

[sub_resource type="StyleBoxFlat" id="ButtonHover"]
bg_color = Color(0.25, 0.29, 0.30, 1)
border_width_bottom = 2
border_color = Color(0.86, 0.71, 0.41, 1)
content_margin_left = 11.0
content_margin_right = 11.0
content_margin_top = 5.0
content_margin_bottom = 5.0

[sub_resource type="Theme" id="Theme_r0"]
default_font = SubResource("SystemFont_zh")
default_font_size = 12
Button/colors/font_color = Color(0.87, 0.88, 0.85, 1)
Button/styles/normal = SubResource("ButtonNormal")
Button/styles/hover = SubResource("ButtonHover")
Button/styles/pressed = SubResource("ButtonHover")''')
    s.node('WestCoastR0', 'Node2D', script=script)
    s.node('Backdrop', 'ColorRect', '.', offset_right='960.0', offset_bottom='540.0',
           color='Color(0.055, 0.085, 0.12, 1)', mouse_filter='2')
    s.node('PortClip', 'Control', '.', offset_left='32.0', offset_top='62.0',
           offset_right='928.0', offset_bottom='466.0', clip_contents='true', mouse_filter='2')
    s.node('World', 'Node2D', 'PortClip', position='Vector2(0, 43)', texture_filter='1')
    base = 'PortClip/World'
    world = json.loads((PROJECT / 'data/port_r0.json').read_text())
    s.node('Background', 'Node2D', base)
    for i, obj in enumerate(world['background']):
        s.sprite('Far' + str(i), base + '/Background', obj['texture'], obj['position'])
    for obj in world['objects']:
        if obj['source_layer'] == '[middleback]':
            for layer in obj['sequence']['frames'][0]['layers']:
                pos = [obj['anchor'][j] + layer['offset'][j] for j in [0, 1]]
                s.sprite('Mid', base + '/Background', layer['texture'], pos)
    s.node('Floor', 'Node2D', base)
    for i, obj in enumerate(world['floor']):
        s.sprite('Tile' + str(i), base + '/Floor', obj['texture'], obj['position'])
    s.node('PortProps', 'Node2D', base)
    for i, obj in enumerate(world['objects']):
        if obj['source_layer'] == '[middleback]':
            continue
        name = obj['name'] + '_' + str(i)
        frames = obj['sequence']['frames']
        props = {'position': f'Vector2({obj["anchor"][0]}, {obj["anchor"][1]})'}
        if len(frames) > 1:
            props['script'] = s.resource('res://scripts/source_prop.gd', 'Script')
            props['frames'] = 'Array[Dictionary](' + gd([
                {'offset': f['layers'][0]['offset'], 'duration_ms': f['duration_ms']} for f in frames]) + ')'
        s.node(name, 'Node2D', base + '/PortProps', **props)
        for layer in frames[0]['layers']:
            s.sprite('Image', base + '/PortProps/' + name, layer['texture'], layer['offset'])
    s.node('Actors', 'Node2D', base, y_sort_enabled='true')
    s.actor('Sharan', base + '/Actors', 'data/npc_sr_r0.json', [150, 267])
    s.actor('Lorian', base + '/Actors', 'data/npc_lo_r0.json', [285, 272])
    s.actor('Swordman', base + '/Actors', 'data/swordman_r0.json', [440, 320], True)
    s.node('Interface', 'CanvasLayer', '.', layer='10')
    for name, y1, y2 in [('Header', 0, 62), ('Footer', 466, 540)]:
        s.node(name, 'ColorRect', 'Interface', offset_top=str(float(y1)), offset_right='960.0',
               offset_bottom=str(float(y2)), color='Color(0.055, 0.085, 0.12, 0.98)', mouse_filter='2')
    s.node('GoldLine', 'ColorRect', 'Interface', offset_left='32.0', offset_top='60.0',
           offset_right='928.0', offset_bottom='61.0', color='Color(0.69, 0.53, 0.29, 0.6)', mouse_filter='2')

    def label(name, text, x, y, size=12, color='Color(0.83, 0.86, 0.87, 1)'):
        s.node(name, 'Label', 'Interface', text=gd(text), offset_left=str(float(x)),
               offset_top=str(float(y)), theme='SubResource("Theme_r0")',
               **{'theme_override_font_sizes/font_size': str(size),
                  'theme_override_colors/font_color': color, 'mouse_filter': '2'})

    label('Title', '西海岸  /  港口', 32, 10, 21, 'Color(0.94, 0.85, 0.64, 1)')
    label('Subtitle', '鬼剑士 · 原图与动作基准', 33, 38, 11)
    label('Build', 'R0   /   01', 856, 17, 13, 'Color(0.78, 0.65, 0.43, 1)')
    label('Status', '', 650, 39, 11)
    s.node('Compare', 'Button', 'Interface', text=gd('R1 混合 F4'),
           offset_left='453.0', offset_top='17.0', offset_right='566.0', offset_bottom='44.0',
           theme='SubResource("Theme_r0")', focus_mode='0')
    s.node('AudioMenu','OptionButton','Interface',offset_left='211.0',offset_top='17.0',
           offset_right='328.0',offset_bottom='44.0',theme='SubResource("Theme_r0")',focus_mode='0',
           tooltip_text=gd('人物动作与港口环境声音量；F8 静音或恢复，背景音乐由 F9 独立控制'))
    s.node('MusicMenu','OptionButton','Interface',offset_left='334.0',offset_top='17.0',
           offset_right='447.0',offset_bottom='44.0',theme='SubResource("Theme_r0")',focus_mode='0',
           tooltip_text=gd('背景音乐音量；F9 静音保留进度，音乐独立于动作暂停，F4 连续播放'))
    s.node('MoreActions','OptionButton','Interface',offset_left='650.0',offset_top='8.0',
           offset_right='824.0',offset_bottom='34.0',theme='SubResource("Theme_r0")',focus_mode='0',
           tooltip_text=gd('原始姿势预览；跳跃、倒地与防御中的长保持帧可用 F1 拖动选帧或 F3 逐帧查看'))
    label('Help', 'WASD 移动 · Shift 奔跑 · Space 跳跃 · X 攻击 · Q 动作 · R 复位 · Esc 自由 · Tab 界面', 32, 511, 11)
    s.node('PoseToggle','CheckButton','Interface',text=gd('补帧 F12'),
           offset_left='490.0',offset_top='506.0',offset_right='648.0',offset_bottom='536.0',
           theme='SubResource("Theme_r0")',**{'theme_override_font_sizes/font_size':'11'},
           focus_mode='0',button_pressed='true',tooltip_text=gd('行走／奔跑的30Hz运动补偿预览；保留800ms周期与原始帧，F12 开关对照'))
    s.node('MotionToggle','CheckButton','Interface',text=gd('平移 F11'),
           offset_left='650.0',offset_top='506.0',offset_right='780.0',offset_bottom='536.0',
           theme='SubResource("Theme_r0")',**{'theme_override_font_sizes/font_size':'11'},
           focus_mode='0',button_pressed='true',tooltip_text=gd('平滑角色移动与跳跃位置；F11 开关对照，动作原图与周期保持不变'))
    s.node('EffectsToggle','CheckButton','Interface',text=gd('特效 F10'),
           offset_left='782.0',offset_top='506.0',offset_right='928.0',offset_bottom='536.0',
           theme='SubResource("Theme_r0")',**{'theme_override_font_sizes/font_size':'11'},
           focus_mode='0',button_pressed='true',tooltip_text=gd('崩山击刀光与落地特效；F10 开关。动作演示，无伤害判定'))
    label('Inspector', '', 46, 76, 12, 'Color(0.93, 1, 1, 1)')
    s.nodes[-1] += '\nvisible = false\ntheme_override_colors/font_shadow_color = Color(0, 0, 0, 1)\ntheme_override_constants/shadow_offset_x = 1\ntheme_override_constants/shadow_offset_y = 1'
    s.node('FrameSlider','HSlider','Interface',offset_left='46.0',offset_top='164.0',
           offset_right='266.0',offset_bottom='184.0',min_value='0.0',max_value='5.0',step='1.0',
           visible='false',focus_mode='0',mouse_default_cursor_shape='2')
    label('FrameLabel','',46,187,11,'Color(0.93, 1, 1, 1)')
    s.nodes[-1] += '\nvisible = false\ntheme_override_colors/font_shadow_color = Color(0, 0, 0, 1)\ntheme_override_constants/shadow_offset_x = 1\ntheme_override_constants/shadow_offset_y = 1'
    s.node('Buttons', 'HBoxContainer', 'Interface', offset_left='32.0', offset_top='477.0',
           offset_right='928.0', offset_bottom='503.0', theme='SubResource("Theme_r0")',
           **{'theme_override_constants/separation': '5'})
    for name, text in [('Free', '自由'),('Jump','跳跃 Space'), ('Action0', '1 待机'), ('Action1', '2 行走'),
                       ('Action2', '3 奔跑'), ('Action3', '4 普攻一'), ('Action4', '5 普攻二'),
                       ('Action5', '6 崩山击'), ('Pause', '暂停 F2'), ('Step', '逐帧 F3'), ('Markers', '脚底 F1'),('Facing','转向 F7')]:
        s.node(name, 'Button', 'Interface/Buttons', text=gd(text), focus_mode='0', mouse_default_cursor_shape='2')
    s.save('scenes/west_coast_r0.tscn')
    print('Saved scenes/west_coast_r0.tscn (editable scene tree, independent sprite layers)')


if __name__ == '__main__':
    main()
