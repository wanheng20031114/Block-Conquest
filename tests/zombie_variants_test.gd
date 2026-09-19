extends SceneTree
## Isolated native resources and authored poses only; never instantiates BattleUnit.
const OUTPUT := "res://.local/zombie-variants/test-results.json"
const EPSILON := 0.0001
# tier, HP, damage, melee armor, ranged armor, penetration, cooldown, windup,
# range, speed, sight. Keep the design contract separate from loaded resources.
const SPECS: Dictionary = {
	"zombie_archer": [1, 80, 9, 0, 0, 0, 1.8, .45, 9, 2.8, 13],
	"zombie_musketeer": [2, 100, 24, 0, 1, 2, 3.0, .65, 7, 2.7, 12],
	"zombie_crossbowman": [2, 95, 12, 0, 1, 3, 1.6, .35, 7, 2.8, 12],
	"zombie_pitchfork": [1, 110, 9, 0, 0, 0, 1.8, .40, 1.4, 2.8, 12],
	"zombie_axe": [2, 145, 18, 1, 0, 0, 2.1, .50, 1.1, 2.8, 12],
	"zombie_miner": [2, 135, 14, 1, 1, 3, 2.2, .55, 1.1, 2.7, 12],
	"zombie_bell": [3, 170, 5, 0, 2, 0, 1.8, .35, 1, 2.6, 12],
	"zombie_door": [3, 240, 11, 3, 8, 0, 2.0, .40, 1, 2.3, 12],
}
const FIELDS: Array[String] = ["pve_tier", "hp", "damage", "melee_armor", "ranged_armor", "armor_penetration", "cooldown", "attack_windup_seconds", "range", "speed", "sight"]
var checks := 0
var failures: Array[String] = []
var details: Dictionary = {}
var active_model: UnitVisual
var ending := false

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("ZOMBIE_VARIANTS_FAIL ", label)

func _run() -> void:
	create_timer(90, true, false, true).timeout.connect(_timeout)
	for id: String in SPECS:
		var definition := load("res://data/prototypes/monsters/" + id + ".tres") as MonsterDefinition
		if definition == null:
			check(false, id + " loads as MonsterDefinition")
			continue
		_check_definition(id, definition)
		await _check_model(id, definition)
	_check_support_contract()
	_check_isolation()
	await _finish(0 if failures.is_empty() else 1)

func _check_definition(id: String, definition: MonsterDefinition) -> void:
	var issues: Array[String] = []
	issues.append_array(definition.validation_errors())
	for index: int in FIELDS.size():
		if not is_equal_approx(float(definition.get(FIELDS[index])), float(SPECS[id][index])):
			issues.append(FIELDS[index] + " differs from the design")
	var expected_projectile: String = {"zombie_archer": "arrow", "zombie_musketeer": "bullet", "zombie_crossbowman": "bolt"}.get(id, "")
	if definition.id != StringName(id) or definition.monster_faction != &"monsters" or definition.combat_class != &"infantry":
		issues.append("identity or physical classification")
	if definition.projectile != expected_projectile or definition.is_ranged_infantry() != (not expected_projectile.is_empty()):
		issues.append("projectile or ranged infantry classification")
	if definition.splash_radius != 0 or definition.min_range != 0 or not definition.production_building.is_empty() or definition.cost != 0 or definition.training_seconds != 0:
		issues.append("single-target prototype must not add production or economy")
	if definition.visual_scene_path != "res://assets/models/units/" + id + ".tscn":
		issues.append("native scene path")
	var expected_bonuses: Dictionary = {}
	if id == "zombie_pitchfork": expected_bonuses = {&"cavalry": 16}
	if id == "zombie_miner": expected_bonuses = {&"siege": 12}
	if definition.bonuses != expected_bonuses: issues.append("class bonus")
	if definition.is_support() != (id == "zombie_bell") or not definition.military:
		issues.append("support role or military classification")
	check(issues.is_empty(), id + " definition: " + "; ".join(issues))

