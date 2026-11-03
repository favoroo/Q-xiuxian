class_name GroundDecorLayer
extends Node2D

## 竞技场战台地面微细节（空洞冷冽国风）
## 2026-10-19 风格统一改造：删去石板裂缝/战痕剑痕/碎石瓦砾（与程序化青玉石板底
## 「干净打磨」气质冲突），只留灵叶结晶与石板角刻纹两样细刻纹点缀。
## 2026-10-21：青苔暗斑（十八组 + 四角苔藓丛）在青玉地砖上读成一团团黑圆斑，用户嫌丑，整段移除。
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

	_draw_ground_details(rng)

# ==============================================================================
# 3. 战场地面细节（石板角刻纹、灵叶结晶）
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

	# 3.1 青苔与风化暗斑：2026-10-21 用户反馈「地图上一堆黑黑的圆点太丑」——
	# 半透明深绿/近黑的叠圆在青玉地砖上被读成一团团黑斑，与「干净打磨玉面」气质冲突，整段移除。
	# （原 3.1 十八组苔藓 + 3.1.1 四角苔藓丛，见 CHANGELOG 2026-10-21 #03 的「精致化」条目）

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
