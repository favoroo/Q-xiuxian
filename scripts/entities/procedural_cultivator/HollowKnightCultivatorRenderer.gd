class_name HollowKnightCultivatorRenderer
extends CultivatorRendererBase

## 通用模块化修仙角色渲染器（土豆兄弟式参数化驱动·高精仙侠版）
## 基于统一修仙素体与 4 大外观插槽（体型、面部、斗篷、武器），实现全道统角色的极速拓展与高辨识度差异化

# ----------------- 颜色缓存 -----------------
var col_void: Color = Color(0.06, 0.07, 0.10)
var col_bone: Color = Color(0.96, 0.97, 0.99)
var col_bone_shadow: Color = Color(0.76, 0.82, 0.88)
var col_eye_glow: Color = Color(0.75, 0.92, 1.0, 0.45)
var col_eye_core: Color = Color(0.98, 1.0, 1.0)
var col_cloak_outer: Color = Color(0.11, 0.24, 0.17)
var col_cloak_inner: Color = Color(0.18, 0.38, 0.28)
var col_cloak_edge: Color = Color(0.28, 0.62, 0.46)
var col_weapon_main: Color = Color(0.95, 0.97, 1.0)
var col_weapon_shadow: Color = Color(0.70, 0.78, 0.86)
var col_weapon_accent: Color = Color(1.0, 1.0, 1.0, 0.9)
var col_slash_arc: Color = Color(0.92, 0.98, 1.0, 0.95)
var col_slash_glow: Color = Color(0.40, 0.85, 0.70, 0.4)

# 修仙细节专属辅助色
var col_gold: Color = Color(0.96, 0.84, 0.32)
var col_gold_shadow: Color = Color(0.65, 0.48, 0.18)
var col_jade: Color = Color(0.58, 0.94, 0.80)
var col_tassel_red: Color = Color(0.88, 0.22, 0.18)

# ----------------- 皮肤系列效果状态 -----------------
## 皮肤效果族调度库（按 fx["kind"] 派发到 skin_fx/ 各模块）
const SkinFxLibrary = preload("res://scripts/entities/procedural_cultivator/skin_fx/SkinFxLibrary.gd")

## 空字典 = 原色（无效果，零开销快路）；非空 = 已合并族默认值的效果参数（含 kind）
var _fx: Dictionary = {}
## 基准色快照：色相流转只改 H，S/V 一律取自快照（防多次流转后褪色/漂白）
var _fx_base: Dictionary = {}

# ----------------- 插槽参数缓存 -----------------
var body_scale: float = 1.0
var width_scale: float = 1.0
var height_scale: float = 1.0
var head_scale: float = 1.0

## 是否抑制眼部柔和同心光晕（App 图标/Splash 特写等高倍缩放场景下避免外圈半透明光盘切边）
var suppress_eye_glow: bool = false

# ----------------- 背负武器位姿基准 -----------------
## 正面：斜背，柄与剑首从右肩外探出、剑尖朝下收进斗篷后。
## 锚点刻意压在面具轮廓（oval_chin 左右 x=±9.5、下巴 y=-5）之外——
## 骨钉剑/厚背断刀/兽骨斧的填充色与骨白面壳色差不到 0.17，一贴脸就画成"剑长在脸上"。
const CARRY_FRONT_POS := Vector2(10.5, 0.0)
const CARRY_FRONT_ROT := 205.0
## 侧面：武器负于后背中下方，端头向后上轻挑，下端收于斗篷内
const CARRY_SIDE_POS := Vector2(-6.5, 4.5)
const CARRY_SIDE_ROT := -18.0
## 背面：横贯背部中下方，上端留足离后脑的空白
const CARRY_BACK_POS := Vector2(2.0, 11.0)
const CARRY_BACK_ROT := 158.0

var carry_front_pos: Vector2 = CARRY_FRONT_POS
var carry_front_rot: float = CARRY_FRONT_ROT
var carry_side_pos: Vector2 = CARRY_SIDE_POS
var carry_side_rot: float = CARRY_SIDE_ROT
var carry_back_pos: Vector2 = CARRY_BACK_POS
var carry_back_rot: float = CARRY_BACK_ROT

var mask_style: String = "oval_chin"
var horns_style: String = "butterfly"
var eye_style: String = "hollow_oval"
var cloak_style: String = "split_flowing"
var chest_ornament: String = "pearl"
var weapon_type: String = "bone_nail"
var strap_style: String = "diagonal"

func _init(p_cfg: CultivatorVisualConfig = null) -> void:
	if p_cfg != null:
		config = p_cfg
	elif config == null:
		config = CultivatorVisualConfig.make_jianchi()
	_sync_config()

func _on_config_changed() -> void:
	_sync_config()

func _sync_config() -> void:
	if config == null:
		return

	# 1. 体型插槽
	var b_dict: Dictionary = config.body
	body_scale = float(b_dict.get("scale", 1.0))
	width_scale = float(b_dict.get("width_scale", 1.0))
	height_scale = float(b_dict.get("height_scale", 1.0))
	head_scale = float(b_dict.get("head_scale", 1.0))

	# 2. 面孔插槽
	var f_dict: Dictionary = config.face
	mask_style = String(f_dict.get("mask_style", "oval_chin"))
	horns_style = String(f_dict.get("horns_style", "butterfly"))
	eye_style = String(f_dict.get("eye_style", "hollow_oval"))
	col_eye_glow = f_dict.get("eye_color", Color(0.75, 0.92, 1.0, 0.45))
	col_eye_core = f_dict.get("eye_core_color", Color(0.98, 1.0, 1.0))

	# 3. 斗篷插槽
	var c_dict: Dictionary = config.cloak
	cloak_style = String(c_dict.get("cloak_style", "split_flowing"))
	chest_ornament = String(c_dict.get("chest_ornament", "pearl"))
	col_cloak_outer = c_dict.get("col_outer", Color(0.11, 0.24, 0.17))
	col_cloak_inner = c_dict.get("col_inner", Color(0.18, 0.38, 0.28))
	col_cloak_edge = c_dict.get("col_edge", Color(0.28, 0.62, 0.46))

	# 4. 武器插槽
	var w_dict: Dictionary = config.weapon
	weapon_type = String(w_dict.get("weapon_type", "bone_nail"))
	strap_style = String(w_dict.get("strap_style", "diagonal"))
	col_weapon_main = w_dict.get("col_main", Color(0.95, 0.97, 1.0))
	col_weapon_shadow = w_dict.get("col_shadow", Color(0.70, 0.78, 0.86))
	col_weapon_accent = w_dict.get("col_accent", Color(1.0, 1.0, 1.0, 0.9))
	carry_front_pos = w_dict.get("carry_front_pos", CARRY_FRONT_POS)
	carry_front_rot = float(w_dict.get("carry_front_rot", CARRY_FRONT_ROT))
	carry_side_pos = w_dict.get("carry_side_pos", CARRY_SIDE_POS)
	carry_side_rot = float(w_dict.get("carry_side_rot", CARRY_SIDE_ROT))
	carry_back_pos = w_dict.get("carry_back_pos", CARRY_BACK_POS)
	carry_back_rot = float(w_dict.get("carry_back_rot", CARRY_BACK_ROT))

	# 骨玉基底
	col_bone = config.bone_white
	col_bone_shadow = config.bone_shadow
	col_void = config.void_black
	col_slash_glow = col_cloak_edge

	# 协调衍生细节色
	if cloak_style == "royal_shawl":
		col_gold = col_cloak_edge
	elif cloak_style == "tattered_rags":
		col_gold = Color(0.80, 0.70, 0.48)
	else:
		col_gold = Color(0.96, 0.84, 0.32)

	# 皮肤系列效果：合并族默认值 + 主题覆盖后缓存；原色（fx 空）清空并复位基准色
	# （非效果皮肤必须在 _sync_config 里清空 _fx，否则同一渲染器实例换皮肤会串色）
	_fx = SkinFxLibrary.params(config.fx)
	_fx_base = {
		"cloak_outer": col_cloak_outer,
		"cloak_inner": col_cloak_inner,
		"cloak_edge": col_cloak_edge,
		"eye_glow": col_eye_glow,
		"eye_core": col_eye_core,
		"weapon_main": col_weapon_main,
		"weapon_shadow": col_weapon_shadow,
		"weapon_accent": col_weapon_accent,
		"gold": col_gold,
		"jade": col_jade,
		"tassel": col_tassel_red,
		"slash_arc": col_slash_arc,
	}

## 重绘前钩子：皮肤系列效果按 _time 重算缓存色，原色零开销
func _on_before_redraw() -> void:
	if _fx.is_empty():
		return
	SkinFxLibrary.on_frame(self, _fx)

## 动态设置视觉配置
func set_visual_config(cfg: CultivatorVisualConfig) -> void:
	config = cfg
	_sync_config()
	queue_redraw()

# ==================== 布料动态：平滑状态与行波上下文 ====================

## 步频基准（与 Player.gd 的 gait_phase_counter 推进同源：delta * 2.4 * speed_k）
const GAIT_RATE := 2.4
## 奔跑悬浮漂移（2026-10-24）：身体上下起伏与脚步解耦，改「飘」不再「蹦」。
## 旧实现是 sin(gait_phase*TAU) 的 ±2.4px —— 与 Player 的 squash 弹跳同相位同频，
## 两个波峰每步一起顶到最高点，读成「跟着脚步一蹦一跳」。
## 现为主频 ~1.2Hz 叠 0.43× 慢副频（副频带 _idle_phase 错相），合成幅度 ±1.3px：
## 波峰不再踩在落地点上，节拍器感消失，剩下缓慢的悬浮起伏。
const GLIDE_MAIN_AMP := 0.9     ## 主频振幅（px）
const GLIDE_SUB_AMP := 0.4      ## 慢副频振幅（px）
const GLIDE_SUB_FREQ := 0.43    ## 副频相对主频
const GLIDE_BASE_FREQ := 1.15   ## 主频（Hz）：远低于 2.4Hz 步频，两者不同拍
const GLIDE_SPEED_GAIN := 0.35  ## 移速对主频的增益（满速 ≈1.55Hz）
## RUN↔IDLE 动作交叉淡化时长（秒）：停步不再瞬间换公式/压平弹跳
const ACTION_BLEND_TIME := 0.18

var _wind_local: Vector2 = Vector2.ZERO  ## 平滑后的移动风压（世界系，绘制时按 flip_h 镜像到局部）
var _speed_smooth: float = 0.0           ## 平滑后的移速比率：起停时斗篷风阻渐变，不突跳
var _lean_smooth: float = 0.0            ## 平滑后的侧倾：衣摆滞后于身体 4.8° 弹性倾角
## RUN 混合权重（0=待机，1=奔跑）：身体浮沉、斗篷振幅/风阻全部按它交叉淡化，
## 避免 play_idle/play_run 切换那一拍公式突变造成「一顿」
var _run_blend: float = 0.0
## 斗篷行波相位（连续积分，不直接取 _time/gait_phase）：动作切换时相位不跳变，
## 频率随 _run_blend 从待机慢呼吸平滑过渡到步频，布料不会瞬移
var _cloak_phase: float = 0.0
## 悬浮漂移相位（连续积分，2026-10-24）：身体上下起伏的唯一时基。
## 不取 gait_phase —— 那是脚步的节拍；身体要「飘」，就不能踩着落地点起跳。
## 连续积分保证变速时相位不跳变（改频率只改推进速率）。
var _float_phase: float = 0.0

## 行波上下文（_draw_modular_cloak 注入，供 _sway_x/_sway_y 消费）
var _cw_amp: float = 0.0              ## 行波振幅基准（px）
var _cw_t: float = 0.0                ## 行波相位基准（由各动作按自身频率给出）
var _cw_wind: Vector2 = Vector2.ZERO  ## 局部空间风压（含镜像校正）
var _cw_lean: float = 0.0             ## 侧倾滞后横推基准

func _process(delta: float) -> void:
	super(delta)
	var running := current_action == CultivatorRendererBase.Action.RUN
	var k := minf(delta * 6.0, 1.0)
	_wind_local = _wind_local.lerp(move_dir if running else Vector2.ZERO, k)
	_speed_smooth = lerpf(_speed_smooth, speed_ratio if running else 0.0, minf(delta * 8.0, 1.0))
	_lean_smooth = lerpf(_lean_smooth, lean_angle if running else 0.0, k)

	# 动作交叉淡化：RUN↔IDLE 的浮沉/斗篷在 0.18s 内过渡，不再瞬间换公式
	_run_blend = move_toward(_run_blend, 1.0 if running else 0.0, delta / ACTION_BLEND_TIME)
	# 斗篷行波相位连续积分：待机 ~0.25Hz 慢呼吸 ↔ 奔跑半步频（布料跟不上脚步，约为步频一半），
	# 按 _run_blend 平滑过渡；相位连续所以起停/变速时衣摆不会瞬移
	var idle_freq := 2.6 / maxf(body_scale, 0.6)
	var run_cloak_rate := TAU * GAIT_RATE * 0.5 * clampf(speed_ratio, 0.7, 1.4)
	var cloak_rate := lerpf(idle_freq * 0.62, run_cloak_rate, _run_blend)
	_cloak_phase = fmod(_cloak_phase + cloak_rate * delta, TAU)

	# 悬浮漂移相位：与步频完全独立的时间基，移速只让漂移略快一点（1.15→1.55Hz），
	# 永远追不上 2.4Hz 的脚步，所以两者不会锁相成「每步一蹦」。
	# 注意：这里**不能** fmod 回绕 —— 副频取 _float_phase * GLIDE_SUB_FREQ（非整数倍），
	# 相位一旦从 TAU 跳回 0，副频项会瞬移 ~2.7 弧度，每 0.7s 抖一下。
	# GDScript float 是 64 位双精度，连续累加数小时也不掉精度。
	var glide_rate := TAU * GLIDE_BASE_FREQ * (1.0 + GLIDE_SPEED_GAIN * clampf(_speed_smooth, 0.0, 1.2))
	_float_phase += glide_rate * delta

	_tick_blink(delta)

## 待机呼吸浮沉（px）：体型越大越沉缓，相位按 instance_id 错开
func _idle_float_y() -> float:
	var idle_freq := 2.6 / maxf(body_scale, 0.6)
	var idle_amp := 1.4 * clampf(body_scale, 0.8, 1.25)
	return sin(_time * idle_freq + _idle_phase) * idle_amp

## 奔跑悬浮漂移（px）：与脚步解耦的双频慢漂（2026-10-24）。
## 旧实现 sin(gait_phase*TAU)*2.4 与 Player 的 squash 弹跳同相叠峰 → 「一蹦一跳」；
## 现改吃独立的 _float_phase，主频 + 慢副频破节拍器感，合成峰值 ±1.3px。
func _run_float_y() -> float:
	return sin(_float_phase) * GLIDE_MAIN_AMP \
			+ sin(_float_phase * GLIDE_SUB_FREQ + _idle_phase) * GLIDE_SUB_AMP

## 漂移归一化值（-1~1）：影子/武器随动共用的同一股浮沉，保证身-影-兵同相位。
## 除以合成峰值，把 ±1.3px 映射回 ±1 供各处的幅度系数直接乘。
func _glide_norm() -> float:
	var amp := GLIDE_MAIN_AMP + GLIDE_SUB_AMP
	if amp <= 0.0001:
		return 0.0
	return _run_float_y() / amp

## 身体浮沉唯一出口：待机/奔跑按 _run_blend 交叉淡化，起停不跳变
func _body_float_y() -> float:
	return lerpf(_idle_float_y(), _run_float_y(), _run_blend)

# ==================== 眨眼：自然拟真调度（2026-10-23） ====================
## 旧实现是 fmod(_time*0.24,1) 的固定 4.17s 单眨：节奏可被肉眼预测，且闭眼靠
## blink>0.45 硬阈值切两套几何，中间没有半闭态 → 「突然就眨一下」的机械感。
## 新实现：随机 2~6s 一次；30% 概率连眨 2~3 下（间隔 0.12~0.22s）；15% 半眨；
## 单次包络「闭合快(0.06s) → 保持(0.02s) → 睁开慢(0.10s)」。
## 随机源用局部 RNG（instance_id 播种）：纯视觉节奏，不消耗 GameManager.rng 的玩法序列，
## 同屏多个角色也能各自错开。绘制端按 0~1 连续盖眼睑，见 _draw_eyelids。
const BLINK_GAP_MIN := 2.0
const BLINK_GAP_MAX := 6.0
const BLINK_BURST_CHANCE := 0.30
const BLINK_BURST_MIN := 2          ## 连眨最少总次数
const BLINK_BURST_MAX := 3          ## 连眨最多总次数
const BLINK_BURST_GAP_MIN := 0.12
const BLINK_BURST_GAP_MAX := 0.22
const BLINK_HALF_CHANCE := 0.15     ## 半眨概率
const BLINK_HALF_MIN := 0.60
const BLINK_HALF_MAX := 0.80
const BLINK_CLOSE_TIME := 0.075
const BLINK_HOLD_TIME := 0.02
const BLINK_OPEN_TIME := 0.12
const BLINK_FORCE_OPEN_TIME := 0.05 ## 切到紧张动作时的快速睁眼时长

var _blink_rng := RandomNumberGenerator.new()
var _blink_wait: float = 0.0        ## 距下一次眨眼（或连眨间隔）的剩余秒
var _blink_burst_left: int = 0      ## 本轮连眨还欠几下
var _blink_t: float = -1.0          ## 当前这一下的进度；<0 表示不在眨
var _blink_amp: float = 1.0         ## 本下闭合幅度（1=全闭，0.6~0.8=半眨）
var _blink_value: float = 0.0       ## 当前闭眼程度 0~1（绘制消费）
## 预览/判据用的手动覆盖（-1 = 关闭，走正常调度）：帧条导出需要逐帧指定闭眼程度，
## 否则渲染器自己的 _process 会在截图间隙把值推进掉。
var _blink_override: float = -1.0

