class_name UnitSpiritPetTests
extends UnitTestsBase

## 随行灵兽数值单测：钉 BalanceSpiritPet 纯函数公式、
## 牵引位移模型与定身环几何守卫，并守住 PetData 文案与生效常量同源。

const PULL_TRAVEL_EPS := 0.5  ## 滑行位移还原误差容差（px）

func _test_fengdiao_vortex_formulas() -> void:
	# 风涡半径：1 倍乘区取基准 220，下钳 120 / 上钳 480
	_c.near(BalanceSpiritPet.vortex_radius(1.0), 220.0, EPS, "风涡半径：1 倍乘区取基准")
	_c.near(BalanceSpiritPet.vortex_radius(0.1), 120.0, EPS, "风涡半径：低乘区钳地板")
	_c.near(BalanceSpiritPet.vortex_radius(3.0), 480.0, EPS, "风涡半径：高乘区钳上限")
	# 定身时长：普通 1.5s、精英 ×0.55、Boss ×0.25，resist 为 0/负/超界不越权
	_c.near(BalanceSpiritPet.pin_duration(1.0), 1.5, EPS, "定身：普通怪 1.5s")
	_c.near(BalanceSpiritPet.pin_duration(0.55), 0.825, EPS, "定身：精英按硬直抗性衰减")
	_c.near(BalanceSpiritPet.pin_duration(0.25), 0.375, EPS, "定身：终Boss 按 0.25 抗性")
	_c.near(BalanceSpiritPet.pin_duration(0.0), 0.25, EPS, "定身：零抗性吃 0.25s 地板")
	_c.near(BalanceSpiritPet.pin_duration(-1.0), 0.25, EPS, "定身：负电阻不增时")
	_c.near(BalanceSpiritPet.pin_duration(2.0), 1.5, EPS, "定身：resist>1 钳回基准不放大")
	# 卷击伤害：1 波基准 24，随波次按 1.18 复利成长
	_c.near(BalanceSpiritPet.vortex_damage(1, 1.0), 24.0, EPS, "卷击伤害：1 波取基准 24")
	_c.check(BalanceSpiritPet.vortex_damage(10, 1.0) > BalanceSpiritPet.vortex_damage(1, 1.0), "卷击伤害：随波次成长")
	_c.check(BalanceSpiritPet.vortex_damage(1, 0.0) >= 1.0, "卷击伤害：地板 1 不归零")
	# 牵引初速反解：v0 = 位移 × KNOCKBACK_DECAY_STUN ⇒ 滑行总位移 ≈ 目标位移（模型见 _resolve_velocity）
	_c.near(BalanceSpiritPet.pull_impulse(100.0) / GameBalance.KNOCKBACK_DECAY_STUN, 100.0, PULL_TRAVEL_EPS, "牵引：冲量反解还原滑行位移")
	_c.near(BalanceSpiritPet.pull_impulse(0.0), 0.0, EPS, "牵引：零位移零冲量")
	_c.near(BalanceSpiritPet.pull_impulse(-5.0), 0.0, EPS, "牵引：负距钳 0")

func _test_fengdiao_ring_geometry() -> void:
	# 定身环下界：接触伤害判定（玩家 14 + 敌身 ~19.5 ≈ 34px）的 2 倍余量 ⇒ 钉住的怪蹭不到人
	var contact_reach := 14.0 + 19.5
	_c.check(BalanceSpiritPet.MELEE_RING > contact_reach * 2.0, "定身环 > 接触判定 2 倍余量（钉住不贴脸）")
	# 定身环上界：环按索敌椭圆铺展，椭圆等效距离 = MELEE_RING，须 ≤ 最弱近战射程（血饮狂刀 120）
	# ⇒ 被卷定的目标必然在近战索敌椭圆内（长剑竖向有效距 120÷0.65≈185 的漏洞已用椭圆环堵住）
	_c.check(BalanceSpiritPet.MELEE_RING <= 120.0, "定身环椭圆等效距 ≤ 最弱近战射程 120")
	# 竖向短轴必须严格小于横向：否则等于回到圆环（正上/正下方骗过椭圆索敌）
	_c.check(GameBalance.TARGETING_ELLIPSE_Y_RATIO < 1.0, "索敌椭圆 y 比 < 1（环沿椭圆铺展的前提）")
	_c.near(BalanceSpiritPet.MELEE_RING * GameBalance.TARGETING_ELLIPSE_Y_RATIO, 78.0, EPS, "定身环竖向落点 78px（椭圆短轴）")

