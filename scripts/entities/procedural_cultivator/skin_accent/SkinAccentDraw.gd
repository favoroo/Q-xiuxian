extends RefCounted

## 角色皮肤挂件绘制（纯函数式，首参传宿主渲染器，不标类型——避免循环类依赖）
##
## 约束：
##  - 全部走 BatchDraw 合批（不新增 draw call）；单角色每帧挂件图元 3~21 个（密集件：
##    算珠 21 / 毛领 18 / 佛珠 17 / 麦穗 15），胸饰 0~6 个；全部并在宿主同一次 _draw 的
##    三角形数组里，新增提交数恒为 0。
##  - 不 new/free 节点；四顶点缓冲用 static PackedVector2Array 复用。
##  - 颜色不硬编码：材质色从宿主现有皮肤色派生，金属/纸白走 GameStyle 常量。
##  - 动画只读宿主在 _process 里积分好的状态（_accent_phase/_accent_sway/_accent_flutter），
##    绘制函数本身不做时间推进，帧率无关。

const BatchDraw = preload("res://scripts/systems/BatchDraw.gd")
const GameStyle = preload("res://scripts/ui/GameStyle.gd")

## 复用的四顶点缓冲（绘制立即合批，不会同时持有两份）
static var _q := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
static var _pts := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
## 材质色缓存（单线程绘制，原地覆写，避免每帧建字典）
static var _pal: Dictionary = {
	"base": Color.WHITE, "hi": Color.WHITE, "deep": Color.BLACK, "tag": "jade",
}

# ==================== 对外入口 ====================

static func draw_chest_ornament(h, float_y: float, angle: int, pal_form: Dictionary) -> void:
	var orn: String = h.chest_ornament
	if orn == "none":
		return
	var c := Vector2(0.0, 4.6 + float_y)
	if angle == 1:  # SIDE：胸饰收窄贴向中轴
		c.x = 2.2
	var pulse: float = sin(h._accent_phase * 1.35 + h._idle_phase)
	material(h, pal_form)
	var base: Color = _pal["base"]
	var hi: Color = _pal["hi"]
	var deep: Color = _pal["deep"]
	if orn == "coin":
		base = h.col_gold
		hi = GameStyle.AURUM_EDGE
		deep = base.darkened(0.45)
	elif orn == "skull":
		base = h.col_bone
		hi = base.lightened(0.18)
		deep = h.col_void
	match orn:
		"pearl":
			BatchDraw.circle(h, c, 2.5, Color(base.r, base.g, base.b, 0.55))
			BatchDraw.circle(h, c, 1.35, hi)
			BatchDraw.circle(h, c + Vector2(-0.6, -0.7), 0.5, Color(1, 1, 1, 0.9))
			BatchDraw.circle(h, c, 2.5 + 0.35 * pulse, Color(base.r, base.g, base.b, 0.20))
		"bagua":
			# 八边形小盘 + 三条卦爻（不逐爻旋转，整盘慢转）
			var rot: float = h._accent_phase * 0.12 + h._idle_phase
			_regular_poly(h, c, 3.0, 8, rot, Color(deep.r, deep.g, deep.b, 0.9))
			_regular_poly(h, c, 2.2, 8, rot, Color(base.r, base.g, base.b, 0.55))
			for i in 3:
				var a: float = rot + float(i) * TAU / 3.0
				var d := Vector2(cos(a), sin(a))
				BatchDraw.native_line(h, c + d * 0.4, c + d * 1.6, hi, 0.9)
			BatchDraw.circle(h, c, 0.7, hi)
		"coin":
			var tilt: float = sin(h._accent_phase * 2.0) * 0.18
			BatchDraw.circle(h, c, 2.7, Color(deep.r, deep.g, deep.b, 0.95))
			BatchDraw.circle(h, c, 2.2, base)
			# 方孔（旋转轻微，随挂点摆动）
			_q[0] = c + Vector2(-0.9, -0.9).rotated(tilt)
			_q[1] = c + Vector2(0.9, -0.9).rotated(tilt)
			_q[2] = c + Vector2(0.9, 0.9).rotated(tilt)
			_q[3] = c + Vector2(-0.9, 0.9).rotated(tilt)
			BatchDraw.poly(h, _q, Color(0.06, 0.05, 0.03, 0.92))
			BatchDraw.circle(h, c + Vector2(-0.9, -1.1), 0.45, Color(1, 1, 1, 0.8))
		"skull":
			BatchDraw.circle(h, c + Vector2(0, -0.5), 2.4, Color(0.10, 0.09, 0.08, 0.9))
			BatchDraw.circle(h, c + Vector2(0, -0.5), 1.9, base)
			BatchDraw.rect(h, Rect2(c + Vector2(-0.9, 0.2), Vector2(1.8, 1.6)), Color(base.r * 0.8, base.g * 0.8, base.b * 0.8, 0.9))
			BatchDraw.circle(h, c + Vector2(-0.7, -0.7), 0.55, deep)
			BatchDraw.circle(h, c + Vector2(0.7, -0.7), 0.55, deep)
			BatchDraw.native_line(h, c + Vector2(-0.8, 1.4), c + Vector2(0.8, 1.4), hi, 0.7)

