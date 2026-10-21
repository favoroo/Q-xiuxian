class_name GroundDecorLayer
extends Node2D

## 竞技场战台地面微细节（空洞冷冽国风）
## 2026-10-19 风格统一改造：删去石板裂缝/战痕剑痕/碎石瓦砾（与程序化青玉石板底
## 「干净打磨」气质冲突），只留青苔暗斑、灵叶结晶与石板角刻纹三样细刻纹点缀。
## （结界外深渊剪影已拆到 BeyondBoundaryLayer 做视差，见 Main._setup_map_bounds）
## 纯静态一次性 _draw()，不参与 _process，零每帧开销。
## 【注意】2026-10-16：draw_circle 全量接 AdaptiveDraw 自适应段数——内置版固定 64 段，
##   本层小点曾单独吃掉 ~14.6k 图元（面板「图元 21.0k」的大头）。

var half_extent: float = 480.0

func _ready() -> void:
	# 位于 MapLayer 内，靠树顺序排在地砖之上、ArenaVisualLayer 之下；z_index 保持 0 不越过实体层
	z_index = 0

func _draw() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4217  # 固定种子确保装饰确定性，不占用或污染 GameManager.rng 战斗流

	_draw_spirit_vein_tint()
	_draw_array_outer_runes()
	_draw_bagua_marks()
	_draw_ground_details(rng)
	_draw_obelisk_ground_rings()

# ==============================================================================
# 2. 太极阵外延展符纹刻度（Outer Array Extension Runes）
# ==============================================================================
func _draw_array_outer_runes() -> void:
	# 在太极古阵外环（r_outer=145）外围点缀一层古朴刻纹与虚线导引
	var col_dark_tick := Color(0.06, 0.12, 0.18, 0.45)
	var col_cyan_tick := Color(0.25, 0.65, 0.85, 0.20)
	var col_gold_dot := Color(0.85, 0.70, 0.25, 0.25)

	# 虚线外导引环 (标准半场 440 下 r=168，随 half_extent 等比缩放，确保始终位于太极外环 r_outer=145*scale_f 外围)
	var scale_f := half_extent / 440.0
	var r_guide: float = 168.0 * scale_f
	AdaptiveDraw.arc(self, Vector2.ZERO, r_guide, 0.0, TAU, col_dark_tick, 1.0)

	# 24 节气辐射刻度齿
	for i in range(24):
		var ang := (TAU / 24.0) * float(i)
		var dir := Vector2(cos(ang), sin(ang))
		var is_major := (i % 3 == 0)
		var len_tick := 10.0 if is_major else 5.0
		var c_tick := col_cyan_tick if is_major else col_dark_tick
		draw_line(dir * (r_guide - 4.0), dir * (r_guide + len_tick), c_tick, 1.2 if is_major else 0.8)
		if is_major:
			AdaptiveDraw.circle(self, dir * (r_guide + len_tick + 4.0), 1.6, col_gold_dot)

