class_name RogueRunState
extends RefCounted
## Pure run state. Scene nodes and unit resources never enter a checkpoint.

const VERSION: int = 2
const SAFE_PHASES: Array[String] = ["map", "siege_briefing", "intermission"]
const RECRUIT_PHASES: Array[String] = ["recruit_unit", "recruit_batch"]
var data: Dictionary = {}
var error_message: String = ""

func start_new(strategy: String, pack: String, run_seed: int = 0) -> Error:
	if not RogueCatalog.STRATEGIES.has(strategy) or not RogueCatalog.PACKS.has(pack):
		return _fail("请选择有效的战略与初始部队")
	if run_seed < 0 or run_seed > 0x7fffffff:
		return _fail("地图种子必须位于 0 到 2147483647")
	var seed_value: int = run_seed
	if seed_value == 0:
		var seed_rng := RandomNumberGenerator.new()
		seed_rng.randomize()
		seed_value = seed_rng.randi_range(1, 0x7fffffff)
	var initial: Dictionary = RogueCatalog.BALANCE.initial
	data = {"version": VERSION, "seed": seed_value, "phase": "map", "floor": 1,
		"strategy": strategy, "pack": pack, "level": int(initial.level), "xp": 0,
		"gold": int(initial.gold), "bread": int(initial.bread), "ap": int(initial.ap),
		"current_node": -1, "start_node": -1, "nodes": [], "edges": [],
		"roster": [], "pending_recruits": [], "recruit_kind": "", "recruit_return_phase": "", "settlement": {}, "relics": {}, "active_node": -1,
		"battle_kind": "outpost", "battle_difficulty": int(RogueCatalog.BALANCE.difficulty), "emergency": false, "pending_choices": [],
		"pending_siege": false, "last_result": "远征已经启程。先完成初始招募，再选择相邻节点开始探索。",
		"next_unit_uid": 1, "next_ticket_uid": 1, "rng_counter": 0}
	_generate_map()
	var units: Dictionary = RogueCatalog.PACKS[pack].units
	for kind: String in units:
		for _index: int in int(units[kind]):
			_add_unit(kind, true)
	for _index: int in int(initial.tickets):
		_add_ticket()
	error_message = ""
	return OK

func population() -> int:
	var result: int = 0
	for unit: Dictionary in data.roster:
		if unit.deployed:
			result += BalanceCatalog.unit(unit.kind).supply
	return result

func population_cap() -> int:
	return int(RogueCatalog.BALANCE.initial.population) + (int(data.level) - 1) * int(RogueCatalog.BALANCE.progression.population_per_level) + int(_relic_bonus("population"))

func xp_required() -> int:
	return int(RogueCatalog.BALANCE.progression.xp_base) + (int(data.level) - 1) * int(RogueCatalog.BALANCE.progression.xp_step)

func adjacent(id: int) -> bool:
	for edge: Array in data.edges:
		if (int(edge[0]) == int(data.current_node) and int(edge[1]) == id) or (int(edge[1]) == int(data.current_node) and int(edge[0]) == id):
			return true
	return false

func node(id: int) -> Dictionary:
	if id < 0 or id >= data.nodes.size():
		return {}
	return data.nodes[id]

func active_node() -> Dictionary:
	return node(int(data.active_node))

func deployed_units() -> Array:
	var result: Array = []
	for unit: Dictionary in data.roster:
		if unit.deployed:
			result.append(unit.duplicate(true))
	return result

func unit_definition(kind: String) -> UnitDefinition:
	var definition: UnitDefinition = BalanceCatalog.unit(kind).duplicate(true)
	var strategy: Dictionary = RogueCatalog.STRATEGIES[data.strategy]
	var attack_key: String = "ranged_attack" if definition.damage_channel == CombatDefinition.DamageChannel.RANGED else "melee_attack"
	definition.damage *= 1.0 + float(strategy.get(attack_key, 0.0)) + _relic_bonus(attack_key)
	definition.hp *= 1.0 + _relic_bonus("health")
	definition.speed *= 1.0 + _relic_bonus("speed")
	definition.melee_armor += float(strategy.get("melee_armor", 0)) + _relic_bonus("melee_armor")
	definition.ranged_armor += _relic_bonus("ranged_armor")
	if RogueCatalog.is_ranged_infantry(kind):
		definition.range += float(strategy.get("range", 0.0)) + _relic_bonus("range")
	return definition

func enter_node(id: int) -> Error:
	if data.phase != "map" or not adjacent(id) or int(data.ap) < 1:
		return _fail("只能消耗 1 行动力移动到当前相邻节点")
	var target: Dictionary = node(id)
	if target.is_empty():
		return _fail("目标节点不存在")
	if target.kind in ["battle", "emergency"] and not target.completed and population() == 0:
		return _fail("请先在编队中安排至少一个出战单位")
	data.ap = int(data.ap) - 1
	data.current_node = id
	data.active_node = id
	data.phase = "node"
	data.last_result = ""
	data.emergency = false
	if target.completed or target.kind == "road":
		return leave_node()
	if target.kind in ["battle", "emergency"]:
		data.battle_kind = "outpost"
		data.battle_difficulty = int(target.difficulty)
		data.emergency = target.kind == "emergency"
		data.phase = "battle"
	return _ok()

