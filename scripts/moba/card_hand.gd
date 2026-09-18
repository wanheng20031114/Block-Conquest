class_name MobaCardHand
extends RefCounted
## Independent match state, no UI timers or global random source own gameplay.
var deck: MobaDeckDefinition
var slots: Array[Dictionary] = []
var bag: Array[MobaCardDefinition] = []
var random := RandomNumberGenerator.new()
var serial: int = 0

func _init(definition: MobaDeckDefinition, seed_value: int) -> void:
	deck = definition
	random.seed = seed_value
	assert(deck.hand_size == 5 and deck.cards.size() >= deck.hand_size)
	for card: MobaCardDefinition in deck.cards: assert(card.is_valid())
	_refill_bag()
	for index: int in deck.hand_size:
		var card: MobaCardDefinition
		if index < deck.opening_hand.size():
			for choice: MobaCardDefinition in bag:
				if choice.id == deck.opening_hand[index]: card = choice; break
		assert(card != null, "Opening card must exist in the authored deck")
		bag.erase(card)
		slots.append(_entry(card))

func _entry(card: MobaCardDefinition) -> Dictionary:
	serial += 1
	return {"card": card, "uid": serial, "remaining": 0.0}

func _refill_bag() -> void:
	bag.assign(deck.cards)
	for index: int in range(bag.size() - 1, 0, -1):
		var other := random.randi_range(0, index)
		var swap := bag[index]
		bag[index] = bag[other]
		bag[other] = swap

func consume(index: int) -> void:
	slots[index] = {"card": null, "uid": 0, "remaining": deck.refill_seconds}

func advance(delta: float) -> void:
	for index: int in slots.size():
		if slots[index].card != null: continue
		slots[index].remaining = maxf(0, float(slots[index].remaining) - delta)
		if slots[index].remaining <= .000001:
			if bag.is_empty(): _refill_bag()
			slots[index] = _entry(bag.pop_back())
