class_name BossEnemy
extends EnemyBase

## 关卡 Boss：固定 Boss 回合（第 10/20 波、无尽每 5 波）登场，参考土豆兄弟的大 Boss 与弹幕射击设计。
## 特征：
##   1. 超厚血条，HUD 底部贴边专设 Boss 血条（boss_hp_changed / boss_defeated 信号驱动，带节流防掉帧）
##   2. 17 种攻击模式轮换（通用 12 招 + 深层签名 5 招 + 数据驱动 SIGNATURE 八变体）：
##      - RING: 双层交错弧线环弹（顺/逆时针交错弧线，二阶段追加直穿环）
##      - BURST_FAN: 扇形连射狙击（逐波加速压迫横向走位）
##      - SPIRAL: 螺旋风暴弹幕（持续原地旋转喷吐弹幕走廊）
##      - SPLIT_BOMB: 分裂子母弹（慢速母弹到期爆裂为一圈高速子火球）
##      - CHARGE / CHAIN_CHARGE: 破阵冲锋 / 多段折返连冲（预警胶囊线与扫掠判定同源）
##      - SKY_FIRE: 追踪天火连环轰炸（多处预警圈定点轰炸，严惩站桩）
##      - SLAM: 震地冲击（预警圈填满式结算，狂暴落地派生冲击环弹）
##      - SUMMON: 召唤妖群 + 弹幕掩护（W45 起换深层妖种）
##      - TURRET_SHIFT / HAZARD_FIELD / BLINK_SLASH: 换桩震爆 / 禁区封锁 / 瞬步回斩
##      - DIVE / MIRROR_FLANK / SOUL_TIDE / FURNACE_BLAST: 四尊专属签名（龙君/照影/引魂/炉君）
##      - SIGNATURE: 八尊深层魔君的数据驱动签名招（EnemyData.BOSS_SIGNATURES）
##   3. 分波次递进 + 半血二阶段狂暴：
##      - 第 10 波火焰Boss：初战常态 5 招，半血狂暴解锁天火与螺旋
##      - 第 20 波极煞魔尊：全套高压招式、紫焰魔弹、四螺旋风暴与多子母弹
## 数值由 WaveSpawner 按 GameBalance 公式注入。

enum Pattern {
	RING,        ## 双层交错弧线环弹
	BURST_FAN,   ## 扇形连射狙击
	SPIRAL,      ## 螺旋风暴弹幕
	SPLIT_BOMB,  ## 分裂子母弹
	CHARGE,      ## 破阵冲锋 + 侧翼洒弹
	SKY_FIRE,    ## 追踪天火连环轰炸
	SLAM,        ## 震地冲击（附二阶段/近远派生）
	SUMMON,      ## 召唤妖群 + 弹幕掩护
	CHAIN_CHARGE, ## 多段折返连冲
	TURRET_SHIFT, ## 阵眼换桩瞬移 + 双环震爆
	HAZARD_FIELD, ## 连环禁区封锁
	BLINK_SLASH,  ## 瞬步贴脸扇形回斩
	DIVE,         ## 飞龙俯冲（太苍龙君专属：拉升换位 → 全场贯穿俯冲 + 路径洒鳞 + 落点环爆）
	MIRROR_FLANK, ## 镜像夹击（照影魔君专属：镜影虚像在玩家对侧发环，主身扇形夹击）
	SOUL_TIDE,    ## 魂潮收网（引魂使专属：以玩家为圆心的包围弹环向内收拢）
	FURNACE_BLAST,## 炉压崩天（焚天炉君专属：站桩蓄力 → 大圆炉爆 + 三环弹幕）
	SIGNATURE,    ## 深层魔君签名招（按 boss_id 从 EnemyData.BOSS_SIGNATURES 取 kind 派发）
}

@export var boss_id: String = ""
@export var boss_title: String = "敌潮Boss"
@export var final_boss: bool = false      ## 第 20 波魔尊：换紫皮、放大身形、全招式全开
@export var attack_interval: float = GameBalance.BOSS_ATTACK_INTERVAL  ## 特殊攻击循环间隔

var _attack_timer: float = 2.4    ## 开场缓冲，让玩家先看清魔君登场
var _pattern_idx: int = 0
var _last_pattern: int = -1
var _phase2: bool = false
var _tint: Color = Color.WHITE    ## 常态染色（二阶段转红/紫，演出后回染）
var _purple_bolts: bool = false        ## 幽紫魔弹口径：仅旧最终Boss与九幽心魔尊使用
var _fx_color: Color = Color(1.0, 0.45, 0.3)  ## 本尊主题特效色（取 EnemyVisualConfig.col_accent，弹幕/冲击环/预警圈同源）

# 血条信号节流
var _hp_emit_acc: float = 0.0
var _hp_emit_cd: float = 0.0
var _heavy_hit_cd: float = 0.0   ## 大比例掉血镜头回应的独立冷却（take_damage 写入）

# 震地状态机
var _slam_pending: bool = false
var _slam_timer: float = 0.0
var _slam_windup_total: float = 0.0  ## 本次震地预警总时长（按半径公平线裁定，进度/姿态读数同源）
var _slam_ring: AoeTelegraph = null

# 螺旋风暴状态机
var _spiral_active: bool = false
var _spiral_timer: float = 0.0
var _spiral_step_timer: float = 0.0
var _spiral_angle: float = 0.0

## 读招姿态：上一帧是否处于「蓄力/施法」态（起手→归零的跳变发一次 recoil 爆发读数）
var _pose_casting: bool = false

## 按招式状态机维持渲染器 special_state 0→1（起手预警有真进度，引导/连射给固定读数）；
## 招式归零瞬间触发一次 recoil，区分「蓄力/爆发」两态。aim_dir 由 EnemyBase 同步段
## 持续指向玩家，蓄力中魔刃收束读数无需此处接线。
func _sync_cast_pose() -> void:
	if procedural_view == null:
		return
	var pose := 0.0
	if _furnace_pending:
		pose = clampf(1.0 - _furnace_timer / maxf(_furnace_windup_total, 0.001), 0.0, 1.0)
	elif _slam_pending:
		pose = clampf(1.0 - _slam_timer / maxf(_slam_windup_total, 0.001), 0.0, 1.0)
	elif _mirror_pending:
		pose = clampf(1.0 - _mirror_timer / maxf(_mirror_windup_total, 0.001), 0.0, 1.0)
	elif _soul_pending:
		pose = clampf(1.0 - _soul_timer / maxf(_soul_windup_total, 0.001), 0.0, 1.0)
	elif _charge_windup > 0.0:
		pose = clampf(1.0 - _charge_windup / maxf(GameBalance.BOSS_CHARGE_WINDUP, 0.001), 0.0, 1.0)
	elif _spiral_active:
		pose = 0.5   # 引导喷吐：恒定收束指向态
	elif _fan_waves_left > 0 or _sky_fire_strikes_left > 0 or _hazard_fields_left > 0:
		pose = 0.35  # 连射/天火/禁区后台推进：轻收束读数
	procedural_view.special_state = pose
	var casting := pose > 0.001
	if _pose_casting and not casting:
		# 出手收势：一次后坐爆发（recoil 由渲染器自行衰减回弹）
		procedural_view.trigger_recoil()
	_pose_casting = casting

## 瞬发招式的爆发读数：无预警蓄力的招式（环弹/子母弹/召唤掩护）出手当帧
## 直接发一次 recoil 后坐，让渲染器至少区分出「爆发」一态。
func _pose_burst() -> void:
	if procedural_view != null:
		procedural_view.trigger_recoil()

# 扇形连射状态机
var _fan_waves_left: int = 0
var _fan_wave_timer: float = 0.0

# 天火连环轰炸状态机
var _sky_fire_strikes_left: int = 0
var _sky_fire_spawn_timer: float = 0.0
var _active_sky_fires: Array[Dictionary] = []

# 连环冲刺状态机
var _chain_charges_left: int = 0

# 飞龙俯冲状态机（2026-11-03 太苍龙君）：拉升换位后借冲锋机架做全场贯穿俯冲，
# 冲锋三件套（时长/倍速/伤害系数）临时换成俯冲口径，收势恢复原值。
var _dive_pending: bool = false        ## 已拉升换位、预警中，等待 _start_charge 起冲
var _dive_active: bool = false         ## 俯冲实冲中（路径洒弹计费中）
var _dive_trail_timer: float = 0.0
var _charge_duration_stash: float = 0.0
var _charge_speed_stash: float = 0.0
var _charge_dmg_stash: float = 0.0

# 炉压崩天状态机（2026-11-03 焚天炉君）：与震地同款的「预警圈填满 → 结算」互斥锁
var _furnace_pending: bool = false
var _furnace_timer: float = 0.0
var _furnace_windup_total: float = 0.0
var _furnace_ring: AoeTelegraph = null

# 镜影夹击前摇状态机（2026-11-03 可读性优化）：先在场对侧亮镜影圈，再发环弹
var _mirror_pending: bool = false
var _mirror_timer: float = 0.0
var _mirror_windup_total: float = 0.0
var _mirror_point: Vector2 = Vector2.ZERO
var _mirror_telegraph: AoeTelegraph = null

# 魂潮收网前摇状态机（2026-11-03 可读性优化）：先在玩家脚下亮收网点，再撒包围环
var _soul_pending: bool = false
var _soul_timer: float = 0.0
var _soul_windup_total: float = 0.0
var _soul_center: Vector2 = Vector2.ZERO
var _soul_telegraph: AoeTelegraph = null

## 签名招延迟步骤的预警圈登记表：Boss 伏诛时统一清理，防 tween 被打断后留圈
var _sig_telegraphs: Array[AoeTelegraph] = []

# 禁区封锁状态机
var _hazard_fields_left: int = 0
var _hazard_spawn_timer: float = 0.0
var _active_hazard_fields: Array[Dictionary] = []

## 出招轮换表：按波次与阶段动态编排
var _patterns: Array = []

# 决策超时保底（2026-11-03）：原地不动累计时长。炮台（move_speed=0）与贴脸站桩的
# 近战 Boss 都靠它打破「长期不挪窝」——超提示线机动招加权，超强制线下次决策必出机动招。
var _since_moved: float = 0.0
var _prev_pos: Vector2 = Vector2.ZERO
var _prev_pos_valid: bool = false
## 招式陈旧度账：pattern → 上次使用时的决策序号（防饿死加权，确定性不抽 rng）
var _pattern_last_cast: Dictionary = {}
var _casts_total: int = 0

var _minion_scenes: Array = [
	preload("res://scenes/entities/SlimeEnemy.tscn"),
	preload("res://scenes/entities/FlowerEnemy.tscn"),
	preload("res://scenes/entities/FengQunEnemy.tscn"),
]
## 深层召唤物：W45 起换用深层妖种，傀王/引魂使的「妖潮/鬼潮」不再是一群史莱姆。
## 用路径懒加载而不是 preload：BossEnemy 类加载时多背 4 个场景会把 MEMORY_STATIC 顶过门禁，
## 只有深层 Boss 真正用召唤时才付这份内存。
const DEEP_MINION_PATHS: Array[String] = [
	"res://scenes/entities/MoWeiEnemy.tscn",
	"res://scenes/entities/HanPoEnemy.tscn",
	"res://scenes/entities/ZhuMuEnemy.tscn",
	"res://scenes/entities/GuYaoEnemy.tscn",
]
var _deep_minion_scenes: Array = []

func _get_deep_minion_scenes() -> Array:
	if _deep_minion_scenes.is_empty():
		for path in DEEP_MINION_PATHS:
			var ps := load(path) as PackedScene
			if ps != null:
				_deep_minion_scenes.append(ps)
	return _deep_minion_scenes

func _ready() -> void:
	if boss_id != "":
		if "BOSS_POOL" in EnemyData and EnemyData.BOSS_POOL.has(boss_id):
			var cfg: Dictionary = EnemyData.BOSS_POOL[boss_id]
			move_speed = float(cfg.get("move_speed", move_speed))
		if boss_id == "qianji":
			move_speed = 0.0
		elif boss_id == "wangu":
			preferred_range = 240.0
		elif boss_id == "kunwang":
			preferred_range = 230.0
		elif boss_id == "kuijia":
			preferred_range = 260.0
		elif boss_id == "yinhun":
			preferred_range = 210.0
		elif boss_id == "luding":
			preferred_range = 170.0
		_apply_boss_visuals()
	elif final_boss:
		spritesheet_path = "res://assets/art/warrior_purple_8dir.png"
		anim_sprite.scale *= 1.16
		var light := get_node_or_null("PointLight2D") as PointLight2D
		if light != null:
			light.color = Color(0.8, 0.45, 1.0)
			light.energy = 0.85
		hit_stun_resist = 0.25
		_tint = Color(1.15, 0.85, 1.35)
		anim_sprite.modulate = _tint

	# 冲刺参数配置（关闭自动长扑定时器，改由出招大脑精确派发）
	charge_hit_radius = GameBalance.BOSS_CHARGE_HIT_RADIUS
	charge_duration = GameBalance.BOSS_CHARGE_DURATION
	charge_brake_time = GameBalance.BOSS_CHARGE_BRAKE
	charge_speed_mul = GameBalance.BOSS_CHARGE_SPEED_MUL
	charge_damage_mul = GameBalance.BOSS_CHARGE_DMG_MULT
	charge_side_bolts = GameBalance.BOSS_CHARGE_SIDE_BOLTS
	charge_whiff_stagger = 0.25
	charge_interval = 999999.0
	_charge_timer = 999999.0

	# 死亡演出分级（2026-10-15）：Boss 伏诛走「倾倒 → 尸体滞留慢渐隐」，不随小怪塌缩
	death_corpse_linger = true

	_purple_bolts = final_boss and (boss_id == "" or boss_id == "xinmo")
	_setup_patterns()
	super._ready()
	if procedural_view != null and boss_id != "":
		procedural_view.setup("boss_" + boss_id, true, true, final_boss)
	# 主题特效色：从程序化外观取主强调色，弹幕/冲击环/预警圈共用，别再靠 final_boss 一刀切紫/红
	if procedural_view != null and procedural_view.config != null:
		_fx_color = procedural_view.config.col_accent
		_fx_color.a = 1.0
	# 登场即上屏：HUD 血条由此信号点亮
	GameManager.boss_hp_changed.emit(current_hp, max_hp, boss_title)
	# Boss 战 BGM 压闷制造紧张感（伏诛/转阶段由 _die 与 play_bgm_key 负责解除）
	AudioManager.set_bgm_muffle(true)

