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
## 2026-10-25 分档加强（用户：「★2→★3 / ★3→★4 的动画要再加强，提升成就感」）：
## ★2 默认档保持快节奏不动；★3「觉醒」与★4「神兵极境」是 9 把 / 27 把 ★1 堆出来的
## 大事件，走「飞行放慢 → 蓄力（星屑汇聚 + 核脉冲 + 蓄力音）→ 迸发（星屑迸散 / 星章，
## ★4 再加光柱 + 压暗 + 扫屏）→ 长停留」的四拍。迸发帧仍 = 数据落地帧，声画对齐不变。

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

## —— 分档节拍（★3/★4 专用）：默认档（★2）不读这些常量，快节奏不受影响 ——
const AWAKEN_FLY := 0.26          ## ★3 飞行放慢：「两件被吸进去」看得更清
const AWAKEN_CHARGE := 0.30       ## ★3 蓄力时长（星屑汇聚 + 核脉冲）
const AWAKEN_HOLD := 0.42         ## ★3 结果停留
const APEX_FLY := 0.30            ## ★4 飞行更慢
const APEX_CHARGE := 0.36         ## ★4 蓄力更长（压暗升起全在蓄力窗里）
const APEX_HOLD := 0.52           ## ★4 结果停留最久
const SHARD_DUR := 0.36           ## 迸发星屑的迸散时长
const CHARGE_SHARDS_AWAKEN := 8   ## ★3 蓄力星屑片数（鎏金交替）
const CHARGE_SHARDS_APEX := 12    ## ★4 蓄力星屑片数（青紫交替）
const DIM_ALPHA := 0.45           ## ★4 压暗峰值（INK）

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
## new_star   —— 合成后的星级（默认 1 = 不特殊分档）：★3 迸发改鎏金、★4 改太虚霓虹双环白核。
##               ★4 极境是「27 把★1 堆出来」的一刻，旧写法与普通三合一同样是一圈金环，
##               全靠横幅文字区分——这里让迸发本身读得出档位。
static func play_slots(host: Control, icon_path: String,
		fly_rects: Array[Rect2], target_rect: Rect2,
		on_burst: Callable = Callable(), follow: Callable = Callable(),
		new_star: int = 1) -> void:
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

	# 分档节拍：★2 走上面的默认常量；★3/★4 取各自的慢节奏 + 蓄力窗
	var star := clampi(new_star, 1, WeaponData.MAX_STAR)
	var is_apex: bool = star >= 4
	var is_awaken: bool = star >= 3
	var fly_dur := FLY
	var charge_dur := 0.0
	var hold_dur := HOLD
	if is_awaken:
		fly_dur = APEX_FLY if is_apex else AWAKEN_FLY
		charge_dur = APEX_CHARGE if is_apex else AWAKEN_CHARGE
		hold_dur = APEX_HOLD if is_apex else AWAKEN_HOLD
		# 蓄力音从起飞就起：riser 铺满整个 pre-burst 窗，迸发帧正好接 weapon_awaken
		AudioManager.play_sfx("merge_charge", 0.9)

	# ★4 压暗垫底：先 add 再压到 0 号位，星屑/飞行体都画在它上面
	if is_apex:
		_make_dim(overlay, LIFT + fly_dur + charge_dur)
	# ★3/★4 蓄力层：星屑向 keeper 汇聚 + 核脉冲（画在飞行体底下，迸发帧原地转迸散）
	var charge: ChargeFx = null
	if charge_dur > 0.0:
		charge = ChargeFx.spawn(overlay, target_center, target, is_apex, charge_dur,
				CHARGE_SHARDS_APEX if is_apex else CHARGE_SHARDS_AWAKEN)
		charge._shard_dur = SHARD_DUR
	# ★3/★4 星章在起飞时就建好（透明待命）：★ 字形与描边在蓄力窗里先排版栅格化一遍，
	# 迸发帧只翻透明度/拍缩放 —— 首次画字形有概率掉一帧，不能让它落在爆点上
	var stamp: Label = null
	if is_awaken:
		stamp = _build_stamp(overlay, target_center, target, star)

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
		# 飞行走一条浅弧而不是直线平移：两件从各自那侧兜着劲儿收进 keeper，一上一下对称。
		# 弧高按起点到落点的距离取（确定性，不进随机源），远景时弧度大、贴脸时不夸张。
		var from_c := icon.position + icon.size * 0.5
		var bow := clampf(from_c.distance_to(target_center) * 0.16, 6.0, 20.0)
		if i % 2 == 1:
			bow = -bow
		_fly_arc(icon, from_c, target_center, bow, LIFT, fly_dur)
		var shrink := _tween(icon)
		shrink.tween_property(icon, "scale", Vector2(0.55, 0.55), fly_dur) \
				.set_delay(LIFT).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		var dissolve := _tween(icon)
		dissolve.tween_property(icon, "modulate:a", 0.0, 0.06).set_delay(LIFT + fly_dur - 0.06)
	if flew > 0:
		burst_at = LIFT + fly_dur + charge_dur
	else:
		burst_at = SOLO_BURST_AT + charge_dur

	var master := _tween(overlay)
	master.tween_interval(burst_at)
	master.tween_callback(func() -> void:
		# 数据在迸发帧落地，之后尾段只是余韵：立刻放开输入，不挡玩家
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# 蓄力星屑原地转迸散；★3/★4 加星章，★4 再加光柱 + 扫屏 + 退压暗
		if charge != null and is_instance_valid(charge):
			charge.explode()
		var pic := _burst(overlay, target_center, target, icon_path, star)
		if stamp != null and is_instance_valid(stamp):
			# 极境让星章慢半拍跟上：爆闪先亮、章再落，层次比全部同帧炸开清楚
			_reveal_stamp(overlay, stamp, 0.03 if is_apex else 0.0)
		if is_apex:
			_make_beam(overlay, target_center, target)
			if is_instance_valid(host):
				GameStyle.slash_wipe(host, GameStyle.STAR4_NEON_EDGE)
			_fade_dim(overlay)
		if on_burst.is_valid():
			on_burst.call()
		# 合成删掉两件后整行向左收拢，keeper 多半挪了位：等重建排完布局（两帧，
		# 同 _keep_row_scroll 的口径），把结果图标一小段滑行修正到格子的最终位置
		if follow.is_valid():
			_glide_to_final(overlay, pic, origin, follow)
	)
	master.tween_interval(hold_dur)
	master.tween_property(overlay, "modulate:a", 0.0, FADE_OUT)
	master.tween_callback(overlay.queue_free)

