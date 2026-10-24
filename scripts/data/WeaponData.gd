class_name WeaponData
extends RefCounted

## 武器静态数据库：所有武器的数值/行为/价格/五行/属性受益唯一定义处
## 星级：集齐 3 把同名同星，在回合间商店手动合成 +1 星，伤害 ×2.0/星，冷却 ×0.92/星，最高 ★3
## 双标签系统：器类（剑系/符箓/雷法/御灵/广域）+ 五行（锐金/青木/玄水/离火/厚土）
## 器类归属口径（2026-10-10 定，用户：「柳叶飞刀怎么是符箓啊？不应该是剑系吗」）：
##   剑系 = 金属锋刃器，近战白刃与远程飞射都算（剑/刀/针 ⇒ 庚金飞剑、柳叶飞刀、暴雨梨花针、玄冰飞针都在内）；
##   弹射（talisman，旧名符箓）= 弹丸机关巧器（符纸、透骨钉、手里剑），羁绊给弹丸穿透 + 远程伤害。
##   例外账：手里剑 2026-10-20 从剑系改判弹射（用户：「应该放进弹射吧」）——金属锋刃不 overrides
##   机制同源，连锁弹射的招牌武器该吃弹射羁绊的穿透收益。
## 归属唯一真话是各武器的 "tags"（"tag" 只是展示文案），器类签/图鉴/商店/羁绊结算全从 tags 取，改归属两处一起改。
## 弹丸类（PROJECTILE）另带 bullet / bullet_scale / bullet_spin 三个外观字段：打出去的东西按武器各自不同
## （火符掷火符、飞剑出飞剑、冰针出针），画布尺寸 × bullet_scale == 屏上像素；缺 bullet 时回退 blade.png。
## bullet_scale 那把尺子（2026-10-09，用户口径：「飞行物太大了，其他几个也挺大」）：
## 弹丸屏上长轴不许大过发射它的武器本体（本体 = 48×48 画布 × FloatingWeapon 的 0.55 ⇒ 26.4px）。
## 符箓是块面状贴图、细长兵器是 40px 长条，按 1.0 出图全都在本体的 1.5 倍 ⇒ 满屏飞招牌。
## bullet_spin 2026-10-09 起才真正生效：以前代码按穿透数反推朝向（pierce<=1 就转），
## 结果表里明明写了"不转"的玄冰飞针，打出去仍在原地打圈。
##
## 朝向与发射点（2026-10-09，用户口径：「飞剑发射时朝向不对，没朝敌人；不知道从哪里发射出来的」）：
## - "tip"：剑尖/器口在【贴图坐标系】里相对画布中心的位置，单位 = 画布像素（图标 48×48，
##   画布中心 (24,24) 即 Sprite2D 的轴心）。一个字段管两件事：
##   方向 = 这张图天生朝哪儿（代码按它补偿，贴图才真正指向目标）；长度 = 出膛点离本体的距离。
##   ◆ 这个数只能【量】不能【猜】：标到柄那头时代码照样自洽（补偿角与出膛点都跟着它走），
##   于是画面上变成"剑尖背对敌人、弹丸从剑柄冒出来"，判据抓不到 —— 庚金飞剑就栽过一次。
##   换素材后跑 `python3 tools/fit_weapon_icon.py <原稿> <产物> 48 48 [--rotate 角度]`，
##   把它打印的 tip 原样抄进来；哪头是尖要靠 tests/WeaponAimPreview 出的图看。
## - "upright": true = 宝灯/法牌/大印/灵藤这类没有锋刃方向的重器，本体保持世界竖直，不许随瞄准
##   转圈（旧写法会把印玺横过来对着人）。此时 tip 只取长度，发射点落在"朝目标那一侧的器口"。
## - 环绕类（DRONE）走 SunOrb，本体不旋转，不需要这两个字段。

