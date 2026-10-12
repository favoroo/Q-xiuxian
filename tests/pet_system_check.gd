extends Node

## 灵兽系统专项测试（PetSystemCheck）
## 覆盖：定义完整性、栏位上限（普通 1 / 御兽师 3）、购买排重、出售回笼、敌弹拦截、经济产出、RunReset 清空。

const EPS := 0.001

func _ready() -> void:
	print("========================================")
	print("       灵兽系统（PetSystem）专项判据")
	print("========================================")
	var all_ok := true

	all_ok = all_ok and _test_pet_data_definitions()
	all_ok = all_ok and _test_pet_slots_and_adding()
	all_ok = all_ok and _test_pet_selling()
	all_ok = all_ok and _test_bolt_interception()
	all_ok = all_ok and _test_wave_harvest_economy()
	all_ok = all_ok and _test_run_reset_cleanup()

	print("========================================")
	if all_ok:
		print("PET_SYSTEM_CHECK_RESULT: ALL PASS")
		get_tree().quit(0)
	else:
		push_error("PET_SYSTEM_CHECK_RESULT: FAILED")
		get_tree().quit(1)

func _test_pet_data_definitions() -> bool:
	print("\n--- 1. 测试 PetData 定义完整性 ---")
	var ids := PetData.all_ids()
	if ids.size() < 7:
		push_error("灵兽种类少于 7 种，当前: %d" % ids.size())
		return false
	var required_keys := ["id", "name", "role", "base_price", "base_cooldown", "base_value", "desc", "color", "halo_color", "decor"]
	for pid in ids:
		var def := PetData.get_def(pid)
		for k in required_keys:
			if not def.has(k):
				push_error("灵兽 %s 缺失字段: %s" % [pid, k])
				return false
		if int(def["base_price"]) <= 0:
			push_error("灵兽 %s 基准价格非法: %s" % [pid, def["base_price"]])
			return false
		if PetData.sell_price(pid) <= 0:
			push_error("灵兽 %s 出售价格非法: %s" % [pid, PetData.sell_price(pid)])
			return false
	print("[OK] 7 种灵兽定义完整有效")
	return true

func _test_pet_slots_and_adding() -> bool:
	print("\n--- 2. 测试栏位上限与添加规则 ---")
	GameManager.reset_run()

	# 普通角色基础栏位为 1
	var normal_slots := PetSystem.max_pet_slots(GameManager)
	if normal_slots != 1:
		push_error("普通角色基础栏位应为 1，实测: %d" % normal_slots)
		return false

	# 成功购买第 1 只
	var ok1 := GameManager.add_pet("yanhu")
	if not ok1 or GameManager.pets.size() != 1:
		push_error("购买第 1 只灵兽失败")
		return false

	# 重复添加同种灵兽应被拒绝
	var ok_dup := GameManager.add_pet("yanhu")
	if ok_dup:
		push_error("重复购买已拥有的灵兽未被拒绝")
		return false

	# 普通角色未扩容前，购买第 2 只应被拒绝
	var ok2 := GameManager.add_pet("leique")
	if ok2 or GameManager.pets.size() != 1:
		push_error("超额购买灵兽未被拒绝")
		return false

	# 模拟御兽师特性加成（pet_slots_bonus = 2，上限变为 3）
	GameManager.pet_slots_bonus = 2
	var tamer_slots := PetSystem.max_pet_slots(GameManager)
	if tamer_slots != 3:
		push_error("御兽师灵兽栏位应为 3，实测: %d" % tamer_slots)
		return false

	var ok3 := GameManager.add_pet("leique")
	var ok4 := GameManager.add_pet("xuangui")
	if not ok3 or not ok4 or GameManager.pets.size() != 3:
		push_error("御兽师配置满 3 只灵兽失败，实测: %d" % GameManager.pets.size())
		return false

	# 满 3 只后再买第 4 只应被拒绝
	var ok5 := GameManager.add_pet("yulu")
	if ok5 or GameManager.pets.size() != 3:
		push_error("御兽师超额配置灵兽未被拒绝")
		return false

	print("[OK] 栏位限制（普通 1 / 御兽师 3）与排重逻辑正确")
	return true

