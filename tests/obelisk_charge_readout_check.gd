extends Node

## 聚灵阵「进度画在阵法上」判据：长按充能时，阵法自己那三处读数必须逐帧跟着进度走。
## 运行: $G --headless --path . res://tests/ObeliskChargeReadoutCheck.tscn
##       $G --headless --path . res://tests/ObeliskChargeReadoutCheck.tscn -- --selftest
##
## 立条目的现场（用户 2026-10-09 真机图）：长按「祭坛」激活聚灵阵，拇指正压在那颗键上，
## 键面上的读数被手挡得死死的 —— 眼睛当时只能看着阵法。所以进度必须出现在阵法上，
## 而这条判据钉的就是「出现了、而且画的是同一个数」：
##   ① 碑脚走针环 ChargeArc.ratio
##   ② 碑身灌灵 desaturate.gdshader 的 fill_ratio
##   ③ 碑顶百分比 Label.text
##   ④ 键面那一圈走针（留着给「拇指压着键、眼睛还在别处」的那一拍，不许和阵法上那三处各说各话）
##
## 为什么逐帧比而不是只比首尾：这条判据真正的敌人是「另抄一套参数」——
## 碑脚那圈用 3s、键面那一圈用 1.5s 这种写法，首尾都对得上（都从 0 到 1），只有中途对不上。
##
## 两条取舍：
##  ① 「人在范围内」这个前置直接写 is_player_inside = true：真造一个 Player 要把 Player.gd
##     拉进来（它此刻正被另一路改动），而本判据判的是「进度画没画在阵法上」，与走位无关。
##     从「按在真键上」往后全是真链路：真 GameHUD、真按钮拾取、真 start_charge。
##  ② 事件走 root.push_input 打按钮真实矩形中心，不直接调 start_charge() —— 直接调只测得到
##     我自己，测不到「拇指按住那颗键的这一刻，阵法上有没有东西在长」。
##     派发不通时先自证并明说，不许把「没收到事件」当成通过。

const HUD_SCENE := preload("res://scenes/ui/GameHUD.tscn")
const OBELISK_SCENE := preload("res://scenes/entities/BlessingObelisk.tscn")
## 逐帧同源比对的容差：一帧 1/60 秒占 CHARGE_TIME 的 1.1%，取两帧宽
const EPS := 0.03

var _c := TestCheck.new()
var _hud: GameHUD
var _ob: BlessingObelisk
## 第二座碑：验「各灌各的」，材质没 local_to_scene 时会在这里露馅
var _ob2: BlessingObelisk
var _btn: Button
var _ring: SkillButtonView.CircleProgressOverlay
var _center := Vector2.ZERO
## 金币前置快照：触发后按差额断扣费
var _stones_before: int = 0

func _ready() -> void:
	call_deferred("_dispatch")

func _dispatch() -> void:
	if "--selftest" in OS.get_cmdline_user_args():
		await _selftest()
		await _teardown()
		get_tree().quit(0 if _c.report("OBELISK_READOUT_SELFTEST_RESULT") else 1)
		return
	await _run()
	await _teardown()
	get_tree().quit(0 if _c.report("OBELISK_READOUT_RESULT") else 1)

## 收尾：等 HUD 那两段淡出 tween 跑完再摘现场，并清掉跳字/特效的常驻池 ——
## 不清的话退出时打「ObjectDB instances were leaked」，把判据自己的噪声混进来
func _teardown() -> void:
	await get_tree().create_timer(0.8).timeout
	for n in [_ob, _ob2, _hud]:
		if n != null and is_instance_valid(n):
			(n as Node).queue_free()
	await get_tree().process_frame
	DamageNumber.clear_cache()
	JuiceEffect.clear_cache()

