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
## 外部镜像路径（2026-10-20）：用 release keystore 签名的包在 Android 上**不是 debuggable**，
## `adb run-as` 读不到内部存储的 user:// 文件；而应用对
## `/sdcard/Android/data/<自己包名>/files/` 无需任何权限即可读写，adb 也能直接 pull。
## 故同时写一份到外部，供「adb 一键收集」使用。内部那份仍保留给游戏内「复制闪屏日志」按钮。
## 非 Android 平台该路径无效（写入会失败，静默忽略）。
const MIRROR_PATH := "/sdcard/Android/data/com.favo.qxiuxian/files/flicker_log.csv"
## 心跳间隔（秒）：无论有没有异常，每这么多秒必写一行（event=HEARTBEAT）。
## 这样「文件存在且有心跳」= 探针确实在跑；某段时间心跳断了 = 主线程卡死/被挂起。
const HEARTBEAT_SEC := 2.0
## 显存单帧跳变阈值（MB）：字形图集重建一次通常几 MB 起步
const VRAM_JUMP_MB := 2.0
## draw call 相对跌幅阈值：一帧掉这么多说明有整批东西没画
const DRAW_DROP_RATIO := 0.35
const DRAW_DROP_MIN := 30
## 闪前环形缓冲帧数：检测到异常时，把最近这么多帧也一起落盘（看「闪之前发生了什么」）
const PREROLL_FRAMES := 90
## 持续采样间隔（秒）：12Hz 采样**抓不住「消失一下又出现」那种 1~2 帧的闪**（实测：整局
## 3104 行里 HUD 可见性全程 true、draw call 平稳、显存无跳变，但用户明确看到 UI 闪）。
## 2026-10-20 改为**逐帧**记录（SAMPLE_INTERVAL=0 表示每渲染帧都记），并把每帧的
## `draws`（含 UI 批次）与上一帧比，任何骤降都单独标记——UI 那帧没被绘制时 draw call
## 会掉一截，这是 GDScript 层唯一能观测到的「UI 没画」信号。
const SAMPLE_INTERVAL := 0.0
## 持续采样总行数上限（逐帧写入更耗磁盘，40 分钟@60fps 约 14 万行，按需调大）
const MAX_ROWS := 300000
## 逐帧写入的落盘节流：攒够这么多行或隔这么久才真正写盘一次。
## 每帧 flush 会自己造成卡顿（同步 IO），污染「闪」的测量。
const PENDING_FLUSH_LINES := 120
const FLUSH_SEC := 0.5

