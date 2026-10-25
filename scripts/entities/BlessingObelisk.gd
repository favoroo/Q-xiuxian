class_name BlessingObelisk
extends Node2D

## 聚灵阵 — 玩家主动长按激活的阵法节点（2026-10-25 重设计：单祭坛 · 每回合金币启动）。
## 玩家进入范围后 HUD 显示激活按钮，长按充能；充满即扣金币并演出「灵石注入」——
## 金铢从玩家身上飞入晶柱，注入完成才爆发：全屏灵气冲击 + 召唤灵兽助战。
## 启动后本回合进入「耗尽灰相」；下一回合开始（wave_changed）自动复燃、可再次启动。
## 金币不够时在 start_charge 入口硬拦（HUD 键是真按得下去的），横幅 + 报错音。
## 启动价显示在 HUD 激活键的键面小字上（HudObeliskButton，2026-10-26 起）——
## 碑体本身不挂任何常驻悬浮文字（用户：很怪）。
##
## 进度读数画在阵法上（用户 2026-10-09 真机）：长按那颗键时拇指正盖在键上，HUD 的
## 充能条被手挡得死死的 —— 眼睛本来就只能盯着阵法，进度不出现在阵法上等于没有进度。
## 于是同一个 ratio 喂三处，全部由本脚本 _process 一处算、三处画，不另编第二套参数：
##   ① 碑脚走针环（ChargeArc）：一整圈暗底轨道 + 从正上方顺时针填满的弧 + 弧头亮点
##   ② 碑身灌灵（desaturate.gdshader 的 fill_ratio）：灵气自下而上把碑灌满
##   ③ 碑顶百分比（Label）：环与灌光给「还剩多少」的形状，数字给准信
## HUD 那根条照旧留着（桌面/鼠标党看得见），它读的是同一条 charge_progress_updated。

## 充能时长（秒）—— 2026-10-11 由 1.5 压到 0.8：缩短站桩窗口，降低引导期间被集火的风险
const CHARGE_TIME: float = 0.8
## 爆闪之后转入灰相的时长（秒）
const SPENT_FADE_TIME: float = 0.55
## 耗尽态去色程度（0~1，喂给 desaturate.gdshader）
const SPENT_DESATURATE: float = 1.0

## 走针环半径：贴着碑脚那一圈（碑底画到 y≈+36、半宽 35），刻意画在 95 判定圈之内 ——
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
## 本回合已启动（灰相）。2026-10-25 重设计：不再是「一局一次」，wave_changed 时自动复燃。
var spent_this_wave: bool = false
## 金币注入进行中：钱已扣、金铢在飞、爆发未放 —— 期间不许再进充能，回合中途结束也不中断
var is_infusing: bool = false
var charge_time: float = 0.0

@onready var light: PointLight2D = get_node_or_null("PointLight2D") as PointLight2D
@onready var circle_sprite: Node2D = get_node_or_null("ChargeCircle") as Node2D
@onready var interaction_area: Area2D = get_node_or_null("InteractionArea") as Area2D
## 石碑褪灰走着色器：modulate 乘不出灰色（蓝底乘灰还是蓝），必须按亮度压色
@onready var stone_mat: ShaderMaterial = (get_node("Sprite2D").material if has_node("Sprite2D") else null) as ShaderMaterial

## 祭坛灵兽（2026-10-11 祭坛强化）：激活时召唤一只，2026-10-25 起最多同场 3 只、存活 3 回合
var beast_scene: PackedScene = preload("res://scenes/entities/SpiritBeast.tscn")

## 程序化矢量阵台渲染器
var _obelisk_renderer: ProceduralObeliskRenderer = null

## 复燃时要把灯光颜色 tween 回出厂值（tscn 里的青蓝），_ready 存底
var _light_base_color: Color = Color(0.45, 0.85, 1.0)

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
	if light != null:
		light.energy = 1.2
		_light_base_color = light.color
	if circle_sprite != null:
		circle_sprite.rotation = 0.0

	# 隐藏旧像素贴图与粗暴复用的摇杆底图，转由纯矢量悬晶大阵接管渲染
	var old_sprite = get_node_or_null("Sprite2D") as CanvasItem
	if old_sprite != null:
		old_sprite.visible = false
	var old_circle = get_node_or_null("ChargeCircle") as CanvasItem
	if old_circle != null:
		old_circle.visible = false

	if _obelisk_renderer == null:
		_obelisk_renderer = ProceduralObeliskRenderer.new()
		add_child(_obelisk_renderer)
		# 确保层级在交互圈之下但在地面之上
		move_child(_obelisk_renderer, 0)

	_setup_charge_particles()
	_build_charge_readout()
	# 回合更替时灰相复燃（价格显示在 HUD 激活键上，随波上涨由键自己读现价，碑不再挂常驻字）
	if not GameManager.wave_changed.is_connected(_on_wave_changed):
		GameManager.wave_changed.connect(_on_wave_changed)