# ==============================================================================
# 1.5 灵脉沁色带（Spirit Vein Tint）：太极阵中心沿四正方位延伸的极淡青色晕染
# ==============================================================================
## 每条沁色带是柔边四边形渐变（中心浓、外端淡），像灵气沿地脉渗出，压在整个地面细节
## 之下（最先绘制），作为整体氛围的底色衬底，绝不抢眼。
func _draw_spirit_vein_tint() -> void:
	var scale_f := half_extent / 440.0
	var col_vein_core := Color(0.25, 0.65, 0.85, 0.06)  # 灵脉核心青玉色，极淡
	var col_vein_edge := Color(0.25, 0.65, 0.85, 0.015) # 外缘衰减到几乎不可见

	# 四正方位（东南西北），每向 2 条沁色带（主带 + 副带偏移），总长 ~380*scale_f
	var reach := 380.0 * scale_f
	var half_w_main := 28.0 * scale_f   # 主带半宽
	var half_w_sub := 18.0 * scale_f    # 副带半宽

	for dir_idx in range(4):
		var ang := PI * 0.5 * float(dir_idx)
		var dir := Vector2(cos(ang), sin(ang))
		var ortho := dir.orthogonal()

		# 主沁色带（从太极阵外环外 160*scale_f 开始，延伸到 reach）
		var start_main := 160.0 * scale_f
		var p0: Vector2 = dir * start_main + ortho * half_w_main
		var p1: Vector2 = dir * start_main - ortho * half_w_main
		var p2: Vector2 = dir * reach - ortho * half_w_main * 0.3
		var p3: Vector2 = dir * reach + ortho * half_w_main * 0.3
		# 分 6 段做径向渐变（每段 alpha 线性衰减）
		const SEGS := 6
		for s in range(SEGS):
			var t0 := float(s) / float(SEGS)
			var t1 := float(s + 1) / float(SEGS)
			var a0 := lerpf(col_vein_core.a, col_vein_edge.a, t0)
			var a1 := lerpf(col_vein_core.a, col_vein_edge.a, t1)
			var q0: Vector2 = p0.lerp(p3, t0)
			var q1: Vector2 = p1.lerp(p2, t0)
			var q2: Vector2 = p1.lerp(p2, t1)
			var q3: Vector2 = p0.lerp(p3, t1)
			var col_seg := Color(col_vein_core, (a0 + a1) * 0.5)
			draw_colored_polygon(PackedVector2Array([q0, q1, q2, q3]), col_seg)

		# 副沁色带（偏移 45° 角向两侧偏移，短一些、淡一些）
		for side in [-1.0, 1.0]:
			var side_f: float = side
			var off_ang: float = ang + side_f * (PI / 4.0)
			var off_dir := Vector2(cos(off_ang), sin(off_ang))
			var start_sub := 200.0 * scale_f
			var reach_sub := 320.0 * scale_f
			var r0: Vector2 = off_dir * start_sub + ortho * half_w_sub * side_f
			var r1: Vector2 = off_dir * start_sub - ortho * half_w_sub * side_f
			var r2: Vector2 = off_dir * reach_sub - ortho * half_w_sub * side_f * 0.4
			var r3: Vector2 = off_dir * reach_sub + ortho * half_w_sub * side_f * 0.4
			for s in range(SEGS):
				var t0 := float(s) / float(SEGS)
				var t1 := float(s + 1) / float(SEGS)
				var a0 := lerpf(col_vein_core.a * 0.6, 0.0, t0)
				var a1 := lerpf(col_vein_core.a * 0.6, 0.0, t1)
				var q0: Vector2 = r0.lerp(r3, t0)
				var q1: Vector2 = r1.lerp(r2, t0)
				var q2: Vector2 = r1.lerp(r2, t1)
				var q3: Vector2 = r0.lerp(r3, t1)
				var col_seg := Color(col_vein_core, (a0 + a1) * 0.5)
				draw_colored_polygon(PackedVector2Array([q0, q1, q2, q3]), col_seg)

# ==============================================================================
# 2.5 太极阵外圈八卦卦象刻印（Bagua Marks）：8 方位各一组三爻卦
# ==============================================================================
## 在太极阵外环 r=145 与导引环 r=168 之间的环带内，按 8 方位刻八卦（乾坤震巽坎离艮兑）。
## 阳爻为整段横线，阴爻为中间断开的两段。青玉描线 + 暗金定位点，古朴内敛。
func _draw_bagua_marks() -> void:
	var scale_f := half_extent / 440.0
	var r_center: float = 156.0 * scale_f  # 卦象中心环带半径（位于 145 与 168 之间）
	var col_trigram := Color(0.25, 0.65, 0.85, 0.18)
	var col_anchor := Color(0.85, 0.70, 0.25, 0.22)

	# 八卦三爻组合（每卦三条线，true=阳爻整线，false=阴爻断线），顺序对应 8 方位
	# 顺序：乾(☰) 兑(☱) 离(☲) 震(☳) 巽(☴) 坎(☵) 艮(☶) 坤(☷)
	var bagua: Array[Array] = [
		[true, true, true],    # 乾 ☰
		[true, true, false],   # 兑 ☱
		[true, false, true],   # 离 ☲
		[true, false, false],  # 震 ☳
		[false, true, true],   # 巽 ☴
		[false, true, false],  # 坎 ☵
		[false, false, true],  # 艮 ☶
		[false, false, false], # 坤 ☷
	]

	for i in range(8):
		var ang := (TAU / 8.0) * float(i)
		var center := Vector2(cos(ang), sin(ang)) * r_center
		var radial := Vector2(cos(ang), sin(ang))  # 径向（爻线沿径向排布）
		var tangent := radial.orthogonal()          # 切向（爻线本身沿切向延伸）

		# 三爻从外向内排列（径向间隔 4.5px），每爻长 8px（切向）
		var trigram: Array = bagua[i]
		for line_idx in range(3):
			var r_line := r_center + 4.5 * float(1 - line_idx)  # 从外向内
			var line_center := radial * r_line
			var is_yang: bool = trigram[line_idx]
			var line_len := 4.0 * scale_f

			if is_yang:
				# 阳爻：整段横线
				var p0 := line_center - tangent * line_len
				var p1 := line_center + tangent * line_len
				draw_line(p0, p1, col_trigram, 1.2)
			else:
				# 阴爻：中间断开的两段
				var gap := 1.2 * scale_f
				var p0 := line_center - tangent * line_len
				var p1 := line_center - tangent * gap
				var p2 := line_center + tangent * gap
				var p3 := line_center + tangent * line_len
				draw_line(p0, p1, col_trigram, 1.2)
				draw_line(p2, p3, col_trigram, 1.2)

		# 卦象中心外侧一枚暗金定位点（在导引环外侧，标识方位）
		var anchor_pos := radial * (r_center + 10.0 * scale_f)
		AdaptiveDraw.circle(self, anchor_pos, 1.4, col_anchor)

