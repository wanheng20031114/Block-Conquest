class_name WarBuilding
extends Node3D
## Editable architectural scene; the match owns population and combat rules.

@export var building_id: int = 0
@export var faction: int = -1
@export_enum("住宅", "炮塔", "铁匠铺") var kind: int = 0
@export var population: float = 20.0
@export var level: int = 1

const HOUSE_PRODUCTION_RATES: Array[float] = [1.0, 1.25, 1.4, 1.5]
const HOUSE_PRODUCTION_LIMITS: Array[float] = [30.0, 50.0, 60.0, 80.0]
const CONSTRUCTION_DURATION := 10.0
const SELECTION_REBOUND: Curve = preload("res://assets/block_war/selection_rebound.tres")
const SELECTION_REBOUND_DURATION := 0.38

# The match advances this clock, so pause and game-over freeze construction too.
var construction_remaining := 0.0
var conversion_target := -1
var disruption_remaining := 0.0
var is_constructing: bool:
	get:
		return construction_remaining > 0.0
# Derived from the current kind and level, including capture and conversion.
# This limits natural production only; the garrison itself is uncapped.
var capacity: float:
	get:
		return HOUSE_PRODUCTION_LIMITS[level - 1] if kind == 0 else 0.0
var production_rate: float:
	get:
		return HOUSE_PRODUCTION_RATES[level - 1] if kind == 0 else 0.0
var max_level: int:
	get:
		return [4, 3, 1][kind]
var upgrade_cost: int:
	get:
		return level * (10 if kind == 0 else 30) if level < max_level else 0

const FACTION_COLORS: Array[Color] = preload("res://scripts/block_war/war_factions.gd").COLORS
const NEUTRAL_COLOR := Color("b5aa87")
const KIND_NAMES: Array[String] = ["住宅", "炮塔", "铁匠铺"]
# One shared ground perimeter survives building conversions and leaves enough
# space for a rotated marcher to appear or disappear outside the outer walls.
const MARCH_PERIMETER_RADIUS := 2.45
# Mesh resources are baked offline; upgrades reuse the same authored scene nodes.
const LEVEL_MESHES := {
	"House/Metal": [preload("res://assets/models/block_war/architecture/house_metal.res"), preload("res://assets/models/block_war/architecture/house_2_metal.res"), preload("res://assets/models/block_war/architecture/house_3_metal.res"), preload("res://assets/models/block_war/architecture/house_4_metal.res")],
	"House/Roof": [preload("res://assets/models/block_war/architecture/house_roof.res"), preload("res://assets/models/block_war/architecture/house_2_roof.res"), preload("res://assets/models/block_war/architecture/house_3_roof.res"), preload("res://assets/models/block_war/architecture/house_4_roof.res")],
	"House/Stone": [preload("res://assets/models/block_war/architecture/house_stone.res"), preload("res://assets/models/block_war/architecture/house_2_stone.res"), preload("res://assets/models/block_war/architecture/house_3_stone.res"), preload("res://assets/models/block_war/architecture/house_4_stone.res")],
	"House/Timber": [preload("res://assets/models/block_war/architecture/house_timber.res"), preload("res://assets/models/block_war/architecture/house_2_timber.res"), preload("res://assets/models/block_war/architecture/house_3_timber.res"), preload("res://assets/models/block_war/architecture/house_4_timber.res")],
	"Tower/Metal": [preload("res://assets/models/block_war/architecture/tower_metal.res"), preload("res://assets/models/block_war/architecture/tower_2_metal.res"), preload("res://assets/models/block_war/architecture/tower_3_metal.res")],
	"Tower/Stone": [preload("res://assets/models/block_war/architecture/tower_stone.res"), preload("res://assets/models/block_war/architecture/tower_2_stone.res"), preload("res://assets/models/block_war/architecture/tower_3_stone.res")],
	"Tower/Timber": [preload("res://assets/models/block_war/architecture/tower_timber.res"), preload("res://assets/models/block_war/architecture/tower_2_timber.res"), preload("res://assets/models/block_war/architecture/tower_3_timber.res")],
	"Smithy/Metal": [preload("res://assets/models/block_war/architecture/smithy_metal.res"), preload("res://assets/models/block_war/architecture/smithy_2_metal.res"), preload("res://assets/models/block_war/architecture/smithy_3_metal.res")],
	"Smithy/Roof": [preload("res://assets/models/block_war/architecture/smithy_roof.res"), preload("res://assets/models/block_war/architecture/smithy_2_roof.res"), preload("res://assets/models/block_war/architecture/smithy_3_roof.res")],
	"Smithy/Stone": [preload("res://assets/models/block_war/architecture/smithy_stone.res"), preload("res://assets/models/block_war/architecture/smithy_2_stone.res"), preload("res://assets/models/block_war/architecture/smithy_3_stone.res")],
	"Smithy/Timber": [preload("res://assets/models/block_war/architecture/smithy_timber.res"), preload("res://assets/models/block_war/architecture/smithy_2_timber.res"), preload("res://assets/models/block_war/architecture/smithy_3_timber.res")],
	"Tower/Gun/MountTimber": [preload("res://assets/models/block_war/architecture/gun_mount_timber.res"), preload("res://assets/models/block_war/architecture/gun_mount_2_timber.res"), preload("res://assets/models/block_war/architecture/gun_mount_3_timber.res")],
	"Tower/Gun/MountMetal": [preload("res://assets/models/block_war/architecture/gun_mount_metal.res"), preload("res://assets/models/block_war/architecture/gun_mount_2_metal.res"), preload("res://assets/models/block_war/architecture/gun_mount_3_metal.res")],
	"Tower/Gun/Barrel/BarrelMetal": [preload("res://assets/models/block_war/architecture/gun_barrel_metal.res"), preload("res://assets/models/block_war/architecture/gun_barrel_2_metal.res"), preload("res://assets/models/block_war/architecture/gun_barrel_3_metal.res")],
	"Tower/Gun/Barrel/BarrelStone": [preload("res://assets/models/block_war/architecture/gun_barrel_stone.res"), preload("res://assets/models/block_war/architecture/gun_barrel_2_stone.res"), preload("res://assets/models/block_war/architecture/gun_barrel_3_stone.res")],
	"Tower/Gun/Barrel/BarrelBands": [preload("res://assets/models/block_war/architecture/gun_barrel_fabric.res"), preload("res://assets/models/block_war/architecture/gun_barrel_2_fabric.res"), preload("res://assets/models/block_war/architecture/gun_barrel_3_fabric.res")],
}
const TOWER_DECK_HEIGHTS := [1.5088, 2.05, 2.2714]
const MUZZLE_LENGTHS := [-1.80, -2.50, -2.80]
const SMITHY_SMOKE_HEIGHTS := [2.8126, 3.649, 3.8909]
const SMITHY_SMOKE_X := [-0.6888, -0.6888, -0.9594]

