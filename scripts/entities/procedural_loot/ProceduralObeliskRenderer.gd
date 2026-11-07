class_name ProceduralObeliskRenderer
extends Node2D

## 九天锁灵悬晶大阵 · 程序化渲染器（2026-11-07「去花」修订：常驻特效全下线，静态庄重）
##
## 用户口径：祭坛是一直都在的东西，循环特效堆满一屏太花。本版只留结构与功能读数：
##   ① 暗玉底盘（地面层，压扁 0.30，静态）
##   ② 外界环（正圆直立，范围读数主体——画多大 == 判多大；玩家在场提亮一档）
##   ③ 阶数徽印（骑环金菱/金点，静态，随灵脉阶增减）
##   ④ 三层玄石基座 + 供金槽收讫回执
##   ⑤ 悬浮白玉晶柱（轻微悬浮呼吸；充能烤金/供金饮金/激活闪白/耗尽石化四态保留）
## 已下线（同日两版折腾的教训）：pixelfx rune_circle 符环 / blessing_cone 充能天光 /
## 巡游追光 / 12 格充能刻度 / 充能向心灵气臂 / 升灵光柱与待机灵息柱 / 随侍悬晶绕行 /
## 星芒闪 / 呼吸光池——常驻 loop 全撤；充能反馈收敛到宿主三处读数契约 + 充能粒子 + 灯光。
##
## 取色铁律（2026-11-07 用户口径「去绿」）：本渲染器一律用固定鎏金/玉白系
## （GameStyle.AURUM / JADE / 自定玉白），**不读主题三件套**——祭坛的鎏金是「供金」
## 语义色，跟玩家主题变荧绿/品红会语义错乱（旧版跟主题走正是「绿圈」观感的根源）。
## 阶数只抬亮度和金浓度，不改色相。

## 重绘节流（2026-10-15 性能优化）：全场 3 座界碑常驻，原 _process 每帧无条件 queue_redraw()，
## 且 BlessingObelisk 每帧写 ring_rotation 在 setter 又 queue_redraw()（一帧两度标脏）。
## 阵盘慢速旋转、浮动与呼吸全是平滑慢速量，20Hz 节流 + 错相完全足够，消灭每帧无谓重绘。
## 【2026-10-21 充能升档】静止仍 20Hz；仅「正在充能 / 熄灭形变 / 激活闪白」这一座升到满帧率
## （VisualRate.interval(60,30)）。玩家同一时刻只能站进一座碑，故峰值只多一个节点的 _draw。
const REDRAW_INTERVAL := 0.05
## 激活闪白时长（秒）：晶柱瞬间超白过曝后回落
const FLASH_DUR := 0.16

## —— 阵盘几何 ——
## 外界环半径（正圆直立）：贴 95px 判定圈内缘，范围读数主体（画多大 == 判多大）
const ARRAY_R := 85.0
## 地面层压扁系数：贴地阵盘的透视口径
const ARRAY_SQUASH := 0.30
## 玉盘半径：略小于界环（85px），盘沿悬在界环内一点
const DISC_R := 74.0

## —— 鎏金语义色（固定，不随主题；唯一取色入口 GameStyle 的世界特效金）——
const AURUM := Color("ffc94d")            ## 暖金：阵盘主色（供金）
const AURUM_EDGE := Color("ffe9b0")       ## 暖金亮边：追光/徽印高光
const AURUM_DIM := Color(0.40, 0.30, 0.12)  ## 暗金：衬线/未点亮刻度
## —— 玉白晶柱（冷白玉；充能时烤向鎏金）——
const GEM_DARK := Color(0.07, 0.15, 0.28, 0.96)
const GEM_MID := Color(0.22, 0.50, 0.76, 0.96)
const GEM_LIGHT := Color(0.70, 0.92, 1.0, 0.98)
const GEM_RIDGE := Color(0.93, 0.98, 1.0, 0.96)

var _draw_phase: float = 0.0
var _dirty: bool = true

