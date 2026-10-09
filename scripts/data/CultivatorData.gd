class_name CultivatorData
extends RefCounted

## 修士流派数据库：不对称设计——每名修士都是「超能力 + 严苛负面代偿」（仿土豆兄弟角色设计）
## mods 支持的键：
##   crit_rate / armor / harvest / thorns / dodge          —— 直接加算
##   speed_mult / damage_mult / hp_mult / shop_price / haste_mult —— 乘算系数
##   tag_damage: {tag: bonus}                   —— 指定流派法器伤害加成
##   non_drone_damage                           —— 非灵蝶法器伤害修正（负值为惩罚）
##   start_drones                               —— 开局自带灵蝶数
##   spirit_threshold_adj                       —— 御灵羁绊门槛下移
##   dodge_cap                                  —— 闪避硬上限上移（魅影：0.6 → 0.9）
##   weapon_slots_max                           —— 上阵法器槽位上限覆盖（独臂刀圣：3）
##   enemy_count_mult                           —— 妖潮规模倍率（狂战蛮修：1.5）
##   harvest_decay                              —— 每波灵韵流失点数（狂战蛮修：3）
##   xp_require_mult                            —— 升级修为需求倍率（夺舍散人：0.6）
##   item_price                                 —— 法宝价格乘区（多宝道人：0.75）
##   shop_slots                                 —— 货架格数加成（多宝道人：+1）
## skill_mods: {skill_id: {...}}                —— 随行神通专属强化（键位见 SkillData 头注；数值合并唯一入口 SkillData.final_stats）
## allowed_tags: 非空时商店大幅偏向这些流派的法器，但仍有少量其他法器漏出；locked_upgrades: 锁死的加点项
## sprite: 角色独立 8 方向行走图（5 行 × 5 列，192px/格，行序见 RunMotion.DIR_ROW）；缺图回退 pawn_blue_8dir
## motion: 移动方式（缺省 "gait" 步态腿帧；"hover" 御剑/悬浮——单姿势图集 + RunMotion.apply_hover 程序驱动浮沉）

