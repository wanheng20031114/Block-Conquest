extends SceneTree
## Offline conversion only. Runtime instantiates saved native PackedScenes.
## GLTFDocument: https://docs.godotengine.org/en/stable/classes/class_gltfdocument.html

const DIRECTORY := "res://assets/campaign/reference_railway/"
## Campaign station names adapt the reference signs without changing its source.
const CAMPAIGN_SIGN_NAMES := {"花田站": "水间花池", "橡木镇": "双径森林"}
var manifest: Dictionary

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	manifest = JSON.parse_string(FileAccess.get_file_as_string(DIRECTORY + "manifest.json"))
	DirAccess.make_dir_recursive_absolute(DIRECTORY + "native")
	var selected_assets := PackedStringArray()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--only="):
			selected_assets = argument.trim_prefix("--only=").split(",")
	for key: String in manifest.assets:
		if not selected_assets.is_empty() and key not in selected_assets:
			continue
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		var error := document.append_from_file(DIRECTORY + manifest.assets[key].file, state)
		if error != OK:
			push_error("GLTF conversion failed: " + key)
			quit(1)
			return
		var model := document.generate_scene(state)
		_prepare_materials(model)
		var packed := PackedScene.new()
		assert(packed.pack(model) == OK)
		assert(ResourceSaver.save(packed, DIRECTORY + "native/" + key + ".scn", ResourceSaver.FLAG_COMPRESS) == OK)
		print("BAKED ", key)
		model.free()
	_build_landscape()
	print("REFERENCE_RAILWAY_BAKE_COMPLETE")
	quit()

func _prepare_materials(node: Node) -> void:
	if node is MeshInstance3D:
		# Native visibility ranges keep grain-level flower geometry close to the
		# camera. Both levels are saved resources, never generated at runtime.
		if String(node.name).begins_with("DetailedFlowers"):
			node.visibility_range_end = 35.0
		if String(node.name).begins_with("DistantFlowers"):
			node.visibility_range_begin = 35.0
		for index: int in node.mesh.get_surface_count():
			var material: StandardMaterial3D = node.mesh.surface_get_material(index)
			if material:
				# Three.js already linearizes setHex vertex colors before export.
				material.vertex_color_use_as_albedo = bool(node.mesh.surface_get_format(index) & Mesh.ARRAY_FORMAT_COLOR)
				material.vertex_color_is_srgb = false
				material.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
				material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
				material.roughness = 1.0
				material.metallic = 0.0
	for child: Node in node.get_children():
		_prepare_materials(child)

func _add(parent: Node, node: Node, name: String, scene: Node) -> Node:
	parent.add_child(node)
	node.name = name
	node.owner = scene
	return node

func _point(distance: float) -> Vector3:
	var samples: Array = manifest.path.samples
	for index: int in range(1, samples.size()):
		var b: Dictionary = samples[index]
		if b.s >= distance:
			var a: Dictionary = samples[index - 1]
			return Vector3(a.x, a.y, a.z).lerp(Vector3(b.x, b.y, b.z), (distance - a.s) / (b.s - a.s))
	return Vector3.ZERO

