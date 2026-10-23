shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;

uniform sampler2D source_texture : source_color, filter_nearest;
uniform float ground_y = 0.025;
varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 color = texture(source_texture, UV);
	ALBEDO = color.rgb;
	ALPHA = color.a;
	vec3 corrected = world_position;
	vec3 toward_camera = normalize(INV_VIEW_MATRIX[2].xyz);
	if (corrected.y < ground_y && toward_camera.y > 0.01) {
		corrected += toward_camera * ((ground_y + 0.02 - corrected.y) / toward_camera.y);
	}
	// The overlay and opaque actor share one upright plane. A 2 mm depth-only
	// margin prevents equal-depth fragments from dropping on the actor's sword.
	corrected += toward_camera * 0.002;
	vec4 projected = PROJECTION_MATRIX * VIEW_MATRIX * vec4(corrected, 1.0);
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		DEPTH = (projected.z / projected.w) * 0.5 + 0.5;
	#else
		DEPTH = projected.z / projected.w;
	#endif
}
