extends SceneTree
## Exercise real map -> combat -> result -> checkpoint transitions, separately
## from the objective/balance simulations. Outcomes are injected at the UI seam.
var rogue: Node
var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	root.visible = false
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func wait_ready() -> void:
	var transition: UITransition = root.get_node("Session").transition
	if transition.busy:
		await transition.completed
	for index: int in 5: await process_frame

func next_node(kind: String, ap: int = 8) -> int:
	var target: int = -1
	for node: Dictionary in rogue.state.data.nodes:
		if node.kind == kind and not node.completed:
			target = int(node.id)
			break
	for edge: Array in rogue.state.data.edges:
		if int(edge[0]) == target:
			rogue.state.data.current_node = int(edge[1])
			break
		if int(edge[1]) == target:
			rogue.state.data.current_node = int(edge[0])
			break
	rogue.state.data.phase = "map"
	rogue.state.data.ap = ap
	return target

func finish(victory: bool) -> void:
	var battle: Node3D = current_scene
	battle.skip_intro()
	battle.end_battle(victory)
	check(battle.finished,"battle result is shown")
	battle.accept_result()
	await scene_changed
	await wait_ready()
	check(current_scene.scene_file_path==RogueSession.MAP_SCENE,"result returns to forest scene")

func claim_and_discard_recruit() -> void:
	check(rogue.state.data.phase == "settlement", "victory awaits explicit reward collection")
	check(current_scene.victory_rewards.visible, "native reward screen is visible")
	current_scene.victory_rewards.claim.pressed.emit()
	await wait_ready()
	check(rogue.confirm_settlement() != OK, "repeated claim cannot grant rewards twice")
	if rogue.state.data.phase == "recruit_unit":
		check(current_scene.recruit_overlay.visible, "reward voucher opens immediately")
		check(rogue.leave_node() != OK, "cannot leave with unresolved recruitment")
		var ticket: Dictionary = rogue.state.pending_recruit()
		check(rogue.discard_recruit(int(ticket.uid)) == OK, "explicitly discard reward voucher")
		await wait_ready()

func _run() -> void:
	create_timer(60.0,true,false,true).timeout.connect(func(): quit(3))
	rogue = root.get_node("Session").rogue
	rogue.save_path = "user://rogue_transition_test_%d.json" % OS.get_process_id()
	check(rogue.start_new("range","mobile",99223)==OK,"new run")
	await scene_changed
	await wait_ready()
	check(rogue.state.data.phase == "recruit_unit", "initial voucher must be handled before exploration")
	check(rogue.discard_recruit(int(rogue.state.pending_recruit().uid)) == OK, "discard initial voucher")
	await wait_ready()
	var roster: Array = rogue.state.data.roster.duplicate(true)
	var normal: int = next_node("battle")
	check(rogue.enter_node(normal)==OK,"enter outpost through session")
	await scene_changed
	await wait_ready()
	check(current_scene.scene_file_path==RogueSession.BATTLE_SCENE,"actual battle scene loads")
	check(current_scene.player_count()==roster.size(),"roster instantiated in battle")
	await finish(true)
	check(int(rogue.state.data.gold) == 20 and int(rogue.state.data.xp) == 0, "settlement preview does not grant rewards")
	await claim_and_discard_recruit()
	check(rogue.state.data.phase=="map" and rogue.state.node(normal).completed,"normal victory completes node")
	check(int(rogue.state.data.xp)==50 and int(rogue.state.data.gold)==40,"normal reward once")
	check(rogue.state.data.roster==roster,"battle does not rewrite roster or layouts")
	var emergency: int = next_node("emergency",1)
	check(rogue.enter_node(emergency)==OK,"enter emergency on last AP")
	await scene_changed
	await wait_ready()
	check(current_scene.emergency,"emergency battle variant selected")
	await finish(true)
	await claim_and_discard_recruit()
	check(rogue.state.data.phase=="reward","emergency waits for relic reward")
	check(int(rogue.state.data.level)==2 and rogue.state.population_cap()==25,"XP upgrades level and population")
	check(rogue.choose_relic(str(rogue.state.data.pending_choices[0]))==OK,"finish emergency relic selection")
	await wait_ready()
	check(rogue.state.data.phase=="siege_briefing","last AP resolved only after reward")
	check(rogue.launch_battle()==OK,"forced siege scene launches")
	await scene_changed
	await wait_ready()
	check(current_scene.battle_kind=="siege","central-base scenario selected")
	await finish(false)
	check(rogue.state.data.phase=="game_over","defeat returns to game over")
	check(rogue.load_run()==OK,"game over can retry last checkpoint")
	await scene_changed
	await wait_ready()
	check(rogue.state.data.phase=="siege_briefing","retry preserves mandatory siege")
	check(rogue.launch_battle()==OK,"retry siege")
	await scene_changed
	await wait_ready()
	await finish(true)
	await claim_and_discard_recruit()
	check(rogue.state.data.phase=="intermission" and int(rogue.state.data.ap)==12,"siege victory restores AP and reaches intermission")
	check(rogue.load_run()==OK,"load intermission checkpoint")
	await scene_changed
	await wait_ready()
	check(rogue.state.data.phase=="intermission","no nonexistent second floor is generated")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(rogue.save_path))
	print("ROGUE_TRANSITION ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
