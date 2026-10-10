class_name CultivatorVisualConfig
extends Resource

## 修仙角色视觉与配件标准配置规范（土豆兄弟式参数化驱动）
## 基于统一修仙素体与 4 大外观插槽（体型、面部、斗篷、武器），实现角色的极速拓展与差异化

# ----------------- 4 大插槽字典配置 -----------------

## 1. 体型与比例插槽 (Body Proportions)
## scale: 整体缩放 | width_scale: 肩宽胖瘦 | height_scale: 高矮比例 | head_scale: 头身比
@export var body: Dictionary = {
	"scale": 1.0,
	"width_scale": 1.0,
	"height_scale": 1.0,
	"head_scale": 1.0
}

## 2. 面部与首服插槽 (Face & Head Gear)
## mask_style: "oval_chin" (鹅蛋尖), "square_rock" (方岩), "round_petite" (娇小圆), "sharp_fox" (敏锐狐), "stout_brute" (粗犷蛮)
## horns_style: "butterfly" (蝶角), "dao_bun" (道髻木簪), "bamboo_hat" (斗笠), "talisman" (悬符), "gold_crown" (金冠), "bull_horns" (牛角), "fox_ears" (狐耳), "none" (光洁)
## eye_style: "hollow_oval" (经典深渊), "sharp_slit" (冷眸细线), "round_pupil" (道童圆目), "angry_slit" (怒目)
@export var face: Dictionary = {
	"mask_style": "oval_chin",
	"horns_style": "butterfly",
	"eye_style": "hollow_oval",
	"eye_color": Color(0.75, 0.92, 1.0, 0.45),
	"eye_core_color": Color(0.98, 1.0, 1.0)
}

## 3. 斗篷与色彩插槽 (Cloak & Palette)
## cloak_style: "split_flowing" (双层裂帛飞扬), "heavy_overcoat" (厚重大氅), "short_cape" (灵动短披), "tattered_rags" (破损残袍), "royal_shawl" (云肩霞帔)
## chest_ornament: "pearl" (灵珠), "bagua" (八卦镜), "coin" (金钱), "skull" (兽骨), "none" (无)
@export var cloak: Dictionary = {
	"cloak_style": "split_flowing",
	"col_outer": Color(0.11, 0.24, 0.17),     # 外袍深色
	"col_inner": Color(0.18, 0.38, 0.28),     # 内衬底色
	"col_edge": Color(0.28, 0.62, 0.46),      # 边缘月辉光
	"chest_ornament": "pearl"
}

## 4. 背负本命法器插槽 (Back Artifact / Weapon)
## weapon_type: "bone_nail" (骨钉剑), "stone_pillar" (玄石尺/碑), "peach_sword" (桃木剑), "golden_abacus" (金算盘),
##              "shadow_daggers" (暗影双刃), "broken_blade" (厚背断刀), "bone_axe" (巨兽骨斧), "soul_banner" (招魂幡), "treasure_chest" (多宝匣)
## carry_front_pos / carry_front_rot / carry_side_pos / carry_side_rot / carry_back_pos / carry_back_rot:
##              可选的背负位姿覆盖。头饰宽大（蛮修双角、刀圣斗笠）或法器填充色接近骨白时，
##              要用它把法器挪到头部轮廓之外，否则会画成"法器长在脸上"。缺省值见渲染器 CARRY_* 常量。
@export var weapon: Dictionary = {
	"weapon_type": "bone_nail",
	"col_main": Color(0.95, 0.97, 1.0),
	"col_shadow": Color(0.70, 0.78, 0.86),
	"col_accent": Color(1.0, 1.0, 1.0, 0.9),
	"strap_style": "diagonal" # "diagonal" 斜跨带, "dual" 双肩带, "floating" 悬浮御物
}

## 基础骨相基础色（全员统一的骨玉基底）
@export var bone_white: Color = Color(0.96, 0.97, 0.99)
@export var bone_shadow: Color = Color(0.76, 0.82, 0.88)
@export var void_black: Color = Color(0.06, 0.07, 0.10)

