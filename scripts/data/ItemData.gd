class_name ItemData
extends RefCounted

## 道具（被动道具）数据库：独立于武器的被动物品，买即生效、无限持有、无栏位限制
## 档位 tier 1~4（普通/稀有/史诗/传说，对齐土豆兄弟道具档位）：决定基准价与出现权重，
## 档位解锁回合与权重公式在 GameBalance.item_tier_weights，定价在 GameBalance.item_price。
## tier 5「逆天」是超级悟道专属的神通（2026-10-25）：带 granted_only + no_sell 两标记，
## 不进商店货架池（_pick_id_filtered / ShopSystem.apply_main_item_pity 都跳过）、不进图鉴
## （ManualDialog 只扫 1~4 档）、不可出售（GameManager.sell_item 直接拒收）。
## 每局只经 SuperUpgradeData 赠送一次，玩法上等价于一件「祝福」。
## nightmare_only（2026-10-30）：只在噩梦难度（GameManager.danger_level >= 1）进抽池 ——
## 硬闸开在 _pick_id_filtered 里（与 granted_only 同层，抽池兜底的未过滤全池也不放行），
## 普通难度的货架 / 玉匣 / 精英掉落三条来源全不出；视野件用它，抽到就是废件。
##
## apply 复用加点字段白名单（GameBalance.upgrade_fields()），由 GameManager._apply_stat_fields 统一落地，
## 与悟道加点共用同一条属性链路。卡面/详情卡的加成行由 BonusRows 从 apply 直接生成（正绿负红），
## desc 只写 apply 之外的机制说明，不再手抄数值——数字与生效幅度天然同源。
## hp_heal 恒与同 apply 里的 max_hp 同值成对（新上限自带满血），卡面折叠不单列（BonusRows.folded_keys）；
## 新件别写不等值的回血数，不等值时回血行会重新冒出来。
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
## 2026-10-25 超级悟道（神通）新增两条机制钩子：
##   weapon_slot_bonus —— 开天辟地：上阵武器槽位 +1（GameManager.max_weapon_slots 读侧叠加）
##   kill_cd_refund    —— 杀戮节奏：击杀返还所有武器当前冷却比例（EnemyDeathFx.drops 读侧）
## 2026-10-25 超级悟道「三道」重构后的机制钩子（全部读侧现算，不进 apply）：
##   melee_range_mult —— 剑气凌霄：近战/横扫判定半径倍率（MeleeHandler/SweepHandler.arc_radius）
##   sword_qi          —— 万剑归宗：剑系出手攒剑意，攒满幻化剑阵驻场数秒（SwordPhantom.tick_attack）
##   projectile_count_bonus / projectile_damage_mult —— 万箭齐发：多发但单发打折（ProjectileHandler）
##   projectile_bounce_bonus —— 弹幕回响：弹丸出膛时叠加弹射次数（ProjectileHandler）
##   attack_chain_lightning  —— 紫电：每 N 次攻击放连锁闪电（FloatingWeapon._perform_attack）
##   kill_chain_lightning    —— 雷劫：击杀时放连锁闪电（EnemyDeathFx.drops）
##   crit_sky_bolt / chain_hop_bonus —— 天罚：暴击落雷 + 链电跳数加成（OnHitEffects / ChainLightning）
##   projectile_chain_lightning —— 雷霆弹幕（共鸣）：弹丸命中时也链电（OnHitEffects.on_projectile_hit）
##   thorns_electric   —— 反震电场：受击时向周围放电（Player.take_damage → OnHitEffects）
##   wuxing_rotation_chance —— 五行轮转：命中按几率附加随机五行异常（OnHitEffects._roll_wuxing）
## 数值口径统一在 scripts/systems/BalanceChain.gd，调参只改那一处。
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

