extends SceneTree
## Sample drawn frames after a real slow scene _ready, not only tween endpoints.
const FIXTURE := "res://tests/ui_transition_slow_fixture.tscn"
var samples: Array[Dictionary] = []
var recording := false
var checks := 0
var failures: Array[String] = []
var transition: UITransition

func _initialize() -> void:
	root.visible = false
	root.unfocusable = true
	if DisplayServer.get_name() != "headless":
		RenderingServer.viewport_set_update_mode(root.get_viewport_rid(), RenderingServer.VIEWPORT_UPDATE_ALWAYS)
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _record() -> void:
	if recording:
		samples.append({"curtain": transition._curtain, "visible": transition.veil.visible, "busy": transition.busy})

func _run() -> void:
	create_timer(15, true, false, true).timeout.connect(func(): quit(3))
	transition = root.get_node("Session").transition
	if DisplayServer.get_name() == "headless": process_frame.connect(_record)
	else: RenderingServer.frame_post_draw.connect(_record)
	for under_pause: bool in [false, true]:
		paused = under_pause
		Engine.time_scale = 0.01 if under_pause else 1.0
		samples.clear()
		check(transition.change_scene(FIXTURE) == OK, "accept slow scene")
		await scene_changed
		recording = true
		check(transition.busy and transition.veil.visible and is_equal_approx(transition._curtain, 1.0), "new scene starts fully covered")
		await transition.completed
		recording = false
		var partial: Array = samples.filter(func(s: Dictionary) -> bool: return s.curtain > 0.02 and s.curtain < 0.98)
		check(partial.size() >= 2, "slow scene preserves multiple drawn frames of upward reveal")
		check(samples.size() > 0 and float(samples[0].curtain) > 0.98, "first scene frame stays covered")
		check(partial.all(func(s: Dictionary) -> bool: return s.visible and s.busy), "input remains blocked throughout upward travel")
		var monotonic := true
		for index: int in range(1, samples.size()):
			if float(samples[index].curtain) > float(samples[index - 1].curtain) + 0.001: monotonic = false
		check(monotonic, "paper withdraws continuously upward")
		check(not transition.busy and not transition.veil.visible and is_zero_approx(transition._curtain), "only hide after paper has left the top edge")
		print("REVEAL_FRAMES ", JSON.stringify({"paused": under_pause, "drawn_frames": samples.size(), "partial_frames": partial.size(), "first": samples[0] if not samples.is_empty() else {}}))
	paused = false
	Engine.time_scale = 1.0
	print("UI_TRANSITION_REVEAL ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
