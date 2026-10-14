class_name ResultFx
extends Control

## 结算屏氛围层（UI 空间，挂 GameOverDialog 内、垫在面板之下）：
## victory_rain() 金色星屑雨（通关的「庆」）；defeat_gloom() 朱砂呼吸暗晕（阵亡的「哀」）。
## 自绘不走 GPUParticles：保像素硬边（无柔光），headless 判据下由调用方直接不建本层。
## 结算屏开着时整树暂停，故 process_mode = ALWAYS，_process 自己推相位。

## 星屑上限：一批撒完不再续，多了糊屏还费 draw
const SHARD_MAX := 28
## 星屑雨总时长（秒）：到点整层自毁
const RAIN_LIFE := 3.2

var _mode := &""
var _shards: Array[Dictionary] = []
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
		return
	var palette: Array[Color] = [GameStyle.JADE, GameStyle.AURUM, GameStyle.JADE_EDGE, GameStyle.PAPER]
	for i in range(SHARD_MAX):
		_shards.append({
			"x": GameManager.rng.randf_range(0.0, vp.x),
			"y": GameManager.rng.randf_range(-vp.y * 0.6, -10.0),
			"vy": GameManager.rng.randf_range(140.0, 260.0),
			"vx": GameManager.rng.randf_range(-28.0, 28.0),
			"size": GameManager.rng.randf_range(3.0, 7.0),
			"rot": GameManager.rng.randf_range(0.0, TAU),
			"spin": GameManager.rng.randf_range(-3.0, 3.0),
			"col": palette[i % palette.size()],
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
