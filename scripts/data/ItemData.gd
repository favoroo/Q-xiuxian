class_name ItemData
extends RefCounted

## 法宝（被动道具）数据库：独立于法器的被动物品，买即生效、无限持有、无栏位限制
## 档位 tier 1~4（凡品/良品/仙品/传说，仿土豆兄弟道具档位）：决定基准价与出现权重，
## 档位解锁波次与权重公式在 GameBalance.item_tier_weights，定价在 GameBalance.item_price。
##
## apply 复用加点字段白名单（GameBalance.upgrade_fields()），由 GameManager._apply_stat_fields 统一落地，
## 与悟道加点共用同一条属性链路。卡面/详情卡的加成行由 BonusRows 从 apply 直接生成（正绿负红），
## desc 只写 apply 之外的机制说明，不再手抄数值——数字与生效幅度天然同源。
## 独特机制走额外字段（由对应系统消费，不进 apply）：
##   wave_heal_pct —— 波末按气血上限百分比回血（GameManager.apply_harvest 结算）
##   revive        —— 致死一击时消耗本法宝免死并回半血（GameManager.try_revive）
##   chest_magnet  —— 砸开宝箱掉出的灵石当场飞向玩家（SpiritChest._drop_gems 消费，可叠多件）
## 2026-10-12 土豆兄弟式「属性转化」核心件（同样走额外字段，item_hook_sum 现算，多件叠系数）：
##   dmg_per_move_speed  —— 疾风刃：移速每超基础 10% 折算一份全伤害（CultivatorSystem.damage_mult）
##   crit_per_dodge      —— 幻影迷踪铃：每 10% 有效闪避折算一份暴击率（GameManager.get_crit_rate）
##   dmg_per_armor       —— 山岳战甲：每点有效护甲折算一份全伤害（damage_mult）
##   dmg_per_max_hp      —— 血盘古玉：每 50 点最大气血折算一份全伤害（damage_mult）
##   dmg_per_100_stones + stone_dmg_cap —— 聚宝盆：每持 100 灵石一份全伤害，带总上限（damage_mult）
##   dmg_per_missing_hp  —— 燃血符：每损失 10% 气血折算一份全伤害（damage_mult）
##   still_damage + still_seconds —— 不动明王印：站定 N 秒后全伤害乘区（damage_mult 读 still_time）
##   kill_explode + kill_explode_radius —— 裂魂铃：击杀爆炸（EnemyBase._die，半径 = 判定同源）
## 转化件的机制数字写在 desc（同回春葫芦/替身娃娃先例）；apply 留空，卡面加成行不冒第二份数字。
## unique: true 时每局限购一件，买后即从货架池剔除

const TIER_LABELS := {1: "普通", 2: "稀有", 3: "史诗", 4: "传说"}
const TIER_COLORS := {
	1: GameStyle.RARITY_COMMON,
	2: GameStyle.RARITY_RARE,
	3: GameStyle.RARITY_EPIC,
	4: GameStyle.RARITY_LEGEND,
}

