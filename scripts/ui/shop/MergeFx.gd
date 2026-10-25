class_name MergeFx
extends RefCounted

## 三合一合成演出层：商店里按下「◆ 三合一 ◆」时，把陈列行里那两件被消耗的同名武器
## 从各自格子拎起来、飞进要保留的那一格（keeper），在 keeper 上迸开再落定。
##
## 为什么从槽位起飞：合成发生在下面那一排武器/背包格里，玩家眼睛盯着的是那几个图标；
## 在屏幕中心凭空冒三枚图标是另一件事（2026-10-24 用户：「就那几个图标一起移动到要合成的
## 那个位置然后合成」）。起飞点与落点由调用方按槽位的全局矩形算好传进来。
##
## 三条口径：
## ① 纯表现层：不读玩法状态。真正的 merge_weapon 由调用方塞进 on_burst，在迸发帧执行 ——
##    音效、陈列行刷出的新星图标、中心迸发同帧落地；被消耗的两格由调用方先藏掉，刷新后一并重建。
## ② 商店开着时整树暂停（WaveShop 的暂停口径），所有 tween 必须 TWEEN_PAUSE_PROCESS；
##    层本身 PROCESS_MODE_ALWAYS，与 DetailTip / ResultFx 同一条。
## ③ 全屏铺底不是布局内容：打 layout_bleed meta 让 LayoutCheck 放行（同 slash_wipe / ResultFx）。
##    迸发帧起立刻放开鼠标过滤，尾段淡出纯装饰，不再挡操作。

## 三枚图标的合成演出约 0.55s 演完（用户口径：「比较快的，比较流畅的动画」——
## 起飞段 0.21s 迸发，结果图标落定即收，只读得清「两个吃进一个」不拖沓）。

## 起飞时先轻轻抬一下（放大一点点），让「拎起来」有起手
const LIFT := 0.05
## 从原格飞进 keeper 的时长
const FLY := 0.16
## 迸发时刻（从 play_slots 起算）：起飞 + 飞行
const BURST_AT := LIFT + FLY
## 没有可飞图标时的最小起手（比如三件里只有 keeper 在屏上）
const SOLO_BURST_AT := 0.06
## 升星图标的停留时长
const HOLD := 0.24
## 整层淡出时长
const FADE_OUT := 0.10

## 飞行的原图标最小/最大边长（槽位现算 56~64，DTO 兜底防畸形矩形）
const FLY_SIZE_MIN := 16.0
const FLY_SIZE_MAX := 96.0
## keeper 上的结果图标同样夹在这个范围（与刷新后的槽位图标对齐）
const RESULT_SIZE_MIN := 24.0
const RESULT_SIZE_MAX := 96.0
## 迸发圆环相对落点格的倍率
const RING_SCALE := 1.35

