class_name ArenaVisualLayer
extends Node2D

## 竞技场战台程序化矢量装饰与九天锁灵结界（空洞冷冽国风）
## 涵盖中心太极四象大阵、四方灵脉刻槽、九幽边界锁灵结界光幕与四角镇魂阵角

var _time: float = 0.0
var half_extent: float = 680.0

func _ready() -> void:
	z_index = 1  # 位于地砖 TextureRect 之上，实体层与判定物之下

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func _draw() -> void:
	_draw_central_taiji_array()
	_draw_array_conduits()
	_draw_sanctum_barrier()

# ==============================================================================
# 1. 中心太极四象大阵（Central Taiji & Quad Array）
# ==============================================================================
func _draw_central_taiji_array() -> void:
	var r_outer: float = 220.0
	var r_mid: float = 140.0
	var r_inner: float = 68.0

	# 柔和灵脉呼吸（低对比度，确保绝对不抢战斗视线）
	var breath: float = sin(_time * 0.8) * 0.04 + 0.22
	var col_cyan := Color(0.25, 0.70, 0.90, breath)
	var col_gold := Color(0.85, 0.70, 0.25, breath * 0.85)
	var col_dark := Color(0.08, 0.15, 0.24, breath * 0.6)

	# 极慢灵脉自转（每 90 秒转一圈，如同天地运转）
	var rot: float = _time * 0.07
	draw_set_transform(Vector2.ZERO, rot, Vector2.ONE)

	# 外同心双环
	draw_arc(Vector2.ZERO, r_outer, 0.0, TAU, 72, col_cyan, 1.8, true)
	draw_arc(Vector2.ZERO, r_outer - 8.0, 0.0, TAU, 72, col_dark, 1.0, true)

	# 12 方位天干地支刻印点
	for i in range(12):
		var a := (TAU / 12.0) * float(i)
		var p_node := Vector2(cos(a), sin(a)) * (r_outer - 4.0)
		draw_circle(p_node, 1.8, col_gold)

	# 中阵环（四象象限与八卦爻刻）
	draw_arc(Vector2.ZERO, r_mid, 0.0, TAU, 64, col_dark, 1.2, true)
	for j in range(8):
		var b := (TAU / 8.0) * float(j)
		var dir := Vector2(cos(b), sin(b))
		draw_line(dir * (r_inner + 8.0), dir * (r_mid - 6.0), col_cyan * 0.8, 1.0)
		# 八卦爻位短横
		var p_mid := dir * r_mid
		draw_line(p_mid - dir.orthogonal() * 4.0, p_mid + dir.orthogonal() * 4.0, col_gold, 1.4)

	# 内阵核：太极双鱼图腾
	draw_arc(Vector2.ZERO, r_inner, 0.0, TAU, 48, col_cyan, 1.5, true)

	# 阴阳鱼 S 曲线刻线
	var s_pts := PackedVector2Array()
	var s_steps := 20
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
	var col_flow := Color(0.20, 0.75, 0.95, flow_alpha)

	# 指向三座界碑大致方向的微暗地表槽纹（长 460px）
	var arms := [
		[Vector2(0, -220), Vector2(0, -460)],       # 北向（中心碑）
		[Vector2(220, 0), Vector2(460, -220)],      # 东北向（东碑）
		[Vector2(-220, 0), Vector2(-460, 220)],     # 西南向（西碑）
		[Vector2(0, 220), Vector2(0, 460)]          # 南向
	]
	for arm in arms:
		var p1: Vector2 = arm[0]
		var p2: Vector2 = arm[1]
		# 阴影深槽
		draw_line(p1, p2, col_trough, 4.0)
		# 灵流
		draw_line(p1, p2, col_flow, 1.5)

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

	# 3.2 锁灵结界流光丝（幽蓝呼吸）
	var pulse_glow := sin(_time * 2.0) * 0.15 + 0.85
	var col_barrier := Color(0.25, 0.80, 1.0, 0.85 * pulse_glow)
	var col_inner_gold := Color(0.90, 0.75, 0.28, 0.70)

	var inner_rect := [
		Vector2(-h + 8.0, -h + 8.0), Vector2(h - 8.0, -h + 8.0),
		Vector2(h - 8.0, h - 8.0), Vector2(-h + 8.0, h - 8.0),
		Vector2(-h + 8.0, -h + 8.0)
	]
	# 结界主光丝
	draw_polyline(PackedVector2Array(inner_rect), col_barrier, 3.5)
	# 内侧鎏金暗引线
	var gold_rect := [
		Vector2(-h + 14.0, -h + 14.0), Vector2(h - 14.0, -h + 14.0),
		Vector2(h - 14.0, h - 14.0), Vector2(-h + 14.0, h - 14.0),
		Vector2(-h + 14.0, -h + 14.0)
	]
	draw_polyline(PackedVector2Array(gold_rect), col_inner_gold, 1.2)

	# 3.3 四角「青铜镇魂阵角」
	var corner_len: float = 95.0
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
