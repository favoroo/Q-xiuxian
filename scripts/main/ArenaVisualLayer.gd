class_name ArenaVisualLayer
extends Node2D

## 竞技场战台程序化矢量装饰与九天锁灵结界（空洞冷冽国风）
## 涵盖中心太极四象大阵、四方灵脉刻槽与九幽边界锁灵结界光幕
## 【注意】T-4A（2026-10-15）：结界主光丝改 BoundaryFlowBand 流光带（shader TIME 驱动，零 CPU 重绘），
##   灵脉刻槽接 GameStyle.FX_HDR_WATER 低档 + 6s 呼吸；太极阵/刻槽仍走本层 _draw。
## 【注意】性能（2026-10-15）：石台砌缝/符印底座等纯静态指令拆到 StaticDecor
##   子节点一次性绘制（show_behind_parent 保持原有叠放次序），本层 10Hz 重绘只剩呼吸/自转动画。

const BOUNDARY_FLOW_SHADER := preload("res://assets/shaders/boundary_flow.gdshader")

var _time: float = 0.0
var half_extent: float = 480.0
var _flow_bands: Array[BoundaryFlowBand] = []
var _static_decor: StaticDecor = null
var _flow_mat: ShaderMaterial = null

# 动态天象主题参数（每5波由 GameBalance.stage_theme_for_wave 注入）
var _taiji_col_cyan: Color = Color(0.25, 0.70, 0.90)
var _taiji_col_gold: Color = Color(0.85, 0.70, 0.25)
var _taiji_rot_mult: float = 0.07
var _talisman_flow_period: float = 8.0

## 重绘节流（2026-10-11 第 6 波卡顿优化，2026-10-14 再降）：本层动画全是慢速量
## （灵脉 90s/圈自转 + 呼吸正弦 + 结界脉冲），10Hz 重绘肉眼无感 —— 高频重绘是白烧。
const REDRAW_INTERVAL := 0.1
var _redraw_timer: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 保持 z_index = 0：位于 MapLayer 内，靠树顺序排在地砖与地面微细节之上；
	# 绝不设 >0（实体层 EntitiesLayer 及其角色默认为 z=0，设 >0 会直接盖在玩家身体上）
	z_index = 0
	# 静态装饰层：砌缝/符印底座/阵角一次画完不再重绘；show_behind_parent 让静态垫底，
	# 保持「静态底座 → 动态描边/脉冲 → 流光带」的原叠放次序
	_static_decor = StaticDecor.new()
	_static_decor.show_behind_parent = true
	add_child(_static_decor)
	_static_decor.sync_half(half_extent)

func _process(delta: float) -> void:
	# _time 逐帧累计不节流，重绘触发时取到的是当前时刻，动画不会因节流变卡
	_time += delta
	_ensure_visibility()
	_static_decor.sync_half(half_extent)  # 变更闸：half 没变就是一次浮点比较
	_redraw_timer -= delta
	if _redraw_timer <= 0.0:
		_redraw_timer = REDRAW_INTERVAL
		queue_redraw()

## 流光带显隐对齐本层可见性：本层是常显层（主战场装饰），带子随层常亮；
## 保留此钩子以便父链隐藏（如预览看板裁切）时带子同步，不留下孤亮。
func _ensure_visibility() -> void:
	if _flow_bands.is_empty():
		return
	var should_show := is_visible_in_tree()
	for band in _flow_bands:
		band.half = half_extent  # 快照对齐宿主现值，顶点重建由 band 自身 half 变更闸把关
		if band.visible != should_show:
			band.visible = should_show

func _draw() -> void:
	_ensure_flow_bands()
	_draw_central_taiji_array()
	_draw_talisman_pulse()

## 结界流光带懒挂载：首次 _draw（half_extent 已由 Main 定值）时创建，
## 三条与主光丝同长的梯形带（上下左右），shader TIME 驱动，之后 CPU 零重绘。
func _ensure_flow_bands() -> void:
	if not _flow_bands.is_empty():
		return
	if _flow_mat == null:
		_flow_mat = ShaderMaterial.new()
		_flow_mat.shader = BOUNDARY_FLOW_SHADER
	var placeholder_tex := PlaceholderTexture2D.new()
	for seg in 4:
		var band := BoundaryFlowBand.new()
		band.segment = seg
		band.half = half_extent
		band.texture = placeholder_tex
		band.material = _flow_mat
		band.visible = false  # _ensure_visibility 定位后再亮
		add_child(band)
		_flow_bands.append(band)