func _ready() -> void:
	super._ready()
	# instance_id 播种：同屏角色各自错开，且判据可复现（不碰玩法随机）
	_blink_rng.seed = int(get_instance_id()) * 7919 + 13
	_blink_wait = _blink_rng.randf_range(0.8, 3.0)

## 眨眼调度推进：等待 → 起眨 → 包络推进 → 收尾/连眨
func _tick_blink(delta: float) -> void:
	if _blink_override >= 0.0:
		_blink_value = _blink_override
		return
	var relaxed := current_action == CultivatorRendererBase.Action.IDLE \
			or current_action == CultivatorRendererBase.Action.RUN
	if not relaxed:
		# 受击/冲刺/攻击：不眨眼；若正眨到一半则快速睁开（0.05s），不硬切
		if _blink_value > 0.0:
			_blink_value = move_toward(_blink_value, 0.0, delta / BLINK_FORCE_OPEN_TIME)
		if _blink_value <= 0.0:
			_blink_t = -1.0
			_blink_burst_left = 0
			if _blink_wait <= 0.0:
				_blink_wait = _blink_rng.randf_range(BLINK_GAP_MIN, BLINK_GAP_MAX)
		return

	if _blink_t < 0.0:
		_blink_wait -= delta
		if _blink_wait <= 0.0:
			_start_blink()
		return

	_blink_t += delta
	var dur := BLINK_CLOSE_TIME + BLINK_HOLD_TIME + BLINK_OPEN_TIME
	if _blink_t >= dur:
		_blink_value = 0.0
		_blink_t = -1.0
		if _blink_burst_left > 0:
			_blink_burst_left -= 1
			_blink_wait = _blink_rng.randf_range(BLINK_BURST_GAP_MIN, BLINK_BURST_GAP_MAX)
		else:
			_blink_wait = _blink_rng.randf_range(BLINK_GAP_MIN, BLINK_GAP_MAX)
		return

	_blink_value = _blink_envelope(_blink_t) * _blink_amp

func _start_blink() -> void:
	_blink_t = 0.0
	_blink_amp = 1.0
	if _blink_rng.randf() < BLINK_HALF_CHANCE:
		_blink_amp = _blink_rng.randf_range(BLINK_HALF_MIN, BLINK_HALF_MAX)
	# 连眨只在序列起点掷一次：burst_left = 总次数-1（后面还有几下）
	if _blink_burst_left <= 0 and _blink_rng.randf() < BLINK_BURST_CHANCE:
		_blink_burst_left = _blink_rng.randi_range(BLINK_BURST_MIN, BLINK_BURST_MAX) - 1
	_blink_value = 0.0

## 单次眨眼包络：闭合 smoothstep（快而不生硬）→ 保持 → 睁开 smoothstep（略慢）
## 两端导数都为 0，起眨/睁眼没有折角；0.075s 闭合在 60fps 下约 4.5 帧，足够看出「合上」的过程
func _blink_envelope(t: float) -> float:
	if t < BLINK_CLOSE_TIME:
		var k := clampf(t / BLINK_CLOSE_TIME, 0.0, 1.0)
		return k * k * (3.0 - 2.0 * k)
	var hold_end := BLINK_CLOSE_TIME + BLINK_HOLD_TIME
	if t < hold_end:
		return 1.0
	var k2 := clampf((t - hold_end) / BLINK_OPEN_TIME, 0.0, 1.0)
	return 1.0 - k2 * k2 * (3.0 - 2.0 * k2)

## 下摆顶点行波偏移（x 方向）：相位随横向位置与下摆深度推进，越靠边、越靠下越滞后，
## 振幅随深度增大——衣摆从躯干向外柔和传播，取代旧版整块共相位摆动。
## 叠加项：高频微风轻颤 + 风压横推/侧倾滞后（含蓄 1~3px 级）。
func _sway_x(x: float, y: float) -> float:
	var depth := clampf((y - 8.0) / 24.0, 0.0, 1.0)
	var travel := absf(x) * 0.14 + depth * 1.7
	var sway := sin(_cw_t + travel) * _cw_amp * (0.35 + depth * 0.8)
	var breeze := sin(_time * 11.0 + travel * 1.6) * _cw_amp * 0.22 * depth
	var wind_x := (-_cw_wind.x * 1.2 + _cw_lean) * depth
	return sway + breeze + wind_x

## 下摆顶点风向掀升（y 方向）：向上移动衣摆向后下轻拖，向下移动衣摆轻扬收拢（2px 级）
func _sway_y(y: float) -> float:
	var depth := clampf((y - 8.0) / 24.0, 0.0, 1.0)
	return -_cw_wind.y * 2.2 * depth

## 头饰软部件（簪尾红绳、髻根头绳穗、额前黄符）的二级动力学偏移：
## 与斗篷同源的平滑风压（_wind_local 按 flip_h 镜像到局部）+ 移速惯性后拖 + 步频颠簸 + 微风轻颤，
## lag 做相位错开（左右穗子不同拍）。骨角/斗笠/金冠等刚性部件禁用——硬物不飘。
func _head_soft_sway(lag: float = 0.0) -> Vector2:
	var wind_x := _wind_local.x * (-1.0 if flip_h else 1.0)
	var speed_k := clampf(_speed_smooth, 0.0, 1.2)
	var breeze := sin(_time * 6.8 + lag * 2.3) * (0.28 + speed_k * 0.4)
	var drag_x := (-wind_x * 1.2 - _lean_smooth * 7.0) * maxf(speed_k, 0.12)
	var run_bob := 0.0
	if current_action == CultivatorRendererBase.Action.RUN:
		run_bob = sin(gait_phase * TAU + lag * 1.7) * 0.45 * speed_k
	return Vector2(drag_x + breeze, run_bob + breeze * 0.3)

## 当前眼皮闭合度 0~1（由 _tick_blink 状态机维护，见「眨眼：自然拟真调度」段）。
## 受击/冲刺/攻击不眨眼（调用侧 _calm_blink 门控），绘制端按连续值压眼睑。
func _blink_amount() -> float:
	return _blink_value

## 仅在松弛动作（待机/奔跑）下眨眼；受击/冲刺/攻击睁眼反而有张力
func _calm_blink() -> float:
	if current_action == CultivatorRendererBase.Action.IDLE or current_action == CultivatorRendererBase.Action.RUN:
		return _blink_amount()
	return 0.0

## 斗篷纵向伪光照渐变：肩部提亮、下摆压暗（逐顶点颜色插值，零 shader 成本）
## 皮肤系列效果额外叠一层袍面色（油膜虹彩/竹节/霜纹等，由族模块决定；原色零开销）
func _cloak_gradient(pts: PackedVector2Array, base: Color) -> PackedColorArray:
	var cols := PackedColorArray()
	var fx_on := not _fx.is_empty()
	for p in pts:
		var t := clampf((p.y + 6.0) / 36.0, 0.0, 1.0)
		var c := base.lightened(0.10 * (1.0 - t)).darkened(0.30 * t)
		if fx_on:
			c = SkinFxLibrary.cloak_sheen(self, c, p, _fx)
		cols.append(c)
	return cols

# ==================== 1. 待机 (IDLE) ====================

func _draw_idle(angle: Angle) -> void:
	var total_scale := Vector2(body_scale * width_scale, body_scale * height_scale)
	draw_set_transform(Vector2.ZERO, 0.0, total_scale)

	# 待机差异化呼吸（2026-10-14 P1）：频率按体型反比调——石岳(1.18)沉缓、灵蝶使(0.85)轻快；
	# 相位按 instance_id 错开，同屏待机的角色不再同步起落像拷贝。
	# 2026-10-23：浮沉改走 _body_float_y()（RUN↔IDLE 交叉淡化），起停不再瞬跳
	var idle_t := _time * (2.6 / maxf(body_scale, 0.6)) + _idle_phase
	var float_y := _body_float_y()
	# 待机布料呼吸：低频慢波（~0.25Hz），振幅克制 2px，站桩也有仙气吐纳感。
	# 相位取连续积分的 _cloak_phase；振幅按 _run_blend 与奔跑档交叉淡化，停步不瞬间收摆
	var cloak_amp := lerpf(2.0, 3.3 * (0.9 + 0.18 * sin(gait_phase * TAU)), _run_blend)
	var cloak_t := _cloak_phase
	# 偶发环视（每 6~10s 一次、持续约 0.8s 的视线偏移）：instance_id 错开时刻，
	# 眼睛朝随机侧偏 1.4px 再荡回——待机也有生命感的廉价高级感
	var gaze_cycle := fmod(_time * 0.145 + _idle_phase, 1.0)  # ~6.9s 一个周期
	var gaze_t := clampf((gaze_cycle - 0.72) / 0.12, 0.0, 1.0)  # 末段 0.83s 内完成
	var gaze_off := sin(gaze_t * PI) * 1.4 * (1.0 if fmod(_idle_phase, TAU) < PI else -1.0)
	var eye_pulse := sin(idle_t * 1.15) * 0.08

	_draw_ground_shadow(Vector2(0, 32), 17.0 * width_scale, 4.8, 0.48)
	_draw_immortal_motes(float_y)

	match angle:
		Angle.FRONT:
			_draw_modular_weapon(carry_front_pos + Vector2(0, float_y), deg_to_rad(carry_front_rot), Angle.FRONT)
			_draw_modular_cloak(float_y, cloak_amp, cloak_t, 0.0, Angle.FRONT)
			_draw_head_front_gaze(float_y, eye_pulse, gaze_off)
		Angle.SIDE:
			_draw_modular_weapon(carry_side_pos + Vector2(0, float_y), deg_to_rad(carry_side_rot), Angle.SIDE)
			_draw_modular_cloak(float_y, cloak_amp, cloak_t, 0.0, Angle.SIDE)
			_draw_head_side(float_y, eye_pulse)
		Angle.BACK:
			_draw_modular_cloak(float_y, cloak_amp, cloak_t, 0.0, Angle.BACK)
			_draw_modular_strap(float_y)
			_draw_modular_weapon(carry_back_pos + Vector2(0, float_y), deg_to_rad(carry_back_rot), Angle.BACK)
			_draw_head_back(float_y)

## 待机专用：正面头部带偶发环视偏移（环视只在前视角有意义——实机恒为正面）
func _draw_head_front_gaze(float_y: float, eye_pulse: float, gaze_off: float) -> void:
	if not _layer_on(Layer.HEAD):
		return
	var head_center := Vector2(0, -15 + float_y)
	_draw_modular_headwear(head_center, Angle.FRONT)
	_draw_modular_mask(head_center, Angle.FRONT)
	_draw_modular_eyes(head_center + Vector2(gaze_off, 0.0), Angle.FRONT, eye_pulse, _calm_blink())

# ==================== 2. 奔跑 / 御风飞行 (RUN / GLIDE) ====================

func _draw_run(angle: Angle, _phase: float, _air_val: float) -> void:
	var total_scale := Vector2(body_scale * width_scale, body_scale * height_scale)
	draw_set_transform(Vector2.ZERO, 0.0, total_scale)

	# 2026-10-24 悬浮漂移：身体浮沉改吃独立 _float_phase（不再与脚步同相），
	# 走 _body_float_y() 而非 _run_float_y()：IDLE→RUN 的 0.18s 内从待机浮沉交叉淡入
	var float_y := _body_float_y()
	# 双频斗篷衣摆：主波相位滞后身体 1/4 步循环（布料惯性，随步频自适应），
	# 振幅随步频呼吸涨落，风阻取平滑移速（起停渐变），高频微风在 _sway_x 内叠加
	var cloak_drag := clampf(maxf(_speed_smooth, 0.2), 0.4, 1.4) * 2.8 * _run_blend
	var cloak_amp := lerpf(2.0, 3.3 * (0.9 + 0.18 * sin(gait_phase * TAU)), _run_blend)
	var cloak_t := _cloak_phase

	# 影子/武器随动取漂移的归一化值（不再吃步态相位）：身-影-兵同相位，
	# 幅度已按漂移量级调小，影子只做极轻的收放提示「人在浮着」而非「在蹦」
	var bob := _glide_norm() * _run_blend
	var shadow_alpha := 0.44 - bob * 0.05
	var shadow_rx := (16.5 - bob * 0.8) * width_scale
	_draw_ground_shadow(Vector2(0, 32), shadow_rx, 4.4, shadow_alpha)
	_draw_immortal_motes(float_y)

	match angle:
		Angle.FRONT:
			_draw_modular_weapon(carry_front_pos + Vector2(0, float_y * 0.85), deg_to_rad(carry_front_rot + bob * 2.5), Angle.FRONT)
			_draw_modular_cloak(float_y, cloak_amp, cloak_t, cloak_drag, Angle.FRONT)
			_draw_head_front(float_y, 0.06)
		Angle.SIDE:
			_draw_modular_weapon(carry_side_pos + Vector2(0, float_y), deg_to_rad(carry_side_rot + 1.0), Angle.SIDE)
			_draw_modular_cloak(float_y, cloak_amp, cloak_t, cloak_drag, Angle.SIDE)
			_draw_head_side(float_y, 0.05)
			_draw_eye_trail(float_y)
		Angle.BACK:
			_draw_modular_cloak(float_y, cloak_amp, cloak_t, cloak_drag, Angle.BACK)
			_draw_modular_strap(float_y)
			_draw_modular_weapon(carry_back_pos + Vector2(0, float_y), deg_to_rad(carry_back_rot), Angle.BACK)
			_draw_head_back(float_y)

# ==================== 3. 冲刺 (DASH) ====================

func _draw_dash(angle: Angle, progress: float) -> void:
	var total_scale := Vector2(body_scale * width_scale, body_scale * height_scale)
	draw_set_transform(Vector2.ZERO, 0.0, total_scale)

	var dash_y := 4.0
	# 冲刺风掀：风阻随进度增强、衣摆短促掀摆，收势回弹由 dash_progress 收尾驱动
	var dash_drag := 5.0 + dash_progress * 2.5
	var dash_amp := 1.4 + dash_progress * 1.2
	var dash_t := _time * 9.0 + dash_progress * 4.0
	for i in [1, 2]:
		var lag := float(i) * 12.0
		draw_filled_ellipse(Vector2(-lag, dash_y + 24), 16.0 * width_scale, 3.8, Color(col_cloak_outer.r, col_cloak_outer.g, col_cloak_outer.b, 0.16 / float(i)))

	draw_filled_ellipse(Vector2(0, 32), 20.0 * width_scale, 3.8, Color(0.04, 0.06, 0.09, 0.55))
	draw_line(Vector2(-18, 31), Vector2(14, 31), col_eye_core, 1.0)

	match angle:
		Angle.FRONT:
			_draw_modular_weapon(carry_front_pos + Vector2(1.5, dash_y + 1.0), deg_to_rad(carry_front_rot + 12.0), Angle.FRONT)
			_draw_modular_cloak(dash_y, dash_amp, dash_t, dash_drag, Angle.FRONT)
			_draw_head_front(dash_y + 1, 0.3)
		Angle.SIDE:
			_draw_modular_weapon(Vector2(8, 7 + dash_y), deg_to_rad(65.0), Angle.SIDE)
			_draw_cloak_dash_side(dash_y, dash_progress)
			_draw_head_side(dash_y + 2, 0.45)
			draw_line(Vector2(8, -5 + dash_y), Vector2(-22, -5 + dash_y), col_eye_glow, 1.8)
		Angle.BACK:
			_draw_modular_cloak(dash_y, dash_amp, dash_t, dash_drag, Angle.BACK)
			_draw_modular_strap(dash_y)
			_draw_modular_weapon(carry_back_pos + Vector2(2.0, dash_y), deg_to_rad(carry_back_rot - 8.0), Angle.BACK)
			_draw_head_back(dash_y + 1)

# ==================== 4. 攻击挥剑 (ATTACK) ====================

func _draw_attack(angle: Angle, progress: float) -> void:
	var total_scale := Vector2(body_scale * width_scale, body_scale * height_scale)
	draw_set_transform(Vector2.ZERO, 0.0, total_scale)

	var float_y := sin(progress * PI) * -2.8
	_draw_ground_shadow(Vector2(0, 32), 19.0 * width_scale, 5.0, 0.55)

	match angle:
		Angle.FRONT:
			_draw_modular_weapon(carry_front_pos + Vector2(0, float_y), deg_to_rad(carry_front_rot), Angle.FRONT)
			_draw_modular_cloak(float_y, 2.2, _time * 5.2, 0.0, Angle.FRONT)
			_draw_head_front(float_y, 0.25)
			_draw_slash_crescent(Vector2(0, 12 + float_y), deg_to_rad(90.0), 38.0, progress)
		Angle.SIDE:
			_draw_modular_cloak(float_y, 2.4, _time * 5.2, 2.0, Angle.SIDE)
			_draw_head_side(float_y, 0.25)
			var slash_rot := lerpf(deg_to_rad(-40.0), deg_to_rad(50.0), progress)
			_draw_modular_weapon(Vector2(14, 3 + float_y), slash_rot, Angle.SIDE)
			_draw_slash_crescent(Vector2(18, 2 + float_y), deg_to_rad(15.0), 42.0, progress)
		Angle.BACK:
			_draw_modular_cloak(float_y, 2.2, _time * 5.2, 0.0, Angle.BACK)
			_draw_modular_strap(float_y)
			_draw_modular_weapon(carry_back_pos + Vector2(-2.0, float_y), deg_to_rad(carry_back_rot), Angle.BACK)
			_draw_head_back(float_y)
			_draw_slash_crescent(Vector2(0, -8 + float_y), deg_to_rad(-90.0), 38.0, progress)

