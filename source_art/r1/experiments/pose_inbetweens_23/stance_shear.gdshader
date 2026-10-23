shader_type canvas_item;
render_mode unshaded;
uniform sampler2D source_texture : source_color,filter_nearest,repeat_disable;
uniform vec2 source_offset;
uniform vec2 source_size;
uniform vec2 foot_shift=vec2(0.0);
uniform sampler2D body_visibility : filter_nearest,repeat_disable;
uniform int kind=0;
uniform float hip_y=114.0;
uniform float ankle_y=158.0;

void fragment() {
	vec2 p=floor(UV*vec2(320.0,224.0))+vec2(0.5);
	if (kind==1) {
		float span=ankle_y-hip_y;
		float end_y=ankle_y+foot_shift.y;
		float source_y=p.y<=hip_y ? p.y : (p.y<end_y ? hip_y+(p.y-hip_y)/(1.0+foot_shift.y/span) : p.y-foot_shift.y);
		float weight=clamp((source_y-hip_y)/span,0.0,1.0);
		p=vec2(p.x-foot_shift.x*weight,source_y);
	} else if (kind==2) p-=foot_shift;
	vec2 q=(p-source_offset)/source_size;
	if (any(lessThan(q,vec2(0.0))) || any(greaterThanEqual(q,vec2(1.0)))) COLOR=vec4(0.0);
	else if (kind==3 && texture(body_visibility,UV).r<0.5) COLOR=vec4(0.0);
	else COLOR=texture(source_texture,q);
}
