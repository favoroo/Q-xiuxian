class_name EnemyVisualConfig
extends Resource

## 敌人视觉配置参数
## 定义冷冽空洞国风下 14 种敌人的体型、色彩、灵核形态与专属装饰

enum LocomotionType {
	HOVER,  ## 悬浮御风
	FLIGHT, ## 振翅疾飞
	CRAWL   ## 贴地蠕动爬行
}

@export var enemy_id: String = ""
@export var display_name: String = ""
@export var locomotion: LocomotionType = LocomotionType.HOVER
@export var is_elite: bool = false
@export var is_boss: bool = false
@export var is_final_boss: bool = false

# 几何尺寸与基准比例
@export var body_radius: float = 14.0
@export var scale_factor: float = 1.0

# 调色盘（空洞冷冽国风：高反差骨白/虚空黑/冷冽荧光）
@export var col_primary: Color = Color(0.12, 0.14, 0.18, 1.0)     ## 主体躯壳色
@export var col_secondary: Color = Color(0.85, 0.88, 0.92, 1.0)   ## 骨甲/辅饰色
@export var col_accent: Color = Color(0.35, 0.45, 0.60, 1.0)      ## 边缘滚边/花纹色
@export var col_glow: Color = Color(0.30, 0.85, 0.95, 1.0)        ## 灵核/幽火/眼眸高光色
@export var col_void: Color = Color(0.04, 0.05, 0.08, 1.0)        ## 虚空极深暗底色

# 细节插槽类型
@export var eye_type: String = "slit"       ## 眼眸类型 (slit, round, multi, twin_slits, evil_eye, void)
@export var ornament_type: String = "none"  ## 专属挂饰 (sword, urn_lid, horns, drum, petals, talisman, halo, wheel, none)

# -------------------- 工厂预设 --------------------

## 1. 史莱姆：幽冥血煞 / 凝魂怨泥 (CRAWL)
static func make_slime() -> EnemyVisualConfig:
	var cfg := EnemyVisualConfig.new()
	cfg.enemy_id = "slime"
	cfg.display_name = "幽冥血煞"
	cfg.locomotion = LocomotionType.CRAWL
	cfg.body_radius = 14.0
	cfg.scale_factor = 1.1
	cfg.col_primary = Color(0.55, 0.10, 0.16, 0.85)     # 暗红半透明流质血煞
	cfg.col_secondary = Color(0.88, 0.86, 0.82, 0.95)   # 森白残碎骨屑
	cfg.col_accent = Color(0.78, 0.22, 0.28, 0.70)      # 鲜红冷血边缘
	cfg.col_glow = Color(0.40, 0.95, 0.55, 1.0)         # 幽绿怨魂核
	cfg.eye_type = "single_core"
	cfg.ornament_type = "bone_shards"
	return cfg

## 2. 御剑邪修：幽冥剑客 / 破戒邪修 (HOVER)
static func make_xiexiu() -> EnemyVisualConfig:
	var cfg := EnemyVisualConfig.new()
	cfg.enemy_id = "xiexiu"
	cfg.display_name = "幽冥邪修"
	cfg.locomotion = LocomotionType.HOVER
	cfg.body_radius = 13.0
	cfg.scale_factor = 1.0
	cfg.col_primary = Color(0.12, 0.16, 0.22, 1.0)     # 墨青残破道袍
	cfg.col_secondary = Color(0.92, 0.90, 0.86, 1.0)   # 苍白修罗骨面
	cfg.col_accent = Color(0.40, 0.35, 0.65, 0.9)      # 暗紫剑煞饰边
	cfg.col_glow = Color(0.35, 0.85, 1.0, 1.0)         # 冰蓝冷冽剑眸
	cfg.eye_type = "slit"
	cfg.ornament_type = "flying_sword"
	return cfg

## 3. 丹爆傀儡：蚀骨毒炉 / 爆炎邪偶 (HOVER)
static func make_danbao() -> EnemyVisualConfig:
	var cfg := EnemyVisualConfig.new()
	cfg.enemy_id = "danbao"
	cfg.display_name = "蚀骨丹炉"
	cfg.locomotion = LocomotionType.HOVER
	cfg.body_radius = 13.5
	cfg.scale_factor = 1.05
	cfg.col_primary = Color(0.24, 0.28, 0.26, 1.0)     # 青铜重器鼎身
	cfg.col_secondary = Color(0.82, 0.72, 0.50, 1.0)   # 铜锈与金错铭文
	cfg.col_accent = Color(0.95, 0.38, 0.18, 0.95)     # 暴烈地火裂纹
	cfg.col_glow = Color(1.0, 0.50, 0.15, 1.0)         # 炉火金红焰心
	cfg.eye_type = "glow_crack"
	cfg.ornament_type = "urn_lid"
	return cfg