## 攻击方式八种：近战=突进一挥（360° 圆判定）；横扫=蓄力大横扫（前方真扇形判定，
## 2026-10-13 从 MELEE 拆出——原先横扫只是近战的一个 arc_scale 乘区，手感与近战零差异）；
## 光束=持续激光（2026-10-13 新增：锁定即照出，射线截断长度即判定长度，按 tick 结算）；
## 喷吐=锥形火焰（2026-10-13 新增：器口前方锥形持续灼烧，tick 折算保证纸面 DPS 即实伤）。
enum Behavior { MELEE, PROJECTILE, BURST, DRONE, TURRET, SWEEP, BEAM, CONE }

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
				# 2026-10-14 风险溢价重排：贴脸风险高于远程，近战单体档 28~36 必须压过点杀远程 22~28
				"damage": 34.0, "cooldown": 1.05, "range": 105.0,
				"knockback": 300.0,
				"price": 25, "icon": "res://assets/art/weapon_sword.png",
				# 2026-10-10 素材返工（旧图为像素风白剑，与新画风脱节）：换空洞冷冽矢量风青云剑，
				# tip 由 tools/fit_weapon_icon.py 实测打印后原样抄入。
				"tip": Vector2(22, -20), "shape": "sword",
				"desc": "近身挥砍，受近战伤害与暴击率加成", "tag": "近战·剑系·金",
				"tags": ["sword", "metal"],
				"stat_scalings": {"melee_damage": 1.0, "crit_rate": 40.0},
			},
					"gengjin_feijian": {
						"name": "飞剑", "behavior": Behavior.PROJECTILE,
						"sfx": "blade_shoot",
						"damage": 24.5, "cooldown": 0.92, "range": 275.0,
						"knockback": 185.0,
						"price": 35, "icon": "res://assets/art/weapon_gold_sword.png",
						# 2026-10-09 素材返工（旧图是弯的、且旧标定 (20,-14) 落在剑首那头上）：
						# 新图为笔直双刃剑斜铺，tip 由 tools/fit_weapon_icon.py 实测打印后原样抄入。
						"tip": Vector2(22, -16), "shape": "sword",
						"desc": "自动追击锁定敌人，受远程伤害与暴击伤害加成", "tag": "远程·剑系·金",
						"bullet": "res://assets/art/bullet_gold_sword.png", "bullet_scale": 0.6, "bullet_spin": false,
						"pierce": 1,
						"tags": ["sword", "metal"],
						"stat_scalings": {"ranged_damage": 1.0, "crit_mult_bonus": 30.0},
					},
				"liuye_feidao": {
					"name": "飞刀", "behavior": Behavior.PROJECTILE,
					"sfx": "metal_dart",
					"damage": 12.0, "cooldown": 1.15, "range": 265.0,
					"knockback": 110.0,
					"price": 35, "icon": "res://assets/art/weapon_dagger.png",
					"tip": Vector2(21, -24), "shape": "dagger",
					"desc": "扇形射出3把飞刀各锁1敌，受远程伤害与暴击率加成", "tag": "远程·剑系·金",
					"bullet": "res://assets/art/bullet_leaf_dagger.png", "bullet_scale": 0.6, "bullet_spin": false,
					"pierce": 1, "projectile_count": 3, "spread_angle": 0.20,
					"tags": ["sword", "metal"],
					"stat_scalings": {"ranged_damage": 0.8, "crit_rate": 30.0},
				},
						"baoyu_liuhuazhen": {
							"name": "暴雨针", "behavior": Behavior.PROJECTILE,
							"sfx": "metal_dart",
							# 机制差异化重构：暴雨梨花式瞬间倾泻细针，与飞刀割草拉开差异
							# 2026-10-14 弹丸数瘦身：8→5 发（群体雪球收敛，单体伤害不变）
							"damage": 13.0, "cooldown": 1.25, "range": 255.0,
							"knockback": 85.0,
							"price": 36, "icon": "res://assets/art/weapon_needle_pouch.png",
							"tip": Vector2(22, -6), "shape": "needles",
							"desc": "倾泻5发密如暴雨的追踪细针，受远程伤害与暴击率加成", "tag": "远程·剑系·金",
						"bullet": "res://assets/art/bullet_silver_needle.png", "bullet_scale": 0.50, "bullet_spin": false,
						"pierce": 1, "projectile_count": 5, "spread_angle": 0.42,
						"tags": ["sword", "metal"],
						"stat_scalings": {"ranged_damage": 0.8, "crit_rate": 30.0},
					},
					"shoulijian": {
						"name": "手里剑", "behavior": Behavior.PROJECTILE,
						"sfx": "metal_dart",
						# 弹射流招牌：单发旋刃连锁弹射3次（1+3 共咬 4 敌），与飞剑穿透点杀、
						# 飞刀扇形铺面拉开差异；裸伤略高于带毒弹射件（毒符/弹弓有剧毒补尾）
						"damage": 20.0, "cooldown": 1.0, "range": 270.0,
						"knockback": 120.0,
						"price": 35, "icon": "res://assets/art/weapon_shoulijian.png",
						# 四芒星径向对称：tip 只取出膛距离（外刃半径），方向补偿对它无意义
						"tip": Vector2(20, 0), "shape": "shuriken",
						"desc": "掷出旋转手里剑连锁弹射3次，受远程伤害与暴击率加成", "tag": "远程·弹射·金",
						"bullet": "res://assets/art/bullet_shuriken.png", "bullet_scale": 0.6, "bullet_spin": true,
						"pierce": 1, "bounce_count": 3,
						# 2026-10-20 从 sword 改判 talisman（用户口径：「应该放进弹射吧」）：
						# 旋刃连锁弹射本就是弹射流招牌（同日注释），弹射羁绊给穿透+远程伤害与它机制同源
						"tags": ["talisman", "metal"],
						"stat_scalings": {"ranged_damage": 0.8, "crit_rate": 35.0},
					},

				# ==================== 木系 (Wood: 生机·回复·剧毒) ====================
					"qingmu_tengbian": {
						"name": "藤鞭", "behavior": Behavior.SWEEP,
						"sfx": "whoosh_heavy", "sfx_impact": "impact_crack",
						# 2026-10-14 风险溢价重排：横扫贴脸档 26~34（2026-10-22 攻速分化：轻灵软鞭 1.15s 疾扫）
						"damage": 23.0, "cooldown": 1.15, "range": 119.0,
						"knockback": 340.0,
					"price": 28, "icon": "res://assets/art/weapon_vine_whip.png",
					"tip": Vector2(22, 0), "shape": "whip", "upright": true,
					"desc": "横扫前方大片敌群并附带中毒，受近战与元素伤害加成", "tag": "近战·横扫·木",
					"arc_scale": 1.35, "proc_poison": true, "poison_ratio": 0.35, "poison_dur": 3.0,
					"tags": ["wide", "wood"],
					"stat_scalings": {"melee_damage": 1.0, "elemental_damage": 0.6, "hp_regen": 4.5},
				},
				"wanmu_lingfu": {
					"name": "毒符", "behavior": Behavior.PROJECTILE,
					"sfx": "talisman_throw",
					"damage": 18.0, "cooldown": 1.05, "range": 250.0,
					"knockback": 140.0,
					"price": 32, "icon": "res://assets/art/weapon_wood_talisman.png",
					# 竖直符纸无锋刃轴：upright 竖直悬浮施法（2026-10-18 随新图统一姿态）
					"tip": Vector2(22, 0), "shape": "talisman", "upright": true,
					"desc": "追踪弹射并叠毒，受远程与元素伤害加成", "tag": "远程·弹射·木",
					"bullet": "res://assets/art/bullet_wood_talisman.png", "bullet_scale": 0.6, "bullet_spin": true,
					"pierce": 1, "bounce_count": 2, "proc_poison": true, "poison_ratio": 0.30, "poison_dur": 2.5,
					"tags": ["talisman", "wood"],
					"stat_scalings": {"ranged_damage": 0.8, "elemental_damage": 0.8, "hp_regen": 3.5},
				},
					"lingdie": {
						"name": "护蝶", "behavior": Behavior.DRONE,
						"sfx": "drone_flutter",
						"damage": 23.0, "cooldown": 0.48, "range": 200.0,
						"knockback": 160.0,
						"price": 40, "icon": "res://assets/art/sun_orb.png",
						"desc": "环绕周身触碰即伤，受召唤伤害与吸血加成", "tag": "召唤·环绕·木",
						"tags": ["spirit", "wood"],
						"stat_scalings": {"engineering_damage": 1.0, "lifesteal": 100.0},
					},
				"lianhuan_lingdan": {
					"name": "弹弓", "behavior": Behavior.PROJECTILE,
					"sfx": "impact_crack",
					"damage": 18.0, "cooldown": 0.95, "range": 250.0,
					"knockback": 120.0,
					"price": 34, "icon": "res://assets/art/weapon_sling.png",
					"tip": Vector2(20, -18), "shape": "sling",
					"desc": "弹丸连锁弹射并附带中毒，受远程与元素伤害加成", "tag": "远程·横扫·木",
					"bullet": "res://assets/art/bullet_spirit_pellet.png", "bullet_scale": 0.55, "bullet_spin": true,
					"pierce": 1, "bounce_count": 3,
					"proc_poison": true, "poison_ratio": 0.25, "poison_dur": 2.5,
					"tags": ["wide", "wood"],
					"stat_scalings": {"ranged_damage": 0.8, "elemental_damage": 0.6, "hp_regen": 3.0},
				},

				# ==================== 水系 (Water: 极寒·缓速·迅捷) ====================
							"bajiao_fan": {
								"name": "风扇", "behavior": Behavior.SWEEP,
								"sfx": "fan_gust", "sfx_impact": "impact_crack",
								# 2026-10-14 风险溢价重排：横扫贴脸档 26~34（2026-10-22 攻速分化：风刃轻挥 1.30s）
								"damage": 35.0, "cooldown": 1.30, "range": 119.0,
								"knockback": 520.0,
							"price": 26, "icon": "res://assets/art/weapon_fan.png",
							"tip": Vector2(0, -15), "shape": "fan",
							"desc": "横扫扇出寒冰风刃减速敌群，受近战伤害与移速加成", "tag": "近战·横扫·水",
						"arc_scale": 1.35, "proc_chill": 0.35, "chill_dur": 2.5,
						"tags": ["wide", "water"],
						"stat_scalings": {"melee_damage": 1.0, "move_speed_bonus": 25.0},
					},
				"xuanbing_feizhen": {
					"name": "冰针", "behavior": Behavior.PROJECTILE,
					"sfx": "metal_dart",
					"damage": 14.0, "cooldown": 1.0, "range": 265.0,
				"knockback": 95.0,
				"price": 30, "icon": "res://assets/art/weapon_ice_needle.png",
				"tip": Vector2(-18, 12), "shape": "needles",
				"desc": "射出2枚冰针追踪并减速，受远程伤害与移速加成", "tag": "远程·剑系·水",
				"bullet": "res://assets/art/bullet_ice_needle.png", "bullet_scale": 0.6, "bullet_spin": false,
				"pierce": 1, "projectile_count": 2, "spread_angle": 0.18, "proc_chill": 0.35, "chill_dur": 2.0,
				"tags": ["sword", "water"],
				"stat_scalings": {"ranged_damage": 0.8, "move_speed_bonus": 28.0},
			},
				"hanquan_yulian": {
					"name": "冰莲", "behavior": Behavior.DRONE,
					"sfx": "drone_chime",
					"damage": 24.0, "cooldown": 0.50, "range": 200.0,
					"knockback": 190.0,
					"price": 42, "icon": "res://assets/art/weapon_ice_lotus.png",
					"desc": "环绕护体触碰即减速，受召唤伤害与攻击间隔加成", "tag": "召唤·环绕·水",
					"proc_chill": 0.40, "chill_dur": 2.5,
					"tags": ["spirit", "water"],
					"stat_scalings": {"engineering_damage": 1.0, "cdr_bonus": 30.0},
				},
					"bihai_chaoyindi": {
						"name": "音笛", "behavior": Behavior.BURST,
						"sfx": "flute_wave", "sfx_impact": "flute_wave",
						# 2026-10-22 攻速分化：笛音回旋连绵 1.15s 轻快回响
						"damage": 25.0, "cooldown": 1.15, "range": 255.0,
						"knockback": 320.0,
					"price": 44, "icon": "res://assets/art/weapon_flute.png",
					"tip": Vector2(20, 0), "shape": "flute", "upright": true,
					"desc": "音波震荡大范围强减速，受元素伤害与移速加成", "tag": "元素·雷法·水",
					"burst_radius": 88.0, "burst_tint": Color(0.35, 0.75, 1.0),
					"burst_kind": "sonic",
					"proc_chill": 0.50, "chill_dur": 2.8,
					"tags": ["thunder", "water"],
					"stat_scalings": {"elemental_damage": 1.0, "move_speed_bonus": 30.0, "cdr_bonus": 25.0},
				},

				# ==================== 火系 (Fire: 烈焰·灼烧·爆裂) ====================
				"huoyan_fu": {
					"name": "火符", "behavior": Behavior.PROJECTILE,
					"sfx": "talisman_throw",
					"damage": 10.0, "cooldown": 0.88, "range": 250.0,
					"knockback": 155.0,
					"price": 30, "icon": "res://assets/art/weapon_staff.png",
					# 斜挂黄纸无锋刃轴：upright 竖直悬浮施法（2026-10-18 修躺倒翻面）
					"tip": Vector2(20, 0), "shape": "talisman", "upright": true,
					"desc": "掷出2张燃烧符追踪引燃，受元素与远程伤害加成", "tag": "元素·弹射·火",
					"bullet": "res://assets/art/bullet_fire_talisman.png", "bullet_scale": 0.5, "bullet_spin": true,
					"pierce": 1, "projectile_count": 2, "spread_angle": 0.14,
					"proc_burn": true, "burn_ratio": 0.40, "burn_dur": 3.0,
					"tags": ["talisman", "fire"],
					"stat_scalings": {"elemental_damage": 1.0, "ranged_damage": 0.6, "damage_bonus": 20.0},
				},
					"chiyan_dao": {
						"name": "烈焰刀", "behavior": Behavior.MELEE,
						"sfx": "whoosh_light", "sfx_impact": "impact_blade",
						"damage": 27.0, "cooldown": 1.15, "range": 124.0,
						"knockback": 380.0,
						"price": 36, "icon": "res://assets/art/weapon_fire_blade.png",
						"tip": Vector2(22, -14), "shape": "saber",
						"desc": "大范围火焰重刀引燃敌人，受近战与元素伤害加成", "tag": "近战·剑系·火",
					"arc_scale": 1.25, "proc_burn": true, "burn_ratio": 0.40, "burn_dur": 3.0,
					"tags": ["sword", "fire"],
					"stat_scalings": {"melee_damage": 1.0, "elemental_damage": 0.8, "range_bonus": 25.0},
				},
						"fentian_baodeng": {
							"name": "天灯", "behavior": Behavior.BURST,
							"sfx": "whoosh_heavy", "sfx_impact": "flame_jet",
							# 2026-10-22 攻速分化：宝灯祭空 1.65s 沉稳引漫天火雨
							"damage": 22.0, "cooldown": 1.65, "range": 265.0,
							"knockback": 200.0,
						"price": 40, "icon": "res://assets/art/weapon_fire_lantern.png",
						"tip": Vector2(22, 0), "shape": "lantern", "upright": true,
						"desc": "降下火雨轰击区域并点燃火海，受元素伤害加成", "tag": "元素·雷法·火",
						"burst_radius": 85.0, "burst_tint": Color(1.0, 0.52, 0.18),
						"burst_kind": "fire_rain",
						"proc_burn": true, "burn_ratio": 0.40, "burn_dur": 3.0,
						"tags": ["thunder", "fire"],
						"stat_scalings": {"elemental_damage": 1.5, "damage_bonus": 25.0},
					},
					"sanmei_huohu": {
						"name": "火葫芦", "behavior": Behavior.CONE,
						"sfx": "flame_jet",
						"damage": 9.0, "cooldown": 0.42, "range": 190.0,
						"knockback": 95.0,
						"price": 36, "icon": "res://assets/art/weapon_fire_calabash.png",
						"tip": Vector2(22, -18), "shape": "calabash",
						"desc": "持续喷吐火焰点燃前方敌群，受元素与远程伤害加成", "tag": "元素·喷吐·火",
						"proc_burn": true, "burn_ratio": 0.40, "burn_dur": 2.5,
						"tags": ["wide", "fire"],
						"stat_scalings": {"elemental_damage": 1.2, "ranged_damage": 0.6, "damage_bonus": 20.0},
					},

					# ==================== 土系 (Earth: 厚重·护甲·震退) ====================
						"wulei_paizi": {
							"name": "雷牌", "behavior": Behavior.BURST,
							"sfx": "whoosh_light", "sfx_impact": "thunder_strike",
							# 2026-10-22 攻速分化：五雷符牌 1.60s 庄严召雷
							"damage": 37.0, "cooldown": 1.60, "range": 260.0,
							"knockback": 280.0,
						"price": 40, "icon": "res://assets/art/weapon_thunder.png",
						"tip": Vector2(22, 0), "shape": "tablet", "upright": true,
						"desc": "落雷轰击区域大范围击退，受元素伤害与护甲加成", "tag": "元素·雷法·土",
						"burst_radius": 80.0, "burst_tint": Color(0.62, 0.86, 1.0),
						"burst_kind": "earth",  # 土系雷法走地裂扬尘：与金雷锥/金霄雷令的雷柱拉开形态
						"tags": ["thunder", "earth"],
						"stat_scalings": {"elemental_damage": 1.2, "armor": 2.0},
					},
						"fantian_yin": {
							"name": "巨印", "behavior": Behavior.BURST,
							"sfx": "whoosh_heavy", "sfx_impact": "impact_blunt",
							# 2026-10-22 攻速分化：番天巨印 1.85s 极沉轰砸，地动山摇
							"damage": 45.0, "cooldown": 1.85, "range": 250.0,
							"knockback": 360.0,
						"price": 42, "icon": "res://assets/art/weapon_earth_seal.png",
						"tip": Vector2(20, 0), "shape": "seal", "upright": true,
						"desc": "巨印从天砸下，受元素伤害与护甲加成", "tag": "元素·横扫·土",
						"burst_radius": 95.0, "burst_tint": Color(0.88, 0.74, 0.46),
						"burst_kind": "seal",
						"tags": ["wide", "earth"],
						"stat_scalings": {"elemental_damage": 1.0, "armor": 3.5},
					},
							"hunyuan_zhong": {
								"name": "古钟", "behavior": Behavior.DRONE,
								"sfx": "orb_hit",
								# 2026-10-22 攻速分化：混元古钟沉稳厚重 0.65s 撼地撞击
								"damage": 31.0, "cooldown": 0.65, "range": 205.0,
								"knockback": 340.0,
							"price": 44, "icon": "res://assets/art/weapon_earth_bell.png",
							"desc": "环绕周身撞击击退敌群，受召唤伤害与最大生命加成", "tag": "召唤·环绕·土",
							"tags": ["spirit", "earth"],
							"stat_scalings": {"engineering_damage": 1.0, "max_hp_bonus": 0.12},
						},
						"xuanwu_lingdun": {
							"name": "重盾", "behavior": Behavior.MELEE,
							"sfx": "whoosh_heavy", "sfx_impact": "impact_blunt",
							# 机制差异化重构：超宽半圆护壁推进（arc 1.55），480 顶级强力击飞，与重剑/锏区分
							# 2026-10-14 风险溢价：防御定位但 DPS 也须入近战档（28~36）
							"damage": 36.0, "cooldown": 1.25, "range": 146.0,
							"knockback": 480.0,
							"price": 38, "icon": "res://assets/art/weapon_earth_shield.png",
							"tip": Vector2(22, -12), "shape": "shield",
								"desc": "厚重大盾超宽弧面横推强力击飞来敌，受近战伤害、护甲与生命加成", "tag": "近战·剑系·土",
						"arc_scale": 1.55,
						"tags": ["sword", "earth"],
						"stat_scalings": {"melee_damage": 0.8, "armor": 3.0, "max_hp_bonus": 0.15},
					},

				# ==================== 2026-10-10 新增 15 把 ====================
				# 目的有二：
				#  1) 补齐 器类×五行 5×5 格子的 9 个空格——符箓(原仅2把)/雷法(3)/御灵(3)凑不齐羁绊 4/6 档；
				#  2) 按土豆兄弟属性加成模式补流派专武（吸血/收益/护甲加成），配合新道具撑起各流派。
				# tip 由 tools/fit_weapon_icon.py 实测回填。

				# ---- 补格子 9 把 ----
					"jinzhen_fu": {
						"name": "金针符", "behavior": Behavior.PROJECTILE,
						"sfx": "metal_dart",
						"damage": 9.0, "cooldown": 0.65, "range": 250.0,
						"knockback": 80.0,
						"price": 34, "icon": "res://assets/art/weapon_jinzhen_fu.png",
						# 竖直符纸无锋刃轴：upright 竖直悬浮施法（2026-10-18 随新图统一姿态）
						"tip": Vector2(22, 0), "shape": "talisman", "upright": true,
						"desc": "连射2枚金针高速追击，受远程伤害与暴击率加成", "tag": "远程·弹射·金",
						"bullet": "res://assets/art/bullet_gold_needle.png", "bullet_scale": 0.55, "bullet_spin": false,
						"pierce": 1, "projectile_count": 2, "spread_angle": 0.10,
						"tags": ["talisman", "metal"],
						"stat_scalings": {"ranged_damage": 0.85, "crit_rate": 35.0},
					},
				"xuanbing_fu": {
					"name": "玄冰符", "behavior": Behavior.PROJECTILE,
					"sfx": "talisman_throw",
					"damage": 20.0, "cooldown": 1.0, "range": 250.0,
					"knockback": 130.0,
					"price": 32, "icon": "res://assets/art/weapon_xuanbing_fu.png",
					# 横躺卷轴是自然姿态：upright 保持不转（2026-10-18 修翻面跳动）
					"tip": Vector2(22, 0), "shape": "talisman", "upright": true,
					"desc": "冰符弹射2次并冰缓敌人，受远程伤害与移速加成", "tag": "远程·弹射·水",
					"bullet": "res://assets/art/bullet_ice_talisman.png", "bullet_scale": 0.6, "bullet_spin": true,
					"pierce": 1, "bounce_count": 2, "proc_chill": 0.35, "chill_dur": 2.0,
					"tags": ["talisman", "water"],
					"stat_scalings": {"ranged_damage": 0.8, "move_speed_bonus": 28.0},
				},
				"zhenshan_fu": {
					"name": "镇山符", "behavior": Behavior.PROJECTILE,
					"sfx": "talisman_throw",
					"damage": 38.0, "cooldown": 1.5, "range": 255.0,
					"knockback": 380.0,
					"price": 38, "icon": "res://assets/art/weapon_zhenshan_fu.png",
					"tip": Vector2(22, 0), "shape": "talisman",
					"desc": "重符缓出沉重击退，受远程伤害与护甲加成", "tag": "远程·弹射·土",
					"bullet": "res://assets/art/bullet_earth_talisman.png", "bullet_scale": 0.6, "bullet_spin": true,
					"pierce": 1,
					"tags": ["talisman", "earth"],
					"stat_scalings": {"ranged_damage": 0.8, "armor": 2.5},
				},
						"jinjiao_jian": {
							"name": "金蛟剪", "behavior": Behavior.SWEEP,
							"sfx": "whoosh_heavy", "sfx_impact": "impact_blade",
							# 2026-10-14 风险溢价重排：横扫贴脸档 26~34（2026-10-22 攻速分化：巨剪开合 1.50s 重击）
							"damage": 41.0, "cooldown": 1.50, "range": 128.0,
							"knockback": 390.0,
						"price": 38, "icon": "res://assets/art/weapon_jinjiao_jian.png",
						"tip": Vector2(22, 0), "shape": "shears",
						"desc": "横扫金蛟大剪剪开敌阵，受近战伤害与暴击率加成", "tag": "近战·横扫·金",
						"arc_scale": 1.45,
						"tags": ["wide", "metal"],
						"stat_scalings": {"melee_damage": 1.0, "crit_rate": 35.0},
					},
					"qingteng_jian": {
						"name": "青藤剑", "behavior": Behavior.MELEE,
						"sfx": "whoosh_light", "sfx_impact": "impact_crack",
						"damage": 24.0, "cooldown": 1.0, "range": 105.0,
						"knockback": 300.0,
						"price": 30, "icon": "res://assets/art/weapon_qingteng_jian.png",
					"tip": Vector2(22, -12), "shape": "sword",
					"desc": "青藤缠绕之剑命中叠毒，受近战伤害与吸血加成", "tag": "近战·剑系·木",
					"proc_poison": true, "poison_ratio": 0.30, "poison_dur": 2.5,
					"tags": ["sword", "wood"],
					"stat_scalings": {"melee_damage": 1.0, "lifesteal": 90.0},
				},
				"jinlei_zhui": {
					"name": "金雷锥", "behavior": Behavior.BURST,
					"sfx": "whoosh_light", "sfx_impact": "thunder_strike",
					# 2026-10-14 风险溢价重排：远程单点归位点杀远程档 22~28（38→37）
					"damage": 37.0, "cooldown": 1.35, "range": 265.0,
					"knockback": 220.0,
					"price": 46, "icon": "res://assets/art/weapon_jinlei_zhui.png",
					"tip": Vector2(22, 8), "shape": "awl", "upright": true,
					"desc": "金雷贯顶单点重击，受元素伤害与暴击率加成", "tag": "元素·雷法·金",
					"burst_radius": 75.0, "burst_tint": Color(1.0, 0.85, 0.4),
					"tags": ["thunder", "metal"],
					"stat_scalings": {"elemental_damage": 1.2, "crit_rate": 30.0},
				},
					"chunlei_gu": {
						"name": "春雷鼓", "behavior": Behavior.BURST,
						"sfx": "drum_boom", "sfx_impact": "drum_boom",
						# 2026-10-22 攻速分化：春雷阵阵鼓点 1.25s 连绵回响
						"damage": 22.0, "cooldown": 1.25, "range": 250.0,
						"knockback": 200.0,
					"price": 44, "icon": "res://assets/art/weapon_chunlei_gu.png",
					"tip": Vector2(22, 0), "shape": "drum", "upright": true,
					"desc": "春雷滚滚落点范围叠毒，受元素伤害与生命回复加成", "tag": "元素·雷法·木",
					"burst_radius": 90.0, "burst_tint": Color(0.5, 0.85, 0.5),
					"burst_kind": "drum",
					"proc_poison": true, "poison_ratio": 0.35, "poison_dur": 3.0,
					"tags": ["thunder", "wood"],
					"stat_scalings": {"elemental_damage": 1.0, "hp_regen": 4.0},
				},
						"haojin_lun": {
							"name": "昊金轮", "behavior": Behavior.DRONE,
							"sfx": "orb_hit",
							# 2026-10-22 攻速分化：金轮疾转切割 0.40s
							"damage": 20.0, "cooldown": 0.40, "range": 195.0,
							"knockback": 200.0,
						"price": 42, "icon": "res://assets/art/weapon_haojin_lun.png",
						"desc": "金轮环绕切割，受召唤伤害与暴击率加成", "tag": "召唤·环绕·金",
						"tags": ["spirit", "metal"],
						"stat_scalings": {"engineering_damage": 1.0, "crit_rate": 30.0},
					},
						"lihuo_ya": {
							"name": "离火鸦", "behavior": Behavior.DRONE,
							"sfx": "drone_flutter",
							# 2026-10-22 攻速分化：火鸦展翅蓄焰 0.55s 盘旋扑咬
							"damage": 21.0, "cooldown": 0.55, "range": 195.0,
							"knockback": 150.0,
						"price": 42, "icon": "res://assets/art/weapon_lihuo_ya.png",
						"desc": "火鸦环绕扑击引燃敌人，受召唤与元素伤害加成", "tag": "召唤·环绕·火",
						"proc_burn": true, "burn_ratio": 0.40, "burn_dur": 2.5,
						"tags": ["spirit", "fire"],
						"stat_scalings": {"engineering_damage": 1.0, "elemental_damage": 0.5},
					},

				# ---- 流派特色 6 把 ----
				"xueyin_dao": {
					"name": "血饮狂刀", "behavior": Behavior.MELEE,
					"sfx": "whoosh_light", "sfx_impact": "impact_blade",
					"damage": 16.0, "cooldown": 0.65, "range": 105.0,
					"knockback": 280.0,
					"price": 36, "icon": "res://assets/art/weapon_xueyin_dao.png",
					"tip": Vector2(-22, 20), "shape": "saber",
					"desc": "狂刀快斩痛饮敌血，受近战伤害与吸血加成", "tag": "近战·剑系·火",
					"proc_burn": true, "burn_ratio": 0.25, "burn_dur": 2.0,
					"tags": ["sword", "fire"],
					"stat_scalings": {"melee_damage": 1.0, "lifesteal": 90.0},
				},
						"jubao_chi": {
							"name": "聚宝金尺", "behavior": Behavior.SWEEP,
							"sfx": "whoosh_heavy", "sfx_impact": "impact_blunt",
							# 2026-10-14 风险溢价重排：横扫贴脸档 26~34（2026-10-22 攻速分化：标准量天尺 1.40s）
							"damage": 37.0, "cooldown": 1.40, "range": 114.0,
							"knockback": 340.0,
						"price": 30, "icon": "res://assets/art/weapon_jubao_chi.png",
						"tip": Vector2(22, -10), "shape": "ruler",
						"desc": "横扫财气金尺越旺打得越狠，受近战伤害与收益加成", "tag": "近战·横扫·金",
						"arc_scale": 1.3,
						"tags": ["wide", "metal"],
						"stat_scalings": {"melee_damage": 0.8, "harvest": 1.2},
					},
						"tougu_ding": {
							"name": "透骨钉", "behavior": Behavior.PROJECTILE,
							"sfx": "metal_dart",
							"damage": 15.0, "cooldown": 0.9, "range": 275.0,
							"knockback": 100.0,
							"price": 34, "icon": "res://assets/art/weapon_tougu_ding.png",
							"tip": Vector2(22, -12), "shape": "nail",
							"desc": "透骨钉射出并叠毒，受远程与元素伤害加成", "tag": "远程·弹射·木",
						"bullet": "res://assets/art/bullet_bone_spike.png", "bullet_scale": 0.55, "bullet_spin": false,
						"pierce": 1, "proc_poison": true, "poison_ratio": 0.30, "poison_dur": 2.5,
						"tags": ["talisman", "wood"],
						"stat_scalings": {"ranged_damage": 0.8, "elemental_damage": 0.6},
					},
						"benlang_chui": {
							"name": "崩浪锤", "behavior": Behavior.SWEEP,
							"sfx": "whoosh_heavy", "sfx_impact": "impact_blunt",
							# 2026-10-14 风险溢价重排：横扫贴脸档 26~34（2026-10-22 攻速分化：千钧重锤 1.75s 沉重破阵）
							"damage": 47.0, "cooldown": 1.75, "range": 119.0,
							"knockback": 680.0,
						"price": 34, "icon": "res://assets/art/weapon_benlang_chui.png",
						"tip": Vector2(22, 14), "shape": "hammer", "upright": true,
						"desc": "横扫崩浪重锤击飞敌群并冰缓，受近战伤害与移速加成", "tag": "近战·横扫·水",
						"arc_scale": 1.35, "proc_chill": 0.40, "chill_dur": 2.5,
						"tags": ["wide", "water"],
						"stat_scalings": {"melee_damage": 1.0, "move_speed_bonus": 25.0},
					},
							"liuling_jian": {
								"name": "六棱锏", "behavior": Behavior.MELEE,
								"sfx": "whoosh_heavy", "sfx_impact": "impact_blunt",
								# 机制差异化重构：缩短冷却至 0.85s 疾速破阵砸击，吃更高护甲加成，专攻重击破防
								"damage": 24.0, "cooldown": 0.85, "range": 105.0,
								"knockback": 340.0,
								"price": 36, "icon": "res://assets/art/weapon_liuling_jian.png",
								"tip": Vector2(22, -8), "shape": "mace", "upright": true,
							"desc": "六棱重锏疾速重砸破阵制敌，受近战伤害与极高护甲加成", "tag": "近战·剑系·土",
						"tags": ["sword", "earth"],
						"stat_scalings": {"melee_damage": 1.0, "armor": 3.5},
					},
							"xuanwu_pei": {
								"name": "玄武佩", "behavior": Behavior.DRONE,
								"sfx": "drone_chime",
								# 2026-10-22 攻速分化：玄武重佩镇御万方 0.75s 沉重震击
								"damage": 35.0, "cooldown": 0.75, "range": 200.0,
								"knockback": 420.0,
							"price": 44, "icon": "res://assets/art/weapon_xuanwu_pei.png",
							"desc": "玄武玉佩环绕震退来敌，受召唤伤害与护甲加成", "tag": "召唤·环绕·土",
							"tags": ["spirit", "earth"],
							"stat_scalings": {"engineering_damage": 1.0, "armor": 2.5, "max_hp_bonus": 0.10},
						},

				# ---- 机关支路 3 把 ----
					"jiguan_nu": {
						"name": "机关弩", "behavior": Behavior.TURRET,
						"sfx": "metal_dart",
						"damage": 18.0, "cooldown": 3.5, "range": 270.0,
						"turret_fire_cd": 0.75, "turret_lifetime": 12.0, "turret_cap": 2,
						"knockback": 120.0,
						"price": 38, "icon": "res://assets/art/weapon_jiguan_nu.png",
						"tip": Vector2(22, -20), "turret_shape": "crossbow", "upright": true,
						"desc": "布设自动索敌的机关弩台，受机关伤害与暴击率加成", "tag": "机关·金",
						"bullet": "res://assets/art/bullet_gold_needle.png", "bullet_scale": 0.55, "bullet_spin": false,
						"pierce": 1,
						"tags": ["contraption", "metal"],
						"stat_scalings": {"contraption_damage": 1.0, "crit_rate": 25.0},
					},
					"jianzhen_pan": {
						"name": "剑阵盘", "behavior": Behavior.TURRET,
						# 疾射飞剑 ⇒ 金属抛体离手族；whoosh_light 是近战前摇的铺垫层，当开火音发虚
						"sfx": "blade_shoot",
						"damage": 15.0, "cooldown": 4.0, "range": 250.0,
						"turret_fire_cd": 0.60, "turret_lifetime": 12.0, "turret_cap": 2,
						"knockback": 140.0,
						"price": 42, "icon": "res://assets/art/weapon_jianzhen_pan.png",
						"tip": Vector2(22, 0), "turret_shape": "array_disc", "upright": true,
						"desc": "布设御剑阵盘疾射飞剑，受机关与近战伤害加成", "tag": "机关·剑系·金",
						"bullet": "res://assets/art/bullet_gold_sword.png", "bullet_scale": 0.55, "bullet_spin": false,
						"pierce": 1,
						"tags": ["contraption", "sword", "metal"],
						"stat_scalings": {"contraption_damage": 1.0, "melee_damage": 0.5},
					},
					"penhuo_jiguanshou": {
						"name": "喷火兽", "behavior": Behavior.TURRET,
						"sfx": "flame_jet",
						"damage": 11.0, "cooldown": 4.2, "range": 195.0,
						"turret_fire_cd": 0.42, "turret_lifetime": 10.0, "turret_cap": 2,
						"knockback": 100.0,
						"price": 40, "icon": "res://assets/art/weapon_penhuo_jiguanshou.png",
						"tip": Vector2(22, -10), "turret_shape": "beast", "upright": true,
						"desc": "布设喷火机关兽持续灼烧敌群，受机关与元素伤害加成", "tag": "机关·火",
						"bullet": "res://assets/art/bullet_fire_flame.png", "bullet_scale": 0.50, "bullet_spin": true,
						"pierce": 1, "proc_burn": true, "burn_ratio": 0.40, "burn_dur": 2.5,
						"tags": ["contraption", "fire"],
						"stat_scalings": {"contraption_damage": 1.0, "elemental_damage": 0.6},
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
							# 机制差异化重构：双柄飞剑交错齐射（2发各引燃），与单柄飞剑单点拉开手感
							"damage": 10.5, "cooldown": 0.95, "range": 275.0,
							"knockback": 150.0,
							"price": 38, "icon": "res://assets/art/weapon_liuhuo_feijian.png",
							"tip": Vector2(20, 2), "shape": "sword",
							"desc": "双柄炽炎飞剑交错射出各引燃敌人，受元素与远程伤害加成", "tag": "元素·剑系·火",
							"bullet": "res://assets/art/bullet_fire_sword.png", "bullet_scale": 0.6, "bullet_spin": false,
							"pierce": 1, "projectile_count": 2, "spread_angle": 0.14,
							"proc_burn": true, "burn_ratio": 0.35, "burn_dur": 3.0,
							"tags": ["sword", "fire"],
							"stat_scalings": {"elemental_damage": 1.0, "ranged_damage": 0.6},
						},
				"zhenhuo_fu": {
					"name": "真火符", "behavior": Behavior.PROJECTILE,
					"sfx": "talisman_throw",
					"damage": 17.0, "cooldown": 1.1, "range": 255.0,
					"knockback": 160.0,
					"price": 34, "icon": "res://assets/art/weapon_zhenhuo_fu.png",
					# 竖直符纸无锋刃轴：upright 竖直悬浮施法（2026-10-18 修歪斜翻面）
					"tip": Vector2(20, 0), "shape": "talisman", "upright": true,
					"desc": "三昧真火符烈焰灼烧，受元素与远程伤害加成", "tag": "元素·远程·弹射·火",
					"bullet": "res://assets/art/bullet_true_fire_talisman.png", "bullet_scale": 0.65, "bullet_spin": true,
					"pierce": 1, "proc_burn": true, "burn_ratio": 0.50, "burn_dur": 3.0,
					"tags": ["talisman", "fire"],
					"stat_scalings": {"elemental_damage": 1.2, "ranged_damage": 0.6},
				},
				"leihuo_fu": {
					"name": "雷火符", "behavior": Behavior.PROJECTILE,
					# 双器类三重共鸣（仿剑阵盘）：同时计入 符箓+雷法 两条器类羁绊与火系羁绊
					"sfx": "talisman_throw",
					"damage": 10.0, "cooldown": 0.95, "range": 260.0,
					"knockback": 140.0,
					"price": 40, "icon": "res://assets/art/weapon_leihuo_fu.png",
					# 竖直符纸无锋刃轴：upright 竖直悬浮施法，器口只在瞄准轴取长度（2026-10-18 修歪斜翻面）
					"tip": Vector2(20, 0), "shape": "talisman", "upright": true,
					"desc": "雷火双符扇射2张引燃爆裂，受元素与远程伤害加成", "tag": "元素·雷法·火",
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
					"damage": 30.0, "cooldown": 1.0, "range": 120.0,
					"knockback": 320.0,
					"price": 32, "icon": "res://assets/art/weapon_hanshuang_jian.png",
					"tip": Vector2(22, 0), "shape": "sword",
					"desc": "霜刃挥砍冻缓敌人，受近战伤害与移速加成", "tag": "近战·剑系·水",
					"arc_scale": 1.2, "proc_chill": 0.40, "chill_dur": 2.0,
					"tags": ["sword", "water"],
					"stat_scalings": {"melee_damage": 1.0, "move_speed_bonus": 25.0},
				},
				"langli_suo": {
					"name": "浪里梭", "behavior": Behavior.PROJECTILE,
					"sfx": "impact_crack",
					"damage": 19.0, "cooldown": 0.95, "range": 260.0,
					"knockback": 130.0,
					"price": 34, "icon": "res://assets/art/weapon_langli_suo.png",
					"tip": Vector2(22, 2), "shape": "shuttle",
					"desc": "水梭连锁弹射3次冻缓敌群，受远程伤害与移速加成", "tag": "远程·横扫·水",
					"bullet": "res://assets/art/bullet_water_shuttle.png", "bullet_scale": 0.6, "bullet_spin": true,
					"pierce": 1, "bounce_count": 3, "proc_chill": 0.35, "chill_dur": 2.0,
					"tags": ["wide", "water"],
					"stat_scalings": {"ranged_damage": 0.8, "move_speed_bonus": 28.0},
				},
					"hanquan_shou": {
						"name": "寒泉兽", "behavior": Behavior.TURRET,
						"sfx": "metal_dart",
						"damage": 9.0, "cooldown": 4.0, "range": 210.0,
						"turret_fire_cd": 0.45, "turret_lifetime": 10.0, "turret_cap": 2,
						"knockback": 90.0,
						"price": 40, "icon": "res://assets/art/weapon_hanquan_shou.png",
						"tip": Vector2(20, -6), "turret_shape": "beast", "upright": true,
						"desc": "布设寒泉机关兽连吐冰针冻缓敌群，受机关伤害与攻击间隔加成", "tag": "机关·水",
						"bullet": "res://assets/art/bullet_ice_needle.png", "bullet_scale": 0.50, "bullet_spin": false,
						"pierce": 1, "proc_chill": 0.30, "chill_dur": 1.5,
						"tags": ["contraption", "water"],
						"stat_scalings": {"contraption_damage": 1.0, "cdr_bonus": 20.0},
					},

				# ---- 木 2 把：木∩符箓第 3 把 + 机关补格 ----
				"gudu_fu": {
					"name": "蛊毒符", "behavior": Behavior.PROJECTILE,
					"sfx": "talisman_throw",
					"damage": 16.0, "cooldown": 1.0, "range": 250.0,
					"knockback": 120.0,
					"price": 34, "icon": "res://assets/art/weapon_gudu_fu.png",
					# 竖直符纸无锋刃轴：upright 竖直悬浮施法（2026-10-18 修歪斜翻面）
					"tip": Vector2(20, 0), "shape": "talisman", "upright": true,
					"desc": "蛊虫毒符连锁弹射3次剧毒蔓延，受远程与元素伤害加成", "tag": "远程·弹射·木",
					"bullet": "res://assets/art/bullet_gu_talisman.png", "bullet_scale": 0.6, "bullet_spin": true,
					"pierce": 1, "bounce_count": 3, "proc_poison": true, "poison_ratio": 0.35, "poison_dur": 3.0,
					"tags": ["talisman", "wood"],
					"stat_scalings": {"ranged_damage": 0.8, "elemental_damage": 0.8, "hp_regen": 3.0},
				},
					"tengluo_jiguan": {
						"name": "藤萝机关", "behavior": Behavior.TURRET,
						"sfx": "impact_crack",
						"damage": 14.0, "cooldown": 3.6, "range": 255.0,
						"turret_fire_cd": 0.65, "turret_lifetime": 12.0, "turret_cap": 2,
						"knockback": 110.0,
						"price": 38, "icon": "res://assets/art/weapon_tengluo_jiguan.png",
						"tip": Vector2(22, -16), "turret_shape": "trebuchet", "upright": true,
						"desc": "布设藤萝弹射器毒镖叠毒，受机关伤害与生命回复加成", "tag": "机关·木",
						"bullet": "res://assets/art/bullet_leaf_dagger.png", "bullet_scale": 0.55, "bullet_spin": false,
						"pierce": 1, "proc_poison": true, "poison_ratio": 0.30, "poison_dur": 2.5,
						"tags": ["contraption", "wood"],
						"stat_scalings": {"contraption_damage": 1.0, "hp_regen": 3.0},
					},

				# ---- 土 2 把：土∩剑第 3 把 + 机关补格（机关 6 把 ⇒ 三档可达） ----
				"bengshan_jian": {
					"name": "崩山剑", "behavior": Behavior.MELEE,
					"sfx": "whoosh_heavy", "sfx_impact": "impact_blunt",
					"damage": 37.0, "cooldown": 1.2, "range": 128.0,
					"knockback": 420.0,
					"price": 38, "icon": "res://assets/art/weapon_bengshan_jian.png",
					"tip": Vector2(22, 0), "shape": "sword",
						"desc": "崩山重剑阔扫大力震退，受近战伤害与护甲加成", "tag": "近战·剑系·土",
					"arc_scale": 1.3,
					"tags": ["sword", "earth"],
					"stat_scalings": {"melee_damage": 1.0, "armor": 2.5},
				},
					"leishi_jiguan": {
						"name": "垒石机关", "behavior": Behavior.TURRET,
						"sfx": "impact_blunt",
						"damage": 20.0, "cooldown": 4.5, "range": 230.0,
						"turret_fire_cd": 0.9, "turret_lifetime": 10.0, "turret_cap": 2,
						"knockback": 300.0,
						"price": 42, "icon": "res://assets/art/weapon_leishi_jiguan.png",
						"tip": Vector2(22, 16), "turret_shape": "trebuchet", "upright": true,
						"desc": "布设垒石投掷机抛石砸退敌群，受机关伤害与护甲加成", "tag": "机关·土",
						"bullet": "res://assets/art/bullet_earth_talisman.png", "bullet_scale": 0.6, "bullet_spin": true,
						"pierce": 1,
						"tags": ["contraption", "earth"],
						"stat_scalings": {"contraption_damage": 1.0, "armor": 2.0},
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
						# 2026-10-22 攻速分化：金铃清脆震鸣 0.46s
						"damage": 22.0, "cooldown": 0.46, "range": 180.0,
						"knockback": 210.0,
					"price": 42, "icon": "res://assets/art/weapon_jinming_ling.png",
					"desc": "金铃环绕震鸣切金，受召唤伤害与暴击率加成", "tag": "召唤·环绕·金",
					"tags": ["spirit", "metal"],
					"stat_scalings": {"engineering_damage": 1.0, "crit_rate": 30.0},
				},
					"muling_ou": {
						"name": "木灵偶", "behavior": Behavior.DRONE,
						"sfx": "drone_flutter",
						# 2026-10-22 攻速分化：木偶人步法 0.52s 守御
						"damage": 25.0, "cooldown": 0.52, "range": 185.0,
						"knockback": 180.0,
					"price": 42, "icon": "res://assets/art/weapon_muling_ou.png",
					"desc": "木偶人环绕护卫生生不息，受召唤伤害与生命回复加成", "tag": "召唤·环绕·木",
					"tags": ["spirit", "wood"],
					"stat_scalings": {"engineering_damage": 1.0, "hp_regen": 4.0},
				},
					"bingpo_zhu": {
						"name": "冰魄珠", "behavior": Behavior.DRONE,
						"sfx": "drone_chime",
						# 2026-10-22 攻速分化：冰魄凝晶宝珠 0.50s 护体
						"damage": 24.0, "cooldown": 0.50, "range": 185.0,
						"knockback": 190.0,
					"price": 42, "icon": "res://assets/art/weapon_bingpo_zhu.png",
					"desc": "冰魄宝珠环绕冻缓来敌，受召唤伤害与攻击间隔加成", "tag": "召唤·环绕·水",
					"proc_chill": 0.40, "chill_dur": 2.5,
					"tags": ["spirit", "water"],
					"stat_scalings": {"engineering_damage": 1.0, "cdr_bonus": 30.0},
				},
					"chiyan_ying": {
						"name": "赤炎萤", "behavior": Behavior.DRONE,
						"sfx": "drone_flutter",
						# 2026-10-22 攻速分化：火萤蜂鸣高速穿刺 0.36s 疾舞
						"damage": 16.0, "cooldown": 0.36, "range": 180.0,
						"knockback": 150.0,
					"price": 42, "icon": "res://assets/art/weapon_chiyan_ying.png",
					"desc": "火萤群环绕扑击引燃敌人，受召唤与元素伤害加成", "tag": "召唤·环绕·火",
					"proc_burn": true, "burn_ratio": 0.35, "burn_dur": 2.5,
					"tags": ["spirit", "fire"],
					"stat_scalings": {"engineering_damage": 1.0, "elemental_damage": 0.5},
				},
						"tuling_shi": {
							"name": "土灵石", "behavior": Behavior.DRONE,
							"sfx": "orb_hit",
							# 2026-10-22 攻速分化：厚土磐石厚重运转 0.70s 强力震退
							"damage": 34.0, "cooldown": 0.70, "range": 185.0,
							"knockback": 330.0,
						"price": 42, "icon": "res://assets/art/weapon_tuling_shi.png",
						"desc": "符文灵石环绕撞击震退敌群，受召唤伤害与护甲加成", "tag": "召唤·环绕·土",
						"tags": ["spirit", "earth"],
						"stat_scalings": {"engineering_damage": 1.0, "armor": 2.5},
					},
					"jianling": {
						"name": "剑灵", "behavior": Behavior.DRONE,
						# 三重共鸣（仿剑阵盘）：同时计入 御灵+剑系 两条器类羁绊与金系羁绊
						"sfx": "drone_chime",
						# 2026-10-22 攻速分化：精魂灵动飞斩 0.42s
						"damage": 20.0, "cooldown": 0.42, "range": 180.0,
						"knockback": 170.0,
					"price": 44, "icon": "res://assets/art/weapon_jianling.png",
					"desc": "剑形精魂环绕飞斩，受召唤伤害与暴击率加成", "tag": "召唤·剑系·金",
					"tags": ["spirit", "sword", "metal"],
					"stat_scalings": {"engineering_damage": 1.0, "crit_rate": 30.0},
				},

				# ---- 三标签交叉 2 把 + 雷法/横扫/符箓/机关补强 ----
					"kuilei_shou": {
						"name": "傀儡兽", "behavior": Behavior.TURRET,
						# 三重共鸣（仿剑阵盘）：同时计入 机关+御灵 两条器类羁绊与土系羁绊
						"sfx": "impact_crack",
						"damage": 12.0, "cooldown": 3.8, "range": 240.0,
						"turret_fire_cd": 0.55, "turret_lifetime": 12.0, "turret_cap": 2,
						"knockback": 150.0,
						"price": 42, "icon": "res://assets/art/weapon_kuilei_shou.png",
						"tip": Vector2(22, -2), "turret_shape": "beast", "upright": true,
						"desc": "布设符灯傀儡兽掷石守御，受机关与召唤伤害加成", "tag": "机关·召唤·土",
						"bullet": "res://assets/art/bullet_earth_talisman.png", "bullet_scale": 0.55, "bullet_spin": true,
						"pierce": 1,
						"tags": ["contraption", "spirit", "earth"],
						"stat_scalings": {"contraption_damage": 1.0, "engineering_damage": 0.5, "armor": 2.0},
					},
						"lieshan_duo": {
							"name": "裂山铎", "behavior": Behavior.BURST,
							"sfx": "whoosh_heavy", "sfx_impact": "drum_boom",
							# 2026-10-22 攻速分化：铎声震山 1.45s 标准雷法
							"damage": 31.0, "cooldown": 1.45, "range": 255.0,
							"knockback": 340.0,
						"price": 40, "icon": "res://assets/art/weapon_lieshan_duo.png",
						"tip": Vector2(20, 2), "shape": "bell", "upright": true,
						"desc": "铎钟裂山震波轰击区域大力击退，受元素伤害与护甲加成", "tag": "元素·雷法·土",
						"burst_radius": 85.0, "burst_tint": Color(0.80, 0.66, 0.38),
						"burst_kind": "earth",
						"tags": ["thunder", "earth"],
						"stat_scalings": {"elemental_damage": 1.2, "armor": 2.5},
					},
				"jingzhe_fu": {
					"name": "惊蛰符", "behavior": Behavior.PROJECTILE,
					# 三重共鸣（仿剑阵盘）：同时计入 符箓+雷法 两条器类羁绊与木系羁绊
					"sfx": "talisman_throw",
					"damage": 16.0, "cooldown": 1.0, "range": 255.0,
					"knockback": 130.0,
					"price": 36, "icon": "res://assets/art/weapon_jingzhe_fu.png",
					# 竖纸符头朝上：upright 竖直悬浮施法（2026-10-18 统一符箓姿态，免旋转翻面）
					"tip": Vector2(22, 0), "shape": "talisman", "upright": true,
					"desc": "惊蛰雷符弹射2次叠毒滋蔓，受远程与元素伤害加成", "tag": "远程·雷法·木",
					"bullet": "res://assets/art/bullet_jingzhe_fu.png", "bullet_scale": 0.6, "bullet_spin": true,
					"pierce": 1, "bounce_count": 2, "proc_poison": true, "poison_ratio": 0.30, "poison_dur": 2.5,
					"tags": ["talisman", "thunder", "wood"],
					"stat_scalings": {"ranged_damage": 0.8, "elemental_damage": 0.8, "hp_regen": 3.0},
				},
					"liaoyuan_shan": {
						"name": "燎原扇", "behavior": Behavior.SWEEP,
						"sfx": "fan_gust", "sfx_impact": "impact_crack",
							# 2026-10-14 风险溢价重排：横扫贴脸档 26~34（2026-10-22 攻速分化：火风急扇 1.25s）
							"damage": 24.0, "cooldown": 1.25, "range": 119.0,
						"knockback": 390.0,
					"price": 36, "icon": "res://assets/art/weapon_liaoyuan_shan.png",
					"tip": Vector2(22, 0), "shape": "fan",
					"desc": "横扫燎原火风焚烧前方敌群，受近战与元素伤害加成", "tag": "近战·横扫·火",
					"arc_scale": 1.35, "proc_burn": true, "burn_ratio": 0.40, "burn_dur": 3.0,
					"tags": ["wide", "fire"],
					"stat_scalings": {"melee_damage": 1.0, "elemental_damage": 0.8, "move_speed_bonus": 25.0},
				},
					"kaishan_fu": {
						"name": "开山斧", "behavior": Behavior.SWEEP,
						"sfx": "whoosh_heavy", "sfx_impact": "impact_blunt",
							# 2026-10-14 风险溢价重排：横扫贴脸档 26~34（2026-10-22 攻速分化：巨斧蓄力 1.65s 力劈）
							"damage": 44.0, "cooldown": 1.65, "range": 114.0,
						"knockback": 620.0,
					"price": 38, "icon": "res://assets/art/weapon_kaishan_fu.png",
					"tip": Vector2(22, 0), "shape": "axe",
					"desc": "横扫开山巨斧劈退正面敌群，受近战伤害与护甲加成", "tag": "近战·横扫·土",
					"arc_scale": 1.3,
					"tags": ["wide", "earth"],
					"stat_scalings": {"melee_damage": 1.0, "armor": 2.5},
				},
						"gengjin_fu": {
							"name": "庚金符", "behavior": Behavior.PROJECTILE,
							"sfx": "metal_dart",
							"damage": 9.0, "cooldown": 0.66, "range": 255.0,
							"knockback": 85.0,
							"price": 34, "icon": "res://assets/art/weapon_gengjin_fu.png",
							# 竖纸符头朝上：upright 竖直悬浮施法（2026-10-18 统一符箓姿态，免旋转翻面）
							"tip": Vector2(22, 0), "shape": "talisman", "upright": true,
							"desc": "连射2张金符高速追击，受远程伤害与暴击率加成", "tag": "远程·弹射·金",
							"bullet": "res://assets/art/bullet_gengjin_fu.png", "bullet_scale": 0.55, "bullet_spin": false,
							"pierce": 1, "projectile_count": 2, "spread_angle": 0.10,
							"tags": ["talisman", "metal"],
							"stat_scalings": {"ranged_damage": 0.85, "crit_rate": 35.0},
						},

					# ==================== 2026-10-12 第三批 8 把：填满只剩 1 把的 器类×五行 交叉格 ====================
					# 空洞格清单（各仅 1 把，羁绊 2 件档都凑不出）：剑-木、符-水、符-土、雷-金、雷-水、
					# 机关-木/水/火。每把照同行为同格锚点法定数值，零新行为代码。
					# 顺带把冷门 scaling 链接进新武器（吸血/冷却/暴击伤害/范围/额外生命），激活死链。
					# 图标暂借同格锚点贴图占位，TODO(media-gen)：出专属图标后替换并补 manifest。
							"taomu_jian": {
								"name": "桃木剑", "behavior": Behavior.MELEE,
								"sfx": "whoosh_light", "sfx_impact": "impact_blade",
								# 机制差异化重构：辟邪纯阳剑芒，中远距离宽弧远扫（range 175/arc 1.25）+ 强力震退，吃范围加成
								"damage": 31.0, "cooldown": 1.10, "range": 124.0,
								"knockback": 380.0,
								# 2026-10-18 media-gen 专属重绘：千年雷击桃木剑，深沉暗红木质与七星连珠刻痕
								"price": 30, "icon": "res://assets/art/weapon_taomu_jian.png",
								"tip": Vector2(22, -16), "shape": "sword",
								"desc": "辟邪纯阳剑芒宽弧远扫强力击退，受近战伤害与范围加成", "tag": "近战·剑系·木",
								"arc_scale": 1.25,
								"tags": ["sword", "wood"],
								"stat_scalings": {"melee_damage": 1.0, "range_bonus": 25.0},
							},
					"guishui_fu": {
						"name": "癸水符", "behavior": Behavior.PROJECTILE,
						"sfx": "talisman_throw",
						"damage": 21.0, "cooldown": 0.85, "range": 255.0,
						"knockback": 120.0,
						"price": 32, "icon": "res://assets/art/weapon_guishui_fu.png",
						# 竖直符纸无锋刃轴：upright 竖直悬浮施法（2026-10-18 随新图统一姿态）
						"tip": Vector2(22, 0), "shape": "talisman", "upright": true,
						"desc": "癸水阴符急速连发，受远程伤害与攻击间隔加成", "tag": "远程·弹射·水",
						"bullet": "res://assets/art/bullet_frost_talisman.png", "bullet_scale": 0.6, "bullet_spin": true,
						"pierce": 1,
						"tags": ["talisman", "water"],
						"stat_scalings": {"ranged_damage": 0.8, "cdr_bonus": 25.0},
					},
						"houtu_fu": {
							"name": "厚土符", "behavior": Behavior.PROJECTILE,
							"sfx": "talisman_throw",
								"damage": 13.0, "cooldown": 1.10, "range": 255.0,
							"knockback": 200.0,
							# 2026-10-18 media-gen 专属重绘：厚土岩甲符，玄铁硬轴与古藤玄黄符纸
							"price": 32, "icon": "res://assets/art/weapon_houtu_fu.png",
							"tip": Vector2(20, 0), "shape": "talisman", "upright": true,
								"desc": "两张厚土符扇形铺开各锁1敌，受远程伤害与护甲加成", "tag": "远程·弹射·土",
								"bullet": "res://assets/art/bullet_stone_talisman.png", "bullet_scale": 0.6, "bullet_spin": true,
								"pierce": 1, "projectile_count": 2, "spread_angle": 0.22,
							"tags": ["talisman", "earth"],
							"stat_scalings": {"ranged_damage": 0.8, "armor": 2.0},
						},
							"jinxiao_leiling": {
								"name": "金霄雷令", "behavior": Behavior.BURST,
								"sfx": "whoosh_light", "sfx_impact": "thunder_strike",
								# 2026-10-22 攻速分化：神霄金令 1.70s 威严肃穆引大雷
								"damage": 36.0, "cooldown": 1.70, "range": 270.0,
								"knockback": 260.0,
								# 2026-10-18 media-gen 专属重绘：五雷天师金牌令牌，雷云兽首吞口与金色雷纹
								"price": 38, "icon": "res://assets/art/weapon_jinxiao_leiling.png",
								"tip": Vector2(18, 4), "shape": "tablet", "upright": true,
								"desc": "金霄神雷轰击一片敌群，受元素伤害与暴击伤害加成", "tag": "元素·雷法·金",
								"burst_radius": 78.0, "burst_tint": Color(1.0, 0.88, 0.45),
								"tags": ["thunder", "metal"],
								"stat_scalings": {"elemental_damage": 1.0, "crit_mult_bonus": 30.0},
							},
							"xuanming_leizhu": {
								"name": "玄冥雷珠", "behavior": Behavior.BURST,
								"sfx": "flute_wave", "sfx_impact": "thunder_strike",
								# 2026-10-22 攻速分化：玄冥阴雷珠 1.50s 运转炸开
								"damage": 31.0, "cooldown": 1.50, "range": 270.0,
								"knockback": 300.0,
								# 2026-10-18 media-gen 专属重绘：玄冥冰晶水雷珠，深邃玄晶与幽蓝冷电
								"price": 38, "icon": "res://assets/art/weapon_xuanming_leizhu.png",
								"tip": Vector2(22, 0), "shape": "bead", "upright": true,
								"desc": "玄冥阴雷炸开冻缓敌群，受元素伤害与移速加成", "tag": "元素·雷法·水",
								"burst_radius": 70.0, "burst_tint": Color(0.45, 0.75, 1.0),
								"burst_kind": "frost",
								"proc_chill": 0.40, "chill_dur": 2.0,
								"tags": ["thunder", "water"],
								"stat_scalings": {"elemental_damage": 1.0, "move_speed_bonus": 28.0},
							},
							"zihong_jing": {
								"name": "紫虹镜", "behavior": Behavior.BEAM,
								"sfx": "flute_wave",
								"damage": 22.0, "cooldown": 1.15, "range": 265.0,
								"knockback": 80.0,
								# 2026-10-18 media-gen 专属重绘：八面棱角玄铁紫玉晶镜，冷月冷冽雷芒
								"price": 42, "icon": "res://assets/art/weapon_zihong_jing.png",
								"tip": Vector2(22, 0), "shape": "mirror", "upright": true,
								"desc": "持续照出紫电光束贯穿一线敌群，受元素伤害与暴击率加成", "tag": "元素·雷法·金",
								"tags": ["thunder", "metal"],
								"stat_scalings": {"elemental_damage": 1.2, "crit_rate": 25.0},
							},
							"qingmu_pao": {
								"name": "青木炮", "behavior": Behavior.TURRET,
								"sfx": "impact_crack",
								"damage": 13.0, "cooldown": 3.8, "range": 260.0,
								"turret_fire_cd": 0.60, "turret_lifetime": 12.0, "turret_cap": 2,
								"knockback": 115.0,
								# 2026-10-18 media-gen 专属重绘：重型攻城青木灵炮，青铜墨木箍合与幽绿木灵光
								"price": 38, "icon": "res://assets/art/weapon_qingmu_pao.png",
								"tip": Vector2(22, -12), "turret_shape": "cannon", "upright": true,
								"desc": "布设青木灵炮贯穿敌阵，受机关伤害与生命回复加成", "tag": "机关·木",
								"bullet": "res://assets/art/bullet_leaf_dagger.png", "bullet_scale": 0.55, "bullet_spin": false,
								"pierce": 1,
								"tags": ["contraption", "wood"],
								"stat_scalings": {"contraption_damage": 1.0, "hp_regen": 4.0},
							},
							"ningbing_nu": {
								"name": "凝冰机弩", "behavior": Behavior.TURRET,
								"sfx": "metal_dart",
								"damage": 12.0, "cooldown": 4.0, "range": 280.0,
								"turret_fire_cd": 0.55, "turret_lifetime": 10.0, "turret_cap": 2,
								"knockback": 95.0,
								# 2026-10-18 media-gen 专属重绘：重型三联装攻城机关弩，玄冰冰晶弩臂与极寒飞针
								"price": 40, "icon": "res://assets/art/weapon_ningbing_nu.png",
								"tip": Vector2(22, -10), "turret_shape": "crossbow", "upright": true,
									"desc": "布设凝冰机弩远程点杀冻缓敌人，受机关伤害与范围加成", "tag": "机关·水",
								"bullet": "res://assets/art/bullet_ice_needle.png", "bullet_scale": 0.50, "bullet_spin": false,
								"pierce": 1, "proc_chill": 0.25, "chill_dur": 1.5,
								"tags": ["contraption", "water"],
								"stat_scalings": {"contraption_damage": 1.0, "range_bonus": 25.0},
							},
							"fenghuo_tai": {
								"name": "烽火台", "behavior": Behavior.TURRET,
								"sfx": "flame_jet",
								"damage": 10.0, "cooldown": 4.4, "range": 195.0,
								"turret_fire_cd": 0.50, "turret_lifetime": 11.0, "turret_cap": 2,
								"knockback": 100.0,
								# 2026-10-18 media-gen 专属重绘：八角重甲玄石烽火台，狼烟火盆与赤红真火
								"price": 40, "icon": "res://assets/art/weapon_fenghuo_tai.png",
								"tip": Vector2(20, 0), "turret_shape": "tower", "upright": true,
								"desc": "布设烽火台持续喷焰引燃敌群，受机关伤害与最大生命加成", "tag": "机关·火",
								"bullet": "res://assets/art/bullet_fire_flame.png", "bullet_scale": 0.50, "bullet_spin": true,
								"pierce": 1, "proc_burn": true, "burn_ratio": 0.35, "burn_dur": 2.5,
								"tags": ["contraption", "fire"],
								"stat_scalings": {"contraption_damage": 1.0, "max_hp_bonus": 0.10},
							},
}

