class_name PetSystem
extends RefCounted

## 灵兽（随行伙伴）统一管理子系统
## 职责：栏位上限、购买、出售、场上实体增删同步、回合末收益触发。

const SPIRIT_PET_SCENE = preload("res://scenes/entities/SpiritPet.tscn")

## 当前灵兽栏位上限：基础 1 格 + 角色/道具/悟道加成
static func max_pet_slots(gm: Node) -> int:
	var bonus: int = int(gm.get("pet_slots_bonus")) if gm.get("pet_slots_bonus") != null else 0
	return maxi(1, gm.PET_BASE_SLOTS + bonus)

## 是否还能再配置灵兽
static func can_add_pet(gm: Node) -> bool:
	return gm.pets.size() < max_pet_slots(gm)

## 购买/添加灵兽
static func add_pet(gm: Node, pet_id: String) -> bool:
	if not PetData.exists(pet_id):
		return false
	if pet_id in gm.pets:
		# 每种限持一只
		return false
	if not can_add_pet(gm):
		return false
	gm.pets.append(pet_id)
	sync_pet_instances(gm)
	gm.pets_updated.emit(gm.pets)
	return true

## 出售灵兽：回收 50% 金币，场上消散，释放栏位，可再次刷出
static func sell_pet(gm: Node, pet_id: String) -> bool:
	var idx: int = gm.pets.find(pet_id)
	if idx == -1:
		return false
	var refund := PetData.sell_price(pet_id)
	gm.pets.remove_at(idx)
	gm.spirit_stones += refund
	# 销毁场上对应的灵兽实体（播放消散动画）
	var tree := gm.get_tree()
	if tree != null:
		for p in tree.get_nodes_in_group("spirit_pets"):
			if is_instance_valid(p) and p.get("pet_id") == pet_id:
				if p.has_method("dissolve"):
					p.dissolve()
				else:
					p.queue_free()
	sync_pet_instances(gm)
	gm.pets_updated.emit(gm.pets)
	gm.stats_updated.emit(gm.kills, gm.game_time, gm.spirit_stones)
	AudioManager.play_sfx("shop_buy", 1.0)
	return true

## 同步场上灵兽实体与 gm.pets 数据对齐
static func sync_pet_instances(gm: Node) -> void:
	var tree := gm.get_tree()
	if tree == null:
		return
	var player = gm.player
	if player == null or not is_instance_valid(player):
		return
	var host = player.get_parent()
	if host == null:
		return

	var existing: Array = []
	for p in tree.get_nodes_in_group("spirit_pets"):
		if is_instance_valid(p) and p.get("_dying") != true:
			existing.append(p)

	# 1. 移除不在 gm.pets 中的实体
	for p in existing:
		# Fixed: Object.get() 只收一个参数 —— 旧写法 p.get("pet_id", "") 当场抛
		# 「Invalid call to function 'get'」并中断整个 sync，后半段（补生成缺失的那只、
		# 重排环绕序号）永远跑不到：场上已有一只时再买第二只（御兽师 3 格、万兽笼 +1）
		# 只多一条数据，第二只灵兽根本不出现在世界里。
		var pid: Variant = p.get("pet_id")
		var p_id: String = String(pid) if pid != null else ""
		if p_id not in gm.pets:
			if p.has_method("dissolve"):
				p.dissolve()
			else:
				p.queue_free()

	# 2. 重新统计活体，并为缺失的 id 实例化
	var alive_ids: Array = []
	for p in tree.get_nodes_in_group("spirit_pets"):
		if is_instance_valid(p) and p.get("_dying") != true:
			var pid: Variant = p.get("pet_id")
			if pid != null:
				alive_ids.append(String(pid))

	var total: int = gm.pets.size()
	for i in range(total):
		var p_id: String = String(gm.pets[i])
		if p_id not in alive_ids:
			var inst = SPIRIT_PET_SCENE.instantiate() as SpiritPet
			if inst != null:
				inst.setup(p_id, i, total, player as Player)
				host.add_child(inst)
				inst.global_position = player.global_position + Vector2(0, -SpiritPet.HEIGHT_OFFSET)
		else:
			# 更新现有实体的序号与总数（重新分相位）
			for p in tree.get_nodes_in_group("spirit_pets"):
				if is_instance_valid(p) and p.get("pet_id") == p_id:
					p.orbit_index = i
					p.total_pets = total

## 回合末触发灵兽收益（聚宝蟾献金币）
static func on_wave_ended(gm: Node) -> void:
	for pet_id in gm.pets:
		if pet_id == "juchan":
			var stones := BalanceSpiritPet.harvest_stones(gm.wave_number, gm.pet_effect_mult)
			gm.add_spirit_stones(stones)
			AudioManager.play_sfx("chest_open", 0.4, 1.2)
	var tree := gm.get_tree()
	if tree != null:
		for p in tree.get_nodes_in_group("spirit_pets"):
			if is_instance_valid(p) and p.get("pet_id") == "juchan":
				if p.has_method("trigger_wave_harvest_fx"):
					p.trigger_wave_harvest_fx()
				else:
					p.set("_action_fx", 0.0)
