extends SceneTree
## Capture actual authored menus and validate the usable bounds after all motion settles.
var failures: Array[String] = []
var checks: int = 0
var lobby: Node3D
var settings: GameSettings
const OUTPUT: String = "res://artifacts/ui_medieval_menu"

func _initialize() -> void:
	root.visible = false
	root.unfocusable = true
	RenderingServer.viewport_set_update_mode(root.get_viewport_rid(), RenderingServer.VIEWPORT_UPDATE_ALWAYS)
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func settle() -> void:
	await create_timer(0.35, true, false, true).timeout

func capture(name: String) -> void:
	await settle()
	check_material_bounds(root, name)
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUTPUT+"/"+name+".png") == OK, name+" saved")

func in_bounds(node: Control, label: String) -> void:
	check(root.get_visible_rect().grow(2).encloses(node.get_global_rect()),label+" stays in viewport")

func check_material_bounds(node: Node, page: String) -> void:
	if node is BaseButton and node.is_visible_in_tree():
		var style: StyleBox = node.get_theme_stylebox("normal")
		if style is StyleBoxTexture:
			var fixed_width: float = style.texture_margin_left + style.texture_margin_right
			var fixed_height: float = style.texture_margin_top + style.texture_margin_bottom
			check(node.size.x >= fixed_width and node.size.y >= fixed_height,
				page+" / "+str(node.name)+" keeps illustrated corners at native proportions")
	for child: Node in node.get_children():
		check_material_bounds(child, page)

func _run() -> void:
	create_timer(90.0,true,false,true).timeout.connect(func(): push_error("Menu capture timeout"); quit(3))
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	change_scene_to_file("res://scenes/lobby.tscn")
	await scene_changed
	lobby=current_scene
	settings=root.get_node("Session/Settings")
	settings.settings_path="user://medieval_menu_probe_%d.cfg" % OS.get_process_id()
	root.content_scale_size=Vector2i(1600,900)
	for dimensions: Vector2i in [Vector2i(1280,720),Vector2i(1600,900),Vector2i(1920,1080)]:
		root.size=dimensions
		await settle()
		for name: String in ["SoloMenu","Multiplayer","RogueMode","Codex","Sandbox","Settings","QuitGame"]:
			var button: Button=lobby.get_node("%"+name)
			in_bounds(button,str(dimensions.x)+" "+name)
			check(button.get_theme_stylebox("normal") is StyleBoxTexture,name+" has material theme")
		await capture("lobby_%d" % dimensions.x)
		lobby._on_open_solo()
		await settle()
		in_bounds(lobby.get_node("%SoloPanel"),"solo briefing")
		in_bounds(lobby.get_node("%SoloStart"),"solo start action")
		await capture("solo_%d" % dimensions.x)
		lobby._on_close_solo()
		lobby._on_open_multiplayer()
		await settle()
		in_bounds(lobby.get_node("%OnlinePanel"),"multiplayer panel")
		await capture("online_%d" % dimensions.x)
		lobby._on_close_multiplayer()
		settings.open_menu()
		for page: String in ["Graphics","Audio","Controls","Hotkeys"]:
			settings.menu.show_page(page)
			await settle()
			in_bounds(settings.menu.get_node("Center/Panel"),"settings parchment")
			in_bounds(settings.menu.get_node("%Done"),"settings done action")
			await capture("settings_%s_%d" % [page.to_lower(),dimensions.x])
		settings.close_menu()
	check(not settings.is_open(),"settings closes without changing preferences")
	print("MEDIEVAL_MENU_UI ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