static func draw(h, spec: Dictionary, form: Dictionary, float_y: float, angle: int) -> void:
	var mot: String = spec["motif"]
	material(h, form)
	var base: Color = _pal["base"]
	var hi: Color = _pal["hi"]
	var deep: Color = _pal["deep"]
	var tag: String = _pal["tag"]
	var rate: float = float(spec["rate"]) * float(form["rate"])
	var amp: float = float(spec["amp"])
	var n: int = maxi(1, int(spec["count"]) + int(form["count"]))
	var ln: float = float(spec["len"]) * float(form["len"])
	var w: float = float(spec["width"]) * float(form["width"])
	var curl: float = float(form["curl"])
	var side_k := 0.55 if angle == 1 else 1.0
	var back_k := 1.18 if angle == 2 else 1.0
	var anchor: Vector2 = spec["anchor"]
	anchor.x *= side_k
	anchor.y += float_y
	if angle == 2:
		anchor.y += 1.5
	anchor.y += h._accent_sway.y * 0.45 * amp
	# 钟摆角：风压 + 恒定微摆 + 偶发抖动（全部来自宿主积分状态）
	var pend: float = h._accent_sway.x * 0.055 * amp \
			+ sin(h._accent_phase * rate + anchor.x * 0.17) * 0.045 * amp \
			+ h._accent_flutter * 0.16 * float(spec["flutter"])
	var run_bob: float = sin(h.gait_phase * TAU) * 0.35 * h._run_blend

	match mot:
		"sword_tassel":
			# 剑穗：一根结绳 + 2~4 缕穗，穗端按材质收尖/成叶；挂点在剑柄外侧，避开剑刃
			BatchDraw.circle(h, anchor + Vector2(0, -0.4), 2.4, Color(deep.r, deep.g, deep.b, 0.95))
			BatchDraw.circle(h, anchor + Vector2(0, -0.4), 1.4, hi)
			for i in n:
				var spread := (float(i) - float(n - 1) * 0.5) * 0.22
				_strand(h, anchor + Vector2(float(i) * 0.55, 0.6), pend + spread, ln * (0.88 + 0.10 * float(i % 2)),
						w * 1.2, base, hi, tag, curl * 0.55, h._accent_phase * rate + float(i) * 0.85, 0.82)
		"shoulder_slabs":
			# 双肩岩甲：厚度感靠深色底 + 亮面，裂纹只一条
			for side in [-1.0, 1.0]:
				if angle == 1 and side < 0.0:
					continue
				var c := Vector2(side * 11.8, anchor.y + run_bob)
				_poly4(h, c + Vector2(-3.9, -2.6), c + Vector2(3.4, -1.6),
						c + Vector2(2.5, 2.5), c + Vector2(-2.9, 2.1), deep)
				_poly4(h, c + Vector2(-3.4, -2.3), c + Vector2(3.0, -1.4),
						c + Vector2(2.1, 0.5), c + Vector2(-2.4, 0.2), Color(base.r, base.g, base.b, 0.95))
				BatchDraw.native_line(h, c + Vector2(-3.0, -0.6), c + Vector2(2.2, -0.2), hi, 1.0)
				BatchDraw.circle(h, c + Vector2(-side * 2.1, 1.6), 0.7, hi)
		"butterflies":
			# 灵蝶：绕身慢飞，翅膀按相位张合（每只 = 深底 + 双翅 + 身线）
			var orbit_n: int = maxi(2, n)
			for i in orbit_n:
				var a: float = h._accent_phase * 0.55 * rate + float(i) * TAU / float(orbit_n)
				var c := Vector2(sin(a) * 12.6 * side_k, anchor.y - cos(a) * 4.0)
				var flap: float = 0.40 + 0.60 * absf(sin(h._accent_phase * 3.1 * rate + float(i) * 1.7))
				var d := Vector2(cos(a), sin(a))
				# 深底先铺一圈，浅色翅压在深袍上才有轮廓（1 倍尺寸下蝶形可辨）
				_poly4(h, c, c + d * (5.4 * flap) + Vector2(0, -2.7),
						c + d * (6.6 * flap) + Vector2(0, 0.6), c + Vector2(0, 1.4), deep)
				_poly4(h, c, c + d * (4.6 * flap) + Vector2(0, -2.4),
						c + d * (5.8 * flap) + Vector2(0, 0.5), c + Vector2(0, 1.2), Color(base.r, base.g, base.b, 0.95))
				_poly4(h, c, c - d * (3.6 * flap) + Vector2(0, -2.1),
						c - d * (4.6 * flap) + Vector2(0, 0.4), c + Vector2(0, 1.1), Color(hi.r, hi.g, hi.b, 0.85))
				BatchDraw.native_line(h, c + Vector2(0, -0.8), c + Vector2(0, 1.2), deep, 0.8)
		"abacus":
			# 算珠：木框一档 + 5~7 颗珠，逐颗错相；顶档横梁让"算盘"不止是一列圆点
			var top := anchor + Vector2(0, -1.9)
			BatchDraw.native_line(h, top, top + Vector2(0, ln + 0.6), Color(deep.r, deep.g, deep.b, 1.0), 1.8)
			BatchDraw.native_line(h, top + Vector2(-2.3, 0.0), top + Vector2(2.3, 0.0), Color(deep.r, deep.g, deep.b, 0.95), 1.2)
			BatchDraw.native_line(h, top + Vector2(-1.7, -0.3), top + Vector2(1.7, -0.3), hi, 0.7)
			for i in n:
				var t := float(i) / float(maxi(1, n - 1))
				var c := top + Vector2(sin(pend + float(i) * 0.7) * 1.0, 1.7 + t * (ln - 2.6))
				BatchDraw.circle(h, c, 2.1, Color(deep.r, deep.g, deep.b, 0.9))
				BatchDraw.circle(h, c, 1.75, hi)
				BatchDraw.circle(h, c + Vector2(-0.5, -0.5), 0.6, Color(1, 1, 1, 0.9))
		"fox_tail":
			# 狐尾：三段锥形接成 S 曲线，末端按材质放一颗结晶/火星
			var p := anchor
			var ang: float = pend * 1.2 + 0.95
			for i in 3:
				var seg := ln / 3.0
				var nxt := p + Vector2(sin(ang), cos(ang)) * seg
				_strand(h, p, ang, seg * 1.15, w * (1.0 - float(i) * 0.18), base, hi, tag, curl, h._accent_phase * rate + float(i), 0.7)
				p = nxt
				ang += 0.42 * (1.0 if ang < 2.6 else -1.0) * (1.0 + h._accent_flutter * 0.5)
			BatchDraw.circle(h, p, w * 0.42, hi)
		"arm_wrap":
			# 断臂缠布：三道横向布条 + 收口
			for i in n:
				var yy := 2.2 - float(i) * 2.4
				_strand(h, anchor + Vector2(0, yy), pend * 0.6 + 1.30, ln * (0.55 + 0.1 * float(i % 2)),
						w, base, hi, tag, curl * 0.6, h._accent_phase * rate + float(i) * 1.2, 0.42)
			BatchDraw.circle(h, anchor + Vector2(0, -1.5), 1.2, deep)
			BatchDraw.native_line(h, anchor + Vector2(-1.2, -2.2), anchor + Vector2(1.2, 0.6), hi, 0.8)
		"tooth_necklace":
			# 兽牙项链：皮绳弧 + 3~5 颗牙（牙身加长，1 倍尺寸下能从胸口钉出来）
			BatchDraw.arc(h, anchor + Vector2(0, -1.2), 8.0, 0.35, PI - 0.35, Color(deep.r, deep.g, deep.b, 0.9), 1.1, false, 10)
			for i in n:
				var t := float(i) / float(maxi(1, n - 1))
				var a: float = lerpf(0.55, PI - 0.55, t)
				var c := anchor + Vector2(cos(a) * 8.0, sin(a) * 8.0 - 1.2)
				var d := Vector2(cos(a), sin(a))
				_poly4(h, c + Vector2(-1.2, -1.5), c + Vector2(1.2, -1.5),
						c + d * 3.6, c + Vector2(0, -0.6), Color(base.r, base.g, base.b, 0.95))
				BatchDraw.native_line(h, c + Vector2(0, -1.2), c + d * 3.2, Color(hi.r, hi.g, hi.b, 0.85), 0.8)
		"soul_flame":
			# 魂火：双层火舌 + 2 颗浮尘，横向不甩、只做呼吸
			var c := anchor + Vector2(0, -2.0 + sin(h._accent_phase * 1.6 * rate) * 0.8)
			var breathe: float = 1.0 + 0.16 * sin(h._accent_phase * 2.1 * rate)
			var fw: float = maxf(1.8, w)
			BatchDraw.circle(h, c + Vector2(0, -1.4), fw * 1.7, Color(hi.r, hi.g, hi.b, 0.16))
			_poly4(h, c + Vector2(-fw, 1.4), c + Vector2(0, -6.2 * breathe),
					c + Vector2(fw, 1.4), c + Vector2(0, 0.4), Color(base.r, base.g, base.b, 0.72))
			_poly4(h, c + Vector2(-fw * 0.5, 0.9), c + Vector2(0, -3.8 * breathe),
					c + Vector2(fw * 0.5, 0.9), c + Vector2(0, 0.2), Color(hi.r, hi.g, hi.b, 0.95))
			BatchDraw.circle(h, c + Vector2(0, 0.6), fw * 0.55, Color(hi.r, hi.g, hi.b, 0.45))
			for i in 2:
				var a: float = h._accent_phase * 2.2 * rate + float(i) * 2.6
				BatchDraw.circle(h, c + Vector2(sin(a) * 3.6, -2.2 - cos(a) * 2.2), 0.45,
						Color(hi.r, hi.g, hi.b, 0.75))
		"treasure_pouch":
			# 百宝囊：锦囊 + 3~5 枚挂件（短线 + 小珠）
			var c := anchor
			_poly4(h, c + Vector2(-2.6, 1.8), c + Vector2(2.6, 1.8),
					c + Vector2(1.8, 6.0), c + Vector2(-1.8, 6.0), deep)
			_poly4(h, c + Vector2(-2.2, 2.2), c + Vector2(2.2, 2.2),
					c + Vector2(1.5, 4.4), c + Vector2(-1.5, 4.4), Color(base.r, base.g, base.b, 0.85))
			BatchDraw.native_line(h, c + Vector2(-2.4, 1.6), c + Vector2(2.4, 1.6), hi, 0.9)
			for i in n:
				var t := float(i) / float(maxi(1, n - 1))
				var x := lerpf(-1.7, 1.7, t)
				var sway: float = sin(h._accent_phase * rate + float(i) * 1.3) * 0.6
				BatchDraw.native_line(h, c + Vector2(x, 4.6), c + Vector2(x + sway, 7.4), Color(hi.r, hi.g, hi.b, 0.8), 0.8)
				BatchDraw.circle(h, c + Vector2(x + sway, 7.8), 0.85, base)
		"wheat":
			# 麦穗：3~5 根穗秆，每根 2 颗穗粒（每根只用 3 个图元，麦穗是挂件里最密的件）
			for i in n:
				var spread := (float(i) - float(n - 1) * 0.5) * 0.24
				var tip := anchor + Vector2(sin(pend + spread) * ln * 0.55 + spread * 3.0, ln * 0.9)
				BatchDraw.native_line(h, anchor + Vector2(float(i) * 0.6, 0), tip, Color(base.r, base.g, base.b, 0.95), 1.3)
				BatchDraw.circle(h, tip + Vector2(-1.0, -1.0), 0.85, hi)
				BatchDraw.circle(h, tip + Vector2(1.0, 0.7), 0.85, hi)
		"thunder_arcs":
			# 肩后雷弧：两道断续折线，闪频高但幅度小
			for side in [-1.0, 1.0]:
				if angle == 1 and side < 0.0:
					continue
				var flick: float = 0.5 + 0.5 * sin(h._accent_phase * 7.0 * rate + side * 2.0 + h._accent_flutter * 4.0)
				var c := Vector2(side * 11.8, anchor.y + run_bob)
				_pts[0] = c + Vector2(0, -5.0)
				_pts[1] = c + Vector2(side * 1.8, -2.0)
				_pts[2] = c + Vector2(side * -0.6, 0.2)
				_pts[3] = c + Vector2(side * 1.4, 2.6)
				_pts[4] = c + Vector2(side * 0.2, 5.0)
				BatchDraw.native_polyline(h, _pts, Color(hi.r, hi.g, hi.b, 0.35 + 0.6 * flick), 1.4)
				BatchDraw.circle(h, c + Vector2(side * 1.2, -2.6), 0.9, Color(base.r, base.g, base.b, 0.5 + 0.4 * flick))
		"gear":
			# 齿轮：唯一恒速旋转件；齿用短线，不画实体齿块
			var rot: float = h._accent_phase * 0.55 * rate
			BatchDraw.circle(h, anchor, 2.7, Color(deep.r, deep.g, deep.b, 0.95))
			BatchDraw.circle(h, anchor, 2.1, Color(base.r, base.g, base.b, 0.8))
			BatchDraw.circle(h, anchor, 0.9, deep)
			for i in n:
				var a: float = rot + float(i) * TAU / float(n)
				var d := Vector2(cos(a), sin(a))
				BatchDraw.native_line(h, anchor + d * 2.0, anchor + d * 3.3, hi, 0.85)
			BatchDraw.circle(h, anchor + Vector2(-0.7, -0.7), 0.5, Color(1, 1, 1, 0.7))
		"gourd":
			_draw_gourd(h, anchor, pend, ln, base, hi, deep)
		"wine_gourd":
			_draw_gourd(h, anchor, pend, ln, base, hi, deep)
			# 瓶口小气团：说明「酒气」，随呼吸胀缩
			var puff: float = 0.7 + 0.3 * sin(h._accent_phase * 1.7 * rate)
			BatchDraw.circle(h, anchor + Vector2(1.0, -2.2 - puff), 0.9 * puff, Color(hi.r, hi.g, hi.b, 0.35))
		"coin_purse":
			var c := anchor
			_poly4(h, c + Vector2(-2.8, 0.0), c + Vector2(2.8, 0.0),
					c + Vector2(2.0, 5.4), c + Vector2(-2.0, 5.4), Color(deep.r, deep.g, deep.b, 0.95))
			_poly4(h, c + Vector2(-2.3, 0.4), c + Vector2(2.3, 0.4),
					c + Vector2(1.6, 3.6), c + Vector2(-1.6, 3.6), Color(base.r, base.g, base.b, 0.9))
			BatchDraw.native_line(h, c + Vector2(-2.6, -0.2), c + Vector2(2.6, -0.2), hi, 1.0)
			for i in n:
				BatchDraw.circle(h, c + Vector2(2.8 + float(i) * 1.1, 3.2 + float(i) * 0.5), 1.0, base)
				BatchDraw.circle(h, c + Vector2(2.8 + float(i) * 1.1, 3.2 + float(i) * 0.5), 0.4, hi)
		"blood_runes":
			# 血纹：两道折线脉动 + 一滴垂血（不随主题改结构，只改色）
			var pulse: float = 0.35 + 0.65 * absf(sin(h._accent_phase * 2.6 * rate))
			for side in [-1.0, 1.0]:
				_pts[0] = anchor + Vector2(side * 3.6, 0.0)
				_pts[1] = anchor + Vector2(side * 1.6, 1.8)
				_pts[2] = anchor + Vector2(side * 3.0, 3.4)
				BatchDraw.native_polyline(h, _pts, Color(base.r, base.g, base.b, 0.35 + 0.55 * pulse), 1.0)
			BatchDraw.circle(h, anchor + Vector2(0, 5.4 + h._accent_flutter * 0.8), 0.9, Color(hi.r, hi.g, hi.b, 0.8))
		"talisman_strip":
			# 符纸：3~5 道垂符，符面一横一竖；flap 时整条翻卷
			for i in n:
				var x := (float(i) - float(n - 1) * 0.5) * 1.9
				var swing: float = sin(h._accent_phase * rate + float(i) * 1.1) * 1.2 + h._accent_flutter * 2.2
				var c := anchor + Vector2(x, 0)
				_poly4(h, c + Vector2(-1.0, 0), c + Vector2(1.0, 0),
						c + Vector2(0.6 + swing, ln), c + Vector2(-0.6 + swing, ln), Color(base.r, base.g, base.b, 0.9))
				BatchDraw.native_line(h, c + Vector2(-0.6, 2.2), c + Vector2(0.8, 2.6), hi, 0.8)
				BatchDraw.native_line(h, c + Vector2(0.2, ln - 1.6), c + Vector2(0.2 + swing * 0.2, ln - 0.6), hi, 0.7)
		"fur_collar":
			# 兽毛肩领：4~6 簇立毛，只呼吸起伏
			for i in n:
				var t := float(i) / float(maxi(1, n - 1))
				var x := lerpf(-8.2, 8.2, t) * side_k
				var lift: float = 3.4 + 1.0 * sin(h._accent_phase * 1.5 * rate + t * 2.4) - absf(t - 0.5) * 3.2
				var c := Vector2(x, anchor.y)
				_poly4(h, c + Vector2(-2.2, 0.9), c + Vector2(2.2, 0.9),
						c + Vector2(0.7, -lift), c + Vector2(-0.7, -lift), Color(deep.r, deep.g, deep.b, 0.95))
				_poly4(h, c + Vector2(-1.5, 0.5), c + Vector2(1.5, 0.5),
						c + Vector2(0.4, -lift * 0.82), c + Vector2(-0.4, -lift * 0.82), Color(base.r, base.g, base.b, 0.95))
				BatchDraw.native_line(h, c + Vector2(0, 0.3), c + Vector2(0, -lift * 0.7), Color(hi.r, hi.g, hi.b, 0.75), 0.8)
		"sash_ribbons":
			# 双飘带：两段接成 S，末段按 flutter 加大摆幅
			for i in n:
				var dx := float(i) * 2.2
				var p := anchor + Vector2(dx, 0)
				var ang: float = pend * 1.5 - 0.78 + float(i) * 0.18
				for seg in 2:
					var nxt := p + Vector2(sin(ang), cos(ang)) * ln * 0.5
					_strand(h, p, ang, ln * 0.58, w * (1.0 - 0.22 * float(seg)), base, hi, tag, curl,
							h._accent_phase * rate + float(i) + float(seg) * 0.8, 0.5)
					p = nxt
					ang += 0.55 + h._accent_flutter * 0.35
		"beast_bell":
			# 兽铃：钟摆式摇摆，铃身 + 铃口线 + 铃心
			var a: float = pend * 1.4
			var c := anchor + Vector2(sin(a) * ln * 0.5, cos(a) * ln * 0.35)
			BatchDraw.native_line(h, anchor, c, Color(deep.r, deep.g, deep.b, 0.9), 0.8)
			_poly4(h, c + Vector2(-2.2, 0.4), c + Vector2(2.2, 0.4),
					c + Vector2(1.4, 3.2), c + Vector2(-1.4, 3.2), base)
			BatchDraw.native_line(h, c + Vector2(-1.5, 3.4), c + Vector2(1.5, 3.4), hi, 0.9)
			BatchDraw.circle(h, c + Vector2(0, 2.0), 0.65, Color(hi.r, hi.g, hi.b, 0.9))
		"prayer_beads":
			# 佛珠：胸前一道弧 + 6~8 颗珠，逐颗按相位轻摆
			BatchDraw.arc(h, anchor + Vector2(0, 1.8), 5.4, 0.5, PI - 0.5, Color(deep.r, deep.g, deep.b, 0.7), 0.6, false, 10)
			for i in n:
				var t := float(i) / float(maxi(1, n - 1))
				var a := lerpf(0.55, PI - 0.55, t)
				var c := anchor + Vector2(cos(a) * 5.4, sin(a) * 5.4 + 1.8 + sin(h._accent_phase * rate + float(i) * 0.9) * 0.35)
				BatchDraw.circle(h, c, 1.0, base)
				BatchDraw.circle(h, c + Vector2(-0.35, -0.35), 0.35, Color(hi.r, hi.g, hi.b, 0.8))
		_:
			pass

