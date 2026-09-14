extends SceneTree
## Real native scenes, isolated save file, and presentation/flow integration.
var failures: Array[String] = []
var checks: int = 0
var rogue: Node
var map: Node3D
var capture_enabled: bool = false
const OUTPUT: String = "res://artifacts/rogue"

func _initialize() -> void:
	root.visible = false
	root.unfocusable = true
	capture_enabled = DisplayServer.get_name() != "headless"
	if capture_enabled:
		RenderingServer.viewport_set_update_mode(root.get_viewport_rid(),RenderingServer.VIEWPORT_UPDATE_ALWAYS)
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func settle() -> void:
	for index: int in 4: await process_frame

func click_world(point: Vector3) -> void:
	var location: Vector2 = map.camera.unproject_position(point)
	var motion := InputEventMouseMotion.new()
	motion.position = location
	motion.global_position = location
	root.push_input(motion, true)
	await physics_frame
	for pressed: bool in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = location
		event.global_position = location
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event,true)
		await physics_frame
	await settle()

func capture(name: String) -> void:
	if not capture_enabled: return
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	var error: Error = root.get_texture().get_image().save_png(OUTPUT + "/" + name + ".png")
	check(error == OK,"capture " + name)

func start_run() -> void:
	check(rogue.start_new("ranged","steady",73113) == OK,"start isolated run")
	await scene_changed
	map = current_scene
	await settle()

func pick_kind(kind: String) -> int:
	for node: Dictionary in rogue.state.data.nodes:
		if node.kind == kind and not node.completed: return int(node.id)
	return -1

func prepare_adjacent(target: int, ap: int = 12) -> void:
	for edge: Array in rogue.state.data.edges:
		if int(edge[0]) == target:
			rogue.state.data.current_node = int(edge[1])
			break
		if int(edge[1]) == target:
			rogue.state.data.current_node = int(edge[0])
			break
	rogue.state.data.ap = ap
	rogue.state.data.phase = "map"
	map._refresh()

func inspect_layout(label: String) -> void:
	var bounds: Rect2 = root.get_visible_rect()
	for path: String in ["Canvas/UI/Top","Canvas/UI/Bottom","Canvas/UI/Rail"]:
		var control: Control = map.get_node(path)
		check(bounds.encloses(control.get_global_rect()),label+" "+path+" within viewport")
	var options: Control = map.get_node("Canvas/UI/Preview")
	check(bounds.encloses(options.get_global_rect()),label+" preview within viewport")

func _run() -> void:
	create_timer(100.0,true,false,true).timeout.connect(func(): push_error("Rogue flow timeout"); quit(3))
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	rogue = root.get_node("Session").rogue
	rogue.save_path = "user://rogue_flow_test_%d.json" % OS.get_process_id()
	root.content_scale_size = Vector2i(1600,900)
	root.size = Vector2i(1600,900)
	await start_run()
	check(map.get_node("Nodes").get_child_count()==34,"34 authored forest nodes")
	check(rogue.state.population()==18,"starter deployment populated")
	var original_cost: int = int(RogueCatalog.EVENTS.bread_cart.gold_cost)
	RogueCatalog.EVENTS.bread_cart.gold_cost = 21
	check("21" in map._event_options("bread_cart")[1] and not map._event_affordable("bread_cart",1),"editable event price updates display and affordability together")
	RogueCatalog.EVENTS.bread_cart.gold_cost = original_cost
	var battle: int = pick_kind("battle")
	prepare_adjacent(battle)
	await click_world(map.get_node("Nodes/Node%d" % battle).global_position+Vector3.UP)
	check(map._preview_id==battle,"actual mouse input picks 3D route node")
	await settle()
	check(map.preview.visible,"node preview is visible")
	check(not map.content.get_node("Primary").disabled,"adjacent battle can enter")
	map._toggle_pause_menu()
	check(map.get_node("Canvas/UI/PauseMenu").visible,"map pause menu opens")
	await capture("pause")
	var selected_before: int = map._preview_id
	map._select_node((selected_before+1)%34)
	check(map._preview_id==selected_before,"pause blocks route interaction")
	map._toggle_pause_menu()
	await capture("map_1600")
	for size: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size = size
		await settle()
		inspect_layout(str(size))
		await capture("map_%d" % size.x)
	root.size = Vector2i(1600,900)
	map._new_run_requested = true
	map._setup_step = 0
	map._refresh()
	await capture("strategy")
	map._setup_choice(1)
	check(map._strategy=="melee" and map._setup_step==1,"strategy then independent pack")
	await capture("starter_army")
	map._new_run_requested = false
	map._refresh()
	map._open_army("formation")
	await settle()
	check(map.army.visible,"real formation opens")
	await capture("formation")
	map.army.close_panel()
	map._open_army("recruit")
	await settle()
	await capture("recruit")
	map.army.close_panel()
	var shop: int = pick_kind("shop")
	prepare_adjacent(shop)
	check(rogue.enter_node(shop)==OK,"enter actual shop")
	await settle()
	check(map._panel_mode=="shop","shop buttons rendered")
	check(map.content.get_node("Options").get_child_count()==6,"six native offer controls")
	await capture("shop")
	check(rogue.leave_node()==OK,"shop exit checkpoint")
	var event: int = pick_kind("event")
	prepare_adjacent(event)
	check(rogue.enter_node(event)==OK,"enter actual event")
	await settle()
	check(map._panel_mode=="event","event options rendered")
	await capture("event")
	check(rogue.resolve_event(0)==OK,"event resolves")
	await settle()
	check(map._panel_mode=="resolved","event result page")
	check(rogue.leave_node()==OK,"event exit saves")
	var camp: int = pick_kind("camp")
	prepare_adjacent(camp)
	check(rogue.enter_node(camp)==OK,"enter camp")
	check(rogue.choose_camp(2)==OK,"camp treasure choice")
	await settle()
	check(map._panel_mode=="relic","three relic choices rendered")
	await capture("relic_choice")
	var relic: String = str(rogue.state.data.pending_choices[0])
	check(rogue.choose_relic(relic)==OK,"take selected relic")
	check(rogue.leave_node()==OK,"camp exits")
	await settle()
	var road: int = pick_kind("road")
	prepare_adjacent(road,1)
	check(rogue.enter_node(road)==OK,"last AP road is traversable")
	await settle()
	check(rogue.state.data.phase=="siege_briefing","AP zero produces unavoidable siege")
	check(map._panel_mode=="siege","siege briefing rendered")
	await create_timer(2.1).timeout
	await capture("siege_briefing")
	check(rogue.load_run()==OK,"reload checkpoint")
	await scene_changed
	map = current_scene
	await settle()
	check(rogue.state.data.phase=="siege_briefing","reload cannot bypass siege")
	rogue.state.data.phase = "intermission"
	rogue.state.data.floor = 2
	rogue.state.data.ap = 12
	map._refresh()
	await capture("intermission")
	rogue.state.data.phase = "game_over"
	map._refresh()
	await capture("game_over")
	var file := FileAccess.open(OUTPUT+"/flow-results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	file.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(rogue.save_path))
	print("ROGUE_FLOW ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
