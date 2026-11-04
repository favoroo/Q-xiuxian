extends Node

## tests/mechanism_button_check.gd — 机关三键（维修 / 布设 / 收回）键面与输入判据
## 运行: python3 tools/run_test.py MechanismButtonCheck
##
## 钉的是「玩家看到的那三颗键」（2026-11-04 布设从维修键里拆出来）：
##   ① 无机关武器 → 整颗收起；有编制 → 独立布设键「布设 ×N」+ 落点钉标；
##      维修主键常驻（「维修」+「未布设」），不再随场上状态整颗消失；
##   ② 靠近自己机关 → 主键「维修」（扳手）/「完好」；布设 / 收回键显隐各自独立；
##   ③ 长按维修：键面走针环推进、耐久实时回填、松手保留已修量；
##   ④ 机关磨损且玩家不在旁边 → 主键「维修」+「走近修」引导 +「N 座待修」芯片；
##   ⑤ 收回：独立收回键 / G 键都能撤场（收回不限距离），收回当刻返还编制；
##   ⑥ 拆键后互不误触：站在机关旁点布设键只布设、点主键只维修；
##      落点被占时布设键写「太近」，拒绝反馈只抖布设键；
##   ⑦ 第二指（原生 ScreenTouch）能布设；三颗键都在摇杆 UI_HOLD 组（按住不长摇杆）。
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
	await _case_waiting_deploy()
	_case_landing_clamp()
	await _case_action_layout_edge()
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

func _deploy_center() -> Vector2:
	return _btn.get_deploy_btn().get_global_rect().get_center()

func _recall_center() -> Vector2:
	return _btn.get_recall_btn().get_global_rect().get_center()

func _field_turret() -> TurretUnit:
	if _fw == null or not is_instance_valid(_fw):
		return null
	return _fw.field_turret() as TurretUnit

# ---------------- ① 无武器收起 / 有编制：主键常驻 + 独立布设键 ----------------

func _case_hidden_without_weapon() -> void:
	await _poll()
	_c.equals(_btn.mode(), HudMechanismButton.Mode.HIDDEN, "没有机关武器时整颗收起")
	_c.check(not _btn.visible, "收起时根节点也不占位")

func _case_deploy_by_tap() -> void:
	await _add_mechanism_weapon()
	# 维修主键：常驻待命，不再随「有编制」变成布设键
	_c.equals(_btn.mode(), HudMechanismButton.Mode.IDLE, "还没有机关 → 维修主键待命态")
	_c.check(_btn.visible and _btn.is_circle_shown(), "维修主键常驻亮着（不再整颗消失）")
	_c.equals(_btn.get_btn().text, HudMechanismButton.FACE_REPAIR, "主键写「维修」")
	_c.equals(_btn.get_sub_label().text, HudMechanismButton.SUB_NOT_DEPLOYED, "副读数写「未布设」")
	_c.check(not _btn.get_glyph().visible, "待命态主键不亮扳手图标")
	# 布设小键：有编制才亮
	_c.equals(_btn.deploy_mode(), HudMechanismButton.DeployMode.READY, "有编制 → 布设键 READY")
	_c.check(_btn.get_deploy_btn().visible, "独立布设键亮出")
	_c.equals(_btn.get_deploy_label().text, HudMechanismButton.FACE_DEPLOY, "布设键写「布设」")
	_c.check(_btn.get_deploy_badge().visible, "编制角标可见")
	_c.check(_btn.get_deploy_badge().text.contains("1"), "角标写 ×1")
	var icon = _btn.get_deploy_icon()
	_c.check(icon != null and icon.visible and icon.kind == 0, "布设键亮落点钉标图标")
	_c.check(not _btn.get_recall_btn().visible, "场上没有机关时收回键隐藏")
	# 布设落点预览：布设键亮着时，地面要有落点虚影 + 射程环
	var preview := _btn.get_preview()
	_c.check(preview != null and is_instance_valid(preview), "布设态生成落点预览")
	if preview != null and is_instance_valid(preview):
		_c.check(preview.visible, "布设态落点预览可见")
		_c.near(preview.global_position.distance_to(
			TurretCommand.deploy_candidate_pos(_player)), 0.0, 1.0, "预览落点与判定落点同源")

	var center := _deploy_center()
	_press_at(center)
	_release_at(center)
	await get_tree().process_frame
	var t := _field_turret()
	_c.check(t != null, "点按布设键在脚下布设了一座机关")
	if t != null:
		_c.check(t.global_position.distance_to(_player.global_position) > 1.0,
			"机关落在脚边而不是玩家中心（不压人物）")
	_c.equals(TurretCommand.ready_count(_player), 0, "编制已用完")
	await _poll()
	_c.check(not _btn.get_deploy_btn().visible, "编制用完后布设键收起")
	_c.equals(_btn.mode(), HudMechanismButton.Mode.OK, "刚布设的机关满耐久且在半径内 → 完好")
	# 布设点就在脚边，玩家自然还在交互半径内 —— 先走远才算「不在机关旁」
	_player.global_position += Vector2(320, 0)
	await _poll()
	_c.equals(_btn.mode(), HudMechanismButton.Mode.IDLE, "走远且机关完好 → 主键常驻待命")
	_c.check(_btn.is_circle_shown(), "走远后维修主键仍亮着（不再整颗收起）")
	_c.equals(_btn.get_sub_label().text, HudMechanismButton.SUB_ALL_OK, "副读数写「都完好」")
	# 收回不限距离（2026-11-03 口径）：走远后收回键照样亮着，随时能收最近那座
	_c.check(_btn.get_recall_btn().visible, "走远后独立收回键仍然可见（收回不限距离）")
	_c.check(_btn.get_preview() == null or not _btn.get_preview().visible,
		"离开布设态后落点预览收起")