func leave_node() -> Error:
	if data.phase != "node" or not data.pending_choices.is_empty() or not data.pending_recruits.is_empty() or not data.settlement.is_empty():
		return _fail("请先完成当前节点的选择")
	var current: Dictionary = active_node()
	if current.is_empty():
		return _fail("没有可退出的节点")
	current.completed = true
	current.resolved = true
	data.active_node = -1
	data.emergency = false
	data.phase = "map"
	if int(data.ap) == 0:
		data.pending_siege = true
		data.battle_kind = "siege"
		data.battle_difficulty = int(RogueCatalog.BALANCE.difficulty)
		data.phase = "siege_briefing"
	return _ok()

func launch_battle() -> Error:
	if data.phase not in ["battle", "siege_briefing"] or population() == 0:
		return _fail("请安排出战编队后再进入作战")
	var reason: String = formation_error(String(data.battle_kind))
	if not reason.is_empty(): return _fail(reason)
	if data.phase == "siege_briefing":
		data.battle_kind = "siege"
		data.battle_difficulty = int(RogueCatalog.BALANCE.difficulty)
		data.emergency = false
	data.phase = "battle"
	return _ok()

func resolve_battle(won: bool) -> Error:
	if data.phase != "battle":
		return _fail("本场作战已结算")
	if not won:
		data.phase = "game_over"
		data.last_result = "远征失败。军队名册保留在最近的节点存档中，可从主菜单读档重试。"
		return _ok()
	var reward_key: String = "emergency" if data.emergency else "battle"
	var reward: Dictionary = {"gold": 0, "bread": 0, "tickets": 0, "xp": 0} if data.battle_kind == "siege" else RogueCatalog.BALANCE.rewards[reward_key].duplicate(true)
	var preview_level: int = int(data.level)
	var preview_xp: int = int(data.xp) + int(reward.xp)
	var required: int = xp_required()
	while preview_xp >= required:
		preview_xp -= required
		preview_level += 1
		required += int(RogueCatalog.BALANCE.progression.xp_step)
	var levels: int = preview_level - int(data.level)
	data.settlement = {"battle_kind": data.battle_kind, "emergency": data.emergency, "rewards": reward, "claimed": false,
		"levels": levels, "bonus_bread": levels * int(RogueCatalog.BALANCE.progression.bread_per_level),
		"bonus_population": levels * int(RogueCatalog.BALANCE.progression.population_per_level)}
	data.phase = "settlement"
	return _ok()

func confirm_settlement() -> Error:
	if data.phase != "settlement" or data.settlement.is_empty() or data.settlement.claimed:
		return _fail("本场战利品已领取或尚未结算")
	var reward: Dictionary = data.settlement.rewards
	data.settlement.claimed = true
	data.gold = int(data.gold) + int(reward.gold)
	data.bread = int(data.bread) + int(reward.bread)
	var levels: int = _grant_xp(int(reward.xp))
	data.last_result = "前哨站作战胜利：+%d 金币，+%d 面包，+%d 招募券，+%d 经验。" % [reward.gold, reward.bread, reward.tickets, reward.xp]
	if levels > 0:
		data.last_result += " 升级 %d 次：+%d 面包，+%d 人口上限。" % [levels, levels * int(RogueCatalog.BALANCE.progression.bread_per_level), levels * int(RogueCatalog.BALANCE.progression.population_per_level)]
	data.phase = "node"
	if data.battle_kind == "outpost":
		active_node().resolved = true
		active_node().result_text = data.last_result
	if data.battle_kind == "outpost" and data.emergency:
		data.pending_choices = active_node().relic_choices.duplicate()
		data.phase = "reward"
	for _index: int in int(reward.tickets):
		_add_ticket()
	return _finish_settlement()

func _finish_settlement() -> Error:
	if data.settlement.is_empty() or not data.settlement.claimed or not data.pending_recruits.is_empty() or not data.pending_choices.is_empty():
		return _ok()
	data.settlement.clear()
	if data.battle_kind == "siege":
		data.ap = int(RogueCatalog.BALANCE.initial.max_ap)
		data.pending_siege = false
		data.floor = 2
		data.phase = "intermission"
		data.active_node = -1
		data.last_result = "围剿突围成功！行动力已恢复。军队抵达层间休整，第二层正在筹备。"
		return _ok()
	data.phase = "node"
	return leave_node()

func purchase(offer_index: int) -> Error:
	var current: Dictionary = active_node()
	if data.phase != "node" or current.is_empty() or current.kind != "shop":
		return _fail("当前没有打开的商店")
	if offer_index < 0 or offer_index >= current.offers.size():
		return _fail("商品不存在")
	var offer: Dictionary = current.offers[offer_index]
	if offer.sold:
		return _fail("这件商品已经售罄")
	if int(data.gold) < int(offer.price):
		return _fail("金币不足")
	data.gold = int(data.gold) - int(offer.price)
	offer.sold = true
	match String(offer.kind):
		"relic": _grant_relic(offer.relic_id)
		"ticket": _add_ticket()
		"bread": data.bread = int(data.bread) + int(offer.count)
	data.last_result = "购买成功，花费 %d 金币。" % int(offer.price)
	return _ok()

