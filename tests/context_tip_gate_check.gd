extends Node

## 局内情境提示（HudContextTips）门控判据：headless 运行，退出码 0 且打印 ALL PASS 即通过。
## 运行: $G --headless --path . res://tests/ContextTipGateCheck.tscn
##       $G --headless --path . res://tests/ContextTipGateCheck.tscn -- --selftest
##
## 为什么立这条（T3 新手引导情境提示：首进商店/首遇藏宝匣/聚灵阵/精英怪各弹一次气泡）：
##  ① 首触发要真弹：只写个偏好键没接信号，玩家永远看不见提示（不崩不报错）；
##  ② 看过不再弹：门控写反（把 seen 当未看用）表现为「每次都弹」或「永远弹不出」；
##  ③ 弹出当刻要真落盘：回读 user://settings.cfg + 内存污染后 _load_settings() 复原，
##     钉「跨会话不复弹」——否则杀一次进程就又弹一遍；
##  ④ 非模态：不暂停、不铺遮罩（气泡矩形之外输入照常落下）、几秒自消、点按即收；
##     落点在横幅之下、底部摇杆/技能键之上（避开血条与准星区）。
## 尺子走生产入口：触发就是真发 GameManager.context_tip_requested（与四个触发点同一条信号），
## 门控/落盘读 SettingsManager 本体，不在此重抄条件。
## 注意：全程动 ctx_tip_* 四个键，收尾还原开发机原值（保护 user://settings.cfg）。

const JITTER := 4.0
const TIP_IDS: Array[StringName] = [&"shop", &"chest", &"obelisk", &"elite", &"mechanism"]

var _c := TestCheck.new()
var _main: Node
var _hud: Control
var _tips: HudContextTips
## 开发机原值，收尾原样写回
var _seen0: Dictionary = {}

func _ready() -> void:
	call_deferred("_boot")

