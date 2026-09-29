extends RefCounted
## Each test owns disposable TLS files; local networking never needs deploy keys.

const P := preload("res://scripts/network/war_protocol.gd")
var directory := ""
var key_path := ""
var certificate_path := ""
var untrusted_certificate_path := ""

func create(label: String) -> Error:
	directory = "res://.local/network-tests/%s-%d-%d" % [label, OS.get_process_id(), Time.get_ticks_usec()]
	key_path = directory + "/relay.key"
	certificate_path = directory + "/relay.crt"
	untrusted_certificate_path = directory + "/untrusted.crt"
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	if error != OK: return error
	return _write_identity(certificate_path, key_path)

func create_untrusted_certificate() -> Error:
	return _write_identity(untrusted_certificate_path)

func _write_identity(certificate_file: String, private_file: String = "") -> Error:
	var crypto := Crypto.new()
	var key := crypto.generate_rsa(2048)
	if key == null: return ERR_CANT_CREATE
	var certificate := crypto.generate_self_signed_certificate(key, "CN=%s,O=Block Conquest Local Test,C=JP" % P.TLS_NAME, "20240101000000", "20400101000000")
	if certificate == null: return ERR_CANT_CREATE
	if not private_file.is_empty():
		var error := key.save(private_file)
		if error != OK: return error
	return certificate.save(certificate_file)

func cleanup() -> Error:
	if directory.is_empty(): return OK
	for path: String in [key_path, certificate_path, untrusted_certificate_path]:
		if FileAccess.file_exists(path):
			var error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
			if error != OK: return error
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(directory)):
		return DirAccess.remove_absolute(ProjectSettings.globalize_path(directory))
	return OK