# ---------------- ② 靠近切换维修/完好 + 小键显隐 ----------------

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
	_c.check(not _btn.get_glyph().visible, "完好态不亮键面图标")
	_c.check(_btn.get_recall_btn().visible, "靠近时独立收回键可见")
	_c.check(_btn.get_recall_icon() != null, "收回键有「机关 → 人物」图标")
	_c.equals(_btn.get_recall_btn().text, "", "收回键不再用按钮文字（图标 + 单行小字）")
	_c.equals(_btn.get_recall_sub().text, "收回", "收回键只写单行「收回」（不再写「可收回」）")
	_c.check(not _btn.get_deploy_btn().visible, "无编制时布设键隐藏")
	_c.check(not _btn.get_deploy_badge().visible, "无编制时编制角标隐藏")

	t.durability = 30.0
	await _poll()
	_c.equals(_btn.mode(), HudMechanismButton.Mode.REPAIR, "机关磨损 → 维修态")
	_c.equals(_btn.get_btn().text, HudMechanismButton.FACE_REPAIR, "键面写「维修」")
	_c.check(_btn.get_glyph().visible and _btn.get_glyph().kind == 1, "维修态键面亮扳手图标")
	_c.equals(_btn.get_sub_label().text, "30%", "副读数是当前耐久百分比")

	# 维修触发距离 2026-11-03：90 → 150 → 120 → 110 → 95（放宽反而老在收回重摆时抢键）
	_player.global_position = t.global_position + Vector2(90, 0)
	await _poll()
	_c.equals(_btn.mode(), HudMechanismButton.Mode.REPAIR, "贴到 90px（旧值附近）进维修态")
	_player.global_position = t.global_position + Vector2(120, 0)
	await _poll()
	_c.check(_btn.mode() != HudMechanismButton.Mode.REPAIR, "超出 95px 交互半径后不再进维修态")
	_c.equals(_btn.mode(), HudMechanismButton.Mode.SPENT, "半径外 + 机关待修 → 走近修引导态")
	_player.global_position = t.global_position + Vector2(30, 0)
	await _poll()

# ---------------- ③ 长按维修 ----------------

