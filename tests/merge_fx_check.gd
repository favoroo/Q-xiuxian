extends Node

## 三合一合成演出（MergeFx）判据：
##   ① 从陈列行起飞：两枚被消耗的图标出现在各自原有格子的位置，随后向 keeper 那一格移动；
##   ② 商店开着时整树暂停，演出照走 —— 迸发帧（~0.28s）调 on_burst 恰好一次；
##   ③ 迸发帧在 keeper 格中心放出结果图标（与刷新后的槽位同位同大），并放开鼠标过滤；
##   ④ 整层 ~0.70s 自毁，不在屏幕上留下死节点；
##   ⑤ 没有可飞图标时走最小起手照样迸发；宿主无效时 on_burst 也必须落地（不能丢合成）；
##   ⑥ 分档（2026-10-25）：默认档（★2）不挂蓄力层/星章（快节奏不回退）；
##      ★3「觉醒」走 0.61s 迸发 + 8 片鎏金星屑蓄力 +「★★★」星章；★4「神兵极境」
##      走 0.71s 迸发 + 压暗 + 12 片青紫星屑 + 光柱 + 扫屏 +「★★★★」霓虹青章。
## 运行: godot --headless --path . res://tests/MergeFxCheck.tscn

const WEAPON_ID := "huoyan_fu"
## 迸发时刻 0.21s + 余量
const BURST_WAIT := 0.35
## 自毁时刻 0.55s + 余量（相对 play 起算）
const FREE_WAIT := 0.48
## 观察飞行位移的时刻（飞行中段）
const MID_WAIT := 0.16
## solo 迸发 0.06s + 余量
const SOLO_BURST_WAIT := 0.14
## solo 自毁 0.40s + 余量（相对 play 起算）
const SOLO_FREE_WAIT := 0.38

var _c := TestCheck.new()
var _burst_count := 0
var _solo_count := 0
var _null_count := 0
var _awaken_count := 0
var _apex_count := 0

func _ready() -> void:
	get_tree().root.size = Vector2i(960, 540)
	call_deferred("_run")

## 造一格「陈列槽」：普通 Control + 显式矩形，足够量全局位置
func _make_slot(parent: Control, pos: Vector2, sz: Vector2) -> Control:
	var slot := Control.new()
	slot.position = pos
	slot.size = sz
	parent.add_child(slot)
	return slot

