class_name UpgradeData
extends RefCounted

## 加点数据库：回合后悟道结算一次给 5 个候选（GameManager.UPGRADE_OFFER_COUNT），武器一律从商店获取
## 稀有度四档 common/rare/epic/legendary（普通/稀有/史诗/传说，与道具 tier 同一套词表与颜色）：
## 权重随波次递进、乘福缘、各档封顶（见 GameBalance.rarity_weights）
## 每项设 max_stacks 上限，叠满后从池中剔除，防数值线性失控
##
## "apply" 是该项的**实际生效幅度**（唯一事实来源）：悟道卡面的加成行由 BonusRows 从 apply
## 直接生成（正绿负红、名左值右），desc 只写 apply 之外的机制说明、不再手抄数值：
##   可加算的字段名直接写：weapon_damage_mult / armor / move_speed_mult / attack_range_mult /
##                         hp_regen / crit_rate / crit_mult / dodge /
##                         lifesteal / luck / harvest / spirit_stones
##   特殊：attack_speed_mult_mul（乘算，地板见 GameManager.ATTACK_SPEED_FLOOR）、
##        max_hp + hp_heal（改的是玩家节点，需要 GameManager 代一手）；
##        hp_heal 恒与 max_hp 同值成对＝新上限自带满血，卡面折叠不单列（BonusRows.folded_keys）
## 字段白名单在 GameManager.apply_upgrade()，写错会在运行时 push_warning 里暴露。

const RARITY_COLORS := {
	"common": GameStyle.RARITY_COMMON,
	"rare": GameStyle.RARITY_RARE,
	"epic": GameStyle.RARITY_EPIC,
	"legendary": GameStyle.RARITY_LEGEND,
}

