class_name CultivatorVisualConfig
extends Resource

## 修仙角色视觉与配件标准配置规范
## 为后续全道统修士（红衣丹修、金刚体修、玄阴毒修等）统一提供规范接口

enum HornsType {
	BUTTERFLY_HORNS, ## 蝶羽仙角（空洞骑士风）
	DAO_BUN,         ## 发髻木簪（正统道家）
	BAMBOO_HAT,      ## 竹编斗笠（江湖浪客）
	CYBER_HEADBAND   ## 赛博抹额战甲（现代国潮）
}

enum CloakType {
	MOTH_WING,       ## 蝉翼破损薄纱披风
	WIDE_SLEEVE_ROBE,## 宽袍大袖流云袍
	STREAMER_SCARF   ## 狂风残影能量飘带
}

enum WeaponType {
	BONE_NAIL,       ## 月光纯白骨钉长剑
	PEACH_SWORD,     ## 桃花金装秋水长剑
	THUNDER_WOOD,    ## 辟邪雷火小木剑
	PLASMA_BLADE     ## 高频等离子弧光太刀
}

@export var character_id: String = "jianchi"
@export var character_name: String = "青云剑修·独孤"
@export var horns_type: HornsType = HornsType.BUTTERFLY_HORNS
@export var cloak_type: CloakType = CloakType.MOTH_WING
@export var weapon_type: WeaponType = WeaponType.BONE_NAIL

## 核心色盘映射
@export var palette: Dictionary = {
	"void_black": Color(0.06, 0.07, 0.10),
	"bone_white": Color(0.96, 0.97, 0.99),
	"bone_shadow": Color(0.76, 0.82, 0.88),
	"eye_glow": Color(0.75, 0.92, 1.0, 0.45),
	"eye_core": Color(0.98, 1.0, 1.0),
	"cloak_outer": Color(0.11, 0.24, 0.17),     # 深邃墨绿
	"cloak_inner": Color(0.18, 0.38, 0.28),     # 青碧月影薄纱
	"cloak_edge": Color(0.28, 0.62, 0.46),      # 边缘冷玉月辉
	"nail_white": Color(0.95, 0.97, 1.0),
	"nail_shadow": Color(0.70, 0.78, 0.86),
	"slash_arc": Color(0.92, 0.98, 1.0, 0.95), # 月牙斩击弧光
	"slash_glow": Color(0.40, 0.85, 0.70, 0.4)
}

## 绿衣空洞修士标准配置生成工厂
static func make_green_hollow_knight() -> CultivatorVisualConfig:
	var cfg := CultivatorVisualConfig.new()
	cfg.character_id = "jianchi"
	cfg.character_name = "青云剑修·独孤"
	cfg.horns_type = HornsType.BUTTERFLY_HORNS
	cfg.cloak_type = CloakType.MOTH_WING
	cfg.weapon_type = WeaponType.BONE_NAIL
	return cfg
