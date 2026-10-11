extends Node

## 全局状态中枢：经济（灵石）、属性加点、武器持有与合成、波次推进、商店货架

signal player_hp_changed(current_hp: float, max_hp: float)
signal player_exp_changed(current_exp: int, target_exp: int, level: int)
signal player_leveled_up(level: int)
signal stats_updated(kills: int, game_time: float, spirit_stones: int)
signal game_over_triggered(victory: bool)
signal upgrade_applied(upgrade_id: String)
signal announcement_triggered(text: String)
signal weapons_updated(weapons: Array)
signal wave_changed(wave_number: int)
signal shop_opened
signal shop_closed
## 波后悟道结算（升级不再打断战斗，攒到回合结束统一加点）
signal alloc_opened
signal alloc_finished
signal pending_points_changed(pending: int)
signal screen_damage_pulsed(color: Color, duration: float)
signal boss_hp_changed(current_hp: float, max_hp: float, boss_title: String)
signal boss_defeated(boss_title: String)
signal achievements_unlocked(ach_ids: Array)

## 打击感分级。顿帧/缩放冲击按档给，**震屏（创伤）只发给"值得看的节点"**：
## 玩家受创、精英与首领的登场/震地/伏诛、界碑聚灵阵、落雷命中。
## 普通命中与普通小怪死亡一律不许走这里（高频事件会把创伤顶满，镜头就一直摇）——
## 兜底见 GameBalance「打击感：镜头创伤」段与 SmoothCamera 的每秒预算。
enum FeedbackTier { SMALL, MEDIUM, LARGE, HEAVY }

const VICTORY_WAVE: int = 20
## 灵田可活动范围的半径（地图地砖 ±2400，超出边界的区域会被界碑拦下）
const MAP_HALF_EXTENT: float = 680.0

## 每次刷新给几个候选：悟道结算与灵石阁货架同一档（2026-10-09 用户指令「改成 5 个」）
const UPGRADE_OFFER_COUNT: int = 5
const SHOP_BASE_SLOTS: int = 5
## 每回合悟道结算的免费刷新次数，用完按商店重掷同一条价格线扣灵石
const ALLOC_FREE_REROLLS: int = 1

## 属性上限（防数值失控）
const DODGE_CAP: float = 0.6          ## 身法闪避硬上限
const CRIT_RATE_CAP: float = 0.75     ## 暴击率软上限
const ATTACK_SPEED_FLOOR: float = 0.3 ## 施法间隔下限（攻速加点的地板，防止叠成连发）
const LIFESTEAL_MAX_PER_SEC: int = 3  ## 噬元每秒最多触发次数（防高频武器无限续航）
const HARVEST_GROWTH_WAVE_CAP: int = 16  ## 灵韵复利增长截止波次

## 可注入随机源：局内自动播种；单测里 `GameManager.rng.seed = N` 后商店/抽取即可确定性复现。
## 全项目凡是「玩法相关」的随机都必须走它，不要用全局 randf()，否则测试无法钉死结果。
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

## 从数组里等概率取一个（走 rng，不走 Array.pick_random 的全局随机，保证可测）
func rng_pick(pool: Array) -> Variant:
	if pool.is_empty():
		return null
	return pool[rng.randi() % pool.size()]

var player: Node2D = null
var joystick = null
var main_camera: Camera2D = null
var wave_spawner: Node = null

# 敌人活体登记（2026-10-11）：EnemyBase 在 _ready/_exit_tree 进出。
# 高频消费方（鼓妖光环每 0.25s、蛛母/影魅/Boss 的召唤上限、刷怪口容量）改读这里，
# 不再各自 get_nodes_in_group("enemies") 构造全组数组；"enemies" 组保留给低频遍历与测试。
var live_enemies: Array = []   ## 当前在场敌人（含濒死未清的，语义与 "enemies" 组一致）
var enemy_count: int = 0       ## live_enemies.size() 的计数镜像

func register_enemy(e: Node) -> void:
	live_enemies.append(e)
	enemy_count = live_enemies.size()

func unregister_enemy(e: Node) -> void:
	live_enemies.erase(e)
	enemy_count = live_enemies.size()

# 友军灵兽登记（2026-10-11 祭坛强化）：SpiritBeast 在 _ready/_exit_tree 进出。
# 敌人嘲讽目标选择（EnemyBase._taunt_target）读这里；语义与 live_enemies 一致。
# 灵兽只在 "allies" 组，绝不进 enemies/turrets/gems/chests —— 那四组波末会被清场。
var live_allies: Array = []   ## 当前在场友方灵兽
var ally_count: int = 0       ## live_allies.size() 的计数镜像

func register_ally(a: Node) -> void:
	live_allies.append(a)
	ally_count = live_allies.size()

func unregister_ally(a: Node) -> void:
	live_allies.erase(a)
	ally_count = live_allies.size()

