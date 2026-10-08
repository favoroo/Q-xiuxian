class_name UpgradeData
extends RefCounted

## 加点数据库：升级三选一只出属性，武器一律从波间商店获取
## 稀有度权重：凡品/良品/仙品基础 60/30/10，福缘每点 +1% 仙品权重（从凡品中扣）
## 每项设 max_stacks 上限，叠满后从池中剔除，防数值线性失控

const RARITY_COLORS := {
	"common": Color(0.96, 0.95, 0.92),
	"rare": Color(1.0, 0.83, 0.3),
	"epic": Color(0.35, 0.75, 1.0),
}

const UPGRADES: Array[Dictionary] = [
	{
		"id": "atk_up",
		"title": "剑意淬锋",
		"desc": "[center]所有法器伤害提升\n• 武器总伤害 [color=#ffd24d][b]+15%[/b][/color]\n• 剑符雷扇尽数受益[/center]",
		"rarity": "common",
		"rarity_label": "凡品",
		"icon": "res://assets/art/icon_atk.png",
		"max_stacks": 8,
	},
	{
		"id": "haste_up",
		"title": "法诀迅捷",
		"desc": "[center]掐诀更快，施法更频\n• 施法间隔 [color=#6fd6ff][b]-12%[/b][/color]\n• 全部法器攻速提升[/center]",
		"rarity": "rare",
		"rarity_label": "良品",
		"icon": "res://assets/art/icon_haste.png",
		"max_stacks": 6,
	},
	{
		"id": "armor_up",
		"title": "罡气护体",
		"desc": "[center]周身凝聚护体罡气\n• 护甲 [color=#7ce860][b]+2[/b][/color]\n• 妖兽爪牙难以近身破防[/center]",
		"rarity": "common",
		"rarity_label": "凡品",
		"icon": "res://assets/art/icon_armor.png",
		"max_stacks": 10,
	},
	{
		"id": "speed_up",
		"title": "神行符",
		"desc": "[center]脚踏神行符，身轻如燕\n• 移动速度 [color=#6fd6ff][b]+8%[/b][/color]\n• 从容穿梭妖潮之间[/center]",
		"rarity": "common",
		"rarity_label": "凡品",
		"icon": "res://assets/art/icon_boots.png",
		"max_stacks": 6,
	},
	{
		"id": "hp_up",
		"title": "淬体凝元",
		"desc": "[center]淬炼肉身，气血充盈\n• 气血上限 [color=#7ce860][b]+25[/b][/color]\n• 立即恢复 [color=#7ce860][b]30[/b][/color] 点气血[/center]",
		"rarity": "rare",
		"rarity_label": "良品",
		"icon": "res://assets/art/icon_hp.png",
		"max_stacks": 10,
	},
	{
		"id": "pickup_up",
		"title": "摄灵术",
		"desc": "[center]袖里摄灵，隔空取物\n• 灵石拾取范围 [color=#6fd6ff][b]+40%[/b][/color]\n• 散落灵石自动入袖[/center]",
		"rarity": "common",
		"rarity_label": "凡品",
		"icon": "res://assets/art/icon_magnet.png",
		"max_stacks": 4,
	},
	{
		"id": "coins_up",
		"title": "灵石补给",
		"desc": "[center]取出一小袋备用灵石\n• 立刻获得 [color=#ffd24d][b]12[/b][/color] 枚灵石\n• 留着去灵石阁置办法器[/center]",
		"rarity": "common",
		"rarity_label": "凡品",
		"icon": "res://assets/art/icon_coin.png",
		"max_stacks": 99,
	},
	{
		"id": "regen_up",
		"title": "灵愈心法",
		"desc": "[center][color=#35bfff][b]【仙品心法】[/b][/color]\n• 每秒恢复 [color=#7ce860][b]1.2[/b][/color] 点气血\n• 灵气滋养，伤势缓慢愈合[/center]",
		"rarity": "epic",
		"rarity_label": "仙品",
		"icon": "res://assets/art/icon_regen.png",
		"max_stacks": 6,
	},
	{
		"id": "crit_up",
		"title": "会心剑意",
		"desc": "[center]剑走偏锋，直取要害\n• 暴击率 [color=#ffd24d][b]+8%[/b][/color]\n• 全部法器皆可会心一击[/center]",
		"rarity": "rare",
		"rarity_label": "良品",
		"icon": "res://assets/art/icon_atk.png",
		"max_stacks": 8,
	},
	{
		"id": "critdmg_up",
		"title": "剑心通明",
		"desc": "[center][color=#35bfff][b]【仙品剑境】[/b][/color]\n• 暴击伤害 [color=#ffd24d][b]+25%[/b][/color]\n• 会心一击威力倍增[/center]",
		"rarity": "epic",
		"rarity_label": "仙品",
		"icon": "res://assets/art/icon_atk.png",
		"max_stacks": 6,
	},
	{
		"id": "dodge_up",
		"title": "流云身法",
		"desc": "[center]身若流云，缥缈难捉\n• 闪避率 [color=#6fd6ff][b]+7%[/b][/color]\n• 最高可至六成（60%）[/center]",
		"rarity": "rare",
		"rarity_label": "良品",
		"icon": "res://assets/art/icon_boots.png",
		"max_stacks": 8,
	},
	{
		"id": "lifesteal_up",
		"title": "噬元诀",
		"desc": "[center][color=#35bfff][b]【仙品魔功】[/b][/color]\n• 命中 [color=#7ce860][b]+4%[/b][/color] 概率吸取 1 点气血\n• 每秒至多生效 3 次[/center]",
		"rarity": "epic",
		"rarity_label": "仙品",
		"icon": "res://assets/art/icon_regen.png",
		"max_stacks": 6,
	},
	{
		"id": "luck_up",
		"title": "福缘深厚",
		"desc": "[center]气运加身，天道眷顾\n• 福缘 [color=#ffd24d][b]+6[/b][/color]\n• 仙品悟道与高阶法缘更易降临[/center]",
		"rarity": "common",
		"rarity_label": "凡品",
		"icon": "res://assets/art/icon_coin.png",
		"max_stacks": 8,
	},
	{
		"id": "harvest_up",
		"title": "灵韵积淀",
		"desc": "[center]灵田蕴灵，厚积薄发\n• 灵韵 [color=#ffd24d][b]+8[/b][/color]\n• 每波结束无偿获得等额灵石与修为，且灵韵自我增长[/center]",
		"rarity": "rare",
		"rarity_label": "良品",
		"icon": "res://assets/art/icon_coin.png",
		"max_stacks": 8,
	},
	{
		"id": "range_up",
		"title": "神识外延",
		"desc": "[center]神识所至，剑气所及\n• 攻击范围 [color=#6fd6ff][b]+12%[/b][/color]\n• 索敌更远，挥砍更阔[/center]",
		"rarity": "common",
		"rarity_label": "凡品",
		"icon": "res://assets/art/icon_magnet.png",
		"max_stacks": 5,
	},
]

