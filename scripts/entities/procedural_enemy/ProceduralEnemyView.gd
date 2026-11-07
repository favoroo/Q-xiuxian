class_name ProceduralEnemyView
extends Node2D

## 敌人程序化矢量视图容器节点
## 挂载于 EnemyBase 下，负责桥接宿主物理状态与 HollowKnightEnemyRenderer 渲染管线
## 2026-10-24 全量 setter 脏值短路：EnemyBase 每物理帧同步 12 项状态（35 敌 × 60Hz ≈ 2.5 万次
## setter/秒），绝大多数帧值未变；不判新旧会白穿透一层转发（口径同 renderer.flip_h 的
## 2026-10-13 掉帧根因注释）。阈值用精确相等 —— 只为拦「完全没变」的写，变了必然放行。

@export var config: EnemyVisualConfig

var renderer: HollowKnightEnemyRenderer

var flip_h: bool = false:
	set(val):
		if val == flip_h:
			return
		flip_h = val
		if renderer:
			renderer.flip_h = val

var facing: String = "s":
	set(val):
		if val == facing:
			return
		facing = val
		if renderer:
			renderer.facing = val

var bank_angle: float = 0.0:
	set(val):
		if val == bank_angle:
			return
		bank_angle = val
		if renderer:
			renderer.bank_angle = val

var advance: float = 0.0:
	set(val):
		if val == advance:
			return
		advance = val
		if renderer:
			renderer.advance = val

var speed_ratio: float = 1.0:
	set(val):
		if val == speed_ratio:
			return
		speed_ratio = val
		if renderer:
			renderer.speed_ratio = val

var is_moving: bool = false:
	set(val):
		if val == is_moving:
			return
		is_moving = val
		if renderer:
			renderer.is_moving = val

## 步态相位（弧度）：EnemyBase 按实际位移推进，渲染器摆翼/蠕波与之同相
var gait_phase: float = 0.0:
	set(val):
		if val == gait_phase:
			return
		gait_phase = val
		if renderer:
			renderer.gait_phase = val

var special_state: float = 0.0:
	set(val):
		if val == special_state:
			return
		special_state = val
		if renderer:
			renderer.special_state = val

var aim_dir: Vector2 = Vector2.ZERO:
	set(val):
		if val == aim_dir:
			return
		aim_dir = val
		if renderer:
			renderer.aim_dir = val

## 生命比例（0~1，1=满血）：渲染层据此加大喘息幅度/压低浮沉/加残血歪斜。
## 纯表现读数，不参与任何判定（分层铁律：渲染层只读状态）。
var hp_ratio: float = 1.0:
	set(val):
		if val == hp_ratio:
			return
		hp_ratio = val
		if renderer:
			renderer.hp_ratio = val

func trigger_recoil(dir: Vector2 = Vector2.ZERO) -> void:
	if renderer != null:
		renderer.trigger_recoil(dir)

## 机制事件脉冲（治疗/产卵等）：渲染器据此演一次动作，纯表现
func trigger_cast_pulse() -> void:
	if renderer != null:
		renderer.trigger_cast_pulse()

func get_weapon_tip_global_pos() -> Vector2:
	if renderer != null:
		return renderer.to_global(renderer.get_tip_local_pos())
	return global_position

## 鼓妖光环标记（0/1）：脚下青玉符环，读出「这只怪被加速了、先杀鼓妖」（土豆兄弟 Buffer 红描边同思路）。
## pixelfx 接入（2026-11-07 车道 E）：原矢量细环下线，换 rune_circle 常驻 loop 子精灵 —— 不占
## FxFlipbookPool 池位，自建 AnimatedSprite2D 子节点（帧/offset/缩放/HDR 见 _ensure_aura_sprite）。
## 尺寸：rune_circle 基础 scale 1.8、帧 136×100 ⇒ 帧世界宽 ≈68px（136×1.8×0.28），
## 帧内符环直径 ≈57px（实测符环宽 ≈112 源px）。青玉染压到半透明，只作「被加速」的脚下读数。
const AURA_FX_ID := &"rune_circle"
const AURA_FX_SCALE_MULT := 0.28
const AURA_FX_TINT := Color(0.55, 1.0, 0.75, 0.5)
const AURA_FX_FEET_Y := 15.0  ## 符环落点：对齐 renderer 地面阴影带（y≈14~16），同旧矢量环 (0,15)