@export var is_spent: bool = false:
	set(val):
		if is_spent != val:
			is_spent = val
			_dirty = true

## 熄灭形变进度（0=鲜活, 1=全灰）。由 BlessingObelisk 在收尾 tween 里推进，
## 让「瞬间切剪影」变成连续下沉/褪色，避免硬切跳变。
var spent_blend: float = 0.0:
	set(val):
		spent_blend = clampf(val, 0.0, 1.0)
		_dirty = true

## 激活闪白强度（1→0 衰减），由 BlessingObelisk.trigger 时置 1
var activation_flash: float = 0.0

## 供金注入比（0..1）：金币注入演出期间由宿主 tween 灌入 —— 晶柱「饮金」渐亮，
## 金脉自基座沿晶面爬升。2026-10-25 重设计新增（单祭坛后细节预算全给这一座）。
var infuse_ratio: float = 0.0:
	set(val):
		infuse_ratio = clampf(val, 0.0, 1.0)
		_dirty = true

## 灵脉阶（1~4，2026-11-02 祭坛成长线）：由 BlessingObelisk 按「波次 + 启动次数」灌入。
## 只改常驻形态（晶柱高度/宽度/徽印档位/颜色），不碰充能/供金/耗尽的时间轴。
@export var tier: int = 1:
	set(val):
		var t := clampi(val, 1, 4)
		if tier != t:
			tier = t
			_dirty = true

@export var fill_ratio: float = 0.0:
	set(val):
		fill_ratio = clampf(val, 0.0, 1.0)
		# 灌灵进度平滑累加，由 20Hz/满帧节流自然呈现，不再每帧直接 queue_redraw

## 旧阵盘自转的外部分量（宿主每帧仍在喂，渲染已不读——「去花」后阵盘无自转元素，仅兼容保留）
@export var ring_rotation: float = 0.0:
	set(val):
		ring_rotation = val
		# 阵盘自转由节流自然呈现，不再每帧直接 queue_redraw

@export var is_charging: bool = false:
	set(val):
		if is_charging != val:
			is_charging = val
			_dirty = true

@export var is_player_inside: bool = false

var _time: float = 0.0

func _ready() -> void:
	_time = randf() * 10.0
	_draw_phase = fposmod(float(get_instance_id() % 97) * 0.001, REDRAW_INTERVAL)

func _process(delta: float) -> void:
	_time += delta
	if activation_flash > 0.0:
		activation_flash = maxf(0.0, activation_flash - delta / FLASH_DUR)

	# 节流间隔：静止 20Hz；充能/供金注入/熄灭形变/闪白这一座升到满帧率（跟随帧率档）
	var interval: float = REDRAW_INTERVAL
	if is_charging or activation_flash > 0.0 or (infuse_ratio > 0.0 and infuse_ratio < 0.999) \
			or (spent_blend > 0.0 and spent_blend < 0.999):
		interval = VisualRate.interval(60.0, 30.0)

	if _dirty or _draw_phase <= 0.0:
		_dirty = false
		_draw_phase = interval
		queue_redraw()
	else:
		_draw_phase -= delta

func _draw() -> void:
	if is_spent or spent_blend >= 0.999:
		_draw_spent_look()
		return

	_draw_ground_disc()
	_draw_array_halo()
	_draw_crystal_spire()

