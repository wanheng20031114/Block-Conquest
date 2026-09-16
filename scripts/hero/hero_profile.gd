class_name HeroProfile
extends RefCounted
const PATH := "user://hero_profile.cfg"
const EXPRESSION_NAMES := ["微笑 · 默认", "开心", "眨眼", "专注", "惊讶", "悠闲"]
const HAT_NAMES := ["无帽子", "皮革小帽 · 默认", "软呢贝雷帽", "旅行宽檐帽"]

static func defaults() -> Dictionary:
	return {"name":"远行者","faction":0,"team_clothes":true,"garment":Color("2087ab"),
		"face":Color("f2dab0"),"boots":Color("63452f"),"hat":true,"headwear":0,"expression":0,
		"backpack":false,"nose":false,"glasses":false,"scarf":false,"moustache":false,"feather":false}

static func sanitize(values: Dictionary) -> Dictionary:
	var result := defaults()
	if values.get("name") is String:
		var name: String = values.name.strip_edges().replace("\n","").replace("\r","").left(20)
		if not name.is_empty(): result.name = name
	if values.get("faction") is int: result.faction = clampi(values.faction,0,FactionPalette.SANDBOX_COLORS.size()-1)
	for key: String in ["team_clothes","hat","backpack","nose","glasses","scarf","moustache","feather"]:
		if values.get(key) is bool: result[key] = values[key]
	if values.get("expression") is int: result.expression = clampi(values.expression,0,EXPRESSION_NAMES.size()-1)
	if values.get("headwear") is int: result.headwear = clampi(values.headwear,0,HAT_NAMES.size()-2)
	for key: String in ["garment","face","boots"]:
		var value: Variant = values.get(key)
		if value is Color and is_finite(value.r) and is_finite(value.g) and is_finite(value.b):
			result[key] = Color(clampf(value.r,0,1),clampf(value.g,0,1),clampf(value.b,0,1),1)
	return result

static func read_profile(path: String = PATH) -> Dictionary:
	var file := ConfigFile.new()
	var values := defaults()
	if file.load(path) == OK:
		for key: String in values: values[key] = file.get_value("hero",key,values[key])
	return sanitize(values)

static func save_profile(values: Dictionary, path: String = PATH) -> Error:
	var file := ConfigFile.new()
	var clean := sanitize(values)
	for key: String in clean: file.set_value("hero",key,clean[key])
	return file.save(path)
