class_name FlickerProbe
extends Node

## 真机「整层 HUD 瞬闪」定位探针（2026-10-20）。
##
## 背景：真机战斗中 HUD（血条/暂停键/技能键等）会「消失一下又出现」快速闪几下，
## 而游戏画面完全正常 —— 说明问题在 UI 层的绘制/纹理，不在整个帧。桌面无法复现。
## 静态读代码已排除：glow/HDR 帧缓冲、2D 灯光照 HUD、字体缺字回退、升级金光、
## StageBackdrop、HUD 根显隐、相机、窗口重排。剩下最可能的是**字形图集重建时的
## 纹理上传导致该帧 UI 批次失效**（UI 用同一份 FontVariation，世界层不用）。
##
## 本探针每帧采样，只在「检测到异常跳变」时写一行 CSV 到 user://flicker_log.csv，
## 平时零日志（不刷屏、不拖慢）。开关走设置 display/flicker_probe（默认关）。
##
## 判读：把 log 发回，看闪的那一行 event 列是什么 ——
##   VRAM_JUMP      显存单帧跳涨 >阈值 ⇒ 纹理/字形图集重建（最可能）
##   DRAW_DROP      draw call 骤降 ⇒ UI 那帧没提交绘制
##   HUD_VIS        GameHUD.visible 变化 ⇒ 谁把它藏了
##   HUD_ALPHA      GameHUD 的 modulate.a 变化 ⇒ 谁把它透明了
##   HUD_RECT       HUD 尺寸/位置突变 ⇒ 布局重排
##   WIN_SIZE       窗口尺寸变化 ⇒ 系统栏/键盘进出
##   SCALE_CHANGED  content_scale 变化 ⇒ 分辨率档位被切
##   TIME_SCALE     Engine.time_scale 跳变 ⇒ 顿帧
##   GLOW           辉光档位变化
##   CROWDED        拥挤档翻转

const LOG_PATH := "user://flicker_log.csv"
## 心跳间隔（秒）：无论有没有异常，每这么多秒必写一行（event=HEARTBEAT）。
## 这样「文件存在且有心跳」= 探针确实在跑；某段时间心跳断了 = 主线程卡死/被挂起。
const HEARTBEAT_SEC := 2.0
## 显存单帧跳变阈值（MB）：字形图集重建一次通常几 MB 起步
const VRAM_JUMP_MB := 2.0
## draw call 相对跌幅阈值：一帧掉这么多说明有整批东西没画
const DRAW_DROP_RATIO := 0.35
const DRAW_DROP_MIN := 30

var _enabled: bool = false
var _f: FileAccess = null
var _frame: int = -1
var _rows: int = 0

# 上一帧快照
var _p_vram: float = -1.0
var _p_draws: int = -1
var _p_hud_vis: bool = true
var _p_hud_a: float = 1.0
var _p_hud_rect: Rect2 = Rect2()
var _p_win: Vector2i = Vector2i.ZERO
var _p_scale_mode: int = -1
var _p_scale_factor: float = -1.0
var _p_time_scale: float = 1.0
var _p_glow: float = -1.0
var _p_crowded: bool = false
var _hud: Control = null
var _warmup: int = 0
var _heartbeat_cd: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	SettingsManager.setting_changed.connect(_on_setting_changed)
	_refresh_enabled()

func _on_setting_changed(section: StringName, key: StringName, _v: Variant) -> void:
	if section == &"display" and key == &"flicker_probe":
		_refresh_enabled()