# ==============================================================================
# 1. 暗玉底盘（地面层 · 压扁 0.30，静态）：托住基座的暗底，给祭坛一片「占地」
# ==============================================================================
func _draw_ground_disc() -> void:
	var alive := 1.0 - spent_blend
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, ARRAY_SQUASH))
	AdaptiveDraw.circle(self, Vector2.ZERO, DISC_R, Color(0.05, 0.08, 0.13, 0.22 * alive))
	AdaptiveDraw.circle(self, Vector2.ZERO, 44.0, Color(0.07, 0.11, 0.17, 0.16 * alive))
	# 盘缘暗金细环：底盘自己的边界，别让墨盘糊进地砖
	draw_arc(Vector2.ZERO, DISC_R, 0, TAU, 48, Color(AURUM_DIM, 0.45 * alive), 1.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ==============================================================================
# 2. 外界环（正圆直立，静态）：范围读数主体 + 阶数徽印
#    玩家在场提亮一档，是「你站进范围了」的功能反馈，不做常驻动画
# ==============================================================================
func _draw_array_halo() -> void:
	var alive := 1.0 - spent_blend
	if alive <= 0.01:
		return
	var a_base: float = (0.56 if is_player_inside else 0.40) * alive

	# 2.1 主界环双线：亮金主线 + 内衬暗线（「这是一圈结界」的唯一整圆）
	draw_arc(Vector2.ZERO, ARRAY_R, 0.0, TAU, 56, Color(AURUM, a_base), 2.2, true)
	draw_arc(Vector2.ZERO, ARRAY_R - 3.5, 0.0, TAU, 56, Color(AURUM_DIM, a_base * 0.5), 1.0, true)

	# 2.2 阶数徽印（静态，骑在界环上）：2 阶四正位金菱、3 阶加四斜位金点、4 阶菱芯加白
	#     高阶阵盘的「镇环」读数，全在 95px 判定圈之内
	if tier >= 2:
		for k in range(4):
			var da := TAU * float(k) / 4.0
			var dpos := Vector2(cos(da), sin(da)) * ARRAY_R
			draw_colored_polygon(PackedVector2Array([
				dpos + Vector2(4.2, 0), dpos + Vector2(0, 4.2),
				dpos + Vector2(-4.2, 0), dpos + Vector2(0, -4.2),
			]), Color(AURUM, minf(a_base * 1.6, 1.0)))
			if tier >= 4:
				AdaptiveDraw.circle(self, dpos, 1.7, Color(1.0, 0.98, 0.9, minf(a_base * 2.0, 1.0)), 3.2)
		if tier >= 3:
			for k in range(4):
				var da2 := TAU * float(k) / 4.0 + PI / 4.0
				var dpos2 := Vector2(cos(da2), sin(da2)) * ARRAY_R
				AdaptiveDraw.circle(self, dpos2, 1.5, Color(AURUM_EDGE, minf(a_base * 1.4, 1.0)), 3.2)

# ==============================================================================
# 3. 白玉玄晶柱（直立）：三层玄石基座 + 悬浮晶柱
# ==============================================================================

## 主晶悬浮中心（本地坐标）：晶柱悬浮呼吸的锚点。
## 与 _draw_crystal_spire 的 bob_y 同一公式，改一处即两处同步。
func crystal_core_position() -> Vector2:
	var bob_amp: float = 3.5 * (1.0 - spent_blend)
	var bob_y: float = sin(_time * 2.2) * bob_amp - 12.0 + spent_blend * 6.0 - fill_ratio * 4.0
	return Vector2(0.0, bob_y)

func _draw_crystal_spire() -> void:
	var core_pos := crystal_core_position()
	var alive := 1.0 - spent_blend

	# 5.0 地面落影：双层软影垫在基座下，悬浮玄晶有落点；随阶数变大
	_draw_ground_shadow(Vector2(0, 12), 26.0 + 3.0 * float(tier - 1), 6.5 + 0.5 * float(tier - 1), 0.5)

	# 5.1 三层玄石基座（下宽上窄，承晶台收顶）：窄一号才读作「坛座」，宽了像跑道（首版教训）
	var bw: float = 24.0 + 2.5 * float(tier - 1)
	_base_layer(11.0, 17.0, bw * 0.76, bw, Color(0.07, 0.09, 0.14, 0.96), Color(0.26, 0.32, 0.42, 0.9))
	_base_layer(5.5, 11.0, bw * 0.56, bw * 0.72, Color(0.09, 0.12, 0.18, 0.96), Color(0.34, 0.40, 0.52, 0.9))
	_base_layer(1.5, 5.5, bw * 0.38, bw * 0.50, Color(0.11, 0.15, 0.22, 0.96), Color(0.42, 0.50, 0.62, 0.9))
	# 层间金缝微光（静态）：鎏金坛身的「缝里漏光」
	var seam_a: float = 0.34 * alive
	draw_line(Vector2(-bw * 0.54, 5.5), Vector2(bw * 0.54, 5.5), Color(AURUM, seam_a), 1.1)
	draw_line(Vector2(-bw * 0.70, 11.0), Vector2(bw * 0.70, 11.0), Color(AURUM_DIM, seam_a * 0.8), 1.0)
	# 承晶台光池：晶柱从一团亮金里长出来，接住悬浮感（也把晶柱底尖从暗座里托出来）
	AdaptiveDraw.circle(self, Vector2(0, 3.0), 10.5, Color(AURUM, 0.26 * alive), 3.2)
	AdaptiveDraw.circle(self, Vector2(0, 3.0), 5.5, Color(AURUM_EDGE, 0.30 * alive), 3.2)
	# 正面三枚供金槽（金铢落位的小圆印，注入比越高越亮 —— 供金的「收讫回执」）
	var slot_step: float = 7.5 + 1.5 * float(tier - 1)
	for s_i in range(3):
		var slot_x: float = -slot_step + slot_step * float(s_i)
		var slot_col := Color(0.55, 0.48, 0.28, 0.4 * alive)
		if infuse_ratio > 0.0:
			slot_col = slot_col.lerp(Color(1.0, 0.85, 0.4, 0.95 * alive), infuse_ratio)
		AdaptiveDraw.circle(self, Vector2(slot_x, 8.4), 1.8 + 0.2 * float(tier - 1), slot_col, 3.2)

	# 5.2 悬浮白玉主晶（2026-11-07 重绘：玉白冷调 + 去整圈硬描边，只留受光棱）
	var spire_h: float = (64.0 + 12.0 * float(tier - 1)) * (1.0 - spent_blend * 0.35)
	var spire_w: float = 16.0 + 3.0 * float(tier - 1)
	var hw: float = spire_w * 0.5
	var top := core_pos + Vector2(0, -spire_h * 0.6)
	var bottom := core_pos + Vector2(0, spire_h * 0.4)
	var mid_y := core_pos.y
	var left := Vector2(-hw, mid_y)
	var right := Vector2(hw, mid_y)
	var ridge := core_pos + Vector2(0, 1.0)

	# 玉白主色（阶数只抬金浓度：越后期晶面越暖，4 阶带明显鎏金边）
	var tier_gold: float = float(tier - 1) / 3.0
	var col_dark := GEM_DARK
	var col_mid := GEM_MID.lerp(Color(0.52, 0.48, 0.30), tier_gold * 0.18)
	var col_light := GEM_LIGHT.lerp(GameStyle.AURUM_EDGE, tier_gold * 0.30)
	var col_ridge := GEM_RIDGE.lerp(GameStyle.AURUM_EDGE, tier_gold * 0.35)

	# 充能灌灵：晶面自玉白烤向鎏金（进度即炉温）
	if is_charging:
		var glow_power: float = fill_ratio
		col_light = col_light.lerp(Color(1.0, 0.92, 0.55), glow_power * 0.85)
		col_ridge = col_ridge.lerp(Color(1.0, 1.0, 0.85), glow_power * 0.9)

	# 供金饮金：注入期间晶面向鎏金过渡 —— 供进来的钱「看得见」
	if infuse_ratio > 0.0:
		var gold := Color(1.0, 0.84, 0.42)
		col_mid = col_mid.lerp(gold.darkened(0.15), infuse_ratio * 0.55)
		col_light = col_light.lerp(gold.lightened(0.15), infuse_ratio * 0.75)
		col_ridge = col_ridge.lerp(Color(1.0, 0.95, 0.8), infuse_ratio * 0.8)

	# 激活闪白：整柱向超白过曝
	if activation_flash > 0.0:
		var f: float = activation_flash
		col_dark = col_dark.lerp(Color(GameStyle.FX_HDR_CORE, 1.0), f)
		col_mid = col_mid.lerp(Color(GameStyle.FX_HDR_CORE, 1.0), f)
		col_light = col_light.lerp(Color(GameStyle.FX_HDR_CORE, 1.0), f)
		col_ridge = col_ridge.lerp(Color(GameStyle.FX_HDR_CORE, 1.0), f)

	# 熄灭形变：晶面褪向冷灰
	if spent_blend > 0.0:
		var grey := Color(0.24, 0.28, 0.33, 0.95)
		var b: float = spent_blend
		col_dark = col_dark.lerp(grey.darkened(0.3), b)
		col_mid = col_mid.lerp(grey, b)
		col_light = col_light.lerp(grey.lightened(0.1), b)
		col_ridge = col_ridge.lerp(grey, b)

	# 4 个主晶几何切面
	draw_colored_polygon(PackedVector2Array([top, ridge, left]), col_mid)      # 上左（次亮）
	draw_colored_polygon(PackedVector2Array([top, right, ridge]), col_light)   # 上右（极亮）
	draw_colored_polygon(PackedVector2Array([left, ridge, bottom]), col_dark)  # 下左（暗面）
	draw_colored_polygon(PackedVector2Array([ridge, right, bottom]), col_mid.darkened(0.2))  # 下右（透光）

	# 中脊高光 + 受光右棱 + 左半面内切棱（三线把「多切面晶体」读出来，不再描整圈硬边）
	draw_line(top, bottom, col_ridge, 1.2, true)
	draw_line(top.lerp(right, 0.2), right.lerp(bottom, 0.5), Color(col_ridge, 0.55 * alive), 1.0, true)
	draw_line(left, ridge.lerp(bottom, 0.35), Color(col_mid.lightened(0.25), 0.5 * alive), 1.0, true)
	# 顶尖光珠
	AdaptiveDraw.circle(self, top, 1.8, Color(col_ridge, 0.9 * alive), 3.2)

	# 灌灵液面（自下而上注入）；熄灭形变时不画
	if fill_ratio > 0.02 and spent_blend < 0.05:
		var fill_y := lerpf(bottom.y, top.y, fill_ratio)
		var fill_col := Color(1.0, 0.92, 0.45, 0.85)
		draw_line(Vector2(-hw * (1.0 - fill_ratio * 0.3), fill_y), Vector2(hw * (1.0 - fill_ratio * 0.3), fill_y), fill_col, 2.0)
		AdaptiveDraw.circle(self, Vector2(0, fill_y), 2.5, Color(1.0, 1.0, 0.9, 0.95), 3.2)

	# 供金金脉：注入比越高，金线自基座沿晶面爬得越高 —— 钱化灵的实际进度
	if infuse_ratio > 0.02 and spent_blend < 0.05:
		var vein_y: float = lerpf(bottom.y, top.y, infuse_ratio * 0.85)
		draw_line(Vector2(-hw * 0.45, vein_y + 4.0), Vector2(hw * 0.5, vein_y), Color(1.0, 0.86, 0.45, 0.85), 1.3, true)
		AdaptiveDraw.circle(self, Vector2(hw * 0.5, vein_y), 1.8, Color(1.0, 0.95, 0.8, 0.9), 3.2)

## 单层基座梯形：面 + 闭合棱线（上窄下宽，立面读作石头）
func _base_layer(y_top: float, y_bot: float, w_top: float, w_bot: float, face: Color, edge: Color) -> void:
	var pts := PackedVector2Array([
		Vector2(-w_top, y_top), Vector2(w_top, y_top),
		Vector2(w_bot, y_bot), Vector2(-w_bot, y_bot),
	])
	draw_colored_polygon(pts, face)
	draw_polyline(PackedVector2Array([
		Vector2(-w_top, y_top), Vector2(w_top, y_top),
		Vector2(w_bot, y_bot), Vector2(-w_bot, y_bot),
		Vector2(-w_top, y_top),
	]), edge, 1.1, true)

## 双层软地影（2026-10-18 阴影统一升级）：外层弥散 + 内层接触暗核，与全场实体同一画法。
## 无 draw_filled_ellipse 辅助，本地以 16 边多边形近似压扁椭圆。
func _draw_ground_shadow(pos: Vector2, rx: float, ry: float, alpha: float) -> void:
	for layer in range(2):
		var k := 1.0 if layer == 0 else 0.66
		var a := alpha * 0.6 if layer == 0 else minf(alpha * 1.35, 0.88)
		var pts := PackedVector2Array()
		for i in range(16):
			var ang := TAU * float(i) / 16.0
			pts.append(pos + Vector2(cos(ang) * rx * k, sin(ang) * ry * k))
		var depth := 1.0 if layer == 0 else 0.4
		draw_colored_polygon(pts, Color(0.04 * depth, 0.05 * depth, 0.08 * depth, a))

# ==============================================================================
# 4. 耗尽沉寂态（Spent / Inactive Look）：熄灭的界环残线 + 暗盘残痕 + 灰岩基座 + 石化晶
# ==============================================================================
func _draw_spent_look() -> void:
	# 暗盘残痕（压扁平面）：比原稿提亮一档——暗底上要还能看出「这儿有座用掉的阵」
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, ARRAY_SQUASH))
	AdaptiveDraw.circle(self, Vector2.ZERO, DISC_R, Color(0.05, 0.06, 0.09, 0.28))
	draw_arc(Vector2.ZERO, DISC_R, 0, TAU, 48, Color(0.30, 0.28, 0.22, 0.22), 1.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 熄灭的界环残线（正圆，比活着时细一档暗一档）
	draw_arc(Vector2.ZERO, ARRAY_R, 0, TAU, 56, Color(0.34, 0.33, 0.30, 0.22), 1.4, true)

	# 地面落影（耗尽态同样垫底；随阶数变大）
	_draw_ground_shadow(Vector2(0, 12), 26.0 + 3.0 * float(tier - 1), 6.5 + 0.5 * float(tier - 1), 0.45)

	# 三层基座（灰岩质感：面提亮、棱描边）；随阶数加宽，几何与鲜活态同一条 _base_layer 链
	var bw: float = 24.0 + 2.5 * float(tier - 1)
	_base_layer(11.0, 17.0, bw * 0.76, bw, Color(0.17, 0.19, 0.22, 0.96), Color(0.36, 0.40, 0.45, 0.85))
	_base_layer(5.5, 11.0, bw * 0.56, bw * 0.72, Color(0.19, 0.21, 0.25, 0.96), Color(0.40, 0.44, 0.50, 0.85))
	_base_layer(1.5, 5.5, bw * 0.38, bw * 0.50, Color(0.21, 0.23, 0.27, 0.96), Color(0.44, 0.48, 0.54, 0.85))

	# 灵晶下落沉入承晶台且失去光泽（石灰色 + 冷高光棱线，读得出是块石化晶石）；高阶残晶更高更宽
	var resting_pos := Vector2(0, -6.0)
	var stone_h: float = 20.0 + 4.0 * float(tier - 1)
	var stone_w: float = 8.0 + 1.5 * float(tier - 1)
	var pts := PackedVector2Array([
		resting_pos + Vector2(0, -stone_h),
		resting_pos + Vector2(stone_w, 6),
		resting_pos + Vector2(0, 14),
	])
	draw_colored_polygon(pts, Color(0.33, 0.36, 0.41, 0.96))
	# 左半面压暗，留一点体积感
	draw_colored_polygon(PackedVector2Array([
		resting_pos + Vector2(0, -stone_h), resting_pos + Vector2(-stone_w, 6),
		resting_pos + Vector2(0, 14)
	]), Color(0.26, 0.29, 0.34, 0.96))
	draw_polyline(pts, Color(0.52, 0.57, 0.62, 0.85), 1.3, true)
	draw_line(resting_pos + Vector2(0, -stone_h), resting_pos + Vector2(0, 14),
		Color(0.46, 0.51, 0.56, 0.9), 1.1)
