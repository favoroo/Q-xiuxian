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
				"name": "剑客",
				"epithet": "一剑在手，所向披靡",
				"icon": "res://assets/art/cultivator_jianchi_icon.png",
				"sprite": "res://assets/art/pawn_blue_8dir.png",
				"motion": "procedural",
				"render_style": "hollow_knight",
				"start_equip": "",
				"pros": ["剑系武器伤害 +35%", "初始暴击率 +15%"],
				"cons": ["商店只卖剑系武器，偶尔有其他"],
				"mods": {
					"crit_rate": 0.15,
					"tag_damage": {"sword": 0.35},
				},
				"allowed_tags": ["sword"],
				"locked_upgrades": [],
				"skill_mods": {"haste": {"duration_add": 2.5}},
			},
		"shiyue": {
			"name": "守卫",
			"epithet": "铁壁之躯，坚不可摧",
			"icon": "res://assets/art/cultivator_shiyue_icon.png",
			"sprite": "res://assets/art/cultivator_shiyue_8dir.png",
			"motion": "procedural",
			"render_style": "hollow_knight",
			"start_equip": "",
			"pros": ["最大生命 ×1.8", "初始护甲 +5", "受击100%反伤"],
			"cons": ["移速 -15%", "移速加点锁定，无法提升"],
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
			"name": "驯兽师",
			"epithet": "以多打少，游刃有余",
			"icon": "res://assets/art/cultivator_fuzhen_icon.png",
			"sprite": "res://assets/art/cultivator_fuzhen_8dir.png",
			"motion": "procedural",
			"render_style": "hollow_knight",
			"start_equip": "开局自带 2 只护蝶（召唤武器）",
			"pros": ["开局自带 2 只护蝶", "召唤羁绊门槛 -1（2件即激活3件效果）"],
			"cons": ["非护蝶武器伤害 -30%"],
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
			"name": "商人",
			"epithet": "精打细算，财源滚滚",
			"icon": "res://assets/art/cultivator_jinsuanpan_icon.png",
			"sprite": "res://assets/art/cultivator_jinsuanpan_8dir.png",
			"motion": "procedural",
			"render_style": "hollow_knight",
			"start_equip": "",
			"pros": ["初始收益 +16（每波白得更多金币与经验）", "商店全场永久八折（-20%）"],
			"cons": ["全武器伤害 -25%", "最大生命 -25%"],
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
			"name": "影者",
			"epithet": "来无影，去无踪",
			"icon": "res://assets/art/cultivator_meiying_icon.png",
			"sprite": "res://assets/art/cultivator_meiying_8dir.png",
			"motion": "procedural",
			"render_style": "hollow_knight",
			"start_equip": "",
			"pros": ["初始闪避 +30%", "闪避上限提升至 90%"],
			"cons": ["最大生命 -35%", "护甲加点锁定，无法提升"],
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
				"name": "狂战士",
				"epithet": "一刀开山，所向无敌",
				"icon": "res://assets/art/cultivator_dubi_icon.png",
				"sprite": "res://assets/art/cultivator_dubi_8dir.png",
				"motion": "procedural",
				"render_style": "hollow_knight",
				"start_equip": "",
				"pros": ["全武器伤害 ×1.65", "攻击间隔 -30%（极速出招）"],
				"cons": ["武器槽上限为 3"],
				"mods": {
					"damage_mult": 1.65,
					"haste_mult": 0.7,
					"weapon_slots_max": 3,
				},
				"allowed_tags": [],
				"locked_upgrades": [],
				"skill_mods": {"haste": {"power_mult": 1.45}},
			},
		"kuangzhan": {
			"name": "蛮兵",
			"epithet": "敌越多，战越狂",
			"icon": "res://assets/art/cultivator_kuangzhan_icon.png",
			"sprite": "res://assets/art/cultivator_kuangzhan_8dir.png",
			"motion": "procedural",
			"render_style": "hollow_knight",
			"start_equip": "",
			"pros": ["全武器伤害 +30%", "敌潮规模 +50%（更多击杀与金币）"],
			"cons": ["每波结束损失 3 点收益"],
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
			"name": "学者",
			"epithet": "进步神速，一日千里",
			"icon": "res://assets/art/cultivator_duoshe_icon.png",
			"sprite": "res://assets/art/cultivator_duoshe_8dir.png",
			"motion": "procedural",
			"render_style": "hollow_knight",
			"start_equip": "",
			"pros": ["升级所需经验 -40%（升级更快）"],
			"cons": ["商店全场物价 +50%"],
			"mods": {
				"xp_require_mult": 0.6,
				"shop_price": 1.5,
			},
			"allowed_tags": [],
			"locked_upgrades": [],
			"skill_mods": {"renewal": {"cooldown_mult": 0.65}},
		},
		"duobao": {
			"name": "收藏家",
			"epithet": "琳琅满目，应有尽有",
			"icon": "res://assets/art/cultivator_duobao_icon.png",
			"sprite": "res://assets/art/cultivator_duobao_8dir.png",
			"motion": "procedural",
			"render_style": "hollow_knight",
			"start_equip": "",
			"pros": ["商店多 1 格（共 6 格）", "道具价格永久 -25%"],
			"cons": ["全武器伤害 -20%"],
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

static func get_visual_config(id: String) -> CultivatorVisualConfig:
	return CultivatorVisualConfig.get_config(id)