## 流派羁绊：同 tag 武器持有多件时激活阶梯加成（重复同名武器也计数）
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
##   field  —— 被改写的 GameManager 属性名（恒 synergy_* 前缀；生命那条再经 apply_synergy_hp 落到 player）
##   list   —— 取数用的列表 key，主效果恒为 "values"
##   op     —— "add"：field += v（1.0 基数的乘区存加成幅度，0.08 即 +8%）；"mul"：field *= v（攻速存 0.92 这类系数）
##   label  —— 给人看的属性名；局内阶梯行与图鉴共用同一个词，不许一处简称一处全称
##   form   —— 展示折算："pct" 0.08→+8%、"pct_down" 0.92→-8%、"flat" 3→+3、"flat1" 1.0→+1.0
##   suffix —— 展示后缀，如 "/秒"
const SYNERGIES: Dictionary = {
	# ---- 器类羁绊 ----
	"sword": {
		# 2026-10-20 再收一档（用户口径「攻击范围很容易提到很大很远」）：范围全域共享
		# （弹丸寿命也吃乘区），+10/20/30 叠上悟道与道具后仍能翻倍，砍到 +5/10/15。
		# 剑系的主要收益仍是「多一把剑」，范围只作点缀
		"name": "剑系", "thresholds": [2, 4, 6], "values": [0.05, 0.10, 0.15],
		"effects": [
			{"field": "synergy_range_mult", "list": "values", "op": "add", "label": "攻击范围", "form": "pct"},
		],
	},
	"talisman": {
		# 2026-10-17 重做（用户口径：+1/2/3 穿透与 PIERCE_CAP=3 冲突——6 件 +3 会被钳成
		# "看着涨实际原地踏步"）。改成双条效果：穿透只给首档 +1（2 件起效、后面档位不再加），
		# 成长换到远程伤害 +6/12/18%——弹射流 13 把全是弹丸（ranged_damage 全员系数 0.8+），
		# 逐档有实感、永不撞上限。满穿透停刷判定按实际阵容逐把对账（PierceLimit）。
		"name": "弹射", "thresholds": [2, 4, 6], "values": [1, 1, 1],
		"dmg_values": [0.06, 0.12, 0.18],
		"effects": [
			{"field": "synergy_bonus_pierce", "list": "values", "op": "add", "label": "弹丸穿透", "form": "flat"},
			{"field": "synergy_ranged_damage", "list": "dmg_values", "op": "add", "label": "远程伤害", "form": "pct"},
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
		# 2026-10-20 击退整系移除：第二条腿从「击退力度」改为「反伤」，与守卫/玄武反震流呼应。
		"thorns_values": [0.10, 0.20, 0.35],
		"effects": [
			{"field": "synergy_armor", "list": "values", "op": "add", "label": "护甲", "form": "flat"},
			{"field": "synergy_thorns", "list": "thorns_values", "op": "add", "label": "反伤", "form": "pct"},
		],
	},
}

## 羁绊可改写的 GameManager 属性全集：SynergySystem 每轮结算前按它清零，
## 判据按它比对增量。新增 synergy_* 属性必须同时进这张表与某条 effects，
## 否则 UnitRunner 报红（漏进清零表 = 跨回合累加的隐形 Bug，漏进 effects = 白送不显示）。
const SYNERGY_FIELDS: Array[String] = [
	"synergy_bonus_pierce", "synergy_damage_mult", "synergy_range_mult", "synergy_haste_mult",
	"synergy_max_hp_bonus", "synergy_engineering_damage", "synergy_crit_rate", "synergy_crit_mult",
	"synergy_hp_regen", "synergy_lifesteal", "synergy_move_speed_mult", "synergy_burn_mult",
	"synergy_armor", "synergy_thorns", "synergy_contraption_mult", "synergy_ranged_damage",
]

## 弹丸穿透总数上限（2026-10-17，用户口径：「最大穿透为3，达到之后就不会继续刷出加穿透的加点和物品」）：
## 表内 pierce + 词条/道具/羁绊合计钳到 PIERCE_CAP；PierceLimit.has_max_pierce 按同一把尺
## 判定"满穿透"：PierceLimit 按当前阵容逐把检查基础 pierce + bonus_pierce，全部达到上限才停刷。
const PIERCE_CAP := 3

## 出膛穿透钳位：FloatingWeapon/TurretUnit 弹丸赋值统一走它，不许各自散写 mini
static func capped_pierce(raw_pierce: int) -> int:
	return mini(maxi(1, raw_pierce), PIERCE_CAP)

## 某属性的羁绊基数（"add" 从基数起算，"mul" 从 1.0 起算）：与 GameManager 声明初值同源
## 基数写成 int 的字段（穿透次数）＝ 声明该属性是整数，SynergySystem 结算后按它回截类型，
## 往 int 属性 set 一个 float 会被引擎打回「Invalid assignment」并静默留旧值。
const SYNERGY_BASE := {
	"synergy_bonus_pierce": 0, "synergy_damage_mult": 1.0, "synergy_range_mult": 1.0,
	"synergy_haste_mult": 1.0, "synergy_max_hp_bonus": 0.0, "synergy_engineering_damage": 0.0,
	"synergy_crit_rate": 0.0, "synergy_crit_mult": 0.0, "synergy_hp_regen": 0.0,
	"synergy_lifesteal": 0.0, "synergy_move_speed_mult": 0.0, "synergy_burn_mult": 1.0,
	"synergy_armor": 0.0, "synergy_thorns": 0.0, "synergy_contraption_mult": 1.0,
	"synergy_ranged_damage": 0.0,
}

## 开局六选一：六大器类齐备（长剑-剑系/雷牌-雷法/风扇-横扫/火符-弹射/机关弩-机关/护蝶-御灵），兼顾五行
const STARTER_IDS: Array = ["qingyun_sword", "wulei_paizi", "bajiao_fan", "huoyan_fu", "jiguan_nu", "lingdie"]

## 商店武器池 = 全部武器。
## 2026-10-24 起由 DEFS 键自动派生：原先是 70 个 id 的手工副本（分批新增记录见各段注释），
## 漏抄一个的后果是「新武器永远不进商店且无任何报错」（13 处消费方与 8 个测试都遍历
## SHOP_POOL 而非 DEFS，测试跟着失明）。机制上根除：加武器只改 DEFS 一处。
## 消费方约定：只读迭代/索引，不得 mutate（static 共享，写坏会污染整个会话）；
## 若未来需要「个别武器不进商店」，在 DEFS 条目加 "in_shop": false 再在这里过滤。
static var SHOP_POOL: Array = DEFS.keys()

## 回血丹（商店消耗品）
const POTION_ID: String = "healing_pill"
const POTION_BASE_PRICE: int = 10

static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, {})