# ==================== 5. 受击硬直 (HIT) ====================

func _draw_hit(angle: Angle, progress: float) -> void:
	var total_scale := Vector2(body_scale * width_scale, body_scale * height_scale)
	draw_set_transform(Vector2.ZERO, 0.0, total_scale)

	var hit_flash := 1.0 - progress
	_draw_ground_shadow(Vector2(0, 32), 16.0 * width_scale, 3.8, 0.4)

	match angle:
		Angle.FRONT:
			_draw_modular_weapon(carry_front_pos + Vector2(0.5, -1.0), deg_to_rad(carry_front_rot - 6.0), Angle.FRONT)
			_draw_modular_cloak(0.0, -1.2, _time * 7.0, 0.0, Angle.FRONT)
			_draw_head_front(0.0, 0.35)
		Angle.SIDE:
			_draw_modular_weapon(carry_side_pos + Vector2(0, 3.0), deg_to_rad(carry_side_rot), Angle.SIDE)
			_draw_modular_cloak(0.0, -1.2, _time * 7.0, -1.0, Angle.SIDE)
			_draw_head_side(0.0, 0.35)
		Angle.BACK:
			_draw_modular_cloak(0.0, -1.2, _time * 7.0, 0.0, Angle.BACK)
			_draw_modular_strap(0.0)
			_draw_modular_weapon(carry_back_pos + Vector2(-2.0, 4.0), deg_to_rad(carry_back_rot + 12.0), Angle.BACK)
			_draw_head_back(0.0)

	if hit_flash > 0.05 and _layer_on(Layer.FX):
		draw_soft_glow(Vector2(0, 0), 22.0, Color(1.0, 1.0, 1.0, hit_flash * 0.4), 2)
		_circle(Vector2(0, -10), 11.0, Color(1.0, 1.0, 1.0, hit_flash * 0.35))

# ==================== 辅助效果：地影与道韵灵气 ====================

func _draw_ground_shadow(pos: Vector2, rx: float, ry: float, alpha: float) -> void:
	if not _layer_on(Layer.SHADOW):
		return
	# 2026-10-18 阴影统一升级：外层弥散减弱、内层接触暗核加深，脚下更「实」
	draw_filled_ellipse(pos, rx, ry, Color(0.03, 0.04, 0.07, alpha * 0.6))
	draw_filled_ellipse(pos, rx * 0.66, ry * 0.66, Color(0.015, 0.02, 0.04, minf(alpha * 1.35, 0.88)))
	var edge_col := col_cloak_edge
	if cloak_shimmer_intensity > 0.05 and cloak_shimmer_color.a > 0.01:
		edge_col = col_cloak_edge.lerp(cloak_shimmer_color, clampf(cloak_shimmer_intensity, 0.0, 1.0))
	_arc(pos, rx + 1.8, 0, TAU, 28, Color(edge_col.r, edge_col.g, edge_col.b, alpha * 0.28), 1.0, true)

func _draw_immortal_motes(float_y: float) -> void:
	if not _layer_on(Layer.MOTES):
		return
	var eff_col := col_cloak_edge
	var eff_eye := col_eye_glow
	if cloak_shimmer_color.a > 0.01:
		eff_col = col_cloak_edge.lerp(cloak_shimmer_color, clampf(cloak_shimmer_intensity, 0.0, 1.0))
	if eye_override_color.a > 0.01:
		eff_eye = col_eye_glow.lerp(eye_override_color, clampf(eye_override_color.a, 0.0, 1.0))

	var speed_mul := 1.0 + motes_boost * 1.6
	var t1 := _time * 1.8 * speed_mul
	var mx1 := sin(t1) * (14.0 * width_scale)
	var my1 := cos(t1 * 1.2) * 8.0 + float_y + 8.0
	var alpha1 := (sin(_time * 2.2 * speed_mul) * 0.5 + 0.5) * (0.35 + motes_boost * 0.45)
	_circle(Vector2(mx1, my1), 1.0 + motes_boost * 0.6, Color(eff_col.r, eff_col.g, eff_col.b, alpha1))

	var t2 := _time * 2.3 * speed_mul + 2.1
	var mx2 := cos(t2) * (12.0 * width_scale)
	var my2 := sin(t2 * 1.4) * 7.0 + float_y - 2.0
	var alpha2 := (cos(_time * 2.5 * speed_mul) * 0.5 + 0.5) * (0.28 + motes_boost * 0.45)
	_circle(Vector2(mx2, my2), 0.9 + motes_boost * 0.6, Color(eff_eye.r, eff_eye.g, eff_eye.b, alpha2))

	# 皮肤系列：常驻粒子（青屑/血雾/雪晶/墨烟/金屑）复用本绘制位，原色零开销
	if not _fx.is_empty():
		SkinFxLibrary.draw_motes(self, float_y, _fx)

	# 技能爆发/法力激荡时，额外环绕 3 颗周天流光微粒子
	if motes_boost > 0.1:
		for i in range(3):
			var extra_t := _time * 3.6 + float(i) * (TAU / 3.0)
			var ex := sin(extra_t) * (18.0 * width_scale)
			var ey := cos(extra_t * 1.2) * 11.0 + float_y + 4.0
			var extra_a := (sin(extra_t * 2.4) * 0.35 + 0.65) * clampf(motes_boost, 0.0, 1.0) * 0.8
			_circle(Vector2(ex, ey), 1.2, Color(1.0, 1.0, 1.0, extra_a))
			var tail_dir := -Vector2(cos(extra_t) * 18.0, -sin(extra_t * 1.2) * 13.2).normalized()
			draw_line(Vector2(ex, ey), Vector2(ex, ey) + tail_dir * 5.0, Color(eff_col.r, eff_col.g, eff_col.b, extra_a * 0.65), 1.2)

func _draw_eye_trail(float_y: float) -> void:
	if not _layer_on(Layer.MOTES):
		return
	var eff_eye := col_eye_glow
	if eye_override_color.a > 0.01:
		eff_eye = col_eye_glow.lerp(eye_override_color, clampf(eye_override_color.a, 0.0, 1.0))
	var trail_len := 8.0 + (eye_glow_boost * 14.0)
	var eye_p := Vector2(2.5, -14.0 + float_y)
	var trail_alpha := 0.32 + eye_glow_boost * 0.35
	draw_line(eye_p, eye_p + Vector2(-trail_len, 1.0), Color(eff_eye.r, eff_eye.g, eff_eye.b, trail_alpha), 1.1 + eye_glow_boost * 0.8)
	if eye_glow_boost > 0.2:
		draw_line(eye_p, eye_p + Vector2(-trail_len * 0.55, 0.6), Color(1.0, 1.0, 1.0, trail_alpha * 0.9), 1.0)

# ==================== 头部与面具插槽绘制 ====================

func _draw_head_front(float_y: float, eye_pulse: float) -> void:
	if not _layer_on(Layer.HEAD):
		return
	var head_center := Vector2(0, -15 + float_y)
	_draw_modular_headwear(head_center, Angle.FRONT)
	_draw_modular_mask(head_center, Angle.FRONT)
	_draw_modular_eyes(head_center, Angle.FRONT, eye_pulse, _calm_blink())

func _draw_head_side(float_y: float, eye_pulse: float) -> void:
	if not _layer_on(Layer.HEAD):
		return
	var head_center := Vector2(1.2, -15 + float_y)
	_draw_modular_headwear(head_center, Angle.SIDE)
	_draw_modular_mask(head_center, Angle.SIDE)
	_draw_modular_eyes(head_center, Angle.SIDE, eye_pulse, _calm_blink())

func _draw_head_back(float_y: float) -> void:
	if not _layer_on(Layer.HEAD):
		return
	var head_center := Vector2(0, -15 + float_y)
	_circle(head_center, 9.5 * head_scale, col_bone)
	_arc(head_center, 9.5 * head_scale, 0, TAU, 24, col_bone_shadow, 1.2, true)
	_arc(head_center, 7.5 * head_scale, PI * 0.2, PI * 0.8, 16, Color(col_bone_shadow.r, col_bone_shadow.g, col_bone_shadow.b, 0.35), 1.0)
	_draw_modular_headwear(head_center, Angle.BACK)

## 插槽 1：面壳轮廓绘制
func _draw_modular_mask(head_center: Vector2, angle: Angle) -> void:
	var hs := head_scale
	if angle == Angle.FRONT:
		var mask_pts: PackedVector2Array = []
		match mask_style:
			"square_rock":
				mask_pts = [
					head_center + Vector2(-11 * hs, -6 * hs),
					head_center + Vector2(-11 * hs, 5 * hs),
					head_center + Vector2(-5 * hs, 10 * hs),
					head_center + Vector2(5 * hs, 10 * hs),
					head_center + Vector2(11 * hs, 5 * hs),
					head_center + Vector2(11 * hs, -6 * hs),
					head_center + Vector2(0, -9 * hs)
				]
			"round_petite":
				mask_pts = [
					head_center + Vector2(-9 * hs, -4 * hs),
					head_center + Vector2(-9 * hs, 4 * hs),
					head_center + Vector2(-4 * hs, 9 * hs),
					head_center + Vector2(4 * hs, 9 * hs),
					head_center + Vector2(9 * hs, 4 * hs),
					head_center + Vector2(9 * hs, -4 * hs),
					head_center + Vector2(0, -8 * hs)
				]
			"sharp_fox":
				mask_pts = [
					head_center + Vector2(-9 * hs, -5 * hs),
					head_center + Vector2(-7 * hs, 3 * hs),
					head_center + Vector2(0, 11 * hs),
					head_center + Vector2(7 * hs, 3 * hs),
					head_center + Vector2(9 * hs, -5 * hs),
					head_center + Vector2(0, -10 * hs)
				]
			"stout_brute":
				mask_pts = [
					head_center + Vector2(-12 * hs, -5 * hs),
					head_center + Vector2(-12 * hs, 6 * hs),
					head_center + Vector2(-4 * hs, 11 * hs),
					head_center + Vector2(4 * hs, 11 * hs),
					head_center + Vector2(12 * hs, 6 * hs),
					head_center + Vector2(12 * hs, -5 * hs),
					head_center + Vector2(0, -8 * hs)
				]
			"oval_chin", _:
				mask_pts = [
					head_center + Vector2(-9.5 * hs, -6 * hs),
					head_center + Vector2(-9.0 * hs, 4 * hs),
					head_center + Vector2(0, 10 * hs),
					head_center + Vector2(9.0 * hs, 4 * hs),
					head_center + Vector2(9.5 * hs, -6 * hs),
					head_center + Vector2(0, -9 * hs)
				]

		draw_colored_polygon(mask_pts, col_bone)
		var shadow_cut: PackedVector2Array = [
			mask_pts[2], mask_pts[3], mask_pts[4],
			head_center + Vector2(4 * hs, 2 * hs),
			head_center + Vector2(0, 5 * hs)
		]
		draw_colored_polygon(shadow_cut, Color(col_bone_shadow.r, col_bone_shadow.g, col_bone_shadow.b, 0.35))
		draw_polyline(mask_pts, col_bone_shadow, 1.2, true)
		_draw_forehead_sigil(head_center, hs, Angle.FRONT)

	else:
		var side_mask: PackedVector2Array = []
		match mask_style:
			"square_rock":
				side_mask = [
					head_center + Vector2(-6 * hs, -8 * hs),
					head_center + Vector2(6 * hs, -5 * hs),
					head_center + Vector2(8 * hs, 4 * hs),
					head_center + Vector2(3 * hs, 10 * hs),
					head_center + Vector2(-4 * hs, 9 * hs),
					head_center + Vector2(-7 * hs, 0)
				]
			"round_petite":
				side_mask = [
					head_center + Vector2(-5 * hs, -7 * hs),
					head_center + Vector2(5 * hs, -4 * hs),
					head_center + Vector2(7 * hs, 3 * hs),
					head_center + Vector2(2 * hs, 8.5 * hs),
					head_center + Vector2(-4 * hs, 7 * hs),
					head_center + Vector2(-6 * hs, 0)
				]
			"sharp_fox":
				side_mask = [
					head_center + Vector2(-6 * hs, -8 * hs),
					head_center + Vector2(6 * hs, -4 * hs),
					head_center + Vector2(8.5 * hs, 2 * hs),
					head_center + Vector2(2 * hs, 10.5 * hs),
					head_center + Vector2(-4 * hs, 7 * hs),
					head_center + Vector2(-7 * hs, 0)
				]
			"stout_brute":
				side_mask = [
					head_center + Vector2(-7 * hs, -7 * hs),
					head_center + Vector2(7 * hs, -4 * hs),
					head_center + Vector2(9 * hs, 5 * hs),
					head_center + Vector2(3 * hs, 11 * hs),
					head_center + Vector2(-5 * hs, 9 * hs),
					head_center + Vector2(-8 * hs, 0)
				]
			"oval_chin", _:
				side_mask = [
					head_center + Vector2(-5.5 * hs, -8 * hs),
					head_center + Vector2(5.5 * hs, -5 * hs),
					head_center + Vector2(7.5 * hs, 3 * hs),
					head_center + Vector2(1.5 * hs, 9.5 * hs),
					head_center + Vector2(-4.5 * hs, 8 * hs),
					head_center + Vector2(-6.5 * hs, 0)
				]

		draw_colored_polygon(side_mask, col_bone)
		var cheek_pts: PackedVector2Array = [
			head_center + Vector2(-2 * hs, 1 * hs),
			side_mask[2], side_mask[3], side_mask[4]
		]
		draw_colored_polygon(cheek_pts, Color(col_bone_shadow.r, col_bone_shadow.g, col_bone_shadow.b, 0.4))
		draw_polyline(side_mask, col_bone_shadow, 1.2, true)
		_draw_forehead_sigil(head_center, hs, Angle.SIDE)

## 额间道统纹样微雕
func _draw_forehead_sigil(head_center: Vector2, hs: float, angle: Angle) -> void:
	if horns_style == "bamboo_hat":
		if angle == Angle.FRONT:
			draw_line(head_center + Vector2(-2.5 * hs, -5 * hs), head_center + Vector2(3.5 * hs, 4 * hs), Color(0.45, 0.48, 0.55), 1.2)
		else:
			draw_line(head_center + Vector2(1.0 * hs, -3 * hs), head_center + Vector2(4.5 * hs, 3 * hs), Color(0.45, 0.48, 0.55), 1.1)
		return

	if horns_style == "talisman":
		return

	match mask_style:
		"square_rock":
			if angle == Angle.FRONT:
				draw_line(head_center + Vector2(-2.5 * hs, -4.5 * hs), head_center + Vector2(2.5 * hs, -4.5 * hs), col_gold, 1.2)
				draw_line(head_center + Vector2(-1.5 * hs, -2.5 * hs), head_center + Vector2(1.5 * hs, -2.5 * hs), col_gold, 1.2)
			else:
				draw_line(head_center + Vector2(1.0 * hs, -4.5 * hs), head_center + Vector2(3.5 * hs, -4.5 * hs), col_gold, 1.1)

		"round_petite":
			var sigil_col := col_tassel_red if horns_style == "dao_bun" or horns_style == "twin_buns" else col_gold
			if angle == Angle.FRONT:
				_circle(head_center + Vector2(0, -4.0 * hs), 1.1 * hs, sigil_col)
			else:
				_circle(head_center + Vector2(2.8 * hs, -3.5 * hs), 1.0 * hs, sigil_col)

		"sharp_fox":
			if angle == Angle.FRONT:
				draw_line(head_center + Vector2(0, -6 * hs), head_center + Vector2(0, -2 * hs), col_eye_glow, 1.1)
				draw_line(head_center + Vector2(-2 * hs, -5 * hs), head_center + Vector2(2 * hs, -5 * hs), col_eye_glow, 0.9)
			else:
				draw_line(head_center + Vector2(2.5 * hs, -5 * hs), head_center + Vector2(2.5 * hs, -2 * hs), col_eye_glow, 1.0)

		"stout_brute":
			var brute_col := col_gold if horns_style == "barbarian_horns" else col_tassel_red
			if horns_style == "barbarian_horns":
				# 蛮兵专属：额心三道炽金战气裂痕，展现陷阵凶蛮
				if angle == Angle.FRONT:
					draw_line(head_center + Vector2(-3.0 * hs, -6.0 * hs), head_center + Vector2(-1.5 * hs, -2.0 * hs), brute_col, 1.3)
					draw_line(head_center + Vector2(0, -6.5 * hs), head_center + Vector2(0, -1.8 * hs), brute_col, 1.4)
					draw_line(head_center + Vector2(3.0 * hs, -6.0 * hs), head_center + Vector2(1.5 * hs, -2.0 * hs), brute_col, 1.3)
				else:
					draw_line(head_center + Vector2(1.5 * hs, -5.5 * hs), head_center + Vector2(3.5 * hs, -2.0 * hs), brute_col, 1.3)
					draw_line(head_center + Vector2(3.2 * hs, -5.0 * hs), head_center + Vector2(5.2 * hs, -1.5 * hs), brute_col, 1.2)
			else:
				if angle == Angle.FRONT:
					draw_line(head_center + Vector2(-2.5 * hs, -6 * hs), head_center + Vector2(2.5 * hs, -2 * hs), brute_col, 1.2)
					draw_line(head_center + Vector2(2.5 * hs, -6 * hs), head_center + Vector2(-2.5 * hs, -2 * hs), brute_col, 1.2)
				else:
					draw_line(head_center + Vector2(1.0 * hs, -5 * hs), head_center + Vector2(4.0 * hs, -2 * hs), brute_col, 1.1)

		"oval_chin", _:
			if angle == Angle.FRONT:
				draw_line(head_center + Vector2(0, -6.5 * hs), head_center + Vector2(0, -2.5 * hs), col_eye_glow, 1.2)
				draw_line(head_center + Vector2(-1.5 * hs, -5.0 * hs), head_center + Vector2(1.5 * hs, -5.0 * hs), col_eye_glow, 0.9)
				_circle(head_center + Vector2(0, -2.5 * hs), 0.7 * hs, col_eye_core)
			else:
				draw_line(head_center + Vector2(2.6 * hs, -5.5 * hs), head_center + Vector2(2.6 * hs, -2.5 * hs), col_eye_glow, 1.1)

	# 额间道印通玄激活动态光晕
	if sigil_boost > 0.05:
		var sigil_pos := head_center + (Vector2(0, -4.2 * hs) if angle == Angle.FRONT else Vector2(2.4 * hs, -3.8 * hs))
		var sigil_glow_col := cloak_shimmer_color if cloak_shimmer_color.a > 0.01 else col_gold
		draw_soft_glow(sigil_pos, 4.2 * hs * (1.0 + sigil_boost * 0.5), Color(sigil_glow_col.r, sigil_glow_col.g, sigil_glow_col.b, 0.45 * sigil_boost), 2)
		_circle(sigil_pos, 1.0 * hs, Color(1, 1, 1, 0.8 * sigil_boost))

