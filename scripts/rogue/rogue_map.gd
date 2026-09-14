extends Node3D
## Forest route, native node interaction, and complete between-battle menus.
const STRATEGY_IDS: Array[String] = ["ranged", "melee", "range"]
const PACK_IDS: Array[String] = ["steady", "ranged", "mobile"]
const OUTPOST: RogueBattleDefinition = preload("res://data/rogue/battles/outpost.tres")
const SIEGE: RogueBattleDefinition = preload("res://data/rogue/battles/siege.tres")
const EVENT_TEXT: Dictionary = {
	"bread_cart": ["林间面包车", "一辆满载吐司的马车陷在林道的泥泞里。车夫愿意拿口粮换取援手。"],
	"lost_guard": ["失散守军", "一小队长矛兵守在旧路标旁。他们已经与大部队失联数日。"],
	"hunter_camp": ["废弃猎营", "湿冷的猎营里留着一束干燥箭材，以及一些还能卖钱的铁器。"],
	"mist_chest": ["雾中木箱", "树根下的木箱压着一只旧钱袋。更深处还藏着什么，谁也说不准。"],
}
@onready var rogue = Session.rogue
@onready var ui: Control = $Canvas/UI
@onready var preview: Control = $Canvas/UI/Preview
@onready var content: VBoxContainer = $Canvas/UI/Preview/Scroll/Content
@onready var setup: Control = $Canvas/UI/Setup
@onready var setup_content: VBoxContainer = $Canvas/UI/Setup/Margin/Content
@onready var army = $Canvas/UI/ArmyPanel
@onready var camera: Camera3D = $CameraRig/Camera3D
var _preview_id: int = -1
var _panel_mode: String = "preview"
var _choice_ids: Array = []
var _setup_step: int = 0
var _strategy: String = "ranged"
var _pack: String = "steady"
var _new_run_requested: bool = false
var _previous_phase: String = ""
var _refresh_queued: bool = false
var _panning: bool = false
var _alert_tween: Tween

func _ready() -> void:
	get_tree().paused = false
	get_tree().auto_accept_quit = true
	rogue.changed.connect(_queue_refresh)
	for route_node: Node3D in $Nodes.get_children():
		route_node.selected.connect(_select_node)
	for index: int in 6:
		content.get_node("Options/Option%d" % index).pressed.connect(_option_pressed.bind(index))
	for index: int in 3:
		setup_content.get_node("Choices/Choice%d" % index).pressed.connect(_setup_choice.bind(index))
	content.get_node("Primary").pressed.connect(_primary_pressed)
	content.get_node("Secondary").pressed.connect(_secondary_pressed)
	ui.get_node("Rail/Army").pressed.connect(_open_army.bind("formation"))
	ui.get_node("Rail/Recruit").pressed.connect(_open_army.bind("recruit"))
	ui.get_node("Rail/Load").pressed.connect(_ask_load)
	ui.get_node("Rail/Pause").pressed.connect(_toggle_pause_menu)
	ui.get_node("Rail/Menu").pressed.connect(_return_menu)
	ui.get_node("PauseMenu/Panel/Content/Resume").pressed.connect(_toggle_pause_menu)
	ui.get_node("PauseMenu/Panel/Content/Settings").pressed.connect(Session.settings.open_menu)
	ui.get_node("PauseMenu/Panel/Content/Load").pressed.connect(_ask_load)
	ui.get_node("PauseMenu/Panel/Content/Menu").pressed.connect(_return_menu)
	ui.get_node("PauseMenu/Panel/Content/Quit").pressed.connect(get_tree().quit)
	Session.settings.pause_requested.connect(_toggle_pause_menu)
	setup_content.get_node("Actions/Back").pressed.connect(_setup_back)
	setup_content.get_node("Actions/Continue").pressed.connect(_load_run)
	ui.get_node("ReplaceRun").confirmed.connect(_start_run)
	ui.get_node("LoadConfirm").confirmed.connect(_load_run)
	army.closed.connect(_refresh)
	UIMotion.bind_buttons(ui)
	_refresh()
	if not rogue.error_message.is_empty():
		_notice.call_deferred(rogue.error_message)
	UIMotion.reveal(ui, Vector2.ZERO)

func _queue_refresh() -> void:
	if not _refresh_queued:
		_refresh_queued = true
		_refresh.call_deferred()

