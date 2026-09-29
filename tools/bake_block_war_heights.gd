extends SceneTree
## Save spline-authored data as native Resource, RF texture and ArrayMesh.
## https://docs.godotengine.org/en/stable/classes/class_arraymesh.html

const INPUT := "res://.local/natural-terrain/"
const OUTPUT := "res://assets/block_war/environment/maps/"

func _initialize() -> void:
	for map_id: String in ["terraces", "switchback", "crown"]:
		if not OS.get_cmdline_user_args().is_empty() and map_id not in OS.get_cmdline_user_args(): continue
		_bake(map_id)
	quit()

func _bake(map_id: String) -> void:
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(INPUT + map_id + ".json"))
	var bytes := FileAccess.get_file_as_bytes(INPUT + map_id + ".rf")
	var field := WarTerrainSurface.new()
	field.origin = Vector2(meta.origin[0], meta.origin[1])
	field.cell_size = meta.cell_size
	field.width = int(meta.width)
	field.depth = int(meta.depth)
	field.heights = bytes.to_float32_array()
	field.max_height = meta.max_height
	for i: int in range(0, meta.ramp_guides.size(), 4):
		field.ramp_guides.append(Vector4(meta.ramp_guides[i], meta.ramp_guides[i+1], meta.ramp_guides[i+2], meta.ramp_guides[i+3]))
	for i: int in range(0, meta.labels.size(), 3):
		field.label_positions.append(Vector3(meta.labels[i],meta.labels[i+1],meta.labels[i+2]))
	field.height_texture = ImageTexture.create_from_image(Image.create_from_data(field.width, field.depth, false, Image.FORMAT_RF, bytes))
	var preview := Image.create(field.width, field.depth, false, Image.FORMAT_RGBA8)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	vertices.resize(field.width * field.depth)
	normals.resize(vertices.size())
	for z: int in field.depth:
		for x: int in field.width:
			var index := z * field.width + x
			var h := field.heights[index]
			var dx := (field.heights[z * field.width + mini(x+1,field.width-1)] - field.heights[z * field.width + maxi(x-1,0)]) / (field.cell_size * (1.0 if x in [0,field.width-1] else 2.0))
			var dz := (field.heights[mini(z+1,field.depth-1)*field.width+x] - field.heights[maxi(z-1,0)*field.width+x]) / (field.cell_size * (1.0 if z in [0,field.depth-1] else 2.0))
			vertices[index] = Vector3(field.origin.x + x * field.cell_size, h, field.origin.y + z * field.cell_size)
			normals[index] = Vector3(-dx,1,-dz).normalized()
			var shade := clampf(normals[index].dot(Vector3(-0.5, 1, -0.6).normalized()), 0.15, 1.0)
			var ink := Color("abb88a").lerp(Color("829d71"), h / maxf(field.max_height,1.0))
			ink = ink.darkened((1.0-shade)*0.38)
			ink.a = smoothstep(0.01,0.35,h)
			preview.set_pixel(x,z,ink)
	field.preview_texture = ImageTexture.create_from_image(preview)
	DirAccess.make_dir_recursive_absolute("res://data/block_war/terrain")
	assert(ResourceSaver.save(field,"res://data/block_war/terrain/" + map_id + ".res",ResourceSaver.FLAG_COMPRESS) == OK)
	var indices := PackedInt32Array()
	for z: int in range(field.depth-1):
		for x: int in range(field.width-1):
			var point := field.origin + Vector2(x+0.5,z+0.5) * field.cell_size
			var water := false
			for rect: Array in meta.water:
				if Rect2(rect[0],rect[1],rect[2],rect[3]).has_point(point): water = true
			if water: continue
			var a := z*field.width+x
			var b := a+1
			var c := a+field.width
			var d := c+1
			# Godot clockwise front faces, with the shared CPU/GPU b--c diagonal.
			indices.append_array(PackedInt32Array([a,b,c,b,d,c]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_INDEX]=indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	assert(ResourceSaver.save(mesh,OUTPUT+map_id+"_upland.res",ResourceSaver.FLAG_COMPRESS)==OK)
	print("NATURAL_TERRAIN_BAKED ",map_id," grid=",field.width,"x",field.depth," triangles=",indices.size()/3)