## 4. 蜂群精：冥火毒螟 / 幽冥骨蜂 (FLIGHT)
static func make_fengqun() -> EnemyVisualConfig:
	var cfg := EnemyVisualConfig.new()
	cfg.enemy_id = "fengqun"
	cfg.display_name = "冥火毒螟"
	cfg.locomotion = LocomotionType.FLIGHT
	cfg.body_radius = 10.0
	cfg.scale_factor = 1.05
	cfg.col_primary = Color(0.10, 0.15, 0.14, 1.0)     # 幽黑虫甲
	cfg.col_secondary = Color(0.85, 0.90, 0.85, 1.0)   # 骨锥针刺
	cfg.col_accent = Color(0.25, 0.75, 0.60, 0.85)     # 半透明薄翼
	cfg.col_glow = Color(0.20, 1.0, 0.50, 1.0)         # 剧毒磷光复眼
	cfg.eye_type = "twin_slits"
	cfg.ornament_type = "insect_wings"
	return cfg

## 5. 花妖：曼珠沙华 / 噬灵妖花 (HOVER)
static func make_flower() -> EnemyVisualConfig:
	var cfg := EnemyVisualConfig.new()
	cfg.enemy_id = "flower"
	cfg.display_name = "噬灵花妖"
	cfg.locomotion = LocomotionType.HOVER
	cfg.body_radius = 14.0
	cfg.scale_factor = 1.05
	cfg.col_primary = Color(0.48, 0.10, 0.25, 1.0)     # 冷绯彼岸花瓣
	cfg.col_secondary = Color(0.92, 0.88, 0.85, 1.0)   # 骨白花萼与利刃
	cfg.col_accent = Color(0.32, 0.08, 0.36, 0.85)     # 幽紫墨痕根茎
	cfg.col_glow = Color(1.0, 0.25, 0.45, 1.0)         # 妖艳血色花蕊瞳
	cfg.eye_type = "evil_eye"
	cfg.ornament_type = "petals"
	return cfg

## 6. 血蛹：九幽血茧 / 煞血鬼蛹 (CRAWL)
static func make_xueyong() -> EnemyVisualConfig:
	var cfg := EnemyVisualConfig.new()
	cfg.enemy_id = "xueyong"
	cfg.display_name = "九幽血茧"
	cfg.locomotion = LocomotionType.CRAWL
	cfg.body_radius = 15.0
	cfg.scale_factor = 1.1
	cfg.col_primary = Color(0.38, 0.12, 0.18, 1.0)     # 暗红凝固血晶
	cfg.col_secondary = Color(0.88, 0.85, 0.78, 1.0)   # 镇煞封印麻布
	cfg.col_accent = Color(0.70, 0.18, 0.22, 0.9)      # 朱砂封灵符纹
	cfg.col_glow = Color(0.95, 0.30, 0.35, 1.0)         # 脉动血光核心
	cfg.eye_type = "void"
	cfg.ornament_type = "talisman_straps"
	return cfg

## 7. 鼓妖：白骨摄魂鼓 / 丧钟怨灵 (HOVER)
static func make_guyao() -> EnemyVisualConfig:
	var cfg := EnemyVisualConfig.new()
	cfg.enemy_id = "guyao"
	cfg.display_name = "白骨摄魂鼓"
	cfg.locomotion = LocomotionType.HOVER
	cfg.body_radius = 14.5
	cfg.scale_factor = 1.05
	cfg.col_primary = Color(0.18, 0.20, 0.25, 1.0)     # 煞铜重鼓框
	cfg.col_secondary = Color(0.92, 0.89, 0.82, 1.0)   # 兽骨獠牙包角与骨槌
	cfg.col_accent = Color(0.60, 0.20, 0.25, 0.9)      # 太极魔纹
	cfg.col_glow = Color(0.40, 0.90, 0.70, 1.0)        # 摄魂光环灵玉
	cfg.eye_type = "void"
	cfg.ornament_type = "drum"
	return cfg