# 危险度（仿土豆兄弟 Danger 0~5）：通关当前最高档解锁下一档，落盘 user://progress.cfg
var danger_level: int = 0          ## 本局危险度（开始菜单选择，reset_run 不动它）
var max_danger_unlocked: int = 0   ## 已解锁的最高危险度
var start_in_endless: bool = false ## 从主菜单直接开启无尽试炼（reset_run 不动它）
const PROGRESS_PATH := "user://progress.cfg"

# 局外成就解锁与生涯统计系统（仿土豆兄弟纯成就解锁）
var unlocked_cultivators: Array = []   ## 已解锁修士 ID 列表
var unlocked_items: Array = []         ## 已解锁法宝 ID 列表
var unlocked_achievements: Array = []  ## 已达成的成就 ID 列表
var career_stats: Dictionary = {
	"total_runs": 0,
	"total_wins": 0,
	"total_kills": 0,
	"best_wave": 0,
	"best_kills": 0,
	"total_stones": 0,
	"total_time": 0.0,
}
var cultivator_best_danger: Dictionary = {}  ## 每位修士通关过的最高危险度 {cultivator_id: danger_int}
var run_history: Array = []                  ## 最近 10 局历史战报列表
var last_run_new_achievements: Array = []    ## 本局刚刚新达成的成就 ID（供结算弹窗展示）

# 道统功名与渡劫实录（2026-10-10 修仙志升级，均局外持久化，不进 reset_run）
var cultivator_records: Dictionary = {}   ## 每位修士生涯档案 {cid: {runs, wins, endless_best_wave, best_kills}}
var victory_log: Array = []               ## 渡劫成功战报快照（新到旧，上限 VICTORY_LOG_CAP）
var last_run_new_records: Array = []      ## 本局刷新的纪录文案（供结算弹窗展示）
const VICTORY_LOG_CAP: int = 50           ## 渡劫实录保留条数上限（控存档体积）

# 单局峰值追踪（供成就判定）
var peak_stones: int = 0
var peak_dodge: float = 0.0
var peak_harvest: float = 0.0

func _ready() -> void:
	_load_progress()
	if DisplayServer.get_name() == "headless" and not Engine.is_editor_hint():
		call_deferred("_setup_headless_guard")

## 无头模式守护：防止测试或工具场景因语法错误/遗漏 quit() 导致 Godot 进程永久挂起
func _setup_headless_guard() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var cs := tree.current_scene
	if cs != null and cs.get_script() == null:
		printerr("[HEADLESS_GUARD] 场景根脚本加载失败 (%s)，已自动终止无头进程以防死循环。" % cs.scene_file_path)
		tree.quit(1)
		return
	await tree.create_timer(45.0, true, false, true).timeout
	var cur := tree.current_scene
	var path := cur.scene_file_path if cur != null else "unknown"
	printerr("[HEADLESS_GUARD] 无头模式运行超过 45s 未退出 (%s)，自动强制终止。" % path)
	tree.quit(124)

func _load_progress() -> void:
	ProgressStore.load_into(self)

func _save_progress() -> void:
	ProgressStore.save_from(self)

## 检查修士是否已解锁
func is_cultivator_unlocked(cid: String) -> bool:
	return cid in unlocked_cultivators

## 检查法宝是否已解锁入池
func is_item_unlocked(item_id: String) -> bool:
	return item_id in unlocked_items

## 检查成就是否已达成
func is_achievement_unlocked(ach_id: String) -> bool:
	return ach_id in unlocked_achievements

## 查询某位修士已通关的最高危险度（未通关返回 -1）
func get_cultivator_best_danger(cid: String) -> int:
	return int(cultivator_best_danger.get(cid, -1))

## 查询某位修士的生涯档案（无记录返回零值字典）
func get_cultivator_record(cid: String) -> Dictionary:
	var rec: Dictionary = cultivator_records.get(cid, {})
	return {
		"runs": int(rec.get("runs", 0)),
		"wins": int(rec.get("wins", 0)),
		"endless_best_wave": int(rec.get("endless_best_wave", 0)),
		"best_kills": int(rec.get("best_kills", 0)),
	}

## 选择危险度：不允许选未解锁的档位
func set_danger(d: int) -> void:
	danger_level = clampi(d, 0, max_danger_unlocked)

## 设置是否从主菜单直接进入无尽试炼
func set_start_in_endless(enabled: bool) -> void:
	start_in_endless = enabled

## 通关当前最高档 → 解锁下一档（打旧档不算数，防刷低档解锁）
func _maybe_unlock_danger() -> void:
	if danger_level >= max_danger_unlocked and max_danger_unlocked < GameBalance.DANGER_MAX:
		max_danger_unlocked += 1
		announcement_triggered.emit("✦ 难度「%d」已解锁 ✦" % max_danger_unlocked)

var kills: int = 0
var game_time: float = 0.0
var spirit_stones: int = 0
var level: int = 1
var experience: int = 0
var experience_to_next: int = GameBalance.EXP_FIRST_LEVEL
var is_game_over: bool = false