func _apply_boss_visuals() -> void:
	var light := get_node_or_null("PointLight2D") as PointLight2D
	if boss_id == "chiyan":
		_tint = Color(1.7, 0.5, 0.45)
		if light != null:
			light.color = Color(1.0, 0.45, 0.3)
			light.energy = 0.75
	elif boss_id == "xiuluo":
		_tint = Color(1.3, 0.4, 0.4)
		hit_stun_resist = 0.2
		if light != null:
			light.color = Color(0.95, 0.25, 0.2)
			light.energy = 0.85
	elif boss_id == "qianji":
		_tint = Color(0.5, 0.85, 1.1)
		hit_stun_resist = 0.0
		if light != null:
			light.color = Color(0.35, 0.8, 0.95)
			light.energy = 0.85
	elif boss_id == "wangu":
		_tint = Color(0.5, 1.25, 0.6)
		hit_stun_resist = 0.2
		if light != null:
			light.color = Color(0.3, 0.9, 0.4)
			light.energy = 0.8
	elif boss_id == "jianpo":
		_tint = Color(0.9, 1.1, 1.3)
		hit_stun_resist = 0.15
		if light != null:
			light.color = Color(0.7, 0.9, 1.0)
			light.energy = 0.8
	# 深层专属魔君（W45~W100）染色必须排在 xinmo/final_boss 之前：深层波次 final_boss 恒真，
	# 新魔君若落进 xinmo 分支会被换紫皮抢走身份
	elif boss_id == "zhaoying":
		_tint = Color(0.85, 1.05, 1.3)
		hit_stun_resist = 0.15
		if light != null:
			light.color = Color(0.65, 0.85, 1.0)
			light.energy = 0.8
	elif boss_id == "yinhun":
		_tint = Color(0.6, 1.1, 0.95)
		hit_stun_resist = 0.2
		if light != null:
			light.color = Color(0.4, 0.85, 0.65)
			light.energy = 0.85
	elif boss_id == "luding":
		_tint = Color(1.45, 0.8, 0.55)
		hit_stun_resist = 0.35
		if light != null:
			light.color = Color(1.0, 0.55, 0.25)
			light.energy = 0.9
	elif boss_id == "canglong":
		_tint = Color(0.55, 1.35, 1.25)
		hit_stun_resist = 0.2
		if light != null:
			light.color = Color(0.35, 0.9, 0.85)
			light.energy = 0.85
	elif boss_id == "jianzhong":
		_tint = Color(0.95, 1.0, 1.15)
		hit_stun_resist = 0.15
		if light != null:
			light.color = Color(0.75, 0.85, 1.0)
			light.energy = 0.8
	elif boss_id == "leijie":
		_tint = Color(1.15, 0.95, 1.5)
		hit_stun_resist = 0.15
		if light != null:
			light.color = Color(0.7, 0.5, 1.0)
			light.energy = 0.9
	elif boss_id == "kunwang":
		_tint = Color(0.5, 0.75, 1.3)
		hit_stun_resist = 0.3
		if light != null:
			light.color = Color(0.3, 0.55, 0.95)
			light.energy = 0.85
	elif boss_id == "kuijia":
		_tint = Color(1.3, 1.05, 0.6)
		hit_stun_resist = 0.3
		if light != null:
			light.color = Color(0.95, 0.75, 0.35)
			light.energy = 0.8
	elif boss_id == "fenghuang":
		_tint = Color(1.6, 0.75, 0.45)
		hit_stun_resist = 0.15
		if light != null:
			light.color = Color(1.0, 0.5, 0.25)
			light.energy = 0.9
	elif boss_id == "tianmo":
		_tint = Color(0.9, 0.7, 1.2)
		hit_stun_resist = 0.2
		if light != null:
			light.color = Color(0.55, 0.35, 0.9)
			light.energy = 0.85
	elif boss_id == "hundun":
		_tint = Color(1.1, 1.1, 1.1)
		hit_stun_resist = 0.25
		if light != null:
			light.color = Color(0.8, 0.8, 0.8)
			light.energy = 0.8
	elif boss_id == "wanjie":
		_tint = Color(1.35, 1.1, 1.6)
		hit_stun_resist = 0.3
		if light != null:
			light.color = Color(0.9, 0.65, 1.0)
			light.energy = 0.95
	elif boss_id == "xinmo" or final_boss:
		spritesheet_path = "res://assets/art/warrior_purple_8dir.png"
		if anim_sprite != null:
			anim_sprite.scale *= 1.16
		_tint = Color(1.15, 0.85, 1.35)
		hit_stun_resist = 0.25
		if light != null:
			light.color = Color(0.8, 0.45, 1.0)
			light.energy = 0.85
	if anim_sprite != null:
		anim_sprite.modulate = _tint

func _setup_patterns() -> void:
	if boss_id == "":
		if final_boss:
			# 第 20 波魔尊：全招式全面施展
			_patterns = [
				Pattern.RING,
				Pattern.BURST_FAN,
				Pattern.SKY_FIRE,
				Pattern.CHARGE,
				Pattern.SPIRAL,
				Pattern.SPLIT_BOMB,
				Pattern.SLAM,
				Pattern.SUMMON,
			]
		elif _phase2:
			# 第 10 波狂暴形态：解锁天火与螺旋
			_patterns = [
				Pattern.RING,
				Pattern.BURST_FAN,
				Pattern.SKY_FIRE,
				Pattern.CHARGE,
				Pattern.SPIRAL,
				Pattern.SLAM,
				Pattern.SUMMON,
			]
		else:
			# 第 10 波常态起手
			_patterns = [
				Pattern.RING,
				Pattern.BURST_FAN,
				Pattern.CHARGE,
				Pattern.SLAM,
				Pattern.SUMMON,
			]
		return

	match boss_id:
		"chiyan":
			if _phase2:
				_patterns = [Pattern.RING, Pattern.BURST_FAN, Pattern.SKY_FIRE, Pattern.CHARGE, Pattern.SPIRAL, Pattern.SLAM, Pattern.SUMMON]
			else:
				_patterns = [Pattern.RING, Pattern.BURST_FAN, Pattern.CHARGE, Pattern.SLAM, Pattern.SUMMON]
		"xiuluo":
			if _phase2:
				_patterns = [Pattern.CHAIN_CHARGE, Pattern.SLAM, Pattern.BLINK_SLASH, Pattern.CHAIN_CHARGE, Pattern.RING, Pattern.SLAM]
			else:
				_patterns = [Pattern.CHAIN_CHARGE, Pattern.SLAM, Pattern.CHARGE, Pattern.BURST_FAN, Pattern.CHAIN_CHARGE, Pattern.SLAM]
		"qianji":
			if _phase2:
				_patterns = [Pattern.SPIRAL, Pattern.SPLIT_BOMB, Pattern.SKY_FIRE, Pattern.TURRET_SHIFT, Pattern.RING, Pattern.SPIRAL, Pattern.SPLIT_BOMB]
			else:
				_patterns = [Pattern.SPIRAL, Pattern.RING, Pattern.SPLIT_BOMB, Pattern.TURRET_SHIFT, Pattern.BURST_FAN, Pattern.RING]
		"wangu":
			if _phase2:
				_patterns = [Pattern.HAZARD_FIELD, Pattern.SUMMON, Pattern.SKY_FIRE, Pattern.SPLIT_BOMB, Pattern.HAZARD_FIELD, Pattern.SPIRAL]
			else:
				_patterns = [Pattern.HAZARD_FIELD, Pattern.SUMMON, Pattern.SPLIT_BOMB, Pattern.BURST_FAN, Pattern.HAZARD_FIELD, Pattern.RING]
		"jianpo":
			if _phase2:
				_patterns = [Pattern.BLINK_SLASH, Pattern.CHAIN_CHARGE, Pattern.BURST_FAN, Pattern.BLINK_SLASH, Pattern.SKY_FIRE, Pattern.SPIRAL]
			else:
				_patterns = [Pattern.BLINK_SLASH, Pattern.BURST_FAN, Pattern.CHARGE, Pattern.BLINK_SLASH, Pattern.RING, Pattern.BURST_FAN]
		"xinmo":
			if _phase2:
				_patterns = [Pattern.CHAIN_CHARGE, Pattern.SPIRAL, Pattern.BLINK_SLASH, Pattern.SPLIT_BOMB, Pattern.HAZARD_FIELD, Pattern.SKY_FIRE, Pattern.TURRET_SHIFT, Pattern.SLAM]
			else:
				_patterns = [Pattern.CHAIN_CHARGE, Pattern.SPIRAL, Pattern.HAZARD_FIELD, Pattern.SPLIT_BOMB, Pattern.BLINK_SLASH, Pattern.SKY_FIRE, Pattern.SLAM, Pattern.RING]
		# ---------------- 深层专属魔君（W45~W100，2026-11-03） ----------------
		"zhaoying":
			# 照影魔君（镜，W45 过渡档）：签名镜像夹击 —— 镜影虚像在玩家对侧发环、主身扇形夹击
			if _phase2:
				_patterns = [Pattern.MIRROR_FLANK, Pattern.SPIRAL, Pattern.BURST_FAN, Pattern.MIRROR_FLANK, Pattern.CHAIN_CHARGE, Pattern.RING]
			else:
				_patterns = [Pattern.MIRROR_FLANK, Pattern.BURST_FAN, Pattern.RING, Pattern.MIRROR_FLANK, Pattern.CHARGE]
		"yinhun":
			# 引魂使（幽冥，W50）：签名魂潮收网 —— 包围弹环从四面八方向玩家收拢，召唤鬼魂压场
			if _phase2:
				_patterns = [Pattern.SOUL_TIDE, Pattern.SUMMON, Pattern.HAZARD_FIELD, Pattern.SOUL_TIDE, Pattern.SPIRAL, Pattern.RING]
			else:
				_patterns = [Pattern.SOUL_TIDE, Pattern.SUMMON, Pattern.RING, Pattern.SOUL_TIDE, Pattern.SPIRAL]
		"luding":
			# 焚天炉君（丹炉，W55 过渡档）：签名炉压崩天 —— 站桩蓄力大圆炉爆，慢速重甲攻城锤
			if _phase2:
				_patterns = [Pattern.FURNACE_BLAST, Pattern.SLAM, Pattern.SPIRAL, Pattern.RING, Pattern.FURNACE_BLAST, Pattern.SPLIT_BOMB]
			else:
				_patterns = [Pattern.FURNACE_BLAST, Pattern.SLAM, Pattern.RING, Pattern.BURST_FAN, Pattern.FURNACE_BLAST]
		"canglong":
			# 太苍龙君（飞龙）：盘旋拉升 → 全场俯冲是签名招；龙息螺旋 + 落鳞天火惩罚站桩
			if _phase2:
				_patterns = [Pattern.DIVE, Pattern.SPIRAL, Pattern.SKY_FIRE, Pattern.DIVE, Pattern.BURST_FAN, Pattern.SPIRAL]
			else:
				_patterns = [Pattern.DIVE, Pattern.SPIRAL, Pattern.SKY_FIRE, Pattern.RING, Pattern.DIVE]
		"jianzhong":
			# 葬剑仙（剑冢）：万剑归宗（SIGNATURE）+ 御剑瞬斩，换桩留剑阵
			if _phase2:
				_patterns = [Pattern.SIGNATURE, Pattern.BLINK_SLASH, Pattern.CHAIN_CHARGE, Pattern.BURST_FAN, Pattern.SPIRAL, Pattern.TURRET_SHIFT]
			else:
				_patterns = [Pattern.SIGNATURE, Pattern.BLINK_SLASH, Pattern.BURST_FAN, Pattern.TURRET_SHIFT, Pattern.RING]
		"leijie":
			# 雷劫神君（雷劫）：连环天劫（SIGNATURE）+ 落雷轰炸，雷光折返冲阵穿插
			if _phase2:
				_patterns = [Pattern.SIGNATURE, Pattern.SKY_FIRE, Pattern.CHAIN_CHARGE, Pattern.SPIRAL, Pattern.SLAM, Pattern.RING]
			else:
				_patterns = [Pattern.SIGNATURE, Pattern.SKY_FIRE, Pattern.CHAIN_CHARGE, Pattern.RING, Pattern.BURST_FAN]
		"kunwang":
			# 覆海鲲王（深海巨兽）：冥海潮汐（SIGNATURE）+ 冥水领域封锁 + 潮汐震地
			if _phase2:
				_patterns = [Pattern.SIGNATURE, Pattern.HAZARD_FIELD, Pattern.SLAM, Pattern.SPIRAL, Pattern.SUMMON, Pattern.SKY_FIRE]
			else:
				_patterns = [Pattern.SIGNATURE, Pattern.HAZARD_FIELD, Pattern.SLAM, Pattern.SUMMON, Pattern.RING]
		"kuijia":
			# 千臂傀王（傀儡）：千臂机括（SIGNATURE）+ 傀潮召唤 + 换桩连弩
			if _phase2:
				_patterns = [Pattern.SIGNATURE, Pattern.SUMMON, Pattern.BURST_FAN, Pattern.SPIRAL, Pattern.TURRET_SHIFT, Pattern.RING]
			else:
				_patterns = [Pattern.SIGNATURE, Pattern.SUMMON, Pattern.BURST_FAN, Pattern.TURRET_SHIFT, Pattern.SLAM]
		"fenghuang":
			# 离火凤皇（火凤）：离火涅槃（SIGNATURE）+ 天火陨落；狂暴瞬间涅槃全屏火环
			if _phase2:
				_patterns = [Pattern.SIGNATURE, Pattern.SKY_FIRE, Pattern.CHAIN_CHARGE, Pattern.SPIRAL, Pattern.SPLIT_BOMB, Pattern.RING]
			else:
				_patterns = [Pattern.SIGNATURE, Pattern.SKY_FIRE, Pattern.CHARGE, Pattern.SPLIT_BOMB, Pattern.BURST_FAN]
		"tianmo":
			# 无相天魔（天魔）：无相三连（SIGNATURE）+ 蚀骨魔域，全场神出鬼没
			if _phase2:
				_patterns = [Pattern.SIGNATURE, Pattern.BLINK_SLASH, Pattern.HAZARD_FIELD, Pattern.CHAIN_CHARGE, Pattern.SKY_FIRE, Pattern.SPIRAL]
			else:
				_patterns = [Pattern.SIGNATURE, Pattern.BLINK_SLASH, Pattern.HAZARD_FIELD, Pattern.SPIRAL, Pattern.CHARGE]
		"hundun":
			# 元初兽（混沌）：混沌星散（SIGNATURE）+ 出招表每次重组，永远是下一招未知
			_patterns = [Pattern.RING, Pattern.BURST_FAN, Pattern.SPIRAL, Pattern.SPLIT_BOMB,
				Pattern.CHARGE, Pattern.SKY_FIRE, Pattern.SLAM, Pattern.SUMMON,
				Pattern.CHAIN_CHARGE, Pattern.TURRET_SHIFT, Pattern.HAZARD_FIELD, Pattern.BLINK_SLASH,
				Pattern.SIGNATURE]
			_shuffle_patterns()
		"wanjie":
			# 道劫化身（天劫压轴）：万劫加身（SIGNATURE）+ 十二招高压轮换
			if _phase2:
				_patterns = [Pattern.SIGNATURE, Pattern.RING, Pattern.BURST_FAN, Pattern.SPIRAL, Pattern.SPLIT_BOMB,
					Pattern.CHARGE, Pattern.SKY_FIRE, Pattern.SLAM, Pattern.SUMMON,
					Pattern.CHAIN_CHARGE, Pattern.TURRET_SHIFT, Pattern.HAZARD_FIELD, Pattern.BLINK_SLASH]
			else:
				_patterns = [Pattern.SIGNATURE, Pattern.RING, Pattern.SKY_FIRE, Pattern.CHAIN_CHARGE, Pattern.SPIRAL, Pattern.HAZARD_FIELD, Pattern.BLINK_SLASH, Pattern.SLAM, Pattern.SPLIT_BOMB]
		_:
			if _phase2 or final_boss:
				_patterns = [Pattern.RING, Pattern.BURST_FAN, Pattern.SKY_FIRE, Pattern.CHARGE, Pattern.SPIRAL, Pattern.SLAM, Pattern.SUMMON]
			else:
				_patterns = [Pattern.RING, Pattern.BURST_FAN, Pattern.CHARGE, Pattern.SLAM, Pattern.SUMMON]

