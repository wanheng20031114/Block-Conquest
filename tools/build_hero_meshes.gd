extends SceneTree
## Offline conversion of this hero only, with no scene factories at runtime.
func _initialize() -> void:
	var material := ShaderMaterial.new()
	material.shader = load("res://assets/models/heroes/hero_surface.gdshader")
	ResourceSaver.save(material,"res://assets/models/heroes/hero_surface.tres")
	for folder: String in ["res://assets/models/heroes/capsule", "res://assets/models/weapons/repeating_musket"]:
		var parts: Array = JSON.parse_string(FileAccess.get_file_as_string(folder+"/parts.json"))
		for part: String in parts:
			var document := GLTFDocument.new()
			var state := GLTFState.new()
			assert(document.append_from_file(folder+"/"+part+".glb",state)==OK)
			var scene := document.generate_scene(state)
			var nodes := scene.find_children("*","MeshInstance3D",true,false)
			assert(nodes.size()==1)
			var mesh: ArrayMesh = nodes[0].mesh
			for surface: int in mesh.get_surface_count(): mesh.surface_set_material(surface,material)
			assert(ResourceSaver.save(mesh,folder+"/"+part+".res",ResourceSaver.FLAG_COMPRESS)==OK)
			scene.free()
	print("Hero meshes baked")
	quit()
