class_name GroundDecorLayer
extends Node2D

## 竞技场战台地面微细节与结界外深渊远景（空洞冷冽国风）
## 涵盖石板暗纹裂缝、青苔风化暗斑、战痕剑痕、碎石瓦砾、阵外延展符纹、
## 以及结界外部深渊中若隐若现的古柱与峰石剪影。
## 纯静态一次性 _draw()，不参与 _process，零每帧开销。

var half_extent: float = 440.0

func _ready() -> void:
	z_index = 0  # 位于地砖 TextureRect 之上，ArenaVisualLayer(z=1) 之下

func _draw() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4217  # 固定种子确保装饰确定性，不占用或污染 GameManager.rng 战斗流

	_draw_beyond_boundary_silhouettes(rng)
	_draw_array_outer_runes()
	_draw_ground_details(rng)

# ==============================================================================
# 1. 结界外深渊远景剪影（Beyond Boundary Silhouettes）
# ==============================================================================
func _draw_beyond_boundary_silhouettes(rng: RandomNumberGenerator) -> void:
	var h: float = half_extent
	var col_shadow := Color(0.015, 0.025, 0.04, 0.95)
	var col_stone := Color(0.025, 0.04, 0.06, 0.90)
	var col_faint_cyan := Color(0.18, 0.55, 0.75, 0.14)

	# 北侧远景：幽冥残峰奇石起伏（y 在 -450 ~ -680 之间）
	var north_pts := PackedVector2Array()
	north_pts.append(Vector2(-h - 180.0, -h - 20.0))
	var peak_x: float = -h - 180.0
	while peak_x < h + 180.0:
		var step: float = rng.randf_range(35.0, 75.0)
		peak_x += step
		var peak_y: float = -h - rng.randf_range(40.0, 160.0)
		north_pts.append(Vector2(peak_x, peak_y))
	north_pts.append(Vector2(h + 180.0, -h - 20.0))
	if north_pts.size() >= 3:
		draw_colored_polygon(north_pts, col_shadow)
		draw_polyline(north_pts, col_stone, 1.5)

	# 南侧断崖远影（y 在 +450 ~ +640 之间）
	var south_pts := PackedVector2Array()
	south_pts.append(Vector2(-h - 180.0, h + 20.0))
	var s_x: float = -h - 180.0
	while s_x < h + 180.0:
		var step_s: float = rng.randf_range(40.0, 80.0)
		s_x += step_s
		var s_y: float = h + rng.randf_range(40.0, 140.0)
		south_pts.append(Vector2(s_x, s_y))
	south_pts.append(Vector2(h + 180.0, h + 20.0))
	if south_pts.size() >= 3:
		draw_colored_polygon(south_pts, col_shadow)
		draw_polyline(south_pts, col_stone, 1.5)

	# 东西两侧深渊中矗立的古刹残柱剪影
	var pillar_xs := [-h - 60.0, -h - 130.0, h + 60.0, h + 130.0]
	for px in pillar_xs:
		var py_base: float = rng.randf_range(-h + 60.0, h - 60.0)
		var p_w: float = rng.randf_range(20.0, 36.0)
		var p_h: float = rng.randf_range(60.0, 120.0)
		var sign_x: float = -1.0 if px < 0.0 else 1.0
		var pts := PackedVector2Array([
			Vector2(px, py_base),
			Vector2(px + sign_x * p_w * 0.4, py_base - p_h * 0.7),
			Vector2(px + sign_x * p_w * 0.8, py_base - p_h),
			Vector2(px + sign_x * p_w, py_base)
		])
		draw_colored_polygon(pts, col_stone)
		draw_polyline(pts, col_shadow, 1.5)
		# 柱顶微弱幽芒
		draw_circle(Vector2(px + sign_x * p_w * 0.8, py_base - p_h), 3.0, col_faint_cyan)

# ==============================================================================
# 2. 太极阵外延展符纹刻度（Outer Array Extension Runes）
# ==============================================================================
func _draw_array_outer_runes() -> void:
	# 在太极古阵外环（r_outer=145）外围点缀一层古朴刻纹与虚线导引
	var col_dark_tick := Color(0.06, 0.12, 0.18, 0.45)
	var col_cyan_tick := Color(0.25, 0.65, 0.85, 0.20)
	var col_gold_dot := Color(0.85, 0.70, 0.25, 0.25)

	# 虚线外导引环 (r = 168)
	var r_guide: float = 168.0
	draw_arc(Vector2.ZERO, r_guide, 0.0, TAU, 64, col_dark_tick, 1.0)

	# 24 节气辐射刻度齿
	for i in range(24):
		var ang := (TAU / 24.0) * float(i)
		var dir := Vector2(cos(ang), sin(ang))
		var is_major := (i % 3 == 0)
		var len_tick := 10.0 if is_major else 5.0
		var c_tick := col_cyan_tick if is_major else col_dark_tick
		draw_line(dir * (r_guide - 4.0), dir * (r_guide + len_tick), c_tick, 1.2 if is_major else 0.8)
		if is_major:
			draw_circle(dir * (r_guide + len_tick + 4.0), 1.6, col_gold_dot)