## 武器攻击方式短标（货架卡色签 / 详情卡「攻击方式」行共用）：
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
		Behavior.SWEEP:
			return "横扫"
		Behavior.BEAM:
			return "光束"
		Behavior.CONE:
			return "喷吐"
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
			"敌人必须在身前一挥够得着的地方，否则这一路武器不出手。",
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
				"不靠出手那一帧：同一个敌人各自有命中间隔，攻击间隔越短贴得越疼。",
				"打得到的是绕身那一圈，远处的敌人够不着 → 通常再配一把近战或远程补上。",
			"升星会分身：★2 一化为二、★3 一化为三，每具独立贴身结算，总伤害不变但贴得更全。",
		],
	},
	Behavior.TURRET: {
		"how": "按冷却在脚下布设一座机关，它自己索敌开火、寿命到点消散",
		"notes": [
			"同时最多站那么几座，摆满就撤掉最旧的一座顶上；升星多站一座。",
			"机关这一类独享「机关」羁绊的伤害档，别的武器不吃这一条。",
		],
	},
	Behavior.SWEEP: {
		"how": "蓄力后朝前方大幅横扫，扇形弧面内的敌人一起挨打",
		"notes": [
			"横扫是扇形判定：只打正前方弧面里的敌人，身后的漏网——站位朝向比近战更讲究。",
			"比近战更沉更慢：单下伤害更高、击退更猛，一扫一片，适合正面压住怪群。",
		],
	},
	Behavior.BEAM: {
		"how": "锁定敌人后持续照出一道光束，被光束压住的敌人持续掉血",
		"notes": [
			"光束会被第一个碰到的敌人挡住，但线上擦到的敌人一起结算——怪群站成一线时一串全中。",
			"光束跟着目标缓慢扫动；拉开距离脱离射程就收束。",
		],
	},
	Behavior.CONE: {
		"how": "朝锁定方向持续喷吐火焰，锥形里的敌人一起挨打并被点燃",
		"notes": [
			"喷吐射程短，要贴近怪群才喷得到——站位比远程更讲究。",
			"被喷到的敌人会点燃，跑出火焰后还要再烧一会儿。",
		],
	},
}