## 插槽 2：头部首服与角冠绘制
func _draw_modular_headwear(head_center: Vector2, angle: Angle) -> void:
	var hs := head_scale
	match horns_style:
		"barbarian_horns":
			# 蛮兵专属：蛮荒重甲战角（根部裹粗犷铜金骨环，双角厚重横展微前倾，粗砺战痕）
			var l_bhorn := [
				head_center + Vector2(-5.5 * hs, -4.5 * hs),
				head_center + Vector2(-14.0 * hs, -10.5 * hs),
				head_center + Vector2(-20.0 * hs, -21.0 * hs),
				head_center + Vector2(-13.0 * hs, -18.5 * hs),
				head_center + Vector2(-4.0 * hs, -7.5 * hs)
			]
			var r_bhorn := [
				head_center + Vector2(4.0 * hs, -7.5 * hs),
				head_center + Vector2(13.0 * hs, -18.5 * hs),
				head_center + Vector2(20.0 * hs, -21.0 * hs),
				head_center + Vector2(14.0 * hs, -10.5 * hs),
				head_center + Vector2(5.5 * hs, -4.5 * hs)
			]
			if angle == Angle.FRONT:
				draw_colored_polygon(l_bhorn, col_bone)
				draw_colored_polygon(r_bhorn, col_bone)
				# 角身暗面阴影
				draw_colored_polygon(PackedVector2Array([
					head_center + Vector2(-5.5 * hs, -4.5 * hs),
					head_center + Vector2(-14.0 * hs, -10.5 * hs),
					head_center + Vector2(-20.0 * hs, -21.0 * hs),
					head_center + Vector2(-15.0 * hs, -14.0 * hs)
				]), col_bone_shadow)
				draw_colored_polygon(PackedVector2Array([
					head_center + Vector2(5.5 * hs, -4.5 * hs),
					head_center + Vector2(14.0 * hs, -10.5 * hs),
					head_center + Vector2(20.0 * hs, -21.0 * hs),
					head_center + Vector2(15.0 * hs, -14.0 * hs)
				]), col_bone_shadow)
				draw_polyline(l_bhorn, col_bone_shadow, 1.3, true)
				draw_polyline(r_bhorn, col_bone_shadow, 1.3, true)
				# 根部粗狂铜金护箍环（加粗明显，形成强辨识度）
				draw_line(head_center + Vector2(-4.5 * hs, -6.0 * hs), head_center + Vector2(-9.5 * hs, -9.5 * hs), col_gold, 2.4)
				draw_line(head_center + Vector2(4.5 * hs, -6.0 * hs), head_center + Vector2(9.5 * hs, -9.5 * hs), col_gold, 2.4)
				# 角尖战纹金芒
				draw_line(head_center + Vector2(-12.0 * hs, -15.0 * hs), head_center + Vector2(-18.5 * hs, -20.0 * hs), Color(col_gold.r, col_gold.g, col_gold.b, 0.75), 1.2)
				draw_line(head_center + Vector2(12.0 * hs, -15.0 * hs), head_center + Vector2(18.5 * hs, -20.0 * hs), Color(col_gold.r, col_gold.g, col_gold.b, 0.75), 1.2)
			elif angle == Angle.SIDE:
				var side_bhorn := [
					head_center + Vector2(-2.0 * hs, -5.5 * hs),
					head_center + Vector2(-11.0 * hs, -13.5 * hs),
					head_center + Vector2(-16.0 * hs, -23.0 * hs),
					head_center + Vector2(-8.0 * hs, -18.0 * hs),
					head_center + Vector2(2.5 * hs, -7.5 * hs)
				]
				draw_colored_polygon(side_bhorn, col_bone)
				draw_polyline(side_bhorn, col_bone_shadow, 1.3, true)
				draw_line(head_center + Vector2(-1.5 * hs, -6.5 * hs), head_center + Vector2(-6.5 * hs, -11.0 * hs), col_gold, 2.4)
				draw_line(head_center + Vector2(-8.0 * hs, -14.0 * hs), head_center + Vector2(-14.5 * hs, -21.0 * hs), Color(col_gold.r, col_gold.g, col_gold.b, 0.75), 1.2)
			else:
				draw_colored_polygon(l_bhorn, col_bone_shadow)
				draw_colored_polygon(r_bhorn, col_bone_shadow)
				draw_polyline(l_bhorn, col_bone, 1.0, true)
				draw_polyline(r_bhorn, col_bone, 1.0, true)

		"bull_horns":
			var l_horn := [
				head_center + Vector2(-6 * hs, -5 * hs),
				head_center + Vector2(-15 * hs, -12 * hs),
				head_center + Vector2(-18 * hs, -24 * hs),
				head_center + Vector2(-11 * hs, -17 * hs),
				head_center + Vector2(-4 * hs, -7 * hs)
			]
			var r_horn := [
				head_center + Vector2(4 * hs, -7 * hs),
				head_center + Vector2(11 * hs, -17 * hs),
				head_center + Vector2(18 * hs, -24 * hs),
				head_center + Vector2(15 * hs, -12 * hs),
				head_center + Vector2(6 * hs, -5 * hs)
			]
			if angle == Angle.FRONT:
				draw_colored_polygon(l_horn, col_bone)
				draw_colored_polygon(r_horn, col_bone)
				draw_polyline(l_horn, col_bone_shadow, 1.2, true)
				draw_polyline(r_horn, col_bone_shadow, 1.2, true)
				draw_line(head_center + Vector2(-10 * hs, -10 * hs), head_center + Vector2(-13 * hs, -14 * hs), col_bone_shadow, 1.2)
				draw_line(head_center + Vector2(10 * hs, -10 * hs), head_center + Vector2(13 * hs, -14 * hs), col_bone_shadow, 1.2)
			elif angle == Angle.SIDE:
				var side_horn := [
					head_center + Vector2(-2 * hs, -6 * hs),
					head_center + Vector2(-12 * hs, -16 * hs),
					head_center + Vector2(-14 * hs, -26 * hs),
					head_center + Vector2(-7 * hs, -17 * hs),
					head_center + Vector2(2 * hs, -8 * hs)
				]
				draw_colored_polygon(side_horn, col_bone)
				draw_polyline(side_horn, col_bone_shadow, 1.2, true)
				draw_line(head_center + Vector2(-8 * hs, -12 * hs), head_center + Vector2(-10 * hs, -16 * hs), col_bone_shadow, 1.1)
			else:
				draw_colored_polygon(l_horn, col_bone_shadow)
				draw_colored_polygon(r_horn, col_bone_shadow)
				draw_polyline(l_horn, col_bone, 1.0, true)
				draw_polyline(r_horn, col_bone, 1.0, true)

		"dao_bun":
			var bun_c: Vector2 = head_center + Vector2(-1.5 * hs, -12 * hs) if angle == Angle.SIDE else head_center + Vector2(0, -12 * hs)
			_circle(bun_c, 5.2 * hs, col_bone)
			_circle(bun_c, 3.0 * hs, col_bone_shadow)
			_arc(bun_c, 4.0 * hs, -0.4, 2.8, 12, col_bone_shadow, 1.1)
			if angle == Angle.SIDE:
				draw_line(bun_c + Vector2(-6 * hs, -1 * hs), bun_c + Vector2(7 * hs, 1 * hs), col_weapon_main, 1.8)
				_circle(bun_c + Vector2(7 * hs, 1 * hs), 1.6, col_jade)
				# 簪尾红绳穗：软部件随移动风压/步频二级摆动
				draw_line(bun_c + Vector2(-5 * hs, -1 * hs), bun_c + Vector2(-7 * hs, 3 * hs) + _head_soft_sway(0.6), col_tassel_red, 1.2)
			else:
				draw_line(bun_c + Vector2(-8 * hs, 0), bun_c + Vector2(8 * hs, 0), col_weapon_main, 1.8)
				_circle(bun_c + Vector2(8 * hs, 0), 1.6, col_jade)
				draw_line(bun_c + Vector2(-7 * hs, 0), bun_c + Vector2(-9 * hs, 4 * hs) + _head_soft_sway(0.6), col_tassel_red, 1.2)

		"twin_buns":
			# 童子双丫髻：左右对称小髻 + 髻根红头绳，无横簪（驯兽师专属）
			var bun_l: Vector2
			var bun_r: Vector2
			if angle == Angle.SIDE:
				bun_l = head_center + Vector2(-3.5 * hs, -11 * hs)   # 后髻（衬垫）
				bun_r = head_center + Vector2(2.5 * hs, -11.5 * hs)  # 前髻
				_circle(bun_l, 2.8 * hs, col_bone_shadow)
				_circle(bun_r, 3.2 * hs, col_bone)
				_arc(bun_r, 2.4 * hs, -0.5, 2.6, 10, col_bone_shadow, 1.0)
				draw_line(bun_r + Vector2(-2.2 * hs, 1.8 * hs), bun_r + Vector2(2.2 * hs, 1.8 * hs), col_tassel_red, 1.2)
				# 髻根垂下的红绳穗：软部件随移动风压/步频二级摆动
				draw_line(bun_r + Vector2(1.6 * hs, 2.2 * hs), bun_r + Vector2(2.4 * hs, 5.0 * hs) + _head_soft_sway(1.4), col_tassel_red, 1.1)
			else:
				bun_l = head_center + Vector2(-6.5 * hs, -10 * hs)
				bun_r = head_center + Vector2(6.5 * hs, -10 * hs)
				_circle(bun_l, 3.4 * hs, col_bone)
				_circle(bun_r, 3.4 * hs, col_bone)
				_arc(bun_l, 2.6 * hs, -0.5, 2.6, 10, col_bone_shadow, 1.0)
				_arc(bun_r, 2.6 * hs, -0.5, 2.6, 10, col_bone_shadow, 1.0)
				draw_line(bun_l + Vector2(-2.4 * hs, 2.0 * hs), bun_l + Vector2(2.4 * hs, 2.0 * hs), col_tassel_red, 1.2)
				draw_line(bun_r + Vector2(-2.4 * hs, 2.0 * hs), bun_r + Vector2(2.4 * hs, 2.0 * hs), col_tassel_red, 1.2)
				# 双髻各垂一条红绳穗，lag 错相不同拍
				draw_line(bun_l + Vector2(-1.6 * hs, 2.4 * hs), bun_l + Vector2(-2.4 * hs, 5.4 * hs) + _head_soft_sway(0.2), col_tassel_red, 1.1)
				draw_line(bun_r + Vector2(1.6 * hs, 2.4 * hs), bun_r + Vector2(2.4 * hs, 5.4 * hs) + _head_soft_sway(1.4), col_tassel_red, 1.1)

		"bamboo_hat":
			var hat_c := head_center + Vector2(0, -9 * hs)
			if angle == Angle.SIDE:
				hat_c = head_center + Vector2(1 * hs, -9 * hs)
				var hat_pts: PackedVector2Array = [
					hat_c + Vector2(-15 * hs, 2 * hs),
					hat_c + Vector2(-1 * hs, -11 * hs),
					hat_c + Vector2(16 * hs, 4 * hs),
					hat_c + Vector2(2 * hs, -1 * hs)
				]
				draw_colored_polygon(hat_pts, Color(0.38, 0.32, 0.22))
				draw_polyline(hat_pts, Color(0.68, 0.58, 0.40), 1.2, true)
				draw_line(hat_c + Vector2(-7 * hs, -4 * hs), hat_c + Vector2(8 * hs, 1 * hs), Color(0.28, 0.22, 0.15), 1.2)
				draw_line(hat_c + Vector2(0, 0), hat_c + Vector2(-1 * hs, 8 * hs), Color(0.12, 0.10, 0.08), 1.2)
			elif angle == Angle.BACK:
				var hat_pts: PackedVector2Array = [
					hat_c + Vector2(-17 * hs, 2 * hs),
					hat_c + Vector2(0, -11 * hs),
					hat_c + Vector2(17 * hs, 2 * hs),
					hat_c + Vector2(0, 1 * hs)
				]
				draw_colored_polygon(hat_pts, Color(0.32, 0.26, 0.17))
				draw_polyline(hat_pts, Color(0.62, 0.52, 0.35), 1.2, true)
				_arc(hat_c + Vector2(0, -3 * hs), 8.0 * hs, 0, PI, 16, Color(0.24, 0.19, 0.12), 1.2)
			else:
				var hat_pts: PackedVector2Array = [
					hat_c + Vector2(-17 * hs, 3 * hs),
					hat_c + Vector2(0, -11 * hs),
					hat_c + Vector2(17 * hs, 3 * hs),
					hat_c + Vector2(0, -2 * hs)
				]
				draw_colored_polygon(hat_pts, Color(0.38, 0.32, 0.22))
				draw_polyline(hat_pts, Color(0.68, 0.58, 0.40), 1.2, true)
				_arc(hat_c + Vector2(0, -3 * hs), 8.0 * hs, 0, PI, 16, Color(0.28, 0.22, 0.15), 1.2)
				draw_line(hat_c + Vector2(0, -11 * hs), hat_c + Vector2(0, -2 * hs), Color(0.24, 0.20, 0.14), 1.4)
				_circle(hat_c + Vector2(0, 0), 1.2, Color(0.12, 0.10, 0.08))

		"talisman":
			if angle == Angle.FRONT:
				var t_pos := head_center + Vector2(0, -10 * hs)
				# 符纸是软部件：下摆随移动风压/步频轻摆（0.75x 收敛幅度，贴额符箓不狂舞）
				var t_sw := _head_soft_sway(0.9) * 0.75
				var t_pts: PackedVector2Array = [
					t_pos + Vector2(-3.2 * hs, 0),
					t_pos + Vector2(3.2 * hs, 0),
					t_pos + Vector2(3.0 * hs, 13 * hs) + t_sw,
					t_pos + Vector2(0, 11.5 * hs) + t_sw,
					t_pos + Vector2(-3.0 * hs, 13 * hs) + t_sw
				]
				draw_colored_polygon(t_pts, Color(0.92, 0.82, 0.28))
				draw_line(t_pos + Vector2(0, 2 * hs), t_pos + Vector2(0, 10 * hs) + t_sw * 0.8, Color(0.85, 0.20, 0.15), 1.3)
				draw_line(t_pos + Vector2(-1.5 * hs, 4 * hs), t_pos + Vector2(1.5 * hs, 4 * hs), Color(0.85, 0.20, 0.15), 1.1)
				draw_line(t_pos + Vector2(-1.2 * hs, 7 * hs) + t_sw * 0.5, t_pos + Vector2(1.2 * hs, 7 * hs) + t_sw * 0.5, Color(0.85, 0.20, 0.15), 1.1)
			elif angle == Angle.SIDE:
				var t_pos := head_center + Vector2(5.5 * hs, -8 * hs)
				var t_sw := _head_soft_sway(0.9) * 0.75
				var t_pts: PackedVector2Array = [
					t_pos,
					t_pos + Vector2(1.5 * hs, 0),
					t_pos + Vector2(0.5 * hs, 12 * hs) + t_sw,
					t_pos + Vector2(-1.0 * hs, 12 * hs) + t_sw
				]
				draw_colored_polygon(t_pts, Color(0.92, 0.82, 0.28))
				draw_line(t_pos + Vector2(0.8 * hs, 2 * hs), t_pos + Vector2(0, 10 * hs) + t_sw * 0.8, Color(0.85, 0.20, 0.15), 1.2)
			else:
				draw_line(head_center + Vector2(-5 * hs, -8 * hs), head_center + Vector2(5 * hs, -8 * hs), Color(0.85, 0.20, 0.15), 1.3)
				_circle(head_center + Vector2(0, -8 * hs), 1.4, Color(0.85, 0.20, 0.15))

		"gold_crown":
			var crown_c := head_center + Vector2(0, -11 * hs)
			if angle == Angle.SIDE:
				crown_c = head_center + Vector2(1 * hs, -11 * hs)
				_circle(crown_c + Vector2(-3 * hs, 0), 3.0 * hs, col_gold_shadow)
				_circle(crown_c + Vector2(2 * hs, -2 * hs), 3.8 * hs, col_gold)
				_circle(crown_c + Vector2(2 * hs, -2 * hs), 1.5 * hs, col_void)
				draw_rect(Rect2(crown_c + Vector2(1.2 * hs, -2.8 * hs), Vector2(1.6 * hs, 1.6 * hs)), col_gold)
			else:
				_circle(crown_c + Vector2(-6 * hs, 0), 3.2 * hs, col_gold_shadow)
				_circle(crown_c + Vector2(6 * hs, 0), 3.2 * hs, col_gold_shadow)
				_circle(crown_c + Vector2(0, -3 * hs), 4.4 * hs, col_gold)
				_circle(crown_c + Vector2(0, -3 * hs), 1.7 * hs, col_void)
				draw_rect(Rect2(crown_c + Vector2(-0.8 * hs, -3.8 * hs), Vector2(1.6 * hs, 1.6 * hs)), col_gold)

		"butterfly_horns_petite":
			# 灵蝶使专属：轻灵小蝶羽仙角（剑士骨角 0.68x 简约微型版，天青灵蓝流光）
			if angle == Angle.SIDE:
				var side_horn: PackedVector2Array = [
					head_center + Vector2(-2.0 * hs, -5.0 * hs),
					head_center + Vector2(-7.5 * hs, -13.0 * hs),
					head_center + Vector2(-9.5 * hs, -20.0 * hs),
					head_center + Vector2(-3.5 * hs, -15.0 * hs),
					head_center + Vector2(1.5 * hs, -6.5 * hs)
				]
				draw_colored_polygon(side_horn, col_bone)
				draw_colored_polygon(PackedVector2Array([
					head_center + Vector2(-2.0 * hs, -5.0 * hs),
					head_center + Vector2(-7.5 * hs, -13.0 * hs),
					head_center + Vector2(-9.5 * hs, -20.0 * hs),
					head_center + Vector2(-5.0 * hs, -13.0 * hs)
				]), col_bone_shadow)
				draw_line(head_center + Vector2(-1.5 * hs, -6.5 * hs), head_center + Vector2(-8.0 * hs, -18.0 * hs), Color(col_eye_glow.r, col_eye_glow.g, col_eye_glow.b, 0.75), 1.0)
			else:
				var l_horn: PackedVector2Array = [
					head_center + Vector2(-4.2 * hs, -3.5 * hs),
					head_center + Vector2(-9.8 * hs, -13.0 * hs),
					head_center + Vector2(-8.4 * hs, -20.0 * hs),
					head_center + Vector2(-4.2 * hs, -14.0 * hs),
					head_center + Vector2(-2.0 * hs, -6.0 * hs)
				]
				var r_horn: PackedVector2Array = [
					head_center + Vector2(2.0 * hs, -6.0 * hs),
					head_center + Vector2(4.2 * hs, -14.0 * hs),
					head_center + Vector2(8.4 * hs, -20.0 * hs),
					head_center + Vector2(9.8 * hs, -13.0 * hs),
					head_center + Vector2(4.2 * hs, -3.5 * hs)
				]
				draw_colored_polygon(l_horn, col_bone)
				draw_colored_polygon(r_horn, col_bone)
				draw_colored_polygon(PackedVector2Array([
					head_center + Vector2(-4.2 * hs, -3.5 * hs),
					head_center + Vector2(-9.8 * hs, -13.0 * hs),
					head_center + Vector2(-8.4 * hs, -20.0 * hs),
					head_center + Vector2(-6.3 * hs, -13.0 * hs)
				]), col_bone_shadow)
				draw_colored_polygon(PackedVector2Array([
					head_center + Vector2(2.0 * hs, -6.0 * hs),
					head_center + Vector2(4.2 * hs, -14.0 * hs),
					head_center + Vector2(8.4 * hs, -20.0 * hs),
					head_center + Vector2(6.3 * hs, -13.0 * hs)
				]), col_bone_shadow)
				draw_line(head_center + Vector2(-2.8 * hs, -5.5 * hs), head_center + Vector2(-7.0 * hs, -17.0 * hs), Color(col_eye_glow.r, col_eye_glow.g, col_eye_glow.b, 0.7), 1.0)
				draw_line(head_center + Vector2(2.8 * hs, -5.5 * hs), head_center + Vector2(7.0 * hs, -17.0 * hs), Color(col_eye_glow.r, col_eye_glow.g, col_eye_glow.b, 0.7), 1.0)

		"merchant_horns":
			# 商人专属：平展从容玉骨角（角底束简金环，温润平缓横展）
			if angle == Angle.SIDE:
				var m_horn: PackedVector2Array = [
					head_center + Vector2(-2.5 * hs, -5.5 * hs),
					head_center + Vector2(-8.5 * hs, -14.0 * hs),
					head_center + Vector2(-12.5 * hs, -21.0 * hs),
					head_center + Vector2(-6.0 * hs, -17.0 * hs),
					head_center + Vector2(1.5 * hs, -7.0 * hs)
				]
				draw_colored_polygon(m_horn, col_bone)
				draw_colored_polygon(PackedVector2Array([
					head_center + Vector2(-2.5 * hs, -5.5 * hs),
					head_center + Vector2(-8.5 * hs, -14.0 * hs),
					head_center + Vector2(-12.5 * hs, -21.0 * hs),
					head_center + Vector2(-7.5 * hs, -15.0 * hs)
				]), col_bone_shadow)
				# 根部简约金环带
				draw_line(head_center + Vector2(-1.5 * hs, -6.0 * hs), head_center + Vector2(-4.5 * hs, -10.0 * hs), col_gold, 1.8)
				draw_line(head_center + Vector2(-2.0 * hs, -7.0 * hs), head_center + Vector2(-10.5 * hs, -19.0 * hs), Color(col_gold.r, col_gold.g, col_gold.b, 0.65), 1.0)
			else:
				var l_mhorn: PackedVector2Array = [
					head_center + Vector2(-5.0 * hs, -4.0 * hs),
					head_center + Vector2(-13.0 * hs, -13.5 * hs),
					head_center + Vector2(-13.5 * hs, -21.0 * hs),
					head_center + Vector2(-7.0 * hs, -15.5 * hs),
					head_center + Vector2(-2.5 * hs, -6.5 * hs)
				]
				var r_mhorn: PackedVector2Array = [
					head_center + Vector2(2.5 * hs, -6.5 * hs),
					head_center + Vector2(7.0 * hs, -15.5 * hs),
					head_center + Vector2(13.5 * hs, -21.0 * hs),
					head_center + Vector2(13.0 * hs, -13.5 * hs),
					head_center + Vector2(5.0 * hs, -4.0 * hs)
				]
				draw_colored_polygon(l_mhorn, col_bone)
				draw_colored_polygon(r_mhorn, col_bone)
				draw_colored_polygon(PackedVector2Array([
					head_center + Vector2(-5.0 * hs, -4.0 * hs),
					head_center + Vector2(-13.0 * hs, -13.5 * hs),
					head_center + Vector2(-13.5 * hs, -21.0 * hs),
					head_center + Vector2(-9.5 * hs, -14.5 * hs)
				]), col_bone_shadow)
				draw_colored_polygon(PackedVector2Array([
					head_center + Vector2(2.5 * hs, -6.5 * hs),
					head_center + Vector2(7.0 * hs, -15.5 * hs),
					head_center + Vector2(13.5 * hs, -21.0 * hs),
					head_center + Vector2(9.5 * hs, -14.5 * hs)
				]), col_bone_shadow)
				# 根部简约金环束角
				draw_line(head_center + Vector2(-3.5 * hs, -5.5 * hs), head_center + Vector2(-7.0 * hs, -9.5 * hs), col_gold, 1.8)
				draw_line(head_center + Vector2(3.5 * hs, -5.5 * hs), head_center + Vector2(7.0 * hs, -9.5 * hs), col_gold, 1.8)
				draw_line(head_center + Vector2(-4.0 * hs, -7.0 * hs), head_center + Vector2(-11.5 * hs, -18.5 * hs), Color(col_gold.r, col_gold.g, col_gold.b, 0.65), 1.0)
				draw_line(head_center + Vector2(4.0 * hs, -7.0 * hs), head_center + Vector2(11.5 * hs, -18.5 * hs), Color(col_gold.r, col_gold.g, col_gold.b, 0.65), 1.0)

		"collector_horns":
			# 收藏家专属：重宝双叠骨羽角（主挺拔 + 外侧微小副羽剪影，紫金灵光中脊）
			if angle == Angle.SIDE:
				var main_h: PackedVector2Array = [
					head_center + Vector2(-2.5 * hs, -6.0 * hs),
					head_center + Vector2(-9.0 * hs, -16.0 * hs),
					head_center + Vector2(-11.5 * hs, -24.0 * hs),
					head_center + Vector2(-4.5 * hs, -18.0 * hs),
					head_center + Vector2(1.5 * hs, -7.5 * hs)
				]
				var sub_h: PackedVector2Array = [
					head_center + Vector2(-5.0 * hs, -8.0 * hs),
					head_center + Vector2(-11.0 * hs, -14.0 * hs),
					head_center + Vector2(-7.5 * hs, -11.0 * hs)
				]
				draw_colored_polygon(sub_h, col_bone_shadow)
				draw_colored_polygon(main_h, col_bone)
				draw_colored_polygon(PackedVector2Array([
					head_center + Vector2(-2.5 * hs, -6.0 * hs),
					head_center + Vector2(-9.0 * hs, -16.0 * hs),
					head_center + Vector2(-11.5 * hs, -24.0 * hs),
					head_center + Vector2(-6.5 * hs, -16.5 * hs)
				]), col_bone_shadow)
				draw_line(head_center + Vector2(-1.5 * hs, -7.5 * hs), head_center + Vector2(-9.5 * hs, -21.0 * hs), Color(col_eye_glow.r, col_eye_glow.g, col_eye_glow.b, 0.75), 1.0)
			else:
				var l_sub: PackedVector2Array = [
					head_center + Vector2(-6.0 * hs, -6.0 * hs),
					head_center + Vector2(-13.0 * hs, -14.0 * hs),
					head_center + Vector2(-8.5 * hs, -12.0 * hs)
				]
				var r_sub: PackedVector2Array = [
					head_center + Vector2(6.0 * hs, -6.0 * hs),
					head_center + Vector2(13.0 * hs, -14.0 * hs),
					head_center + Vector2(8.5 * hs, -12.0 * hs)
				]
				var l_main: PackedVector2Array = [
					head_center + Vector2(-5.0 * hs, -4.5 * hs),
					head_center + Vector2(-11.5 * hs, -16.0 * hs),
					head_center + Vector2(-10.0 * hs, -25.0 * hs),
					head_center + Vector2(-5.0 * hs, -17.5 * hs),
					head_center + Vector2(-2.5 * hs, -7.0 * hs)
				]
				var r_main: PackedVector2Array = [
					head_center + Vector2(2.5 * hs, -7.0 * hs),
					head_center + Vector2(5.0 * hs, -17.5 * hs),
					head_center + Vector2(10.0 * hs, -25.0 * hs),
					head_center + Vector2(11.5 * hs, -16.0 * hs),
					head_center + Vector2(5.0 * hs, -4.5 * hs)
				]
				draw_colored_polygon(l_sub, col_bone_shadow)
				draw_colored_polygon(r_sub, col_bone_shadow)
				draw_colored_polygon(l_main, col_bone)
				draw_colored_polygon(r_main, col_bone)
				draw_colored_polygon(PackedVector2Array([
					head_center + Vector2(-5.0 * hs, -4.5 * hs),
					head_center + Vector2(-11.5 * hs, -16.0 * hs),
					head_center + Vector2(-10.0 * hs, -25.0 * hs),
					head_center + Vector2(-7.5 * hs, -16.0 * hs)
				]), col_bone_shadow)
				draw_colored_polygon(PackedVector2Array([
					head_center + Vector2(2.5 * hs, -7.0 * hs),
					head_center + Vector2(5.0 * hs, -17.5 * hs),
					head_center + Vector2(10.0 * hs, -25.0 * hs),
					head_center + Vector2(7.5 * hs, -16.0 * hs)
				]), col_bone_shadow)
				draw_line(head_center + Vector2(-3.5 * hs, -6.5 * hs), head_center + Vector2(-8.5 * hs, -22.0 * hs), Color(col_eye_glow.r, col_eye_glow.g, col_eye_glow.b, 0.7), 1.0)
				draw_line(head_center + Vector2(3.5 * hs, -6.5 * hs), head_center + Vector2(8.5 * hs, -22.0 * hs), Color(col_eye_glow.r, col_eye_glow.g, col_eye_glow.b, 0.7), 1.0)

		"miser_horns":
			# 守财奴专属：内敛月牙骨角（内扣挺拔，精瘦锐利，冷光中脊）
			if angle == Angle.SIDE:
				var s_horn: PackedVector2Array = [
					head_center + Vector2(-2.5 * hs, -5.5 * hs),
					head_center + Vector2(-7.0 * hs, -14.0 * hs),
					head_center + Vector2(-8.0 * hs, -23.0 * hs),
					head_center + Vector2(-3.5 * hs, -16.5 * hs),
					head_center + Vector2(1.5 * hs, -7.0 * hs)
				]
				draw_colored_polygon(s_horn, col_bone)
				draw_colored_polygon(PackedVector2Array([
					head_center + Vector2(-2.5 * hs, -5.5 * hs),
					head_center + Vector2(-7.0 * hs, -14.0 * hs),
					head_center + Vector2(-8.0 * hs, -23.0 * hs),
					head_center + Vector2(-5.0 * hs, -15.0 * hs)
				]), col_bone_shadow)
				draw_line(head_center + Vector2(-1.5 * hs, -7.0 * hs), head_center + Vector2(-6.5 * hs, -20.0 * hs), Color(col_eye_glow.r, col_eye_glow.g, col_eye_glow.b, 0.65), 1.0)
			else:
				var l_shorn: PackedVector2Array = [
					head_center + Vector2(-4.5 * hs, -4.0 * hs),
					head_center + Vector2(-8.5 * hs, -14.5 * hs),
					head_center + Vector2(-6.0 * hs, -23.5 * hs),
					head_center + Vector2(-3.2 * hs, -15.5 * hs),
					head_center + Vector2(-2.0 * hs, -6.5 * hs)
				]
				var r_shorn: PackedVector2Array = [
					head_center + Vector2(2.0 * hs, -6.5 * hs),
					head_center + Vector2(3.2 * hs, -15.5 * hs),
					head_center + Vector2(6.0 * hs, -23.5 * hs),
					head_center + Vector2(8.5 * hs, -14.5 * hs),
					head_center + Vector2(4.5 * hs, -4.0 * hs)
				]
				draw_colored_polygon(l_shorn, col_bone)
				draw_colored_polygon(r_shorn, col_bone)
				draw_colored_polygon(PackedVector2Array([
					head_center + Vector2(-4.5 * hs, -4.0 * hs),
					head_center + Vector2(-8.5 * hs, -14.5 * hs),
					head_center + Vector2(-6.0 * hs, -23.5 * hs),
					head_center + Vector2(-5.0 * hs, -14.5 * hs)
				]), col_bone_shadow)
				draw_colored_polygon(PackedVector2Array([
					head_center + Vector2(2.0 * hs, -6.5 * hs),
					head_center + Vector2(3.2 * hs, -15.5 * hs),
					head_center + Vector2(6.0 * hs, -23.5 * hs),
					head_center + Vector2(5.0 * hs, -14.5 * hs)
				]), col_bone_shadow)
				draw_line(head_center + Vector2(-3.0 * hs, -6.0 * hs), head_center + Vector2(-5.0 * hs, -20.5 * hs), Color(col_eye_glow.r, col_eye_glow.g, col_eye_glow.b, 0.65), 1.0)
				draw_line(head_center + Vector2(3.0 * hs, -6.0 * hs), head_center + Vector2(5.0 * hs, -20.5 * hs), Color(col_eye_glow.r, col_eye_glow.g, col_eye_glow.b, 0.65), 1.0)

		"fox_ears":
			if angle == Angle.SIDE:
				var rear_ear := [
					head_center + Vector2(-5 * hs, -7 * hs),
					head_center + Vector2(-10 * hs, -19 * hs),
					head_center + Vector2(-2 * hs, -13 * hs)
				]
				var front_ear := [
					head_center + Vector2(1 * hs, -6 * hs),
					head_center + Vector2(8 * hs, -21 * hs),
					head_center + Vector2(4 * hs, -14 * hs)
				]
				draw_colored_polygon(rear_ear, col_bone_shadow)
				draw_colored_polygon(front_ear, col_bone)
				draw_colored_polygon([
					head_center + Vector2(2 * hs, -7 * hs),
					head_center + Vector2(7 * hs, -18 * hs),
					head_center + Vector2(3 * hs, -13 * hs)
				], col_cloak_outer)
			else:
				var l_ear := [
					head_center + Vector2(-4 * hs, -6 * hs),
					head_center + Vector2(-11 * hs, -21 * hs),
					head_center + Vector2(-2 * hs, -14 * hs)
				]
				var r_ear := [
					head_center + Vector2(4 * hs, -6 * hs),
					head_center + Vector2(11 * hs, -21 * hs),
					head_center + Vector2(2 * hs, -14 * hs)
				]
				draw_colored_polygon(l_ear, col_bone)
				draw_colored_polygon(r_ear, col_bone)
				if angle == Angle.FRONT:
					draw_colored_polygon([
						head_center + Vector2(-4 * hs, -7 * hs),
						head_center + Vector2(-9 * hs, -18 * hs),
						head_center + Vector2(-3 * hs, -13 * hs)
					], col_cloak_outer)
					draw_colored_polygon([
						head_center + Vector2(4 * hs, -7 * hs),
						head_center + Vector2(9 * hs, -18 * hs),
						head_center + Vector2(3 * hs, -13 * hs)
					], col_cloak_outer)

		"none":
			pass

		"butterfly", _:
			_draw_butterfly_horns(head_center, hs, angle)

