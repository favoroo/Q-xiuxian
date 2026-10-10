class_name StyleStardew
extends CultivatorBase

## 风格 C：星露谷物语风 (Stardew Valley / HD Modern 精致微像素暖调仙侠)
## 特征：
## 1. 现代 16-bit 精品微像素艺术（对标星露谷、风来之国），带暗色像素勾边
## 2. 温暖明媚的青竹绿三段式色阶（高光薄荷翠、中调竹青、暗调林墨）
## 3. 比例匀称的 2.5 头身精致人设，五官清秀发丝分明
## 4. 典雅交领道袍、暖棕丝绦、羊脂白玉佩与金装青锋剑

const PIXEL := 1.8 # 精致微像素网格单位

const COLOR_RAMP := {
	"outline": Color(0.12, 0.14, 0.18),      # 经典深色像素勾边
	"skin": Color(0.98, 0.85, 0.74),
	"skin_shadow": Color(0.88, 0.72, 0.60),
	"hair_black": Color(0.14, 0.16, 0.20),
	"hair_high": Color(0.28, 0.32, 0.40),
	"robe_light": Color(0.44, 0.80, 0.56),   # 阳光面竹青
	"robe_mid": Color(0.28, 0.62, 0.40),     # 主调翡翠
	"robe_dark": Color(0.18, 0.42, 0.28),    # 背光深林
	"white_inner": Color(0.93, 0.95, 0.96),  # 月白中衣
	"belt_buckle": Color(0.96, 0.80, 0.28),  # 纯金扣
	"shoes_black": Color(0.16, 0.18, 0.22),
	"tassel_red": Color(0.86, 0.22, 0.25)
}

func _draw_front() -> void:
	var bob := sin(_time * 3.2) * 1.2 if animate else 0.0

	# 1. 柔和像素地影
	_draw_px_rect(Vector2(-12, 26), Vector2(24, 5), Color(0.08, 0.12, 0.16, 0.25))

	# 2. 背负青锋剑（剑柄与剑身从肩后斜露出）
	_draw_stardew_sword(Vector2(7, -3 + bob), deg_to_rad(28.0))

	# 3. 双足与布履（带深色底座）
	_draw_px_rect(Vector2(-7, 21), Vector2(5, 6), COLOR_RAMP["outline"])
	_draw_px_rect(Vector2(-6, 22), Vector2(4, 4), COLOR_RAMP["shoes_black"])
	_draw_px_rect(Vector2(2, 21), Vector2(5, 6), COLOR_RAMP["outline"])
	_draw_px_rect(Vector2(3, 22), Vector2(4, 4), COLOR_RAMP["shoes_black"])

	# 4. 下裳长裙（带深色像素轮廓与层次明暗）
	_draw_px_rect(Vector2(-9, 7 + bob), Vector2(18, 16), COLOR_RAMP["outline"])
	_draw_px_rect(Vector2(-8, 8 + bob), Vector2(16, 14), COLOR_RAMP["robe_mid"])
	# 左侧受光面，右侧背光面
	_draw_px_rect(Vector2(-8, 8 + bob), Vector2(7, 14), COLOR_RAMP["robe_light"])
	_draw_px_rect(Vector2(4, 8 + bob), Vector2(4, 14), COLOR_RAMP["robe_dark"])
	# 裙摆中缝露月白内衬
	_draw_px_rect(Vector2(-1, 13 + bob), Vector2(2, 9), COLOR_RAMP["white_inner"])

	# 5. 上身躯干
	_draw_px_rect(Vector2(-8, -5 + bob), Vector2(16, 14), COLOR_RAMP["outline"])
	_draw_px_rect(Vector2(-7, -4 + bob), Vector2(14, 12), COLOR_RAMP["robe_mid"])
	_draw_px_rect(Vector2(-7, -4 + bob), Vector2(6, 12), COLOR_RAMP["robe_light"])

	# 6. 交领领口（V字叠衽）
	_draw_px_rect(Vector2(-3.5, -5 + bob), Vector2(7, 4.5), COLOR_RAMP["white_inner"])
	_draw_px_rect(Vector2(-2, -5 + bob), Vector2(4, 2.5), COLOR_RAMP["skin"])

	# 7. 双臂与衣袖
	_draw_px_rect(Vector2(-11, -4 + bob), Vector2(4, 12), COLOR_RAMP["outline"])
	_draw_px_rect(Vector2(-10, -3 + bob), Vector2(3, 10), COLOR_RAMP["robe_light"])
	_draw_px_rect(Vector2(7, -4 + bob), Vector2(4, 12), COLOR_RAMP["outline"])
	_draw_px_rect(Vector2(7, -3 + bob), Vector2(3, 10), COLOR_RAMP["robe_dark"])
	_draw_px_rect(Vector2(-9, 7 + bob), Vector2(2.5, 2.5), COLOR_RAMP["skin"])
	_draw_px_rect(Vector2(7.5, 7 + bob), Vector2(2.5, 2.5), COLOR_RAMP["skin"])

	# 8. 头部与清秀五官
	var head_y := -19.0 + bob
	_draw_px_rect(Vector2(-6, head_y - 1), Vector2(12, 12), COLOR_RAMP["outline"])
	_draw_px_rect(Vector2(-5, head_y), Vector2(10, 10), COLOR_RAMP["skin"])
	_draw_px_rect(Vector2(-5, head_y + 7.5), Vector2(10, 2.5), COLOR_RAMP["skin_shadow"])
	# 清秀双眼（星露谷经典深棕目带白高光）
	_draw_px_rect(Vector2(-3.5, head_y + 3.5), Vector2(2.2, 3.0), Color(0.18, 0.14, 0.12))
	_draw_px_rect(Vector2(-3.5, head_y + 3.5), Vector2(1.0, 1.2), Color.WHITE)
	_draw_px_rect(Vector2(1.5, head_y + 3.5), Vector2(2.2, 3.0), Color(0.18, 0.14, 0.12))
	_draw_px_rect(Vector2(1.5, head_y + 3.5), Vector2(1.0, 1.2), Color.WHITE)
	# 脸颊微红晕
	_draw_px_rect(Vector2(-4.5, head_y + 6.8), Vector2(2, 1.2), Color(0.95, 0.60, 0.55, 0.7))
	_draw_px_rect(Vector2(2.5, head_y + 6.8), Vector2(2, 1.2), Color(0.95, 0.60, 0.55, 0.7))

	# 9. 墨发、刘海与道簪发髻
	_draw_px_rect(Vector2(-3.5, head_y - 7), Vector2(7, 7), COLOR_RAMP["hair_black"])
	_draw_px_rect(Vector2(-2, head_y - 6), Vector2(4, 2.5), COLOR_RAMP["hair_high"])
	# 青色玉簪
	_draw_px_rect(Vector2(-6, head_y - 4.5), Vector2(12, 2.0), Color(0.40, 0.95, 0.75))
	# 前额发际线
	_draw_px_rect(Vector2(-5.5, head_y - 1.5), Vector2(11, 4), COLOR_RAMP["hair_black"])
	_draw_px_rect(Vector2(-5.5, head_y + 2), Vector2(2, 6), COLOR_RAMP["hair_black"])
	_draw_px_rect(Vector2(3.5, head_y + 2), Vector2(2, 6), COLOR_RAMP["hair_black"])

