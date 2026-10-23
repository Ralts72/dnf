shader_type canvas_item;
render_mode unshaded;

uniform sampler2D source_texture : source_color, filter_nearest, repeat_disable;
#include "res://shaders/pose_inbetween.gdshaderinc"

void fragment() {
	COLOR = sample_pose(source_texture, UV);
}
