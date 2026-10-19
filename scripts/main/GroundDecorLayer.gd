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
# 3. 战场地面细节（青苔暗斑、石板角刻纹、灵叶结晶）
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
	var col_moss := Color(0.10, 0.24, 0.18, 0.14)
	var col_moss_inner := Color(0.14, 0.32, 0.22, 0.18)
	for _i in range(10):
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
