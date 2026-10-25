extends Node

## 三合一合成在真实灵石阁里的端到端判据（MergeFx 接线层，Mock 场景由 MergeFxCheck 管）：
##   ① 点陈列行第 0 格开详情卡 → 按「三合一」后，演出层的两枚飞行体必须从被消耗的
##      那两个原有格子起飞（详情卡 close 会先重建陈列行，接线若抓错节点/抓到没排布局的
##      新节点，这里直接打红）；
##   ② 迸发帧（~0.21s）合成真的落地：2 星 +1、1 星清零；
##   ③ 尾段演完演出层自毁，商店还能正常操作；
##   ④ 分档（2026-10-25）：★2→★3「觉醒」同一条生产链走慢节奏 —— 蓄力层在场、
##      蓄力期数据不落地、0.61s 迸发帧 ★3 +1 / ★2 清零、「★★★」星章在场、按时自毁。
## 运行: $G --headless --path . res://tests/MergeFlowCheck.tscn

const W := "qingyun_sword"

var _c := TestCheck.new()
var _main: Node
var _shop: WaveShop

func _ready() -> void:
	get_tree().root.size = Vector2i(960, 540)
	call_deferred("_run")

func _frame(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func _run() -> void:
	_main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(_main)
	await _frame(3)
	GameManager.cultivator_id = ""
	GameManager.start_run(W)
	get_tree().paused = false
	GameManager.add_weapon(W)
	GameManager.add_weapon(W)
	await _frame(2)
	_shop = _main.get_node_or_null("UILayer/WaveShop") as WaveShop
	_c.check(_shop != null, "Main 里有灵石阁节点")
	if _shop == null:
		_done()
		return
	_quiet_arena()
	_shop._on_shop_opened()
	# 判据直接开店，绕过了回合流程 ⇒ 货架是空的；补一次 roll 才有「合成时货架不该重建」的对照
	GameManager.roll_shop(false)
	_shop.refresh(false)
	# 等真实时间：行是重建出来的，headless 一帧不到 1ms，等帧数量到的是还没摆位的矩形
	await get_tree().create_timer(0.8).timeout
	await _frame(2)

	_c.check(GameManager.count_copies(W, 1) >= 3,
			"手里凑齐 3 把同名 1 星（实得 %d）" % GameManager.count_copies(W, 1))
	# 合成只该重铺陈列行：货架 5 张大卡与报价都是原账。逮住第一张大卡的实例，
	# 迸发后它还必须活着 —— 旧写法在爆点调 refresh(false) 会把它 queue_free 掉，
	# 那笔重建开销正是合成动画顿一下的来源
	var offer0: Control = null
	if _shop.offers_container.get_child_count() > 0:
		offer0 = _shop.offers_container.get_child(0) as Control
	_c.check(offer0 != null, "货架第一张大卡在场（对照用）")
	# keeper 选第 3 格（index 2）：两件被消耗的前面两格，重建后 keeper 向左补两格 ——
	# 正好压住「结果图标要滑行跟到格子新位置」这条收尾
	var slot0 := _slot_node("equipped", 0)
	var slot1 := _slot_node("equipped", 1)
	var slot2 := _slot_node("equipped", 2)
	_c.check(slot0 != null and slot1 != null and slot2 != null, "陈列行里找得到三个格位节点")
	if slot0 == null or slot1 == null or slot2 == null:
		_done()
		return
	var summary: Array = GameManager.get_weapons_summary()
	var item2: Dictionary = summary[2]
	_c.equals(String(item2.get("id", "")), W, "第 2 格就是这把长剑")

	# 走生产入口：选中 → 开详情卡 → 从 payload 拿「三合一」那颗键的回调
	_shop.selected = {"pool": "equipped", "index": 2}
	ShopWeaponTip.open(_shop, item2, "equipped", 2, slot2)
	var tip := DetailTip.live(_shop)
	_c.check(tip != null, "点开后武器详情卡在场")
	if tip == null:
		_done()
		return
	var acts: Array = tip.payload.get("actions", [])
	# actions 是多行：[[三合一], [卸装/装备, 出售]] —— 按文字找到那颗键，不赌行号
	var merge_cb := Callable()
	for row in acts:
		for act in (row as Array):
			var d: Dictionary = act
			if String(d.get("text", "")).contains("三合一"):
				merge_cb = d.get("callback", Callable())
	_c.check(merge_cb.is_valid(), "详情卡里有三合一回调")
	if not merge_cb.is_valid():
		_done()
		return

	# 先记下两个被消耗格子的「起飞前」全局矩形（此刻旧行还在原位）。
	# 消耗顺序复刻引擎（悬浮武器从尾部←）：先 index1 再 index0
	var r1 := slot1.get_global_rect()
	var r0 := slot0.get_global_rect()

	# 生产时序：按键时 DetailTip 先 close（closed 回调里陈列行整排重建），再跑按钮回调 ——
	# 接线必须抓到「还有有效矩形的旧格子」，抓到刚 add_child 还没排布局的新格子就会打红
	DetailTip.close_all(_shop)
	merge_cb.call()
	await _frame(1)

	var overlay := _shop.get_node_or_null("MergeFx") as Control
	_c.check(overlay != null, "按下三合一后挂出合成演出层")
	if overlay != null:
		var origin := _shop.get_global_rect().position
		var f0 := overlay.get_node_or_null("FlyIcon0") as Control
		var f1 := overlay.get_node_or_null("FlyIcon1") as Control
		_c.check(f0 != null and f1 != null, "两件被消耗的图标各生成一枚飞行体")
		if f0 != null:
			_c.check(f0.position.distance_to(r1.position - origin) <= 1.5,
					"飞行体①从 index1 原格起飞（期望 %s，实得 %s）" % [
					str(r1.position - origin), str(f0.position)])
		if f1 != null:
			_c.check(f1.position.distance_to(r0.position - origin) <= 1.5,
					"飞行体②从 index0 原格起飞（期望 %s，实得 %s）" % [
					str(r0.position - origin), str(f1.position)])

	# 迸发帧（0.21s）+ 余量：合成必须真的落地
	await get_tree().create_timer(0.35).timeout
	_c.equals(GameManager.count_copies(W, 2), 1, "合成落地：多出 1 把 2 星")
	_c.equals(GameManager.count_copies(W, 1), 0, "同名 1 星清零")
	# 轻量刷新锁定：货架大卡还是原来那张实例（没被重建），陈列行则确实换成了新的
	if offer0 != null and is_instance_valid(offer0):
		_c.check(_shop.offers_container.get_child_count() > 0
				and _shop.offers_container.get_child(0) == offer0,
				"合成只重铺陈列行，货架大卡没有重建")
	else:
		_c.check(false, "货架大卡不该在合成时被销毁")
	_c.check(is_instance_valid(overlay), "迸发后演出层还在（结果图标的尾段余韵）")
	var pic: Control = null
	if is_instance_valid(overlay):
		_c.check(overlay.mouse_filter == Control.MOUSE_FILTER_IGNORE, "迸发后放开输入")
		pic = overlay.get_node_or_null("MergeResult") as Control
		_c.check(pic != null, "迸发帧放出了升星结果图标")

	# 滑行收尾：迸发后等 3 帧布局 + 0.13s 滑行，结果图标必须跟到左移两格后的 keeper 新位
	await get_tree().create_timer(0.18).timeout
	if pic != null and is_instance_valid(pic):
		var final_slot := _slot_node("equipped", 0)
		_c.check(final_slot != null, "重建后行首摆着 2 星 keeper（左移了两格）")
		if final_slot != null:
			var it_final: Dictionary = GameManager.get_weapons_summary()[0]
			_c.equals(String(it_final.get("id", "")), W, "行首那格就是合成结果")
			_c.equals(int(it_final.get("star", 1)), 2, "行首那格已是 2 星")
			var d := pic.get_global_rect().get_center().distance_to(
					final_slot.get_global_rect().get_center())
			_c.check(d <= 2.0, "结果图标滑行并轨到 keeper 新位置（差 %.1f px）" % d)

	# 自毁时刻 0.70s + 余量
	await get_tree().create_timer(0.45).timeout
	_c.check(_shop.get_node_or_null("MergeFx") == null, "尾段结束演出层自毁")
	_c.check(_shop.visible, "演完商店还开着，玩家接着操作")

	# —— ④ 分档端到端：★2→★3「觉醒」—— 与 ★1→★2 同一条生产链，走慢节奏 ——
	GameManager.add_weapon(W, 2)
	GameManager.add_weapon(W, 2)
	_shop.refresh(false)
	await get_tree().create_timer(0.4).timeout
	await _frame(2)
	_c.equals(GameManager.count_copies(W, 2), 3,
			"补 2 把 2 星后凑齐 3 把（实得 %d）" % GameManager.count_copies(W, 2))
	var aw_slot2 := _slot_node("equipped", 2)
	_c.check(aw_slot2 != null, "陈列行里找得到 2 星 keeper 格位")
	if aw_slot2 == null:
		_done()
		return
	var aw_summary: Array = GameManager.get_weapons_summary()
	var aw_item: Dictionary = aw_summary[2]
	_c.equals(int(aw_item.get("star", 1)), 2, "第 2 格是 2 星")

	_shop.selected = {"pool": "equipped", "index": 2}
	ShopWeaponTip.open(_shop, aw_item, "equipped", 2, aw_slot2)
	var aw_tip := DetailTip.live(_shop)
	_c.check(aw_tip != null, "★2 详情卡在场")
	var aw_cb := Callable()
	if aw_tip != null:
		for row in (aw_tip.payload.get("actions", []) as Array):
			for act in (row as Array):
				var d: Dictionary = act
				if String(d.get("text", "")).contains("三合一"):
					aw_cb = d.get("callback", Callable())
	_c.check(aw_cb.is_valid(), "★2 详情卡里有三合一回调")
	if not aw_cb.is_valid():
		_done()
		return
	DetailTip.close_all(_shop)
	aw_cb.call()
	await _frame(1)

	var ov3 := _shop.get_node_or_null("MergeFx") as Control
	_c.check(ov3 != null, "★2→★3 挂出演出层")
	if ov3 != null:
		_c.check(ov3.get_node_or_null("MergeCharge") != null, "★2→★3 挂出蓄力层（觉醒档）")
	_c.equals(GameManager.count_copies(W, 3), 0, "蓄力期合成未落地")

	# 迸发 ~0.61s + 余量
	await get_tree().create_timer(0.85).timeout
	_c.equals(GameManager.count_copies(W, 3), 1, "★3 合成落地：多出 1 把 3 星")
	_c.equals(GameManager.count_copies(W, 2), 0, "同名 2 星清零")
	if is_instance_valid(ov3):
		var st3 := ov3.get_node_or_null("MergeStarStamp") as Label
		_c.check(st3 != null and st3.text == "★★★", "迸发帧挂出「★★★」星章")

	# 自毁 ~1.13s + 余量
	await get_tree().create_timer(0.65).timeout
	_c.check(_shop.get_node_or_null("MergeFx") == null, "★3 演出按时自毁")
	_c.check(_shop.visible, "★3 演完商店还开着")

	_shop.visible = false
	get_tree().paused = false
	await _frame(2)
	_done()

## 场地静音：刷怪器不再出人，判据只管商店这一屏
func _quiet_arena() -> void:
	var spawner: Node = GameManager.wave_spawner
	if spawner != null:
		spawner.set_process(false)
		spawner.set_physics_process(false)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy is EnemyBase:
			enemy.dissolve()

## 按 drag_src 元数据在陈列行里找格位节点（合成接线的同一把尺）
func _slot_node(pool: String, index: int) -> Control:
	for child in _shop.owned_container.get_children():
		if not (child is Control) or not child.has_meta("drag_src"):
			continue
		var s: Dictionary = child.get_meta("drag_src")
		if String(s.get("pool", "")) == pool and int(s.get("index", -1)) == index:
			return child as Control
	return null

func _done() -> void:
	get_tree().quit(0 if _c.report("MERGE_FLOW_RESULT") else 1)