const UPGRADES: Array[Dictionary] = [
		{
			"id": "atk_up",
			"apply": {"weapon_damage_mult": 0.08},
			"title": "武器强化",
			"desc": "武器伤害超过 +100% 后收益减半",
			"rarity": "common",
			"rarity_label": "普通",
			"icon": "res://assets/art/upgrade_atk.png",
			"max_stacks": 6,
		},
		{
			"id": "melee_up",
			"apply": {"melee_damage": 3.0},
			"title": "近战强化",
			"desc": "",
			"rarity": "common",
			"rarity_label": "普通",
			"icon": "res://assets/art/upgrade_melee.png",
			"max_stacks": 6,
		},
		{
			"id": "ranged_up",
			"apply": {"ranged_damage": 3.0},
			"title": "远程强化",
			"desc": "",
			"rarity": "common",
			"rarity_label": "普通",
			"icon": "res://assets/art/upgrade_ranged.png",
			"max_stacks": 6,
		},
		{
			"id": "elemental_up",
			"apply": {"elemental_damage": 3.0},
			"title": "元素强化",
			"desc": "并提升灼烧、中毒等持续伤害",
			"rarity": "common",
			"rarity_label": "普通",
			"icon": "res://assets/art/upgrade_elemental.png",
			"max_stacks": 6,
		},
			{
				"id": "engineering_up",
				"apply": {"engineering_damage": 3.0},
				"title": "召唤强化",
				"desc": "",
				"rarity": "common",
				"rarity_label": "普通",
				"icon": "res://assets/art/upgrade_engineering.png",
				"max_stacks": 6,
			},
			{
				"id": "contraption_up",
				"apply": {"contraption_damage": 3.0},
				"title": "机关强化",
				"desc": "",
				"rarity": "common",
				"rarity_label": "普通",
				"icon": "res://assets/art/upgrade_contraption.png",
				"max_stacks": 6,
			},
	{
		"id": "haste_up",
		"apply": {"attack_speed_mult_mul": 0.88},
		"title": "攻击间隔缩短",
		"desc": "",
		"rarity": "rare",
		"rarity_label": "稀有",
		"icon": "res://assets/art/upgrade_haste.png",
		"max_stacks": 6,
	},
	{
		"id": "armor_up",
		"apply": {"armor": 2.0},
		"title": "护甲提升",
		"desc": "按百分比减免每次受击伤害",
		"rarity": "common",
		"rarity_label": "普通",
		"icon": "res://assets/art/upgrade_armor.png",
		"max_stacks": 6,
	},
	{
		"id": "speed_up",
		"apply": {"move_speed_mult": 0.08},
		"title": "移速提升",
		"desc": "",
		"rarity": "common",
		"rarity_label": "普通",
		"icon": "res://assets/art/upgrade_speed.png",
		"max_stacks": 6,
	},
	{
		"id": "hp_up",
		# 2026-10-24 回血 30→25 对齐全表口径：hp_heal 恒与 max_hp 同值成对（新上限自带满血），
		# 卡面按 BonusRows.folded_keys 折叠、不单列回血行；不等值的孤儿回血没有界面承载它。
		"apply": {"max_hp": 25.0, "hp_heal": 25.0},
		"title": "生命提升",
		"desc": "",
		"rarity": "rare",
		"rarity_label": "稀有",
		"icon": "res://assets/art/upgrade_hp.png",
		"max_stacks": 6,
	},
	# 2026-10-20 拾取范围整系移除（用户口径：不管玩什么流派都没用），原 pickup_up 位换成通用生存档。
	{
		"id": "temper",
		"apply": {"armor": 3.0, "max_hp": 15.0, "hp_heal": 15.0},
		"title": "淬体",
		"desc": "厚甲护身，同时提升生命上限",
		"rarity": "common",
		"rarity_label": "普通",
		"icon": "res://assets/art/upgrade_temper.png",
		"max_stacks": 6,
	},
	# 2026-10-20 金币补给重做：原来 8 层共 96 金币性价比过低，改成收益复利 + 幸运的长期经济档。
	{
		"id": "greed",
		"apply": {"harvest": 10.0, "luck": 3.0},
		"title": "贪婪",
		"desc": "每回合结束白得金币与经验，并小幅提升幸运",
		"rarity": "common",
		"rarity_label": "普通",
		"icon": "res://assets/art/upgrade_greed.png",
		"max_stacks": 4,
	},
	{
		"id": "regen_up",
		"apply": {"hp_regen": 1.2},
		"title": "生命回复",
		"desc": "每秒持续回复生命",
		"rarity": "epic",
		"rarity_label": "史诗",
		"icon": "res://assets/art/upgrade_regen.png",
		"max_stacks": 6,
	},
	{
		"id": "crit_up",
		"apply": {"crit_rate": 0.08},
		"title": "暴击率",
		"desc": "暴击率有软上限，到顶再加是白加",
		"rarity": "rare",
		"rarity_label": "稀有",
		"icon": "res://assets/art/upgrade_crit.png",
		"max_stacks": 6,
	},
	{
		"id": "critdmg_up",
		"apply": {"crit_mult": 0.25},
		"title": "暴击伤害",
		"desc": "打出暴击时伤害额外提升，上限 250%",
		"rarity": "epic",
		"rarity_label": "史诗",
		"icon": "res://assets/art/upgrade_critdmg.png",
		"max_stacks": 4,
	},
	{
		"id": "dodge_up",
		"apply": {"dodge": 0.07},
		"title": "闪避率",
		"desc": "有概率完全闪避一次攻击，不掉血",
		"rarity": "rare",
		"rarity_label": "稀有",
		"icon": "res://assets/art/upgrade_dodge.png",
		"max_stacks": 6,
	},
	{
		"id": "lifesteal_up",
		"apply": {"lifesteal": 0.04},
		"title": "吸血",
		"desc": "命中时吸取 1 点生命（每秒最多 3 次），近战更易触发",
		"rarity": "rare",
		"rarity_label": "稀有",
		"icon": "res://assets/art/upgrade_lifesteal.png",
		"max_stacks": 6,
	},
	{
		"id": "luck_up",
		"apply": {"luck": 6.0},
		"title": "幸运提升",
		"desc": "高稀有升级与道具更易出现",
		"rarity": "common",
		"rarity_label": "普通",
		"icon": "res://assets/art/upgrade_luck.png",
		"max_stacks": 8,
	},
	{
		"id": "harvest_up",
		"apply": {"harvest": 8.0},
		"title": "收益提升",
		"desc": "每回合结束白得金币与经验",
		"rarity": "rare",
		"rarity_label": "稀有",
		"icon": "res://assets/art/upgrade_harvest.png",
		"max_stacks": 6,
	},
	# 2026-10-11 寻宝流三项：生效幅度在这里，兑现点在 BalanceChest（数量 / 档次权重 / 开箱收益）
	# 与 WaveSpawner._spawn_chests、SpiritChest._destroy。图标与同名道具配对（重掷令/破甲针同款先例）。
	# 2026-10-12：第三条腿从「开箱省力（砍砸开击数）」换成「宝箱掉落（抬兑现量）」——
	# 匣子只吃闲着那几法，少挨几下省的是本来就要浪费的零头，读数还反着看（口径见 BalanceChest 头）。
	{
		"id": "chest_count_up",
		"apply": {"chest_count": 1},
		"title": "宝箱数量",
		"desc": "每回合场上多刷几口宝箱",
		"rarity": "common",
		"rarity_label": "普通",
		"icon": "res://assets/art/upgrade_chest.png",
		"max_stacks": 3,
	},
	{
		"id": "chest_quality_up",
		"apply": {"chest_quality": 2.0},
		"title": "宝箱品质",
		"desc": "铜匣与玉匣更易出现，玉匣砸开必送道具",
		"rarity": "rare",
		"rarity_label": "稀有",
		"icon": "res://assets/art/upgrade_chest_quality.png",
		"max_stacks": 4,
	},
	{
		"id": "chest_reward_up",
		"apply": {"chest_reward": 0.35},
		"title": "宝箱掉落",
		"desc": "砸开的宝箱掉得更多（金币与回复量同涨）",
		"rarity": "rare",
		"rarity_label": "稀有",
		"icon": "res://assets/art/upgrade_chest_reward.png",
		"max_stacks": 3,
	},
	{
		# 2026-10-20 由 +0.12 降到 +0.05（共 5 档 ⇒ 满叠 +25%）：范围是全域乘区，
		# 与剑系羁绊、道具同乘，单档给太多会让同屏弹道直接拉满
		"id": "range_up",
		"apply": {"attack_range_mult": 0.05},
		"title": "攻击范围",
		"desc": "",
		"rarity": "common",
		"rarity_label": "普通",
		"icon": "res://assets/art/upgrade_range.png",
		"max_stacks": 5,
	},
	# 2026-10-20 击退提升整系移除（用户口径：不管玩什么流派都没用），原 knockback_up 位换成攻防一体的吸血档。
	{
		"id": "bloodlust",
		"apply": {"lifesteal": 0.06, "weapon_damage_mult": 0.10},
		"title": "嗜血",
		"desc": "边打边回血，同时提升武器伤害",
		"rarity": "epic",
		"rarity_label": "史诗",
		"icon": "res://assets/art/upgrade_bloodlust.png",
		"max_stacks": 5,
	},
	{
		"id": "insight_up",
		"apply": {"xp_gain_mult": 0.15},
		"title": "经验加成",
		"desc": "吸收经验光球获得更多经验",
		"rarity": "rare",
		"rarity_label": "稀有",
		"icon": "res://assets/art/upgrade_insight.png",
		"max_stacks": 4,
	},
	{
		"id": "tongxuan_up",
		"apply": {"free_rerolls": 1.0},
		"title": "免费重掷",
		"desc": "回合间商店免费重掷次数",
		"rarity": "rare",
		"rarity_label": "稀有",
		"icon": "res://assets/art/upgrade_tongxuan.png",
		"max_stacks": 2,
	},
	{
		"id": "revive_up",
		"apply": {"revive_charges": 1.0},
		"title": "轮回重生",
		"desc": "复活次数增加一次；阵亡后可原地复活，恢复半血并短暂无敌",
		"rarity": "epic",
		"rarity_label": "史诗",
		"icon": "res://assets/art/item_tisi_kuilei.png",
		"max_stacks": 2,
	},
	{
		"id": "elite_up",
		"apply": {"elite_damage": 0.25},
		"title": "精英伤害",
		"desc": "仅对精英与首领生效",
		"rarity": "rare",
		"rarity_label": "稀有",
		"icon": "res://assets/art/upgrade_elite.png",
		"max_stacks": 4,
	},
	{
		"id": "wuxing_up",
		"apply": {"element_damage_all": 0.08},
		"title": "全元素强化",
		"desc": "提升全系武器的元素伤害",
		"rarity": "epic",
		"rarity_label": "史诗",
		"icon": "res://assets/art/upgrade_wuxing.png",
		"max_stacks": 5,
	},
	# 2026-10-10 新增：单元素专精加点，与同名单元素道具（金精石等）构成专精流双链路
	{
		"id": "metal_up",
		"apply": {"element_damage_metal": 0.10},
		"title": "锐金真解",
		"desc": "仅对金系武器生效",
		"rarity": "rare",
		"rarity_label": "稀有",
		"icon": "res://assets/art/upgrade_metal.png",
		"max_stacks": 4,
	},
	{
		"id": "wood_up",
		"apply": {"element_damage_wood": 0.10},
		"title": "青木真解",
		"desc": "仅对木系武器生效",
		"rarity": "rare",
		"rarity_label": "稀有",
		"icon": "res://assets/art/upgrade_wood.png",
		"max_stacks": 4,
	},
	{
		"id": "water_up",
		"apply": {"element_damage_water": 0.10},
		"title": "玄水真解",
		"desc": "仅对水系武器生效",
		"rarity": "rare",
		"rarity_label": "稀有",
		"icon": "res://assets/art/upgrade_water.png",
		"max_stacks": 4,
	},
	{
		"id": "fire_up",
		"apply": {"element_damage_fire": 0.10},
		"title": "离火真解",
		"desc": "仅对火系武器生效",
		"rarity": "rare",
		"rarity_label": "稀有",
		"icon": "res://assets/art/upgrade_fire.png",
		"max_stacks": 4,
	},
	{
		"id": "earth_up",
		"apply": {"element_damage_earth": 0.10},
		"title": "厚土真解",
		"desc": "仅对土系武器生效",
		"rarity": "rare",
		"rarity_label": "稀有",
		"icon": "res://assets/art/upgrade_earth.png",
		"max_stacks": 4,
	},

	# 2026-10-10 新增：穿透与反伤体系 + 史诗级高阶加点（打破低阶上限）
	{
		"id": "pierce_up",
		"apply": {"bonus_pierce": 1.0},
		"title": "穿透强化",
		"desc": "弹丸可多穿透 1 名敌人（近战不生效）",
		"rarity": "rare",
		"rarity_label": "稀有",
		"icon": "res://assets/art/upgrade_pierce.png",
		"max_stacks": 2,
	},
	{
		"id": "thorns_up",
		"apply": {"thorns": 0.35},
		"title": "护体罡气",
		"desc": "受到近身碰撞时反震",
		"rarity": "common",
		"rarity_label": "普通",
		"icon": "res://assets/art/upgrade_thorns.png",
		"max_stacks": 6,
	},
	{
		"id": "grand_thorns",
		"apply": {"thorns": 0.70, "armor": 2.0},
		"title": "九幽逆鳞",
		"desc": "受到近身碰撞时反震",
		"rarity": "epic",
		"rarity_label": "史诗",
		"icon": "res://assets/art/upgrade_thorns_grand.png",
		"max_stacks": 3,
	},
	{
		"id": "grand_melee",
		"apply": {"melee_damage": 6.0},
		"title": "气冲霄汉",
		"desc": "",
		"rarity": "epic",
		"rarity_label": "史诗",
		"icon": "res://assets/art/upgrade_melee_grand.png",
		"max_stacks": 5,
	},
	{
		"id": "grand_ranged",
		"apply": {"ranged_damage": 6.0},
		"title": "百步穿杨",
		"desc": "",
		"rarity": "epic",
		"rarity_label": "史诗",
		"icon": "res://assets/art/upgrade_ranged_grand.png",
		"max_stacks": 5,
	},
	{
		"id": "grand_elemental",
		"apply": {"elemental_damage": 6.0},
		"title": "万法归宗",
		"desc": "",
		"rarity": "epic",
		"rarity_label": "史诗",
		"icon": "res://assets/art/upgrade_elemental_grand.png",
		"max_stacks": 5,
	},
	{
		"id": "grand_engineering",
		"apply": {"engineering_damage": 6.0, "max_hp": 15.0, "hp_heal": 15.0},
		"title": "万灵朝元",
		"desc": "召唤兵器护主，附带护体罡气",
		"rarity": "epic",
		"rarity_label": "史诗",
		"icon": "res://assets/art/upgrade_engineering_grand.png",
		"max_stacks": 5,
	},
			{
				# 2026-10-20 修数值阶梯：0.82 连乘 3 层=0.55，反而弱于 haste_up 满叠 0.88 连乘 6 层=0.46，
				# 传说卡不如普通卡。改为每层 ×0.75（满叠约 0.42），真正压过普通档，仍在地板 0.3 之上。
				"id": "grand_haste",
				"apply": {"attack_speed_mult_mul": 0.75},
				"title": "雷厉风行",
				"desc": "",
				"rarity": "legendary",
				"rarity_label": "传说",
				"icon": "res://assets/art/upgrade_haste_grand.png",
				"max_stacks": 3,
			},
			{
				# 2026-10-20 修数值阶梯：原 +0.15/层 满叠 +45% 弱于 atk_up 满叠 +48%。
				# 改为 +0.20/层（满叠 +60%），超过软顶 2.0 后按 50% 兑现自然收敛。
				"id": "grand_atk",
				"apply": {"weapon_damage_mult": 0.20},
				"title": "仙兵奥义",
				"desc": "全系兵刃威能大幅跃升；武器伤害超过 +100% 后收益减半",
				"rarity": "legendary",
				"rarity_label": "传说",
				"icon": "res://assets/art/upgrade_atk_grand.png",
				"max_stacks": 3,
			},
		# ==================== 2026-10-21 结构补档（机关史诗 / 技能流 / 闪避史诗 / 商店折扣） ====================
		{
			"id": "grand_contraption",
			"apply": {"contraption_damage": 6.0, "max_hp": 10.0, "hp_heal": 10.0},
			"title": "万机归元",
			"desc": "机关护主，附带护体罡气",
			"rarity": "epic",
			"rarity_label": "史诗",
			"icon": "res://assets/art/upgrade_contraption_grand.png",
			"max_stacks": 4,
		},
		{
			"id": "skill_cd_up",
			"apply": {"skill_cooldown_mult": 0.08},
			"title": "凝神",
			"desc": "随行技能冷却时间缩短；与道具冷却缩减相加",
			"rarity": "rare",
			"rarity_label": "稀有",
			"icon": "res://assets/art/upgrade_skill_cd.png",
			"max_stacks": 3,
		},
		{
			"id": "grand_skill_cd",
			"apply": {"skill_cooldown_mult": 0.15},
			"title": "坐忘",
			"desc": "随行技能冷却大幅缩短；与道具冷却缩减相加",
			"rarity": "legendary",
			"rarity_label": "传说",
			"icon": "res://assets/art/upgrade_skill_cd_grand.png",
			"max_stacks": 2,
		},
		{
			"id": "grand_dodge",
			"apply": {"dodge": 0.10, "armor": -1.0},
			"title": "踏虚",
			"desc": "身法登峰，护体略薄",
			"rarity": "epic",
			"rarity_label": "史诗",
			"icon": "res://assets/art/upgrade_dodge_grand.png",
			"max_stacks": 2,
		},
		{
			# 2026-10-22 折扣腿 0.85 → 0.80（用户口径：商店价 ×0.8、武器伤害 −3% 不动）。
			# 与商人角色开局 0.8 相乘 = 0.64，会被 StatSystem 的 SHOP_PRICE_FLOOR(0.7) 夹住；
			# 夹掉那份不兑现，负代偿腿由 cost_scale() 按「实收降幅/名义降幅」折算，不会白扣伤害。
			"id": "merchant_up",
			"apply": {"shop_price_mul": 0.8, "weapon_damage_mult": -0.03},
			"title": "讨价还价",
			"desc": "商店价格降低；武器伤害略减",
			"rarity": "rare",
			"rarity_label": "稀有",
			"icon": "res://assets/art/upgrade_merchant.png",
			"max_stacks": 2,
		},
		# ==================== 灵兽强化体系 ====================
		{
			"id": "pet_damage_up",
			"apply": {"pet_damage_mult": 0.15},
			"title": "灵兽淬炼",
			"desc": "",
			"rarity": "common",
			"rarity_label": "普通",
			"icon": "res://assets/art/upgrade_pet_damage.png",
			"max_stacks": 8,
		},
		{
			"id": "pet_effect_up",
			"apply": {"pet_effect_mult": 0.12},
			"title": "灵兽通灵",
			"desc": "",
			"rarity": "common",
			"rarity_label": "普通",
			# 2026-10-20 修图标错配：原来误用血瓶 icon_hp（语义不符），改用灵兽道具图标。
			"icon": "res://assets/art/upgrade_pet_effect.png",
			"max_stacks": 8,
		},
		{
			"id": "pet_haste_up",
			"apply": {"pet_cooldown_mult_mul": 0.92},
			"title": "灵兽疾行",
			"desc": "",
			"rarity": "rare",
			"rarity_label": "稀有",
			"icon": "res://assets/art/upgrade_pet_haste.png",
			"max_stacks": 5,
		},
		{
			"id": "pet_slots_up",
			"apply": {"pet_slots": 1.0},
			"title": "万兽灵契",
			"desc": "",
			"rarity": "legendary",
			"rarity_label": "传说",
			"icon": "res://assets/art/upgrade_pet_slots.png",
			"max_stacks": 2,
		},
	]