## Boss 出招大脑：与 EnemyBase._physics_process 的移动/接触伤害并行运行
func _process(delta: float) -> void:
	if GameManager.is_game_over or dying:
		return
	# 位移账：本帧位置有变化就清零「没挪窝」计时（追击/冲锋/瞬移都算挪窝），
	# 否则累计 —— 互斥招式（震地/冲锋/螺旋）期间也照计，出来后才可能被强制机动。
	if _prev_pos_valid:
		# 阈值取 0.5px（平方 0.25）：60fps 下 Boss 移速 55~118px/s，单帧只有 0.9~2.0px，
		# 旧阈值 4.0（2px）会把正常追击判成「没挪窝」——反蹲坑实际变成「距上次冲锋/瞬移 9s」。
		if global_position.distance_squared_to(_prev_pos) > 0.25:
			_since_moved = 0.0
		else:
			_since_moved += delta
	_prev_pos = global_position
	_prev_pos_valid = true
	_hp_emit_cd -= delta
	_heavy_hit_cd = maxf(0.0, _heavy_hit_cd - delta)
	# 读招姿态接线（2026-10-19）：按 Boss 招式状态机维持 procedural_view.special_state 0→1，
	# _process 在物理帧之后运行（最后写者生效），覆盖 EnemyBase 同步段的归零。
	# 震地/冲锋预警有真实前摇给满值；引导/连射类（螺旋/扇形/天火）无起手预警，
	# 用固定中位读数表「正在施法」态，与蓄力可区分；全招式都发 recoil 爆发读数。
	_sync_cast_pose()
	var player = GameManager.player
	if player == null:
		return

	# 1a. 镜影夹击：对侧镜影圈填满 → 虚像环弹 + 主身扇形（预警期互斥锁）
	if _mirror_pending:
		_mirror_timer -= delta
		if _mirror_telegraph != null and is_instance_valid(_mirror_telegraph):
			_mirror_telegraph.progress = 1.0 - _mirror_timer / maxf(_mirror_windup_total, 0.001)
		_pp_target_vel = Vector2.ZERO
		velocity = Vector2.ZERO
		if _mirror_timer <= 0.0:
			_resolve_mirror_flank(player)
		return

	# 1b. 魂潮收网：玩家脚下收网点填满 → 四周包围环向内收拢（预警期互斥锁）
	if _soul_pending:
		_soul_timer -= delta
		if _soul_telegraph != null and is_instance_valid(_soul_telegraph):
			_soul_telegraph.progress = 1.0 - _soul_timer / maxf(_soul_windup_total, 0.001)
		_pp_target_vel = Vector2.ZERO
		velocity = Vector2.ZERO
		if _soul_timer <= 0.0:
			_resolve_soul_tide(player)
		return

	# 1c. 震地冲击：预警圈「填满式」倒计时 → 结算（预警期互斥锁）
	if _slam_pending:
		_slam_timer -= delta
		if _slam_ring != null:
			_slam_ring.progress = 1.0 - _slam_timer / maxf(_slam_windup_total, 0.001)
		if _slam_timer <= 0.0:
			_resolve_slam(player)
		return

	# 1b. 炉压崩天：站桩蓄力（更大更慢的全屏圈） → 炉爆结算（预警期互斥锁）
	if _furnace_pending:
		_furnace_timer -= delta
		if _furnace_ring != null:
			_furnace_ring.progress = 1.0 - _furnace_timer / maxf(_furnace_windup_total, 0.001)
		_pp_target_vel = Vector2.ZERO
		velocity = Vector2.ZERO
		if _furnace_timer <= 0.0:
			_resolve_furnace(player)
		return

	# 2. 破阵冲锋锁定段：预警或冲刺中不插新技能
	if _charge_windup > 0.0 or _charge_active > 0.0 or _charge_brake > 0.0:
		# 飞龙俯冲实冲段：沿路径两侧洒鳞弹（判定随机不涉及，固定夹角；轨迹读数与位移同源）
		if _dive_active and _charge_active > 0.0 and get_parent() != null:
			_dive_trail_timer -= delta
			if _dive_trail_timer <= 0.0:
				_dive_trail_timer = GameBalance.BOSS_DIVE_TRAIL_INTERVAL
				var dmg := maxf(1.0, contact_damage * GameBalance.BOSS_DIVE_TRAIL_DMG_MULT)
				var base_ang := _charge_dir.angle()
				for side in [-1.0, 1.0]:
					var bolt := EnemyBolt.acquire(get_parent())
					bolt.global_position = global_position
					bolt.direction = Vector2.from_angle(base_ang + side * PI * 0.5)
					bolt.speed = 190.0 * bolt_speed_mult
					bolt.damage = dmg
					bolt.scale_factor = 1.15
					bolt.purple_style = _purple_bolts
					bolt.tint_color = _fx_color
					bolt.activate()
				AudioManager.play_sfx("enemy_bolt", 0.35, 1.2)
		return

	# 3. 螺旋风暴引导施法：引导期间原地喷射弹幕
	if _spiral_active:
		_tick_spiral(delta)
		return

	# 4. 后台招式推进（扇形连射、天火定点与禁区封锁）
	_tick_burst_fan(delta, player)
	_tick_sky_fires(delta, player)
	_tick_hazard_fields(delta, player)

	# 5. 主技能循环定时器
	_attack_timer -= delta
	if _attack_timer <= 0.0:
		var mult := GameBalance.BOSS_PHASE2_INTERVAL_MULT if _phase2 else 1.0
		_attack_timer = attack_interval * mult
		_cast_next(player)

## Boss 选招权重（AI 行为，不改伤害）：远距离偏突进/远程，贴脸偏震地/环弹；上一招降权防连发；
## 按「多久没用」陈旧度加权防饿死（旧平局轮换规则会让部分招式永久坐板凳）；原地不动超时强制机动。
const PICK_WEIGHT_BASE := 1.0
const PICK_WEIGHT_FAR := 2.2
const PICK_WEIGHT_NEAR := 2.0
const PICK_WEIGHT_WRONG_RANGE := 0.3
const PICK_WEIGHT_REPEAT := 0.2
const PICK_STALENESS_BOOST := 0.6   ## 每搁置一次决策的权重增益
## 陈旧度上限从 2.4 提到 4.0（×5.0）：旧上限下「签名招 2.2 × 陈旧 2.2 = 4.84」永远压过
## 从未出过的 1.0 招（×3.4=3.4），canglong 只带 DIVE/RING 两招能赢，60s 只出 2 种。
## 5.0 让冷门招至少能翻上来一次，签名招仍靠 2.2 底权 + 施放后重置保持存在感。
const PICK_STALENESS_CAP := 4.0     ## 陈旧度增益上限（1+4.0=5.0 倍）
const PICK_MOBILITY_HINT_MULT := 3.0 ## 超提示线后机动招额外倍率
const PICK_FAR_RANGE := 320.0
const PICK_NEAR_RANGE := 140.0
const PICK_FAR_PATTERNS := [Pattern.CHARGE, Pattern.SKY_FIRE, Pattern.BURST_FAN, Pattern.CHAIN_CHARGE, Pattern.BLINK_SLASH, Pattern.DIVE, Pattern.MIRROR_FLANK, Pattern.SOUL_TIDE]
const PICK_NEAR_PATTERNS := [Pattern.SLAM, Pattern.RING, Pattern.BURST_FAN]
## 全距离中性招：以玩家为锚 / 自身位移后再打，贴脸时不该按「远距离错位」降权。
## 天火落点跟着玩家、俯冲先拉升换位、镜影/魂潮以玩家为圆心 —— 这些招与 Boss 站位无关。
const PICK_NEAR_NEUTRAL := [Pattern.BURST_FAN, Pattern.BLINK_SLASH, Pattern.MIRROR_FLANK, Pattern.SOUL_TIDE, Pattern.SKY_FIRE, Pattern.DIVE]
## 签名招身份底权：独立于距离偏好，保证每尊魔君的招牌动作稳定出场（不再被通用扇射/环弹挤掉）。
## 2.2 与远距离偏好同档，但不受贴脸降权；陈旧度/防连发仍在其上叠乘。
const PICK_SIGNATURE_BASE := 2.2
const PICK_SIGNATURE_PATTERNS := [Pattern.MIRROR_FLANK, Pattern.SOUL_TIDE, Pattern.FURNACE_BLAST, Pattern.DIVE, Pattern.SIGNATURE]
## 机动招（位移类）：决策超时保底的候选集，按优先级取第一个在轮换表里的
const MOBILITY_PATTERNS := [Pattern.TURRET_SHIFT, Pattern.BLINK_SLASH, Pattern.CHAIN_CHARGE, Pattern.CHARGE, Pattern.DIVE]

## 机动招落点钳制边界：地图物理边界内缩 BOSS_ARENA_EDGE_INSET（与 EnemyBase 的 ±460 钳制同图）
static func _arena_lim() -> float:
	return GameManager.MAP_HALF_EXTENT - GameBalance.BOSS_ARENA_EDGE_INSET

func _pick_pattern(player: Node2D) -> int:
	var dist: float = global_position.distance_to(player.global_position)
	# 决策超时强制档：长时间没挪窝且轮换表有机动招 → 直接出机动招（蹲坑硬上界）
	if _since_moved >= GameBalance.BOSS_REPOSITION_FORCE_SEC:
		for pat in MOBILITY_PATTERNS:
			if pat in _patterns:
				return pat
	var best_idx: int = 0
	var best_w: float = -1.0
	for i in range(_patterns.size()):
		var pat: int = _patterns[i]
		var w: float = PICK_WEIGHT_BASE
		if pat in PICK_SIGNATURE_PATTERNS:
			# 签名招不参与距离错位降权：贴脸时仍要出招牌，否则 Boss 身份被通用招淹没
			w = PICK_SIGNATURE_BASE
		elif dist > PICK_FAR_RANGE:
			if pat in PICK_FAR_PATTERNS:
				w = PICK_WEIGHT_FAR
			elif pat in PICK_NEAR_PATTERNS and pat != Pattern.BURST_FAN:
				w = PICK_WEIGHT_WRONG_RANGE
		elif dist < PICK_NEAR_RANGE:
			if pat in PICK_NEAR_PATTERNS:
				w = PICK_WEIGHT_NEAR
			elif pat in PICK_FAR_PATTERNS and pat not in PICK_NEAR_NEUTRAL:
				# 全距离中性招（瞬步/扇形/镜影/魂潮/天火/俯冲）不降权；只惩罚真正吃距离的冲锋类
				w = PICK_WEIGHT_WRONG_RANGE
		# 防连发：上一招降权
		if pat == _last_pattern:
			w *= PICK_WEIGHT_REPEAT
		# 防饿死：按搁置决策数加权，每个招式都有出场机会（确定性，不抽 rng）
		var stale: int = _casts_total - int(_pattern_last_cast.get(pat, -20))
		w *= 1.0 + minf(float(maxi(0, stale)) * PICK_STALENESS_BOOST, PICK_STALENESS_CAP)
		# 决策超时提示档：一段时间没挪窝 → 机动招额外加权
		if _since_moved >= GameBalance.BOSS_REPOSITION_HINT_SEC and pat in MOBILITY_PATTERNS:
			w *= PICK_MOBILITY_HINT_MULT
		if w > best_w + 0.0001:
			best_w = w
			best_idx = i
	return _patterns[best_idx]