func _draw_butterfly_horns(head_center: Vector2, hs: float, angle: Angle) -> void:
	if angle == Angle.SIDE:
		var side_horn: PackedVector2Array = [
			head_center + Vector2(-3 * hs, -6 * hs),
			head_center + Vector2(-11 * hs, -17 * hs),
			head_center + Vector2(-14 * hs, -27 * hs),
			head_center + Vector2(-5 * hs, -20 * hs),
			head_center + Vector2(2 * hs, -8 * hs)
		]
		draw_colored_polygon(side_horn, col_bone)
		draw_colored_polygon(PackedVector2Array([
			head_center + Vector2(-3 * hs, -6 * hs),
			head_center + Vector2(-11 * hs, -17 * hs),
			head_center + Vector2(-14 * hs, -27 * hs),
			head_center + Vector2(-7 * hs, -17 * hs)
		]), col_bone_shadow)
		draw_line(head_center + Vector2(-2 * hs, -8 * hs), head_center + Vector2(-12 * hs, -24 * hs), Color(col_eye_core.r, col_eye_core.g, col_eye_core.b, 0.75), 1.0)
		return

	var l_horn: PackedVector2Array = [
		head_center + Vector2(-6 * hs, -4 * hs),
		head_center + Vector2(-14 * hs, -17 * hs),
		head_center + Vector2(-12 * hs, -27 * hs),
		head_center + Vector2(-6 * hs, -19 * hs),
		head_center + Vector2(-3 * hs, -8 * hs)
	]
	draw_colored_polygon(l_horn, col_bone)
	draw_colored_polygon(PackedVector2Array([
		head_center + Vector2(-6 * hs, -4 * hs),
		head_center + Vector2(-14 * hs, -17 * hs),
		head_center + Vector2(-12 * hs, -27 * hs),
		head_center + Vector2(-9 * hs, -17 * hs)
	]), col_bone_shadow)
	draw_line(head_center + Vector2(-4 * hs, -7 * hs), head_center + Vector2(-10 * hs, -23 * hs), Color(col_eye_core.r, col_eye_core.g, col_eye_core.b, 0.7), 1.0)

	var r_horn: PackedVector2Array = [
		head_center + Vector2(3 * hs, -8 * hs),
		head_center + Vector2(6 * hs, -19 * hs),
		head_center + Vector2(12 * hs, -27 * hs),
		head_center + Vector2(14 * hs, -17 * hs),
		head_center + Vector2(6 * hs, -4 * hs)
	]
	draw_colored_polygon(r_horn, col_bone)
	draw_colored_polygon(PackedVector2Array([
		head_center + Vector2(3 * hs, -8 * hs),
		head_center + Vector2(6 * hs, -19 * hs),
		head_center + Vector2(12 * hs, -27 * hs),
		head_center + Vector2(9 * hs, -17 * hs)
	]), col_bone_shadow)
	draw_line(head_center + Vector2(4 * hs, -7 * hs), head_center + Vector2(10 * hs, -23 * hs), Color(col_eye_core.r, col_eye_core.g, col_eye_core.b, 0.7), 1.0)