func _case_repair_hold() -> void:
	var t := _field_turret()
	if t == null:
		return
	var center := _btn_center()
	_press_at(center)
	await get_tree().create_timer(0.3).timeout
	_c.check(t.is_repairing(), "按住主键开始维修")
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
	_c.near(t.durability, BalanceTurret.MAX_DURABILITY, 0.01,
		"长按满 %.1f 秒把耐久修满" % BalanceTurret.REPAIR_HOLD_SEC)
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

	# 玩家走远：场上有缺耐久机关 → 主键「维修」+「走近修」引导（主键不再消失）
	_player.global_position = t.global_position + Vector2(320, 0)
	await _poll()
	_c.equals(_btn.mode(), HudMechanismButton.Mode.SPENT, "走远后场上有坏机关 → 维修引导态")
	_c.equals(_btn.get_btn().text, HudMechanismButton.FACE_REPAIR, "键面写「维修」")
	_c.equals(_btn.get_sub_label().text, HudMechanismButton.FACE_SPENT_SUB, "副读数提示「走近修」")
	_c.check(_btn.get_glyph().visible and _btn.get_glyph().kind == 1, "维修引导态亮扳手图标")
	_c.check(_btn.get_chip().visible, "待修芯片仍然可见")
	_c.check(_btn.get_chip().text.contains("1"), "芯片写「1 座待修」")
	_c.check(_btn.is_circle_shown(), "维修引导态圆键亮着")
	# 走远后收回键照样亮着（2026-11-03 收回不限距离）：按 G 真的把最近那座收回来
	_c.check(_btn.get_recall_btn().visible, "走远后收回键仍然可见")
	var turret_id := t.get_instance_id()
	_btn.recall_by_key()
	await get_tree().process_frame
	_c.check(_field_turret() == null, "走远也能收回（不再要求走近）")
	_c.check(is_instance_valid(t) and t._is_dying,
		"收回的是走远前那座机关（id=%d）" % turret_id)
	# 收回当刻编制返还：布设键立刻亮回来（没有整备倒数）
	_c.check(bool(_fw.deploy_ready()), "收回当刻就能重新布设（无整备倒数）")
	await _poll()
	_c.equals(_btn.deploy_mode(), HudMechanismButton.DeployMode.READY, "收回后布设键立刻恢复 READY")
	_c.equals(_btn.mode(), HudMechanismButton.Mode.IDLE, "场上没有机关 → 维修主键待命")
	_c.equals(_btn.get_sub_label().text, HudMechanismButton.SUB_NOT_DEPLOYED, "副读数回到「未布设」")

	# 再摆一座（收回把 0% 耐久带回来了，顺便验证「布设后可立刻修」）
	await get_tree().create_timer(0.2).timeout
	var dc := _deploy_center()
	_press_at(dc)
	_release_at(dc)
	await get_tree().process_frame
	var t2 := _field_turret()
	_c.check(t2 != null, "收回后能立刻重摆")
	if t2 == null:
		return
	_player.global_position = t2.global_position + Vector2(30, 0)
	await _poll()
	# 修好后芯片消失
	t2.durability = BalanceTurret.MAX_DURABILITY
	await _poll()
	_c.check(not _btn.get_chip().visible, "没有待修机关时芯片消失")

# ---------------- ⑤ 收回 ----------------

func _case_recall() -> void:
	var t := _field_turret()
	if t == null:
		return
	t.durability = 40.0
	await _poll()
	_c.check(_btn.get_recall_btn().visible, "收回键亮着")
	var tag_c := _recall_center()
	_press_at(tag_c)
	_release_at(tag_c)
	await get_tree().process_frame
	_c.equals(_field_turret(), null, "点独立收回键后机关撤场")
	_c.check(float(_fw.pending_turret_durability) > 0.0, "耐久随机关带回本体")
	await _poll()
	# 2026-11-03 用户口径：收回后不再等整备，当刻就能重摆
	_c.near(float(_fw.redeploy_timer), 0.0, 0.001, "收回后没有整备倒数（RECALL_COOLDOWN_SEC = 0）")
	_c.equals(_btn.deploy_mode(), HudMechanismButton.DeployMode.READY, "收回当刻布设键恢复 READY")
	_c.check(_btn.get_deploy_btn().visible, "布设键亮回来")
	_c.check(not _btn.get_recall_btn().visible, "机关已收回，收回键隐藏")
	_c.check(_btn.get_deploy_badge().visible, "编制角标重新亮回来（不能一黑到底）")
	_c.check(_btn.get_deploy_badge().text.contains("1"), "编制已返还")

