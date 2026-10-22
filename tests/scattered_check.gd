extends Node

## 散修·博采众长 判据（2026-10-22）：
## 走杂才强、凑器类羁绊反而变弱；五行共鸣一律不受影响。
##
## 断言链：
##   ① 单独持有 N 个器类（都未成档）→ 伤害 ×(1 + 0.15N)；
##   ② 某器类凑到 2 件成档 → 该系从「加伤」翻成「惩罚」，且按成档条数各扣 20%；
##   ③ 五行共鸣（金属性 2 件成档）完全不计入：伤害与不带五行时逐位相同；
##   ④ 六系全部成档 → 惩罚叠加到下限钳 0.2，伤害不为负、不为零；
##   ⑤ 非散修角色（scattered_mode=0）不产生任何影响（回归旧口径）；
##   ⑥ 解锁成就 ach_cult_sanxiu：4 种器类真、3 种假；进度短句同步。
##
## 运行: godot --headless --path . res://tests/ScatteredCheck.tscn
## 反例（判据的牙齿）：
##   ① 把 WeaponData.CLASSES 换成 WeaponData.ELEMENTS ⇒ ③ 报红；
##   ② 去掉 maxf(0.2, ...) 下限 ⇒ ④ 报红；
##   ③ 把 level>=1 判定改成 count>=1 ⇒ ② 不翻惩罚、① 的加伤条数报红。

var _c := TestCheck.new()
var _enabled_once := false

## 参考武器：qingyun_sword = ["sword","metal"]，最干净的剑系样本
const SWORD_ID := "qingyun_sword"

func _ready() -> void:
	GameManager.reset_run()
	_c.set_min_checks(18)
	_test_solo_bonus()
	_test_synergy_penalty()
	_test_element_ignored()
	_test_floor_clamp()
	_test_non_scattered_noop()
	_test_unlock_achievement()
	_test_data_and_visual_wiring()
	var ok := _c.report("SCATTERED_RESULT")
	get_tree().quit(0 if ok else 1)

## 铺一份「tag → {count, level}」的羁绊快照，口径与 SynergySystem.apply_counts 一致：
## 只有实际持有的 tag 才进 active_synergies；成档（>=2 件）level 至少 1。
func _set_counts(counts: Dictionary) -> void:
	GameManager.active_synergies = {}
	for tag in counts:
		var n := int(counts[tag])
		if n <= 0:
			continue
		var info: Dictionary = WeaponData.SYNERGIES.get(String(tag), {})
		var lv := GameBalance.synergy_level(n, info.get("thresholds", []), 0) if not info.is_empty() else 0
		GameManager.active_synergies[String(tag)] = {"count": n, "level": lv}

func _enable_scattered() -> void:
	if not _enabled_once:
		_enabled_once = true
		var def := CultivatorData.get_def("sanxiu")
		_c.check(not def.is_empty(), "散修条目已登记进 CultivatorData.DEFS")
		GameManager.cultivator_id = "sanxiu"
		GameManager.scattered_mode = float(def.get("mods", {}).get("scattered_mode", 0.0))
		GameManager.scattered_bonus_per_class = float(def.get("mods", {}).get("scattered_bonus_per_class", 0.0))
		GameManager.scattered_penalty_per_synergy = float(def.get("mods", {}).get("scattered_penalty_per_synergy", 0.0))

## ① 单独持有：每系 +15%
func _test_solo_bonus() -> void:
	_enable_scattered()
	_c.near(GameManager.scattered_bonus_per_class, 0.15, 0.0001, "散修走杂加成幅度 = +15%/系")
	_c.near(GameManager.scattered_penalty_per_synergy, -0.20, 0.0001, "散修成档惩罚幅度 = -20%/条")

	_set_counts({"sword": 1})
	_c.near(GameManager.cultivator_damage_mult(SWORD_ID), 1.15, 0.0001, "1 系单独持有 → ×1.15")
	_set_counts({"sword": 1, "talisman": 1, "wide": 1})
	_c.near(GameManager.cultivator_damage_mult(SWORD_ID), 1.45, 0.0001, "3 系单独持有 → ×1.45")
	_set_counts({"sword": 1, "talisman": 1, "wide": 1, "thunder": 1, "spirit": 1, "contraption": 1})
	_c.near(GameManager.cultivator_damage_mult(SWORD_ID), 1.90, 0.0001, "6 系全杂 → ×1.90（满槽走杂）")