func resolve_event(option: int) -> Error:
	var current: Dictionary = active_node()
	if data.phase != "node" or current.is_empty() or current.kind != "event" or current.resolved:
		return _fail("这个事件已经结束或尚未开始")
	var event: Dictionary = RogueCatalog.EVENTS[current.event_id]
	if option < 0 or option >= event.options.size():
		return _fail("事件选项不存在")
	var result: String = "你继续沿着林间小路前进。"
	match String(current.event_id):
		"bread_cart":
			if option == 0:
				if int(data.ap) < int(event.ap_cost): return _fail("行动力不足，无法搜集粮车补给")
				data.ap = int(data.ap) - int(event.ap_cost)
				data.bread = int(data.bread) + int(event.ap_bread)
				result = "搜集补给：-%d 行动力，+%d 面包。" % [event.ap_cost, event.ap_bread]
			elif option == 1:
				if int(data.gold) < int(event.gold_cost): return _fail("金币不足")
				data.gold = int(data.gold) - int(event.gold_cost)
				data.bread = int(data.bread) + int(event.gold_bread)
				result = "交换补给：-%d 金币，+%d 面包。" % [event.gold_cost, event.gold_bread]
		"lost_guard":
			if option == 0:
				if int(data.bread) < int(event.bread_cost): return _fail("面包不足")
				data.bread = int(data.bread) - int(event.bread_cost)
				for _index: int in int(event.unit_count): _add_unit("spearman", false)
				result = "%d 名长枪兵加入待命区。" % int(event.unit_count)
			elif option == 1:
				if int(data.gold) < int(event.gold_cost): return _fail("金币不足")
				data.gold = int(data.gold) - int(event.gold_cost)
				_add_ticket()
				result = "获得 1 张招募券。"
		"hunter_camp":
			if option == 0:
				_grant_relic(event.relic)
				result = "获得收藏品：%s。" % RogueCatalog.RELICS[event.relic].name
			else:
				data.gold = int(data.gold) + int(event.gold)
				result = "获得 %d 金币。" % int(event.gold)
		"mist_chest":
			var gold: int = int(event.safe_gold) if option == 0 else (int(event.risk_gold) if current.risk_success else 0)
			data.gold = int(data.gold) + gold
			result = "迷雾散去，获得 %d 金币。" % gold
	current.resolved = true
	current.result_text = result
	data.last_result = result
	return _ok()

func choose_camp(option: int) -> Error:
	var current: Dictionary = active_node()
	if data.phase != "node" or current.is_empty() or current.kind != "camp" or current.resolved or option < 0 or option > 2:
		return _fail("这个营地的补给已经领取或选项无效")
	current.resolved = true
	match option:
		0:
			var before: int = int(data.ap)
			data.ap = mini(int(RogueCatalog.BALANCE.initial.max_ap), before + int(RogueCatalog.BALANCE.camp.ap))
			data.last_result = "整顿行装，恢复 %d 行动力。" % (int(data.ap) - before)
		1:
			data.bread = int(data.bread) + int(RogueCatalog.BALANCE.camp.bread)
			data.last_result = "领取 %d 面包。" % int(RogueCatalog.BALANCE.camp.bread)
		2:
			data.pending_choices = current.relic_choices.duplicate()
			data.last_result = "请从三件收藏品中选择一件。"
	current.result_text = data.last_result
	return _ok()

func choose_relic(id: String) -> Error:
	if data.phase not in ["node", "reward"] or not data.pending_choices.has(id):
		return _fail("请选择当前可领取的收藏品")
	_grant_relic(id)
	data.pending_choices.clear()
	data.last_result += " 获得收藏品：%s。" % RogueCatalog.RELICS[id].name
	active_node().result_text = data.last_result
	if data.phase == "reward":
		return _finish_settlement()
	return _ok()

func pending_recruit() -> Dictionary:
	return {} if data.pending_recruits.is_empty() else data.pending_recruits[0].duplicate(true)

func choose_recruit_unit(ticket_uid: int, kind: String) -> Error:
	if data.phase != "recruit_unit" or not _current_ticket(ticket_uid) or not data.pending_recruits[0].candidates.has(kind):
		return _fail("请从当前招募的三个兵种中选择")
	data.recruit_kind = kind
	data.phase = "recruit_batch"
	return _ok()

func back_to_recruit_units() -> Error:
	if data.phase != "recruit_batch": return _fail("当前没有可返回的招募选择")
	data.recruit_kind = ""
	data.phase = "recruit_unit"
	return _ok()

func confirm_recruit_batches(ticket_uid: int, batches: int) -> Error:
	if data.phase != "recruit_batch" or not _current_ticket(ticket_uid) or batches < 1 or batches > 3:
		return _fail("请为当前兵种选择 1 到 3 批，或弃置本次招募")
	var kind: String = data.recruit_kind
	var price: Dictionary = RogueCatalog.RECRUIT[kind]
	var cost: int = int(price.bread) * batches
	if int(data.bread) < cost:
		return _fail("面包不足，需要 %d 面包" % cost)
	data.bread = int(data.bread) - cost
	var count: int = int(price.count) * batches
	for _index: int in count: _add_unit(kind, false)
	data.last_result = "%d 名%s加入待命区，消耗 %d 面包。" % [count, BalanceCatalog.unit(kind).name, cost]
	return _complete_recruit()

func discard_recruit(ticket_uid: int) -> Error:
	if data.phase not in RECRUIT_PHASES or not _current_ticket(ticket_uid):
		return _fail("只能弃置当前待处理的招募")
	data.last_result = "已弃置本次招募。"
	return _complete_recruit()

func recruit(ticket_uid: int, kind: String, batches: int) -> Error:
	# The legacy entry point must not bypass the mandatory unit-selection round.
	if data.phase != "recruit_batch" or data.recruit_kind != kind:
		return _fail("请先确认当前招募的兵种")
	return confirm_recruit_batches(ticket_uid, batches)

func _current_ticket(uid: int) -> bool:
	return not data.pending_recruits.is_empty() and int(data.pending_recruits[0].uid) == uid

