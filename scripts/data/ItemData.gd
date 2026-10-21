class_name ItemData
extends RefCounted

## 道具（被动道具）数据库：独立于武器的被动物品，买即生效、无限持有、无栏位限制
## 档位 tier 1~4（普通/稀有/史诗/传说，对齐土豆兄弟道具档位）：决定基准价与出现权重，
## 档位解锁回合与权重公式在 GameBalance.item_tier_weights，定价在 GameBalance.item_price。
##
## apply 复用加点字段白名单（GameBalance.upgrade_fields()），由 GameManager._apply_stat_fields 统一落地，
## 与悟道加点共用同一条属性链路。卡面/详情卡的加成行由 BonusRows 从 apply 直接生成（正绿负红），
## desc 只写 apply 之外的机制说明，不再手抄数值——数字与生效幅度天然同源。
## 独特机制走额外字段（由对应系统消费，不进 apply）：
##   wave_heal_pct —— 回合末按生命上限百分比回血（GameManager.apply_harvest 结算）
##   revive        —— 致死一击时消耗本道具免死并回半血（GameManager.try_revive）
##   chest_magnet  —— 砸开宝箱掉出的经验球当场飞向玩家（SpiritChest._drop_gems 消费，可叠多件）
## 2026-10-12 土豆兄弟式「属性转化」核心件（同样走额外字段，item_hook_sum 现算，多件叠系数）：
##   dmg_per_move_speed  —— 疾风刃：移速每超基础 10% 折算一份全伤害（CultivatorSystem.damage_mult）
##   crit_per_dodge      —— 幻影迷踪铃：每 10% 有效闪避折算一份暴击率（GameManager.get_crit_rate）
##   dmg_per_armor       —— 山岳战甲：每点有效护甲折算一份全伤害（damage_mult）
##   dmg_per_max_hp      —— 血盘古玉：每 50 点最大生命折算一份全伤害（damage_mult）
##   dmg_per_100_stones + stone_dmg_cap —— 聚宝盆：每持 100 金币一份全伤害，带总上限（damage_mult）
##   dmg_per_missing_hp  —— 燃血符：每损失 10% 生命折算一份全伤害（damage_mult）
##   still_damage + still_seconds —— 不动明王印/磐石印：站定 N 秒后全伤害乘区（damage_mult 读 still_time）
##   kill_explode + kill_explode_radius —— 裂魂铃：击杀爆炸（EnemyBase._die，半径 = 判定同源）
## 2026-10-12 深度联动与站定流道具核心件（额外字段，item_hook_sum 现算）：
##   still_regen_pct     —— 打坐蒲团：站定每秒回复最大生命比例（Player.gd 消费）
##   still_dodge         —— 入定香：站定闪避率加成（GameManager.get_effective_dodge）
##   still_armor         —— 入定香/玄武法坛：站定护甲加成（GameManager.get_effective_armor）
##   （still_knockback 已于 2026-10-20 随击退系移除，字段保留但无道具使用）
##   still_thorns        —— 玄武法坛：站定反伤比例加成（EnemyBase._resolve_contact_damage）
##   still_attack_speed  —— 金刚神像：站定不动时攻击间隔缩减（GameManager.get_effective_attack_speed_mult）
##   dmg_per_empty_slot  —— 三昧归真：武器少于 4 把时每少 1 把全伤害加成（CultivatorSystem.damage_mult）
##   heal_buff_damage / heal_buff_speed / heal_buff_dur —— 灵髓丹气：吃药/回复珠后短时爆发（Player.heal）
##   dodge_heal_chance / dodge_heal_hp —— 流云潜影玉：闪避成功概率回血（Player.take_damage）
##   crit_kill_stone_chance —— 金芒搜魂令：暴击击杀概率额外得金币（GameManager.register_kill）
##   turret_haste        —— 天工发条：机关炮台攻击间隔缩减（TurretUnit.gd）
##   drone_spin_speed    —— 天工发条：环绕物旋转速度加成（SunOrb.gd）
##   projectile_count_bonus —— 千符连环印：符箓与远程弹丸武器额外弹丸数（FloatingWeapon.gd）
##   wide_range_mult     —— 开山重刃谱：横扫类武器范围加成（FloatingWeapon.gd）
##   melee_lifesteal_flat —— 开山重刃谱：近战命中吸血固定值（FloatingWeapon.gd）
##   skill_cooldown_mult —— 凝神符：随行技能冷却缩减比例（SkillData.final_stats）
##   wave_end_max_hp / wave_end_regen / wave_end_lifesteal —— 突破古玉：回合结束永久成长（GameManager.apply_harvest）
## 2026-10-21 角色专属玩法补充（同样走额外字段，item_hook_sum 现算）：
##   dmg_per_nearby_enemy + dmg_per_nearby_enemy_cap —— 战旗：附近敌人越多全伤害越高（CultivatorSystem.damage_mult）
##   dmg_per_unique_item + dmg_per_unique_item_cap   —— 藏珍卷：每持有一种不同道具全伤害加成（同上）
##   on_hit_damage_bonus —— 血海符：受击叠层增伤，与嗜血魔修同一条乘区（CultivatorSystem.damage_mult / GameManager.on_player_hit）
##   heal_orb_chance     —— 灵草袋：敌人死亡额外掉回复珠概率（EnemyBase 掉落块）
##   （吸血类走 apply 的 "lifesteal" 键即可，无需专属钩子：血纹符 / 饮血珠 / 嗜血石。
##    吸血概率在 GameManager.try_lifesteal 里按武器攻击方式打折，见 BalanceTargeting.lifesteal_weapon_mult）
## 转化件的机制数字写在 desc（同回复葫芦/替身娃娃先例）；apply 留空，卡面加成行不冒第二份数字。
## unique: true 时每局限购一件：本局买过（或被玉匣送过）就再不进货架池，出售也不解禁
##
## 出售（2026-10-12 用户：「商店里的这些道具，如果有买到不想要的，也可以卖掉」）：
## 回收价与武器、灵兽同一条口径 —— 基准价 × SELL_RATIO，不跟着回合加价涨。
## 上架价 = 基准价 + 2×(回合−1)（BalanceEconomy.ITEM_WAVE_STEP），所以后期那件退货是亏的：
## 亏多少由详情卡上「原价 / 出售返还」两行自己摆出来，不藏。

