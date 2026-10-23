shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform sampler2D source_texture : source_color, filter_nearest, repeat_disable;
uniform float ground_y = 0.025;
#include "res://shaders/pose_inbetween.gdshaderinc"
varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 color = sample_pose(source_texture, UV);
	ALBEDO = color.rgb;
	ALPHA = color.a;
	ALPHA_SCISSOR_THRESHOLD = 0.25;
	// Source weapons and toes sometimes extend below the logical foot anchor.
	// Shift only their depth to the ground along the view ray, preserving pixels
	// on screen while retaining native depth occlusion against taller geometry.
	vec3 corrected = world_position;
	vec3 toward_camera = normalize(INV_VIEW_MATRIX[2].xyz);
	if (corrected.y < ground_y && toward_camera.y > 0.01) {
		// Leave a small depth margin for MSAA's per-sample floor depth. Without
		// it, toes and prone poses partly blend with the floor at some samples.
		corrected += toward_camera * ((ground_y + 0.02 - corrected.y) / toward_camera.y);
	}
	vec4 projected = PROJECTION_MATRIX * VIEW_MATRIX * vec4(corrected, 1.0);
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		DEPTH = (projected.z / projected.w) * 0.5 + 0.5;
	#else
		DEPTH = projected.z / projected.w;
	#endif
}
