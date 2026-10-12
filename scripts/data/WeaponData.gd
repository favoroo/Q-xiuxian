class_name WeaponData
extends RefCounted

## 武器静态数据库：所有法器的数值/行为/价格/五行/属性受益唯一定义处
## 星级：集齐 3 把同名同星，在波间商店手动合成 +1 星，伤害 ×2.0/星，冷却 ×0.92/星，最高 ★3
## 双标签系统：器类（剑系/符箓/雷法/御灵/广域）+ 五行（锐金/青木/玄水/离火/厚土）
## 器类归属口径（2026-10-10 定，用户：「柳叶飞刀怎么是符箓啊？不应该是剑系吗」）：
##   剑系 = 金属锋刃器，近战白刃与远程飞射都算（剑/刀/针 ⇒ 庚金飞剑、柳叶飞刀、暴雨梨花针、玄冰飞针都在内）；
##   符箓 = 符纸（万木灵符、火焰符），该羁绊给弹丸穿透。
## 归属唯一真话是各法器的 "tags"（"tag" 只是展示文案），器类签/图鉴/商店/羁绊结算全从 tags 取，改归属两处一起改。
## 弹丸类（PROJECTILE）另带 bullet / bullet_scale / bullet_spin 三个外观字段：打出去的东西按法器各自不同
## （火符掷火符、飞剑出飞剑、冰针出针），画布尺寸 × bullet_scale == 屏上像素；缺 bullet 时回退 blade.png。
## bullet_scale 那把尺子（2026-10-09，用户口径：「飞行物太大了，其他几个也挺大」）：
## 弹丸屏上长轴不许大过发射它的法器本体（本体 = 48×48 画布 × FloatingWeapon 的 0.55 ⇒ 26.4px）。
## 符箓是块面状贴图、细长兵器是 40px 长条，按 1.0 出图全都在本体的 1.5 倍 ⇒ 满屏飞招牌。
## bullet_spin 2026-10-09 起才真正生效：以前代码按穿透数反推朝向（pierce<=1 就转），
## 结果表里明明写了"不转"的玄冰飞针，打出去仍在原地打圈。
##
## 朝向与发射点（2026-10-09，用户口径：「飞剑发射时朝向不对，没朝敌人；不知道从哪里发射出来的」）：
## - "tip"：剑尖/器口在【贴图坐标系】里相对画布中心的位置，单位 = 画布像素（图标 48×48，
##   画布中心 (24,24) 即 Sprite2D 的轴心）。一个字段管两件事：
##   方向 = 这张图天生朝哪儿（代码按它补偿，贴图才真正指向目标）；长度 = 出膛点离本体的距离。
##   ⚠ 这个数只能【量】不能【猜】：标到柄那头时代码照样自洽（补偿角与出膛点都跟着它走），
##   于是画面上变成"剑尖背对敌人、弹丸从剑柄冒出来"，判据抓不到 —— 庚金飞剑就栽过一次。
##   换素材后跑 `python3 tools/fit_weapon_icon.py <原稿> <产物> 48 48 [--rotate 角度]`，
##   把它打印的 tip 原样抄进来；哪头是尖要靠 tests/WeaponAimPreview 出的图看。
## - "upright": true = 宝灯/法牌/大印/灵藤这类没有锋刃方向的重器，本体保持世界竖直，不许随瞄准
##   转圈（旧写法会把印玺横过来对着人）。此时 tip 只取长度，发射点落在"朝目标那一侧的器口"。
## - 环绕类（DRONE）走 SunOrb，本体不旋转，不需要这两个字段。

enum Behavior { MELEE, PROJECTILE, BURST, DRONE, TURRET }

const MAX_STAR: int = 3
const MAX_SLOTS: int = 6
const MAX_STASH_SLOTS: int = 9
const STAR_DAMAGE_MULT: float = 2.0
const STAR_COOLDOWN_MULT: float = 0.92
const SELL_RATIO: float = 0.5
const STAR_SELL_MULT: float = 1.6

const CLASSES: Array[String] = ["sword", "talisman", "wide", "thunder", "spirit", "contraption"]
const ELEMENTS: Array[String] = ["metal", "wood", "water", "fire", "earth"]

