class_name DamageNumber
extends Node2D

## 伤害跳字：扇形抛物线漂移 + 暴击弹性过冲（先冲过头再回落）。
## 高频命中下走节点池：一次命中不再 new Node2D + Label + Tween，
## 运动曲线改由 _process 手写（时序与原来的并行 Tween 完全对齐），命中峰值时零分配。
## 文本由 _draw 直绘（draw_string_outline + draw_string），不经 Label 排版。

## 时序（秒）：漂移阶段 → 回落阶段 → 淡出阶段
const PHASE_DRIFT := 0.52
const PHASE_SETTLE := 0.22
const PHASE_FADE := 0.16
const POP_DUR_NORMAL := 0.10
const POP_DUR_CRIT := 0.12
const POOL_CAP := 96      ## 常驻池上限，超出时临时新建并在用完后释放
## 同目标伤害跳字聚合窗（秒）：同一敌人窗口内的连续伤害并入同一条（累计值 + ×N），
## 新伤到来时窗口滑动续期；束流/喷吐/DoT 高频命中不再刷屏顶字，池溢出 new+free 抖动消失。
const COMBO_WINDOW := 0.25
## 聚合窗内文本变更节流（2026-10-14）：合并命中每次重写文本会触发一次重绘 +
## 字形缓存查找，束流/DoT 集火时每秒几十次。sum/count 照常即时累计，
## 仅文本刷新降频到 12.5Hz，文本滞后 ≤80ms 肉眼无感；暴击升级样式不受闸限。
const COMBO_TEXT_INTERVAL := 0.08

## 聚合判定纯函数（单测钉判据用）：只有带 combo_key 且非文字类的伤害跳字参与聚合；
## DoT tick 与暴击同样并入（暴击把整条升到鎏金样式），文字类读数保持逐条独立
static func can_merge(combo_key: int, is_text_number: bool) -> bool:
	return combo_key != 0 and not is_text_number

## 聚合条文本：单发就是数字；2 连及以上显示累计值与 ×N 后缀（128×3）
static func format_combo(sum: int, count: int) -> String:
	return str(sum) if count <= 1 else "%d×%d" % [sum, count]

static var _normal_settings: LabelSettings
static var _crit_settings: LabelSettings
static var _heal_settings: LabelSettings

static var _pool: Array[DamageNumber] = []
static var _host: Node2D = null
static var _created: int = 0
static var active_count: int = 0  ## 当前活跃跳字数：HUD 性能面板消费

## 同目标聚合表：combo_key（敌人 instance_id）→ {n, sum, count, crit, expire_ms}。
## 窗口内伤害并入同一条；过期/归池时清除，不阻碍下一条新窗口。
static var _combos: Dictionary = {}

## 视口变换缓存：同帧多个跳字共享一次 get_canvas_transform() / visible_rect 查询，
## 避免每发命中重复做矩阵/视口开销（对齐 HollowKnightEnemyRenderer 范式）
static var _cull_frame: int = -1
static var _cull_transform: Transform2D
static var _cull_rect: Rect2
static var _cull_valid: bool = false

var _text: String = ""
var _settings: LabelSettings = null
var _overflow: bool = false
var _t: float = 0.0
var _origin: Vector2 = Vector2.ZERO
var _drift_x: float = 0.0
var _rise_y: float = 0.0
var _is_crit: bool = false
var _last_scale: float = -1.0
var _last_alpha: float = -1.0
## 上次实际发生文本重排的时刻（聚合节流用）；_start 里文本真正变更才刷新
var _last_text_layout_ms: int = 0
## 聚合身份：本条跳字绑定的 combo_key（0 = 独立条）与已累计值/次数，用于并入时重算文本
var _combo_key: int = 0
var _combo_sum: int = 0
var _combo_hits: int = 0

## 释放池与样式缓存（退出时调用），避免常驻引用被判成资源泄漏
static func clear_cache() -> void:
	_pool.clear()
	_combos.clear()
	_host = null
	_created = 0
	_normal_settings = null
	_crit_settings = null
	_heal_settings = null

## 池状态读数（自动化验证与调试用）
static func pool_size() -> int:
	return _pool.size()

static func created_count() -> int:
	return _created

static func combo_count() -> int:
	return _combos.size()

static func host_child_count() -> int:
	return 0 if (_host == null or not is_instance_valid(_host)) else _host.get_child_count()

