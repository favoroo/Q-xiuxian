class_name ResultFx
extends Control

## 结算屏氛围层（UI 空间，挂 GameOverDialog 内、垫在面板之下）：
## victory_rain() 金色星屑雨（通关的「庆」）；defeat_gloom() 朱砂呼吸暗晕（阵亡的「哀」）。
## 自绘不走 GPUParticles：保像素硬边（无柔光），headless 判据下由调用方直接不建本层。
## 结算屏开着时整树暂停，故 process_mode = ALWAYS，_process 自己推相位。
## 【注意】T-5.2（2026-10-15）：
##   ① victory_rain 加入 GameStyle.FX_HDR_GOLD 超白起辉金色粒 + 少量大颗粒慢速飘落层次；
##   ② defeat_gloom 朱砂暗晕叠加上升墨色魂屑（4 缕冷墨带微紫，呼应 T-1.2 死亡消散）。

## 星屑上限：一批撒完不再续，多了糊屏还费 draw
const SHARD_MAX := 28
## 星屑雨总时长（秒）：到点整层自毁
const RAIN_LIFE := 3.2
## 败局暗晕墨色魂屑数量
const WISP_COUNT := 4

var _mode := &""
var _shards: Array[Dictionary] = []
var _wisps: Array[Dictionary] = []
var _age := 0.0
var _gloom_phase := 0.0

static func victory_rain(host: Control) -> ResultFx:
	var fx := _make(host)
	fx._mode = &"rain"
	fx._seed_shards()
	return fx

static func defeat_gloom(host: Control) -> ResultFx:
	var fx := _make(host)
	fx._mode = &"gloom"
	fx._seed_wisps()
	return fx

static func _make(host: Control) -> ResultFx:
	var fx := ResultFx.new()
	fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx.process_mode = Node.PROCESS_MODE_ALWAYS
	# 星屑起播时小半在屏外、暗晕全屏铺底，均非布局内容，判据放行（同 slash_wipe 惯例）
	fx.set_meta("layout_bleed", true)
	host.add_child(fx)
	host.move_child(fx, 0)
	return fx

func _seed_shards() -> void:
	var vp := get_viewport_rect().size
	if vp.x <= 0.0:
		vp = Vector2(960, 540)
	_shards.clear()
	# T-5.2 调色板：既有纸白/暖金/点缀金 + 新增 GameStyle.FX_HDR_GOLD 超白起辉金色粒
	var palette: Array[Color] = [
		GameStyle.FX_HDR_GOLD,      ## 超白浩然金（WorldEnvironment 下泛光起辉）
		GameStyle.JADE,             ## 点缀金
		GameStyle.AURUM,            ## 暖金
		GameStyle.FX_HDR_GOLD,      ## 超白浩然金
		GameStyle.PAPER,            ## 纸白
		GameStyle.GOLD_EDGE,        ## 天蓝亮边
	]
	# 分层撒播：前 6 粒为慢速大颗粒（飘落浮游层次），后 22 粒为中速中颗粒
	for i in range(SHARD_MAX):
		var is_large := (i < 6)
		var sz: float = GameManager.rng.randf_range(8.5, 13.5) if is_large else GameManager.rng.randf_range(3.0, 6.5)
		var vy: float = GameManager.rng.randf_range(65.0, 115.0) if is_large else GameManager.rng.randf_range(160.0, 270.0)
		var vx: float = GameManager.rng.randf_range(-14.0, 14.0) if is_large else GameManager.rng.randf_range(-30.0, 30.0)
		var spin: float = GameManager.rng.randf_range(-1.5, 1.5) if is_large else GameManager.rng.randf_range(-3.5, 3.5)
		_shards.append({
			"x": GameManager.rng.randf_range(0.0, vp.x),
			"y": GameManager.rng.randf_range(-vp.y * 0.65, -10.0),
			"vy": vy,
			"vx": vx,
			"size": sz,
			"rot": GameManager.rng.randf_range(0.0, TAU),
			"spin": spin,
			"col": palette[i % palette.size()],
		})