## 这一攻击方式的机制解释（缺条目返回空字典，由调用方决定要不要画）
static func behavior_tip(behavior: int) -> Dictionary:
	return BEHAVIOR_TIPS.get(behavior, {})

## 全武器库里属于这一攻击方式的把数（解释卡上的「这一类共 N 把」）
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
	# 基础 pierce=1 即只打一名敌人（不穿透），卡面不显「穿透」；仅基础 ≥2 才上卡。
	if pierce > 1:
		out.append("穿透%d" % pierce)
	var count := int(def.get("projectile_count", 1))
	if count > 1:
		out.append("%d发" % count)
	var bounce := int(def.get("bounce_count", 0))
	if bounce > 0:
		out.append("弹射%d" % bounce)
	if float(def.get("arc_scale", 1.0)) > 1.001:
		# 近战里摆幅更宽的剑（烈焰刀/重盾这一族）叫「宽扫」——2026-10-13 横扫独立成
		# Behavior.SWEEP 后，卡面特性不许再与攻击方式短标「横扫」撞词
		out.append("宽扫")
	if out.size() > 2:
		out.resize(2)
	return "·".join(out)

## 环绕灵宝的分身具数：★1 一具、★2 一分为二、★3 一分为三（Player.sync_drones 按此生成）。
## 单武器总纸面伤害仍走 damage_for 的星级翻倍曲线，分身只均摊结算、抬贴身覆盖与占空比。
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