## 向后兼容色盘字典
@export var palette: Dictionary = {}

func _init() -> void:
	_sync_palette()

func _sync_palette() -> void:
	palette = {
		"void_black": void_black,
		"bone_white": bone_white,
		"bone_shadow": bone_shadow,
		"eye_glow": face.get("eye_color", Color(0.75, 0.92, 1.0, 0.45)),
		"eye_core": face.get("eye_core_color", Color(0.98, 1.0, 1.0)),
		"cloak_outer": cloak.get("col_outer", Color(0.11, 0.24, 0.17)),
		"cloak_inner": cloak.get("col_inner", Color(0.18, 0.38, 0.28)),
		"cloak_edge": cloak.get("col_edge", Color(0.28, 0.62, 0.46)),
		"nail_white": weapon.get("col_main", Color(0.95, 0.97, 1.0)),
		"nail_shadow": weapon.get("col_shadow", Color(0.70, 0.78, 0.86)),
		"slash_arc": Color(0.92, 0.98, 1.0, 0.95),
		"slash_glow": cloak.get("col_edge", Color(0.40, 0.85, 0.70, 0.4))
	}

# ==============================================================================
# 9 大道统官方预设工厂（土豆兄弟式参数化注册表）
# ==============================================================================

## 根据道统 ID 一键获取官方视觉配置
static func get_config(character_id: String) -> CultivatorVisualConfig:
	match character_id:
		"shiyue":
			return make_shiyue()
		"fuzhen":
			return make_fuzhen()
		"jinsuanpan":
			return make_jinsuanpan()
		"meiying":
			return make_meiying()
		"dubi", "duanbi":
			return make_duanbi()
		"kuangzhan":
			return make_kuangzhan()
		"duoshe":
			return make_duoshe()
		"duobao":
			return make_duobao()
		"jianchi", _:
			return make_jianchi()

## 向后兼容
static func make_green_hollow_knight() -> CultivatorVisualConfig:
	return make_jianchi()

# 1. 青云剑修·独孤（轻灵冷傲，一身转战三千里，一剑曾当百万师）
static func make_jianchi() -> CultivatorVisualConfig:
	var cfg := CultivatorVisualConfig.new()
	cfg.body = { "scale": 1.0, "width_scale": 1.0, "height_scale": 1.0, "head_scale": 1.0 }
	cfg.face = {
		"mask_style": "oval_chin",
		"horns_style": "butterfly",
		"eye_style": "hollow_oval",
		"eye_color": Color(0.75, 0.92, 1.0, 0.45),
		"eye_core_color": Color(0.98, 1.0, 1.0)
	}
	cfg.cloak = {
		"cloak_style": "split_flowing",
		"col_outer": Color(0.11, 0.24, 0.17),     # 深邃墨绿
		"col_inner": Color(0.18, 0.38, 0.28),     # 青碧月影
		"col_edge": Color(0.28, 0.62, 0.46),      # 冷玉月辉
		"chest_ornament": "pearl"
	}
	cfg.weapon = {
		"weapon_type": "bone_nail",
		"col_main": Color(0.95, 0.97, 1.0),
		"col_shadow": Color(0.70, 0.78, 0.86),
		"col_accent": Color(1.0, 1.0, 1.0, 0.9),
		"strap_style": "diagonal"
	}
	cfg._sync_palette()
	return cfg

