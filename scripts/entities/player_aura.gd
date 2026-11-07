class_name PlayerAura
extends Node2D

## 境界突破脉冲（T-3.5，空洞冷冽修仙风）：
## 挂在 Player 角色脚下（阴影层高度）。【2026-11-07「去花」】常驻境界光环整体下线 ——
## 原为 pixelfx rune_circle 金符环循环帧常驻子精灵（符文游转 + 追光扫环 + 浮尘 + 4s 呼吸明灭），
## 与祭坛「去花」同口径：常驻部件一直转圈抢角色读数，拆掉；只留境界突破那一拍的
## 一次性扩散脉冲（0.6s，事件驱动，平时零帧耗 —— 不进 _process、不重绘）。
##   ① 档位 1/2/3 仍按等级/加点解析（_update_tier），只决定脉冲的收束半径（档位越高扩散越远）；
##   ② 升档瞬间一圈 2px 高亮从丹田扩散 0.6s（矢量弧，俯视透视扁率同旧口径）；
##   ③ 纯视觉零碰撞判定。
## 【坑】本节点靠 Player.tscn 子树序（领先角色贴图）+ show_behind_parent 压在角色脚下；
## 不可用负 z 调层 —— EntitiesLayer 全员 z=0，负 z 会整体掉进 MapLayer 不透明地砖之下
## （FloatingWeapon 同款教训）。
## 目检预览台已随常驻光环一起下线（原 tests/AuraPreview.tscn 主体是三档环对比，环没了即无意义）。

const PULSE_DUR := 0.6          ## 突破脉冲时长（秒）
const PULSE_R0 := 6.0           ## 突破脉冲扩散起始半径（丹田）
## 档位 → 脉冲收束半径（px）：对齐下线前符环三档世界半径（≈37/44/52）+ 12 外扩余量
const TIER_PULSE_R: Array[float] = [49.0, 56.0, 64.0]

var _pulse_t: float = -1.0      ## 突破脉冲时间轴（<0 空闲；空闲时不进 _process，零帧耗）
var _tier: int = 1              ## 境界档位（1~3）

func _ready() -> void:
	show_behind_parent = true
	position = Vector2(0, 16)   ## 对齐角色脚下/阴影基准位
	set_process(false)
	_update_tier()
	if GameManager.has_signal("player_leveled_up"):
		GameManager.player_leveled_up.connect(_on_player_leveled_up)
	if GameManager.has_signal("upgrade_applied"):
		GameManager.upgrade_applied.connect(_on_upgrade_applied)

func _on_player_leveled_up(_lv: int) -> void:
	_advance_tier()

func _on_upgrade_applied(_u: String) -> void:
	_advance_tier()

## 只在脉冲期间进 _process：推时间轴 + 逐帧重绘，收尾清帧后自断
func _process(delta: float) -> void:
	_pulse_t += delta
	if _pulse_t > PULSE_DUR:
		_pulse_t = -1.0
		set_process(false)
		queue_redraw()   # 收尾清帧：脉冲结束后必须再重绘一次，否则最后一帧弧残留（_draw 此后不再画）
		return
	queue_redraw()

## 当前档位索引（0~2），越界一律钳到有效档
func _tier_index() -> int:
	return clampi(_tier - 1, 0, TIER_PULSE_R.size() - 1)

## 计算当前境界档位（1-3 档）：依据角色等级与已加点数综合评定
##   1 档（初入道途）：初始档
##   2 档（渐入佳境）：等级 ≥ 6 或 加点 ≥ 4
##   3 档（道法圆满）：等级 ≥ 12 或 加点 ≥ 8
func _update_tier() -> void:
	var lv := GameManager.level
	var total_upgrades := 0
	for count in GameManager.upgrade_counts.values():
		total_upgrades += int(count)
	if lv >= 12 or total_upgrades >= 8:
		_tier = 3
	elif lv >= 6 or total_upgrades >= 4:
		_tier = 2
	else:
		_tier = 1

## 升档解析：境界抬升才放突破脉冲（同档内反复升级/加点只重算不脉冲）
func _advance_tier() -> void:
	var prev := _tier
	_update_tier()
	if _tier > prev:
		_pulse_t = 0.0
		set_process(true)
		queue_redraw()

## 突破脉冲（升档那一拍）：一圈 2px 高亮从丹田扩散到新境界外缘，压在角色脚下（show_behind_parent）。
func _draw() -> void:
	if _pulse_t < 0.0:
		return
	var k := _pulse_t / PULSE_DUR
	var ease_out := 1.0 - (1.0 - k) * (1.0 - k)
	var pulse_r: float = lerpf(PULSE_R0, TIER_PULSE_R[_tier_index()], ease_out)
	var pulse_a: float = pow(1.0 - k, 1.5) * 0.85
	BatchDraw.flush(self)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.48))   # 俯视透视扁率（同旧口径）
	BatchDraw.arc(self, Vector2.ZERO, pulse_r, 0.0, TAU, GameStyle.with_alpha(GameStyle.FX_HDR_GOLD, pulse_a), 2.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	BatchDraw.flush(self)
