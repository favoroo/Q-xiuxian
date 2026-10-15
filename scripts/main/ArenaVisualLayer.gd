class_name ArenaVisualLayer
extends Node2D

## 竞技场战台程序化矢量装饰与九天锁灵结界（空洞冷冽国风）
## 涵盖中心太极四象大阵、四方灵脉刻槽、九幽边界锁灵结界光幕与四角镇魂阵角
## ⚠ T-4A（2026-10-15）：结界主光丝改 BoundaryFlowBand 流光带（shader TIME 驱动，零 CPU 重绘），
##   灵脉刻槽接 GameStyle.FX_HDR_WATER 低档 + 6s 呼吸；太极阵/刻槽/镇魂阵角仍走本层 _draw。

const BOUNDARY_FLOW_SHADER := preload("res://assets/shaders/boundary_flow.gdshader")

var _time: float = 0.0
var half_extent: float = 440.0
var _flow_bands: Array[BoundaryFlowBand] = []

## 重绘节流（2026-10-11 第 6 波卡顿优化，2026-10-14 再降）：本层动画全是慢速量
## （灵脉 90s/圈自转 + 呼吸正弦 + 结界脉冲），10Hz 重绘肉眼无感 —— 高频重绘是白烧。
const REDRAW_INTERVAL := 0.1
var _redraw_timer: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 保持 z_index = 0：位于 MapLayer 内，靠树顺序排在地砖与地面微细节之上；
	# 绝不设 >0（实体层 EntitiesLayer 及其角色默认为 z=0，设 >0 会直接盖在玩家身体上）
	z_index = 0

func _process(delta: float) -> void:
	# _time 逐帧累计不节流，重绘触发时取到的是当前时刻，动画不会因节流变卡
	_time += delta
	_ensure_visibility()
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
	_draw_array_conduits()
	_draw_sanctum_barrier()

## 结界流光带懒挂载：首次 _draw（half_extent 已由 Main 定值）时创建，
## 三条与主光丝同长的梯形带（上下左右），shader TIME 驱动，之后 CPU 零重绘。
func _ensure_flow_bands() -> void:
	if not _flow_bands.is_empty():
		return
	var mat := ShaderMaterial.new()
	mat.shader = BOUNDARY_FLOW_SHADER
	for seg in 4:
		var band := BoundaryFlowBand.new()
		band.segment = seg
		band.half = half_extent
		band.material = mat
		band.visible = false  # _ensure_visibility 定位后再亮
		add_child(band)
		_flow_bands.append(band)