func _cast_next(player: Node2D) -> void:
	if _patterns.is_empty():
		return
	var pattern: int = _pick_pattern(player)
	_last_pattern = pattern
	_pattern_last_cast[pattern] = _casts_total
	_casts_total += 1
	_pattern_idx += 1
	match pattern:
		Pattern.RING:
			_cast_ring()
		Pattern.BURST_FAN:
			_cast_burst_fan(player)
		Pattern.SPIRAL:
			_cast_spiral()
		Pattern.SPLIT_BOMB:
			_cast_split_bomb(player)
		Pattern.CHARGE:
			_cast_charge(player)
		Pattern.SKY_FIRE:
			_cast_sky_fire(player)
		Pattern.SLAM:
			_cast_slam()
		Pattern.SUMMON:
			_cast_summon(player)
		Pattern.CHAIN_CHARGE:
			_cast_chain_charge(player)
		Pattern.TURRET_SHIFT:
			_cast_turret_shift(player)
		Pattern.HAZARD_FIELD:
			_cast_hazard_field(player)
		Pattern.BLINK_SLASH:
			_cast_blink_slash(player)
		Pattern.DIVE:
			_cast_dive(player)
		Pattern.MIRROR_FLANK:
			_cast_mirror_flank(player)
		Pattern.SOUL_TIDE:
			_cast_soul_tide(player)
		Pattern.FURNACE_BLAST:
			_cast_furnace_blast(player)
		Pattern.SIGNATURE:
			_cast_signature(player)

## 元初兽（混沌）出招表重组：Fisher-Yates 走玩法 RNG（出招序列影响判定，不许用全局 randf）
func _shuffle_patterns() -> void:
	for i in range(_patterns.size() - 1, 0, -1):
		var j := GameManager.rng.randi_range(0, i)
		var tmp: int = _patterns[i]
		_patterns[i] = _patterns[j]
		_patterns[j] = tmp

# ---------------- 招式 1：双层交错弧线环弹 ----------------

func _cast_ring() -> void:
	play_squash(Vector2(1.25, 0.78), 0.5)
	_pose_burst()  # 瞬发爆发读数（渲染器后坐一态）
	var tw := create_tween()
	tw.tween_property(anim_sprite, "modulate", _fx_color.lightened(0.35), 0.35)
	tw.tween_callback(func(): _fire_ring_layer(1))
	tw.tween_interval(GameBalance.BOSS_RING_LAYER_DELAY)
	tw.tween_callback(func(): _fire_ring_layer(2))
	if _phase2:
		tw.tween_interval(0.24)
		tw.tween_callback(func(): _fire_ring_layer(3))
	tw.tween_property(anim_sprite, "modulate", _tint, 0.25)

func _fire_ring_layer(layer: int) -> void:
	if dying or get_parent() == null:
		return
	var count: int = GameBalance.BOSS_RING_COUNT + (GameBalance.BOSS_RING_COUNT_P2 if _phase2 else 0)
	var dmg := maxf(1.0, contact_damage * GameBalance.BOSS_RING_DMG_MULT)
	var ang_spd := 0.0
	var offset_ang := 0.0
	var spd := GameBalance.BOSS_BOLT_SPEED * bolt_speed_mult

	if layer == 1:
		ang_spd = GameBalance.BOSS_RING_CURVE_ANG   # 顺时针弧线
		offset_ang = 0.0
	elif layer == 2:
		ang_spd = -GameBalance.BOSS_RING_CURVE_ANG  # 逆时针交错弧线
		offset_ang = TAU / float(count * 2)
	elif layer == 3:
		ang_spd = 0.0                              # 直线高速穿透环
		spd = GameBalance.BOSS_BOLT_SPEED * 1.25 * bolt_speed_mult
		offset_ang = TAU / float(count * 4)

	for i in range(count):
		var ang := offset_ang + TAU * float(i) / float(count)
		var bolt := EnemyBolt.acquire(get_parent())
		bolt.global_position = global_position
		bolt.direction = Vector2(cos(ang), sin(ang))
		bolt.speed = spd
		bolt.damage = dmg
		bolt.scale_factor = GameBalance.BOSS_BOLT_SCALE
		bolt.angular_speed = ang_spd
		bolt.purple_style = _purple_bolts
		bolt.tint_color = _fx_color
		bolt.activate()
	AudioManager.play_sfx("enemy_bolt", 0.65)
	GameManager.add_trauma(0.12)

# ---------------- 招式 2：扇形连射狙击 ----------------

func _cast_burst_fan(player: Node2D) -> void:
	_fan_waves_left = GameBalance.BOSS_FAN_WAVES_P2 if _phase2 else GameBalance.BOSS_FAN_WAVES
	_fan_wave_timer = 0.0
	play_squash(Vector2(1.2, 0.82), 0.3)

func _tick_burst_fan(delta: float, player: Node2D) -> void:
	if _fan_waves_left <= 0:
		return
	_fan_wave_timer -= delta
	if _fan_wave_timer <= 0.0:
		_fan_wave_timer = GameBalance.BOSS_FAN_WAVE_INTERVAL
		_fan_waves_left -= 1
		var total_waves := GameBalance.BOSS_FAN_WAVES_P2 if _phase2 else GameBalance.BOSS_FAN_WAVES
		var wave_idx := total_waves - _fan_waves_left
		var to_p: Vector2 = player.global_position - global_position
		var base_dir: Vector2 = to_p.normalized() if to_p.length_squared() > 1.0 else Vector2.RIGHT
		var count := GameBalance.BOSS_FAN_COUNT
		var spread := GameBalance.BOSS_FAN_SPREAD
		var spd := (GameBalance.BOSS_FAN_BASE_SPEED + float(wave_idx - 1) * 45.0) * bolt_speed_mult
		var dmg := maxf(1.0, contact_damage * GameBalance.BOSS_FAN_DMG_MULT)
		for i in range(count):
			var ang_offset := (float(i) - float(count - 1) * 0.5) * spread
			var bolt := EnemyBolt.acquire(get_parent())
			bolt.global_position = global_position
			bolt.direction = base_dir.rotated(ang_offset)
			bolt.speed = spd
			bolt.damage = dmg
			bolt.scale_factor = 1.3
			bolt.purple_style = _purple_bolts
			bolt.tint_color = _fx_color
			bolt.activate()
		AudioManager.play_sfx("enemy_bolt", 0.6, 1.0 + float(wave_idx) * 0.08)

# ---------------- 招式 3：螺旋风暴弹幕 ----------------

func _cast_spiral() -> void:
	_spiral_active = true
	_spiral_timer = GameBalance.BOSS_SPIRAL_DURATION
	_spiral_step_timer = 0.0
	_spiral_angle = 0.0
	play_squash(Vector2(0.85, 1.25), 0.4)
	var tw := create_tween()
	tw.tween_property(anim_sprite, "modulate", _fx_color.lightened(0.3), 0.25)
	tw.tween_interval(GameBalance.BOSS_SPIRAL_DURATION)
	tw.tween_property(anim_sprite, "modulate", _tint, 0.25)

func _tick_spiral(delta: float) -> void:
	_spiral_timer -= delta
	_spiral_step_timer -= delta
	_spiral_angle += GameBalance.BOSS_SPIRAL_ROT_SPEED * delta
	# 引导期间保持蓄力姿态
	_pp_target_vel = Vector2.ZERO
	velocity = Vector2.ZERO
	if _spiral_step_timer <= 0.0:
		_spiral_step_timer = GameBalance.BOSS_SPIRAL_INTERVAL
		var arms := GameBalance.BOSS_SPIRAL_ARMS_FINAL if (final_boss or _phase2) else GameBalance.BOSS_SPIRAL_ARMS
		var dmg := maxf(1.0, contact_damage * GameBalance.BOSS_SPIRAL_DMG_MULT)
		for arm in range(arms):
			var arm_ang := _spiral_angle + TAU * float(arm) / float(arms)
			var bolt := EnemyBolt.acquire(get_parent())
			bolt.global_position = global_position
			bolt.direction = Vector2(cos(arm_ang), sin(arm_ang))
			bolt.speed = GameBalance.BOSS_SPIRAL_BOLT_SPEED * bolt_speed_mult
			bolt.angular_speed = GameBalance.BOSS_SPIRAL_ANGULAR
			bolt.damage = dmg
			bolt.scale_factor = 1.2
			bolt.purple_style = _purple_bolts
			bolt.tint_color = _fx_color
			bolt.activate()
		AudioManager.play_sfx("enemy_bolt", 0.45)
	if _spiral_timer <= 0.0:
		_spiral_active = false

# ---------------- 招式 4：分裂子母弹 ----------------

func _cast_split_bomb(player: Node2D) -> void:
	var count := GameBalance.BOSS_SPLIT_BOMB_COUNT_FINAL if (final_boss or _phase2) else GameBalance.BOSS_SPLIT_BOMB_COUNT
	var to_p: Vector2 = player.global_position - global_position
	var base_dir: Vector2 = to_p.normalized() if to_p.length_squared() > 1.0 else Vector2.RIGHT
	var base_ang := base_dir.angle()
	play_squash(Vector2(0.82, 1.25), 0.3)
	_pose_burst()  # 瞬发爆发读数（渲染器后坐一态）
	AudioManager.play_sfx("enemy_fuse", 0.75)
	for i in range(count):
		var offset := (float(i) - float(count - 1) * 0.5) * 0.32
		var dir := Vector2.from_angle(base_ang + offset)
		var bolt := EnemyBolt.acquire(get_parent())
		bolt.global_position = global_position
		bolt.direction = dir
		bolt.speed = GameBalance.BOSS_SPLIT_BOMB_SPEED * bolt_speed_mult
		bolt.scale_factor = GameBalance.BOSS_SPLIT_BOMB_SCALE
		bolt.damage = maxf(1.0, contact_damage * GameBalance.BOSS_SPLIT_BOMB_DMG_MULT)
		bolt.split_timer = GameBalance.BOSS_SPLIT_BOMB_FUSE
		bolt.split_count = GameBalance.BOSS_SPLIT_BOMB_CHILD_COUNT
		bolt.split_speed = GameBalance.BOSS_SPLIT_BOMB_CHILD_SPEED * bolt_speed_mult
		bolt.split_scale = GameBalance.BOSS_SPLIT_BOMB_CHILD_SCALE
		bolt.split_damage = maxf(1.0, contact_damage * GameBalance.BOSS_SPLIT_CHILD_DMG_MULT)
		bolt.purple_style = _purple_bolts
		bolt.tint_color = _fx_color
		bolt.activate()
	# 齐射瞬间给一圈主题色冲击环：读出「这一波要散成子母弹」，与分裂时子弹出膛呼应
	JuiceEffect.spawn_shockwave(get_parent(), global_position, 44.0, _fx_color, 0.24)

# ---------------- 招式 5：破阵冲锋 + 侧翼洒弹 ----------------

func _cast_charge(player: Node2D) -> void:
	_charge_dir = (player.global_position - global_position).normalized()
	# 锁向复位：旧写法只在第一次冲锋后保持 true，后续每轮从起手就锁死，预警线不再跟人。
	# 现在每轮重新进入「先跟随后锁向」，与 EnemyAiCharge 的末段锁向约定一致。
	_charge_aim_locked = false
	_charge_windup = GameBalance.BOSS_CHARGE_WINDUP
	_charge_windup_total = _charge_windup
	_charge_timer = 999999.0
	charge_interval = 999999.0
	_update_charge_warning(player)
	play_squash(Vector2(1.22, 0.78), GameBalance.BOSS_CHARGE_WINDUP)
	AudioManager.play_sfx("enemy_fuse", 0.7)

func _start_charge(dir: Vector2) -> void:
	if _dive_pending:
		_dive_pending = false
		_dive_active = true
		_dive_trail_timer = 0.0
	_charge_active = charge_duration
	_charge_dir = dir
	_charge_brake = 0.0
	_charge_stagger = 0.0
	_charge_hit = false
	# 冲锋期间关掉对玩家的物理碰撞（2026-11-03）：贴身起冲会被玩家碰撞体挡成零位移
	# （身体已嵌在玩家碰撞半径里，move_and_slide 全程滑动）——冲锋伤害本就走
	# charge_hit_radius 线段扫掠、不靠身体碰撞，关掉后冲锋能穿身而过完成换位。
	collision_mask &= ~2
	play_squash(Vector2(0.78, 1.24), 0.2)
	JuiceEffect.spawn_step_dust(get_parent(), global_position + Vector2(0, 12), dir)
	if charge_side_bolts > 0 and get_parent() != null:
		var base_ang := dir.angle()
		var dmg := maxf(1.0, contact_damage * 0.45)
		for side in [-1.0, 1.0]:
			for i in range(charge_side_bolts):
				var bolt := EnemyBolt.acquire(get_parent())
				bolt.global_position = global_position
				bolt.direction = Vector2.from_angle(base_ang + side * PI * 0.5 + side * float(i) * 0.22)
				bolt.damage = dmg
				bolt.scale_factor = 1.2
				bolt.purple_style = _purple_bolts
				bolt.tint_color = _fx_color
				bolt.activate()
	AudioManager.play_sfx("enemy_slam", 0.85)
	GameManager.add_trauma(0.12)
	_clear_charge_warning()