func _complete_recruit() -> Error:
	data.pending_recruits.pop_front()
	data.recruit_kind = ""
	if not data.pending_recruits.is_empty():
		data.phase = "recruit_unit"
		return _ok()
	data.phase = data.recruit_return_phase
	data.recruit_return_phase = ""
	return _finish_settlement()

func set_deployed(uid: int, value: bool) -> Error:
	return set_deployed_many([uid], value)

func set_deployed_many(uids: Array, value: bool) -> Error:
	if not _army_editable(): return _fail("作战期间不能修改编队")
	if uids.is_empty(): return _fail("请先选择要调整的单位")
	var seen: Dictionary = {}
	var next_population: int = population()
	for uid: Variant in uids:
		if not _integer(uid) or seen.has(int(uid)) or _unit(int(uid)).is_empty(): return _fail("编队单位编号无效或重复")
		seen[int(uid)] = true
		var unit: Dictionary = _unit(int(uid))
		if unit.deployed != value:
			next_population += BalanceCatalog.unit(unit.kind).supply * (1 if value else -1)
	if next_population > population_cap(): return _fail("出战人口不足，请先将其他单位移入待命区")
	var previous: Array = data.roster
	data.roster = previous.duplicate(true)
	for uid: Variant in uids:
		var unit: Dictionary = _unit(int(uid))
		if unit.deployed == value: continue
		if value:
			for encounter: String in ["outpost", "siege"]:
				if not _layout_error(unit, encounter, unit.layouts[encounter], true).is_empty():
					unit.layouts[encounter] = _find_layout(unit, encounter)
				if unit.layouts[encounter].is_empty():
					data.roster = previous
					return _fail("编队区域没有足够的空位")
		unit.deployed = value
	return _ok()

func set_layout(uid: int, encounter: String, layout: Array) -> Error:
	return set_layouts(encounter, [{"uid": uid, "layout": layout}])

func set_layouts(encounter: String, changes: Array) -> Error:
	if not _army_editable(): return _fail("作战期间不能修改编队")
	if encounter not in ["outpost", "siege"] or changes.is_empty(): return _fail("请选择有效战场和布阵单位")
	var seen: Dictionary = {}
	for change: Variant in changes:
		if typeof(change) != TYPE_DICTIONARY or not _integer(change.get("uid")) or typeof(change.get("layout")) != TYPE_ARRAY:
			return _fail("批量布阵数据无效")
		var uid: int = int(change.uid)
		if seen.has(uid) or _unit(uid).is_empty(): return _fail("编队单位编号无效或重复")
		seen[uid] = true
		var reason: String = _layout_error(_unit(uid), encounter, change.layout, false)
		if not reason.is_empty(): return _fail(reason)
	var previous: Array = data.roster
	data.roster = previous.duplicate(true)
	for change: Dictionary in changes:
		var layout: Array = change.layout
		_unit(int(change.uid)).layouts[encounter] = [float(layout[0]), float(layout[1]), wrapf(float(layout[2]), -PI, PI)]
	# Compare final candidate positions, never intermediate positions during a drag.
	for uid: int in seen:
		var unit: Dictionary = _unit(uid)
		var reason: String = _layout_error(unit, encounter, unit.layouts[encounter], bool(unit.deployed))
		if not reason.is_empty():
			data.roster = previous
			return _fail(reason)
	return _ok()

func formation_error(encounter: String) -> String:
	if population() == 0: return "请安排至少一个单位出战"
	if population() > population_cap(): return "编队超过人口上限"
	for unit: Dictionary in data.roster:
		if unit.deployed:
			var reason: String = _layout_error(unit, encounter, unit.layouts[encounter], true)
			if not reason.is_empty(): return reason
	return ""

func _generate_map() -> void:
	var balance: Resource = RogueCatalog.BALANCE
	for index: int in balance.coordinates.size():
		var coord: Vector2 = balance.coordinates[index]
		data.nodes.append({"id": index, "x": int(coord.x), "z": int(coord.y), "kind": "road", "difficulty": int(balance.difficulty), "completed": false, "resolved": false, "content_seed": 0, "result_text": ""})
	for index: int in range(0, balance.edges.size(), 2):
		data.edges.append([int(balance.edges[index]), int(balance.edges[index + 1])])
	var topology_rng: RandomNumberGenerator = _stream(0x13579)
	var content_rng: RandomNumberGenerator = _stream(0x24680)
	var starts: Array = []
	for entry: Dictionary in data.nodes:
		if int(entry.x) > 0 and int(entry.x) < 7 and int(entry.z) > 0 and int(entry.z) < 4 and _neighbors(int(entry.id)).size() >= 3:
			starts.append(int(entry.id))
	data.start_node = starts[topology_rng.randi_range(0, starts.size() - 1)]
	data.current_node = data.start_node
	node(int(data.start_node)).completed = true
	node(int(data.start_node)).resolved = true
	var distances: Dictionary = _distances(int(data.start_node))
	var available: Array = []
	for entry: Dictionary in data.nodes:
		if int(entry.id) != int(data.start_node): available.append(int(entry.id))
	_shuffle(available, content_rng)
	var counts: Dictionary = balance.node_counts.duplicate(true)
	for guarantee: Array in [["battle", 2], ["camp", 3]]:
		for id: int in available:
			if int(distances[id]) <= int(guarantee[1]):
				node(id).kind = guarantee[0]
				counts[guarantee[0]] = int(counts[guarantee[0]]) - 1
				available.erase(id)
				break
	# Place emergencies before other content so they always remain away from the start.
	for _index: int in int(counts.emergency):
		for id: int in available:
			if int(distances[id]) > 1:
				node(id).kind = "emergency"
				available.erase(id)
				break
	counts.erase("emergency")
	for kind: String in counts:
		for _index: int in int(counts[kind]): node(int(available.pop_back())).kind = kind
	var event_ids: Array = RogueCatalog.EVENTS.keys()
	_shuffle(event_ids, content_rng)
	var event_index: int = 0
	for entry: Dictionary in data.nodes:
		entry.content_seed = content_rng.randi_range(1, 0x7fffffff)
		var node_rng := RandomNumberGenerator.new()
		node_rng.seed = int(entry.content_seed)
		if entry.kind in ["emergency", "camp"]: entry.relic_choices = _relic_choices(node_rng)
		if entry.kind == "shop": entry.offers = _shop_offers(node_rng)
		if entry.kind == "event":
			entry.event_id = event_ids[event_index]
			entry.risk_success = node_rng.randf() < float(RogueCatalog.EVENTS.mist_chest.risk_chance)
			event_index += 1