## 迸发：圆环冲击波 + 中心一闪 + 升星图标在 keeper 格上拍入（返回结果图标，供滑行收尾引用）
## new_star 分档：★4 白核爆闪 + 青紫双环错峰扩散（环径放大一档）；★3 鎏金单环；
## 其余保持原本的浩然金。色值一律取 GameStyle.STAR4_* / GOLD，不硬编码。
static func _burst(overlay: Control, center: Vector2, target: Vector2, icon_path: String,
		new_star: int = 1) -> Control:
	var is_apex: bool = new_star >= 4
	var is_awaken: bool = new_star >= 3
	var main_col: Color = GameStyle.STAR4_NEON if is_apex else (GameStyle.GOLD if is_awaken else GameStyle.GOLD_EDGE)

	var flash := ColorRect.new()
	flash.color = GameStyle.with_alpha(GameStyle.FX_HDR_CORE if is_apex else GameStyle.GOLD_EDGE, 0.55)
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
	# 极境环径放大一档（1.35 → 见 APEX_RING_SCALE 说明），让「神兵极境」比普通升星撑得更开
	if is_apex:
		ring_size = clampf(target.x * RING_SCALE * 1.25, 48.0, 200.0)
	_make_ring(overlay, center, ring_size, main_col, 0.0)
	if is_apex:
		# 第二道太虚紫环错峰扩散（0.06s 后起跑、略小一圈）：双环是极境的记忆点
		_make_ring(overlay, center, ring_size * 0.82, GameStyle.STAR4_NEON_EDGE, 0.06)

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