func _check_model(id: String, definition: MonsterDefinition) -> void:
	var packed := load(definition.visual_scene_path) as PackedScene
	if packed == null:
		check(false, id + " native scene loads")
		return
	var instance := packed.instantiate()
	if not instance is UnitVisual:
		check(false, id + " scene root is UnitVisual")
		instance.free()
		return
	active_model = instance as UnitVisual
	root.add_child(active_model)
	await process_frame
	active_model.locomotion.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	active_model.attack.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	active_model._refresh_animation_visibility()
	var meshes := active_model.get_node("Rig").find_children("*", "MeshInstance3D", true, false)
	var triangles := 0
	var marked_parts: Array[String] = []
	var geometry_valid := true
	for mesh: MeshInstance3D in meshes:
		if mesh.mesh == null:
			geometry_valid = false
			continue
		triangles += mesh.mesh.get_faces().size() / 3
		var marked := false
		for surface: int in mesh.mesh.get_surface_count():
			var colors: PackedColorArray = mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_COLOR]
			geometry_valid = geometry_valid and not colors.is_empty()
			for color: Color in colors:
				if color.a > .75: marked = true
		if marked: marked_parts.append(String(mesh.name))
	details[id] = {"triangles": triangles, "rigid_parts": meshes.size(), "team_parts": marked_parts}
	check(geometry_valid and meshes.size() >= 8 and triangles <= 4500 and marked_parts == ["ArmLeft"], id + " native geometry, triangle budget and left armband: " + str(details[id]))

	var track_issues: Array[String] = []
	for player: AnimationPlayer in [active_model.locomotion, active_model.attack]:
		var animation_root := player.get_node(player.root_node)
		for clip_name: StringName in player.get_animation_list():
			var clip := player.get_animation(clip_name)
			for track: int in clip.get_track_count():
				var path := clip.track_get_path(track)
				if not animation_root.has_node(NodePath(path.get_concatenated_names())):
					track_issues.append(String(clip_name) + ":" + String(path))
	var clips_valid := active_model.locomotion.has_animation("idle") and active_model.locomotion.has_animation("walk") and active_model.attack.has_animation("strike")
	if id == "zombie_bell": clips_valid = clips_valid and active_model.attack.has_animation("rally")
	check(clips_valid and track_issues.is_empty(), id + " saved animation clips and tracks: " + "; ".join(track_issues))
	if clips_valid:
		_check_poses(id)
		_check_release(id, definition)
	active_model.queue_free()
	await process_frame
	active_model = null

func _idle_pose() -> void:
	active_model.attack.stop()
	active_model.locomotion.play("idle", 0)
	active_model.locomotion.seek(0, true)

func _snapshot() -> Dictionary:
	var pose: Dictionary = {NodePath("."): [active_model.transform, active_model.visible]}
	for node: Node3D in active_model.find_children("*", "Node3D", true, false):
		pose[active_model.get_path_to(node)] = [node.transform, node.visible]
	return pose

func _pose_differences(rest: Dictionary) -> Array[String]:
	var differences: Array[String] = []
	for path: NodePath in rest:
		var node: Node3D = active_model.get_node(path)
		var expected: Transform3D = rest[path][0]
		var current := node.transform
		if current.origin.distance_to(expected.origin) > EPSILON or current.basis.x.distance_to(expected.basis.x) > EPSILON or current.basis.y.distance_to(expected.basis.y) > EPSILON or current.basis.z.distance_to(expected.basis.z) > EPSILON or node.visible != bool(rest[path][1]):
			differences.append(String(path))
	return differences

func _check_poses(id: String) -> void:
	_idle_pose()
	var rest := _snapshot()
	var end_issues: Array[String] = []
	var cancel_issues: Array[String] = []
	var clips: Array[String] = ["strike"]
	if id == "zombie_bell": clips.append("rally")
	for clip_name: String in clips:
		var clip := active_model.attack.get_animation(clip_name)
		_idle_pose()
		active_model.attack.play(clip_name, 0)
		active_model.attack.seek(clip.length, true)
		for issue: String in _pose_differences(rest): end_issues.append(clip_name + ":" + issue)
		active_model.attack.play(clip_name, 0)
		active_model.attack.seek(clip.length * .47, true)
		_idle_pose()
		for issue: String in _pose_differences(rest): cancel_issues.append(clip_name + ":" + issue)
	check(end_issues.is_empty(), id + " action ends at idle transform and visibility: " + "; ".join(end_issues))
	check(cancel_issues.is_empty(), id + " interrupted action restores idle: " + "; ".join(cancel_issues))
	_idle_pose()
	var walk := active_model.locomotion.get_animation("walk")
	var foot_issues: Array[String] = []
	for side: String in ["Left", "Right"]:
		var foot: MeshInstance3D = active_model.get_node("Rig/Action/Step" + side + "/Leg" + side)
		var vertices := foot.mesh.get_faces()
		for sample: int in 13:
			active_model.locomotion.play("walk", 0)
			active_model.locomotion.seek(walk.length * sample / 12.0, true)
			var minimum := INF
			for vertex: Vector3 in vertices:
				minimum = minf(minimum, (foot.global_transform * vertex).y)
			if minimum < -.008: foot_issues.append(side + "@" + str(sample) + "=" + str(minimum))
	check(foot_issues.is_empty(), id + " walking feet stay above ground: " + "; ".join(foot_issues))