const TIER_LABELS := {1: "普通", 2: "稀有", 3: "史诗", 4: "传说", 5: "逆天"}
const SELL_RATIO: float = 0.5  ## 出售回收比例（对齐 WeaponData.SELL_RATIO / PetData.SELL_RATIO）
const TIER_COLORS := {
	1: GameStyle.RARITY_COMMON,
	2: GameStyle.RARITY_RARE,
	3: GameStyle.RARITY_EPIC,
	4: GameStyle.RARITY_LEGEND,
	5: GameStyle.RARITY_MYTHIC,
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
			"apply": {"armor": 4.0},
		},
		"yushou_ling": {
			"name": "驭兽铃", "tier": 2, "price": 28,
			"icon": "res://assets/art/item_yushou_ling.png",
			"desc": "",
			"apply": {"pet_damage_mult": 0.25},
		},
		"jifeng_shoufu": {
			"name": "疾风兽符", "tier": 2, "price": 26,
			"icon": "res://assets/art/item_jifeng_shoufu.png",
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
				"icon": "res://assets/art/item_wanshou_long.png",
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
			# 2026-10-22 由 幸运+8/收益+8 提到 +12/+10：原数值被同价位的天机盘
			# （幸运+10、免费重掷+1、收益+5）全面支配，传说档纯数值件不该输给同档机制件。
			"apply": {"luck": 12.0, "harvest": 10.0},
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
			# 2026-10-22 收益 8→15、武器伤害代价 −8%→−5%：原版比普通档储蓄罐（14 金/收益+6/无代价）
			# 只多 2 点收益却贵 10 金还永久 −8% 伤害，被同价位与免费加点两头夹。现按「高投入高回报」重定。
			"apply": {"harvest": 15.0, "weapon_damage_mult": -0.05},
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
					"desc": "机关伤害提升",
					"apply": {"contraption_damage": 3.0},
				},
				"jiguan_hexin": {
					"name": "机簧核心", "tier": 3, "price": 48,
					"icon": "res://assets/art/item_jiguan_hexin.png",
					"desc": "机关伤害与攻速提升",
					"apply": {"contraption_damage": 5.0, "attack_speed_mult_mul": 0.92},
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
			# 2026-10-22 纳灵盘（chest_magnet）整件移除：用户口径「自动吸附掉落物的都没用」。
			# 它只省一趟走位、不改任何收益量，同价位重掷令直接换钱 ⇒ 永远是垫底选择。
			# chest_magnet 机制本身保留（SpiritChest._drop_gems 仍认这个字段），只是暂无道具使用。
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
			"icon": "res://assets/art/item_jifeng_ren.png",
			"desc": "身法越快刃越利：移速每超基础10%，全伤害+4%",
			"apply": {},
			"dmg_per_move_speed": 0.04,
		},
		"huanying_ling": {
			"name": "幻影迷踪铃", "tier": 3, "price": 46,
			"icon": "res://assets/art/item_huanying_ling.png",
			"desc": "铃声扰敌心神的刹那即是破绽：每10%闪避化为+5%暴击率",
			"apply": {},
			"crit_per_dodge": 0.05,
		},
		"shanyue_jia": {
			"name": "山岳战甲", "tier": 4, "price": 90,
			"icon": "res://assets/art/item_shanyue_jia.png",
			"desc": "甲越厚势越沉：每点护甲+1.5%全伤害",
			"apply": {},
			"dmg_per_armor": 0.015,
		},
		"xuepan_guyu": {
			"name": "血盘古玉", "tier": 4, "price": 88,
			"icon": "res://assets/art/item_xuepan_guyu.png",
			# 2026-10-22 系数 0.01→0.02：CultivatorSystem.damage_mult 里除数是写死的 /50.0，
			# 故等价于「每 25 点最大生命 +1% 全伤害」。原版基线 120 血只有 +2.4%、
			# 堆到 300 血才 +6%，同价位山岳战甲（每点护甲 +1.5%）远远更强。
			"desc": "生命如炉：每25点最大生命+1%全伤害",
			"apply": {},
			"dmg_per_max_hp": 0.02,
		},
		"jubao_pen": {
			"name": "聚宝盆", "tier": 3, "price": 48,
			"icon": "res://assets/art/item_jubao_pen.png",
			"desc": "财大气粗：每持100金币+3%全伤害（至多+30%）",
			"apply": {},
			"dmg_per_100_stones": 0.03, "stone_dmg_cap": 0.30,
		},
		"ranxue_fu": {
			"name": "燃血符", "tier": 3, "price": 44,
			"icon": "res://assets/art/item_ranxue_fu.png",
			"desc": "以血为引：每损失10%生命+2.5%全伤害",
			"apply": {},
			"dmg_per_missing_hp": 0.025,
		},
		"budong_yin": {
			"name": "不动明王印", "tier": 3, "price": 48,
			"icon": "res://assets/art/item_budong_yin.png",
			"desc": "站定1秒后全伤害+30%，脚底一动即失效",
			"apply": {},
			"still_damage": 0.30, "still_seconds": 1.0,
		},
		"liehun_ling": {
			"name": "裂魂铃", "tier": 4, "price": 92,
			"icon": "res://assets/art/item_liehun_ling.png",
			"desc": "击杀的敌人会爆炸，波及周围；爆炸伤害受元素伤害加成\n（限购一件）",
			"apply": {},
			"kill_explode": 40.0, "kill_explode_radius": 90.0,
			"unique": true,
		},

		# ---- 单元素史诗（tier 3）：专精流后期核心，幅度是稀有单元素石的近两倍 ----
		"taijin_jing": {
			"name": "太白金精", "tier": 3, "price": 46,
			"icon": "res://assets/art/item_taijin_jing.png",
			"desc": "",
			"apply": {"element_damage_metal": 0.15},
		},
		"yimu_sui": {
			"name": "乙木灵髓", "tier": 3, "price": 46,
			"icon": "res://assets/art/item_yimu_sui.png",
			"desc": "",
			"apply": {"element_damage_wood": 0.15},
		},
		"xuanshui_po": {
			"name": "玄水精魄", "tier": 3, "price": 46,
			"icon": "res://assets/art/item_xuanshui_po.png",
			"desc": "",
			"apply": {"element_damage_water": 0.15},
		},
		"lihuo_shenjing": {
			"name": "离火神晶", "tier": 3, "price": 46,
			"icon": "res://assets/art/item_lihuo_shenjing.png",
			"desc": "",
			"apply": {"element_damage_fire": 0.15},
		},
			"houtu_shenyuan": {
				"name": "后土神源", "tier": 3, "price": 46,
				"icon": "res://assets/art/item_houtu_shenyuan.png",
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
				"icon": "res://assets/art/item_ruding_xiang.png",
				"desc": "凝神入定：站定不动时闪避率+25%，护甲+3",
				"apply": {},
				"still_dodge": 0.25, "still_armor": 3.0,
			},
				"xuanwu_fashan": {
					"name": "玄武法坛", "tier": 3, "price": 46,
					"icon": "res://assets/art/item_xuanwu_fashan.png",
					"desc": "阵起玄武：站定不动时受击反伤+60%，护甲+3",
					"apply": {"attack_range_mult": -0.10},
					"still_armor": 3.0, "still_thorns": 0.6,
				},
				"jingang_shenxiang": {
					"name": "金刚神像", "tier": 3, "price": 46,
					"icon": "res://assets/art/item_jingang_shenxiang.png",
					"desc": "金刚怒目：站定不动时攻击间隔-30%；身法略受拘束",
					"apply": {"move_speed_mult": -0.08},
					"still_attack_speed": 0.30,
				},
				"panshi_yin": {
				"name": "磐石印", "tier": 4, "price": 92,
				"icon": "res://assets/art/item_panshi_yin.png",
				"desc": "气沉丹田：站定1秒后全伤害+45%",
				"apply": {},
				"still_damage": 0.45, "still_seconds": 1.0,
			},

			# ---- 2. 角色机制与核心痛点联动 ----
			"sanmei_guizhen": {
				"name": "三昧归真", "tier": 4, "price": 88,
				"icon": "res://assets/art/item_sanmei_guizhen.png",
				"desc": "上阵武器少于 4 把时，每少 1 把全伤害 +15%",
				"apply": {},
				"dmg_per_empty_slot": 0.15,
			},
			"lingsui_danqi": {
				"name": "灵髓丹气", "tier": 2, "price": 26,
				"icon": "res://assets/art/item_lingsui_danqi.png",
					"desc": "拾取回复珠或药爆后 3 秒内：全伤害 +25%、移速 +15%",
				"apply": {"hp_regen": -0.2},
				"heal_buff_damage": 0.25, "heal_buff_speed": 0.15, "heal_buff_dur": 3.0,
			},
			"liuyun_qianyin": {
				"name": "流云潜影玉", "tier": 3, "price": 46,
				"icon": "res://assets/art/item_liuyun_qianyin.png",
				"desc": "虚实莫测：成功闪避攻击时，50%概率回复3点生命",
				"apply": {"armor": -1.0},
				"dodge_heal_chance": 0.5, "dodge_heal_hp": 3.0,
			},
			"jinmang_souhun": {
				"name": "金芒搜魂令", "tier": 3, "price": 45,
				"icon": "res://assets/art/item_jinmang_souhun.png",
				# 2026-10-22 30% 概率掉 1 枚 → 100% 概率掉 2 枚（GameManager.register_kill 读 crit_kill_stone_bonus）。
				# 原版代价是永久 −6% 武器伤害，回报却是「每 3 次暴击击杀才 1 金币」，完全不值。
				"desc": "剑芒截气：暴击击杀敌人时，额外吸收2枚金币",
				"apply": {"weapon_damage_mult": -0.06},
				"crit_kill_stone_chance": 1.0, "crit_kill_stone_bonus": 2.0,
			},

			# ---- 3. 武器器类与行为质变 ----
			"tiangong_fatiao": {
				"name": "天工发条", "tier": 2, "price": 28,
				"icon": "res://assets/art/item_tiangong_fatiao.png",
				"desc": "机关炮台攻速 +20%，环绕武器转速 +30%",
				"apply": {"luck": -2.0},
				"turret_haste": 0.20, "drone_spin_speed": 0.30,
			},
			"qianfu_lianhuan": {
				"name": "千符连环印", "tier": 3, "price": 50,
				"icon": "res://assets/art/item_qianfu_lianhuan.png",
				"desc": "弹射与远程武器多 1 发弹丸，散布略增",
				"apply": {"attack_range_mult": -0.10},
				"projectile_count_bonus": 1,
			},
			"kaishan_jianyi": {
				"name": "开山重刃谱", "tier": 2, "price": 26,
				"icon": "res://assets/art/item_kaishan_jianyi.png",
				"desc": "横扫范围 +25%；近战命中吸血 1 点（每秒至多 2 次）",
				"apply": {"move_speed_mult": -0.05},
				"wide_range_mult": 0.25, "melee_lifesteal_flat": 1.0,
			},

			# ---- 4. 随行技能与长线成长 ----
			"ningshen_fu": {
				"name": "凝神符", "tier": 2, "price": 28,
				"icon": "res://assets/art/item_ningshen_fu.png",
				# 2026-10-22 技能冷却 −10%→−12%：原版与更便宜的静心符（−8%/幸运−1）相比
				# 只多 2% 冷却却多扣 1 点幸运，且同为稀有档 ⇒ 被全面支配。现拉开成 8/12/25 三档阶梯。
				"desc": "心若冰清：随行技能冷却时间缩短12%；福缘 -2",
				"apply": {"luck": -2.0},
				"skill_cooldown_mult": 0.12,
			},
			"tupo_guyu": {
				"name": "突破古玉", "tier": 4, "price": 95,
				"icon": "res://assets/art/item_tupo_guyu.png",
				"desc": "每回合结束永久 +3 生命、+0.5 回复、+1% 吸血\n（限购一件；上限 +30 生命 / +5 回复 / +10% 吸血）",
				"apply": {},
				"unique": true,
				"wave_end_max_hp": 3.0, "wave_end_regen": 0.5, "wave_end_lifesteal": 0.01,
			},
			# ==================== 2026-10-20 新增：通用强力选项（补删件空位 + 直给输出/生存） ====================
			# 用户口径「值得选的东西太少」：这三件不挑流派，任何构筑都能吃到，专治「没东西可挑」。
			"xuantie_ling": {
				"name": "玄铁令", "tier": 3, "price": 46,
				"icon": "res://assets/art/item_xuantie_ling.png",
				"desc": "武器伤害大幅提升，攻速略降",
				"apply": {"weapon_damage_mult": 0.20, "attack_speed_mult_mul": 1.03},
			},
			"bumie_jinshen": {
				"name": "不灭金身", "tier": 4, "price": 90,
				"icon": "res://assets/art/item_bumie_jinshen.png",
				"desc": "生命与护甲大幅提升，移速略降",
				"apply": {"max_hp": 50.0, "hp_heal": 50.0, "armor": 4.0, "hp_regen": 1.0, "move_speed_mult": -0.04},
			},
			"tiangang_zhanyi": {
				"name": "天罡战意", "tier": 4, "price": 88,
				"icon": "res://assets/art/item_tiangang_zhanyi.png",
				"desc": "暴击与暴伤大幅提升，护甲略降",
				"apply": {"crit_rate": 0.10, "crit_mult": 0.30, "armor": -1.0},
			},
			# ==================== 2026-10-21 流派补齐（1 主属性 + 1 跨流派负面） ====================
			# 补近战/远程/元素/召唤/机关/技能/闪避的物品入口，以及收藏家/蛮兵/嗜血魔修/灵植夫
			# 四个角色专属玩法的转化件。图标先借同系贴图占位，media-gen 出专属图后替换并补 manifest。
			"tieshou": {
				"name": "铁手套", "tier": 1, "price": 14,
				"icon": "res://assets/art/item_tieshou.png",
				"desc": "近战伤害提升，远程伤害降低",
				# 2026-10-22 近战 2→3 / 远程 −1→−2：原版主属性与无代价的砺剑石同为 +2，
			# 同价却白背一条远程惩罚 ⇒ 被砺剑石严格支配。有代价就该换到更高主属性。
			"apply": {"melee_damage": 3.0, "ranged_damage": -2.0},
			},
			"lingyan_fu": {
				"name": "灵焰符", "tier": 1, "price": 14,
				"icon": "res://assets/art/item_lingyan_fu.png",
				"desc": "元素伤害提升，攻速略降",
				# 2026-10-22 元素 2→3：原版与无代价的聚灵符同为 +2 却多背一条攻速惩罚，被严格支配。
			"apply": {"elemental_damage": 3.0, "attack_speed_mult_mul": 1.03},
			},
			"tongling": {
				"name": "铜铃", "tier": 1, "price": 14,
				"icon": "res://assets/art/item_tongling.png",
				"desc": "召唤伤害提升，移速略降",
				# 2026-10-22 召唤 2→3：原版与无代价的召唤牌同为 +2 却多背一条移速惩罚，被严格支配。
			"apply": {"engineering_damage": 3.0, "move_speed_mult": -0.03},
			},
			"pojun_fu": {
				"name": "破军符", "tier": 2, "price": 26,
				"icon": "res://assets/art/item_pojun_fu.png",
				"desc": "近战伤害提升，攻击范围略降",
				"apply": {"melee_damage": 4.0, "attack_range_mult": -0.05},
			},
			"liannu_shi": {
				"name": "连弩石", "tier": 2, "price": 26,
				"icon": "res://assets/art/item_liannu_shi.png",
				"desc": "远程伤害提升，攻击范围略降",
				"apply": {"ranged_damage": 4.0, "attack_range_mult": -0.05},
			},
			"wuxing_sha": {
				"name": "五行砂", "tier": 2, "price": 26,
				"icon": "res://assets/art/item_wuxing_sha.png",
				"desc": "元素伤害提升，生命回复略降",
				"apply": {"elemental_damage": 4.0, "hp_regen": -0.3},
			},
			"tongji_chi": {
				"name": "铜机齿", "tier": 2, "price": 28,
				"icon": "res://assets/art/item_tongji_chi.png",
				"desc": "机关伤害提升，移速略降",
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
				"desc": "闪避与移速提升，护甲略降",
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
				"name": "天机锁", "tier": 3, "price": 48,
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
				"desc": "随行技能冷却大幅缩短；攻击间隔略增\n（限购一件）",
				"apply": {"skill_cooldown_mult": 0.25, "attack_speed_mult_mul": 0.92},
				"unique": true,
			},
			"wanshi_jian": {
				"name": "万矢箭", "tier": 4, "price": 88,
				"icon": "res://assets/art/item_wanshi_jian.png",
				"desc": "远程武器多 1 发弹丸；攻击范围略降\n（限购一件）",
				"apply": {"ranged_damage": 6.0, "attack_range_mult": -0.10},
				"projectile_count_bonus": 1,
				"unique": true,
			},
			# ==================== 噩梦专属 · 视野件（2026-10-30） ====================
			# 只放大噩梦迷雾的清晰圈（apply 的 fog_vision_bonus 加算，渲染侧封顶 +80%）：
			# nightmare_only 硬闸让它们只在噩梦出现，unique 保证每件每局最多一件 ——
			# 三件买满正好到顶（15+25+40），两侧仍留浓雾，迷雾机制不会被买没。
			"yinlu_deng": {
				"name": "引路灯", "tier": 1, "price": 20,
				"icon": "res://assets/art/item_yinlu_deng.png",
				"desc": "噩梦迷雾视野变宽\n（每局限购一件）",
				"apply": {"fog_vision_bonus": 0.15},
				"nightmare_only": true,
				"unique": true,
			},
			"powu_deng": {
				"name": "破雾灯", "tier": 2, "price": 42,
				"icon": "res://assets/art/item_powu_deng.png",
				"desc": "噩梦迷雾视野进一步变宽\n（每局限购一件）",
				"apply": {"fog_vision_bonus": 0.25},
				"nightmare_only": true,
				"unique": true,
			},
			"qianli_yan": {
				"name": "千里眼", "tier": 3, "price": 68,
				"icon": "res://assets/art/item_qianli_yan.png",
				"desc": "噩梦迷雾视野大幅变宽\n（每局限购一件）",
				"apply": {"fog_vision_bonus": 0.40},
				"nightmare_only": true,
				"unique": true,
			},
		# ==================== 神通（tier 5 · 逆天 · 超级悟道专属） ====================
		# 只由 SuperUpgradeData 赠送，绝不进商店货架池（granted_only）、不可出售（no_sell）。
		# 道途/阶段元数据在 scripts/data/SuperUpgradeData.gd；此处只管「这件神通干什么」。
		# 2026-10-25 重构：删掉全部纯数值放大卡（与普通悟道无区别），只留机制卡与真代价卡。
		# 机制卡一律 apply 留空、机制数字写进顶层字段（一致性测试会把顶层数值当「已解释」），
		# desc 只写一句人话，不重复 apply 里的数字。

		# ---- 剑道 ----
		"shen_jianqi": {
			"name": "剑气凌霄", "tier": 5, "price": 0, "granted_only": true, "no_sell": true,
			"icon": "res://assets/art/item_kaishan_jianyi.png",
			"desc": "近战与横扫改为挥出远距离剑气，攻击距离翻倍",
			"apply": {},
			"melee_range_mult": 1.0,
		},
		"shen_wanjian_guizong": {
			"name": "万剑归宗", "tier": 5, "price": 0, "granted_only": true, "no_sell": true,
			"icon": "res://assets/art/item_lijian_shi.png",
			"desc": "剑系武器出手攒剑意（头顶计数），攒满幻化剑阵并驻场数秒",
			"apply": {},
			"sword_qi": 1.0,
		},

		# ---- 箭道 ----
		"shen_wanjian_qifa": {
			"name": "万箭齐发", "tier": 5, "price": 0, "granted_only": true, "no_sell": true,
			"icon": "res://assets/art/item_wanshi_jian.png",
			"desc": "远程多 2 发弹丸，单发伤害略降",
			"apply": {},
			"projectile_count_bonus": 2.0,
			"projectile_damage_mult": 0.85,
		},
		"shen_tanmu": {
			"name": "弹幕回响", "tier": 5, "price": 0, "granted_only": true, "no_sell": true,
			"icon": "res://assets/art/item_qianfu_lianhuan.png",
			"desc": "弹丸命中后额外弹射",
			"apply": {},
			"projectile_bounce_bonus": 2.0,
		},
		"shen_jianyu": {
			"name": "箭雨倾盆", "tier": 5, "price": 0, "granted_only": true, "no_sell": true,
			"icon": "res://assets/art/item_liannu_shi.png",
			"desc": "远程武器每隔数次出手，朝敌群落下一轮箭雨",
			"apply": {},
			"arrow_rain_every": 6.0,
		},

		# ---- 雷法 ----
		"shen_zidian": {
			"name": "紫电", "tier": 5, "price": 0, "granted_only": true, "no_sell": true,
			"icon": "res://assets/art/item_leiling_zhu.png",
			"desc": "攻击间隔积累到一定程度放出连锁闪电",
			"apply": {},
			"attack_chain_lightning": 1.0,
		},
		"shen_leijie": {
			"name": "雷劫", "tier": 5, "price": 0, "granted_only": true, "no_sell": true,
			"icon": "res://assets/art/item_liehun_ling.png",
			"desc": "击杀时向附近敌人放出闪电",
			"apply": {},
			"kill_chain_lightning": 1.0,
		},
		"shen_tianfa": {
			"name": "天罚", "tier": 5, "price": 0, "granted_only": true, "no_sell": true,
			"icon": "res://assets/art/item_jinmang_souhun.png",
			"desc": "暴击时额外落下一道天雷",
			"apply": {},
			"crit_sky_bolt": 1.0,
			"chain_hop_bonus": 1.0,
		},

		# ---- 体修 ----
		"shen_fanzhen_dianchang": {
			"name": "反震电场", "tier": 5, "price": 0, "granted_only": true, "no_sell": true,
			"icon": "res://assets/art/item_fanzhen_tongjia.png",
			"desc": "受到伤害时向周围敌人放电",
			"apply": {},
			"thorns_electric": 1.0,
		},
		"shen_xuehai": {
			"name": "血海护盾", "tier": 5, "price": 0, "granted_only": true, "no_sell": true,
			"icon": "res://assets/art/item_xuehai_fu.png",
			"desc": "满血时吸血的溢出结成血盾，盾碎时向周身放电",
			"apply": {},
			"lifesteal_overflow_shield": 1.0,
		},

		# ---- 五行 ----
		"shen_wuxing_lunzhuan": {
			"name": "五行轮转", "tier": 5, "price": 0, "granted_only": true, "no_sell": true,
			"icon": "res://assets/art/item_wuxing_pei.png",
			"desc": "命中时可能附加随机五行异常",
			"apply": {},
			"wuxing_rotation_chance": 0.35,
		},
		"shen_wuxing_guiyi": {
			"name": "五行归一", "tier": 5, "price": 0, "granted_only": true, "no_sell": true,
			"icon": "res://assets/art/item_hunyuan_zhu.png",
			"desc": "每次命中同时附加灼烧、冰缓与剧毒",
			"apply": {},
			"wuxing_all": 1.0,
		},

		# ---- 灵兽 ----
		"shen_shouxue": {
			"name": "兽血沸腾", "tier": 5, "price": 0, "granted_only": true, "no_sell": true,
			"icon": "res://assets/art/item_yushou_ling.png",
			"desc": "灵兽栏 +1，灵兽出手更快",
			"apply": {"pet_cooldown_mult_mul": 0.75, "pet_slots": 1.0},
		},
		"shen_shouqun": {
			"name": "兽群", "tier": 5, "price": 0, "granted_only": true, "no_sell": true,
			"icon": "res://assets/art/item_wanshou_long.png",
			"desc": "灵兽栏 +2，灵兽的直击附带闪电",
			"apply": {"pet_slots": 2.0},
			"pet_chain_lightning": 1.0,
		},

		# ---- 跨道共鸣 ----
		"shen_leiting_danmu": {
			"name": "雷霆弹幕", "tier": 5, "price": 0, "granted_only": true, "no_sell": true,
			"icon": "res://assets/art/item_qianfu_lianhuan.png",
			"desc": "弹丸命中时也放出连锁闪电",
			"apply": {},
			"projectile_chain_lightning": 1.0,
		},
		"shen_lingyun_wuxing": {
			"name": "灵蕴五行", "tier": 5, "price": 0, "granted_only": true, "no_sell": true,
			"icon": "res://assets/art/item_tongling.png",
			"desc": "灵兽直击时大概率附加随机五行异常",
			"apply": {},
			"pet_wuxing_chance": 0.6,
		},

		# ---- 仪式（无道途，随时可出） ----
		"shen_kaitian": {
			"name": "开天辟地", "tier": 5, "price": 0, "granted_only": true, "no_sell": true,
			"icon": "res://assets/art/item_luban_suo.png",
			"desc": "上阵武器槽位 +1",
			"apply": {},
			"weapon_slot_bonus": 1,
		},
		"shen_shalu": {
			"name": "杀戮节奏", "tier": 5, "price": 0, "granted_only": true, "no_sell": true,
			"icon": "res://assets/art/item_tongji_chi.png",
			"desc": "每次击杀使所有武器当前冷却缩短",
			"apply": {},
			"kill_cd_refund": 0.08,
		},
		"shen_xueji": {
			"name": "血祭盛宴", "tier": 5, "price": 0, "granted_only": true, "no_sell": true,
			"icon": "res://assets/art/item_liehun_ling.png",
			"desc": "击杀引发尸爆，死者越壮爆炸越狠",
			"apply": {},
			"kill_explode": 120.0, "kill_explode_radius": 170.0, "kill_explode_hp_ratio": 0.25,
		},
		"shen_moyan": {
			"name": "魔焰锻体", "tier": 5, "price": 0, "granted_only": true, "no_sell": true,
			"icon": "res://assets/art/item_xuepan_guyu.png",
			"desc": "武器伤害暴涨，代价是生命上限下降",
			"apply": {"weapon_damage_mult": 0.60, "max_hp": -30.0, "hp_heal": -30.0},
		},
		"shen_dixue": {
			"name": "滴血重生", "tier": 5, "price": 0, "granted_only": true, "no_sell": true,
			"icon": "res://assets/art/item_naling_zhuo.png",
			"desc": "获得 1 次复活机会",
			"apply": {"revive_charges": 1.0, "max_hp": 50.0, "hp_heal": 50.0},
		},
		"shen_yixing": {
			"name": "移形换影", "tier": 5, "price": 0, "granted_only": true, "no_sell": true,
			"icon": "res://assets/art/item_liuyun_qianyin.png",
			"desc": "闪避提升；闪避成功时回复生命",
			"apply": {"dodge": 0.12},
			"dodge_heal_chance": 0.5, "dodge_heal_hp": 5.0,
		},
		"shen_xianji": {
			"name": "献祭", "tier": 5, "price": 0, "granted_only": true, "no_sell": true,
			"icon": "res://assets/art/item_xuepan_guyu.png",
			"desc": "武器槽 -1，其余武器伤害大涨",
			"apply": {"weapon_damage_mult": 0.60},
			"weapon_slot_bonus": -1,
		},
		# 2026-10-27 飞升悟道补「技能冷却」入口：此前飞升屏（5/10/15 回合）抽不到任何
		# 减随行技能冷却的卡，只有普通悟道的凝神/坐忘与道具三档。取 40% 是对齐
		# SKILL_CD_CAP(0.7) 的「一张卡走完大半程」：单独拿一次闪避 3→1.8s、治疗 15→9s；
		# 再叠两张坐忘即到顶，不与上限空转。按飞升卡「要有真代价」的规矩配 -20 生命上限。
		"shen_cuijue": {
			"name": "燃血催诀", "tier": 5, "price": 0, "granted_only": true, "no_sell": true,
			"icon": "res://assets/art/item_ningshen_fu.png",
			"desc": "燃血催动口诀：随行技能冷却大幅缩短，代价是生命上限下降",
			"apply": {"skill_cooldown_mult": 0.40, "max_hp": -20.0, "hp_heal": -20.0},
		},
	}