func _run() -> void:
	var host := Control.new()
	host.name = "Host"
	host.size = Vector2(960, 540)
	add_child(host)
	var slot_a := _make_slot(host, Vector2(100, 400), Vector2(56, 56))
	var slot_b := _make_slot(host, Vector2(200, 400), Vector2(56, 56))
	var keeper := _make_slot(host, Vector2(400, 400), Vector2(64, 64))
	await get_tree().process_frame

	var ra := slot_a.get_global_rect()
	var rb := slot_b.get_global_rect()
	var rk := keeper.get_global_rect()
	var target_center := rk.get_center()

	# 商店开着时整树暂停：演出必须靠 PROCESS 暂停模式照走
	get_tree().paused = true
	MergeFx.play_slots(host, WEAPON_ID, [ra, rb], rk, func() -> void:
		_burst_count += 1
	)
	var overlay := host.get_node_or_null("MergeFx") as Control
	_c.check(overlay != null, "播放后挂出 MergeFx 覆盖层")
	var fly0: Control = null
	var fly1: Control = null
	if overlay != null:
		_c.check(bool(overlay.get_meta("layout_bleed", false)), "覆盖层打 layout_bleed，布局判据放行")
		_c.check(overlay.process_mode == Node.PROCESS_MODE_ALWAYS, "覆盖层 PROCESS_ALWAYS，暂停下照走")
		_c.check(overlay.mouse_filter == Control.MOUSE_FILTER_STOP, "起手挡输入，防连点")
		fly0 = overlay.get_node_or_null("FlyIcon0") as Control
		fly1 = overlay.get_node_or_null("FlyIcon1") as Control
		_c.check(fly0 != null and fly1 != null, "两枚被消耗的图标各生成一枚飞行体")
		if fly0 != null:
			_c.check(fly0.position.distance_to(ra.position) <= 0.5, "飞行体从第一个原格起飞")
		if fly1 != null:
			_c.check(fly1.position.distance_to(rb.position) <= 0.5, "飞行体从第二个原格起飞")
	_c.check(_burst_count == 0, "迸发帧之前不执行合成回调")

	# 全屏锚点在布局那一帧才折算成尺寸：等一帧再量铺满
	await get_tree().process_frame
	_c.check(overlay.size == Vector2(960, 540), "覆盖层铺满宿主")

	await get_tree().create_timer(MID_WAIT).timeout
	if fly0 != null and is_instance_valid(fly0):
		var moved := fly0.position.distance_to(ra.position)
		var to_target := fly0.get_global_rect().get_center().distance_to(target_center)
		_c.check(moved > 5.0, "飞行体确实在向 keeper 移动（已挪 %.0f px）" % moved)
		_c.check(to_target < ra.get_center().distance_to(target_center), "飞行体离 keeper 更近了")

	await get_tree().create_timer(BURST_WAIT - MID_WAIT).timeout
	_c.check(_burst_count == 1, "迸发帧调用 on_burst 恰好一次")
	_c.check(is_instance_valid(overlay), "迸发后结果图标还在（尾段余韵）")
	if is_instance_valid(overlay):
		_c.check(overlay.mouse_filter == Control.MOUSE_FILTER_IGNORE, "迸发后放开输入")
		var pic := overlay.get_node_or_null("MergeResult") as Control
		_c.check(pic != null, "迸发帧在 keeper 上放结果图标")
		if pic != null:
			_c.check(pic.get_global_rect().get_center().distance_to(target_center) <= 1.5,
				"结果图标与 keeper 格同心（与实际槽位并轨）")
		# 默认档锁定（2026-10-25 分档加强）：快节奏不许被蓄力段拖慢
		_c.check(overlay.get_node_or_null("MergeCharge") == null, "默认档不挂蓄力层")
		_c.check(overlay.get_node_or_null("MergeStarStamp") == null, "默认档不挂星章")

	await get_tree().create_timer(FREE_WAIT).timeout
	_c.check(host.get_node_or_null("MergeFx") == null, "尾段结束覆盖层自毁")

	# 没有可飞图标（三件里只有 keeper 在屏上）：最小起手照样迸发
	MergeFx.play_slots(host, WEAPON_ID, [], rk, func() -> void:
		_solo_count += 1
	)
	await get_tree().create_timer(SOLO_BURST_WAIT).timeout
	_c.check(_solo_count == 1, "无飞行体也照常迸发")
	await get_tree().create_timer(SOLO_FREE_WAIT).timeout
	_c.check(host.get_node_or_null("MergeFx") == null, "无飞行体的演出同样自毁")

	# 宿主无效：画不出来也必须把合成回调落地（否则玩家按了合成什么也没发生）
	MergeFx.play_slots(null, WEAPON_ID, [], rk, func() -> void:
		_null_count += 1
	)
	_c.check(_null_count == 1, "宿主无效时 on_burst 立即兜底执行")

	# —— ⑥ 分档：★3 觉醒 —— 飞行放慢 + 蓄力窗（星屑 8 片）→ 0.61s 迸发 +「★★★」星章
	# 计数走成员变量：GDScript 的 lambda 按值捕获局部变量，局部计数器在闭包里加不动
	_awaken_count = 0
	MergeFx.play_slots(host, WEAPON_ID, [ra, rb], rk, func() -> void:
		_awaken_count += 1
	, Callable(), 3)
	var ov3 := host.get_node_or_null("MergeFx") as Control
	_c.check(ov3 != null, "★3 档挂出演出层")
	if ov3 != null:
		_c.check(ov3.mouse_filter == Control.MOUSE_FILTER_STOP, "★3 起手挡输入，防连点")
		var ch3 := ov3.get_node_or_null("MergeCharge") as Control
		_c.check(ch3 != null, "★3 挂出蓄力层")
		if ch3 != null:
			_c.check(int(ch3.get_meta("shard_count", 0)) == 8, "★3 蓄力星屑 8 片（鎏金档）")
	_c.check(_awaken_count == 0, "★3 起手不执行合成回调")

	await get_tree().create_timer(0.35).timeout
	if is_instance_valid(ov3):
		_c.check(is_instance_valid(ov3.get_node_or_null("MergeCharge")), "★3 蓄力层在迸发前存活")
	_c.check(_awaken_count == 0, "★3 飞行+蓄力窗内不落地（迸发在 ~0.61s）")

	await get_tree().create_timer(0.80 - 0.35).timeout
	_c.check(_awaken_count == 1, "★3 迸发帧调用 on_burst 恰好一次")
	if is_instance_valid(ov3):
		_c.check(ov3.mouse_filter == Control.MOUSE_FILTER_IGNORE, "★3 迸发后放开输入")
		_c.check(ov3.get_node_or_null("MergeResult") != null, "★3 迸发帧放结果图标")
		var st3 := ov3.get_node_or_null("MergeStarStamp") as Label
		_c.check(st3 != null and st3.text == "★★★", "★3 挂出「★★★」星章")

	await get_tree().create_timer(1.45 - 0.80).timeout
	_c.check(host.get_node_or_null("MergeFx") == null, "★3 演出按时自毁（~1.13s）")

	# —— ⑥ 分档：★4 神兵极境 —— 压暗 + 星屑 12 片 → 0.71s 迸发 + 光柱 + 扫屏 + 青章
	_apex_count = 0
	MergeFx.play_slots(host, WEAPON_ID, [ra, rb], rk, func() -> void:
		_apex_count += 1
	, Callable(), 4)
	var ov4 := host.get_node_or_null("MergeFx") as Control
	_c.check(ov4 != null, "★4 档挂出演出层")
	if ov4 != null:
		_c.check(ov4.get_node_or_null("MergeDim") != null, "★4 挂出压暗层")
		var ch4 := ov4.get_node_or_null("MergeCharge") as Control
		_c.check(ch4 != null, "★4 挂出蓄力层")
		if ch4 != null:
			_c.check(int(ch4.get_meta("shard_count", 0)) == 12, "★4 蓄力星屑 12 片（青紫档）")
	_c.check(_apex_count == 0, "★4 起手不执行合成回调")

	await get_tree().create_timer(0.90).timeout
	_c.check(_apex_count == 1, "★4 迸发帧调用 on_burst 恰好一次（~0.71s）")
	if is_instance_valid(ov4):
		_c.check(ov4.mouse_filter == Control.MOUSE_FILTER_IGNORE, "★4 迸发后放开输入")
		var st4 := ov4.get_node_or_null("MergeStarStamp") as Label
		_c.check(st4 != null and st4.text == "★★★★", "★4 挂出「★★★★」霓虹青章")
		_c.check(ov4.get_node_or_null("MergeBeam") != null, "★4 迸发帧放光柱")
		var bleed := 0
		for child in host.get_children():
			if child is Control and bool((child as Control).get_meta("layout_bleed", false)):
				bleed += 1
		_c.check(bleed >= 2, "★4 迸发帧挂出扫屏带（layout_bleed 层 ≥ 2）")

	await get_tree().create_timer(1.65 - 0.90).timeout
	_c.check(host.get_node_or_null("MergeFx") == null, "★4 演出按时自毁（~1.33s）")

	get_tree().paused = false
	var ok := _c.report("MERGE_FX_RESULT")
	get_tree().quit(0 if ok else 1)
