class_name CultivatorData
extends RefCounted

## 角色流派数据库：不对称设计——每名角色都是「超能力 + 严苛负面代偿」（仿土豆兄弟角色设计）
## mods 支持的键：
##   crit_rate / armor / harvest / thorns / dodge          —— 直接加算
##   speed_mult / damage_mult / hp_mult / shop_price / haste_mult —— 乘算系数
##   tag_damage: {tag: bonus}                   —— 指定流派武器伤害加成
##   non_tag_damage: {tag: bonus}               —— 不带指定 tag 的武器伤害修正（负值为惩罚，符修/霸王的代偿）
##   non_drone_damage                           —— 非灵蝶武器伤害修正（负值为惩罚）
##   start_drones                               —— 开局自带灵蝶数
##   spirit_threshold_adj                       —— 御灵羁绊门槛下移
##   dodge_cap                                  —— 闪避硬上限上移（魅影：0.6 → 0.9）
##   weapon_slots_max                           —— 上阵武器槽位上限覆盖（独臂刀圣：3）
##   enemy_count_mult                           —— 敌潮规模倍率（狂战蛮修：1.5）
##   harvest_decay                              —— 每回合灵韵流失点数（狂战蛮修：3）
##   xp_require_mult                            —— 升级经验需求倍率（夺舍散人：0.6）
##   item_price                                 —— 道具价格乘区（多宝道人：0.75）
##   shop_slots                                 —— 货架格数加成（多宝道人：+1）
##   guard_stance                               —— 盾势机制开关（守卫：受击蓄能满自动爆发，数值全在 GuardStanceData）
##   heal_orb_chance / heal_overflow_mult       —— 灵植夫：敌人额外掉回复珠概率 / 回复珠溢出折金币倍率
##   alloc_offer_bonus / alloc_free_reroll_bonus —— 学者：悟道候选数 / 每回合免费刷新加成
##   collection_damage_per_unique               —— 收藏家：每持有一种不同道具的全伤害加成
##   frenzy                                     —— 战意机制开关（狂战士：击杀攒层增伤、停杀流失，数值全在 FrenzyData）
##   free_rerolls                               —— 每回合商店免费重掷次数（商人：+1，走 ShopSystem 既有免单口径）
##   reroll_price                               —— 商店重掷费用乘区（商人：0.5 半价）
##   thunder_strike                             —— 天雷机制开关（雷法真君：周期落雷轰最近敌人，数值全在 ThunderData）
##   crowd_damage_per_enemy / crowd_damage_cap / crowd_damage_radius
##                                              —— 蛮兵·陷阵：感知圈内每只敌人的全伤害加成与上限（damage_mult 现算）
##   stone_damage_per_100 / stone_damage_cap    —— 守财奴·财可通神：每持 100 金币的全伤害加成与上限（damage_mult 现算）
##   kill_cd_reduction_normal / kill_cd_reduction_elite —— 绝尘·斩灭凝神：击杀普通怪/精英怪返还的技能冷却秒数
##   kuxingseng_mode / still_damage_bonus / still_haste_bonus / still_armor_bonus / still_pickup_bonus
##   / move_damage_penalty / move_haste_penalty —— 苦行僧：站定与移动不对称收益/惩罚
## skill_mods: {skill_id: {...}}                —— 随行技能专属强化（键位见 SkillData 头注；数值合并唯一入口 SkillData.final_stats）
## extra_skill: "skill_id"                      —— 随角色绑定的「额外技能」（独立于五选一技能，HUD 第二颗按钮释放；
##                                                 缺省 = 该角色无额外技能，按钮隐藏。免冷却类由资源门控，见 SkillData.BURST）
##                                                 它的玩法说明不写在本表：get_extra_desc() 现读那张机制表，
##                                                 卡面上单独成一段（不并进 pros 列表）
## allowed_tags: 非空时商店大幅偏向这些流派的武器，但仍有少量其他武器漏出；locked_upgrades: 锁死的加点项
## sprite: 角色独立 8 方向行走图（5 行 × 5 列，192px/格，行序见 RunMotion.DIR_ROW）；缺图回退 pawn_blue_8dir
## 【注意】发布包不含 *_8dir 帧集（export_presets.cfg exclude_filter 已排除，约 18MB 死重——
## 全员 procedural 渲染不加载图集）。未来新角色若真要启用图集渲染，先把排除名单里的
## *_8dir.png 两项移除，否则真机上 ResourceLoader.exists 直接失败、走 pawn_blue 兜底白模。
## motion: 移动方式（缺省 "gait" 步态腿帧；"hover" 御剑/悬浮——单姿势图集 + RunMotion.apply_hover 程序驱动浮沉）

