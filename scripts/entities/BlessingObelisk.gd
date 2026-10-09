class_name BlessingObelisk
extends Node2D

## 聚灵阵 — 玩家主动长按激活的阵法节点。
## 玩家进入范围后 HUD 显示激活按钮，长按充能，松手前完成则触发全屏灵气冲击；
## 松手过早或离开范围则中断充能、进度归零。
## 触发后进入「耗尽灰相」：熄灯、光圈撤掉、石碑去色 —— 一眼看出这座已经用掉了
## （三座界碑共用同一份 .tscn，所以褪灰材质必须 resource_local_to_scene，见 .tscn）。
##
## 进度读数画在阵法上（用户 2026-10-09 真机）：长按那颗键时拇指正盖在键上，HUD 的
## 充能条被手挡得死死的 —— 眼睛本来就只能盯着阵法，进度不出现在阵法上等于没有进度。
## 于是同一个 ratio 喂三处，全部由本脚本 _process 一处算、三处画，不另编第二套参数：
##   ① 碑脚走针环（ChargeArc）：一整圈暗底轨道 + 从正上方顺时针填满的弧 + 弧头亮点
##   ② 碑身灌灵（desaturate.gdshader 的 fill_ratio）：灵气自下而上把碑灌满
##   ③ 碑顶百分比（Label）：环与灌光给「还剩多少」的形状，数字给准信
## HUD 那根条照旧留着（桌面/鼠标党看得见），它读的是同一条 charge_progress_updated。

## 充能时长（秒）—— 比旧版 3s 短，手感更利落
const CHARGE_TIME: float = 1.5
## 触发伤害
const BLESSING_DAMAGE: float = 85.0
## 击退力度
const KNOCK_FORCE: float = 320.0
## 掉落金色灵石数量
const GEM_COUNT: int = 5
## 爆闪之后转入灰相的时长（秒）
const SPENT_FADE_TIME: float = 0.55
## 耗尽态去色程度（0~1，喂给 desaturate.gdshader）
const SPENT_DESATURATE: float = 1.0

## 走针环半径：贴着碑脚那一圈（碑底画到 y≈+36、半宽 35），刻意画在 85 判定圈之内 ——
## 它是「这座碑的进度」，不许冒充「站在哪儿算在范围内」（范围视觉与判定同源）。
const ARC_RADIUS: float = 46.0
## 走针环线宽（同时也是弧头亮点的尺寸基准）
const ARC_WIDTH: float = 5.0
## 走针环轨道线宽：比进度弧细一档，进度才是主角
const ARC_TRACK_WIDTH: float = 3.0
## 走针起点：正上方，顺时针填满
const ARC_START_ANGLE: float = -PI / 2.0
## 弧上采样点数：一圈 72 段，斜切像素风下够圆
const ARC_POINTS: int = 72
## 走针环从主蓝转到点缀黄的起点：只有最后这一档算「快好了」，全程线性拉色会提前发土
const ARC_WARM_FROM: float = 0.62
## 碑顶百分比的摆位：碑画到 y=-78，再往上留一档
const READOUT_LABEL_POS := Vector2(0, -104)
## 读数淡入/淡出时长（秒）：只做「别闪」，不改进度真值
const READOUT_FADE_TIME: float = 0.15

## 与 HUD 通信的信号
signal activation_available(obelisk: BlessingObelisk)
signal activation_unavailable(obelisk: BlessingObelisk)
signal charge_started(obelisk: BlessingObelisk)
signal charge_progress_updated(obelisk: BlessingObelisk, ratio: float)
signal charge_cancelled(obelisk: BlessingObelisk)
signal blessing_triggered(obelisk: BlessingObelisk)

var is_player_inside: bool = false
var is_charging: bool = false
var is_triggered: bool = false
var charge_time: float = 0.0

@onready var light: PointLight2D = $PointLight2D
@onready var circle_sprite: Node2D = $ChargeCircle
@onready var interaction_area: Area2D = $InteractionArea
## 石碑褪灰走着色器：modulate 乘不出灰色（蓝底乘灰还是蓝），必须按亮度压色
@onready var stone_mat: ShaderMaterial = $Sprite2D.material as ShaderMaterial

var gem_scene: PackedScene = preload("res://scenes/entities/AstralGem.tscn")
var gold_gem_tex: Texture2D = preload("res://assets/art/gem_gold.png")