# ---------------- ⑥ 第二指原生触摸 + 摇杆豁免 ----------------

func _case_second_finger() -> void:
	_c.equals(_btn.deploy_mode(), HudMechanismButton.DeployMode.READY, "前提：有待布设编制")
	# 第二指（左手正拉着摇杆）：走原生 ScreenTouch 直通布设键
	_press_at(_deploy_center(), 1)
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

	# 热区重叠带（2026-11-04 拆键后仍有三圈外扩热区）：主键左缘内 20px 只归主键；
	# 再往收回键方向探到两心连线中点附近就归收回键 —— 按「离谁的心更近」分配，
	# 不按声明顺序（取样点跟着真实摆位算，竖排 / 横排都不写死方向）。
	var inner := _btn_center() + Vector2(-20.0, 0.0)
	_c.check(_btn._hit_action(inner) == 0, "主键圆心附近的点归主键")
	var band := _btn_center() + (_recall_center() - _btn_center()).normalized() * 45.0
	_c.check(band.distance_to(_recall_center()) < 45.0, "前提：取样点比主键更贴近收回键")
	_c.check(_btn._hit_action(band) == 2, "贴近收回键那一侧的重叠点归收回键（最近心）")
	var st2 := InputEventScreenTouch.new()
	st2.position = inner
	st2.index = 1
	st2.pressed = true
	_btn.handle_engine_input(st2)
	await get_tree().process_frame
	_c.check(_field_turret() == t, "重叠带点按不误收机关")
	_c.check(t.is_repairing(), "主键侧点按走维修")
	var st2_rel := InputEventScreenTouch.new()
	st2_rel.position = inner
	st2_rel.index = 1
	st2_rel.pressed = false
	_btn.handle_engine_input(st2_rel)
	await get_tree().process_frame
	_c.check(not t.is_repairing(), "重叠带松开停止维修")

	# 暂停/失焦（2026-11-03）：暂停态收不到松开事件，必须主动收手；
	# 否则回到战斗后没人按住也在回填耐久，F 的按住标志还会卡到下一次松开。
	_btn.key_press()
	await get_tree().process_frame
	_c.check(t.is_repairing(), "F 长按开始维修")
	_btn.notification(Node.NOTIFICATION_PAUSED)
	await get_tree().process_frame
	_c.check(not t.is_repairing(), "暂停通知主动收手（维修不跨暂停继续）")
	_btn.key_press()
	await get_tree().process_frame
	_c.check(t.is_repairing(), "暂停收手后 F 未被锁死（再按能继续维修）")
	_btn.key_release()
	await get_tree().process_frame
	_c.check(not t.is_repairing(), "松开 F 结束维修")

# ---------------- ⑧ 双联布设（站原地「太近」+ 挪开可布设） ----------------

