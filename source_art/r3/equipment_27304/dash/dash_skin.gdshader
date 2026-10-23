shader_type canvas_item;
render_mode unshaded;
uniform sampler2D source_texture : source_color,filter_nearest,repeat_disable;
uniform sampler2D part_visibility : filter_nearest,repeat_disable;
uniform vec2 source_offset;
uniform vec2 source_size;
uniform vec2 source_shift=vec2(0.0);
uniform int kind=0;
uniform float hip_y=115.0;
uniform float waist_overlap=3.0;
varying vec2 target_position;

void vertex() { target_position=VERTEX; }

void fragment() {
	vec2 p=UV*vec2(320.0,224.0)-source_shift;
	vec2 uv=(p-source_offset)/source_size;
	bool outside=any(lessThan(uv,vec2(0.0))) || any(greaterThanEqual(uv,vec2(1.0)));
	vec4 value=outside ? vec4(0.0) : texture(source_texture,uv);
	if (kind==1 && (p.y<hip_y || target_position.y<hip_y)) value.a=0.0;
	if (kind==2 && p.y>=hip_y+waist_overlap) value.a=0.0;
	if (kind==1 || kind==3 || kind==4) value.a*=texture(part_visibility,p/vec2(320.0,224.0)).r;
	COLOR=value;
}