const DEFS: Dictionary = {
		"jianchi": {
			"name": "剑痴·独孤",
			"epithet": "一人一剑，不问苍生",
			"icon": "res://assets/art/cultivator_jianchi_icon.png",
			"sprite": "res://assets/art/pawn_blue_8dir.png",
			"motion": "hover",
			"start_equip": "",
			"pros": ["剑系法器伤害 +60%", "初始暴击率 +15%"],
			"cons": ["此生只执剑：商店以剑系法器为主，偶有他派漏出"],
			"mods": {
				"crit_rate": 0.15,
				"tag_damage": {"sword": 0.6},
			},
			"allowed_tags": ["sword"],
			"locked_upgrades": [],
			"skill_mods": {"haste": {"duration_add": 2.5}},
		},
		"shiyue": {
			"name": "石岳·体修",
			"epithet": "肉身成圣，岿然如山",
			"icon": "res://assets/art/cultivator_shiyue_icon.png",
			"sprite": "res://assets/art/cultivator_shiyue_8dir.png",
			"motion": "hover",
			"start_equip": "",
			"pros": ["气血上限 ×1.8", "初始护甲 +5", "受击全额反震（100%敌方攻击力）"],
			"cons": ["基础移速 -15%", "无法领悟神行符（移速加点锁死）"],
			"mods": {
				"hp_mult": 1.8,
				"armor": 5.0,
				"thorns": 1.0,
				"speed_mult": 0.85,
			},
			"allowed_tags": [],
			"locked_upgrades": ["speed_up"],
			"skill_mods": {"aegis": {"duration_add": 1.0}},
		},
		"fuzhen": {
			"name": "符阵灵童",
			"epithet": "御灵驱蝶，以众凌寡",
			"icon": "res://assets/art/cultivator_fuzhen_icon.png",
			"sprite": "res://assets/art/cultivator_fuzhen_8dir.png",
			"motion": "hover",
			"start_equip": "开局额外自带 2 只「灵蝶」（御灵法器）协同作战",
			"pros": ["御灵羁绊激活门槛 -1（2件即激活3件御灵羁绊）"],
			"cons": ["非灵蝶法器伤害 -30%"],
			"mods": {
				"start_drones": 2,
				"spirit_threshold_adj": 1,
				"non_drone_damage": -0.3,
			},
			"allowed_tags": [],
			"locked_upgrades": [],
			"skill_mods": {"dash": {"cooldown_mult": 0.65}},
		},
		"jinsuanpan": {
			"name": "散修·金算盘",
			"epithet": "灵田生金，以利证道",
			"icon": "res://assets/art/cultivator_jinsuanpan_icon.png",
			"sprite": "res://assets/art/cultivator_jinsuanpan_8dir.png",
			"motion": "hover",
			"start_equip": "",
			"pros": ["初始灵韵 +16（波末白得丰厚灵石）", "灵石阁全场商品永久八折（-20%）"],
			"cons": ["全法器伤害 -25%", "气血上限 -25%"],
			"mods": {
				"harvest": 16.0,
				"shop_price": 0.8,
				"damage_mult": 0.75,
				"hp_mult": 0.75,
			},
			"allowed_tags": [],
			"locked_upgrades": [],
			"skill_mods": {"renewal": {"power_mult": 1.6}},
		},
		"meiying": {
			"name": "魅影·幽娘",
			"epithet": "来无影，去无踪",
			"icon": "res://assets/art/cultivator_meiying_icon.png",
			"sprite": "res://assets/art/cultivator_meiying_8dir.png",
			"motion": "hover",
			"start_equip": "",
			"pros": ["初始闪避 +30%", "闪避上限由 60% 提升至 90%"],
			"cons": ["气血上限 -35%", "肉身孱弱：无法领悟罡气护体（护甲锁死）"],
			"mods": {
				"dodge": 0.30,
				"dodge_cap": 0.30,
				"hp_mult": 0.65,
			},
			"allowed_tags": [],
			"locked_upgrades": ["armor_up"],
			"skill_mods": {"dash": {"distance_mult": 1.55}},
		},
			"dubi": {
				"name": "独臂刀圣",
				"epithet": "一臂一刀，足以开山",
				"icon": "res://assets/art/cultivator_dubi_icon.png",
				"sprite": "res://assets/art/cultivator_dubi_8dir.png",
				"motion": "hover",
				"start_equip": "",
				"pros": ["全法器伤害 ×2.0（伤害翻倍）", "攻击间隔 -30%（极速出刀）"],
				"cons": ["独臂御器：上阵法器槽上限为 3"],
				"mods": {
					"damage_mult": 2.0,
					"haste_mult": 0.7,
					"weapon_slots_max": 3,
				},
				"allowed_tags": [],
				"locked_upgrades": [],
				"skill_mods": {"haste": {"power_mult": 1.45}},
			},
		"kuangzhan": {
			"name": "狂战蛮修",
			"epithet": "妖越多，血越热",
			"icon": "res://assets/art/cultivator_kuangzhan_icon.png",
			"sprite": "res://assets/art/cultivator_kuangzhan_8dir.png",
			"motion": "hover",
			"start_equip": "",
			"pros": ["全法器伤害 +30%", "妖潮规模 +50%（更多击杀与灵石掉落）"],
			"cons": ["杀气冲天：每波结束灵韵流失 3 点"],
			"mods": {
				"damage_mult": 1.3,
				"enemy_count_mult": 1.5,
				"harvest_decay": 3.0,
			},
			"allowed_tags": [],
			"locked_upgrades": [],
			"skill_mods": {"gale": {"power_mult": 1.583}},
		},
		"duoshe": {
			"name": "夺舍散人",
			"epithet": "借壳修身，一日千里",
			"icon": "res://assets/art/cultivator_duoshe_icon.png",
			"sprite": "res://assets/art/cultivator_duoshe_8dir.png",
			"motion": "hover",
			"start_equip": "",
			"pros": ["升级所需修为 -40%（悟道加点一日千里）"],
			"cons": ["臭名远扬：灵石阁全场物价 +50%"],
			"mods": {
				"xp_require_mult": 0.6,
				"shop_price": 1.5,
			},
			"allowed_tags": [],
			"locked_upgrades": [],
			"skill_mods": {"renewal": {"cooldown_mult": 0.65}},
		},
		"duobao": {
			"name": "多宝道人",
			"epithet": "法宝傍身，琳琅满目",
			"icon": "res://assets/art/cultivator_duobao_icon.png",
			"sprite": "res://assets/art/cultivator_duobao_8dir.png",
			"motion": "hover",
			"start_equip": "",
			"pros": ["灵石阁货架 +1 格（共 6 格）", "被动法宝价格永久 -25%"],
			"cons": ["疏于炼器：全法器伤害 -20%"],
			"mods": {
				"shop_slots": 1,
				"item_price": 0.75,
				"damage_mult": 0.8,
			},
			"allowed_tags": [],
			"locked_upgrades": [],
			"skill_mods": {"aegis": {"cooldown_mult": 0.65}},
		},
}

static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, {})

static func all_ids() -> Array:
	return DEFS.keys()

static func get_start_equip(id: String) -> String:
	return String(get_def(id).get("start_equip", ""))

static func get_synergy_skill_id(id: String) -> String:
	var s_mods: Dictionary = get_def(id).get("skill_mods", {})
	if s_mods.is_empty():
		return ""
	return String(s_mods.keys()[0])