func _test_fengdiao_data_desc_consistency() -> void:
	# 文案数字与生效常量同源（对齐 unit_consistency 的 desc/apply 口径）
	var def: Dictionary = PetData.get_def("fengdiao")
	_c.check(String(def.get("desc", "")).contains("3.8"), "灵风貂描述：冷却 3.8 秒与 base_cooldown 同源")
	_c.near(float(def.get("base_cooldown", 0.0)), 3.8, EPS, "灵风貂 base_cooldown = 3.8")
	_c.near(float(def.get("base_value", 0.0)), BalanceSpiritPet.vortex_radius(1.0), EPS, "灵风貂 base_value = 1 倍乘区风涡半径")
	_c.check(String(def.get("desc", "")).contains(str(int(BalanceSpiritPet.MELEE_RING))), "灵风貂描述：环半径与 MELEE_RING 同源")
	_c.check(String(def.get("desc", "")).contains(str(BalanceSpiritPet.pin_duration(1.0))), "灵风貂描述：定身时长与 pin_duration 同源")
	_c.check(def.get("role") == "control", "灵风貂定位改控制系")
	_c.check(int(def.get("base_price", 0)) == 38, "灵风貂价格对齐控制档")

## 攻击类灵兽：基础伤害成长曲线与 1.18 复利（2026-10-20 双调）
func _test_attack_pets_formulas() -> void:
	# 焰灵狐：1 波基准 38，随波按 1.18 复利
	_c.near(BalanceSpiritPet.fire_damage(1, 1.0), 38.0, EPS, "焰灵狐：1 波基准 38")
	_c.near(BalanceSpiritPet.fire_damage(2, 1.0), 38.0 * 1.18, 0.01, "焰灵狐：2 波 1.18 复利")
	_c.check(BalanceSpiritPet.fire_damage(1, 0.0) >= 1.0, "焰灵狐：地板 1 不归零")
	_c.near(BalanceSpiritPet.fire_burn_dps(100.0), 40.0, EPS, "焰灵狐：灼烧 DPS = 直伤 40%")
	# 雷灵雀：1 波基准 64
	_c.near(BalanceSpiritPet.thunder_damage(1, 1.0), 64.0, EPS, "雷灵雀：1 波基准 64")
	_c.check(BalanceSpiritPet.thunder_damage(10, 1.0) > BalanceSpiritPet.thunder_damage(1, 1.0), "雷灵雀：随波次成长")
	_c.check(BalanceSpiritPet.THUNDER_CHAIN_MAX == 3, "雷灵雀：连锁目标上限 3")
	# 磐石猿：1 波基准 34
	_c.near(BalanceSpiritPet.smash_damage(1, 1.0), 34.0, EPS, "磐石猿：1 波基准 34")
	_c.near(BalanceSpiritPet.smash_radius(1.0), 160.0, EPS, "磐石猿：震地半径基准 160")
	_c.near(BalanceSpiritPet.smash_radius(0.1), 100.0, EPS, "磐石猿：震地半径钳地板 100")
	_c.near(BalanceSpiritPet.smash_radius(3.0), 320.0, EPS, "磐石猿：震地半径钳上限 320")
	_c.near(BalanceSpiritPet.SMASH_SLOW_DURATION, 3.5, EPS, "磐石猿：减速时长 3.5s（对齐冷却）")

## 聚宝蟾金舌鞭击：替代原战中吸宝
func _test_juchan_tongue_formulas() -> void:
	_c.near(BalanceSpiritPet.tongue_damage(1, 1.0), 30.0, EPS, "聚宝蟾：鞭击 1 波基准 30")
	_c.check(BalanceSpiritPet.tongue_damage(10, 1.0) > BalanceSpiritPet.tongue_damage(1, 1.0), "聚宝蟾：鞭击随波次成长")
	_c.check(BalanceSpiritPet.tongue_damage(1, 0.0) >= 1.0, "聚宝蟾：鞭击地板 1 不归零")
	_c.check(BalanceSpiritPet.harvest_stones(1, 1.0) >= 3, "聚宝蟾：回合末产金下限 3")
	_c.check(BalanceSpiritPet.harvest_stones(10, 1.0) > BalanceSpiritPet.harvest_stones(1, 1.0), "聚宝蟾：产金随波次成长")

## 玉露鹿：治疗削弱（12 固定 + 2.0% 最大生命），仍随效果乘区放大
func _test_yulu_heal_formulas() -> void:
	_c.near(BalanceSpiritPet.heal_value(1000.0, 1.0), 32.0, 0.01, "玉露鹿：1000 血治疗量 32")
	_c.near(BalanceSpiritPet.heal_value(1000.0, 2.0), 64.0, 0.01, "玉露鹿：效果乘区放大治疗")
	_c.check(BalanceSpiritPet.heal_value(100.0, 0.0) >= 5.0, "玉露鹿：治疗地板 5")
	_c.near(BalanceSpiritPet.heal_ratio(1.0), 0.020, EPS, "玉露鹿：治疗比例 2.0%")

## 玄甲龟：护盾随波成长（原固定 25 后期形同虚设）
func _test_xuangui_shield_formulas() -> void:
	_c.near(BalanceSpiritPet.shield_amount(1), 25.0, EPS, "玄甲龟：1 波护盾 25")
	_c.check(BalanceSpiritPet.shield_amount(10) > BalanceSpiritPet.shield_amount(1), "玄甲龟：护盾随波数成长")
	_c.near(BalanceSpiritPet.intercept_radius(1.0), 120.0, EPS, "玄甲龟：拦截半径基准 120")