var aura_level: float = 0.0:
	set(val):
		if aura_level == val:
			return
		aura_level = val
		_set_aura_visible(aura_level > 0.0)

var _aura_sprite: AnimatedSprite2D = null
var _aura_frames_missing: bool = false  ## 序列帧缺失：不再重试建精灵，走 _draw 矢量细环兜底

func _draw() -> void:
	# 画在视图容器自身（y=0 是敌人身体中心），脚下偏移对齐 renderer 的地面阴影带（y≈14~16）。
	# 符环子精灵建起来后只走子精灵；子精灵缺席（序列帧未导入，或下面 pixelfx 接入点被回退）才走矢量细环。
	if aura_level > 0.0 and _aura_sprite == null:
		draw_arc(Vector2(0.0, AURA_FX_FEET_Y), 18.0, 0.0, TAU, 24, GameStyle.JADE, 2.0, true)

## 建一次符环子精灵（loop 常驻、不占池）：帧/offset/缩放/HDR 一步到位。
## 序列帧不可用时置 _aura_frames_missing，_draw 退回矢量细环，光环读数不丢。
func _ensure_aura_sprite() -> void:
	if _aura_sprite != null or _aura_frames_missing:
		return
	var frames := FxSheetData.get_sprite_frames(AURA_FX_ID)
	if frames == null:
		_aura_frames_missing = true
		return
	var sp := AnimatedSprite2D.new()
	sp.sprite_frames = frames
	sp.animation = &"default"
	sp.centered = true
	# offset 把 pivot(68,80)=符环地面圆心对齐节点原点，再下移到脚底，与旧矢量环同落点
	sp.offset = FxSheetData.get_offset(AURA_FX_ID)
	sp.position = Vector2(0.0, AURA_FX_FEET_Y)
	sp.scale = Vector2.ONE * float(FxSheetData.get_config(AURA_FX_ID).get("scale", 1.8)) * AURA_FX_SCALE_MULT
	sp.modulate = AURA_FX_TINT
	sp.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var mat := FxFlipbookPool.get_hdr_material()
	if mat != null and not FxBudget.crowded:
		sp.material = mat
	sp.visible = aura_level > 0.0
	add_child(sp)
	move_child(sp, 0)  # 排在 renderer 之前：符环压在敌身之下（同旧矢量环的父自绘层次）
	_aura_sprite = sp

## 光环显隐（与 aura_level 同拍）：显隐与播放状态一致，禁止隐藏后仍留播放中精灵
func _set_aura_visible(on: bool) -> void:
	if on:
		# pixelfx 接入点（回退：注释下一行）
		_ensure_aura_sprite()
	if _aura_sprite != null:
		_aura_sprite.visible = on
		if on:
			if not _aura_sprite.is_playing():
				_aura_sprite.play(&"default")
		else:
			_aura_sprite.stop()
	elif is_inside_tree():
		queue_redraw()  # 子精灵缺席（序列帧未导入/接入点已回退）：矢量细环兜底要重绘

## 池化实体出树（回池休眠/清场/释放）同拍整备：符环子精灵熄灯停表，禁止休眠体上残留播放中精灵（坑 13）。
## 同时把 aura_level 归零 —— EnemyBase.reset_for_reuse 只清 _aura_shown、不清视图读数；不归零则下一命
## 在视野外用旧值 1.0 被罩到时 setter 直接短路，符环永远不再亮起。
func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE:
		if _aura_sprite != null:
			_aura_sprite.visible = false
			_aura_sprite.stop()
		aura_level = 0.0

func _ready() -> void:
	if renderer == null:
		_init_renderer()

func _init_renderer() -> void:
	renderer = HollowKnightEnemyRenderer.new()
	renderer.use_parent_material = true
	if config:
		renderer.config = config
	renderer.flip_h = flip_h
	renderer.facing = facing
	add_child(renderer)

## 外部初始化敌种配置入口
func setup(eid: String, is_elite: bool = false, is_boss: bool = false, is_final: bool = false) -> void:
	config = EnemyVisualConfig.get_config(eid, is_elite, is_boss, is_final)
	if renderer == null:
		_init_renderer()
	else:
		renderer.config = config