static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, {})

static func all_ids() -> Array:
	return DEFS.keys()

static func tier_label(tier: int) -> String:
	return TIER_LABELS.get(clampi(tier, 1, 5), "普通")

static func tier_color(tier: int) -> Color:
	return TIER_COLORS.get(clampi(tier, 1, 5), TIER_COLORS[1])

## 神通：只由超级悟道赠送，不进商店货架池、不进图鉴（tier 5 不在图鉴档位页内）
static func is_granted_only(id: String) -> bool:
	return bool(get_def(id).get("granted_only", false))

## 神通不可出售（哈迪斯式祝福：拿了就是本局的一部分，不退货）
static func is_no_sell(id: String) -> bool:
	return bool(get_def(id).get("no_sell", false))

## 噩梦专属件：只有 danger_level >= 1 的局才进抽池（视野件用，普通难度抽到等于废件）。
## 抽池里的位置必须与 granted_only 同层（_pick_id_filtered 的硬闸），
## 不能只靠 BalanceBuildFilter —— 池被过滤空时兜底那一轮会跳过构筑过滤。
static func is_nightmare_only(id: String) -> bool:
	return bool(get_def(id).get("nightmare_only", false))

## 可上货架的道具 id（排除神通）：图鉴计数与任何全表遍历用它，别用 all_ids()
static func shop_ids() -> Array:
	var out: Array = []
	for id in DEFS.keys():
		if not is_granted_only(String(id)):
			out.append(id)
	return out

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
	"weapon_slot_bonus": "generic", "kill_cd_refund": "haste",
		# 2026-10-25 超级悟道机制卡（链电 / 剑气 / 五行轮转 / 范围与弹丸变异）
		"melee_range_mult": "melee", "sword_qi": "melee",
		"projectile_damage_mult": "projectile", "projectile_bounce_bonus": "projectile",
		"attack_chain_lightning": "thunder", "kill_chain_lightning": "thunder",
		"crit_sky_bolt": "thunder", "chain_hop_bonus": "thunder",
		"projectile_chain_lightning": "thunder",
		"thorns_electric": "tank", "wuxing_rotation_chance": "elemental",
		# 二阶段（箭雨 / 血盾 / 归一 / 兽群 / 灵蕴 / 尸爆口径）
		"arrow_rain_every": "ranged", "lifesteal_overflow_shield": "lifesteal",
		"wuxing_all": "elemental", "pet_chain_lightning": "pet",
		"pet_wuxing_chance": "pet", "kill_explode_hp_ratio": "elemental",
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
	# 先按构筑感知过滤收一版池（玩剑系就不刷纯召唤/机关/单元素/灵兽件；宝箱件是经济件不过闸）；
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
		if is_granted_only(String(id)):
			continue
		# 噩梦专属件（视野件）：普通难度不进池。硬闸 —— 兜底那轮不过构筑过滤，这里必须自己拦
		if is_nightmare_only(String(id)) and (gm == null or int(gm.danger_level) < 1):
			continue
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
		# 噩梦专属件在噩梦内加权：不受构筑亲和影响（它们没有构筑标签），纯随机池下否则几乎刷不到
		if is_nightmare_only(String(id)):
			w *= GameBalance.ITEM_NIGHTMARE_ONLY_WEIGHT
		pool.append(id)
		weights.append(w)
	if pool.is_empty():
		return ""
	var active_rng: RandomNumberGenerator = rng if rng != null else GameManager.rng
	var roll: float = active_rng.randf()
	return String(pool[GameBalance.weighted_pick_index(weights, roll)])