## 单道圆环冲击波：从 0.35 扩到 1.9 + 淡出。delay 用于极境双环的错峰。
static func _make_ring(overlay: Control, center: Vector2, ring_size: float, col: Color, delay: float) -> void:
	var ring := PanelContainer.new()
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.size = Vector2(ring_size, ring_size)
	ring.pivot_offset = ring.size * 0.5
	ring.position = center - ring.size * 0.5
	ring.scale = Vector2(0.35, 0.35)
	if delay > 0.0:
		ring.modulate.a = 0.0
	var ring_box := GameStyle.outlined_panel(Color(0, 0, 0, 0), col, 3, 0.0)
	ring_box.set_corner_radius_all(int(ring_size * 0.5))
	ring.add_theme_stylebox_override("panel", ring_box)
	overlay.add_child(ring)
	if delay > 0.0:
		var ring_in := _tween(ring)
		ring_in.tween_property(ring, "modulate:a", 1.0, delay * 0.5).set_delay(delay)
	var ring_scale := _tween(ring)
	ring_scale.tween_property(ring, "scale", Vector2(1.9, 1.9), 0.22) \
			.set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var ring_fade := _tween(ring)
	ring_fade.tween_property(ring, "modulate:a", 0.0, 0.22).set_delay(delay) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	ring_fade.tween_callback(ring.queue_free)

## ★4 压暗垫底：飞行 + 蓄力期间整层罩一层墨色，把视线收到 keeper 上；迸发帧 _fade_dim 退场。
## 压在 overlay 最底（add 后挪到 0 号位），星屑/飞行体/迸发全套都画在它上面。
static func _make_dim(overlay: Control, rise_dur: float) -> void:
	var dim := ColorRect.new()
	dim.name = "MergeDim"
	dim.color = GameStyle.with_alpha(GameStyle.INK, DIM_ALPHA)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.modulate.a = 0.0
	overlay.add_child(dim)
	overlay.move_child(dim, 0)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var tw := _tween(dim)
	tw.tween_property(dim, "modulate:a", 1.0, maxf(rise_dur - 0.08, 0.05))

static func _fade_dim(overlay: Control) -> void:
	var dim := overlay.get_node_or_null("MergeDim") as ColorRect
	if dim == null:
		return
	var tw := _tween(dim)
	tw.tween_property(dim, "modulate:a", 0.0, 0.30).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_callback(dim.queue_free)

## ★4 光柱：外紫内青两根硬边矩形从 keeper 中心向上生长再淡出。
## 野兽派口径：无渐变无辉光，纯矩形 + 透明度；pivot 钉在底边中心，scale.y 从 0.12 长到 1。
static func _make_beam(overlay: Control, center: Vector2, target: Vector2) -> void:
	var specs := [
		{"name": "MergeBeamOuter", "col": GameStyle.STAR4_NEON_EDGE,
			"w": target.x * 0.52, "h": target.y * 2.8, "a": 0.38},
		{"name": "MergeBeam", "col": GameStyle.STAR4_NEON,
			"w": target.x * 0.26, "h": target.y * 2.2, "a": 0.55},
	]
	for sp: Dictionary in specs:
		var beam := ColorRect.new()
		beam.name = String(sp["name"])
		beam.color = sp["col"]
		beam.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sz := Vector2(float(sp["w"]), float(sp["h"]))
		beam.size = sz
		beam.position = center - Vector2(sz.x * 0.5, sz.y)
		beam.pivot_offset = Vector2(sz.x * 0.5, sz.y)
		beam.modulate.a = 0.0
		beam.scale = Vector2(1.0, 0.12)
		overlay.add_child(beam)
		var tin := _tween(beam)
		tin.set_parallel(true)
		tin.tween_property(beam, "modulate:a", float(sp["a"]), 0.08)
		tin.tween_property(beam, "scale:y", 1.0, 0.18) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		var tout := _tween(beam)
		tout.tween_property(beam, "modulate:a", 0.0, 0.34).set_delay(0.22) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tout.tween_callback(beam.queue_free)