func _refresh() -> void:
	_refresh_queued = false
	if rogue.state == null or rogue.state.data.is_empty() or _new_run_requested:
		_show_setup()
		return
	var data: Dictionary = rogue.state.data
	var phase: String = data.phase
	if phase != _previous_phase:
		preview.get_node("Scroll").scroll_vertical = 0
	setup.hide()
	$Nodes.show()
	$Routes.show()
	for element: String in ["Top", "JourneyPlaque", "ProvisionTray", "Hint"]:
		ui.get_node(element).show()
	ui.get_node("Rail").show()
	ui.get_node("Bottom").show()
	ui.get_node("Top/TitleBlock/Journey").text = "第 %d 层  ·  Lv.%d  ·  经验 %d / %d" % [mini(int(data.floor),1), data.level, data.xp, rogue.state.xp_required()]
	ui.get_node("Top/TitleBlock/XP").max_value = rogue.state.xp_required()
	ui.get_node("Top/TitleBlock/XP").value = data.xp
	ui.get_node("Top/Gold/Value").text = str(data.gold)
	ui.get_node("Top/Bread/Value").text = str(data.bread)
	ui.get_node("Top/Action/Value").text = "%d/12" % data.ap
	ui.get_node("Rail/Recruit").text = "招募  %d" % data.tickets.size()
	_refresh_relics(data.relics)
	for model: Node3D in $Nodes.get_children():
		var id: int = model.node_id
		model.configure(rogue.state.node(id), phase == "map" and rogue.state.adjacent(id), id == int(data.current_node), id == _preview_id)
	content.get_node("MapView").hide()
	content.get_node("Options").show()
	for option: Button in content.get_node("Options").get_children():
		option.hide()
		option.disabled = false
		option.custom_minimum_size.y = 58.0
	content.get_node("Primary").show()
	content.get_node("Primary").disabled = false
	content.get_node("Secondary").show()
	content.get_node("Secondary").text = "关闭预览"
	match phase:
		"map":
			ui.get_node("Hint").text = data.last_result if not str(data.last_result).is_empty() else "点击节点查看详情 · 中键拖动地图 · 滚轮缩放"
			if _preview_id >= 0:
				_show_preview(_preview_id)
			else:
				preview.hide()
		"node":
			ui.get_node("Hint").text = "离开节点后自动保存 · 中途退出将恢复最近完整节点"
			_show_content()
		"reward":
			_show_relic_choices("紧急作战胜利", str(data.last_result))
		"siege_briefing":
			_show_siege()
			if _previous_phase != phase:
				_play_siege_alert()
		"intermission", "game_over":
			_show_terminal(phase)
		"battle":
			preview.hide()
	_previous_phase = phase

func _refresh_relics(relics: Dictionary) -> void:
	var row: HBoxContainer = ui.get_node("Bottom/Content/Scroll/Relics")
	row.get_node("Empty").visible = relics.is_empty()
	var ids: Array = RogueCatalog.RELICS.keys()
	for index: int in 8:
		var button: Button = row.get_node("Relic%d" % index)
		var id: String = str(ids[index])
		var count: int = int(relics.get(id,0))
		button.visible = count > 0
		button.text = "%s ×%d" % [RogueCatalog.RELICS[id].name,count]
		button.tooltip_text = "%s\n%s\n拥有 %d 层，效果相加" % [RogueCatalog.RELICS[id].name,RogueCatalog.RELICS[id].description,count]
		if not button.pressed.is_connected(_show_relic_detail.bind(id)):
			button.pressed.connect(_show_relic_detail.bind(id))

func _show_relic_detail(id: String) -> void:
	_notice("%s\n%s\n已拥有 %d 层，效果相加。" % [RogueCatalog.RELICS[id].name, RogueCatalog.RELICS[id].description, rogue.state.data.relics[id]])

