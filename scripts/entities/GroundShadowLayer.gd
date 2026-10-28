class_name GroundShadowLayer
extends Node2D

## 全场地面投影层（2026-10-28 渲染性能治理）。
##
## 根因：地影原先由每个实体自己的渲染器在 `_draw` 里用 2 个多边形椭圆画（外层弥散 + 内层接触暗核）。
## 每个 CanvasItem 是各自独立的绘制对象，跨 item 不合并批次 ⇒ 每只敌人 2~3 个绘制调用、
## 每颗宝石 2 个，满场 48 敌 + 140 宝石就是 300+ 个调用只为了几摊影子；宝石侧还要每次重绘
## 新建 2 个 PackedVector2Array（20Hz × 140 颗 = 每秒上万次分配）。
##
## 改法：投影集中到本节点一个 CanvasItem 里画，全部用同一张共享径向渐变贴图铺矩形。
## 同一 item、同贴图、同材质的连续矩形在兼容渲染器里合成极少数批次，实体自己不再画影子。
## 本层是 EntitiesLayer 的第一个子节点，层级天然落在所有实体之下（不需要动 z_index：
## 负数 z 会被 MapLayer 的地面盖住）。
##
## 口径：实体在**重绘时**上报（20/30Hz 节流的节奏），本层按 30Hz 重画；
## 位置每帧从 caster 的全局变换现算 ⇒ 影子跟随移动，尺寸/透明度沿用上报值（软影看不出差）。
## 池化实体出树即自动作废（`is_instance_valid` + `is_inside_tree` 双判，无需额外解绑）。

## 目标重绘间隔（30Hz）。影子是软边大块，30Hz 跟随与实体 20/30Hz 的重绘同档，肉眼无差。
const REDRAW_INTERVAL := 1.0 / 30.0
## 外层弥散影的透明度系数与内层接触暗核的尺寸/透明度系数（与旧矢量双层影同口径）
const OUTER_ALPHA := 0.52
const INNER_SCALE := 0.58
const INNER_ALPHA := 1.55
const INNER_DEPTH := 0.4
## 默认影子色（近黑冷调，与旧 draw_filled_ellipse 的底色一致）
const DEFAULT_TINT := Color(0.04, 0.05, 0.08)

class Slot extends RefCounted:
	var id: int = 0
	var node: CanvasItem = null
	var offset: Vector2 = Vector2.ZERO  ## 影子中心在渲染器本地坐标里的偏移（一般只有 y 分量）
	var rx: float = 8.0
	var ry: float = 2.5
	var alpha: float = 0.45
	var tint: Color = DEFAULT_TINT

static var _instance: GroundShadowLayer = null
static var _slots: Dictionary = {}      ## id(int) -> Slot，首次上报时建槽
static var _list: Array[Slot] = []      ## 同内容的顺序表（绘制时免 Dictionary 遍历开销）
static var _soft_tex: Texture2D = null

var _redraw_acc := 0.0

func _ready() -> void:
	name = "GroundShadowLayer"
	# 层级：插到父节点第一位，保证同 z_index 下先于所有实体绘制
	if get_parent() != null:
		get_parent().move_child(self, 0)
	_instance = self
	set_process(true)

func _exit_tree() -> void:
	if _instance == self:
		_instance = null

## 自建实例的脚本路径：本脚本内不能直接写类名（编译期类名尚未注册），走 preload 常量。
const SCRIPT_PATH := "res://scripts/entities/GroundShadowLayer.gd"

## 由 Main 在场景装配时调用（只建一次）。重复调用返回既有实例。
static func ensure(parent: Node) -> GroundShadowLayer:
	if _instance != null and is_instance_valid(_instance) and _instance.is_inside_tree():
		return _instance
	var layer = load(SCRIPT_PATH).new()
	parent.add_child(layer)
	return layer

