extends Node

## tests/mechanism_button_check.gd — 机关按钮（布设 / 维修 / 收回）四态与输入判据
## 运行: python3 tools/run_test.py MechanismButtonCheck
##
## 钉的是「玩家看到的那颗键」：
##   ① 无机关武器 → 整颗收起；有编制 → 「布设 ×N」+ 副读数 = 下一把机关名；
##   ② 靠近自己机关 → 「维修」（磨损）/「完好」（满耐久）+ 顶部「收回」角标；
##   ③ 长按维修：键面走针环推进、耐久实时回填、松手保留已修量；
##   ④ 收回：编制返还 + 整备冷却期间不显示 + 冷却结束淡回；
##   ⑤ 机关磨损且玩家不在旁边 → 「N 座待修」芯片仍挂在原位上（圆键收起也看得见）；
##   ⑥ 第二指（原生 ScreenTouch）能布设；键已进摇杆的 UI_HOLD 组（按住不长摇杆）。
##
## 本判据用真 GameHUD + 真按钮拾取（事件走 root.push_input 打真实矩形），
## 宿主玩家用带 weapon_holder 的 Node2D（按钮读玩家全是鸭类型访问）。

const HUD_SCENE := preload("res://scenes/ui/GameHUD.tscn")
const JOYSTICK_SCENE := preload("res://scenes/ui/VirtualJoystick.tscn")

## 假宿主玩家：TurretCommand 读的是 player.weapon_holder 这个**属性**（真 Player 是 @onready var），
## 所以宿主必须自带同名字段。真 Player 由真机手测覆盖，本判据只钉按钮本身。
## current_health 两件套：机关的 stat_scalings 带 hp_regen / max_hp_bonus 时，
## StatSystem.player_stat_dict 会读这两项（真 Player 恒有）。
class FakePlayer extends Node2D:
	var weapon_holder: Node2D = null
	var current_health: float = 100.0
	var max_health: float = 100.0

	func heal(amount: float, _silent: bool = false) -> float:
		var before := current_health
		current_health = minf(max_health, current_health + amount)
		return current_health - before

class FakeSpawner extends Node:
	var phase: int = 0