func _show_setup() -> void:
	var opening: bool = not setup.visible
	setup.show()
	preview.hide()
	ui.get_node("Rail").hide()
	$Nodes.hide()
	$Routes.hide()
	for element: String in ["Top", "JourneyPlaque", "ProvisionTray", "Bottom", "Hint"]:
		ui.get_node(element).hide()
	setup_content.get_node("Actions/Continue").show()
	setup_content.get_node("Footnote").text = "初始人口 20，战斗后全军恢复。离开节点时自动保存。"
	setup_content.get_node("Title").text = "选择你的战略" if _setup_step == 0 else "选择初始部队"
	setup_content.get_node("Description").text = "第 1 步，共 2 步 · 为这次远征选择一项优势" if _setup_step == 0 else "第 2 步，共 2 步 · 已选%s，每套部队均占 18 人口" % RogueCatalog.STRATEGIES[_strategy].name
	setup_content.get_node("Actions/Back").text = "返回大厅" if _setup_step == 0 else "重新选择战略"
	var choices: Array = []
	if _setup_step == 0:
		choices = [["远程优先战略", "远程基础攻击力 +10%"], ["近战分队", "近战基础攻击力 +10%\n所有单位近战护甲 +1"], ["射程优先战略", "远程步兵射程 +1"]]
	else:
		choices = [["稳阵部队", "剑士4 · 盾卫3 · 长矛兵2\n弓箭手4 · 投石车1 · 牧师1"], ["远射部队", "盾卫4 · 长矛兵2 · 弓箭手7\n加农炮1 · 工程兵2"], ["机动部队", "剑士3 · 长矛兵2 · 弓箭手4\n骑士4 · 轻骑兵2 · 投石车1"]]
	for index: int in 3:
		var choice: Button = setup_content.get_node("Choices/Choice%d" % index)
		choice.get_node("Title").text = choices[index][0]
		choice.get_node("Effect").text = choices[index][1]
		choice.get_node("Motto").text = ""
		choice.tooltip_text = "%s\n%s" % [choices[index][0], choices[index][1]]
		var models: Node3D = setup_content.get_node("Choices/Choice%d/Illustration/Viewport/Models" % index)
		models.get_node("Stage").hide()
		models.get_node("Strategy").visible = _setup_step == 0
		models.get_node("Pack").visible = _setup_step == 1
	if opening:
		UIMotion.reveal(setup_content)

func _setup_choice(index: int) -> void:
	if not _new_run_requested and rogue.state != null and not rogue.state.data.is_empty():
		var phase: String = rogue.state.data.phase
		if phase in ["intermission","game_over"]:
			if index == 0:
				if phase == "game_over": _load_run()
				else: _open_army("formation")
			elif index == 1:
				_new_run_requested = true
				_setup_step = 0
				_show_setup()
			else: _return_menu()
			return
	if _setup_step == 0:
		_strategy = STRATEGY_IDS[index]
		_setup_step = 1
		_show_setup()
		UIMotion.reveal(setup_content.get_node("Choices"), Vector2(24, 0))
	else:
		_pack = PACK_IDS[index]
		if FileAccess.file_exists(RogueSession.SAVE_PATH):
			ui.get_node("ReplaceRun").popup_centered()
		else:
			_start_run()

func _setup_back() -> void:
	if _setup_step == 1:
		_setup_step = 0
		_show_setup()
		UIMotion.reveal(setup_content.get_node("Choices"), Vector2(-24, 0))
	else: _return_menu()

func _start_run() -> void:
	_new_run_requested = false
	if rogue.start_new(_strategy,_pack) != OK:
		_notice(rogue.error_message)

func _load_run() -> void:
	_new_run_requested = false
	if rogue.load_run() != OK:
		_notice(rogue.error_message)

func _ask_load() -> void:
	ui.get_node("LoadConfirm").popup_centered()

func _return_menu() -> void:
	if Session.settings.is_open(): Session.settings.close_menu()
	Session.back_to_lobby()

func _toggle_pause_menu() -> void:
	if Session.settings.is_open(): Session.settings.close_menu()
	_panning = false
	ui.get_node("PauseMenu").visible = not ui.get_node("PauseMenu").visible
	if ui.get_node("PauseMenu").visible:
		UIMotion.reveal(ui.get_node("PauseMenu/Panel"))

func _select_node(id: int) -> void:
	if setup.visible or army.visible or ui.get_node("PauseMenu").visible or rogue.state == null or rogue.state.data.phase != "map":
		return
	_preview_id = id
	preview.get_node("Scroll").scroll_vertical = 0
	_refresh()
	UIMotion.reveal(preview, Vector2(26, 0))