func _test_pet_selling() -> bool:
	print("\n--- 3. 测试出售灵兽与回笼 ---")
	var stones_before: int = GameManager.spirit_stones
	var refund_expected := PetData.sell_price("yanhu")

	var ok_sell := GameManager.sell_pet("yanhu")
	if not ok_sell:
		push_error("出售灵兽失败")
		return false

	if "yanhu" in GameManager.pets:
		push_error("出售后灵兽未从持有列表中移除")
		return false

	if GameManager.spirit_stones != stones_before + refund_expected:
		push_error("出售返还灵石不符，期望: %d, 实际: %d" % [stones_before + refund_expected, GameManager.spirit_stones])
		return false

	# 出售之后，该灵兽重新可被购买（回笼）
	var ok_rebuy := GameManager.add_pet("yanhu")
	if not ok_rebuy:
		push_error("出售后重新购买该灵兽失败")
		return false

	print("[OK] 出售返款 50%、栏位释放与回笼可购正确")
	return true

func _test_bolt_interception() -> bool:
	print("\n--- 4. 测试敌弹拦截功能 ---")
	var bolt := EnemyBolt.acquire(self)
	bolt.activate()
	if not bolt.is_in_group("enemy_bolts"):
		push_error("EnemyBolt 未能加入 enemy_bolts 组")
		return false
	if not bolt.has_method("intercept"):
		push_error("EnemyBolt 缺失 intercept 方法")
		return false
	bolt.intercept()
	if bolt.get("_pooled") != true:
		push_error("EnemyBolt 调用 intercept 后未正常回池")
		return false
	print("[OK] 敌方火球组标记与拦截回池接口正确")
	return true

func _test_wave_harvest_economy() -> bool:
	print("\n--- 5. 测试聚宝蟾波末经济产出 ---")
	GameManager.reset_run()
	GameManager.wave_number = 5
	GameManager.add_pet("juchan")
	var stones_before := GameManager.spirit_stones

	# 触发波末
	PetSystem.on_wave_ended(GameManager)
	var stones_gained := GameManager.spirit_stones - stones_before
	var expected := BalanceSpiritPet.harvest_stones(5, GameManager.pet_effect_mult)
	if stones_gained != expected or stones_gained <= 0:
		push_error("聚宝蟾波末产出不符，期望: %d, 实际: %d" % [expected, stones_gained])
		return false
	print("[OK] 聚宝蟾波末成长产出灵石成功 (+%d 金币)" % stones_gained)
	return true

func _test_run_reset_cleanup() -> bool:
	print("\n--- 6. 测试 RunReset 清空灵兽状态 ---")
	GameManager.add_pet("yulu")
	GameManager.pet_slots_bonus = 2
	GameManager.pet_damage_mult = 1.45
	GameManager.pet_effect_mult = 1.30
	GameManager.pet_cooldown_mult = 0.8
	GameManager.pet_offer_chance_bonus = 0.15

	GameManager.reset_run()
	if not GameManager.pets.is_empty():
		push_error("reset_run 未清空 pets")
		return false
	if GameManager.pet_slots_bonus != 0:
		push_error("reset_run 未重置 pet_slots_bonus")
		return false
	if absf(GameManager.pet_damage_mult - 1.0) > EPS:
		push_error("reset_run 未重置 pet_damage_mult")
		return false
	if absf(GameManager.pet_effect_mult - 1.0) > EPS:
		push_error("reset_run 未重置 pet_effect_mult")
		return false
	if absf(GameManager.pet_cooldown_mult - 1.0) > EPS:
		push_error("reset_run 未重置 pet_cooldown_mult")
		return false
	if absf(GameManager.pet_offer_chance_bonus - 0.0) > EPS:
		push_error("reset_run 未重置 pet_offer_chance_bonus")
		return false
	print("[OK] RunReset 全量恢复默认值成功")
	return true
