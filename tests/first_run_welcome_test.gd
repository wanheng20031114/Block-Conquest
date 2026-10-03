extends SceneTree
## Exercise the real first-visit lobby overlay through native pointer and keyboard input.
## Every onboarding write belongs to this process's isolated .local fixture.

const SAVE_FILES: Array[String] = ["onboarding.cfg", "settings.cfg", "campaign.cfg", "tutorial_progress.cfg"]
const BACKGROUND_ENTRIES: Array[String] = ["Campaign", "BlockWarMode", "OnlineMode", "Codex", "Settings", "Quit"]
var checks := 0
var failures: Array[String] = []
var output := ""
var session: Node
var state_script: Script
var profile := ""
var user_files: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL ", label)

func frames(count: int = 6) -> void:
	for frame: int in count:
		await process_frame

func settle(seconds: float = 0.7) -> void:
	await create_timer(seconds, true, false, true).timeout
	await frames(3)

func motion(at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	root.push_input(event, true)

func click(control: Control) -> void:
	var at := control.get_global_rect().get_center()
	motion(at)
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.global_position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event, true)

func key(code: Key, shift: bool = false) -> void:
	for down: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.shift_pressed = shift
		event.pressed = down
		root.push_input(event, true)

func expect_scene(path: String) -> bool:
	for frame: int in 600:
		await process_frame
		if current_scene != null and current_scene.scene_file_path == path and not session.transition.busy:
			await settle()
			return true
	check(false, "native navigation reaches " + path)
	return false

func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, "capture " + label)
	print("FIRST_RUN_WELCOME_CAPTURE ", label, " window=", root.size, " viewport=", root.get_visible_rect().size)

func fresh_lobby(label: String) -> Node:
	profile = output.path_join(label)
	check(DirAccess.make_dir_recursive_absolute(profile) == OK, label + " isolated profile exists")
	session.first_run = state_script.new(profile)
	check(session.first_run.pending, label + " begins with an unseen recommendation")
	check(change_scene_to_file(session.LOBBY_SCENE) == OK, label + " lobby loads")
	await scene_changed
	var guide: Node = current_scene.get_node("TutorialWelcome")
	check(not guide.active and session.first_run.pending, label + " waits for the visible menu entrance before consuming first visit")
	for frame: int in 600:
		await process_frame
		if guide.active:
			break
	await frames(3)
	check(guide.active and guide.visible, label + " shows the recommendation after entrance")
	check(not session.first_run.pending, label + " consumes the recommendation only after showing it")
	check(not state_script.new(profile).pending, label + " persists seen state for a future process")
	check(current_scene.get_node("%Tutorial").has_focus(), label + " focuses the real tutorial entry")
	return guide

func check_geometry(guide: Node, label: String) -> void:
	var target: Button = current_scene.get_node("%Tutorial")
	var target_rect := target.get_global_rect()
	var dimmer: ColorRect = guide.get_node("UI/Dimmer")
	var card: Control = guide.get_node("UI/Card")
	var viewport: Rect2 = guide.get_node("UI").get_global_rect()
	check(is_equal_approx(target.modulate.a, 1.0), label + " target has finished its entrance fade")
	check(viewport.encloses(card.get_global_rect()), label + " recommendation card stays inside the viewport")
	check(not card.get_global_rect().intersects(target_rect), label + " recommendation never covers the tutorial entry")
	check(dimmer.interaction_regions.size() == 1, label + " permits exactly one background interaction region")
	if dimmer.interaction_regions.size() == 1:
		var hit_rect: Rect2 = dimmer.interaction_regions[0]
		check(hit_rect.grow(1.0).encloses(target_rect), label + " native hit-test hole follows the entire tutorial button")
		check(hit_rect.get_center().distance_to(target_rect.get_center()) < 1.0, label + " native hit-test hole is centered on tutorial")
		for entry: String in BACKGROUND_ENTRIES:
			var button: Button = current_scene.get_node("%" + entry)
			check(not hit_rect.has_point(button.get_global_rect().get_center()), label + " veil blocks " + entry)
	var material: ShaderMaterial = dimmer.material
	check(int(material.get_shader_parameter("spotlight_count")) == 1, label + " renders one spotlight")
	var cutouts: Variant = material.get_shader_parameter("spotlights")
	if not cutouts.is_empty():
		var cutout := Rect2(Vector2(cutouts[0].x, cutouts[0].y), Vector2(cutouts[0].z, cutouts[0].w))
		check(cutout.grow(1.0).encloses(target_rect), label + " rendered spotlight contains tutorial")
		check(cutout.get_center().distance_to(target_rect.get_center()) < 1.0, label + " rendered spotlight follows tutorial's visual center")
	check(Vector2(material.get_shader_parameter("viewport_size")).is_equal_approx(dimmer.size), label + " shader uses the actual canvas dimensions")
	check(not dimmer._has_point(target_rect.get_center()), label + " actual target receives pointer events")
	check(dimmer._has_point(current_scene.get_node("%Settings").get_global_rect().get_center()), label + " shaded settings rejects pointer events")

func check_focus(guide: Node) -> void:
	var tutorial: Button = current_scene.get_node("%Tutorial")
	var dismiss: Button = guide.get_node("%Dismiss")
	for code: Key in [KEY_TAB, KEY_DOWN, KEY_UP, KEY_LEFT, KEY_RIGHT]:
		for press: int in 4:
			key(code)
			await frames(1)
			var focused := root.gui_get_focus_owner()
			check(focused == tutorial or focused == dismiss, "active guide contains keyboard focus for key %s press %d" % [code, press])
	for press: int in 4:
		key(KEY_TAB, true)
		await frames(1)
		var focused := root.gui_get_focus_owner()
		check(focused == tutorial or focused == dismiss, "active guide contains reverse Tab focus %d" % press)