@onready var _visual: Node3D = $Visual
@onready var _visual_rest_scale: Vector3 = _visual.scale
@onready var _team_material: ShaderMaterial = $Visual/Flag.material_override
@onready var _fire_material: ShaderMaterial = $Visual/Smithy/Embers.material_override
@onready var _population_label: Label3D = $PopulationLabel
@onready var _kind_label: Label3D = $KindLabel
@onready var _selection: MeshInstance3D = $SelectionRing
@onready var _construction_particles: Array[GPUParticles3D] = [$Construction/Dust, $Construction/Chips, $Construction/Complete]
var _selection_tween: Tween
var _selection_body_tween: Tween
var _capture_tween: Tween
var _is_selected := false
var _last_faction := -999
var _last_kind := -1
var _last_population := -1
var _last_level := -1
var _visual_time := 0.0
var _visual_paused := false
var _recoil_tween: Tween


func _ready() -> void:
	_visual_time = float(building_id) * 0.73
	refresh_visual()
	_selection.visible = false
	_kind_label.visible = false


func _exit_tree() -> void:
	# Explicitly release paused animation tracks too when the match is removed.
	for tween: Tween in [_selection_tween, _selection_body_tween, _capture_tween, _recoil_tween]:
		if tween:
			tween.kill()


func _process(delta: float) -> void:
	if _visual_paused:
		return
	_visual_time += delta
	_team_material.set_shader_parameter("visual_time", _visual_time)
	if kind == 2:
		_fire_material.set_shader_parameter("visual_time", _visual_time)


func set_visual_paused(value: bool) -> void:
	_visual_paused = value
	$Visual/Smithy/Smoke.speed_scale = 0.0 if value else 1.0
	$Visual/Smithy/ForgeAnimation.speed_scale = 0.0 if value or disruption_remaining > 0.0 else 1.0
	$Disruption.set_running(not value)
	for particles: GPUParticles3D in _construction_particles:
		particles.speed_scale = 0.0 if value else 1.0
	for tween: Tween in [_selection_tween, _selection_body_tween, _capture_tween, _recoil_tween]:
		# A completed tween can remain valid until the next SceneTree cleanup.
		# Only unfinished loops may be paused or resumed during that interval.
		if tween and tween.is_valid() and tween.get_loops_left() != 0:
			if value:
				tween.pause()
			else:
				tween.play()