func _shop_offers(random: RandomNumberGenerator) -> Array:
	var result: Array = []
	var settings: Dictionary = RogueCatalog.BALANCE.shop
	var candidates: Array = _relic_choices(random)
	for id: String in candidates:
		result.append({"kind": "relic", "relic_id": id, "price": int(RogueCatalog.RELICS[id].price), "sold": false})
	for _index: int in int(settings.ticket_count):
		result.append({"kind": "ticket", "price": int(settings.ticket_price), "sold": false})
	result.append({"kind": "bread", "count": int(settings.bread_count), "price": int(settings.bread_price), "sold": false})
	return result

func _relic_choices(random: RandomNumberGenerator) -> Array:
	var ids: Array = RogueCatalog.RELICS.keys()
	_shuffle(ids, random)
	return ids.slice(0, 3)

func _add_ticket() -> void:
	var random: RandomNumberGenerator = _stream(0x54321 + int(data.rng_counter))
	data.rng_counter = int(data.rng_counter) + 1
	var candidates: Array = RogueCatalog.RECRUIT.keys()
	_shuffle(candidates, random)
	var choices: Array = candidates.slice(0, 3)
	var affordable: bool = false
	for kind: String in choices:
		if int(RogueCatalog.RECRUIT[kind].bread) == 1: affordable = true
	if not affordable:
		for kind: String in candidates:
			if int(RogueCatalog.RECRUIT[kind].bread) == 1:
				choices[2] = kind
				break
	data.pending_recruits.append({"uid": int(data.next_ticket_uid), "candidates": choices})
	data.next_ticket_uid = int(data.next_ticket_uid) + 1
	if data.phase not in RECRUIT_PHASES:
		data.recruit_return_phase = data.phase
		data.recruit_kind = ""
		data.phase = "recruit_unit"

func _add_unit(kind: String, deployed: bool) -> void:
	var unit: Dictionary = {"uid": int(data.next_unit_uid), "kind": kind, "deployed": deployed, "layouts": {"outpost": [9.8, -9.8, -PI * 0.5], "siege": [9.8, -9.8, -PI * 0.25]}}
	if deployed:
		for encounter: String in ["outpost", "siege"]:
			unit.layouts[encounter] = _find_layout(unit, encounter)
	data.roster.append(unit)
	data.next_unit_uid = int(data.next_unit_uid) + 1

func _find_layout(unit: Dictionary, encounter: String) -> Array:
	if encounter == "outpost":
		var columns: Array = [3.5, 6.5]
		if RogueCatalog.is_ranged_infantry(unit.kind): columns = [0.0, -2.8]
		elif unit.kind in ["catapult", "cannon", "heavy_cannon", "triple_cannon"]: columns = [-5.6, -8.4]
		elif unit.kind in ["priest", "engineer"]: columns = [-8.4, -5.6]
		for x: float in columns:
			for z: float in [0.0, -2.8, 2.8, -5.6, 5.6, -8.4, 8.4]:
				var rank_candidate: Array = [x, z, -PI * 0.5]
				if _layout_error(unit, encounter, rank_candidate, true).is_empty(): return rank_candidate
	if encounter == "siege":
		# Fill each compass side in turn so the starting army defends all four fronts.
		for offset: float in [-7.0, -3.5, 0.0, 3.5, 7.0]:
			for point: Vector2 in [Vector2(offset, -9.8), Vector2(9.8, offset), Vector2(offset, 9.8), Vector2(-9.8, offset)]:
				var ring_candidate: Array = [point.x, point.y, atan2(-point.x, -point.y)]
				if _layout_error(unit, encounter, ring_candidate, true).is_empty(): return ring_candidate
	for column: int in 8:
		for row: int in 8:
			var candidate: Array = [9.8 - column * 2.8, -9.8 + row * 2.8, -PI * 0.5]
			if _layout_error(unit, encounter, candidate, true).is_empty(): return candidate
	return []

