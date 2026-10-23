shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
instance uniform float height_ratio = 0.0;

void fragment() {
	vec2 d = (UV - vec2(0.5)) * 2.0;
	ALBEDO = vec3(0.12, 0.14, 0.17);
	ALPHA = exp(-3.8 * dot(d, d)) * mix(0.27, 0.12, clamp(height_ratio, 0.0, 1.0));
}