func begin_disruption(seconds: float) -> void:
	disruption_remaining = seconds
	$Disruption.start(seconds)
	_sync_disruption_visual()


func advance_disruption(delta: float) -> bool:
	var was_active := disruption_remaining > 0.0
	disruption_remaining = maxf(0.0, disruption_remaining - delta)
	if disruption_remaining < 0.000001:
		disruption_remaining = 0.0
	$Disruption.tick(delta)
	if was_active and disruption_remaining <= 0.0:
		_sync_disruption_visual()
		return true
	return false


func clear_disruption() -> void:
	if disruption_remaining <= 0.0:
		return
	disruption_remaining = 0.0
	$Disruption.finish()
	_sync_disruption_visual()


func _sync_disruption_visual() -> void:
	var working := disruption_remaining <= 0.0
	$Visual/Smithy/Smoke.emitting = kind == 2 and working
	$Visual/Smithy/Embers.visible = kind == 2 and working
	$Visual/Smithy/HearthLight.visible = kind == 2 and working
	$Visual/Smithy/ForgeAnimation.speed_scale = 1.0 if working and not _visual_paused else 0.0


func begin_construction(target_kind: int = -1) -> void:
	assert(not is_constructing)
	assert((target_kind == -1 and level < max_level) or (target_kind in [0, 1, 2] and target_kind != kind))
	conversion_target = target_kind
	construction_remaining = CONSTRUCTION_DURATION
	$Construction.show()
	$Construction/Complete.hide()
	$Construction/Complete.emitting = false
	$Construction/Dust.restart()
	$Construction/Chips.restart()


func advance_construction(delta: float) -> bool:
	if not is_constructing:
		return false
	construction_remaining = maxf(0.0, construction_remaining - delta)
	if construction_remaining > 0.000001:
		return false
	construction_remaining = 0.0
	if conversion_target >= 0:
		kind = conversion_target
		level = 1
	else:
		level += 1
	conversion_target = -1
	$Construction/Dust.emitting = false
	$Construction/Chips.emitting = false
	$Construction/Complete.show()
	$Construction/Complete.restart()
	pulse_capture()
	return true


func cancel_construction() -> void:
	construction_remaining = 0.0
	conversion_target = -1
	# Hide immediately on capture, including any dust from a recent completion.
	$Construction.hide()
	for particles: GPUParticles3D in _construction_particles:
		particles.emitting = false


