class_name EnemyBase
extends CharacterBody2D

## 敌人通用基类（行为开关式上帝基类）：8 种行为支路靠 @export 开关组装，已按支路补分节注释。
## 组件化重构暂缓（2026-10-11 决策）：涉及每帧 AI/物理逻辑，留待大型敌人扩展需求出现时单独立项。
# ---------------- 敌种行为开关（.tscn 按敌种配置；>0 启用对应行为支路） ----------------
@export var max_hp: float = 18.0
@export var move_speed: float = 110.0
@export var contact_damage: float = 12.0
@export var is_elite: bool = false
@export var exp_reward: int = 1
@export var enemy_id: String = ""          ## 敌种标识（为空时自动由节点名推导）
@export var spritesheet_path: String = ""
# 移动方式：gait=步态腿帧（默认）/ hover=悬浮（单姿势图集 + apply_hover 浮沉前倾）/ slither=蠕动（apply_slither 行进波）
@export var locomotion_mode: String = "gait"
# 可选行为（0 = 关闭，场景按怪种配置）
@export var preferred_range: float = 0.0   ## >0：远程怪，保持该距离环绕游走
@export var bolt_interval: float = 0.0     ## >0：每隔 N 秒向玩家发射火球
@export var bolt_damage: float = 9.0
@export var charge_interval: float = 0.0   ## >0：每隔 N 秒（含预警+冲刺的整周期）朝玩家长扑一次
@export var charge_min_range: float = 120.0  ## 长扑需要的「跑道」下沿：比这更近不起手（旧写法写死 120² 在判定里）
@export var charge_max_range: float = 450.0  ## 长扑上沿：远了不追扑（旧写法写死 450²）
@export var charge_windup_time: float = 1.2  ## 站桩预警时长
@export var charge_duration: float = 0.8     ## 冲刺时长（实冲位移见 GameBalance.charge_reach，不含纸面）
@export var charge_speed_mul: float = 3.2    ## 冲刺倍速（起步即满速，不再靠加速度爬）
@export var charge_brake_time: float = 0.25  ## 收势刹车时长：峰速线性刹到站定，这段位移也计入预警线
@export var charge_hit_radius: float = 34.0  ## 冲刺走廊半宽：建议取「敌我碰撞半径之和」⇒ 预警带画多宽就判多宽
@export var charge_damage_mul: float = 1.0   ## 冲刺伤害 = contact_damage × 它（与接触/短咬同一条尺子，别另起一档）
@export var charge_whiff_stagger: float = 0.9 ## 落空收势硬直：冲空罚站给玩家反打窗口（命中则不罚）
@export var bite_range: float = 0.0          ## >0：贴近短扑咬的触发上沿。建议与 charge_min_range 取同值 ⇒ 两带互补、中间不留空隙
@export var bite_interval: float = 2.4       ## 短扑咬冷却（同样是整周期）
@export var bite_windup_time: float = 0.35   ## 下蹲预告时长（方向在这一帧锁死，之后不追踪玩家，否则 0.35s 躲不开）
@export var bite_duration: float = 0.22      ## 起跳时长（位移 ≈ 69px，只当"咬一口"的凑身，不当跑道冲刺）
@export var bite_speed_mul: float = 2.6      ## 起跳倍速
@export var bite_hit_radius: float = 40.0    ## 咬合判定半径（狼嘴够得到的距离）
@export var bite_damage_mul: float = 1.0     ## 咬合伤害 = contact_damage × 它（与接触伤害同一条尺子，别另起一档）
@export var explode_radius: float = 0.0    ## >0：贴近玩家 40px 后点燃 0.8s 引信自爆
@export var heal_orb_drop: int = 0         ## >0：死亡掉「残丹」回血珠而非灵石
@export var bolt_count: int = 1            ## 火球扇射数量（>1 时按 bolt_spread 扇形展开）
@export var bolt_spread: float = 0.18      ## 扇射间隔角（弧度）
@export var split_count: int = 0           ## >0：血蛹系——死亡时分裂出 N 只幼体（split_scene）
@export var split_scene: PackedScene = null
@export var buff_radius: float = 0.0       ## >0：鼓妖光环——范围内同伴获得移速加成
@export var buff_speed_mult: float = 1.35  ## 光环加速倍率
@export var spawn_minion_interval: float = 0.0  ## >0：蛛母系——每隔 N 秒产一只幼体（minion_scene）
@export var minion_scene: PackedScene = null
@export var teleport_interval: float = 0.0 ## >0：影魅系——每隔 N 秒闪现到玩家侧翼
@export var charge_side_bolts: int = 0     ## >0：冲刺起步时向左右两侧各放 N 发火球（烈雷兽变异，犀牛同款）
@export var slam_interval: float = 0.0     ## >0：每隔 N 秒以自身为中心震地（铁甲巨怪变异后启用）
@export var slam_radius: float = 0.0       ## 震地半径：预警圈 = 判定圈（同源）
@export var slam_windup: float = 0.8       ## 震地预警时长
@export var slam_dmg_mult: float = 1.2     ## 震地伤害 = contact_damage × 它
@export var heal_interval: float = 0.0     ## >0：灵医系——每隔 N 秒治疗范围内同伴
@export var heal_radius: float = 0.0       ## 治疗光环半径
@export var heal_amount: float = 0.0       ## 每跳治疗量（WaveSpawner 按波次注入，见 BalanceWave.healer_amount）
@export var always_flee: bool = false      ## true：金蟾系——恒背离玩家逃窜（土豆兄弟 Looter 对应位）
@export var stone_reward: int = 0          ## >0：击杀额外掉金币（WaveSpawner 按波次注入，见 BalanceWave.looter_stone_reward）

# ---------------- 运行时状态 ----------------
var current_hp: float = 60.0
var knockback_velocity: Vector2 = Vector2.ZERO
var hit_stun_timer: float = 0.0   ## 受击定身硬直计时（期间暂停主动追击速度，仅随击退滑行）
var hit_stun_resist: float = 1.0  ## 受击硬直倍率（小怪 1.0，精英 0.55，Boss 0.25）
var _hit_freeze_timer: float = 0.0 ## 局部受击卡肉定格（秒）：冻结位移吸附在刀尖，随后释放击退冲量
var _hit_jiggle_offset: Vector2 = Vector2.ZERO  ## 受击瞬间视觉微反冲偏移
var _skid_dust_timer: float = 0.0 ## 滑行擦地扬尘计时
var _death_crit_kill: bool = false      ## 致命一刀是否为暴击（暴击击杀：独立顿帧 + 缩放冲击 + 精英 HEAVY 反馈）
var facing: String = "s"
var anim_base_scale: Vector2 = Vector2.ONE
var juice_scale: Vector2 = Vector2.ONE
var _bolt_timer: float = 1.2
var _charge_timer: float = 0.0
var _charge_active: float = 0.0
var _charge_dir: Vector2 = Vector2.ZERO
var _charge_windup: float = -1.0   ## >=0 表示进入冲刺预警阶段
var _charge_warning_line: Line2D = null  ## 冲刺预警线节点
var _charge_brake: float = 0.0     ## >0 收势刹车锁定段（这一段的位移同样是承诺出去的一部分）
var _charge_stagger: float = 0.0   ## >0 落空罚站：不追人、任人打（冲刺的代价，与预警的兑现配成一对）
var _charge_hit: bool = false      ## 这一冲已经结算过（一次冲刺只碾一下，同 _bite_hit 一口只结算一次）
var _bite_timer: float = 0.0       ## 短扑咬冷却
var _bite_windup: float = -1.0     ## >=0 表示下蹲预告中
var _bite_active: float = 0.0      ## >0 表示起跳中
var _bite_dir: Vector2 = Vector2.ZERO
var _bite_warning_line: Line2D = null
var _bite_hit: bool = false        ## 这一跳已经咬到（一次起跳只结算一口）
var _fuse: float = -1.0   ## >=0 表示引信已点燃
const EXPLODE_FUSE := 0.8  ## 丹爆引信时长（秒）：预警圈填满 = 引信烧完 = 自爆结算
var _explode_ring: AoeTelegraph = null  ## 丹爆引信预警圈（挂身上跟随，半径 = explode_radius 同源）
var _no_drop: bool = false
var _minion_timer: float = 0.0     ## 产卵计时
var _teleport_timer: float = 0.0   ## 闪现计时
var _buff_timer: float = 0.0       ## 光环脉冲计时（每 0.25s 刷新一次范围内同伴）
var _aura_speed_mult: float = 1.0  ## 被鼓妖光环覆盖时的移速加成
var _aura_until_ms: int = 0        ## 光环有效期（毫秒时间戳）
var _focus_hit_timer: float = 0.0  ## 同目标短窗集火保护计时
var _focus_hit_count: int = 0      ## 短窗内已承受直击次数

# 精英变异（2026-10-12，仿土豆兄弟 Elite Mutation：过血线一次性切换行为参数）
var _eid: String = ""              ## 解析后的敌种标识（_ready 落定，变异分发的依据）
var _mutated: bool = false         ## 变异只触发一次
var _elite_slam_timer: float = 0.0       ## 震地周期计时
var _elite_slam_windup_t: float = -1.0   ## >=0 表示震地预警中
var _elite_slam_ring: AoeTelegraph = null
var _heal_timer: float = 0.0       ## 灵医治疗跳计时

# 五行元素异常状态（灼烧/冰缓/剧毒）
var burn_timer: float = 0.0
var burn_dps: float = 0.0
var _burn_tick: float = 0.0
var poison_timer: float = 0.0
var poison_dps: float = 0.0
var _poison_tick: float = 0.0
var chill_timer: float = 0.0
var chill_slow: float = 0.0

@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var shadow_sprite: Sprite2D = get_node_or_null("Shadow") as Sprite2D
@onready var hit_flash_mat: ShaderMaterial = anim_sprite.material as ShaderMaterial

var gem_scene: PackedScene = preload("res://scenes/entities/AstralGem.tscn")
# —— 受击视觉零 Tween 分配化（2026-10-11 第 6 波卡顿优化）——
## 旧写法每次受击 create_tween ×2（挤压回弹 + 闪白），DoT 每 0.5s×N 敌也在持续触发；
## 35 怪高频命中的波次里 Tween 生命周期管理是实打实的分配热点。改帧内计时衰减，
## 曲线与原 Tween 一致（挤压 TRANS_BACK EASE_OUT；闪白 0.02s 拉满段在 60fps 下只有
## 1~2 帧，命中瞬间直接置峰，视觉无差）。衰减统一在 _tick_hit_fx 逐帧做。
var _squash_from: Vector2 = Vector2.ONE  ## 挤压起点（目标形变）
var _squash_t: float = 0.0               ## 挤压剩余时长
var _squash_dur: float = 0.16            ## 挤压总时长（插值分母）
var _flash_t: float = 0.0                ## 闪白剩余时长（衰减段）
var _flash_down_dur: float = 0.11        ## 本次闪白衰减总时长（归一化分母）
var _flash_swap_t: float = 0.0           ## 暴击绯金→暖白换色倒计时（普通命中为 0）
var _hit_tilt: float = 0.0          ## 受创后仰倾角（受击瞬间沿受力反向倾斜，急刹后平滑回正）