const DEFS: Dictionary = {
	# ==================== 凡品（tier 1 · 第 1 波起） ====================
	"jubaopen": {
		"name": "储蓄罐", "tier": 1, "price": 14,
		"icon": "res://assets/art/item_jubaopen.png",
		"desc": "每波结束白得金币与经验",
		"apply": {"harvest": 6.0},
	},
	"mibao_luopan": {
		"name": "寻宝罗盘", "tier": 1, "price": 12,
		"icon": "res://assets/art/item_mibao_luopan.png",
		"desc": "高稀有度的悟道候选与法宝更易出现",
		"apply": {"luck": 5.0},
	},
	"qiankun_dai": {
		"name": "拾取袋", "tier": 1, "price": 12,
		"icon": "res://assets/art/item_qiankun_dai.png",
		"desc": "",
		"apply": {"pickup_range_mult": 0.3},
	},
		"jifeng_xue": {
			"name": "速跑靴", "tier": 1, "price": 13,
			"icon": "res://assets/art/item_jifeng_xue.png",
			"desc": "",
			"apply": {"move_speed_mult": 0.07},
		},
		"qingxin_cha": {
			"name": "速攻药", "tier": 1, "price": 14,
			"icon": "res://assets/art/item_qingxin_cha.png",
			"desc": "",
			"apply": {"attack_speed_mult_mul": 0.92},
		},

		# ==================== 良品（tier 2 · 第 4 波起） ====================
	"zhekou_yufu": {
		"name": "折扣券", "tier": 2, "price": 26,
		"icon": "res://assets/art/item_zhekou_yufu.png",
		"desc": "商店全场 8 折，可叠加",
		"apply": {"shop_price_mul": 0.92},
	},
	"kuangxue_dan": {
		"name": "狂暴药", "tier": 2, "price": 24,
		"icon": "res://assets/art/item_kuangxue_dan.png",
		"desc": "",
		"apply": {"weapon_damage_mult": 0.18, "armor": -2.0},
	},
	"guijia_fu": {
		"name": "龟甲", "tier": 2, "price": 24,
		"icon": "res://assets/art/item_guijia_fu.png",
		"desc": "",
		"apply": {"armor": 4.0, "move_speed_mult": -0.06},
	},
	"tongxuan_ling": {
		"name": "重掷令", "tier": 2, "price": 22,
		"icon": "res://assets/art/item_tongxuan_ling.png",
		"desc": "",
		"apply": {"free_rerolls": 1.0},
	},
		"leiyin_zhen": {
			"name": "雷击针", "tier": 2, "price": 25,
			"icon": "res://assets/art/item_leiyin_zhen.png",
			"desc": "",
			"apply": {"knockback_mult": 0.35},
		},
		"yinhun_deng": {
			"name": "引路灯", "tier": 2, "price": 25,
			"icon": "res://assets/art/item_yinhun_deng.png",
			"desc": "",
			"apply": {"pickup_range_mult": 0.25, "attack_range_mult": 0.15},
		},
		"suoling_jia": {
			"name": "狂战枷", "tier": 2, "price": 26,
			"icon": "res://assets/art/item_suoling_jia.png",
			"desc": "",
			"apply": {"weapon_damage_mult": 0.22, "move_speed_mult": -0.06},
		},
		"lingbo_xue": {
			"name": "凌波靴", "tier": 2, "price": 25,
			"icon": "res://assets/art/item_lingbo_xue.png",
			"desc": "",
			"apply": {"dodge": 0.06, "armor": -1.0},
		},

		# ==================== 仙品（tier 3 · 第 9 波起） ====================
		"wuxing_pei": {
			"name": "五行石", "tier": 3, "price": 45,
			"icon": "res://assets/art/item_wuxing_pei.png",
			"desc": "",
			"apply": {"element_damage_all": 0.06},
		},
		"wujian_shi": {
			"name": "经验石", "tier": 3, "price": 42,
			"icon": "res://assets/art/item_wujian_shi.png",
			"desc": "",
			"apply": {"xp_gain_mult": 0.12},
		},
		"huichun_hulu": {
			"name": "回复葫芦", "tier": 3, "price": 48,
			"icon": "res://assets/art/item_huichun_hulu.png",
			"desc": "每波结束恢复15%生命",
			"apply": {"hp_regen": 0.5},
			"wave_heal_pct": 0.15,
		},
		"pojia_zhui": {
			"name": "破甲针", "tier": 3, "price": 40,
			"icon": "res://assets/art/item_pojia_zhui.png",
			"desc": "",
			"apply": {"elite_damage": 0.25},
		},
		"xiuluo_pei": {
			"name": "嗜血石", "tier": 3, "price": 46,
			"icon": "res://assets/art/item_xiuluo_pei.png",
			"desc": "",
			"apply": {"lifesteal": 0.04, "weapon_damage_mult": 0.12, "armor": -1.0},
		},

		# ==================== 传说（tier 4 · 第 14 波起） ====================
		"tisi_kuilei": {
			"name": "替身娃娃", "tier": 4, "price": 90,
			"icon": "res://assets/art/item_tisi_kuilei.png",
			"desc": "致死一击时娃娃碎裂：免死并恢复50%生命\n（每局限购一件，一次性消耗）",
			"apply": {},
			"revive": true,
			"unique": true,
		},
		"hunyuan_zhu": {
			"name": "万能珠", "tier": 4, "price": 85,
			"icon": "res://assets/art/item_hunyuan_zhu.png",
			"desc": "",
			"apply": {"luck": 8.0, "harvest": 8.0},
		},
		"taiyi_jindan": {
			"name": "极效药丸", "tier": 4, "price": 88,
			"icon": "res://assets/art/item_taiyi_jindan.png",
			"desc": "",
			"apply": {"max_hp": 25.0, "hp_heal": 25.0, "weapon_damage_mult": 0.15, "armor": 2.0, "move_speed_mult": 0.05},
		},

		# ==================== 2026-10-10 新增 24 件（参考土豆兄弟道具池） ====================
		# 补四条伤害链路（近战/远程/元素/召唤）的物品支撑，首次启用单元素加成字段
		# element_damage_<五行>（专精流核心），并加一批「有得有失」的交易式道具。

		# ---- 凡品（tier 1 · 第 1 波起） ----
		"lijian_shi": {
			"name": "砺剑石", "tier": 1, "price": 14,
			"icon": "res://assets/art/item_lijian_shi.png",
			"desc": "",
			"apply": {"melee_damage": 2.0},
		},
		"feihuang_shi": {
			"name": "飞蝗石", "tier": 1, "price": 14,
			"icon": "res://assets/art/item_feihuang_shi.png",
			"desc": "",
			"apply": {"ranged_damage": 2.0},
		},
		"juling_fu": {
			"name": "聚灵符", "tier": 1, "price": 14,
			"icon": "res://assets/art/item_juling_fu.png",
			"desc": "",
			"apply": {"elemental_damage": 2.0},
		},
		"yuling_pai": {
			"name": "御灵牌", "tier": 1, "price": 14,
			"icon": "res://assets/art/item_yuling_pai.png",
			"desc": "",
			"apply": {"engineering_damage": 2.0},
		},
		"hupi_qun": {
			"name": "虎皮裙", "tier": 1, "price": 15,
			"icon": "res://assets/art/item_hupi_qun.png",
			"desc": "",
			"apply": {"max_hp": 12.0, "hp_heal": 12.0},
		},
		"manli_huwan": {
			"name": "蛮力护腕", "tier": 1, "price": 15,
			"icon": "res://assets/art/item_manli_huwan.png",
			"desc": "",
			"apply": {"weapon_damage_mult": 0.10, "attack_speed_mult_mul": 1.04},
		},

		# ---- 良品（tier 2 · 第 4 波起） ----
		"jinjing_shi": {
			"name": "金精石", "tier": 2, "price": 26,
			"icon": "res://assets/art/item_jinjing_shi.png",
			"desc": "",
			"apply": {"element_damage_metal": 0.08},
		},
		"chenxiang_mu": {
			"name": "沉香木", "tier": 2, "price": 26,
			"icon": "res://assets/art/item_chenxiang_mu.png",
			"desc": "",
			"apply": {"element_damage_wood": 0.08},
		},
		"hantan_yu": {
			"name": "寒潭玉", "tier": 2, "price": 26,
			"icon": "res://assets/art/item_hantan_yu.png",
			"desc": "",
			"apply": {"element_damage_water": 0.08},
		},
		"dihuo_jing": {
			"name": "地火精", "tier": 2, "price": 26,
			"icon": "res://assets/art/item_dihuo_jing.png",
			"desc": "",
			"apply": {"element_damage_fire": 0.08},
		},
		"houtu_he": {
			"name": "厚土核", "tier": 2, "price": 26,
			"icon": "res://assets/art/item_houtu_he.png",
			"desc": "",
			"apply": {"element_damage_earth": 0.08},
		},
		"liren_fu": {
			"name": "利刃符", "tier": 2, "price": 25,
			"icon": "res://assets/art/item_liren_fu.png",
			"desc": "",
			"apply": {"crit_rate": 0.06, "armor": -1.0},
		},
		"yinxue_zhu": {
			"name": "饮血珠", "tier": 2, "price": 25,
			"icon": "res://assets/art/item_yinxue_zhu.png",
			"desc": "",
			"apply": {"lifesteal": 0.03, "hp_regen": -0.3},
		},
		"dingxing_pan": {
			"name": "定星盘", "tier": 2, "price": 24,
			"icon": "res://assets/art/item_dingxing_pan.png",
			"desc": "",
			"apply": {"attack_range_mult": 0.15, "move_speed_mult": -0.04},
		},
		"jucai_dai": {
			"name": "聚财袋", "tier": 2, "price": 24,
			"icon": "res://assets/art/item_jucai_dai.png",
			"desc": "",
			"apply": {"harvest": 8.0, "weapon_damage_mult": -0.08},
		},
		"poxu_lingfu": {
			"name": "破虚符", "tier": 2, "price": 28,
			"icon": "res://assets/art/item_poxu_lingfu.png",
			"desc": "",
			"apply": {"bonus_pierce": 1.0, "attack_range_mult": -0.08},
		},
		"fanzhen_tongjia": {
			"name": "反震铜甲", "tier": 2, "price": 26,
			"icon": "res://assets/art/item_fanzhen_tongjia.png",
			"desc": "",
			"apply": {"thorns": 0.40, "armor": 2.0, "move_speed_mult": -0.04},
		},

		# ---- 仙品（tier 3 · 第 9 波起） ----
		"potian_zhui": {
			"name": "破天锥", "tier": 3, "price": 46,
			"icon": "res://assets/art/item_potian_zhui.png",
			"desc": "",
			"apply": {"crit_mult": 0.35},
		},
		"jingang_zhuo": {
			"name": "金刚琢", "tier": 3, "price": 44,
			"icon": "res://assets/art/item_jingang_zhuo.png",
			"desc": "",
			"apply": {"armor": 5.0, "dodge": -0.08},
		},
		"shenxing_xue": {
			"name": "神行靴", "tier": 3, "price": 43,
			"icon": "res://assets/art/item_shenxing_xue.png",
			"desc": "",
			"apply": {"move_speed_mult": 0.12, "attack_range_mult": -0.10},
		},
		"leiling_zhu": {
			"name": "雷灵珠", "tier": 3, "price": 46,
			"icon": "res://assets/art/item_leiling_zhu.png",
			"desc": "",
			"apply": {"attack_speed_mult_mul": 0.88, "luck": -3.0},
		},
		"juling_zhentu": {
			"name": "聚灵阵图", "tier": 3, "price": 48,
			"icon": "res://assets/art/item_juling_zhentu.png",
			"desc": "",
			"apply": {"engineering_damage": 4.0, "max_hp": 10.0, "hp_heal": 10.0},
		},
		"hunyuan_yiqifu": {
			"name": "混元一气符", "tier": 3, "price": 50,
			"icon": "res://assets/art/item_hunyuan_yiqifu.png",
			"desc": "",
			"apply": {"element_damage_all": 0.08},
		},
		"jingang_fumo_jia": {
			"name": "降魔宝甲", "tier": 3, "price": 48,
			"icon": "res://assets/art/item_jingang_fumo_jia.png",
			"desc": "",
			"apply": {"thorns": 0.60, "armor": 3.0, "max_hp": 25.0, "hp_heal": 25.0},
		},

		# ---- 传说（tier 4 · 第 14 波起） ----
		"zhuxian_sui": {
			"name": "诛仙剑穗", "tier": 4, "price": 92,
			"icon": "res://assets/art/item_zhuxian_sui.png",
			"desc": "",
			"apply": {"weapon_damage_mult": 0.30, "crit_rate": 0.08, "armor": -2.0},
		},
		"xuanwu_yin": {
			"name": "玄武印", "tier": 4, "price": 90,
			"icon": "res://assets/art/item_xuanwu_yin.png",
			"desc": "",
			"apply": {"max_hp": 40.0, "hp_heal": 40.0, "armor": 4.0, "move_speed_mult": -0.08},
		},
		"tianji_pan": {
			"name": "天机盘", "tier": 4, "price": 88,
			"icon": "res://assets/art/item_tianji_pan.png",
			"desc": "",
			"apply": {"luck": 10.0, "free_rerolls": 1.0, "harvest": 5.0},
		},
			"wuji_tianchuan_zhen": {
				"name": "洞虚针", "tier": 4, "price": 88,
				"icon": "res://assets/art/item_wuji_tianchuan_zhen.png",
				"desc": "",
				"apply": {"bonus_pierce": 2.0, "ranged_damage": 4.0},
			},

			# ---- 机关/召唤配套法宝 ----
			"luban_suo": {
				"name": "鲁班锁", "tier": 2, "price": 28,
				"icon": "res://assets/art/item_luban_suo.png",
				"desc": "榫卯严丝合缝",
				"apply": {"engineering_damage": 2.0},
			},
			"jiguan_hexin": {
				"name": "机簧核心", "tier": 3, "price": 48,
				"icon": "res://assets/art/item_jiguan_hexin.png",
				"desc": "机括极速运转",
				"apply": {"engineering_damage": 3.0, "attack_speed_mult_mul": 0.92},
			},

			# ---- 2026-10-11 寻宝流法宝（与悟道「宝箱数量/宝箱品质/开箱省力」同一条链路） ----
			# 兑现点全在 BalanceChest + WaveSpawner._spawn_chests + SpiritChest._destroy；
			# 藏宝图刻意做进凡品第 1 波就能刷到 —— 寻宝流得让人在第一波就撞见料。
			"cangbao_tu": {
				"name": "藏宝图", "tier": 1, "price": 15,
				"icon": "res://assets/art/item_cangbao_tu.png",
				"desc": "每波场上多刷几口宝箱",
				"apply": {"chest_count": 1},
			},
			"naling_zhuo": {
				"name": "纳灵盘", "tier": 2, "price": 26,
				"icon": "res://assets/art/item_naling_zhuo.png",
				"desc": "宝箱砸开时掉出的金币直接飞进袖中，回春葫芦仍需贴身",
				"apply": {"pickup_range_mult": 0.2},
				"chest_magnet": true,
			},
			"liexia_zhui": {
				"name": "卸匣锥", "tier": 2, "price": 28,
				"icon": "res://assets/art/item_liexia_zhui.png",
				"desc": "砸开宝箱所需击数减少；法器攻击间隔 +5%",
				"apply": {"chest_break": 1, "attack_speed_mult_mul": 1.05},
			},
		"dianjin_jue": {
			"name": "点金诀", "tier": 3, "price": 46,
			"icon": "res://assets/art/item_dianjin_jue.png",
			"desc": "铜匣与玉匣更易出现，玉匣砸开必送法宝",
			"apply": {"chest_quality": 4.0},
		},

		# ---- 2026-10-12 土豆兄弟式「属性转化」核心件 + 单元素仙品 ----
		# 转化件全部走额外字段（item_hook_sum 现算，机制数字写在 desc）；图标暂借同系现有贴图占位，
		# TODO(media-gen)：这批法宝待 media-gen 出专属图标后替换并补 manifest。
		"jifeng_ren": {
			"name": "疾风刃", "tier": 3, "price": 46,
			"icon": "res://assets/art/item_shenxing_xue.png",
			"desc": "身法越快刃越利：移速每超基础10%，全伤害+4%",
			"apply": {},
			"dmg_per_move_speed": 0.04,
		},
		"huanying_ling": {
			"name": "幻影迷踪铃", "tier": 3, "price": 46,
			"icon": "res://assets/art/item_lingbo_xue.png",
			"desc": "铃声扰敌心神的刹那即是破绽：每10%闪避化为+5%暴击率",
			"apply": {},
			"crit_per_dodge": 0.05,
		},
		"shanyue_jia": {
			"name": "山岳战甲", "tier": 3, "price": 48,
			"icon": "res://assets/art/item_guijia_fu.png",
			"desc": "甲越厚势越沉：每点护甲+1.5%全伤害",
			"apply": {},
			"dmg_per_armor": 0.015,
		},
		"xuepan_guyu": {
			"name": "血盘古玉", "tier": 4, "price": 88,
			"icon": "res://assets/art/item_hupi_qun.png",
			"desc": "气血如炉：每50点最大生命+1%全伤害",
			"apply": {},
			"dmg_per_max_hp": 0.01,
		},
		"jubao_pen": {
			"name": "聚宝盆", "tier": 3, "price": 48,
			"icon": "res://assets/art/item_jubaopen.png",
			"desc": "财大气粗：每持100金币+3%全伤害（至多+30%）",
			"apply": {},
			"dmg_per_100_stones": 0.03, "stone_dmg_cap": 0.30,
		},
		"ranxue_fu": {
			"name": "燃血符", "tier": 3, "price": 44,
			"icon": "res://assets/art/item_xiuluo_pei.png",
			"desc": "以血为引：每损失10%生命+2.5%全伤害",
			"apply": {},
			"dmg_per_missing_hp": 0.025,
		},
		"budong_yin": {
			"name": "不动明王印", "tier": 3, "price": 48,
			"icon": "res://assets/art/item_xuanwu_yin.png",
			"desc": "站定1秒后全伤害+30%，脚底一动即失效",
			"apply": {},
			"still_damage": 0.30, "still_seconds": 1.0,
		},
		"liehun_ling": {
			"name": "裂魂铃", "tier": 4, "price": 92,
			"icon": "res://assets/art/item_leiyin_zhen.png",
			"desc": "被杀的妖兽当场爆开，伤及周身同伴（伤害随元素成长）\n（每局限购一件）",
			"apply": {},
			"kill_explode": 40.0, "kill_explode_radius": 90.0,
			"unique": true,
		},

		# ---- 单元素仙品（tier 3）：专精流后期核心，幅度是良品单元素石的近两倍 ----
		"taijin_jing": {
			"name": "太白金精", "tier": 3, "price": 46,
			"icon": "res://assets/art/item_jinjing_shi.png",
			"desc": "",
			"apply": {"element_damage_metal": 0.15},
		},
		"yimu_sui": {
			"name": "乙木灵髓", "tier": 3, "price": 46,
			"icon": "res://assets/art/item_chenxiang_mu.png",
			"desc": "",
			"apply": {"element_damage_wood": 0.15},
		},
		"xuanshui_po": {
			"name": "玄水精魄", "tier": 3, "price": 46,
			"icon": "res://assets/art/item_hantan_yu.png",
			"desc": "",
			"apply": {"element_damage_water": 0.15},
		},
		"lihuo_shenjing": {
			"name": "离火神晶", "tier": 3, "price": 46,
			"icon": "res://assets/art/item_dihuo_jing.png",
			"desc": "",
			"apply": {"element_damage_fire": 0.15},
		},
		"houtu_shenyuan": {
			"name": "后土神源", "tier": 3, "price": 46,
			"icon": "res://assets/art/item_houtu_he.png",
			"desc": "",
			"apply": {"element_damage_earth": 0.15},
		},
}

