class_name SealImpactFx
extends Node2D

## 巨印（番天镇岳印）落点砸物的纯矢量印体（2026-10-14）：取代 AI 位图 weapon_earth_seal.png
## 充当动态特效的旧写法 —— 128px 图标缩放染色砸在爆心，与全场扁平 _draw 风格违和。
## 俯视方印一座：玄石印身 + 土黄印面 + 朱砂符带 + 中心灵纹，全部几何由 size 一个量派生
## （size = 判定半径 × 1.4，画多大 == 砸多大），静态构图一次画成，淡出演由 ThunderBurst 的 tween 负责。

## 画幅宽度（px）—— 由 ThunderBurst 按 radius * 1.4 下发，与旧位图落点同一把尺子
var size: float = 100.0
## 印面色相（由 WeaponData.burst_tint 下发，土黄系）
var tint: Color = Color(0.88, 0.74, 0.46)

const INK := Color(0.08, 0.09, 0.12)          ## 粗黑外轮廓（空洞冷冽硬边）
const STONE := Color(0.16, 0.18, 0.24)        ## 玄石印身
const STONE_HI := Color(0.30, 0.33, 0.42)     ## 玄石受光棱
const CINNABAR := Color(0.72, 0.22, 0.16)     ## 朱砂符带

func _ready() -> void:
	queue_redraw()

func _draw() -> void:
	var h := size * 0.5
	var face := h * 0.62          ## 印面半边长
	var band := size * 0.075      ## 朱砂符带宽

	# 玄石印身（外方）
	var body := PackedVector2Array([
		Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)])
	draw_colored_polygon(body, STONE)
	# 左上受光棱：一道亮边把「一块石头」从剪影里拎出来
	draw_line(Vector2(-h, -h), Vector2(h, -h), STONE_HI, 3.0)
	draw_line(Vector2(-h, -h), Vector2(-h, h), STONE_HI, 3.0)

	# 土黄印面（内方）
	var inner := PackedVector2Array([
		Vector2(-face, -face), Vector2(face, -face),
		Vector2(face, face), Vector2(-face, face)])
	draw_colored_polygon(inner, Color(tint.r * 0.82, tint.g * 0.8, tint.b * 0.72))

	# 朱砂符带：对角交叉封缄压过印面（镇岳印的封条读法；正十字会被读成医疗包）
	draw_line(Vector2(-face, -face), Vector2(face, face), CINNABAR, band * 2.0)
	draw_line(Vector2(-face, face), Vector2(face, -face), CINNABAR, band * 2.0)

	# 中心灵纹：符带交汇处的镇字符环 + 八方卦刻
	draw_arc(Vector2.ZERO, face * 0.42, 0.0, TAU, 24, Color(tint.r, tint.g, tint.b, 0.95), 2.2)
	for k in 8:
		var ang := float(k) * TAU / 8.0 + TAU / 16.0
		var dir := Vector2(cos(ang), sin(ang))
		draw_line(dir * face * 0.52, dir * face * 0.78,
			Color(INK.r, INK.g, INK.b, 0.65), 1.6)

	# 粗黑外轮廓最后压一圈（外方 + 印面各一道）
	var body_outline := PackedVector2Array([
		Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h), Vector2(-h, -h)])
	draw_polyline(body_outline, INK, 3.2)
	var face_outline := PackedVector2Array([
		Vector2(-face, -face), Vector2(face, -face), Vector2(face, face),
		Vector2(-face, face), Vector2(-face, -face)])
	draw_polyline(face_outline, Color(INK.r, INK.g, INK.b, 0.8), 2.0)