## 屏外减负（2026-10-10 第 6 波卡顿优化）：出屏边距与节流判定缓存
const CULL_MARGIN := 64.0
const CULL_INTERVAL := 0.1          ## 屏外判定 10Hz（敌人进出屏幕是秒级事件，60Hz 判定是白烧）
var _offscreen: bool = false
var _cull_timer: float = 0.0        ## 错相初值在 _ready 按 instance_id 摊开
var dying: bool = false
var procedural_view: ProceduralEnemyView = null

# ---------------- 生命周期与程序化外观初始化 ----------------
func _ready() -> void:
	# 小怪整体加血（GameBalance.MOB_HP_BASE_MULT）：精英/Boss 不吃这条，它们的厚度由基础值拉开。
	# 放在 _ready 这一唯一收口：WaveSpawner 刷怪、蛛母产卵、血蛹分裂、Boss 召唤全都经过这里，
	# 不用在四个刷怪口各乘一遍。2026-10-10 用户口径：「敌人都是一击秒杀，感觉不到打击感」。
	if not is_elite:
		max_hp = ceilf(max_hp * GameBalance.MOB_HP_BASE_MULT)
	current_hp = max_hp
	anim_base_scale = anim_sprite.scale
	var eid := enemy_id
	if eid.is_empty():
		eid = _deduce_enemy_id()
	_eid = eid
	# 程序化矢量视图先装配 —— 它决定图集还要不要加载（见下）
	var has_procedural: bool = _init_procedural_view(eid)

	# 图集腿帧只在「没有程序化配置」时才加载。EnemyVisualConfig.get_config 对全部敌种
	# 都有配置（含 _ 兜底分支），所以当前一只怪都不会走这里：20 张 960×960 图集解码后
	# 单张 3.5MB、合计约 70MB 常驻，是全项目最大的一块内存/显存开销，而屏上角色实际
	# 只有约 121px（192px 格 × 0.63 缩放）。spritesheet_path 与 _setup_frames 保留为兜底。
	# 注意：anim_sprite 节点不能删 —— 它不再是渲染器，而是 RunMotion 的形变状态载体
	# （步态/悬浮/蠕动的 scale·rotation·offset 写在它身上，再由 _update_facing_and_anim
	# 转发给 procedural_view），LingYi/JinChan 无图集却动画正常即是这条路径的现成反证。
	if not has_procedural:
		if spritesheet_path != "" and ResourceLoader.exists(spritesheet_path):
			_setup_frames(spritesheet_path)
		elif anim_sprite.sprite_frames != null and anim_sprite.sprite_frames.has_animation("idle"):
			anim_sprite.play("idle")

	# 妖物出生时的弹性跃出感
	juice_scale = Vector2(0.3, 0.3)
	play_squash(Vector2(1.18, 0.85), 0.22)

	# 出生缓冲：封顶 1.0 秒（仍然不是「出屏第一帧就扑」，玩家有 1 秒看清这只怪逼近）。
	# 旧写法直接取 charge_interval（4.0s），而狼移速 120px/s 从 380~480px 走到冲刺下沿
	# （120px）只要 2.2~3.0s ⇒ 冷却就绪时狼已贴脸进短咬带，冲刺条件 dist>120px 永远不满足。
	# 封顶 1.0s 而非 2.0s：v0.0.7 全局砍血后狼只有 45HP，2.0s+1.2s 预警=3.2s 站桩太长，
	# 中等火力下狼在预警期间就被打死了，活不到冲刺出手那一下。
	_charge_timer = minf(charge_interval, 1.0)
	_bite_timer = bite_interval
	_minion_timer = spawn_minion_interval
	_teleport_timer = teleport_interval
	_elite_slam_timer = slam_interval
	_heal_timer = heal_interval

	# 活体登记（2026-10-11）：鼓妖光环/产卵上限/召唤上限改走 GameManager.live_enemies，
	# 不再每脉冲 get_nodes_in_group("enemies") 造全组数组；_exit_tree 注销，语义与组一致
	GameManager.register_enemy(self)
	# 屏外判定错相：35 只怪的 10Hz 查询摊到不同帧，不扎堆
	_cull_timer = float(get_instance_id() % 6) * (CULL_INTERVAL / 6.0)

func _exit_tree() -> void:
	GameManager.unregister_enemy(self)

func _deduce_enemy_id() -> String:
	var n := name.to_lower()
	if n.begins_with("boss"):
		return "boss"
	elif n.begins_with("chilei"):
		return "chilei_elite"
	elif n.begins_with("jiansha"):
		return "jiansha_elite"
	elif n.begins_with("golem"):
		return "golem"
	elif n.begins_with("slime"):
		return "slime"
	elif n.begins_with("flower"):
		return "flower"
	elif n.begins_with("leibeast"):
		return "leibeast"
	elif n.begins_with("xiexiu"):
		return "xiexiu"
	elif n.begins_with("danbao"):
		return "danbao"
	elif n.begins_with("fengqun"):
		return "fengqun"
	elif n.begins_with("xueyong"):
		return "xueyong"
	elif n.begins_with("guyao"):
		return "guyao"
	elif n.begins_with("yingmei"):
		return "yingmei"
	elif n.begins_with("zhumu"):
		return "zhumu"
	elif n.begins_with("lingyi"):
		return "lingyi"
	elif n.begins_with("jinchan"):
		return "jinchan"
	return "slime"

## 装配程序化矢量视图。返回 true = 已挂上渲染器（调用方据此跳过图集加载）。
## EnemyVisualConfig.get_config 对全部敌种都有配置（含 _ 兜底），当前恒返回 true。
func _init_procedural_view(eid: String) -> bool:
	if procedural_view != null:
		procedural_view.queue_free()
	procedural_view = ProceduralEnemyView.new()
	var is_boss_enemy: bool = (eid == "boss" or self.get("final_boss") != null)
	var is_final: bool = bool(self.get("final_boss")) if self.get("final_boss") != null else false
	procedural_view.setup(eid, is_elite, is_boss_enemy, is_final)
	var ok: bool = procedural_view.config != null
	if anim_sprite != null and ok:
		# 只在确实有矢量外观时才藏旧精灵 —— 否则「图集没加载 + 精灵被藏」= 场上出现隐形怪
		anim_sprite.visible = false
		procedural_view.position = anim_sprite.position
		procedural_view.scale = anim_sprite.scale
		if hit_flash_mat != null:
			procedural_view.material = hit_flash_mat
	add_child(procedural_view)
	return ok

## 同种敌人的帧集合逐字节相同，按「贴图路径|是否精英」缓存：
## 原先每只敌人在 _ready 里新建一套 SpriteFrames + 8 方向 ×6 帧 AtlasTexture，
## 是长局里最大的一块分配压力（比 instantiate/free 节点本身贵得多）。
## 共享后 SpriteFrames 只读，节点级状态（scale/modulate/position/frame）互不影响。
static var _frames_cache: Dictionary = {}

## 释放共享帧缓存（退出时调用）。缓存是刻意常驻的，但不主动放开引用会被
## Godot 报成 "resources still in use at exit"，让退出日志一片假警报。
static func clear_frame_cache() -> void:
	_frames_cache.clear()

## 当前缓存的帧集合数量（调试/自动化验证用）
static func cache_size() -> int:
	return _frames_cache.size()

static func _cell_tex(tex: Texture2D, col: int, row: int) -> AtlasTexture:
	var at = AtlasTexture.new()
	at.atlas = tex
	at.region = Rect2(col * 192, row * 192, 192, 192)
	return at

## 取（或首次构建）某种怪共享的 SpriteFrames
static func _shared_frames(path: String, elite: bool) -> SpriteFrames:
	var key := "%s|%s" % [path, elite]
	if _frames_cache.has(key):
		return _frames_cache[key]
	var tex = load(path) as Texture2D
	if tex == null:
		return null
	var sf := SpriteFrames.new()
	for dir in RunMotion.DIR_ROW:
		var row: int = RunMotion.DIR_ROW[dir]
		sf.add_animation("idle_" + dir)
		sf.set_animation_speed("idle_" + dir, 1.0)
		sf.set_animation_loop("idle_" + dir, true)
		sf.add_frame("idle_" + dir, _cell_tex(tex, 0, row))

		sf.add_animation("run_" + dir)
		sf.set_animation_speed("run_" + dir, 10.0 if not elite else 8.5)
		sf.set_animation_loop("run_" + dir, true)
		for c in range(1, 5):
			sf.add_frame("run_" + dir, _cell_tex(tex, c, row))
	_frames_cache[key] = sf
	return sf

func _setup_frames(path: String) -> void:
	var sf := _shared_frames(path, is_elite)
	if sf == null:
		return
	anim_sprite.sprite_frames = sf
	anim_sprite.play("run_s")

## 挤压与拉伸形变回弹（Squash & Stretch）——零 Tween 分配版：记录起点与时长，
## 回弹插值在 _tick_hit_fx 逐帧做（TRANS_BACK EASE_OUT 同款过冲曲线）
func play_squash(target: Vector2, duration: float = 0.16) -> void:
	juice_scale = target
	_squash_from = target
	_squash_t = maxf(duration, 0.001)
	_squash_dur = _squash_t

# ---------------- 每帧调度：移动 / 行为计时器 / 状态机推进 ----------------
## 2026-10-11 机械拆分：原 367 行上帝函数按支路切成「异常结算 / 有效移速 / 硬直计时 /
## 行为推进 / 速度解算 / 受击视觉 / 动画同步 / 接触结算」八个私有函数，零逻辑改动。
## 帧内中间量走 _pp_* 成员（帧首重写，不跨帧持有语义），跨函数不再拖一长串参数。

# —— _physics_process 帧内中间量 ——
var _pp_stun: bool = false                   ## 本帧受击硬直是否仍在
var _pp_target_vel: Vector2 = Vector2.ZERO   ## 本帧期望速度（各行为支路共同写这一个出口）

