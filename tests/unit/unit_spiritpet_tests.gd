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
	# 卷击伤害：1 波基准 16，随波次按 1.15 复利成长
	_c.near(BalanceSpiritPet.vortex_damage(1, 1.0), 16.0, EPS, "卷击伤害：1 波取基准 16")
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
	_c.check(String(def.get("desc", "")).contains("4.5"), "灵风貂描述：冷却 4.5 秒与 base_cooldown 同源")
	_c.near(float(def.get("base_cooldown", 0.0)), 4.5, EPS, "灵风貂 base_cooldown = 4.5")
	_c.near(float(def.get("base_value", 0.0)), BalanceSpiritPet.vortex_radius(1.0), EPS, "灵风貂 base_value = 1 倍乘区风涡半径")
	_c.check(String(def.get("desc", "")).contains(str(int(BalanceSpiritPet.MELEE_RING))), "灵风貂描述：环半径与 MELEE_RING 同源")
	_c.check(String(def.get("desc", "")).contains(str(BalanceSpiritPet.pin_duration(1.0))), "灵风貂描述：定身时长与 pin_duration 同源")
	_c.check(def.get("role") == "control", "灵风貂定位改控制系")
	_c.check(int(def.get("base_price", 0)) == 38, "灵风貂价格对齐控制档")