## 充能期间的粒子效果 —— 灵气汇聚
var _charge_particles: CPUParticles2D = null
## 世界侧进度读数（碑脚环 + 碑顶数字），只在充能期间挂着
var _readout: Node2D = null
var _readout_arc: ChargeArc = null
var _readout_label: Label = null
var _readout_fade: Tween = null
## 已画出去的百分比，用来避免每帧重排一次文本
var _readout_pct: int = -1
## 世界侧读数的进度真值：与 _process 里那条 ratio 同一个数，判据也读它
var _readout_ratio: float = 0.0

## 碑脚走针环：轨道一整圈 + 进度弧 + 弧头。颜色由外部按进度从主蓝拉到点缀黄。
## 尺寸/颜色一律由外层 _build_charge_readout() 灌进来（不在内类里自取外层常量：
## 同一个脚本的内类反向引用外层 class_name 属于自引用解析，Godot 未必接）。
class ChargeArc:
	extends Node2D
	var ratio: float = 0.0
	var radius: float = 46.0
	var width: float = 5.0
	var start_angle: float = -PI / 2.0
	var points: int = 72
	## 颜色一律由外层灌进来（GameStyle 是唯一取色入口，这里只留空默认）
	var track_color: Color = Color(0, 0, 0, 0)
	var track_width: float = 3.0
	var progress_color: Color = Color.WHITE
	var head_color: Color = Color.WHITE

	func _draw() -> void:
		## 轨道比进度细一档、暗一档：先看的是"填到哪儿"，轨道只交代"这是一根会填满的东西"
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, points, track_color, track_width, true)
		if ratio <= 0.0:
			return
		var end_angle: float = start_angle + TAU * clampf(ratio, 0.0, 1.0)
		draw_arc(Vector2.ZERO, radius, start_angle, end_angle, points, progress_color, width, true)
		draw_circle(Vector2.RIGHT.rotated(end_angle) * radius, width * 0.82, head_color)

func _ready() -> void:
	light.energy = 1.2
	circle_sprite.rotation = 0.0
	_setup_charge_particles()
	_build_charge_readout()

func _setup_charge_particles() -> void:
	_charge_particles = CPUParticles2D.new()
	_charge_particles.emitting = false
	_charge_particles.amount = 12
	_charge_particles.lifetime = 0.8
	_charge_particles.explosiveness = 0.0
	_charge_particles.direction = Vector2(0, -1)
	_charge_particles.spread = 180.0
	_charge_particles.gravity = Vector2(0, -30)
	_charge_particles.initial_velocity_min = 20.0
	_charge_particles.initial_velocity_max = 40.0
	_charge_particles.angular_velocity_min = -60.0
	_charge_particles.angular_velocity_max = 60.0
	_charge_particles.scale_amount_min = 1.0
	_charge_particles.scale_amount_max = 2.5
	_charge_particles.color = Color(0.45, 0.85, 1.0, 0.6)
	_charge_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RING
	_charge_particles.emission_ring_radius = 50.0
	_charge_particles.emission_ring_inner_radius = 0.0
	add_child(_charge_particles)

## 世界侧进度读数：碑脚走针环 + 碑顶百分比。平时不显示，充能期间才亮。
## 为什么要它：长按时拇指就压在 HUD 那颗键上，键底下的充能条被手挡得看不见
## （用户 2026-10-09 真机图）。眼睛当时能看的只有阵法本身。
func _build_charge_readout() -> void:
	_readout = Node2D.new()
	_readout.name = "ChargeReadout"
	_readout.visible = false
	## 压在碑身之上（同一 MapLayer 内），仍在人物/妖物之下 —— 环是地上的东西
	_readout.z_index = 2
	add_child(_readout)

	_readout_arc = ChargeArc.new()
	_readout_arc.radius = ARC_RADIUS
	_readout_arc.width = ARC_WIDTH
	_readout_arc.track_width = ARC_TRACK_WIDTH
	_readout_arc.start_angle = ARC_START_ANGLE
	_readout_arc.points = ARC_POINTS
	## 轨道取 GameStyle 的描线色（唯一取色入口），只留一半存在感：
	## 满屏深黑圈会把「填到哪儿」那件事盖掉
	_readout_arc.track_color = Color(GameStyle.LINE, 0.55)
	_readout.add_child(_readout_arc)

	_readout_label = Label.new()
	var ls := LabelSettings.new()
	ls.font = GameStyle.body_font()
	ls.font_size = 15
	ls.outline_size = 5
	ls.outline_color = Color(0.02, 0.03, 0.06, 0.92)
	_readout_label.label_settings = ls
	_readout_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_readout_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_readout_label.custom_minimum_size = Vector2(120, 22)
	_readout_label.position = READOUT_LABEL_POS - Vector2(60, 11)
	_readout.add_child(_readout_label)

	if stone_mat != null:
		## 灌灵色仍从 GameStyle 取，不在着色器里留一份第二真话
		stone_mat.set_shader_parameter("fill_color", GameStyle.GOLD_EDGE)