## 动态天象主题切换（纯函数字典输入，零 CPU 重绘增幅）：
## 切换结界流光边缘色彩、流速、脉动与大阵/符印灵韵
func apply_stage_theme(theme: Dictionary) -> void:
	if theme.is_empty():
		return
	_taiji_col_cyan = theme.get("taiji_cyan", Color(0.25, 0.70, 0.90))
	_taiji_col_gold = theme.get("taiji_gold", Color(0.85, 0.70, 0.25))
	_taiji_rot_mult = theme.get("taiji_rot_speed", 0.07)
	_talisman_flow_period = theme.get("talisman_flow_period", 8.0)
	_ensure_flow_bands()
	if _flow_mat != null:
		var bar_base: Color = theme.get("barrier_base", Color(0.12, 0.36, 0.58, 0.65))
		var bar_flow: Color = theme.get("barrier_flow", Color(0.55, 1.35, 2.00, 0.95))
		var is_boss: bool = theme.get("is_boss", false)
		if is_boss:
			bar_flow = bar_flow.lightened(0.12)
		_flow_mat.set_shader_parameter("base_color", bar_base)
		_flow_mat.set_shader_parameter("flow_color", bar_flow)
		_flow_mat.set_shader_parameter("flow_speed", theme.get("flow_speed", 0.035) * (1.25 if is_boss else 1.0))
		_flow_mat.set_shader_parameter("pulse_speed", theme.get("pulse_speed", 0.9) * (1.3 if is_boss else 1.0))
	queue_redraw()