## 稀有度加权抽取：过滤叠满项与角色锁死项，高稀有权重随波次递进、随幸运放大。
## 纯函数：一切上下文由 ctx 传入（luck / wave / locked_upgrades / counts / rng），不读 GameManager 单例，
## 因此可以在不启动场景、不建 autoload 的情况下被单元测试直接断言。
## ctx 约定：
##   luck: float                 幸运
##   wave: int                   当前波次（缺省 1；高稀有档未解锁时权重为 0）
##   locked_upgrades: Array      角色锁死的加点 id
##   counts: Dictionary          已加点次数 {id: int}
##   rng: RandomNumberGenerator  随机源；缺省时用全局 randf()（单测里务必传入固定种子）
static func get_random_upgrades(count: int = 3, ctx: Dictionary = {}) -> Array[Dictionary]:
	var luck: float = float(ctx.get("luck", 0.0))
	var wave: int = int(ctx.get("wave", 1))
	var locked: Array = ctx.get("locked_upgrades", [])
	var owned_counts: Dictionary = ctx.get("counts", {})
	var rng: RandomNumberGenerator = ctx.get("rng", null)
	var has_pets: bool = bool(ctx.get("has_pets", false))
	# 满穿透闸（2026-10-17）：ctx 可选带 gm，阵容穿透顶到上限时 pierce_up 不进候选池
	var gm_for_pierce: Node = ctx.get("gm", null)

	var weights_dict := GameBalance.rarity_weights(luck, wave)
	var common_w: float = weights_dict["common"]
	var rare_w: float = weights_dict["rare"]
	var epic_w: float = weights_dict["epic"]
	var legendary_w: float = weights_dict["legendary"]

	var gm_filter: Node = ctx.get("gm", null)

	# 先按构筑感知过滤（BalanceBuildFilter）收一版池；不足 count 时回退到未过滤池，绝不让候选变少。
	var filtered := _collect_pool(locked, owned_counts, has_pets, gm_for_pierce, gm_filter,
		common_w, rare_w, epic_w, legendary_w, true)
	var pool: Array[Dictionary] = filtered[0]
	var pool_weights: Array[float] = filtered[1]
	if pool.size() < count:
		var full := _collect_pool(locked, owned_counts, has_pets, gm_for_pierce, gm_filter,
			common_w, rare_w, epic_w, legendary_w, false)
		pool = full[0]
		pool_weights = full[1]

	var result: Array[Dictionary] = []
	var active_rng: RandomNumberGenerator = rng if rng != null else GameManager.rng
	for i in range(count):
		if pool.is_empty():
			break
		var roll: float = active_rng.randf()
		var chosen: int = GameBalance.weighted_pick_index(pool_weights, roll)
		var picked: Dictionary = pool[chosen].duplicate()
		picked["border_color"] = RARITY_COLORS.get(picked.get("rarity", "common"), Color.WHITE)
		result.append(picked)
		pool.remove_at(chosen)
		pool_weights.remove_at(chosen)
	return result