# ==================== 共用小件 ====================

static func _draw_gourd(h, c: Vector2, pend: float, ln: float, base: Color, hi: Color, deep: Color) -> void:
	var a: float = pend * 1.3
	# 尺寸跟 len 走（7~8px 的葫芦按 1.25 倍画，1 倍尺寸下才有壶形，不是墨点）
	var k: float = 0.85 + ln * 0.06
	var body := c + Vector2(sin(a) * ln * 0.35, ln * 0.35)
	BatchDraw.native_line(h, c, body + Vector2(0, -1.6 * k), Color(deep.r, deep.g, deep.b, 0.85), 0.9)
	BatchDraw.circle(h, body + Vector2(0, -1.0 * k), 1.5 * k, Color(deep.r, deep.g, deep.b, 0.9))
	BatchDraw.circle(h, body + Vector2(0, 1.6 * k), 2.6 * k, Color(deep.r, deep.g, deep.b, 0.95))
	BatchDraw.circle(h, body + Vector2(0, -1.0 * k), 1.1 * k, base)
	BatchDraw.circle(h, body + Vector2(0, 1.6 * k), 2.2 * k, base)
	BatchDraw.circle(h, body + Vector2(-0.9 * k, 0.9 * k), 0.6 * k, Color(hi.r, hi.g, hi.b, 0.85))
	BatchDraw.native_line(h, body + Vector2(-2.2 * k, 3.4 * k), body + Vector2(2.2 * k, 3.4 * k), hi, 0.8)

