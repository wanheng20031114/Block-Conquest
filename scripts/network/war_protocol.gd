extends RefCounted
## Wire data is bounded JSON, never Variant object deserialization or remote RPC.

const VERSION := 1
const RELEASE := "1.3.1"
const PORT := 42300
const TLS_NAME := "block-conquest-relay"
const CHANNEL_COUNT := 6
const ROOM_CHANNEL := 0
const COMMAND_CHANNEL := 1
const EVENT_CHANNEL := 2
const CURSOR_CHANNEL := 3
const ANCHOR_CHANNEL := 4
const SNAPSHOT_CHANNEL := 5
const MAX_PACKET_BYTES := 65536
const MAX_CONTROL_BYTES := 4096
const MAX_CURSOR_BYTES := 1024
const MAX_DATAGRAM_BYTES := 1200
const MAX_PLAYERS := 6
const MAP_SEATS := {"rift": 2, "lake": 2, "rivers": 4, "ridges": 4, "islands": 6, "highland": 6,
	"terraces": 2, "switchback": 4, "crown": 6}
const COMMANDERS := ["squirrel", "rabbit", "bear", "frog"]
const HOST_KINDS := ["events", "anchors", "digest", "snapshot_begin", "snapshot_chunk", "snapshot_end", "command_result", "time", "finished"]
const CLIENT_KINDS := ["ack", "resync"]
const CONTENT_MANIFEST := "res://data/block_war/network_manifest.json"

static func content_hash() -> String:
	return FileAccess.get_sha256(CONTENT_MANIFEST)

static func encode(message: Dictionary) -> PackedByteArray:
	if not primitive(message):
		return PackedByteArray()
	var data := JSON.stringify(message, "", false, true).to_utf8_buffer()
	return data if data.size() <= MAX_PACKET_BYTES else PackedByteArray()

static func decode(data: PackedByteArray) -> Dictionary:
	if data.is_empty() or data.size() > MAX_PACKET_BYTES:
		return {}
	var parser := JSON.new()
	if parser.parse(data.get_string_from_utf8()) != OK or not parser.data is Dictionary:
		return {}
	return parser.data if primitive(parser.data) else {}

static func primitive(value: Variant) -> bool:
	var budget: Array[int] = [32768]
	return _primitive(value, 0, budget)

static func _primitive(value: Variant, depth: int, budget: Array[int]) -> bool:
	budget[0] -= 1
	if budget[0] < 0 or depth > 16:
		return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT:
			return true
		TYPE_FLOAT:
			return is_finite(value)
		TYPE_STRING, TYPE_STRING_NAME:
			return value.length() <= MAX_PACKET_BYTES
		TYPE_ARRAY:
			for child: Variant in value:
				if not _primitive(child, depth + 1, budget): return false
		TYPE_DICTIONARY:
			for key: Variant in value:
				if (not key is String and not key is StringName) or key.length() > 64 or not _primitive(value[key], depth + 1, budget): return false
		_:
			return false
	return true

static func integer(value: Variant, minimum: int = 0, maximum: int = 2147483647) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and floorf(float(value)) == float(value) and value >= minimum and value <= maximum

static func finite_number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= minimum and value <= maximum

static func nickname(value: Variant) -> String:
	if not value is String: return "指挥官"
	var result := ""
	for character: String in value.strip_edges():
		var code := character.unicode_at(0)
		if code >= 32 and code != 127 and code not in [0x200b, 0x200e, 0x200f, 0x202a, 0x202b, 0x202c, 0x202d, 0x202e, 0x2066, 0x2067, 0x2068, 0x2069]:
			result += character
	return "指挥官" if result.is_empty() else result.left(20)

static func valid_code(value: Variant) -> bool:
	if not value is String or value.length() != 6: return false
	for character: String in value:
		if not "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".contains(character): return false
	return true

static func valid_cursor(value: Variant) -> bool:
	return value is Dictionary and integer(value.get("cursor_seq"), 0) and integer(value.get("presence_epoch"), 0) and value.get("visible") is bool and value.get("pressed") is bool and finite_number(value.get("world_x"), -2048.0, 2048.0) and finite_number(value.get("world_z"), -2048.0, 2048.0)

static func match_channel(kind: String) -> int:
	if kind.begins_with("snapshot_"): return SNAPSHOT_CHANNEL
	if kind == "anchors": return ANCHOR_CHANNEL
	if kind in ["command_result", "ack", "resync"]: return COMMAND_CHANNEL
	return EVENT_CHANNEL

static func valid_match_channel(kind: String, channel: int, reliable: bool) -> bool:
	return channel == match_channel(kind) and reliable == (kind != "anchors")

static func slot_for_player(room: Dictionary, player: int) -> Dictionary:
	for slot: Dictionary in room.get("slots", []):
		if int(slot.player_id) == player and slot.kind == "human": return slot
	return {}