func _case_dual_deploy() -> void:
	# 先收掉之前的机关，进入干净状态
	while _field_turret() != null:
		_btn._do_recall()
		await get_tree().create_timer(0.21).timeout
	_fw.pending_turret_durability = -1.0
	if _fw.get("pending_turret_durabilities") != null:
		_fw.pending_turret_durabilities.clear()
	# 上面收回起了 2 秒整备倒数：判据不等真实时间，直接清零模拟到点
	_fw.redeploy_timer = 0.0

	GameManager.items.append("shen_shuanglian")
	await get_tree().process_frame
	_c.equals(TurretCommand.ready_count(_player), 2, "双联神机给 2 份编制")

	_player.global_position = Vector2.ZERO
	await _poll()
	_c.equals(_btn.deploy_mode(), HudMechanismButton.DeployMode.READY, "空地且有编制 → 布设键 READY")
	_c.equals(_btn.mode(), HudMechanismButton.Mode.IDLE, "没有机关时维修主键仍在待命")
	_c.check(_btn.get_deploy_badge().text.contains("2"), "角标写 ×2")

	# 放第一座
	await get_tree().create_timer(0.2).timeout
	_press_at(_deploy_center())
	_release_at(_deploy_center())
	await get_tree().process_frame
	_c.equals(_fw.field_turrets().size(), 1, "先放了一座")
	var t1: TurretUnit = _fw.field_turrets()[0]

	# 站原地不动：落点被占 → 布设键「太近」；主键只管维修，照常写「完好」
	await _poll()
	_c.equals(_btn.deploy_mode(), HudMechanismButton.DeployMode.BLOCKED, "站原地落点被占 → 布设键 BLOCKED")
	_c.equals(_btn.get_deploy_label().text, HudMechanismButton.FACE_TOO_CLOSE, "布设键写「太近」")
	_c.equals(_btn.mode(), HudMechanismButton.Mode.OK, "站在满耐久机关旁 → 主键仍写「完好」")
	_c.check(_btn.get_recall_btn().visible, "有机关在场上时收回键可见")

	# 点布设键不新增机关（走拒绝反馈），也不会顺手开始维修
	await get_tree().create_timer(0.2).timeout
	_press_at(_deploy_center())
	_release_at(_deploy_center())
	await get_tree().process_frame
	_c.equals(_fw.field_turrets().size(), 1, "点布设键被拒，不新增机关")
	_c.check(not t1.is_repairing(), "点布设键不会顺手开始维修（拆键的核心验收）")

	# 把玩家沿远离机关方向挪约 40px 使落点 ≥64
	# t1 在 (0, 26)，玩家挪到 (0, 66)：离 t1 为 40px（在维修交互半径内），落点在 (0, 92)，离 t1 为 66px (>=64)
	_player.global_position = t1.global_position + Vector2(0, 40.0)
	await _poll()
	_c.equals(_btn.deploy_mode(), HudMechanismButton.DeployMode.READY, "挪约 40px 使落点 ≥64 → 布设键 READY")
	_c.equals(_btn.get_deploy_label().text, HudMechanismButton.FACE_DEPLOY, "布设键写「布设」")
	_c.check(_btn.get_recall_btn().visible, "布设键 READY 时收回键仍独立可见")
	var main_c := _btn_center()
	var recall_c := _recall_center()
	var deploy_c := _deploy_center()
	_c.check(main_c.distance_to(recall_c) > HudMechanismButton.BTN_SIZE.x * 0.5,
		"收回键不在主键热区内（不会再误触）")
	_c.check(deploy_c.distance_to(recall_c) > HudMechanismButton.ACTION_SIZE,
		"两颗小键圆心距大于键径（视觉不叠）")
	_c.check(deploy_c.distance_to(main_c) > (HudMechanismButton.BTN_SIZE.x
		+ HudMechanismButton.ACTION_SIZE) * 0.5, "布设键也不压主键")

	# 放第二座成功，且此时玩家仍在第一座的维修交互半径内
	await get_tree().create_timer(0.2).timeout
	_press_at(_deploy_center())
	_release_at(_deploy_center())
	await get_tree().process_frame
	_c.equals(_fw.field_turrets().size(), 2, "再放第二座成功")
	_c.check(_player.global_position.distance_to(t1.global_position) <= BalanceTurret.INTERACT_RADIUS,
		"此时玩家仍在第一座的交互半径内（证明靠近也能布设）")

	# 维修目标优先级（2026-11-04）：两座都在半径内时，先修「最该修」的那座，不是最近那座
	var t2: TurretUnit = _fw.field_turrets()[1]
	t1.durability = 80.0
	t2.durability = 20.0
	_player.global_position = (t1.global_position + t2.global_position) * 0.5
	await _poll()
	_c.equals(_btn.mode(), HudMechanismButton.Mode.REPAIR, "两座都缺耐久 → 进维修态")
	_c.check(_btn.get_target() == t2, "优先选中耐久更低的那座（最该修的）")

	# 最近的满耐久、稍远那座缺耐久：仍要进维修态并选中缺耐久的那座
	# （旧逻辑只认 nearest，会把整座坏机关忽略）
	t1.durability = BalanceTurret.MAX_DURABILITY
	t2.durability = 60.0
	_player.global_position = t1.global_position + Vector2(10, 0)
	await _poll()
	_c.equals(_btn.mode(), HudMechanismButton.Mode.REPAIR,
		"最近那座满耐久、旁边一座缺耐久 → 仍进维修态")
	_c.check(_btn.get_target() == t2, "选中的是缺耐久那座（不是最近的满耐久）")

	# 恢复满耐久，后续收回防抖用例仍按两座满耐久跑
	t2.durability = BalanceTurret.MAX_DURABILITY
	t1.durability = BalanceTurret.MAX_DURABILITY
	await _poll()

