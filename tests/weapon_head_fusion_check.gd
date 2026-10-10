extends Node

## tests/weapon_head_fusion_check.gd — 背负法器与面部「粘连/融合」像素判据
##
## 要解决的问题：骨白法器（骨钉剑、厚背断刀、兽骨斧）与骨白面壳几乎同色，而正面位姿
## 又把剑身压在面具轮廓上，两层白连成一片，看着就是「剑长在脸上」。
##
## 尺子为什么这么量：图元包围盒骗得过眼睛（矩形含大量空白），所以这里只认真实画出来的
## 那一圈像素。用 CultivatorRendererBase.debug_layers 把武器层、斗篷层、头部层各自单独
## 离屏渲染一遍（不做帧间差分，差分会被渲染抖动糊成一片噪声）：
##   可见武器 = 武器层画到、且没被斗篷层和头部层挡住的那些像素；
##   头部 = 头部层的实体像素（眼神辉光是光不是脸，按亮度剔掉）。
## 再对头部像素做切比雪夫距离变换，取可见武器像素上的最小值 = 两者之间的隔离带宽度。
##
## 判据（两条任一满足即 PASS）：
##   A. 隔离带宽度不小于 GAP_MIN_PX 逻辑像素；
##   B. 武器主色与骨白面具的色差不少于 COLOR_MIN（不同色时挨着也分得开）。
##
## 跑法（必须带窗口，headless 下 Viewport 不出图，脚本打 [HEADLESS_GUARD] 并以失败退出）：
##   G=/Applications/Godot.app/Contents/MacOS/Godot
##   $G --path . res://tests/WeaponHeadFusionCheck.tscn
##   $G --path . res://tests/WeaponHeadFusionCheck.tscn -- --dump    # 另出诊断图到 tests/styles/weapon_fusion/
##   $G --path . res://tests/WeaponHeadFusionCheck.tscn -- --only=jianchi

const SS := 6                        ## 超采样倍率：1 逻辑像素 = 6 设备像素，描边级差异才测得出
const CANVAS_W := 80                 ## 离屏画布（逻辑像素）
const CANVAS_H := 92
const GAP_MIN_PX := 2.0              ## 判据 A：武器与头部之间至少留出的隔离带宽度
const COLOR_MIN := 0.18              ## 判据 B：两层填充色的最小 RGB 欧氏色差
## 动作与时刻：取浮沉到达波峰/波谷的那一帧。待机与奔跑的武器浮沉系数不同
## （奔跑是 float_y * 0.85，头部是 float_y），会产生约 0.36 逻辑像素的相对位移，
## 所以两个动作的最不利帧都要量。冲刺与受击是固定偏移，不随时间变化。
const STEPS: Array = [
	[CultivatorRendererBase.Action.IDLE, 0.604],
	[CultivatorRendererBase.Action.RUN, 0.302],
	[CultivatorRendererBase.Action.RUN, 0.906],
]
const SOLID_MIN := 20            ## 实体亮度门槛：低于它的是辉光/半透明边缘，不算"画在那儿的一块"
const HEAD_SOLID := 110          ## 头部实体门槛：眼神辉光只是光不是脸，不能算进"脸的那一圈"

const CHAR_IDS: Array[String] = [
	"jianchi", "shiyue", "fuzhen", "jinsuanpan", "meiying",
	"dubi", "kuangzhan", "duoshe", "duobao",
]
const ANGLE_NAMES: Array[String] = ["front", "side", "back"]
const BG := Color(0.0, 0.0, 0.0, 1.0)

const L_WEAPON_ONLY := 4         ## 只画武器层
const L_CLOAK_ONLY := 8          ## 只画斗篷层
const L_HEAD_ONLY := 16          ## 只画头部：面具 + 首服 + 眼

var _check := TestCheck.new()
var _dump := false
var _only := ""
var _worst_gap := 1e9
var _worst_line := ""
var _shots: Array[Image] = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_dump = args.has("--dump")
	for a in args:
		if String(a).begins_with("--only="):
			_only = String(a).trim_prefix("--only=")
	if DisplayServer.get_name() == "headless":
		print("[HEADLESS_GUARD] 本判据要真实出图，必须带窗口跑：$G --path . res://tests/WeaponHeadFusionCheck.tscn")
		get_tree().quit(1)
		return
	_run()