func _boot() -> void:
	for id in TIP_IDS:
		_seen0[id] = SettingsManager.context_tip_seen(id)
	get_tree().root.size = Vector2i(960, 540)
	_main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(_main)
	await _settle(4)
	_hud = _main.get_node_or_null("UILayer/GameHUD") as Control
	if _hud != null:
		_tips = _hud.get_node_or_null("ContextTipsLayer") as HudContextTips
	# Main 加载期间可能自然触发（玩家出生点在聚灵阵范围内会弹 obelisk）——统一清回「没看过」
	for id in TIP_IDS:
		_set_seen(id, false)
	if "--selftest" in OS.get_cmdline_user_args():
		await _selftest()
	else:
		await _run()
	for id in TIP_IDS:
		_set_seen(id, bool(_seen0[id]))
	if _c.report("CONTEXT_TIP_GATE_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)

# ================================ 正判 ================================

func _run() -> void:
	_check(_hud != null and _tips != null, "现场：GameHUD 下挂着 HudContextTips（ContextTipsLayer）")
	if _tips == null:
		return
	_check(_tips.layer > 10, "提示层在 UILayer(10) 之上（商店开着时也盖得住面板）")
	_check(_tips.process_mode == Node.PROCESS_MODE_ALWAYS, "提示层 ALWAYS 处理（商店暂停时仍点得动）")

	# ---------- 1. 首触发真弹：发信号 → 气泡出、文案对、不动暂停态 ----------
	# （主菜单态整棵树本来就 paused，口径是「弹气泡这件事不改变暂停态」，不是「必须未暂停」）
	var paused_before := get_tree().paused
	GameManager.context_tip_requested.emit(&"chest")
	await _settle(3)
	_check(_tips.is_showing(), "首遇藏宝匣 → 气泡真弹出来了（不是只改了个变量）")
	_check(_tips.current_text() == "藏宝匣打碎掉金币和道具", "气泡文案 = 藏宝匣那条（标题+一句机制说明）")
	_check(get_tree().paused == paused_before, "弹气泡不动暂停态（非模态，战斗中弹也不暂停）")
	_check(not _bubble_blocks_screen(), "气泡之外不拦输入（无整屏遮罩，鼠标过滤只吃自己那条矩形）")

	# ---------- 2. 落点：横幅之下、底部操作区之上，水平居中不顶边 ----------
	var r: Rect2 = _bubble_rect()
	_check(r.position.y >= 122.0, "气泡顶在播报横幅(84~122)之下，不压顶栏血条")
	_check(r.end.y < 540.0 - 100.0, "气泡底在摇杆/技能键之上（不压准星区）")
	_check(r.position.x >= 0.0 and r.end.x <= 960.0, "气泡整条在屏内")
	_check(absf(r.get_center().x - 480.0) < 2.0, "气泡水平居中")

	# ---------- 3. 弹出当刻已标记 + 落盘 ----------
	_check(SettingsManager.context_tip_seen(&"chest"), "弹出当刻「已看过」已写入内存")
	_check(_disk_seen(&"chest") == true, "弹出当刻已落 user://settings.cfg（重启进程还在）")

	# ---------- 4. 看过不再弹：同 id 再发被门控吞掉，别的 id 照常 ----------
	GameManager.context_tip_requested.emit(&"chest")
	await _settle(2)
	_check(_tips.current_text() == "藏宝匣打碎掉金币和道具", "再看过的 id 再发信号被吞（文案没被重刷）")
	GameManager.context_tip_requested.emit(&"elite")
	await _settle(3)
	_check(_tips.current_text() == "精英怪血厚招狠，击杀掉好货", "换一个没看过的 id 照常弹（文案换精英那条）")
	_check(SettingsManager.context_tip_seen(&"elite"), "精英那条也落标记")

	# ---------- 5. 跨会话：内存污染成「没看过」→ 重新读盘 → 门控照旧 ----------
	SettingsManager._settings["ui"]["ctx_tip_elite"] = false
	_check(not SettingsManager.context_tip_seen(&"elite"), "反例现场：内存被污染成没看过")
	SettingsManager._load_settings()
	_check(SettingsManager.context_tip_seen(&"elite"), "重新读盘后按存档口径仍是看过（跨会话不复弹）")

	# ---------- 6. 点按即收：真发一次按下/抬起 ----------
	await _tap(_tips.get("_bubble") as Control)
	await _settle(2)
	await get_tree().create_timer(HudContextTips.FADE_OUT + 0.15).timeout
	_check(not _tips.is_showing(), "点按气泡即收（不必等自消）")
	GameManager.context_tip_requested.emit(&"elite")
	await _settle(2)
	_check(not _tips.is_showing(), "收掉后再发已看过的 id 也不弹")

	# ---------- 7. 几秒自消：不收也会自己淡掉 ----------
	GameManager.context_tip_requested.emit(&"shop")
	await _settle(3)
	_check(_tips.is_showing() and _tips.current_text() == "金币阁回合间隙花金币买武器道具",
		"首进商店那条照常弹")
	await get_tree().create_timer(HudContextTips.AUTO_HIDE_SEC + HudContextTips.FADE_OUT + 0.4).timeout
	_check(not _tips.is_showing(), "到点自消（不常驻挡画面）")

	# ---------- 8. 四条文案与四个触发点 id 一一对应 ----------
	for id in TIP_IDS:
		_check(HudContextTips.TIPS.has(id), "文案表含触发点 id「%s」" % id)

# ================================ 反例 ================================

## 判据自己得拦得住东西：发一个没注册的 id（相当于触发点接错信号名），尺子必须量出
## 「什么都没弹」；紧接着发真 id 必须弹 —— 否则上面的「弹了」可能只是别的路径碰出来的。
func _selftest() -> void:
	if _tips == null:
		_check(false, "反例现场：HudContextTips 存在")
		return
	GameManager.context_tip_requested.emit(&"nope_unregistered")
	await _settle(3)
	_check(not _tips.is_showing(), "反例：没注册的 id 发信号不弹（门控/文案表双双认生）")
	_check(not SettingsManager.context_tip_seen(&"nope_unregistered"), "反例：未注册 id 不落任何偏好键")
	GameManager.context_tip_requested.emit(&"obelisk")
	await _settle(3)
	_check(_tips.is_showing() and _tips.current_text() == "聚灵阵站进去充能领灵兽",
		"正例：同一通道发真 id 必须弹 —— 反例的「没弹」不是信号没人收到")
	_tips._dismiss()
	await get_tree().create_timer(HudContextTips.FADE_OUT + 0.15).timeout

# ================================ 工具 ================================

func _check(cond: bool, label: String) -> void:
	_c.check(cond, label)

## 测试侧写偏好键（与生产同一入口，写内存并落盘）
func _set_seen(id: StringName, seen: bool) -> void:
	if seen:
		SettingsManager.mark_context_tip_seen(id)
	else:
		SettingsManager.set_val(&"ui", StringName("ctx_tip_" + String(id)), false)

## 落盘回读：直接开 settings.cfg 问「这个键真在文件里吗」
func _disk_seen(id: StringName) -> Variant:
	var cfg := ConfigFile.new()
	if cfg.load(SettingsManager.SETTINGS_PATH) != OK:
		return null
	var key := "ctx_tip_" + String(id)
	if not cfg.has_section_key("ui", key):
		return null
	return bool(cfg.get_value("ui", key, false))

func _bubble_rect() -> Rect2:
	var b := _tips.get("_bubble") as Control
	if b == null or not is_instance_valid(b):
		return Rect2()
	return b.get_global_rect()

## 气泡矩形之外不应有拦输入的兄弟节点：提示层只许有气泡一个可见控件，
## 且气泡自身尺寸远小于屏（不是整屏遮罩）
func _bubble_blocks_screen() -> bool:
	var b := _tips.get("_bubble") as Control
	if b == null:
		return true
	if b.mouse_filter != Control.MOUSE_FILTER_STOP:
		return true
	var screen := Vector2(960, 540)
	var r := b.get_global_rect()
	# 判定：吃输入的矩形盖过屏心四分之一就算拦（气泡实际约 300×30）
	return r.size.x * r.size.y > screen.x * screen.y * 0.25

func _tap(c: Control) -> void:
	var pos := c.get_global_rect().get_center()
	await _press(pos)
	await _release(pos + Vector2(0, -JITTER))
	await _settle(2)

func _press(pos: Vector2) -> void:
	var p := _to_input(pos)
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = p
	e.global_position = p
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_tree().root.push_input(e)
	await get_tree().process_frame

func _release(pos: Vector2) -> void:
	var p := _to_input(pos)
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = false
	e.position = p
	e.global_position = p
	get_tree().root.push_input(e)
	await get_tree().process_frame

## 画布坐标 → 窗口坐标：root.size 与视口不同尺时不打折就打歪
func _to_input(pos: Vector2) -> Vector2:
	return get_tree().root.get_final_transform() * pos

func _settle(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame
