// Motion-compensated nearest-source sampling. No silhouette cross-fade.
uniform sampler2D next_texture : source_color, filter_nearest, repeat_disable;
uniform sampler2DArray current_layers : source_color, filter_nearest, repeat_disable;
uniform sampler2DArray next_layers : source_color, filter_nearest, repeat_disable;
uniform sampler2D pose_flow : filter_nearest, repeat_disable;
uniform float pose_phase = 0.0;
uniform vec2 pose_size = vec2(320.0, 224.0);

vec4 pose_source(sampler2D source, vec2 pixel) {
	vec2 uv = (pixel + vec2(0.5)) / pose_size;
	if (any(lessThan(uv, vec2(0.0))) || any(greaterThanEqual(uv, vec2(1.0)))) return vec4(0.0);
	return texture(source, uv);
}

vec4 sample_pose(sampler2D source, vec2 uv) {
	if (pose_phase <= 0.0) return texture(source, uv);
	vec4 mapping = texture(pose_flow, uv);
	if (mapping.b < 0.5) return vec4(0.0);
	vec2 source_uv = (mapping.rg + vec2(0.5)) / pose_size;
	vec3 layer_uv = vec3(source_uv, mapping.b - 1.0);
	return mapping.a < 0.5 ? texture(current_layers, layer_uv) : texture(next_layers, layer_uv);
}