var _enabled: bool = false
var _f: FileAccess = null
## 外部镜像文件句柄（Android 上供 adb 直接 pull；其他平台为 null）
var _fmirror: FileAccess = null
## 待落盘的行缓冲（逐帧采样 + 节流写盘）
var _pending: Array[String] = []
var _pending_since_ms: int = 0
var _frame: int = -1
var _rows: int = 0
## 闪前环形缓冲：每帧存一行快照字符串，异常时整段吐出
var _preroll: Array[String] = []

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
var _sample_cd: float = 0.0
## StageBackdrop（全屏纯黑，盖在 GameHUD 之上）：它一亮就整层 UI 被黑幕遮住、
## 但世界画面（UILayer 之下）照常可见 —— 与用户描述「只有 UI 消失、画面正常」高度吻合。
## 项目原有的 visibility_changed 审计只在 debug 包 push_warning，不进日志，故此处专盯。
var _backdrop: Control = null
var _p_backdrop_vis: bool = false
## HUD 子控件可见性快照（顶栏/武器栏/横幅/技能键等）：定位「是整层还是某几个」。
var _p_children_sig: String = ""

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
		# 教训①（2026-10-20）：首版只在检测到异常时才创建文件，用户开开关玩了一局却没找到
		# 文件 —— 「没记录」与「没异常」无法区分，探针等于失效。现在改成：开即建、
		# 每 HEARTBEAT_SEC 必写一行心跳（event=HEARTBEAT），异常行另标事件名。
		# 教训②（2026-10-20）：用 FileAccess.WRITE 会在**每次场景重载**（死亡重开/暂停重启
		# 都走 reload_current_scene）时把整份日志截断重写，用户一局的数据全丢、只剩最后几行。
		# 改用 READ_WRITE + 定位到末尾（追加），跨场景重载累积保留；首次创建才写表头。
		var existed := FileAccess.file_exists(LOG_PATH)
		_f = FileAccess.open(LOG_PATH, FileAccess.READ_WRITE)
		if _f == null:
			_f = FileAccess.open(LOG_PATH, FileAccess.WRITE)
		if _f != null:
			_f.seek_end()
		# 外部镜像（Android）：供 adb pull。非 Android / 路径不可写时静默为 null。
		_fmirror = null
		if OS.has_feature("mobile"):
			var mexisted := FileAccess.file_exists(MIRROR_PATH)
			_fmirror = FileAccess.open(MIRROR_PATH, FileAccess.READ_WRITE)
			if _fmirror == null:
				_fmirror = FileAccess.open(MIRROR_PATH, FileAccess.WRITE)
			if _fmirror != null:
				_fmirror.seek_end()
				if not mexisted:
					_fmirror.store_line("frame,t_ms,fps,proc_ms,phys_ms,draws,prims,vram_mb,hud_vis,hud_alpha,hud_x,hud_y,hud_w,hud_h,win_w,win_h,scale_mode,scale_factor,time_scale,glow,crowded,dmg,enemies,backdrop_vis,children,event")
				_fmirror.store_line("# PROBE_STARTED app=%s platform=%s" % [Version.APP_VERSION_NAME, OS.get_name()])
				_fmirror.flush()
		_rows = 0
		_preroll.clear()
		_warmup = 30  # 前 30 帧只建基线，不判异常
		_heartbeat_cd = 0.0
		_sample_cd = 0.0
		if _f != null:
			# 表头只在「文件首次创建」时写一次；追加到已有文件时不能再写表头，
			# 否则每次场景重载都会往中间插一行表头，日志无法解析。
			if not existed:
				_f.store_line("frame,t_ms,fps,proc_ms,phys_ms,draws,prims,vram_mb,hud_vis,hud_alpha,hud_x,hud_y,hud_w,hud_h,win_w,win_h,scale_mode,scale_factor,time_scale,glow,crowded,dmg,enemies,backdrop_vis,children,event")
			_f.store_line("# PROBE_STARTED app=%s platform=%s" % [Version.APP_VERSION_NAME, OS.get_name()])
			_f.flush()
	elif not _enabled and _f != null:
		_flush_pending()
		if _f != null:
			_f.store_line("# PROBE_STOPPED")
			_f.flush()
			_f.close()
		_f = null
		if _fmirror != null:
			_fmirror.store_line("# PROBE_STOPPED")
			_fmirror.flush()
			_fmirror.close()
			_fmirror = null

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
	var dmg := DamageNumber.active_count
	var enemies := GameManager.enemy_count
	# StageBackdrop（全屏纯黑、盖在 GameHUD 之上）：一亮就会「只盖住 UI、世界画面照常」，
	# 与用户描述高度吻合，必须逐帧盯住它的可见性。
	if _backdrop == null or not is_instance_valid(_backdrop):
		var ui_layer := _hud.get_parent()
		if ui_layer != null:
			_backdrop = ui_layer.get_node_or_null("StageBackdrop") as Control
	var backdrop_vis := _backdrop != null and _backdrop.visible
	# 签名合并：HUD 自身子控件 + **UILayer 全部兄弟节点**（StageBackdrop/各对话框）。
	# 后者是关键——它们排在 GameHUD 之后，一亮就整层盖住 HUD、世界画面照常可见。
	var children_sig := _children_signature() + " ||UI|| " + _ui_layer_signature()

	# 每帧把这一行的快照压进环形缓冲（异常时把最近这些帧一起吐出去，看「闪之前发生了什么」）。
	# 心跳行也算普通帧，这样异常时能看到前 90 帧的完整上下文。
	var row := _format_row(vram, draws, hud_vis, hud_a, hud_rect, win, scale_mode,
		scale_factor, ts, glow, crowded, dmg, enemies, backdrop_vis, children_sig, "")
	_preroll.append(row)
	if _preroll.size() > PREROLL_FRAMES:
		_preroll.pop_front()

	# 首帧/预热：只建基线
	if _warmup > 0:
		_warmup -= 1
		_snapshot(vram, draws, hud_vis, hud_a, hud_rect, win, scale_mode, scale_factor, ts, glow, crowded)
		_p_backdrop_vis = backdrop_vis
		_p_children_sig = children_sig
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
	# 黑幕复亮 = 最高优先级嫌疑（整层 UI 被纯黑盖住但世界画面照常）
	if backdrop_vis != _p_backdrop_vis:
		events.append("BACKDROP_VIS(%s->%s)" % [str(_p_backdrop_vis), str(backdrop_vis)])
	# HUD 子控件可见性签名变化 = 某个/某几个子控件被藏了
	if children_sig != _p_children_sig:
		events.append("CHILDREN_CHANGED(%s=>%s)" % [_p_children_sig, children_sig])
	# 逐帧 draw call 骤降检测（2026-10-20 关键加强）：UI 那帧没被绘制时，引擎本帧的
	# draw call 会掉一截。**阈值调小到 8% 且下限 40**，因为「消失一下又出现」通常只掉
	# 几十个 call、持续 1~2 帧，用原来的 35% 大阈值根本抓不到（实测整局 0 命中）。
	# 只在战斗态（backdrop 灭、HUD 可见）判，避免菜单切换的巨幅波动刷屏。
	if _p_draws >= 200 and hud_vis and not backdrop_vis:
		var drop := _p_draws - draws
		if drop >= 40 and float(drop) / float(_p_draws) >= 0.08:
			events.append("DRAW_DIP(%d->%d,-%d)" % [_p_draws, draws, drop])

	if not events.is_empty():
		# 异常：先把闪前环形缓冲整段吐出（看「闪之前发生了什么」），再写异常行本身
		_emit_preroll("PREROLL_BEFORE:" + events[0].get_slice("(", 0))
		_write_row(vram, draws, hud_vis, hud_a, hud_rect, win, scale_mode, scale_factor, ts, glow, crowded, dmg, enemies, backdrop_vis, children_sig, "|".join(events))

	# 持续采样（2026-10-20 加强）：SAMPLE_INTERVAL=0 ⇒ **每渲染帧**写一行（逐帧）。
	# 12Hz 抽样抓不住 1~2 帧的闪（实测整局 HUD 可见性全程 true、draw 平稳、显存无跳变，
	# 但用户明确看到 UI 闪）—— 只有逐帧才可能对上。行数上限 MAX_ROWS 兜底防写爆。
	_sample_cd += delta
	if _sample_cd >= SAMPLE_INTERVAL and events.is_empty():
		_sample_cd = 0.0
		_write_row(vram, draws, hud_vis, hud_a, hud_rect, win, scale_mode, scale_factor, ts, glow, crowded, dmg, enemies, backdrop_vis, children_sig, "SAMPLE")

	# 心跳：无论有无异常都定期写一行，保证「探针在跑」这件事有据可查
	_heartbeat_cd += delta
	if _heartbeat_cd >= HEARTBEAT_SEC:
		_heartbeat_cd = 0.0
		if events.is_empty():
			_write_row(vram, draws, hud_vis, hud_a, hud_rect, win, scale_mode, scale_factor, ts, glow, crowded, dmg, enemies, backdrop_vis, children_sig, "HEARTBEAT")

	_snapshot(vram, draws, hud_vis, hud_a, hud_rect, win, scale_mode, scale_factor, ts, glow, crowded)
	_p_backdrop_vis = backdrop_vis
	_p_children_sig = children_sig
	# 按时间节流落盘（配合 PENDING_FLUSH_LINES 的行数阈值，两条任一满足就写）
	if _pending_since_ms != 0 and Time.get_ticks_msec() - _pending_since_ms >= int(FLUSH_SEC * 1000.0):
		_flush_pending()