# ==============================================================================
# 1. 中心太极四象大阵（Central Taiji & Quad Array）
# ==============================================================================
func _draw_central_taiji_array() -> void:
	# 三圈半径与灵脉刻槽端点随 2026-10-12 缩图（半场 500→440）等比收缩
	var r_outer: float = 145.0
	var r_mid: float = 92.0
	var r_inner: float = 44.0

	# 柔和灵脉呼吸（低对比度，确保绝对不抢战斗视线）
	var breath: float = sin(_time * 0.8) * 0.04 + 0.22
	var col_cyan := Color(0.25, 0.70, 0.90, breath)
	var col_gold := Color(0.85, 0.70, 0.25, breath * 0.85)
	var col_dark := Color(0.08, 0.15, 0.24, breath * 0.6)

	# 极慢灵脉自转（每 90 秒转一圈，如同天地运转）
	var rot: float = _time * 0.07
	draw_set_transform(Vector2.ZERO, rot, Vector2.ONE)

	# 外同心双环（弧段按半径自适应修剪：145px 半径 48 段已远超肉眼分辨）
	draw_arc(Vector2.ZERO, r_outer, 0.0, TAU, 48, col_cyan, 1.8, true)
	draw_arc(Vector2.ZERO, r_outer - 8.0, 0.0, TAU, 48, col_dark, 1.0, true)

	# 12 方位天干地支刻印点
	for i in range(12):
		var a := (TAU / 12.0) * float(i)
		var p_node := Vector2(cos(a), sin(a)) * (r_outer - 4.0)
		draw_circle(p_node, 1.8, col_gold)

	# 中阵环（四象象限与八卦爻刻）
	draw_arc(Vector2.ZERO, r_mid, 0.0, TAU, 40, col_dark, 1.2, true)
	for j in range(8):
		var b := (TAU / 8.0) * float(j)
		var dir := Vector2(cos(b), sin(b))
		draw_line(dir * (r_inner + 8.0), dir * (r_mid - 6.0), col_cyan * 0.8, 1.0)
		# 八卦爻位短横
		var p_mid := dir * r_mid
		draw_line(p_mid - dir.orthogonal() * 4.0, p_mid + dir.orthogonal() * 4.0, col_gold, 1.4)

	# 内阵核：太极双鱼图腾
	draw_arc(Vector2.ZERO, r_inner, 0.0, TAU, 28, col_cyan, 1.5, true)

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
	draw_circle(Vector2(0, -r_inner * 0.5), 3.5, col_cyan)
	draw_circle(Vector2(0, r_inner * 0.5), 3.5, col_dark)
	draw_circle(Vector2(0, r_inner * 0.5), 1.5, col_gold)

	# 还原坐标系
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ==============================================================================
# 2. 四方灵脉刻槽（Conduits Leading to Obelisks）
# ==============================================================================
func _draw_array_conduits() -> void:
	var flow_alpha: float = (sin(_time * 1.5) * 0.5 + 0.5) * 0.15 + 0.10
	var col_trough := Color(0.04, 0.08, 0.12, 0.7)
	# T-4.4 灵脉刻槽 HDR 脉动：灵流接 GameStyle.FX_HDR_WATER 灵蓝超白低档（alpha 压低、仅槽内起细辉），
	# 6s 周期明灭呼吸（振幅 ≤30% alpha，慢速量沿既有 10Hz 重绘通道改色值，零新节点）
	var hdr_breath: float = sin(_time * TAU / 6.0) * 0.12 + 0.76
	var col_flow := Color(0.20, 0.75, 0.95, flow_alpha)
	var col_hdr := GameStyle.FX_HDR_WATER
	col_hdr.a = flow_alpha * hdr_breath

	# 指向三座界碑大致方向的微暗地表槽纹（东北/西南端点与 Main.tscn 祭坛坐标严格一致）
	var arms := [
		[Vector2(0, -145), Vector2(0, -300)],        # 北向（中心碑）
		[Vector2(145, 0), Vector2(300, -140)],       # 东北向（东碑）
		[Vector2(-145, 0), Vector2(-300, 140)],      # 西南向（西碑）
		[Vector2(0, 145), Vector2(0, 300)]           # 南向
	]
	for arm in arms:
		var p1: Vector2 = arm[0]
		var p2: Vector2 = arm[1]
		# 阴影深槽
		draw_line(p1, p2, col_trough, 4.0)
		# 灵流（底色铺槽）
		draw_line(p1, p2, col_flow, 1.5)
		# HDR 起辉芯线（细 0.4px，只在槽内泛光，不外溢糊边界）
		draw_line(p1, p2, col_hdr, 1.1)