const TIER_LABELS := {1: "普通", 2: "稀有", 3: "史诗", 4: "传说"}
const SELL_RATIO: float = 0.5  ## 出售回收比例（对齐 WeaponData.SELL_RATIO / PetData.SELL_RATIO）
const TIER_COLORS := {
	1: GameStyle.RARITY_COMMON,
	2: GameStyle.RARITY_RARE,
	3: GameStyle.RARITY_EPIC,
	4: GameStyle.RARITY_LEGEND,
}

const DEFS: Dictionary = {
	# ==================== 普通（tier 1 · 第 1 波起） ====================
	"jubaopen": {
		"name": "储蓄罐", "tier": 1, "price": 14,
		"icon": "res://assets/art/item_jubaopen.png",
		"desc": "每回合结束白得金币与经验",
		"apply": {"harvest": 6.0},
	},
	"mibao_luopan": {
		"name": "寻宝罗盘", "tier": 1, "price": 12,
		"icon": "res://assets/art/item_mibao_luopan.png",
		"desc": "高稀有度的悟道候选与道具更易出现",
		"apply": {"luck": 5.0},
	},
	# 2026-10-20 拾取袋（qiankun_dai）整系移除：拾取范围对任何流派都无感，玩家不会选。
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
			"lingshou_kouliang": {
				"name": "灵兽口粮", "tier": 1, "price": 16,
				"icon": "res://assets/art/item_lingshou_kouliang.png",
				"desc": "",
				"apply": {"pet_effect_mult": 0.20},
			},

		# ==================== 稀有（tier 2 · 第 4 波起） ====================
	"zhekou_yufu": {
		"name": "折扣券", "tier": 2, "price": 26,
		"icon": "res://assets/art/item_zhekou_yufu.png",
		"desc": "商店全场 8 折，最多叠到 7 折",
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
			"apply": {"armor": 3.0},
		},
		"yushou_ling": {
			"name": "驭兽铃", "tier": 2, "price": 28,
			"icon": "res://assets/art/item_yushou_ling.png",
			"desc": "",
			"apply": {"pet_damage_mult": 0.25},
		},
		"jifeng_shoufu": {
			"name": "疾风兽符", "tier": 2, "price": 26,
			"icon": "res://assets/art/item_jifeng_xue.png",
			"desc": "",
			"apply": {"pet_cooldown_mult_mul": 0.88},
		},
	"tongxuan_ling": {
		"name": "重掷令", "tier": 2, "price": 22,
		"icon": "res://assets/art/item_tongxuan_ling.png",
		"desc": "",
		"apply": {"free_rerolls": 1.0},
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

		# ==================== 史诗（tier 3 · 第 9 波起） ====================
		"wuxing_pei": {
			"name": "五行石", "tier": 3, "price": 45,
			"icon": "res://assets/art/item_wuxing_pei.png",
			"desc": "",
			"apply": {"element_damage_all": 0.07, "move_speed_mult": -0.04},
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
			"desc": "每回合结束恢复15%生命",
			"apply": {"hp_regen": 0.5},
			"wave_heal_pct": 0.15,
		},
		"pojia_zhui": {
			"name": "破甲针", "tier": 3, "price": 40,
			"icon": "res://assets/art/item_pojia_zhui.png",
			"desc": "",
			"apply": {"elite_damage": 0.25, "armor": -1.0},
		},
			"xiuluo_pei": {
				"name": "嗜血石", "tier": 3, "price": 46,
				"icon": "res://assets/art/item_xiuluo_pei.png",
				"desc": "",
				"apply": {"lifesteal": 0.04, "weapon_damage_mult": 0.12, "armor": -1.0},
			},
			"wanshou_long": {
				"name": "万兽笼", "tier": 3, "price": 55,
				"icon": "res://assets/art/item_cangbao_tu.png",
				"desc": "随行灵兽上限 +1\n（每局限购一件）",
				"apply": {"pet_slots": 1.0},
				"unique": true,
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
			"desc": "（每局限购一件）",
			"apply": {"max_hp": 25.0, "hp_heal": 25.0, "weapon_damage_mult": 0.15, "armor": 2.0, "move_speed_mult": 0.05, "attack_speed_mult_mul": 1.04},
			"unique": true,
		},

		# ==================== 2026-10-10 新增 24 件（参考土豆兄弟道具池） ====================
		# 补四条伤害链路（近战/远程/元素/召唤）的物品支撑，首次启用单元素加成字段
		# element_damage_<五行>（专精流核心），并加一批「有得有失」的交易式道具。

		# ---- 普通（tier 1 · 第 1 波起） ----
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
			"name": "召唤牌", "tier": 1, "price": 14,
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
		# 2026-10-19 低档吸血入口：此前吸血只有 tier2 起，前几波几乎见不到。
		# 数值按档位压低（+2%），用一点生命回复换，避免把高档饮血珠/嗜血石挤成废件。
		"xuewen_fu": {
			"name": "血纹符", "tier": 1, "price": 14,
			"icon": "res://assets/art/item_xuewen_fu.png",
			"desc": "",
			"apply": {"lifesteal": 0.02, "hp_regen": -0.2},
		},

		# ---- 稀有（tier 2 · 第 4 波起） ----
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
			"apply": {"attack_range_mult": 0.10, "move_speed_mult": -0.04},
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

		# ---- 史诗（tier 3 · 第 9 波起） ----
		"potian_zhui": {
			"name": "破天锥", "tier": 3, "price": 46,
			"icon": "res://assets/art/item_potian_zhui.png",
			"desc": "（每局限购一件）",
			"apply": {"crit_mult": 0.35, "move_speed_mult": -0.04},
			"unique": true,
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
			"apply": {"engineering_damage": 4.0, "max_hp": 10.0, "hp_heal": 10.0, "move_speed_mult": -0.04},
		},
		"hunyuan_yiqifu": {
			"name": "混元一气符", "tier": 3, "price": 50,
			"icon": "res://assets/art/item_hunyuan_yiqifu.png",
			"desc": "",
			"apply": {"element_damage_all": 0.09, "luck": -3.0},
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
			"desc": "（每局限购一件）",
			"apply": {"weapon_damage_mult": 0.30, "crit_rate": 0.08, "armor": -2.0},
			"unique": true,
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

				# ---- 机关/召唤配套道具 ----
				"luban_suo": {
					"name": "鲁班锁", "tier": 2, "price": 28,
					"icon": "res://assets/art/item_luban_suo.png",
					"desc": "榫卯严丝合缝",
					"apply": {"contraption_damage": 3.0},
				},
				"jiguan_hexin": {
					"name": "机簧核心", "tier": 3, "price": 48,
					"icon": "res://assets/art/item_jiguan_hexin.png",
					"desc": "机括极速运转",
					"apply": {"contraption_damage": 4.0, "attack_speed_mult_mul": 0.92},
				},

			# ---- 2026-10-11 寻宝流道具（与悟道「宝箱数量/宝箱品质/宝箱掉落」同一条链路） ----
			# 兑现点全在 BalanceChest + WaveSpawner._spawn_chests + SpiritChest._destroy；
			# 藏宝图刻意做进普通档第 1 波就能刷到 —— 寻宝流得让人在第一波就撞见料。
			"cangbao_tu": {
				"name": "藏宝图", "tier": 1, "price": 15,
				"icon": "res://assets/art/item_cangbao_tu.png",
				"desc": "每回合场上多刷几口宝箱",
				"apply": {"chest_count": 1},
			},
			"naling_zhuo": {
				"name": "纳灵盘", "tier": 2, "price": 22,
				"icon": "res://assets/art/item_naling_zhuo.png",
				"desc": "宝箱砸开时掉的掉落物当场飞进袖中，不必再绕一趟走位",
				"apply": {},
				"chest_magnet": true,
			},
		"dianjin_jue": {
			"name": "点金诀", "tier": 3, "price": 46,
			"icon": "res://assets/art/item_dianjin_jue.png",
			"desc": "铜匣与玉匣更易出现，玉匣砸开必送道具",
			"apply": {"chest_quality": 4.0},
		},

		# ---- 2026-10-12 土豆兄弟式「属性转化」核心件 + 单元素史诗 ----
		# 转化件全部走额外字段（item_hook_sum 现算，机制数字写在 desc）；图标暂借同系现有贴图占位，
		# TODO(media-gen)：这批道具待 media-gen 出专属图标后替换并补 manifest。
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
			"name": "山岳战甲", "tier": 4, "price": 90,
			"icon": "res://assets/art/item_guijia_fu.png",
			"desc": "甲越厚势越沉：每点护甲+1.5%全伤害",
			"apply": {},
			"dmg_per_armor": 0.015,
		},
		"xuepan_guyu": {
			"name": "血盘古玉", "tier": 4, "price": 88,
			"icon": "res://assets/art/item_hupi_qun.png",
			"desc": "生命如炉：每50点最大生命+1%全伤害",
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
			"desc": "被杀的敌人当场爆开，伤及周身同伴（伤害随元素成长）\n（每局限购一件）",
			"apply": {},
			"kill_explode": 40.0, "kill_explode_radius": 90.0,
			"unique": true,
		},

		# ---- 单元素史诗（tier 3）：专精流后期核心，幅度是稀有单元素石的近两倍 ----
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

			# ==================== 2026-10-12 深度联动与站定流道具（14 件） ====================
			# ---- 1. 站定/入定流（打坐修仙体系） ----
			"dazuo_putuan": {
				"name": "打坐蒲团", "tier": 1, "price": 16,
				"icon": "res://assets/art/item_dazuo_putuan.png",
				"desc": "站定不动时每秒恢复2%最大生命；身法略受拘束",
				"apply": {"move_speed_mult": -0.04},
				"still_regen_pct": 0.02,
			},
			"ruding_xiang": {
				"name": "入定香", "tier": 2, "price": 28,
				"icon": "res://assets/art/item_yinhun_deng.png",
				"desc": "凝神入定：站定不动时闪避率+25%，护甲+3",
				"apply": {},
				"still_dodge": 0.25, "still_armor": 3.0,
			},
				"xuanwu_fashan": {
					"name": "玄武法坛", "tier": 3, "price": 46,
					"icon": "res://assets/art/item_fanzhen_tongjia.png",
					"desc": "阵起玄武：站定不动时受击反伤+60%，护甲+3",
					"apply": {"attack_range_mult": -0.10},
					"still_armor": 3.0, "still_thorns": 0.6,
				},
				"jingang_shenxiang": {
					"name": "金刚神像", "tier": 3, "price": 46,
					"icon": "res://assets/art/item_xuanwu_yin.png",
					"desc": "金刚怒目：站定不动时攻击间隔-30%；身法略受拘束",
					"apply": {"move_speed_mult": -0.08},
					"still_attack_speed": 0.30,
				},
				"panshi_yin": {
				"name": "磐石印", "tier": 4, "price": 92,
				"icon": "res://assets/art/item_xuanwu_yin.png",
				"desc": "气沉丹田：站定1秒后全伤害+45%",
				"apply": {},
				"still_damage": 0.45, "still_seconds": 1.0,
			},

			# ---- 2. 角色机制与核心痛点联动 ----
			"sanmei_guizhen": {
				"name": "三昧归真", "tier": 4, "price": 88,
				"icon": "res://assets/art/item_lijian_shi.png",
				"desc": "残缺即圆满：上阵武器少于4把时，每少1把全伤害+15%（狂战士绝配）",
				"apply": {},
				"dmg_per_empty_slot": 0.15,
			},
			"lingsui_danqi": {
				"name": "灵髓丹气", "tier": 2, "price": 26,
				"icon": "res://assets/art/item_qingxin_cha.png",
					"desc": "药力发作：拾取回复珠或药爆后3秒内，全伤害+25%、移速+15%",
				"apply": {"hp_regen": -0.2},
				"heal_buff_damage": 0.25, "heal_buff_speed": 0.15, "heal_buff_dur": 3.0,
			},
			"liuyun_qianyin": {
				"name": "流云潜影玉", "tier": 3, "price": 46,
				"icon": "res://assets/art/item_lingbo_xue.png",
				"desc": "虚实莫测：成功闪避攻击时，50%概率回复3点生命",
				"apply": {"armor": -1.0},
				"dodge_heal_chance": 0.5, "dodge_heal_hp": 3.0,
			},
			"jinmang_souhun": {
				"name": "金芒搜魂令", "tier": 3, "price": 45,
				"icon": "res://assets/art/item_jinjing_shi.png",
				"desc": "剑芒截气：暴击击杀敌人时，有30%概率额外吸收1枚金币",
				"apply": {"weapon_damage_mult": -0.06},
				"crit_kill_stone_chance": 0.30,
			},

			# ---- 3. 武器器类与行为质变 ----
			"tiangong_fatiao": {
				"name": "天工发条", "tier": 2, "price": 28,
				"icon": "res://assets/art/item_tiangong_fatiao.png",
				"desc": "机括极转：机关炮台攻击间隔缩短20%，环绕武器旋转速度提升30%",
				"apply": {"luck": -2.0},
				"turret_haste": 0.20, "drone_spin_speed": 0.30,
			},
			"qianfu_lianhuan": {
				"name": "千符连环印", "tier": 3, "price": 50,
				"icon": "res://assets/art/item_juling_fu.png",
				"desc": "万符齐发：弹射类与远程武器发射弹丸数+1，弹丸散布角略微增加",
				"apply": {"attack_range_mult": -0.10},
				"projectile_count_bonus": 1,
			},
			"kaishan_jianyi": {
				"name": "开山重刃谱", "tier": 2, "price": 26,
				"icon": "res://assets/art/item_kaishan_jianyi.png",
				"desc": "大巧不工：横扫类武器挥砍范围+25%，近身挥砍命中时吸收1点生命（每秒至多2次）",
				"apply": {"move_speed_mult": -0.05},
				"wide_range_mult": 0.25, "melee_lifesteal_flat": 1.0,
			},

			# ---- 4. 随行技能与长线成长 ----
			"ningshen_fu": {
				"name": "凝神符", "tier": 2, "price": 28,
				"icon": "res://assets/art/item_chenxiang_mu.png",
				"desc": "心若冰清：随行技能冷却时间缩短10%；福缘 -2",
				"apply": {"luck": -2.0},
				"skill_cooldown_mult": 0.10,
			},
			"tupo_guyu": {
				"name": "突破古玉", "tier": 4, "price": 95,
				"icon": "res://assets/art/item_hunyuan_zhu.png",
				"desc": "道果累进：每回合结束时永久+3最大生命、+0.5生命回复、+1%吸血\n（每局限购一件，成长累计上限 +30 生命 / +5 回复 / +10% 吸血）",
				"apply": {},
				"unique": true,
				"wave_end_max_hp": 3.0, "wave_end_regen": 0.5, "wave_end_lifesteal": 0.01,
			},
			# ==================== 2026-10-20 新增：通用强力选项（补删件空位 + 直给输出/生存） ====================
			# 用户口径「值得选的东西太少」：这三件不挑流派，任何构筑都能吃到，专治「没东西可挑」。
			"xuantie_ling": {
				"name": "玄铁令", "tier": 3, "price": 46,
				"icon": "res://assets/art/item_suoling_jia.png",
				"desc": "玄铁压手：出刀略沉",
				"apply": {"weapon_damage_mult": 0.20, "attack_speed_mult_mul": 1.03},
			},
			"bumie_jinshen": {
				"name": "不灭金身", "tier": 4, "price": 90,
				"icon": "res://assets/art/item_jingang_fumo_jia.png",
				"desc": "金身沉重，步履稍缓",
				"apply": {"max_hp": 50.0, "hp_heal": 50.0, "armor": 4.0, "hp_regen": 1.0, "move_speed_mult": -0.04},
			},
			"tiangang_zhanyi": {
				"name": "天罡战意", "tier": 4, "price": 88,
				"icon": "res://assets/art/item_potian_zhui.png",
				"desc": "战意催命，护体略薄",
				"apply": {"crit_rate": 0.10, "crit_mult": 0.30, "armor": -1.0},
			},
			# ==================== 2026-10-21 流派补齐（1 主属性 + 1 跨流派负面） ====================
			# 补近战/远程/元素/召唤/机关/技能/闪避的物品入口，以及收藏家/蛮兵/嗜血魔修/灵植夫
			# 四个角色专属玩法的转化件。图标先借同系贴图占位，media-gen 出专属图后替换并补 manifest。
			"tieshou": {
				"name": "铁手套", "tier": 1, "price": 14,
				"icon": "res://assets/art/item_tieshou.png",
				"desc": "近身硬功，远程手法生疏",
				"apply": {"melee_damage": 2.0, "ranged_damage": -1.0},
			},
			"lingyan_fu": {
				"name": "灵焰符", "tier": 1, "price": 14,
				"icon": "res://assets/art/item_lingyan_fu.png",
				"desc": "灵焰催动略滞手势",
				"apply": {"elemental_damage": 2.0, "attack_speed_mult_mul": 1.03},
			},
			"tongling": {
				"name": "铜铃", "tier": 1, "price": 14,
				"icon": "res://assets/art/item_tongling.png",
				"desc": "铃声引灵，身法稍重",
				"apply": {"engineering_damage": 2.0, "move_speed_mult": -0.03},
			},
			"pojun_fu": {
				"name": "破军符", "tier": 2, "price": 26,
				"icon": "res://assets/art/item_pojun_fu.png",
				"desc": "重刃破军，出手距离略短",
				"apply": {"melee_damage": 4.0, "attack_range_mult": -0.05},
			},
			"liannu_shi": {
				"name": "连弩石", "tier": 2, "price": 26,
				"icon": "res://assets/art/item_liannu_shi.png",
				"desc": "机弩连发，射程略收",
				"apply": {"ranged_damage": 4.0, "attack_range_mult": -0.05},
			},
			"wuxing_sha": {
				"name": "五行砂", "tier": 2, "price": 26,
				"icon": "res://assets/art/item_wuxing_sha.png",
				"desc": "五行相激，生机略滞",
				"apply": {"elemental_damage": 4.0, "hp_regen": -0.3},
			},
			"tongji_chi": {
				"name": "铜机齿", "tier": 2, "price": 28,
				"icon": "res://assets/art/item_tongji_chi.png",
				"desc": "机齿咬合，负重增加",
				"apply": {"contraption_damage": 4.0, "move_speed_mult": -0.04},
			},
			"jingxin_fu": {
				"name": "静心符", "tier": 2, "price": 26,
				"icon": "res://assets/art/item_jingxin_fu.png",
				"desc": "静心凝神：随行技能冷却缩短；福缘 -1",
				"apply": {"skill_cooldown_mult": 0.08, "luck": -1.0},
			},
			"huansha": {
				"name": "幻纱", "tier": 2, "price": 26,
				"icon": "res://assets/art/item_huansha.png",
				"desc": "身轻如纱，护体略薄",
				"apply": {"dodge": 0.05, "move_speed_mult": 0.04, "armor": -1.0},
			},
			"lingcao_dai": {
				"name": "灵草袋", "tier": 2, "price": 24,
				"icon": "res://assets/art/item_lingcao_dai.png",
				"desc": "灵草滋生灵药：敌人死亡额外掉回复珠；自身回复略减",
				"apply": {"hp_regen": -0.3},
				"heal_orb_chance": 0.10,
			},
			"wanling_fan": {
				"name": "万灵幡", "tier": 3, "price": 48,
				"icon": "res://assets/art/item_wanling_fan.png",
				"desc": "万灵来朝：召唤物与灵兽同受加持；幡重步缓",
				"apply": {"engineering_damage": 5.0, "pet_damage_mult": 0.15, "move_speed_mult": -0.04},
			},
			"tianji_suo": {
				"name": "天机锁", "tier": 3, "price": 46,
				"icon": "res://assets/art/item_tianji_suo.png",
				"desc": "天机咬合：机关运转更快；福缘 -2",
				"apply": {"contraption_damage": 6.0, "attack_speed_mult_mul": 0.94, "luck": -2.0},
			},
			"zhanqi": {
				"name": "战旗", "tier": 3, "price": 46,
				"icon": "res://assets/art/item_zhanqi.png",
				"desc": "战旗所指：每1个附近敌人全伤害+0.8%，至多+24%",
				"apply": {},
				"dmg_per_nearby_enemy": 0.008, "dmg_per_nearby_enemy_cap": 0.24,
			},
			"cangzhen_juan": {
				"name": "藏珍卷", "tier": 3, "price": 46,
				"icon": "res://assets/art/item_cangzhen_juan.png",
				"desc": "藏品越杂底蕴越厚：每1种不同道具全伤害+1.5%，至多+30%",
				"apply": {},
				"dmg_per_unique_item": 0.015, "dmg_per_unique_item_cap": 0.30,
			},
			"xuehai_fu": {
				"name": "血海符", "tier": 3, "price": 46,
				"icon": "res://assets/art/item_xuehai_fu.png",
				"desc": "受伤即蓄血海：每次受击叠1层，每层全伤害+1.5%，最多10层",
				"apply": {"armor": -2.0},
				"on_hit_damage_bonus": 0.015,
			},
			"daoyun_jing": {
				"name": "道蕴镜", "tier": 4, "price": 90,
				"icon": "res://assets/art/item_daoyun_jing.png",
				"desc": "镜照道蕴：随行技能冷却大幅缩短；出招略慢\n（每局限购一件）",
				"apply": {"skill_cooldown_mult": 0.25, "attack_speed_mult_mul": 0.92},
				"unique": true,
			},
			"wanshi_jian": {
				"name": "万矢箭", "tier": 4, "price": 88,
				"icon": "res://assets/art/item_wanshi_jian.png",
				"desc": "一箭化万矢：远程武器额外发射1枚弹丸；射程略收\n（每局限购一件）",
				"apply": {"ranged_damage": 6.0, "attack_range_mult": -0.10},
				"projectile_count_bonus": 1,
				"unique": true,
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

## 物品标签：从 apply / 额外字段自动派生，供 ItemOfferSystem 做构筑亲和。
## 不手工维护 tags 数组 —— 数值一改标签跟着变，避免「标签说近战、实际加远程」的脏数据。
const TAG_FIELDS := {
	"melee_damage": "melee", "ranged_damage": "ranged",
	"elemental_damage": "elemental", "engineering_damage": "summon",
	"contraption_damage": "contraption",
	"crit_rate": "crit", "crit_mult": "crit", "dodge": "dodge",
	"lifesteal": "lifesteal", "max_hp": "tank", "armor": "tank",
	"hp_regen": "heal", "thorns": "thorns", "move_speed_mult": "speed",
	"attack_speed_mult_mul": "haste", "attack_range_mult": "range",
	"bonus_pierce": "pierce", "harvest": "economy", "luck": "economy",
	"xp_gain_mult": "economy", "shop_price_mul": "economy",
	"free_rerolls": "economy", "spirit_stones": "economy",
	"chest_count": "chest", "chest_quality": "chest", "chest_reward": "chest",
	"pet_damage_mult": "pet", "pet_effect_mult": "pet",
	"pet_cooldown_mult_mul": "pet", "pet_slots": "pet",
	"skill_cooldown_mult": "skill",
}

const HOOK_TAGS := {
	"still_regen_pct": "still", "still_dodge": "still", "still_armor": "still",
	"still_thorns": "still", "still_attack_speed": "still", "still_damage": "still",
	"skill_cooldown_mult": "skill", "projectile_count_bonus": "projectile",
	"wide_range_mult": "wide", "melee_lifesteal_flat": "lifesteal",
	"heal_buff_damage": "heal", "dodge_heal_chance": "dodge",
	"turret_haste": "contraption", "drone_spin_speed": "summon",
	"dmg_per_nearby_enemy": "crowd", "dmg_per_unique_item": "collection",
	"on_hit_damage_bonus": "onhit", "heal_orb_chance": "heal",
	"kill_explode": "elemental", "dmg_per_move_speed": "speed",
	"crit_per_dodge": "dodge", "dmg_per_armor": "tank",
	"dmg_per_max_hp": "tank", "dmg_per_100_stones": "economy",
	"dmg_per_missing_hp": "lifesteal", "dmg_per_empty_slot": "generic",
	"wave_heal_pct": "heal", "chest_magnet": "chest", "revive": "tank",
}

static func tags_of(id: String) -> Array:
	var d: Dictionary = get_def(id)
	var out: Array = []
	if d.is_empty():
		return out
	var apply: Dictionary = d.get("apply", {})
	for k in apply.keys():
		var key := String(k)
		if key.begins_with("element_damage_") and key != "element_damage_all":
			var elem := key.trim_prefix("element_damage_")
			if not out.has(elem):
				out.append(elem)
			# 单元素件同时算「元素流」：雷法/符修的角色偏好标签能命中，具体五行另由 _element_hit 判。
			if not out.has("elemental"):
				out.append("elemental")
		var tag := String(TAG_FIELDS.get(key, ""))
		if tag != "" and not out.has(tag):
			out.append(tag)
	if apply.has("element_damage_all") and not out.has("elemental"):
		out.append("elemental")
	for k in d.keys():
		var tag := String(HOOK_TAGS.get(String(k), ""))
		if tag != "" and not out.has(tag):
			out.append(tag)
	return out

## 出售回收价：基准价 × SELL_RATIO（与 WeaponData.sell_price / PetData.sell_price 同一条口径：
## 按数据表里的基准价折半，不按当回合上架价 —— 上架价每回合 +2，回收不跟着涨，详情卡两行并排印出来）。
static func sell_price(id: String) -> int:
	var def: Dictionary = get_def(id)
	if def.is_empty():
		return 0
	return maxi(1, int(ceil(float(int(def.get("price", 20))) * SELL_RATIO)))

## 抽一件道具上货架：按档位权重抽取（公式见 GameBalance.item_tier_weights），
## bought = 本局已购入过的道具（含已出售的那件）：unique 道具只要买过一次就再不进池，
## 详情卡上「出售后本局不再出现」那句承诺由这里兑现。若传入 unlocked_items，则未解锁道具不入池；
## gm 可选透传（满穿透闸 PierceLimit：阵容穿透顶到上限后穿透道具停刷）；
## 池空返回 ""，调用方落回武器位
static func pick_id(luck: float, wave: int, bought: Array, rng: RandomNumberGenerator, unlocked_items: Array = [], gm: Node = null) -> String:
	# 先按构筑感知过滤收一版池（玩剑系就不刷纯召唤/机关/单元素/灵兽/寻宝件）；
	# 池被过滤空时回退到未过滤池，绝不让货架落空（2026-10-20）
	var picked := _pick_id_filtered(luck, wave, bought, rng, unlocked_items, gm, true)
	if picked != "":
		return picked
	return _pick_id_filtered(luck, wave, bought, rng, unlocked_items, gm, false)

static func _pick_id_filtered(luck: float, wave: int, bought: Array, rng: RandomNumberGenerator,
		unlocked_items: Array, gm: Node, apply_build_filter: bool) -> String:
	var tier_w: Array = GameBalance.item_tier_weights(luck, wave)
	var pool: Array = []
	var weights: Array = []
	for id in DEFS.keys():
		if not unlocked_items.is_empty() and not (id in unlocked_items):
			continue
		# 满穿透时不进穿透道具（破虚符/裂空锥/洞虚针），判定收口在 PierceLimit
		if gm != null and not PierceLimit.filter_item_id(gm, id):
			continue
		var d: Dictionary = DEFS[id]
		if bool(d.get("unique", false)) and id in bought:
			continue
		# 构筑感知过滤：只滤纯条件件，混装件放行
		if apply_build_filter and gm != null and not BalanceBuildFilter.item_allowed(gm, String(id)):
			continue
		var tier := clampi(int(d.get("tier", 1)), 1, 4)
		var w := float(tier_w[tier - 1])
		if w <= 0.0:
			continue
		# 构筑亲和（2026-10-21）：档位权重 × 当前武器类别/五行/角色偏好/已持有同类。
		# gm 为空时倍率恒 1，单测的纯池抽取仍可钉住。
		w *= BalanceBuildFilter.item_affinity(gm, String(id))
		pool.append(id)
		weights.append(w)
	if pool.is_empty():
		return ""
	var active_rng: RandomNumberGenerator = rng if rng != null else GameManager.rng
	var roll: float = active_rng.randf()
	return String(pool[GameBalance.weighted_pick_index(weights, roll)])
