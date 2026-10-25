extends Node

## 构筑感知降噪判据（2026-10-20）：验证 BalanceBuildFilter 把「对当前构筑无效」的条件型
## 加点/道具拦在候选池外，且兜底不会把池子榨干。
## 2026-10-24：宝箱系加点/道具（经济件，匣子对全流派有效）解除「寻宝流已入场」硬闸——
## 唯一入场券纳灵盘下架后旧闸死锁，宝箱卡自己拦自己，寻宝流永远刷不出来。
##
## 运行: godot --headless --path . res://tests/BuildFilterCheck.tscn
##       godot --headless --path . res://tests/BuildFilterCheck.tscn -- --selftest

var _c := TestCheck.new()

func _check(cond: bool, label: String) -> void:
	_c.check(cond, label)

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	# ---- 1. 纯剑系玩家：召唤/机关/单元素真解/灵兽 不进池；宝箱系经济件放行 ----
	GameManager.reset_run()
	GameManager.cultivator_id = "jianchi"
	GameManager.stash = [{"id": "qingyun_sword", "star": 1}]
	_c.check(BalanceBuildFilter.upgrade_allowed(GameManager, "melee_up"), "剑系：近战强化放行")
	_c.check(not BalanceBuildFilter.upgrade_allowed(GameManager, "engineering_up"), "剑系：召唤强化被拦")
	_c.check(not BalanceBuildFilter.upgrade_allowed(GameManager, "contraption_up"), "剑系：机关强化被拦")
	_c.check(not BalanceBuildFilter.upgrade_allowed(GameManager, "fire_up"), "剑系：离火真解被拦（无火系武器）")
	_c.check(not BalanceBuildFilter.upgrade_allowed(GameManager, "pet_damage_up"), "剑系：灵兽淬炼被拦（无灵兽）")
	_c.check(BalanceBuildFilter.upgrade_allowed(GameManager, "chest_count_up"), "剑系：宝箱数量放行（经济件不设闸）")
	_c.check(BalanceBuildFilter.upgrade_allowed(GameManager, "atk_up"), "剑系：通用武器强化放行")

	# ---- 2. 出 5 张候选时，剑系玩家不再看到召唤/机关/单元素卡 ----
	GameManager.reset_run()
	GameManager.cultivator_id = "jianchi"
	GameManager.stash = [{"id": "qingyun_sword", "star": 1}]
	GameManager.rng.seed = 20261020
	var seen_forbidden := 0
	for i in range(60):
		for u in GameManager.roll_upgrades():
			var uid := String(u.get("id", ""))
			# 长剑是金系，故锐金真解(metal_up)合法放行，不列入禁用项
			if uid in ["engineering_up", "contraption_up", "wood_up",
					"water_up", "fire_up", "earth_up", "pet_damage_up"]:
				seen_forbidden += 1
	_c.equals(seen_forbidden, 0, "剑系玩家 60 屏候选里 0 张条件型死卡")

	# ---- 3. 纯召唤玩家：召唤/机关强化放行，近战强化视武器而定 ----
	GameManager.reset_run()
	GameManager.cultivator_id = "fuzhen"
	GameManager.drones = [{"id": "lingdie", "star": 1}]
	_c.check(BalanceBuildFilter.upgrade_allowed(GameManager, "engineering_up"), "召唤流：召唤强化放行")
	_c.check(not BalanceBuildFilter.upgrade_allowed(GameManager, "contraption_up"), "召唤流：机关强化仍被拦")

	# ---- 4. 兜底：过滤后候选不足时回退到未过滤池，绝不让候选少于 requested ----
	GameManager.reset_run()
	GameManager.cultivator_id = "jianchi"
	GameManager.stash = [{"id": "qingyun_sword", "star": 1}]
	GameManager.rng.seed = 7
	var got := UpgradeData.get_random_upgrades(5, {
		"luck": 0.0, "wave": 20, "locked_upgrades": [], "counts": {},
		"rng": GameManager.rng, "has_pets": false, "gm": GameManager,
	})
	_c.equals(got.size(), 5, "过滤后候选仍能抽满 5 张（兜底生效）")

	# ---- 5. 道具：纯单元素道具按构筑过滤，混装件放行 ----
	GameManager.reset_run()
	GameManager.cultivator_id = "jianchi"
	GameManager.stash = [{"id": "qingyun_sword", "star": 1}]
	_c.check(not BalanceBuildFilter.item_allowed(GameManager, "dihuo_jing"), "剑系：纯火系道具（地火精）被拦")
	_c.check(BalanceBuildFilter.item_allowed(GameManager, "juling_zhentu"), "混装件（聚灵阵图带生命）放行")
	_c.check(BalanceBuildFilter.item_allowed(GameManager, "xuantie_ling"), "通用强力件（玄铁令）放行")
	_c.check(not BalanceBuildFilter.item_allowed(GameManager, "luban_suo"), "剑系：纯机关道具（鲁班锁）被拦")

	# ---- 6. 宝箱系是经济件：不设构筑闸，剑系开局也能刷到宝箱加点与藏宝图/点金诀 ----
	GameManager.reset_run()
	GameManager.cultivator_id = "jianchi"
	GameManager.stash = [{"id": "qingyun_sword", "star": 1}]
	_c.check(BalanceBuildFilter.upgrade_allowed(GameManager, "chest_quality_up"), "未寻宝：宝箱品质放行（经济件）")
	_c.check(BalanceBuildFilter.upgrade_allowed(GameManager, "chest_reward_up"), "未寻宝：宝箱掉落放行（经济件）")
	_c.check(BalanceBuildFilter.item_allowed(GameManager, "cangbao_tu"), "剑系：藏宝图放行（经济件）")
	_c.check(BalanceBuildFilter.item_allowed(GameManager, "dianjin_jue"), "剑系：点金诀放行（经济件）")

	GameManager.reset_run()
	get_tree().quit(0 if _c.report("BUILDFILTER_RESULT") else 1)