func _physics_process(delta: float) -> void:
	if GameManager.is_game_over or dying:
		return

	var player = GameManager.player
	if player == null:
		return

	# 灵兽嘲讽（2026-10-11 祭坛灵兽）：周身嘲讽圈内有友方灵兽时改追灵兽，替玩家分担火力。
	# 追击方向、扑咬/冲刺/自爆/火球的瞄准与接触结算都改吃这个目标；Boss 出招大脑仍锁玩家。
	var target: Node2D = _taunt_target(player)

	# 屏外缓存（2026-10-10 第 6 波卡顿优化，2026-10-11 加 10Hz 节流）：take_damage 里
	# 屏外只扣血跳过跳字与火花（音效/硬直/击退/闪白保留）。
	# 敌人进出屏幕是秒级事件，10Hz 判定足够；每敌错相劈开 transform 查询
	_cull_timer -= delta
	if _cull_timer <= 0.0:
		_cull_timer = CULL_INTERVAL
		_update_offscreen_cull()

	# 受击视觉衰减（零分配）：挤压回弹与闪白逐帧推进。
	# 必须放在行为支路之前 —— 冲刺/短咬等支路会提前 return，衰减不能跟着断
	_tick_hit_fx(delta)

	if _focus_hit_timer > 0.0:
		_focus_hit_timer -= delta
		if _focus_hit_timer <= 0.0:
			_focus_hit_count = 0

	# 0. 五行元素异常状态结算（灼烧/剧毒跳伤；致死即结束本帧）
	if _tick_damage_over_time(delta):
		return

	# 有效移速：冰缓减速 × 鼓妖光环加速
	var eff_speed := _effective_speed(delta)

	# 1. 击退速度急刹与受击硬直定身（空洞骑士/死亡细胞风格：0帧瞬发冲量 → ~0.11s急刹刹停 → 原地僵直定身）
	_pp_stun = _tick_hit_stun(delta)

	# 2. 追击目标（平滑加速度 + 贴身防旋转抽搐）：期望速度与各行为支路推进
	var to_player: Vector2 = target.global_position - global_position
	var dist_sq: float = to_player.length_squared()
	var dir: Vector2 = to_player.normalized() if dist_sq > 0.0001 else Vector2.ZERO
	# 引入轻微加减速平滑，消除突然转向时的身躯瞬间硬切；
	# 受击硬直（hit-stun）期间主动追击速度归零，位移纯由击退速度主导，呈现土豆兄弟式的受击定身与推开感
	_pp_target_vel = Vector2.ZERO if _pp_stun else (dir * eff_speed)
	if _tick_behaviors(delta, target, dir, dist_sq, eff_speed):
		return

	# 位移解算（冲刺锁定段不插值）+ 界碑拦阻
	_resolve_velocity(delta)
	var pos_before_move: Vector2 = global_position
	move_and_slide()
	var lim: float = GameManager.MAP_HALF_EXTENT - 20.0
	global_position = global_position.clamp(Vector2(-lim, -lim), Vector2(lim, lim))

	_tick_hit_visuals(delta)
	_update_facing_and_anim(delta, dir, dist_sq)
	_resolve_contact_damage(target, pos_before_move)

## 嘲讽目标选择（2026-10-11 祭坛灵兽）：嘲讽圈内有灵兽则追最近的灵兽，否则维持追玩家。
## 灵兽最多 3 只（三座祭坛各召唤一只），全表扫描开销可忽略。
func _taunt_target(player: Node2D) -> Node2D:
	var best: Node2D = player
	var best_sq: float = GameBalance.SPIRIT_BEAST_TAUNT_RADIUS * GameBalance.SPIRIT_BEAST_TAUNT_RADIUS
	for ally in GameManager.live_allies:
		if ally == null or not is_instance_valid(ally):
			continue
		var d: float = global_position.distance_squared_to(ally.global_position)
		if d < best_sq:
			best_sq = d
			best = ally
	return best

func _update_offscreen_cull() -> void:
	var vp := get_viewport()
	if vp != null:
		var sp: Vector2 = vp.get_canvas_transform() * global_position
		var lim: Vector2 = vp.get_visible_rect().size + Vector2.ONE * CULL_MARGIN
		_offscreen = sp.x < -CULL_MARGIN or sp.y < -CULL_MARGIN or sp.x > lim.x or sp.y > lim.y

## 灼烧/剧毒跳伤结算；致死（dying）返回 true，调用方立即结束本帧
func _tick_damage_over_time(delta: float) -> bool:
	if burn_timer > 0.0:
		burn_timer -= delta
		_burn_tick += delta
		if _burn_tick >= GameBalance.DOT_TICK_INTERVAL:
			_burn_tick = 0.0
			var b_dmg := GameBalance.burn_tick_damage(burn_dps, GameManager.elemental_damage, GameManager.synergy_burn_mult)
			take_damage(b_dmg, Vector2.ZERO, false, true)
			if dying:
				return true
		if burn_timer <= 0.0:
			burn_dps = 0.0
	if poison_timer > 0.0:
		poison_timer -= delta
		_poison_tick += delta
		if _poison_tick >= GameBalance.DOT_TICK_INTERVAL:
			_poison_tick = 0.0
			var p_dmg := GameBalance.poison_tick_damage(poison_dps, GameManager.elemental_damage)
			take_damage(p_dmg, Vector2.ZERO, false, true)
			if dying:
				return true
		if poison_timer <= 0.0:
			poison_dps = 0.0
	return false

## 有效移速 = 基础 ×（1-冰缓）× 光环；顺带处理冰缓染色与光环过期待遇失效
func _effective_speed(delta: float) -> float:
	var eff_speed: float = move_speed
	if chill_timer > 0.0:
		chill_timer -= delta
		eff_speed = move_speed * (1.0 - chill_slow)
		if _fuse < 0.0:
			anim_sprite.modulate = Color(0.68, 0.88, 1.05)
		if chill_timer <= 0.0:
			chill_slow = 0.0
			if _fuse < 0.0:
				anim_sprite.modulate = Color.WHITE
	# 鼓妖光环：被覆盖期间加速，过期待遇自动失效
	if _aura_speed_mult != 1.0 and Time.get_ticks_msec() > _aura_until_ms:
		_aura_speed_mult = 1.0
	return eff_speed * _aura_speed_mult

## 受击卡肉/硬直计时与击退急刹擦地扬尘；返回硬直是否仍在
func _tick_hit_stun(delta: float) -> bool:
	var is_in_hit_freeze := _hit_freeze_timer > 0.0
	if is_in_hit_freeze:
		_hit_freeze_timer -= delta
	var is_in_hit_stun := hit_stun_timer > 0.0
	if is_in_hit_stun:
		hit_stun_timer -= delta

	# 击退急刹擦地烟尘（被击退起步瞬间扬尘，表现地面抓地阻力）
	if is_in_hit_stun and knockback_velocity.length_squared() > 14400.0:
		_skid_dust_timer -= delta
		if _skid_dust_timer <= 0.0:
			_skid_dust_timer = 0.045
			JuiceEffect.spawn_step_dust(get_parent(), global_position + Vector2(0, 12), knockback_velocity)
	return is_in_hit_stun

