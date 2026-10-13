class_name HudFpsCounter
extends Label

## 左下角 FPS/性能面板：默认关，设置·显示页控制显隐。
## 从 GameHUD 拆出：自管显隐监听与每帧读数。
## 2026-10-11 扩展为真机定位面板：CPU 逻辑耗时（process/physics）、渲染量
## （draw call / 图元）、活动实体计数（敌/弹/宝/特/字）。2Hz 刷新 —— 面板自身不能成为负担。
## 读数用法：逻辑/物理耗时合计 > 16ms ⇒ 卡在 CPU 侧；耗时不高但 FPS 低 ⇒ 卡在渲染/GPU 侧。

const REFRESH_INTERVAL := 0.5  ## 面板刷新周期（秒）：2Hz

var _timer: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 钉左下角而不是写死 y=514：窗口比 16:9 高时设计高度会涨（expand），写死就漂到半屏
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = 16.0
	offset_top = -124.0
	offset_right = 336.0
	offset_bottom = -8.0
	GameStyle.label(self, 12, GameStyle.PAPER_DIM)
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
	_timer += delta
	if _timer < REFRESH_INTERVAL:
		return
	_timer = 0.0
	var fps := Engine.get_frames_per_second()
	var fps_col := GameStyle.GOOD if fps >= 55 else (GameStyle.JADE if fps >= 35 else GameStyle.BAD)
	add_theme_color_override("font_color", fps_col)
	var proc_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var phys_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var prims := _fmt_count(int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
	var bolts := BladeProjectile.active_count + EnemyBolt.active_count
	text = "FPS: %d\n逻辑 %.1fms  物理 %.1fms\n绘制 %d  图元 %s\n敌 %d  弹 %d  宝 %d  特 %d  字 %d" % [
		fps, proc_ms, phys_ms, draws, prims,
		GameManager.enemy_count, bolts, AstralGem.active_gem_count() + HealOrb.active_count,
		JuiceEffect.active_count, DamageNumber.active_count,
	]

## 大数缩写：≥1 万按 k 显示，防面板被长数字撑宽
func _fmt_count(n: int) -> String:
	if n >= 10000:
		return "%.1fk" % (float(n) / 1000.0)
	return str(n)