const DEFS: Dictionary = {
			# ==================== 金系 (Metal: 锋芒·暴击·破甲) ====================
			"qingyun_sword": {
				"name": "长剑", "behavior": Behavior.MELEE,
				"sfx": "whoosh_light", "sfx_impact": "impact_blade",
				"damage": 30.0, "cooldown": 1.05, "range": 150.0,
				"knockback": 240.0,
				"price": 25, "icon": "res://assets/art/weapon_sword.png",
				# 2026-10-10 素材返工（旧图为像素风白剑，与新画风脱节）：换空洞冷冽矢量风青云剑，
				# tip 由 tools/fit_weapon_icon.py 实测打印后原样抄入。
				"tip": Vector2(22, -20),
				"desc": "近身挥砍，受近战伤害与暴击率加成", "tag": "近战·剑系·金",
				"tags": ["sword", "metal"],
				"stat_scalings": {"melee_damage": 1.0, "crit_rate": 40.0},
			},
				"gengjin_feijian": {
					"name": "飞剑", "behavior": Behavior.PROJECTILE,
					"sfx": "blade_shoot",
					"damage": 26.0, "cooldown": 0.92, "range": 245.0,
					"knockback": 185.0,
					"price": 35, "icon": "res://assets/art/weapon_gold_sword.png",
					# 2026-10-09 素材返工（旧图是弯的、且旧标定 (20,-14) 落在剑首那头上）：
					# 新图为笔直双刃剑斜铺，tip 由 tools/fit_weapon_icon.py 实测打印后原样抄入。
					"tip": Vector2(22, -16),
					"desc": "自动追击并穿透2名敌人，受远程伤害与暴击伤害加成", "tag": "远程·剑系·金",
					"bullet": "res://assets/art/bullet_gold_sword.png", "bullet_scale": 0.6, "bullet_spin": false,
					"pierce": 2,
					"tags": ["sword", "metal"],
					"stat_scalings": {"ranged_damage": 1.0, "crit_mult_bonus": 30.0},
				},
				"liuye_feidao": {
					"name": "飞刀", "behavior": Behavior.PROJECTILE,
					"sfx": "metal_dart",
					"damage": 12.0, "cooldown": 1.15, "range": 235.0,
					"knockback": 110.0,
					"price": 35, "icon": "res://assets/art/weapon_dagger.png",
					"tip": Vector2(21, -24),
					"desc": "扇形射出3把飞刀各锁1敌，受远程伤害与暴击率加成", "tag": "远程·剑系·金",
					"bullet": "res://assets/art/bullet_leaf_dagger.png", "bullet_scale": 0.6, "bullet_spin": false,
					"pierce": 3, "projectile_count": 3, "spread_angle": 0.20,
					"tags": ["sword", "metal"],
					"stat_scalings": {"ranged_damage": 0.8, "crit_rate": 30.0},
				},
					"baoyu_liuhuazhen": {
						"name": "暴雨针", "behavior": Behavior.PROJECTILE,
						"sfx": "metal_dart",
						# 2026-10-11 平衡校准：剑痴核心交叉件单体偏软，12→13 抬离群伤带下沿（★1 单体 20.8 仍带内）
						"damage": 13.0, "cooldown": 1.25, "range": 220.0,
						"knockback": 90.0,
						"price": 36, "icon": "res://assets/art/weapon_needle_pouch.png",
						"tip": Vector2(22, -6),
						"desc": "连射5发追踪细针，受远程伤害与暴击率加成", "tag": "远程·剑系·金",
					"bullet": "res://assets/art/bullet_silver_needle.png", "bullet_scale": 0.55, "bullet_spin": false,
					"pierce": 1, "projectile_count": 5, "spread_angle": 0.32,
					"tags": ["sword", "metal"],
					"stat_scalings": {"ranged_damage": 0.8, "crit_rate": 30.0},
				},

				# ==================== 木系 (Wood: 生机·回复·剧毒) ====================
				"qingmu_tengbian": {
					"name": "藤鞭", "behavior": Behavior.MELEE,
					"sfx": "whoosh_light", "sfx_impact": "impact_crack",
					"damage": 18.0, "cooldown": 1.20, "range": 175.0,
					"knockback": 260.0,
					"price": 28, "icon": "res://assets/art/weapon_vine_whip.png",
					"tip": Vector2(22, 0), "upright": true,
					"desc": "大范围横扫并附带中毒，受近战与元素伤害加成", "tag": "近战·横扫·木",
					"arc_scale": 1.35, "proc_poison": true, "poison_ratio": 0.35, "poison_dur": 3.0,
					"tags": ["wide", "wood"],
					"stat_scalings": {"melee_damage": 1.0, "elemental_damage": 0.6, "hp_regen": 4.5},
				},
				"wanmu_lingfu": {
					"name": "毒符", "behavior": Behavior.PROJECTILE,
					"sfx": "talisman_throw",
					"damage": 18.0, "cooldown": 1.05, "range": 230.0,
					"knockback": 140.0,
					"price": 32, "icon": "res://assets/art/weapon_wood_talisman.png",
					"tip": Vector2(20, -18),
					"desc": "追踪弹射并叠毒，受远程与元素伤害加成", "tag": "远程·弹射·木",
					"bullet": "res://assets/art/bullet_wood_talisman.png", "bullet_scale": 0.6, "bullet_spin": true,
					"pierce": 1, "bounce_count": 2, "proc_poison": true, "poison_ratio": 0.30, "poison_dur": 2.5,
					"tags": ["talisman", "wood"],
					"stat_scalings": {"ranged_damage": 0.8, "elemental_damage": 0.8, "hp_regen": 3.5},
				},
					"lingdie": {
						"name": "护蝶", "behavior": Behavior.DRONE,
						"sfx": "drone_flutter",
						"damage": 23.0, "cooldown": 0.48, "range": 205.0,
						"knockback": 160.0,
						"price": 40, "icon": "res://assets/art/sun_orb.png",
						"desc": "环绕周身触碰即伤，受召唤伤害与吸血加成", "tag": "环绕·召唤·木",
						"tags": ["spirit", "wood"],
						"stat_scalings": {"engineering_damage": 1.0, "lifesteal": 100.0},
					},
				"lianhuan_lingdan": {
					"name": "弹弓", "behavior": Behavior.PROJECTILE,
					"sfx": "impact_crack",
					"damage": 19.0, "cooldown": 0.95, "range": 230.0,
					"knockback": 120.0,
					"price": 34, "icon": "res://assets/art/weapon_sling.png",
					"tip": Vector2(20, -18),
					"desc": "弹丸连锁弹射并附带中毒，受远程与元素伤害加成", "tag": "远程·横扫·木",
					"bullet": "res://assets/art/bullet_spirit_pellet.png", "bullet_scale": 0.55, "bullet_spin": true,
					"pierce": 1, "bounce_count": 4,
					"proc_poison": true, "poison_ratio": 0.25, "poison_dur": 2.5,
					"tags": ["wide", "wood"],
					"stat_scalings": {"ranged_damage": 0.8, "elemental_damage": 0.6, "hp_regen": 3.0},
				},

				# ==================== 水系 (Water: 极寒·缓速·迅捷) ====================
					"bajiao_fan": {
						"name": "风扇", "behavior": Behavior.MELEE,
						"sfx": "fan_gust", "sfx_impact": "impact_crack",
						"damage": 25.0, "cooldown": 1.25, "range": 185.0,
						"knockback": 400.0,
						"price": 20, "icon": "res://assets/art/weapon_fan.png",
						"tip": Vector2(0, -15),
						"desc": "扇出宽大风刃减速敌人，受近战伤害与移速加成", "tag": "近战·横扫·水",
					"arc_scale": 1.35, "proc_chill": 0.35, "chill_dur": 2.5,
					"tags": ["wide", "water"],
					"stat_scalings": {"melee_damage": 1.0, "move_speed_bonus": 25.0},
				},
				"xuanbing_feizhen": {
					"name": "冰针", "behavior": Behavior.PROJECTILE,
					"sfx": "metal_dart",
					"damage": 14.0, "cooldown": 1.0, "range": 235.0,
				"knockback": 95.0,
				"price": 30, "icon": "res://assets/art/weapon_ice_needle.png",
				"tip": Vector2(-18, 12),
				"desc": "射出3枚冰针追踪并减速，受远程伤害与移速加成", "tag": "远程·剑系·水",
				"bullet": "res://assets/art/bullet_ice_needle.png", "bullet_scale": 0.6, "bullet_spin": false,
				"pierce": 1, "projectile_count": 3, "spread_angle": 0.18, "proc_chill": 0.35, "chill_dur": 2.0,
				"tags": ["sword", "water"],
				"stat_scalings": {"ranged_damage": 0.8, "move_speed_bonus": 28.0},
			},
				"hanquan_yulian": {
					"name": "冰莲", "behavior": Behavior.DRONE,
					"sfx": "drone_chime",
					"damage": 24.0, "cooldown": 0.50, "range": 205.0,
					"knockback": 190.0,
					"price": 42, "icon": "res://assets/art/weapon_ice_lotus.png",
					"desc": "环绕护体触碰即减速，受召唤伤害与攻击间隔加成", "tag": "环绕·召唤·水",
					"proc_chill": 0.40, "chill_dur": 2.5,
					"tags": ["spirit", "water"],
					"stat_scalings": {"engineering_damage": 1.0, "cdr_bonus": 30.0},
				},
				"bihai_chaoyindi": {
					"name": "音笛", "behavior": Behavior.BURST,
					"sfx": "flute_wave", "sfx_impact": "flute_wave",
					"damage": 31.0, "cooldown": 1.40, "range": 225.0,
					"knockback": 320.0,
					"price": 44, "icon": "res://assets/art/weapon_flute.png",
					"tip": Vector2(20, 0), "upright": true,
					"desc": "音波震荡大范围强减速，受元素伤害与移速加成", "tag": "区域·范围·水",
					"burst_radius": 88.0, "burst_tint": Color(0.35, 0.75, 1.0),
					"proc_chill": 0.50, "chill_dur": 2.8,
					"tags": ["thunder", "water"],
					"stat_scalings": {"elemental_damage": 1.0, "move_speed_bonus": 30.0, "cdr_bonus": 25.0},
				},

				# ==================== 火系 (Fire: 烈焰·灼烧·爆裂) ====================
				"huoyan_fu": {
					"name": "火符", "behavior": Behavior.PROJECTILE,
					"sfx": "talisman_throw",
					"damage": 11.0, "cooldown": 0.88, "range": 230.0,
					"knockback": 155.0,
					"price": 30, "icon": "res://assets/art/weapon_staff.png",
					"tip": Vector2(6, -24),
					"desc": "掷出2张燃烧符追踪引燃，受元素与远程伤害加成", "tag": "远程·弹射·火",
					"bullet": "res://assets/art/bullet_fire_talisman.png", "bullet_scale": 0.5, "bullet_spin": true,
					"pierce": 1, "projectile_count": 2, "spread_angle": 0.14,
					"proc_burn": true, "burn_ratio": 0.40, "burn_dur": 3.0,
					"tags": ["talisman", "fire"],
					"stat_scalings": {"elemental_damage": 1.0, "ranged_damage": 0.6, "damage_bonus": 20.0},
				},
					"chiyan_dao": {
						"name": "烈焰刀", "behavior": Behavior.MELEE,
						"sfx": "whoosh_light", "sfx_impact": "impact_blade",
						"damage": 24.0, "cooldown": 1.15, "range": 165.0,
						"knockback": 320.0,
						"price": 36, "icon": "res://assets/art/weapon_fire_blade.png",
						"tip": Vector2(22, -14),
						"desc": "大范围火焰重刀引燃敌人，受近战与元素伤害加成", "tag": "近战·剑系·火",
					"arc_scale": 1.25, "proc_burn": true, "burn_ratio": 0.40, "burn_dur": 3.0,
					"tags": ["sword", "fire"],
					"stat_scalings": {"melee_damage": 1.0, "elemental_damage": 0.8, "range_bonus": 25.0},
				},
				"fentian_baodeng": {
					"name": "天灯", "behavior": Behavior.BURST,
					"sfx": "whoosh_heavy", "sfx_impact": "flame_jet",
					"damage": 20.0, "cooldown": 1.45, "range": 230.0,
					"knockback": 200.0,
					"price": 46, "icon": "res://assets/art/weapon_fire_lantern.png",
					"tip": Vector2(22, 0), "upright": true,
					"desc": "召唤火雨轰击区域并点燃火海，受元素伤害加成", "tag": "远程·范围·火",
					"burst_radius": 85.0, "burst_tint": Color(1.0, 0.52, 0.18),
					"proc_burn": true, "burn_ratio": 0.40, "burn_dur": 3.0,
					"tags": ["thunder", "fire"],
					"stat_scalings": {"elemental_damage": 1.5, "damage_bonus": 25.0},
				},
					"sanmei_huohu": {
						"name": "火葫芦", "behavior": Behavior.PROJECTILE,
						"sfx": "flame_jet",
						"damage": 8.0, "cooldown": 0.42, "range": 170.0,
						"knockback": 95.0,
						"price": 42, "icon": "res://assets/art/weapon_fire_calabash.png",
						"tip": Vector2(22, -18),
						"desc": "近距离喷射火焰持续灼烧，受元素与远程伤害加成", "tag": "近程·横扫·火",
					"bullet": "res://assets/art/bullet_fire_flame.png", "bullet_scale": 0.50, "bullet_spin": true,
					"pierce": 3, "projectile_count": 1,
					"proc_burn": true, "burn_ratio": 0.40, "burn_dur": 2.5,
					"tags": ["wide", "fire"],
					"stat_scalings": {"elemental_damage": 1.2, "ranged_damage": 0.6, "damage_bonus": 20.0},
				},

				# ==================== 土系 (Earth: 厚重·护甲·震退) ====================
				"wulei_paizi": {
					"name": "雷牌", "behavior": Behavior.BURST,
					"sfx": "whoosh_light", "sfx_impact": "thunder_strike",
					"damage": 35.0, "cooldown": 1.50, "range": 225.0,
					"knockback": 280.0,
					"price": 45, "icon": "res://assets/art/weapon_thunder.png",
					"tip": Vector2(22, 0), "upright": true,
					"desc": "落雷轰击区域大范围击退，受元素伤害与护甲加成", "tag": "远程·范围·土",
					"burst_radius": 80.0, "burst_tint": Color(0.62, 0.86, 1.0),
					"tags": ["thunder", "earth"],
					"stat_scalings": {"elemental_damage": 1.2, "armor": 2.0},
				},
				"fantian_yin": {
					"name": "巨印", "behavior": Behavior.BURST,
					"sfx": "whoosh_heavy", "sfx_impact": "impact_blunt",
					"damage": 38.0, "cooldown": 1.55, "range": 220.0,
					"knockback": 360.0,
					"price": 48, "icon": "res://assets/art/weapon_earth_seal.png",
					"tip": Vector2(20, 0), "upright": true,
					"desc": "巨印从天砸下，受元素伤害与护甲加成", "tag": "区域·横扫·土",
					"burst_radius": 95.0, "burst_tint": Color(0.88, 0.74, 0.46),
					"burst_icon": "res://assets/art/weapon_earth_seal.png",
					"tags": ["wide", "earth"],
					"stat_scalings": {"elemental_damage": 1.0, "armor": 3.5},
				},
					"hunyuan_zhong": {
						"name": "古钟", "behavior": Behavior.DRONE,
						"sfx": "orb_hit",
						"damage": 25.0, "cooldown": 0.52, "range": 210.0,
						"knockback": 340.0,
						"price": 44, "icon": "res://assets/art/weapon_earth_bell.png",
						"desc": "环绕周身撞击击退敌群，受召唤伤害与最大生命加成", "tag": "环绕·召唤·土",
						"tags": ["spirit", "earth"],
						"stat_scalings": {"engineering_damage": 1.0, "max_hp_bonus": 0.12},
					},
					"xuanwu_lingdun": {
						"name": "重盾", "behavior": Behavior.MELEE,
						"sfx": "whoosh_heavy", "sfx_impact": "impact_blunt",
						"damage": 24.0, "cooldown": 1.20, "range": 170.0,
						"knockback": 350.0,
						"price": 38, "icon": "res://assets/art/weapon_earth_shield.png",
						"tip": Vector2(22, -12),
						"desc": "厚盾横推大力击退，受近战伤害与护甲加成", "tag": "近战·剑系·土",
					"arc_scale": 1.35,
					"tags": ["sword", "earth"],
					"stat_scalings": {"melee_damage": 0.8, "armor": 3.0, "max_hp_bonus": 0.10},
				},

				# ==================== 2026-10-10 新增 15 把 ====================
				# 目的有二：
				#  1) 补齐 器类×五行 5×5 格子的 9 个空格——符箓(原仅2把)/雷法(3)/御灵(3)凑不齐羁绊 4/6 档；
				#  2) 按土豆兄弟属性加成模式补流派专武（吸血/收益/护甲加成），配合新法宝撑起各流派。
				# tip 由 tools/fit_weapon_icon.py 实测回填。

				# ---- 补格子 9 把 ----
				"jinzhen_fu": {
					"name": "金针符", "behavior": Behavior.PROJECTILE,
					"sfx": "metal_dart",
					"damage": 9.0, "cooldown": 0.58, "range": 230.0,
					"knockback": 80.0,
					"price": 34, "icon": "res://assets/art/weapon_jinzhen_fu.png",
					"tip": Vector2(22, -6),
					"desc": "连射2枚金针高速追击，受远程伤害与暴击率加成", "tag": "远程·弹射·金",
					"bullet": "res://assets/art/bullet_gold_needle.png", "bullet_scale": 0.55, "bullet_spin": false,
					"pierce": 1, "projectile_count": 2, "spread_angle": 0.10,
					"tags": ["talisman", "metal"],
					"stat_scalings": {"ranged_damage": 0.8, "crit_rate": 30.0},
				},
				"xuanbing_fu": {
					"name": "玄冰符", "behavior": Behavior.PROJECTILE,
					"sfx": "talisman_throw",
					"damage": 20.0, "cooldown": 1.0, "range": 230.0,
					"knockback": 130.0,
					"price": 32, "icon": "res://assets/art/weapon_xuanbing_fu.png",
					"tip": Vector2(22, -6),
					"desc": "冰符弹射2次并冰缓敌人，受远程伤害与移速加成", "tag": "远程·弹射·水",
					"bullet": "res://assets/art/bullet_ice_talisman.png", "bullet_scale": 0.6, "bullet_spin": true,
					"pierce": 1, "bounce_count": 2, "proc_chill": 0.35, "chill_dur": 2.0,
					"tags": ["talisman", "water"],
					"stat_scalings": {"ranged_damage": 0.8, "move_speed_bonus": 28.0},
				},
				"zhenshan_fu": {
					"name": "镇山符", "behavior": Behavior.PROJECTILE,
					"sfx": "talisman_throw",
					"damage": 38.0, "cooldown": 1.5, "range": 220.0,
					"knockback": 380.0,
					"price": 38, "icon": "res://assets/art/weapon_zhenshan_fu.png",
					"tip": Vector2(22, 0),
					"desc": "重符缓出穿透2敌沉重击退，受远程伤害与护甲加成", "tag": "远程·弹射·土",
					"bullet": "res://assets/art/bullet_earth_talisman.png", "bullet_scale": 0.6, "bullet_spin": true,
					"pierce": 2,
					"tags": ["talisman", "earth"],
					"stat_scalings": {"ranged_damage": 0.8, "armor": 2.5},
				},
					"jinjiao_jian": {
						"name": "金蛟剪", "behavior": Behavior.MELEE,
						"sfx": "whoosh_light", "sfx_impact": "impact_blade",
						"damage": 27.0, "cooldown": 1.25, "range": 185.0,
						"knockback": 300.0,
						"price": 38, "icon": "res://assets/art/weapon_jinjiao_jian.png",
						"tip": Vector2(22, 0),
						"desc": "金蛟大剪横扫一片，受近战伤害与暴击率加成", "tag": "近战·横扫·金",
						"arc_scale": 1.45,
						"tags": ["wide", "metal"],
						"stat_scalings": {"melee_damage": 1.0, "crit_rate": 35.0},
					},
					"qingteng_jian": {
						"name": "青藤剑", "behavior": Behavior.MELEE,
						"sfx": "whoosh_light", "sfx_impact": "impact_crack",
						"damage": 21.0, "cooldown": 1.0, "range": 160.0,
						"knockback": 220.0,
						"price": 30, "icon": "res://assets/art/weapon_qingteng_jian.png",
						"tip": Vector2(22, -12),
						"desc": "青藤缠绕之剑命中叠毒，受近战伤害与吸血加成", "tag": "近战·剑系·木",
					"proc_poison": true, "poison_ratio": 0.30, "poison_dur": 2.5,
					"tags": ["sword", "wood"],
					"stat_scalings": {"melee_damage": 1.0, "lifesteal": 90.0},
				},
				"jinlei_zhui": {
					"name": "金雷锥", "behavior": Behavior.BURST,
					"sfx": "whoosh_light", "sfx_impact": "thunder_strike",
					# 2026-10-11 平衡校准：单点重击定位（爆裂半径 55 全库最小）归位单体档，38/1.35≈28.1 入 26~32 带
					"damage": 38.0, "cooldown": 1.35, "range": 230.0,
					"knockback": 220.0,
					"price": 46, "icon": "res://assets/art/weapon_jinlei_zhui.png",
					"tip": Vector2(22, 8), "upright": true,
					"desc": "金雷贯顶单点重击，受元素伤害与暴击率加成", "tag": "远程·范围·金",
					"burst_radius": 55.0, "burst_tint": Color(1.0, 0.85, 0.4),
					"tags": ["thunder", "metal"],
					"stat_scalings": {"elemental_damage": 1.2, "crit_rate": 30.0},
				},
				"chunlei_gu": {
					"name": "春雷鼓", "behavior": Behavior.BURST,
					"sfx": "drum_boom", "sfx_impact": "drum_boom",
					"damage": 24.0, "cooldown": 1.4, "range": 225.0,
					"knockback": 200.0,
					"price": 44, "icon": "res://assets/art/weapon_chunlei_gu.png",
					"tip": Vector2(22, 0), "upright": true,
					"desc": "春雷滚滚落点范围叠毒，受元素伤害与生命回复加成", "tag": "区域·范围·木",
					"burst_radius": 90.0, "burst_tint": Color(0.5, 0.85, 0.5),
					"proc_poison": true, "poison_ratio": 0.35, "poison_dur": 3.0,
					"tags": ["thunder", "wood"],
					"stat_scalings": {"elemental_damage": 1.0, "hp_regen": 4.0},
				},
					"haojin_lun": {
						"name": "昊金轮", "behavior": Behavior.DRONE,
						"sfx": "orb_hit",
						"damage": 22.0, "cooldown": 0.45, "range": 200.0,
						"knockback": 200.0,
						"price": 42, "icon": "res://assets/art/weapon_haojin_lun.png",
						"desc": "金轮环绕切割，受召唤伤害与暴击率加成", "tag": "环绕·召唤·金",
						"tags": ["spirit", "metal"],
						"stat_scalings": {"engineering_damage": 1.0, "crit_rate": 30.0},
					},
					"lihuo_ya": {
						"name": "离火鸦", "behavior": Behavior.DRONE,
						"sfx": "drone_flutter",
						"damage": 19.0, "cooldown": 0.50, "range": 200.0,
						"knockback": 150.0,
						"price": 42, "icon": "res://assets/art/weapon_lihuo_ya.png",
						"desc": "火鸦环绕扑击引燃敌人，受召唤与元素伤害加成", "tag": "环绕·召唤·火",
						"proc_burn": true, "burn_ratio": 0.40, "burn_dur": 2.5,
						"tags": ["spirit", "fire"],
						"stat_scalings": {"engineering_damage": 1.0, "elemental_damage": 0.5},
					},

				# ---- 流派特色 6 把 ----
				"xueyin_dao": {
					"name": "血饮狂刀", "behavior": Behavior.MELEE,
					"sfx": "whoosh_light", "sfx_impact": "impact_blade",
					"damage": 14.0, "cooldown": 0.65, "range": 150.0,
					"knockback": 160.0,
					"price": 36, "icon": "res://assets/art/weapon_xueyin_dao.png",
					"tip": Vector2(-22, 20),
					"desc": "狂刀快斩痛饮敌血，受近战伤害与吸血加成", "tag": "近战·剑系·火",
					"proc_burn": true, "burn_ratio": 0.25, "burn_dur": 2.0,
					"tags": ["sword", "fire"],
					"stat_scalings": {"melee_damage": 1.0, "lifesteal": 90.0},
				},
					"jubao_chi": {
						"name": "聚宝金尺", "behavior": Behavior.MELEE,
						"sfx": "whoosh_light", "sfx_impact": "impact_blunt",
						"damage": 22.0, "cooldown": 1.15, "range": 175.0,
						"knockback": 260.0,
						"price": 30, "icon": "res://assets/art/weapon_jubao_chi.png",
						"tip": Vector2(22, -10),
						"desc": "财气越旺打得越狠，受近战伤害与收益加成", "tag": "近战·横扫·金",
						"arc_scale": 1.3,
						"tags": ["wide", "metal"],
						"stat_scalings": {"melee_damage": 0.8, "harvest": 1.2},
					},
					"tougu_ding": {
						"name": "透骨钉", "behavior": Behavior.PROJECTILE,
						"sfx": "metal_dart",
						"damage": 14.0, "cooldown": 0.9, "range": 240.0,
						"knockback": 100.0,
						"price": 34, "icon": "res://assets/art/weapon_tougu_ding.png",
						"tip": Vector2(22, -12),
						"desc": "透骨钉穿透4敌并叠毒，受远程与元素伤害加成", "tag": "远程·弹射·木",
					"bullet": "res://assets/art/bullet_bone_spike.png", "bullet_scale": 0.55, "bullet_spin": false,
					"pierce": 4, "proc_poison": true, "poison_ratio": 0.30, "poison_dur": 2.5,
					"tags": ["talisman", "wood"],
					"stat_scalings": {"ranged_damage": 0.8, "elemental_damage": 0.6},
				},
				"benlang_chui": {
					"name": "崩浪锤", "behavior": Behavior.MELEE,
					"sfx": "whoosh_heavy", "sfx_impact": "impact_blunt",
					"damage": 30.0, "cooldown": 1.4, "range": 180.0,
					"knockback": 520.0,
					"price": 34, "icon": "res://assets/art/weapon_benlang_chui.png",
					"tip": Vector2(22, 14), "upright": true,
					"desc": "崩浪重锤击飞敌群并冰缓，受近战伤害与移速加成", "tag": "近战·横扫·水",
				"arc_scale": 1.35, "proc_chill": 0.40, "chill_dur": 2.5,
				"tags": ["wide", "water"],
				"stat_scalings": {"melee_damage": 1.0, "move_speed_bonus": 25.0},
			},
					"liuling_jian": {
						"name": "六棱锏", "behavior": Behavior.MELEE,
						"sfx": "whoosh_heavy", "sfx_impact": "impact_blunt",
						"damage": 26.0, "cooldown": 1.2, "range": 165.0,
						"knockback": 330.0,
						"price": 36, "icon": "res://assets/art/weapon_liuling_jian.png",
						"tip": Vector2(22, -8), "upright": true,
					"desc": "六棱重锏以守为攻，受近战伤害与护甲加成", "tag": "近战·剑系·土",
				"tags": ["sword", "earth"],
				"stat_scalings": {"melee_damage": 1.0, "armor": 3.0},
			},
					"xuanwu_pei": {
						"name": "玄武佩", "behavior": Behavior.DRONE,
						"sfx": "drone_chime",
						"damage": 25.0, "cooldown": 0.54, "range": 205.0,
						"knockback": 420.0,
						"price": 44, "icon": "res://assets/art/weapon_xuanwu_pei.png",
						"desc": "玄武玉佩环绕震退来敌，受召唤伤害与护甲加成", "tag": "环绕·召唤·土",
						"tags": ["spirit", "earth"],
						"stat_scalings": {"engineering_damage": 1.0, "armor": 2.5, "max_hp_bonus": 0.10},
					},

				# ---- 机关支路 3 把 ----
				"jiguan_nu": {
					"name": "机关弩", "behavior": Behavior.TURRET,
					"sfx": "metal_dart",
					"damage": 18.0, "cooldown": 3.5, "range": 220.0,
					"turret_fire_cd": 0.75, "turret_lifetime": 12.0, "turret_cap": 2,
					"knockback": 120.0,
					"price": 38, "icon": "res://assets/art/weapon_jiguan_nu.png",
					"tip": Vector2(22, -20), "upright": true,
					"desc": "布设自动索敌的机关弩台，受召唤伤害与暴击率加成", "tag": "机关·召唤·金",
					"bullet": "res://assets/art/bullet_gold_needle.png", "bullet_scale": 0.55, "bullet_spin": false,
					"pierce": 1,
					"tags": ["contraption", "metal"],
					"stat_scalings": {"engineering_damage": 1.0, "crit_rate": 25.0},
				},
				"jianzhen_pan": {
					"name": "剑阵盘", "behavior": Behavior.TURRET,
					# 疾射飞剑 ⇒ 金属抛体离手族；whoosh_light 是近战前摇的铺垫层，当开火音发虚
					"sfx": "blade_shoot",
					"damage": 15.0, "cooldown": 4.0, "range": 200.0,
					"turret_fire_cd": 0.60, "turret_lifetime": 12.0, "turret_cap": 2,
					"knockback": 140.0,
					"price": 42, "icon": "res://assets/art/weapon_jianzhen_pan.png",
					"tip": Vector2(22, 0), "upright": true,
					"desc": "布设御剑阵盘疾射飞剑，受召唤与近战伤害加成", "tag": "机关·剑系·金",
					"bullet": "res://assets/art/bullet_gold_sword.png", "bullet_scale": 0.55, "bullet_spin": false,
					"pierce": 2,
					"tags": ["contraption", "sword", "metal"],
					"stat_scalings": {"engineering_damage": 1.0, "melee_damage": 0.5},
				},
				"penhuo_jiguanshou": {
					"name": "喷火兽", "behavior": Behavior.TURRET,
					"sfx": "flame_jet",
					"damage": 11.0, "cooldown": 4.2, "range": 175.0,
					"turret_fire_cd": 0.42, "turret_lifetime": 10.0, "turret_cap": 2,
					"knockback": 100.0,
					"price": 40, "icon": "res://assets/art/weapon_penhuo_jiguanshou.png",
					"tip": Vector2(22, -10), "upright": true,
					"desc": "布设喷火机关兽持续灼烧敌群，受召唤与元素伤害加成", "tag": "机关·召唤·火",
					"bullet": "res://assets/art/bullet_fire_flame.png", "bullet_scale": 0.50, "bullet_spin": true,
					"pierce": 2, "proc_burn": true, "burn_ratio": 0.40, "burn_dur": 2.5,
					"tags": ["contraption", "fire"],
					"stat_scalings": {"engineering_damage": 1.0, "elemental_damage": 0.6},
				},

				# ==================== 2026-10-11 新增 10 把 ====================
				# 设计口径（用户）：剑痴好玩的本质 = 剑系∩金系交叉武器够多（5 把），6 槽全放金剑
				# 即可同时点亮剑系三档 + 金系三档双羁绊。本次给每个五行加厚一条"主打交叉格子"到 3 把，
				# 配合商店梯度亲和 + 双流派共鸣（BalanceEconomy.tag_affinity_combo），让各流派都凑得出
				# "6 件同交叉 = 双三档"的成装路线。机关补齐 木/水/土 三格（6 把 ⇒ 三档可达），
				# 雷火符走剑阵盘式双器类三重共鸣（符箓+雷法+火），雷法升到 6 把。
				# tip 均为 tools/fit_weapon_icon.py 实测打印值（2026-10-11 批次）。

				# ---- 火 3 把：火∩剑成装路 + 火系第 10 把 ----
				"liuhuo_feijian": {
					"name": "流火飞剑", "behavior": Behavior.PROJECTILE,
					"sfx": "blade_shoot",
					"damage": 20.0, "cooldown": 0.95, "range": 240.0,
					"knockback": 150.0,
					"price": 38, "icon": "res://assets/art/weapon_liuhuo_feijian.png",
					"tip": Vector2(20, 2),
					"desc": "炽炎飞剑自动追击并穿透2敌引燃，受元素与远程伤害加成", "tag": "远程·剑系·火",
					"bullet": "res://assets/art/bullet_fire_sword.png", "bullet_scale": 0.6, "bullet_spin": false,
					"pierce": 2, "proc_burn": true, "burn_ratio": 0.35, "burn_dur": 3.0,
					"tags": ["sword", "fire"],
					"stat_scalings": {"elemental_damage": 1.0, "ranged_damage": 0.6},
				},
				"zhenhuo_fu": {
					"name": "真火符", "behavior": Behavior.PROJECTILE,
					"sfx": "talisman_throw",
					"damage": 17.0, "cooldown": 1.1, "range": 225.0,
					"knockback": 160.0,
					"price": 34, "icon": "res://assets/art/weapon_zhenhuo_fu.png",
					"tip": Vector2(12, 12),
					"desc": "三昧真火符穿透2敌烈焰灼烧，受元素与远程伤害加成", "tag": "远程·弹射·火",
					"bullet": "res://assets/art/bullet_true_fire_talisman.png", "bullet_scale": 0.65, "bullet_spin": true,
					"pierce": 2, "proc_burn": true, "burn_ratio": 0.50, "burn_dur": 3.0,
					"tags": ["talisman", "fire"],
					"stat_scalings": {"elemental_damage": 1.2, "ranged_damage": 0.6},
				},
				"leihuo_fu": {
					"name": "雷火符", "behavior": Behavior.PROJECTILE,
					# 双器类三重共鸣（仿剑阵盘）：同时计入 符箓+雷法 两条器类羁绊与火系羁绊
					"sfx": "talisman_throw",
					"damage": 10.0, "cooldown": 0.95, "range": 235.0,
					"knockback": 140.0,
					"price": 40, "icon": "res://assets/art/weapon_leihuo_fu.png",
					"tip": Vector2(16, -6),
					"desc": "雷火双符扇射2张引燃爆裂，受元素与远程伤害加成", "tag": "远程·雷法·火",
					"bullet": "res://assets/art/bullet_thunder_fire_talisman.png", "bullet_scale": 0.6, "bullet_spin": true,
					"pierce": 1, "projectile_count": 2, "spread_angle": 0.12,
					"proc_burn": true, "burn_ratio": 0.35, "burn_dur": 3.0,
					"tags": ["talisman", "thunder", "fire"],
					"stat_scalings": {"elemental_damage": 1.2, "ranged_damage": 0.6},
				},

				# ---- 水 3 把：水∩剑/水∩横扫交叉格 + 机关补格 ----
				"hanshuang_jian": {
					"name": "寒霜剑", "behavior": Behavior.MELEE,
					"sfx": "whoosh_light", "sfx_impact": "impact_blade",
					"damage": 27.0, "cooldown": 1.0, "range": 160.0,
					"knockback": 260.0,
					"price": 32, "icon": "res://assets/art/weapon_hanshuang_jian.png",
					"tip": Vector2(22, 0),
					"desc": "霜刃挥砍冻缓敌人，受近战伤害与移速加成", "tag": "近战·剑系·水",
					"arc_scale": 1.2, "proc_chill": 0.40, "chill_dur": 2.0,
					"tags": ["sword", "water"],
					"stat_scalings": {"melee_damage": 1.0, "move_speed_bonus": 25.0},
				},
				"langli_suo": {
					"name": "浪里梭", "behavior": Behavior.PROJECTILE,
					"sfx": "impact_crack",
					"damage": 19.0, "cooldown": 0.95, "range": 225.0,
					"knockback": 130.0,
					"price": 34, "icon": "res://assets/art/weapon_langli_suo.png",
					"tip": Vector2(22, 2),
					"desc": "水梭连锁弹射3次冻缓敌群，受远程伤害与移速加成", "tag": "远程·横扫·水",
					"bullet": "res://assets/art/bullet_water_shuttle.png", "bullet_scale": 0.6, "bullet_spin": true,
					"pierce": 1, "bounce_count": 3, "proc_chill": 0.35, "chill_dur": 2.0,
					"tags": ["wide", "water"],
					"stat_scalings": {"ranged_damage": 0.8, "move_speed_bonus": 28.0},
				},
				"hanquan_shou": {
					"name": "寒泉兽", "behavior": Behavior.TURRET,
					"sfx": "metal_dart",
					"damage": 9.0, "cooldown": 4.0, "range": 170.0,
					"turret_fire_cd": 0.45, "turret_lifetime": 10.0, "turret_cap": 2,
					"knockback": 90.0,
					"price": 40, "icon": "res://assets/art/weapon_hanquan_shou.png",
					"tip": Vector2(20, -6), "upright": true,
					"desc": "布设寒泉机关兽连吐冰针冻缓敌群，受召唤伤害与攻击间隔加成", "tag": "机关·召唤·水",
					"bullet": "res://assets/art/bullet_ice_needle.png", "bullet_scale": 0.50, "bullet_spin": false,
					"pierce": 2, "proc_chill": 0.30, "chill_dur": 1.5,
					"tags": ["contraption", "water"],
					"stat_scalings": {"engineering_damage": 1.0, "cdr_bonus": 20.0},
				},

				# ---- 木 2 把：木∩符箓第 3 把 + 机关补格 ----
				"gudu_fu": {
					"name": "蛊毒符", "behavior": Behavior.PROJECTILE,
					"sfx": "talisman_throw",
					"damage": 16.0, "cooldown": 1.0, "range": 230.0,
					"knockback": 120.0,
					"price": 34, "icon": "res://assets/art/weapon_gudu_fu.png",
					"tip": Vector2(12, 10),
					"desc": "蛊虫毒符连锁弹射3次剧毒蔓延，受远程与元素伤害加成", "tag": "远程·弹射·木",
					"bullet": "res://assets/art/bullet_gu_talisman.png", "bullet_scale": 0.6, "bullet_spin": true,
					"pierce": 1, "bounce_count": 3, "proc_poison": true, "poison_ratio": 0.35, "poison_dur": 3.0,
					"tags": ["talisman", "wood"],
					"stat_scalings": {"ranged_damage": 0.8, "elemental_damage": 0.8, "hp_regen": 3.0},
				},
				"tengluo_jiguan": {
					"name": "藤萝机关", "behavior": Behavior.TURRET,
					"sfx": "impact_crack",
					"damage": 14.0, "cooldown": 3.6, "range": 210.0,
					"turret_fire_cd": 0.65, "turret_lifetime": 12.0, "turret_cap": 2,
					"knockback": 110.0,
					"price": 38, "icon": "res://assets/art/weapon_tengluo_jiguan.png",
					"tip": Vector2(22, -16), "upright": true,
					"desc": "布设藤萝弹射器毒镖叠毒，受召唤伤害与生命回复加成", "tag": "机关·召唤·木",
					"bullet": "res://assets/art/bullet_leaf_dagger.png", "bullet_scale": 0.55, "bullet_spin": false,
					"pierce": 1, "proc_poison": true, "poison_ratio": 0.30, "poison_dur": 2.5,
					"tags": ["contraption", "wood"],
					"stat_scalings": {"engineering_damage": 1.0, "hp_regen": 3.0},
				},

				# ---- 土 2 把：土∩剑第 3 把 + 机关补格（机关 6 把 ⇒ 三档可达） ----
				"bengshan_jian": {
					"name": "崩山剑", "behavior": Behavior.MELEE,
					"sfx": "whoosh_heavy", "sfx_impact": "impact_blunt",
					"damage": 33.0, "cooldown": 1.2, "range": 170.0,
					"knockback": 420.0,
					"price": 38, "icon": "res://assets/art/weapon_bengshan_jian.png",
					"tip": Vector2(22, 0),
					"desc": "崩山重剑横扫大力震退，受近战伤害与护甲加成", "tag": "近战·剑系·土",
					"arc_scale": 1.3,
					"tags": ["sword", "earth"],
					"stat_scalings": {"melee_damage": 1.0, "armor": 2.5},
				},
				"leishi_jiguan": {
					"name": "垒石机关", "behavior": Behavior.TURRET,
					"sfx": "impact_blunt",
					"damage": 20.0, "cooldown": 4.5, "range": 190.0,
					"turret_fire_cd": 0.9, "turret_lifetime": 10.0, "turret_cap": 2,
					"knockback": 300.0,
					"price": 42, "icon": "res://assets/art/weapon_leishi_jiguan.png",
					"tip": Vector2(22, 16), "upright": true,
					"desc": "布设垒石投掷机抛石砸退敌群，受召唤伤害与护甲加成", "tag": "机关·召唤·土",
					"bullet": "res://assets/art/bullet_earth_talisman.png", "bullet_scale": 0.6, "bullet_spin": true,
					"pierce": 1,
					"tags": ["contraption", "earth"],
					"stat_scalings": {"engineering_damage": 1.0, "armor": 2.0},
				},

				# ==================== 2026-10-11 第二批新增 12 把 ====================
				# 设计口径（用户）：召唤（御灵）搭不出来——御灵 6 把每五行仅 1 把、御灵∩土仅 2 把；
				# "除了剑系其他的都要继续拓展"，且合理处上三标签（仿剑阵盘机关+剑系+金的双重身份逻辑）。
				# 本批：御灵 +6（每五行交叉 ≥2，追平剑系）、雷法 +2、横扫 +2、符箓 +1、机关 +1；
				# 三标签 3 把：剑灵 [spirit,sword,metal]、傀儡兽 [contraption,spirit,earth]（机关师
				# 双器类交叉从 0→1）、惊蛰符 [talisman,thunder,wood]（雷法真君交叉第 2 把）。
				# 御灵纸面 DPS 44~48（×SPIRIT_CONTACT_DUTY 0.75 ⇒ 有效 33~36 落御灵带 30~38）。
				# tip 由 tools/fit_weapon_icon.py 实测回填。

				# ---- 御灵 6 把（DRONE）：每五行交叉补到 2~3 把 ----
				"jinming_ling": {
					"name": "金鸣铃", "behavior": Behavior.DRONE,
					"sfx": "drone_chime",
					"damage": 22.0, "cooldown": 0.47, "range": 170.0,
					"knockback": 210.0,
					"price": 42, "icon": "res://assets/art/weapon_jinming_ling.png",
					"desc": "金铃环绕震鸣切金，受召唤伤害与暴击率加成", "tag": "环绕·召唤·金",
					"tags": ["spirit", "metal"],
					"stat_scalings": {"engineering_damage": 1.0, "crit_rate": 30.0},
				},
				"muling_ou": {
					"name": "木灵偶", "behavior": Behavior.DRONE,
					"sfx": "drone_flutter",
					"damage": 24.0, "cooldown": 0.50, "range": 175.0,
					"knockback": 180.0,
					"price": 42, "icon": "res://assets/art/weapon_muling_ou.png",
					"desc": "木偶人环绕护卫生生不息，受召唤伤害与生命回复加成", "tag": "环绕·召唤·木",
					"tags": ["spirit", "wood"],
					"stat_scalings": {"engineering_damage": 1.0, "hp_regen": 4.0},
				},
				"bingpo_zhu": {
					"name": "冰魄珠", "behavior": Behavior.DRONE,
					"sfx": "drone_chime",
					"damage": 23.0, "cooldown": 0.48, "range": 175.0,
					"knockback": 190.0,
					"price": 42, "icon": "res://assets/art/weapon_bingpo_zhu.png",
					"desc": "冰魄宝珠环绕冻缓来敌，受召唤伤害与攻击间隔加成", "tag": "环绕·召唤·水",
					"proc_chill": 0.40, "chill_dur": 2.5,
					"tags": ["spirit", "water"],
					"stat_scalings": {"engineering_damage": 1.0, "cdr_bonus": 30.0},
				},
				"chiyan_ying": {
					"name": "赤炎萤", "behavior": Behavior.DRONE,
					"sfx": "drone_flutter",
					"damage": 18.0, "cooldown": 0.42, "range": 170.0,
					"knockback": 150.0,
					"price": 42, "icon": "res://assets/art/weapon_chiyan_ying.png",
					"desc": "火萤群环绕扑击引燃敌人，受召唤与元素伤害加成", "tag": "环绕·召唤·火",
					"proc_burn": true, "burn_ratio": 0.35, "burn_dur": 2.5,
					"tags": ["spirit", "fire"],
					"stat_scalings": {"engineering_damage": 1.0, "elemental_damage": 0.5},
				},
				"tuling_shi": {
					"name": "土灵石", "behavior": Behavior.DRONE,
					"sfx": "orb_hit",
					"damage": 25.0, "cooldown": 0.52, "range": 175.0,
					"knockback": 330.0,
					"price": 42, "icon": "res://assets/art/weapon_tuling_shi.png",
					"desc": "符文灵石环绕撞击震退敌群，受召唤伤害与护甲加成", "tag": "环绕·召唤·土",
					"tags": ["spirit", "earth"],
					"stat_scalings": {"engineering_damage": 1.0, "armor": 2.5},
				},
				"jianling": {
					"name": "剑灵", "behavior": Behavior.DRONE,
					# 三重共鸣（仿剑阵盘）：同时计入 御灵+剑系 两条器类羁绊与金系羁绊
					"sfx": "drone_chime",
					"damage": 21.0, "cooldown": 0.45, "range": 172.0,
					"knockback": 170.0,
					"price": 44, "icon": "res://assets/art/weapon_jianling.png",
					"desc": "剑形精魂环绕飞斩，受召唤伤害与暴击率加成", "tag": "环绕·剑灵·金",
					"tags": ["spirit", "sword", "metal"],
					"stat_scalings": {"engineering_damage": 1.0, "crit_rate": 30.0},
				},

				# ---- 三标签交叉 2 把 + 雷法/横扫/符箓/机关补强 ----
				"kuilei_shou": {
					"name": "傀儡兽", "behavior": Behavior.TURRET,
					# 三重共鸣（仿剑阵盘）：同时计入 机关+御灵 两条器类羁绊与土系羁绊
					"sfx": "impact_crack",
					"damage": 12.0, "cooldown": 3.8, "range": 200.0,
					"turret_fire_cd": 0.55, "turret_lifetime": 12.0, "turret_cap": 2,
					"knockback": 150.0,
					"price": 42, "icon": "res://assets/art/weapon_kuilei_shou.png",
					"tip": Vector2(22, -2), "upright": true,
					"desc": "布设符灯傀儡兽掷石守御，受召唤伤害与护甲加成", "tag": "机关·傀儡·土",
					"bullet": "res://assets/art/bullet_earth_talisman.png", "bullet_scale": 0.55, "bullet_spin": true,
					"pierce": 1,
					"tags": ["contraption", "spirit", "earth"],
					"stat_scalings": {"engineering_damage": 1.0, "armor": 2.0},
				},
				"lieshan_duo": {
					"name": "裂山铎", "behavior": Behavior.BURST,
					"sfx": "whoosh_heavy", "sfx_impact": "drum_boom",
					"damage": 30.0, "cooldown": 1.40, "range": 225.0,
					"knockback": 340.0,
					"price": 45, "icon": "res://assets/art/weapon_lieshan_duo.png",
					"tip": Vector2(20, 2), "upright": true,
					"desc": "铎钟裂山震波轰击区域大力击退，受元素伤害与护甲加成", "tag": "区域·范围·土",
					"burst_radius": 85.0, "burst_tint": Color(0.80, 0.66, 0.38),
					"tags": ["thunder", "earth"],
					"stat_scalings": {"elemental_damage": 1.2, "armor": 2.5},
				},
				"jingzhe_fu": {
					"name": "惊蛰符", "behavior": Behavior.PROJECTILE,
					# 三重共鸣（仿剑阵盘）：同时计入 符箓+雷法 两条器类羁绊与木系羁绊
					"sfx": "talisman_throw",
					"damage": 16.0, "cooldown": 1.0, "range": 230.0,
					"knockback": 130.0,
					"price": 36, "icon": "res://assets/art/weapon_jingzhe_fu.png",
					"tip": Vector2(0, -22),
					"desc": "惊蛰雷符弹射2次叠毒滋蔓，受远程与元素伤害加成", "tag": "远程·雷法·木",
					"bullet": "res://assets/art/bullet_jingzhe_fu.png", "bullet_scale": 0.6, "bullet_spin": true,
					"pierce": 1, "bounce_count": 2, "proc_poison": true, "poison_ratio": 0.30, "poison_dur": 2.5,
					"tags": ["talisman", "thunder", "wood"],
					"stat_scalings": {"ranged_damage": 0.8, "elemental_damage": 0.8, "hp_regen": 3.0},
				},
				"liaoyuan_shan": {
					"name": "燎原扇", "behavior": Behavior.MELEE,
					"sfx": "fan_gust", "sfx_impact": "impact_crack",
					"damage": 20.0, "cooldown": 1.20, "range": 180.0,
					"knockback": 300.0,
					"price": 36, "icon": "res://assets/art/weapon_liaoyuan_shan.png",
					"tip": Vector2(22, 0),
					"desc": "扇出燎原火风宽幅引燃，受近战与元素伤害加成", "tag": "近战·横扫·火",
					"arc_scale": 1.35, "proc_burn": true, "burn_ratio": 0.40, "burn_dur": 3.0,
					"tags": ["wide", "fire"],
					"stat_scalings": {"melee_damage": 1.0, "elemental_damage": 0.8, "move_speed_bonus": 25.0},
				},
				"kaishan_fu": {
					"name": "开山斧", "behavior": Behavior.MELEE,
					"sfx": "whoosh_heavy", "sfx_impact": "impact_blunt",
					"damage": 29.0, "cooldown": 1.35, "range": 175.0,
					"knockback": 480.0,
					"price": 38, "icon": "res://assets/art/weapon_kaishan_fu.png",
					"tip": Vector2(22, 0),
					"desc": "开山巨斧横劈大力震退，受近战伤害与护甲加成", "tag": "近战·横扫·土",
					"arc_scale": 1.3,
					"tags": ["wide", "earth"],
					"stat_scalings": {"melee_damage": 1.0, "armor": 2.5},
				},
					"gengjin_fu": {
						"name": "庚金符", "behavior": Behavior.PROJECTILE,
						"sfx": "metal_dart",
						"damage": 9.0, "cooldown": 0.60, "range": 230.0,
						"knockback": 85.0,
						"price": 34, "icon": "res://assets/art/weapon_gengjin_fu.png",
						"tip": Vector2(0, -22),
						"desc": "连射2张金符高速追击，受远程伤害与暴击率加成", "tag": "远程·弹射·金",
						"bullet": "res://assets/art/bullet_gengjin_fu.png", "bullet_scale": 0.55, "bullet_spin": false,
						"pierce": 1, "projectile_count": 2, "spread_angle": 0.10,
						"tags": ["talisman", "metal"],
						"stat_scalings": {"ranged_damage": 0.8, "crit_rate": 30.0},
					},

					# ==================== 2026-10-12 第三批 8 把：填满只剩 1 把的 器类×五行 交叉格 ====================
					# 空洞格清单（各仅 1 把，羁绊 2 件档都凑不出）：剑-木、符-水、符-土、雷-金、雷-水、
					# 机关-木/水/火。每把照同行为同格锚点法定数值，零新行为代码。
					# 顺带把冷门 scaling 链接进新法器（吸血/冷却/暴击伤害/范围/额外生命），激活死链。
					# 图标暂借同格锚点贴图占位，TODO(media-gen)：出专属图标后替换并补 manifest。
					"taomu_jian": {
						"name": "桃木剑", "behavior": Behavior.MELEE,
						"sfx": "whoosh_light", "sfx_impact": "impact_blade",
						"damage": 20.0, "cooldown": 0.95, "range": 150.0,
						"knockback": 230.0,
						"price": 30, "icon": "res://assets/art/weapon_qingteng_jian.png",
						"tip": Vector2(22, -12),
						"desc": "桃木辟邪之剑快斩汲血，受近战伤害与吸血加成", "tag": "近战·剑系·木",
						"tags": ["sword", "wood"],
						"stat_scalings": {"melee_damage": 1.0, "lifesteal": 90.0},
					},
					"guishui_fu": {
						"name": "癸水符", "behavior": Behavior.PROJECTILE,
						"sfx": "talisman_throw",
						"damage": 21.0, "cooldown": 0.85, "range": 230.0,
						"knockback": 120.0,
						"price": 32, "icon": "res://assets/art/weapon_xuanbing_fu.png",
						"tip": Vector2(22, -6),
						"desc": "癸水阴符急速连发穿透2敌，受远程伤害与攻击间隔加成", "tag": "远程·弹射·水",
						"bullet": "res://assets/art/bullet_ice_talisman.png", "bullet_scale": 0.6, "bullet_spin": true,
						"pierce": 2,
						"tags": ["talisman", "water"],
						"stat_scalings": {"ranged_damage": 0.8, "cdr_bonus": 25.0},
					},
					"houtu_fu": {
						"name": "厚土符", "behavior": Behavior.PROJECTILE,
						"sfx": "talisman_throw",
						"damage": 11.0, "cooldown": 1.10, "range": 220.0,
						"knockback": 200.0,
						"price": 32, "icon": "res://assets/art/weapon_zhenshan_fu.png",
						"tip": Vector2(22, 0),
						"desc": "三张厚土符扇形铺开各锁1敌，受远程伤害与护甲加成", "tag": "远程·弹射·土",
						"bullet": "res://assets/art/bullet_earth_talisman.png", "bullet_scale": 0.6, "bullet_spin": true,
						"pierce": 1, "projectile_count": 3, "spread_angle": 0.22,
						"tags": ["talisman", "earth"],
						"stat_scalings": {"ranged_damage": 0.8, "armor": 2.0},
					},
					"jinxiao_leiling": {
						"name": "金霄雷令", "behavior": Behavior.BURST,
						"sfx": "whoosh_light", "sfx_impact": "thunder_strike",
						"damage": 30.0, "cooldown": 1.50, "range": 230.0,
						"knockback": 260.0,
						"price": 46, "icon": "res://assets/art/weapon_jinlei_zhui.png",
						"tip": Vector2(22, 8), "upright": true,
						"desc": "金霄神雷轰击一片敌群，受元素伤害与暴击伤害加成", "tag": "区域·范围·金",
						"burst_radius": 78.0, "burst_tint": Color(1.0, 0.88, 0.45),
						"tags": ["thunder", "metal"],
						"stat_scalings": {"elemental_damage": 1.0, "crit_mult_bonus": 30.0},
					},
					"xuanming_leizhu": {
						"name": "玄冥雷珠", "behavior": Behavior.BURST,
						"sfx": "flute_wave", "sfx_impact": "thunder_strike",
						"damage": 28.0, "cooldown": 1.45, "range": 225.0,
						"knockback": 300.0,
						"price": 44, "icon": "res://assets/art/weapon_flute.png",
						"tip": Vector2(20, 0), "upright": true,
						"desc": "玄冥阴雷炸开冻缓敌群，受元素伤害与移速加成", "tag": "区域·范围·水",
						"burst_radius": 70.0, "burst_tint": Color(0.45, 0.75, 1.0),
						"proc_chill": 0.40, "chill_dur": 2.0,
						"tags": ["thunder", "water"],
						"stat_scalings": {"elemental_damage": 1.0, "move_speed_bonus": 28.0},
					},
					"qingmu_pao": {
						"name": "青木炮", "behavior": Behavior.TURRET,
						"sfx": "impact_crack",
						"damage": 14.0, "cooldown": 3.4, "range": 220.0,
						"turret_fire_cd": 0.70, "turret_lifetime": 12.0, "turret_cap": 2,
						"knockback": 120.0,
						"price": 38, "icon": "res://assets/art/weapon_tengluo_jiguan.png",
						"tip": Vector2(22, -16), "upright": true,
						"desc": "布设青木灵炮贯穿敌阵，受召唤伤害与生命回复加成", "tag": "机关·召唤·木",
						"bullet": "res://assets/art/bullet_leaf_dagger.png", "bullet_scale": 0.55, "bullet_spin": false,
						"pierce": 2,
						"tags": ["contraption", "wood"],
						"stat_scalings": {"engineering_damage": 1.0, "hp_regen": 4.0},
					},
					"ningbing_nu": {
						"name": "凝冰机弩", "behavior": Behavior.TURRET,
						"sfx": "metal_dart",
						"damage": 12.0, "cooldown": 4.0, "range": 260.0,
						"turret_fire_cd": 0.55, "turret_lifetime": 10.0, "turret_cap": 2,
						"knockback": 95.0,
						"price": 40, "icon": "res://assets/art/weapon_hanquan_shou.png",
						"tip": Vector2(20, -6), "upright": true,
						"desc": "布设凝冰机弩远程点杀冻缓敌人，受召唤伤害与攻击范围加成", "tag": "机关·召唤·水",
						"bullet": "res://assets/art/bullet_ice_needle.png", "bullet_scale": 0.50, "bullet_spin": false,
						"pierce": 1, "proc_chill": 0.25, "chill_dur": 1.5,
						"tags": ["contraption", "water"],
						"stat_scalings": {"engineering_damage": 1.0, "range_bonus": 25.0},
					},
					"fenghuo_tai": {
						"name": "烽火台", "behavior": Behavior.TURRET,
						"sfx": "flame_jet",
						"damage": 10.0, "cooldown": 4.4, "range": 175.0,
						"turret_fire_cd": 0.50, "turret_lifetime": 11.0, "turret_cap": 2,
						"knockback": 100.0,
						"price": 40, "icon": "res://assets/art/weapon_penhuo_jiguanshou.png",
						"tip": Vector2(22, -10), "upright": true,
						"desc": "布设烽火台持续喷焰引燃敌群，受召唤伤害与最大生命加成", "tag": "机关·召唤·火",
						"bullet": "res://assets/art/bullet_fire_flame.png", "bullet_scale": 0.50, "bullet_spin": true,
						"pierce": 2, "proc_burn": true, "burn_ratio": 0.35, "burn_dur": 2.5,
						"tags": ["contraption", "fire"],
						"stat_scalings": {"engineering_damage": 1.0, "max_hp_bonus": 0.10},
					},
}

