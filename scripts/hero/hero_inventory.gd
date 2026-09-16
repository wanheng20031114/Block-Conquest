class_name HeroInventory
extends Node
## Shortcuts identify an item type, not a copy of a stack or its cooldown.
signal changed
const CAPACITY := 24
const HOTBAR_SIZE := 5
const ITEMS := {
	&"healing_potion":preload("res://data/sandbox/items/healing_potion.tres"),
	&"windwalk_potion":preload("res://data/sandbox/items/windwalk_potion.tres")}
var slots: Array[Dictionary] = []
var hotbar: Array[StringName] = [&"healing_potion",&"windwalk_potion",&"",&"",&""]
var cooldowns: Dictionary = {}

func _ready() -> void:
	for index: int in CAPACITY: slots.append({"id":&"","count":0})
	add(&"healing_potion",3)
	add(&"windwalk_potion",2)

func advance(delta: float) -> void:
	for id: StringName in cooldowns: cooldowns[id] = maxf(0.0,cooldowns[id]-delta)

func count(id: StringName) -> int:
	var result: int = 0
	for slot: Dictionary in slots:
		if slot.id == id: result += slot.count
	return result

func add(id: StringName, amount: int) -> int:
	if not ITEMS.has(id) or amount <= 0: return amount
	var remaining := amount
	for empty: bool in [false,true]:
		for slot: Dictionary in slots:
			if (empty and slot.count==0) or (not empty and slot.id==id and slot.count<ITEMS[id].stack_limit):
				var added := mini(remaining,ITEMS[id].stack_limit-slot.count)
				slot.id = id
				slot.count += added
				remaining -= added
				if remaining == 0: changed.emit(); return 0
	changed.emit()
	return remaining

func move_stack(source: int,destination: int) -> bool:
	if source<0 or source>=CAPACITY or destination<0 or destination>=CAPACITY or source==destination: return false
	var a := slots[source]
	var b := slots[destination]
	if a.count==0: return false
	if a.id==b.id:
		var moved := mini(a.count,ITEMS[a.id].stack_limit-b.count)
		a.count -= moved
		b.count += moved
		if a.count==0: a.id = &""
	else:
		slots[source] = b
		slots[destination] = a
	changed.emit()
	return true

func assign(index: int,id: StringName) -> bool:
	if index<0 or index>=HOTBAR_SIZE or (not id.is_empty() and (not ITEMS.has(id) or count(id)==0)): return false
	hotbar[index] = id
	changed.emit()
	return true

func use(id: StringName, hero: HeroUnit) -> String:
	if not hero.alive: return "英雄已阵亡"
	if not ITEMS.has(id) or count(id)==0: return "没有这种药剂"
	if cooldowns.get(id,0.0)>.000001: return "药剂正在冷却"
	var item: HeroItemDefinition = ITEMS[id]
	match item.effect:
		HeroItemDefinition.Effect.HEAL:
			if hero.restore_health(item.amount)<=0: return "生命值已满"
		HeroItemDefinition.Effect.SPEED:
			if hero.speed_boost_remaining>0.0: return "加速效果仍在持续"
			hero.speed_boost_remaining = item.duration
			hero.speed_boost_multiplier = item.amount
			hero.speed = hero._stats.speed*item.amount
	cooldowns[id] = item.cooldown
	for slot: Dictionary in slots:
		if slot.id==id and slot.count>0:
			slot.count -= 1
			if slot.count==0: slot.id = &""
			break
	changed.emit()
	return ""