## ★3/★4 星章：「★★★」/「★★★★」的牌子，起飞时就建好（理由见 play_slots），透明待命。
## 结果图标本身不画星（刷新后的槽位右下角就是新的 ★n），星章是给「这一刻」的记号，
## 飘在格子外不影响并轨。颜色：★3 鎏金 JADE，★4 霓虹青 STAR4_NEON。
static func _build_stamp(overlay: Control, center: Vector2, target: Vector2, star: int) -> Label:
	var is_apex: bool = star >= 4
	var lbl := Label.new()
	lbl.name = "MergeStarStamp"
	lbl.text = WeaponData.star_text(star)
	lbl.add_theme_font_override("font", GameStyle.display_font())
	lbl.add_theme_font_size_override("font_size", 30 if is_apex else 24)
	lbl.add_theme_color_override("font_color", GameStyle.STAR4_NEON if is_apex else GameStyle.JADE)
	lbl.add_theme_color_override("font_outline_color", GameStyle.INK)
	lbl.add_theme_constant_override("outline_size", 6)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var box := Vector2(maxf(target.x * 2.8, 120.0), 52.0)
	lbl.custom_minimum_size = box
	lbl.size = box
	lbl.position = center - Vector2(box.x * 0.5, target.y * 0.5 + box.y)
	lbl.pivot_offset = box * 0.5
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.scale = Vector2(0.5, 0.5)
	lbl.modulate.a = 0.0
	overlay.add_child(lbl)
	return lbl

## 迸发帧把星章拍到最上层（它是提前建的，躺着时在飞行体下面）并演「拍入 → 停一拍 → 浮起淡出」。
## delay 给极境一点错峰，让星章跟在爆闪后面出现。
static func _reveal_stamp(overlay: Control, lbl: Label, delay: float) -> void:
	overlay.move_child(lbl, overlay.get_child_count() - 1)
	# 拍入：淡入 + BACK 弹到 1.12，再收回 1.0
	var tin := _tween(lbl)
	tin.set_parallel(true)
	tin.tween_property(lbl, "modulate:a", 1.0, 0.08).set_delay(delay)
	tin.tween_property(lbl, "scale", Vector2(1.12, 1.12), 0.16).set_delay(delay) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tin.chain().tween_property(lbl, "scale", Vector2.ONE, 0.10) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# 浮起淡出：约 0.26s 后上浮 14px 并退场，总寿命 ≈ STAMP_DUR + 淡出
	var tout := _tween(lbl)
	tout.set_parallel(true)
	tout.tween_property(lbl, "position:y", lbl.position.y - 14.0, 0.30).set_delay(delay + 0.26) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tout.tween_property(lbl, "modulate:a", 0.0, 0.30).set_delay(delay + 0.26) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tout.chain().tween_callback(lbl.queue_free)

## 二次贝塞尔飞行：起点 → 垂直偏移的控制点 → keeper 中心。位移在 tween_method 里逐帧算，
## 一条 tween 管一条轨迹（不再让 position 与 scale 两条 tween 抢时序）。
## 缓动取 QUAD EASE_IN：起手别像 CUBIC 那样先「定住」几十毫秒，进 keeper 时仍在加速 —— 才像被吸进去。
static func _fly_arc(icon: Control, from_c: Vector2, to_c: Vector2, bow: float,
		delay: float, dur: float) -> void:
	var half := icon.size * 0.5
	var ctrl := (from_c + to_c) * 0.5 + (to_c - from_c).orthogonal().normalized() * bow
	var tw := _tween(icon)
	tw.tween_method(func(t: float) -> void:
		if not is_instance_valid(icon):
			return
		var p := from_c.lerp(ctrl, t).lerp(ctrl.lerp(to_c, t), t)
		icon.position = p - half
	, 0.0, 1.0, dur).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

## 迸发后把结果图标滑行到 keeper 的最终位置：follow 回查重建排完布局后的全局矩形，
## 差 1px 以内不动（keeper 在行首没挪位就是这种情况）。等三帧 = 陈列行重建一帧（调用方
## 挪到迸发帧的下一帧）+ 容器排布局一帧 + 一帧保险；overlay 若已自毁（极端时序）就什么都不做。
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
		tw.tween_property(pic, "position", to, 0.16) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
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


