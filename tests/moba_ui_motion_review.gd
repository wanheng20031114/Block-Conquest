extends SceneTree
## Actual GUI input and saved native animations; may also run headless for assertions.
const OUTPUT := "res://.local/moba-ui/"
var game: Node3D
var failures: Array[String] = []
var checks := 0
var _pointer := Vector2.ZERO
var _dragging := false

func _initialize() -> void: run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr("FAIL ",message)

func pause_for(seconds: float) -> void:
	await create_timer(seconds).timeout

func screen_rect(control: Control) -> Rect2:
	return control.get_global_transform() * Rect2(Vector2.ZERO,control.size)

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT + name + ".png")
	print("MOBA_MOTION_FRAME ",name)

func mouse(at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	event.relative = at - _pointer
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if _dragging else 0
	_pointer = at
	Input.parse_input_event(event)

func click(pressed: bool, code: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.position = _pointer
	event.global_position = _pointer
	event.button_index = code
	event.pressed = pressed
	Input.parse_input_event(event)
	if code == MOUSE_BUTTON_LEFT: _dragging = pressed

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	var release: InputEventKey = event.duplicate()
	release.pressed = false
	Input.parse_input_event(release)

func drag(card: Control, target: Vector2) -> void:
	mouse(card.get_global_rect().get_center())
	await process_frame
	click(true)
	await process_frame
	var start: Vector2 = _pointer
	for progress: float in [.2,.5,.75,1.0]:
		mouse(start.lerp(target,progress))
		await pause_for(.07)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	create_timer(60,true,false,true).timeout.connect(func(): quit(3))
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	root.size = Vector2i(1600,900)
	change_scene_to_file("res://scenes/moba/test1.tscn")
	await scene_changed
	game = current_scene
	while not game._match_ready: await process_frame
	if "--recording" in OS.get_cmdline_user_args():
		DisplayServer.window_set_position(Vector2i(20000,20000))
	game.camera_rig.edge_scroll = false
	game.camera_rig.set_process(false)
	game.hud.toast_remaining = .01
	var hud: Control = game.hud
	var card: Control = hud.cards[0]
	await pause_for(.6)
	var board: Control = hud.get_node("%Console")
	check(board.is_ancestor_of(hud.get_node("%MapPanel")) and board.is_ancestor_of(hud.get_node("%Hand")) and board.is_ancestor_of(hud.get_node("%HeroPanel")),"all bottom controls share one saved console")
	check(board.get_global_rect().size.x == root.size.x,"console spans the viewport")
	check(card.get_node("%Visual").modulate.a == 1 and card.phase == card.Phase.STEADY,"entrance finishes without leaving translucent cards")
	await capture("console")
	mouse(hud.cards[2].get_global_rect().get_center())
	await pause_for(.4)
	check(hud.cards[2].get_node("%Lift").position.y < -16,"native hover lifts the card")
	check(hud.get_node("ModelPreviews")._animated_kind == "swordsman","only hovered portrait animates")
	await capture("hover")
	mouse(Vector2(800,480))
	await pause_for(.25)
	check(hud.get_node("ModelPreviews")._animated_kind == "","portrait clock stops when not hovered")
	await drag(card,Vector2(670,470))
	await pause_for(.25)
	check(root.gui_is_dragging(),"native card preview is active")
	await capture("drag")
	click(true,MOUSE_BUTTON_RIGHT)
	await process_frame
	click(false)
	click(false,MOUSE_BUTTON_RIGHT)
	await pause_for(.35)
	check(card.get_node("%Lift").position.is_equal_approx(Vector2.ZERO),"cancel returns the card to its slot")
	check(card.get_node("%Lift").scale.is_equal_approx(Vector2.ONE) and card.get_node("%Lift").modulate.a == 1,"cancel restores scale and opacity")
	check(game.players[0].gold == 240 and game.card_plays[0] == 0,"return animation does not spend currency")
	await drag(card,Vector2(800,440))
	await pause_for(.2)
	click(false)
	await pause_for(.12)
	check(game.card_plays[0] == 1 and game.players[0].gold == 120,"purchase settles once before departure completes")
	check(card.definition == null and card.phase == card.Phase.DISPATCHING,"departure preserves the spent card visual only")
	await capture("dispatch")
	# Rapid hover while the card is leaving must never cancel its fade or refill.
	for index: int in 8:
		card._hover(index % 2 == 0)
	await pause_for(.4)
	check(card.phase == card.Phase.WAITING and not card.get_node("%Visual").visible,"hover cannot revive a consumed card")
	check(card.get_node("%Refill").visible and card.get_node("%RefillProgress").value > 0,"empty slot displays authoritative refill progress")
	await capture("refill")
	await pause_for(1.55)
	check(card.definition != null and card.phase == card.Phase.STEADY,"new card completes its entrance")
	check(card.get_node("%Visual").modulate.a == 1 and card.get_node("%Visual").scale.is_equal_approx(Vector2.ONE),"new card has no residual departure transform")
	await capture("dealt")
	key(KEY_4)
	await pause_for(.35)
	check(game.card_plays[0] == 1,"unaffordable input never plays a card")
	game.local_hero().hp = 80
	key(KEY_E)
	key(KEY_R)
	await pause_for(.25)
	var recovery: Button = hud.get_node("%Recovery")
	check(recovery.get_node("%Title").text == "肉体强化" and recovery.get_node("%Status").text.ends_with("秒"),"cooldown preserves the skill name")
	check(recovery.get_node("%Cooldown").value < 5,"cooldown progress begins empty")
	check(recovery.get_node("%Cooldown").get_theme_stylebox("fill").get_minimum_size() == Vector2.ZERO,"cooldown fill has no artificial minimum footprint")
	await capture("skills")
	await pause_for(.45)
	key(KEY_F5)
	await process_frame
	game.hero_controller.capture_mouse(false)
	await pause_for(.5)
	check(hud.get_node("%Console").visible and game.hero_controller.first_person,"same console works in first person")
	await capture("first-person")
	key(KEY_ESCAPE)
	await pause_for(.2)
	var remaining: float = game.local_hero().recovery_cooldown
	await pause_for(.4)
	check(game.local_hero().recovery_cooldown == remaining,"presentation never advances paused gameplay clocks")
	key(KEY_ESCAPE)
	await process_frame
	key(KEY_F5)
	await pause_for(.3)
	var resolutions: Array[Vector2i] = []
	if "--recording" not in OS.get_cmdline_user_args():
		resolutions.assign([Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1080)])
	for resolution: Vector2i in resolutions:
		root.size = resolution
		await process_frame
		await process_frame
		check(is_equal_approx(screen_rect(board).size.x,root.get_visible_rect().size.x),"continuous console spans the logical viewport at %s"%resolution)
		check(not screen_rect(hud.cards[0]).intersects(screen_rect(hud.get_node("%MapPanel"))) and not screen_rect(hud.cards[4]).intersects(screen_rect(hud.get_node("%HeroPanel"))),"map, cards and hero retain separate hit areas %s"%resolution)
	root.size = Vector2i(1600,900)
	await process_frame
	# Right-clicking blank console surface must not issue a world order.
	game.local_hero().stop()
	mouse(Vector2(350,850))
	click(true,MOUSE_BUTTON_RIGHT)
	click(false,MOUSE_BUTTON_RIGHT)
	await process_frame
	check(game.local_hero().order == BattleUnit.Order.IDLE,"blank console blocks battlefield commands")
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await process_frame
	print("MOBA_MOTION ",checks," checks; ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