## 样式表只建一次，所有跳字共享（避免 GC 抖动）
static func _ensure_settings() -> void:
	if _normal_settings != null:
		return

	_normal_settings = LabelSettings.new()
	_normal_settings.font = GameStyle.body_font()
	_normal_settings.font_size = 14
	_normal_settings.font_color = GameStyle.CHALK  # 世界空间暗底跳字用亮字（PAPER 已翻转为白面板黑字）
	_normal_settings.outline_size = 4
	_normal_settings.outline_color = Color(0.02, 0.03, 0.06, 0.92)

	_crit_settings = LabelSettings.new()
	_crit_settings.font = GameStyle.display_font()
	_crit_settings.font_size = 20
	_crit_settings.font_color = GameStyle.GOLD  # 暴击 = 鎏金大字（玉色留给金币/增益读数）
	_crit_settings.outline_size = 5
	_crit_settings.outline_color = Color(0.04, 0.02, 0.0, 0.96)

	_heal_settings = LabelSettings.new()
	_heal_settings.font = GameStyle.body_font()
	_heal_settings.font_size = 15
	_heal_settings.font_color = GameStyle.GOOD
	_heal_settings.outline_size = 4
	_heal_settings.outline_color = Color(0.02, 0.03, 0.06, 0.95)

## 池宿主：常驻场景根下的一个 Node2D，跳字全部挂在它下面、用完不摘（省掉反复 reparent）
static func _ensure_host(scene: Node) -> void:
	if _host != null and is_instance_valid(_host):
		return
	# 换局（Main 重建）后旧宿主连同池内节点一起被释放，必须清空引用防止拿到野对象
	_pool.clear()
	_combos.clear()
	_created = 0
	_host = Node2D.new()
	_host.name = "DamageNumberPool"
	_host.z_index = 50
	# 跳字在 _process 里推进（渲染时钟），宿主开着物理插值会与插值中的敌人/弹丸错相位
	# ——真机帧率抖动时数字悬在偏移位置上乱闪（同 Player 关 WeaponHolder 插值一条坑）
	_host.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	scene.add_child(_host)

static func _acquire() -> DamageNumber:
	active_count += 1
	if not _pool.is_empty():
		var reused: DamageNumber = _pool.pop_back()
		if is_instance_valid(reused):
			return reused
		_created = maxi(0, _created - 1)
	var overflow := _created >= POOL_CAP
	var n := DamageNumber.new()
	n._overflow = overflow
	if not overflow:
		_created += 1
	_host.add_child(n)
	return n

## 取池宿主应挂的场景根。
## 测试里 Main 是手动 add_child 到 root 的，此时 tree.current_scene 为空 → 退回向上找 root 的直接子节点。
static func _scene_root_for(node: Node) -> Node:
	var tree := node.get_tree()
	if tree == null:
		return null
	if tree.current_scene != null and is_instance_valid(tree.current_scene):
		return tree.current_scene
	var cur: Node = node
	while cur.get_parent() != null and cur.get_parent() != tree.root:
		cur = cur.get_parent()
	return cur