## 流派羁绊：同 tag 法器持有多件时激活阶梯加成（重复同名法器也计数）
## 涵盖器类 6 系 + 五行 5 系，共 11 种流派羁绊
##
## 本表是羁绊的**唯一真话**，数值和文案都只从这里出：
##   · 数值 —— 每档幅度只有 `values` 与 effects 声明的 side 列表这一份；
##     SynergySystem 按 effects 逐条结算进 GameManager 的 `field`，代码里不许再抄字面量。
##   · 文案 —— SynergyUI.tier_line() / synergy_desc() 由 effects 生成。
##     **表里不许手写 "desc"**（UnitRunner 断言它不存在）：2026-10-11 火系局内写「法伤」
##     而属性表根本没有这条、木系与召唤当天补的伤害乘区漏在局内文案外，
##     根因都是「同一事实抄了三份」，抄的那一份永远不会跟着改。
##   · 判据 —— tests/unit/unit_consistency_tests.gd 走 apply_counts 真结算，
##     把 field 增量与生成文案里的数字逐个对账，并断言没一条隐性加成绕过 effects。
##
## effects 每条：
##   field  —— 被改写的 GameManager 属性名（恒 synergy_* 前缀；气血那条再经 apply_synergy_hp 落到 player）
##   list   —— 取数用的列表 key，主效果恒为 "values"
##   op     —— "add"：field += v（1.0 基数的乘区存加成幅度，0.08 即 +8%）；"mul"：field *= v（攻速存 0.92 这类系数）
##   label  —— 给人看的属性名；局内阶梯行与图鉴共用同一个词，不许一处简称一处全称
##   form   —— 展示折算："pct" 0.08→+8%、"pct_down" 0.92→-8%、"flat" 3→+3、"flat1" 1.0→+1.0
##   suffix —— 展示后缀，如 "/秒"
const SYNERGIES: Dictionary = {
	# ---- 器类羁绊 ----
	"sword": {
		"name": "剑系", "thresholds": [2, 4, 6], "values": [0.15, 0.30, 0.50],
		"effects": [
			{"field": "synergy_range_mult", "list": "values", "op": "add", "label": "攻击范围", "form": "pct"},
		],
	},
	"talisman": {
		"name": "弹射", "thresholds": [2, 4, 6], "values": [1, 2, 3],
		"effects": [
			{"field": "synergy_bonus_pierce", "list": "values", "op": "add", "label": "弹丸穿透", "form": "flat"},
		],
	},
	"thunder": {
		# 名字与武器 def.tag 里的「雷法」对齐；效果给的是攻速（攻击间隔），不是范围
		"name": "雷法", "thresholds": [2, 4, 6], "values": [0.92, 0.85, 0.75],
		"effects": [
			{"field": "synergy_haste_mult", "list": "values", "op": "mul", "label": "攻击间隔", "form": "pct_down"},
		],
	},
	"spirit": {
		"name": "召唤", "thresholds": [2, 4, 6], "values": [15, 30, 50],
		# 2026-10-11：这一档只给「生命 + 召唤伤害」两条。当天曾另立过一条环绕专属伤害乘区
		# （局内叫「灵宝伤害」），玩家看不懂那个词，且它和已有的「武器伤害」是第三种伤害词，
		# 已按用户决定撤销，幅度全部折进下面这条召唤伤害（环绕/机关炮台/灵兽共用这一条属性链路）。
		# 幅度由 tests/BalanceSimCheck 的御灵 W10/W20 TTK 带（30~70s）标定，改数要重跑那条判据。
		"eng_values": [4.0, 9.0, 16.0],
		"effects": [
			{"field": "synergy_max_hp_bonus", "list": "values", "op": "add", "label": "生命", "form": "flat"},
			{"field": "synergy_engineering_damage", "list": "eng_values", "op": "add", "label": "召唤伤害", "form": "flat"},
		],
	},
	"wide": {
		"name": "横扫", "thresholds": [2, 4, 6], "values": [0.10, 0.20, 0.30],
		"effects": [
			{"field": "synergy_damage_mult", "list": "values", "op": "add", "label": "武器伤害", "form": "pct"},
		],
	},
	"contraption": {
		"name": "机关", "thresholds": [2, 4, 6], "values": [0.15, 0.30, 0.50],
		"effects": [
			{"field": "synergy_contraption_mult", "list": "values", "op": "add", "label": "机关伤害", "form": "pct"},
		],
	},

	# ---- 五行羁绊 ----
	"metal": {
		"name": "金系", "thresholds": [2, 4, 6], "values": [0.06, 0.12, 0.20],
		"crit_mult_values": [0.20, 0.40, 0.75],
		"effects": [
			{"field": "synergy_crit_rate", "list": "values", "op": "add", "label": "暴击率", "form": "pct"},
			{"field": "synergy_crit_mult", "list": "crit_mult_values", "op": "add", "label": "暴击伤害", "form": "pct"},
		],
	},
	"wood": {
		"name": "木系", "thresholds": [2, 4, 6], "values": [1.0, 2.0, 3.5],
		"ls_values": [0.02, 0.04, 0.07],
		# 2026-10-11 平衡校准：此前零伤害乘区（剧毒流成型 TTK 垫底根因），仿火系补一条伤害档
		"dmg_values": [0.06, 0.12, 0.20],
		"effects": [
			{"field": "synergy_hp_regen", "list": "values", "op": "add", "label": "回复", "form": "flat1", "suffix": "/秒"},
			{"field": "synergy_lifesteal", "list": "ls_values", "op": "add", "label": "吸血", "form": "pct"},
			{"field": "synergy_damage_mult", "list": "dmg_values", "op": "add", "label": "武器伤害", "form": "pct"},
		],
	},
	"water": {
		"name": "水系", "thresholds": [2, 4, 6], "values": [0.94, 0.88, 0.80],
		"spd_values": [0.08, 0.16, 0.25],
		"effects": [
			{"field": "synergy_haste_mult", "list": "values", "op": "mul", "label": "攻击间隔", "form": "pct_down"},
			{"field": "synergy_move_speed_mult", "list": "spd_values", "op": "add", "label": "移动速度", "form": "pct"},
		],
	},
	"fire": {
		"name": "火系", "thresholds": [2, 4, 6], "values": [0.08, 0.16, 0.26],
		"burn_values": [0.30, 0.60, 1.00],
		"effects": [
			{"field": "synergy_damage_mult", "list": "values", "op": "add", "label": "武器伤害", "form": "pct"},
			{"field": "synergy_burn_mult", "list": "burn_values", "op": "add", "label": "灼烧", "form": "pct"},
		],
	},
	"earth": {
		"name": "土系", "thresholds": [2, 4, 6], "values": [3.0, 6.0, 10.0],
		"kb_values": [0.25, 0.50, 0.80],
		"effects": [
			{"field": "synergy_armor", "list": "values", "op": "add", "label": "护甲", "form": "flat"},
			{"field": "synergy_knockback_mult", "list": "kb_values", "op": "add", "label": "击退力度", "form": "pct"},
		],
	},
}