func _refresh_enabled() -> void:
	_enabled = bool(SettingsManager.get_val(&"display", &"flicker_probe", false))
	set_process(_enabled)
	if _enabled and _f == null:
		# 一开启就建文件并立刻落表头 + 首行心跳：保证「文件一定存在」。
		# 教训（2026-10-20）：首版只在检测到异常时才创建文件，用户开开关玩了一局却没找到
		# 文件 —— 「没记录」与「没异常」无法区分，探针等于失效。现在改成：开即建、
		# 每 HEARTBEAT_SEC 必写一行心跳（event=HEARTBEAT），异常行另标事件名。
		_f = FileAccess.open(LOG_PATH, FileAccess.WRITE)
		_rows = 0
		_warmup = 30  # 前 30 帧只建基线，不判异常
		_heartbeat_cd = 0.0
		if _f != null:
			_f.store_line("frame,t_ms,fps,proc_ms,phys_ms,draws,prims,vram_mb,hud_vis,hud_alpha,hud_x,hud_y,hud_w,hud_h,win_w,win_h,scale_mode,scale_factor,time_scale,glow,crowded,dmg,enemies,event")
			_f.store_line("# PROBE_STARTED app=%s platform=%s" % [Version.APP_VERSION_NAME, OS.get_name()])
			_f.flush()
	elif not _enabled and _f != null:
		if _f != null:
			_f.store_line("# PROBE_STOPPED")
			_f.flush()
			_f.close()
		_f = null

func _process(delta: float) -> void:
	if not _enabled or _f == null:
		return
	# 同帧去重：优先用 frames_drawn，但 headless/无渲染后端下它恒为 0（实测），
	# 单纯比较它会把 _process 从第二帧起永久挡死。这里只在它真的推进时才做去重。
	var drawn := Engine.get_frames_drawn()
	if drawn > 0:
		if drawn == _frame:
			return
		_frame = drawn

	if _hud == null or not is_instance_valid(_hud):
		# 探针就挂在 GameHUD 下 ⇒ 父节点就是 HUD。**不要**走 get_tree().current_scene：
		# 探针 _ready 早于 Main 成为 current_scene，且测试/换局时 current_scene 也可能不是 Main，
		# 那条路径会永久解析失败 → _hud 恒 null → 每帧 return → 一行都不写。
		# （2026-10-20 真机「开了开关没记录」的第二个根因，集成判据才暴露出来）
		_hud = get_parent() as Control
		if _hud == null:
			var m := get_tree().current_scene
			if m != null:
				_hud = m.get_node_or_null("UILayer/GameHUD") as Control
	if _hud == null:
		return

	var vram := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var hud_vis := _hud.visible
	var hud_a := _hud.modulate.a
	var hud_rect := Rect2(_hud.global_position, _hud.size)
	var win := DisplayServer.window_get_size()
	var scale_mode := int(get_window().content_scale_mode)
	var scale_factor := get_window().content_scale_factor
	var ts := Engine.time_scale
	var glow := 0.0
	# WorldEnvironment 在 Main 根下。沿 HUD 的父链往上找到 Main 再取，别用 current_scene
	# （同 _hud 的理由：current_scene 在探针就绪/测试场景下不可靠）。
	var we := _find_world_environment()
	if we != null and we.environment != null:
		glow = we.environment.glow_intensity if we.environment.glow_enabled else 0.0
	var crowded := FxBudget.crowded

	# 首帧/预热：只建基线
	if _warmup > 0:
		_warmup -= 1
		_snapshot(vram, draws, hud_vis, hud_a, hud_rect, win, scale_mode, scale_factor, ts, glow, crowded)
		return

	var events: Array[String] = []
	if _p_vram >= 0.0 and vram - _p_vram > VRAM_JUMP_MB:
		events.append("VRAM_JUMP(%.1f->%.1f)" % [_p_vram, vram])
	if _p_draws > DRAW_DROP_MIN and draws < int(_p_draws * (1.0 - DRAW_DROP_RATIO)):
		events.append("DRAW_DROP(%d->%d)" % [_p_draws, draws])
	if hud_vis != _p_hud_vis:
		events.append("HUD_VIS(%s->%s)" % [str(_p_hud_vis), str(hud_vis)])
	if absf(hud_a - _p_hud_a) > 0.01:
		events.append("HUD_ALPHA(%.2f->%.2f)" % [_p_hud_a, hud_a])
	if _p_hud_rect.size != hud_rect.size:
		events.append("HUD_RECT(%s->%s)" % [str(_p_hud_rect.size), str(hud_rect.size)])
	if win != _p_win:
		events.append("WIN_SIZE(%s->%s)" % [str(_p_win), str(win)])
	if scale_mode != _p_scale_mode:
		events.append("SCALE_MODE(%d->%d)" % [_p_scale_mode, scale_mode])
	if absf(scale_factor - _p_scale_factor) > 0.001:
		events.append("SCALE_FACTOR(%.2f->%.2f)" % [_p_scale_factor, scale_factor])
	if absf(ts - _p_time_scale) > 0.05:
		events.append("TIME_SCALE(%.2f->%.2f)" % [_p_time_scale, ts])
	if _p_glow >= 0.0 and absf(glow - _p_glow) > 0.02:
		events.append("GLOW(%.2f->%.2f)" % [_p_glow, glow])
	if crowded != _p_crowded:
		events.append("CROWDED(%s->%s)" % [str(_p_crowded), str(crowded)])

	if not events.is_empty():
		_write_row(vram, draws, hud_vis, hud_a, hud_rect, win, scale_mode, scale_factor, ts, glow, crowded, "|".join(events))

	# 心跳：无论有无异常都定期写一行，保证「探针在跑」这件事有据可查
	_heartbeat_cd += delta
	if _heartbeat_cd >= HEARTBEAT_SEC:
		_heartbeat_cd = 0.0
		if events.is_empty():
			_write_row(vram, draws, hud_vis, hud_a, hud_rect, win, scale_mode, scale_factor, ts, glow, crowded, "HEARTBEAT")

	_snapshot(vram, draws, hud_vis, hud_a, hud_rect, win, scale_mode, scale_factor, ts, glow, crowded)