# ==============================================================================
# 1. 中心太极四象大阵（Central Taiji & Quad Array）
# ==============================================================================
func _draw_central_taiji_array() -> void:
	# 三圈半径随 half_extent 等比缩放（标准半场 440 下为 145 / 92 / 44）
	var scale_f := half_extent / 440.0
	var r_outer: float = 145.0 * scale_f
	var r_mid: float = 92.0 * scale_f
	var r_inner: float = 44.0 * scale_f

	# 柔和灵脉呼吸（低对比度，确保绝对不抢战斗视线）
	var breath: float = sin(_time * 0.8) * 0.04 + 0.22
	var col_cyan := Color(_taiji_col_cyan.r, _taiji_col_cyan.g, _taiji_col_cyan.b, breath)
	var col_gold := Color(_taiji_col_gold.r, _taiji_col_gold.g, _taiji_col_gold.b, breath * 0.85)
	var col_dark := Color(0.08, 0.15, 0.24, breath * 0.6)

	# 极慢灵脉自转（每 90 秒转一圈，如同天地运转）
	var rot: float = _time * _taiji_rot_mult
	draw_set_transform(Vector2.ZERO, rot, Vector2.ONE)

	# 外同心双环（弧段按半径自适应修剪：145px 半径 48 段已远超肉眼分辨）
	AdaptiveDraw.arc(self, Vector2.ZERO, r_outer, 0.0, TAU, col_cyan, 1.8, true)
	AdaptiveDraw.arc(self, Vector2.ZERO, r_outer - 8.0, 0.0, TAU, col_dark, 1.0, true)

	# 12 方位天干地支刻印点
	for i in range(12):
		var a := (TAU / 12.0) * float(i)
		var p_node := Vector2(cos(a), sin(a)) * (r_outer - 4.0)
		AdaptiveDraw.circle(self, p_node, 1.8, col_gold)

	# 中阵环（四象象限与八卦爻刻）
	AdaptiveDraw.arc(self, Vector2.ZERO, r_mid, 0.0, TAU, col_dark, 1.2, true)
	for j in range(8):
		var b := (TAU / 8.0) * float(j)
		var dir := Vector2(cos(b), sin(b))
		draw_line(dir * (r_inner + 8.0), dir * (r_mid - 6.0), col_cyan * 0.8, 1.0)
		# 八卦爻位短横
		var p_mid := dir * r_mid
		draw_line(p_mid - dir.orthogonal() * 4.0, p_mid + dir.orthogonal() * 4.0, col_gold, 1.4)

	# 内阵核：太极双鱼图腾
	AdaptiveDraw.arc(self, Vector2.ZERO, r_inner, 0.0, TAU, col_cyan, 1.5, true)

	# 阴阳鱼 S 曲线刻线
	var s_pts := PackedVector2Array()
	var s_steps := 14
	for k in range(s_steps + 1):
		var t := float(k) / float(s_steps)
		var ang := -PI * 0.5 + PI * t
		var r_half := r_inner * 0.5
		s_pts.append(Vector2(0, -r_half) + Vector2(cos(ang), sin(ang)) * r_half)
	for k in range(s_steps + 1):
		var t := float(k) / float(s_steps)
		var ang := PI * 0.5 - PI * t
		var r_half := r_inner * 0.5
		s_pts.append(Vector2(0, r_half) + Vector2(cos(ang), sin(ang)) * r_half)
	draw_polyline(s_pts, col_cyan, 1.4, true)

	# 阴阳眼
	AdaptiveDraw.circle(self, Vector2(0, -r_inner * 0.5), 3.5, col_cyan)
	AdaptiveDraw.circle(self, Vector2(0, r_inner * 0.5), 3.5, col_dark)
	AdaptiveDraw.circle(self, Vector2(0, r_inner * 0.5), 1.5, col_gold)

	# 还原坐标系
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ==============================================================================
# 2. 结界灵枢符印脉冲（动态部分：描边与核心的慢呼吸 + 流光涟漪激活）
# 静态部分（石台砌缝、菱形底座、镇魂阵角）已拆到 StaticDecor 一次性绘制，见文件尾
# （注：原 2. 四方灵脉刻槽 _draw_array_conduits 已于 2026-10-19 移除，消除切断玉面的直穿连线）
# 2026-10-21 精致化：符印核心加「流光涟漪」——能量脉冲沿结界环流转（8s/圈），
#   当前激活符印提亮放大，相邻符印渐变衰减，像灵力在结界节点间传递。
# ==============================================================================
func _draw_talisman_pulse() -> void:
	var h: float = half_extent
	var node_pulse := sin(_time * 1.6) * 0.15 + 0.85
	var col_node_rim := Color(_taiji_col_cyan.r, _taiji_col_cyan.g, _taiji_col_cyan.b, 0.65 * node_pulse)
	var col_node_core := Color(_taiji_col_gold.r, _taiji_col_gold.g, _taiji_col_gold.b, 0.80 * node_pulse)
	var node_spacing := 68.0
	var node_count := int((h * 2.0 - 180.0) / node_spacing)
	var node_start := -h + 90.0 + (h * 2.0 - 180.0 - float(node_count) * node_spacing) * 0.5
	var r_dist: float = h - 14.0  # 正好嵌在流光带（h-22 到 h-6）中心轴线上

	# 流光涟漪：当前激活符印 index（沿四边循环，周期 _talisman_flow_period）
	# 总符印数 = (node_count + 1) * 4（四边，每边 node_count+1 个）
	var total_nodes := float(node_count + 1) * 4.0
	var flow_period := _talisman_flow_period  # 流转一圈周期（秒）
	var active_idx := int(fmod(_time / flow_period, 1.0) * total_nodes)

	var node_global_idx := 0  # 全局符印序号（跨四边连续编号）
	for n_idx in node_count + 1:
		var pos_coord := node_start + float(n_idx) * node_spacing
		var node_positions := [
			Vector2(pos_coord, -r_dist), # 上
			Vector2(r_dist, pos_coord),  # 右
			Vector2(pos_coord, r_dist),  # 下
			Vector2(-r_dist, pos_coord), # 左
		]
		for n_pos in node_positions:
			# 流光涟漪激活强度：距离当前激活符印的环形距离 → 高亮衰减
			var ring_dist := absi(node_global_idx - active_idx)
			# 环形距离（取顺/逆时针最近）
			var ring_dist_wrap := mini(ring_dist, int(total_nodes) - ring_dist)
			var glow_factor := 1.0
			if ring_dist_wrap == 0:
				glow_factor = 1.8  # 当前激活：核心半径 ×1.8
			elif ring_dist_wrap == 1:
				glow_factor = 1.4  # 相邻符印：渐变衰减
			elif ring_dist_wrap == 2:
				glow_factor = 1.15

			# 菱形灵枢符印描边（底座填色在 StaticDecor）
			var d_r := 3.2
			var diamond := PackedVector2Array([
				n_pos + Vector2(0, -d_r * 1.3),
				n_pos + Vector2(d_r, 0),
				n_pos + Vector2(0, d_r * 1.3),
				n_pos + Vector2(-d_r, 0),
				n_pos + Vector2(0, -d_r * 1.3)
			])
			draw_polyline(diamond, col_node_rim, 1.0)
			# 核心半径按激活强度缩放，alpha 同步增强
			var core_col := col_node_core
			core_col.a = minf(core_col.a * glow_factor, 1.0)
			AdaptiveDraw.circle(self, n_pos, 1.2 * glow_factor, core_col)

			node_global_idx += 1