## 收一版候选池，返回 [pool, weights]。apply_build_filter=false 时跳过构筑感知过滤（兜底用）。
static func _collect_pool(locked: Array, owned_counts: Dictionary, has_pets: bool,
		gm_for_pierce: Node, gm_filter: Node, common_w: float, rare_w: float,
		epic_w: float, legendary_w: float, apply_build_filter: bool) -> Array:
	var pool: Array[Dictionary] = []
	var pool_weights: Array[float] = []
	for u in UPGRADES:
		var uid: String = u.get("id", "")
		if uid in locked:
			continue
		if int(owned_counts.get(uid, 0)) >= int(u.get("max_stacks", 99)):
			continue
		# 无随行灵兽且非御兽师时，不刷出灵兽强化项（防污染卡池）
		if uid.begins_with("pet_") and not has_pets:
			continue
		# 阵容穿透已全部顶到上限 ⇒ 穿透强化不再刷出（PierceLimit 唯一判定）
		if gm_for_pierce != null and not PierceLimit.filter_upgrade_id(gm_for_pierce, uid):
			continue
		# 构筑感知过滤：玩剑系就别刷召唤/机关/单元素等死卡（2026-10-20）
		if apply_build_filter and not BalanceBuildFilter.upgrade_allowed(gm_filter, uid):
			continue
		var w: float = common_w
		match u.get("rarity", "common"):
			"rare":
				w = rare_w
			"epic":
				w = epic_w
			"legendary":
				w = legendary_w
		pool.append(u)
		pool_weights.append(w)
	return [pool, pool_weights]

static func get_upgrade_def(upgrade_id: String) -> Dictionary:
	for u in UPGRADES:
		if u.get("id", "") == upgrade_id:
			var copy: Dictionary = u.duplicate()
			copy["border_color"] = RARITY_COLORS.get(copy.get("rarity", "common"), Color.WHITE)
			return copy
	return {}