# 2. 石岳·体修（肉身成圣，高血高甲，磐石厚土，巍峨如山）
static func make_shiyue() -> CultivatorVisualConfig:
	var cfg := CultivatorVisualConfig.new()
	cfg.body = { "scale": 1.18, "width_scale": 1.25, "height_scale": 1.02, "head_scale": 0.96 }
	cfg.face = {
		"mask_style": "square_rock",
		"horns_style": "bull_horns",
		"eye_style": "angry_slit",
		"eye_color": Color(1.0, 0.65, 0.25, 0.55), # 磐石厚土琥珀金光
		"eye_core_color": Color(1.0, 0.92, 0.65)
	}
	cfg.cloak = {
		"cloak_style": "heavy_overcoat",
		"col_outer": Color(0.22, 0.18, 0.15),     # 玄岩深褐
		"col_inner": Color(0.35, 0.28, 0.22),     # 赭石厚土
		"col_edge": Color(0.72, 0.52, 0.32),      # 古金岩纹
		"chest_ornament": "skull"
	}
	cfg.weapon = {
		"weapon_type": "stone_pillar",
		"col_main": Color(0.42, 0.44, 0.48),      # 墨青玄铁重尺
		"col_shadow": Color(0.24, 0.26, 0.30),
		"col_accent": Color(0.85, 0.65, 0.35),
		"strap_style": "dual"
	}
	cfg._sync_palette()
	return cfg

# 3. 符阵灵童（御灵驱蝶，以众凌寡，娇小玲珑，道法自然）
static func make_fuzhen() -> CultivatorVisualConfig:
	var cfg := CultivatorVisualConfig.new()
	cfg.body = { "scale": 0.85, "width_scale": 0.92, "height_scale": 0.95, "head_scale": 1.14 }
	cfg.face = {
		"mask_style": "round_petite",
		"horns_style": "dao_bun",
		"eye_style": "round_pupil",
		"eye_color": Color(0.35, 0.85, 1.0, 0.5), # 清澈灵动天青蓝
		"eye_core_color": Color(0.85, 0.98, 1.0)
	}
	cfg.cloak = {
		"cloak_style": "short_cape",
		"col_outer": Color(0.36, 0.16, 0.14),     # 朱砂赤红
		"col_inner": Color(0.55, 0.38, 0.18),     # 杏黄道袍
		"col_edge": Color(0.95, 0.78, 0.30),      # 金符流光
		"chest_ornament": "bagua"
	}
	cfg.weapon = {
		"weapon_type": "peach_sword",
		"col_main": Color(0.76, 0.42, 0.24),      # 辟邪千年桃木
		"col_shadow": Color(0.48, 0.24, 0.12),
		"col_accent": Color(1.0, 0.85, 0.30),
		"strap_style": "diagonal"
	}
	cfg._sync_palette()
	return cfg

# 4. 散修·金算盘（灵田生金，富态圆润，以利证道，满面财光）
static func make_jinsuanpan() -> CultivatorVisualConfig:
	var cfg := CultivatorVisualConfig.new()
	cfg.body = { "scale": 1.06, "width_scale": 1.20, "height_scale": 0.98, "head_scale": 1.02 }
	cfg.face = {
		"mask_style": "round_petite",
		"horns_style": "gold_crown",
		"eye_style": "sharp_slit",
		"eye_color": Color(1.0, 0.82, 0.20, 0.6), # 聚宝黄金财光
		"eye_core_color": Color(1.0, 0.98, 0.75)
	}
	cfg.cloak = {
		"cloak_style": "royal_shawl",
		"col_outer": Color(0.12, 0.18, 0.32),     # 宝蓝绸缎
		"col_inner": Color(0.32, 0.24, 0.12),     # 铜金内衬
		"col_edge": Color(0.98, 0.82, 0.24),      # 纯金滚边
		"chest_ornament": "coin"
	}
	cfg.weapon = {
		"weapon_type": "golden_abacus",
		"col_main": Color(0.92, 0.76, 0.22),      # 紫檀纯金算盘
		"col_shadow": Color(0.56, 0.42, 0.12),
		"col_accent": Color(1.0, 0.95, 0.60),
		"strap_style": "diagonal"
	}
	cfg._sync_palette()
	return cfg