## 待加点数：升几级攒几点，回合结束统一结算（战斗中不弹面板）
var pending_upgrade_points: int = 0

# 波次
var wave_number: int = 0
var endless_mode: bool = false
var run_started: bool = false

## 跨场景路由标记：局内「重新开始 / 再战一局」重载场景前置真，
## Main._ready 消费后跳过主菜单直落选角界面（不在 reset_run 里清，避免先于消费被抹掉）
var restart_to_select: bool = false

# 玩家属性（加点系统）
var weapon_damage_mult: float = 1.0
var melee_damage: float = 0.0       ## 近战伤害：加成所有近战挥扫法器
var ranged_damage: float = 0.0      ## 远程伤害：加成所有飞射弹道法器
var elemental_damage: float = 0.0   ## 元素伤害：加成符箓、雷法及灼烧/剧毒跳字伤害
var engineering_damage: float = 0.0 ## 御灵伤害：加成所有环绕护体灵宝
var attack_speed_mult: float = 1.0
var move_speed_mult: float = 1.0
var pickup_range_mult: float = 1.0
var attack_range_mult: float = 1.0
var armor: float = 0.0
var hp_regen: float = 0.0
var crit_rate: float = 0.05
var crit_mult: float = 1.5
var dodge: float = 0.0        ## 身法：闪避概率（硬上限 DODGE_CAP）
var lifesteal: float = 0.0    ## 噬元：命中回复 1 点气血的概率
var luck: float = 0.0         ## 福缘：提升高稀有度悟道与商店亲和权重
var harvest: float = 0.0      ## 灵韵：每波结束无偿获得等额灵石+修为，并自我复利
var xp_gain_mult: float = 1.0 ## 悟性：修为获取倍率（只放大修为，不放大灵石）
var knockback_mult: float = 1.0 ## 震退：法器击退力度倍率
var elite_damage: float = 0.0 ## 斩将：对精英/Boss 的额外伤害加成
var free_rerolls: int = 0     ## 通玄：每波免费重掷货架次数
var element_damage: Dictionary = {}  ## 五行真解：{元素 tag(String): 伤害加成(float)}
var locked_upgrades: Array = []  ## 被角色负面代偿锁死的加点项 id（UpgradeData 过滤用）

# 修士流派（角色）特性
var cultivator_id: String = ""
var thorns_pct: float = 0.0        ## 石岳反震：按敌方攻击力比例反弹
var spirit_threshold_adj: int = 0  ## 符阵灵童：御灵羁绊门槛下移
var dodge_cap_bonus: float = 0.0   ## 魅影：闪避硬上限上移（上限 = DODGE_CAP + 本值）
var weapon_slots_override: int = 0 ## 独臂刀圣：上阵槽位上限覆盖（0 = 用 WeaponData.MAX_SLOTS）
var enemy_count_mult: float = 1.0  ## 狂战蛮修：妖潮规模倍率（WaveSpawner 消费）
var harvest_decay: float = 0.0     ## 狂战蛮修：每波灵韵流失点数
var xp_require_mult: float = 1.0   ## 夺舍散人：升级修为需求倍率
var item_price_mult: float = 1.0   ## 多宝道人：法宝价格乘区（叠加在商店价格系数之上）
var shop_slots_bonus: int = 0      ## 多宝道人：货架格数加成
var contraption_threshold_adj: int = 0  ## 机关师：机关羁绊门槛下移
var stone_interest_rate: float = 0.0    ## 守财奴：波末灵石结息比率
var stone_interest_cap: int = 15        ## 守财奴：波末灵石结息上限
var on_hit_damage_bonus: float = 0.0    ## 嗜血魔修：受击单层增伤
var on_hit_damage_cap_stacks: int = 10  ## 嗜血魔修：增伤最大层数
var on_hit_damage_stacks: int = 0
var on_hit_damage_timer: float = 0.0
var total_damage_taken_count: int = 0   ## 单局累计受击次数（嗜血魔修解锁判定）
var total_hp_healed: float = 0.0        ## 单局累计回复气血量（药王解锁判定）
var max_concurrent_summons: int = 0     ## 单局同时上阵机关/御灵峰值（机关师解锁判定）
var _exp_chain: int = GameBalance.EXP_FIRST_LEVEL  ## 未折算的修为门槛链（xp_require_mult 只作用于显示/判定值）

# 随行神通（技能）：选技能界面写 pending，start_run 转正；buff_* 是技能短时增益乘区，
# 与加点/羁绊乘区隔离，到期由 Player 精确回 1.0，互不污染
var pending_skill_id: String = "dash"  ## 选人流程里选定的技能（默认缩地成寸，直接 start_run 也有技能可用）
var active_skill_id: String = ""       ## 本局生效的技能 id
var buff_move_speed_mult: float = 1.0  ## 神行术短时移速乘区（Player._physics_process 消费）
var buff_attack_speed_mult: float = 1.0 ## 疾风咒短时施法间隔乘区（FloatingWeapon._perform_attack 消费）