func _setup_charge_particles() -> void:
	# 界碑充能粒子（T-3.6）：外圈螺旋向心吸入（空洞骑士 Focus 灵气聚流）
	_charge_particles = CPUParticles2D.new()
	_charge_particles.emitting = false
	_charge_particles.amount = 16
	_charge_particles.lifetime = 0.75
	_charge_particles.explosiveness = 0.0
	_charge_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RING
	_charge_particles.emission_ring_radius = 64.0
	_charge_particles.emission_ring_inner_radius = 52.0
	_charge_particles.gravity = Vector2.ZERO
	_charge_particles.initial_velocity_min = 6.0
	_charge_particles.initial_velocity_max = 14.0
	_charge_particles.radial_accel_min = -80.0
	_charge_particles.radial_accel_max = -130.0
	_charge_particles.tangential_accel_min = 40.0
	_charge_particles.tangential_accel_max = 70.0
	_charge_particles.angular_velocity_min = -60.0
	_charge_particles.angular_velocity_max = 60.0
	_charge_particles.scale_amount_min = 1.4
	_charge_particles.scale_amount_max = 2.8
	## 2026-10-21 精修：寸缕内卷——尺寸沿寿命「小→大→收」曲线，配合轻微阻尼，
	## 让吸入更像被丹田吸扯而非匀速穿场（数量维持 16，不越粒子预算）。
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.35))
	sc.add_point(Vector2(0.45, 1.0))
	sc.add_point(Vector2(1.0, 0.18))
	_charge_particles.scale_amount_curve = sc
	_charge_particles.damping_min = 6.0
	_charge_particles.damping_max = 14.0
	_charge_particles.color = Color(0.45, 0.85, 1.0, 0.75)
	add_child(_charge_particles)

## 世界侧进度读数：碑脚走针环 + 碑顶百分比。平时不显示，充能期间才亮。
## 为什么要它：长按时拇指就压在 HUD 那颗键上，键底下的充能条被手挡得看不见
## （用户 2026-10-09 真机图）。眼睛当时能看的只有阵法本身。
func _build_charge_readout() -> void:
	_readout = Node2D.new()
	_readout.name = "ChargeReadout"
	_readout.visible = false
	## 位于地砖与碑身之上（树顺序后于碑身），但在角色/敌人之下（MapLayer 树序先于 EntitiesLayer，z=0）
	_readout.z_index = 0
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
		stone_mat.set_shader_parameter("fill_color", GameStyle.GOLD_FX_EDGE)
		## fill_ratio/amount 先落成确定值：直接触发（判据不走充能）时 tween 读到 Nil 会报类型错
		stone_mat.set_shader_parameter("fill_ratio", 0.0)
		stone_mat.set_shader_parameter("amount", 0.0)

## 回合开始：上回合灰相的祭坛在此复燃（启动价的显示在 HUD 激活键上，键自己读现价）
func _on_wave_changed(_wave_number: int) -> void:
	if spent_this_wave:
		spent_this_wave = false
		_revive_from_spent()