## 行为支路推进：远程风筝 / 扑咬状态机 / 自爆引信 / 火球 / 产卵 / 光环 / 闪现。
## 期望速度统一写 _pp_target_vel；返回 true = 自爆已结算（_explode 内部已走死亡流），调用方立即结束本帧。
func _tick_behaviors(delta: float, player: Node2D, dir: Vector2, dist_sq: float, eff_speed: float) -> bool:
	# 金蟾系：恒背离玩家逃窜（土豆兄弟 Looter：击杀爆金币的限时宝藏怪）
	if always_flee and not _pp_stun:
		_pp_target_vel = -dir * eff_speed

	# 远程怪：保持距离，近了退、远了进、合适距离环绕游走
	if not always_flee and not _pp_stun and preferred_range > 0.0:
		var dist := sqrt(dist_sq)
		if dist < preferred_range - 30.0:
			_pp_target_vel = -dir * eff_speed * 0.8
		elif dist <= preferred_range + 30.0:
			_pp_target_vel = Vector2(-dir.y, dir.x) * eff_speed * 0.5

	# 妖狼系的两套扑击（共用同一个移动出口 _pp_target_vel，靠 elif 链天然互斥）：
	#   长扑 = 跑道够（charge_min_range ~ charge_max_range）→ 站桩预警 → 直线冲刺 → 收势（落空则罚站）
	#   短咬 = 贴进 charge_min_range 以内 → 下蹲预告（方向当帧锁死、之后不追踪）→ 小幅跃击咬一口
	# 长扑的三件事必须同源，都取自 GameBalance.charge_reach：预警带长度、真实位移、扫掠判定。
	# 冲刺/收势两段自己把 velocity 写死（下面 charge_locked 那一段因此跳过吸附插值）。
	# 旧版只有长扑，且触发带下沿写死 120px：贴着脸它整个技能就不出手，只剩毫无预告的
	# 接触伤害一路蹭（2026-10-08 用户现场：「近距离一直追着我、远距离才扑」）。
	# 两带以 charge_min_range 为界互补 ⇒ 任何距离都有一个看得见预告的威胁。
	if charge_interval > 0.0 or bite_range > 0.0:
		_charge_timer -= delta
		_bite_timer -= delta
		var min_sq: float = charge_min_range * charge_min_range
		var max_sq: float = charge_max_range * charge_max_range

		# 预警阶段：原地不动，画预警线
		if _charge_windup > 0.0:
			_charge_windup -= delta
			_pp_target_vel = Vector2.ZERO
			_update_charge_warning(player)
			if _charge_windup <= 0.0:
				# 预警期间玩家贴进了「没跑道」的距离 ⇒ 就地转成短咬：它已经站桩预警了
				# 1.2s、玩家看得很清楚，所以不再补一次下蹲预告，直接跳。
				# 旧写法不复查距离，症状是「都贴脸了还往前冲 300px、从玩家身上碾过去」
				if bite_range > 0.0 and dist_sq < min_sq:
					_clear_charge_warning()
					_launch_bite(dir)
				else:
					_start_charge(dir)

		# 冲刺阶段：起步即满速，位移由锁定段直接写进 velocity（同 Player 缩地成寸的口径）。
		# 旧写法只交一个 target_vel，让下方 900 px/s² 的吸附插值从站桩预警的 0 速去爬峰速 384
		# ⇒ 0.43s 才够到速度（锁定时长一半耗在起步上），冲刺结束后还留一段朝玩家拐弯的滑行尾巴
		# ⇒ 「画的线」「撞的段」「判的范围」是三套数，玩家只要动一下就永远碰不到它
		elif _charge_active > 0.0:
			_charge_active -= delta
			velocity = _charge_dir * move_speed * charge_speed_mul
			_pp_target_vel = velocity
			knockback_velocity = Vector2.ZERO
			_clear_charge_warning()
			if _charge_active <= 0.0:
				_charge_brake = charge_brake_time

		# 收势刹车：峰速线性刹到站定。这一段也是承诺出去的位移，预警线按 GameBalance.charge_reach 已把它算进线长
		elif _charge_brake > 0.0:
			_charge_brake -= delta
			var brake_k: float = maxf(_charge_brake / maxf(charge_brake_time, 0.0001), 0.0)
			velocity = _charge_dir * (move_speed * charge_speed_mul) * brake_k
			_pp_target_vel = velocity
			knockback_velocity = Vector2.ZERO
			if _charge_brake <= 0.0:
				_settle_charge_recovery()

		# 落空罚站：冲空了就是白给，玩家看得见「它过去了、站着不动」⇒ 躲开这条路才有奖励，而不只是没被打到
		elif _charge_stagger > 0.0:
			_charge_stagger -= delta
			_pp_target_vel = Vector2.ZERO

		# 短咬：下蹲预告。方向在锁死那一帧定、之后不追踪玩家（0.35s 还追踪就躲不开了）
		elif _bite_windup > 0.0:
			_bite_windup -= delta
			_pp_target_vel = Vector2.ZERO
			if _bite_windup <= 0.0:
				_launch_bite(_bite_dir)

		# 短咬：起跳。一次起跳只结算一口，伤害与接触伤害同一把尺子（走玩家那套无敌帧，
		# 所以贴着它被蹭到的那一下不会和这一口叠加）
		elif _bite_active > 0.0:
			_bite_active -= delta
			_pp_target_vel = _bite_dir * move_speed * bite_speed_mul
			if not _bite_hit and dist_sq < bite_hit_radius * bite_hit_radius:
				_bite_hit = true
				player.take_damage(contact_damage * bite_damage_mul)
				# 不在这里再发一次反馈：player.take_damage 已经按「玩家受创」这个节点给过
				# 大创伤 + 顿帧 + 红晕，两边都发就是同一下挨打震两回
			if _bite_active <= 0.0:
				_clear_bite_warning()

		# 空闲：冷却到 + 跑道够 → 长扑预警（硬直中不起手：预警/起跳是冲刺的蓄力段，
		# 被钉着还起手，后续 _bite_active/_start_charge 会从硬直滑行分支夺走位移，「定身」成空话）
		if charge_interval > 0.0 and _charge_timer <= 0.0 and dist_sq > min_sq and dist_sq < max_sq and not _pp_stun:
			_charge_timer = charge_interval
			_charge_windup = charge_windup_time

		# 空闲：冷却到 + 玩家已贴进 bite_range → 短咬下蹲（同样只挡「起手」，不夺已承诺段）
		# （bite_range 与 charge_min_range 取同值 ⇒ 两带互补，中间不留"谁都不出手"的缝）
		elif bite_range > 0.0 and _bite_timer <= 0.0 and dist_sq > 16.0 and dist_sq <= bite_range * bite_range and not _pp_stun:
			_bite_timer = bite_interval
			_bite_windup = bite_windup_time
			_bite_dir = dir
			_show_bite_warning(dir)
			play_squash(Vector2(1.24, 0.76), bite_windup_time)
			# 起手是妖物自己的扑咬声，不许借玩家法器的挥砍（旧写法播 sword_swing，战场上分不清谁在打）
			AudioManager.play_sfx("enemy_claw", 0.5, GameManager.rng.randf_range(0.92, 1.08))

	# 丹爆傀儡：贴近点燃引信，原地颤抖后自爆
	if explode_radius > 0.0:
		if _fuse < 0.0:
			if dist_sq < 1600.0:
				_fuse = EXPLODE_FUSE
				anim_sprite.modulate = Color(2.2, 0.9, 0.6)
				play_squash(Vector2(1.2, 0.82), 0.3)
				AudioManager.play_sfx("enemy_fuse", 1.0)   ## 引信是递进爆点的倒计时，不是灵宝触体的钟
				_ignite_explode_ring()
		else:
			_fuse -= delta
			_pp_target_vel = Vector2.ZERO
			if _explode_ring != null:
				_explode_ring.progress = 1.0 - _fuse / EXPLODE_FUSE
			anim_sprite.position.x = GameManager.rng.randf_range(-1.6, 1.6)
			if _fuse <= 0.0:
				anim_sprite.position.x = 0.0
				_explode(player)
				return true

	# 御剑邪修：保持距离的同时周期性发射火球
	if bolt_interval > 0.0 and _fuse < 0.0:
		_bolt_timer -= delta
		if _bolt_timer <= 0.0 and dist_sq < 396900.0:
			_bolt_timer = bolt_interval
			_fire_bolt(player)

	# 蛛母系：周期性产卵（受同屏上限约束，不冲破刷怪口的上限）
	if spawn_minion_interval > 0.0 and minion_scene != null and _fuse < 0.0:
		_minion_timer -= delta
		if _minion_timer <= 0.0:
			_minion_timer = spawn_minion_interval
			if GameManager.enemy_count < GameBalance.ZHUMU_MINION_CAP:
				_spawn_minion()

	# 鼓妖光环：每 0.25s 给范围内同伴刷新一次加速
	if buff_radius > 0.0:
		_buff_timer -= delta
		if _buff_timer <= 0.0:
			_buff_timer = 0.25
			_pulse_buff_aura()

	# 影魅系：周期性闪现到玩家侧翼（自爆引信点燃时不闪现，避免爆点漂移）
	if teleport_interval > 0.0 and _fuse < 0.0:
		_teleport_timer -= delta
		if _teleport_timer <= 0.0:
			_teleport_timer = teleport_interval
			_teleport_near_player(player)

	# 铁甲巨怪变异·震地：预警圈「填满式」倒计时 → 结算（与 Boss 震地同一套视觉语言）
	if slam_interval > 0.0 and _fuse < 0.0:
		if _elite_slam_windup_t >= 0.0:
			_elite_slam_windup_t -= delta
			_pp_target_vel = Vector2.ZERO
			if _elite_slam_ring != null:
				_elite_slam_ring.progress = 1.0 - _elite_slam_windup_t / maxf(slam_windup, 0.001)
			if _elite_slam_windup_t <= 0.0:
				_resolve_elite_slam(player)
		else:
			_elite_slam_timer -= delta
			if _elite_slam_timer <= 0.0 and dist_sq < slam_radius * slam_radius * 2.25:
				_elite_slam_timer = slam_interval
				_start_elite_slam()

	# 灵医系：周期性治疗范围内同伴（土豆兄弟 Healer：制造优先击杀目标）
	if heal_interval > 0.0 and _fuse < 0.0:
		_heal_timer -= delta
		if _heal_timer <= 0.0:
			_heal_timer = heal_interval
			_pulse_heal()

	return false

## 速度解算：冲刺/收势锁定段由状态机逐帧写死（不交给插值、不被硬直夺走）；
## 硬直期间位移纯由击退主导并快速衰减；平时吸附插值追击
func _resolve_velocity(delta: float) -> void:
	var charge_locked := _charge_active > 0.0 or _charge_brake > 0.0
	if charge_locked:
		# velocity 已由状态机逐帧写死 ⇒ 既不交给吸附插值去改，
		# 也不被受击硬直夺走（commit-through，与旧写法「硬直期间冲刺照冲」同一条口径）
		pass
	elif _pp_stun and _bite_active <= 0.0:
		velocity = knockback_velocity
		# 衰减在赋予 velocity 之后执行：第 0 帧吃满初速，并在 ~0.11s 内快速到位并完全刹停
		var decay_rate: float = GameBalance.KNOCKBACK_DECAY_STUN
		if knockback_velocity.length_squared() > 16.0:
			knockback_velocity = knockback_velocity.lerp(Vector2.ZERO, minf(delta * decay_rate, 1.0))
		else:
			knockback_velocity = Vector2.ZERO
	else:
		velocity = velocity.move_toward(_pp_target_vel, 900.0 * delta)
		# 硬直结束时残余击退彻底清零，杜绝边追击边滑步的打冰球现象
		knockback_velocity = Vector2.ZERO

## 受击视觉零分配衰减（2026-10-11）：挤压回弹（TRANS_BACK EASE_OUT 同款过冲曲线）
## 与闪白衰减逐帧推进，替代原先每次受击 create_tween ×2 的分配热点
func _tick_hit_fx(delta: float) -> void:
	if _squash_t > 0.0:
		_squash_t = maxf(0.0, _squash_t - delta)
		var t := 1.0 - _squash_t / _squash_dur
		var c1 := 1.70158
		var e := 1.0 + (c1 + 1.0) * pow(t - 1.0, 3.0) + c1 * pow(t - 1.0, 2.0)
		juice_scale = _squash_from.lerp(Vector2.ONE, clampf(e, 0.0, 1.0))
	if _flash_t > 0.0:
		_flash_t = maxf(0.0, _flash_t - delta)
		if hit_flash_mat != null:
			hit_flash_mat.set_shader_parameter("flash_modifier", clampf(_flash_t / _flash_down_dur, 0.0, 1.0))
	if _flash_swap_t > 0.0:
		_flash_swap_t -= delta
		if _flash_swap_t <= 0.0 and hit_flash_mat != null:
			hit_flash_mat.set_shader_parameter("flash_color", Color(1.0, 0.96, 0.85, 1.0))

## 受击视觉：微反冲回弹（非自爆抖动期间生效，同步作用于精灵与程序化矢量视图）与后仰倾角衰减
func _tick_hit_visuals(delta: float) -> void:
	if _hit_jiggle_offset.length_squared() > 0.01:
		_hit_jiggle_offset = _hit_jiggle_offset.lerp(Vector2.ZERO, minf(delta * 24.0, 1.0))
	else:
		_hit_jiggle_offset = Vector2.ZERO
	if _fuse < 0.0:
		anim_sprite.position = _hit_jiggle_offset
		if procedural_view != null:
			procedural_view.position = anim_sprite.position

	# 受创后仰倾角衰减
	if absf(_hit_tilt) > 0.005:
		_hit_tilt = lerpf(_hit_tilt, 0.0, minf(delta * 14.0, 1.0))
	else:
		_hit_tilt = 0.0