# 5. 魅影·幽娘（身法入微，冷艳轻盈，如梦似幻，暗夜幽魂）
static func make_meiying() -> CultivatorVisualConfig:
	var cfg := CultivatorVisualConfig.new()
	cfg.body = { "scale": 0.95, "width_scale": 0.88, "height_scale": 1.04, "head_scale": 0.98 }
	cfg.face = {
		"mask_style": "sharp_fox",
		"horns_style": "fox_ears",
		"eye_style": "sharp_slit",
		"eye_color": Color(0.82, 0.45, 1.0, 0.55), # 幽夜魅惑深紫
		"eye_core_color": Color(0.96, 0.85, 1.0)
	}
	cfg.cloak = {
		"cloak_style": "split_flowing",
		"col_outer": Color(0.14, 0.08, 0.20),     # 幽冥夜紫
		"col_inner": Color(0.24, 0.14, 0.34),     # 曼陀罗幽香
		"col_edge": Color(0.75, 0.45, 0.95),      # 暗夜流霞
		"chest_ornament": "pearl"
	}
	cfg.weapon = {
		"weapon_type": "shadow_daggers",
		"col_main": Color(0.30, 0.28, 0.36),      # 淬毒冷铁双匕
		"col_shadow": Color(0.16, 0.14, 0.22),
		"col_accent": Color(0.85, 0.40, 0.95),
		"strap_style": "dual"
	}
	cfg._sync_palette()
	return cfg

# 6. 独臂刀圣（断臂残躯，霸道无匹，江湖浪客，刀断天河）
static func make_duanbi() -> CultivatorVisualConfig:
	var cfg := CultivatorVisualConfig.new()
	cfg.body = { "scale": 1.08, "width_scale": 1.08, "height_scale": 1.02, "head_scale": 0.94 }
	cfg.face = {
		"mask_style": "oval_chin",
		"horns_style": "bamboo_hat",
		"eye_style": "sharp_slit",
		"eye_color": Color(0.95, 0.95, 1.0, 0.4),  # 冰冷肃杀白光
		"eye_core_color": Color(1.0, 1.0, 1.0)
	}
	cfg.cloak = {
		"cloak_style": "heavy_overcoat",
		"col_outer": Color(0.32, 0.12, 0.12),     # 狂血深绯
		"col_inner": Color(0.18, 0.12, 0.12),     # 焦褐炭黑
		"col_edge": Color(0.85, 0.35, 0.32),      # 刀芒赤焰
		"chest_ornament": "none"
	}
	cfg.weapon = {
		"weapon_type": "broken_blade",
		"col_main": Color(0.88, 0.90, 0.94),      # 厚背斩马狂刀
		"col_shadow": Color(0.52, 0.56, 0.62),
		"col_accent": Color(0.98, 0.35, 0.30),
		"strap_style": "diagonal",
		# 刀身与骨白面具几乎同色，且竹斗笠横挑很宽：把刀压到斗笠下方、肩外再探出来
		"carry_front_pos": Vector2(9.5, 8.0), "carry_front_rot": 214.0,
		"carry_side_pos": Vector2(-7.5, 8.0), "carry_side_rot": -12.0,
	}
	cfg._sync_palette()
	return cfg

static func make_dubi() -> CultivatorVisualConfig:
	return make_duanbi()

