extends RefCounted

## 皮肤效果族调度库（皮肤系列动效总入口）
##
## 宿主 HollowKnightCultivatorRenderer 的 5 个钩子（重绘前重算 / 袍面叠色 / 缘边描边 /
## 常驻粒子 / 眼柔光收窄）一律委派到本库；未注册 kind 返回空参数，宿主走零开销快路。
##
## 并行协作约定：新增/调整一个皮肤系列只改对应族模块文件，别动本库与宿主。
## 族模块一律按路径 preload（不加 class_name），避免新类名触发全局扫描串行点。

const SkinFxCommon = preload("res://scripts/entities/procedural_cultivator/skin_fx/SkinFxCommon.gd")
const SkinFxChroma = preload("res://scripts/entities/procedural_cultivator/skin_fx/SkinFxChroma.gd")
const SkinFxJade = preload("res://scripts/entities/procedural_cultivator/skin_fx/SkinFxJade.gd")
const SkinFxBloodlust = preload("res://scripts/entities/procedural_cultivator/skin_fx/SkinFxBloodlust.gd")
const SkinFxSnow = preload("res://scripts/entities/procedural_cultivator/skin_fx/SkinFxSnow.gd")
const SkinFxInk = preload("res://scripts/entities/procedural_cultivator/skin_fx/SkinFxInk.gd")
const SkinFxGold = preload("res://scripts/entities/procedural_cultivator/skin_fx/SkinFxGold.gd")

## kind -> 族模块。SkinData 主题的 fx["kind"] 必须命中这里的键。
const _KINDS: Dictionary = {
	"chroma": SkinFxChroma,
	"jade": SkinFxJade,
	"bloodlust": SkinFxBloodlust,
	"snow": SkinFxSnow,
	"ink": SkinFxInk,
	"gold": SkinFxGold,
}

## 全部已注册的 kind（判据与预览工具用来遍历）
static func kinds() -> Array:
	return _KINDS.keys()

static func has_kind(kind: String) -> bool:
	return _KINDS.has(kind)

static func _find(kind: String):
	return _KINDS.get(kind, null)

## 合并族默认参数与主题覆盖：SkinData 只写 kind + 需要微调的键，默认值住在族模块里
## （这样各系列调参不碰共享数据表，并行改皮肤不冲突）。
## 未注册 kind 返回空字典 —— 宿主据此走静态换色快路。
static func params(fx: Dictionary) -> Dictionary:
	if fx.is_empty():
		return {}
	var kind := String(fx.get("kind", ""))
	var mod = _find(kind)
	if mod == null:
		return {}
	var p: Dictionary = mod.defaults()
	for k in fx.keys():
		if String(k) == "kind":
			continue
		p[k] = fx[k]
	p["kind"] = kind
	return p

# ----------------- 5 个钩子（宿主逐帧调用，参数为已合并的 params） -----------------

## 重绘前重算宿主缓存色（流光/脉动）。宿主仅在 _fx 非空时调用。
static func on_frame(h, p: Dictionary) -> void:
	var mod = _find(String(p.get("kind", "")))
	if mod != null:
		mod.on_frame(h, p)

## 袍面逐顶点叠色。返回原色即不叠（静态换色族直接返回 base）。
static func cloak_sheen(h, base: Color, pt: Vector2, p: Dictionary) -> Color:
	var mod = _find(String(p.get("kind", "")))
	if mod == null:
		return base
	return mod.cloak_sheen(h, base, pt, p)

## 缘边描边叠加（在宿主基础描边之后画）。
static func draw_rim(h, pts: PackedVector2Array, base_w: float, p: Dictionary) -> void:
	var mod = _find(String(p.get("kind", "")))
	if mod != null:
		mod.draw_rim(h, pts, base_w, p)

## 常驻粒子（在宿主 2 颗周天灵气之后画，复用同一绘制位）。
static func draw_motes(h, float_y: float, p: Dictionary) -> void:
	var mod = _find(String(p.get("kind", "")))
	if mod != null:
		mod.draw_motes(h, float_y, p)

## 眼柔光调整。返回 {"radius": float, "color": Color}；缺省原样返回。
static func eye_glow_adjust(h, radius: float, col: Color, p: Dictionary) -> Dictionary:
	var mod = _find(String(p.get("kind", "")))
	if mod == null:
		return {"radius": radius, "color": col}
	return mod.eye_glow_adjust(h, radius, col, p)
