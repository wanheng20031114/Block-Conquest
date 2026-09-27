extends TextureProgressBar
## Fractional charge is native clipped texture fill; only complete stars emit light.

const PARTIAL_TINT := Color(0.6, 0.6, 0.6, 1.0)
var _glow_tween: Tween

func set_charge(charge: float) -> void:
	value = clampf(charge, 0.0, 1.0)
	var full: bool = value >= 1.0
	# A near-full 16 px star can lose only a subpixel tip; tint keeps it distinct.
	tint_progress = Color.WHITE if full else PARTIAL_TINT
	if $Glow.visible == full:
		return
	$Glow.visible = full
	if _glow_tween != null and _glow_tween.is_valid():
		_glow_tween.kill()
	$Glow.scale = Vector2.ONE
	$Glow.modulate.a = 0.72
	if full:
		_glow_tween = create_tween().set_loops().set_parallel(true)
		_glow_tween.tween_property($Glow, "scale", Vector2(1.12, 1.12), 1.15).set_trans(Tween.TRANS_SINE)
		_glow_tween.tween_property($Glow, "modulate:a", 0.35, 1.15).set_trans(Tween.TRANS_SINE)
		_glow_tween.chain().tween_property($Glow, "scale", Vector2.ONE, 1.15).set_trans(Tween.TRANS_SINE)
		_glow_tween.parallel().tween_property($Glow, "modulate:a", 0.72, 1.15).set_trans(Tween.TRANS_SINE)