# 武器羁绊加成（由 recalc_synergies 每波/换装时重算）
var stat_bonus_pierce: int = 0      ## 升级/法宝：弹丸额外穿透基础
var synergy_bonus_pierce: int = 0   ## 符箓羁绊：弹丸额外穿透增量
var bonus_pierce: int = 0           ## 弹丸额外穿透合计（stat + synergy）
var synergy_damage_mult: float = 1.0  ## 广域/离火羁绊：额外伤害乘区
var synergy_range_mult: float = 1.0   ## 剑系羁绊：额外攻击范围乘区
var synergy_haste_mult: float = 1.0   ## 雷法/玄水羁绊：额外攻速乘区
var synergy_max_hp_bonus: float = 0.0 ## 御灵羁绊：额外气血上限
var synergy_engineering_damage: float = 0.0 ## 御灵羁绊：额外召唤伤害
var synergy_crit_rate: float = 0.0    ## 锐金羁绊：额外暴击率
var synergy_crit_mult: float = 0.0    ## 锐金羁绊：额外暴击伤害
var synergy_hp_regen: float = 0.0     ## 青木羁绊：额外气血回复
var synergy_lifesteal: float = 0.0    ## 青木羁绊：额外吸血
var synergy_move_speed_mult: float = 0.0 ## 玄水羁绊：额外移速加成
var synergy_burn_mult: float = 1.0    ## 离火羁绊：额外灼烧伤害倍率
var synergy_armor: float = 0.0        ## 厚土羁绊：额外护甲
var synergy_knockback_mult: float = 1.0 ## 厚土羁绊：额外受击震退力倍率
var synergy_contraption_mult: float = 1.0 ## 机关羁绊：机关法器伤害乘区

var _lifesteal_procs: int = 0
var _lifesteal_window: float = 0.0
var _hud_tick: float = 0.0  ## HUD 计时刷新节流：只走时间显示，事件驱动的数值变化各自单独 emit

# 商店
var shop_offers: Array = []
var reroll_cost: int = 2
var reroll_count: int = 0          ## 本波已重掷次数（费用递增，跨波重置）
var reroll_free_left: int = 0      ## 本波剩余免费重掷次数（roll_shop(new_wave) 时按 free_rerolls 重置）
var shop_price_mult: float = 1.0   ## 商店价格系数（角色特性用，如散修 8 折）
var shop_tag_filter: Array = []    ## 非空时这些 tag 法器权重大幅提升，其余法器仍以低概率漏出（剑痴等流派偏好）
var _no_main_tag_waves: int = 0    ## 连续未刷出主流派法器的波数（保底计数）

# 波后悟道结算会话（与商店重掷同一把尺子：免费次数用完才扣灵石，价格随波次与已刷次数上升）
var alloc_offers: Array[Dictionary] = []
var alloc_points_total: int = 0   ## 本次结算开局时攒下的点数（面板写「待加点 2/共 3」用）
var alloc_reroll_cost: int = 2
var alloc_reroll_count: int = 0
var alloc_reroll_free_left: int = 0

## 已持有法宝（被动道具）的 id 列表：无限持有、买即生效，数据定义见 ItemData
var items: Array = []

# 武器库存：上阵 = 悬浮法器节点 + 灵蝶星级数组；背包 = 仅用于合成/出售的仓库
var drones: Array = []   # 上阵灵蝶的星级列表，如 [1, 2]
var stash: Array = []    # 背包，元素 {id: String, star: int}

# 本局历史悟道加点记录
var upgrade_history: Array[Dictionary] = []
var upgrade_counts: Dictionary = {}

func reset_run() -> void:
	# 70+ 单局成员的清零表在 RunReset（显式类型化赋值），新增成员记得去那边补默认值
	RunReset.reset(self)

func _process(delta: float) -> void:
	if on_hit_damage_timer > 0.0:
		on_hit_damage_timer -= delta
		if on_hit_damage_timer <= 0.0:
			on_hit_damage_stacks = 0

	if not is_game_over and not get_tree().paused and player != null:
		game_time += delta
		_lifesteal_window += delta
		if _lifesteal_window >= 1.0:
			_lifesteal_window = 0.0
			_lifesteal_procs = 0
		# HUD 只关心「斩妖/灵石/计时」三个读数：计时按 0.2s 节流即可（显示精度是整秒），
		# 数值真正变化时由各事件函数自己 emit，不必每帧重画 60 次。
		_hud_tick += delta
		if _hud_tick >= 0.2:
			_hud_tick = 0.0
			stats_updated.emit(kills, game_time, spirit_stones)

# ---------------- 经验 / 灵石 ----------------