## 插槽 3：眼睛神态与光芒
## 皮肤系列可收窄眼部柔光（如墨煞压到只剩一点），由族模块决定；原色零开销
func _draw_eye_soft_glow(center: Vector2, radius: float, col: Color, layers: int = 3) -> void:
	if suppress_eye_glow:
		return
	if not _fx.is_empty():
		var adj := SkinFxLibrary.eye_glow_adjust(self, radius, col, _fx)
		draw_soft_glow(center, float(adj["radius"]), adj["color"] as Color, layers)
	else:
		draw_soft_glow(center, radius, col, layers)

func _draw_modular_eyes(head_center: Vector2, angle: Angle, eye_pulse: float, blink: float = 0.0) -> void:
	var hs := head_scale
	var b := clampf(blink, 0.0, 1.0)
	var open_a := 1.0 - b
	# 睁眼垂直压扁系数：blink=0 全开，blink=1 压到 12%（留一条细线，不彻底消失）
	var sq := 1.0 - b * 0.88
	var eff_glow := col_eye_glow
	var eff_core := col_eye_core
	if eye_override_color.a > 0.01:
		eff_glow = col_eye_glow.lerp(eye_override_color, clampf(eye_override_color.a, 0.0, 1.0))
		eff_core = col_eye_core.lerp(Color(1, 1, 1, 1), 0.55).lerp(eye_override_color, 0.45)
	var glow_r := eye_glow_boost * 3.6
	var glow_a := eye_glow_boost * 0.4
	# 2026-10-23 连续眨眼：睁眼几何按 open_a 淡出、按 sq 垂直压扁；闭眼眼缝按 b 淡入。
	# 两套几何交叉淡化 + 压扁同时进行，任意 blink 值都有自然中间态，不再有 blink>0.45 硬切。
	var eff_glow_col := Color(eff_glow.r, eff_glow.g, eff_glow.b,
			clampf(eff_glow.a + eye_pulse + glow_a, 0.0, 1.0) * open_a)
	var c_void := Color(col_void.r, col_void.g, col_void.b, col_void.a * open_a)
	var c_core := Color(eff_core.r, eff_core.g, eff_core.b, eff_core.a * open_a)

	if angle == Angle.FRONT:
		var l_eye := head_center + Vector2(-4.2 * hs, 1.0 * hs)
		var r_eye := head_center + Vector2(4.2 * hs, 1.0 * hs)

		match eye_style:
			"sharp_slit":
				draw_line(l_eye + Vector2(-3.2 * hs, 0), l_eye + Vector2(3.2 * hs, 0), c_void, 2.8)
				draw_line(r_eye + Vector2(-3.2 * hs, 0), r_eye + Vector2(3.2 * hs, 0), c_void, 2.8)
				_draw_eye_soft_glow(l_eye, 5.2 + glow_r, eff_glow_col, 2)
				_draw_eye_soft_glow(r_eye, 5.2 + glow_r, eff_glow_col, 2)
				draw_line(l_eye + Vector2(-1.6 * hs, 0), l_eye + Vector2(1.6 * hs, 0), c_core, 1.5)
				draw_line(r_eye + Vector2(-1.6 * hs, 0), r_eye + Vector2(1.6 * hs, 0), c_core, 1.5)

			"round_pupil":
				draw_filled_ellipse(l_eye, 3.8 * hs, 3.8 * hs * sq, c_void)
				draw_filled_ellipse(r_eye, 3.8 * hs, 3.8 * hs * sq, c_void)
				_draw_eye_soft_glow(l_eye, 6.0 + glow_r, eff_glow_col, 3)
				_draw_eye_soft_glow(r_eye, 6.0 + glow_r, eff_glow_col, 3)
				draw_filled_ellipse(l_eye + Vector2(0.4, -0.4 * sq), 1.7 * hs, 1.7 * hs * sq, c_core)
				draw_filled_ellipse(r_eye + Vector2(-0.4, -0.4 * sq), 1.7 * hs, 1.7 * hs * sq, c_core)

			"round_bright":
				# 童子亮眼：小黑瞳大高光，去"空洞眼窝"感（驯兽师专属）
				draw_filled_ellipse(l_eye, 2.7 * hs, 2.7 * hs * sq, c_void)
				draw_filled_ellipse(r_eye, 2.7 * hs, 2.7 * hs * sq, c_void)
				_draw_eye_soft_glow(l_eye, 6.0 + glow_r, eff_glow_col, 3)
				_draw_eye_soft_glow(r_eye, 6.0 + glow_r, eff_glow_col, 3)
				draw_filled_ellipse(l_eye + Vector2(0.5, -0.5 * sq), 1.5 * hs, 1.5 * hs * sq, c_core)
				draw_filled_ellipse(r_eye + Vector2(-0.5, -0.5 * sq), 1.5 * hs, 1.5 * hs * sq, c_core)
				draw_filled_ellipse(l_eye + Vector2(-0.7, -0.8 * sq), 0.8 * hs, 0.8 * hs * sq, Color(1, 1, 1, 0.9 * open_a))
				draw_filled_ellipse(r_eye + Vector2(-0.7, -0.8 * sq), 0.8 * hs, 0.8 * hs * sq, Color(1, 1, 1, 0.9 * open_a))

			"angry_slit":
				var l_poly: PackedVector2Array = [
					l_eye + Vector2(-3.5 * hs, 2 * hs * sq), l_eye + Vector2(3.5 * hs, -1.5 * hs * sq),
					l_eye + Vector2(3 * hs, 1.5 * hs * sq)]
				var r_poly: PackedVector2Array = [
					r_eye + Vector2(-3.5 * hs, -1.5 * hs * sq), r_eye + Vector2(3.5 * hs, 2 * hs * sq),
					r_eye + Vector2(-3 * hs, 1.5 * hs * sq)]
				draw_colored_polygon(l_poly, c_void)
				draw_colored_polygon(r_poly, c_void)
				_draw_eye_soft_glow(l_eye, 6.0 + glow_r, eff_glow_col, 2)
				_draw_eye_soft_glow(r_eye, 6.0 + glow_r, eff_glow_col, 2)
				draw_filled_ellipse(l_eye, 1.6 * hs, 1.6 * hs * sq, c_core)
				draw_filled_ellipse(r_eye, 1.6 * hs, 1.6 * hs * sq, c_core)

			"hollow_oval", _:
				draw_filled_ellipse(l_eye, 3.8 * hs, 5.2 * hs * sq, c_void)
				draw_filled_ellipse(r_eye, 3.8 * hs, 5.2 * hs * sq, c_void)
				_draw_eye_soft_glow(l_eye, 6.2 + glow_r, eff_glow_col, 3)
				_draw_eye_soft_glow(r_eye, 6.2 + glow_r, eff_glow_col, 3)
				draw_filled_ellipse(l_eye + Vector2(0.2, -0.3 * sq), 2.2 * hs, 3.6 * hs * sq, c_core)
				draw_filled_ellipse(r_eye + Vector2(-0.2, -0.3 * sq), 2.2 * hs, 3.6 * hs * sq, c_core)

		if eye_glow_boost > 0.15:
			_circle(l_eye, 1.1 * hs, Color(1, 1, 1, eye_glow_boost * 0.85 * open_a))
			_circle(r_eye, 1.1 * hs, Color(1, 1, 1, eye_glow_boost * 0.85 * open_a))

		if b > 0.02:
			_draw_closed_eye_slits(head_center, angle, hs, b)

	else:
		var eye_pos := head_center + Vector2(4.2 * hs, 1.0 * hs)
		match eye_style:
			"sharp_slit":
				var slit_pts: PackedVector2Array = [
					eye_pos + Vector2(-3.0 * hs, 1.0 * hs * sq),
					eye_pos + Vector2(3.2 * hs, -1.6 * hs * sq),
					eye_pos + Vector2(2.2 * hs, 0.8 * hs * sq)
				]
				draw_colored_polygon(slit_pts, c_void)
				_draw_eye_soft_glow(eye_pos, 5.2 + glow_r, eff_glow_col, 2)
				draw_line(eye_pos + Vector2(-1.8 * hs, 0.6 * hs * sq), eye_pos + Vector2(2.4 * hs, -0.8 * hs * sq), c_core, 1.2)

			"angry_slit":
				var angry_pts: PackedVector2Array = [
					eye_pos + Vector2(-3.2 * hs, -1.4 * hs * sq),
					eye_pos + Vector2(3.2 * hs, 1.6 * hs * sq),
					eye_pos + Vector2(-2.2 * hs, 1.4 * hs * sq)
				]
				draw_colored_polygon(angry_pts, c_void)
				_draw_eye_soft_glow(eye_pos, 5.8 + glow_r, eff_glow_col, 2)
				draw_filled_ellipse(eye_pos + Vector2(0.4, 0.2 * sq), 1.5 * hs, 1.5 * hs * sq, c_core)

			"round_pupil":
				draw_filled_ellipse(eye_pos, 3.2 * hs, 3.2 * hs * sq, c_void)
				_draw_eye_soft_glow(eye_pos, 5.8 + glow_r, eff_glow_col, 2)
				draw_filled_ellipse(eye_pos + Vector2(0.3, -0.3 * sq), 1.7 * hs, 1.7 * hs * sq, c_core)

			"round_bright":
				draw_filled_ellipse(eye_pos, 2.4 * hs, 2.4 * hs * sq, c_void)
				_draw_eye_soft_glow(eye_pos, 5.8 + glow_r, eff_glow_col, 2)
				draw_filled_ellipse(eye_pos + Vector2(0.4, -0.4 * sq), 1.4 * hs, 1.4 * hs * sq, c_core)
				draw_filled_ellipse(eye_pos + Vector2(-0.4, -0.5 * sq), 0.7 * hs, 0.7 * hs * sq, Color(1, 1, 1, 0.9 * open_a))

			"hollow_oval", _:
				draw_filled_ellipse(eye_pos, 3.6 * hs, 5.0 * hs * sq, c_void)
				_draw_eye_soft_glow(eye_pos, 6.2 + glow_r, eff_glow_col, 3)
				draw_filled_ellipse(eye_pos + Vector2(0.3, -0.2 * sq), 2.2 * hs, 3.6 * hs * sq, c_core)

		if eye_glow_boost > 0.15:
			_circle(eye_pos, 1.2 * hs, Color(1, 1, 1, eye_glow_boost * 0.85 * open_a))

		if b > 0.02:
			_draw_closed_eye_slits(head_center, angle, hs, b)

## 闭眼眼缝：按 blink 淡入的深色下弯弧线（沿用旧闭眼造型，改成连续透明度）。
## 与睁眼几何交叉淡化，配合 _draw_modular_eyes 里的垂直压扁，形成「眼皮合上」的连续过程。
func _draw_closed_eye_slits(head_center: Vector2, angle: Angle, hs: float, b: float) -> void:
	var lid_col := Color(col_bone_shadow.r, col_bone_shadow.g, col_bone_shadow.b, 0.9 * b)
	if angle == Angle.FRONT:
		var l_lid := head_center + Vector2(-4.2 * hs, 1.0 * hs)
		var r_lid := head_center + Vector2(4.2 * hs, 1.0 * hs)
		_arc(l_lid + Vector2(0, -0.2 * hs), 2.7 * hs, PI * 0.15, PI * 0.85, 8, lid_col, 1.4)
		_arc(r_lid + Vector2(0, -0.2 * hs), 2.7 * hs, PI * 0.15, PI * 0.85, 8, lid_col, 1.4)
	else:
		var lid_pos := head_center + Vector2(4.2 * hs, 1.0 * hs)
		_arc(lid_pos + Vector2(0, -0.2 * hs), 2.5 * hs, PI * 0.15, PI * 0.85, 8, lid_col, 1.3)

## 绘制斗篷轮廓描边与法力流动反光（仙侠高精流光反光感）
func _draw_cloak_rim_shimmer(pts: PackedVector2Array, default_edge: Color) -> void:
	if pts.size() < 3:
		return
	var eff_edge := default_edge
	if cloak_shimmer_intensity > 0.02 and cloak_shimmer_color.a > 0.01:
		eff_edge = default_edge.lerp(cloak_shimmer_color, clampf(cloak_shimmer_intensity * 0.85, 0.0, 1.0))
	var base_w := 1.2 + cloak_shimmer_intensity * 0.8
	draw_polyline(pts, eff_edge, base_w, true)

	# 皮肤系列：缘边专属描边（彩虹环流/竹节亮带/赤光脉动/冷光横扫/金属扫光/暗光游走）
	# 由族模块决定，原色零开销；此段在基础描边之后、下摆微光之前
	if not _fx.is_empty():
		SkinFxLibrary.draw_rim(self, pts, base_w, _fx)

	# 常驻下摆微光：沿下摆顶点叠一条细亮线，随行波轻闪（技能流光叠加其上）
	var hem := PackedVector2Array()
	for p in pts:
		if p.y >= 20.0:
			hem.append(p)
	if hem.size() >= 2:
		var hem_a := 0.24 + 0.10 * sin(_time * 5.2 + hem[0].x * 0.2) + cloak_shimmer_intensity * 0.15
		var hem_c := Color(eff_edge.r, eff_edge.g, eff_edge.b, clampf(hem_a, 0.0, 1.0)).lightened(0.25)
		draw_polyline(hem, hem_c, base_w * 0.9, true)

	if cloak_shimmer_intensity > 0.05:
		var n := pts.size()
		var phase := fmod(_time * 2.8, 1.0)
		var center_idx := int(phase * float(n))
		var shimmer_c := cloak_shimmer_color if cloak_shimmer_color.a > 0.01 else Color(1.0, 0.95, 0.72)
		var s_pts := PackedVector2Array()
		for off in range(-2, 3):
			var idx := (center_idx + off + n) % n
			s_pts.append(pts[idx])
		if s_pts.size() >= 2:
			var s_alpha := clampf(cloak_shimmer_intensity, 0.0, 1.0)
			draw_polyline(s_pts, Color(shimmer_c.r, shimmer_c.g, shimmer_c.b, s_alpha * 0.85), base_w + 1.5, true)
			draw_polyline(s_pts, Color(1.0, 1.0, 1.0, s_alpha * 0.95), base_w * 0.8, true)

# ==================== 斗篷插槽绘制（端正挺拔躯干 + 逐顶点行波衣摆） ====================

## amp=行波振幅基准（可负，负值仅反相），wave_t=行波相位基准，drag=风阻拉伸
func _draw_modular_cloak(float_y: float, amp: float, wave_t: float, drag: float, angle: Angle) -> void:
	if not _layer_on(Layer.CLOAK):
		return
	# 注入行波上下文；世界系风压按 flip_h 镜像到局部空间
	_cw_amp = amp
	_cw_t = wave_t
	_cw_wind = Vector2(_wind_local.x * (-1.0 if flip_h else 1.0), _wind_local.y)
	_cw_lean = -_lean_smooth * 22.0
	match angle:
		Angle.FRONT:
			_draw_cloak_front_modular(float_y, amp, wave_t, drag)
		Angle.SIDE:
			_draw_cloak_side_modular(float_y, amp, wave_t, drag)
		Angle.BACK:
			_draw_cloak_back_modular(float_y, amp, wave_t, drag)

