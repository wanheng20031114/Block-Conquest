extends Node

@onready var relay: Node = $RelayServer

func _ready() -> void:
	Engine.max_fps = 120
	var config := ConfigFile.new()
	var path := OS.get_environment("BLOCK_CONQUEST_RELAY_CONFIG")
	if path.is_empty(): path = "user://relay.cfg"
	if config.load(path) != OK:
		push_error("BLOCK_CONQUEST_RELAY_CONFIG_MISSING")
		get_tree().quit(1)
		return
	relay.model.max_rooms = int(config.get_value("relay", "max_rooms", 32))
	var result: Error = relay.start(str(config.get_value("relay", "bind", "*")), int(config.get_value("relay", "port", 42300)), str(config.get_value("tls", "private_key", "")), str(config.get_value("tls", "certificate", "")))
	if result != OK:
		push_error("BLOCK_CONQUEST_RELAY_START_FAILED code=%d" % result)
		get_tree().quit(1)
		return
	print("BLOCK_CONQUEST_RELAY_RUNTIME version=%s editor=%s debug=%s dedicated_server=%s" % [Engine.get_version_info().string, OS.has_feature("editor"), OS.is_debug_build(), OS.has_feature("dedicated_server")])
	print("BLOCK_CONQUEST_RELAY_READY protocol=%d version=%s port=%d rooms=%d" % [relay.P.VERSION, relay.P.RELEASE, relay.connection.get_local_port(), relay.model.max_rooms])