## 羁绊可改写的 GameManager 属性全集：SynergySystem 每轮结算前按它清零，
## 判据按它比对增量。新增 synergy_* 属性必须同时进这张表与某条 effects，
## 否则 UnitRunner 报红（漏进清零表 = 跨波累加的隐形 Bug，漏进 effects = 白送不显示）。
const SYNERGY_FIELDS: Array[String] = [
	"synergy_bonus_pierce", "synergy_damage_mult", "synergy_range_mult", "synergy_haste_mult",
	"synergy_max_hp_bonus", "synergy_engineering_damage", "synergy_crit_rate", "synergy_crit_mult",
	"synergy_hp_regen", "synergy_lifesteal", "synergy_move_speed_mult", "synergy_burn_mult",
	"synergy_armor", "synergy_knockback_mult", "synergy_contraption_mult",
]

## 某属性的羁绊基数（"add" 从基数起算，"mul" 从 1.0 起算）：与 GameManager 声明初值同源
## 基数写成 int 的字段（穿透次数）＝ 声明该属性是整数，SynergySystem 结算后按它回截类型，
## 往 int 属性 set 一个 float 会被引擎打回「Invalid assignment」并静默留旧值。
const SYNERGY_BASE := {
	"synergy_bonus_pierce": 0, "synergy_damage_mult": 1.0, "synergy_range_mult": 1.0,
	"synergy_haste_mult": 1.0, "synergy_max_hp_bonus": 0.0, "synergy_engineering_damage": 0.0,
	"synergy_crit_rate": 0.0, "synergy_crit_mult": 0.0, "synergy_hp_regen": 0.0,
	"synergy_lifesteal": 0.0, "synergy_move_speed_mult": 0.0, "synergy_burn_mult": 1.0,
	"synergy_armor": 0.0, "synergy_knockback_mult": 1.0, "synergy_contraption_mult": 1.0,
}