func _layout_error(unit: Dictionary, encounter: String, layout: Array, collision_check: bool) -> String:
	if encounter not in ["outpost", "siege"] or layout.size() != 3: return "布阵位置或战场无效"
	for value: Variant in layout:
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)): return "布阵位置必须是有限数值"
	var radius: float = BalanceCatalog.unit(unit.kind).radius
	var point := Vector2(float(layout[0]), float(layout[1]))
	if absf(point.x) + radius > RogueCatalog.DEPLOYMENT_HALF_SIZE or absf(point.y) + radius > RogueCatalog.DEPLOYMENT_HALF_SIZE:
		return "单位必须完整位于布阵区域内"
	if encounter == "siege" and absf(point.x) < RogueCatalog.SIEGE_BASE_HALF_SIZE.x + radius and absf(point.y) < RogueCatalog.SIEGE_BASE_HALF_SIZE.y + radius:
		return "不能在中央基地及其通行区域布阵"
	if collision_check:
		for other: Dictionary in data.roster:
			if not other.deployed or int(other.uid) == int(unit.uid): continue
			var other_layout: Array = other.layouts[encounter]
			var clearance: float = radius + BalanceCatalog.unit(other.kind).radius + 0.15
			if point.distance_to(Vector2(float(other_layout[0]), float(other_layout[1]))) < clearance:
				return "单位初始位置不能重叠"
	return ""

func _grant_xp(amount: int) -> int:
	data.xp = int(data.xp) + amount
	var levels: int = 0
	while int(data.xp) >= xp_required():
		data.xp = int(data.xp) - xp_required()
		data.level = int(data.level) + 1
		data.bread = int(data.bread) + int(RogueCatalog.BALANCE.progression.bread_per_level)
		levels += 1
	return levels

func _grant_relic(id: String) -> void:
	data.relics[id] = int(data.relics.get(id, 0)) + 1

func _relic_bonus(id: String) -> float:
	return int(data.relics.get(id, 0)) * float(RogueCatalog.RELICS[id].amount)

func _unit(uid: int) -> Dictionary:
	for unit: Dictionary in data.roster:
		if int(unit.uid) == uid: return unit
	return {}

func _army_editable() -> bool:
	return data.phase in ["map", "node", "reward", "siege_briefing", "intermission", "settlement", "recruit_unit", "recruit_batch"]

func checkpoint_phase() -> String:
	return str(data.recruit_return_phase) if data.phase in RECRUIT_PHASES else str(data.phase)

func can_checkpoint() -> bool:
	return not data.is_empty() and checkpoint_phase() in SAFE_PHASES and int(data.active_node) == -1 and data.settlement.is_empty()

func _stream(salt: int) -> RandomNumberGenerator:
	var random := RandomNumberGenerator.new()
	random.seed = int(data.seed) ^ salt
	return random

func _neighbors(id: int) -> Array:
	var result: Array = []
	for edge: Array in data.edges:
		if int(edge[0]) == id: result.append(int(edge[1]))
		elif int(edge[1]) == id: result.append(int(edge[0]))
	return result

func _distances(start: int) -> Dictionary:
	var result: Dictionary = {start: 0}
	var queue: Array = [start]
	while not queue.is_empty():
		var id: int = int(queue.pop_front())
		for neighbor: int in _neighbors(id):
			if not result.has(neighbor):
				result[neighbor] = int(result[id]) + 1
				queue.append(neighbor)
	return result

func _shuffle(values: Array, random: RandomNumberGenerator) -> void:
	for index: int in range(values.size() - 1, 0, -1):
		var target: int = random.randi_range(0, index)
		var temporary: Variant = values[index]
		values[index] = values[target]
		values[target] = temporary

func export_checkpoint() -> Dictionary:
	return data.duplicate(true)

func import_checkpoint(snapshot: Dictionary) -> Error:
	var candidate := RogueRunState.new()
	candidate.data = snapshot.duplicate(true)
	if _integer(candidate.data.get("version")) and int(candidate.data.version) == 1:
		if typeof(candidate.data.get("tickets")) != TYPE_ARRAY or candidate.data.get("phase") not in SAFE_PHASES:
			return _fail("旧存档的节点或招募券数据无效", ERR_FILE_CORRUPT)
		# Preserve each old coupon's exact identity and candidates; never reroll it.
		candidate.data.version = VERSION
		candidate.data.pending_recruits = candidate.data.tickets
		candidate.data.erase("tickets")
		candidate.data.recruit_kind = ""
		candidate.data.recruit_return_phase = ""
		candidate.data.settlement = {}
		if not candidate.data.pending_recruits.is_empty():
			candidate.data.recruit_return_phase = candidate.data.phase
			candidate.data.phase = "recruit_unit"
	var reason: String = candidate.checkpoint_error()
	if not reason.is_empty(): return _fail(reason, ERR_FILE_CORRUPT)
	candidate._normalize_checkpoint_integers()
	data = candidate.data
	return _ok()

func _normalize_checkpoint_integers() -> void:
	# JSON represents every number as float; restore the documented integer fields.
	for key: String in ["version", "seed", "floor", "level", "xp", "gold", "bread", "ap", "current_node", "start_node", "active_node", "battle_difficulty", "next_unit_uid", "next_ticket_uid", "rng_counter"]:
		data[key] = int(data[key])
	for edge: Array in data.edges:
		edge[0] = int(edge[0])
		edge[1] = int(edge[1])
	for entry: Dictionary in data.nodes:
		for key: String in ["id", "x", "z", "content_seed", "difficulty"]: entry[key] = int(entry[key])
		if entry.kind == "shop":
			for offer: Dictionary in entry.offers:
				offer.price = int(offer.price)
				if offer.kind == "bread": offer.count = int(offer.count)
	for unit: Dictionary in data.roster: unit.uid = int(unit.uid)
	for ticket: Dictionary in data.pending_recruits: ticket.uid = int(ticket.uid)
	for id: String in data.relics: data.relics[id] = int(data.relics[id])

