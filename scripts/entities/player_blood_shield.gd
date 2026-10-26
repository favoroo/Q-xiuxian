class_name PlayerBloodShield
extends Node2D

## 血海护盾的「玩家本体」视觉（2026-10-26 飞升悟道演出升级）。
##
## 为什么要有这个节点：升级前血海护盾只有 HUD 血条上那道靛青细条，玩家角色身上
## 完全读不出「我有盾」—— 积攒、吸收都是纯数值 + signal，只有盾碎那一刻才炸一下。
## 现在盾量 >0 时角色周身常驻一圈半透明血泡：厚度随盾量涨、呼吸脉动、
## 结盾/吸盾瞬间闪一下亮边，盾碎立即收场（爆破由 OnHitEffects 的血红 nova 承担）。
##
## 纪律：
##   - 只读 GameManager.shield_hp，不写任何玩法状态；
##   - 相位用 instance_id 取模错相（不需要随机数，不碰 GameManager.rng）；
##   - 纯 _draw，不申请 FxBudget 的动态灯名额（20/20 已顶格）。

## 血泡几何（对齐程序化角色身形：宽 ±12、头顶 y≈-18、脚底 y≈+24，留几 px 余量）
const CENTER := Vector2(0.0, 3.0)
const RX := 22.0
const RY := 31.0
## 血泡厚度上限随盾量从 MIN 涨到 MAX（盾满时最厚）
const THICK_MIN := 0.10
const THICK_MAX := 0.26
## 呼吸脉动幅度（叠加在厚度上，±）
const PULSE_AMP := 0.045
const PULSE_HZ := 1.5
## 结盾/吸盾的亮边闪一下，强度每秒衰减（1 → 0 约 0.25s）
const FLASH_DECAY := 4.0
## 上浮血珠数量与几何
const DRIP_COUNT := 3
const DRIP_RISE := 26.0

var _t: float = 0.0
var _phase: float = 0.0
var _flash: float = 0.0
var _shown: bool = false

func _ready() -> void:
	# 盖在角色贴图之上（半透明血泡），但远低于 HUD / 特效层
	z_index = 1
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_phase = fposmod(float(get_instance_id() % 97) * 0.013, TAU)
	if not GameManager.shield_changed.is_connected(_on_shield_changed):
		GameManager.shield_changed.connect(_on_shield_changed)
	set_process(true)

func _process(delta: float) -> void:
	var shield: float = GameManager.shield_hp
	if shield <= 0.05:
		if _shown:
			_shown = false
			visible = false
		_flash = 0.0
		return
	_shown = true
	visible = true
	_t += delta
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * FLASH_DECAY)
	queue_redraw()

func _on_shield_changed(_shield: float, _cap: float) -> void:
	# 结盾（涨）/ 吸盾（落）都闪一下 —— 这是玩家唯一能读到「盾在动」的时刻
	_flash = 1.0

func _draw() -> void:
	var shield: float = GameManager.shield_hp
	if shield <= 0.05:
		return
	var cap := BalanceChain.shield_cap(_max_hp())
	var ratio: float = clampf(shield / maxf(cap, 1.0), 0.0, 1.0)
	var pulse: float = sin(_t * TAU * PULSE_HZ + _phase) * PULSE_AMP
	var thick: float = lerpf(THICK_MIN, THICK_MAX, ratio) + pulse + _flash * 0.22
	thick = clampf(thick, 0.04, 0.5)
	var body := GameStyle.FX_HDR_XUEHAI
	# 椭圆用「圆 + 非等比缩放」画：省掉手写多边形，外缘仍是解析椭圆
	draw_set_transform(CENTER, 0.0, Vector2(RX / RY, 1.0))
	# 1. 填充血泡（半透明，盾越厚越实）
	draw_circle(Vector2.ZERO, RY, Color(body.r, body.g, body.b, thick * 0.42), true, -1.0, true)
	# 2. 亮边（血泡的边界要读得出，不然就是一团雾）
	draw_arc(Vector2.ZERO, RY, 0.0, TAU, 40, Color(body.r, body.g, body.b, thick + 0.18), 2.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 3. 上浮血珠：三颗沿椭圆外缘缓慢上升，纯相位驱动（不需随机数）
	var edge := Color(body.r, body.g, body.b, 0.55 + _flash * 0.35)
	for i in range(DRIP_COUNT):
		var ph: float = fposmod(_t * 0.55 + float(i) / float(DRIP_COUNT) + _phase * 0.1, 1.0)
		var ang: float = -PI * 0.5 + (float(i) - 1.0) * 0.7
		var start := CENTER + Vector2(cos(ang) * RX, sin(ang) * RY * 0.9)
		var p := start - Vector2(0.0, ph * DRIP_RISE)
		draw_circle(p, 1.8 * (1.0 - ph * 0.6), Color(edge.r, edge.g, edge.b, edge.a * (1.0 - ph)), true, -1.0, true)

func _max_hp() -> float:
	var p := GameManager.player
	if p != null and is_instance_valid(p):
		return float(p.max_health)
	return 1.0
