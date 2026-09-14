extends SceneTree
## Actual saved-model, codex and battlefield captures. Atlases avoid raw-frame clutter.
const OUTPUT := "res://.local/musketeer-20260914/visual/"
var checks: int = 0
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL ", label)
func frame(viewport: Viewport) -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()
func save(label: String, picture: Image) -> void:
	check(picture.save_png(OUTPUT + label + ".png") == OK, label + " captured")
func cell(sheet: Image, picture: Image, index: int, columns: int, size: Vector2i) -> void:
	var fit: float = minf(float(size.x)/picture.get_width(), float(size.y)/picture.get_height())
	picture.resize(roundi(picture.get_width()*fit), roundi(picture.get_height()*fit), Image.INTERPOLATE_LANCZOS)
	picture.convert(sheet.get_format())
	sheet.blit_rect(picture, Rect2i(Vector2i.ZERO, picture.get_size()), Vector2i(index % columns, index / columns) * size + (size-picture.get_size())/2)
func _run() -> void:
	create_timer(90,true,false,true).timeout.connect(func():quit(3))
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	root.gui_disable_input = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var codex: Control = load("res://scenes/unit_codex.tscn").instantiate()
	root.add_child(codex)
	codex.open_codex()
	codex.select_entry(0,"musketeer")
	await create_timer(.4).timeout
	codex.set_process(false)
	var model: UnitVisual = codex._model
	var triangles: int = 0
	for mesh: MeshInstance3D in model.get_node("Rig").find_children("*","MeshInstance3D",true,false):
		triangles += mesh.mesh.get_faces().size()/3
	check(triangles <= 6500,"triangle budget")
	check(codex.get_node("%Stats").text.contains("无视 3 点护甲") and codex.get_node("%FamilyTag").text == "远程步兵","penetration and classification visible")
	save("codex",await frame(root))
	var stills := Image.create(1600,1200,false,Image.FORMAT_RGBA8)
	var index: int = 0
	for angle: int in [0,45,90,180,270,315]:
		codex._anchor.rotation.y = deg_to_rad(angle)
		codex._request_preview_redraw()
		cell(stills,await frame(codex._viewport),index,4,Vector2i(400,600))
		index += 1
	codex._anchor.rotation.y = 0
	var camera_transform: Transform3D = codex._camera.transform
	var camera_size: float = codex._camera.size
	codex._camera.position = Vector3(3,2,-5)
	codex._camera.look_at(Vector3(0,1.45,-.30),Vector3.UP)
	codex._camera.size = 1.5
	codex._request_preview_redraw()
	cell(stills,await frame(codex._viewport),6,4,Vector2i(400,600))
	codex._camera.position = Vector3(1,6,-1.5)
	codex._camera.look_at(Vector3(0,1,0),Vector3.UP)
	codex._camera.size = 3.4
	codex._request_preview_redraw()
	cell(stills,await frame(codex._viewport),7,4,Vector2i(400,600))
	save("model-angles",stills)
	codex._camera.transform = camera_transform
	codex._camera.size = camera_size
	for action: int in [1,2]:
		codex._select_preview_action(action)
		codex.set_process(false)
		# Finish the idle -> walk blend before manually seeking capture frames.
		codex._advance_preview(.20)
		var atlas := Image.create(2400,2000,false,Image.FORMAT_RGBA8)
		for sample: int in 24:
			var player: AnimationPlayer = model.locomotion if action == 1 else model.attack
			player.seek(sample*(.72 if action==1 else 2.16)/24.0,true)
			if action==1 and sample in [6,18]:
				var angle: float = model.get_node("Rig/Action/LegLeft").rotation.x
				check(angle>.15 if sample==6 else angle<-.15,"preview walk visibly alternates feet "+str(sample))
			codex._request_preview_redraw()
			cell(atlas,await frame(codex._viewport),sample,6,Vector2i(400,500))
		save("walk-atlas" if action==1 else "strike-atlas",atlas)
	codex.get_node("%FamilyFilter").select(2)
	codex._on_filters_changed(2)
	check(codex._entries == ["archer","crossbowman","musketeer"],"all three ranged infantry appear in filter")
	codex.queue_free()
	await process_frame
	var previews: Node = load("res://scenes/model_previews.tscn").instantiate()
	root.add_child(previews)
	await create_timer(.4).timeout
	await RenderingServer.frame_post_draw
	var bounds: Rect2i = previews.portrait("musketeer").get_image().get_used_rect()
	check(bounds.size.x>40 and bounds.position.x>1 and bounds.end.x<191 and bounds.position.y>1 and bounds.end.y<215,"portrait including hat and barrel fits")
	previews.queue_free()
	await process_frame
	change_scene_to_file("res://scenes/sandbox.tscn")
	await scene_changed
	var game: Node3D = current_scene
	while not game._match_ready: await process_frame
	game.camera_rig.set_process(false)
	game.camera_rig.edge_scroll = false
	game.hud.get_node("Sidebar/Scroll/Content/Kinds/musketeer").pressed.emit()
	check(game.paint_kind=="musketeer" and game._ghost.kind=="musketeer","sandbox button and ghost")
	game.set_placing(false)
	game.hud.hide()
	game.camera_rig.camera.size = 8.5
	game.camera_rig.camera.position = Vector3(3,6,-10)
	game.camera_rig.camera.look_at(Vector3(0,.8,0),Vector3.UP)
	for entry: Array in [["archer",-3],["crossbowman",0],["musketeer",3]]:
		game.spawn_unit(entry[0],0,Vector3(entry[1],0,0))
	save("comparison",await frame(root))
	game.clear_units()
	await process_frame
	for owner: int in 3: game.spawn_unit("musketeer",owner,Vector3((owner-1)*2,0,0))
	save("teams",await frame(root))
	game.clear_units()
	await process_frame
	var shooter: BattleUnit = game.spawn_unit("musketeer",0,Vector3(0,0,1.5))
	var target: BattleUnit = game.spawn_unit("shield_guard",1,Vector3(0,0,-4))
	target.hold()
	shooter.issue_attack(target)
	game.set_running(true)
	await create_timer(.7).timeout
	check(target.hp == 127,"real bullet deals eighteen through shield armor")
	game.select_entities([shooter])
	var battlefield := Image.create(1280,1440,false,Image.FORMAT_RGBA8)
	cell(battlefield,await frame(root),0,1,Vector2i(1280,720))
	game.camera_rig.camera.size = 24
	cell(battlefield,await frame(root),1,1,Vector2i(1280,720))
	save("battle-scales",battlefield)
	game.camera_rig.camera.size = 5
	shooter.receive_damage(75)
	await create_timer(.55).timeout
	save("death",await frame(root))
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await process_frame
	FileAccess.open(OUTPUT+"results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"triangles":triangles,"failures":failures},"\t"))
	print("MUSKETEER_VISUAL ",checks," checks; ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