static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, {})

static func all_ids() -> Array:
	return DEFS.keys()

static func tier_label(tier: int) -> String:
	return TIER_LABELS.get(clampi(tier, 1, 4), "普通")

static func tier_color(tier: int) -> Color:
	return TIER_COLORS.get(clampi(tier, 1, 4), TIER_COLORS[1])

## 抽一件法宝上货架：按档位权重抽取（公式见 GameBalance.item_tier_weights），
## 已持有的 unique 法宝从池中剔除；若传入 unlocked_items，则未解锁法宝不入池；池空返回 ""，调用方落回法器位
static func pick_id(luck: float, wave: int, owned: Array, rng: RandomNumberGenerator, unlocked_items: Array = []) -> String:
	var tier_w: Array = GameBalance.item_tier_weights(luck, wave)
	var pool: Array = []
	var weights: Array = []
	for id in DEFS.keys():
		if not unlocked_items.is_empty() and not (id in unlocked_items):
			continue
		var d: Dictionary = DEFS[id]
		if bool(d.get("unique", false)) and id in owned:
			continue
		var tier := clampi(int(d.get("tier", 1)), 1, 4)
		var w := float(tier_w[tier - 1])
		if w <= 0.0:
			continue
		pool.append(id)
		weights.append(w)
	if pool.is_empty():
		return ""
	var active_rng: RandomNumberGenerator = rng if rng != null else GameManager.rng
	var roll: float = active_rng.randf()
	return String(pool[GameBalance.weighted_pick_index(weights, roll)])