func _run() -> void:
	get_tree().root.size = Vector2i(960, 540)
	await get_tree().process_frame
	_build_stage()
	await get_tree().process_frame
	await get_tree().process_frame

	_btn = _hud._obelisk_btn
	_ring = _hud._obelisk_ring
	_c.check(_btn != null and _ring != null, "前提：HUD 的聚灵键与键面走针环都建起来了")
	if _btn == null or _ring == null:
		return
	_center = _btn.get_global_rect().get_center()

	# 一、平时不许亮着：读数只在充能期间挂在阵法上
	_c.check(_ob.readout_ratio() == 0.0, "开局阵法读数为 0（实得 %.3f）" % _ob.readout_ratio())
	_c.check(not _ob.is_readout_shown(), "开局阵法上没有进度读数（不许平时就亮着）")

	# 二、读数挂在阵法自己底下 —— 跟着碑走，不是另立一根屏幕坐标的条
	var ro: Node = _ob.get_node_or_null("ChargeReadout")
	_c.check(ro != null and ro.get_parent() == _ob, "读数节点是界碑自己的孩子（附属读数贴在主体上）")

	# 三、走针环不许冒充判定圈：它是进度，画在判定圈之内
	var shape: CircleShape2D = (_ob.interaction_area.get_node("CollisionShape2D") as CollisionShape2D).shape
	_c.check(BlessingObelisk.ARC_RADIUS < shape.radius - 20.0,
		"走针环半径 %.0f 明显收在判定圈 %.0f 之内（范围视觉不许被进度糊大）" % [BlessingObelisk.ARC_RADIUS, shape.radius])

	# 四、派发通路自证：真打进引擎的按下能不能叫醒那颗键
	# 金币前置（2026-10-25 祭坛改金币启动）：给足本回合启动价的富余，充能才进得去
	_stones_before = GameBalance.obelisk_activation_cost(maxi(GameManager.wave_number, 1)) * 2
	GameManager.spirit_stones = _stones_before
	_hud.show_obelisk_activation(_ob)
	await get_tree().create_timer(0.3).timeout
	if not await _dispatch_works():
		print("[SKIP] 派发不通，阵法读数各项不予判定")
		return

	# 五、按住 ⇒ 三处读数逐帧同源，且真的在长
	# 按「充到八成」取样，不按帧数：headless 能跑到几百 FPS，按帧数取样会在进度
	# 还没挪动时就收工，那样「中途对不上」这一类错根本量不出来。
	var samples := 0
	var bad := 0
	var bad_label := 0
	var first := 0.0
	var last := 0.0
	var guard := 0
	while guard < 3000:
		await get_tree().process_frame
		guard += 1
		if not _ob.is_charging:
			break
		var internal: float = _ob.charge_time / BlessingObelisk.CHARGE_TIME
		if samples == 0:
			first = internal
		if not _tracks(_ob, internal):
			bad += 1
		if _ob._readout_label.text != _pct_text(internal):
			bad_label += 1
		last = internal
		samples += 1
		if internal >= 0.8:
			break
	_c.check(samples >= 12, "采到 %d 帧充能过程（够不够看出「中途对不上」）" % samples)
	_c.check(bad == 0, "%d 帧里碑脚环 / 碑身灌光 / 碑顶读数 / 键面那一圈 与充能进度逐帧相等（错 %d 帧）" % [samples, bad])
	_c.check(bad_label == 0, "碑顶百分比文本逐帧等于进度（错 %d 帧）" % bad_label)
	_c.check(last > first + 0.5, "采样期间进度确实在往上涨（%.2f → %.2f）" % [first, last])
	_c.check(_ob.is_readout_shown(), "按住期间读数挂在阵法上")
	_c.check(absf(_ring.ratio - last) <= EPS, "键面那一圈与阵法读数同源（键面 %.3f / 阵法 %.3f）" % [_ring.ratio, last])
	# 各灌各的：另一座碑此刻必须还是空的（褪灰材质若没 local_to_scene，这里会一起亮）
	_c.check(not _ob2.is_readout_shown() and _ob2.readout_ratio() == 0.0,
		"同一时刻另一座碑没跟着亮（各灌各的，材质 local_to_scene 隔离）")

	# 六、中途松手 ⇒ 阵法读数归零并撤下，不许留半截看着像还在充
	await _press(_center, false)
	_c.check(not _ob.is_charging, "松手过早 ⇒ 充能中断")
	_c.check(_ob.readout_ratio() == 0.0, "中断 ⇒ 阵法读数归零（实得 %.3f）" % _ob.readout_ratio())
	_c.check(_ob._readout_arc.ratio == 0.0, "中断 ⇒ 走针环退干净")
	_c.check(float(_ob.stone_mat.get_shader_parameter("fill_ratio")) == 0.0, "中断 ⇒ 碑身灌光退干净")
	_c.check(_ring.ratio == 0.0, "中断 ⇒ 键面那一圈同归零")
	await get_tree().create_timer(0.35).timeout
	_c.check(not _ob.is_readout_shown(), "中断后读数从阵法上撤下")

	# 六·五、进度画在键面上（用户 2026-10-09：「这个进度条可以显示到按钮上面」；
	# 2026-10-10 键改成圆形，横条换成一圈走针）。三件事分别钉：
	#  ① 挂在键上，不是键外面另起一块被拇指根盖住；
	#  ② 整圈收在圆面之内（半径 + 半根线宽越过键半径，探出去的就是一圈悬空的黄线）；
	#  ③ 按在走针那一片上仍然算按在这颗键上（显示件默认 STOP，会在键缘挖一条死带）。
	var btn_rect: Rect2 = _btn.get_global_rect()
	_c.check(_ring.get_parent() == _btn, "走针环挂在键面上（不是键外面另起一块）")
	_c.check(_ring.arc_radius() + _ring.width * 0.5 <= btn_rect.size.x * 0.5 + 0.01,
		"走针整圈收在圆键之内（半径 %.1f + 半宽 %.1f vs 键半径 %.1f）" % [
				_ring.arc_radius(), _ring.width, btn_rect.size.x * 0.5])
	## 死带取样打在针尖那一片：键底缘内侧 4 单位，正是弧画过的地方
	var ring_pt := btn_rect.get_center() + Vector2(0, btn_rect.size.y * 0.5 - 4.0)
	await _press(ring_pt, true)
	_c.check(_ob.is_charging, "按在走针那一片上 ⇒ 照样开始充能（显示件不许挖死带）")
	await _press(ring_pt, false)
	_c.check(not _ob.is_charging, "在走针那一片抬起 ⇒ 停住")

	# 七、按住到满 ⇒ 扣费进注入，读数定格画满一整圈（不许「已经放了但看着还差一截」）
	await _press(_center, true)
	guard = 0
	while not _ob.spent_this_wave and guard < 600:
		await get_tree().process_frame
		guard += 1
	_c.check(_ob.spent_this_wave, "按住到 CHARGE_TIME ⇒ 扣费注入后自动触发（进灰相）")
	_c.check(GameManager.spirit_stones == _stones_before - GameBalance.obelisk_activation_cost(maxi(GameManager.wave_number, 1)),
		"启动扣走本回合启动价金币（剩 %d / 前置 %d）" % [GameManager.spirit_stones, _stones_before])
	_c.check(_ob.readout_ratio() >= 1.0 - EPS, "触发那一帧阵法读数画满（实得 %.3f）" % _ob.readout_ratio())
	_c.check(_ob._readout_arc.ratio >= 1.0 - EPS, "触发那一帧走针环画满一整圈")
	_c.check(_ob._readout_label.text == "100%", "触发那一帧碑顶写着 100%%（实得 %s）" % _ob._readout_label.text)
	await get_tree().create_timer(1.2).timeout
	_c.check(not _ob.is_readout_shown(), "触发后读数收掉（兑现交给冲击波，环再留着就是多余读数）")

	# 八、本回合用完的碑不许再亮进度
	_ob.start_charge()
	_c.check(not _ob.is_charging, "本回合已启动的界碑不再接单")
	_c.check(not _ob.is_readout_shown(), "本回合已启动的界碑不许再亮进度读数")