## 悬垂缕状件：1 个锥形四边形 + 1 条材质高光；
## tag 决定收尖程度与附加小件（晶=尖锐+棱线 / 墨=湿笔+墨点 / 焰=火尖+火星 / 金=箔面 / 虹=棱彩）
static func _strand(h, base: Vector2, ang: float, length: float, width: float,
		col: Color, hi: Color, tag: String, curl: float, phase: float, sharp: float) -> void:
	var dir := Vector2(sin(ang), cos(ang))
	var perp := Vector2(cos(ang), -sin(ang))
	var sway := perp * sin(phase) * curl * length * 0.22
	var tip := base + dir * length + sway
	var w0 := width * 0.5
	var w_tip := w0 * (1.0 - sharp)
	if tag == "crystal":
		w_tip = 0.0
		w0 *= 0.9
	elif tag == "ink":
		w_tip = w0 * 0.78
	elif tag == "ember":
		w_tip = w0 * 0.12
	elif tag == "gold":
		w_tip = w0 * 0.42
	var mid_perp := perp * sin(phase * 1.3) * curl * length * 0.10
	_poly4(h, base + perp * w0, tip + mid_perp + perp * w_tip,
			tip + mid_perp - perp * w_tip, base - perp * w0, Color(col.r, col.g, col.b, 0.95))
	# 中缝走深色而不是亮色：挂件填充已抬亮，亮线只会被吞掉；深色折痕才有布/穗的厚度感
	BatchDraw.native_line(h, base, tip + sway * 0.4, Color(hi.r * 0.35, hi.g * 0.35, hi.b * 0.35, 0.5), maxf(0.6, width * 0.45))
	if tag == "ember":
		BatchDraw.circle(h, tip, 0.7, Color(hi.r, hi.g, hi.b, 0.9))
	elif tag == "ink":
		BatchDraw.circle(h, tip, w0 * 0.55, Color(col.r, col.g, col.b, 0.45))
	elif tag == "crystal":
		BatchDraw.native_line(h, base, tip, Color(hi.r, hi.g, hi.b, 0.45), 0.5)