func add_experience(amount: int) -> void:
	if is_game_over:
		return
	# 悟性只放大修为，灵石始终按原价入账（否则经济会双重受益）
	experience += int(round(float(amount) * xp_gain_mult))
	spirit_stones += amount
	AudioManager.play_sfx("gem_pickup")

	# 连升音阶：一次吃大经验球跨多级时音高逐级抬升（同 gem_pickup 的连击升调手感）；
	# 首级不传 pitch，保住音效本来的随机变体
	var levels_gained := 0
	while experience >= experience_to_next:
		experience -= experience_to_next
		level += 1
		_exp_chain = GameBalance.exp_to_next(_exp_chain)
		# 夺舍散人这类需求倍率只折算判定值，链条本身保持原曲线（避免倍率逐层复利）
		experience_to_next = maxi(1, int(round(float(_exp_chain) * xp_require_mult)))
		if levels_gained == 0:
			AudioManager.play_sfx("level_up")
		else:
			AudioManager.play_sfx("level_up", 1.0, 1.0 + 0.08 * float(mini(levels_gained, 4)))
		levels_gained += 1
		# 升级不再当场弹面板打断战斗：升 1 级攒 1 点，回合结束统一结算
		pending_upgrade_points += 1
		pending_points_changed.emit(pending_upgrade_points)
		player_leveled_up.emit(level)

	player_exp_changed.emit(experience, experience_to_next, level)
	stats_updated.emit(kills, game_time, spirit_stones)

func add_spirit_stones(amount: int) -> void:
	spirit_stones += amount
	touch_peak_stones()
	stats_updated.emit(kills, game_time, spirit_stones)

func register_kill(is_elite: bool = false) -> void:
	kills += 1
	if is_elite:
		spirit_stones += GameBalance.ELITE_STONE_BONUS
		touch_peak_stones()
	stats_updated.emit(kills, game_time, spirit_stones)

## 单局灵石峰值记账（成就判定用）：所有改 spirit_stones 后想记峰值的地方都走这个
func touch_peak_stones() -> void:
	if spirit_stones > peak_stones:
		peak_stones = spirit_stones

# ---------------- 属性加点 ----------------

## 加点：幅度全部来自 UpgradeData 每项的 "apply" 表，这里只规定「往哪个字段加、有没有上限」。
## 这样「数值」和「卡片文案」同源，调参只改数据表一处（历史上二者分家，改一项要动两个文件）。
func apply_upgrade(upgrade_id: String) -> void:
	var def := UpgradeData.get_upgrade_def(upgrade_id)
	_apply_stat_fields(def.get("apply", {}), upgrade_id)

	var prev_count: int = int(upgrade_counts.get(upgrade_id, 0)) + 1
	upgrade_counts[upgrade_id] = prev_count
	upgrade_history.append({
		"id": upgrade_id,
		"title": def.get("title", upgrade_id),
		"rarity": def.get("rarity", "common"),
		"rarity_label": def.get("rarity_label", "普通"),
		"icon": def.get("icon", ""),
		"desc": def.get("desc", ""),
		"border_color": def.get("border_color", Color.WHITE),
		"level": level,
		"time": game_time,
		"count": prev_count,
	})
	upgrade_applied.emit(upgrade_id)

## 属性字段统一落地入口：悟道加点（apply_upgrade）与法宝（add_item）共用同一条链路，
## 白名单与落地规则在 StatSystem（2026-10-11 抽离）
func _apply_stat_fields(apply: Dictionary, source: String) -> void:
	StatSystem.apply_stat_fields(self, apply, source)

## 抽一批悟道候选。UpgradeData 是纯函数层、不读单例，所以这里负责把当前局面打包成 ctx 传过去。
## 默认一次给 UPGRADE_OFFER_COUNT（5）个：候选太少时「刷新」没意义（2026-10-09 用户指令）。
func roll_upgrades(count: int = UPGRADE_OFFER_COUNT) -> Array[Dictionary]:
	return UpgradeData.get_random_upgrades(count, {
		"luck": luck,
		"locked_upgrades": locked_upgrades,
		"counts": upgrade_counts,
		"rng": rng,
	})

# ---------------- 波后悟道结算（委托 AllocSession） ----------------

func has_pending_upgrades() -> bool:
	return pending_upgrade_points > 0

func open_alloc_session() -> void:
	AllocSession.open_alloc_session(self)

func force_end_alloc(reason: String) -> void:
	AllocSession.force_end_alloc(self, reason)

func roll_alloc_offers() -> void:
	AllocSession.roll_alloc_offers(self)

func take_alloc_upgrade(index: int) -> bool:
	return AllocSession.take_alloc_upgrade(self, index)

func reroll_alloc() -> bool:
	return AllocSession.reroll_alloc(self)

func alloc_reroll_label() -> String:
	return AllocSession.alloc_reroll_label(self)

func can_reroll_alloc() -> bool:
	return AllocSession.can_reroll_alloc(self)

## 属性面板聚合口径在 StatBreakdown（ui/stats，2026-10-11 迁出）：渲染层只读模型
func get_stat_breakdown() -> Dictionary:
	return StatBreakdown.breakdown(self)