## 读数上屏（淡入）：淡的只是外观，进度真值由 _set_readout_ratio 单独维护
func _show_readout() -> void:
	if _readout == null:
		return
	if _readout_fade != null and _readout_fade.is_valid():
		_readout_fade.kill()
	_readout.visible = true
	_readout.modulate.a = 0.0
	_readout_fade = create_tween()
	_readout_fade.tween_property(_readout, "modulate:a", 1.0, READOUT_FADE_TIME)

## 读数下屏（淡出）：松手过早、走出范围、已触发都走这里
func _hide_readout() -> void:
	if _readout == null or not _readout.visible:
		return
	if _readout_fade != null and _readout_fade.is_valid():
		_readout_fade.kill()
	_readout_fade = create_tween()
	_readout_fade.tween_property(_readout, "modulate:a", 0.0, READOUT_FADE_TIME)
	_readout_fade.tween_callback(func() -> void: _readout.visible = false)

## 三处同源：碑脚环、碑身灌光、碑顶百分比都读同一个 ratio（= charge_time / CHARGE_TIME）
func _set_readout_ratio(ratio: float) -> void:
	_readout_ratio = clampf(ratio, 0.0, 1.0)
	if _readout_arc != null:
		_readout_arc.ratio = _readout_ratio
		## 转黄只留给最后一档：线性拉色的话充到六成半就已经是土黄，看着像"卡住了"
		var warm: float = smoothstep(ARC_WARM_FROM, 1.0, _readout_ratio)
		_readout_arc.progress_color = GameStyle.GOLD.lerp(GameStyle.JADE, warm)
		_readout_arc.head_color = GameStyle.GOLD_EDGE.lerp(GameStyle.JADE_EDGE, warm)
		_readout_arc.queue_redraw()
	if _readout_label != null:
		var pct: int = int(roundf(_readout_ratio * 100.0))
		if pct != _readout_pct:
			_readout_pct = pct
			_readout_label.text = "%d%%" % pct
			_readout_label.add_theme_color_override("font_color",
				GameStyle.PAPER.lerp(GameStyle.JADE_EDGE, smoothstep(ARC_WARM_FROM, 1.0, _readout_ratio)))
	if stone_mat != null:
		stone_mat.set_shader_parameter("fill_ratio", _readout_ratio)

## 世界侧读数最后画出来的进度真值（判据与 HUD 条同源用）：中断即归零、放满停在 1.0
func readout_ratio() -> float:
	return _readout_ratio

## 世界侧读数此刻是否挂在阵法上（淡出尾巴仍算挂着，进度真值已经归零）
func is_readout_shown() -> bool:
	return _readout != null and _readout.visible

func _process(delta: float) -> void:
	if is_triggered:
		return
	if is_charging:
		charge_time = minf(CHARGE_TIME, charge_time + delta)
		var ratio: float = charge_time / CHARGE_TIME
		charge_progress_updated.emit(self, ratio)
		_set_readout_ratio(ratio)
		# 充能视觉反馈：光能随进度提升
		light.energy = 1.2 + ratio * 2.3
		# 灵符环旋转加速 —— 充能越快转越急
		circle_sprite.rotation += delta * (1.8 + ratio * 5.0)
		if charge_time >= CHARGE_TIME:
			_trigger_blessing()

## HUD 调用：玩家按下激活按钮
func start_charge() -> void:
	if is_triggered or not is_player_inside:
		return
	is_charging = true
	charge_time = 0.0
	_set_readout_ratio(0.0)
	_show_readout()
	charge_started.emit(self)
	if _charge_particles != null:
		_charge_particles.emitting = true