# ==============================================================================
# 4. 界碑脚下阵法光圈（Obelisk Ground Rings）：与中心太极阵呼应的小型阵法
# ==============================================================================
## 三座界碑（中心碑 + 东西翼碑）脚下各画一圈小型阵法环：双层同心圆 + 8 方位刻度点，
## 让界碑与地面的视觉连接更紧密，强化「阵法节点」的语义。
func _draw_obelisk_ground_rings() -> void:
	var col_ring := Color(0.25, 0.65, 0.85, 0.16)
	var col_tick := Color(0.85, 0.70, 0.25, 0.20)
	var col_inner := Color(0.08, 0.15, 0.24, 0.30)

	## 与 Main.tscn 三座碑体真实落点对齐（2026-10-21 修正：原先偏了 19~54px，地环与碑体错位）
	var obelisk_positions: Array[Vector2] = [
		Vector2(0, -116),
		Vector2(326, -153),
		Vector2(-326, 153),
	]

	for ob_pos in obelisk_positions:
		var r_outer := 52.0
		var r_inner := 46.0

		# 外环（青玉）+ 内环（暗青填色）
		AdaptiveDraw.arc(self, ob_pos, r_outer, 0.0, TAU, col_ring, 1.2)
		AdaptiveDraw.arc(self, ob_pos, r_inner, 0.0, TAU, col_inner, 0.8)

		# 8 方位刻度点（暗金小点，嵌在两环之间）
		for k in range(8):
			var a := (TAU / 8.0) * float(k)
			var tick_pos := ob_pos + Vector2(cos(a), sin(a)) * ((r_outer + r_inner) * 0.5)
			AdaptiveDraw.circle(self, tick_pos, 1.0, col_tick)