func _settle_charge_recovery() -> void:
	# 俯冲收势优先：先恢复原冲锋口径再进常规收势，避免链冲续段吃到俯冲参数
	var was_dive := _dive_active or _dive_pending
	if was_dive:
		_settle_dive()
	super._settle_charge_recovery()
	if (_phase2 or final_boss) and not was_dive:  # 俯冲已有落点环爆，不再叠通用收势环
		_fire_mini_ring(8, 255.0, 1.1)
	if _chain_charges_left > 0:
		_chain_charges_left -= 1
		var p = GameManager.player
		if p != null and not dying:
			_charge_stagger = 0.0
			_charge_dir = (p.global_position - global_position).normalized()
			_charge_aim_locked = false
			var gap: float = GameBalance.BOSS_CHAIN_CHARGE_GAP
			_charge_windup = gap
			_charge_windup_total = gap
			_update_charge_warning(p)
			play_squash(Vector2(1.22, 0.78), gap)
			AudioManager.play_sfx("enemy_fuse", 0.7)
			if _chain_charges_left == 0:
				charge_whiff_stagger = 0.55
	else:
		charge_whiff_stagger = 0.25
	if _chain_charges_left <= 0:
		collision_mask |= 2  # 冲锋全程结束才恢复对玩家的物理碰撞（连环冲段间保持穿透）

## 罡风定身打断俯冲前摇：super 只清预警线，这里补回冲锋口径与 _dive_pending，
## 否则下一次普通冲锋会被 _start_charge 当成俯冲（7.2 倍速 + 路径洒鳞）。
func apply_vortex_pin(pull_velocity: Vector2, pin_sec: float) -> void:
	super.apply_vortex_pin(pull_velocity, pin_sec)
	if _dive_pending:
		_dive_pending = false
		_dive_active = false
		_restore_charge_params()

# ---------------- 招式 9：多段折返连冲 ----------------

func _cast_chain_charge(player: Node2D) -> void:
	var total_cnt: int = GameBalance.BOSS_CHAIN_CHARGE_COUNT_P2 if (_phase2 or final_boss) else GameBalance.BOSS_CHAIN_CHARGE_COUNT
	_chain_charges_left = maxi(1, total_cnt) - 1
	charge_whiff_stagger = 0.55 if _chain_charges_left == 0 else 0.0
	_cast_charge(player)

# ---------------- 招式 10：阵眼换桩瞬移 + 双环震爆 ----------------

func _cast_turret_shift(player: Node2D) -> void:
	if dying or get_parent() == null:
		return
	# 换桩落点以地图原点为心（2026-11-03 修复：旧屏幕坐标中心 (480,270) + 90~870 钳制会把
	# 落点钳出 ±460 物理边界，被物理钳硬拉回边缘 —— 炮台越换桩越贴角落的根因）
	var center := Vector2.ZERO
	var p_pos := player.global_position if (player != null and is_instance_valid(player)) else center
	var from_center := (p_pos - center)
	var away_dir := -from_center.normalized() if from_center.length_squared() > 1.0 else Vector2.LEFT
	var jitter := (GameManager.rng.randf() - 0.5) * 0.7
	var new_pos := center + away_dir.rotated(jitter) * GameBalance.BOSS_TURRET_TELEPORT_RADIUS
	# 落点重采样：玩家不动时 away_dir 恒定，jitter≈0 会让连续换桩落在原地（照样「不动」）；
	# 用玩法 rng 最多重摇 4 次，保证新桩位与现位拉开距离（判定性随机，走 GameManager.rng）
	for try in range(4):
		if new_pos.distance_to(global_position) >= 140.0:
			break
		jitter = (GameManager.rng.randf() - 0.5) * PI
		new_pos = center + away_dir.rotated(jitter) * GameBalance.BOSS_TURRET_TELEPORT_RADIUS
	var lim := _arena_lim()
	new_pos = new_pos.clamp(Vector2(-lim, -lim), Vector2(lim, lim))

	# 1. 原位留小环弹与震波
	JuiceEffect.spawn_shockwave(get_parent(), global_position, 60.0, _fx_color, 0.26)
	_fire_mini_ring(8, 200.0, 1.0)
	AudioManager.play_sfx("enemy_fuse", 0.7)

	# 2. 瞬移到新阵点
	global_position = new_pos
	JuiceEffect.spawn_shockwave(get_parent(), new_pos, 85.0, _fx_color, 0.3)
	play_squash(Vector2(0.78, 1.25), 0.25)
	_pose_burst()

	# 3. 爆一圈弧线环弹
	_fire_ring_layer(1)

# ---------------- 招式 6：追踪天火连环轰炸 ----------------

func _cast_sky_fire(player: Node2D) -> void:
	_sky_fire_strikes_left = GameBalance.BOSS_SKY_FIRE_COUNT_P2 if _phase2 else GameBalance.BOSS_SKY_FIRE_COUNT
	_sky_fire_spawn_timer = 0.0
	play_squash(Vector2(0.9, 1.2), 0.3)

func _tick_sky_fires(delta: float, player: Node2D) -> void:
	if _sky_fire_strikes_left > 0:
		_sky_fire_spawn_timer -= delta
		if _sky_fire_spawn_timer <= 0.0:
			_sky_fire_spawn_timer = GameBalance.BOSS_SKY_FIRE_INTERVAL
			_sky_fire_strikes_left -= 1
			var lead: Vector2 = player.velocity * 0.18 if (player is CharacterBody2D) else Vector2.ZERO
			var strike_pos: Vector2 = player.global_position + lead
			var tg := AoeTelegraph.new()
			tg.radius = GameBalance.BOSS_SKY_FIRE_RADIUS
			tg.color = _fx_color
			tg.progress = 0.0
			get_parent().add_child(tg)
			tg.global_position = strike_pos
			var windup: float = GameBalance.aoe_windup(GameBalance.BOSS_SKY_FIRE_RADIUS)
			_active_sky_fires.append({
				"telegraph": tg,
				"timer": windup,
				"windup": windup,
				"pos": strike_pos
			})
			AudioManager.play_sfx("enemy_fuse", 0.6)

	var i := 0
	while i < _active_sky_fires.size():
		var fire: Dictionary = _active_sky_fires[i]
		fire.timer -= delta
		var tg: AoeTelegraph = fire.telegraph
		if tg != null and is_instance_valid(tg):
			tg.progress = 1.0 - fire.timer / maxf(float(fire.windup), 0.001)
		if fire.timer <= 0.0:
			_resolve_single_sky_fire(fire.pos, player)
			if tg != null and is_instance_valid(tg):
				tg.queue_free()
			_active_sky_fires.remove_at(i)
		else:
			i += 1

func _resolve_single_sky_fire(pos: Vector2, player: Node2D) -> void:
	if dying or get_parent() == null:
		return
	JuiceEffect.spawn_shockwave(get_parent(), pos, GameBalance.BOSS_SKY_FIRE_RADIUS, _fx_color)
	# 落点留焦痕（纯视觉贴花，判定已在下方结算）
	GroundDecal.spawn(get_parent(), pos, GroundDecal.Kind.SCORCH, GameBalance.BOSS_SKY_FIRE_RADIUS * 0.6)
	AudioManager.play_sfx("enemy_slam", 0.9)
	if player != null and is_instance_valid(player) and player.global_position.distance_to(pos) <= GameBalance.BOSS_SKY_FIRE_RADIUS:
		player.take_damage(maxf(1.0, contact_damage * GameBalance.BOSS_SKY_FIRE_DMG_MULT), pos)
		GameManager.trigger_screen_shockwave(player.global_position)

# ---------------- 招式 7：震地冲击（含近远派生） ----------------

func _cast_slam() -> void:
	_slam_pending = true
	# 预警时长按半径公平线裁定（R=175 → ~1.22s）：大圈给足跑出半径的逃生时间
	_slam_windup_total = GameBalance.aoe_windup(GameBalance.BOSS_SLAM_RADIUS)
	_slam_timer = _slam_windup_total
	if _slam_ring == null:
		_slam_ring = AoeTelegraph.new()
		_slam_ring.radius = GameBalance.BOSS_SLAM_RADIUS
		add_child(_slam_ring)
	_slam_ring.color = _fx_color
	_slam_ring.progress = 0.0
	_slam_ring.visible = true
	AudioManager.play_sfx("enemy_fuse", 0.7)
	play_squash(Vector2(0.82, 1.2), 0.4)

func _resolve_slam(player: Node2D = null) -> void:
	_slam_pending = false
	if _slam_ring != null:
		_slam_ring.visible = false
	if dying:
		return
	JuiceEffect.spawn_shockwave(get_parent(), global_position, GameBalance.BOSS_SLAM_RADIUS, _fx_color)
	# 落点留震裂（纯视觉贴花，判定已在下方结算）
	GroundDecal.spawn(get_parent(), global_position, GroundDecal.Kind.CRACK, GameBalance.BOSS_SLAM_RADIUS)
	GameManager.feedback(GameManager.FeedbackTier.HEAVY)
	AudioManager.play_sfx("enemy_slam", 1.1)
	if player == null:
		player = GameManager.player
	if player != null and is_instance_valid(player) and player.global_position.distance_to(global_position) <= GameBalance.BOSS_SLAM_RADIUS:
		player.take_damage(maxf(1.0, contact_damage * GameBalance.BOSS_SLAM_DMG_MULT), global_position)
		GameManager.trigger_screen_shockwave(player.global_position)
	# 二阶段或魔尊：震地炸裂顺发 12 颗外散冲击火球
	if _phase2 or final_boss:
		_fire_mini_ring(12, 280.0, 1.2)

# ---------------- 招式 8：召唤妖群 + 弹幕掩护 ----------------

func _cast_summon(player: Node2D) -> void:
	if GameManager.enemy_count < GameBalance.BOSS_SUMMON_CAP:
		var count: int = GameBalance.BOSS_SUMMON_COUNT + (1 if _phase2 else 0)
		var hp_mult := GameBalance.enemy_hp_mult(GameManager.wave_number) * GameBalance.danger_hp_mult(GameManager.danger_level)
		var dmg_mult := GameBalance.enemy_dmg_mult(GameManager.wave_number) * GameBalance.danger_dmg_mult(GameManager.danger_level)
		var scenes: Array = _get_deep_minion_scenes() if GameManager.wave_number >= GameBalance.BOSS_DEEP_MINION_MIN_WAVE else _minion_scenes
		if scenes.is_empty():
			scenes = _minion_scenes
		for i in range(count):
			var scene: PackedScene = scenes[i % scenes.size()]
			var minion := EnemyBase.acquire_or_new(scene)
			if minion == null:
				continue
			minion.reset_for_reuse()
			var ang := GameManager.rng.randf() * TAU
			minion.global_position = global_position + Vector2(cos(ang), sin(ang)) * 110.0
			minion.add_to_group("enemies")
			minion.max_hp = ceilf(minion.max_hp * hp_mult)
			minion.contact_damage = ceilf(minion.contact_damage * dmg_mult)
			minion.activate()
			get_parent().add_child(minion)
		play_squash(Vector2(1.18, 0.85), 0.25)
		AudioManager.play_sfx("wave_start", 0.7)
	# 召唤同时朝玩家打出一组掩护火球
	_fire_cover_spread(player)
	_pose_burst()  # 瞬发爆发读数（掩护齐射的渲染器后坐一态）

# ---------------- 辅助弹幕发射 ----------------

func _fire_mini_ring(count: int, spd: float, scl: float) -> void:
	if dying or get_parent() == null:
		return
	var dmg := maxf(1.0, contact_damage * 0.45)
	for i in range(count):
		var ang := TAU * float(i) / float(count)
		var bolt := EnemyBolt.acquire(get_parent())
		bolt.global_position = global_position
		bolt.direction = Vector2(cos(ang), sin(ang))
		bolt.speed = spd * bolt_speed_mult
		bolt.damage = dmg
		bolt.scale_factor = scl
		bolt.purple_style = _purple_bolts
		bolt.tint_color = _fx_color
		bolt.activate()

func _fire_cover_spread(player: Node2D) -> void:
	if dying or get_parent() == null or player == null:
		return
	var base_dir := (player.global_position - global_position).normalized()
	var dmg := maxf(1.0, contact_damage * 0.45)
	for ang in [-0.28, 0.0, 0.28]:
		var bolt := EnemyBolt.acquire(get_parent())
		bolt.global_position = global_position
		bolt.direction = base_dir.rotated(ang)
		bolt.speed = 260.0 * bolt_speed_mult
		bolt.damage = dmg
		bolt.scale_factor = 1.2
		bolt.purple_style = _purple_bolts
		bolt.tint_color = _fx_color
		bolt.activate()

# ---------------- 招式 11：连环禁区封锁 ----------------

func _cast_hazard_field(player: Node2D) -> void:
	_hazard_fields_left = GameBalance.BOSS_HAZARD_FIELD_COUNT_P2 if (_phase2 or final_boss) else GameBalance.BOSS_HAZARD_FIELD_COUNT
	_hazard_spawn_timer = 0.0
	play_squash(Vector2(0.9, 1.2), 0.3)
	_pose_burst()

