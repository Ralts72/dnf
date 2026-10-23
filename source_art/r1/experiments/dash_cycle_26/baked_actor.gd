extends Node2D
## Lightweight native playback of the validated1x PNG samples.

var recipe: Dictionary
var textures: Array[Texture2D]=[]
var sprite: Sprite2D
var frame_index: int=-1
var subframe: int=-1

func _ready() -> void:
	recipe=JSON.parse_string(FileAccess.get_file_as_string("res://source_art/r1/experiments/dash_cycle_26/dash_recipe.json"))
	for frame: int in 8:
		for sub: int in 3:
			var image:=Image.new();assert(image.load_png_from_buffer(FileAccess.get_file_as_bytes("res://source_art/r1/experiments/dash_cycle_26/baked/dash_%02d_%d.png"%[frame,sub]))==OK)
			textures.append(ImageTexture.create_from_image(image))
	sprite=Sprite2D.new();sprite.centered=false;sprite.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;add_child(sprite)
	update_pose(0,0)

func update_pose(frame: int,sub: int) -> void:
	frame_index=frame;subframe=sub;sprite.texture=textures[frame*3+sub]
