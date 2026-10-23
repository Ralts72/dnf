// Motion-compensated nearest-source sampling. No silhouette cross-fade.
uniform sampler2D next_texture : source_color, filter_nearest, repeat_disable;
uniform sampler2D pose_flow : filter_linear, repeat_disable;
uniform float pose_phase = 0.0;
uniform vec2 pose_size = vec2(320.0, 224.0);

vec4 pose_source(sampler2D source, vec2 pixel) {
	vec2 uv = (pixel + vec2(0.5)) / pose_size;
	if (any(lessThan(uv, vec2(0.0))) || any(greaterThanEqual(uv, vec2(1.0)))) return vec4(0.0);
	return texture(source, uv);
}

vec4 pose_vectors(vec2 pixel) {
	return texture(pose_flow, (pixel + vec2(0.5)) / pose_size);
}

vec4 sample_pose(sampler2D source, vec2 uv) {
	if (pose_phase <= 0.0) return texture(source, uv);
	vec2 pixel = uv * pose_size - vec2(0.5);
	vec2 a = pixel;
	vec2 b = pixel;
	for (int i = 0; i < 4; i++) {
		a = pixel - pose_phase * pose_vectors(a).rg;
		b = pixel - (1.0 - pose_phase) * pose_vectors(b).ba;
	}
	vec4 ca = pose_source(source, a);
	vec4 cb = pose_source(next_texture, b);
	return pose_phase < 0.5 ? ca : cb;
}
