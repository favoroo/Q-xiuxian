class_name PetIconDraw
extends RefCounted

## 灵兽图标的统一画法：无脸圆球光灵（外圈灵光晕 + 核心圆球 + 左上单点高光），
## 与游戏内 SpiritPet 本体（2026-10-24 圆球光灵重做）同源。货架卡 / 已持有灵兽徽记 /
## 图鉴条目三处共用本函数，禁止各处手抄三行 draw_circle —— 上一版徽记就是这么漂移成旧焰形的。

static func draw_orb(ctrl: Control, def: Dictionary) -> void:
	var c: Color = def.get("color", Color(0.9, 0.9, 0.9))
	var halo: Color = def.get("halo_color", Color(1.0, 1.0, 1.0, 0.3))
	var sz: Vector2 = ctrl.size
	var center := sz * 0.5
	var r: float = sz.x * 0.28
	ctrl.draw_circle(center, r * 1.6, halo)
	ctrl.draw_circle(center, r, c)
	ctrl.draw_circle(center + Vector2(-r * 0.25, -r * 0.25), r * 0.35, Color(1.0, 1.0, 1.0, 0.85))