# ----------------- 正面斗篷 -----------------

func _draw_cloak_front_modular(float_y: float, _amp: float, _wave_t: float, extra_drag: float = 0.0) -> void:
	var w := width_scale
	var flare := extra_drag * 0.45

	# 1. 内衬道袍底衬（下摆随行波起伏）
	var inner_pts: PackedVector2Array = [
		Vector2(0, -4 + float_y),
		Vector2((-15 - flare * 0.4) * w, 12 + float_y),
		Vector2((-14 - flare) * w + _sway_x(-14.0 * w, 30.0), 30 + float_y + _sway_y(30.0)),
		Vector2(_sway_x(0.0, 27.0) * 0.5, 27 + float_y + _sway_y(27.0)),
		Vector2((14 + flare) * w + _sway_x(14.0 * w, 30.0), 30 + float_y + _sway_y(30.0)),
		Vector2((15 + flare * 0.4) * w, 12 + float_y)
	]
	draw_polygon(inner_pts, _cloak_gradient(inner_pts, col_cloak_inner))

	# 胸前交领右衽领口（道门中衣与素雪白领）
	var collar_outer: PackedVector2Array = [
		Vector2(-5.0 * w, -5 + float_y),
		Vector2(5.0 * w, -5 + float_y),
		Vector2(0, 5 + float_y)
	]
	draw_colored_polygon(collar_outer, Color(col_cloak_inner.r * 1.35, col_cloak_inner.g * 1.35, col_cloak_inner.b * 1.35))
	draw_line(Vector2(-5.0 * w, -5 + float_y), Vector2(1.5 * w, 5 + float_y), Color(col_bone.r, col_bone.g, col_bone.b, 0.8), 1.2)
	draw_line(Vector2(5.0 * w, -5 + float_y), Vector2(-1.0 * w, 2 + float_y), Color(col_bone_shadow.r, col_bone_shadow.g, col_bone_shadow.b, 0.4), 1.0)
	draw_line(Vector2(0, 5 + float_y), Vector2(0, 11 + float_y), Color(col_cloak_inner.r, col_cloak_inner.g, col_cloak_inner.b, 0.6), 1.0)

	# 2. 外袍款式（下摆顶点走逐顶点行波）
	var outer_pts: PackedVector2Array = []
	match cloak_style:
		"heavy_overcoat":
			outer_pts = [
				Vector2(0, -6 + float_y),
				Vector2(-11 * w, -2 + float_y),
				Vector2((-16 - flare * 0.5) * w, 15 + float_y),
				Vector2((-14 - flare) * w + _sway_x(-14.0 * w, 31.0), 31 + float_y + _sway_y(31.0)),
				Vector2(_sway_x(0.0, 30.0) * 0.5, 30 + float_y + _sway_y(30.0)),
				Vector2((14 + flare) * w + _sway_x(14.0 * w, 31.0), 31 + float_y + _sway_y(31.0)),
				Vector2((16 + flare * 0.5) * w, 15 + float_y),
				Vector2(11 * w, -2 + float_y)
			]
		"short_cape":
			outer_pts = [
				Vector2(0, -6 + float_y),
				Vector2(-9 * w, -2 + float_y),
				Vector2((-13 - flare * 0.5) * w, 12 + float_y),
				Vector2((-10 - flare) * w + _sway_x(-10.0 * w, 22.0), 22 + float_y + _sway_y(22.0)),
				Vector2(-4 * w + _sway_x(-4.0 * w, 25.0), 25 + float_y + _sway_y(25.0)),
				Vector2(4 * w + _sway_x(4.0 * w, 25.0), 25 + float_y + _sway_y(25.0)),
				Vector2((10 + flare) * w + _sway_x(10.0 * w, 22.0), 22 + float_y + _sway_y(22.0)),
				Vector2((13 + flare * 0.5) * w, 12 + float_y),
				Vector2(9 * w, -2 + float_y)
			]
		"tattered_rags":
			outer_pts = [
				Vector2(0, -6 + float_y),
				Vector2(-10 * w, -2 + float_y),
				Vector2((-15 - flare * 0.5) * w, 15 + float_y),
				Vector2((-13 - flare) * w + _sway_x(-13.0 * w, 27.0), 27 + float_y + _sway_y(27.0)),
				Vector2((-9 - flare * 0.6) * w + _sway_x(-9.0 * w, 32.0), 32 + float_y + _sway_y(32.0)),
				Vector2(-5 * w + _sway_x(-5.0 * w, 24.0), 24 + float_y + _sway_y(24.0)),
				Vector2(_sway_x(0.0, 31.0) * 0.6, 31 + float_y + _sway_y(31.0)),
				Vector2(6 * w + _sway_x(6.0 * w, 23.0), 23 + float_y + _sway_y(23.0)),
				Vector2((11 + flare * 0.8) * w + _sway_x(11.0 * w, 32.0), 32 + float_y + _sway_y(32.0)),
				Vector2((15 + flare * 0.5) * w, 15 + float_y),
				Vector2(10 * w, -2 + float_y)
			]
		"royal_shawl":
			outer_pts = [
				Vector2(0, -6 + float_y),
				Vector2(-10 * w, -2 + float_y),
				Vector2((-15 - flare * 0.5) * w, 14 + float_y),
				Vector2((-12 - flare) * w + _sway_x(-12.0 * w, 29.0), 29 + float_y + _sway_y(29.0)),
				Vector2(_sway_x(0.0, 27.0) * 0.5, 27 + float_y + _sway_y(27.0)),
				Vector2((12 + flare) * w + _sway_x(12.0 * w, 29.0), 29 + float_y + _sway_y(29.0)),
				Vector2((15 + flare * 0.5) * w, 14 + float_y),
				Vector2(10 * w, -2 + float_y)
			]
		"split_flowing", _:
			outer_pts = [
				Vector2(0, -6 + float_y),
				Vector2(-9 * w, -2 + float_y),
				Vector2((-14 - flare * 0.5) * w, 15 + float_y),
				Vector2((-12 - flare) * w + _sway_x(-12.0 * w, 28.0), 28 + float_y + _sway_y(28.0)),
				Vector2(-7 * w + _sway_x(-7.0 * w, 24.0), 24 + float_y + _sway_y(24.0)),
				Vector2(-3 * w + _sway_x(-3.0 * w, 31.0), 31 + float_y + _sway_y(31.0)),
				Vector2(2 * w + _sway_x(2.0 * w, 26.0), 26 + float_y + _sway_y(26.0)),
				Vector2((8 + flare) * w + _sway_x(8.0 * w, 29.0), 29 + float_y + _sway_y(29.0)),
				Vector2((14 + flare * 0.5) * w, 15 + float_y),
				Vector2(9 * w, -2 + float_y)
			]

	draw_polygon(outer_pts, _cloak_gradient(outer_pts, col_cloak_outer))
	_draw_cloak_rim_shimmer(outer_pts, col_cloak_edge)

	# 内衬折痕线：底端跟随行波相位轻微摆动
	draw_line(Vector2(-5 * w, 14 + float_y), Vector2(-4 * w + _sway_x(-4.0 * w, 26.0) * 0.6, 26 + float_y + _sway_y(26.0) * 0.5), Color(col_cloak_inner.r, col_cloak_inner.g, col_cloak_inner.b, 0.45), 1.0)
	draw_line(Vector2(5 * w, 14 + float_y), Vector2(4 * w + _sway_x(4.0 * w, 26.0) * 0.6, 26 + float_y + _sway_y(26.0) * 0.5), Color(col_cloak_inner.r, col_cloak_inner.g, col_cloak_inner.b, 0.45), 1.0)

# ----------------- 侧面斗篷（端正挺拔躯干 + 逐顶点行波下摆） -----------------

func _draw_cloak_side_modular(float_y: float, _amp: float, _wave_t: float, extra_drag: float) -> void:
	var w := width_scale
	var d := extra_drag

	# 1. 侧面内衬底色（下摆随行波起伏）
	var inner_side: PackedVector2Array = [
		Vector2(1.5, -5 + float_y),
		Vector2(5.5 * w, 1 + float_y),
		Vector2(5.0 * w, 14 + float_y),
		Vector2(4.0 * w + _sway_x(4.0 * w, 28.0), 28 + float_y + _sway_y(28.0)),
		Vector2(-4.5 * w - d * 0.2 + _sway_x(-4.5 * w, 28.0), 28 + float_y + _sway_y(28.0)),
		Vector2(-4.0 * w, 12 + float_y)
	]
	draw_polygon(inner_side, _cloak_gradient(inner_side, col_cloak_inner))

	# 2. 侧面外袍主体（前摆与后摆水平高度完全对齐，下摆走逐顶点行波）
	var side_pts: PackedVector2Array = []
	match cloak_style:
		"heavy_overcoat": # 厚重大氅（石岳、独臂刀圣）
			side_pts = [
				Vector2(2.0, -6 + float_y),
				Vector2(4.5 * w, -4 + float_y),
				Vector2(7.5 * w, 2 + float_y),
				Vector2(6.8 * w, 14 + float_y),
				Vector2(5.2 * w + _sway_x(5.2 * w, 29.5), 29.5 + float_y + _sway_y(29.5)),
				Vector2(_sway_x(0.0, 30.0) * 0.5, 30.0 + float_y + _sway_y(30.0)),
				Vector2(-6.8 * w - d * 0.35 + _sway_x(-6.8 * w, 29.5), 29.5 + float_y + _sway_y(29.5)),
				Vector2(-7.5 * w, 14 + float_y),
				Vector2(-6.5 * w, 2 + float_y),
				Vector2(-3.5 * w, -5 + float_y)
			]

		"short_cape": # 灵动短披（符童）
			var skirt_pts: PackedVector2Array = [
				Vector2(1.5, 14 + float_y),
				Vector2(5.2 * w, 15 + float_y),
				Vector2(4.0 * w + _sway_x(4.0 * w, 27.5), 27.5 + float_y + _sway_y(27.5)),
				Vector2(-4.8 * w + _sway_x(-4.8 * w, 27.5), 27.5 + float_y + _sway_y(27.5)),
				Vector2(-4.0 * w, 14 + float_y)
			]
			draw_colored_polygon(skirt_pts, col_cloak_inner)
			draw_polyline(skirt_pts, col_gold, 1.0, true)

			side_pts = [
				Vector2(1.8, -6 + float_y),
				Vector2(4.0 * w, -4 + float_y),
				Vector2(6.2 * w, 2 + float_y),
				Vector2(5.5 * w, 10 + float_y),
				Vector2(3.5 * w + _sway_x(3.5 * w, 18.0), 18.0 + float_y + _sway_y(18.0)),
				Vector2(-1.0 * w + _sway_x(-1.0 * w, 18.5), 18.5 + float_y + _sway_y(18.5)),
				Vector2(-6.5 * w - d * 0.3 + _sway_x(-6.5 * w, 18.0), 18.0 + float_y + _sway_y(18.0)),
				Vector2(-6.0 * w, 10 + float_y),
				Vector2(-5.0 * w, 1 + float_y),
				Vector2(-3.0 * w, -5 + float_y)
			]

		"tattered_rags": # 破残百衲袍（狂战、夺舍）
			side_pts = [
				Vector2(2.0, -6 + float_y),
				Vector2(4.2 * w, -4 + float_y),
				Vector2(7.0 * w, 2 + float_y),
				Vector2(6.2 * w, 14 + float_y),
				Vector2(4.8 * w + _sway_x(4.8 * w, 29.0), 29.0 + float_y + _sway_y(29.0)),
				Vector2(1.5 * w + _sway_x(1.5 * w, 26.5), 26.5 + float_y + _sway_y(26.5)),
				Vector2(-2.5 * w + _sway_x(-2.5 * w, 29.5), 29.5 + float_y + _sway_y(29.5)),
				Vector2(-5.0 * w + _sway_x(-5.0 * w, 26.0), 26.0 + float_y + _sway_y(26.0)),
				Vector2(-7.2 * w - d * 0.35 + _sway_x(-7.2 * w, 29.0), 29.0 + float_y + _sway_y(29.0)),
				Vector2(-7.0 * w, 14 + float_y),
				Vector2(-6.0 * w, 2 + float_y),
				Vector2(-3.5 * w, -5 + float_y)
			]

		"royal_shawl": # 锦绣云肩（金算盘、多宝）
			side_pts = [
				Vector2(2.0, -6 + float_y),
				Vector2(4.5 * w, -4 + float_y),
				Vector2(7.2 * w, 2 + float_y),
				Vector2(6.5 * w, 14 + float_y),
				Vector2(4.8 * w + _sway_x(4.8 * w, 28.5), 28.5 + float_y + _sway_y(28.5)),
				Vector2(_sway_x(0.0, 29.0) * 0.5, 29.0 + float_y + _sway_y(29.0)),
				Vector2(-6.8 * w - d * 0.3 + _sway_x(-6.8 * w, 28.5), 28.5 + float_y + _sway_y(28.5)),
				Vector2(-7.0 * w, 14 + float_y),
				Vector2(-6.0 * w, 2 + float_y),
				Vector2(-3.5 * w, -5 + float_y)
			]

		"split_flowing", _: # 经典双尾裂帛长袍（青云独孤、幽娘）
			side_pts = [
				Vector2(1.8, -6 + float_y),
				Vector2(4.0 * w, -4 + float_y),
				Vector2(6.8 * w, 2 + float_y),
				Vector2(6.0 * w, 14 + float_y),
				Vector2(4.5 * w + _sway_x(4.5 * w, 28.5), 28.5 + float_y + _sway_y(28.5)),
				Vector2(_sway_x(0.0, 27.5) * 0.5, 27.5 + float_y + _sway_y(27.5)),
				Vector2(-3.5 * w + _sway_x(-3.5 * w, 29.0), 29.0 + float_y + _sway_y(29.0)),
				Vector2(-6.8 * w - d * 0.35 + _sway_x(-6.8 * w, 28.5), 28.5 + float_y + _sway_y(28.5)),
				Vector2(-6.5 * w, 14 + float_y),
				Vector2(-5.5 * w, 2 + float_y),
				Vector2(-3.0 * w, -5 + float_y)
			]

	draw_polygon(side_pts, _cloak_gradient(side_pts, col_cloak_outer))
	_draw_cloak_rim_shimmer(side_pts, col_cloak_edge)

	draw_line(Vector2(1.8, -5 + float_y), Vector2(4.5 * w, 5 + float_y), Color(col_bone.r, col_bone.g, col_bone.b, 0.7), 1.1)
	draw_line(Vector2(-1.5 * w, 3 + float_y), Vector2(-2.5 * w - d * 0.1 + _sway_x(-2.5 * w, 24.0) * 0.6, 24 + float_y + _sway_y(24.0) * 0.5), Color(col_cloak_inner.r, col_cloak_inner.g, col_cloak_inner.b, 0.45), 1.0)

func _draw_cloak_dash_side(dash_y: float, progress: float = 1.0) -> void:
	if not _layer_on(Layer.CLOAK):
		return
	var w := width_scale
	# 冲刺长尾：尾梢随时间轻颤，随进度展开
	var flap := sin(_time * 12.0) * 1.1 * progress
	var dash_pts: PackedVector2Array = [
		Vector2(2.0, -6 + dash_y),
		Vector2(6.0 * w, -2 + dash_y),
		Vector2(8.0 * w, 5 + dash_y),
		Vector2(2.0 * w, 14 + dash_y + flap * 0.4),
		Vector2(-18 * w, 8 + dash_y + flap),
		Vector2(-26 * w, 4 + dash_y + flap * 1.2),
		Vector2(-14 * w, 0 + dash_y + flap * 0.6),
		Vector2(-5 * w, -3 + dash_y)
	]
	draw_polygon(dash_pts, _cloak_gradient(dash_pts, col_cloak_outer))
	_draw_cloak_rim_shimmer(dash_pts, col_cloak_edge)

# ----------------- 背面斗篷 -----------------