# 7. 狂战蛮修（嗜血狂暴，妖潮战神，双角擎天，力拔山兮）
static func make_kuangzhan() -> CultivatorVisualConfig:
	var cfg := CultivatorVisualConfig.new()
	cfg.body = { "scale": 1.22, "width_scale": 1.26, "height_scale": 1.04, "head_scale": 0.94 }
	cfg.face = {
		"mask_style": "stout_brute",
		"horns_style": "bull_horns",
		"eye_style": "angry_slit",
		"eye_color": Color(1.0, 0.22, 0.18, 0.65), # 暴怒嗜血猩红
		"eye_core_color": Color(1.0, 0.85, 0.85)
	}
	cfg.cloak = {
		"cloak_style": "tattered_rags",
		"col_outer": Color(0.24, 0.08, 0.08),     # 暗赤血污
		"col_inner": Color(0.15, 0.05, 0.05),     # 焦骨黑
		"col_edge": Color(0.85, 0.25, 0.20),      # 狂暴战意
		"chest_ornament": "skull"
	}
	cfg.weapon = {
		"weapon_type": "bone_axe",
		"col_main": Color(0.92, 0.90, 0.85),      # 蛮荒巨兽头骨双刃斧
		"col_shadow": Color(0.62, 0.58, 0.52),
		"col_accent": Color(0.95, 0.20, 0.20),
		"strap_style": "diagonal",
		# 骨斧同样近骨白，而蛮修双角横挑到 x=±26：把斧子整体压到下巴以下横躺，
		# 斧刃朝上从右肩外探出，避开双角与面具那两圈白
		"carry_front_pos": Vector2(14.0, 12.0), "carry_front_rot": 8.0,
		"carry_side_pos": Vector2(-8.0, 9.0), "carry_side_rot": -10.0,
	}
	cfg._sync_palette()
	return cfg

# 8. 夺舍散人（九幽幽冥，借尸还魂，破衣烂衫，魂火幽幽）
static func make_duoshe() -> CultivatorVisualConfig:
	var cfg := CultivatorVisualConfig.new()
	cfg.body = { "scale": 0.96, "width_scale": 0.90, "height_scale": 1.0, "head_scale": 1.0 }
	cfg.face = {
		"mask_style": "sharp_fox",
		"horns_style": "talisman",
		"eye_style": "hollow_oval",
		"eye_color": Color(0.25, 0.95, 0.55, 0.6), # 九幽冥灵幽绿
		"eye_core_color": Color(0.82, 1.0, 0.90)
	}
	cfg.cloak = {
		"cloak_style": "tattered_rags",
		"col_outer": Color(0.08, 0.16, 0.14),     # 尸青阴绿
		"col_inner": Color(0.05, 0.10, 0.09),     # 阴司冥黑
		"col_edge": Color(0.35, 0.85, 0.60),      # 幽魂残火
		"chest_ornament": "skull"
	}
	cfg.weapon = {
		"weapon_type": "soul_banner",
		"col_main": Color(0.20, 0.22, 0.25),      # 墨竹招魂灵幡
		"col_shadow": Color(0.10, 0.12, 0.15),
		"col_accent": Color(0.40, 1.0, 0.70),
		"strap_style": "diagonal"
	}
	cfg._sync_palette()
	return cfg

# 9. 多宝道人（法宝齐出，锦绣华贵，七彩霞帔，福禄双全）
static func make_duobao() -> CultivatorVisualConfig:
	var cfg := CultivatorVisualConfig.new()
	cfg.body = { "scale": 1.10, "width_scale": 1.16, "height_scale": 1.0, "head_scale": 1.0 }
	cfg.face = {
		"mask_style": "round_petite",
		"horns_style": "gold_crown",
		"eye_style": "round_pupil",
		"eye_color": Color(0.95, 0.75, 1.0, 0.55), # 紫金宝气祥光
		"eye_core_color": Color(1.0, 0.95, 1.0)
	}
	cfg.cloak = {
		"cloak_style": "royal_shawl",
		"col_outer": Color(0.25, 0.12, 0.32),     # 紫极天华
		"col_inner": Color(0.38, 0.20, 0.45),     # 锦绣烟霞
		"col_edge": Color(0.98, 0.85, 0.35),      # 七宝金光
		"chest_ornament": "coin"
	}
	cfg.weapon = {
		"weapon_type": "treasure_chest",
		"col_main": Color(0.72, 0.48, 0.20),      # 紫金乾坤万宝匣
		"col_shadow": Color(0.42, 0.28, 0.10),
		"col_accent": Color(0.98, 0.88, 0.45),
		"strap_style": "dual"
	}
	cfg._sync_palette()
	return cfg