func _show_preview(id: int) -> void:
	_panel_mode = "preview"
	var target: Dictionary = rogue.state.node(id)
	preview.show()
	content.get_node("Kind").text = "林海路线  /  " + RogueCatalog.NODE_NAMES[target.kind]
	content.get_node("Name").text = "前哨站" if target.kind in ["battle","emergency"] else RogueCatalog.NODE_NAMES[target.kind]
	var detail: String = "沿林间小径行军，寻找下一次机遇。"
	match str(target.kind):
		"battle", "emergency":
			_show_map_preview(false)
			var emergency: bool = target.kind == "emergency"
			var reward: Dictionary = RogueCatalog.BALANCE.rewards[target.kind]
			var reinforcement: String = "敌方生命 +%d%%，攻击 +%d%%。\n" % [roundi((OUTPOST.emergency_hp_multiplier-1.0)*100.0),roundi((OUTPOST.emergency_damage_multiplier-1.0)*100.0)] if emergency else ""
			content.get_node("Kind").text = "%s  /  难度 %d" % ["紧急军情" if emergency else "作战军情", target.difficulty]
			detail = "摧毁所有敌方建筑与部队。\n5座箭塔 · 3座兵营 · 初始%d名守军\n兵营会补充援军，摧毁后停止。\n\n%s战利品：%d金币 · %d面包 · %d招募券\n%d经验%s" % [16+OUTPOST.emergency_reinforcements.size() if emergency else 16,reinforcement,reward.gold,reward.bread,reward.tickets,reward.xp," · 收藏品三选一" if emergency else ""]
		"shop": detail = "林间商人带来了收藏品、招募券和口粮。\n\n离开后商队启程，无法再次购物。"
		"event": detail = "林道深处传来一些动静。\n\n一次相遇，几个选择，也许会改变军团的命运。"
		"camp": detail = "一处可以暂歇的安全营地。\n\n整顿脚步、领取口粮或寻找收藏品，只能选择一项。"
	if bool(target.completed):
		detail += "\n\n此节点已完成。本次仅通过，不会重复获得奖励。"
	var current: bool = id == int(rogue.state.data.current_node)
	var adjacent: bool = rogue.state.adjacent(id)
	if not adjacent and not current:
		detail += "\n\n需要先抵达与此处直接相连的节点。"
	content.get_node("Detail").text = detail
	content.get_node("Primary").text = "当前驻扎位置" if current else "进入节点  ·  行动力 −1"
	content.get_node("Primary").disabled = current or not adjacent

func _show_content() -> void:
	preview.show()
	var active: Dictionary = rogue.state.active_node()
	var kind: String = active.kind
	content.get_node("Kind").text = "第一层  /  " + RogueCatalog.NODE_NAMES[kind]
	content.get_node("Name").text = RogueCatalog.NODE_NAMES[kind]
	content.get_node("Secondary").text = "编队与招募"
	content.get_node("Primary").text = "离开节点"
	if not rogue.state.data.pending_choices.is_empty():
		_show_relic_choices("发现收藏品", "选择一件收藏品，强化本局军团。")
		return
	if bool(active.get("resolved",false)):
		_panel_mode = "resolved"
		content.get_node("Detail").text = str(active.get("result_text",rogue.state.data.last_result))
		return
	match kind:
		"shop":
			_panel_mode = "shop"
			content.get_node("Detail").text = "金币购买 · 每件商品限购一次\n离开后商队便会启程。"
			var offers: Array = active.offers
			for index: int in offers.size():
				var offer: Dictionary = offers[index]
				content.get_node("Options/Option%d" % index).custom_minimum_size.y = 46.0
				var label: String = "招募券"
				if offer.kind == "bread": label = "吐司面包 ×%d" % int(offer.count)
				elif offer.kind == "relic": label = RogueCatalog.RELICS[offer.relic_id].name
				_option(index,"%s%s  ·  %d 金币" % [label,"（售罄）" if offer.sold else "",offer.price],bool(offer.sold) or int(rogue.state.data.gold)<int(offer.price))
				if offer.kind == "relic": content.get_node("Options/Option%d" % index).tooltip_text = RogueCatalog.RELICS[offer.relic_id].description
		"event":
			_panel_mode = "event"
			var event_id: String = active.event_id
			var info: Array = EVENT_TEXT[event_id]
			content.get_node("Name").text = info[0]
			content.get_node("Detail").text = info[1]
			var options: Array[String] = _event_options(event_id)
			for index: int in options.size():
				_option(index,options[index],not _event_affordable(event_id,index))
			content.get_node("Primary").hide()
		"camp":
			_panel_mode = "camp"
			content.get_node("Detail").text = "篝火旁还有一些干燥的木柴。\n选择一项补给，然后继续前进。"
			var camp: Dictionary = RogueCatalog.BALANCE.camp
			var max_ap: int = int(RogueCatalog.BALANCE.initial.max_ap)
			_option(0,"整顿脚步  ·  恢复%d行动力（上限%d）" % [camp.ap,max_ap],int(rogue.state.data.ap)>=max_ap)
			_option(1,"领取口粮  ·  面包 +%d" % int(camp.bread))
			_option(2,"搜索营地  ·  收藏品三选一")
			content.get_node("Primary").hide()