func checkpoint_error() -> String:
	# Validate only plain data. Never load resource paths or instantiate classes from saves.
	var integer_fields: Array[String] = ["version", "seed", "floor", "level", "xp", "gold", "bread", "ap", "current_node", "start_node", "active_node", "battle_difficulty", "next_unit_uid", "next_ticket_uid", "rng_counter"]
	for key: String in integer_fields:
		if not data.has(key) or not _integer(data[key]): return "存档缺少有效数值字段：%s" % key
	for key: String in ["phase", "strategy", "pack", "battle_kind", "last_result", "recruit_kind", "recruit_return_phase"]:
		if not data.has(key) or typeof(data[key]) != TYPE_STRING: return "存档缺少有效文本字段：%s" % key
	for key: String in ["nodes", "edges", "roster", "pending_recruits", "pending_choices"]:
		if not data.has(key) or typeof(data[key]) != TYPE_ARRAY: return "存档缺少有效列表字段：%s" % key
	for key: String in ["pending_siege", "emergency"]:
		if not data.has(key) or typeof(data[key]) != TYPE_BOOL: return "存档缺少状态字段：%s" % key
	if not data.has("relics") or typeof(data.relics) != TYPE_DICTIONARY: return "收藏品存档无效"
	if typeof(data.get("settlement")) != TYPE_DICTIONARY or not data.settlement.is_empty(): return "节点战利品尚未处理完毕"
	if int(data.version) != VERSION: return "此存档版本不受支持"
	if not RogueCatalog.STRATEGIES.has(data.strategy) or not RogueCatalog.PACKS.has(data.pack): return "存档中的初始战略或部队无效"
	if not can_checkpoint() or not data.pending_choices.is_empty() or data.emergency:
		return "存档必须位于已退出节点的安全检查点"
	if data.phase in RECRUIT_PHASES:
		if data.pending_recruits.is_empty(): return "强制招募缺少待处理候选"
		if data.phase == "recruit_unit" and not data.recruit_kind.is_empty(): return "招募选择阶段不一致"
	elif not data.pending_recruits.is_empty() or not data.recruit_kind.is_empty() or not data.recruit_return_phase.is_empty():
		return "待处理招募不能绕过选择返回地图"
	if int(data.seed) <= 0 or int(data.seed) > 0x7fffffff or int(data.level) < 1 or int(data.xp) < 0 or int(data.xp) >= xp_required():
		return "存档中的种子或成长数据无效"
	if int(data.gold) < 0 or int(data.bread) < 0 or int(data.ap) < 0 or int(data.ap) > int(RogueCatalog.BALANCE.initial.max_ap) or int(data.rng_counter) < 0:
		return "存档中的经济数据无效"
	if checkpoint_phase() == "intermission":
		if int(data.floor) != 2 or data.pending_siege or int(data.ap) != int(RogueCatalog.BALANCE.initial.max_ap): return "层间休整状态不一致"
	elif int(data.floor) != 1:
		return "当前版本仅支持第一层探索"
	if (checkpoint_phase() == "siege_briefing") != bool(data.pending_siege) or (int(data.ap) == 0) != bool(data.pending_siege):
		return "行动力与围剿状态不一致"
	if data.battle_kind not in ["outpost", "siege"] or (data.pending_siege and data.battle_kind != "siege"): return "作战类型无效"
	if int(data.battle_difficulty) < 1 or int(data.battle_difficulty) > 5: return "作战难度必须位于 1 到 5"
	var balance: Resource = RogueCatalog.BALANCE
	if data.nodes.size() != balance.coordinates.size() or data.edges.size() * 2 != balance.edges.size(): return "地图模板数据不完整"
	for edge_index: int in data.edges.size():
		var edge: Variant = data.edges[edge_index]
		if typeof(edge) != TYPE_ARRAY or edge.size() != 2: return "地图道路数据无效"
		for endpoint: int in 2:
			if not _integer(edge[endpoint]) or int(edge[endpoint]) != int(balance.edges[edge_index * 2 + endpoint]): return "地图道路与模板不匹配"
	if int(data.current_node) < 0 or int(data.current_node) >= data.nodes.size() or int(data.start_node) < 0 or int(data.start_node) >= data.nodes.size(): return "当前位置无效"
	var counts: Dictionary = {}
	for index: int in data.nodes.size():
		var entry: Variant = data.nodes[index]
		if typeof(entry) != TYPE_DICTIONARY: return "地图节点无效"
		for key: String in ["id", "x", "z", "content_seed", "difficulty"]:
			if not entry.has(key) or not _integer(entry[key]): return "地图节点坐标无效"
		var coord: Vector2 = balance.coordinates[index]
		if int(entry.id) != index or int(entry.x) != int(coord.x) or int(entry.z) != int(coord.y) or int(entry.content_seed) <= 0: return "地图节点与模板不匹配"
		if int(entry.difficulty) < 1 or int(entry.difficulty) > 5: return "节点难度必须位于 1 到 5"
		if not entry.has("kind") or not RogueCatalog.NODE_NAMES.has(entry.kind): return "地图节点类型无效"
		for key: String in ["completed", "resolved"]:
			if not entry.has(key) or typeof(entry[key]) != TYPE_BOOL: return "节点完成状态无效"
		if not entry.has("result_text") or typeof(entry.result_text) != TYPE_STRING: return "节点结果无效"
		if entry.completed != entry.resolved: return "节点结算未完成，不能读取半节点存档"
		counts[entry.kind] = int(counts.get(entry.kind, 0)) + 1
		if entry.kind == "shop":
			var shop_error: String = _shop_snapshot_error(entry)
			if not shop_error.is_empty(): return shop_error
		if entry.kind in ["camp", "emergency"] and (not entry.has("relic_choices") or not _valid_choices(entry.relic_choices, RogueCatalog.RELICS)): return "节点收藏品候选无效"
		if entry.kind == "event":
			if not entry.has("event_id") or not RogueCatalog.EVENTS.has(entry.event_id) or not entry.has("risk_success") or typeof(entry.risk_success) != TYPE_BOOL: return "事件数据无效"
	for kind: String in balance.node_counts:
		if int(counts.get(kind, 0)) != int(balance.node_counts[kind]): return "地图内容数量与当前第一层配置不匹配"
	if node(int(data.start_node)).kind != "road" or not node(int(data.current_node)).completed: return "检查点不在已完成节点"
	var seen_units: Dictionary = {}
	for entry: Variant in data.roster:
		if typeof(entry) != TYPE_DICTIONARY or not entry.has("uid") or not _integer(entry.uid) or int(entry.uid) < 1 or seen_units.has(int(entry.uid)): return "军队单位编号无效"
		seen_units[int(entry.uid)] = true
		if int(data.next_unit_uid) <= int(entry.uid) or not entry.has("kind") or not RogueCatalog.RECRUIT.has(entry.kind): return "军队兵种无效"
		if not entry.has("deployed") or typeof(entry.deployed) != TYPE_BOOL or not entry.has("layouts") or typeof(entry.layouts) != TYPE_DICTIONARY: return "编队数据无效"
		for encounter: String in ["outpost", "siege"]:
			if not entry.layouts.has(encounter) or typeof(entry.layouts[encounter]) != TYPE_ARRAY: return "缺少战场布阵"
			var reason: String = _layout_error(entry, encounter, entry.layouts[encounter], false)
			if not reason.is_empty(): return "存档布阵无效：" + reason
	if int(data.next_unit_uid) < 1 or int(data.next_ticket_uid) < 1: return "存档编号计数器无效"
	var seen_tickets: Dictionary = {}
	for entry: Variant in data.pending_recruits:
		if typeof(entry) != TYPE_DICTIONARY or not entry.has("uid") or not _integer(entry.uid) or int(entry.uid) < 1 or seen_tickets.has(int(entry.uid)) or int(entry.uid) >= int(data.next_ticket_uid): return "招募券编号无效"
		seen_tickets[int(entry.uid)] = true
		if not entry.has("candidates") or not _valid_choices(entry.candidates, RogueCatalog.RECRUIT): return "招募券候选无效"
		var affordable: bool = false
		for kind: String in entry.candidates:
			if int(RogueCatalog.RECRUIT[kind].bread) == 1: affordable = true
		if not affordable: return "招募券缺少基础兵种"
	if data.phase == "recruit_batch" and not data.pending_recruits[0].candidates.has(data.recruit_kind): return "招募批量缺少已选兵种"
	for id: Variant in data.relics:
		if typeof(id) != TYPE_STRING or not RogueCatalog.RELICS.has(id) or not _integer(data.relics[id]) or int(data.relics[id]) < 1: return "收藏品数据无效"
	if population() > population_cap(): return "存档编队超过人口上限"
	for entry: Dictionary in data.roster:
		if entry.deployed:
			for encounter: String in ["outpost", "siege"]:
				var reason: String = _layout_error(entry, encounter, entry.layouts[encounter], true)
				if not reason.is_empty(): return "存档布阵无效：" + reason
	return ""

