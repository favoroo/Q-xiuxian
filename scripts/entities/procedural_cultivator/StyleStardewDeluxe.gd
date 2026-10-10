class_name StyleStardewDeluxe
extends CultivatorBase

## 风格 C 豪华版：星露谷 / 风来之国现代精致像素 · 天青桃花剑侠 (Pixel Deluxe)
## 特征：
## 1. 现代 16-bit 艺术级微像素：暗色像素勾边与高光像素抖动
## 2. 头戴微倾的精编竹斗笠，额前散落飘逸碎发
## 3. 天青月华流云道袍，素净无腰封
## 4. 腰悬赤朱仙家酒葫芦与羊脂白玉佩，桃花金装秋水长剑

const OUTLINE := Color(0.12, 0.14, 0.18)
const PALETTE := {
	"hat_light": Color(0.88, 0.74, 0.52),     # 竹斗笠受光
	"hat_mid": Color(0.72, 0.56, 0.36),       # 竹斗笠编织
	"hat_dark": Color(0.50, 0.36, 0.22),      # 竹斗笠阴影
	"hat_ribbon": Color(0.20, 0.30, 0.38),    # 斗笠系带
	"hair": Color(0.14, 0.16, 0.20),
	"hair_high": Color(0.30, 0.35, 0.44),
	"skin": Color(0.98, 0.85, 0.74),
	"skin_shadow": Color(0.88, 0.72, 0.60),
	"robe_light": Color(0.52, 0.78, 0.88),    # 天青浅云
	"robe_mid": Color(0.32, 0.60, 0.72),      # 天青主调
	"robe_dark": Color(0.20, 0.42, 0.52),     # 天青深影
	"white_inner": Color(0.95, 0.96, 0.98),   # 月华素白
	"belt": Color(0.22, 0.24, 0.30),          # 剑柄丝绦玄墨
	"gold": Color(0.96, 0.82, 0.28),          # 纯金饰扣
	"gourd": Color(0.85, 0.30, 0.22),         # 赤朱酒葫芦
	"jade": Color(0.85, 0.96, 0.92),          # 羊脂白玉
	"shoes": Color(0.16, 0.18, 0.22)
}

