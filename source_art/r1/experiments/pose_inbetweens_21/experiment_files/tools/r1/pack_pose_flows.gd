extends SceneTree
## Losslessly pack numeric displacement fields as native texture resources.

func _initialize() -> void:
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/swordman_inbetweens.json"))
	var layer_arrays: Dictionary=pack_source_layers(data)
	var packed: Dictionary={}
	var changed: int=0
	var maps: Array=[]
	for pairs: Array in data["actions"].values():
		for pair: Dictionary in pairs:maps.append_array(pair["maps"])
	for pair: Dictionary in maps:
			var path: String=pair["texture"]
			if packed.has(path):continue
			var raw: PackedByteArray=FileAccess.get_file_as_bytes(pair["raw"])
			assert(raw.size()==320*224*8 and FileAccess.get_sha256(pair["raw"])==pair["raw_sha256"])
			var identical: bool=false
			if ResourceLoader.exists(path):
				var existing: Texture2D=load(path)
				identical=existing.get_image().get_format()==Image.FORMAT_RGBAH and existing.get_image().get_data()==raw
			if not identical:
				var image:=Image.create_from_data(320,224,false,Image.FORMAT_RGBAH,raw)
				var texture:=ImageTexture.create_from_image(image)
				assert(ResourceSaver.save(texture,path,ResourceSaver.FLAG_COMPRESS)==OK)
				changed+=1
			var actual: Texture2D=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
			assert(actual.get_image().get_data()==raw and not actual.get_image().has_mipmaps())
			packed[path]={"sha256":FileAccess.get_sha256(path),"raw_sha256":pair["raw_sha256"],"raw_bytes":raw.size(),
				"format":actual.get_image().get_format(),"size":[actual.get_width(),actual.get_height()]}
	var report: Dictionary={"candidate":"R1/21","resources":packed,"layer_arrays":layer_arrays,"numeric_fields":packed.size(),"changed":changed,
		"qa_source_sha256":get_script().source_code.sha256_text(),"runtime_data_sha256":FileAccess.get_sha256("res://data/swordman_inbetweens.json")}
	var out:=FileAccess.open("res://docs/r1_21_motion_pack.json",FileAccess.WRITE)
	out.store_string(JSON.stringify(report,"  "));out.close()
	print("Packed ",packed.size()," numeric fields; ",changed," changed. All half-float bytes exact.")
	quit()


func pack_source_layers(data: Dictionary) -> Dictionary:
	var source: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/swordman_r0.json"))
	var result: Dictionary={}
	var anchor:=Vector2i(data["foot_anchor"][0],data["foot_anchor"][1])
	for action: String in ["move","dash"]:
		for index: int in 8:
			var images: Array[Image]=[]
			var frame: Dictionary=source["animations"][action]["frames"][index]
			for layer: Dictionary in frame["layers"]:
				var original:=Image.new()
				assert(original.load_png_from_buffer(FileAccess.get_file_as_bytes(layer["texture"]))==OK)
				original.convert(Image.FORMAT_RGBA8)
				var aligned:=Image.create(320,224,false,Image.FORMAT_RGBA8)
				var point:=anchor+Vector2i(layer["offset"][0],layer["offset"][1])
				aligned.blit_rect(original,Rect2i(Vector2i.ZERO,original.get_size()),point)
				images.append(aligned)
			var path: String=data["actions"][action][index]["current_layers"]
			var array:=Texture2DArray.new()
			assert(array.create_from_images(images)==OK)
			assert(ResourceSaver.save(array,path,ResourceSaver.FLAG_COMPRESS)==OK)
			var actual: Texture2DArray=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
			for slot: int in images.size():assert(actual.get_layer_data(slot).get_data()==images[slot].get_data())
			result[path]={"sha256":FileAccess.get_sha256(path),"layers":images.size(),"size":[320,224],"rgba_exact":true}
	return result