# ==============================================================================
# 4. 结界流光带（BoundaryFlowBand，T-4.1）
# ==============================================================================
## 结界主光丝的 shader 化载体：四段梯形沿边界内缘 8px 拼成整圈，
## UV.x 按整圈周长参数化 → 亮团跨段流转无缝；动画全在 boundary_flow.gdshader 的 TIME 里，
## 挂上后 CPU 零重绘（不再吃本层 10Hz queue_redraw）。
## 树序在父层 _draw 内容之上（后挂 + z=0），恰好压在玄铁基线与金引线之间高光位。
## half_extent 运行时可改（Main / 预览看板），每帧按当前值重建顶点，成本可忽略。
class BoundaryFlowBand:
	extends Polygon2D

	## 第几段：0=上 1=右 2=下 3=左（顺时针，与 UV 参数化一致）
	var segment: int = 0
	## 结界半边长（宿主 half_extent 快照）
	var half: float = 480.0
	var _built_half: float = -1.0  # 顶点缓存：half 未变不重建

	func _process(_delta: float) -> void:
		if is_equal_approx(half, _built_half):
			return
		_built_half = half
		var e := half - 6.0   # 结界外沿（与石台外层咬合）
		var i := half - 22.0  # 结界内沿（带宽 16px，更充实更具光障质感）
		var quad := PackedVector2Array()
		var uvs := PackedVector2Array()
		match segment:
			0:  # 上：左→右，UV.x 沿周长 [0, 0.25]，角部 45° 梯形斜切
				quad = PackedVector2Array([Vector2(-e, -e), Vector2(e, -e), Vector2(i, -i), Vector2(-i, -i)])
				uvs = PackedVector2Array([Vector2(0.0, 0), Vector2(0.25, 0), Vector2(0.25, 1), Vector2(0.0, 1)])
			1:  # 右：上→下 [0.25, 0.5]
				quad = PackedVector2Array([Vector2(e, -e), Vector2(e, e), Vector2(i, i), Vector2(i, -i)])
				uvs = PackedVector2Array([Vector2(0.25, 0), Vector2(0.5, 0), Vector2(0.5, 1), Vector2(0.25, 1)])
			2:  # 下：右→左 [0.5, 0.75]
				quad = PackedVector2Array([Vector2(e, e), Vector2(-e, e), Vector2(-i, i), Vector2(i, i)])
				uvs = PackedVector2Array([Vector2(0.5, 0), Vector2(0.75, 0), Vector2(0.75, 1), Vector2(0.5, 1)])
			3:  # 左：下→上 [0.75, 1.0]
				quad = PackedVector2Array([Vector2(-e, e), Vector2(-e, -e), Vector2(-i, -i), Vector2(-i, i)])
				uvs = PackedVector2Array([Vector2(0.75, 0), Vector2(1.0, 0), Vector2(1.0, 1), Vector2(0.75, 1)])
		polygon = quad
		uv = uvs