func _build_landscape() -> void:
	var scene := Node3D.new()
	scene.name = "Landscape"
	scene.set_meta("source", "medieval-voxel-railway / original geometry")
	scene.set_meta("world_size", Vector2(168, 40))
	for pair: Array in [["terrain", "ReferenceTerrain"], ["props", "ReferenceProps"], ["track", "ReferenceTrack"], ["water", "ReferenceWater"], ["campaign_stations", "ReferenceStations"], ["hydrangeas", "HydrangeaGarden"]]:
		var packed: PackedScene = load(DIRECTORY + "native/" + pair[0] + ".scn")
		_add(scene, packed.instantiate(), pair[1], scene)
	var anchors := _add(scene, Node3D.new(), "StageAnchors", scene)
	var parking := _add(scene, Node3D.new(), "ParkAnchors", scene)
	var park_s: Array = [26.0, 75.36412780356204, 100.628256, 122.628256, 145.833415, 170.35651121424797]
	var label_s: Array = [14.0, 66.06412780356204, 100.628256, 119.378256, 140.0, 162.75651121424797]
	for index: int in 6:
		var label: Marker3D = _add(anchors, Marker3D.new(), "Stage%02d" % (index + 1), scene)
		label.position = _point(label_s[index]) + Vector3(0, 0.8, 1.7)
		var park: Marker3D = _add(parking, Marker3D.new(), "Stage%02d" % (index + 1), scene)
		park.position = _point(park_s[index])
		park.set_meta("source_s", park_s[index])
	var curve := Curve3D.new()
	curve.bake_interval = 0.1
	for point: Dictionary in manifest.path.samples:
		curve.add_point(Vector3(point.x, point.y, point.z))
	assert(ResourceSaver.save(curve, "res://data/campaign/journey_3d.tres") == OK)
	curve.take_over_path("res://data/campaign/journey_3d.tres")
	var journey: Path3D = _add(scene, Path3D.new(), "Journey", scene)
	journey.curve = curve
	var names := ["Train", "Tender", "Coach", "Car04", "Car05", "Car06", "Car07", "Car08", "Car09"]
	for car: Dictionary in manifest.train.cars:
		var follower: PathFollow3D = _add(journey, PathFollow3D.new(), names[car.index], scene)
		follower.loop = false
		follower.rotation_mode = PathFollow3D.ROTATION_XYZ
		follower.set_meta("rail_offset", car.offset)
		follower.progress = curve.get_closest_offset(_point(26)) - car.offset
		var packed: PackedScene = load(DIRECTORY + "native/car_%02d.scn" % car.index)
		var model: Node3D = _add(follower, packed.instantiate(), "Model", scene)
		model.rotation.y = PI / 2.0
	var signs := _add(scene, Node3D.new(), "Signs", scene)
	var font: Font = load("res://assets/ui/medieval/fonts/body.tres")
	for index: int in manifest.signs.size():
		var sign: Dictionary = manifest.signs[index]
		var label: Label3D = _add(signs, Label3D.new(), "Sign%02d" % index, scene)
		label.text = CAMPAIGN_SIGN_NAMES.get(sign.text, sign.text)
		label.font = font
		label.font_size = 64
		label.outline_size = 0
		label.pixel_size = minf(sign.height * 0.65 / 64.0, sign.width * 0.88 / (maxi(1, label.text.length()) * 64.0))
		label.modulate = Color(sign.fg)
		label.shaded = true
		var q: Array = sign.quaternion
		label.quaternion = Quaternion(q[0], q[1], q[2], q[3])
		label.position = Vector3(sign.position[0], sign.position[1], sign.position[2]) + label.basis.z * 0.012
	_add_smoke(scene)
	_add_ambient_animation(scene)
	var animation := Animation.new()
	animation.length = 2.0
	animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(0, NodePath(".:position"))
	animation.track_insert_key(0, 0, Vector3(0, -1.2, 0))
	animation.track_insert_key(0, 2, Vector3.ZERO)
	var library := AnimationLibrary.new()
	library.add_animation("unfold", animation)
	var entrance: AnimationPlayer = _add(scene, AnimationPlayer.new(), "Entrance", scene)
	entrance.add_animation_library("", library)
	var packed := PackedScene.new()
	assert(packed.pack(scene) == OK)
	assert(ResourceSaver.save(packed, "res://scenes/campaign/campaign_landscape.tscn") == OK)
	scene.free()

func _add_ambient_animation(scene: Node3D) -> void:
	var motion := Animation.new()
	motion.length = 12.0
	motion.loop_mode = Animation.LOOP_LINEAR
	var blades := "ReferenceProps/ReferenceDynamicProps/ReferenceWindmillBlades0:rotation:z"
	motion.add_track(Animation.TYPE_VALUE)
	motion.track_set_path(0, NodePath(blades))
	motion.track_insert_key(0, 0.0, 0.0)
	motion.track_insert_key(0, 12.0, TAU)
	for index: int in manifest.dynamics.flags:
		var track := motion.add_track(Animation.TYPE_VALUE)
		motion.track_set_path(track, NodePath("ReferenceProps/ReferenceDynamicProps/ReferenceFlag%d:rotation:y" % index))
		for key: int in 13:
			motion.track_insert_key(track, float(key), sin(key * PI * 0.5 + index) * 0.055)
	var library := AnimationLibrary.new()
	library.add_animation("breeze", motion)
	var player: AnimationPlayer = _add(scene, AnimationPlayer.new(), "Ambient", scene)
	player.add_animation_library("", library)
	player.autoplay = "breeze"

func _add_smoke(scene: Node3D) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.92, 0.93, 0.94, 0.55)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var puff := SphereMesh.new()
	puff.radius = 0.18
	puff.height = 0.36
	puff.radial_segments = 6
	puff.rings = 3
	puff.material = material
	var particles: CPUParticles3D = _add(scene.get_node("Journey/Train/Model"), CPUParticles3D.new(), "Steam", scene)
	particles.position = Vector3(0.98, 1.72, 0)
	particles.amount = 14
	particles.lifetime = 2.8
	particles.mesh = puff
	particles.direction = Vector3(0, 1, 0)
	particles.spread = 12
	particles.gravity = Vector3(-0.04, 0.1, 0)
	particles.initial_velocity_min = 0.6
	particles.initial_velocity_max = 0.85
	particles.scale_amount_min = 0.5
	particles.scale_amount_max = 1.3
	particles.local_coords = false