## ② 凑羁绊：该系翻成惩罚
func _test_synergy_penalty() -> void:
	_enable_scattered()
	# 4 杂 + 1 条成档 = 1 + 0.15×4 − 0.20 = 1.40
	_set_counts({"sword": 2, "talisman": 1, "wide": 1, "thunder": 1, "spirit": 1})
	_c.near(GameManager.cultivator_damage_mult(SWORD_ID), 1.40, 0.0001, "4 杂 + 1 条器类羁绊 → ×1.40")
	# 1 系 2 件成档（无其它系）：0 单独 + 1 条惩罚 = 0.80
	_set_counts({"sword": 2})
	_c.near(GameManager.cultivator_damage_mult(SWORD_ID), 0.80, 0.0001, "纯 2 剑（成档）→ ×0.80")
	# 成档后件数继续涨（4 件）仍是 1 条，不重复扣
	_set_counts({"sword": 4})
	_c.near(GameManager.cultivator_damage_mult(SWORD_ID), 0.80, 0.0001, "同系堆到 4 件仍只算 1 条羁绊（不重复扣）")

## ③ 五行共鸣不计：金属性 2 件成档不产生任何变化
func _test_element_ignored() -> void:
	_enable_scattered()
	_set_counts({"sword": 1, "metal": 1})
	var base := GameManager.cultivator_damage_mult(SWORD_ID)
	_set_counts({"sword": 1, "metal": 2})
	_c.near(GameManager.cultivator_damage_mult(SWORD_ID), base, 0.0001, "金系共鸣成档不改变伤害（五行不计）")
	_set_counts({"sword": 1, "metal": 2, "wood": 2, "water": 2, "fire": 2, "earth": 2})
	_c.near(GameManager.cultivator_damage_mult(SWORD_ID), base, 0.0001, "五行全成档也不改变伤害（五行不计）")

## ④ 下限钳：六系全成档
func _test_floor_clamp() -> void:
	_enable_scattered()
	_set_counts({"sword": 2, "talisman": 2, "wide": 2, "thunder": 2, "spirit": 2, "contraption": 2})
	# 1 − 0.20×6 = −0.2 → 钳到 0.2
	_c.near(GameManager.cultivator_damage_mult(SWORD_ID), 0.2, 0.0001, "六系全成档 → 钳到下限 ×0.2（伤害不为负）")

## ⑤ 非散修不受影响
func _test_non_scattered_noop() -> void:
	GameManager.reset_run()
	GameManager.cultivator_id = ""
	_set_counts({"sword": 2})
	_c.near(GameManager.cultivator_damage_mult(SWORD_ID), 1.0, 0.0001, "非散修：成档不产生惩罚（回归旧口径）")
	_set_counts({"sword": 1})
	_c.near(GameManager.cultivator_damage_mult(SWORD_ID), 1.0, 0.0001, "非散修：单独持有也不加伤")

## ⑥ 解锁成就
func _test_unlock_achievement() -> void:
	var four := {"sword": 1, "talisman": 1, "wide": 1, "thunder": 1}
	var three := {"sword": 1, "talisman": 1, "wide": 1}
	var ctx_four := {"max_class_counts": four}
	var ctx_three := {"max_class_counts": three}
	_c.check(AchievementData.is_condition_met("ach_cult_sanxiu", ctx_four, {}), "成就：4 种器类 → 解锁散修")
	_c.check(not AchievementData.is_condition_met("ach_cult_sanxiu", ctx_three, {}), "成就：3 种器类 → 不解锁")
	var ach := AchievementData.get_def("ach_cult_sanxiu")
	_c.equals(ach.get("reward_id", ""), "sanxiu", "成就奖励指向散修")
	_c.check(String(AchievementData.progress_text("ach_cult_sanxiu", {"best_class_counts": four})).contains("4/4"), "进度短句报 4/4 系")

## ⑦ 数据与形象接线
func _test_data_and_visual_wiring() -> void:
	_c.check(CultivatorData.all_ids().has("sanxiu"), "散修已进 all_ids（选人/图鉴自动收录）")
	_c.check(CultivatorData.item_tags_of("sanxiu").size() > 0, "散修有道具软亲和标签")
	var cfg := CultivatorVisualConfig.get_config("sanxiu")
	_c.equals(cfg.weapon.get("weapon_type", ""), "assorted_bundle", "散修背负一捆杂兵器（独立 weapon_type）")