## 把缓冲的行批量落盘（主文件 + 外部镜像）。
func _flush_pending() -> void:
	if _pending.is_empty():
		return
	for ln in _pending:
		if _f != null:
			_f.store_line(ln)
		if _fmirror != null:
			_fmirror.store_line(ln)
	if _f != null:
		_f.flush()
	if _fmirror != null:
		_fmirror.flush()
	_pending.clear()
	_pending_since_ms = 0

## UILayer 全层遮挡签名（2026-10-20 关键补充）：GameHUD 只是 UILayer 的第 1 个子节点，
## **它上面还盖着 StageBackdrop（索引 2，全屏纯黑 ColorRect）以及各种对话框**。
## 只盯 GameHUD 的 visible 完全不够 —— 任何「排在 GameHUD 之后」的兄弟节点一旦变可见，
## 都会盖住整层 HUD 而世界画面（UILayer 之下）照常显示，正是「UI 消失露出游戏画面」。
## 这里记录 UILayer 每个子节点的 索引:类:可见:alpha，任何变化都进事件。
func _ui_layer_signature() -> String:
	if _hud == null:
		return ""
	var ui := _hud.get_parent()
	if ui == null:
		return ""
	var parts: Array[String] = []
	for i in ui.get_child_count():
		var ch := ui.get_child(i)
		if ch is CanvasItem:
			var ci := ch as CanvasItem
			parts.append("%d:%s:%d:%.2f" % [i, String(ch.name).substr(0, 8), 1 if ci.visible else 0, ci.modulate.a])
	return ";".join(parts)