func _draw_side() -> void:
	var bob := sin(_time * 3.2) * 1.2 if animate else 0.0

	# 1. 地影
	_draw_px_rect(Vector2(-10, 26), Vector2(20, 5), Color(0.08, 0.12, 0.16, 0.25))

	# 2. 侧行脚步
	_draw_px_rect(Vector2(-6, 21), Vector2(5, 6), COLOR_RAMP["outline"])
	_draw_px_rect(Vector2(-5, 22), Vector2(4, 4), COLOR_RAMP["shoes_black"])
	_draw_px_rect(Vector2(2, 21), Vector2(5, 6), COLOR_RAMP["outline"])
	_draw_px_rect(Vector2(3, 22), Vector2(4, 4), COLOR_RAMP["shoes_black"])

	# 3. 侧身道袍下裳
	_draw_px_rect(Vector2(-7, 7 + bob), Vector2(14, 16), COLOR_RAMP["outline"])
	_draw_px_rect(Vector2(-6, 8 + bob), Vector2(12, 14), COLOR_RAMP["robe_mid"])
	_draw_px_rect(Vector2(1, 8 + bob), Vector2(5, 14), COLOR_RAMP["robe_light"])

	# 4. 侧身上身
	_draw_px_rect(Vector2(-6, -5 + bob), Vector2(12, 14), COLOR_RAMP["outline"])
	_draw_px_rect(Vector2(-5, -4 + bob), Vector2(10, 12), COLOR_RAMP["robe_mid"])
	_draw_px_rect(Vector2(0, -4 + bob), Vector2(5, 12), COLOR_RAMP["robe_light"])

	# 5. 侧面头部与五官
	var head_y := -19.0 + bob
	_draw_px_rect(Vector2(-4, head_y - 1), Vector2(10, 12), COLOR_RAMP["outline"])
	_draw_px_rect(Vector2(-3, head_y), Vector2(8, 10), COLOR_RAMP["skin"])
	# 单侧眼
	_draw_px_rect(Vector2(1.5, head_y + 3.5), Vector2(2.2, 3.0), Color(0.18, 0.14, 0.12))
	_draw_px_rect(Vector2(1.5, head_y + 3.5), Vector2(1.0, 1.2), Color.WHITE)
	_draw_px_rect(Vector2(2.5, head_y + 6.8), Vector2(2, 1.2), Color(0.95, 0.60, 0.55, 0.7))

	# 侧面发丝与后垂马尾
	_draw_px_rect(Vector2(-5, head_y - 2), Vector2(9, 5), COLOR_RAMP["hair_black"])
	_draw_px_rect(Vector2(-6, head_y + 3), Vector2(3.5, 10), COLOR_RAMP["hair_black"])
	_draw_px_rect(Vector2(-2.5, head_y - 7), Vector2(6, 6), COLOR_RAMP["hair_black"])
	_draw_px_rect(Vector2(-4.5, head_y - 4.5), Vector2(9, 2.0), Color(0.40, 0.95, 0.75))

	# 6. 单手掐剑诀前伸，飞剑浮游身前
	_draw_px_rect(Vector2(3.5, -1 + bob), Vector2(6, 4), COLOR_RAMP["outline"])
	_draw_px_rect(Vector2(4, 0 + bob), Vector2(5, 3), COLOR_RAMP["robe_light"])
	_draw_px_rect(Vector2(8.5, 0 + bob), Vector2(2.5, 2.5), COLOR_RAMP["skin"])
	_draw_stardew_sword(Vector2(18, -3 + bob), deg_to_rad(65.0))