func fire_at(target: Vector3) -> void:
	var gun: Node3D = $Visual/Tower/Gun
	var local_target: Vector3 = $Visual/Tower.to_local(target) - gun.position
	gun.rotation.y = atan2(-local_target.x, -local_target.z)
	var barrel: Node3D = $Visual/Tower/Gun/Barrel
	if _recoil_tween:
		_recoil_tween.kill()
	barrel.position = Vector3(0, 1.18, 0)
	_recoil_tween = create_tween()
	_recoil_tween.tween_property(barrel, "position:z", 0.24, 0.055).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_recoil_tween.tween_property(barrel, "position:z", 0.0, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if _visual_paused:
		_recoil_tween.pause()
	$Visual/Tower/Gun/Barrel/Muzzle.force_update_transform()


func muzzle_position() -> Vector3:
	# Flush the authored transform chain before a same-frame projectile request.
	$Visual/Tower/Gun.force_update_transform()
	$Visual/Tower/Gun/Barrel.force_update_transform()
	$Visual/Tower/Gun/Barrel/Muzzle.force_update_transform()
	return $Visual/Tower/Gun/Barrel/Muzzle.global_position


func refresh_visual() -> void:
	if level != _last_level or kind != _last_kind:
		_apply_level_visuals()
	if faction != _last_faction:
		var color: Color = NEUTRAL_COLOR if faction < 0 else FACTION_COLORS[faction]
		var cloth_color := color.lerp(Color("c1a674"), 0.12)
		$Visual/Flag.set_instance_shader_parameter("team_color", cloth_color)
		# Only roof tiles carry ownership; both kinds update immediately on capture.
		$Visual/House/Roof.set_instance_shader_parameter("team_tint", color)
		$Visual/Smithy/Roof.set_instance_shader_parameter("team_tint", color)
		$Visual/Tower/Gun/Barrel/BarrelBands.set_instance_shader_parameter("team_color", cloth_color)
		$OwnershipRing.material_override.albedo_color = Color(color, 0.82)
		_population_label.modulate = Color("34382e")
		_kind_label.modulate = color.lightened(0.3)
		_last_faction = faction
	if kind != _last_kind:
		$Visual/House.visible = kind == 0
		$Visual/Tower.visible = kind == 1
		$Visual/Smithy.visible = kind == 2
		_sync_disruption_visual()
	if kind != _last_kind or level != _last_level:
		_kind_label.text = KIND_NAMES[kind] if level == 1 else "%s · %d" % [KIND_NAMES[kind], level]
		_last_kind = kind
		_last_level = level
	var displayed_population := maxi(0, int(floor(population)))
	if displayed_population != _last_population:
		_population_label.text = str(displayed_population)
		# Keep ordinary totals prominent; three digits share the same white badge.
		_population_label.font_size = 54 if displayed_population >= 100 else 64
		var text_width := _population_label.font.get_string_size(_population_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _population_label.font_size).x
		# Reinforcements can exceed three digits; keep those exceptional totals inside.
		$PopulationBadge.scale = Vector3.ONE * maxf(1.0, text_width * _population_label.pixel_size / 2.2)
		$PickArea/BadgeCollisionShape3D.scale = $PopulationBadge.scale
		_last_population = displayed_population


func _apply_level_visuals() -> void:
	assert(level >= 1 and level <= max_level, "Building level must have an authored model.")
	var tier := level - 1
	var kind_path: String = ["House/", "Tower/", "Smithy/"][kind]
	$Visual/Flag.set_instance_shader_parameter("building_level", level)
	for path: String in LEVEL_MESHES:
		if path.begins_with(kind_path):
			var part: MeshInstance3D = _visual.get_node(path)
			part.mesh = LEVEL_MESHES[path][tier]
	# One aiming/recoil hierarchy serves every cannon, including a capture downgrade.
	if _recoil_tween:
		_recoil_tween.kill()
	if kind == 1:
		$Visual/Tower/Gun.position.y = TOWER_DECK_HEIGHTS[tier]
		$Visual/Tower/Gun/Barrel.position = Vector3(0, 1.18, 0)
		$Visual/Tower/Gun/Barrel/Muzzle.position.z = MUZZLE_LENGTHS[tier]
		muzzle_position()
	elif kind == 2:
		$Visual/Smithy/Smoke.position.y = SMITHY_SMOKE_HEIGHTS[tier]
		$Visual/Smithy/Smoke.position.x = SMITHY_SMOKE_X[tier]


func door_position() -> Vector3:
	return $Door.global_position


func march_perimeter_towards(point: Vector3) -> Vector3:
	var direction := point - global_position
	direction.y = 0.0
	assert(direction.length_squared() > 0.001, "A perimeter needs a direction away from the building center.")
	return global_position + direction.normalized() * MARCH_PERIMETER_RADIUS


func set_selected(selected: bool) -> void:
	if _is_selected == selected:
		return
	_is_selected = selected
	if _selection_tween:
		_selection_tween.kill()
	_selection.visible = selected
	_kind_label.visible = selected
	if selected:
		_selection.scale = Vector3.ONE * 0.78
		_selection_tween = create_tween()
		_selection_tween.tween_property(_selection, "scale", Vector3.ONE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if _visual_paused:
			_selection_tween.pause()
		_play_selection_rebound()


func _play_selection_rebound() -> void:
	# Capture and construction completion own the body until their pulse settles.
	if _capture_tween and _capture_tween.is_valid():
		return
	if _selection_body_tween:
		_selection_body_tween.kill()
	var initial_height := _visual.scale.y / _visual_rest_scale.y
	_selection_body_tween = create_tween()
	_selection_body_tween.tween_method(_sample_selection_rebound.bind(initial_height), 0.0, 1.0, SELECTION_REBOUND_DURATION).set_trans(Tween.TRANS_LINEAR)
	if _visual_paused:
		_selection_body_tween.pause()


func _sample_selection_rebound(progress: float, initial_height: float) -> void:
	var height := 1.0 + SELECTION_REBOUND.sample_baked(progress)
	# Blend a rapid re-click from its current pose into the first compression,
	# without snapping to rest or accumulating additional stretch on every click.
	height += (initial_height - 1.0) * (1.0 - smoothstep(0.0, 0.13, progress))
	var width := 1.0 / sqrt(height)
	_visual.scale = _visual_rest_scale * Vector3(width, height, width)


func pulse_capture() -> void:
	refresh_visual()
	if _selection_body_tween:
		_selection_body_tween.kill()
	if _capture_tween:
		_capture_tween.kill()
	_capture_tween = create_tween()
	_capture_tween.tween_property(_visual, "scale", _visual_rest_scale * Vector3(1.12, 0.86, 1.12), 0.1).set_trans(Tween.TRANS_QUAD)
	_capture_tween.tween_property(_visual, "scale", _visual_rest_scale, 0.38).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _visual_paused:
		_capture_tween.pause()