const DEFS: Dictionary = {
			"jianchi": {
				"name": "剑士",
				"epithet": "一剑在手，所向披靡",
				"icon": "res://assets/art/cultivator_jianchi_icon.png",
				"sprite": "res://assets/art/pawn_blue_8dir.png",
				"motion": "procedural",
				"render_style": "hollow_knight",
					"start_equip": "",
					"pros": ["剑系武器伤害 +35%", "初始暴击率 +15%"],
					"cons": ["商店主要刷新剑系武器"],
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
				"pros": ["最大生命 ×1.8", "初始护甲 +5", "受击反伤 100%", "【盾势】蓄满护甲伤害后爆发击退周身敌人"],
				"cons": ["移速 -15%", "移速无法通过加点提升"],
			"mods": {
				"hp_mult": 1.8,
				"armor": 5.0,
				"thorns": 1.0,
				"speed_mult": 0.85,
				"guard_stance": 1.0,
			},
			"allowed_tags": [],
			"locked_upgrades": ["speed_up"],
			"skill_mods": {"aegis": {"duration_add": 1.0}},
		},
		"fuzhen": {
			"name": "灵蝶使",
			"epithet": "以多打少，游刃有余",
				"icon": "res://assets/art/cultivator_fuzhen_icon.png",
				"sprite": "res://assets/art/cultivator_fuzhen_8dir.png",
				"motion": "procedural",
				"render_style": "hollow_knight",
				"start_equip": "★2 护蝶 ×1",
				"pros": ["开局自带 ★2 护蝶", "召唤类武器伤害 +12%", "召唤伤害属性 +2", "召唤羁绊门槛 -1（1/3/5 件成档）"],
				"cons": ["非召唤类武器伤害 -30%"],
				"mods": {
					"start_drones": 1,
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
				"pros": ["初始收益 +16（每回合得更多金币与经验）", "商店全场永久 8 折", "每回合首次重掷免费，后续重掷半价"],
				"cons": ["全武器伤害 -25%", "最大生命 -25%"],
				"mods": {
					"harvest": 16.0,
					"shop_price": 0.8,
					"damage_mult": 0.75,
					"hp_mult": 0.75,
					"free_rerolls": 1,
					"reroll_price": 0.5,
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
				"pros": ["初始闪避 +30%，上限提至 90%", "最大生命 ×1.3，每秒回复 +1.5"],
				"cons": ["全武器伤害 -20%", "护甲无法通过加点提升"],
			"mods": {
				"dodge": 0.30,
				"dodge_cap": 0.30,
				"hp_mult": 1.30,
				"hp_regen": 1.5,
				"damage_mult": 0.80,
			},
			"allowed_tags": [],
			"locked_upgrades": ["armor_up"],
			"skill_mods": {"gale": {"dodge_add_mult": 2.0}},
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
					"pros": ["全武器伤害 ×1.5", "攻击间隔 -30%", "【战意】连续击杀大幅提升伤害"],
					"cons": ["最大武器槽限制为 3 格"],
					"mods": {
						"damage_mult": 1.5,
						"haste_mult": 0.7,
						"weapon_slots_max": 3,
						"frenzy": 1.0,
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
				"pros": ["全武器伤害 +30%", "敌人数量 +50%（更多击杀与金币）", "陷阵：周身敌人每只 +3% 全伤害（至多 +45%）"],
				"cons": ["每回合结算损失 3 点收益"],
				"mods": {
					"damage_mult": 1.3,
					"enemy_count_mult": 1.5,
					"harvest_decay": 3.0,
					"crowd_damage_per_enemy": 0.03,
					"crowd_damage_cap": 0.45,
					"crowd_damage_radius": 260.0,
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
				"pros": ["升级所需经验 -40%", "悟道候选 +1（每回合 6 选 1）", "每回合悟道免费刷新 +1"],
				"cons": ["商店物价 +50%"],
				"mods": {
					"xp_require_mult": 0.6,
					"shop_price": 1.5,
					"alloc_offer_bonus": 1,
					"alloc_free_reroll_bonus": 1,
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
				"pros": ["商店槽位 +1（共 6 格）", "道具价格永久 -25%", "每持有一种不同道具，全伤害 +2%"],
				"cons": ["全武器伤害 -20%"],
				"mods": {
					"shop_slots": 1,
					"item_price": 0.75,
					"damage_mult": 0.8,
					"collection_damage_per_unique": 0.02,
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
					"pros": ["初始收益 +12", "击杀额外掉落回复珠几率 +15%", "满血吃回复珠双倍转化为金币"],
					"cons": ["全武器伤害 -10%"],
				"mods": {
					"harvest": 12.0,
					"damage_mult": 0.90,
					"heal_orb_chance": 0.15,
					"heal_overflow_mult": 2.0,
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
					"pros": ["初始元素伤害 +3", "雷法与弹射武器伤害 +30%", "【天雷】自动落雷轰击敌人，受元素伤害加成"],
				"cons": ["剑系武器伤害 -40%"],
				"mods": {
					"elemental": 3.0,
					"tag_damage": {"thunder": 0.30, "talisman": 0.30, "sword": -0.40},
					"thunder_strike": 1.0,
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
						"pros": ["初始机关伤害 +3", "机关羁绊门槛 -1（1/3/5 件成档）"],
						"cons": ["非机关/非召唤武器伤害 -25%"],
						"mods": {
							"contraption": 3.0,
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
					"pros": ["初始每秒生命回复 +2.5"],
					"cons": ["全武器伤害 -20%", "初始护甲 -2"],
					"mods": {
						"hp_regen": 2.5,
						"damage_mult": 0.80,
						"armor": -2.0,
					},
					"allowed_tags": [],
					"locked_upgrades": [],
					"skill_mods": {"renewal": {"power_mult": 1.5}},
					"extra_skill": "elixir",
				},
				"shoucainu": {
					"name": "守财奴",
					"epithet": "寸利必争，金山积垒",
					"icon": "res://assets/art/cultivator_shoucainu_icon.png",
					"sprite": "res://assets/art/pawn_blue_8dir.png",
					"motion": "procedural",
					"render_style": "hollow_knight",
					"start_equip": "",
					"pros": ["每回合按持有的金币额外得 8% 金币（至多 +30）", "财可通神：每持 100 金币 +2% 全伤害（至多 +50%）"],
					"cons": ["全武器伤害 -10%", "初始收益 -5"],
					"mods": {
						"stone_interest_rate": 0.08,
						"stone_interest_cap": 30,
						"damage_mult": 0.90,
						"harvest": -5.0,
						"stone_damage_per_100": 0.02,
						"stone_damage_cap": 0.5,
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
					"pros": ["受击后 5 秒内全伤害 +3%（至多 10 层）"],
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
				"fuxiu": {
					"name": "灵符子",
					"epithet": "万符归宗，弹射无影",
					"icon": "res://assets/art/cultivator_fuxiu_icon.png",
					"sprite": "res://assets/art/pawn_blue_8dir.png",
					"motion": "procedural",
					"render_style": "hollow_knight",
					"start_equip": "",
					"pros": ["弹射类武器伤害 +35%", "初始元素伤害 +2"],
					"cons": ["非弹射类武器伤害 -25%", "商店主要刷新弹射类武器"],
					"mods": {
						"elemental": 2.0,
						"tag_damage": {"talisman": 0.35},
						"non_tag_damage": {"talisman": -0.25},
					},
					"allowed_tags": ["talisman"],
					"locked_upgrades": [],
					"skill_mods": {"haste": {"cooldown_mult": 0.7}},
				},
					"bawang": {
						"name": "霸王",
						"epithet": "横扫千军，所向披靡",
						"icon": "res://assets/art/cultivator_bawang_icon.png",
						"sprite": "res://assets/art/pawn_blue_8dir.png",
						"motion": "procedural",
						"render_style": "hollow_knight",
						"start_equip": "",
						"pros": ["横扫类武器伤害 +30%", "初始护甲 +2"],
						"cons": ["非横扫类武器伤害 -25%", "商店主要刷新横扫类武器"],
						"mods": {
							"armor": 2.0,
							"tag_damage": {"wide": 0.30},
							"non_tag_damage": {"wide": -0.25},
						},
						"allowed_tags": ["wide"],
						"locked_upgrades": [],
						"skill_mods": {"aegis": {"duration_add": 1.0}},
					},
				"juechen": {
					"name": "绝尘",
					"epithet": "一剑绝尘，万法无歇",
					"icon": "res://assets/art/cultivator_juechen_icon.png",
					"sprite": "res://assets/art/pawn_blue_8dir.png",
					"motion": "procedural",
					"render_style": "hollow_knight",
					"start_equip": "",
					"pros": ["击杀敌人减 0.4s 技能冷却（精英 -2.0s）", "技能持续期间击杀可预扣后续冷却"],
					"cons": ["全武器基础伤害 -20%", "最大生命 -15%"],
					"mods": {
						"damage_mult": 0.80,
						"hp_mult": 0.85,
						"kill_cd_reduction_normal": 0.4,
						"kill_cd_reduction_elite": 2.0,
					},
					"allowed_tags": ["sword"],
					"locked_upgrades": [],
					"skill_mods": {},
				},
					"yushou": {
						"name": "御兽师",
						"epithet": "万灵来朝，兽伴同行",
						"icon": "res://assets/art/cultivator_yushou_icon.png",
						"sprite": "res://assets/art/cultivator_fuzhen_8dir.png",
						"motion": "procedural",
						"render_style": "hollow_knight",
						"start_equip": "焰灵狐（随行灵兽）",
						"pros": ["开局自带随行灵兽（焰灵狐）", "灵兽栏位 +2（可同时配置 3 只）", "商店灵兽出现概率 +15%", "随行灵兽造成的伤害 +15%"],
						"cons": ["本体武器伤害 -10%"],
						"mods": {
							"start_pet": "yanhu",
							"pet_slots": 2,
							"pet_offer_chance_bonus": 0.15,
							"pet_damage_mult": 0.15,
							"damage_mult": 0.90,
						},
						"allowed_tags": [],
						"locked_upgrades": [],
							"skill_mods": {"renewal": {"power_mult": 1.30}},
					},
					"kuxingseng": {
						"name": "苦行僧",
						"epithet": "心如止水，金刚怒目",
						"icon": "res://assets/art/cultivator_kuxingseng_icon.png",
						"sprite": "res://assets/art/pawn_blue_8dir.png",
						"motion": "procedural",
						"render_style": "hollow_knight",
						"start_equip": "",
						"pros": [
							"站定不动时全伤害 +50%",
							"站定不动时攻击间隔 -35%",
							"站定不动时护甲 +5、拾取范围 +100%",
						],
						"cons": [
							"移动中全伤害 -60%",
							"移动中攻击间隔 +60%",
							"基础移动速度 -10%",
						],
						"mods": {
							"speed_mult": 0.90,
							"kuxingseng_mode": 1.0,
							"still_damage_bonus": 0.50,
							"still_haste_bonus": 0.35,
							"still_armor_bonus": 5.0,
							"still_pickup_bonus": 1.0,
							"move_damage_penalty": -0.60,
							"move_haste_penalty": 0.60,
						},
						"allowed_tags": [],
						"locked_upgrades": [],
						"skill_mods": {"aegis": {"duration_add": 1.5}},
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

## 随角色绑定的额外技能 id（独立于五选一技能）；没配 extra_skill 的角色返回空串
static func get_extra_skill_id(id: String) -> String:
	return String(get_def(id).get("extra_skill", ""))

## 额外技能的卡面说明（选角/图鉴/属性面板共用的一段）：按 extra_skill 分派到该机制自己的表去取，
## 数字由那张表负责（踏影 = ShadowStepData、服丹 = ElixirData），本表不抄一份；没配额外技能的角色返回空数组。
static func get_extra_desc(id: String) -> Array[String]:
	match get_extra_skill_id(id):
		"shadowburst":
			return ShadowStepData.card_lines()
		"elixir":
			return ElixirData.card_lines()
	return []

static func get_visual_config(id: String) -> CultivatorVisualConfig:
	return CultivatorVisualConfig.get_config(id)

