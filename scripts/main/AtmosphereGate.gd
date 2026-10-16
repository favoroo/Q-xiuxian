class_name AtmosphereGate
extends Node2D

## 全屏 UI 期间的环境氛围闸（2026-10-16 CPU/GPU 双省）：
## 商店/悟道/结算等全屏遮挡状态下，3 组环境粒子（68 颗）仍在 PROCESS_MODE_ALWAYS
## 后台模拟、3 层全屏薄雾仍吃移动端半透明 Overdraw 带宽 —— 全被 UI 盖住看不见。
## 本脚本挂在 AtmosphereLayer 上（process_mode ALWAYS 保证暂停时也能响应信号），
## 监听 GameManager 的开/关信号，进入全屏 UI 阶段时藏起整个氛围层，回到战斗恢复。
## 注意：不能用裸 get_tree().paused 判断 —— 开局即 paused=true，主菜单的持续飘动
## 是设计意图（Main.gd 注释），所以只拦「已开战后的全屏 UI」（wave_number >= 1）。

var _suspended: bool = false
var _particles: Array[CPUParticles2D] = []
var _was_emitting: Array[bool] = []

func _ready() -> void:
	# 自身 ALWAYS：暂停期间信号依旧能驱动本节点（子粒子/薄雾不受影响，
	# 藏节点靠 visible，不靠 process_mode）
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = true
	# 粒子在 _setup_atmosphere（Main._ready 第 49 行）创建；本节点是场景静态子节点，
	# _ready 早于 Main._ready，等一拍再收集
	await get_tree().process_frame
	if not is_inside_tree():
		return
	for child in get_children():
		if child is CPUParticles2D:
			_particles.append(child)
	if not GameManager.shop_opened.is_connected(_on_fullscreen_ui_opened):
		GameManager.shop_opened.connect(_on_fullscreen_ui_opened)
	if not GameManager.alloc_opened.is_connected(_on_fullscreen_ui_opened):
		GameManager.alloc_opened.connect(_on_fullscreen_ui_opened)
	if not GameManager.game_over_triggered.is_connected(_on_fullscreen_ui_opened):
		GameManager.game_over_triggered.connect(_on_fullscreen_ui_opened)
	if not GameManager.shop_closed.is_connected(_resume):
		GameManager.shop_closed.connect(_resume)
	if not GameManager.alloc_finished.is_connected(_resume):
		GameManager.alloc_finished.connect(_resume)
	if not GameManager.wave_changed.is_connected(_on_wave_changed):
		GameManager.wave_changed.connect(_on_wave_changed)

func _on_fullscreen_ui_opened() -> void:
	# 主菜单（wave_number == 0）不拦：氛围是主菜单背景的一部分
	if GameManager.wave_number < 1:
		return
	_suspend()

func _on_wave_changed(_n: int) -> void:
	# 新波开打必然离开全屏 UI（shop_closed/alloc_finished 也会各来一次，幂等无害）
	_resume()

func _suspend() -> void:
	if _suspended:
		return
	_suspended = true
	_was_emitting.clear()
	for p in _particles:
		_was_emitting.append(p.emitting)
		p.emitting = false
	visible = false

func _resume() -> void:
	if not _suspended:
		return
	_suspended = false
	for i in range(_particles.size()):
		if i < _was_emitting.size():
			_particles[i].emitting = _was_emitting[i]
	visible = true

func _exit_tree() -> void:
	if GameManager.shop_opened.is_connected(_on_fullscreen_ui_opened):
		GameManager.shop_opened.disconnect(_on_fullscreen_ui_opened)
	if GameManager.alloc_opened.is_connected(_on_fullscreen_ui_opened):
		GameManager.alloc_opened.disconnect(_on_fullscreen_ui_opened)
	if GameManager.game_over_triggered.is_connected(_on_fullscreen_ui_opened):
		GameManager.game_over_triggered.disconnect(_on_fullscreen_ui_opened)
	if GameManager.shop_closed.is_connected(_resume):
		GameManager.shop_closed.disconnect(_resume)
	if GameManager.alloc_finished.is_connected(_resume):
		GameManager.alloc_finished.disconnect(_resume)
	if GameManager.wave_changed.is_connected(_on_wave_changed):
		GameManager.wave_changed.disconnect(_on_wave_changed)
