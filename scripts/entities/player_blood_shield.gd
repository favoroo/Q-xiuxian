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
##
## 【2026-11-07 pixelfx 罩面】矢量血泡（_draw）保留为底层 —— 低配兜底 + 判定同源；
## 其上叠 pixelfx `blood_ward` 常驻子精灵（球面经线 + 扫光 loop，血红调 modulate），
## 罩心对齐泡心；血珠上浮与结盾闪边原样保留。

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

## pixelfx 血盾罩面（2026-11-07 线条圈通刷接入）：叠在矢量血泡之上的常驻子精灵。
const WARD_ID := &"blood_ward"      ## 88×84 源画幅，基础 scale 1.0，pivot(44,68)=罩心
const WARD_ALPHA := 0.6             ## 罩面基准不透明度（血红调 modulate，半透不挡角色）
const WARD_FLASH_EXTRA := 0.35      ## 结盾/吸盾闪光叠加到罩面上的额外不透明度

var _t: float = 0.0
var _phase: float = 0.0
var _flash: float = 0.0
var _shown: bool = false
var _ward: AnimatedSprite2D = null  ## 罩面常驻子精灵（loop，随本节点显隐）

func _ready() -> void:
	# 盖在角色贴图之上（半透明血泡），但远低于 HUD / 特效层
	z_index = 1
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_phase = fposmod(float(get_instance_id() % 97) * 0.013, TAU)
	_build_ward()   # pixelfx 接入点（回退：注释本行即只剩矢量血泡）
	if not GameManager.shield_changed.is_connected(_on_shield_changed):
		GameManager.shield_changed.connect(_on_shield_changed)
	set_process(true)

func _process(delta: float) -> void:
	var shield: float = GameManager.shield_hp
	if shield <= 0.05:
		if _shown:
			_shown = false
			visible = false
		# 罩面自带贴图，宿主 _draw 的提前 return 挡不住子精灵：无盾时显式收掉
		if _ward != null:
			_ward.visible = false
		_flash = 0.0
		return
	_shown = true
	visible = true
	_t += delta
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * FLASH_DECAY)
	# 罩面随结盾/吸盾一起闪一下（与矢量亮边同一个 _flash 读数）
	if _ward != null:
		_ward.visible = true
		_ward.modulate = GameStyle.with_alpha(GameStyle.FX_HDR_XUEHAI, minf(1.0, WARD_ALPHA + _flash * WARD_FLASH_EXTRA))
	queue_redraw()

func _on_shield_changed(_shield: float, _cap: float) -> void:
	# 结盾（涨）/ 吸盾（落）都闪一下 —— 这是玩家唯一能读到「盾在动」的时刻
	_flash = 1.0

## pixelfx 血盾罩面（blood_ward）：贴图自带球面经线 + 扫光 loop，压在矢量血泡（宿主 _draw）之上。
## pivot(44,68) 是罩心，配置 offset 把罩心对到节点原点；这里再摆到泡心 CENTER，罩心对齐泡心。
## 已知风险：源效果导出时剥离了假人（holy/divine-shield），罩面若被确认空壳，本子项整段回退
## （注释掉 _ready 里的 _build_ward() 调用即可，矢量血泡不受影响）。
func _build_ward() -> void:
	if _ward != null:
		return
	var frames := FxSheetData.get_sprite_frames(WARD_ID)
	if frames == null:
		return
	var conf: Dictionary = FxSheetData.get_config(WARD_ID)
	var fw: float = 88.0
	var base: float = 1.0
	if not conf.is_empty():
		var fs: Vector2 = conf.get("frame_size", Vector2(88.0, 84.0))
		fw = maxf(fs.x, 1.0)
		base = float(conf.get("scale", 1.0))
	# 罩径换算：血泡是椭圆（RX×RY），罩是球 —— 取主导直径（2×RY）作目标世界宽，
	# 球面完整罩住血泡（2×RY=62 ≥ 泡宽 2×RX=44）；mult = D /(画幅宽 × 基础 scale)
	var mult: float = (2.0 * RY) / (fw * base)
	var anim := AnimatedSprite2D.new()
	anim.name = "BloodWardFx"
	anim.sprite_frames = frames
	anim.animation = &"default"
	anim.centered = true
	anim.offset = FxSheetData.get_offset(WARD_ID)
	anim.position = CENTER
	anim.scale = Vector2.ONE * (base * mult)
	anim.modulate = GameStyle.with_alpha(GameStyle.FX_HDR_XUEHAI, WARD_ALPHA)
	anim.visible = false   ## 无盾时先收起（_process 按盾量显隐）
	var mat := FxFlipbookPool.get_hdr_material()
	if mat != null and not FxBudget.crowded:
		anim.material = mat
	add_child(anim)
	anim.play(&"default")
	_ward = anim

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