func _tick_hazard_fields(delta: float, player: Node2D) -> void:
	if _hazard_fields_left > 0:
		_hazard_spawn_timer -= delta
		if _hazard_spawn_timer <= 0.0:
			_hazard_spawn_timer = 0.18
			_hazard_fields_left -= 1
			var total_cnt: int = GameBalance.BOSS_HAZARD_FIELD_COUNT_P2 if (_phase2 or final_boss) else GameBalance.BOSS_HAZARD_FIELD_COUNT
			var idx: int = total_cnt - _hazard_fields_left
			var p_pos := player.global_position if (player != null and is_instance_valid(player)) else global_position
			var p_vel: Vector2 = player.velocity if (player is CharacterBody2D) else Vector2.ZERO
			# 落点编排（禁区不压顶治理）：首圈沿速度侧向踢出半步，后续圈沿跑向逐个前压时
			# 保持同侧收拢、站桩时绕身散布 —— 三片呈弧形封位而非包围，身后始终留安全走廊。
			var side_dir: Vector2 = aoe_zone_side_dir(p_vel)
			var edge: float = GameBalance.aoe_zone_edge_offset(GameBalance.BOSS_HAZARD_FIELD_RADIUS)
			var offset := Vector2.ZERO
			if idx == 0:
				offset = side_dir * edge
			elif p_vel.length_squared() > 100.0:
				offset = p_vel.normalized() * (60.0 * float(idx)) + side_dir * (edge + 35.0 * float(idx - 1))
			else:
				offset = side_dir.rotated(float(idx) * 2.1) * (edge + 80.0 + float(idx) * 25.0)
			var target_pos := p_pos + offset
			var lim := _arena_lim()
			target_pos = target_pos.clamp(Vector2(-lim, -lim), Vector2(lim, lim))

			var tg := AoeTelegraph.new()
			tg.radius = GameBalance.BOSS_HAZARD_FIELD_RADIUS
			tg.color = _fx_color
			tg.progress = 0.0
			get_parent().add_child(tg)
			tg.global_position = target_pos
			var windup: float = GameBalance.aoe_windup(GameBalance.BOSS_HAZARD_FIELD_RADIUS)
			_active_hazard_fields.append({
				"telegraph": tg,
				"timer": windup,
				"windup": windup,
				"pos": target_pos
			})
			AudioManager.play_sfx("enemy_fuse", 0.6)

	var i := 0
	while i < _active_hazard_fields.size():
		var field: Dictionary = _active_hazard_fields[i]
		field.timer -= delta
		var tg: AoeTelegraph = field.get("telegraph")
		if tg != null and is_instance_valid(tg):
			tg.progress = 1.0 - field.timer / maxf(float(field.windup), 0.001)
		if field.timer <= 0.0:
			_resolve_single_hazard_field(field.pos)
			if tg != null and is_instance_valid(tg):
				tg.queue_free()
			_active_hazard_fields.remove_at(i)
		else:
			i += 1

func _resolve_single_hazard_field(pos: Vector2) -> void:
	if dying or get_parent() == null:
		return
	var pool := PoisonPool.acquire(get_parent())
	pool.global_position = pos
	pool.damage = maxf(1.0, contact_damage * GameBalance.BOSS_HAZARD_FIELD_DMG_MULT)
	pool.duration = GameBalance.BOSS_HAZARD_FIELD_DURATION
	pool.scale_factor = GameBalance.BOSS_HAZARD_FIELD_RADIUS / PoisonPool.RADIUS
	pool.activate()
	# 场域颜色跟随本尊主题色：万蛊碧绿、鲲王沧蓝、引魂幽绿、心魔紫红，不再 W20+ 一刀切红
	pool.modulate = _fx_color.lightened(0.25) if not _purple_bolts else Color(1.55, 0.45, 0.55)
	JuiceEffect.spawn_shockwave(get_parent(), pos, GameBalance.BOSS_HAZARD_FIELD_RADIUS, _fx_color, 0.28)
	AudioManager.play_sfx("enemy_poison", 1.0, 0.85)

# ---------------- 招式 12：瞬步贴脸扇形回斩 ----------------

func _cast_blink_slash(player: Node2D) -> void:
	if dying or get_parent() == null or player == null or not is_instance_valid(player):
		return
	var p_pos := player.global_position
	var p_vel: Vector2 = player.velocity if (player is CharacterBody2D) else Vector2.ZERO
	var behind_dir: Vector2
	if p_vel.length_squared() > 100.0:
		behind_dir = -p_vel.normalized().rotated((GameManager.rng.randf() - 0.5) * 0.8)
	else:
		behind_dir = Vector2.from_angle(GameManager.rng.randf() * TAU)
	var target_pos := p_pos + behind_dir * GameBalance.BOSS_BLINK_SLASH_DIST
	var lim := _arena_lim()
	target_pos = target_pos.clamp(Vector2(-lim, -lim), Vector2(lim, lim))

	JuiceEffect.spawn_shockwave(get_parent(), global_position, 50.0, _fx_color, 0.22)
	global_position = target_pos
	JuiceEffect.spawn_shockwave(get_parent(), target_pos, 60.0, _fx_color, 0.25)
	AudioManager.play_sfx("enemy_slam", 0.85)
	play_squash(Vector2(1.25, 0.8), 0.2)
	_pose_burst()

	var bolts_count: int = GameBalance.BOSS_BLINK_SLASH_BOLTS_P2 if (_phase2 or final_boss) else GameBalance.BOSS_BLINK_SLASH_BOLTS
	var to_p: Vector2 = (player.global_position - global_position).normalized()
	var base_ang := to_p.angle()
	var spread: float = GameBalance.BOSS_BLINK_SLASH_SPREAD
	var spd: float = GameBalance.BOSS_BLINK_SLASH_SPEED * bolt_speed_mult
	var dmg: float = maxf(1.0, contact_damage * GameBalance.BOSS_BLINK_SLASH_DMG_MULT)
	for i in range(bolts_count):
		var ang_offset := (float(i) - float(bolts_count - 1) * 0.5) * spread
		var bolt := EnemyBolt.acquire(get_parent())
		bolt.global_position = global_position
		bolt.direction = Vector2.from_angle(base_ang + ang_offset)
		bolt.speed = spd
		bolt.damage = dmg
		bolt.scale_factor = 1.25
		bolt.sword_style = true
		bolt.purple_style = _purple_bolts
		bolt.tint_color = _fx_color
		bolt.activate()
	AudioManager.play_sfx("enemy_bolt", 0.7, 1.1)

# ---------------- 招式 13：飞龙俯冲（太苍龙君签名招） ----------------

## 盘旋拉升 → 换位到玩家远侧 → 胶囊预警 → 全场贯穿俯冲 → 落点环爆收势。
## 复用冲锋机架（EnemyAiCharge 预警胶囊/扫掠判定同源），冲锋三件套临时换俯冲口径。
func _cast_dive(player: Node2D) -> void:
	if dying or get_parent() == null or player == null or not is_instance_valid(player):
		return
	# 拉升换位：撤到玩家远侧锚点（升天盘旋读招，落点钳在物理边界内）
	var away: Vector2 = (global_position - player.global_position).normalized()
	if away.length_squared() < 0.5:
		away = Vector2.RIGHT
	var anchor := _pick_dive_anchor(player, away)
	JuiceEffect.spawn_shockwave(get_parent(), global_position, 55.0, _fx_color, 0.24)
	global_position = anchor
	play_squash(Vector2(0.8, 1.3), 0.3)   # 拉升拔高读数
	# 冲锋参数换俯冲口径（收势在 _settle_charge_recovery 恢复）
	_charge_duration_stash = charge_duration
	_charge_speed_stash = charge_speed_mul
	_charge_dmg_stash = charge_damage_mul
	charge_duration = GameBalance.BOSS_DIVE_DURATION
	charge_speed_mul = GameBalance.BOSS_DIVE_SPEED_MUL
	charge_damage_mul = GameBalance.BOSS_DIVE_DMG_MULT
	_dive_pending = true
	_dive_trail_timer = 0.0
	_charge_aim_locked = false
	_charge_dir = (player.global_position - global_position).normalized()
	_charge_windup = GameBalance.BOSS_DIVE_WINDUP
	_charge_windup_total = _charge_windup
	_charge_timer = 999999.0
	charge_interval = 999999.0
	_update_charge_warning(player)
	AudioManager.play_sfx("enemy_fuse", 0.9, 0.85)

## 俯冲换位锚点：优先「玩家 + 远离方向 × 380」，被墙钳回时依次尝试对侧/切向，
## 保证至少 BOSS_DIVE_MIN_LEAP 的助跑距离，避免在墙角把「拉升换位」钳成原地俯冲。
func _pick_dive_anchor(player: Node2D, away: Vector2) -> Vector2:
	var lim := _arena_lim()
	var raw: Array[Vector2] = [
		player.global_position + away * GameBalance.BOSS_DIVE_LEAP_DIST,
		player.global_position - away * GameBalance.BOSS_DIVE_LEAP_DIST,
		player.global_position + away.rotated(PI * 0.5) * GameBalance.BOSS_DIVE_LEAP_DIST,
		player.global_position - away.rotated(PI * 0.5) * GameBalance.BOSS_DIVE_LEAP_DIST,
	]
	var fallback: Vector2 = global_position
	for i in range(raw.size()):
		var p: Vector2 = raw[i].clamp(Vector2(-lim, -lim), Vector2(lim, lim))
		if i == 0:
			fallback = p
		if p.distance_to(player.global_position) >= GameBalance.BOSS_DIVE_MIN_LEAP \
				and p.distance_to(global_position) >= 120.0:
			return p
	return fallback

## 恢复冲锋三件套：俯冲结束/伏诛/被定身打断三处共用，避免残留俯冲口径污染下一次普通冲锋。
func _restore_charge_params() -> void:
	charge_duration = _charge_duration_stash
	charge_speed_mul = _charge_speed_stash
	charge_damage_mul = _charge_dmg_stash

## 俯冲路径上的收尾：恢复原冲锋口径 + 落点环爆（在连锁冲派发前执行，别污染链冲）
func _settle_dive() -> void:
	_dive_pending = false
	_dive_active = false
	_restore_charge_params()
	if dying or get_parent() == null:
		return
	var ring_count: int = GameBalance.BOSS_DIVE_LAND_RING_P2 if (_phase2 or final_boss) else GameBalance.BOSS_DIVE_LAND_RING
	_fire_mini_ring(ring_count, 260.0, 1.2)
	JuiceEffect.spawn_shockwave(get_parent(), global_position, 90.0, _fx_color, 0.3)
	GroundDecal.spawn(get_parent(), global_position, GroundDecal.Kind.CRACK, 70.0)
	AudioManager.play_sfx("enemy_slam", 1.0)
	GameManager.add_trauma(0.14)

# ---------------- 招式 14：镜像夹击（照影魔君签名招） ----------------

## 镜影虚像凝聚在「玩家背对主身的一侧」，先亮镜影圈预警，再发环弹 + 主身扇形。
## 旧写法把镜影放在「玩家关于场心的对称点」，如果主身恰好在同侧就不再是夹击；
## 现在以 Boss→玩家方向取反，保证镜影永远在玩家身后、主身永远在身前，形成真正的双向交叉火力。
func _cast_mirror_flank(player: Node2D) -> void:
	if dying or get_parent() == null or player == null or not is_instance_valid(player):
		return
	var lim := _arena_lim()
	var from_boss := player.global_position - global_position
	var mirror_dir := from_boss.normalized() if from_boss.length_squared() > 1.0 else Vector2.RIGHT
	var phantom: Vector2 = (player.global_position + mirror_dir * GameBalance.BOSS_MIRROR_FLANK_DIST)\
		.clamp(Vector2(-lim, -lim), Vector2(lim, lim))
	_mirror_point = phantom
	_mirror_windup_total = GameBalance.BOSS_MIRROR_WINDUP
	_mirror_timer = _mirror_windup_total
	_mirror_pending = true
	if _mirror_telegraph == null:
		_mirror_telegraph = AoeTelegraph.new()
		_mirror_telegraph.radius = 72.0
		get_parent().add_child(_mirror_telegraph)
	_mirror_telegraph.color = _fx_color
	_mirror_telegraph.global_position = phantom
	_mirror_telegraph.progress = 0.0
	_mirror_telegraph.visible = true
	JuiceEffect.spawn_shockwave(get_parent(), phantom, 72.0, _fx_color, 0.3)
	AudioManager.play_sfx("enemy_fuse", 0.7, 1.2)
	play_squash(Vector2(1.05, 0.9), 0.3)

func _resolve_mirror_flank(player: Node2D) -> void:
	_mirror_pending = false
	if _mirror_telegraph != null and is_instance_valid(_mirror_telegraph):
		_mirror_telegraph.visible = false
	if dying or get_parent() == null or player == null or not is_instance_valid(player):
		return
	var dmg := maxf(1.0, contact_damage * GameBalance.BOSS_MIRROR_DMG_MULT)
	var ring_count: int = GameBalance.BOSS_MIRROR_RING_COUNT_P2 if _phase2 else GameBalance.BOSS_MIRROR_RING_COUNT
	for i in range(ring_count):
		var ang := TAU * float(i) / float(ring_count)
		_spawn_boss_bolt(_mirror_point, Vector2(cos(ang), sin(ang)),
			GameBalance.BOSS_MIRROR_RING_SPEED * bolt_speed_mult, dmg, 1.1)
	# 主身配合扇形夹击（弹速略快于镜影环，形成内外两层交叉）
	var to_p: Vector2 = player.global_position - global_position
	var base_dir: Vector2 = to_p.normalized() if to_p.length_squared() > 1.0 else Vector2.RIGHT
	for i in range(GameBalance.BOSS_MIRROR_FAN_COUNT):
		var off := (float(i) - float(GameBalance.BOSS_MIRROR_FAN_COUNT - 1) * 0.5) * GameBalance.BOSS_MIRROR_FAN_SPREAD
		_spawn_boss_bolt(global_position, base_dir.rotated(off),
			GameBalance.BOSS_FAN_BASE_SPEED * bolt_speed_mult, dmg, 1.2)
	JuiceEffect.spawn_shockwave(get_parent(), _mirror_point, 96.0, _fx_color, 0.3)
	AudioManager.play_sfx("enemy_bolt", 0.7, 1.1)
	play_squash(Vector2(1.15, 0.85), 0.3)
	_pose_burst()

# ---------------- 招式 15：魂潮收网（引魂使签名招） ----------------