## 8. 影魅：幽冥影煞 / 虚空厉鬼 (HOVER)
static func make_yingmei() -> EnemyVisualConfig:
	var cfg := EnemyVisualConfig.new()
	cfg.enemy_id = "yingmei"
	cfg.display_name = "幽冥影魅"
	cfg.locomotion = LocomotionType.HOVER
	cfg.body_radius = 13.0
	cfg.scale_factor = 1.0
	cfg.col_primary = Color(0.06, 0.08, 0.12, 0.95)    # 纯黑煞气流体
	cfg.col_secondary = Color(0.85, 0.80, 0.95, 1.0)   # 惨白影骨双角
	cfg.col_accent = Color(0.42, 0.25, 0.65, 0.75)     # 幽紫残烟雾气
	cfg.col_glow = Color(0.85, 0.60, 1.0, 1.0)         # 妖异紫瞳狭缝
	cfg.eye_type = "twin_slits"
	cfg.ornament_type = "horns"
	return cfg

## 9. 百目妖：千目邪母 / 万瞳魔核 (HOVER)
static func make_zhumu() -> EnemyVisualConfig:
	var cfg := EnemyVisualConfig.new()
	cfg.enemy_id = "zhumu"
	cfg.display_name = "千目邪母"
	cfg.locomotion = LocomotionType.HOVER
	cfg.body_radius = 18.0
	cfg.scale_factor = 1.25
	cfg.col_primary = Color(0.20, 0.12, 0.25, 1.0)     # 深紫虚空巨核
	cfg.col_secondary = Color(0.90, 0.85, 0.80, 1.0)   # 骨质眼环外眶
	cfg.col_accent = Color(0.55, 0.18, 0.35, 0.85)     # 脉动血肉筋络
	cfg.col_glow = Color(1.0, 0.75, 0.20, 1.0)         # 密密麻麻金红邪眸
	cfg.eye_type = "multi"
	cfg.ornament_type = "tentacles"
	return cfg

## 10. 雷兽：幽都凶兽 / 冥雷煞兽 (CRAWL)
static func make_leibeast() -> EnemyVisualConfig:
	var cfg := EnemyVisualConfig.new()
	cfg.enemy_id = "leibeast"
	cfg.display_name = "冥雷煞兽"
	cfg.locomotion = LocomotionType.CRAWL
	cfg.body_radius = 15.0
	cfg.scale_factor = 1.15
	cfg.col_primary = Color(0.12, 0.16, 0.26, 1.0)     # 深蓝玄夜兽躯
	cfg.col_secondary = Color(0.92, 0.90, 0.85, 1.0)   # 骨质狼首骨面与利齿
	cfg.col_accent = Color(0.28, 0.45, 0.75, 0.9)      # 脊椎幽蓝雷甲
	cfg.col_glow = Color(0.35, 0.85, 1.0, 1.0)         # 暴虐电弧双眸
	cfg.eye_type = "twin_slits"
	cfg.ornament_type = "back_spikes"
	return cfg

## 11. 铁甲魔傀（精英）：幽冥玄铁巨傀 (HOVER)
static func make_golem() -> EnemyVisualConfig:
	var cfg := EnemyVisualConfig.new()
	cfg.enemy_id = "golem"
	cfg.display_name = "铁甲魔傀"
	cfg.locomotion = LocomotionType.HOVER
	cfg.is_elite = true
	cfg.body_radius = 20.0
	cfg.scale_factor = 1.35
	cfg.col_primary = Color(0.14, 0.18, 0.20, 1.0)     # 青黑玄铁重甲板
	cfg.col_secondary = Color(0.85, 0.82, 0.78, 1.0)   # 蛮荒巨骨肩盾
	cfg.col_accent = Color(0.30, 0.65, 0.75, 0.85)     # 灵流青铜铭纹
	cfg.col_glow = Color(0.30, 0.90, 1.0, 1.0)         # 旋转阵眼灵石
	cfg.eye_type = "slit"
	cfg.ornament_type = "floating_shields"
	return cfg