func _run() -> void:
	for cid in CHAR_IDS:
		if _only != "" and _only != cid:
			continue
		var cfg := CultivatorVisualConfig.get_config(cid)
		for ai in ANGLE_NAMES.size():
			var angle: CultivatorRendererBase.Angle = ai
			var worst: Dictionary = {}
			for st in STEPS:
				var m := await _measure(cfg, angle, st[0], st[1])
				if worst.is_empty() or float(m["gap"]) < float(worst["gap"]):
					worst = m
			_report(cid, ANGLE_NAMES[ai], worst)
			if _dump:
				_dump_diagnostic(cid, ANGLE_NAMES[ai], worst)
	print("WEAPON_HEAD_FUSION_RESULT: %s" % ("ALL PASS" if _check.all_passed() else "%d FAILURES" % _check.failures.size()))
	print("最粘连处: %s" % _worst_line)
	get_tree().quit(0 if _check.all_passed() else 1)


# ==================== 一次测量 ====================

func _measure(cfg: CultivatorVisualConfig, angle: CultivatorRendererBase.Angle, action: CultivatorRendererBase.Action, time_val: float) -> Dictionary:
	var wpn := await _render(cfg, angle, action, time_val, L_WEAPON_ONLY)
	var clo := await _render(cfg, angle, action, time_val, L_CLOAK_ONLY)
	var hd := await _render(cfg, angle, action, time_val, L_HEAD_ONLY)

	var w := wpn.get_width()
	var h := wpn.get_height()
	var cloak_on_top := angle == CultivatorRendererBase.Angle.BACK
	var n := w * h
	var weapon_mask := PackedByteArray()
	weapon_mask.resize(n)
	var head_mask := PackedByteArray()
	head_mask.resize(n)
	var dw := wpn.get_data()
	var dc := clo.get_data()
	var dh := hd.get_data()
	var weapon_px := 0
	var head_px := 0
	for i in range(n):
		var o := i * 4
		var is_head := maxi(maxi(dh[o], dh[o + 1]), dh[o + 2]) >= HEAD_SOLID
		if is_head:
			head_mask[i] = 1
			head_px += 1
			continue
		var is_wpn := maxi(maxi(dw[o], dw[o + 1]), dw[o + 2]) >= SOLID_MIN
		# 被斗篷盖住的那截剑没有在屏幕上成像，不参与"贴脸"判定；
		# 但背面视角的层序是斗篷在底、法器挂在最外层，那时斗篷不构成遮挡。
		var buried := false
		if not cloak_on_top:
			buried = maxi(maxi(dc[o], dc[o + 1]), dc[o + 2]) >= SOLID_MIN
		if is_wpn and not buried:
			weapon_mask[i] = 1
			weapon_px += 1

	return {
		"gap": _min_gap(weapon_mask, head_mask, w, h) / float(SS),
		"weapon_px": weapon_px,
		"head_px": head_px,
		"weapon_mask": weapon_mask,
		"head_mask": head_mask,
		"w": w,
		"h": h,
		"color_delta": _color_delta(cfg),
	}


## 两层填充色差：同色时眼睛分不开，只能靠隔离带
func _color_delta(cfg: CultivatorVisualConfig) -> float:
	var wc: Color = cfg.weapon.get("col_main", Color.WHITE)
	var hc: Color = cfg.bone_white
	return sqrt(pow(wc.r - hc.r, 2) + pow(wc.g - hc.g, 2) + pow(wc.b - hc.b, 2))


# ==================== 离屏渲染 ====================

