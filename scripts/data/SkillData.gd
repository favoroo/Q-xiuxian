class_name SkillData
extends RefCounted

## 随行技能数据库：每局选定道统后择一携带，战斗右侧按钮手动释放，带冷却。
## 冷却从「效果活跃窗口走完」起算（不是按下那帧）：疾行/急速/无敌的窗口 = duration，
## 闪避的窗口 = iframe 无敌时长，治疗瞬发窗口为 0（按下即进冷却）。
## 另有一类「额外技能」：随角色绑定（CultivatorData 的 extra_skill 键）、不走选择界面，
## 也登记在本表用 Kind 区分（如影爆——免冷却，由资源层门控而非 CD）。
## 所有角色均可自由搭配随行技能，无角色针对性绑定，各技能基础数值均已全面强化。
## glyph: 占位符文单字（正式图标走 media-gen 生成后填 icon 路径替换）

enum Kind { DASH, SPEED, HASTE, IFRAME, HEAL, BURST }

const DEFS: Dictionary = {
		"dash": {
		"name": "闪避",
		"glyph": "闪",
			"icon": "res://assets/art/skill_dash.png",
			"kind": Kind.DASH,
			"cooldown": 3.0,      # 全技能最短冷却，闪避是走位主手段不是保命大招
			"duration": 0.16,     # 闪避位移耗时（秒）
			"iframe": 0.35,       # 无敌总时长（秒）：覆盖位移全程 + 落地脱身余量
			"distance": 110.0,    # 闪避距离（像素）
			# 落地震开（2026-10-24 用户现场：闪到怪脸上，无敌一结束就立刻吃接触伤）。
			# 位移走受击硬直滑行段（初速按 KNOCKBACK_DECAY_STUN=12 指数急刹），
			# 520 初速的净位移 ≈ 520 × (1-e^(-12×0.20)) / 12 ≈ 36px；定身时长盖过落地后剩余的 ~0.19s 无敌。
			"land_push_radius": 76.0,  # 落点震开判定半径（像素）：同时是环特效半径（画多大 == 判多大）
			"land_push_impulse": 520.0, # 落点震开初速（px/s，精英 ×0.55、Boss ×0.18）
			"land_push_stun": 0.20,    # 落点震开定身时长（秒）：受击硬直滑行段没有硬直就没有位移
			"crit_window": 1.0,   # 闪避后必定暴击窗口（秒）
			"attack_reset": 1,    # 落地即重置所有在役武器的攻击间隔（技能重置普攻，落地那一拍立刻出手）
			"desc": "向当前方向闪避，短暂无敌；落地震开贴身敌人，之后 1 秒内攻击必定暴击，并重置全部武器攻击间隔",
		},
		"shadowburst": {
			"name": "影爆",
			"glyph": "爆",
			"icon": "",           # 占位字面上键（正式图标走 media-gen 生成后填路径）
			"kind": Kind.BURST,
			"cooldown": 0.0,      # 免冷却：门控是影层本身——没攒上层按不动，攒上随时能放
			"duration": 0.0,
			"desc": "踩碎闪避攒下的影层：把躲掉的伤害还给周身敌人并推开，每层附带短暂无敌",
		},
		"elixir": {
			"name": "药爆",
			"glyph": "爆",
			"icon": "",           # 占位字面上键（正式图标走 media-gen 生成后填路径）
			"kind": Kind.HEAL,
			"cooldown": 10.0,     # 带冷却：摔碎药罐回血并伤敌，到期即可再放
			"duration": 0.0,
			"desc": "摔碎药罐：回复生命，药雾对周身敌人造成一次性毒伤并短时增伤",
		},
		"gale": {
			"name": "疾行",
			"glyph": "行",
			"icon": "res://assets/art/skill_gale.png",
			"kind": Kind.SPEED,
			"cooldown": 7.5,
			"duration": 4.5,
			"power": 0.80,        # 移速加成比例
			"dodge_add": 0.60,    # 期间闪避率提升（abs/abs，进 get_effective_dodge 硬上限）
			"desc": "移速提升80%，闪避率提升60%，持续4.5秒",
		},
		"haste": {
			"name": "急速",
			"glyph": "快",
			"icon": "res://assets/art/skill_haste.png",
			"kind": Kind.HASTE,
			"cooldown": 8.5,
			"duration": 5.0,
			"power": 0.40,        # 攻击间隔缩减比例
			"desc": "攻击间隔缩短40%，持续5秒",
		},
			"aegis": {
				"name": "无敌",
				"glyph": "盾",
				"icon": "res://assets/art/skill_aegis.png",
				"kind": Kind.IFRAME,
				"cooldown": 8.0,
				"duration": 2.5,
				"knockback_boost": 3.0,   # 期间武器击退力度倍率
				"lifesteal_boost": 0.50,  # 期间吸血触发概率加法加成（与加点/道具同一口径，每次仍回 1 点）
				"desc": "震开周身敌人并不受伤害，期间武器吸血提升50%，击退提升至3倍，持续2.5秒",
			},
		"renewal": {
			"name": "治疗",
			"glyph": "治",
			"icon": "res://assets/art/skill_renewal.png",
			"kind": Kind.HEAL,
			"cooldown": 15.0,
		"power": 0.40,        # 回复最大生命比例
		"pet_heal_pct": 0.025, # 灵兽每秒回复最大生命比例
			"pet_duration": 8.0,  # 灵兽存活时长（秒），重施替换旧灵
			"desc": "立即回复40%最大生命，并召唤灵兽每秒回复2.5%最大生命，持续8秒",
		},
}

