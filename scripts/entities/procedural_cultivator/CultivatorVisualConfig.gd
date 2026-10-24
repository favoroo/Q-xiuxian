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
## horns_style: "butterfly" (蝶角), "dao_bun" (道髻木簪), "twin_buns" (童子双丫髻), "bamboo_hat" (斗笠), "talisman" (悬符), "gold_crown" (金冠), "bull_horns" (牛角), "barbarian_horns" (蛮荒重战角), "fox_ears" (狐耳), "none" (光洁)
## eye_style: "hollow_oval" (经典深渊), "sharp_slit" (冷眸细线), "round_pupil" (道童圆目), "round_bright" (童子亮眼), "angry_slit" (怒目)
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

## 4. 背负本命武器插槽 (Back Artifact / Weapon)
## weapon_type: "bone_nail" (骨钉剑), "stone_pillar" (玄石尺/碑), "peach_sword" (桃木剑), "golden_abacus" (金算盘),
##              "shadow_daggers" (暗影双刃), "broken_blade" (厚背断刀), "bone_axe" (巨兽骨斧), "soul_banner" (招魂幡), "treasure_chest" (多宝匣),
##              "assorted_bundle" (麻绳捆扎的一捆杂兵器，散修)
## carry_front_pos / carry_front_rot / carry_side_pos / carry_side_rot / carry_back_pos / carry_back_rot:
##              可选的背负位姿覆盖。头饰宽大（蛮修双角、刀圣斗笠）或武器填充色接近骨白时，
##              要用它把武器挪到头部轮廓之外，否则会画成"武器长在脸上"。缺省值见渲染器 CARRY_* 常量。
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

## 炫彩皮肤动画参数（空字典 = 普通静态换色）
## 由 SkinData.apply_to_config() 从主题 "chroma" 键整份拷入，渲染器只读消费：
## cycle 秒/圈、hue_offsets 各部位相位偏移、sheen 袍面油膜强度、rim_glow 缘边常驻流光强度。
@export var chroma: Dictionary = {}

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
static var _cache: Dictionary = {}  ## character_id -> 配置；配置创建后只读，可安全共享

static func get_config(character_id: String) -> CultivatorVisualConfig:
	var cached: CultivatorVisualConfig = _cache.get(character_id, null)
	if cached != null:
		return cached
	var cfg := _build_config(character_id)
	_cache[character_id] = cfg
	return cfg

