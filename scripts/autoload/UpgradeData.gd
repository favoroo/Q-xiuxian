class_name UpgradeData
extends RefCounted

## 加点数据库：升级三选一只出属性，武器一律从波间商店获取

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
		"icon": "res://assets/art/icon_atk.png"
	},
	{
		"id": "haste_up",
		"title": "法诀迅捷",
		"desc": "[center]掐诀更快，施法更频\n• 施法间隔 [color=#6fd6ff][b]-12%[/b][/color]\n• 全部法器攻速提升[/center]",
		"rarity": "rare",
		"rarity_label": "良品",
		"icon": "res://assets/art/icon_haste.png"
	},
	{
		"id": "armor_up",
		"title": "罡气护体",
		"desc": "[center]周身凝聚护体罡气\n• 护甲 [color=#7ce860][b]+2[/b][/color]\n• 妖兽爪牙难以近身破防[/center]",
		"rarity": "common",
		"rarity_label": "凡品",
		"icon": "res://assets/art/icon_armor.png"
	},
	{
		"id": "speed_up",
		"title": "神行符",
		"desc": "[center]脚踏神行符，身轻如燕\n• 移动速度 [color=#6fd6ff][b]+8%[/b][/color]\n• 从容穿梭妖潮之间[/center]",
		"rarity": "common",
		"rarity_label": "凡品",
		"icon": "res://assets/art/icon_boots.png"
	},
	{
		"id": "hp_up",
		"title": "淬体凝元",
		"desc": "[center]淬炼肉身，气血充盈\n• 气血上限 [color=#7ce860][b]+25[/b][/color]\n• 立即恢复 [color=#7ce860][b]30[/b][/color] 点气血[/center]",
		"rarity": "rare",
		"rarity_label": "良品",
		"icon": "res://assets/art/icon_hp.png"
	},
	{
		"id": "pickup_up",
		"title": "摄灵术",
		"desc": "[center]袖里摄灵，隔空取物\n• 灵石拾取范围 [color=#6fd6ff][b]+40%[/b][/color]\n• 散落灵石自动入袖[/center]",
		"rarity": "common",
		"rarity_label": "凡品",
		"icon": "res://assets/art/icon_magnet.png"
	},
	{
		"id": "coins_up",
		"title": "灵石补给",
		"desc": "[center]取出一小袋备用灵石\n• 立刻获得 [color=#ffd24d][b]12[/b][/color] 枚灵石\n• 留着去灵石阁置办法器[/center]",
		"rarity": "common",
		"rarity_label": "凡品",
		"icon": "res://assets/art/icon_coin.png"
	},
	{
		"id": "regen_up",
		"title": "灵愈心法",
		"desc": "[center][color=#35bfff][b]【仙品心法】[/b][/color]\n• 每秒恢复 [color=#7ce860][b]1.2[/b][/color] 点气血\n• 灵气滋养，伤势缓慢愈合[/center]",
		"rarity": "epic",
		"rarity_label": "仙品",
		"icon": "res://assets/art/icon_regen.png"
	},
]

static func get_random_upgrades(count: int = 3) -> Array[Dictionary]:
	var pool := UPGRADES.duplicate()
	pool.shuffle()
	var result: Array[Dictionary] = []
	for i in range(mini(count, pool.size())):
		var u: Dictionary = pool[i].duplicate()
		u["border_color"] = RARITY_COLORS.get(u.get("rarity", "common"), Color.WHITE)
		result.append(u)
	return result

static func get_upgrade_def(upgrade_id: String) -> Dictionary:
	for u in UPGRADES:
		if u.get("id", "") == upgrade_id:
			var copy: Dictionary = u.duplicate()
			copy["border_color"] = RARITY_COLORS.get(copy.get("rarity", "common"), Color.WHITE)
			return copy
	return {}