## 实体重绘时上报自己的影子（本地偏移 + 世界半径）。同 id 复用槽位，稳态零分配。
static func push(caster: CanvasItem, offset: Vector2, rx: float, ry: float, alpha: float,
		tint := DEFAULT_TINT) -> void:
	if _instance == null or not is_instance_valid(_instance):
		return
	var id := caster.get_instance_id()
	var slot: Slot = _slots.get(id)
	if slot == null:
		slot = Slot.new()
		slot.id = id
		slot.node = caster
		_slots[id] = slot
		_list.append(slot)
	slot.offset = offset
	slot.rx = rx
	slot.ry = ry
	slot.alpha = alpha
	slot.tint = tint

## 实体停画影子时撤销（例如渲染器切了样式）。池化/死亡不必调用，出树自动跳过。
static func erase(caster: CanvasItem) -> void:
	var id := caster.get_instance_id()
	if _slots.erase(id):
		for i in range(_list.size() - 1, -1, -1):
			if _list[i].node == caster:
				_list.remove_at(i)
				break

## 共享软影贴图（径向渐变：中心一段平顶再向外淡出，比纯线性更接近原来的实心椭圆边）。
static func soft_texture() -> Texture2D:
	if _soft_tex != null:
		return _soft_tex
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	g.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	# 平顶 62%：保留「实心影 + 柔边」的旧观感，避免整块变成高斯模糊
	g.add_point(0.62, Color(1.0, 1.0, 1.0, 1.0))
	g.add_point(0.86, Color(1.0, 1.0, 1.0, 0.42))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 64
	t.height = 64
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	_soft_tex = t
	return _soft_tex

## 当前登记的影子槽位数（判据用：确认实体确实在向上报，而不是整体不画影子）
static func debug_slot_count() -> int:
	return _list.size()

func _process(delta: float) -> void:
	_redraw_acc += delta
	if _redraw_acc < REDRAW_INTERVAL:
		return
	_redraw_acc = 0.0
	# 清槽放在 _process 而不是 _draw：无头/判据里根本没有真实绘制，靠 _draw 清会一直攒野槽
	_prune_dead()
	if _list.is_empty():
		return
	queue_redraw()

## 出树/释放的 caster 逐出登记表（池化实体回收后不会再上报，必须在这里收）
func _prune_dead() -> void:
	var i := _list.size() - 1
	while i >= 0:
		var slot: Slot = _list[i]
		var node = slot.node
		if node == null or not is_instance_valid(node) or not node.is_inside_tree():
			_slots.erase(slot.id)
			_list.remove_at(i)
		i -= 1

func _draw() -> void:
	var tex := soft_texture()
	# 视口世界矩形（每帧一次）：屏外实体连影子都不用画
	var xform := get_viewport().get_canvas_transform()
	var view := get_viewport().get_visible_rect()
	var inv := xform.affine_inverse()
	var tl: Vector2 = inv * view.position
	var br: Vector2 = inv * (view.position + view.size)
	var dead: Array[Slot] = []
	for slot in _list:
		var node: CanvasItem = slot.node
		if node == null or not is_instance_valid(node) or not node.is_inside_tree():
			dead.append(slot)
			continue
		if not node.is_visible_in_tree():
			continue
		var world: Vector2 = node.get_global_transform() * slot.offset
		if world.x < tl.x - slot.rx or world.x > br.x + slot.rx \
				or world.y < tl.y - slot.ry or world.y > br.y + slot.ry:
			continue
		var p := to_local(world)
		var c := slot.tint
		draw_texture_rect(tex, Rect2(p.x - slot.rx, p.y - slot.ry, slot.rx * 2.0, slot.ry * 2.0),
			false, Color(c.r, c.g, c.b, slot.alpha * OUTER_ALPHA))
		var irx := slot.rx * INNER_SCALE
		var iry := slot.ry * INNER_SCALE
		draw_texture_rect(tex, Rect2(p.x - irx, p.y - iry, irx * 2.0, iry * 2.0),
			false, Color(c.r * INNER_DEPTH, c.g * INNER_DEPTH, c.b * INNER_DEPTH,
				minf(slot.alpha * INNER_ALPHA, 0.90)))
	if not dead.is_empty():
		for slot in dead:
			_slots.erase(slot.id)
			_list.erase(slot)