func _event_options(id: String) -> Array[String]:
	var event: Dictionary = RogueCatalog.EVENTS[id]
	match id:
		"bread_cart": return ["帮忙推车  ·  行动力 −%d / 面包 +%d" % [event.ap_cost,event.ap_bread],"购买口粮  ·  金币 −%d / 面包 +%d" % [event.gold_cost,event.gold_bread],"继续前进"]
		"lost_guard": return ["分给口粮  ·  面包 −%d / 长矛兵 +%d" % [event.bread_cost,event.unit_count],"联络援军  ·  金币 −%d / 招募券 +1" % int(event.gold_cost),"祝他们平安"]
		"hunter_camp": return ["带走箭材  ·  %s +1" % RogueCatalog.RELICS[event.relic].name,"回收铁器  ·  金币 +%d" % int(event.gold)]
		"mist_chest": return ["收好钱袋  ·  金币 +%d" % int(event.safe_gold),"深入搜寻  ·  %d%% 金币 +%d / %d%% 无收获" % [roundi(float(event.risk_chance)*100.0),event.risk_gold,roundi((1.0-float(event.risk_chance))*100.0)]]
	return []

func _event_affordable(id: String, option: int) -> bool:
	var d: Dictionary = rogue.state.data
	var event: Dictionary = RogueCatalog.EVENTS[id]
	if id == "bread_cart":
		if option == 0: return int(d.ap) >= int(event.ap_cost)
		if option == 1: return int(d.gold) >= int(event.gold_cost)
	if id == "lost_guard":
		if option == 0: return int(d.bread) >= int(event.bread_cost)
		if option == 1: return int(d.gold) >= int(event.gold_cost)
	return true

func _show_relic_choices(title: String, detail: String) -> void:
	_panel_mode = "relic"
	preview.show()
	content.get_node("Name").text = title
	content.get_node("Detail").text = detail + "\n\n选择一件收藏品。"
	_choice_ids = rogue.state.data.pending_choices.duplicate()
	for index: int in _choice_ids.size():
		var relic: Dictionary = RogueCatalog.RELICS[_choice_ids[index]]
		_option(index,"%s\n%s" % [relic.name,relic.description])
	content.get_node("Primary").hide()
	content.get_node("Secondary").text = "整理编队"

func _show_siege() -> void:
	_panel_mode = "siege"
	preview.show()
	content.get_node("Kind").text = "行动力耗尽  /  强制作战"
	content.get_node("Name").text = "围 剿"
	_show_map_preview(true)
	content.get_node("Detail").text = "敌军正在封锁林道。守住大本营，等待突围。\n\n坚守 %d 秒 · 敌军从四边增援\n同时存活不超过 %d 名\n\n基地被毁即失败；士兵全灭仍可坚守。\n胜利后补满行动力，进入层间整备。" % [roundi(SIEGE.duration),SIEGE.enemy_cap]
	content.get_node("Primary").text = "准备迎战"
	content.get_node("Secondary").text = "调整围剿编队"
	ui.get_node("Hint").text = "围剿不可回避 · 可以整备或退出后读档续战"

func _show_map_preview(siege: bool) -> void:
	content.get_node("MapView").show()
	content.get_node("MapView/Viewport/Model/Outpost").visible = not siege
	content.get_node("MapView/Viewport/Model/Siege").visible = siege