## 开局六选一：金木水火土五种代表性本命法器 + 御灵入门「灵蝶」
const STARTER_IDS: Array = ["qingyun_sword", "wanmu_lingfu", "bajiao_fan", "huoyan_fu", "fantian_yin", "lingdie"]

## 商店武器池（全部法器，分批新增记录见各段注释）
const SHOP_POOL: Array = [
	"qingyun_sword", "gengjin_feijian", "liuye_feidao", "baoyu_liuhuazhen",
	"qingmu_tengbian", "wanmu_lingfu", "lingdie", "lianhuan_lingdan",
	"bajiao_fan", "xuanbing_feizhen", "hanquan_yulian", "bihai_chaoyindi",
	"huoyan_fu", "chiyan_dao", "fentian_baodeng", "sanmei_huohu",
	"wulei_paizi", "fantian_yin", "hunyuan_zhong", "xuanwu_lingdun",
	# 2026-10-10 新增 15 把：补 器类×五行 格子 + 流派专武
	"jinzhen_fu", "xuanbing_fu", "zhenshan_fu", "jinjiao_jian", "qingteng_jian",
	"jinlei_zhui", "chunlei_gu", "haojin_lun", "lihuo_ya",
	"xueyin_dao", "jubao_chi", "tougu_ding", "benlang_chui", "liuling_jian", "xuanwu_pei",
	# 机关支路 3 把
	"jiguan_nu", "jianzhen_pan", "penhuo_jiguanshou",
	# 2026-10-11 新增 10 把：加厚五行×器类交叉格子 + 补机关/雷法（详见 DEFS 尾部设计注释）
	"liuhuo_feijian", "zhenhuo_fu", "leihuo_fu",
	"hanshuang_jian", "langli_suo", "hanquan_shou",
	"gudu_fu", "tengluo_jiguan", "bengshan_jian", "leishi_jiguan",
	# 2026-10-11 第二批 12 把：御灵全面加厚 + 三标签交叉（详见 DEFS 尾部设计注释）
	"jinming_ling", "muling_ou", "bingpo_zhu", "chiyan_ying", "tuling_shi", "jianling",
	"kuilei_shou", "lieshan_duo", "jingzhe_fu", "liaoyuan_shan", "kaishan_fu", "gengjin_fu",
	# 2026-10-12 第三批 8 把：填满只剩 1 把的 器类×五行 交叉格（详见 DEFS 尾部设计注释）
	"taomu_jian", "guishui_fu", "houtu_fu", "jinxiao_leiling",
	"xuanming_leizhu", "qingmu_pao", "ningbing_nu", "fenghuo_tai",
]