## 蓄力层（★3/★4 专用）：星屑从 keeper 四周向中心汇聚收拢 + 中心一枚旋转菱形核脉冲，
## 迸发帧由宿主调 explode() 原地转「向外迸散」。仿 HudLevelBadgeFx 的口径：
## 纯 _draw 无贴图、参数按序号取确定性值不进随机源（判据可钉、连放不重样）、
## tween_method 驱动、播完自毁。所有配置经 spawn 参数传入，不读外部状态。
class ChargeFx extends Control:
	var _center := Vector2.ZERO      ## 覆盖层本地坐标的 keeper 中心
	var _radius := 40.0              ## 星屑初始半径（汇聚起点）
	var _apex := false               ## ★4：青紫交替；★3：鎏金
	var _shards: Array[Dictionary] = []
	var _shard_dur := 0.36
	var _t := 0.0                    ## 蓄力相位 0→1（汇聚 + 核脉冲）
	var _ex := -1.0                  ## 迸散相位 0→1；-1 = 尚未迸发

	static func spawn(overlay: Control, center: Vector2, target: Vector2,
			apex: bool, charge_dur: float, shard_count: int) -> ChargeFx:
		var fx := ChargeFx.new()
		fx.name = "MergeCharge"
		fx._center = center
		fx._radius = maxf(target.x, target.y) * 1.35
		fx._apex = apex
		fx.set_meta("shard_count", shard_count)   ## 判据用：钉住各档片数
		fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for i in range(shard_count):
			var dir := Vector2.from_angle(TAU * float(i) / float(shard_count) + 0.35 * float(i % 2))
			var col: Color
			if apex:
				col = GameStyle.STAR4_NEON if i % 2 == 0 else GameStyle.STAR4_NEON_EDGE
			else:
				col = GameStyle.JADE if i % 2 == 0 else GameStyle.GOLD_EDGE
			fx._shards.append({
				"dir": dir,
				"spin": (1.0 if i % 2 == 0 else -1.0) * (2.0 + 0.5 * float(i % 3)),
				"col": col,
			})
		overlay.add_child(fx)
		fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var tw := fx.create_tween()
		tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tw.tween_method(fx._set_charge, 0.0, 1.0, charge_dur)
		return fx

	## 迸发帧调用：星屑从近核处向外炸开，播完自毁（宿主保证只调一次）
	func explode() -> void:
		_ex = 0.0
		var tw := create_tween()
		tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tw.tween_method(_set_explode, 0.0, 1.0, _shard_dur)
		tw.tween_callback(queue_free)

	func _set_charge(v: float) -> void:
		_t = v
		queue_redraw()

	func _set_explode(v: float) -> void:
		_ex = v
		queue_redraw()

	func _draw() -> void:
		# 核：旋转菱形描边。蓄力期以两拍脉冲呼吸；迸散后随 _ex 一并淡出
		var core_col: Color = GameStyle.STAR4_NEON if _apex else GameStyle.GOLD
		core_col.a = 0.75 if _ex < 0.0 else 0.75 * (1.0 - _ex)
		var pulse := 1.0 + 0.14 * sin(_t * TAU * 2.0)
		var core_r: float = maxf(_radius * 0.22, 10.0) * pulse
		var rot := _t * 1.6 if _ex < 0.0 else _t * 1.6 + _ex * 2.4
		draw_set_transform(_center, rot, Vector2.ONE)
		var pts := PackedVector2Array([
			Vector2(0, -core_r), Vector2(core_r, 0), Vector2(0, core_r), Vector2(-core_r, 0), Vector2(0, -core_r),
		])
		draw_polyline(pts, core_col, 2.5)
		# 星屑：蓄力期向核收拢（ease-in，越到后面越快）；迸散期从近核处向外炸开
		for s in _shards:
			var dir: Vector2 = s["dir"]
			var col: Color = s["col"]
			if _ex < 0.0:
				var k := 1.0 - pow(1.0 - _t, 2.0)
				var r := lerpf(_radius, 4.0, k)
				col.a = 0.15 + 0.6 * _t
				draw_set_transform(_center + dir * r, dir.angle() + float(s["spin"]) * _t, Vector2.ONE)
			else:
				var e := 1.0 - pow(1.0 - _ex, 2.0)
				var r := lerpf(6.0, _radius * 1.7, e)
				col.a = (1.0 - _ex) * 0.75
				draw_set_transform(_center + dir * r, dir.angle() + float(s["spin"]) * (1.0 + _ex), Vector2.ONE)
			var half := 3.2
			draw_colored_polygon(PackedVector2Array([
				Vector2(-half, -half), Vector2(half * 0.4, -half),
				Vector2(half, half * 0.4), Vector2(-half * 0.4, half),
			]), col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