## HUD 调用：玩家松开激活按钮
func stop_charge() -> void:
	if not is_charging:
		return
	is_charging = false
	if _charge_particles != null:
		_charge_particles.emitting = false
	if charge_time < CHARGE_TIME:
		# 未完成 → 取消，进度归零（碑上的读数跟着一起归零，不许留半截看着像还在充）
		charge_time = 0.0
		light.energy = 1.2
		circle_sprite.rotation = 0.0
		_set_readout_ratio(0.0)
		_hide_readout()
		charge_cancelled.emit(self)

func _trigger_blessing() -> void:
	is_triggered = true
	is_charging = false
	if _charge_particles != null:
		_charge_particles.emitting = false
	## 进度读数收工：兑现由冲击波接管，环再留着就是多余的读数
	_hide_readout()
	blessing_triggered.emit(self)
	AudioManager.play_sfx("obelisk_blessing")
	GameManager.feedback(GameManager.FeedbackTier.HEAVY)
	JuiceEffect.spawn_death_burst(get_parent(), global_position, true)
	GameManager.announcement_triggered.emit("⚡ 护山大阵启动 · 灵气荡涤四方 ⚡")
	_spawn_shockwave_ring()
	# 对范围内所有敌人造成伤害与击退
	# 方向走 GameBalance.knock_dir（永不把敌人往玩家身上推）
	var enemies = get_tree().get_nodes_in_group("enemies")
	var player_pos: Vector2 = global_position if GameManager.player == null else GameManager.player.global_position
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy.has_method("take_damage"):
			var knock = GameBalance.knock_dir(global_position, enemy.global_position, player_pos) * KNOCK_FORCE
			enemy.take_damage(BLESSING_DAMAGE, knock, true)
	# 掉落金色灵石
	for i in range(GEM_COUNT):
		var gem = gem_scene.instantiate() as AstralGem
		var offset = Vector2(randf_range(-40.0, 40.0), randf_range(-40.0, 40.0))
		gem.global_position = global_position + offset
		gem.is_gold = true
		gem.exp_value = 10
		gem.get_node("Sprite2D").texture = gold_gem_tex
		gem.get_node("PointLight2D").color = Color(1.0, 0.85, 0.35)
		get_parent().call_deferred("add_child", gem)
	# 触发视觉：光能爆闪一下作为兑现，随后彻底熄灯、光圈散尽、石碑褪成灰相
	var tw = create_tween()
	tw.tween_property(light, "energy", 5.0, 0.12)
	tw.tween_property(light, "energy", 0.0, SPENT_FADE_TIME)
	tw.parallel().tween_property(circle_sprite, "modulate:a", 0.0, SPENT_FADE_TIME)
	if stone_mat != null:
		tw.parallel().tween_property(stone_mat, ^"shader_parameter/amount", SPENT_DESATURATE, SPENT_FADE_TIME)
		tw.parallel().tween_property(stone_mat, ^"shader_parameter/fill_ratio", 0.0, SPENT_FADE_TIME)
	tw.tween_callback(_enter_spent_look)

## 灰相收口：灯直接关掉、范围环不再占位（看不见却还在的圈就是 bug）
func _enter_spent_look() -> void:
	light.enabled = false
	circle_sprite.visible = false

## 触发时的扩散灵气环 —— 视觉冲击
func _spawn_shockwave_ring() -> void:
	var ring := Sprite2D.new()
	ring.texture = circle_sprite.get_node("RingSprite").texture
	ring.modulate = Color(0.45, 0.85, 1.0, 0.7)
	ring.scale = Vector2(0.5, 0.5)
	ring.z_index = 10
	get_parent().add_child(ring)
	ring.global_position = global_position
	var tw = create_tween()
	tw.tween_property(ring, "scale", Vector2(6.0, 6.0), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(ring, "modulate:a", 0.0, 0.45)
	tw.tween_callback(ring.queue_free)

func _on_interaction_area_body_entered(body: Node2D) -> void:
	if body is Player and not is_triggered:
		is_player_inside = true
		activation_available.emit(self)

func _on_interaction_area_body_exited(body: Node2D) -> void:
	if body is Player:
		if is_charging:
			stop_charge()
		is_player_inside = false
		if not is_triggered:
			activation_unavailable.emit(self)