## 回血丹（商店消耗品）
const POTION_ID: String = "healing_pill"
const POTION_BASE_PRICE: int = 10

static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, {})

## 法器攻击方式短标（货架卡色签 / 详情卡「攻击方式」行共用）：
## behavior 是结构真话，词汇与 def.tag 首段（"近战·剑系·金"）保持一致。
static func behavior_label(def: Dictionary) -> String:
	match int(def.get("behavior", Behavior.MELEE)):
		Behavior.MELEE:
			return "近战"
		Behavior.PROJECTILE:
			return "远程"
		Behavior.BURST:
			return "范围"
		Behavior.DRONE:
			return "环绕"
		Behavior.TURRET:
			return "机关"
	return "近战"

## 攻击方式的机制解释（点货架卡那颗「攻击方式」色签弹出，消费方 ShopChipTips）。
## 三条口径：
## ① 只写代码里真做了的事（出手条件 / 判定形状 / 伤害怎么结算），**数值一个都不写在这里**：
##    范围、冷却、同时站几座、吃哪些属性，全部由 ShopChipTips 现读数据表与账单，
##    改表不改文案 ⇒ 这段解释永远不会变成假话。
## ② 短标与 behavior_label 同源。图鉴旧写法自有一套词（把 DRONE 叫「召唤」、BURST 叫「轰击」），
##    而「召唤」同时是 spirit 羁绊的名字 ⇒ 同一排两颗色签，一颗说出手方式一颗说流派，
##    玩家分不出来（2026-10-11 用户「标签看不懂，点一下要能解释」）。
## ③ 新增 Behavior 必须同时补这一条，由单测「每种攻击方式都有机制解释」钉住。
const BEHAVIOR_TIPS: Dictionary = {
	Behavior.MELEE: {
		"how": "锁到敌人后朝它突进一挥，身前一片扇形一起扫到",
		"notes": [
			"挥得多宽、打得到多远，就是卡上「攻击范围」那一行；特性带「横扫」的扇形更宽。",
			"敌人必须在身前一挥够得着的地方，否则这一路法器不出手。",
		],
	},
	Behavior.PROJECTILE: {
		"how": "朝锁定的敌人发射弹丸，弹丸出膛后自己追上去",
		"notes": [
			"卡上「特性」那一行写的就是弹丸的行为：穿透几名、一次几发、弹射几次。",
			"弹丸类最吃「弹射」羁绊（每档加穿透），也吃攻击范围（锁敌的圈更大）。",
		],
	},
	Behavior.BURST: {
		"how": "蓄力后在敌人脚下引雷爆发，落点周围一圈一起吃",
		"notes": [
			"打的是区域不是单体：挤成一团的敌群一次全中。",
			"没有锁到目标时朝身前落，不会空转。",
		],
	},
	Behavior.DRONE: {
		"how": "绕着本体转圈，贴到的敌人持续掉血",
		"notes": [
			"不靠出手那一帧：同一个敌人各自有命中间隔，攻速越快贴得越疼。",
			"打得到的是绕身那一圈，远处的敌人够不着 ⇒ 通常再配一把近战或远程补上。",
			"升星会分身：★2 一化为二、★3 一化为三，每具独立贴身结算，总伤害不变但贴得更全。",
		],
	},
	Behavior.TURRET: {
		"how": "按冷却在脚下布设一座机关，它自己索敌开火、寿命到点消散",
		"notes": [
			"同时最多站那么几座，摆满就撤掉最旧的一座顶上；升星多站一座。",
			"机关这一类独享「机关」羁绊的伤害档，别的法器不吃这一条。",
		],
	},
}