func _check_support_contract() -> void:
	var bell: MonsterDefinition = load("res://data/prototypes/monsters/zombie_bell.tres")
	check(bell.monster_ability == MonsterDefinition.Ability.RALLY and bell.support_kind.is_empty() and bell.rally_radius == 5 and is_equal_approx(bell.rally_speed_bonus, .20) and bell.rally_duration == 4 and bell.rally_period == 10, "rally is separate from recovery with the locked parameters")
	var mutated: MonsterDefinition = bell.duplicate()
	mutated.role = UnitDefinition.Role.COMBAT
	check(not mutated.validation_errors().is_empty(), "rally rejects a combat-only role")
	mutated = bell.duplicate()
	mutated.support_kind = &"heal"
	check(not mutated.validation_errors().is_empty(), "rally rejects recovery capability mixing")
	mutated = bell.duplicate()
	mutated.rally_radius = 0
	mutated.rally_duration = 11
	check(not mutated.validation_errors().is_empty(), "rally rejects empty range or duration above its period")
	mutated = bell.duplicate()
	mutated.monster_ability = MonsterDefinition.Ability.NONE
	mutated.role = UnitDefinition.Role.COMBAT
	check(not mutated.validation_errors().is_empty(), "no-ability monster rejects residual rally parameters")
	var legacy_valid := true
	for id: String in ["engineer", "priest"]:
		var definition := BalanceCatalog.unit(StringName(id))
		legacy_valid = legacy_valid and definition.is_support() and definition.validation_errors().is_empty()
		var invalid: UnitDefinition = definition.duplicate()
		invalid.support_kind = &"rally"
		legacy_valid = legacy_valid and not invalid.validation_errors().is_empty()
	var ordinary: UnitDefinition = load("res://data/prototypes/monsters/zombie.tres")
	legacy_valid = legacy_valid and ordinary.validation_errors().is_empty() and ordinary.hp == 100 and ordinary.damage == 10 and ordinary.melee_armor == 0 and ordinary.ranged_armor == 0
	check(legacy_valid, "engineer, priest and ordinary zombie preserve their original validation")

func _check_release(id: String, definition: MonsterDefinition) -> void:
	_idle_pose()
	var rest_origin: Vector3 = active_model.get_projectile_origin()
	active_model.attack.play("strike", 0)
	active_model.attack.seek(definition.attack_windup_seconds + .001, true)
	if id in ["zombie_pitchfork", "zombie_axe", "zombie_miner", "zombie_bell", "zombie_door"]:
		var hit_origin: Vector3 = active_model.get_projectile_origin()
		check(hit_origin.z < rest_origin.z - .15, id + " contact reaches forward at its data windup " + str(rest_origin) + " -> " + str(hit_origin))
	elif id in ["zombie_archer", "zombie_crossbowman"]:
		var arrow_name := "Arrow" if id == "zombie_archer" else "Bolt"
		var arrow: MeshInstance3D = active_model.find_child(arrow_name, true, false)
		check(not arrow.visible, id + " projectile leaves the weapon at release")
		_idle_pose()
		active_model.attack.play("strike", 0)
		active_model.attack.seek(definition.attack_windup_seconds - .001, true)
		check(arrow.visible, id + " projectile remains nocked before release")
	_idle_pose()

func _check_isolation() -> void:
	var codex := FileAccess.get_file_as_string("res://scenes/model_previews.tscn")
	var sandbox := FileAccess.get_file_as_string("res://scenes/sandbox_model_previews.tscn")
	var isolated := true
	for id: String in SPECS:
		isolated = isolated and not BalanceCatalog.UNITS.has(id) and not codex.contains(id) and not sandbox.contains(id)
	check(isolated and not BalanceCatalog.UNITS.has("zombie"), "all monster prototypes remain outside live, codex and sandbox rosters")

func _timeout() -> void:
	check(false, "90-second validation timeout")
	await _finish(3)

func _finish(code: int) -> void:
	if ending: return
	ending = true
	if is_instance_valid(active_model): active_model.queue_free()
	await process_frame
	DirAccess.make_dir_recursive_absolute(OUTPUT.get_base_dir())
	var file := FileAccess.open(OUTPUT, FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "models": details}, "\t"))
	file.close()
	print("ZOMBIE_VARIANTS_TEST ", checks, " checks, ", failures.size(), " failures")
	quit(code)
