extends Node2D

## 武器特效现场预览（非判据，2026-10-13）：真渲染排布本轮新增的特效件——
## 上排：六元素近战刀光（金/火/水/木/土/雷）；中排：六元素横扫扇面；
## 下排：光束（紫）+ 火锥 + BURST 六种落点形态（fire_rain/frost/sonic/drum/earth/seal）。
## 运行: godot --path . res://tests/FxPreview.tscn
## （自动在第 12 帧截图存 /tmp/fx_preview.png 后退出；不接判据，纯目检）

var _frame := 0

func _ready() -> void:
	var elems := ["metal", "fire", "water", "wood", "earth", "thunder"]
	for i in elems.size():
		var arc := WeaponArcRenderer.new()
		arc.configure(WeaponArcRenderer.ArcMode.MELEE, elems[i])
		arc.position = Vector2(110 + i * 140, 120)
		arc.scale = Vector2.ONE * 0.75
		arc.visible = true
		arc.modulate.a = 1.0
		add_child(arc)
	for i in elems.size():
		var fan := WeaponArcRenderer.new()
		fan.configure(WeaponArcRenderer.ArcMode.SWEEP, elems[i])
		fan.position = Vector2(110 + i * 140, 280)
		fan.scale = Vector2.ONE * 0.75
		fan.visible = true
		fan.modulate.a = 1.0
		add_child(fan)
	var beam := BeamRenderer.new()
	beam.position = Vector2(80, 420)
	add_child(beam)
	beam.beam_on(240.0, 10.0, Color(0.70, 0.55, 1.0))
	var cone := FlameConeRenderer.new()
	cone.position = Vector2(420, 420)
	add_child(cone)
	cone.cone_on(170.0, 80.0)
	var kinds := ["fire_rain", "frost", "sonic", "drum", "earth", "seal"]
	var tints := [Color(1.0, 0.52, 0.18), Color(0.45, 0.75, 1.0), Color(0.35, 0.75, 1.0),
		Color(0.5, 0.85, 0.5), Color(0.80, 0.66, 0.38), Color(0.88, 0.74, 0.46)]
	for i in kinds.size():
		var fx := BurstKindFx.new()
		fx.position = Vector2(620 + (i % 3) * 130, 400 + int(i / 3.0) * 110)
		add_child(fx)
		fx.activate_fx(kinds[i], 48.0, tints[i])
		# 2026-10-23：命中微粒已从 activate_fx 拆出（改由 ThunderBurst 命中后调），
		# 出图台要看到首拍碎屑，这里显式补一发
		fx.emit_hit_spark()

func _process(_delta: float) -> void:
	_frame += 1
	if _frame == 12:
		# BURST 形态演到中段、火锥张开后再拍
		var img := get_viewport().get_texture().get_image()
		img.save_png("/tmp/fx_preview.png")
		print("FX_PREVIEW_SAVED /tmp/fx_preview.png")
		get_tree().quit(0)