func get_effective_armor() -> float:
	return armor + synergy_armor

func get_crit_rate() -> float:
	return minf(crit_rate + synergy_crit_rate, CRIT_RATE_CAP)

func get_effective_dodge() -> float:
	return minf(dodge, DODGE_CAP + dodge_cap_bonus)

## 上阵法器槽位上限：独臂刀圣这类角色会覆盖（0 = 用 WeaponData.MAX_SLOTS）
func max_weapon_slots() -> int:
	return weapon_slots_override if weapon_slots_override > 0 else WeaponData.MAX_SLOTS

## 多法器神识分流系数：按当前上阵法器总数（悬浮法器 + 环绕灵物）计算单把直击伤害折算
func get_multi_weapon_damage_mult() -> float:
	return GameBalance.multi_weapon_damage_mult(slots_used())

## 五行真解：某件法器吃到的元素伤害乘区（按 WeaponData.element_of 取对应元素加成）
func element_damage_mult(w_id: String) -> float:
	if element_damage.is_empty():
		return 1.0
	return 1.0 + float(element_damage.get(WeaponData.element_of(w_id), 0.0))

## 法器击退力度：玩家震退属性 × 厚土羁绊倍率
func knockback_force(base: float) -> float:
	return base * knockback_mult * synergy_knockback_mult

## 法器震退向量：方向走 GameBalance.knock_dir（永不把敌人往玩家身上推），力度走 knockback_force。
## source = 施力点（落雷点 / 法器自身 / 灵宝自身），enemy_pos = 受击敌人位置。
## 玩家不在场（单测、局外预览）时把玩家位置退回施力点 = 纯径向旧行为，不会出 NaN。
## 各法器只许经这一个出口拿方向，别再自己写 (enemy - source).normalized()。
func knockback_vec(source: Vector2, enemy_pos: Vector2, base: float) -> Vector2:
	var player_pos: Vector2 = source if player == null else player.global_position
	return GameBalance.knock_dir(source, enemy_pos, player_pos) * knockback_force(base)

## 斩将：对精英/Boss（is_elite 标记）的额外伤害乘区，普通妖兽不受影响
func elite_damage_mult_for(enemy: Variant) -> float:
	if elite_damage <= 0.0 or enemy == null:
		return 1.0
	return 1.0 + elite_damage if enemy.get("is_elite") == true else 1.0

func get_player_stat_dict() -> Dictionary:
	var cur_hp := 120.0
	var max_hp := 120.0
	if player != null and is_instance_valid(player):
		cur_hp = player.current_health
		max_hp = player.max_health
	return {
		"armor": armor + synergy_armor,
		"max_hp": max_hp,
		"current_hp": cur_hp,
		"hp_regen": hp_regen + synergy_hp_regen,
		"lifesteal": lifesteal + synergy_lifesteal,
		"crit_rate": get_crit_rate(),
		"crit_mult": crit_mult + synergy_crit_mult,
		"attack_speed_mult": attack_speed_mult * synergy_haste_mult,
		"move_speed_mult": move_speed_mult + synergy_move_speed_mult,
		"weapon_damage_mult": weapon_damage_mult * synergy_damage_mult,
		"attack_range_mult": attack_range_mult * synergy_range_mult,
		"melee_damage": melee_damage,
		"ranged_damage": ranged_damage,
		"elemental_damage": elemental_damage,
		"engineering_damage": engineering_damage + synergy_engineering_damage,
		"harvest": harvest,
	}

func get_weapon_stat_bonus(w_id: String, star: int = 1) -> float:
	var def := WeaponData.get_def(w_id)
	var scalings: Dictionary = def.get("stat_scalings", {})
	if scalings.is_empty():
		return 0.0
	return GameBalance.weapon_stat_bonus(scalings, get_player_stat_dict(), star)

## 命中时尝试噬元回血（每秒最多触发 LIFESTEAL_MAX_PER_SEC 次，防高频武器无限续航）
func try_lifesteal() -> void:
	var total_ls := lifesteal + synergy_lifesteal
	if total_ls <= 0.0 or player == null or not is_instance_valid(player):
		return
	if _lifesteal_procs >= LIFESTEAL_MAX_PER_SEC:
		return
	if rng.randf() < total_ls:
		_lifesteal_procs += 1
		player.heal(1.0, true)