## 灰相反向：灯光复燃、石碑回色、阵盘重亮，泽青灵环宣告「下回合又能用了」
func _revive_from_spent() -> void:
	var tw := create_tween()
	if light != null:
		light.enabled = true
		tw.tween_property(light, "energy", 1.2, 0.4)
		tw.parallel().tween_property(light, "color", _light_base_color, 0.4)
	if circle_sprite != null:
		circle_sprite.visible = true
		tw.parallel().tween_property(circle_sprite, "modulate:a", 1.0, 0.4)
	if stone_mat != null:
		tw.parallel().tween_property(stone_mat, ^"shader_parameter/amount", 0.0, 0.4)
		tw.parallel().tween_property(stone_mat, ^"shader_parameter/fill_ratio", 0.0, 0.4)
	if _obelisk_renderer != null:
		_obelisk_renderer.is_spent = false
		tw.parallel().tween_property(_obelisk_renderer, "spent_blend", 0.0, 0.4)
	var host: Node = get_parent()
	if host != null:
		JuiceEffect.spawn_shockwave(host, global_position, 40.0, Color(0.45, 0.9, 1.0), 0.3)
		FxParticlePool.burst(FxParticlePool.SOUL_ORB, global_position, Color(0.45, 0.85, 1.0, 1.0), 1.0, true)
	# 玩家正好站在阵里：复活即把激活键请回来，不必让他走出去再进来
	if is_player_inside:
		activation_available.emit(self)

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
		_readout_arc.progress_color = GameStyle.GOLD_FX.lerp(GameStyle.JADE, warm)
		_readout_arc.head_color = GameStyle.GOLD_FX_EDGE.lerp(GameStyle.JADE_EDGE, warm)
		_readout_arc.queue_redraw()
	if _readout_label != null:
		var pct: int = int(roundf(_readout_ratio * 100.0))
		if pct != _readout_pct:
			_readout_pct = pct
			_readout_label.text = "%d%%" % pct
			_readout_label.add_theme_color_override("font_color",
				GameStyle.CHALK.lerp(GameStyle.JADE_EDGE, smoothstep(ARC_WARM_FROM, 1.0, _readout_ratio)))
	if stone_mat != null:
		stone_mat.set_shader_parameter("fill_ratio", _readout_ratio)
	if _obelisk_renderer != null:
		_obelisk_renderer.fill_ratio = _readout_ratio

## 世界侧读数最后画出来的进度真值（判据与 HUD 条同源用）：中断即归零、放满停在 1.0
func readout_ratio() -> float:
	return _readout_ratio

## 世界侧读数此刻是否挂在阵法上（淡出尾巴仍算挂着，进度真值已经归零）
func is_readout_shown() -> bool:
	return _readout != null and _readout.visible

func _process(delta: float) -> void:
	if _obelisk_renderer != null:
		_obelisk_renderer.is_player_inside = is_player_inside
		_obelisk_renderer.is_charging = is_charging
		_obelisk_renderer.ring_rotation = circle_sprite.rotation
	if spent_this_wave or is_infusing:
		return
	if is_charging:
		# 回合结束守门：敌潮平息后再充满 = 空场释放，白白耗掉这回合唯一的碑。
		# 回合一离开 FIGHT 阶段立即按取消处理（进度归零，碑保留到下一回合）。
		var spawner = GameManager.wave_spawner
		if spawner != null and spawner.phase != WaveSpawner.Phase.FIGHT:
			stop_charge()
			return
		charge_time = minf(CHARGE_TIME, charge_time + delta)
		var ratio: float = charge_time / CHARGE_TIME
		charge_progress_updated.emit(self, ratio)
		_set_readout_ratio(ratio)
		# 充能视觉反馈：光能随进度提升
		light.energy = 1.2 + ratio * 2.3
		# 灯色随进度青→金（2026-10-25 供金主题：连灯色一起往金价靠）
		light.color = _light_base_color.lerp(Color(1.0, 0.9, 0.6), ratio * 0.7)
		# 灵符环旋转加速 —— 充能越快转越急
		circle_sprite.rotation += delta * (1.8 + ratio * 5.0)
		if charge_time >= CHARGE_TIME:
			_begin_infusion()

## HUD 调用：玩家按下激活按钮
func start_charge() -> void:
	if spent_this_wave or is_infusing or not is_player_inside:
		return
	## 金币闸（2026-10-25 重设计）：不够就横幅 + 报错音，不进充能。
	## HUD 圆键是真按得下去的（不像商店先置灰），必须在这里硬拦。
	var cost := GameBalance.obelisk_activation_cost(GameManager.wave_number)
	if GameManager.spirit_stones < cost:
		GameManager.announcement_triggered.emit("金币不够启动祭坛")
		AudioManager.play_sfx("ui_error", 0.9)
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
		light.color = _light_base_color
		circle_sprite.rotation = 0.0
		_set_readout_ratio(0.0)
		_hide_readout()
		charge_cancelled.emit(self)