## 技能卡横排顺序（也是选择界面的展示顺序）
const OFFER_IDS: Array = ["dash", "gale", "haste", "aegis", "renewal"]

static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, {})

static func all_ids() -> Array:
	return DEFS.keys()

## 角色是否强化该技能（已废弃：全角色自由搭配，统一返回 false）
static func is_enhanced_for_cultivator(_skill_id: String, _cid: String) -> bool:
	return false

## 基础值 + 道具合并：{kind, cooldown, duration, power, distance, iframe, dodge_add, crit_window, attack_reset, knockback_boost, lifesteal_boost, pet_heal_pct, pet_duration, land_push_radius, land_push_impulse, land_push_stun}
## 冷却语义：效果活跃窗口（duration / 闪避=iframe）走完才进冷却，cooldown 是「结束后」的等待值
static func final_stats(skill_id: String, _cid: String = "") -> Dictionary:
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
		"attack_reset": int(def.get("attack_reset", 0)),
		"knockback_boost": float(def.get("knockback_boost", 1.0)),
		"lifesteal_boost": float(def.get("lifesteal_boost", 0.0)),
		"pet_heal_pct": float(def.get("pet_heal_pct", 0.0)),
		"pet_duration": float(def.get("pet_duration", 0.0)),
		"land_push_radius": float(def.get("land_push_radius", 0.0)),
		"land_push_impulse": float(def.get("land_push_impulse", 0.0)),
		"land_push_stun": float(def.get("land_push_stun", 0.0)),
	}
	# 技能冷却缩减：加点/新道具走正式属性，旧凝神符仍走 item hook；两腿相加后统一夹顶。
	var cd_reduction := minf(GameManager.SKILL_CD_CAP,
			GameManager.skill_cooldown_mult + GameManager.item_hook_sum("skill_cooldown_mult"))
	var cd_mult := 1.0 - cd_reduction
	# 影爆免冷却（门控是影层层数本身），不吃 maxf(1.0) 的冷却下限
	if int(out["kind"]) == Kind.BURST:
		out["cooldown"] = 0.0
	else:
		out["cooldown"] = maxf(1.0, float(out["cooldown"]) * maxf(0.2, cd_mult))
	return out

## 强化文案（已废弃：全角色自由搭配，统一返回空串）
static func enhance_desc(_skill_id: String, _cid: String) -> String:
	return ""