func _draw_cloak_back_modular(float_y: float, _amp: float, _wave_t: float, extra_drag: float = 0.0) -> void:
	var w := width_scale
	var flare := extra_drag * 0.4

	var back_pts: PackedVector2Array = []
	match cloak_style:
		"heavy_overcoat":
			back_pts = [
				Vector2(0, -6 + float_y),
				Vector2(-11 * w, -2 + float_y),
				Vector2(-16 * w, 15 + float_y),
				Vector2((-14 - flare) * w + _sway_x(-14.0 * w, 31.0), 31 + float_y + _sway_y(31.0)),
				Vector2(_sway_x(0.0, 30.0) * 0.5, 30 + float_y + _sway_y(30.0)),
				Vector2((14 + flare) * w + _sway_x(14.0 * w, 31.0), 31 + float_y + _sway_y(31.0)),
				Vector2(16 * w, 15 + float_y),
				Vector2(11 * w, -2 + float_y)
			]
		"short_cape":
			back_pts = [
				Vector2(0, -6 + float_y),
				Vector2(-9 * w, -2 + float_y),
				Vector2(-13 * w, 12 + float_y),
				Vector2((-10 - flare) * w + _sway_x(-10.0 * w, 22.0), 22 + float_y + _sway_y(22.0)),
				Vector2(-4 * w + _sway_x(-4.0 * w, 25.0), 25 + float_y + _sway_y(25.0)),
				Vector2(4 * w + _sway_x(4.0 * w, 25.0), 25 + float_y + _sway_y(25.0)),
				Vector2((10 + flare) * w + _sway_x(10.0 * w, 22.0), 22 + float_y + _sway_y(22.0)),
				Vector2(13 * w, 12 + float_y),
				Vector2(9 * w, -2 + float_y)
			]
		"tattered_rags":
			back_pts = [
				Vector2(0, -6 + float_y),
				Vector2(-10 * w, -2 + float_y),
				Vector2(-15 * w, 15 + float_y),
				Vector2((-13 - flare * 0.6) * w + _sway_x(-13.0 * w, 27.0), 27 + float_y + _sway_y(27.0)),
				Vector2((-9 - flare * 0.8) * w + _sway_x(-9.0 * w, 32.0), 32 + float_y + _sway_y(32.0)),
				Vector2(-5 * w + _sway_x(-5.0 * w, 24.0), 24 + float_y + _sway_y(24.0)),
				Vector2(_sway_x(0.0, 31.0) * 0.6, 31 + float_y + _sway_y(31.0)),
				Vector2(6 * w + _sway_x(6.0 * w, 23.0), 23 + float_y + _sway_y(23.0)),
				Vector2((11 + flare * 0.8) * w + _sway_x(11.0 * w, 32.0), 32 + float_y + _sway_y(32.0)),
				Vector2(15 * w, 15 + float_y),
				Vector2(10 * w, -2 + float_y)
			]
		"royal_shawl":
			back_pts = [
				Vector2(0, -6 + float_y),
				Vector2(-10 * w, -2 + float_y),
				Vector2(-15 * w, 14 + float_y),
				Vector2((-12 - flare) * w + _sway_x(-12.0 * w, 29.0), 29 + float_y + _sway_y(29.0)),
				Vector2(_sway_x(0.0, 27.0) * 0.5, 27 + float_y + _sway_y(27.0)),
				Vector2((12 + flare) * w + _sway_x(12.0 * w, 29.0), 29 + float_y + _sway_y(29.0)),
				Vector2(15 * w, 14 + float_y),
				Vector2(10 * w, -2 + float_y)
			]
		"split_flowing", _:
			back_pts = [
				Vector2(0, -6 + float_y),
				Vector2(-9 * w, -2 + float_y),
				Vector2(-14 * w, 15 + float_y),
				Vector2((-12 - flare) * w + _sway_x(-12.0 * w, 28.0), 28 + float_y + _sway_y(28.0)),
				Vector2(-7 * w + _sway_x(-7.0 * w, 24.0), 24 + float_y + _sway_y(24.0)),
				Vector2(-3 * w + _sway_x(-3.0 * w, 31.0), 31 + float_y + _sway_y(31.0)),
				Vector2(2 * w + _sway_x(2.0 * w, 26.0), 26 + float_y + _sway_y(26.0)),
				Vector2((8 + flare) * w + _sway_x(8.0 * w, 29.0), 29 + float_y + _sway_y(29.0)),
				Vector2(14 * w, 15 + float_y),
				Vector2(9 * w, -2 + float_y)
			]

	draw_polygon(back_pts, _cloak_gradient(back_pts, col_cloak_outer))
	_draw_cloak_rim_shimmer(back_pts, col_cloak_edge)
	draw_line(Vector2(0, -2 + float_y), Vector2(_sway_x(0.0, 24.0) * 0.3, 24 + float_y + _sway_y(24.0) * 0.4), Color(col_cloak_inner.r, col_cloak_inner.g, col_cloak_inner.b, 0.5), 1.1)

# ==================== 背负本命武器插槽绘制 ====================

func _draw_modular_strap(float_y: float) -> void:
	if not _layer_on(Layer.CLOAK):
		return
	match strap_style:
		"dual":
			var l_top := Vector2(-6, -6 + float_y)
			var l_bot := Vector2(-4, 14 + float_y)
			var r_top := Vector2(6, -6 + float_y)
			var r_bot := Vector2(4, 14 + float_y)
			draw_line(l_top, l_bot, Color(0.05, 0.08, 0.12, 0.95), 2.2)
			draw_line(r_top, r_bot, Color(0.05, 0.08, 0.12, 0.95), 2.2)
			_circle(Vector2(0, 4 + float_y), 2.8, col_bone)
			_circle(Vector2(0, 4 + float_y), 1.4, col_void)
			_circle(Vector2(0, 4 + float_y), 0.7, col_gold)
		"floating":
			_arc(Vector2(0, 4 + float_y), 9.0, 0, TAU, 20, Color(col_cloak_edge.r, col_cloak_edge.g, col_cloak_edge.b, 0.45), 1.2)
			_circle(Vector2(cos(_time * 3.0) * 9.0, 4 + float_y + sin(_time * 3.0) * 9.0), 1.2, col_eye_core)
		"diagonal", _:
			var p_top := Vector2(7, -6 + float_y)
			var p_bot := Vector2(-5, 12 + float_y)
			draw_line(p_top, p_bot, Color(0.05, 0.08, 0.12, 0.95), 2.4)
			draw_line(p_top, p_bot, col_cloak_edge, 0.8)
			var center := (p_top + p_bot) * 0.5
			_circle(center, 2.4, col_bone)
			_circle(center, 1.2, col_void)
			_circle(center, 0.6, col_gold)

## 绘制武器（正面探出右肩上方、下半部藏于斗篷后绝不露底，侧面贴背，背面外挂最表层）
func _draw_modular_weapon(pos: Vector2, rot: float, angle: Angle) -> void:
	if not _layer_on(Layer.WEAPON):
		return
	var t := Transform2D(rot, pos)

	match weapon_type:
		"stone_pillar": # 玄重墨石尺（体修石岳）
			var r_pts: PackedVector2Array = [
				t * Vector2(-3.2, -15), t * Vector2(3.2, -15),
				t * Vector2(3.2, 5), t * Vector2(-3.2, 5)
			]
			draw_colored_polygon(r_pts, col_weapon_main)
			draw_colored_polygon(PackedVector2Array([
				t * Vector2(0, -15), t * Vector2(3.2, -15),
				t * Vector2(3.2, 5), t * Vector2(0, 5)
			]), col_weapon_shadow)
			draw_polyline(r_pts, Color(0.18, 0.20, 0.24), 1.2, true)
			draw_line(t * Vector2(-1.5, -11), t * Vector2(1.5, -11), col_weapon_accent, 1.2)
			draw_line(t * Vector2(0, -11), t * Vector2(0, 0), col_weapon_accent, 1.2)
			draw_line(t * Vector2(-1.5, -5), t * Vector2(1.5, -5), col_weapon_accent, 1.2)
			draw_line(t * Vector2(-1.5, 0), t * Vector2(1.5, 0), col_weapon_accent, 1.2)
			draw_line(t * Vector2(0, 5), t * Vector2(0, 11), col_weapon_shadow, 2.6)
			_circle(t * Vector2(0, 11.5), 1.8, col_weapon_main)
			_circle(t * Vector2(0, 11.5), 0.9, col_void)

		"peach_sword": # 辟邪千年桃木剑（符阵灵童）
			var s_pts: PackedVector2Array = [
				t * Vector2(0, -14), t * Vector2(2.0, -8),
				t * Vector2(1.8, 3), t * Vector2(-1.8, 3), t * Vector2(-2.0, -8)
			]
			draw_colored_polygon(s_pts, col_weapon_main)
			draw_colored_polygon(PackedVector2Array([
				t * Vector2(0, -14), t * Vector2(2.0, -8),
				t * Vector2(1.8, 3), t * Vector2(0, 3)
			]), col_weapon_shadow)
			draw_line(t * Vector2(-3.2, 3), t * Vector2(3.2, 3), col_weapon_accent, 2.0)
			_circle(t * Vector2(-1.2, 3), 0.6, col_void)
			_circle(t * Vector2(1.2, 3), 0.6, col_eye_core)
			draw_line(t * Vector2(0, 3), t * Vector2(0, 9.5), col_weapon_main, 1.8)
			_circle(t * Vector2(0, 10), 1.4, col_weapon_accent)
			if angle != Angle.FRONT:
				draw_line(t * Vector2(0, 10), t * Vector2(-2.5, 14), Color(0.95, 0.85, 0.3), 1.2)

		"golden_abacus": # 乾坤金算盘（散修金算盘）
			var ab_pts: PackedVector2Array = [
				t * Vector2(-5.5, -12), t * Vector2(5.5, -12),
				t * Vector2(5.5, 6), t * Vector2(-5.5, 6)
			]
			draw_colored_polygon(ab_pts, col_weapon_main)
			draw_polyline(ab_pts, col_weapon_shadow, 1.2, true)
			draw_line(t * Vector2(-5, -6), t * Vector2(5, -6), col_weapon_shadow, 1.4)
			for b in [-3.2, 0, 3.2]:
				_circle(t * Vector2(b, -9), 1.0, col_weapon_accent)
				_circle(t * Vector2(b, -1), 1.0, col_weapon_accent)
				_circle(t * Vector2(b, 2.5), 1.0, col_weapon_accent)
			draw_line(t * Vector2(0, 6), t * Vector2(0, 11), col_weapon_shadow, 2.0)

		"shadow_daggers": # 阴煞双刃短刺（魅影幽娘）
			for side in [-2.5, 2.5]:
				var dt := t.translated(Vector2(side, 0))
				var d_pts: PackedVector2Array = [
					dt * Vector2(0, -13), dt * Vector2(1.8, -7),
					dt * Vector2(1.4, 2), dt * Vector2(-1.4, 2), dt * Vector2(-1.8, -7)
				]
				draw_colored_polygon(d_pts, col_weapon_main)
				draw_colored_polygon(PackedVector2Array([
					dt * Vector2(0, -13), dt * Vector2(1.8, -7),
					dt * Vector2(1.4, 2), dt * Vector2(0, 2)
				]), col_weapon_shadow)
				draw_line(dt * Vector2(0, -12), dt * Vector2(0, 1), col_weapon_accent, 1.0)
				draw_line(dt * Vector2(0, 2), dt * Vector2(0, 7.5), col_weapon_shadow, 1.6)
				_circle(dt * Vector2(0, 8), 1.2, col_weapon_accent)

		"broken_blade": # 厚背断马狂刀（独臂刀圣）
			var b_pts: PackedVector2Array = [
				t * Vector2(-2.5, -14), t * Vector2(4.5, -10),
				t * Vector2(4.0, 4), t * Vector2(-2.5, 4)
			]
			draw_colored_polygon(b_pts, col_weapon_main)
			draw_line(t * Vector2(-2.5, -14), t * Vector2(-2.5, 4), col_weapon_shadow, 1.8)
			draw_line(t * Vector2(0, -11), t * Vector2(0, 2), Color(0.85, 0.25, 0.20), 1.1)
			_circle(t * Vector2(0, 4.5), 2.8, col_weapon_shadow)
			draw_line(t * Vector2(0, 5), t * Vector2(0, 11.5), Color(0.9, 0.88, 0.84), 2.2)
			_circle(t * Vector2(0, 12), 1.8, col_weapon_main)

		"bone_axe": # 巨兽头骨双刃战斧（狂战蛮修）
			var h_pts: PackedVector2Array = [
				t * Vector2(-8, -13), t * Vector2(-3, -7),
				t * Vector2(-3, -1), t * Vector2(-7, 5),
				t * Vector2(-1, 0), t * Vector2(1, 0),
				t * Vector2(7, 5), t * Vector2(3, -1),
				t * Vector2(3, -7), t * Vector2(8, -13)
			]
			draw_colored_polygon(h_pts, col_weapon_main)
			draw_colored_polygon(PackedVector2Array([
				t * Vector2(0, -13), t * Vector2(8, -13),
				t * Vector2(3, -7), t * Vector2(1, 0)
			]), col_weapon_shadow)
			draw_line(t * Vector2(0, -14), t * Vector2(0, 11), col_weapon_shadow, 2.4)
			_circle(t * Vector2(0, 11.5), 1.8, col_weapon_accent)

		"soul_banner": # 墨竹引魂冥幡（夺舍散人）
			draw_line(t * Vector2(0, -16), t * Vector2(0, 11), Color(0.18, 0.20, 0.22), 2.0)
			draw_line(t * Vector2(-1, -14), t * Vector2(6.5, -14), Color(0.18, 0.20, 0.22), 1.4)
			var banner_pts: PackedVector2Array = [
				t * Vector2(1, -13), t * Vector2(6.5, -13),
				t * Vector2(5.5, 4), t * Vector2(1, 2)
			]
			draw_colored_polygon(banner_pts, col_weapon_main)
			_circle(t * Vector2(3.5, -5), 1.5, col_weapon_accent)
			draw_line(t * Vector2(3.5, -8), t * Vector2(3.5, -2), col_eye_core, 1.0)

		"treasure_chest": # 紫金百宝乾坤匣（多宝道人）
			var box_pts: PackedVector2Array = [
				t * Vector2(-6.5, -9), t * Vector2(6.5, -9),
				t * Vector2(6.5, 7), t * Vector2(-6.5, 7)
			]
			draw_colored_polygon(box_pts, col_weapon_main)
			draw_polyline(box_pts, col_weapon_shadow, 1.2, true)
			draw_line(t * Vector2(-6.5, 0), t * Vector2(6.5, 0), col_weapon_accent, 1.6)
			draw_line(t * Vector2(0, -9), t * Vector2(0, 7), col_weapon_accent, 1.6)
			_circle(t * Vector2(0, 0), 2.4, Color(1.0, 0.88, 0.35))
			_circle(t * Vector2(0, 0), 1.2, col_jade)

		"assorted_bundle": # 麻绳捆扎的一捆杂兵器（散修：什么都会一点）
			# 四根长短不一的兵刃从同一绳结明显扇形散开，暗示「六系各带一件」的走杂构筑；
			# 张角要够大（±0.55 rad）才能在 96px 图标里从斗篷轮廓外辨认出来
			for i in range(4):
				var spread := (float(i) - 1.5) * 0.36
				var blade_len := 16.5 - absf(float(i) - 1.5) * 3.0
				var tip: Vector2 = t * Vector2(sin(spread) * 13.0, -blade_len)
				var butt: Vector2 = t * Vector2(sin(spread) * 3.5, 8.5)
				draw_line(butt, tip, col_weapon_shadow, 3.0)
				draw_line(butt, tip, col_weapon_main, 1.8)
				# 各兵刃的护手/刃镡：一眼看出是「不同来路」的兵器
				var guard_at: Vector2 = t * Vector2(sin(spread) * 5.2, 1.5)
				draw_line(guard_at, t * Vector2(guard_at.x + cos(spread) * 3.2, guard_at.y), col_weapon_accent, 1.6)
			# 麻绳捆扎：两道横绳 + 绳结
			draw_line(t * Vector2(-5.2, 2.2), t * Vector2(5.2, 2.2), col_weapon_accent, 2.0)
			draw_line(t * Vector2(-4.4, 5.6), t * Vector2(4.4, 5.6), col_weapon_accent, 1.6)
			_circle(t * Vector2(0, 3.9), 2.1, col_weapon_accent)
			_circle(t * Vector2(0, 3.9), 0.9, col_void)

		"bone_nail", _: # 纯白月光骨钉/长剑（青云剑修独孤）
			var nail_pts: PackedVector2Array = [
				t * Vector2(0, -15),
				t * Vector2(2.4, -9),
				t * Vector2(2.0, 3),
				t * Vector2(-2.0, 3),
				t * Vector2(-2.4, -9)
			]
			draw_colored_polygon(nail_pts, col_weapon_main)
			draw_colored_polygon(PackedVector2Array([
				t * Vector2(0, -15), t * Vector2(2.4, -9),
				t * Vector2(2.0, 3), t * Vector2(0, 3)
			]), col_weapon_shadow)
			draw_line(t * Vector2(0, -13), t * Vector2(0, 2), col_weapon_accent, 1.1)
			var guard_pts: PackedVector2Array = [
				t * Vector2(-3.2, 3), t * Vector2(3.2, 3),
				t * Vector2(2.2, 5.5), t * Vector2(-2.2, 5.5)
			]
			draw_colored_polygon(guard_pts, col_bone_shadow)
			_circle(t * Vector2(0, 4.2), 0.9, col_jade)
			draw_line(t * Vector2(0, 5.5), t * Vector2(0, 10.5), col_weapon_main, 2.0)
			_circle(t * Vector2(0, 11), 1.6, col_weapon_main)
			_circle(t * Vector2(0, 11), 0.8, col_bone_shadow)

## 绘制月牙斩痕
func _draw_slash_crescent(pos: Vector2, rot: float, radius: float, progress: float) -> void:
	if not _layer_on(Layer.FX):
		return
	if progress <= 0.0 or progress >= 1.0:
		return
	var t := Transform2D(rot, pos)
	var alpha := (1.0 - progress) * 0.95
	var cur_radius := radius * (0.8 + progress * 0.3)

	draw_soft_glow(pos + t * Vector2(cur_radius * 0.6, 0), 16.0, Color(col_slash_glow.r, col_slash_glow.g, col_slash_glow.b, alpha * 0.6), 3)

	var arc_start := deg_to_rad(-65.0)
	var arc_end := deg_to_rad(65.0)
	var arc_points := 24

	var outer_pts := PackedVector2Array()
	var inner_pts := PackedVector2Array()
	for i in range(arc_points + 1):
		var theta := lerpf(arc_start, arc_end, float(i) / float(arc_points))
		outer_pts.append(pos + t * Vector2(cos(theta) * cur_radius, sin(theta) * cur_radius))
		inner_pts.append(pos + t * Vector2(cos(theta) * (cur_radius - 8.0), sin(theta) * (cur_radius - 8.0)))

	inner_pts.reverse()
	var crescent_poly := outer_pts
	crescent_poly.append_array(inner_pts)
	draw_colored_polygon(crescent_poly, Color(col_slash_arc.r, col_slash_arc.g, col_slash_arc.b, alpha))
	draw_polyline(outer_pts, Color(1.0, 1.0, 1.0, alpha), 1.6, true)