## 以玩家为圆心在 340 半径上撒一圈魂弹，全部朝圆心内收 —— 包围网从四面八方收拢，
## 与现有所有「从 Boss 向外」的弹幕方向感相反，逼玩家找缺口突围而非绕 Boss。
## 2026-11-03 可读性优化：先在玩家脚下亮收网点（0.55s），再撒环；玩家有明确反应窗。
func _cast_soul_tide(player: Node2D) -> void:
	if dying or get_parent() == null or player == null or not is_instance_valid(player):
		return
	_soul_center = player.global_position
	_soul_windup_total = GameBalance.BOSS_SOUL_TIDE_WINDUP
	_soul_timer = _soul_windup_total
	_soul_pending = true
	if _soul_telegraph == null:
		_soul_telegraph = AoeTelegraph.new()
		_soul_telegraph.radius = 80.0
		get_parent().add_child(_soul_telegraph)
	_soul_telegraph.color = _fx_color
	_soul_telegraph.global_position = _soul_center
	_soul_telegraph.progress = 0.0
	_soul_telegraph.visible = true
	JuiceEffect.spawn_shockwave(get_parent(), _soul_center, 120.0, _fx_color, 0.35)
	AudioManager.play_sfx("enemy_fuse", 0.7, 0.9)

func _resolve_soul_tide(player: Node2D) -> void:
	_soul_pending = false
	if _soul_telegraph != null and is_instance_valid(_soul_telegraph):
		_soul_telegraph.visible = false
	if dying or get_parent() == null:
		return
	var center := _soul_center
	var count: int = GameBalance.BOSS_SOUL_TIDE_COUNT_P2 if _phase2 else GameBalance.BOSS_SOUL_TIDE_COUNT
	var dmg := maxf(1.0, contact_damage * GameBalance.BOSS_SOUL_TIDE_DMG_MULT)
	var radius := GameBalance.BOSS_SOUL_TIDE_RADIUS
	# 起手留一个随机缺口当「网眼」（走玩法 RNG：缺口位置影响躲避判定）
	var gap := GameManager.rng.randi_range(0, count - 1)
	for i in range(count):
		if i == gap or (not _phase2 and i == (gap + 1) % count):
			continue  # 网眼：P1 留双缺口、狂暴后只剩单缺口
		var ang := TAU * float(i) / float(count)
		var dir := Vector2(cos(ang), sin(ang))
		_spawn_boss_bolt(center + dir * radius, -dir,
			GameBalance.BOSS_SOUL_TIDE_SPEED * bolt_speed_mult, dmg, 1.2)
	# 收网视觉锚：玩家脚下主题色收缩环
	JuiceEffect.spawn_shockwave(get_parent(), center, radius * 0.35, _fx_color, 0.4)
	AudioManager.play_sfx("enemy_bolt", 0.65, 0.95)
	_pose_burst()

# ---------------- 招式 16：炉压崩天（焚天炉君签名招） ----------------

## 站桩蓄力（预警圈比震地更大更慢，按半径公平线裁定）→ 炉爆：大圆 AoE 结算
## + 三环弹幕 + 焦痕。蓄力期完全不动是输出窗口，也是压迫来源。
func _cast_furnace_blast(player: Node2D) -> void:
	if dying or get_parent() == null:
		return
	_furnace_pending = true
	_furnace_windup_total = GameBalance.aoe_windup(GameBalance.BOSS_FURNACE_RADIUS)
	_furnace_timer = _furnace_windup_total
	if _furnace_ring == null:
		_furnace_ring = AoeTelegraph.new()
		_furnace_ring.radius = GameBalance.BOSS_FURNACE_RADIUS
		add_child(_furnace_ring)
	_furnace_ring.color = _fx_color
	_furnace_ring.progress = 0.0
	_furnace_ring.visible = true
	AudioManager.play_sfx("enemy_fuse", 0.9, 0.7)
	play_squash(Vector2(0.85, 1.15), 0.4)

func _resolve_furnace(player: Node2D) -> void:
	_furnace_pending = false
	if _furnace_ring != null:
		_furnace_ring.visible = false
	if dying or get_parent() == null:
		return
	var radius := GameBalance.BOSS_FURNACE_RADIUS
	JuiceEffect.spawn_shockwave(get_parent(), global_position, radius, _fx_color, 0.4)
	GroundDecal.spawn(get_parent(), global_position, GroundDecal.Kind.SCORCH, radius * 0.65)
	AudioManager.play_sfx("enemy_slam", 1.0)
	GameManager.add_trauma(0.2)
	# 炉心 AoE 结算（判定与预警圈同源同径）
	if player != null and is_instance_valid(player) and player.global_position.distance_to(global_position) <= radius:
		player.take_damage(maxf(1.0, contact_damage * GameBalance.BOSS_FURNACE_DMG_MULT), global_position)
		GameManager.trigger_screen_shockwave(player.global_position)
	# 炉爆余焰：三环弹幕连发（独立系数，不再借用镜影的 BOSS_MIRROR_DMG_MULT）
	var dmg := maxf(1.0, contact_damage * GameBalance.BOSS_FURNACE_RING_DMG_MULT)
	var layers := 3 if _phase2 else 2
	for layer in range(layers):
		var tw := create_tween()
		tw.tween_interval(0.18 * float(layer))
		var spd := GameBalance.BOSS_FURNACE_RING_SPEED * (1.0 + float(layer) * 0.12) * bolt_speed_mult
		tw.tween_callback(_fire_furnace_ring.bind(spd, dmg, layer))
	play_squash(Vector2(1.25, 0.78), 0.35)

func _fire_furnace_ring(spd: float, dmg: float, layer: int) -> void:
	if dying or get_parent() == null:
		return
	var offset := TAU / float(GameBalance.BOSS_FURNACE_RING * 2) * float(layer % 2)
	for i in range(GameBalance.BOSS_FURNACE_RING):
		var ang := offset + TAU * float(i) / float(GameBalance.BOSS_FURNACE_RING)
		var bolt := EnemyBolt.acquire(get_parent())
		bolt.global_position = global_position
		bolt.direction = Vector2(cos(ang), sin(ang))
		bolt.speed = spd
		bolt.damage = dmg
		bolt.scale_factor = 1.25
		bolt.purple_style = _purple_bolts
		bolt.tint_color = _fx_color
		bolt.activate()
	AudioManager.play_sfx("enemy_bolt", 0.55)

# ---------------- 招式 17：深层魔君签名招（数据驱动） ----------------
## 八尊原本只靠旧招表组合的深层魔君，各给一个身份招；kind 与参数全在 EnemyData.BOSS_SIGNATURES，
## 这里只做行为派发。所有弹幕统一挂 _fx_color，不再出现「绿 Boss 打紫弹」。
func _cast_signature(player: Node2D) -> void:
	var def: Dictionary = EnemyData.BOSS_SIGNATURES.get(boss_id, {})
	if def.is_empty():
		_cast_ring()
		return
	match String(def.get("kind", "")):
		"sword_rain":
			_sig_sword_rain(player, def)
		"thunder_chain":
			_sig_thunder_chain(player, def)
		"tidal_wave":
			_sig_tidal_wave(player, def)
		"arm_volley":
			_sig_arm_volley(player, def)
		"phoenix_flame":
			_sig_phoenix_flame(player, def)
		"void_step":
			_sig_void_step(player, def)
		"chaos_orb":
			_sig_chaos_orb(player, def)
		"tribulation":
			_sig_tribulation(player, def)
		_:
			_cast_ring()
	_pose_burst()

## 签名招统一弹幕出口：主题色/剑形/弧线一次挂齐，子母弹与普通弹共用同一套池化口径。
func _spawn_boss_bolt(pos: Vector2, dir: Vector2, spd: float, dmg: float, scl: float,
		sword: bool = false, angular: float = 0.0) -> EnemyBolt:
	if dying or get_parent() == null:
		return null
	var bolt := EnemyBolt.acquire(get_parent())
	bolt.global_position = pos
	bolt.direction = dir
	bolt.speed = spd
	bolt.damage = dmg
	bolt.scale_factor = scl
	bolt.angular_speed = angular
	bolt.sword_style = sword
	bolt.purple_style = _purple_bolts
	bolt.tint_color = _fx_color
	bolt.activate()
	return bolt

## 签名招预警圈：世界坐标铺一个 AoeTelegraph，进度用 tween 推满后回调出招。
## 圈登记进 _sig_telegraphs，Boss 伏诛时统一清掉，防 tween 被杀后留下无主预警。
func _spawn_windup_telegraph(pos: Vector2, radius: float, duration: float, on_fire: Callable) -> AoeTelegraph:
	if get_parent() == null:
		return null
	var tg := AoeTelegraph.new()
	tg.radius = radius
	tg.color = _fx_color
	tg.progress = 0.0
	get_parent().add_child(tg)
	tg.global_position = pos
	_sig_telegraphs.append(tg)
	var tw := create_tween()
	tw.tween_method(func(v: float):
		if is_instance_valid(tg):
			tg.progress = v
	, 0.0, 1.0, duration)
	tw.tween_callback(func():
		if is_instance_valid(tg):
			_sig_telegraphs.erase(tg)
			tg.queue_free()
		if not dying and on_fire.is_valid():
			on_fire.call()
	)
	return tg

## 万剑归宗（葬剑仙）：玩家脚下亮圈 → 剑环从四周内收，逼玩家离开落点。
func _sig_sword_rain(player: Node2D, def: Dictionary) -> void:
	if player == null or not is_instance_valid(player):
		return
	var radius := float(def.get("radius", 190.0))
	var count := int(def.get("count", 12))
	var speed := float(def.get("speed", 300.0)) * bolt_speed_mult
	var dmg := maxf(1.0, contact_damage * float(def.get("dmg_mult", 0.55)))
	var center := player.global_position
	play_squash(Vector2(0.9, 1.2), 0.3)
	AudioManager.play_sfx("enemy_fuse", 0.8, 1.1)
	_spawn_windup_telegraph(center, radius, float(def.get("windup", 0.55)), func():
		if dying or get_parent() == null:
			return
		for i in range(count):
			var ang := TAU * float(i) / float(count)
			var dir := Vector2(cos(ang), sin(ang))
			_spawn_boss_bolt(center + dir * radius, -dir, speed, dmg, 1.25, true)
		JuiceEffect.spawn_shockwave(get_parent(), center, radius, _fx_color, 0.35)
		AudioManager.play_sfx("enemy_bolt", 0.7, 1.15)
		_pose_burst()
	)

## 连环天劫（雷劫神君）：连续三处落雷，每处预警圈填满后炸开一圈雷弹。
func _sig_thunder_chain(player: Node2D, def: Dictionary) -> void:
	var strikes := int(def.get("strikes", 3))
	var interval := float(def.get("interval", 0.34))
	var tw := create_tween()
	for i in range(strikes):
		tw.tween_interval(interval)
		tw.tween_callback(_sig_thunder_strike.bind(player, def))

func _sig_thunder_strike(player: Node2D, def: Dictionary) -> void:
	if dying or get_parent() == null or player == null or not is_instance_valid(player):
		return
	var radius := float(def.get("radius", 95.0))
	var pos := player.global_position
	if player is CharacterBody2D:
		pos += (player as CharacterBody2D).velocity * 0.12
	var bolts := int(def.get("bolts", 8))
	var speed := float(def.get("speed", 270.0)) * bolt_speed_mult
	var dmg := maxf(1.0, contact_damage * float(def.get("dmg_mult", 0.5)))
	_spawn_windup_telegraph(pos, radius, float(def.get("windup", 0.42)), func():
		if dying or get_parent() == null:
			return
		for i in range(bolts):
			var ang := TAU * float(i) / float(bolts)
			_spawn_boss_bolt(pos, Vector2(cos(ang), sin(ang)), speed, dmg, 1.2)
		JuiceEffect.spawn_shockwave(get_parent(), pos, radius, _fx_color, 0.28)
		AudioManager.play_sfx("enemy_slam", 0.9, 1.1)
		_pose_burst()
	)

## 冥海潮汐（覆海鲲王）：三道带缺口的外扩潮环，缺口逐波转动，逼玩家跟着缺口走位。
func _sig_tidal_wave(player: Node2D, def: Dictionary) -> void:
	if player == null or not is_instance_valid(player):
		return
	var waves := int(def.get("waves", 3))
	var gap := deg_to_rad(float(def.get("gap_deg", 58.0)))
	var step := deg_to_rad(float(def.get("gap_step_deg", 46.0)))
	var base_ang := (player.global_position - global_position).angle()
	var tw := create_tween()
	for w in range(waves):
		tw.tween_interval(float(def.get("interval", 0.34)))
		tw.tween_callback(_sig_tidal_ring.bind(def, base_ang + step * float(w), gap))
	play_squash(Vector2(0.85, 1.2), 0.3)

func _sig_tidal_ring(def: Dictionary, gap_center: float, gap_width: float) -> void:
	if dying or get_parent() == null:
		return
	var count := int(def.get("count", 20))
	var speed := float(def.get("speed", 220.0)) * bolt_speed_mult
	var dmg := maxf(1.0, contact_damage * float(def.get("dmg_mult", 0.45)))
	for i in range(count):
		var ang := TAU * float(i) / float(count)
		if absf(wrapf(ang - gap_center, -PI, PI)) < gap_width * 0.5:
			continue
		_spawn_boss_bolt(global_position, Vector2(cos(ang), sin(ang)), speed, dmg, 1.3)
	JuiceEffect.spawn_shockwave(get_parent(), global_position, 70.0, _fx_color, 0.25)
	AudioManager.play_sfx("enemy_bolt", 0.6, 0.9)
	_pose_burst()

## 千臂机括（千臂傀王）：四轮交替转向的机弩扇射，像多臂机关依次点火。
func _sig_arm_volley(player: Node2D, def: Dictionary) -> void:
	var waves := int(def.get("waves", 4))
	var tw := create_tween()
	for w in range(waves):
		tw.tween_interval(float(def.get("interval", 0.24)))
		tw.tween_callback(_sig_arm_volley_wave.bind(player, def, w))
	play_squash(Vector2(1.1, 0.9), 0.3)