## 朝向迟滞 + 三档步态动画（步态腿帧 / 悬浮 / 蠕动）+ 程序化矢量视图同步
func _update_facing_and_anim(delta: float, dir: Vector2, dist_sq: float) -> void:
	# 3. Sprite 方向 & 动画（带迟滞滤波 + 贴近锁定 + 移速步频自适应）
	# 当怪物与玩家极度贴近（小于 18px）时锁定原有朝向，避免围绕玩家中心旋转时的抽风风扇效应
	if dist_sq > 324.0 and dir.length_squared() > 0.01:
		var face: Array = RunMotion.facing_stable(dir, facing, anim_sprite.flip_h, 32.0)
		if face[0] != "":
			facing = face[0]
			anim_sprite.flip_h = face[1]

	var current_base := anim_base_scale * juice_scale
	var current_speed := velocity.length()
	var speed_ratio: float = (current_speed / move_speed) if move_speed > 0.0 else 1.0
	# 受击硬直期间强制停步：不踏步、不迈腿；正常移动且实际位移足够才播跑步动画
	var is_moving := (not _pp_stun) and current_speed > maxf(20.0, move_speed * 0.2)

	if locomotion_mode == "hover":
		# 悬浮：不切腿帧（单姿势图集），浮沉/侧倾/纵向意图由程序驱动。
		# 侧倾喂**实际位移方向**而不是「面向玩家」的方向：邪修这类带 preferred_range 的
		# 远程怪会后退放风筝，用面向方向 bank 的话，逼近与后撤倾同一个方向，玩家分不清
		#（2026-10-09 用户现场：「踩着黑雾的为什么背对着走向我」——它其实在往后撤）。
		# advance = 位移与面向的夹角余弦：+1 压过来 / -1 后撤 / ≈0 环绕侧滑。
		# 受击定身期间归零：那一拍已有 play_squash + 微反冲在发反馈，不叠第二处。
		var vel_dir := Vector2.ZERO
		if is_moving and current_speed > 0.01:
			vel_dir = velocity / current_speed
		var advance := 0.0
		if not _pp_stun:
			advance = vel_dir.dot(dir)
		RunMotion.select_anim(anim_sprite, "idle_" + facing, false)
		RunMotion.apply_hover(anim_sprite, current_base, is_moving, vel_dir, delta, speed_ratio, shadow_sprite, advance)
	elif locomotion_mode == "slither":
		# 蠕动：贴地行进波（scale 伸缩），无悬浮无前倾
		RunMotion.select_anim(anim_sprite, "idle_" + facing, false)
		RunMotion.apply_slither(anim_sprite, current_base, is_moving, delta, speed_ratio, shadow_sprite)
	else:
		# 步态腿帧：有图集才切腿帧；程序化敌种没有帧集，但形变链路照走
		#（RunMotion.apply 对 null 帧集内部按 4 帧 / 10fps 默认推进步态相位）
		var has_run_frames := anim_sprite.sprite_frames != null and anim_sprite.sprite_frames.has_animation("run_" + facing)
		if has_run_frames and is_moving:
			var run_anim: String = "run_" + facing
			RunMotion.select_anim(anim_sprite, run_anim, true)
			RunMotion.apply(anim_sprite, current_base, true, anim_sprite.flip_h, absf(dir.x), delta, speed_ratio, 0.0, shadow_sprite)
		elif has_run_frames:
			RunMotion.select_anim(anim_sprite, "idle_" + facing, false)
			RunMotion.apply(anim_sprite, current_base, false, anim_sprite.flip_h, 0.0, delta, 1.0, 0.0, shadow_sprite)
		elif is_moving:
			RunMotion.apply(anim_sprite, current_base, true, anim_sprite.flip_h, absf(dir.x), delta, speed_ratio, 0.0, shadow_sprite)
		else:
			RunMotion.apply(anim_sprite, current_base, false, anim_sprite.flip_h, 0.0, delta)

	# 3.5 同步程序化矢量视图
	if procedural_view != null:
		procedural_view.facing = facing
		procedural_view.flip_h = anim_sprite.flip_h
		procedural_view.scale = anim_sprite.scale
		procedural_view.modulate = anim_sprite.modulate
		procedural_view.is_moving = is_moving
		procedural_view.speed_ratio = speed_ratio
		if _pp_stun:
			procedural_view.bank_angle = _hit_tilt
		elif locomotion_mode == "hover":
			var vel_dir := Vector2.ZERO
			if is_moving and current_speed > 0.01:
				vel_dir = velocity / current_speed
			procedural_view.bank_angle = deg_to_rad(vel_dir.x * 6.5)
			procedural_view.advance = vel_dir.dot(dir)
		if _fuse >= 0.0:
			procedural_view.special_state = 1.0
		elif _charge_windup >= 0.0 or _bite_windup >= 0.0:
			procedural_view.special_state = 1.0
		else:
			procedural_view.special_state = 0.0

	## 冲刺走廊扫掠结算 + 追击目标接触伤害判定（石岳反震只认玩家，灵兽无反震）
func _resolve_contact_damage(target: Node2D, pos_before_move: Vector2) -> void:
	# 3.6 冲刺走廊扫掠结算：判定走的是「狼身这一帧扫过的那一段」，独立于本体碰撞。
	# 旧写法长扑只有下面那条身位滑碰（狼 19.5 + 玩家 14 = 33.5px）这一个出口，
	# 而预警 0.8s 够玩家横移 168px ⇒ 只要动一下就必然躲开，整个技能形同虚设
	#（2026-10-10 用户现场：「根本冲刺不到我」）。近战短咬反倒有 bite_hit_radius 那道口
	# ⇒ 近距离打得人、远距离打不到，威胁段刚好落在最不需要威胁的地方。
	# 伤害只走目标自己的 take_damage 这一个口子：玩家侧的无敌帧/闪避/护甲/受创反馈全复用，
	# 不在这里发第二次反馈（同短咬那处口径）；一个 flag 钉死「一次冲刺只碾一下」。
	var charge_locked := _charge_active > 0.0 or _charge_brake > 0.0
	if charge_locked and not _charge_hit:
		var closest: Vector2 = GameBalance.seg_closest_point(pos_before_move, global_position, target.global_position)
		if closest.distance_to(target.global_position) <= charge_hit_radius:
			_charge_hit = true
			if target is Player:
				var hp_before_charge: float = target.current_health
				target.take_damage(contact_damage * charge_damage_mul)
				# 石岳/玄武反震：与接触伤害同一个口径，实际被打中才反弹
				var eff_thorns: float = GameManager.get_effective_thorns()
				if eff_thorns > 0.0 and target.current_health < hp_before_charge:
					take_damage(contact_damage * eff_thorns, Vector2.ZERO, false)
			elif target.has_method("take_damage"):
				target.take_damage(contact_damage * charge_damage_mul)

		# 4. 接触伤害判定：撞到谁咬谁（玩家走无敌帧/反震那套，灵兽走自己的受击无敌帧）
		for i in range(get_slide_collision_count()):
			var col = get_slide_collision(i)
			var collider = col.get_collider()
			if collider is Player:
				var hp_before: float = collider.current_health
				collider.take_damage(contact_damage)
				# 石岳/玄武反震：实际被打中才反弹（闪避/无敌帧不触发）
				var eff_thorns: float = GameManager.get_effective_thorns()
				if eff_thorns > 0.0 and collider.current_health < hp_before:
					take_damage(contact_damage * eff_thorns, Vector2.ZERO, false)
			elif collider != null and collider.is_in_group("allies") and collider.has_method("take_damage"):
				collider.take_damage(contact_damage)

# ---------------- 受击结算 / 硬直 / 击退 / 掉落 ----------------
func take_damage(amount: float, knockback: Vector2, is_crit: bool = false, from_dot: bool = false) -> void:
	if dying:
		return
	# 普通小怪同目标短窗集火保护：防多把法器同帧命中瞬间蒸发，保证受击硬直/击退/闪白充分展现
	if not from_dot and not is_elite:
		if _focus_hit_timer <= 0.0:
			_focus_hit_count = 0
		amount *= GameBalance.focus_fire_mult(_focus_hit_count)
		_focus_hit_count += 1
		_focus_hit_timer = GameBalance.FOCUS_FIRE_WINDOW
	current_hp -= amount
	# 精英变异血线检查（只触发一次；Boss 走自己的二阶段，_enter_mutation 内部按敌种分发）
	if not _mutated and is_elite and current_hp > 0.0 and current_hp <= max_hp * GameBalance.ELITE_MUTATION_HP_PCT:
		_enter_mutation()
	# 致命一刀不再发命中火花：尸体 0.185s 就塌缩没，火花要放 0.22s，会在空处留一道白闪；
	# 击杀点反馈由 _die() 的死亡爆散一力承担（视觉不丢，只是不再双发）
	var lethal := current_hp <= 0.0

	# 击退冲量瞬发与武器分级（空洞骑士/死亡细胞风格：第 0 帧爆发、轻武器短击退~12px、重武器强击退~45px）
	var elite_scale: float = 0.55 if is_elite else 1.0
	var crit_kb_mult: float = 1.25 if is_crit else 1.0
	var raw_kb := knockback * (GameBalance.KNOCKBACK_IMPULSE_SCALE * elite_scale * crit_kb_mult)
	var max_spd: float = GameBalance.KNOCKBACK_MAX_SPEED_CRIT if is_crit else GameBalance.KNOCKBACK_MAX_SPEED_NORMAL
	if raw_kb.length() > max_spd:
		raw_kb = raw_kb.normalized() * max_spd
	knockback_velocity = raw_kb

	# 受击硬直定身（hit-stun）与后仰姿态：
	# 受击当帧立即暂停主动 AI 追击速度，并在极速刹停后原地僵直定身；DoT tick 不触发硬直以保手感纯粹
	if not from_dot:
		var base_stun: float = GameBalance.HIT_STUN_CRIT if is_crit else GameBalance.HIT_STUN_NORMAL
		hit_stun_timer = maxf(hit_stun_timer, base_stun * elite_scale * hit_stun_resist)
		var freeze_dur: float = GameBalance.HIT_FREEZE_CRIT if is_crit else GameBalance.HIT_FREEZE_NORMAL
		_hit_freeze_timer = maxf(_hit_freeze_timer, freeze_dur * elite_scale * hit_stun_resist)
		if knockback.length_squared() > 10.0:
			_hit_tilt = -knockback.normalized().x * deg_to_rad(14.0)

	# 1. 声音与震动（分层听觉：入肉撕裂+低频下潜 + 肉眼可见的方向性顿挫冲击）
		if is_crit:
			if not from_dot:
				AudioManager.play_sfx("enemy_hit", 1.25, randf_range(1.08, 1.22))
				AudioManager.play_sfx("enemy_hit_crit", 1.35, randf_range(0.95, 1.05))
			GameManager.crit_hit_stop()
			GameManager.kick_camera(knockback, 6.5)
		GameFeel.zoom_punch(GameManager, 0.022, 0.12)
		# 暴击从「只冲不摇」升级为可见摇晃：普通暴击也发一笔小额创伤（走每秒预算，稳态不变）
		if is_elite:
			GameManager.add_trauma(GameBalance.CRIT_TRAUMA_ELITE)
			GameFeel.vibrate(26, 0.65)
		else:
			GameManager.add_trauma(GameBalance.CRIT_TRAUMA_NORMAL)
	elif not from_dot:
		# 普通命中：即时方向性微冲击（Directional Micro-Kick，2.8px），让刀刀入肉清晰可感，不累加持续性正弦创伤。
		# 走全局限流闸（2026-10-11 频闪治理）：远程穿透/弹射下每秒几十次命中逐刀微震会糊成持续抖屏
		GameFeel.micro_kick(GameManager, knockback, 2.8)
		var pitch: float = randf_range(0.94, 1.08) if not is_elite else 0.85
		AudioManager.play_sfx("enemy_hit", 1.15 if not is_elite else 0.95, pitch)
		if is_elite or raw_kb.length() > GameBalance.KNOCKBACK_HEAVY_SPEED:
			AudioManager.play_sfx("enemy_hit_heavy", 1.00, randf_range(0.92, 1.06))

	# 跳字（2026-10-10 屏外减负）：屏外一概不发（玩家看不见，白烧分配）；
	# DoT tick 常驻发跳字。音效/硬直/击退/闪白/顿帧全部保留 —— 打击感读数不变。
	# 受击火花已整体下线（2026-10-11 用户拍板：远程高频命中下仍「空白处乱闪」，待重构替代品）
	if not _offscreen:
		DamageNumber.spawn(get_parent(), global_position, int(amount), is_crit)
	var squash_target := _calculate_hit_squash(knockback, is_crit)
	play_squash(squash_target, 0.16)

	# 受击微反冲视觉位移（Jiggle Recoil）：受击当帧向击退方向微颤并同步至程序化视图
	if not from_dot and knockback.length_squared() > 10.0:
		_hit_jiggle_offset = knockback.normalized() * (4.2 if is_crit else 2.8)
		anim_sprite.position = _hit_jiggle_offset
		if procedural_view != null:
			procedural_view.position = anim_sprite.position

	# 3. 闪白 Shader（分级闪白：普通亮白 vs 暴击绯金，加实留存时间）——零 Tween 分配版：
	# 命中瞬间拉满 flash_modifier 并启动衰减计时（原 0.02s 拉满段在 60fps 下只有 1~2 帧），
	# 暴击先绯金、0.02s 后换暖白再衰减（换色倒计时走 _flash_swap_t）
	if hit_flash_mat != null:
		if is_crit:
			hit_flash_mat.set_shader_parameter("flash_color", Color(1.0, 0.42, 0.22, 1.0))
			_flash_t = 0.12
			_flash_down_dur = 0.12
			_flash_swap_t = 0.02
		else:
			hit_flash_mat.set_shader_parameter("flash_color", Color(1.0, 1.0, 0.95, 1.0))
			_flash_t = 0.11
			_flash_down_dur = 0.11
			_flash_swap_t = 0.0
		hit_flash_mat.set_shader_parameter("flash_modifier", 1.0)

	if lethal:
		# 致命一刀不做任何位移：knockback_velocity 只作死亡镜头反馈的方向读数，
		# 精英 kick_camera / 小怪 micro_kick 内部都只 normalized() 取方向，不读模长。
		# 暴击击杀特写：更实的独立顿帧 + 一记缩放冲击（2026-10-11；爆散规模放大于 2026-10-12 随爆散下线移除）
		_death_crit_kill = is_crit and not from_dot
		if _death_crit_kill:
			# 精英伏诛走 HEAVY 反馈自带更大顿帧/缩放，此处不重复发
			if not is_elite:
				GameFeel.crit_kill_hit_stop(GameManager)
				GameFeel.zoom_punch(GameManager, 0.03, 0.14)
		# 击杀微顿帧（GameFeel 限流）：减潮加肉后击杀是低频事件，这一记「确认感」值得给；
		# DoT 跳死不发（那不是玩家亲手砍的一刀），精英伏诛走 LARGE 反馈自带顿帧不重复发
		elif not from_dot and not is_elite:
			GameManager.kill_hit_stop()
		_die()