# ==============================================================================
# 5. 静态装饰层（StaticDecor，一次性绘制）
# ==============================================================================
## 战台装饰中不随时间变化的部分：石台砌缝/金纹（原 3.1）、符印菱形底座（原 3.2 填色）。
## 拆出后只在进树/half 变更时画一次，不再吃宿主 10Hz queue_redraw。
## 宿主设置 show_behind_parent，叠放次序与原单次 _draw 一致。
class StaticDecor:
	extends Node2D

	## 结界半边长（宿主 half_extent 快照）
	var half: float = 480.0
	var _built_half: float = -1.0  # 变更闸：half 未变不重画

	func sync_half(v: float) -> void:
		if is_equal_approx(v, _built_half):
			return
		half = v
		if _built_half >= 0.0:
			queue_redraw()  # 进树首次由引擎自动 _draw，只有运行中变更才需要标脏
		_built_half = v

	func _draw() -> void:
		_draw_barrier_base()
		_draw_talisman_diamonds()
		_draw_quad_spirit_marks()

	# --------------------------------------------------------------------------
	# 3.1 战台边缘界石台基（古石砌筑、榫卯咬合与台阶立体阴影）
	# --------------------------------------------------------------------------
	func _draw_barrier_base() -> void:
		var h: float = half
		# (a) 悬空台阶外沿与坠崖深影（h 到 h + 10）
		var drop_rect := [
			Vector2(-h - 8.0, -h - 8.0), Vector2(h + 8.0, -h - 8.0),
			Vector2(h + 8.0, h + 8.0), Vector2(-h - 8.0, h + 8.0),
			Vector2(-h - 8.0, -h - 8.0)
		]
		draw_polyline(PackedVector2Array(drop_rect), Color(0.015, 0.025, 0.04, 0.95), 16.0)
		# 台阶最外围的一线微弱冷墨收边线
		draw_polyline(PackedVector2Array(drop_rect), Color(0.05, 0.09, 0.14, 0.65), 1.5)

		# (b) 压顶玄岩石基（h - 18 到 h）
		var coping_rect := [
			Vector2(-h + 8.0, -h + 8.0), Vector2(h - 8.0, -h + 8.0),
			Vector2(h - 8.0, h - 8.0), Vector2(-h + 8.0, h - 8.0),
			Vector2(-h + 8.0, -h + 8.0)
		]
		draw_polyline(PackedVector2Array(coping_rect), Color(0.045, 0.075, 0.115, 0.98), 16.0)

		# (c) 古石板榫卯砌缝（Masonry Joints）：规整石条砌筑感，每隔约 55px 一处砌缝
		var joint_col_shadow := Color(0.015, 0.025, 0.035, 0.9)
		var joint_col_light := Color(0.18, 0.32, 0.45, 0.35)
		var joint_spacing := 55.0
		var joint_count := int((h * 2.0 - 160.0) / joint_spacing)
		var start_offset := -h + 80.0 + (h * 2.0 - 160.0 - float(joint_count) * joint_spacing) * 0.5

		for idx in joint_count + 1:
			var coord := start_offset + float(idx) * joint_spacing
			# 上下两侧石缝（垂直线，y 跨越 [-h - 2, -h + 16] 与 [h - 16, h + 2]）
			draw_line(Vector2(coord, -h - 2.0), Vector2(coord, -h + 16.0), joint_col_shadow, 1.4)
			draw_line(Vector2(coord + 1.0, -h - 2.0), Vector2(coord + 1.0, -h + 16.0), joint_col_light, 0.8)
			draw_line(Vector2(coord, h - 16.0), Vector2(coord, h + 2.0), joint_col_shadow, 1.4)
			draw_line(Vector2(coord + 1.0, h - 16.0), Vector2(coord + 1.0, h + 2.0), joint_col_light, 0.8)
			# 左右两侧石缝（水平线，x 跨越 [-h - 2, -h + 16] 与 [h - 16, h + 2]）
			draw_line(Vector2(-h - 2.0, coord), Vector2(-h + 16.0, coord), joint_col_shadow, 1.4)
			draw_line(Vector2(-h - 2.0, coord + 1.0), Vector2(-h + 16.0, coord + 1.0), joint_col_light, 0.8)
			draw_line(Vector2(h - 16.0, coord), Vector2(h + 2.0, coord), joint_col_shadow, 1.4)
			draw_line(Vector2(h - 16.0, coord + 1.0), Vector2(h + 2.0, coord), joint_col_light, 0.8)

		# (d) 台阶内缘倒角分界金纹（嵌在石基与战台地砖之间，h - 22）
		var inner_filigree_rect := [
			Vector2(-h + 22.0, -h + 22.0), Vector2(h - 22.0, -h + 22.0),
			Vector2(h - 22.0, h - 22.0), Vector2(-h + 22.0, h - 22.0),
			Vector2(-h + 22.0, -h + 22.0)
		]
		draw_polyline(PackedVector2Array(inner_filigree_rect), Color(0.85, 0.70, 0.28, 0.45), 1.0)
		# 并在内缘内侧衬一条极微暗线，增强石台阶的高差深度感
		var inner_depth_rect := [
			Vector2(-h + 23.5, -h + 23.5), Vector2(h - 23.5, -h + 23.5),
			Vector2(h - 23.5, h - 23.5), Vector2(-h + 23.5, h - 23.5),
			Vector2(-h + 23.5, -h + 23.5)
		]
		draw_polyline(PackedVector2Array(inner_depth_rect), Color(0.02, 0.04, 0.06, 0.6), 1.0)

	# --------------------------------------------------------------------------
	# 3.3 四象方位灵纹（Quad Spirit Marks）：太极阵内环外缘的云雷纹角花
	# --------------------------------------------------------------------------
	## 在太极阵内环 r=44*scale_f 外缘，东西南北四方位各刻一组极简云雷纹角花：
	## L 形主纹 + 内侧卷曲回纹，象征四象镇守。暗青色低对比，不抢太极阵主体。
	func _draw_quad_spirit_marks() -> void:
		var scale_f := half / 440.0
		var r_base: float = 50.0 * scale_f  # 灵纹起始半径（内环 44 外缘）
		var col_mark := Color(0.08, 0.15, 0.24, 0.35)
		var col_curl := Color(0.25, 0.65, 0.85, 0.12)

		for i in range(4):
			var ang := PI * 0.5 * float(i)
			var radial := Vector2(cos(ang), sin(ang))
			var tangent := radial.orthogonal()

			# L 形主纹：径向 6px + 切向 6px（指向阵心）
			var p_corner := radial * r_base
			var p_radial_end := radial * (r_base + 6.0 * scale_f)
			var p_tangent_end := p_corner + tangent * 6.0 * scale_f
			draw_line(p_corner, p_radial_end, col_mark, 1.2)
			draw_line(p_corner, p_tangent_end, col_mark, 1.2)

			# 内侧卷曲回纹：从 L 形拐点向外卷 180° 小弧
			var curl_center := p_corner + radial * 2.0 * scale_f + tangent * 2.0 * scale_f
			var curl_r := 1.8 * scale_f
			AdaptiveDraw.arc(self, curl_center, curl_r, ang + PI * 0.5, ang + PI * 1.5, col_curl, 0.9)

	# --------------------------------------------------------------------------
	# 3.2 结界灵枢符印底座（菱形暗色填色；描边/核心脉冲留在宿主 10Hz 动态层）
	# --------------------------------------------------------------------------
	func _draw_talisman_diamonds() -> void:
		var h: float = half
		var node_spacing := 68.0
		var node_count := int((h * 2.0 - 180.0) / node_spacing)
		var node_start := -h + 90.0 + (h * 2.0 - 180.0 - float(node_count) * node_spacing) * 0.5
		var r_dist: float = h - 14.0

		for n_idx in node_count + 1:
			var pos_coord := node_start + float(n_idx) * node_spacing
			var node_positions := [
				Vector2(pos_coord, -r_dist),
				Vector2(r_dist, pos_coord),
				Vector2(pos_coord, r_dist),
				Vector2(-r_dist, pos_coord),
			]
			for n_pos in node_positions:
				var d_r := 3.2
				var diamond := PackedVector2Array([
					n_pos + Vector2(0, -d_r * 1.3),
					n_pos + Vector2(d_r, 0),
					n_pos + Vector2(0, d_r * 1.3),
					n_pos + Vector2(-d_r, 0),
					n_pos + Vector2(0, -d_r * 1.3)
				])
				draw_colored_polygon(diamond, Color(0.04, 0.09, 0.14, 0.9))