# ---------------- ⑨ 收回防抖 ----------------

func _case_recall_debounce() -> void:
	_c.equals(_fw.field_turrets().size(), 2, "前提：场上有两座机关")
	var t1: TurretUnit = _fw.field_turrets()[0]
	var t2: TurretUnit = _fw.field_turrets()[1]
	# 玩家移到两座机关中间，使两座都在维修交互半径内
	_player.global_position = (t1.global_position + t2.global_position) * 0.5
	_c.check(_player.global_position.distance_to(t1.global_position) <= BalanceTurret.INTERACT_RADIUS,
		"第一座在交互范围内")
	_c.check(_player.global_position.distance_to(t2.global_position) <= BalanceTurret.INTERACT_RADIUS,
		"第二座在交互范围内")

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

	# 收回起了 2 秒整备倒数：判据不等真实时间，直接清零给下一段
	_fw.redeploy_timer = 0.0
	GameManager.items.erase("shen_shuanglian")
	await _poll()

# ---------------- ⑩ CLEARING 阶段布设 ----------------

func _case_clearing_deploy() -> void:
	_c.equals(TurretCommand.ready_count(_player), 1, "编制返还为 1")
	_player.global_position = Vector2(200, 200)
	await _poll()
	_c.equals(_btn.deploy_mode(), HudMechanismButton.DeployMode.READY, "空地布设键 READY")

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
		_fw.redeploy_timer = 0.0

	fake_spawner.free()
	GameManager.wave_spawner = null
	await _poll()

# ---------------- ⑩b 波间 WAITING 布设 ----------------

func _case_waiting_deploy() -> void:
	_c.equals(TurretCommand.ready_count(_player), 1, "编制返还为 1（WAITING 前提）")
	_player.global_position = Vector2(-200, -200)
	await _poll()
	_c.equals(_btn.deploy_mode(), HudMechanismButton.DeployMode.READY, "WAITING 空地 → 布设键 READY")

	var fake_spawner := FakeSpawner.new()
	fake_spawner.phase = int(WaveSpawner.Phase.WAITING)
	GameManager.wave_spawner = fake_spawner
	_c.check(_btn._is_gameplay_active(), "波间 WAITING 阶段允许布设（下一波开打前摆阵地）")

	# 避开 150ms deploy 防抖
	await get_tree().create_timer(0.2).timeout
	_btn._do_deploy()
	await get_tree().process_frame
	var t := _field_turret()
	_c.check(t != null, "WAITING 阶段布设成功")
	if t != null:
		_btn._do_recall()
		await get_tree().process_frame
		_fw.redeploy_timer = 0.0

	fake_spawner.free()
	GameManager.wave_spawner = null
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

# ---------------- ⑫ 小键贴边摆位（两颗同时亮） ----------------