## 根据受击方向计算定向挤压形变
func _calculate_hit_squash(knockback: Vector2, is_crit: bool) -> Vector2:
	if knockback.length_squared() < 10.0:
		return Vector2(1.36, 0.70) if is_crit else Vector2(1.24, 0.80)
	var k_norm := knockback.normalized()
	if absf(k_norm.x) >= absf(k_norm.y):
		# 水平冲击为主：水平压扁、竖直拉伸
		return Vector2(0.68, 1.38) if is_crit else Vector2(0.76, 1.26)
	else:
		# 垂直冲击为主：竖直压扁、水平拉伸
		return Vector2(1.38, 0.68) if is_crit else Vector2(1.26, 0.76)

## 施加【离火灼烧】：按秒持续扣血，受离火羁绊与元素伤害增伤，多源叠加共鸣
# ---------------- 五行异常施加（灼烧 / 冰缓 / 剧毒） ----------------

func apply_burn(dps: float, duration: float) -> void:
	if dying:
		return
	var active_dps: float = burn_dps if burn_timer > 0.0 else 0.0
	burn_dps = GameBalance.stack_burn_dps(active_dps, dps)
	burn_timer = maxf(burn_timer, duration)

## 施加【玄水冰缓】：降低移动速度并附加冰蓝色温
func apply_chill(slow_pct: float, duration: float) -> void:
	if dying:
		return
	chill_slow = maxf(chill_slow, clampf(slow_pct, 0.1, 0.7))
	chill_timer = maxf(chill_timer, duration)

## 施加【青木剧毒】：持续毒素侵蚀，受元素伤害增伤
func apply_poison(dps: float, duration: float) -> void:
	if dying:
		return
	var active_dps: float = poison_dps if poison_timer > 0.0 else 0.0
	poison_dps = GameBalance.stack_poison_dps(active_dps, dps)
	poison_timer = maxf(poison_timer, duration)

## 施加【罡风卷定】（灵兽·灵风貂）：牵引初速 + 钉身 + 吹散在途扑咬蓄力。
## 位移复用受击硬直滑行段（_resolve_velocity：velocity = knockback_velocity 后按
## KNOCKBACK_DECAY_STUN 指数急刹），调用方用 BalanceSpiritPet.pull_impulse 反解出
## 「恰好刹停在定身环」的初速，本函数不再过 take_damage 的击退限速（那是武器刀的尺子，
## 卷位移的目标是到环，不是推多远）。伤害由调用方另走 take_damage（复用飘字/集火保护）。
## 长扑承诺段不夺（项目口径：冲刺一旦起步 commit-through，wolf_ai_check 判据在守）；
## 但预警站桩与短咬起跳直接吹散 —— 挂着「定身」还把人扑出去咬一口，文案就是假的。
## 哨兵注意：_charge_windup/_bite_windup 的「不在该阶段」是 -1.0 而不是 0.0，
## 写 0.0 会让本帧末的预警到点分支照常发射。冷却无需重置：进蓄力时 _charge_timer/
## _bite_timer 已按整周期回满，吹散不会导致立刻再扑。
func apply_vortex_pin(pull_velocity: Vector2, pin_sec: float) -> void:
	if dying:
		return
	hit_stun_timer = maxf(hit_stun_timer, pin_sec)
	knockback_velocity = pull_velocity
	if _charge_windup > 0.0:
		_charge_windup = -1.0
		_clear_charge_warning()
	if _bite_windup > 0.0:
		_bite_windup = -1.0
		_clear_bite_warning()
	if _bite_active > 0.0:
		_bite_active = 0.0
		_clear_bite_warning()

## 自爆结算：范围内伤玩家，不掉落、不计击杀奖励
# ---------------- 行为支路：自爆 ----------------

func _explode(player: Node2D) -> void:
	if dying:
		return
	_clear_explode_ring()
	# 冲击波扫到 explode_radius 为止：扫过的范围就是受伤的范围（与判定同源）
	JuiceEffect.spawn_shockwave(get_parent(), global_position, explode_radius, GameStyle.BAD)
	GameManager.feedback(GameManager.FeedbackTier.MEDIUM)
	AudioManager.play_sfx("enemy_death_elite", 0.9)
	if player.global_position.distance_to(global_position) <= explode_radius:
		player.take_damage(contact_damage * 2.0, global_position)
	_no_drop = true
	_die()

## 点燃丹爆引信预警圈：半径 = 判定半径（同源），引信烧完圈正好填满
func _ignite_explode_ring() -> void:
	if _explode_ring == null:
		_explode_ring = AoeTelegraph.new()
		_explode_ring.radius = explode_radius
		add_child(_explode_ring)
	_explode_ring.progress = 0.0
	_explode_ring.visible = true

## 清理丹爆预警圈（自爆结算 / 引信中途被杀时调用）
func _clear_explode_ring() -> void:
	if _explode_ring != null and is_instance_valid(_explode_ring):
		_explode_ring.queue_free()
	_explode_ring = null

## 开始冲刺（预警结束后调用）：方向到此锁死，之后不再追踪玩家
# ---------------- 行为支路：长扑冲刺 ----------------

func _start_charge(dir: Vector2) -> void:
	_charge_active = charge_duration
	_charge_dir = dir
	_charge_brake = 0.0
	_charge_stagger = 0.0
	_charge_hit = false
	play_squash(Vector2(0.78, 1.24), 0.2)
	# 起步扬尘：位移是瞬时满速，视觉就得卖「蹬地弹射」而不是「匀速滑出去」
	JuiceEffect.spawn_step_dust(get_parent(), global_position + Vector2(0, 12), dir)
	# 烈雷兽变异：冲刺起步向左右两侧各放一排火球（犀牛 Mutation 同款）
	if charge_side_bolts > 0:
		var base_ang := dir.angle()
		for side in [-1.0, 1.0]:
			for i in range(charge_side_bolts):
				var bolt := EnemyBolt.acquire(get_parent())
				bolt.global_position = global_position
				bolt.direction = Vector2.from_angle(base_ang + side * PI * 0.5 + side * float(i) * 0.22)
				bolt.damage = bolt_damage * (contact_damage / 13.0)
				bolt.activate()
	_clear_charge_warning()

## 收势落空判定：要等整段承诺（冲刺 + 刹车）的扫掠都结算完才许罚站。
## 冲刺归零那一帧的命中判定在本函数之后才跑（扫掠在 move_and_slide 之后），
## 在冲刺段末尾判会漏掉"最后一帧才够到人"的那一冲 ⇒ 碾到了还罚站，玩家看不懂。
## 落空才罚站（这是玩家侧身一步的奖励）；碾到人则不罚（已贴脸，下一步自然接短咬）。
func _settle_charge_recovery() -> void:
	if not _charge_hit and charge_whiff_stagger > 0.0:
		_charge_stagger = charge_whiff_stagger
		play_squash(Vector2(1.22, 0.78), 0.18)

