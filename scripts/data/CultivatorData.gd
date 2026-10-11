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
## extra_skill: "skill_id"                      —— 随角色绑定的「额外技能」（独立于五选一神通，HUD 第二颗按钮释放；
##                                                 缺省 = 该角色无额外技能，按钮隐藏。免冷却类由资源门控，见 SkillData.BURST）
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
				"start_equip": "开局自带 2 只★2 双生护蝶（4 具环绕灵宝）",
				"pros": ["开局自带 2 只★2 双生护蝶", "灵宝伤害 +12% · 召唤伤害 +2", "召唤羁绊门槛 -1（1/3/5 件成档，原 2/4/6）"],
				"cons": ["非召唤类法器伤害 -30%"],
				"mods": {
				"start_drones": 2,
				"start_drone_star": 2,
				"spirit_threshold_adj": 1,
				"engineering": 2.0,
				"tag_damage": {"spirit": 0.12},
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
			"pros": ["初始闪避 +30%", "闪避上限提升至 90%", "最大生命 ×1.3、每秒回复 +1.5", "闪避攒「影」：每层 +5% 法器伤害（至多 8 层），按「影爆」随时爆发还回去"],
			"cons": ["全武器伤害 -20%", "护甲加点锁定，无法提升"],
			"mods": {
				"dodge": 0.30,
				"dodge_cap": 0.30,
				"hp_mult": 1.30,
				"hp_regen": 1.5,
				"damage_mult": 0.80,
			},
			"allowed_tags": [],
			"locked_upgrades": ["armor_up"],
			"skill_mods": {"dash": {"distance_mult": 1.55}},
			"extra_skill": "shadowburst",
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
			"lingzhifu": {
				"name": "灵植夫",
				"epithet": "灵田百亩，春华秋实",
				"icon": "res://assets/art/cultivator_lingzhifu_icon.png",
				"sprite": "res://assets/art/pawn_blue_8dir.png",
				"motion": "procedural",
				"render_style": "hollow_knight",
				"start_equip": "",
				"pros": ["初始收益 +12（每波白得更多金币与经验）"],
				"cons": ["全武器伤害 -15%"],
				"mods": {
					"harvest": 12.0,
					"damage_mult": 0.85,
				},
				"allowed_tags": [],
				"locked_upgrades": [],
				"skill_mods": {"gale": {"duration_add": 1.5}},
			},
			"leifa": {
				"name": "雷法真君",
				"epithet": "天雷引动，万法归一",
				"icon": "res://assets/art/cultivator_leifa_icon.png",
				"sprite": "res://assets/art/pawn_blue_8dir.png",
				"motion": "procedural",
				"render_style": "hollow_knight",
				"start_equip": "",
				"pros": ["初始元素伤害 +3", "范围与弹射武器伤害 +30%"],
				"cons": ["剑系武器伤害 -40%"],
				"mods": {
					"elemental": 3.0,
					"tag_damage": {"thunder": 0.30, "talisman": 0.30, "sword": -0.40},
				},
				"allowed_tags": ["thunder", "talisman"],
				"locked_upgrades": [],
				"skill_mods": {"haste": {"power_mult": 1.3}},
			},
			"jiguan": {
				"name": "机关师",
				"epithet": "千机百炼，甲阵通神",
				"icon": "res://assets/art/cultivator_jiguan_icon.png",
				"sprite": "res://assets/art/pawn_blue_8dir.png",
				"motion": "procedural",
				"render_style": "hollow_knight",
				"start_equip": "",
				"pros": ["初始召唤伤害 +3", "机关羁绊门槛 -1（1/3/5 件成档，原 2/4/6）"],
				"cons": ["非机关与非召唤武器伤害 -25%"],
				"mods": {
					"engineering": 3.0,
					"contraption_threshold_adj": 1,
					"non_contraption_damage": -0.25,
				},
				"allowed_tags": ["contraption", "spirit"],
				"locked_upgrades": [],
				"skill_mods": {"aegis": {"duration_add": 1.0}},
			},
			"yaowang": {
				"name": "药王",
				"epithet": "悬壶济世，金针度人",
				"icon": "res://assets/art/cultivator_yaowang_icon.png",
				"sprite": "res://assets/art/pawn_blue_8dir.png",
				"motion": "procedural",
				"render_style": "hollow_knight",
				"start_equip": "",
				"pros": ["初始生命回复 +2.5/秒"],
				"cons": ["全武器伤害 -20%", "初始护甲 -2"],
				"mods": {
					"hp_regen": 2.5,
					"damage_mult": 0.80,
					"armor": -2.0,
				},
				"allowed_tags": [],
				"locked_upgrades": [],
				"skill_mods": {"renewal": {"power_mult": 1.5}},
			},
			"shoucainu": {
				"name": "守财奴",
				"epithet": "寸利必争，金山积垒",
				"icon": "res://assets/art/cultivator_shoucainu_icon.png",
				"sprite": "res://assets/art/pawn_blue_8dir.png",
				"motion": "procedural",
				"render_style": "hollow_knight",
				"start_equip": "",
				"pros": ["每波结束随身金币结息 +8%（最多 15 枚）"],
				"cons": ["全武器伤害 -10%", "初始收益 -5"],
				"mods": {
					"stone_interest_rate": 0.08,
					"stone_interest_cap": 15,
					"damage_mult": 0.90,
					"harvest": -5.0,
				},
				"allowed_tags": [],
				"locked_upgrades": [],
				"skill_mods": {"dash": {"cooldown_mult": 0.80}},
			},
			"shixue": {
				"name": "嗜血魔修",
				"epithet": "以痛为引，煞血滔天",
				"icon": "res://assets/art/cultivator_shixue_icon.png",
				"sprite": "res://assets/art/pawn_blue_8dir.png",
				"motion": "procedural",
				"render_style": "hollow_knight",
				"start_equip": "",
				"pros": ["受击后 5 秒内全伤害 +3%（最多叠 10 层）"],
				"cons": ["初始护甲 -3"],
				"mods": {
					"armor": -3.0,
					"on_hit_damage_bonus": 0.03,
					"on_hit_damage_cap_stacks": 10,
				},
				"allowed_tags": [],
				"locked_upgrades": [],
				"skill_mods": {"haste": {"power_mult": 1.40}},
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

## 随角色绑定的额外技能 id（独立于五选一神通）；没配 extra_skill 的角色返回空串
static func get_extra_skill_id(id: String) -> String:
	return String(get_def(id).get("extra_skill", ""))

static func get_visual_config(id: String) -> CultivatorVisualConfig:
	return CultivatorVisualConfig.get_config(id)