var _c := TestCheck.new()
var _hud: GameHUD = null
var _btn: HudMechanismButton = null
var _world: Node2D = null
## 不标类型：要动态写 weapon_holder 这个属性
var _player = null
var _holder: Node2D = null
var _fw: Node = null

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	get_tree().root.size = Vector2i(960, 540)
	await get_tree().process_frame
	await _build_stage()
	_btn = _hud.mechanism_widget()
	_c.check(_btn != null, "HUD 建起了机关键")
	if _btn == null:
		await _teardown()
		get_tree().quit(1)
		return

	await _case_hidden_without_weapon()
	await _case_deploy_by_tap()
	await _case_near_modes()
	await _case_repair_hold()
	await _case_broken_and_service_chip()
	await _case_recall()
	await _case_second_finger()
	await _case_multi_touch_repair()
	await _case_dual_deploy()
	await _case_recall_debounce()
	await _case_clearing_deploy()
	_case_landing_clamp()
	await _check_joystick_group()
	await _teardown()
	if _c.report("MECHANISM_BTN_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)

func _build_stage() -> void:
	GameManager.reset_run()
	_world = Node2D.new()
	_world.name = "MechanismBtnWorld"
	get_tree().root.add_child(_world)
	# 摇杆先建：它靠 node_added 收编后来创建的 BaseButton（不长摇杆的那条口径）
	var joy: Node = JOYSTICK_SCENE.instantiate()
	joy.name = "VirtualJoystick"
	_world.add_child(joy)
	_player = FakePlayer.new()
	_player.name = "FakePlayer"
	_world.add_child(_player)
	_holder = Node2D.new()
	_holder.name = "WeaponHolder"
	_player.add_child(_holder)
	_player.weapon_holder = _holder
	GameManager.player = _player
	GameManager.run_started = true
	_hud = HUD_SCENE.instantiate()
	_world.add_child(_hud)
	await get_tree().process_frame
	await get_tree().process_frame

func _teardown() -> void:
	await get_tree().create_timer(0.4).timeout
	if _world != null and is_instance_valid(_world):
		_world.queue_free()
	await get_tree().process_frame
	GameManager.player = null
	GameManager.run_started = false
	GameManager.reset_run()
	TurretUnit.clear_pool()
	DamageNumber.clear_cache()

## 一次状态轮询（10Hz）后取状态
func _poll() -> void:
	await get_tree().create_timer(0.16).timeout

func _add_mechanism_weapon(wid: String = "jiguan_nu", star: int = 1) -> void:
	_fw = (load("res://scenes/weapons/FloatingWeapon.tscn") as PackedScene).instantiate()
	_fw.setup(wid, star)
	_holder.add_child(_fw)
	_fw.set_process(false)
	await get_tree().process_frame
	await _poll()

func _press_at(pos: Vector2, touch_index: int = -1) -> void:
	if touch_index >= 0:
		var st := InputEventScreenTouch.new()
		st.position = pos
		st.index = touch_index
		st.pressed = true
		_btn.handle_engine_input(st)
		return
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	get_tree().root.push_input(ev)

func _release_at(pos: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	ev.position = pos
	get_tree().root.push_input(ev)

func _btn_center() -> Vector2:
	return _btn.get_btn().get_global_rect().get_center()

func _tag_center() -> Vector2:
	return _btn.get_tag().get_global_rect().get_center()

func _field_turret() -> TurretUnit:
	if _fw == null or not is_instance_valid(_fw):
		return null
	return _fw.field_turret() as TurretUnit

# ---------------- ① 无武器收起 / 有编制布设 ----------------

func _case_hidden_without_weapon() -> void:
	await _poll()
	_c.equals(_btn.mode(), HudMechanismButton.Mode.HIDDEN, "没有机关武器时整颗收起")
	_c.check(not _btn.visible, "收起时根节点也不占位")

func _case_deploy_by_tap() -> void:
	await _add_mechanism_weapon()
	_c.equals(_btn.mode(), HudMechanismButton.Mode.DEPLOY, "有待布设编制 → 布设态")
	_c.check(_btn.visible and _btn.is_circle_shown(), "布设态圆键亮出")
	_c.equals(_btn.get_btn().text, HudMechanismButton.FACE_DEPLOY, "键面写「布设」")
	_c.check(_btn.get_badge().visible, "编制角标可见")
	_c.check(_btn.get_badge().text.contains("1"), "角标写 ×1")
	_c.equals(_btn.get_sub_label().text, "机关弩", "副读数是下一把机关武器名")
	_c.check(not _btn.get_tag().visible, "不靠近机关时不显示收回角标")

	var center := _btn_center()
	_press_at(center)
	_release_at(center)
	await get_tree().process_frame
	var t := _field_turret()
	_c.check(t != null, "点按主键在脚下布设了一座机关")
	if t != null:
		_c.check(t.global_position.distance_to(_player.global_position) > 1.0,
			"机关落在脚边而不是玩家中心（不压人物）")
	_c.equals(TurretCommand.ready_count(_player), 0, "编制已用完")
	# 布设点就在脚边，玩家自然还在交互半径内 —— 先走远才算「不在机关旁」
	_player.global_position += Vector2(320, 0)
	await _poll()
	_c.equals(_btn.mode(), HudMechanismButton.Mode.HIDDEN, "编制用完且走远 → 收起")

# ---------------- ② 靠近切换维修/完好 + 收回角标 ----------------

func _case_near_modes() -> void:
	var t := _field_turret()
	_c.check(t != null, "前提：场上有一座机关")
	if t == null:
		return
	# 玩家贴到机关旁边
	_player.global_position = t.global_position + Vector2(30, 0)
	await _poll()
	_c.equals(_btn.mode(), HudMechanismButton.Mode.OK, "靠近满耐久机关 → 完好态")
	_c.equals(_btn.get_btn().text, HudMechanismButton.FACE_OK, "键面写「完好」")
	_c.check(_btn.get_tag().visible, "靠近时浮出收回角标")
	_c.check(not _btn.get_badge().visible, "收回角标与编制角标互斥")

	t.durability = 30.0
	await _poll()
	_c.equals(_btn.mode(), HudMechanismButton.Mode.REPAIR, "机关磨损 → 维修态")
	_c.equals(_btn.get_btn().text, HudMechanismButton.FACE_REPAIR, "键面写「维修」")
	_c.equals(_btn.get_sub_label().text, "30%", "副读数是当前耐久百分比")

# ---------------- ③ 长按维修 ----------------

func _case_repair_hold() -> void:
	var t := _field_turret()
	if t == null:
		return
	var center := _btn_center()
	_press_at(center)
	await get_tree().create_timer(0.3).timeout
	_c.check(t.is_repairing(), "按住开始维修")
	_c.check(t.durability > 30.0, "维修期间耐久实时回填")
	_c.check(_btn.get_ring().ratio > 0.0, "键面走针环跟着推进")
	var mid := t.durability
	_release_at(center)
	await get_tree().process_frame
	_c.check(not t.is_repairing(), "松手结束维修")
	_c.check(t.durability >= mid - 0.01, "松手保留已修耐久（不回退）")
	_c.near(_btn.get_ring().ratio, 0.0, 0.01, "松手后走针环归零")

	# 按到满：耐久回满、走针环到 1 之前就收手
	_press_at(center)
	await get_tree().create_timer(BalanceTurret.REPAIR_HOLD_SEC + 0.25).timeout
	_c.near(t.durability, BalanceTurret.MAX_DURABILITY, 0.01, "长按满 0.8 秒把耐久修满")
	_release_at(center)
	await _poll()
	_c.equals(_btn.mode(), HudMechanismButton.Mode.OK, "修满后回到完好态")

# ---------------- ④ 停摆 + 待修芯片 ----------------

func _case_broken_and_service_chip() -> void:
	var t := _field_turret()
	if t == null:
		return
	t.durability = 0.0
	await _poll()
	_c.equals(_btn.get_sub_label().text, "0%", "停摆时副读数读到 0%")
	_c.check(t.is_broken(), "耐久归零进入停摆")

	# 玩家走远：圆键收起，但芯片要留在原位提示
	_player.global_position = t.global_position + Vector2(320, 0)
	await _poll()
	_c.equals(_btn.mode(), HudMechanismButton.Mode.HIDDEN, "走远后圆键收起")
	_c.check(_btn.get_chip().visible, "圆键收起后待修芯片仍然可见")
	_c.check(_btn.get_chip().text.contains("1"), "芯片写「1 座待修」")
	_c.check(not _btn.is_circle_shown(), "芯片可见时圆键本体收起")

	# 修好后芯片消失
	_player.global_position = t.global_position + Vector2(30, 0)
	await _poll()
	t.durability = BalanceTurret.MAX_DURABILITY
	await _poll()
	_c.check(not _btn.get_chip().visible, "没有待修机关时芯片消失")

# ---------------- ⑤ 收回 ----------------

func _case_recall() -> void:
	var t := _field_turret()
	if t == null:
		return
	t.durability = 40.0
	await _poll()
	_c.check(_btn.get_tag().visible, "收回角标亮着")
	var tag_c := _tag_center()
	_press_at(tag_c)
	_release_at(tag_c)
	await get_tree().process_frame
	_c.equals(_field_turret(), null, "点收回角标后机关撤场")
	_c.check(float(_fw.pending_turret_durability) > 0.0, "耐久随机关带回本体")
	await _poll()
	_c.equals(_btn.mode(), HudMechanismButton.Mode.HIDDEN, "整备冷却期间不显示布设态")

	_fw.redeploy_timer = 0.0
	await _poll()
	_c.equals(_btn.mode(), HudMechanismButton.Mode.DEPLOY, "整备冷却结束恢复布设态")
	_c.check(_btn.get_badge().visible, "编制角标重新亮回来（收回角标压下后不能一黑到底）")
	_c.check(_btn.get_badge().text.contains("1"), "编制已返还")

# ---------------- ⑥ 第二指原生触摸 + 摇杆豁免 ----------------

func _case_second_finger() -> void:
	_c.equals(_btn.mode(), HudMechanismButton.Mode.DEPLOY, "前提：有待布设编制")
	# 第二指（左手正拉着摇杆）：走原生 ScreenTouch 直通
	_press_at(_btn_center(), 1)
	await get_tree().process_frame
	_c.check(_field_turret() != null, "第二指原生触摸也能布设")
	await _poll()

# ---------------- ⑦ 多指维修（左手摇杆不打断右手） ----------------

func _case_multi_touch_repair() -> void:
	var t := _field_turret()
	_c.check(t != null, "前提：场上有机关")
	if t == null:
		return
	_player.global_position = t.global_position + Vector2(30, 0)
	t.durability = 30.0
	await _poll()
	_c.equals(_btn.mode(), HudMechanismButton.Mode.REPAIR, "进入维修态")

	# 右手按住开始维修（touch index 1）
	var st1 := InputEventScreenTouch.new()
	st1.position = _btn_center()
	st1.index = 1
	st1.pressed = true
	_btn.handle_engine_input(st1)
	await get_tree().process_frame
	_c.check(t.is_repairing(), "原生 press index=1 开始维修")

	# 左手松开摇杆（touch index 0 release）不应打断右手维修
	var st0 := InputEventScreenTouch.new()
	st0.position = Vector2(100, 400)
	st0.index = 0
	st0.pressed = false
	_btn.handle_engine_input(st0)
	await get_tree().process_frame
	_c.check(t.is_repairing(), "发 index=0 的 release，右手维修仍在继续")

	# 右手松开（touch index 1 release）才停止维修
	var st1_rel := InputEventScreenTouch.new()
	st1_rel.position = _btn_center()
	st1_rel.index = 1
	st1_rel.pressed = false
	_btn.handle_engine_input(st1_rel)
	await get_tree().process_frame
	_c.check(not t.is_repairing(), "index=1 release 停止维修")

# ---------------- ⑧ 双联布设（站原地「太近」+ 挪开可布设） ----------------

func _case_dual_deploy() -> void:
	# 先收掉之前的机关，进入干净状态
	if _field_turret() != null:
		_btn._do_recall()
		await get_tree().process_frame
	_fw.redeploy_timer = 0.0
	_fw.pending_turret_durability = -1.0
	if _fw.get("pending_turret_durabilities") != null:
		_fw.pending_turret_durabilities.clear()

	GameManager.items.append("shen_shuanglian")
	await get_tree().process_frame
	_c.equals(TurretCommand.ready_count(_player), 2, "双联神机给 2 份编制")

	_player.global_position = Vector2.ZERO
	await _poll()
	_c.equals(_btn.mode(), HudMechanismButton.Mode.DEPLOY, "空地且有编制 → DEPLOY")

	# 放第一座
	_press_at(_btn_center())
	_release_at(_btn_center())
	await get_tree().process_frame
	_c.equals(_fw.field_turrets().size(), 1, "先放了一座")
	var t1: TurretUnit = _fw.field_turrets()[0]

	# 站原地不动：落点被占 → TOO_CLOSE「太近」
	await _poll()
	_c.equals(_btn.mode(), HudMechanismButton.Mode.TOO_CLOSE, "站原地落点被占 → TOO_CLOSE")
	_c.equals(_btn.get_btn().text, HudMechanismButton.FACE_TOO_CLOSE, "键面写「太近」")
	_c.check(_btn.get_tag().visible, "TOO_CLOSE 模式下显示收回角标")

	# 点主键不新增机关（走拒绝反馈）
	_press_at(_btn_center())
	_release_at(_btn_center())
	await get_tree().process_frame
	_c.equals(_fw.field_turrets().size(), 1, "点主键被拒，不新增机关")

	# 把玩家沿远离机关方向挪约 40px 使落点 ≥64
	# t1 在 (0, 26)，玩家挪到 (0, 66)：离 t1 为 40px (<=90)，落点在 (0, 92)，离 t1 为 66px (>=64)
	_player.global_position = t1.global_position + Vector2(0, 40.0)
	await _poll()
	_c.equals(_btn.mode(), HudMechanismButton.Mode.DEPLOY, "挪约 40px 使落点 ≥64 → DEPLOY")
	_c.equals(_btn.get_btn().text, HudMechanismButton.FACE_DEPLOY, "键面写「布设」")
	_c.check(not _btn.get_tag().visible, "DEPLOY 态即使靠近机关也不显示收回角标（防误触）")

	# 放第二座成功，且此时玩家仍在第一座 90px 内
	await get_tree().create_timer(0.2).timeout
	_press_at(_btn_center())
	_release_at(_btn_center())
	await get_tree().process_frame
	_c.equals(_fw.field_turrets().size(), 2, "再放第二座成功")
	_c.check(_player.global_position.distance_to(t1.global_position) <= BalanceTurret.INTERACT_RADIUS,
		"此时玩家仍在第一座 90px 内（证明靠近也能布设）")

# ---------------- ⑨ 收回防抖 ----------------

func _case_recall_debounce() -> void:
	_c.equals(_fw.field_turrets().size(), 2, "前提：场上有两座机关")
	var t1: TurretUnit = _fw.field_turrets()[0]
	var t2: TurretUnit = _fw.field_turrets()[1]
	# 玩家移到两座机关中间，使两座都在 90px 内
	_player.global_position = (t1.global_position + t2.global_position) * 0.5
	_c.check(_player.global_position.distance_to(t1.global_position) <= BalanceTurret.INTERACT_RADIUS,
		"第一座在 90px 交互范围内")
	_c.check(_player.global_position.distance_to(t2.global_position) <= BalanceTurret.INTERACT_RADIUS,
		"第二座在 90px 交互范围内")

	# 快速调用两次 _do_recall（模拟原生按下 + 鼠标松开跨帧双发）
	_btn._do_recall()
	_btn._do_recall()
	await get_tree().process_frame
	_c.equals(_fw.field_turrets().size(), 1, "收回防抖生效：快速两次调用只收回了一座")

	# 等待 200ms 防抖窗口过后，再次调用可以收回第二座
	await get_tree().create_timer(0.25).timeout
	_btn._do_recall()
	await get_tree().process_frame
	_c.equals(_fw.field_turrets().size(), 0, "防抖结束后可收回第二座")

	GameManager.items.erase("shen_shuanglian")
	_fw.redeploy_timer = 0.0
	await _poll()

# ---------------- ⑩ CLEARING 阶段布设 ----------------

func _case_clearing_deploy() -> void:
	_c.equals(TurretCommand.ready_count(_player), 1, "编制返还为 1")
	_player.global_position = Vector2(200, 200)
	await _poll()
	_c.equals(_btn.mode(), HudMechanismButton.Mode.DEPLOY, "空地布设态")

	var fake_spawner := FakeSpawner.new()
	fake_spawner.phase = int(WaveSpawner.Phase.CLEARING)
	GameManager.wave_spawner = fake_spawner

	_c.check(_btn._is_gameplay_active(), "CLEARING 阶段允许布设交互")

	# 避开 150ms deploy 防抖
	await get_tree().create_timer(0.2).timeout
	_btn._do_deploy()
	await get_tree().process_frame

	var t := _field_turret()
	_c.check(t != null, "CLEARING 阶段布设成功")
	if t != null:
		_c.check(not t._wave_active, "CLEARING 阶段布设的机关进入停火休眠态（_wave_active=false）")
		_btn._do_recall()
		await get_tree().process_frame

	fake_spawner.free()
	GameManager.wave_spawner = null
	_fw.redeploy_timer = 0.0
	await _poll()

# ---------------- ⑪ 落点边界钳制 ----------------

func _case_landing_clamp() -> void:
	var bound: float = GameManager.MAP_HALF_EXTENT - 26.0
	# 玩家位于 (bound, 0)
	_player.global_position = Vector2(bound, 0.0)
	var pos := TurretCommand.deploy_candidate_pos(_player)
	_c.check(pos.x <= bound, "右边界附近落点 x <= MAP_HALF_EXTENT - 26")

	# 玩家超出边界
	_player.global_position = Vector2(bound + 60.0, bound + 60.0)
	pos = TurretCommand.deploy_candidate_pos(_player)
	_c.near(pos.x, bound, 0.001, "超出右边界落点 x 钳制在 bound")
	_c.near(pos.y, bound, 0.001, "超出下边界落点 y 钳制在 bound")

	_player.global_position = Vector2(-bound - 60.0, -bound - 60.0)
	pos = TurretCommand.deploy_candidate_pos(_player)
	_c.near(pos.x, -bound, 0.001, "超出左边界落点 x 钳制在 -bound")
	_c.near(pos.y, -bound, 0.001, "超出上边界落点 y 钳制在 -bound")

func _check_joystick_group() -> void:
	var btn: Button = _btn.get_btn()
	_c.check(btn.is_in_group(DawnJoystick.UI_PRESS_HOLD_GROUP),
		"机关键已进摇杆 UI_HOLD 组（按住维修不会在脚下长出摇杆）")
	var tag: Button = _btn.get_tag()
	_c.check(tag.is_in_group(DawnJoystick.UI_PRESS_HOLD_GROUP),
		"收回角标同样豁免摇杆（点它不会误起摇杆）")