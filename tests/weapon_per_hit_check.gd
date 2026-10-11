extends Node

## tests/weapon_per_hit_check.gd — 卡面与详情伤害读数 vs 运行时跳字 逐把对账
## 运行: godot --headless --path . res://tests/WeaponPerHitCheck.tscn
##
## 为什么要有这条判据：2026-10-11 货架卡把「伤害 24 / 属性加成 +10」两行并成「伤害 24 → 34」，
## 右边那个数从此承诺"这就是你一下打出来的伤害"。而商店详情与属性面板此前各自维护一份乘区式子，
## 两边都漏乘了神识分流与机关羁绊（挂 6 把法器时把实际的 32.5 报成 52，虚高 60%）。
## 读数不兑现等于玩家按假数字花金币，所以这里把读数出口钉在真武器节点的 _final_damage 上：
## 以后谁往乘区链里加一档、或从 WeaponDamageReadout 里漏一档，这里当场报红。
##
## 环绕灵宝（DRONE）的运行时结算点在 SunOrb._try_damage，与 FloatingWeapon 同一套六档乘区、
## 不含机关羁绊；这一条由 _check_factor_chain 的「非机关不许乘机关羁绊」断言钉住。

var _c := TestCheck.new()

## 采样：覆盖全部 behavior 档，逐个建真武器节点对账（全库 48 把都建节点没必要，乘区链是同一份）
const NODE_SAMPLE: Array[String] = [
	"qingyun_sword",      ## 近战挥扫
	"chiyan_dao",         ## 近战 + 灼烧
	"gengjin_feijian",    ## 弹丸
	"liuye_feidao",       ## 多发弹丸
	"huoyan_fu",          ## 符箓弹丸 + 灼烧
	"fentian_baodeng",    ## 范围爆发
	"lingdie",            ## 环绕灵宝
	"jiguan_nu",          ## 机关炮台（吃机关羁绊）
	"baoyu_liuhuazhen",   ## 机关阵盘
]

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var world := Node2D.new()
	world.name = "WeaponPerHitWorld"
	get_tree().root.add_child(world)
	await get_tree().process_frame

	_setup_state()
	_check_factor_chain()
	await _check_against_real_nodes(world)
	_check_bill_and_text()
	_check_card_rows()

	world.queue_free()
	GameManager.reset_run()
	if _c.report("WEAPON_PERHIT_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)

## 每一档乘区都取互不相同的非 1 值：任何一档被漏乘，下面的数都会偏
func _setup_state() -> void:
	GameManager.reset_run()
	GameManager.weapon_damage_mult = 1.25
	GameManager.synergy_damage_mult = 1.2
	GameManager.synergy_contraption_mult = 1.3
	GameManager.melee_damage = 8.0
	GameManager.ranged_damage = 6.0
	GameManager.elemental_damage = 5.0
	GameManager.engineering_damage = 4.0
	GameManager.armor = 12.0
	GameManager.harvest = 2.0
	GameManager.attack_speed_mult = 0.9
	GameManager.synergy_haste_mult = 0.95
	GameManager.attack_range_mult = 1.15
	GameManager.synergy_range_mult = 1.1

## 读数出口 vs 测试里独立写出的乘区式子（全库 × 三星）
func _check_factor_chain() -> void:
	var slots := GameManager.slots_used()
	var checked := 0
	for key in WeaponData.DEFS.keys():
		var w_id := String(key)
		var def: Dictionary = WeaponData.get_def(w_id)
		var is_turret := WeaponDamageReadout.is_turret(def)
		for star in range(1, WeaponData.MAX_STAR + 1):
			var expected: float = (WeaponData.damage_for(w_id, star)
					+ GameManager.get_weapon_stat_bonus(w_id, star)) \
					* GameManager.weapon_damage_mult * GameManager.synergy_damage_mult \
					* GameManager.cultivator_damage_mult(w_id) * GameManager.element_damage_mult(w_id) \
					* GameBalance.multi_weapon_damage_mult(slots)
			if is_turret:
				expected *= GameManager.synergy_contraption_mult
			_c.near(WeaponDamageReadout.per_hit(w_id, star), expected, 0.001,
					"【%s ★%d】读数 = 基础+属性加伤 × 全套乘区%s" % [
						w_id, star, "（含机关羁绊）" if is_turret else "（非机关不吃机关羁绊）"])
			checked += 1
	_c.check(checked >= 100, "乘区链逐把对账覆盖 %d 条（全库 × 三星，不是空转）" % checked)

## 读数出口 vs 真武器节点自己算出来的那一刀
func _check_against_real_nodes(world: Node2D) -> void:
	for w_id in NODE_SAMPLE:
		var def: Dictionary = WeaponData.get_def(w_id)
		if def.is_empty():
			_c.check(false, "采样法器【%s】在数据表里存在" % w_id)
			continue
		var is_turret := WeaponDamageReadout.is_turret(def)
		var node: Node
		if is_turret:
			node = (load("res://scenes/weapons/TurretUnit.tscn") as PackedScene).instantiate()
		else:
			node = (load("res://scenes/weapons/FloatingWeapon.tscn") as PackedScene).instantiate()
		node.setup(w_id, 1)
		node.set_process(false)
		world.add_child(node)
		await get_tree().process_frame
		var runtime: float = node._final_damage()
		var readout: float = WeaponDamageReadout.per_hit(w_id, 1)
		_c.near(readout, runtime, 0.001, "【%s】卡面读数 == %s 真实跳字（%.2f）" % [
			w_id, "炮台" if is_turret else "法器本体", runtime])
		node.queue_free()
	await get_tree().process_frame

## 属性加伤账单：逐项之和必须等于总额；系数以前按百分比印会把 max_hp_bonus 0.12 印成「+0%」
func _check_bill_and_text() -> void:
	var hp_bill_found := false
	for key in WeaponData.DEFS.keys():
		var w_id := String(key)
		var def: Dictionary = WeaponData.get_def(w_id)
		var bill := WeaponDamageReadout.bonus_bill(w_id, 1)
		var sum := 0.0
		for r in bill:
			sum += float(r[1])
		var total: float = GameManager.get_weapon_stat_bonus(w_id, 1)
		_c.near(sum, maxf(0.0, total), 0.05, "【%s】账单逐项相加 == 属性加伤总额" % w_id)
		if def.get("stat_scalings", {}).has("max_hp_bonus"):
			hp_bill_found = false
			for r in bill:
				if String(r[0]) == "额外生命" and float(r[1]) > 0.05:
					hp_bill_found = true
	_c.check(hp_bill_found,
			"吃额外生命的法器在账单里给出的是伤害数值，不是旧写法那个四舍五入成「+0%」的系数")
	_c.equals(WeaponDamageReadout.arrow_text(24.0, 24.0), "24",
			"两数相同不画箭头（不承诺一个兑现不了的提升）")
	_c.equals(WeaponDamageReadout.arrow_text(24.0, 34.0), "24 → 34", "两数不同才画箭头")
	var txt := WeaponDamageReadout.bonus_bill_text("chiyan_dao", 1)
	_c.check(txt.contains("多打") and txt.contains("+"),
			"账单整句用人话写多打多少：「%s」" % txt)

## 判据走生产入口：货架卡真的把这两个数印出来了，不是只有 helper 算得对
func _check_card_rows() -> void:
	var data: Dictionary = ShopOfferCardFactory.resolve_offer_data(
			{"kind": "weapon", "id": "qingyun_sword"})
	var rows: Array = data.get("stat_rows", [])
	_c.check(rows.size() >= 3, "货架卡装配出 %d 行加成" % rows.size())
	var dmg_row: Array = rows[0]
	_c.equals(String(dmg_row[0]), "伤害", "首行仍是伤害")
	_c.check(String(dmg_row[1]).contains("→"),
			"首行印成「纸面 → 你现在」两数（实得「%s」）" % String(dmg_row[1]))
	var ps_label := String(rows[1][0])
	# 行名必须自带「伤害」两个字（2026-10-11 用户：光写「每秒」看不懂是什么的每秒）。
	# 这里按后缀拦，不放行旧写法：将来谁再把它缩回「每秒」，这条当场红。
	_c.check(ps_label.ends_with("每秒伤害"),
			"第二行写成每秒伤害（实得「%s」）" % ps_label)
	var turret_label := WeaponDamageReadout.per_second_label("jiguan_nu")
	_c.equals(turret_label, "单座每秒伤害", "炮台类另标「单座」，不与整把法器的每秒伤害混成同一个词")
	for key in WeaponData.DEFS.keys():
		var w_id := String(key)
		var d: Dictionary = ShopOfferCardFactory.resolve_offer_data({"kind": "weapon", "id": w_id})
		var r: Array = d.get("stat_rows", [])
		_c.equals(String(r[0][1]),
				WeaponDamageReadout.arrow_text(WeaponData.damage_for(w_id, 1),
						WeaponDamageReadout.per_hit(w_id, 1,
								WeaponDamageReadout.slot_count_after_purchase())),
				"【%s】卡面伤害行文本与读数出口同源" % w_id)