## 充满即成交：先扣钱，再演「灵石注入」，注入完成才爆发（2026-10-25 重设计）。
## 钱到手就不退：注入中途玩家阵亡 / 回合结束都照常爆发，不因中断吃哑巴亏。
func _begin_infusion() -> void:
	is_charging = false
	if _charge_particles != null:
		_charge_particles.emitting = false
	is_infusing = true
	var cost := GameBalance.obelisk_activation_cost(GameManager.wave_number)
	var player_pos: Vector2 = global_position if GameManager.player == null else GameManager.player.global_position
	GameManager.spirit_stones -= cost
	GameManager.total_stones_spent += cost
	GameManager.stats_updated.emit(GameManager.kills, GameManager.game_time, GameManager.spirit_stones)
	# 供金声：拾金音降音高变体（沉一点的「入账」，不新增音频资产）
	AudioManager.play_sfx("gem_pickup", 0.9, 0.82)
	# 供金扣费飘字挂玩家头顶：钱从玩家身上出；碑顶那片是价格/读数的地盘，别挤在一起
	_spawn_cost_float_text(cost, player_pos)
	# 注入演出：金铢从玩家身上沿弧线飞入晶柱；晶柱随金币落进「饮金」渐亮
	var fx_host: Node = get_parent()
	if fx_host != null:
		ObeliskFx.play_coin_infusion(fx_host, global_position, player_pos)
	if _obelisk_renderer != null:
		var itw := create_tween()
		itw.tween_property(_obelisk_renderer, "infuse_ratio", 1.0, ObeliskFx.INFUSION_DUR)
	var tw := create_tween()
	tw.tween_interval(ObeliskFx.INFUSION_DUR)
	tw.tween_callback(_release_blessing)

## 供金扣费飘字：金色「-N」从玩家头顶上浮淡出（低频事件，一次性 Label 自释放；
## 不走 DamageNumber——它的自定义文案固定治疗绿，扣费用绿字会读错）
func _spawn_cost_float_text(cost: int, from_pos: Vector2) -> void:
	var host: Node = get_parent()
	if host == null:
		return
	var lbl := Label.new()
	var ls := LabelSettings.new()
	ls.font = GameStyle.body_font()
	ls.font_size = 16
	ls.font_color = GameStyle.JADE
	ls.outline_size = 5
	ls.outline_color = Color(0.02, 0.03, 0.06, 0.92)
	lbl.label_settings = ls
	lbl.text = "-%d" % cost
	lbl.z_index = 5
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(lbl)
	lbl.global_position = from_pos + Vector2(-30.0, -76.0)
	var tw := lbl.create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y - 26.0, 0.8).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.8).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(lbl.queue_free)

## 注入完成 → 爆发：全屏冲击 + 召灵兽 + 转灰相（伤害/击退走随波公式）
func _release_blessing() -> void:
	is_infusing = false
	spent_this_wave = true
	## 进度读数收工：兑现由冲击波接管，环再留着就是多余的读数
	_hide_readout()
	blessing_triggered.emit(self)
	AudioManager.play_sfx("obelisk_blessing")
	GameManager.feedback(GameManager.FeedbackTier.HEAVY)
	GameManager.announcement_triggered.emit("◆ 灵石注阵 · 灵兽现身助战 ◆")
	## 激活演出（2026-10-25 强化）：三重地面环 + 通天青金光柱 + 全屏冲击环，
	## 由 ObeliskFx 一次性自释放节点接管（不常驻不占预算）。
	var fx_host: Node = get_parent()
	if fx_host != null:
		ObeliskFx.play_activation(fx_host, global_position)
		ObeliskFx.play_shock_ring(fx_host, global_position)
	# 一次性喷发粒子：低频事件，绕过同帧限流（金色灵气光柱向上喷）
	FxParticlePool.burst(FxParticlePool.LEVEL_PILLAR, global_position, GameStyle.FX_HDR_GOLD, 1.0, true)
	if _obelisk_renderer != null:
		_obelisk_renderer.activation_flash = 1.0
	_summon_spirit_beast()
	# 对场上所有敌人造成伤害与击退（冲击波是全场光环演出，不是范围判定——口径走 EnemyFilter，
	# radius 传 INF 即「全场」；方向走 GameBalance.knock_dir，永不把敌人往玩家身上推）
	var dmg: float = GameBalance.obelisk_blessing_damage(GameManager.wave_number)
	var knock: float = GameBalance.obelisk_knock_force(GameManager.wave_number)
	var player_pos: Vector2 = global_position if GameManager.player == null else GameManager.player.global_position
	for enemy in EnemyFilter.collect(GameManager.live_enemies, global_position, INF):
		var knock_vec = GameBalance.knock_dir(global_position, enemy.global_position, player_pos) * knock
		enemy.take_damage(dmg, knock_vec, true)
		# 受击金花：给「全场都被扫到」逐个盖章（JuiceEffect 池化，超量由池限流兜底）
		if fx_host != null:
			JuiceEffect.spawn_impact_pop(fx_host, enemy.global_position, GameStyle.FX_HDR_GOLD, knock_vec.normalized())
	# 触发视觉：光能爆闪一下作为兑现，随后彻底熄灯、光圈散尽、石碑褪成灰相。
	# 2026-10-21：以 spent_blend 连续形变（下沉/褪色/收束）取代原先 0.55s 后的硬切剪影。
	var tw = create_tween()
	tw.tween_property(light, "energy", 5.0, 0.12)
	tw.tween_property(light, "energy", 0.0, SPENT_FADE_TIME)
	tw.parallel().tween_property(light, "color", Color(0.55, 0.62, 0.70), SPENT_FADE_TIME)
	tw.parallel().tween_property(circle_sprite, "modulate:a", 0.0, SPENT_FADE_TIME)
	if stone_mat != null:
		tw.parallel().tween_property(stone_mat, ^"shader_parameter/amount", SPENT_DESATURATE, SPENT_FADE_TIME)
		tw.parallel().tween_property(stone_mat, ^"shader_parameter/fill_ratio", 0.0, SPENT_FADE_TIME)
	if _obelisk_renderer != null:
		tw.parallel().tween_property(_obelisk_renderer, "spent_blend", 1.0, SPENT_FADE_TIME)
	tw.tween_callback(_enter_spent_look)
	# 熄灭余烬：几缕冷灰蓝灵屑上升淡出（给「余温散尽」一点回味）
	if fx_host != null:
		ObeliskFx.play_spent_wisp(fx_host, global_position)