## 这一攻击方式的机制解释（缺条目返回空字典，由调用方决定要不要画）
static func behavior_tip(behavior: int) -> Dictionary:
	return BEHAVIOR_TIPS.get(behavior, {})

## 全法器库里属于这一攻击方式的把数（解释卡上的「这一类共 N 把」）
static func behavior_count(behavior: int) -> int:
	var n := 0
	for id in DEFS.keys():
		if int((DEFS[id] as Dictionary).get("behavior", Behavior.MELEE)) == behavior:
			n += 1
	return n

## 货架卡窄行用的紧凑特性串：只取数据表字段（穿透 / 发数 / 弹射 / 横扫），
## 不含 proc 类（desc 已覆盖）与全局羁绊加成（详情卡 StatsTipFactory.weapon_feats 才是完整口径）。
## 卡内宽最小 124px 且 BonusRows 行不换行 ⇒ 最多取 2 段、无空格，超宽必溢出卡面。
## 量词用「发」不用「段」（2026-10-11 用户：看不懂）：projectile_count 是出膛弹丸数
## （FloatingWeapon._volley_targets 逐发各咬一个目标），「3 段」会被读成三段连击。
static func card_feats(def: Dictionary) -> String:
	var out: Array[String] = []
	var pierce := int(def.get("pierce", 0))
	if pierce > 0:
		out.append("穿透%d" % pierce)
	var count := int(def.get("projectile_count", 1))
	if count > 1:
		out.append("%d发" % count)
	var bounce := int(def.get("bounce_count", 0))
	if bounce > 0:
		out.append("弹射%d" % bounce)
	if float(def.get("arc_scale", 1.0)) > 1.001:
		out.append("横扫")
	if out.size() > 2:
		out.resize(2)
	return "·".join(out)