func _draw_front() -> void:
	var bob := sin(_time * 3.4) * 1.3 if animate else 0.0

	# 1. 柔和像素地影
	_px_rect(Vector2(-13, 27), Vector2(26, 5), Color(0.08, 0.12, 0.16, 0.28))

	# 2. 背后斜插秋水长剑（露出剑柄与桃花金格）
	_draw_peach_sword(Vector2(8, -4 + bob), deg_to_rad(30.0))

	# 3. 踩踏地面的玄靴
	_px_rect(Vector2(-7, 22), Vector2(5, 6), OUTLINE)
	_px_rect(Vector2(-6, 23), Vector2(4, 4), PALETTE["shoes"])
	_px_rect(Vector2(2, 22), Vector2(5, 6), OUTLINE)
	_px_rect(Vector2(3, 23), Vector2(4, 4), PALETTE["shoes"])

	# 4. 下裳长裙（天青色阶与深色像素勾边）
	_px_rect(Vector2(-10, 8 + bob), Vector2(20, 16), OUTLINE)
	_px_rect(Vector2(-9, 9 + bob), Vector2(18, 14), PALETTE["robe_mid"])
	_px_rect(Vector2(-9, 9 + bob), Vector2(8, 14), PALETTE["robe_light"])
	_px_rect(Vector2(5, 9 + bob), Vector2(4, 14), PALETTE["robe_dark"])
	# 中缝月白内衬露出
	_px_rect(Vector2(-1, 14 + bob), Vector2(2, 9), PALETTE["white_inner"])

	# 5. 上身躯干与交领
	_px_rect(Vector2(-9, -4 + bob), Vector2(18, 14), OUTLINE)
	_px_rect(Vector2(-8, -3 + bob), Vector2(16, 12), PALETTE["robe_mid"])
	_px_rect(Vector2(-8, -3 + bob), Vector2(7, 12), PALETTE["robe_light"])
	# 月白交领叠衽（V字）
	_px_rect(Vector2(-4, -4 + bob), Vector2(8, 5), PALETTE["white_inner"])
	_px_rect(Vector2(-2, -4 + bob), Vector2(4, 3), PALETTE["skin"])

	# 6. 赤朱酒葫芦 + 羊脂白玉佩
	# 左侧悬挂赤朱仙家酒葫芦
	var gourd_pos := Vector2(-7, 8 + bob)
	_px_rect(gourd_pos, Vector2(4, 6), PALETTE["gourd"])
	_px_rect(gourd_pos + Vector2(1, -2), Vector2(2, 2), PALETTE["hat_mid"]) # 葫芦塞
	_px_rect(gourd_pos + Vector2(1, 1), Vector2(1, 2), Color(1.0, 0.6, 0.5)) # 葫芦高光

	# 右侧垂挂羊脂白玉佩与金流苏
	var jade_pos := Vector2(3, 8 + bob)
	_px_rect(jade_pos, Vector2(3, 3.5), PALETTE["jade"])
	_px_rect(jade_pos + Vector2(1, 3.5), Vector2(1.5, 5), PALETTE["gold"])

	# 7. 双臂与衣袖
	_px_rect(Vector2(-12, -3 + bob), Vector2(4, 12), OUTLINE)
	_px_rect(Vector2(-11, -2 + bob), Vector2(3, 10), PALETTE["robe_light"])
	_px_rect(Vector2(8, -3 + bob), Vector2(4, 12), OUTLINE)
	_px_rect(Vector2(8, -2 + bob), Vector2(3, 10), PALETTE["robe_dark"])
	_px_rect(Vector2(-10, 8 + bob), Vector2(2.5, 2.5), PALETTE["skin"])
	_px_rect(Vector2(8.5, 8 + bob), Vector2(2.5, 2.5), PALETTE["skin"])

	# 8. 头部容貌与灵动双目
	var head_y := -18.0 + bob
	_px_rect(Vector2(-6, head_y), Vector2(12, 11), PALETTE["skin"])
	_px_rect(Vector2(-6, head_y + 8), Vector2(12, 3), PALETTE["skin_shadow"])
	# 清亮像素星眸（深墨双目带纯白高光点）
	_px_rect(Vector2(-4, head_y + 4), Vector2(2.5, 3.0), PALETTE["hair"])
	_px_rect(Vector2(-4, head_y + 4), Vector2(1.0, 1.2), Color.WHITE)
	_px_rect(Vector2(1.5, head_y + 4), Vector2(2.5, 3.0), PALETTE["hair"])
	_px_rect(Vector2(1.5, head_y + 4), Vector2(1.0, 1.2), Color.WHITE)
	# 脸颊淡红晕
	_px_rect(Vector2(-5, head_y + 7.2), Vector2(2, 1.2), Color(0.95, 0.60, 0.55, 0.7))
	_px_rect(Vector2(3, head_y + 7.2), Vector2(2, 1.2), Color(0.95, 0.60, 0.55, 0.7))

	# 9. 额前飘逸发丝与精编竹斗笠
	_px_rect(Vector2(-6, head_y - 1), Vector2(12, 3), PALETTE["hair"])
	_px_rect(Vector2(-6.5, head_y + 2), Vector2(2, 7), PALETTE["hair"]) # 左侧鬓发
	_px_rect(Vector2(4.5, head_y + 2), Vector2(2, 7), PALETTE["hair"])  # 右侧鬓发

	# 竹斗笠（微倾，经典仙侠斗笠多边形）
	var hat_y := head_y - 3.0
	var hat_pts: PackedVector2Array = [
		Vector2(0, hat_y - 8),     # 斗笠尖顶
		Vector2(17, hat_y + 2),    # 右侧宽帽沿
		Vector2(-17, hat_y + 1)    # 左侧微扬帽沿
	]
	draw_colored_polygon(hat_pts, PALETTE["hat_mid"])
	# 斗笠高光受光面
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, hat_y - 8), Vector2(-17, hat_y + 1), Vector2(0, hat_y)
	]), PALETTE["hat_light"])
	draw_polyline(hat_pts, OUTLINE, 1.4, true)
	# 斗笠编织环线
	draw_line(Vector2(-10, hat_y - 2), Vector2(10, hat_y - 1), PALETTE["hat_dark"], 1.5)

	# 斗笠下垂的青玄系带（随风微飘）
	var ribbon_sway := sin(_time * 4.0) * 2.0 if animate else 0.0
	draw_line(Vector2(-8, hat_y + 1), Vector2(-11 + ribbon_sway, hat_y + 16), PALETTE["hat_ribbon"], 1.6)

