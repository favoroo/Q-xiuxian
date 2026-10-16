extends Node2D

## 击杀残晕（GroundDecal.FADE_GLOW）现场预览（非判据，2026-10-16）：
## 三种敌种主色（血煞红 / 腐沼绿 / 鎏金黄）残晕循环重喷，定格帧可见不同生命阶段的形态。
## 运行: godot --path . res://tests/DecalGlowPreview.tscn
## （自动在第 30 帧截图存 /tmp/decal_glow_preview.png 后退出；不接判据，纯目检）

var _frame := 0
var _spots: Array[Vector2] = [Vector2(200, 240), Vector2(480, 240), Vector2(760, 240)]
var _tints: Array[Color] = [
	Color(0.55, 0.10, 0.16, 0.85),   # 血煞流质（旧版撞脸出生预警的红）
	Color(0.14, 0.26, 0.16, 1.0),    # 腐沼暗绿
	Color(0.55, 0.38, 0.08, 1.0),    # 鎏金蟾躯
]

func _ready() -> void:
	# 贴近实战胜率底色（深蓝地砖色）
	RenderingServer.set_default_clear_color(Color(0.09, 0.12, 0.18))
	for i in range(_spots.size()):
		var lb := Label.new()
		lb.text = ["血煞红", "腐沼绿", "鎏金黄"][i]
		lb.position = _spots[i] + Vector2(-30, 60)
		add_child(lb)

## 三柱分别在第 12/18/24 帧出膛，第 34 帧截图时落在 0.37s / 0.27s / 0.17s 三个生命阶段
const SPAWN_FRAMES := [12, 18, 24]
const SHOT_FRAME := 34

func _process(_delta: float) -> void:
	_frame += 1
	for i in range(SPAWN_FRAMES.size()):
		if _frame == SPAWN_FRAMES[i]:
			GroundDecal.spawn_tinted(self, _spots[i], 30.0, _tints[i])
	if _frame == SHOT_FRAME:
		var img := get_viewport().get_texture().get_image()
		img.save_png("/tmp/decal_glow_preview.png")
		get_tree().quit(0)