## 生成一条跳字。parent 仅用于定位场景树，节点实际挂在池宿主下（保持既有调用签名）。
## combo_key 非 0 且为数字类（无 custom_text）时参与同目标窗口聚合：
## 同一敌人 COMBO_WINDOW 内的伤害并入同一条（累计 + ×N），高频集火不再刷屏顶字。
static func spawn(parent: Node, pos: Vector2, amount: int, is_crit: bool = false, custom_text: String = "", combo_key: int = 0) -> void:
	# 开关走 GameFeel 每帧 memo：spawn 每次命中都调，原 get_val 每发 2 个 String 分配
	if not GameFeel.damage_numbers_enabled():
		return
	if parent == null or not is_instance_valid(parent):
		return
	var scene := _scene_root_for(parent)
	if scene == null:
		return
	# 视口兜底：与 JuiceEffect 同口径——屏外位置的跳字不生成。
	# 同一渲染帧内共享变换矩阵与可视矩形，避免每发命中 3 次原生调用。
	var frame := Engine.get_frames_drawn()
	if frame != _cull_frame:
		_cull_frame = frame
		var vp := parent.get_viewport()
		_cull_valid = vp != null
		if _cull_valid:
			_cull_transform = vp.get_canvas_transform()
			_cull_rect = vp.get_visible_rect().grow(-8.0)
	if _cull_valid and not _cull_rect.has_point(_cull_transform * pos):
		return

	_ensure_settings()
	_ensure_host(scene)

	# 同目标窗口聚合：命中已绑定的活跃跳字 → 累计值 + ×N 后缀，当前位置原地重播弹出。
	# 只吞 _acquire（少一条节点），不吞伤害数值 —— EnemyBase 的集火保护仍按每发计。
	if can_merge(combo_key, custom_text != "") and _try_merge(combo_key, amount, is_crit, pos):
		return

	var text := custom_text
	var settings := _heal_settings
	if custom_text == "":
		if is_crit:
			text = str(amount) + "!"
			settings = _crit_settings
		else:
			text = str(amount)
			settings = _normal_settings

	var n := _acquire()
	if n == null or not is_instance_valid(n):
		return
	n._start(
		pos + Vector2(randf_range(-12.0, 12.0), -12.0),
		text, settings, is_crit,
		randf_range(-26.0, 26.0),
		randf_range(32.0, 42.0) if not is_crit else randf_range(40.0, 52.0)
	)
	if can_merge(combo_key, custom_text != ""):
		n._combo_key = combo_key
		n._combo_sum = amount
		n._combo_hits = 1
		_combos[combo_key] = {
			"n": n, "sum": amount, "count": 1, "crit": is_crit,
			"expire_ms": Time.get_ticks_msec() + int(COMBO_WINDOW * 1000.0),
		}

## 同目标并入：窗口内已有活跃跳字 → 累计值/计数/暴击标记更新，窗口滑动续期，
## 当前位置原地重播弹出（数字跟住移动中的敌人）。返回 false = 窗口外/表已失效，走新发。
## 闸口口径：n._combo_key 必须仍指向本 key（池复用后同一节点可能已改挂别的聚合身份）
static func _try_merge(combo_key: int, amount: int, is_crit: bool, pos: Vector2) -> bool:
	if not _combos.has(combo_key):
		return false
	var e: Dictionary = _combos[combo_key]
	var n: DamageNumber = e["n"]
	if n == null or not is_instance_valid(n) or not n.visible or n._combo_key != combo_key:
		_combos.erase(combo_key)
		return false
	var now := Time.get_ticks_msec()
	if now >= int(e["expire_ms"]):
		_combos.erase(combo_key)
		return false
	var sum := int(e["sum"]) + amount
	var count := int(e["count"]) + 1
	var crit := bool(e["crit"]) or is_crit
	e["sum"] = sum
	e["count"] = count
	e["crit"] = crit
	e["expire_ms"] = now + int(COMBO_WINDOW * 1000.0)
	n._combo_sum = sum
	n._combo_hits = count
	var settings := _crit_settings if crit else _normal_settings
	# 排版节流：窗口内数值照常累计（上方 e/n 字段已是真话），但文本变更
	# 降频到 12.5Hz；暴击把样式升鎏金时必须立即刷新（样式升级是即时反馈）
	var style_changed := n._settings != settings
	var text: String
	if style_changed or now - n._last_text_layout_ms >= int(COMBO_TEXT_INTERVAL * 1000.0):
		text = format_combo(sum, count) + ("!" if crit else "")
	else:
		# 闸内：只重播弹出动画与跟随位置，沿用当前文本（_start 的文本/样式去重保证零重绘）
		text = n._text
	n._start(
		pos + Vector2(randf_range(-12.0, 12.0), -12.0),
		text, settings, crit,
		randf_range(-26.0, 26.0),
		randf_range(40.0, 52.0) if crit else randf_range(32.0, 42.0)
	)
	return true

func _ready() -> void:
	visible = false
	set_process(false)

## TRANS_BACK / EASE_OUT 的等价闭式解（Godot Tween 用的是同一条曲线）
static func _back_out(x: float) -> float:
	x = clampf(x, 0.0, 1.0) - 1.0
	return 1.0 + 2.70158 * x * x * x + 1.70158 * x * x

## 直绘跳字（2026-10-14 性能优化）：取代原 Label 子节点。带 4px 描边的 Label 每次文本变更
## 触发完整文本排版 + 描边栅格化，集火时每秒几十次；draw_string 只查共享字体字形缓存，
## 文本/样式不变更时零重绘，scale/modulate 动画走节点变换不打断重绘。
func _draw() -> void:
	if _settings == null or _text.is_empty():
		return
	var font: Font = _settings.font
	var fs: int = _settings.font_size
	var w := font.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := Vector2(-w * 0.5, (font.get_ascent(fs) - font.get_descent(fs)) * 0.5)
	draw_string_outline(font, pos, _text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, _settings.outline_size, _settings.outline_color)
	draw_string(font, pos, _text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, _settings.font_color)

