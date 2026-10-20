class_name BalanceBuildFilter
extends RefCounted

## 构筑感知过滤（2026-10-20）：把「对当前构筑完全无效」的条件型加点/道具从候选池里挑出去，
## 让 5 张悟道卡、货架道具真正都是能点的。
##
## 用户口径：「值得选的东西太少」+「加拾取范围、加击退这种不管玩什么流派都没用的」。
## 前者一半是「废卡占位」造成的 —— 玩剑系时还刷召唤/机关/单元素/灵兽/寻宝的卡。
## 本模块只做「要不要把它刷给你」这一个判断，不删内容、不改数值。
##
## 纯静态、只读 WeaponData 与传入的 gm 字段；gm 为空（单测纯池）时一律放行 = 原行为。
## 兜底：调用方在过滤后候选不足时回退到未过滤池，绝不让候选/货架变少。

## 伤害类别加点/道具 → 武器 stat_scalings 里对应键
const CATEGORY_KEYS := {
	"melee": "melee_damage",
	"ranged": "ranged_damage",
	"elemental": "elemental_damage",
	"engineering": "engineering_damage",
	"contraption": "contraption_damage",
}

## 加点 id → 需要的伤害类别；不在此表的加点恒为通用项
const UPGRADE_CATEGORY := {
	"melee_up": "melee", "grand_melee": "melee",
	"ranged_up": "ranged", "grand_ranged": "ranged",
	"elemental_up": "elemental", "grand_elemental": "elemental",
	"engineering_up": "engineering", "grand_engineering": "engineering",
	"contraption_up": "contraption",
}

## 加点 id → 需要的五行
const UPGRADE_ELEMENT := {
	"metal_up": "metal", "wood_up": "wood", "water_up": "water",
	"fire_up": "fire", "earth_up": "earth",
}

## 灵兽 / 寻宝条件的加点 id 前缀（pet_ 单独按 has_pets 判，chest_ 按寻宝流判）
const CHEST_UPGRADE_PREFIX := "chest_"

## 道具里认定「纯某类别」的字段集合：只有整件道具的 apply + hook 全落在一个条件桶里才过滤，
## 带生命/移速等通用收益的混装件（如聚灵阵图）永远放行，避免误伤。
const PET_ITEM_KEYS := [
	"pet_damage_mult", "pet_effect_mult", "pet_cooldown_mult_mul", "pet_slots",
]
const CHEST_ITEM_KEYS := ["chest_count", "chest_quality", "chest_reward"]

## 当前持有武器 id（上阵悬浮武器 + 环绕灵宝 + 背包备选）。
## 背包也算持有：手里攥着剑，就该刷近战卡；否则玩家「有剑却抽不到近战强化」。
static func weapon_ids(gm: Node) -> Array:
	var out: Array = []
	if gm == null:
		return out
	if gm.player != null and is_instance_valid(gm.player) and gm.player.has_method("get_equipped_weapons_data"):
		for w in gm.player.get_equipped_weapons_data():
			out.append(String(w.get("id", "")))
	for d in gm.get("drones"):
		out.append(WeaponInventory.drone_id(d))
	for s in gm.get("stash"):
		if s is Dictionary:
			out.append(String(s.get("id", "")))
	return out

## 上阵武器里存在吃某伤害类别（stat_scalings 对应键 > 0）的武器
static func has_category(gm: Node, category: String) -> bool:
	var key := String(CATEGORY_KEYS.get(category, ""))
	if key.is_empty():
		return true
	for wid in weapon_ids(gm):
		var scal: Dictionary = WeaponData.get_def(String(wid)).get("stat_scalings", {})
		if float(scal.get(key, 0.0)) > 0.0:
			return true
	return false

## 上阵武器里存在某五行的武器
static func has_element(gm: Node, elem: String) -> bool:
	for wid in weapon_ids(gm):
		if WeaponData.element_of(String(wid)) == elem:
			return true
	return false

static func has_any_pet(gm: Node) -> bool:
	if gm == null:
		return false
	return not gm.get("pets").is_empty() or String(gm.get("cultivator_id")) == "yushou"

## 是否已走寻宝流：点过任一宝箱加点，或持有任一宝箱道具，或宝箱属性已被抬起
static func has_chest_build(gm: Node) -> bool:
	if gm == null:
		return false
	if float(gm.get("chest_count_bonus")) > 0.0 or float(gm.get("chest_quality")) > 0.0 \
			or float(gm.get("chest_reward_mult")) > 1.0:
		return true
	var counts: Dictionary = gm.get("upgrade_counts")
	for uid in counts.keys():
		if String(uid).begins_with(CHEST_UPGRADE_PREFIX) and int(counts[uid]) > 0:
			return true
	for iid in gm.get("items"):
		var d: Dictionary = ItemData.get_def(String(iid))
		for k in CHEST_ITEM_KEYS:
			if d.has(k):
				return true
		if bool(d.get("chest_magnet", false)):
			return true
	return false

## 某条悟道加点当前是否该刷出（true = 放行）
static func upgrade_allowed(gm: Node, uid: String) -> bool:
	if gm == null:
		return true
	if UPGRADE_CATEGORY.has(uid):
		return has_category(gm, String(UPGRADE_CATEGORY[uid]))
	if UPGRADE_ELEMENT.has(uid):
		return has_element(gm, String(UPGRADE_ELEMENT[uid]))
	if uid.begins_with("pet_"):
		return has_any_pet(gm)
	if uid.begins_with(CHEST_UPGRADE_PREFIX):
		return has_chest_build(gm)
	return true

## 某件道具当前是否该刷新。只过滤「纯条件件」，混装件一律放行。
static func item_allowed(gm: Node, id: String) -> bool:
	if gm == null:
		return true
	var d: Dictionary = ItemData.get_def(id)
	if d.is_empty():
		return true
	var keys: Array = []
	for k in (d.get("apply", {}) as Dictionary).keys():
		keys.append(String(k))
	# hook 字段同样计入（如 pet 类走额外字段的情形）
	for k in ["still_regen_pct", "still_dodge", "still_armor", "still_attack_speed",
			"still_damage", "kill_explode"]:
		if d.has(k):
			keys.append(String(k))
	if keys.is_empty():
		return true

	# 单一五行纯件
	var only_elem := ""
	var all_elem := true
	for k in keys:
		if k.begins_with("element_damage_") and k != "element_damage_all":
			var e: String = String(k).trim_prefix("element_damage_")
			if only_elem == "":
				only_elem = e
			elif only_elem != e:
				all_elem = false
		else:
			all_elem = false
	if all_elem and only_elem != "":
		return has_element(gm, only_elem)

	# 单一伤害类别纯件
	var only_cat := ""
	var all_cat := true
	for k in keys:
		var hit := ""
		for cat in CATEGORY_KEYS.keys():
			if String(CATEGORY_KEYS[cat]) == k:
				hit = String(cat)
				break
		if hit == "":
			all_cat = false
			break
		if only_cat == "":
			only_cat = hit
		elif only_cat != hit:
			all_cat = false
			break
	if all_cat and only_cat != "":
		return has_category(gm, only_cat)

	# 纯灵兽件
	var all_pet := true
	for k in keys:
		if not (k in PET_ITEM_KEYS):
			all_pet = false
			break
	if all_pet:
		return has_any_pet(gm)

	# 纯寻宝件
	var all_chest := true
	for k in keys:
		if not (k in CHEST_ITEM_KEYS):
			all_chest = false
			break
	if all_chest:
		return has_chest_build(gm)

	return true
