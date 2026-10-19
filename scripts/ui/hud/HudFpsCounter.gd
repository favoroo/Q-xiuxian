class_name HudFpsCounter
extends Label

## 左下角 FPS/性能面板：默认关，设置·显示页控制显隐。
## 从 GameHUD 拆出：自管显隐监听与每帧读数。
## 2026-10-11 扩展为真机定位面板：CPU 逻辑耗时（process/physics）、渲染量
## （draw call / 图元）、活动实体计数（敌/弹/宝/特/字）。2Hz 刷新 —— 面板自身不能成为负担。
## 2026-10-14 再扩：逻辑帧窗口峰值（平均值的尖峰盲区，对应「帧率波动大」主诉）、
## 渲染对象数（区分「对象多」还是「draw call 多」）、节点/孤儿节点/内存（池泄漏症状）、
## 物理体/碰撞对（对照物理耗时）。
## 2026-10-16 又扩：显存（纹理预算是否爆）与渲染命令提交耗时
## （RenderingServer.get_frame_setup_time_cpu：CPU 侧 canvas 命令录制/提交负担，
## draw call 或图元虚高时它会跟着涨——GPU 纯耗时 Godot 无常规 API，此项是最接近的信号）。
## 读数用法升级：逻辑/物理 > 16ms ⇒ 卡 CPU；提交耗时高 ⇒ 渲染命令负担重；
## 两者都不高而 FPS 低 ⇒ GPU 填充率/后处理卡（glow/灯光/高分屏拉伸）。
## 读数用法：逻辑/物理耗时合计 > 16ms ⇒ 卡在 CPU 侧；耗时不高但 FPS 低 ⇒ 卡在渲染/GPU 侧。

const REFRESH_INTERVAL := 0.5  ## 面板刷新周期（秒）：2Hz

var _timer: float = 0.0
var _proc_peak_ms: float = 0.0  ## 当前刷新窗口内逻辑帧耗时峰值（每帧采样，刷新后清零）
var _last_fps_col: Color = GameStyle.GOOD  ## 上次写入的帧率色（未变不覆写主题色）

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 钉左下角而不是写死 y=514：窗口比 16:9 高时设计高度会涨（expand），写死就漂到半屏
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = 16.0
	offset_top = -170.0
	offset_right = 336.0
	offset_bottom = -8.0
	GameStyle.label(self, 12, GameStyle.with_alpha(GameStyle.CHALK, 0.75))
	text = "FPS: 60"
	_update_visibility()
	SettingsManager.setting_changed.connect(func(sec: StringName, key: StringName, _val: Variant):
		if sec == &"display" and key == &"show_fps":
			_update_visibility()
	)

func _update_visibility() -> void:
	visible = bool(SettingsManager.get_val(&"display", &"show_fps", false))

func _process(delta: float) -> void:
	if not visible:
		return
	# 峰值采样每帧都做（TIME_PROCESS 是上一渲染帧的逻辑耗时，读取本身极廉价）
	var proc_now_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	if proc_now_ms > _proc_peak_ms:
		_proc_peak_ms = proc_now_ms
	_timer += delta
	if _timer < REFRESH_INTERVAL:
		return
	_timer = 0.0
	var fps := Engine.get_frames_per_second()
	var fps_col := GameStyle.GOOD if fps >= 55 else (GameStyle.JADE if fps >= 35 else GameStyle.BAD)
	# 颜色未变不覆写：每次 add_theme_color_override 都触发 NOTIFICATION_THEME_CHANGED 无谓开销
	if fps_col != _last_fps_col:
		_last_fps_col = fps_col
		add_theme_color_override("font_color", fps_col)
	var phys_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var draw_ms := RenderingServer.get_frame_setup_time_cpu()
	var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var prims := _fmt_count(int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
	var render_objs := _fmt_count(int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)))
	var bolts := BladeProjectile.active_count + EnemyBolt.active_count
	var nodes := _fmt_count(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
	var orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var mem_mb := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var vram_mb := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	var phys_bodies := int(Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS))
	var phys_pairs := int(Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS))
	# 判读提示（2026-10-17 第二次踩坑后固定上屏）：移动渲染器下 TIME_PROCESS/TIME_PHYSICS_PROCESS
	# 含 CPU 等 GPU 帧同步的墙钟（headless 同场景逻辑仅 0.78ms vs 真机 31ms），不可当 CPU 真耗时
	text = "FPS: %d\n逻辑 %.1fms 峰 %.1fms  物理 %.1fms  提交 %.2fms\n绘制 %d  图元 %s  对象 %s\n敌 %d  弹 %d  宝 %d  特 %d  字 %d\n节点 %s  孤儿 %d  内存 %.0fMB  显存 %.0fMB\n物理体 %d  碰撞对 %d\n注:逻辑/物理含等GPU墙钟" % [
		fps, proc_now_ms, _proc_peak_ms, phys_ms, draw_ms, draws, prims, render_objs,
		GameManager.enemy_count, bolts, AstralGem.active_gem_count() + HealOrb.active_count,
		JuiceEffect.active_count, DamageNumber.active_count,
		nodes, orphans, mem_mb, vram_mb, phys_bodies, phys_pairs,
	]
	_proc_peak_ms = 0.0

## 大数缩写：≥1 万按 k 显示，防面板被长数字撑宽
func _fmt_count(n: int) -> String:
	if n >= 10000:
		return "%.1fk" % (float(n) / 1000.0)
	return str(n)