## HUD 子控件可见性签名：**用「索引:类名首字母:可见」**，不用名字（HUD 里大量子节点是
## 代码 new 出来的、名字全是 `@Control@69` 这类，substr 后全都撞成 `@Contr`，
## 2026-10-20 实测 18 次翻转无法区分是 Boss血条/祭坛键/技能键中的哪一个）。
## 索引稳定（GameHUD 子节点顺序固定），配合已知映射即可定位。
func _children_signature() -> String:
	if _hud == null:
		return ""
	var parts: Array[String] = []
	for i in _hud.get_child_count():
		var ch := _hud.get_child(i)
		if ch is Control:
			parts.append("%d%s%d" % [i, _cls_tag(ch), 1 if (ch as Control).visible else 0])
	return ";".join(parts)

## 类名短标签：Control 一律 C（区分不了就靠索引），其余取首字母
func _cls_tag(n: Node) -> String:
	if n is Control and n.get_class() == "Control":
		return "C"
	return String(n.get_class()).substr(0, 1)

## 异常时吐出闪前环形缓冲（整段，带一条分隔注释）。只在异常时调用，平时零成本。
func _emit_preroll(tag: String) -> void:
	if _f == null or _preroll.is_empty():
		return
	_f.store_line("# %s (%d frames)" % [tag, _preroll.size()])
	for ln in _preroll:
		_f.store_line(ln)
	_preroll.clear()

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

## 把一帧快照格式化成一行 CSV（不含换行）。event 为空表示普通帧（供环形缓冲用）。
func _format_row(vram: float, draws: int, hud_vis: bool, hud_a: float, hud_rect: Rect2,
		win: Vector2i, scale_mode: int, scale_factor: float, ts: float, glow: float,
		crowded: bool, dmg: int, enemies: int, backdrop_vis: bool, children_sig: String,
		event: String) -> String:
	var proc_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var phys_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var prims := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	# children_sig 可能含逗号（"TopCon=1;Weapo=0"）—— CSV 里会把列切错，这里把分号换成竖线，
	# 并去掉可能出现的逗号（签名本身不含逗号，只防万一）。
	var csig := children_sig.replace(",", "|")
	return "%d,%d,%d,%.2f,%.2f,%d,%d,%.2f,%s,%.2f,%.1f,%.1f,%.1f,%.1f,%d,%d,%d,%.2f,%.2f,%.2f,%s,%d,%d,%s,%s,%s" % [
		_frame, Time.get_ticks_msec(), Engine.get_frames_per_second(), proc_ms, phys_ms,
		draws, prims, vram, str(hud_vis), hud_a,
		hud_rect.position.x, hud_rect.position.y, hud_rect.size.x, hud_rect.size.y,
		win.x, win.y, scale_mode, scale_factor, ts, glow, str(crowded),
		dmg, enemies, str(backdrop_vis), csig, event,
	]

func _write_row(vram: float, draws: int, hud_vis: bool, hud_a: float, hud_rect: Rect2,
		win: Vector2i, scale_mode: int, scale_factor: float, ts: float, glow: float,
		crowded: bool, dmg: int, enemies: int, backdrop_vis: bool, children_sig: String,
		event: String) -> void:
	if _f == null:
		return
	if _rows >= MAX_ROWS:
		if _rows == MAX_ROWS:
			_f.store_line("# ROW_LIMIT_REACHED (%d)" % MAX_ROWS)
			_f.flush()
			if _fmirror != null:
				_fmirror.store_line("# ROW_LIMIT_REACHED (%d)" % MAX_ROWS)
				_fmirror.flush()
			_rows += 1
		return
	_rows += 1
	var line := _format_row(vram, draws, hud_vis, hud_a, hud_rect, win, scale_mode,
		scale_factor, ts, glow, crowded, dmg, enemies, backdrop_vis, children_sig, event)
	# 逐帧写入时**不能每行 flush**（真机上每帧同步 IO 会自己造卡顿，污染测量）。
	# 改为先入内存缓冲，攒够 PENDING_FLUSH 行或每隔 FLUSH_SEC 才真正落盘一次。
	_pending.append(line)
	_pending_since_ms = Time.get_ticks_msec() if _pending_since_ms == 0 else _pending_since_ms
	if _pending.size() >= PENDING_FLUSH_LINES:
		_flush_pending()

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
