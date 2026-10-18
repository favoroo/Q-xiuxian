class_name GroundDecorLayer
extends Node2D

## 竞技场战台地面微细节（空洞冷冽国风）
## 涵盖石板暗纹裂缝、青苔风化暗斑、战痕剑痕、碎石瓦砾、阵外延展符纹。
## （结界外深渊剪影已拆到 BeyondBoundaryLayer 做视差，见 Main._setup_map_bounds）
## 纯静态一次性 _draw()，不参与 _process，零每帧开销。
## 【注意】2026-10-16：draw_circle 全量接 AdaptiveDraw 自适应段数——内置版固定 64 段，
##   本层 ~116 个 0.8~1.6px 小点曾单独吃掉 ~14.6k 图元（面板「图元 21.0k」的大头）。

var half_extent: float = 480.0

func _ready() -> void:
	# 位于 MapLayer 内，靠树顺序排在地砖之上、ArenaVisualLayer 之下；z_index 保持 0 不越过实体层
	z_index = 0

func _draw() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4217  # 固定种子确保装饰确定性，不占用或污染 GameManager.rng 战斗流

	_draw_array_outer_runes()
	_draw_ground_details(rng)

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
# 3. 战场地面细节（石板裂纹、青苔暗斑、剑痕、碎石、落瓣）
# ==============================================================================
func _draw_ground_details(rng: RandomNumberGenerator) -> void:
	var scale_f := half_extent / 440.0
	# 避位区检查：中心阵（随 scale_f 动态调整）、三座界碑坐标与四灵脉主走廊
	var obstacles: Array[Dictionary] = [
		{"pos": Vector2.ZERO, "r": 200.0 * scale_f},
		{"pos": Vector2(0, -135), "r": 85.0},
		{"pos": Vector2(380, -178), "r": 85.0},
		{"pos": Vector2(-380, 178), "r": 85.0},
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
			AdaptiveDraw.circle(self, p + offset, r_sub, col_moss)
		AdaptiveDraw.circle(self, p, base_r * 0.4, col_moss_inner)

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
		AdaptiveDraw.circle(self, pos_peb + Vector2(0.0, -peb_size * 0.4), 0.8, col_pebble_rim)

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