# ==============================================================================
# 3. 战场地面细节（青苔暗斑、石板角刻纹、灵叶结晶）
# ==============================================================================
func _draw_ground_details(rng: RandomNumberGenerator) -> void:
	var scale_f := half_extent / 440.0
	# 避位区检查：中心阵（随 scale_f 动态调整）、三座界碑坐标与四灵脉主走廊
	var obstacles: Array[Dictionary] = [
		{"pos": Vector2.ZERO, "r": 200.0 * scale_f},
		{"pos": Vector2(0, -116), "r": 85.0},
		{"pos": Vector2(326, -153), "r": 85.0},
		{"pos": Vector2(-326, 153), "r": 85.0},
	]

	var conduit_reach := 320.0 * scale_f
	var can_place := func(pos: Vector2, min_dist: float) -> bool:
		for ob in obstacles:
			if pos.distance_to(ob.pos) < (ob.r + min_dist):
				return false
		# 避开四条导灵脉（水平和垂直轴心主线）
		if (absf(pos.x) < 26.0 and absf(pos.y) < conduit_reach):
			return false
		if (absf(pos.y) < 26.0 and absf(pos.x) < conduit_reach):
			return false
		return true

	var margin: float = 38.0
	var bound: float = half_extent - margin

	# 3.1 青苔与风化暗斑 (Ancient Moss & Weathering)
	# 2026-10-21 精致化：10→18 组提升密度，四角额外加 4 簇「苔藓丛」增强边缘岁月感
	var col_moss := Color(0.10, 0.24, 0.18, 0.14)
	var col_moss_inner := Color(0.14, 0.32, 0.22, 0.18)
	for _i in range(18):
		var p := Vector2(rng.randf_range(-bound, bound), rng.randf_range(-bound, bound))
		if not can_place.call(p, 10.0):
			continue
		var base_r := rng.randf_range(8.0, 18.0)
		var sub_count := rng.randi_range(3, 5)
		for _j in range(sub_count):
			var offset := Vector2(rng.randf_range(-base_r * 0.7, base_r * 0.7), rng.randf_range(-base_r * 0.7, base_r * 0.7))
			var r_sub := rng.randf_range(base_r * 0.4, base_r * 0.8)
			AdaptiveDraw.circle(self, p + offset, r_sub, col_moss)
		AdaptiveDraw.circle(self, p, base_r * 0.4, col_moss_inner)

	# 3.1.1 四角苔藓丛（战台四角远离中心走廊，岁月侵蚀感更重）
	# 每角一簇 6~8 个子圆的密集苔藓群，位置在四角向内偏移 60~100px 的区域
	var corner_offsets: Array[Vector2] = [
		Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)
	]
	for corner_sign in corner_offsets:
		var corner_base := Vector2(
			corner_sign.x * rng.randf_range(half_extent - 160.0, half_extent - 80.0),
			corner_sign.y * rng.randf_range(half_extent - 160.0, half_extent - 80.0)
		)
		if not can_place.call(corner_base, 20.0):
			continue
		var cluster_count := rng.randi_range(6, 8)
		for _j in range(cluster_count):
			var offset := Vector2(rng.randf_range(-28.0, 28.0), rng.randf_range(-28.0, 28.0))
			var r_sub := rng.randf_range(4.0, 10.0)
			AdaptiveDraw.circle(self, corner_base + offset, r_sub, col_moss)
		# 丛中心一块稍亮的苔藓核心
		AdaptiveDraw.circle(self, corner_base, 8.0, col_moss_inner)

	# 3.2 石板角刻纹（与 ground_tile.gdshader 的 160px 石板网格对齐：
	# 每个石板交点画一枚极小回纹角花，代替旧版随机石板裂缝的「打磨刻度」）
	var col_engrave := Color(0.06, 0.10, 0.13, 0.30)
	var col_engrave_lit := Color(0.30, 0.55, 0.68, 0.10)
	var tile_step := 160.0
	var arm := 7.0
	var grid_n := int(bound / tile_step)
	for gx in range(-grid_n, grid_n + 1):
		for gy in range(-grid_n, grid_n + 1):
			var corner := Vector2(float(gx), float(gy)) * tile_step
			if not can_place.call(corner, 6.0):
				continue
			# 每格交点四角各一 L 形刻角，指向石板内侧
			for sx in [-1.0, 1.0]:
				for sy in [-1.0, 1.0]:
					var base := corner + Vector2(sx * 2.5, sy * 2.5)
					draw_line(base, base + Vector2(sx * arm, 0.0), col_engrave, 1.0)
					draw_line(base, base + Vector2(0.0, sy * arm), col_engrave, 1.0)
			# 中心一点微弱冷光，像玉面磨出的高光
			AdaptiveDraw.circle(self, corner, 0.9, col_engrave_lit)

	# 3.3 散落灵木落叶与灵气结晶点 (Fallen Petals & Jade Motes)
	var col_petal_cyan := Color(0.40, 0.82, 0.95, 0.22)
	var col_petal_gold := Color(0.92, 0.80, 0.40, 0.16)
	for _i in range(12):
		var p_leaf := Vector2(rng.randf_range(-bound, bound), rng.randf_range(-bound, bound))
		if not can_place.call(p_leaf, 6.0):
			continue
		var rot_ang := rng.randf_range(0.0, TAU)
		var dir_l := Vector2(cos(rot_ang), sin(rot_ang))
		var norm_l := dir_l.orthogonal()
		var l_len := rng.randf_range(2.4, 4.0)
		var l_w := rng.randf_range(1.0, 1.8)
		var pts_leaf := PackedVector2Array([
			p_leaf + dir_l * l_len,
			p_leaf + norm_l * l_w,
			p_leaf - dir_l * (l_len * 0.6),
			p_leaf - norm_l * l_w
		])
		var c_leaf := col_petal_cyan if (rng.randf() > 0.3) else col_petal_gold
		draw_colored_polygon(pts_leaf, c_leaf)
