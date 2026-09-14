extends SceneTree
## Native codex, animation and the actual batched sandbox; no synthetic renders.
const OUTPUT := "res://.local/crossbow-20260914/visual/"
var checks: int = 0
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL ",label)
func capture(label: String, viewport: Viewport) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	check(viewport.get_texture().get_image().save_png(OUTPUT+label+".png") == OK,label)
func _run() -> void:
	create_timer(90,true,false,true).timeout.connect(func(): quit(3))
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	root.gui_disable_input = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var codex: Control = load("res://scenes/unit_codex.tscn").instantiate()
	root.add_child(codex)
	codex.open_codex()
	codex.select_entry(0,"crossbowman")
	await create_timer(.4).timeout
	codex.set_process(false)
	var model: UnitVisual = codex._model
	var triangles: int = 0
	for mesh: MeshInstance3D in model.get_node("Rig").find_children("*","MeshInstance3D",true,false):
		triangles += mesh.mesh.get_faces().size()/3
	check(triangles <= 6500,"triangle budget")
	check(codex.get_node("%Stats").text.contains("无视 3 点护甲") and codex.get_node("%FamilyTag").text == "远程步兵","penetration and shared tag shown")
	await capture("codex",root)
	for angle: int in [0,45,90,180,270]:
		codex._anchor.rotation.y = deg_to_rad(angle)
		codex._request_preview_redraw()
		await capture("angle-%03d" % angle,codex._viewport)
	codex._anchor.rotation.y = 0
	var camera_transform: Transform3D = codex._camera.transform
	var camera_size: float = codex._camera.size
	codex._camera.position = Vector3(3,2,-5)
	codex._camera.look_at(Vector3(0,1.22,-.35),Vector3.UP)
	codex._camera.size = 1.4
	codex._request_preview_redraw()
	await capture("grip-detail",codex._viewport)
	codex._camera.position = Vector3(2,2.6,-4)
	codex._camera.look_at(Vector3(0,1.77,0),Vector3.UP)
	codex._camera.size = 1
	codex._request_preview_redraw()
	await capture("face-detail",codex._viewport)
	codex._camera.transform = camera_transform
	codex._camera.size = camera_size
	for action: int in [1,2]:
		codex._select_preview_action(action)
		codex.set_process(false)
		codex._advance_preview(.2)
		for frame: int in 24:
			var player: AnimationPlayer = model.locomotion if action == 1 else model.attack
			player.seek(frame*(.72 if action==1 else .96)/24.0,true)
			codex._request_preview_redraw()
			await capture("%s-%02d" % ["walk" if action==1 else "strike",frame],codex._viewport)
	codex._camera.position = Vector3(1,6,-1.5)
	codex._camera.look_at(Vector3(0,1,0),Vector3.UP)
	codex._camera.size = 3.4
	codex._request_preview_redraw()
	await capture("top",codex._viewport)
	codex.get_node("%FamilyFilter").select(2)
	codex._on_filters_changed(2)
	check(codex._entries == ["archer","crossbowman","musketeer"],"ranged infantry filter shows all three ranged infantry")
	await capture("ranged-filter",root)
	codex.get_node("%RoleFilter").select(2)
	codex._on_filters_changed(2)
	check(codex._entries.is_empty() and codex.get_node("%EmptyResults").visible,"incompatible filter has explicit empty state")
	await capture("empty-filter",root)
	codex._clear_filters()
	codex.get_node("%RoleFilter").select(2)
	codex._on_filters_changed(2)
	check(codex._entries == ["engineer","priest"],"support role filter")
	await capture("support-filter",root)
	codex.select_entry(0,"crossbowman")
	check(codex.selected_id == "crossbowman" and codex._entries.size() == 16,"explicit entry link clears obstructing filters")
	codex.queue_free()
	await process_frame
	var previews: Node = load("res://scenes/model_previews.tscn").instantiate()
	root.add_child(previews)
	await create_timer(.4).timeout
	await RenderingServer.frame_post_draw
	var bounds: Rect2i = previews.portrait("crossbowman").get_image().get_used_rect()
	check(bounds.size.x>40 and bounds.position.x>1 and bounds.end.x<191 and bounds.position.y>1 and bounds.end.y<215,"portrait fits")
	previews.queue_free()
	await process_frame
	change_scene_to_file("res://scenes/sandbox.tscn")
	await scene_changed
	var game: Node3D = current_scene
	while not game._match_ready: await process_frame
	game.camera_rig.set_process(false)
	game.camera_rig.edge_scroll = false
	game.hud.get_node("Sidebar/Scroll/Content/Kinds/crossbowman").pressed.emit()
	check(game.paint_kind=="crossbowman" and game._ghost.kind=="crossbowman","sandbox entry")
	game.set_placing(false)
	game.hud.hide()
	game.camera_rig.camera.size = 8.5
	game.camera_rig.camera.position = Vector3(3,6,-10)
	game.camera_rig.camera.look_at(Vector3(0,.8,0),Vector3.UP)
	for entry: Array in [["swordsman",-3],["crossbowman",0],["archer",3]]:
		game.spawn_unit(entry[0],0,Vector3(entry[1],0,0))
	await capture("comparison",root)
	game.clear_units()
	await process_frame
	for owner: int in 3: game.spawn_unit("crossbowman",owner,Vector3((owner-1)*2,0,0))
	await capture("teams",root)
	game.clear_units()
	await process_frame
	var shooter: BattleUnit = game.spawn_unit("crossbowman",0,Vector3(0,0,1.5))
	var target: BattleUnit = game.spawn_unit("shield_guard",1,Vector3(0,0,-4))
	target.hold()
	shooter.issue_attack(target)
	game.set_running(true)
	await create_timer(.65).timeout
	check(target.hp == 140,"real bolt deals five through shield armor")
	game.select_entities([shooter])
	await capture("battle",root)
	game.camera_rig.camera.size = 24
	await capture("battle-scale",root)
	game.camera_rig.camera.size = 5
	shooter.receive_damage(60)
	await create_timer(.55).timeout
	await capture("death",root)
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await process_frame
	FileAccess.open(OUTPUT+"results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"triangles":triangles,"failures":failures},"\t"))
	print("CROSSBOW_VISUAL ",checks," checks; ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