## 播一次三合一演出。
## fly_rects  —— 被消耗的那两件在屏幕上的全局矩形（0~2 个，全是同一把武器的图标）
## target_rect —— keeper 格子在屏幕上的全局矩形（结果图标与圆环以它为中心）
## on_burst   —— 迸发帧调用一次；调用方在这里执行合成、刷新陈列行
## follow     —— 可选：迸发后（陈列行重建排完布局）回一次 keeper 的当前矩形。
##               合成会删格子、行会向左收拢，keeper 挪位时结果图标补一小段滑行跟过去。
## 宿主只当画布用（全屏装饰层的宿主），不读商店状态。
static func play_slots(host: Control, icon_path: String,
		fly_rects: Array[Rect2], target_rect: Rect2,
		on_burst: Callable = Callable(), follow: Callable = Callable()) -> void:
	if host == null or not is_instance_valid(host) or not host.is_inside_tree():
		# 没有画布也得让合成落地：这层只负责演，玩法状态不能因为画不出来就丢
		if on_burst.is_valid():
			on_burst.call()
		return
	var area: Vector2 = host.size
	if area.x <= 0.0 or area.y <= 0.0:
		area = host.get_viewport_rect().size
	if area.x <= 0.0 or area.y <= 0.0:
		if on_burst.is_valid():
			on_burst.call()
		return
	# 全局矩形 → 覆盖层本地坐标：覆盖层是 host 的全屏子节点，原点就是 host 的全局原点
	var origin: Vector2 = host.get_global_rect().position

	var overlay := Control.new()
	overlay.name = "MergeFx"
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	overlay.set_meta("layout_bleed", true)
	host.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var target := _size_of(target_rect)
	if target == Vector2.ZERO:
		target = Vector2(56.0, 56.0)
	var target_center := target_rect.get_center() - origin
	if target_rect.size == Vector2.ZERO:
		target_center = area * 0.5

	var burst_at := SOLO_BURST_AT
	var flew := 0
	for i in range(fly_rects.size()):
		var r: Rect2 = fly_rects[i]
		if r.size == Vector2.ZERO:
			continue
		var icon := _make_icon(icon_path, _size_of(r))
		icon.name = "FlyIcon%d" % i
		icon.position = r.position - origin
		overlay.add_child(icon)
		flew += 1

		# 拎起：放大一点，随后的飞行把这点放大收回去（读起来才像「被吸走」）
		var lift := _tween(icon)
		lift.tween_property(icon, "scale", Vector2(1.12, 1.12), LIFT) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		var fly := _tween(icon)
		fly.tween_property(icon, "position", target_center - icon.size * 0.5, FLY) \
				.set_delay(LIFT).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		var shrink := _tween(icon)
		shrink.tween_property(icon, "scale", Vector2(0.55, 0.55), FLY) \
				.set_delay(LIFT).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		var dissolve := _tween(icon)
		dissolve.tween_property(icon, "modulate:a", 0.0, 0.06).set_delay(LIFT + FLY - 0.06)
	if flew > 0:
		burst_at = BURST_AT

	var master := _tween(overlay)
	master.tween_interval(burst_at)
	master.tween_callback(func() -> void:
		# 数据在迸发帧落地，之后尾段只是余韵：立刻放开输入，不挡玩家
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var pic := _burst(overlay, target_center, target, icon_path)
		if on_burst.is_valid():
			on_burst.call()
		# 合成删掉两件后整行向左收拢，keeper 多半挪了位：等重建排完布局（两帧，
		# 同 _keep_row_scroll 的口径），把结果图标一小段滑行修正到格子的最终位置
		if follow.is_valid():
			_glide_to_final(overlay, pic, origin, follow)
	)
	master.tween_interval(HOLD)
	master.tween_property(overlay, "modulate:a", 0.0, FADE_OUT)
	master.tween_callback(overlay.queue_free)