## 更新冲刺预警线（预警期间每帧调用）
func _update_charge_warning(player: Node2D) -> void:
	if _charge_warning_line == null:
		_charge_warning_line = Line2D.new()
		# 带宽 = 判定走廊直径。Line2D 默认圆头端帽，所以画出来那颗胶囊就是
		# 「玩家中心到本帧扫掠线段 ≤ charge_hit_radius」的点集本身 ⇒ 画多大 == 判多大
		_charge_warning_line.width = charge_hit_radius * 2.0
		_charge_warning_line.default_color = Color(1.0, 0.4, 0.2, 0.2)
		add_child(_charge_warning_line)

	# 更新端点：画「真撞得到的那一段」，不是画到玩家身上。
	# 旧写法线恒等于当前距离，玩家站在 450px 时线长 450、而冲刺只有 ~307px
	# ⇒ 预告虚报 143px（看得见的那条线必须就是它真能撞到的范围）。
	# 线长与扫掠判定、与判据 ⑧ 的实测位移，三处都取自 GameBalance.charge_reach 这一个式子。
	_charge_warning_line.clear_points()
	_charge_warning_line.add_point(Vector2.ZERO)
	var local_target: Vector2 = player.global_position - global_position
	var reach: float = GameBalance.charge_reach(move_speed * charge_speed_mul, charge_duration, charge_brake_time)
	if local_target.length() > reach:
		local_target = local_target.normalized() * reach
	_charge_warning_line.add_point(local_target)

	# 闪烁效果：宽带只能压透明度，否则一条带子糊掉半个场地（稀缺反馈预算）
	var alpha: float = 0.15 + 0.10 * sin(_charge_windup * 12.0)
	_charge_warning_line.default_color.a = alpha

## 清理预警线
func _clear_charge_warning() -> void:
	if _charge_warning_line != null:
		_charge_warning_line.queue_free()
		_charge_warning_line = null

## 短咬起跳（下蹲预告结束、或长扑预警中被玩家贴掉跑道时调用）
# ---------------- 行为支路：短扑咬 ----------------

func _launch_bite(dir: Vector2) -> void:
	_bite_active = bite_duration
	_bite_dir = dir
	_bite_hit = false
	play_squash(Vector2(0.72, 1.3), 0.18)
	AudioManager.play_sfx("enemy_claw", 0.85, GameManager.rng.randf_range(0.92, 1.08))

## 画短咬预告线：长度 = 这一跳真跳得出去的位移（bite_hit_radius 是终点附近的咬合半径，
## 不另画圈 —— 判定就落在看得见这条线的落点上，"特效范围 = 判定范围"）
func _show_bite_warning(dir: Vector2) -> void:
	_clear_bite_warning()
	if dir.length_squared() < 0.01:
		return
	_bite_warning_line = Line2D.new()
	_bite_warning_line.width = 5.0
	_bite_warning_line.default_color = Color(1.0, 0.72, 0.15, 0.8)
	add_child(_bite_warning_line)
	_bite_warning_line.add_point(Vector2.ZERO)
	_bite_warning_line.add_point(dir * (bite_duration * move_speed * bite_speed_mul))

## 清理短咬预告线（一次起跳只画一条，落点即结束）
func _clear_bite_warning() -> void:
	if _bite_warning_line != null:
		_bite_warning_line.queue_free()
		_bite_warning_line = null

## 发射火球（御剑邪修；bolt_count>1 时按 bolt_spread 扇形展开，剑煞邪修三连击）
# ---------------- 行为支路：远程火球 ----------------

func _fire_bolt(player: Node2D) -> void:
	var base_dir: Vector2 = (player.global_position - global_position).normalized()
	for i in range(maxi(1, bolt_count)):
		# 火球走对象池（2026-10-11）：远程妖周期直射不再走 instantiate/free
		var bolt := EnemyBolt.acquire(get_parent())
		bolt.global_position = global_position
		var offset_ang := 0.0
		if bolt_count > 1:
			offset_ang = (float(i) - float(bolt_count - 1) * 0.5) * bolt_spread
		bolt.direction = base_dir.rotated(offset_ang)
		bolt.damage = bolt_damage * (contact_damage / 13.0)  # 随波次缩放比例与接触伤害一致（基准取邪修基础值 13）
		bolt.activate()
	play_squash(Vector2(1.16, 0.84), 0.16)
	AudioManager.play_sfx("enemy_bolt", 0.7)

## 鼓妖光环：范围内同伴获得短时加速（0.4s 有效期，光环脉冲每 0.25s 续期）
# ---------------- 行为支路：鼓妖光环 ----------------

func _pulse_buff_aura() -> void:
	var radius_sq := buff_radius * buff_radius
	for e in GameManager.live_enemies:
		if e == self or not (e is EnemyBase) or e.dying:
			continue
		if global_position.distance_squared_to(e.global_position) <= radius_sq:
			e.receive_aura(buff_speed_mult, 400)

## 被鼓妖光环覆盖：取最高倍率，过期待遇由 _physics_process 自动清除
func receive_aura(mult: float, duration_ms: int) -> void:
	if dying:
		return
	_aura_speed_mult = maxf(_aura_speed_mult, mult)
	_aura_until_ms = Time.get_ticks_msec() + duration_ms

## 蛛母产卵：幼体在自身周围落点，血量/伤害按当前波次 × 危险度缩放（与 WaveSpawner._scale_to_wave 同一把尺子）
# ---------------- 行为支路：产卵 / 闪现 / 分裂 ----------------

func _spawn_minion() -> void:
	var m := minion_scene.instantiate() as EnemyBase
	if m == null:
		return
	var angle := GameManager.rng.randf() * TAU
	m.global_position = global_position + Vector2(cos(angle), sin(angle)) * 34.0
	m.max_hp = ceilf(m.max_hp * GameBalance.enemy_hp_mult(GameManager.wave_number) * GameBalance.danger_hp_mult(GameManager.danger_level))
	m.contact_damage = ceilf(m.contact_damage * GameBalance.enemy_dmg_mult(GameManager.wave_number) * GameBalance.danger_dmg_mult(GameManager.danger_level))
	m.add_to_group("enemies")
	get_parent().call_deferred("add_child", m)
	play_squash(Vector2(1.22, 0.78), 0.2)
	AudioManager.play_sfx("enemy_death", 0.5, 1.3)

## 影魅闪现：瞬移到玩家侧翼 210px 处（落点受界碑约束），原地留一个淡出剪影当残影
func _teleport_near_player(player: Node2D) -> void:
	_spawn_teleport_ghost()
	var angle := GameManager.rng.randf() * TAU
	var pos: Vector2 = player.global_position + Vector2(cos(angle), sin(angle)) * 210.0
	var lim: float = GameManager.MAP_HALF_EXTENT - 40.0
	global_position = pos.clamp(Vector2(-lim, -lim), Vector2(lim, lim))
	play_squash(Vector2(1.3, 0.7), 0.2)
	AudioManager.play_sfx("enemy_blink", 0.8)   ## 妖异残影是「下坠」，不许借玩家缩地成寸的 dodge

## 闪现残影：在旧位置生成一个本体的半透明剪影，快速淡出（区别于命中火花）
## 程序化视图走矢量剪影（复用同一份 EnemyVisualConfig）；无程序化配置才回退图集帧。
## 2026-10-13：图集在程序化敌种下不再加载，这条回退分支当前不会命中，保留为兜底。
func _spawn_teleport_ghost() -> void:
	if procedural_view != null and procedural_view.config != null:
		_spawn_vector_ghost()
		return
	if anim_sprite == null or anim_sprite.sprite_frames == null:
		return
	var tex := anim_sprite.sprite_frames.get_frame_texture(anim_sprite.animation, anim_sprite.frame)
	if tex == null:
		return
	var ghost := Sprite2D.new()
	ghost.texture = tex
	ghost.position = position  # 与本体同父节点，本地坐标即等价位置
	ghost.flip_h = anim_sprite.flip_h
	ghost.offset = anim_sprite.offset
	ghost.scale = anim_sprite.global_scale
	ghost.z_index = anim_sprite.z_index
	ghost.modulate = Color(0.55, 0.75, 1.0, 0.5)
	get_parent().add_child(ghost)
	var tw := ghost.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ghost, "modulate:a", 0.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(ghost, "scale", ghost.scale * 0.85, 0.25)
	tw.chain().tween_callback(ghost.queue_free)

## 矢量残影：复制本体当前姿态的渲染器，染成妖异蓝后淡出。
## 不继承受击闪白材质（残影要的是剪影，不是再闪一下）。
func _spawn_vector_ghost() -> void:
	var ghost := HollowKnightEnemyRenderer.new()
	ghost.config = procedural_view.config
	ghost.facing = procedural_view.facing
	ghost.flip_h = procedural_view.flip_h
	ghost.is_moving = procedural_view.is_moving
	ghost.speed_ratio = procedural_view.speed_ratio
	ghost.position = position
	ghost.scale = procedural_view.scale
	ghost.z_index = anim_sprite.z_index
	ghost.modulate = Color(0.55, 0.75, 1.0, 0.5)
	get_parent().add_child(ghost)
	var tw := ghost.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ghost, "modulate:a", 0.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(ghost, "scale", ghost.scale * 0.85, 0.25)
	tw.chain().tween_callback(ghost.queue_free)

## 血蛹分裂：死亡时裂出 N 只幼体（幼体按当前波次 × 危险度缩放；自爆/消散不触发）
func _split_offspring() -> void:
	for i in range(split_count):
		var child := split_scene.instantiate() as EnemyBase
		if child == null:
			continue
		var angle := TAU * float(i) / float(split_count) + GameManager.rng.randf() * 0.5
		child.global_position = global_position + Vector2(cos(angle), sin(angle)) * 26.0
		child.max_hp = ceilf(child.max_hp * GameBalance.enemy_hp_mult(GameManager.wave_number) * GameBalance.danger_hp_mult(GameManager.danger_level))
		child.contact_damage = ceilf(child.contact_damage * GameBalance.enemy_dmg_mult(GameManager.wave_number) * GameBalance.danger_dmg_mult(GameManager.danger_level))
		child.add_to_group("enemies")
		get_parent().call_deferred("add_child", child)

# ---------------- 行为支路：精英变异·震地（铁甲巨怪） ----------------

func _start_elite_slam() -> void:
	_elite_slam_windup_t = slam_windup
	if _elite_slam_ring == null:
		_elite_slam_ring = AoeTelegraph.new()
		_elite_slam_ring.radius = slam_radius
		add_child(_elite_slam_ring)
	_elite_slam_ring.progress = 0.0
	_elite_slam_ring.visible = true
	AudioManager.play_sfx("enemy_fuse", 0.6)
	play_squash(Vector2(0.82, 1.2), 0.4)