func _draw_side() -> void:
	var bob := sin(_time * 3.4) * 1.3 if animate else 0.0
	var ribbon_sway := sin(_time * 4.5) * 3.0 if animate else 0.0

	# 1. 地影
	_px_rect(Vector2(-10, 27), Vector2(22, 5), Color(0.08, 0.12, 0.16, 0.28))

	# 2. 侧行脚步
	_px_rect(Vector2(-6, 22), Vector2(5, 6), OUTLINE)
	_px_rect(Vector2(-5, 23), Vector2(4, 4), PALETTE["shoes"])
	_px_rect(Vector2(3, 22), Vector2(5, 6), OUTLINE)
	_px_rect(Vector2(4, 23), Vector2(4, 4), PALETTE["shoes"])

	# 3. 侧身天青道袍
	_px_rect(Vector2(-8, 8 + bob), Vector2(16, 16), OUTLINE)
	_px_rect(Vector2(-7, 9 + bob), Vector2(14, 14), PALETTE["robe_mid"])
	_px_rect(Vector2(1, 9 + bob), Vector2(6, 14), PALETTE["robe_light"])

	# 4. 侧身上身与酒葫芦
	_px_rect(Vector2(-7, -4 + bob), Vector2(14, 14), OUTLINE)
	_px_rect(Vector2(-6, -3 + bob), Vector2(12, 12), PALETTE["robe_mid"])
	_px_rect(Vector2(0, -3 + bob), Vector2(6, 12), PALETTE["robe_light"])

	# 侧身酒葫芦
	_px_rect(Vector2(-8, 7 + bob), Vector2(4, 6), PALETTE["gourd"])

	# 5. 侧面头部
	var head_y := -18.0 + bob
	_px_rect(Vector2(-4, head_y), Vector2(10, 11), PALETTE["skin"])
	# 单侧星眸
	_px_rect(Vector2(1.5, head_y + 4), Vector2(2.5, 3.0), PALETTE["hair"])
	_px_rect(Vector2(1.5, head_y + 4), Vector2(1.0, 1.2), Color.WHITE)
	# 侧面长发垂落
	_px_rect(Vector2(-6, head_y + 2), Vector2(4, 12), PALETTE["hair"])

	# 侧面竹斗笠（斜戴，轮廓极飒）
	var hat_pts: PackedVector2Array = [
		Vector2(-2, head_y - 10),
		Vector2(16, head_y + 1),
		Vector2(-16, head_y - 1)
	]
	draw_colored_polygon(hat_pts, PALETTE["hat_mid"])
	draw_polyline(hat_pts, OUTLINE, 1.4, true)
	# 斗笠系带向后飘扬
	draw_line(Vector2(-6, head_y), Vector2(-18 + ribbon_sway, head_y + 14), PALETTE["hat_ribbon"], 1.8)

	# 6. 单手持桃花青锋剑前指
	_px_rect(Vector2(4, 0 + bob), Vector2(6, 4), OUTLINE)
	_px_rect(Vector2(5, 1 + bob), Vector2(5, 3), PALETTE["robe_light"])
	_px_rect(Vector2(9.5, 1 + bob), Vector2(2.5, 2.5), PALETTE["skin"])
	_draw_peach_sword(Vector2(20, -3 + bob), deg_to_rad(65.0))