static func _build_config(character_id: String) -> CultivatorVisualConfig:
	match character_id:
		"shiyue":
			return make_shiyue()
		"fuzhen":
			return make_fuzhen()
		"jinsuanpan":
			return make_jinsuanpan()
		"meiying":
			return make_meiying()
		"dubi":
			return make_dubi()
		"kuangzhan":
			return make_kuangzhan()
		"duoshe":
			return make_duoshe()
		"duobao":
			return make_duobao()
		"lingzhifu":
			return make_lingzhifu()
		"leifa":
			return make_leifa()
		"jiguan":
			return make_jiguan()
		"yaowang":
			return make_yaowang()
		"shoucainu":
			return make_shoucainu()
		"shixue":
			return make_shixue()
		"fuxiu":
			return make_fuxiu()
		"bawang":
			return make_bawang()
		"juechen":
			return make_juechen()
		"yushou":
			return make_yushou()
		"kuxingseng":
			return make_kuxingseng()
		"sanxiu":
			return make_sanxiu()
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
# 体型 2026-10-24 减脂：宽度 1.25→1.10，块头往纵方向收（巍峨不臃肿）
# 配色 2026-10-24 岩灰化：原棕褐大氅与蛮兵兽皮棕撞色相，改玄岩青灰+岩缝琥珀金（磐石本相）
static func make_shiyue() -> CultivatorVisualConfig:
	var cfg := CultivatorVisualConfig.new()
	cfg.body = { "scale": 1.14, "width_scale": 1.10, "height_scale": 1.04, "head_scale": 0.96 }
	cfg.face = {
		"mask_style": "square_rock",
		"horns_style": "bull_horns",
		"eye_style": "angry_slit",
		"eye_color": Color(1.0, 0.65, 0.25, 0.55), # 磐石厚土琥珀金光
		"eye_core_color": Color(1.0, 0.92, 0.65)
	}
	cfg.cloak = {
		"cloak_style": "heavy_overcoat",
		"col_outer": Color(0.26, 0.29, 0.34),     # 玄岩深灰
		"col_inner": Color(0.42, 0.46, 0.52),     # 岩层青灰
		"col_edge": Color(0.85, 0.66, 0.32),      # 岩缝琥珀金
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

# 3. 灵蝶使（御蝶驱兽，以众凌寡，娇小玲珑，道法自然）
static func make_fuzhen() -> CultivatorVisualConfig:
	var cfg := CultivatorVisualConfig.new()
	cfg.body = { "scale": 0.85, "width_scale": 0.92, "height_scale": 0.95, "head_scale": 1.10 }
	cfg.face = {
		"mask_style": "round_petite",
		"horns_style": "butterfly_horns_petite",
		"eye_style": "round_bright",
		"eye_color": Color(0.35, 0.85, 1.0, 0.65), # 清澈灵动天青蓝
		"eye_core_color": Color(0.85, 0.98, 1.0)
	}
	cfg.cloak = {
		"cloak_style": "short_cape",
		"col_outer": Color(0.60, 0.22, 0.15),     # 明朱红短披
		"col_inner": Color(0.92, 0.84, 0.64),     # 米杏白中衣
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

# 4. 商人·金算盘（灵田生金，富态圆润，以利证道，满面财光）
static func make_jinsuanpan() -> CultivatorVisualConfig:
	var cfg := CultivatorVisualConfig.new()
	cfg.body = { "scale": 1.06, "width_scale": 1.20, "height_scale": 0.98, "head_scale": 1.02 }
	cfg.face = {
		"mask_style": "round_petite",
		"horns_style": "merchant_horns",
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

# 6. 狂战士（断臂残躯，霸道无匹，江湖浪客，刀断天河）
static func make_dubi() -> CultivatorVisualConfig:
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

## 向后兼容
static func make_duanbi() -> CultivatorVisualConfig:
	return make_dubi()

# 7. 蛮兵（荒古狂战，陷阵无双，铜金战角，金芒怒目，兽皮深褐百衲袍，蛮荒兽骨巨斧）
# 体型 2026-10-24 减脂：宽度 1.26→1.10，全角色第二宽的横桶身收成纵高块头
static func make_kuangzhan() -> CultivatorVisualConfig:
	var cfg := CultivatorVisualConfig.new()
	cfg.body = { "scale": 1.18, "width_scale": 1.10, "height_scale": 1.06, "head_scale": 0.94 }
	cfg.face = {
		"mask_style": "stout_brute",
		"horns_style": "barbarian_horns",
		"eye_style": "angry_slit",
		"eye_color": Color(1.0, 0.72, 0.16, 0.85), # 陷阵狂战炽金怒眸（彻底区分魔修猩红）
		"eye_core_color": Color(1.0, 0.96, 0.78)
	}
	cfg.cloak = {
		"cloak_style": "tattered_rags",
		"col_outer": Color(0.24, 0.16, 0.10),     # 荒原兽皮深棕褐
		"col_inner": Color(0.38, 0.24, 0.14),     # 焦土赭黄内衬
		"col_edge": Color(0.96, 0.76, 0.24),      # 陷阵战意炽金光辉
		"chest_ornament": "skull"
	}
	cfg.weapon = {
		"weapon_type": "bone_axe",
		"col_main": Color(0.92, 0.90, 0.85),      # 蛮荒巨兽头骨双刃斧
		"col_shadow": Color(0.62, 0.58, 0.52),
		"col_accent": Color(0.98, 0.78, 0.25),    # 战痕金铜光
		"strap_style": "diagonal",
		# 骨斧同样近骨白，而蛮修双角横挑到 x=±26：把斧子整体压到下巴以下横躺，
		# 斧刃朝上从右肩外探出，避开双角与面具那两圈白
		"carry_front_pos": Vector2(14.0, 12.0), "carry_front_rot": 8.0,
		"carry_side_pos": Vector2(-8.0, 10.0), "carry_side_rot": -10.0,
		# 背面位姿（2026-10-15 实机三向启用后补齐）：狂战体型 1.22 放大，默认背位
		# 斧刃会贴上后脑（穿模判据 kuangzhan/back 隔离带 0.83px < 2.0），整体再压低 2px
		"carry_back_pos": Vector2(2.0, 13.0), "carry_back_rot": 158.0,
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

# 9. 收藏家·多宝（道具齐出，锦绣华贵，七彩霞帔，福禄双全）
static func make_duobao() -> CultivatorVisualConfig:
	var cfg := CultivatorVisualConfig.new()
	cfg.body = { "scale": 1.10, "width_scale": 1.16, "height_scale": 1.0, "head_scale": 1.0 }
	cfg.face = {
		"mask_style": "round_petite",
		"horns_style": "collector_horns",
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

# 10. 灵植夫（躬耕灵田，福泽延绵，青草麦香，生生不息）
static func make_lingzhifu() -> CultivatorVisualConfig:
	var cfg := CultivatorVisualConfig.new()
	cfg.body = { "scale": 1.02, "width_scale": 1.08, "height_scale": 0.98, "head_scale": 1.04 }
	cfg.face = {
		"mask_style": "round_petite",
		"horns_style": "bamboo_hat",
		"eye_style": "round_pupil",
		"eye_color": Color(0.35, 0.88, 0.45, 0.55),
		"eye_core_color": Color(0.85, 1.0, 0.90)
	}
	cfg.cloak = {
		"cloak_style": "short_cape",
		"col_outer": Color(0.14, 0.28, 0.16),
		"col_inner": Color(0.35, 0.32, 0.14),
		"col_edge": Color(0.65, 0.88, 0.45),
		"chest_ornament": "none"
	}
	cfg.weapon = {
		"weapon_type": "peach_sword",
		"col_main": Color(0.48, 0.32, 0.18),
		"col_shadow": Color(0.28, 0.18, 0.10),
		"col_accent": Color(0.65, 0.88, 0.45),
		"strap_style": "diagonal"
	}
	cfg._sync_palette()
	return cfg

# 11. 雷法真君（天雷轰顶，万法归宗，紫电破空，仙威赫赫）
static func make_leifa() -> CultivatorVisualConfig:
	var cfg := CultivatorVisualConfig.new()
	cfg.body = { "scale": 1.05, "width_scale": 0.98, "height_scale": 1.06, "head_scale": 0.96 }
	cfg.face = {
		"mask_style": "oval_chin",
		"horns_style": "dao_bun",
		"eye_style": "sharp_slit",
		"eye_color": Color(0.55, 0.65, 1.0, 0.65),
		"eye_core_color": Color(0.92, 0.95, 1.0)
	}
	cfg.cloak = {
		"cloak_style": "split_flowing",
		"col_outer": Color(0.15, 0.12, 0.28),
		"col_inner": Color(0.22, 0.18, 0.38),
		"col_edge": Color(0.65, 0.75, 1.0),
		"chest_ornament": "bagua"
	}
	cfg.weapon = {
		"weapon_type": "bone_nail",
		"col_main": Color(0.68, 0.75, 0.95),
		"col_shadow": Color(0.35, 0.42, 0.65),
		"col_accent": Color(0.95, 0.92, 0.45),
		"strap_style": "diagonal"
	}
	cfg._sync_palette()
	return cfg

# 12. 机关师（百炼千机，甲阵锁岳，铜骨齿轮，巧夺天工）
static func make_jiguan() -> CultivatorVisualConfig:
	var cfg := CultivatorVisualConfig.new()
	cfg.body = { "scale": 0.98, "width_scale": 1.05, "height_scale": 0.98, "head_scale": 1.02 }
	cfg.face = {
		"mask_style": "square_rock",
		"horns_style": "gold_crown",
		"eye_style": "sharp_slit",
		"eye_color": Color(0.95, 0.75, 0.25, 0.6),
		"eye_core_color": Color(1.0, 0.95, 0.75)
	}
	cfg.cloak = {
		"cloak_style": "heavy_overcoat",
		"col_outer": Color(0.22, 0.18, 0.16),
		"col_inner": Color(0.32, 0.24, 0.18),
		"col_edge": Color(0.85, 0.68, 0.32),
		"chest_ornament": "coin"
	}
	cfg.weapon = {
		"weapon_type": "golden_abacus",
		"col_main": Color(0.55, 0.48, 0.38),
		"col_shadow": Color(0.32, 0.28, 0.22),
		"col_accent": Color(0.92, 0.72, 0.30),
		"strap_style": "diagonal"
	}
	cfg._sync_palette()
	return cfg

# 13. 药王（悬壶济世，金针度劫，仙草灵雾，玉体清心）
static func make_yaowang() -> CultivatorVisualConfig:
	var cfg := CultivatorVisualConfig.new()
	cfg.body = { "scale": 0.96, "width_scale": 0.92, "height_scale": 1.02, "head_scale": 1.02 }
	cfg.face = {
		"mask_style": "oval_chin",
		"horns_style": "dao_bun",
		"eye_style": "hollow_oval",
		"eye_color": Color(0.35, 0.92, 0.78, 0.55),
		"eye_core_color": Color(0.88, 1.0, 0.95)
	}
	cfg.cloak = {
		"cloak_style": "royal_shawl",
		"col_outer": Color(0.12, 0.24, 0.24),
		"col_inner": Color(0.18, 0.34, 0.32),
		"col_edge": Color(0.45, 0.88, 0.78),
		"chest_ornament": "pearl"
	}
	cfg.weapon = {
		"weapon_type": "peach_sword",
		"col_main": Color(0.35, 0.52, 0.48),
		"col_shadow": Color(0.20, 0.32, 0.30),
		"col_accent": Color(0.65, 0.95, 0.85),
		"strap_style": "diagonal"
	}
	cfg._sync_palette()
	return cfg

# 14. 守财奴（寸利不让，金山聚顶，算盘敲响，财气逼人）
static func make_shoucainu() -> CultivatorVisualConfig:
	var cfg := CultivatorVisualConfig.new()
	cfg.body = { "scale": 0.94, "width_scale": 1.15, "height_scale": 0.92, "head_scale": 1.06 }
	cfg.face = {
		"mask_style": "round_petite",
		"horns_style": "miser_horns",
		"eye_style": "sharp_slit",
		"eye_color": Color(1.0, 0.85, 0.15, 0.7),
		"eye_core_color": Color(1.0, 0.98, 0.80)
	}
	cfg.cloak = {
		"cloak_style": "tattered_rags",
		"col_outer": Color(0.24, 0.18, 0.10),
		"col_inner": Color(0.38, 0.28, 0.14),
		"col_edge": Color(0.95, 0.82, 0.22),
		"chest_ornament": "coin"
	}
	cfg.weapon = {
		"weapon_type": "treasure_chest",
		"col_main": Color(0.62, 0.48, 0.22),
		"col_shadow": Color(0.36, 0.26, 0.12),
		"col_accent": Color(1.0, 0.88, 0.32),
		"strap_style": "dual"
	}
	cfg._sync_palette()
	return cfg

# 15. 嗜血魔修（以煞养身，痛极狂笑，血海翻涌，修罗降世）
static func make_shixue() -> CultivatorVisualConfig:
	var cfg := CultivatorVisualConfig.new()
	cfg.body = { "scale": 1.15, "width_scale": 1.12, "height_scale": 1.05, "head_scale": 0.95 }
	cfg.face = {
		"mask_style": "stout_brute",
		"horns_style": "bull_horns",
		"eye_style": "angry_slit",
		"eye_color": Color(1.0, 0.15, 0.15, 0.75),
		"eye_core_color": Color(1.0, 0.85, 0.85)
	}
	cfg.cloak = {
		"cloak_style": "tattered_rags",
		"col_outer": Color(0.18, 0.05, 0.05),
		"col_inner": Color(0.28, 0.08, 0.08),
		"col_edge": Color(0.92, 0.20, 0.18),
		"chest_ornament": "skull"
	}
	cfg.weapon = {
		"weapon_type": "broken_blade",
		"col_main": Color(0.55, 0.22, 0.20),
		"col_shadow": Color(0.30, 0.12, 0.12),
		"col_accent": Color(0.98, 0.25, 0.20),
		"strap_style": "diagonal",
		"carry_front_pos": Vector2(10.0, 9.0), "carry_front_rot": 210.0,
		"carry_side_pos": Vector2(-7.0, 8.0), "carry_side_rot": -10.0,
	}
	cfg._sync_palette()
	return cfg

# 16. 灵符子·符修（万符归宗，黄符镇额，弹射无影，符剑诛邪）
static func make_fuxiu() -> CultivatorVisualConfig:
	var cfg := CultivatorVisualConfig.new()
	cfg.body = { "scale": 0.95, "width_scale": 0.90, "height_scale": 1.0, "head_scale": 1.05 }
	cfg.face = {
		"mask_style": "oval_chin",
		"horns_style": "talisman",
		"eye_style": "sharp_slit",
		"eye_color": Color(1.0, 0.80, 0.25, 0.60),  # 朱砂符光金
		"eye_core_color": Color(1.0, 0.95, 0.70)
	}
	cfg.cloak = {
		"cloak_style": "royal_shawl",
		"col_outer": Color(0.48, 0.32, 0.10),       # 赭黄符纸
		"col_inner": Color(0.90, 0.84, 0.62),       # 米白纸色
		"col_edge": Color(0.85, 0.25, 0.15),        # 朱砂红
		"chest_ornament": "bagua"
	}
	cfg.weapon = {
		"weapon_type": "peach_sword",
		"col_main": Color(0.70, 0.40, 0.22),        # 辟邪桃木
		"col_shadow": Color(0.42, 0.22, 0.12),
		"col_accent": Color(1.0, 0.35, 0.20),       # 朱砂符光
		"strap_style": "diagonal"
	}
	cfg._sync_palette()
	return cfg

# 17. 霸王（横扫千军，怒面无饰自生威，玄黑赤金大氅，兽骨战斧）
# 体型 2026-10-24 减脂（接守卫/蛮兵 #14）：宽度 1.22→1.10，纵高块头
static func make_bawang() -> CultivatorVisualConfig:
	var cfg := CultivatorVisualConfig.new()
	cfg.body = { "scale": 1.12, "width_scale": 1.10, "height_scale": 1.04, "head_scale": 0.95 }
	cfg.face = {
		"mask_style": "stout_brute",
		"horns_style": "none",
		"eye_style": "angry_slit",
		"eye_color": Color(1.0, 0.55, 0.15, 0.70),  # 赤金怒目
		"eye_core_color": Color(1.0, 0.90, 0.60)
	}
	cfg.cloak = {
		"cloak_style": "heavy_overcoat",
		"col_outer": Color(0.08, 0.07, 0.10),       # 玄黑
		"col_inner": Color(0.42, 0.10, 0.08),       # 赤红内衬
		"col_edge": Color(0.88, 0.60, 0.22),        # 赤金镶边
		"chest_ornament": "skull"
	}
	cfg.weapon = {
		"weapon_type": "bone_axe",
		"col_main": Color(0.45, 0.35, 0.20),        # 玄铁暗金
		"col_shadow": Color(0.22, 0.17, 0.10),
		"col_accent": Color(0.98, 0.65, 0.20),      # 赤金流光
		"strap_style": "dual"
	}
	cfg._sync_palette()
	return cfg

# 18. 绝尘（一剑绝尘，轻灵出尘，逍遥仙道髻，冰青剑目，流云开衩仙袍，太乙青冥剑）
static func make_juechen() -> CultivatorVisualConfig:
	var cfg := CultivatorVisualConfig.new()
	cfg.body = { "scale": 1.04, "width_scale": 0.92, "height_scale": 1.05, "head_scale": 1.0 }
	cfg.face = {
		"mask_style": "oval_chin",
		"horns_style": "dao_bun",
		"eye_style": "sharp_slit",
		"eye_color": Color(0.40, 0.85, 1.0, 0.70),  # 冰青仙芒剑目
		"eye_core_color": Color(0.95, 1.0, 1.0)
	}
	cfg.cloak = {
		"cloak_style": "split_flowing",
		"col_outer": Color(0.18, 0.35, 0.48),       # 冰魄天青
		"col_inner": Color(0.82, 0.90, 0.96),       # 凝霜银白内衬
		"col_edge": Color(0.45, 0.88, 1.0),        # 太乙青辉镶边
		"chest_ornament": "bagua"
	}
	cfg.weapon = {
		"weapon_type": "peach_sword",
		"col_main": Color(0.85, 0.95, 1.0),        # 青冥寒光剑身
		"col_shadow": Color(0.40, 0.55, 0.68),
		"col_accent": Color(0.45, 0.90, 1.0),      # 冰青流光
		"strap_style": "floating"
	}
	cfg._sync_palette()
	return cfg

# 19. 御兽师（万灵来朝，兽伴同行，灵动双髻，翡翠通灵目，墨绿玄青短披，驭兽灵杖）
static func make_yushou() -> CultivatorVisualConfig:
	var cfg := CultivatorVisualConfig.new()
	cfg.body = { "scale": 0.94, "width_scale": 0.96, "height_scale": 0.98, "head_scale": 1.04 }
	cfg.face = {
		"mask_style": "round_petite",
		"horns_style": "twin_buns",
		"eye_style": "round_bright",
		"eye_color": Color(0.20, 0.88, 0.55, 0.70),  # 翡翠通灵目
		"eye_core_color": Color(0.85, 1.0, 0.90)
	}
	cfg.cloak = {
		"cloak_style": "short_cape",
		"col_outer": Color(0.12, 0.28, 0.22),        # 墨绿玄袍
		"col_inner": Color(0.82, 0.94, 0.86),        # 浅葱玉色
		"col_edge": Color(0.95, 0.82, 0.35),         # 暖金符线
		"chest_ornament": "bagua"
	}
	cfg.weapon = {
		"weapon_type": "peach_sword",
		"col_main": Color(0.35, 0.65, 0.55),         # 驭兽青玉笛
		"col_shadow": Color(0.18, 0.36, 0.28),
		"col_accent": Color(0.98, 0.85, 0.40),
		"strap_style": "diagonal"
	}
	cfg._sync_palette()
	return cfg

# 20. 苦行僧（心如止水，金刚怒目，光洁僧首，怒目金刚眸，赭褐破衲法衣，降魔玄石法杖）
static func make_kuxingseng() -> CultivatorVisualConfig:
	var cfg := CultivatorVisualConfig.new()
	cfg.body = { "scale": 1.06, "width_scale": 1.12, "height_scale": 1.0, "head_scale": 1.0 }
	cfg.face = {
		"mask_style": "oval_chin",
		"horns_style": "none",
		"eye_style": "angry_slit",
		"eye_color": Color(1.0, 0.78, 0.25, 0.85),  # 佛门怒目金刚眸
		"eye_core_color": Color(1.0, 0.96, 0.80)
	}
	cfg.cloak = {
		"cloak_style": "tattered_rags",
		"col_outer": Color(0.32, 0.22, 0.14),        # 赭褐深苦修僧袍
		"col_inner": Color(0.55, 0.38, 0.22),        # 土褐中衲
		"col_edge": Color(0.92, 0.76, 0.32),         # 佛门金纹
		"chest_ornament": "pearl"
	}
	cfg.weapon = {
		"weapon_type": "stone_pillar",
		"col_main": Color(0.48, 0.40, 0.32),         # 降魔降妖金刚石柱/法杖
		"col_shadow": Color(0.28, 0.24, 0.20),
		"col_accent": Color(0.95, 0.80, 0.35),
		"strap_style": "diagonal"
	}
	cfg._sync_palette()
	return cfg

# 21. 散修（无门无派，博采众长，竹笠遮面，百衲杂袍，背负一捆杂兵器）
static func make_sanxiu() -> CultivatorVisualConfig:
	var cfg := CultivatorVisualConfig.new()
	cfg.body = { "scale": 1.0, "width_scale": 1.04, "height_scale": 1.0, "head_scale": 1.0 }
	cfg.face = {
		"mask_style": "oval_chin",
		"horns_style": "bamboo_hat",
		"eye_style": "round_pupil",
		"eye_color": Color(0.72, 0.86, 0.95, 0.42),  # 淡蓝灰：不属任何一系的旁观者眸
		"eye_core_color": Color(0.96, 0.98, 1.0)
	}
	cfg.cloak = {
		"cloak_style": "tattered_rags",
		"col_outer": Color(0.24, 0.26, 0.30),        # 灰蓝百衲布
		"col_inner": Color(0.36, 0.33, 0.26),        # 土褐补丁
		"col_edge": Color(0.62, 0.72, 0.80),         # 冷银走线
		"chest_ornament": "none"
	}
	cfg.weapon = {
		"weapon_type": "assorted_bundle",
		"col_main": Color(0.36, 0.38, 0.44),         # 玄铁杂兵刃身（深铁灰，压在骨白面具旁也分得开）
		"col_shadow": Color(0.18, 0.20, 0.25),
		"col_accent": Color(0.72, 0.60, 0.36),       # 麻绳与旧木柄
		"strap_style": "dual",
		# 捆束右移出肩外、刃尖朝上外展：正面视角武器先画、斗篷后盖，压原位会被袍身整片吞掉
		"carry_front_pos": Vector2(12.0, 1.0), "carry_front_rot": 24.0,
		"carry_side_pos": Vector2(-8.5, 6.0), "carry_side_rot": -16.0,
	}
	cfg._sync_palette()
	return cfg