## 稀有度加权抽取：过滤叠满项与角色锁死项，福缘提升仙品权重
static func get_random_upgrades(count: int = 3) -> Array[Dictionary]:
	var epic_w: float = 10.0 + GameManager.luck * 1.0
	var rare_w: float = 30.0
	var common_w: float = maxf(10.0, 100.0 - rare_w - epic_w)

	var pool: Array = []
	for u in UPGRADES:
		var uid: String = u.get("id", "")
		if uid in GameManager.locked_upgrades:
			continue
		var owned: int = int(GameManager.upgrade_counts.get(uid, 0))
		if owned >= int(u.get("max_stacks", 99)):
			continue
		var w: float = common_w
		match u.get("rarity", "common"):
			"rare":
				w = rare_w
			"epic":
				w = epic_w
		pool.append({"def": u, "weight": w})

	var result: Array[Dictionary] = []
	for i in range(count):
		if pool.is_empty():
			break
		var total: float = 0.0
		for p in pool:
			total += p["weight"]
		var r: float = randf() * total
		var chosen_idx: int = 0
		for j in range(pool.size()):
			r -= pool[j]["weight"]
			if r <= 0.0:
				chosen_idx = j
				break
		var u: Dictionary = pool[chosen_idx]["def"].duplicate()
		u["border_color"] = RARITY_COLORS.get(u.get("rarity", "common"), Color.WHITE)
		result.append(u)
		pool.remove_at(chosen_idx)
	return result

static func get_upgrade_def(upgrade_id: String) -> Dictionary:
	for u in UPGRADES:
		if u.get("id", "") == upgrade_id:
			var copy: Dictionary = u.duplicate()
			copy["border_color"] = RARITY_COLORS.get(copy.get("rarity", "common"), Color.WHITE)
			return copy
	return {}