## T-5.2 败局暗晕墨色魂屑：4 缕从屏幕下部缓缓升腾的冷墨微粒
func _seed_wisps() -> void:
	var vp := get_viewport_rect().size
	if vp.x <= 0.0:
		vp = Vector2(960, 540)
	_wisps.clear()
	for i in range(WISP_COUNT):
		_wisps.append({
			"x": GameManager.rng.randf_range(vp.x * 0.15, vp.x * 0.85),
			"y": GameManager.rng.randf_range(vp.y * 0.55, vp.y * 0.95),
			"vy": GameManager.rng.randf_range(-35.0, -65.0),
			"sway_speed": GameManager.rng.randf_range(1.2, 2.2),
			"sway_amp": GameManager.rng.randf_range(12.0, 24.0),
			"phase": GameManager.rng.randf_range(0.0, TAU),
			"size": GameManager.rng.randf_range(4.5, 8.5),
			"rot": GameManager.rng.randf_range(0.0, TAU),
			"spin": GameManager.rng.randf_range(-1.0, 1.0),
		})

func _process(delta: float) -> void:
	if _mode == &"rain":
		_age += delta
		var alive := false
		for s in _shards:
			s["y"] += s["vy"] * delta
			s["x"] += s["vx"] * delta
			s["rot"] += s["spin"] * delta
			if s["y"] < get_viewport_rect().size.y + 12.0:
				alive = true
		if not alive or _age > RAIN_LIFE:
			queue_free()
			return
		queue_redraw()
	elif _mode == &"gloom":
		_gloom_phase += delta * 1.6
		var vp_h := get_viewport_rect().size.y
		if vp_h <= 0.0:
			vp_h = 540.0
		var vp_w := get_viewport_rect().size.x
		if vp_w <= 0.0:
			vp_w = 960.0
		for w in _wisps:
			w["y"] += w["vy"] * delta
			w["rot"] += w["spin"] * delta
			w["phase"] += w["sway_speed"] * delta
			if w["y"] < vp_h * 0.15:
				w["y"] = GameManager.rng.randf_range(vp_h * 0.85, vp_h * 0.98)
				w["x"] = GameManager.rng.randf_range(vp_w * 0.15, vp_w * 0.85)
		queue_redraw()

func _draw() -> void:
	if _mode == &"rain":
		# 尾段整体淡出，不硬切
		var fade := clampf((RAIN_LIFE - _age) / 0.6, 0.0, 1.0)
		for s in _shards:
			var c: Color = GameStyle.with_alpha(s["col"], 0.85 * fade)
			_draw_shard(s["x"], s["y"], s["size"], s["rot"], c)
	elif _mode == &"gloom":
		# 呼吸暗晕：朱砂贴底缓起伏，压得住又不盖战报（画在面板之下，只染边缘视野）
		var a := 0.05 + (sin(_gloom_phase) * 0.5 + 0.5) * 0.05
		draw_rect(Rect2(Vector2.ZERO, size), GameStyle.with_alpha(GameStyle.BAD_DK, a))
		# T-5.2 上升墨色魂屑：呼应 T-1.2 死亡消散，冷墨带微紫，下部淡入、上部淡出
		var vp_h := get_viewport_rect().size.y
		if vp_h <= 0.0:
			vp_h = 540.0
		for w in _wisps:
			var wx: float = w["x"] + sin(w["phase"]) * w["sway_amp"]
			var wy: float = w["y"]
			var t := clampf((wy - vp_h * 0.15) / (vp_h * 0.7), 0.0, 1.0)
			var w_alpha := sin(t * PI) * 0.55
			var col := Color(0.18, 0.16, 0.28, w_alpha)
			_draw_wisp(wx, wy, w["size"], w["rot"], col)

## 斜切小方块（与全项目斜切语言同款的一笔）：绕 (x,y) 转 rot 的平行四边形
func _draw_shard(x: float, y: float, sz: float, rot: float, col: Color) -> void:
	var skew := sz * 0.45
	var pts := PackedVector2Array([
		Vector2(-sz + skew, -sz), Vector2(sz + skew, -sz),
		Vector2(sz - skew, sz), Vector2(-sz - skew, sz),
	])
	var xf := Transform2D(rot, Vector2(x, y))
	for i in range(pts.size()):
		pts[i] = xf * pts[i]
	draw_colored_polygon(pts, col)

## T-5.2 墨色魂屑细长菱晶：微斜切
func _draw_wisp(x: float, y: float, sz: float, rot: float, col: Color) -> void:
	var skew := sz * 0.3
	var h := sz * 1.6
	var pts := PackedVector2Array([
		Vector2(0, -h),
		Vector2(sz, skew),
		Vector2(0, h),
		Vector2(-sz, -skew),
	])
	var xf := Transform2D(rot, Vector2(x, y))
	for i in range(pts.size()):
		pts[i] = xf * pts[i]
	draw_colored_polygon(pts, col)