## 12. 赤雷兽（精英）：九幽赤煞雷帝兽 (CRAWL)
static func make_chilei_elite() -> EnemyVisualConfig:
	var cfg := EnemyVisualConfig.new()
	cfg.enemy_id = "chilei_elite"
	cfg.display_name = "赤雷巨兽"
	cfg.locomotion = LocomotionType.CRAWL
	cfg.is_elite = true
	cfg.body_radius = 18.0
	cfg.scale_factor = 1.4
	cfg.col_primary = Color(0.28, 0.12, 0.12, 1.0)     # 焦黑血煞战躯
	cfg.col_secondary = Color(0.95, 0.85, 0.75, 1.0)   # 巨大赤金雷角
	cfg.col_accent = Color(0.85, 0.35, 0.15, 0.9)      # 背棘赤焰刀羽
	cfg.col_glow = Color(1.0, 0.45, 0.20, 1.0)         # 狂暴金红雷光
	cfg.eye_type = "twin_slits"
	cfg.ornament_type = "grand_horns"
	return cfg

## 13. 剑煞邪修（精英）：万剑煞宗残魂 (HOVER)
static func make_jiansha_elite() -> EnemyVisualConfig:
	var cfg := EnemyVisualConfig.new()
	cfg.enemy_id = "jiansha_elite"
	cfg.display_name = "剑煞邪尊"
	cfg.locomotion = LocomotionType.HOVER
	cfg.is_elite = true
	cfg.body_radius = 15.0
	cfg.scale_factor = 1.15
	cfg.col_primary = Color(0.12, 0.08, 0.16, 1.0)     # 墨黑血煞长袍
	cfg.col_secondary = Color(0.92, 0.88, 0.84, 1.0)   # 鬼道白骨面具
	cfg.col_accent = Color(0.75, 0.22, 0.35, 0.9)      # 扇形血光剑轮
	cfg.col_glow = Color(1.0, 0.35, 0.50, 1.0)         # 血煞冷眸
	cfg.eye_type = "slit"
	cfg.ornament_type = "tri_swords"
	return cfg

## 14. 妖潮魔君 & 心魔魔尊 (BOSS / HOVER)
static func make_boss(final_boss: bool = false) -> EnemyVisualConfig:
	var cfg := EnemyVisualConfig.new()
	cfg.enemy_id = "boss"
	cfg.is_boss = true
	cfg.is_final_boss = final_boss
	cfg.locomotion = LocomotionType.HOVER
	cfg.body_radius = 26.0
	cfg.scale_factor = 1.6 if not final_boss else 1.85
	if final_boss:
		cfg.display_name = "最终Boss"
		cfg.col_primary = Color(0.10, 0.06, 0.16, 1.0)   # 紫黑虚空神铠
		cfg.col_secondary = Color(0.88, 0.82, 0.95, 1.0) # 九幽魔冠骨面
		cfg.col_accent = Color(0.60, 0.30, 0.85, 0.95)   # 神魔紫焰法轮
		cfg.col_glow = Color(0.85, 0.50, 1.0, 1.0)       # 虚空极光魔眼
		cfg.ornament_type = "god_wheel"
	else:
		cfg.display_name = "赤炎魔将"
		cfg.col_primary = Color(0.16, 0.10, 0.12, 1.0)   # 赤黑鬼王重铠
		cfg.col_secondary = Color(0.92, 0.88, 0.82, 1.0) # 獠牙冲天骨面
		cfg.col_accent = Color(0.85, 0.28, 0.20, 0.95)   # 煞气魔刃骨环
		cfg.col_glow = Color(1.0, 0.40, 0.25, 1.0)       # 滚滚赤炎神瞳
		cfg.ornament_type = "blade_ring"
	cfg.eye_type = "twin_slits"
	return cfg

## 通用查找入口
static func get_config(eid: String, is_elite_flag: bool = false, is_boss_flag: bool = false, is_final: bool = false) -> EnemyVisualConfig:
	if is_boss_flag or eid == "boss":
		return make_boss(is_final)
	match eid:
		"slime":
			return make_slime()
		"xiexiu":
			return make_xiexiu()
		"danbao":
			return make_danbao()
		"fengqun":
			return make_fengqun()
		"flower":
			return make_flower()
		"xueyong":
			return make_xueyong()
		"guyao":
			return make_guyao()
		"yingmei":
			return make_yingmei()
		"zhumu":
			return make_zhumu()
		"leibeast":
			return make_leibeast()
		"golem":
			return make_golem()
		"chilei_elite":
			return make_chilei_elite()
		"jiansha_elite":
			return make_jiansha_elite()
		_:
			# 兜底：如果是精英则优先转入对应精英或通用
			if is_elite_flag:
				return make_golem()
			return make_slime()
