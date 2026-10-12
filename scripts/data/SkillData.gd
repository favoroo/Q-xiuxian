class_name SkillData
extends RefCounted

## 随行神通数据库：每局选定道统后择一携带，战斗右侧按钮手动释放，带冷却。
## 冷却从「效果活跃窗口走完」起算（不是按下那帧）：加速/急速/无敌的窗口 = duration，
## 冲刺的窗口 = iframe 无敌时长，治疗瞬发窗口为 0（按下即进冷却）。
## 另有一类「额外技能」：随角色绑定（CultivatorData 的 extra_skill 键）、不走选择界面，
## 也登记在本表用 Kind 区分（如影爆——免冷却，由资源层门控而非 CD）。
## 角色专属强化写在 CultivatorData.DEFS[cid]["skill_mods"][skill_id]，
## 卡片文案与实战数值都走 final_stats() 合并结果（唯一真话），别处不抄数字。
## skill_mods 支持的键：
##   duration_add  —— 持续/无敌秒数加算（石岳：金光护体 +1.0s；对冲刺 = 无敌窗口加时）
##   power_mult    —— 效果强度乘算（移速加成 / 间隔减免 / 回血比例）
##   distance_mult —— 冲刺距离乘算（魅影：+55%）
##   cooldown_mult —— 冷却乘算（多宝/符阵/夺舍：0.65）
## glyph: 占位符文单字（正式图标走 media-gen 生成后填 icon 路径替换）

enum Kind { DASH, SPEED, HASTE, IFRAME, HEAL, BURST }

const DEFS: Dictionary = {
		"dash": {
			"name": "冲刺",
			"glyph": "冲",
			"icon": "res://assets/art/skill_dash.png",
			"kind": Kind.DASH,
			"cooldown": 4.0,      # 全技能最短冷却（其余 9/11/10/20），冲刺是走位主手段不是保命大招
			"duration": 0.16,     # 冲刺位移耗时（秒）
			"iframe": 0.30,       # 无敌总时长（秒）：覆盖位移全程 + 落地脱身余量，落地贴脸啃不动
			"distance": 150.0,    # 冲刺距离（像素）—— 落地即收速，纸面值≈实际位移（见 Player.DASH_LANDING_SPEED_MUL）
			"crit_window": 2.0,   # 冲刺后必定暴击窗口（秒）：起跳即计时，覆盖冲刺与落地追击
			"desc": "向当前方向冲刺，冲刺及落地后0.3秒内无敌，冲刺后2秒内攻击必定暴击",
		},
		"shadowburst": {
			"name": "影爆",
			"glyph": "爆",
			"icon": "",           # 占位字面上键（正式图标走 media-gen 生成后填路径）
			"kind": Kind.BURST,
			"cooldown": 0.0,      # 免冷却：门控是影层本身——没攒上层按不动，攒上随时能放
			"duration": 0.0,
			"desc": "踩碎攒下的影层：把躲掉的伤害按 55% 还给周身敌人并推开，每层再加一段无敌",
		},
		"elixir": {
			"name": "服丹",
			"glyph": "丹",
			"icon": "",           # 占位字面上键（正式图标走 media-gen 生成后填路径）
			"kind": Kind.BURST,
			"cooldown": 0.0,      # 免冷却：门控是药池本身——池空按不动，有存量随时能喝
			"duration": 0.0,
			"desc": "服下存好的药力回一大口气血，并短时提升全部法器伤害",
		},
		"gale": {
			"name": "加速",
			"glyph": "行",
			"icon": "res://assets/art/skill_gale.png",
			"kind": Kind.SPEED,
			"cooldown": 9.0,
			"duration": 4.0,
			"power": 0.60,        # 移速加成比例
			"dodge_add": 0.50,    # 期间闪避率提升（abs/abs，进 get_effective_dodge 硬上限）
			"desc": "移速提升60%，闪避率提升50%，持续4秒",
		},
		"haste": {
			"name": "急速",
			"glyph": "快",
			"icon": "res://assets/art/skill_haste.png",
			"kind": Kind.HASTE,
			"cooldown": 11.0,
			"duration": 5.0,
			"power": 0.30,        # 攻击间隔缩减比例
			"desc": "攻击间隔缩短30%，持续5秒",
		},
		"aegis": {
			"name": "无敌",
			"glyph": "盾",
			"icon": "res://assets/art/skill_aegis.png",
			"kind": Kind.IFRAME,
			"cooldown": 10.0,
			"duration": 2.0,
			"knockback_boost": 3.0,  # 期间法器击退力度倍率（knockback_force 消费，到期回 1.0）
			"desc": "短时间内不受任何伤害，期间法器击退力度提升至3倍",
		},
		"renewal": {
			"name": "治疗",
			"glyph": "治",
			"icon": "res://assets/art/skill_renewal.png",
			"kind": Kind.HEAL,
			"cooldown": 20.0,
			"power": 0.35,        # 回复最大气血比例（单口须压过回气丹 50% 的体感线，商人/药王契合后 5 成以上）
			"pet_heal_pct": 0.02, # 灵兽每秒回复最大气血比例
			"pet_duration": 8.0,  # 灵兽存活时长（秒），重施替换旧灵
			"desc": "立即回复35%最大生命，并召唤灵兽每秒回复2%最大生命，持续8秒",
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

## 基础值 + 角色强化合并：{kind, cooldown, duration, power, distance, iframe, dodge_add, crit_window, knockback_boost, pet_heal_pct, pet_duration}
## 冷却语义：效果活跃窗口（duration / 冲刺=iframe）走完才进冷却，cooldown 是「结束后」的等待值
static func final_stats(skill_id: String, cid: String) -> Dictionary:
	var def: Dictionary = get_def(skill_id)
	if def.is_empty():
		return {}
	var out: Dictionary = {
		"kind": int(def.get("kind", 0)),
		"cooldown": float(def.get("cooldown", 10.0)),
		"duration": float(def.get("duration", 0.0)),
		"iframe": float(def.get("iframe", 0.0)),
		"power": float(def.get("power", 0.0)),
		"distance": float(def.get("distance", 0.0)),
		"dodge_add": float(def.get("dodge_add", 0.0)),
		"crit_window": float(def.get("crit_window", 0.0)),
		"knockback_boost": float(def.get("knockback_boost", 1.0)),
		"pet_heal_pct": float(def.get("pet_heal_pct", 0.0)),
		"pet_duration": float(def.get("pet_duration", 0.0)),
	}
	var cdef: Dictionary = CultivatorData.get_def(cid)
	var mods: Dictionary = Dictionary(cdef.get("skill_mods", {})).get(skill_id, {})
	# 冲刺的 duration 只管位移耗时，duration_add 改走无敌窗口（对冲刺 = 无敌加时）
	if int(out["kind"]) == Kind.DASH:
		out["iframe"] = float(out["iframe"]) + float(mods.get("duration_add", 0.0))
	else:
		out["duration"] = float(out["duration"]) + float(mods.get("duration_add", 0.0))
	out["power"] = float(out["power"]) * float(mods.get("power_mult", 1.0))
	out["distance"] = float(out["distance"]) * float(mods.get("distance_mult", 1.0))
	# 影爆免冷却（门控是影层层数本身），不吃 maxf(1.0) 的冷却下限，也不吃角色 cooldown_mult
	if int(out["kind"]) == Kind.BURST:
		out["cooldown"] = 0.0
	else:
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
		var kind := int(def.get("kind", 0))
		var unit := "无敌" if kind == Kind.IFRAME or kind == Kind.DASH else "持续"
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