func _shop_snapshot_error(entry: Dictionary) -> String:
	if not entry.has("offers") or typeof(entry.offers) != TYPE_ARRAY or entry.offers.size() != 6: return "商店货架数据不完整"
	var kinds: Dictionary = {}
	var relic_ids: Dictionary = {}
	for offer: Variant in entry.offers:
		if typeof(offer) != TYPE_DICTIONARY or not offer.has("kind") or offer.kind not in ["relic", "ticket", "bread"] or not offer.has("price") or not _integer(offer.price) or not offer.has("sold") or typeof(offer.sold) != TYPE_BOOL: return "商店商品数据无效"
		kinds[offer.kind] = int(kinds.get(offer.kind, 0)) + 1
		match String(offer.kind):
			"relic":
				if not offer.has("relic_id") or not RogueCatalog.RELICS.has(offer.relic_id) or relic_ids.has(offer.relic_id): return "商店收藏品无效"
				relic_ids[offer.relic_id] = true
				if int(offer.price) != int(RogueCatalog.RELICS[offer.relic_id].price): return "收藏品价格无效"
			"ticket":
				if int(offer.price) != int(RogueCatalog.BALANCE.shop.ticket_price): return "招募券价格无效"
			"bread":
				if not offer.has("count") or not _integer(offer.count) or int(offer.count) != int(RogueCatalog.BALANCE.shop.bread_count) or int(offer.price) != int(RogueCatalog.BALANCE.shop.bread_price): return "面包商品无效"
	if int(kinds.get("relic", 0)) != 3 or int(kinds.get("ticket", 0)) != 2 or int(kinds.get("bread", 0)) != 1: return "商店商品构成无效"
	return ""

func _valid_choices(value: Variant, catalog: Dictionary) -> bool:
	if typeof(value) != TYPE_ARRAY or value.size() != 3: return false
	var seen: Dictionary = {}
	for id: Variant in value:
		if typeof(id) != TYPE_STRING or not catalog.has(id) or seen.has(id): return false
		seen[id] = true
	return true

func _integer(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) == float(int(value))

func _ok() -> Error:
	error_message = ""
	return OK

func _fail(message: String, code: Error = ERR_INVALID_PARAMETER) -> Error:
	error_message = message
	return code
