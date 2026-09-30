extends Node
## Injected only into a verification copy of the finished PCK. Run that copy
## with the shipped release EXE, never an editor (which embeds the ICU data).

const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(2560, 1440)]
var checks: int = 0
var failures: Array[String] = []
var samples: Array[Dictionary] = []
var output: String

func _ready() -> void:
	_run.call_deferred()

func _check(passed: bool, message: String) -> void:
	checks += 1
	if not passed:
		failures.append(message)
		printerr("FAIL EXPORT_TEXT_LAYOUT ", message)

func _settle() -> void:
	for frame: int in 8:
		await get_tree().process_frame

func _label(page: Control, name: String, context: String) -> void:
	var label: Label = page.get_node("%" + name)
	if not label.is_visible_in_tree():
		return
	# Label minimum size does not expose overflowing unbreakable words. Measure
	# actual shaped line widths with the same native font and wrapping rules.
	var paragraph := TextParagraph.new()
	paragraph.width = label.size.x
	paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND
	paragraph.add_string(label.text, label.get_theme_font("font"), label.get_theme_font_size("font_size"), label.language)
	var widest: float = 0.0
	for line: int in paragraph.get_line_count():
		widest = maxf(widest, paragraph.get_line_size(line).x)
	_check(widest <= label.size.x + 1.0, "%s / %s shaped text %.1f fits %.1f" % [context, name, widest, label.size.x])
	_check(label.get_visible_line_count() >= label.get_line_count(), context + " / " + name + " has no clipped lines")
	if name == "GuideTip":
		samples.append({"context": context, "lines": label.get_line_count(), "width": label.size.x, "widest_line": widest})

func _capture(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	_check(get_tree().root.get_texture().get_image().save_png(output.path_join(name + ".png")) == OK, "save " + name)

func _run() -> void:
	get_tree().create_timer(80.0, true, false, true).timeout.connect(func(): get_tree().quit(3))
	output = OS.get_cmdline_user_args()[0]
	var text_server := TextServerManager.get_primary_interface()
	_check(not OS.has_feature("editor") and not OS.is_debug_build(), "actual release template, without embedded editor data")
	_check(FileAccess.file_exists("res://" + text_server.get_support_data_filename()), "ICU support data shipped inside the PCK")
	_check(ProjectSettings.get_setting("internationalization/locale/include_text_server_data", false), "CJK support export enabled")
	print("EXPORT_TEXT_RUNTIME ", JSON.stringify({"engine": Engine.get_version_info().string, "editor": OS.has_feature("editor"), "debug": OS.is_debug_build(), "text_server": text_server.get_name()}))
	await _settle()
	var page: Control = get_tree().current_scene
	get_tree().root.mode = Window.MODE_WINDOWED
	for resolution: Vector2i in RESOLUTIONS:
		get_tree().root.size = resolution
		page._set_category(1)
		await _settle()
		_check(page.get_node("%Entries").texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR, "guide vectors use smooth sampling")
		for row: int in page._guides.size():
			page.get_node("%Entries").select(row)
			page.get_node("%Entries").ensure_current_is_visible()
			page._select_entry(row)
			await _settle()
			var context := "%dx%d guide %d" % [resolution.x, resolution.y, row]
			var icon: Texture2D = page.get_node("%Entries").get_item_icon(row)
			_check(icon is DPITexture and icon.get_width() >= 128, context + " has an independent high-resolution vector icon")
			for name: String in ["GuideTip", "DetailSummary", "SectionBody0", "SectionBody1", "SectionBody2"]:
				_label(page, name, context)
			if row == 1:
				_check(page.get_node("%GuideTip").get_line_count() >= 3, context + " Chinese-only capture tip wraps")
				await _capture("victory_%dx%d" % [resolution.x, resolution.y])
		page._set_category(0)
		_check(page.get_node("%Entries").texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "hero portraits retain pixel sampling")
		for row: int in page.get_node("%Entries").item_count:
			page.get_node("%Entries").select(row)
			page.get_node("%Entries").ensure_current_is_visible()
			page._select_entry(row)
			for skill: int in 4:
				page._select_skill(skill, false)
				await _settle()
				# Give a resized SubViewport a real rendered frame before pausing;
				# otherwise its new texture contains uninitialized GPU memory.
				page.get_node("%Demo").set_playing(false)
				var context := "%dx%d hero %d skill %d" % [resolution.x, resolution.y, row, skill]
				for name: String in ["DetailSummary", "HeroRole", "HeroNote", "SkillDescription"]:
					_label(page, name, context)
			if row == 5:
				await _capture("hero_%dx%d" % [resolution.x, resolution.y])
	var report := {"checks": checks, "failures": failures, "guide_tips": samples}
	var file := FileAccess.open(output.path_join("text-layout.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("EXPORT_TEXT_LAYOUT checks=", checks, " failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