func check_restored(guide: Node, label: String) -> void:
	check(not guide.active and not guide.visible, label + " removes both the guide and input veil")
	for entry: String in BACKGROUND_ENTRIES:
		var button: Button = current_scene.get_node("%" + entry)
		check(button.focus_mode == Control.FOCUS_ALL, label + " restores normal keyboard access to " + entry)
	check(current_scene._presentation_active, label + " restores the lobby presentation")

func check_early_settings() -> void:
	profile = output.path_join("early-settings")
	DirAccess.make_dir_recursive_absolute(profile)
	session.first_run = state_script.new(profile)
	change_scene_to_file(session.LOBBY_SCENE)
	await scene_changed
	await frames(3)
	# The menu is still revealing. Opening settings postpones the invitation,
	# then closing it must allow the invitation to claim keyboard focus last.
	click(current_scene.get_node("%Settings"))
	check(session.settings.is_open(), "native settings can open before menu entrance completes")
	for frame: int in 600:
		await process_frame
		if current_scene.get_node("MenuEntrance").finished:
			break
	var guide: Node = current_scene.get_node("TutorialWelcome")
	check(not guide.active and session.first_run.pending, "early settings postpones the recommendation without consuming it")
	click(session.settings.menu.get_node("%Close"))
	await settle(0.25)
	check(guide.active and not session.first_run.pending, "closing early settings presents the postponed recommendation")
	check(current_scene.get_node("%Tutorial").has_focus(), "settings close cannot overwrite the recommendation's tutorial focus")
	await check_focus(guide)
	key(KEY_ESCAPE)
	await frames()
	check_restored(guide, "postponed recommendation Escape")

func check_direct_launch() -> void:
	profile = output.path_join("direct-launch")
	DirAccess.make_dir_recursive_absolute(profile)
	session.first_run = state_script.new(profile)
	change_scene_to_file(session.LOBBY_SCENE)
	await scene_changed
	check(not current_scene.get_node("TutorialWelcome").active, "command-line battle launch starts without a recommendation")
	if await expect_scene(session.BATTLE_SCENE):
		check(session.first_run.pending, "command-line battle launch does not consume an unseen recommendation")
		check(state_script.new(profile).pending, "command-line battle launch does not persist an unseen recommendation")

func _finish() -> void:
	for filename: String in SAVE_FILES:
		var path := "user://".path_join(filename)
		var current_bytes: Variant = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
		check(current_bytes == user_files[filename], "native UI verification preserves real user " + filename)
	print("FIRST_RUN_WELCOME_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)

func _run() -> void:
	create_timer(90.0, true, false, true).timeout.connect(func(): printerr("FIRST_RUN_WELCOME_TIMEOUT"); quit(3))
	output = ProjectSettings.globalize_path("res://.local/first-run-tutorial/ui-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(output)
	for filename: String in SAVE_FILES:
		var path := "user://".path_join(filename)
		user_files[filename] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	session = root.get_node("Session")
	state_script = session.first_run.get_script()
	root.size = Vector2i(1600, 900)
	if OS.get_cmdline_user_args().has("--block-war"):
		await check_direct_launch()
		_finish()
		return
	var guide := await fresh_lobby("dismiss")
	for resolution: Vector2i in [Vector2i(1600, 900), Vector2i(1280, 720), Vector2i(1024, 768), Vector2i(1920, 1080)]:
		root.size = resolution
		await settle(0.25)
		motion(Vector2(1500, 30))
		await settle(0.25)
		check_geometry(guide, str(resolution) + " rest")
		motion(current_scene.get_node("%Tutorial").get_global_rect().get_center())
		await settle(0.25)
		check_geometry(guide, str(resolution) + " hover")
		await capture("first_visit_%dx%d" % [resolution.x, resolution.y])
	await check_focus(guide)
	click(current_scene.get_node("%Settings"))
	await frames()
	check(not session.settings.is_open() and guide.active, "native shaded settings click cannot open a competing modal")
	click(current_scene.get_node("%Campaign"))
	await frames()
	check(current_scene.scene_file_path == session.LOBBY_SCENE and not session.transition.busy, "native shaded campaign click cannot navigate away")
	click(guide.get_node("%Dismiss"))
	await settle(0.25)
	check_restored(guide, "native later button")
	click(current_scene.get_node("%Settings"))
	await settle(0.25)
	check(session.settings.is_open(), "dismissal restores native settings button interaction")
	click(session.settings.menu.get_node("%Close"))
	await settle(0.25)
	check(not session.settings.is_open(), "settings can close normally after dismissal")
	session.first_run = state_script.new(profile)
	change_scene_to_file(session.LOBBY_SCENE)
	await scene_changed
	await settle()
	check(not current_scene.get_node("TutorialWelcome").active, "persisted dismiss survives a fresh state instance and lobby load")
	root.size = Vector2i(1600, 900)
	guide = await fresh_lobby("escape")
	key(KEY_ESCAPE)
	await frames()
	check_restored(guide, "native Escape")
	await check_early_settings()
	guide = await fresh_lobby("tutorial")
	click(current_scene.get_node("%Tutorial"))
	if not await expect_scene(session.TUTORIAL_MENU_SCENE):
		_finish()
		return
	check(current_scene.cards.size() == 11, "real spotlight target opens the existing full tutorial menu")
	click(current_scene.get_node("%Back"))
	if not await expect_scene(session.LOBBY_SCENE):
		_finish()
		return
	check(not current_scene.get_node("TutorialWelcome").active, "returning from tutorial never repeats first-visit recommendation")
	check(current_scene.get_node("%Tutorial").has_focus(), "tutorial return restores its normal menu focus")
	_finish()
