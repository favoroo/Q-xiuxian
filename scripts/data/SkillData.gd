class_name SkillData
extends RefCounted

## 随行神通数据库：每局选定道统后择一携带，战斗右侧按钮手动释放，带冷却。
## 角色专属强化写在 CultivatorData.DEFS[cid]["skill_mods"][skill_id]，
## 卡片文案与实战数值都走 final_stats() 合并结果（唯一真话），别处不抄数字。
## skill_mods 支持的键：
##   duration_add  —— 持续/无敌秒数加算（石岳：金光护体 +1.0s）
##   power_mult    —— 效果强度乘算（移速加成 / 间隔减免 / 回血比例）
##   distance_mult —— 冲刺距离乘算（魅影：+55%）
##   cooldown_mult —— 冷却乘算（多宝/符阵/夺舍：0.65）
## glyph: 占位符文单字（正式图标走 media-gen 生成后填 icon 路径替换）

enum Kind { DASH, SPEED, HASTE, IFRAME, HEAL }

const DEFS: Dictionary = {
	"dash": {
		"name": "缩地成寸",
		"glyph": "冲",
		"icon": "res://assets/art/skill_dash.png",
		"kind": Kind.DASH,
		"cooldown": 8.0,
		"duration": 0.16,     # 冲刺位移耗时（秒），期间无敌
		"distance": 150.0,    # 冲刺距离（像素）—— 落地即收速，纸面值≈实际位移（见 Player.DASH_LANDING_SPEED_MUL）
		"desc": "向当前方向瞬身突进，突进途中万法不侵。",
	},
	"gale": {
		"name": "神行术",
		"glyph": "行",
		"icon": "res://assets/art/skill_gale.png",
		"kind": Kind.SPEED,
		"cooldown": 14.0,
		"duration": 4.0,
		"power": 0.60,        # 移速加成比例
		"desc": "御风而行：移速提升六成，持续四息。",
	},
	"haste": {
		"name": "疾风咒",
		"glyph": "疾",
		"icon": "res://assets/art/skill_haste.png",
		"kind": Kind.HASTE,
		"cooldown": 16.0,
		"duration": 5.0,
		"power": 0.40,        # 攻击间隔缩减比例
		"desc": "咒力催动法器：攻击间隔缩短四成，持续五息。",
	},
	"aegis": {
		"name": "金光护体",
		"glyph": "护",
		"icon": "res://assets/art/skill_aegis.png",
		"kind": Kind.IFRAME,
		"cooldown": 20.0,
		"duration": 1.6,
		"desc": "金光罩体：短时间内刀枪不入，不受任何伤害。",
	},
	"renewal": {
		"name": "回春术",
		"glyph": "愈",
		"icon": "res://assets/art/skill_renewal.png",
		"kind": Kind.HEAL,
		"cooldown": 25.0,
		"power": 0.25,        # 回复最大气血比例
		"desc": "枯木逢春：立即回复两成半最大气血。",
	},
}

## 技能卡横排顺序（也是选择界面的展示顺序）
const OFFER_IDS: Array = ["dash", "gale", "haste", "aegis", "renewal"]

static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, {})

static func all_ids() -> Array:
	return DEFS.keys()

## 角色是否强化该技能（选择界面黄边「✦契合」判定）
static func is_enhanced_for_cultivator(skill_id: String, cid: String) -> bool:
	var cdef: Dictionary = CultivatorData.get_def(cid)
	if cdef.is_empty():
		return false
	return Dictionary(cdef.get("skill_mods", {})).has(skill_id)

## 基础值 + 角色强化合并：{kind, cooldown, duration, power, distance}
static func final_stats(skill_id: String, cid: String) -> Dictionary:
	var def: Dictionary = get_def(skill_id)
	if def.is_empty():
		return {}
	var out: Dictionary = {
		"kind": int(def.get("kind", 0)),
		"cooldown": float(def.get("cooldown", 10.0)),
		"duration": float(def.get("duration", 0.0)),
		"power": float(def.get("power", 0.0)),
		"distance": float(def.get("distance", 0.0)),
	}
	var cdef: Dictionary = CultivatorData.get_def(cid)
	var mods: Dictionary = Dictionary(cdef.get("skill_mods", {})).get(skill_id, {})
	out["duration"] = float(out["duration"]) + float(mods.get("duration_add", 0.0))
	out["power"] = float(out["power"]) * float(mods.get("power_mult", 1.0))
	out["distance"] = float(out["distance"]) * float(mods.get("distance_mult", 1.0))
	out["cooldown"] = maxf(1.0, float(out["cooldown"]) * float(mods.get("cooldown_mult", 1.0)))
	return out

## 强化文案（卡片上的「✦ 道统契合：…」一行），未强化返回空串
static func enhance_desc(skill_id: String, cid: String) -> String:
	var cdef: Dictionary = CultivatorData.get_def(cid)
	var mods: Dictionary = Dictionary(cdef.get("skill_mods", {})).get(skill_id, {})
	if mods.is_empty():
		return ""
	var def: Dictionary = get_def(skill_id)
	var parts: Array[String] = []
	if mods.has("distance_mult"):
		parts.append("冲刺距离 +%d%%" % int(round((float(mods["distance_mult"]) - 1.0) * 100.0)))
	if mods.has("duration_add"):
		var unit := "无敌" if int(def.get("kind", 0)) == Kind.IFRAME else "持续"
		parts.append("%s +%.1f 秒" % [unit, float(mods["duration_add"])])
	if mods.has("power_mult"):
		var base := float(def.get("power", 0.0)) * 100.0
		var final := base * float(mods["power_mult"])
		match int(def.get("kind", 0)):
			Kind.SPEED:
				parts.append("移速加成 %d%%→%d%%" % [int(round(base)), int(round(final))])
			Kind.HASTE:
				parts.append("间隔缩减 %d%%→%d%%" % [int(round(base)), int(round(final))])
			Kind.HEAL:
				parts.append("回复量 %d%%→%d%%" % [int(round(base)), int(round(final))])
	if mods.has("cooldown_mult"):
		parts.append("冷却 -%d%%" % int(round((1.0 - float(mods["cooldown_mult"])) * 100.0)))
	return "、".join(parts)