func _snapshot(vram: float, draws: int, hud_vis: bool, hud_a: float, hud_rect: Rect2,
		win: Vector2i, scale_mode: int, scale_factor: float, ts: float, glow: float, crowded: bool) -> void:
	_p_vram = vram
	_p_draws = draws
	_p_hud_vis = hud_vis
	_p_hud_a = hud_a
	_p_hud_rect = hud_rect
	_p_win = win
	_p_scale_mode = scale_mode
	_p_scale_factor = scale_factor
	_p_time_scale = ts
	_p_glow = glow
	_p_crowded = crowded

func _write_row(vram: float, draws: int, hud_vis: bool, hud_a: float, hud_rect: Rect2,
		win: Vector2i, scale_mode: int, scale_factor: float, ts: float, glow: float,
		crowded: bool, event: String) -> void:
	if _f == null or _rows > 5000:
		return
	_rows += 1
	var proc_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var phys_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var prims := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	_f.store_line("%d,%d,%d,%.2f,%.2f,%d,%d,%.2f,%s,%.2f,%.1f,%.1f,%.1f,%.1f,%d,%d,%d,%.2f,%.2f,%.2f,%s,%d,%d,%s" % [
		_frame, Time.get_ticks_msec(), Engine.get_frames_per_second(), proc_ms, phys_ms,
		draws, prims, vram, str(hud_vis), hud_a,
		hud_rect.position.x, hud_rect.position.y, hud_rect.size.x, hud_rect.size.y,
		win.x, win.y, scale_mode, scale_factor, ts, glow, str(crowded),
		DamageNumber.active_count, GameManager.enemy_count, event,
	])
	_f.flush()

## 供判据/调试：日志路径与当前是否在采集
static func log_path() -> String:
	return LOG_PATH
func is_active() -> bool:
	return _enabled
func rows_written() -> int:
	return _rows

## 沿 HUD 父链向上找 WorldEnvironment（挂在 Main 根下）。找不到返回 null 不报错。
func _find_world_environment() -> WorldEnvironment:
	if _hud == null:
		return null
	var cur: Node = _hud.get_parent()
	while cur != null:
		if cur is WorldEnvironment:
			return cur as WorldEnvironment
		var we := cur.get_node_or_null("WorldEnvironment") as WorldEnvironment
		if we != null:
			return we
		cur = cur.get_parent()
	return null