func _draw_back() -> void:
	var bob := sin(_time * 3.4) * 1.3 if animate else 0.0

	# 1. 地影
	_px_rect(Vector2(-13, 27), Vector2(26, 5), Color(0.08, 0.12, 0.16, 0.28))

	# 2. 背后垂直背负的秋水长剑与雕纹剑鞘
	_draw_peach_sword(Vector2(0, 0 + bob), deg_to_rad(0.0))

	# 3. 双足
	_px_rect(Vector2(-7, 22), Vector2(5, 6), OUTLINE)
	_px_rect(Vector2(-6, 23), Vector2(4, 4), PALETTE["shoes"])
	_px_rect(Vector2(2, 22), Vector2(5, 6), OUTLINE)
	_px_rect(Vector2(3, 23), Vector2(4, 4), PALETTE["shoes"])

	# 4. 后背长裙
	_px_rect(Vector2(-10, 8 + bob), Vector2(20, 16), OUTLINE)
	_px_rect(Vector2(-9, 9 + bob), Vector2(18, 14), PALETTE["robe_mid"])
	_px_rect(Vector2(-1, 9 + bob), Vector2(2, 14), PALETTE["robe_dark"])

	# 5. 上身后背与酒葫芦
	_px_rect(Vector2(-9, -4 + bob), Vector2(18, 14), OUTLINE)
	_px_rect(Vector2(-8, -3 + bob), Vector2(16, 12), PALETTE["robe_mid"])
	_px_rect(Vector2(-8, 7 + bob), Vector2(4, 6), PALETTE["gourd"])

	# 6. 后脑发丝与从上俯视的竹斗笠
	var head_y := -18.0 + bob
	_px_rect(Vector2(-5, head_y + 6), Vector2(10, 9), PALETTE["hair"]) # 垂于背后的整齐发丝

	# 俯视圆形竹斗笠
	var hat_center := Vector2(0, head_y - 2)
	draw_filled_ellipse(hat_center, 18.0, 10.0, PALETTE["hat_mid"])
	draw_filled_ellipse(hat_center, 9.0, 5.0, PALETTE["hat_light"])
	draw_stroked_ellipse(hat_center, 18.0, 10.0, PALETTE["hat_mid"], OUTLINE, 1.4)
	draw_arc(hat_center, 13.0, 0, TAU, 24, PALETTE["hat_dark"], 1.2, true)

func _px_rect(pos: Vector2, sz: Vector2, col: Color) -> void:
	draw_rect(Rect2(pos, sz), col)

## 绘制桃花金装秋水长剑
func _draw_peach_sword(pos: Vector2, rot: float) -> void:
	var t := Transform2D(rot, pos)
	# 秋水银刃
	var blade_pts: PackedVector2Array = [
		t * Vector2(0, -22),
		t * Vector2(3.0, -17),
		t * Vector2(2.8, 5),
		t * Vector2(-2.8, 5),
		t * Vector2(-3.0, -17)
	]
	draw_colored_polygon(blade_pts, Color(0.92, 0.96, 1.0))
	draw_polyline(blade_pts, OUTLINE, 1.2, true)
	draw_line(t * Vector2(0, -20), t * Vector2(0, 5), Color(0.65, 0.80, 0.95), 1.2)

	# 桃花五瓣金剑格
	var guard_pos := t * Vector2(0, 6)
	draw_circle(guard_pos, 4.0, PALETTE["gold"])
	draw_circle(guard_pos, 2.0, Color(1.0, 0.75, 0.85)) # 粉白桃花心

	# 剑柄与真丝金红流苏
	draw_line(t * Vector2(0, 8), t * Vector2(0, 14), PALETTE["belt"], 2.0)
	draw_line(t * Vector2(0, 14), t * Vector2(2, 20), Color(0.90, 0.25, 0.25), 1.8)