func _render(cfg: CultivatorVisualConfig, angle: CultivatorRendererBase.Angle, action: CultivatorRendererBase.Action, time_val: float, layers: int) -> Image:
	var vp := SubViewport.new()
	vp.size = Vector2i(CANVAS_W * SS, CANVAS_H * SS)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)

	var backdrop := ColorRect.new()
	backdrop.color = BG
	backdrop.size = Vector2(CANVAS_W * SS, CANVAS_H * SS)
	vp.add_child(backdrop)

	var r := HollowKnightCultivatorRenderer.new(cfg)
	r.current_angle = angle
	r.current_action = action
	r.debug_layers = layers
	r.position = Vector2(CANVAS_W * SS * 0.5, CANVAS_H * SS * 0.55)
	r.scale = Vector2(SS, SS)
	r.set_process(false)
	r._time = time_val
	vp.add_child(r)

	for i in range(2):
		r._time = time_val
		r.queue_redraw()
		await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img == null:
		push_error("离屏渲染取不到图像，判据无法工作")
		return Image.create(CANVAS_W * SS, CANVAS_H * SS, false, Image.FORMAT_RGBA8)
	img.convert(Image.FORMAT_RGBA8)
	return img


# ==================== 距离变换：头部像素到武器像素的最小切比雪夫间距 ====================

func _min_gap(weapon: PackedByteArray, head: PackedByteArray, w: int, h: int) -> int:
	var inf := 1 << 20
	var dist := PackedInt32Array()
	dist.resize(w * h)
	for i in range(w * h):
		dist[i] = 0 if head[i] == 1 else inf
	for i in range(w * h):
		if weapon[i] == 1 and dist[i] == 0:
			return 0
	var best := inf
	for y in range(h):
		var row := y * w
		for x in range(w):
			var i := row + x
			var d := dist[i]
			if y > 0:
				d = mini(d, dist[i - w] + 1)
				if x > 0:
					d = mini(d, dist[i - w - 1] + 1)
				if x < w - 1:
					d = mini(d, dist[i - w + 1] + 1)
			if x > 0:
				d = mini(d, dist[i - 1] + 1)
			dist[i] = d
	for y in range(h - 1, -1, -1):
		var row := y * w
		for x in range(w):
			var i := row + x
			var d := dist[i]
			if y < h - 1:
				d = mini(d, dist[i + w] + 1)
				if x > 0:
					d = mini(d, dist[i + w - 1] + 1)
				if x < w - 1:
					d = mini(d, dist[i + w + 1] + 1)
			if x < w - 1:
				d = mini(d, dist[i + 1] + 1)
			dist[i] = d
	for i in range(w * h):
		if weapon[i] == 1 and dist[i] < best:
			best = dist[i]
	return best if best < inf else -1


# ==================== 报告与诊断图 ====================

func _report(cid: String, angle_name: String, m: Dictionary) -> void:
	var gap := float(m["gap"])
	var delta := float(m["color_delta"])
	var label := "%s/%s" % [cid, angle_name]
	if gap < 0.0 or int(m["weapon_px"]) == 0:
		_check.check(false, "%s 该视角下武器一个像素都没露出来（背的法器完全被遮住）" % label)
		return
	if gap >= GAP_MIN_PX:
		_check.check(true, "%s 隔离带 %.2f 逻辑像素，达标线 %.1f" % [label, gap, GAP_MIN_PX])
	else:
		_check.check(delta >= COLOR_MIN,
			"%s 隔离带只有 %.2f 逻辑像素，且武器与面具色差 %.3f 低于 %.2f（白叠白，看着就是剑长在脸上）" % [label, gap, delta, COLOR_MIN])
	if gap < _worst_gap:
		_worst_gap = gap
		_worst_line = "%s 隔离带 %.2fpx 色差 %.3f 武器露出 %d 设备像素" % [label, gap, delta, int(m["weapon_px"])]


## 诊断图：武器像素染红、头部像素染蓝，两圈是否粘连一眼可见
func _dump_diagnostic(cid: String, angle_name: String, m: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute("tests/styles/weapon_fusion")
	var w := int(m["w"])
	var h := int(m["h"])
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.05, 0.06, 0.09, 1.0))
	var weapon: PackedByteArray = m["weapon_mask"]
	var head: PackedByteArray = m["head_mask"]
	for y in range(h):
		for x in range(w):
			var i := y * w + x
			if weapon[i] == 1:
				img.set_pixel(x, y, Color(1.0, 0.25, 0.25, 1.0))
			elif head[i] == 1:
				img.set_pixel(x, y, Color(0.30, 0.60, 1.0, 1.0))
	var path := "tests/styles/weapon_fusion/%s_%s.png" % [cid, angle_name]
	img.save_png(path)