func _show_terminal(phase: String) -> void:
	preview.hide()
	setup.show()
	ui.get_node("Rail").hide()
	$Nodes.hide()
	$Routes.hide()
	for element: String in ["Top", "JourneyPlaque", "ProvisionTray", "Bottom", "Hint"]:
		ui.get_node(element).hide()
	setup_content.get_node("Actions/Continue").hide()
	setup_content.get_node("Title").text = "第一层 · 突围成功" if phase == "intermission" else "远征失败"
	setup_content.get_node("Description").text = "军团已完成突围，行动力恢复。军队与成长已保存，第二层暂未开放。" if phase == "intermission" else "本次作战失败。最近的节点检查点仍然保留，可以读档再次挑战。"
	setup_content.get_node("Footnote").text = "Lv.%d  ·  出战人口 %d / %d  ·  金币 %d  ·  面包 %d" % [rogue.state.data.level, rogue.state.population(), rogue.state.population_cap(), rogue.state.data.gold, rogue.state.data.bread]
	var labels: Array = ["整理军队","开始新远征","返回大厅"] if phase == "intermission" else ["读取节点存档","开始新远征","返回大厅"]
	var descriptions: Array = ["检视军团，调整阵位", "重选战略与初始部队", "军团成长已经保存"] if phase == "intermission" else ["从最近完整节点再次出发", "重选战略与初始部队", "保留存档，暂别林海"]
	for index: int in 3:
		var choice: Button = setup_content.get_node("Choices/Choice%d" % index)
		choice.get_node("Title").text = labels[index]
		choice.get_node("Effect").text = descriptions[index]
		choice.get_node("Motto").text = ""
		choice.tooltip_text = descriptions[index]
	setup_content.get_node("Actions/Back").text = "返回大厅"
	_setup_step = 0

func _option(index: int, text_value: String, disabled: bool = false) -> void:
	var button: Button = content.get_node("Options/Option%d" % index)
	button.show()
	button.text = text_value
	button.disabled = disabled

func _option_pressed(index: int) -> void:
	var error: Error = OK
	match _panel_mode:
		"shop": error = rogue.purchase(index)
		"event": error = rogue.resolve_event(index)
		"camp": error = rogue.choose_camp(index)
		"relic": error = rogue.choose_relic(str(_choice_ids[index]))
	if error != OK: _notice(rogue.error_message)
	_refresh()

func _primary_pressed() -> void:
	var error: Error = OK
	match _panel_mode:
		"preview":
			var target_id: int = _preview_id
			_preview_id = -1
			error = rogue.enter_node(target_id)
		"siege": error = rogue.launch_battle()
		"shop", "resolved":
			_preview_id = -1
			error = rogue.leave_node()
	if error != OK: _notice(rogue.error_message)
	_refresh()

func _secondary_pressed() -> void:
	if _panel_mode == "preview":
		_preview_id = -1
		_refresh()
	else:
		_open_army("formation")

func _open_army(tab: String) -> void:
	if rogue.state == null or rogue.state.data.is_empty(): return
	var encounter: String = "siege" if rogue.state.data.phase in ["siege_briefing","intermission"] else "outpost"
	army.open_panel(tab,encounter)

func _play_siege_alert() -> void:
	var alert: ColorRect = ui.get_node("Alert")
	if _alert_tween != null: _alert_tween.kill()
	alert.show()
	alert.modulate.a = 0.0
	_alert_tween = create_tween()
	_alert_tween.tween_property(alert,"modulate:a",1.0,0.25)
	_alert_tween.tween_interval(1.0)
	_alert_tween.tween_property(alert,"modulate:a",0.0,0.65)
	_alert_tween.tween_callback(alert.hide)

func _notice(message: String) -> void:
	ui.get_node("Notice").dialog_text = message
	ui.get_node("Notice").popup_centered()

func _unhandled_input(event: InputEvent) -> void:
	if setup.visible or army.visible or Session.settings.is_open(): return
	if event is InputEventKey and event.pressed and event.keycode in [KEY_ESCAPE,KEY_F5]:
		if event.keycode == KEY_ESCAPE and _preview_id >= 0 and not ui.get_node("PauseMenu").visible:
			_preview_id = -1
			_refresh()
		else:
			_toggle_pause_menu()
		get_viewport().set_input_as_handled()
		return
	if ui.get_node("PauseMenu").visible: return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = event.pressed
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.size = clampf(camera.size - 3.0,32.0,82.0)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.size = clampf(camera.size + 3.0,32.0,82.0)
	elif event is InputEventMouseMotion and _panning:
		var step: float = camera.size / get_viewport().get_visible_rect().size.y
		$CameraRig.position.x = clampf($CameraRig.position.x-event.relative.x*step,-28.0,28.0)
		$CameraRig.position.z = clampf($CameraRig.position.z-event.relative.y*step*1.15,-20.0,20.0)
