extends SceneTree
## Exercises the authored cards with native pointer input and immutable state snapshots.
var checks: int = 0
var failures: Array[String] = []
var recruit: Control
var rewards: Control
var run_state: RogueRunState
var choices: Array[Dictionary] = []
var claims: int = 0
var escaped_clicks: int = 0

func _initialize() -> void:
	root.visible = false
	root.unfocusable = true
	root.size = Vector2i(1280,720)
	root.content_scale_size = Vector2i(1280,720)
	RenderingServer.viewport_set_update_mode(root.get_viewport_rid(),RenderingServer.VIEWPORT_UPDATE_ALWAYS)
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL ", label)

func settle() -> void:
	await create_timer(.5,true,false,true).timeout

func click(control: Control, double_click: bool = false) -> void:
	var at: Vector2 = control.get_global_rect().get_center()
	for down: bool in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = at
		event.global_position = at
		event.pressed = down
		event.double_click = double_click and down
		root.push_input(event,true)
		await process_frame

func image(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://.local/rogue_reward_components/"+label+".png") == OK,"capture "+label)

func check_card_bounds() -> void:
	for card: Button in recruit.cards:
		check(root.get_visible_rect().encloses(card.get_global_rect()),"card fits 1280×720")
		for item: Node in card.find_children("*","Label",true,false):
			check(card.get_global_rect().encloses(item.get_global_rect()),"card label "+str(item.name)+" stays on paper")
			check(not str(item.text).contains("人口"),"recruit card omits per-unit population")

func _run() -> void:
	create_timer(45,true,false,true).timeout.connect(func(): quit(3))
	# Apply after Session settings have initialized the window.
	root.size = Vector2i(1280,720)
	root.content_scale_size = Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute("res://.local/rogue_reward_components")
	var underlying := Button.new()
	root.add_child(underlying)
	underlying.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	underlying.pressed.connect(func(): escaped_clicks += 1)
	var shade := ColorRect.new()
	root.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(.12,.23,.18,1)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	run_state = RogueRunState.new()
	check(run_state.start_new("ranged","steady",73017) == OK,"prepare run only in memory")
	var original_state: String = JSON.stringify(run_state.data)
	recruit = load("res://scenes/rogue/recruit_overlay.tscn").instantiate()
	rewards = load("res://scenes/rogue/victory_rewards.tscn").instantiate()
	root.add_child(recruit)
	root.add_child(rewards)
	recruit.unit_chosen.connect(func(uid: int, kind: String): choices.append({"action":"kind","uid":uid,"kind":kind}))
	recruit.batches_chosen.connect(func(uid: int, batches: int): choices.append({"action":"batches","uid":uid,"batches":batches}))
	recruit.back_requested.connect(func(): choices.append({"action":"back"}))
	recruit.discard_requested.connect(func(uid: int): choices.append({"action":"discard","uid":uid}))
	rewards.claim_requested.connect(func(): claims += 1)
	var ticket: Dictionary = {"uid":41,"candidates":["swordsman","archer","heavy_cannon"]}
	recruit.render_ticket(ticket,3,run_state)
	await settle()
	check_card_bounds()
	check(recruit.cards[2].disabled,"unaffordable heavy cannon card is disabled")
	check(recruit.cards[2].get_node("Margin/Body/Action/Text").text == "还差 1 面包","disabled card explains missing bread")
	check(not recruit.back_button.visible,"unit selection has no ordinary close/back button")
	check(recruit.cards[0].get_meta("count") == 3 and recruit.cards[1].get_meta("cost") == 1,"unit cards show batch counts and bread prices")
	await image("units_1280")
	var stable_tween: Variant = recruit._animation
	recruit.render_ticket(ticket,3,run_state)
	check(recruit._animation == stable_tween,"unchanged refresh does not restart entrance")
	await click(recruit.cards[2])
	check(choices.is_empty(),"native disabled card cannot emit a choice")
	await click(recruit.cards[1])
	check(choices.size() == 1 and choices[0] == {"action":"kind","uid":41,"kind":"archer"},"native card selects correct ticket and unit")
	await click(recruit.cards[1])
	check(choices.size() == 1,"repeated click cannot resubmit before owner refresh")
	recruit.render_ticket(ticket,2,run_state,"archer")
	await settle()
	check(recruit.cards[1].get_meta("count") == 6 and recruit.cards[1].get_meta("cost") == 2,"two archer batches show six units and two bread")
	check(recruit.cards[2].disabled,"three batches disabled with two bread")
	check(recruit.back_button.visible,"batch selection offers return to units")
	check_card_bounds()
	await image("batches_1280")
	await click(recruit.back_button)
	check(choices[-1].action == "back","native return requests previous stage")
	recruit.render_ticket(ticket,2,run_state)
	await click(recruit.cards[0])
	check(choices[-1].action == "kind" and choices[-1].kind == "swordsman","first click during entrance still performs selection")
	recruit.render_ticket(ticket,3,run_state,"swordsman")
	await click(recruit.cards[2])
	check(choices[-1].action == "batches" and choices[-1].batches == 3,"first click during phase flip still confirms three batches")
	recruit.render_ticket(ticket,3,run_state)
	var choices_before_double: int = choices.size()
	recruit.unit_chosen.connect(func(_uid: int, kind: String): recruit.render_ticket(ticket,3,run_state,kind),CONNECT_ONE_SHOT)
	await click(recruit.cards[0])
	check(choices.size() == choices_before_double + 1 and recruit._selected_kind == "swordsman","first native press changes to batch round immediately")
	await click(recruit.cards[0],true)
	check(choices.size() == choices_before_double + 1 and not recruit._submitted,"native double-click second press cannot purchase through phase flip")
	await click(recruit.cards[0])
	check(choices.size() == choices_before_double + 2 and choices[-1].action == "batches" and choices[-1].batches == 1,"separate click after double-click confirms exactly one chosen batch")
	recruit.render_ticket(ticket,0,run_state)
	await settle()
	await click(recruit.discard_button)
	check(choices[-1].action == "discard" and choices[-1].uid == 41,"discard only requests confirmation from owner")
	recruit.render_ticket(ticket,0,run_state)
	check(not recruit.discard_button.disabled,"cancelled external discard confirmation can restore actions")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape,true)
	await process_frame
	check(recruit.visible,"Esc never silently closes or discards a ticket")
	var gap := InputEventMouseButton.new()
	gap.button_index = MOUSE_BUTTON_LEFT
	gap.position = Vector2(20,350)
	gap.pressed = true
	root.push_input(gap,true)
	gap = gap.duplicate()
	gap.pressed = false
	root.push_input(gap,true)
	check(escaped_clicks == 0,"overlay blocks empty-space clicks from world UI")
	recruit.hide()
	check(recruit.cards[0].scale.is_equal_approx(Vector2.ONE) and recruit.cards[0].position.y == 0,"hide interrupts card animation cleanly")
	var settlement: Dictionary = {"battle_kind":"outpost","emergency":true,"rewards":{"gold":30,"bread":3,"xp":80,"tickets":1},"claimed":false,"levels":1,"bonus_bread":1,"bonus_population":5,"duration":183.0,"defeated":20}
	rewards.render_settlement(settlement,run_state)
	await settle()
	check(root.get_visible_rect().encloses(rewards.get_node("Center/Paper").get_global_rect()),"reward paper fits 1280×720")
	check(rewards.record.text.contains("3 分 03 秒") and rewards.record.text.contains("击败敌军 20"),"only supplied battle statistics are displayed")
	check(rewards.growth.visible and rewards.growth.text.contains("人口上限 +5"),"settlement shows one-time upgrade preview")
	await image("rewards_1280")
	var stable_reward_tween: Variant = rewards._animation
	rewards.render_settlement(settlement,run_state)
	check(rewards._animation == stable_reward_tween,"duplicate settlement refresh does not restart animation")
	await click(rewards.claim)
	await click(rewards.claim)
	check(claims == 1,"claim only emits once across repeated native clicks")
	settlement.claimed = true
	rewards.render_settlement(settlement,run_state)
	check(rewards.claim.disabled and rewards.claim.text == "已领取","claimed snapshot clearly disables a second claim")
	settlement = {"battle_kind":"siege","emergency":false,"rewards":{"gold":0,"bread":0,"xp":0,"tickets":0},"claimed":false,"levels":0,"bonus_bread":0,"bonus_population":0}
	rewards.render_settlement(settlement,run_state)
	await settle()
	check(not rewards.get_node("Center/Paper/Margin/Content/Rewards").visible,"siege omits four empty reward columns")
	check(rewards.get_node("Center/Paper/Margin/Content/Recovery").visible and rewards.claim.text == "完成整备","siege shows restored action and intermission action")
	check(not rewards.status.text.contains("招募券"),"siege does not promise nonexistent recruitment rewards")
	await image("siege_1280")
	await click(rewards.claim)
	check(rewards.claim.disabled,"siege claim locks while owner saves")
	rewards.render_settlement(settlement,run_state)
	check(not rewards.claim.disabled and not rewards._submitted,"same unclaimed snapshot unlocks claim after save rollback")
	await click(rewards.claim)
	check(claims == 3,"siege save rollback allows exactly one new claim attempt")
	rewards.hide()
	check(JSON.stringify(run_state.data) == original_state,"rendering and all card actions leave the run state unchanged")
	recruit.queue_free()
	rewards.queue_free()
	await process_frame
	print("ROGUE_REWARD_COMPONENT_CHECKS ",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