# ==============================================================================
# 3. 九天锁灵结界光墙与四角镇魂阵角（Sanctum Barrier）
# ==============================================================================
func _draw_sanctum_barrier() -> void:
	var h: float = half_extent

	# 3.1 外层玄铁界石基线（深沉稳固）
	var outer_rect := [
		Vector2(-h, -h), Vector2(h, -h),
		Vector2(h, h), Vector2(-h, h),
		Vector2(-h, -h)
	]
	draw_polyline(PackedVector2Array(outer_rect), Color(0.03, 0.05, 0.08, 0.95), 18.0)

	# 3.2 锁灵结界流光丝（T-4.1：主光丝改 BoundaryFlowBand 流光带承担，shader 流光沿法阵转动；
	# 此处保留内金色引线等静态衬托，脉冲色值供带子底色参考注释）
	# var pulse_glow := sin(_time * 2.0) * 0.15 + 0.85  # 已由 shader 内呼吸接管
	var col_inner_gold := Color(0.90, 0.75, 0.28, 0.70)

	# 内侧鎏金暗引线
	var gold_rect := [
		Vector2(-h + 14.0, -h + 14.0), Vector2(h - 14.0, -h + 14.0),
		Vector2(h - 14.0, h - 14.0), Vector2(-h + 14.0, h - 14.0),
		Vector2(-h + 14.0, -h + 14.0)
	]
	draw_polyline(PackedVector2Array(gold_rect), col_inner_gold, 1.2)

	# 3.3 四角「青铜镇魂阵角」
	var corner_len: float = 82.0
	var corners := [
		[Vector2(-h + 12.0, -h + 12.0), Vector2(1, 1)],
		[Vector2(h - 12.0, -h + 12.0), Vector2(-1, 1)],
		[Vector2(h - 12.0, h - 12.0), Vector2(-1, -1)],
		[Vector2(-h + 12.0, h - 12.0), Vector2(1, -1)]
	]
	for c in corners:
		var pos: Vector2 = c[0]
		var sgn: Vector2 = c[1]
		var pts := PackedVector2Array([
			pos + Vector2(0, sgn.y * corner_len),
			pos,
			pos + Vector2(sgn.x * corner_len, 0)
		])
		# 青铜厚底
		draw_polyline(pts, Color(0.06, 0.10, 0.16, 0.95), 10.0, true)
		# 翡翠青玉锁魂线
		draw_polyline(pts, Color(0.20, 0.85, 0.65, 0.9), 4.5, true)
		# 角端镇魂金钉
		draw_circle(pos, 5.0, Color(1.0, 0.85, 0.35, 0.95))
		draw_circle(pos, 2.5, Color(1.0, 1.0, 1.0, 0.95))

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
	var half: float = 440.0
	var _built_half: float = -1.0  # 顶点缓存：half 未变不重建

	func _process(_delta: float) -> void:
		if is_equal_approx(half, _built_half):
			return
		_built_half = half
		var e := half - 8.0   # 与原 inner_rect 内缩量一致
		var i := half - 20.0  # 带宽 12px
		var quad := PackedVector2Array()
		var uvs := PackedVector2Array()
		match segment:
			0:  # 上：左→右，UV.x 沿周长 [0, 0.25]
				quad = PackedVector2Array([Vector2(-e, -e), Vector2(e, -e), Vector2(e, -i), Vector2(-e, -i)])
				uvs = PackedVector2Array([Vector2(0.0, 0), Vector2(0.25, 0), Vector2(0.25, 1), Vector2(0.0, 1)])
			1:  # 右：上→下 [0.25, 0.5]
				quad = PackedVector2Array([Vector2(e, -e), Vector2(e, e), Vector2(i, e), Vector2(i, -e)])
				uvs = PackedVector2Array([Vector2(0.25, 0), Vector2(0.5, 0), Vector2(0.5, 1), Vector2(0.25, 1)])
			2:  # 下：右→左 [0.5, 0.75]
				quad = PackedVector2Array([Vector2(e, e), Vector2(-e, e), Vector2(-e, i), Vector2(e, i)])
				uvs = PackedVector2Array([Vector2(0.5, 0), Vector2(0.75, 0), Vector2(0.75, 1), Vector2(0.5, 1)])
			3:  # 左：下→上 [0.75, 1.0]
				quad = PackedVector2Array([Vector2(-e, e), Vector2(-e, -e), Vector2(-i, -e), Vector2(-i, e)])
				uvs = PackedVector2Array([Vector2(0.75, 0), Vector2(1.0, 0), Vector2(1.0, 1), Vector2(0.75, 1)])
		polygon = quad
		uv = uvs