func _draw_back() -> void:
	var bob := sin(_time * 3.2) * 1.2 if animate else 0.0

	# 1. 地影
	_draw_px_rect(Vector2(-12, 26), Vector2(24, 5), Color(0.08, 0.12, 0.16, 0.25))

	# 2. 背后背负之青锋长剑（正中背负）
	_draw_stardew_sword(Vector2(0, 0 + bob), deg_to_rad(0.0))

	# 3. 双足
	_draw_px_rect(Vector2(-7, 21), Vector2(5, 6), COLOR_RAMP["outline"])
	_draw_px_rect(Vector2(-6, 22), Vector2(4, 4), COLOR_RAMP["shoes_black"])
	_draw_px_rect(Vector2(2, 21), Vector2(5, 6), COLOR_RAMP["outline"])
	_draw_px_rect(Vector2(3, 22), Vector2(4, 4), COLOR_RAMP["shoes_black"])

	# 4. 后背长裙
	_draw_px_rect(Vector2(-9, 7 + bob), Vector2(18, 16), COLOR_RAMP["outline"])
	_draw_px_rect(Vector2(-8, 8 + bob), Vector2(16, 14), COLOR_RAMP["robe_mid"])
	_draw_px_rect(Vector2(-1, 8 + bob), Vector2(2, 14), COLOR_RAMP["robe_dark"])

	# 5. 上身后背
	_draw_px_rect(Vector2(-8, -5 + bob), Vector2(16, 14), COLOR_RAMP["outline"])
	_draw_px_rect(Vector2(-7, -4 + bob), Vector2(14, 12), COLOR_RAMP["robe_mid"])

	# 6. 后脑发丝与整齐发束
	var head_y := -19.0 + bob
	_draw_px_rect(Vector2(-6, head_y - 1), Vector2(12, 12), COLOR_RAMP["outline"])
	_draw_px_rect(Vector2(-5.5, head_y), Vector2(11, 11), COLOR_RAMP["hair_black"])
	_draw_px_rect(Vector2(-4, head_y + 8), Vector2(8, 7), COLOR_RAMP["hair_black"])
	_draw_px_rect(Vector2(-3.5, head_y - 7), Vector2(7, 7), COLOR_RAMP["hair_black"])
	_draw_px_rect(Vector2(-6, head_y - 4.5), Vector2(12, 2.0), Color(0.40, 0.95, 0.75))

## 辅助函数：绘制对齐像素网格的矩形块
func _draw_px_rect(pos: Vector2, sz: Vector2, col: Color) -> void:
	draw_rect(Rect2(pos, sz), col)

## 辅助函数：绘制星露谷精致像素小剑
func _draw_stardew_sword(pos: Vector2, rot: float) -> void:
	var t := Transform2D(rot, pos)
	# 银亮锋刃
	var blade_pts: PackedVector2Array = [
		t * Vector2(0, -20),
		t * Vector2(3.0, -15),
		t * Vector2(3.0, 5),
		t * Vector2(-3.0, 5),
		t * Vector2(-3.0, -15)
	]
	draw_colored_polygon(blade_pts, Color(0.92, 0.95, 1.0))
	draw_polyline(blade_pts, COLOR_RAMP["outline"], 1.2, true)
	draw_line(t * Vector2(0, -18), t * Vector2(0, 5), Color(0.68, 0.78, 0.90), 1.2)
	# 金色剑格
	var guard_r := Rect2(t * Vector2(-5, 5), Vector2(10, 3.0))
	draw_rect(guard_r, COLOR_RAMP["belt_buckle"])
	# 木色剑柄与红剑穗
	draw_line(t * Vector2(0, 8), t * Vector2(0, 13), Color(0.35, 0.22, 0.15), 1.8)
	draw_line(t * Vector2(0, 13), t * Vector2(1.5, 18), COLOR_RAMP["tassel_red"], 1.8)