func _resolve_elite_slam(player: Node2D) -> void:
	_elite_slam_windup_t = -1.0
	if _elite_slam_ring != null:
		_elite_slam_ring.visible = false
	if dying:
		return
	JuiceEffect.spawn_shockwave(get_parent(), global_position, slam_radius, GameStyle.BAD)
	AudioManager.play_sfx("enemy_slam", 0.8)
	if player == null or player.global_position.distance_to(global_position) > slam_radius:
		return
	var slam_dmg := maxf(1.0, contact_damage * slam_dmg_mult)
	if player is Player:
		player.take_damage(slam_dmg, global_position)
	elif player.has_method("take_damage"):
		player.take_damage(slam_dmg)

# ---------------- 行为支路：灵医治疗 ----------------

func _pulse_heal() -> void:
	var radius_sq := heal_radius * heal_radius
	var healed_any := false
	for e in GameManager.live_enemies:
		if e == self or not (e is EnemyBase) or e.dying:
			continue
		if global_position.distance_squared_to(e.global_position) > radius_sq:
			continue
		if e.current_hp >= e.max_hp:
			continue
		e.receive_heal(heal_amount)
		healed_any = true
	if healed_any:
		JuiceEffect.spawn_shockwave(get_parent(), global_position, heal_radius, GameStyle.GOOD, 0.35)
		AudioManager.play_sfx("drone_chime", 0.5)
		play_squash(Vector2(1.18, 0.84), 0.18)

func receive_heal(amount: float) -> void:
	if dying:
		return
	current_hp = minf(max_hp, current_hp + amount)
	if not _offscreen:
		DamageNumber.spawn(get_parent(), global_position, int(amount), false, "+%d" % int(amount))
	play_squash(Vector2(1.1, 0.9), 0.14)

# ---------------- 精英变异（Mutation） ----------------

func _enter_mutation() -> void:
	match _eid:
		"golem":
			move_speed *= GameBalance.MUT_GOLEM_SPEED_MULT
			slam_interval = GameBalance.MUT_GOLEM_SLAM_INTERVAL
			slam_radius = GameBalance.MUT_GOLEM_SLAM_RADIUS
			slam_windup = GameBalance.MUT_GOLEM_SLAM_WINDUP
			slam_dmg_mult = GameBalance.MUT_GOLEM_SLAM_DMG_MULT
			_elite_slam_timer = 1.2
		"chilei_elite":
			charge_interval *= GameBalance.MUT_CHILEI_INTERVAL_MULT
			charge_side_bolts = GameBalance.MUT_CHILEI_SIDE_BOLTS
		"jiansha_elite":
			bolt_count = GameBalance.MUT_JIANSHA_BOLT_COUNT
			bolt_interval *= GameBalance.MUT_JIANSHA_INTERVAL_MULT
			preferred_range = GameBalance.MUT_JIANSHA_RANGE
		_:
			return
	_mutated = true
	anim_sprite.modulate = Color(1.5, 0.65, 0.6)
	play_squash(Vector2(1.3, 0.75), 0.3)
	GameManager.announcement_triggered.emit("⚠ 精英狂暴化 ⚠")
	AudioManager.play_sfx("boss_raid", 0.9, 0.85)
	GameManager.feedback(GameManager.FeedbackTier.MEDIUM)

## 波次结束时的消散：不掉落、不计数
# ---------------- 死亡与清场 ----------------

func dissolve() -> void:
	if dying:
		return
	dying = true
	set_physics_process(false)
	$CollisionShape2D.set_deferred("disabled", true)
	$Hurtbox/CollisionShape2D.set_deferred("disabled", true)
	var tw = create_tween()
	tw.set_parallel(true)
	tw.tween_property(anim_sprite, "modulate:a", 0.0, 0.4)
	tw.tween_property(anim_sprite, "scale", anim_sprite.scale * 0.6, 0.4)
	if procedural_view != null:
		tw.tween_property(procedural_view, "modulate:a", 0.0, 0.4)
		tw.tween_property(procedural_view, "scale", procedural_view.scale * 0.6, 0.4)
	tw.chain().tween_callback(queue_free)

func _die() -> void:
	if dying:
		return
	dying = true
	GameManager.register_kill(is_elite, _death_crit_kill)

	# 血蛹系：临死分裂出幼体（自爆/波末消散不触发）
	if split_count > 0 and split_scene != null and not _no_drop:
		_split_offspring()

	# 清理预警线（如果存在）
	_clear_charge_warning()
	_clear_bite_warning()
	_clear_explode_ring()
	if _elite_slam_ring != null and is_instance_valid(_elite_slam_ring):
		_elite_slam_ring.queue_free()
	_elite_slam_ring = null

	# 金蟾系：击杀额外爆金币（波末消散/自爆不算战果）
	if stone_reward > 0 and not _no_drop:
		GameManager.add_spirit_stones(stone_reward)
		DamageNumber.spawn(get_parent(), global_position + Vector2(0.0, -30.0), stone_reward, false, "+%d 金币" % stone_reward)
		AudioManager.play_sfx("gem_pickup", 0.9)

	# 击杀反馈分级震屏（死亡爆散视觉已于 2026-10-12 整体下线：击杀反馈 = 尸体塌缩 + 跳字 + 音效）
	if is_elite:
		GameManager.kick_camera(knockback_velocity, 8.5)
		# 暴击斩杀精英/首领启用 HEAVY 档（此前预留未用）：更重的创伤/顿帧/缩放冲击
		if _death_crit_kill:
			GameManager.feedback(GameManager.FeedbackTier.HEAVY)
		else:
			GameManager.feedback(GameManager.FeedbackTier.LARGE)
		AudioManager.play_sfx("enemy_death_elite", 1.0)
	else:
		# 普通妖物死亡给一记沿致命一刀方向的微冲量（2.5px），确认感极佳且不累加持续创伤（走全局限流闸）
		GameFeel.micro_kick(GameManager, knockback_velocity, 2.5)
		AudioManager.play_sfx("enemy_death", 0.90)

	var gem_count = 1 if not is_elite else 5
	if _no_drop:
		gem_count = 0
	if heal_orb_drop > 0 and gem_count > 0:
		gem_count = 0
		# 回复珠走对象池（2026-10-11，与宝石同一条路）
		var orb := HealOrb.acquire_or_new(get_parent())
		orb.global_position = global_position
		orb.heal_amount = float(heal_orb_drop)
		orb.activate()
	# 灵植夫·灵药滋生：死亡按概率额外掉一颗回复珠（与本体掉落独立，不占灵石位）
	if GameManager.heal_orb_chance > 0.0 and not _no_drop and GameManager.rng.randf() < GameManager.heal_orb_chance:
		var extra_orb := HealOrb.acquire_or_new(get_parent())
		extra_orb.global_position = global_position + Vector2(
			GameManager.rng.randf_range(-16.0, 16.0), GameManager.rng.randf_range(-16.0, 16.0))
		extra_orb.heal_amount = HealOrb.BASE_HEAL
		extra_orb.activate()
	# 裂魂铃·击杀爆炸：尸体处一记小震荡，半径 = 判定（同源），伤害随元素成长（BalanceCombat 公式）。
	# 波末消散（_no_drop）不触发：清场不算击杀战果，不该白拿爆炸链。
	var ex_base := GameManager.item_hook_sum("kill_explode")
	if ex_base > 0.0 and not _no_drop:
		var ex_radius := GameManager.item_hook_sum("kill_explode_radius")
		var ex_dmg := BalanceCombat.kill_explode_damage(ex_base, GameManager.elemental_damage) * GameManager.buff_damage_mult
		var ex_impulse := BalanceCombat.KILL_EXPLODE_IMPULSE * GameManager.knockback_mult
		for node in get_tree().get_nodes_in_group("enemies"):
			var e := node as EnemyBase
			if e == null or not is_instance_valid(e) or e.dying or e == self:
				continue
			if e.is_in_group("chests") or e.is_in_group("herbs"):
				continue
			var ex_off: Vector2 = e.global_position - global_position
			if ex_off.length() > ex_radius:
				continue
			var ex_dir := ex_off.normalized() if ex_off.length_squared() > 0.0001 else Vector2.UP
			e.take_damage(ex_dmg, ex_dir * ex_impulse)
		JuiceEffect.spawn_shockwave(get_parent(), global_position, ex_radius, GameStyle.GOLD_EDGE, 0.25)
	for i in range(gem_count):
		# 宝石走对象池（2026-10-10 第 6 波卡顿优化）：击杀高频 instantiate/queue_free 归零
		var gem := AstralGem.acquire_or_new(gem_scene, get_tree().current_scene)
		var offset = Vector2.ZERO if gem_count == 1 else Vector2(GameManager.rng.randf_range(-24.0, 24.0), GameManager.rng.randf_range(-24.0, 24.0))
		gem.global_position = global_position + offset
		gem.exp_value = exp_reward
		gem.is_gold = is_elite   ## 金宝视觉统一由 is_gold 驱动（灯色在 _update_visual 里跟色）
		if is_elite:
			gem.exp_value = 8
		gem.activate()

	set_physics_process(false)
	$CollisionShape2D.set_deferred("disabled", true)
	$Hurtbox/CollisionShape2D.set_deferred("disabled", true)
	# 尸体停帧后 _tick_hit_fx / _tick_hit_visuals 都不再跑：闪白、挤压、受击微反冲一律就地归位，
	# 别让尸体挂着半截闪白或歪着半格消散
	_squash_t = 0.0
	juice_scale = Vector2.ONE
	_flash_t = 0.0
	_flash_swap_t = 0.0
	_hit_jiggle_offset = Vector2.ZERO
	anim_sprite.position = Vector2.ZERO
	if procedural_view != null:
		procedural_view.position = Vector2.ZERO
	if hit_flash_mat != null:
		hit_flash_mat.set_shader_parameter("flash_modifier", 0.0)

		# 死灭动画：先微幅膨胀（Anticipation）再塌缩消散
		var tw = create_tween()
		tw.tween_property(anim_sprite, "scale", anim_base_scale * Vector2(1.28, 1.28), 0.045)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		if procedural_view != null:
			tw.parallel().tween_property(procedural_view, "scale", anim_base_scale * Vector2(1.28, 1.28), 0.045)\
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.set_parallel(true)
		tw.tween_property(anim_sprite, "scale", Vector2.ZERO, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.tween_property(anim_sprite, "modulate:a", 0.0, 0.14)
		if procedural_view != null:
			tw.tween_property(procedural_view, "scale", Vector2.ZERO, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
			tw.tween_property(procedural_view, "modulate:a", 0.0, 0.14)
		# 尸体不再沿击退方向滑出：致命一刀既已击杀，就不该再有击退位移 ——
		# 原地塌缩才是「这一下打死了」的读数（旧斩杀击飞会在消散中把尸体推出最多 42px）
		tw.chain().tween_callback(queue_free)