## 波间灵韵结算：无偿发放等额灵石+修为；狂战蛮修的杀气让灵韵每波流失；随后灵韵自我复利（增长截止波次见常量区）
## budget_comp_exp：刷怪预算未花完部分的折算经验补差（WaveSpawner 传入，BalanceEconomy.budget_compensation_exp），
## 与灵韵一并到账、同一句播报 —— 减潮不减收入，购买力与旧口径持平
func apply_harvest(budget_comp_exp: int = 0) -> void:
	var gain := GameBalance.harvest_gain(harvest)
	var total_gain := gain + maxi(0, budget_comp_exp)
	if total_gain > 0:
		add_experience(total_gain)
		announcement_triggered.emit("✦ 收益到账 · 金币与经验 +%d ✦" % total_gain)
	if harvest_decay > 0.0:
		harvest = maxf(0.0, harvest - harvest_decay)
	harvest = GameBalance.harvest_next(harvest, wave_number, HARVEST_GROWTH_WAVE_CAP)
	# 守财奴金币结息 hook
	if stone_interest_rate > 0.0 and spirit_stones > 0:
		var interest := mini(stone_interest_cap, int(floor(float(spirit_stones) * stone_interest_rate)))
		if interest > 0:
			spirit_stones += interest
			stats_updated.emit(kills, game_time, spirit_stones)
			announcement_triggered.emit("✦ 金山结息 · 获得 %d 枚灵石 ✦" % interest)
	# 回春葫芦等法宝的波末回血 hook
	var heal_pct := item_hook_sum("wave_heal_pct")
	if heal_pct > 0.0 and player != null and is_instance_valid(player) and player.has_method("heal"):
		player.heal(player.max_health * heal_pct)

# ---------------- 法宝（被动道具） ----------------

func has_item(item_id: String) -> bool:
	return item_id in items

## 购入法宝：属性走 _apply_stat_fields（与悟道同一条链路）；unique 法宝重复购买会被拒绝
func add_item(item_id: String) -> bool:
	var def := ItemData.get_def(item_id)
	if def.is_empty():
		return false
	if bool(def.get("unique", false)) and has_item(item_id):
		return false
	items.append(item_id)
	_apply_stat_fields(def.get("apply", {}), "item:" + item_id)
	return true

## 消耗一件法宝（替死傀儡这类一次性机制用），返回是否真的消耗了
func consume_item(item_id: String) -> bool:
	var i := items.find(item_id)
	if i < 0:
		return false
	items.remove_at(i)
	return true

## 同名字段 hook 的叠加求和（如多件回春葫芦的 wave_heal_pct 相加）
func item_hook_sum(hook: String) -> float:
	var total := 0.0
	for item_id in items:
		total += float(ItemData.get_def(item_id).get(hook, 0.0))
	return total

## 替死傀儡：致死一击时消耗它免死并回半血。Player.take_damage 在扣血归零后调用
func try_revive() -> bool:
	if not consume_item("tisi_kuilei"):
		return false
	if player != null and is_instance_valid(player):
		player.current_health = player.max_health * 0.5
		player.invulnerable_time = 2.0
		player_hp_changed.emit(player.current_health, player.max_health)
	announcement_triggered.emit("✦ 替身娃娃碎裂 · 死里逃生 ✦")
	AudioManager.play_sfx("level_up", 1.0)
	return true

# ---------------- 武器系统 ----------------

func start_run(starter_id: String) -> void:
	run_started = true
	endless_mode = start_in_endless
	_apply_cultivator()
	# 随行神通转正：选择界面写的是 pending_skill_id；id 失效时回退缩地成寸
	active_skill_id = pending_skill_id if SkillData.get_def(pending_skill_id).size() > 0 else "dash"
	add_weapon(starter_id)
	if endless_mode:
		announcement_triggered.emit("✦ 无尽模式 · 战至终局 ✦")
	else:
		announcement_triggered.emit("✦ 生存战斗 · 击杀敌人 ✦")

## 开局应用修士流派的正负代偿（规则在 CultivatorSystem，2026-10-11 抽离）
func _apply_cultivator() -> void:
	CultivatorSystem.apply_cultivator(self)

## 修士特性的单武器伤害系数（tag 加成 × 非灵蝶/非机关惩罚 + 受击增伤）
func cultivator_damage_mult(w_id: String) -> float:
	return CultivatorSystem.damage_mult(self, w_id)

func on_player_hit(_amount: float) -> void:
	total_damage_taken_count += 1
	if on_hit_damage_bonus > 0.0:
		on_hit_damage_stacks = mini(on_hit_damage_cap_stacks, on_hit_damage_stacks + 1)
		on_hit_damage_timer = 5.0

# ---------------- 武器系统（委托 WeaponInventory） ----------------

func _drone_id(item) -> String:
	return WeaponInventory.drone_id(item)

func _drone_star(item) -> int:
	return WeaponInventory.drone_star(item)

func slots_used() -> int:
	return WeaponInventory.slots_used(self)

func add_weapon(w_id: String, star: int = 1) -> bool:
	return WeaponInventory.add_weapon(self, w_id, star)

func count_copies(w_id: String, star: int) -> int:
	return WeaponInventory.count_copies(self, w_id, star)

func _count_mergeable_copies(w_id: String, star: int, keep: Dictionary) -> int:
	return WeaponInventory.count_mergeable_copies(self, w_id, star, keep)

func merge_weapon(w_id: String, star: int, keep: Dictionary) -> bool:
	return WeaponInventory.merge_weapon(self, w_id, star, keep)

