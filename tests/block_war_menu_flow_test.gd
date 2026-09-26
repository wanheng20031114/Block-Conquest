extends SceneTree
## Native input verifies locked animals, back/forward state, scoped settings and overlays.
const RULES := preload("res://scripts/block_war/war_skill_rules.gd")
const THEME := preload("res://assets/ui/block_war/menu_theme.tres")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL ", label)

func settle() -> void:
	for frame: int in 4:
		await process_frame
	while root.get_node("Session").transition.busy:
		await process_frame

func click(button: Button) -> void:
	var at := button.get_global_rect().get_center()
	var move := InputEventMouseMotion.new()
	move.position = at
	move.global_position = at
	root.push_input(move, true)
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.global_position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event, true)

func key(code: Key) -> void:
	for down: bool in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.keycode = code
		event.pressed = down
		root.push_input(event, true)

func _run() -> void:
	create_timer(80.0, true, false, true).timeout.connect(func(): quit(3))
	root.size = Vector2i(1600, 900)
	var session := root.get_node("Session")
	var settings: GameSettings = session.settings
	var original_audio: Array = [settings.volume_percent, settings.music_volume_percent]
	check(session.block_war_commander == &"squirrel", "first launch defaults to squirrel")
	change_scene_to_file("res://scenes/lobby.tscn")
	await scene_changed
	await settle()
	click(current_scene.get_node("%BlockWarMode"))
	await scene_changed
	await settle()
	check(current_scene.scene_file_path.ends_with("commander_select.tscn"), "lobby enters animal selection first")
	var picker := current_scene
	check(picker.get_node("%AnimalName").text == "松鼠", "species name has no nickname or title")
	for i: int in range(2, 6):
		var locked: Button = picker.get_node("%%Animal%d" % i)
		check(locked.is_visible_in_tree() and locked.disabled and locked.focus_mode == Control.FOCUS_NONE, "locked animal %d is visible but excluded from mouse and keyboard selection" % i)
		click(locked)
		check(session.block_war_commander == &"squirrel", "locked click preserves the commander")
		check(locked.get_node("Content/Status/Availability").text == "尚未开放", "locked status uses words as well as color")
	picker._select(5)
	check(session.block_war_commander == &"squirrel", "selection boundary rejects unimplemented profiles")
	click(picker.get_node("%Animal1"))
	await settle()
	check(session.block_war_commander == &"rabbit" and picker.get_node("%Animal1").button_pressed, "native rabbit click updates and retains selection")
	click(picker.get_node("%Animal1"))
	check(picker.get_node("%Animal1").button_pressed, "clicking the current animal cannot clear selection")
	for i: int in 4:
		check(picker.get_node("%%SkillName%d" % i).text == RULES.names_for(&"rabbit")[i], "rabbit skill %d uses live rules" % i)
		check(picker.get_node("%%SkillIcon%d" % i).texture == RULES.icons_for(&"rabbit")[i], "rabbit skill %d uses established artwork" % i)
	click(picker.get_node("%Settings"))
	await settle()
	check(settings.is_open() and settings.menu.theme == THEME, "selection settings receives the campaign theme")
	settings.menu.show_page("Hotkeys")
	check(settings.menu.get_node("%Pages/WarHotkeys").visible and not settings.menu.get_node("%Pages/Hotkeys").visible, "campaign hotkeys show the actual combat controls")
	check(not settings.menu.get_node("%Categories/FirstPerson").visible, "campaign settings omit unrelated first-person options")
	key(KEY_ESCAPE)
	await settle()
	check(not settings.is_open() and current_scene == picker, "Esc closes settings without leaving animal selection")
	click(picker.get_node("%Next"))
	await scene_changed
	await settle()
	check(current_scene.scene_file_path.ends_with("map_select.tscn"), "confirmation enters battlefield selection")
	click(current_scene.get_node("%Size2"))
	await settle()
	click(current_scene.get_node("%Map1"))
	click(current_scene.get_node("%OpponentCommander1"))
	var remembered: String = current_scene.selected.map_id
	key(KEY_ESCAPE)
	await scene_changed
	await settle()
	check(current_scene.get_node("%Animal1").button_pressed, "map Back restores the selected animal")
	click(current_scene.get_node("%Next"))
	await scene_changed
	await settle()
	check(current_scene.selected.map_id == remembered and current_scene.get_node("%OpponentCommander1").button_pressed, "round trip preserves map and opponent")
	click(current_scene.get_node("%Start"))
	await scene_changed
	await settle()
	var game := current_scene
	game.set_process(false)
	game.camera_rig.set_process(false)
	check(game.faction_skills[0].commander == &"rabbit" and game.faction_skills[1].commander == &"rabbit", "both chosen animals reach the match")
	key(KEY_ESCAPE)
	await settle()
	check(game._local_menu and game.hud.get_node("%Resume").has_focus(), "Esc opens pause with Continue as its safe default")
	click(game.hud.get_node("%PauseSettings"))
	await settle()
	check(settings.is_open() and settings.menu.theme == THEME and game._local_menu, "pause settings stays in the paused campaign")
	key(KEY_F1)
	check(not game.hud.help_visible(), "settings owns keyboard input over pause")
	key(KEY_ESCAPE)
	await settle()
	check(not settings.is_open() and game._local_menu and game.hud.get_node("%PauseSettings").has_focus(), "closing settings returns focus to paused settings entry")
	click(game.hud.get_node("%PauseHelp"))
	check(game.hud.help_visible(), "native Help opens the redesigned manual")
	key(KEY_ESCAPE)
	check(not game.hud.help_visible() and game._local_menu, "manual Back returns to pause")
	check(game.hud.get_node("%PausePortrait").texture == RULES.PORTRAITS[&"rabbit"], "pause portrait follows the selected animal")
	game.hud.show_result(true)
	check(game.hud.get_node("%ResultCard").is_visible_in_tree() and game.hud.get_node("%ResultPortrait").texture == RULES.PORTRAITS[&"rabbit"], "results retain the player's animal")
	await game.prepare_shutdown()
	change_scene_to_file("res://scenes/lobby.tscn")
	await scene_changed
	await settle()
	settings.open_menu()
	check(settings.menu.theme.resource_path == "res://assets/ui/medieval/theme.tres", "returning to the lobby restores its original settings theme")
	check(settings.menu.get_node("%Categories/FirstPerson").visible, "lobby keeps its complete settings categories")
	check([settings.volume_percent, settings.music_volume_percent] == original_audio, "reskin preserves calibrated audio preferences")
	settings.close_menu()
	print("BLOCK_WAR_MENU_FLOW checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