## 迸发：金色圆环冲击波 + 中心一闪 + 升星图标在 keeper 格上拍入（返回结果图标，供滑行收尾引用）
static func _burst(overlay: Control, center: Vector2, target: Vector2, icon_path: String) -> Control:
	var flash := ColorRect.new()
	flash.color = GameStyle.with_alpha(GameStyle.GOLD_EDGE, 0.55)
	flash.size = target * 1.2
	flash.pivot_offset = flash.size * 0.5
	flash.position = center - flash.size * 0.5
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(flash)
	var flash_scale := _tween(flash)
	flash_scale.tween_property(flash, "scale", Vector2(1.4, 1.4), 0.14) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var flash_fade := _tween(flash)
	flash_fade.tween_property(flash, "modulate:a", 0.0, 0.14)
	flash_fade.tween_callback(flash.queue_free)

	# 圆环走「圆形 StyleBoxFlat」的既有技巧（同货架卡「合」角标），不引入自绘节点
	var ring_size: float = clampf(target.x * RING_SCALE, 40.0, 160.0)
	var ring := PanelContainer.new()
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.size = Vector2(ring_size, ring_size)
	ring.pivot_offset = ring.size * 0.5
	ring.position = center - ring.size * 0.5
	ring.scale = Vector2(0.35, 0.35)
	var ring_box := GameStyle.outlined_panel(Color(0, 0, 0, 0), GameStyle.GOLD, 3, 0.0)
	ring_box.set_corner_radius_all(int(ring_size * 0.5))
	ring.add_theme_stylebox_override("panel", ring_box)
	overlay.add_child(ring)
	var ring_scale := _tween(ring)
	ring_scale.tween_property(ring, "scale", Vector2(1.9, 1.9), 0.22) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var ring_fade := _tween(ring)
	ring_fade.tween_property(ring, "modulate:a", 0.0, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	ring_fade.tween_callback(ring.queue_free)

	# 结果图标：和 keeper 格等大、等位（刷新后的槽位就在它底下，淡出时无缝并轨）。
	# 星级字不另画 —— 同一帧刷新的槽位右下角就是新的 ★n，两处再叠一遍反而打架。
	var result_size := Vector2(
		clampf(target.x, RESULT_SIZE_MIN, RESULT_SIZE_MAX),
		clampf(target.y, RESULT_SIZE_MIN, RESULT_SIZE_MAX))
	var pic := _make_icon(icon_path, result_size)
	pic.name = "MergeResult"
	pic.position = center - result_size * 0.5
	pic.scale = Vector2(0.55, 0.55)
	pic.modulate.a = 0.0
	overlay.add_child(pic)
	var result_fade := _tween(pic)
	result_fade.tween_property(pic, "modulate:a", 1.0, 0.05)
	var result_pop := _tween(pic)
	result_pop.tween_property(pic, "scale", Vector2(1.15, 1.15), 0.14) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	result_pop.tween_property(pic, "scale", Vector2.ONE, 0.10) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return pic

## 迸发后把结果图标滑行到 keeper 的最终位置：follow 回查重建排完布局后的全局矩形，
## 差 1px 以内不动（keeper 在行首没挪位就是这种情况）。等三帧 = refresh 的两帧布局
## + 一帧保险；overlay 若已自毁（极端时序）就什么都不做。
static func _glide_to_final(overlay: Control, pic: Control, origin: Vector2, follow: Callable) -> void:
	if pic == null or not follow.is_valid():
		return
	await_frames(overlay, 3, func() -> void:
		if not is_instance_valid(overlay) or not is_instance_valid(pic):
			return
		var final_rect: Rect2 = follow.call()
		if final_rect.size == Vector2.ZERO:
			return
		var to := final_rect.get_center() - origin - pic.size * 0.5
		if to.distance_to(pic.position) <= 1.0:
			return
		var tw := _tween(pic)
		tw.tween_property(pic, "position", to, 0.13).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	)

## 等 n 个渲染帧再跑 fn：lambda 协程，不阻塞、不进循环。
## 用 SceneTree 的 process_frame —— 整树暂停时它照样每渲染帧发（tween 走的同一把时钟），
## 而 physics_frame 在暂停下不发，演出会被冻死。
static func await_frames(node: Node, n: int, fn: Callable) -> void:
	var tree := node.get_tree()
	if tree == null:
		return
	var co := func() -> void:
		for _i in range(n):
			await tree.process_frame
		if is_instance_valid(node):
			fn.call()
	co.call()

## 飞行/结果图标共用：与槽位图标同一套贴图口径（UI 高清变体 + 线性过滤）
static func _make_icon(icon_path: String, sz: Vector2) -> TextureRect:
	var icon := GameStyle.icon_texture_rect(icon_path, sz)
	icon.size = sz
	icon.pivot_offset = sz * 0.5
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon

## 槽位矩形夹到合理边长；畸形/空矩形返回 0，由调用方走兜底
static func _size_of(r: Rect2) -> Vector2:
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return Vector2.ZERO
	return Vector2(
		clampf(r.size.x, FLY_SIZE_MIN, FLY_SIZE_MAX),
		clampf(r.size.y, FLY_SIZE_MIN, FLY_SIZE_MAX))

## 商店开着时整树暂停，tween 必须显式走 PROCESS 模式（同 GameStyle.pop_in 的口径）
static func _tween(node: Node) -> Tween:
	var tw := node.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	return tw