func get_weapons_summary() -> Array:
	return WeaponInventory.get_weapons_summary(self)

func notify_weapons_updated(weapons: Array) -> void:
	recalc_synergies()
	var cur_summons: int = drones.size()
	if player != null and player.has_method("get_equipped_weapons_data"):
		for w in player.get_equipped_weapons_data():
			var beh := int(WeaponData.get_def(w.get("id", "")).get("behavior", -1))
			if beh == WeaponData.Behavior.TURRET or beh == WeaponData.Behavior.DRONE:
				cur_summons += 1
	max_concurrent_summons = maxi(max_concurrent_summons, cur_summons)
	weapons_updated.emit(weapons)

func sell_weapon(index: int) -> bool:
	return WeaponInventory.sell_weapon(self, index)

func equip_from_stash(index: int) -> bool:
	return WeaponInventory.equip_from_stash(self, index)

func unequip_to_stash(index: int) -> bool:
	return WeaponInventory.unequip_to_stash(self, index)

## 背包 → 上阵换装（上阵满时与该格互换，换下的回背包原位）：拖拽换装用
func swap_into_equipped(stash_index: int, equipped_index: int) -> bool:
	return WeaponInventory.swap_into_equipped(self, stash_index, equipped_index)

## 背包内拖拽排序
func reorder_stash(from: int, to: int) -> bool:
	return WeaponInventory.reorder_stash(self, from, to)

func sell_stash(index: int) -> bool:
	return WeaponInventory.sell_stash(self, index)

# ---------------- 流派羁绊（委托 SynergySystem） ----------------

var active_synergies: Dictionary = {}
var _applied_hp_bonus: float = 0.0

func recalc_synergies() -> void:
	SynergySystem.recalc_synergies(self)

func _apply_synergy_hp(new_bonus: float) -> void:
	SynergySystem.apply_synergy_hp(self, new_bonus)

# ---------------- 波间商店（委托 ShopSystem） ----------------

func roll_shop(new_wave: bool = false) -> void:
	ShopSystem.roll_shop(self, new_wave)

func _gen_offer(wave: int) -> Dictionary:
	return ShopSystem.gen_offer(self, wave)

func _weighted_weapon_pick() -> String:
	return ShopSystem.weighted_weapon_pick(self)

func _tag_counts() -> Dictionary:
	return SynergySystem.tag_counts(self)

func get_tag_count(tag: String) -> int:
	return int(SynergySystem.tag_counts(self).get(tag, 0))

func _main_tag() -> String:
	return SynergySystem.main_tag(self)

func _apply_main_tag_pity(wave: int) -> void:
	SynergySystem.apply_main_tag_pity(self, wave)

func toggle_lock(index: int) -> void:
	ShopSystem.toggle_lock(self, index)

func buy_offer(index: int) -> bool:
	return ShopSystem.buy_offer(self, index)

func reroll_shop() -> bool:
	return ShopSystem.reroll_shop(self)

func confirm_shop() -> void:
	ShopSystem.confirm_shop(self)

# ---------------- 流程与打击感系统（委托 GameFeel 与 ProgressStore） ----------------

var _hitstop_token: int = 0

func add_trauma(amount: float) -> void:
	GameFeel.add_trauma(self, amount)

func zoom_punch(scale_amount: float = 0.05, duration: float = 0.18) -> void:
	GameFeel.zoom_punch(self, scale_amount, duration)

func shake_camera(intensity: float = 3.5, duration: float = 0.12) -> void:
	GameFeel.shake_camera(self, intensity, duration)

func kick_camera(dir: Vector2, strength: float = 3.0) -> void:
	GameFeel.kick_camera(self, dir, strength)

func hit_stop(duration: float = 0.045, target_scale: float = 0.05) -> void:
	GameFeel.hit_stop(self, duration, target_scale)

## 小怪伏诛的微顿帧（GameFeel 内部限流）：只在 EnemyBase 判定致命一刀时调用
func kill_hit_stop() -> void:
	GameFeel.kill_hit_stop(self)

func feedback(tier: int) -> void:
	GameFeel.feedback(self, tier)

func pulse_damage_vignette(color: Color = Color(0.85, 0.12, 0.12, 0.65), duration: float = 0.22) -> void:
	GameFeel.pulse_damage_vignette(self, color, duration)

func trigger_game_over(victory: bool = false) -> void:
	if is_game_over:
		return
	Engine.time_scale = 1.0
	_hitstop_token += 1
	is_game_over = true
	if victory:
		_maybe_unlock_danger()
	_record_run_and_check_achievements(victory)
	game_over_triggered.emit(victory)

func _record_run_and_check_achievements(victory: bool) -> void:
	ProgressStore.record_run_and_check_achievements(self, victory)

func continue_endless() -> void:
	endless_mode = true
	is_game_over = false
	get_tree().paused = false
	if wave_spawner != null and wave_spawner.has_method("open_shop"):
		wave_spawner.open_shop()