## 环绕灵宝的分身具数：★1 一具、★2 一分为二、★3 一分为三（Player.sync_drones 按此生成）。
## 单法器总纸面伤害仍走 damage_for 的星级翻倍曲线，分身只均摊结算、抬贴身覆盖与占空比。
static func drone_orb_count(star: int) -> int:
	return clampi(star, 1, MAX_STAR)

static func damage_for(id: String, star: int) -> float:
	var def: Dictionary = DEFS.get(id, {})
	if def.is_empty():
		return 0.0
	return float(def.get("damage", 10.0)) * pow(STAR_DAMAGE_MULT, float(star - 1))

static func cooldown_for(id: String, star: int) -> float:
	var def: Dictionary = DEFS.get(id, {})
	if def.is_empty():
		return 1.0
	return float(def.get("cooldown", 1.0)) * pow(STAR_COOLDOWN_MULT, float(star - 1))

static func knockback_for(id: String, fallback: float = 180.0) -> float:
	var def: Dictionary = DEFS.get(id, {})
	if def.is_empty():
		return fallback
	return float(def.get("knockback", fallback))

static func sell_price(id: String, star: int) -> int:
	var def: Dictionary = DEFS.get(id, {})
	if def.is_empty():
		return 0
	var base := int(def.get("price", 10))
	return int(ceil(float(base) * SELL_RATIO * pow(STAR_SELL_MULT, float(star - 1))))

static func star_text(star: int) -> String:
	return "★".repeat(clampi(star, 1, MAX_STAR))

static func full_name(id: String, star: int) -> String:
	var def: Dictionary = DEFS.get(id, {})
	if def.is_empty():
		return "未知武器"
	return "%s %s" % [star_text(star), def.get("name", "?")]

static func tags_of(id: String) -> Array:
	return DEFS.get(id, {}).get("tags", [])

static func class_of(id: String) -> String:
	var t := tags_of(id)
	for tag in t:
		if tag in CLASSES:
			return tag
	return ""

static func element_of(id: String) -> String:
	var t := tags_of(id)
	for tag in t:
		if tag in ELEMENTS:
			return tag
	return ""

## 该法器的开火音 key（缺省回落到通用的 blade_shoot，保证老调用不会哑）
static func sfx_for(id: String) -> String:
	return String(DEFS.get(id, {}).get("sfx", "blade_shoot"))

## 该法器的「第二层」音 key：MELEE=命中材质声（只在真打中时播），BURST=落点爆发声。
static func sfx_impact_for(id: String) -> String:
	return String(DEFS.get(id, {}).get("sfx_impact", ""))

## 弹丸从 2026-10-08 起带有限转向追踪（BladeProjectile.HOMING_TURN_RATE）：
## 场上只剩一个敌人时，一次三发的法器每一发最终都归它 ⇒ 单体口径按发数求和才与运行时一致。
## 下面两个纯函数是给"档位体检"当尺子用的（判据见 tests/unit_runner.gd::_test_ranged_focus_dps），
## 口径：★star、不吃玩家属性/羁绊/暴击/危险度，只比较法器自身的设计强度。
const FOCUS_RANGED_MAX_TARGETS := 2   ## 单发最多结算这么几个敌人的远程法器 = 「点杀位」

## 单发（一次开火）最多能结算几个敌人。近战横扫 / 区域落雷 / 环绕接触天生打一片，按"群体"给档；
## 弹丸按 发数 ×（穿透 + 弹射）计，穿透与弹射都各自吃一个独立敌人。
static func targets_per_shot(id: String) -> int:
	var def: Dictionary = DEFS.get(id, {})
	if def.is_empty():
		return 0
	var behavior := int(def.get("behavior", Behavior.MELEE))
	if behavior == Behavior.PROJECTILE:
		var per_bullet := maxi(1, int(def.get("pierce", 1))) + maxi(0, int(def.get("bounce_count", 0)))
		return maxi(1, int(def.get("projectile_count", 1))) * per_bullet
	if behavior == Behavior.DRONE:
		return 3      ## 环绕接触：同时贴身的一般是两三尊
	if behavior == Behavior.TURRET:
		return 4      ## 机关炮台独立索敌
	return 6          ## 近战弧扫 / 落雷圆形：天生群体
## 「点杀位」远程法器：弹丸类里单发最多只结算 FOCUS_RANGED_MAX_TARGETS 个敌人的那些。
## 这一档必须在"啃硬目标"上赢过贴脸与环绕，否则就是纯下位（用户 2026-10-08 的火符投诉）。
static func is_focus_ranged(id: String) -> bool:
	var def: Dictionary = DEFS.get(id, {})
	return int(def.get("behavior", -1)) == Behavior.PROJECTILE \
		and targets_per_shot(id) <= FOCUS_RANGED_MAX_TARGETS

## 对一个孤立敌人的持续 DPS（不含玩家加成）。灼烧/剧毒按"单次施加的常驻量"折算：
## 冷却 < 异常时长 ⇒ 全程挂着（灼烧在 EnemyBase 里取 max 不叠层）；否则按占比折算。冰缓不加伤，不计。
## 2026-10-10 重标定：近战移除隐藏 ×1.35（面板即实伤），多发散射弹丸对单目标按最多 2 发命中折算。
static func sustained_single_dps(id: String, star: int = 1) -> float:
	var def: Dictionary = DEFS.get(id, {})
	if def.is_empty():
		return 0.0
	var dmg := damage_for(id, star)
	var cd := maxf(0.05, cooldown_for(id, star))
	if int(def.get("behavior", Behavior.MELEE)) == Behavior.TURRET:
		var fire_cd: float = maxf(0.1, float(def.get("turret_fire_cd", 0.75)))
		var t_dps: float = dmg / fire_cd
		if def.get("proc_burn", false):
			t_dps += dmg * float(def.get("burn_ratio", 0.4)) * minf(1.0, float(def.get("burn_dur", 2.5)) / fire_cd)
		return t_dps
	var per_hit: float = 1.0
	if int(def.get("behavior", Behavior.MELEE)) == Behavior.PROJECTILE:
		per_hit = float(mini(2, maxi(1, int(def.get("projectile_count", 1)))))
	var dps: float = dmg * per_hit / cd
	if def.get("proc_burn", false):
		dps += dmg * float(def.get("burn_ratio", 0.4)) * minf(1.0, float(def.get("burn_dur", 3.0)) / cd)
	if def.get("proc_poison", false):
		dps += dmg * float(def.get("poison_ratio", 0.3)) * minf(1.0, float(def.get("poison_dur", 2.5)) / cd)
	# 环绕接触天生带"占空比税"：纸面 DPS × 接触占空比 = 有效单体 DPS（实伤口径）。
	# ★2/★3 分身后多具同环扫掠，占空比随星抬升（★1 保持 0.75 实测基准，档带不漂移）。
	if int(def.get("behavior", Behavior.MELEE)) == Behavior.DRONE:
		dps *= GameBalance.spirit_contact_duty(star)
	return dps

## 该法器是否吃「元素伤害」属性加成：stat_scalings 里配了 elemental_damage 系数才算。
## 返回系数（0 = 不吃），供各界面挂角标与悟道加点提示共用。
static func elemental_scaling_coef(id: String) -> float:
	return float(get_def(id).get("stat_scalings", {}).get("elemental_damage", 0.0))