func _case_action_layout_edge() -> void:
	# 前提：两颗小键同时亮 —— 双联神机（一座在场上 + 一份编制在手）
	if not GameManager.items.has("shen_shuanglian"):
		GameManager.items.append("shen_shuanglian")
	await get_tree().process_frame
	await _poll()
	if _field_turret() == null and TurretCommand.ready_count(_player) >= 2:
		_player.global_position = Vector2.ZERO
		await _poll()
		await get_tree().create_timer(0.2).timeout
		_btn._do_deploy()
		await get_tree().process_frame
		await _poll()
	_c.check(_btn.get_deploy_btn().visible, "前提：布设键亮着")
	_c.check(_btn.get_recall_btn().visible, "前提：收回键亮着")

	# 主键拖到左上角时，左侧放不下 → 自动改到右侧，三颗键都仍在屏内
	SettingsManager.set_mechanism_btn_xy(Vector2(0.0, 0.0), false)
	_btn._apply_layout()
	await get_tree().process_frame
	var vp := _btn.get_viewport_rect().size
	var keys: Array = [_btn.get_btn(), _btn.get_deploy_btn(), _btn.get_recall_btn()]
	var names: Array = ["维修主键", "布设键", "收回键"]
	for i in keys.size():
		var rr: Rect2 = (keys[i] as Control).get_global_rect()
		_c.check(rr.position.x >= 0.0 and rr.position.y >= 0.0
			and rr.end.x <= vp.x and rr.end.y <= vp.y,
			"%s 在主键贴左上角时仍完整留在屏内（实得 %s / 屏 %s）" % [names[i], str(rr), str(vp)])

	# 默认位再量一次：两颗小键在主键左侧竖排（上布设、下收回），整列底边与主键底边对齐
	SettingsManager.set_mechanism_btn_xy(SettingsManager.MECHANISM_BTN_XY_DEFAULT, false)
	_btn._apply_layout()
	await get_tree().process_frame
	var dc := _deploy_center()
	var rc := _recall_center()
	var mc := _btn_center()
	_c.check(dc.distance_to(rc) >= HudMechanismButton.ACTION_SIZE, "默认位两颗小键不重叠")
	_c.near(dc.x, rc.x, 0.5, "默认位两颗小键同一列（竖排）")
	_c.check(dc.y < rc.y, "竖排顺序：上「布设」下「收回」")
	_c.check(dc.x < mc.x and rc.x < mc.x, "默认位两颗小键都在主键左侧")
	_c.near(rc.y + HudMechanismButton.ACTION_SIZE * 0.5,
		mc.y + HudMechanismButton.BTN_SIZE.x * 0.5, 0.5,
		"整列底边与主键底边对齐（不往下方祭坛键方向探）")
	_c.check(not Rect2(dc - Vector2(28, 28), Vector2(56, 56)).intersects(
		Rect2(mc - Vector2(44, 44), Vector2(88, 88))), "布设键不压主键")
	_c.check(not Rect2(rc - Vector2(28, 28), Vector2(56, 56)).intersects(
		Rect2(mc - Vector2(44, 44), Vector2(88, 88))), "收回键不压主键")

	# 收尾：把场上那座收回、清掉双联，别把状态带进后面的用例
	if _field_turret() != null:
		_btn._do_recall()
		await get_tree().process_frame
	GameManager.items.erase("shen_shuanglian")
	await _poll()

func _check_joystick_group() -> void:
	var btn: Button = _btn.get_btn()
	_c.check(btn.is_in_group(DawnJoystick.UI_PRESS_HOLD_GROUP),
		"维修主键已进摇杆 UI_HOLD 组（按住维修不会在脚下长出摇杆）")
	var deploy: Button = _btn.get_deploy_btn()
	_c.check(deploy.is_in_group(DawnJoystick.UI_PRESS_HOLD_GROUP),
		"独立布设键同样豁免摇杆（点它不会误起摇杆）")
	var recall: Button = _btn.get_recall_btn()
	_c.check(recall.is_in_group(DawnJoystick.UI_PRESS_HOLD_GROUP),
		"独立收回键同样豁免摇杆（点它不会误起摇杆）")