static func _poly4(h, a: Vector2, b: Vector2, c: Vector2, d: Vector2, col: Color) -> void:
	_q[0] = a
	_q[1] = b
	_q[2] = c
	_q[3] = d
	BatchDraw.poly(h, _q, col)

static func _regular_poly(h, c: Vector2, r: float, n: int, rot: float, col: Color) -> void:
	_pts.resize(n)
	for i in n:
		var a := rot + float(i) * TAU / float(n)
		_pts[i] = c + Vector2(cos(a), sin(a)) * r
	BatchDraw.poly(h, _pts, col)

## 材质色：只从宿主皮肤色 + GameStyle 常量派生，杜绝硬编码
static func material(h, form: Dictionary) -> void:
	var tag: String = form["tag"]
	var edge: Color = h.col_cloak_edge
	var eye: Color = h.col_eye_core
	var gold: Color = h.col_gold
	_pal["tag"] = tag
	# 关键：base 必须比斗篷本体的 col_edge 更亮一档。此前 base 直接取 col_edge，
	# 挂件和斗篷缘边同色，1 倍尺寸下整件"融"进袍子里（2026-11-04 实抓确认）。
	# 现在统一把 base 向 eye_core（各皮肤最亮的那档）混 35%~60%，hi 再抬到接近纸白，
	# 深色只留作勾边/压暗底，材质色相仍由 edge/eye/gold 决定，不算硬编码。
	match tag:
		"origin":
			_pal["base"] = edge.lerp(eye, 0.50)
			_pal["hi"] = eye.lerp(GameStyle.CHALK, 0.35)
			_pal["deep"] = edge.darkened(0.55)
		"jade":
			_pal["base"] = edge.lerp(eye, 0.42)
			_pal["hi"] = eye.lerp(GameStyle.CHALK, 0.55)
			_pal["deep"] = edge.darkened(0.50)
		"ember":
			_pal["base"] = edge.lerp(eye, 0.55)
			_pal["hi"] = eye.lerp(GameStyle.CHALK, 0.45)
			_pal["deep"] = edge.darkened(0.62)
		"crystal":
			_pal["base"] = eye.lerp(GameStyle.CHALK, 0.55)
			_pal["hi"] = GameStyle.CHALK
			_pal["deep"] = edge.darkened(0.30)
		"ink":
			_pal["base"] = edge.lightened(0.55)
			_pal["hi"] = GameStyle.CHALK.lerp(eye, 0.35)
			_pal["deep"] = edge.darkened(0.62)
		"gold":
			_pal["base"] = gold.lerp(GameStyle.AURUM_EDGE, 0.75)
			_pal["hi"] = GameStyle.AURUM_EDGE.lightened(0.30)
			_pal["deep"] = gold.darkened(0.60)
		"prism":
			_pal["base"] = Color.from_hsv(fmod(h._accent_phase * 0.12, 1.0), 0.45, 1.0)
			_pal["hi"] = Color(1, 1, 1)
			_pal["deep"] = eye.darkened(0.55)