## 一处判据：阵法上那三处读数是否都跟着同一个进度
func _tracks(ob: BlessingObelisk, internal: float) -> bool:
	if not ob.is_readout_shown():
		return false
	if absf(ob.readout_ratio() - internal) > EPS:
		return false
	if ob._readout_arc == null or absf(ob._readout_arc.ratio - internal) > EPS:
		return false
	if absf(float(ob.stone_mat.get_shader_parameter("fill_ratio")) - internal) > EPS:
		return false
	return absf(_ring.ratio - internal) <= EPS

func _pct_text(ratio: float) -> String:
	return "%d%%" % int(roundf(clampf(ratio, 0.0, 1.0) * 100.0))

func _build_stage() -> void:
	var stage := Node2D.new()
	stage.name = "Stage"
	get_tree().root.add_child(stage)
	_ob = OBELISK_SCENE.instantiate()
	_ob.position = Vector2(300, 300)
	## 前置：人在范围内。真造 Player 会把另一路在改的 Player.gd 拖进判据，这里只钉读数
	_ob.is_player_inside = true
	stage.add_child(_ob)
	_ob2 = OBELISK_SCENE.instantiate()
	_ob2.position = Vector2(600, 300)
	stage.add_child(_ob2)
	_hud = HUD_SCENE.instantiate()
	get_tree().root.add_child(_hud)
	## 接线照 Main.gd 那一套（六条一根不落）：键面那一圈是信号驱动的，
	## 不接的话「阵法与键面同源」就变成我自己喂给自己的数
	_ob.activation_available.connect(_hud.show_obelisk_activation)
	_ob.activation_unavailable.connect(_hud.hide_obelisk_activation)
	_ob.charge_started.connect(_hud.on_obelisk_charge_started)
	_ob.charge_progress_updated.connect(_hud.on_obelisk_charge_progress)
	_ob.charge_cancelled.connect(_hud.on_obelisk_charge_cancelled)
	_ob.blessing_triggered.connect(_hud.on_obelisk_blessing_triggered)