const _EMPTY_ARRAY: Array = []

static func star_text(star: int) -> String:
	return "★".repeat(clampi(star, 1, MAX_STAR))

static func full_name(id: String, star: int) -> String:
	var def: Dictionary = DEFS.get(id, {})
	if def.is_empty():
		return "未知武器"
	return "%s %s" % [star_text(star), def.get("name", "?")]

static func tags_of(id: String) -> Array:
	if not DEFS.has(id):
		return _EMPTY_ARRAY
	return DEFS[id].get("tags", _EMPTY_ARRAY)

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

## 该武器的开火音 key（缺省回落到通用的 blade_shoot，保证老调用不会哑）
static func sfx_for(id: String) -> String:
	return String(DEFS.get(id, {}).get("sfx", "blade_shoot"))

## 该武器的「第二层」音 key：MELEE=命中材质声（只在真打中时播），BURST=落点爆发声。
static func sfx_impact_for(id: String) -> String:
	return String(DEFS.get(id, {}).get("sfx_impact", ""))

## 弹丸从 2026-10-08 起带有限转向追踪（BladeProjectile.HOMING_TURN_RATE）：
## 场上只剩一个敌人时，一次三发的武器每一发最终都归它 ⇒ 单体口径按发数求和才与运行时一致。
## 下面两个纯函数是给"档位体检"当尺子用的（判据见 tests/unit_runner.gd::_test_ranged_focus_dps），
## 口径：★star、不吃玩家属性/羁绊/暴击/危险度，只比较武器自身的设计强度。
const FOCUS_RANGED_MAX_TARGETS := 2   ## 单发最多结算这么几个敌人的远程武器 = 「点杀位」

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
	if behavior == Behavior.SWEEP:
		return 6      ## 横扫扇形：一扫一片，天生群体
	return 6          ## 近战弧扫 / 落雷圆形：天生群体
## 「点杀位」远程武器：弹丸类里单发最多只结算 FOCUS_RANGED_MAX_TARGETS 个敌人的那些。
## 2026-10-14 风险溢价重排：档位按贴脸风险排序 —— 近战 28~36 > 横扫 26~34 > 点杀远程 22~28
## > 群伤/功能 18~26（御灵 30~38 为半自动贴身特例）。远程射程安全 ⇒ 单体必须输给近战，
## 判据在 tests/unit/unit_targeting_tests.gd::_test_ranged_focus_dps 与 BalanceSimCheck 分档。
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

## 该武器是否吃「元素伤害」属性加成：stat_scalings 里配了 elemental_damage 系数才算。
## 返回系数（0 = 不吃），供各界面挂角标与悟道加点提示共用。
static func elemental_scaling_coef(id: String) -> float:
	return float(get_def(id).get("stat_scalings", {}).get("elemental_damage", 0.0))