# ==============================================================================
# 3. 战场地面细节（石板裂纹、青苔暗斑、剑痕、碎石、落瓣）
# ==============================================================================
func _draw_ground_details(rng: RandomNumberGenerator) -> void:
	# 避位区检查：中心阵、三座界碑坐标与四灵脉主走廊
	var obstacles: Array[Dictionary] = [
		{"pos": Vector2.ZERO, "r": 180.0},
		{"pos": Vector2(0, -105), "r": 70.0},
		{"pos": Vector2(300, -140), "r": 70.0},
		{"pos": Vector2(-300, 140), "r": 70.0},
	]

	var can_place := func(pos: Vector2, min_dist: float) -> bool:
		for ob in obstacles:
			if pos.distance_to(ob.pos) < (ob.r + min_dist):
				return false
		# 避开四条导灵脉（水平和垂直轴心主线）
		if (absf(pos.x) < 26.0 and absf(pos.y) < 320.0):
			return false
		if (absf(pos.y) < 26.0 and absf(pos.x) < 320.0):
			return false
		return true

	var margin: float = 38.0
	var bound: float = half_extent - margin

	# 3.1 青苔与风化暗斑 (Ancient Moss & Weathering)
	var col_moss := Color(0.10, 0.24, 0.18, 0.18)
	var col_moss_inner := Color(0.14, 0.32, 0.22, 0.24)
	for _i in range(16):
		var p := Vector2(rng.randf_range(-bound, bound), rng.randf_range(-bound, bound))
		if not can_place.call(p, 10.0):
			continue
		var base_r := rng.randf_range(8.0, 18.0)
		var sub_count := rng.randi_range(3, 5)
		for _j in range(sub_count):
			var offset := Vector2(rng.randf_range(-base_r * 0.7, base_r * 0.7), rng.randf_range(-base_r * 0.7, base_r * 0.7))
			var r_sub := rng.randf_range(base_r * 0.4, base_r * 0.8)
			draw_circle(p + offset, r_sub, col_moss)
		draw_circle(p, base_r * 0.4, col_moss_inner)

	# 3.2 石板裂缝 (Stone Cracks)
	var col_crack_shadow := Color(0.03, 0.05, 0.08, 0.65)
	var col_crack_rim := Color(0.20, 0.40, 0.55, 0.16)
	for _i in range(18):
		var start_p := Vector2(rng.randf_range(-bound, bound), rng.randf_range(-bound, bound))
		if not can_place.call(start_p, 10.0):
			continue
		var pts := PackedVector2Array()
		pts.append(start_p)
		var curr := start_p
		var seg_count := rng.randi_range(2, 4)
		var dir := Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU))
		for _k in range(seg_count):
			dir = dir.rotated(rng.randf_range(-0.5, 0.5))
			var seg_len := rng.randf_range(8.0, 16.0)
			curr += dir * seg_len
			pts.append(curr)
		draw_polyline(pts, col_crack_shadow, 1.4)
		# 微弱冷月反光边
		draw_polyline(pts, col_crack_rim, 0.7)

	# 3.3 战痕与剑痕 (Battle Scratches)
	var col_scratch := Color(0.04, 0.08, 0.12, 0.55)
	var col_scratch_glint := Color(0.30, 0.60, 0.80, 0.22)
	for _i in range(12):
		var p_mid := Vector2(rng.randf_range(-bound, bound), rng.randf_range(-bound, bound))
		if not can_place.call(p_mid, 12.0):
			continue
		var angle := rng.randf_range(0.0, PI)
		var dir := Vector2(cos(angle), sin(angle))
		var len_sc := rng.randf_range(16.0, 36.0)
		draw_line(p_mid - dir * (len_sc * 0.5), p_mid + dir * (len_sc * 0.5), col_scratch, 1.2)
		draw_line(p_mid - dir * (len_sc * 0.2), p_mid + dir * (len_sc * 0.2), col_scratch_glint, 0.8)

	# 3.4 碎石瓦砾 (Pebbles & Stone Chips)
	var col_pebble_dark := Color(0.05, 0.09, 0.14, 0.85)
	var col_pebble_top := Color(0.18, 0.28, 0.38, 0.70)
	var col_pebble_rim := Color(0.35, 0.60, 0.75, 0.35)
	for _i in range(28):
		var pos_peb := Vector2(rng.randf_range(-bound, bound), rng.randf_range(-bound, bound))
		if not can_place.call(pos_peb, 8.0):
			continue
		var peb_size := rng.randf_range(2.0, 4.2)
		var peb_pts := PackedVector2Array([
			pos_peb + Vector2(-peb_size, peb_size * 0.3),
			pos_peb + Vector2(0.0, -peb_size),
			pos_peb + Vector2(peb_size * 1.1, -peb_size * 0.2),
			pos_peb + Vector2(peb_size * 0.5, peb_size * 0.8),
			pos_peb + Vector2(-peb_size * 0.6, peb_size * 0.9)
		])
		draw_colored_polygon(peb_pts, col_pebble_dark)
		# 碎石顶部冷光切面
		draw_line(pos_peb + Vector2(-peb_size * 0.5, -peb_size * 0.3), pos_peb + Vector2(peb_size * 0.5, -peb_size * 0.6), col_pebble_top, 1.0)
		draw_circle(pos_peb + Vector2(0.0, -peb_size * 0.4), 0.8, col_pebble_rim)

	# 3.5 散落灵木落叶与灵气结晶点 (Fallen Petals & Jade Motes)
	var col_petal_cyan := Color(0.40, 0.82, 0.95, 0.26)
	var col_petal_gold := Color(0.92, 0.80, 0.40, 0.20)
	for _i in range(24):
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
