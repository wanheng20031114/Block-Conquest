extends Control
## Combat-only native controls; no recruitment, resources or construction actions.
var game: Node3D
var _notice_seconds: float = 0.0

func _ready() -> void:
	UIMotion.bind_buttons(self)
	UIMotion.reveal.call_deferred(%Objectives, Vector2(0, -8))
	UIMotion.reveal.call_deferred(%IntroPanel)

func bind_game(controller: Node3D) -> void:
	game = controller
	%Minimap.game = game
	%Minimap.map_clicked.connect(game._on_minimap_clicked)
	%Army.pressed.connect(game.select_army)
	%Attack.pressed.connect(game.set_attack_mode.bind(true))
	%Stop.pressed.connect(game.stop_selected)
	%Hold.pressed.connect(game.hold_selected)
	%Pause.pressed.connect(game.handle_pause_action)
	%Skip.pressed.connect(game.skip_intro)
	%Continue.pressed.connect(game.accept_result)
	%Resume.pressed.connect(game.handle_pause_action)
	%Settings.pressed.connect(game.open_settings)
	%Leave.pressed.connect(game.return_to_menu)

func refresh() -> void:
	if game == null or game.encounter == null:
		return
	%Title.text = "围剿" if game.battle_kind == "siege" else ("前哨站 · 紧急作战" if game.emergency else "前哨站")
	%Eyebrow.text = ("作战目标 · 坚守待援 · 难度 %d" if game.battle_kind == "siege" else "作战目标 · 肃清据点 · 难度 %d") % game.encounter.difficulty
	if game.battle_kind == "siege":
		var seconds: int = maxi(0, ceili(game.encounter.duration - game.elapsed))
		%Objective.text = "守住中央大本营，等待援军抵达"
		%Progress.text = "坚守 %02d:%02d    ·    第 %d / 7 波    ·    敌军 %d" % [seconds / 60, seconds % 60, game.wave_index, game.living_enemies()]
		if is_instance_valid(game.headquarters):
			%Detail.text = "大本营  %d / %d    ·    部队全灭后仍可继续坚守" % [ceili(game.headquarters.hp), ceili(game.headquarters.max_hp)]
	else:
		%Objective.text = "摧毁所有敌方建筑物与部队"
		%Progress.text = "剩余建筑 %d / 8    ·    敌军 %d / %d" % [game.remaining_buildings(), game.living_enemies(), game.enemy_total]
		%Detail.text = "向东推进 · 搜索队会主动接近我军"
	%ArmyCount.text = "远征军  %d 人" % game.player_count()
	%IntroPanel.visible = game.intro_active and not game.finished
	%Commands.visible = not game.intro_active
	%MapPanel.visible = not game.intro_active
	%Skip.disabled = not game._match_ready
	%PortraitName.text = "侦察队长 · 罗文"
	%Dialogue.text = ("包围已经形成。敌军会从四周不断涌来！守住中央大本营，援军将在两分半后抵达。" if game.battle_kind == "siege" else "指挥官，前方是林地前哨站。五座箭塔扼守道路，三个兵营分列纵深。清除所有守军与建筑，小心巡逻队从侧翼接近。")
	var own: Array = game.own_selected_units()
	%Selection.text = "框选部队 · 右键移动或攻击" if game.selection.is_empty() else "%s%s" % [game.selection[0].display_name, "  ·  已选择 %d 个目标" % game.selection.size() if game.selection.size() > 1 else ""]
	%Attack.disabled = own.is_empty() or game.intro_active or game.finished
	%Stop.disabled = %Attack.disabled
	%Hold.disabled = %Attack.disabled
	%Pause.disabled = game.intro_active or game.finished
	%Attack.set_pressed_no_signal(game.attack_mode)

func toast(message: String, seconds: float = 2.0) -> void:
	%Notice.text = message
	_notice_seconds = seconds

func _process(delta: float) -> void:
	if _notice_seconds > 0.0:
		_notice_seconds -= delta
		if _notice_seconds <= 0.0:
			%Notice.text = ""

func show_result(victory: bool, duration: float, defeated: int) -> void:
	%IntroPanel.hide()
	%ModalShade.show()
	%ResultPanel.show()
	UIMotion.reveal(%ResultPanel, Vector2(0, 18))
	%ResultTitle.text = "坚守成功" if victory and game.battle_kind == "siege" else ("作战胜利" if victory else "远征结束")
	%ResultBody.text = ("援军抵达，围剿已经瓦解。前往整顿营地。" if game.battle_kind == "siege" else "前哨站已肃清，军队准备继续探索。") if victory else ("大本营被摧毁，本次远征到此结束。" if game.battle_kind == "siege" else "部署部队已全部阵亡，本次远征到此结束。")
	%ResultDetail.text = "作战用时 %02d:%02d    ·    击败敌军 %d\n军队名册与初始编队保留，本场伤亡不带出战场。" % [int(duration) / 60, int(duration) % 60, defeated]
	%Continue.text = "前往整顿营地" if victory and game.battle_kind == "siege" else ("领取结算" if victory else "查看远征记录")

func show_pause(value: bool) -> void:
	%PausePanel.visible = value
	%ModalShade.visible = value
	if value:
		UIMotion.reveal(%PausePanel)

func help_visible() -> bool:
	return false