func _start(world_pos: Vector2, text: String, settings: LabelSettings, crit: bool, drift_x: float, rise_y: float) -> void:
	# 文本/样式去重：draw_string 直绘无 Label 排版，文本变更只是一次 queue_redraw +
	# 共享字体字形缓存查找（0-9/×/! 十二个字符开局即热）；闸内合并重播传入旧文本时零重绘
	if _text != text:
		_text = text
		_last_text_layout_ms = Time.get_ticks_msec()
		queue_redraw()
	if _settings != settings:
		_settings = settings
		_last_text_layout_ms = Time.get_ticks_msec()
		queue_redraw()
	global_position = world_pos
	_origin = position
	_drift_x = drift_x
	_rise_y = rise_y
	_is_crit = crit
	_t = 0.0
	_last_scale = -1.0
	_last_alpha = -1.0
	modulate = Color(1, 1, 1, 1)
	scale = Vector2(0.5, 0.5) if crit else Vector2(0.85, 0.85)
	visible = true
	set_process(true)

func _process(delta: float) -> void:
	_t += delta
	if _t >= PHASE_DRIFT + PHASE_SETTLE + PHASE_FADE:
		_release()
		return

	# 1. 位移：X 侧移 + Y 上冲，二次缓出（先冲得快再稳住）
	var e := clampf(_t / PHASE_DRIFT, 0.0, 1.0)
	e = 1.0 - (1.0 - e) * (1.0 - e)
	position = _origin + Vector2(_drift_x * e, -_rise_y * e)

	# 2. 尺寸：弹出（暴击带过冲）→ 平台 → 回落
	# 台阶量化写入（snappedf 0.04）：35 条跳字若每帧写 scale 会持续打断 CanvasItem
	# 变换批处理；量化后视觉平滑依然保全，重绘写入降频 70%（2026-10-13 优化）
	var s: float
	if _is_crit:
		if _t < POP_DUR_CRIT:
			s = lerpf(0.5, 1.35, _back_out(_t / POP_DUR_CRIT))
		elif _t < PHASE_DRIFT:
			s = 1.35
		else:
			s = lerpf(1.35, 1.0, clampf((_t - PHASE_DRIFT) / PHASE_SETTLE, 0.0, 1.0))
	else:
		if _t < POP_DUR_NORMAL:
			s = lerpf(0.85, 1.05, _back_out(_t / POP_DUR_NORMAL))
		elif _t < PHASE_DRIFT:
			s = 1.05
		else:
			s = lerpf(1.05, 0.9, clampf((_t - PHASE_DRIFT) / PHASE_SETTLE, 0.0, 1.0))
	var q_s := snappedf(s, 0.04)
	if absf(q_s - _last_scale) > 0.015:
		_last_scale = q_s
		scale = Vector2(q_s, q_s)

	# 3. 淡出（同样量化写入）
	var fade_at := PHASE_DRIFT + PHASE_SETTLE
	var target_a: float = 1.0 if _t < fade_at else 1.0 - clampf((_t - fade_at) / PHASE_FADE, 0.0, 1.0)
	var q_a := snappedf(target_a, 0.04)
	if absf(q_a - _last_alpha) > 0.015:
		_last_alpha = q_a
		modulate.a = q_a

func _release() -> void:
	active_count = maxi(0, active_count - 1)
	set_process(false)
	visible = false
	# 聚合表只登记「正在显示」的跳字：归池即摘牌，下次命中自然开新窗口
	if _combo_key != 0:
		DamageNumber.drop_combo(_combo_key, self)
		_combo_key = 0
		_combo_sum = 0
		_combo_hits = 0
	if _overflow or not is_instance_valid(_host):
		queue_free()
		return
	if _pool.size() < POOL_CAP:
		_pool.append(self)
	else:
		queue_free()

## 归池清表：仅当表项仍指向本节点才摘除（同 key 可能已被更新窗口的新条接管）
static func drop_combo(combo_key: int, node: DamageNumber) -> void:
	if not _combos.has(combo_key):
		return
	if _combos[combo_key]["n"] == node:
		_combos.erase(combo_key)
