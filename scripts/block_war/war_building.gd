class_name WarBuilding
extends Node3D
## Editable architectural scene; the match owns population and combat rules.

@export var building_id: int = 0
@export var faction: int = -1
@export_enum("住宅", "炮塔", "铁匠铺") var kind: int = 0
@export var population: float = 20.0
@export var capacity: float = 200.0
@export var level: int = 1

const FACTION_COLORS: Array[Color] = [Color(1.0, 0.65, 0.18), Color(0.2, 0.83, 0.67)]
const NEUTRAL_COLOR := Color("b5aa87")
const KIND_NAMES: Array[String] = ["住宅", "炮塔", "铁匠铺"]

@onready var _visual: Node3D = $Visual
@onready var _team_material: ShaderMaterial = $Visual/Flag.material_override
@onready var _fire_material: ShaderMaterial = $Visual/Smithy/Embers.material_override
@onready var _population_label: Label3D = $PopulationLabel
@onready var _kind_label: Label3D = $KindLabel
@onready var _selection: MeshInstance3D = $SelectionRing
var _selection_tween: Tween
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
	$Visual/Smithy/ForgeAnimation.speed_scale = 0.0 if value else 1.0
	if _recoil_tween and _recoil_tween.is_valid():
		if value:
			_recoil_tween.pause()
		else:
			_recoil_tween.play()
	if _capture_tween and _capture_tween.is_valid():
		if value:
			_capture_tween.pause()
		else:
			_capture_tween.play()


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


func refresh_visual() -> void:
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
		$Visual/Smithy/Smoke.emitting = kind == 2
	if kind != _last_kind or level != _last_level:
		_kind_label.text = KIND_NAMES[kind] if level == 1 else "%s · %d" % [KIND_NAMES[kind], level]
		_last_kind = kind
		_last_level = level
	var displayed_population := maxi(0, int(floor(population)))
	if displayed_population != _last_population:
		_population_label.text = str(displayed_population)
		# Enlarge all four petals together for long totals; preserve readable digits.
		var text_width := _population_label.font.get_string_size(_population_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 48).x
		$PopulationBadge.scale = Vector3.ONE * maxf(1.0, text_width * _population_label.pixel_size / 2.0)
		_last_population = displayed_population


func door_position() -> Vector3:
	return $Door.global_position


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


func pulse_capture() -> void:
	refresh_visual()
	if _capture_tween:
		_capture_tween.kill()
	_visual.scale = Vector3.ONE
	_capture_tween = create_tween()
	_capture_tween.tween_property(_visual, "scale", Vector3(1.12, 0.86, 1.12), 0.1).set_trans(Tween.TRANS_QUAD)
	_capture_tween.tween_property(_visual, "scale", Vector3.ONE, 0.38).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
