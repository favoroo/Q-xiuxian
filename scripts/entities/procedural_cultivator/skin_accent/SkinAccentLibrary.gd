extends RefCounted

## 角色皮肤挂件调度：cid + 皮肤系列 → 形制 + 配色 + 绘制
##
## 只读宿主渲染器状态：character_id / config.fx / col_* / _accent_*。
## 不持有节点、不做时间推进；调用点由 HollowKnightCultivatorRenderer 统一管。
## 家族模块按路径 preload、不加 class_name（与 skin_fx/ 同约定）。

const AccentData = preload("res://scripts/entities/procedural_cultivator/skin_accent/SkinAccentData.gd")
const AccentDraw = preload("res://scripts/entities/procedural_cultivator/skin_accent/SkinAccentDraw.gd")

static func draw(h, float_y: float, angle: int, include_ornament: bool) -> void:
	var form := form_for(h)
	if include_ornament:
		AccentDraw.draw_chest_ornament(h, float_y, angle, form)
	var cid: String = h.character_id
	if cid == "":
		return
	var spec: Dictionary = AccentData.MOTIFS.get(cid, {})
	if spec.is_empty():
		return
	AccentDraw.draw(h, spec, form, float_y, angle)

## 皮肤系列 → 形制；原色（fx 空）取 0 号本相形制
static func form_for(h) -> Dictionary:
	var idx := 0
	var cfg = h.config
	if cfg != null and not cfg.fx.is_empty():
		var kind := String(cfg.fx.get("kind", ""))
		idx = int(AccentData.KIND_INDEX.get(kind, 0))
	return AccentData.FORMS[idx]
