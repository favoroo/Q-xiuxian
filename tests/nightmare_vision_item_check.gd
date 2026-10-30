extends Node

## 噩梦视野件判据（2026-10-30）：
##   ① 数据口径：三件都在道具表、都标 nightmare_only + unique、都进初始解锁池且可上架
##   ② 抽池硬闸：普通难度（danger_level = 0）抽 2000 次零命中 —— 抽池兜底的未过滤全池也不放行；
##      噩梦难度（danger_level = 1）同一颗种子能抽到三件（×3 权重把「几乎刷不到」拉到可遇见）
##   ③ 属性链路：买入 +15%/+25%/+40% 加算、unique 限购一件、卖掉原样退回
##   ④ 定价：与普通道具同一条 item_price（基准价 + 每回合 +2）
## 运行: $G --headless --path . res://tests/NightmareVisionItemCheck.tscn
## 退出码 0 且末行 NIGHTMARE_VISION_RESULT: ALL PASS

const VISION_IDS: Array[String] = ["yinlu_deng", "powu_deng", "qianli_yan"]
const EPS := 0.0001
const ROLLS_NORMAL := 2000
const ROLLS_NIGHTMARE := 3000

var _c := TestCheck.new()


func _ready() -> void:
	_c.set_min_checks(16)
	call_deferred("_run")


func _run() -> void:
	GameManager.author_mode = true  # 不写生涯统计/成就
	GameManager.reset_run()

	# ① 数据口径
	var bad_flags: Array[String] = []
	var missing_pool: Array[String] = []
	for id in VISION_IDS:
		var def := ItemData.get_def(id)
		if not ItemData.is_nightmare_only(String(id)) or not bool(def.get("unique", false)):
			bad_flags.append(String(id))
		if not (String(id) in AchievementData.DEFAULT_ITEMS):
			missing_pool.append(String(id))
	_c.check(bad_flags.is_empty(), "三件都标了 nightmare_only + unique（缺：%s）" % str(bad_flags))
	_c.check(missing_pool.is_empty(), "三件都在初始解锁池 DEFAULT_ITEMS（缺：%s）" % str(missing_pool))
	_c.check(not ItemData.is_nightmare_only("jubaopen"), "普通道具不带 nightmare_only 标记")
	_c.check(GameBalance.upgrade_fields().has("fog_vision_bonus"), "fog_vision_bonus 在加点字段白名单里")

	# ② 抽池硬闸
	GameManager.danger_level = 0
	var seen_normal := _sweep(ROLLS_NORMAL)
	_c.check(seen_normal.is_empty(), "普通难度抽 %d 次零命中视野件（实得 %s）" % [ROLLS_NORMAL, str(seen_normal)])
	GameManager.danger_level = 1
	var seen_night := _sweep(ROLLS_NIGHTMARE)
	_c.check(seen_night.size() == VISION_IDS.size(),
		"噩梦难度抽 %d 次三件都抽得到（实得 %s）" % [ROLLS_NIGHTMARE, str(seen_night)])

	# ③ 属性链路
	_c.check(GameManager.add_item("yinlu_deng"), "引路灯买得进")
	_c.near(GameManager.fog_vision_bonus, 0.15, EPS, "引路灯落地 +15% 迷雾视野")
	_c.check(not GameManager.add_item("yinlu_deng"), "unique：同一件买不进第二次")
	_c.near(GameManager.fog_vision_bonus, 0.15, EPS, "重复购买不叠第二份")
	_c.check(GameManager.add_item("powu_deng") and GameManager.add_item("qianli_yan"), "破雾灯/千里眼买得进")
	_c.near(GameManager.fog_vision_bonus, 0.80, EPS, "三件叠满 +80%")
	_c.near(GameBalance.nightmare_fog_clear_radius(GameManager.fog_vision_bonus), 360.0, EPS,
			"满配清晰半径 360px")
	_c.check(GameManager.sell_item("qianli_yan"), "千里眼卖得掉")
	_c.near(GameManager.fog_vision_bonus, 0.40, EPS, "卖出退回 +40%，剩 0.4")

	# ④ 定价
	_c.equals(GameBalance.item_price(42, 5, 1.0), 50, "破雾灯第 5 波价 = 42 + 4×2")

	GameManager.author_mode = false
	_finish()


## 用固定种子扫一遍道具抽池，返回命中的视野件 id（去重、按首次出现序）
func _sweep(rolls: int) -> Array[String]:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261030
	var seen: Array[String] = []
	for i in range(rolls):
		var id := ItemData.pick_id(50.0, 20, [], rng, [], GameManager)
		if id in VISION_IDS and not (id in seen):
			seen.append(id)
	return seen


func _finish() -> void:
	if not _c.report("NIGHTMARE_VISION_RESULT"):
		get_tree().quit(1)
	else:
		get_tree().quit(0)