## 召唤灵兽助战（2026-10-25 重设计）：落在祭坛旁（小幅随机偏移走 rng，测试可钉）。
## 同场上限 GameBalance.SPIRIT_BEAST_MAX_ACTIVE（3）：满员顶替召唤波最早的那只；
## 配色取场上未占用的最小档位 —— 场上同时存在的灵兽永不撞色。
func _summon_spirit_beast() -> void:
	var host: Node = GameManager.player.get_parent() if GameManager.player != null else get_tree().current_scene
	if host == null:
		return
	var beasts: Array[SpiritBeast] = []
	for ally in GameManager.live_allies:
		if ally is SpiritBeast and is_instance_valid(ally):
			beasts.append(ally)
	if beasts.size() >= GameBalance.SPIRIT_BEAST_MAX_ACTIVE:
		var oldest: SpiritBeast = beasts[0]
		for b in beasts:
			if b.summon_wave < oldest.summon_wave:
				oldest = b
		# 先把将散的摘出选色名单再消散：它的配色档要当场让给新灵兽，
		# 不然新灵兽会避开一个马上空出来的档、跟某只活着的撞色
		beasts.erase(oldest)
		oldest.expire_for_replacement()
	var beast := beast_scene.instantiate() as SpiritBeast
	beast.palette_idx = ProceduralDroneRenderer.pick_palette_idx(beasts)
	host.add_child(beast)
	beast.global_position = global_position + Vector2(
		GameManager.rng.randf_range(-36.0, 36.0),
		GameManager.rng.randf_range(-36.0, 36.0))
	# 现身演出（2026-10-25）：落点起同色聚灵漩涡（ObeliskFx 0.32s 自灭）+ 扩散环 + 灵光
	if host != null:
		ObeliskFx.play_beast_entrance(host, beast.global_position)
	var body_col: Color = ProceduralDroneRenderer.body_color(beast.palette_idx)
	FxParticlePool.burst(FxParticlePool.SOUL_ORB, beast.global_position, body_col, 1.0, true)
	JuiceEffect.spawn_shockwave(host, beast.global_position, 30.0, body_col, 0.3)

## 灰相收口：灯直接关掉、范围环不再占位（看不见却还在的圈就是 bug）
func _enter_spent_look() -> void:
	light.enabled = false
	circle_sprite.visible = false
	if _obelisk_renderer != null:
		_obelisk_renderer.is_spent = true

func _on_interaction_area_body_entered(body: Node2D) -> void:
	if body is Player:
		# 进出登记与灰相解耦：灰相期间照常记录位置，复燃时才好把激活键请回来
		is_player_inside = true
		if not spent_this_wave and not is_infusing:
			activation_available.emit(self)

func _on_interaction_area_body_exited(body: Node2D) -> void:
	if body is Player:
		if is_charging:
			stop_charge()
		is_player_inside = false
		if not spent_this_wave and not is_infusing:
			activation_unavailable.emit(self)