func _sig_arm_volley_wave(player: Node2D, def: Dictionary, wave_idx: int) -> void:
	if dying or get_parent() == null or player == null or not is_instance_valid(player):
		return
	var fan := int(def.get("fan", 7))
	var spread := float(def.get("spread", 0.13))
	var speed := float(def.get("speed", 265.0)) * bolt_speed_mult
	var dmg := maxf(1.0, contact_damage * float(def.get("dmg_mult", 0.45)))
	var turn := deg_to_rad(float(def.get("turn_deg", 32.0))) * float(wave_idx) * (1.0 if wave_idx % 2 == 0 else -1.0)
	var base_dir := (player.global_position - global_position).normalized().rotated(turn)
	for i in range(fan):
		var off := (float(i) - float(fan - 1) * 0.5) * spread
		_spawn_boss_bolt(global_position, base_dir.rotated(off), speed, dmg, 1.2)
	AudioManager.play_sfx("enemy_bolt", 0.6, 1.0 + 0.06 * float(wave_idx))
	_pose_burst()

## 离火涅槃（离火凤皇）：双层离火环 + 天火陨落。
func _sig_phoenix_flame(player: Node2D, def: Dictionary) -> void:
	var rings := int(def.get("rings", 2))
	var count := int(def.get("ring_count", 18))
	for layer in range(rings):
		var tw := create_tween()
		tw.tween_interval(0.2 * float(layer))
		tw.tween_callback(_sig_fire_ring.bind(def, layer, count))
	_cast_sky_fire(player)
	play_squash(Vector2(1.15, 0.85), 0.3)

func _sig_fire_ring(def: Dictionary, layer: int, count: int) -> void:
	if dying or get_parent() == null:
		return
	var speed := float(def.get("speed", 250.0)) * bolt_speed_mult
	var dmg := maxf(1.0, contact_damage * float(def.get("dmg_mult", 0.45)))
	var offset := TAU / float(count * 2) * float(layer % 2)
	for i in range(count):
		var ang := offset + TAU * float(i) / float(count)
		_spawn_boss_bolt(global_position, Vector2(cos(ang), sin(ang)), speed, dmg, 1.3)
	JuiceEffect.spawn_shockwave(get_parent(), global_position, 80.0, _fx_color, 0.25)
	AudioManager.play_sfx("enemy_bolt", 0.55, 1.0)
	_pose_burst()

## 无相三连（无相天魔）：连续三次瞬步贴脸回斩，每次落点重算。
func _sig_void_step(player: Node2D, def: Dictionary) -> void:
	var steps := int(def.get("steps", 3))
	var tw := create_tween()
	for i in range(steps):
		tw.tween_interval(float(def.get("interval", 0.22)))
		tw.tween_callback(_sig_void_step_once.bind(player))
	play_squash(Vector2(0.8, 1.2), 0.25)

func _sig_void_step_once(player: Node2D) -> void:
	if dying or get_parent() == null or player == null or not is_instance_valid(player):
		return
	_cast_blink_slash(player)

## 混沌星散（元初兽）：一圈随机旋向/速度的四象弹，部分弹染成异色，读作「混沌不定」。
func _sig_chaos_orb(player: Node2D, def: Dictionary) -> void:
	if dying or get_parent() == null:
		return
	var count := int(def.get("count", 18))
	var speed_base := float(def.get("speed", 215.0)) * bolt_speed_mult
	var spin_max := float(def.get("spin", 1.2))
	var dmg := maxf(1.0, contact_damage * float(def.get("dmg_mult", 0.45)))
	for i in range(count):
		var ang := TAU * float(i) / float(count)
		var spd := speed_base * GameManager.rng.randf_range(0.85, 1.15)
		var spin := GameManager.rng.randf_range(-spin_max, spin_max)
		var bolt := _spawn_boss_bolt(global_position, Vector2(cos(ang), sin(ang)), spd, dmg, 1.25, false, spin)
		if bolt != null and i % 3 == 0:
			bolt.tint_color = _fx_color.lerp(GameStyle.FX_HDR_GOLD, 0.45)
	JuiceEffect.spawn_shockwave(get_parent(), global_position, 90.0, _fx_color, 0.3)
	AudioManager.play_sfx("enemy_bolt", 0.65, 0.95)

## 万劫加身（道劫化身）：双层劫环 + 天火 + 收束环，全招式里最重的一档。
func _sig_tribulation(player: Node2D, def: Dictionary) -> void:
	var rings := int(def.get("rings", 2))
	var count := int(def.get("ring_count", 20))
	for layer in range(rings):
		var tw := create_tween()
		tw.tween_interval(0.22 * float(layer))
		tw.tween_callback(_sig_fire_ring.bind(def, layer, count))
	_cast_sky_fire(player)
	_fire_mini_ring(12, 300.0, 1.25)
	GameManager.add_trauma(0.18)
	play_squash(Vector2(1.2, 0.8), 0.35)

# ---------------- 二阶段与死亡结算 ----------------

func _enter_phase2() -> void:
	_phase2 = true
	if boss_id == "xiuluo":
		_tint = Color(1.7, 0.3, 0.3)
	elif boss_id == "qianji":
		_tint = Color(0.6, 1.1, 1.4)
	elif boss_id == "wangu":
		_tint = Color(0.6, 1.5, 0.7)
	elif boss_id == "jianpo":
		_tint = Color(1.1, 1.3, 1.6)
	# 深层专属魔君须排在 xinmo/final_boss 之前（深层波次 final_boss 恒真，否则被抢染紫色）
	elif boss_id == "zhaoying":
		_tint = Color(1.05, 1.3, 1.7)
	elif boss_id == "yinhun":
		_tint = Color(0.6, 1.45, 1.1)
	elif boss_id == "luding":
		_tint = Color(1.9, 0.9, 0.5)
	elif boss_id == "canglong":
		_tint = Color(0.5, 1.6, 1.5)
	elif boss_id == "jianzhong":
		_tint = Color(1.2, 1.3, 1.6)
	elif boss_id == "leijie":
		_tint = Color(1.4, 1.1, 1.9)
	elif boss_id == "kunwang":
		_tint = Color(0.45, 0.9, 1.6)
	elif boss_id == "kuijia":
		_tint = Color(1.6, 1.25, 0.6)
	elif boss_id == "fenghuang":
		_tint = Color(2.0, 0.9, 0.4)
	elif boss_id == "tianmo":
		_tint = Color(1.1, 0.7, 1.6)
	elif boss_id == "hundun":
		_tint = Color(1.4, 1.4, 1.4)
	elif boss_id == "wanjie":
		_tint = Color(1.7, 1.2, 2.0)
	elif boss_id == "xinmo" or final_boss:
		_tint = Color(1.5, 0.5, 1.8)
	else:
		_tint = Color(1.4, 0.6, 0.6)
	if anim_sprite != null:
		anim_sprite.modulate = _tint

	if boss_id == "qianji":
		move_speed = 0.0
		attack_interval *= 0.8
	else:
		move_speed *= GameBalance.BOSS_PHASE2_SPEED_MULT

	_setup_patterns()
	play_squash(Vector2(1.3, 0.75), 0.35)
	# 离火凤皇·涅槃：狂暴瞬间全屏离火环爆（一次性，不进轮换表；重生仪式感）
	if boss_id == "fenghuang" and get_parent() != null:
		_fire_ring_layer(3)
		_fire_mini_ring(16, 300.0, 1.3)
		JuiceEffect.spawn_shockwave(get_parent(), global_position, 130.0, _fx_color, 0.4)
	# 道劫化身·万劫加身：狂暴后出招节奏再压一档（全场最高压）
	if boss_id == "wanjie":
		attack_interval *= 0.85
	GameManager.announcement_triggered.emit("◆ %s · 狂暴形态 ◆" % boss_title)
	AudioManager.play_sfx("boss_raid", 1.15)
	# 狂暴是全游戏最高光的瞬间之一，给最强档（HEAVY 自带更大创伤/顿帧/缩放，内部单发，
	# 不再叠第二处反馈 —— 「同一次事件只许一处发反馈」口径）。
	GameManager.feedback(GameManager.FeedbackTier.HEAVY)

func take_damage(amount: float, knockback: Vector2, is_crit: bool = false, from_dot: bool = false, chain_tint: Color = Color(0, 0, 0, 0)) -> void:
	if dying:
		return
	# Boss 抗击退：几乎推不动，走位压力全靠技能（千机尊完全不动）
	var kb: Vector2 = Vector2.ZERO if boss_id == "qianji" else (knockback * GameBalance.BOSS_KNOCKBACK_RESIST)
	super.take_damage(amount, kb, is_crit, from_dot, chain_tint)
	if dying:
		return
	# 大比例掉血的镜头回应（2026-10-14）：Boss 挨一刀超过最大生命该比例时给一笔轻创伤，
	# 让「砍疼 Boss」这件事有回响（此前 Boss 被打几乎 silent，只有自己的招式发反馈）。
	# 冷却按 Boss 独立计时；trauma 仍受全局每秒预算闸保护，群攻刷伤不会变持续抖屏。
	# 暴击走 EnemyBase 的暴击创伤，同一事件不双发（本闸排除暴击）。
	if not from_dot and not is_crit and _heavy_hit_cd <= 0.0 and amount >= max_hp * GameBalance.BOSS_HEAVY_HIT_PCT:
		_heavy_hit_cd = GameBalance.BOSS_HEAVY_HIT_COOLDOWN
		GameManager.add_trauma(GameBalance.BOSS_HEAVY_HIT_TRAUMA)
	# 二阶段变身判定独立于重击创伤闸（2026-11-03 修复：此前误嵌在重击闸内，
	# 单发伤害 <6% 最大生命的快速小伤害流派打到死都触发不了狂暴）
	if not _phase2 and current_hp <= max_hp * GameBalance.boss_phase2_hp_pct(GameManager.danger_level):
		_enter_phase2()
	_hp_emit_acc += amount
	if _hp_emit_acc >= max_hp * 0.005 or _hp_emit_cd <= 0.0:
		_hp_emit_acc = 0.0
		_hp_emit_cd = 0.1
		GameManager.boss_hp_changed.emit(current_hp, max_hp, boss_title)

func _die() -> void:
	if dying:
		return
	_slam_pending = false
	_spiral_active = false
	_fan_waves_left = 0
	_sky_fire_strikes_left = 0
	_hazard_fields_left = 0
	_chain_charges_left = 0
	if _dive_active or _dive_pending:
		# 俯冲中途伏诛：只恢复冲锋口径，不发落点环爆
		_dive_pending = false
		_dive_active = false
		_restore_charge_params()
	_furnace_pending = false
	if _furnace_ring != null:
		_furnace_ring.visible = false
	_mirror_pending = false
	_soul_pending = false
	if _mirror_telegraph != null and is_instance_valid(_mirror_telegraph):
		_mirror_telegraph.queue_free()
		_mirror_telegraph = null
	if _soul_telegraph != null and is_instance_valid(_soul_telegraph):
		_soul_telegraph.queue_free()
		_soul_telegraph = null
	for tg in _sig_telegraphs:
		if tg != null and is_instance_valid(tg):
			tg.queue_free()
	_sig_telegraphs.clear()
	_since_moved = 0.0
	_prev_pos_valid = false
	_clear_charge_warning()
	if _slam_ring != null:
		_slam_ring.visible = false
	for fire in _active_sky_fires:
		var tg: AoeTelegraph = fire.get("telegraph")
		if tg != null and is_instance_valid(tg):
			tg.queue_free()
	_active_sky_fires.clear()
	for field in _active_hazard_fields:
		var tg: AoeTelegraph = field.get("telegraph")
		if tg != null and is_instance_valid(tg):
			tg.queue_free()
	_active_hazard_fields.clear()

	GameManager.add_spirit_stones(GameBalance.BOSS_STONE_REWARD)
	GameManager.feedback(GameManager.FeedbackTier.HEAVY)
	# Boss 伏诛也进击杀连击音阶（低音巨物基准压半档），阶梯高位时斩杀音顺势冲顶
	AudioManager.register_kill_pitch(0.8)
	AudioManager.play_sfx("enemy_death_elite", 0.75)
	GameManager.announcement_triggered.emit("◆ %s · 已击杀 ◆" % boss_title)
	# Boss 伏诛：一局一次的屏幕级暖白脉冲，不走限流闸
	GameManager.pulse_damage_vignette(Color(1.0, 0.95, 0.78, 0.6), 0.45)
	AudioManager.set_bgm_muffle(false)
	GameManager.boss_defeated.emit(boss_title)
	super._die()

## Boss 登场凝聚成形演出（T-5.4）：
## 1. 材质切换为 dissolve.gdshader，dissolve_amount 从 1.0 (全隐) 缓动到 0.0 (凝实)；
## 2. 凝聚成形完毕时恢复 hit_flash_mat，爆发金色冲击环 + 短震屏与创伤反馈。
func play_spawn_sequence(on_complete: Callable = Callable()) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = _get_dissolve_shader()
	mat.set_shader_parameter("noise_texture", _get_noise_texture())
	mat.set_shader_parameter("dissolve_amount", 1.0)
	mat.set_shader_parameter("edge_width", 0.08)
	mat.set_shader_parameter("edge_color", GameStyle.FX_HDR_GOLD)
	if procedural_view != null:
		procedural_view.material = mat
	anim_sprite.material = mat

	scale = Vector2.ONE * 0.4
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float):
		mat.set_shader_parameter("dissolve_amount", v)
	, 1.0, 0.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	tw.chain().tween_callback(func():
		if procedural_view != null and hit_flash_mat != null:
			procedural_view.material = hit_flash_mat
		anim_sprite.material = hit_flash_mat
		var parent := get_parent()
		if parent != null:
			JuiceEffect.spawn_shockwave(parent, global_position, 96.0, GameStyle.FX_HDR_GOLD, 0.35)
		GameManager.shake_camera(8.0, 0.38)
		GameManager.add_trauma(0.35)
		if on_complete.is_valid():
			on_complete.call()
	)