## 打真事件：按下 / 松开那颗键
func _press(pos: Vector2, down: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = down
	ev.position = pos
	ev.global_position = pos
	get_tree().root.push_input(ev)
	await get_tree().process_frame

## 派发通路自证：按下真键 ⇒ 充能真的开始（不通就别把「没收到」当通过）
func _dispatch_works() -> bool:
	await _press(_center, true)
	var ok := _ob.is_charging
	if not ok:
		await _press(_center, false)
	_c.check(ok, "前提：push_input 打按钮真实矩形中心能走通到 start_charge()")
	return ok

## 判据自己的牙齿：把三处读数分别钉回「旧写法」的样子，必须判红
func _selftest() -> void:
	get_tree().root.size = Vector2i(960, 540)
	await get_tree().process_frame
	_build_stage()
	await get_tree().process_frame
	_btn = _hud._obelisk_btn
	_ring = _hud._obelisk_ring
	# 不依赖派发：直接走 HUD 之外最短的一条真链路把进度推到一半
	# 金币前置（2026-10-25 祭坛改金币启动）：不给钱 start_charge 会硬拦
	GameManager.spirit_stones = GameBalance.obelisk_activation_cost(maxi(GameManager.wave_number, 1)) * 2
	_ob.start_charge()
	var guard := 0
	while _ob.charge_time < BlessingObelisk.CHARGE_TIME * 0.55 and guard < 400:
		await get_tree().process_frame
		guard += 1
	# 冻住进度：后面要拿同一个 internal 反复比，不许它继续涨
	_ob.is_charging = false
	var internal: float = _ob.charge_time / BlessingObelisk.CHARGE_TIME
	_c.check(internal > 0.4, "前提：进度已推到 %.2f 并冻住" % internal)
	_c.check(_tracks(_ob, internal), "正例：真充能中的碑，三处读数与键面那一圈都在跟同一个进度")

	_ob._readout_arc.ratio = 0.0
	_c.check(not _tracks(_ob, internal), "反例① 走针环没跟上 ⇒ 判红（旧写法：进度只画在按钮上）")
	_ob._readout_arc.ratio = internal

	_ob.stone_mat.set_shader_parameter("fill_ratio", 0.0)
	_c.check(not _tracks(_ob, internal), "反例② 碑身灌光没接到 shader ⇒ 判红")
	_ob.stone_mat.set_shader_parameter("fill_ratio", internal)

	_ob._readout.visible = false
	_c.check(not _tracks(_ob, internal), "反例③ 读数没挂在阵法上 ⇒ 判红")
	_ob._readout.visible = true

	_ob._readout_arc.ratio = internal * 0.5
	_c.check(not _tracks(_ob, internal), "反例④ 环与进度不同径（另抄一套时长）⇒ 判红")
	_ob._readout_arc.ratio = internal

	_ring.ratio = 0.0
	_c.check(not _tracks(_ob, internal), "反例⑤ 键面那一圈没接到进度 ⇒ 判红（换了画法也不许断源）")
	_ring.ratio = internal

	_c.check(_tracks(_ob, internal), "复原 ⇒ 判绿（反例是人为造的，不是判据空转）")
