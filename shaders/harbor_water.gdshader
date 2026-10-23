shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;

uniform float water_time = 0.0;
uniform float phase_steps_per_second = 8.0;
uniform vec2 shore_start = vec2(449.0,190.0);
uniform vec2 shore_bend = vec2(673.0,254.0);
uniform vec2 shore_end = vec2(958.0,254.0);
uniform vec4 far_pier_bounds = vec4(510.0,135.0,958.0,153.0);
uniform vec4 middle_pier_bounds = vec4(510.0,175.0,958.0,187.0);
uniform vec4 deep : source_color;
uniform vec4 shade : source_color;
uniform vec4 blue : source_color;
uniform vec4 body_dark : source_color;
uniform vec4 body : source_color;
uniform vec4 cyan : source_color;
uniform vec4 ripple : source_color;
uniform vec4 glint : source_color;
uniform vec4 foam : source_color;
varying vec3 world_position;

float hash_cell(vec2 p) {
	return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);
}

float segment_distance(vec2 p,vec2 a,vec2 b) {
	vec2 d=b-a;
	return length(p-a-d*clamp(dot(p-a,d)/dot(d,d),0.0,1.0));
}

float rectangle_distance(vec2 p,vec4 bounds) {
	return length(max(max(bounds.xy-p,p-bounds.zw),vec2(0.0)));
}

void vertex() {
	world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
}

void fragment() {
	// Fixed source-pixel grid on the existing native surface, independent of F6.
	vec2 ground_pixel=vec2(world_position.x*60.0+448.0,
		159.0+(world_position.z+1.6)*36.9396885);
	vec2 pixel=floor(ground_pixel-vec2(0.0,(world_position.y-0.025)*47.2806452));
	ground_pixel=pixel+vec2(0.5,0.5+(world_position.y-0.025)*47.2806452);
	float edge=min(segment_distance(ground_pixel,shore_start,shore_bend),
		segment_distance(ground_pixel,shore_bend,shore_end));
	edge=min(edge,rectangle_distance(ground_pixel,far_pier_bounds));
	edge=min(edge,rectangle_distance(ground_pixel,middle_pier_bounds));
	vec3 color=body.rgb;
	if(edge<2.0) color=deep.rgb;
	else if(edge<4.0) color=shade.rgb;
	else if(edge<6.0) color=blue.rgb;
	else if(edge<8.0) color=body_dark.rgb;
	float clock=floor(water_time*phase_steps_per_second)/phase_steps_per_second;
	float row=floor((pixel.y+floor(clock*0.45))/5.0);
	float line=mod(pixel.y+floor(clock*0.45),5.0);
	float drift=floor(clock*(1.3+hash_cell(vec2(row,7.0))*0.8));
	float block=floor((pixel.x+drift)/32.0);
	float part=mod(pixel.x+drift,32.0);
	float seed=hash_cell(vec2(block,row));
	float width=6.0+floor(seed*18.0);
	if(edge>6.0 && seed>0.42 && part<width) {
		if(line<1.0) color=edge<23.0 ? (seed>0.76 ? foam.rgb : glint.rgb) : ripple.rgb;
		else if(line<2.0 && part>2.0 && part<width-2.0) color=cyan.rgb;
	}
	ALBEDO=color;
}
