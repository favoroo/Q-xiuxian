extends Node

## 全局状态中枢：经济（金币）、属性加点、武器持有与合成、回合推进、商店货架

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
## 回合后悟道结算（升级不再打断战斗，攒到回合结束统一加点）
signal alloc_opened
signal alloc_finished
signal pending_points_changed(pending: int)
signal screen_damage_pulsed(color: Color, duration: float)
signal screen_shockwave_triggered(pos: Vector2, strength: float, duration: float)
signal boss_hp_changed(current_hp: float, max_hp: float, boss_title: String)
signal boss_defeated(boss_title: String)
signal achievements_unlocked(ach_ids: Array)
signal pets_updated(pets: Array)

## 打击感分级。顿帧/缩放冲击按档给，**震屏（创伤）只发给"值得看的节点"**：
## 玩家受创、精英与首领的登场/震地/伏诛、界碑聚灵阵、落雷命中。
## 普通命中与普通小怪死亡一律不许走这里（高频事件会把创伤顶满，镜头就一直摇）——
## 兜底见 GameBalance「打击感：镜头创伤」段与 SmoothCamera 的每秒预算。
enum FeedbackTier { SMALL, MEDIUM, LARGE, HEAVY }

const VICTORY_WAVE: int = 20
## 灵田可活动范围的半径（地图地砖 ±2400，超出边界的区域会被界碑拦下）
## 2026-10-11 缩图 680→500；2026-10-12 缩图 500→440；2026-10-15 扩图 440→560（1120×1120，面积约 +62%）；2026-10-17 缩图 560→480（960×960，面积约 -27%）：压缩跑路时间、提升局部密度，保留走位余地
const MAP_HALF_EXTENT: float = 480.0

## 每次刷新给几个候选：悟道结算与商店货架同一档（2026-10-09 用户指令「改成 5 个」）
const UPGRADE_OFFER_COUNT: int = 5
const SHOP_BASE_SLOTS: int = 5
const PET_BASE_SLOTS: int = 1         ## 基础灵兽栏位：普通角色默认 1 只，御兽师通过特性加成
## 每回合悟道结算的免费刷新次数，用完按商店重掷同一条价格线扣金币
const ALLOC_FREE_REROLLS: int = 1

## 属性上限（防数值失控）
const DODGE_CAP: float = 0.6          ## 身法闪避硬上限
const CRIT_RATE_CAP: float = 0.75     ## 暴击率软上限
const ATTACK_SPEED_FLOOR: float = 0.3 ## 施法间隔下限（攻速加点的地板，防止叠成连发）
const LIFESTEAL_MAX_PER_SEC: int = 3  ## 噬元每秒最多触发次数（防高频武器无限续航）
const HARVEST_GROWTH_WAVE_CAP: int = 16  ## 收益复利增长截止回合
# 2026-10-13 输出侧上限补全（对标土豆兄弟：生存侧早就有顶，输出侧此前全敞开）：
const CRIT_MULT_CAP: float = 2.5      ## 暴击伤害总上限（加点层 + 锐金羁绊合计，1.5 基础 +1.0 头）
const LIFESTEAL_CAP: float = 0.5      ## 噬元概率上限（频次另有 LIFESTEAL_MAX_PER_SEC 限）
const ELITE_DAMAGE_CAP: float = 1.0   ## 斩将加成上限（elite_up 4 层正好到顶）
const ELEMENT_DAMAGE_CAP: float = 0.6 ## 五行真解单系上限（同时扎住直击/灼烧/剧毒/击杀爆炸四个兑现口）
const SHOP_PRICE_FLOOR: float = 0.7   ## 道具折扣腿地板（对标土豆 Coupon 叠顶；角色价格乘区另算不夹）
## 突破古玉回合末永久成长的累计封顶（绕过 max_stacks 治理体系的口子，钉在 apply_harvest 消费处）
const WAVE_END_HP_CAP: float = 30.0
const WAVE_END_REGEN_CAP: float = 5.0
const WAVE_END_LIFESTEAL_CAP: float = 0.10

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
# 灵兽只在 "allies" 组，绝不进 enemies/turrets/gems/chests —— 那四组回合末会被清场。
var live_allies: Array = []   ## 当前在场友方灵兽
var ally_count: int = 0       ## live_allies.size() 的计数镜像

func register_ally(a: Node) -> void:
	live_allies.append(a)
	ally_count = live_allies.size()

func unregister_ally(a: Node) -> void:
	live_allies.erase(a)
	ally_count = live_allies.size()

# 危险度（D0 ~ D3 共 4 档，2026-10-20 起全部开放、不再逐档解锁）：开始菜单自由选择
var danger_level: int = 0          ## 本局危险度（开始菜单选择，reset_run 不动它）
var start_in_endless: bool = false ## 从主菜单直接开启无尽试炼（reset_run 不动它）

# 局外成就解锁与生涯统计系统（仿土豆兄弟纯成就解锁）
var unlocked_cultivators: Array = []   ## 已解锁角色 ID 列表
var unlocked_items: Array = []         ## 已解锁道具 ID 列表
var unlocked_achievements: Array = []  ## 已达成的成就 ID 列表
var career_stats: Dictionary = {
	"total_runs": 0,
	"total_wins": 0,
	"total_kills": 0,
	"best_wave": 0,
	"best_kills": 0,
	"total_stones": 0,
	"total_time": 0.0,
	# —— 单局生涯最佳（成就进度展示数据源，ProgressStore 结算时并入并落盘）——
	"best_class_counts": {},       ## {器类tag: 单局同时上阵峰值生涯最佳}
	"best_summons": 0,             ## 单局同时召唤峰值生涯最佳
	"best_element_spread": 0,      ## 单局五行同阵种数峰值生涯最佳
	"best_stones": 0,              ## 单局持有金币峰值生涯最佳
	"best_dodge": 0.0,             ## 单局有效闪避峰值生涯最佳
	"best_harvest": 0.0,           ## 单局收益峰值生涯最佳
	"best_healed": 0.0,            ## 单局累计回复峰值生涯最佳
	"best_hits_taken": 0,          ## 单局承受伤害次数峰值生涯最佳
	"best_level": 0,               ## 单局最高等级生涯最佳
	"best_danger_cleared": -1,     ## 生涯最高通关难度（-1 = 尚未通关）
	"wins_no_skill_enhance": 0,    ## 使用不契合技能通关累计次数（→ ach_style_rebel「就不听你话」）
}
var cultivator_best_danger: Dictionary = {}  ## 每位角色通关过的最高危险度 {cultivator_id: danger_int}
var cultivator_danger_clears: Dictionary = {}  ## 每位角色各难度通关位掩码 {cultivator_id: int}（位 d = 通关过难度 d）
var skin_selections: Dictionary = {}         ## 每位角色已选皮肤 {cultivator_id: skin_idx}（缺省/-1 = 原色）
var run_history: Array = []                  ## 最近 10 局历史战报列表
var last_run_new_achievements: Array = []    ## 本局刚刚新达成的成就 ID（供结算弹窗展示）

# 道统功名与渡劫实录（2026-10-10 修仙志升级，均局外持久化，不进 reset_run）
var cultivator_records: Dictionary = {}   ## 每位角色生涯档案 {cid: {runs, wins, endless_best_wave, best_kills}}
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

# ---------------- 中断续玩（2026-10-15，落盘与恢复在 RunSave） ----------------

## 战斗中自动存档间隔（秒）：波内金币/经验/血量以最后一次快照为准，本波从头重打
const AUTOSAVE_INTERVAL: float = 10.0
var _autosave_cd: float = AUTOSAVE_INTERVAL

## 应用生命周期兜底：Android 上滑杀进程/Home 键、系统返回键、桌面关窗 ——
## 这些路径没有别的存档点，同步写一份。通知不受树暂停门控，商店/悟道面板开着也收得到；
## 非局内态（没开局/已结算）由 RunSave.save_from 自行拒绝，无需在此判断。
## （Godot 4.7 无 APPLICATION_TERMINATING 通知；Android 划掉应用也不发任何通知，
## 兜底靠 PAUSED 这一根 —— 3 秒自动存已把窗口收窄到可接受）
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, \
		NOTIFICATION_WM_CLOSE_REQUEST, \
		NOTIFICATION_WM_GO_BACK_REQUEST:
			RunSave.autosave_current(self)

## 无头守护时长（秒）：兜底抓「真挂起」，不该顺手把「真在干活的慢判据」一起打死。
## 判据卡数涨上来后 45s 会变成误杀线（ManualHotzoneCheck 115 张卡 × 12 取样点实测 ~55s），
## 所以慢判据在自己的 _ready 里把本值调大即可 —— autoload 的 call_deferred 在场景 _ready
## 之后才冲刷，这条赋值赶得上。默认 45s 不变：不申报的判据仍按老时长兜底。
var headless_guard_sec: float = 45.0

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
	await tree.create_timer(headless_guard_sec, true, false, true).timeout
	var cur := tree.current_scene
	var path := cur.scene_file_path if cur != null else "unknown"
	printerr("[HEADLESS_GUARD] 无头模式运行超过 %ds 未退出 (%s)，自动强制终止。" % [int(headless_guard_sec), path])
	tree.quit(124)

func _load_progress() -> void:
	ProgressStore.load_into(self)

func _save_progress() -> void:
	ProgressStore.save_from(self)

## 检查角色是否已解锁
func is_cultivator_unlocked(cid: String) -> bool:
	return cid in unlocked_cultivators

## 检查道具是否已解锁入池
func is_item_unlocked(item_id: String) -> bool:
	return item_id in unlocked_items

## 检查成就是否已达成
func is_achievement_unlocked(ach_id: String) -> bool:
	return ach_id in unlocked_achievements

## 查询某位角色已通关的最高危险度（未通关返回 -1）
func get_cultivator_best_danger(cid: String) -> int:
	return int(cultivator_best_danger.get(cid, -1))

## 查询某位角色各难度通关位掩码（位 d = 通关过难度 d）
func get_cultivator_danger_mask(cid: String) -> int:
	return int(cultivator_danger_clears.get(cid, 0))

## 某位角色是否通关过指定难度
func is_cultivator_danger_cleared(cid: String, d: int) -> bool:
	return (get_cultivator_danger_mask(cid) & (1 << d)) != 0

## 皮肤是否已解锁：原色(-1)恒可用；主题皮肤按「该角色累计通关次数 >= tier + 1」判定。
## 2026-10-20 与难度解耦：不再看通关过哪一档，任意难度通关都记一次，攒够次数逐套解锁。
func is_skin_unlocked(cid: String, skin_idx: int) -> bool:
	if skin_idx < 0:
		return true
	var t := SkinData.get_theme(skin_idx)
	if t.is_empty():
		return false
	var wins_needed := int(t.get("tier", 0)) + 1
	return get_cultivator_record(cid).get("wins", 0) >= wins_needed

## 查询某角色当前选用的皮肤（-1 = 原色；已选皮肤若未解锁则惰性回落原色兜底）
func get_selected_skin(cid: String) -> int:
	var idx := int(skin_selections.get(cid, -1))
	if idx >= 0 and not is_skin_unlocked(cid, idx):
		return -1
	return idx

## 选用皮肤（未解锁的主题直接拒绝；原色用擦除键的方式落盘，保持存档干净）
func set_selected_skin(cid: String, skin_idx: int) -> void:
	if skin_idx >= 0 and not is_skin_unlocked(cid, skin_idx):
		return
	if skin_idx < 0:
		skin_selections.erase(cid)
	else:
		skin_selections[cid] = skin_idx
	_save_progress()

## 查询某位角色的生涯档案（无记录返回零值字典）
func get_cultivator_record(cid: String) -> Dictionary:
	var rec: Dictionary = cultivator_records.get(cid, {})
	return {
		"runs": int(rec.get("runs", 0)),
		"wins": int(rec.get("wins", 0)),
		"endless_best_wave": int(rec.get("endless_best_wave", 0)),
		"best_kills": int(rec.get("best_kills", 0)),
	}

## 选择危险度：4 档全部开放，只夹合法区间
func set_danger(d: int) -> void:
	danger_level = clampi(d, 0, GameBalance.DANGER_MAX)

## 设置是否从主菜单直接进入无尽试炼
func set_start_in_endless(enabled: bool) -> void:
	start_in_endless = enabled

var kills: int = 0
var game_time: float = 0.0
var spirit_stones: int = 0
var level: int = 1
var experience: int = 0
var experience_to_next: int = GameBalance.EXP_FIRST_LEVEL
var is_game_over: bool = false

## 待加点数：升几级攒几点，回合结束统一结算（战斗中不弹面板）
var pending_upgrade_points: int = 0

# 回合
var wave_number: int = 0
var endless_mode: bool = false
var run_started: bool = false

## 跨场景路由标记：局内「重新开始 / 再战一局」重载场景前置真，
## Main._ready 消费后跳过主菜单直落选角界面（不在 reset_run 里清，避免先于消费被抹掉）
var restart_to_select: bool = false

# 玩家属性（加点系统）
var weapon_damage_mult: float = 1.0
var melee_damage: float = 0.0       ## 近战伤害：加成所有近战挥扫武器
var ranged_damage: float = 0.0      ## 远程伤害：加成所有飞射弹道武器
var elemental_damage: float = 0.0   ## 元素伤害：加成符箓、雷法及灼烧/剧毒跳字伤害
var engineering_damage: float = 0.0 ## 召唤伤害：加成所有环绕护体灵宝
var contraption_damage: float = 0.0 ## 机关伤害：加成所有地面机关炮台与阵盘
var attack_speed_mult: float = 1.0
var move_speed_mult: float = 1.0
var pickup_range_mult: float = 1.0
var attack_range_mult: float = 1.0
var armor: float = 0.0
var hp_regen: float = 0.0
var crit_rate: float = 0.05
var crit_mult: float = 1.5
var dodge: float = 0.0        ## 身法：闪避概率（硬上限 DODGE_CAP）
var lifesteal: float = 0.0    ## 噬元：命中回复 1 点生命的概率
var luck: float = 0.0         ## 幸运：提升高稀有度悟道与商店亲和权重
var harvest: float = 0.0      ## 收益：每回合结束无偿获得等额金币+经验，并自我复利
var xp_gain_mult: float = 1.0 ## 经验获取倍率（只放大经验，不放大金币）
var knockback_mult: float = 1.0 ## 震退：武器击退力度倍率
var elite_damage: float = 0.0 ## 斩将：对精英/Boss 的额外伤害加成
var free_rerolls: int = 0     ## 通玄：每回合免费重掷货架次数
var element_damage: Dictionary = {}  ## 五行真解：{元素 tag(String): 伤害加成(float)}
var locked_upgrades: Array = []  ## 被角色负面代偿锁死的加点项 id（UpgradeData 过滤用）
var chest_count_bonus: int = 0   ## 宝箱数量：每回合额外刷几口宝箱（WaveSpawner._spawn_chests 消费）
var chest_quality: float = 0.0   ## 宝箱品质：抬高铜匣/玉匣出现权重（BalanceChest.tier_weights 消费）
var chest_break_bonus: int = 0   ## 开箱省力兼容字段
var chest_reward_mult: float = 1.0  ## 宝箱掉落：砸开的匣子掉得更多的乘区（SpiritChest._destroy 经 GameBalance.chest_reward_scaled 消费）
var chest_item_grants: int = 0   ## 本局玉匣已送出的道具件数（上限见 BalanceChest.JADE_ITEM_GRANT_CAP）

# 灵兽系统属性（随行伙伴）
var pet_damage_mult: float = 1.0       ## 灵兽伤害倍率
var pet_effect_mult: float = 1.0       ## 灵兽效果倍率（回复/磁吸/产出等）
var pet_cooldown_mult: float = 1.0     ## 灵兽行为节拍缩减乘区
var pet_slots_bonus: int = 0           ## 额外灵兽栏位加成
var pet_offer_chance_bonus: float = 0.0 ## 商店灵兽刷出概率加成（御兽师专属）

# 角色流派（角色）特性
var cultivator_id: String = ""
var thorns_pct: float = 0.0        ## 石岳反震：按敌方攻击力比例反弹
var spirit_threshold_adj: int = 0  ## 符阵灵童：御灵羁绊门槛下移
var dodge_cap_bonus: float = 0.0   ## 魅影：闪避硬上限上移（上限 = DODGE_CAP + 本值）
var weapon_slots_override: int = 0 ## 狂战士：上阵槽位上限覆盖（0 = 用 WeaponData.MAX_SLOTS）
var enemy_count_mult: float = 1.0  ## 狂战蛮修：敌潮规模倍率（WaveSpawner 消费）
var harvest_decay: float = 0.0     ## 蛮兵：每回合收益流失点数
var xp_require_mult: float = 1.0   ## 学者：升级经验需求倍率
var item_price_mult: float = 1.0   ## 多宝道人：道具价格乘区（叠加在商店价格系数之上）
var shop_slots_bonus: int = 0      ## 多宝道人：货架格数加成
var contraption_threshold_adj: int = 0  ## 机关师：机关羁绊门槛下移
var stone_interest_rate: float = 0.0    ## 守财奴：回合末金币结息比率
var stone_interest_cap: int = 30        ## 守财奴：回合末金币结息上限
var on_hit_damage_bonus: float = 0.0    ## 嗜血魔修：受击单层增伤
var on_hit_damage_cap_stacks: int = 10  ## 嗜血魔修：增伤最大层数
var on_hit_damage_stacks: int = 0
var on_hit_damage_timer: float = 0.0
var guard_stance: float = 0.0           ## 守卫：盾势机制开关（>0 启用；蓄能/爆发数值全在 GuardStanceData）
var shield_charge: float = 0.0          ## 守卫：盾势槽当前蓄能（Player.take_damage 写入，蓄满当帧爆发清空）
var heal_orb_chance: float = 0.0        ## 灵植夫：敌人死亡额外掉回复珠概率（EnemyBase 掉落块消费）
var heal_overflow_mult: float = 1.0     ## 灵植夫：回复珠溢出折金币倍率（HealOrb._collect 消费）
var alloc_offer_bonus: int = 0          ## 学者：悟道候选数加成（AllocSession.roll_alloc_offers 消费）
var alloc_free_reroll_bonus: int = 0    ## 学者：每回合悟道免费刷新加成（AllocSession.open_alloc_session 消费）
var collection_damage_per_unique: float = 0.0  ## 收藏家：每持有一种不同道具的全伤害加成
var unique_item_count: int = 0          ## 当前持有不同道具种数（add_item/consume_item 两写点维护）
var frenzy_enabled: float = 0.0       ## 狂战士：战意机制开关（>0 启用；每层幅度/上限/流失全在 FrenzyData）
var frenzy_stacks: float = 0.0          ## 狂战士：战意当前层数（register_kill 攒，_process 计时流失）
var frenzy_idle: float = 0.0            ## 距上次击杀的秒数（战意流失宽限计时）
var thunder_strike: float = 0.0         ## 雷法真君：天雷机制开关（>0 启用；数值全在 ThunderData，计时器在 Player）
# ---- 角色轻钩子（2026-10-12，照嗜血 on_hit 先例：不建机制表，apply 时从 mods 落字段，damage_mult 现算） ----
var crowd_damage_per_enemy: float = 0.0  ## 蛮兵·陷阵：感知圈内每只敌人的全伤害加成
var crowd_damage_cap: float = 0.0        ## 蛮兵·陷阵：加成总上限
var crowd_damage_radius: float = 0.0     ## 蛮兵·陷阵：感知半径（0 = 未启用，Player 不数怪）
var nearby_enemy_count: int = 0          ## 陷阵感知圈内的敌人数（Player 按 0.2s 节流写入）
var stone_damage_per_100: float = 0.0    ## 守财奴·财可通神：每持 100 金币的全伤害加成
var stone_damage_cap: float = 0.0        ## 守财奴·财可通神：加成总上限
var kill_cd_reduction_normal: float = 0.0  ## 绝尘·斩灭凝神：击杀普通怪返还的技能冷却（秒）
var kill_cd_reduction_elite: float = 0.0   ## 绝尘·斩灭凝神：击杀精英怪返还的技能冷却（秒）
var still_time: float = 0.0              ## 连续站定秒数（不动明王印账本，Player._physics_process 维护）
var player_is_moving: bool = false       ## 玩家当前是否处于移动中（Player._physics_process 维护）
var kuxingseng_mode: float = 0.0         ## 苦行僧：专属站定/移动机制开关
var still_damage_bonus: float = 0.0      ## 苦行僧：站定时额外全伤害加成（+0.50）
var still_haste_bonus: float = 0.0       ## 苦行僧：站定时攻击间隔缩减（0.35）
var still_armor_bonus: float = 0.0       ## 苦行僧：站定时护甲加成（+5）
var still_pickup_bonus: float = 0.0      ## 苦行僧：站定时拾取范围倍率加成（+1.0）
var move_damage_penalty: float = 0.0     ## 苦行僧：移动中全伤害衰减（-0.60）
var move_haste_penalty: float = 0.0      ## 苦行僧：移动中攻击间隔增加（+0.60）
var total_damage_taken_count: int = 0   ## 单局累计受击次数（嗜血魔修解锁判定）
var total_hp_healed: float = 0.0        ## 单局累计回复生命量（药王解锁判定）
var max_concurrent_summons: int = 0     ## 单局同时上阵机关/御灵峰值（机关师解锁判定）
var max_class_counts: Dictionary = {}   ## 单局各器类同时上阵峰值 {class_tag: int}（灵符子/霸王解锁判定）
var max_element_spread: int = 0         ## 单局同时上阵的五行元素种数峰值（五行同阵成就判定）
## 突破古玉回合末永久成长的累计到账账本（封顶常量 WAVE_END_HP/REGEN/LIFESTEAL_CAP，apply_harvest 消费）
var _wave_end_growth: Dictionary = {"max_hp": 0.0, "hp_regen": 0.0, "lifesteal": 0.0}
var _exp_chain: int = GameBalance.EXP_FIRST_LEVEL  ## 未折算的经验门槛链（xp_require_mult 只作用于显示/判定值）

# 随行技能：选技能界面写 pending，start_run 转正；buff_* 是技能短时增益乘区，
# 与加点/羁绊乘区隔离，到期由 Player 精确回 1.0，互不污染
var pending_skill_id: String = "dash"  ## 选人流程里选定的技能（默认缩地成寸，直接 start_run 也有技能可用）
var active_skill_id: String = ""       ## 本局生效的技能 id
var extra_skill_id: String = ""        ## 本局生效的「额外技能」id（随角色绑定，影者=影爆；空 = 无额外技能，第二按钮隐藏）
var buff_move_speed_mult: float = 1.0  ## 神行术短时移速乘区（Player._physics_process 消费）
var buff_pickup_range_mult: float = 1.0 ## 玉露鹿灵泉感知短时拾取范围乘区（Player._sync_pickup_radius 消费，到期回 1.0）
var buff_attack_speed_mult: float = 1.0 ## 疾风咒短时施法间隔乘区（FloatingWeapon._perform_attack 消费）
var buff_dodge: float = 0.0            ## 神行术短时闪避加成（get_effective_dodge 消费，到期归零）
var buff_knockback_mult: float = 1.0   ## 金光护体短时击退乘区（knockback_force 消费，到期回 1.0）
var force_crit_left: float = 0.0       ## 冲刺必暴剩余秒（roll_crit 消费，Player 每帧递减，>0 时所有攻击必暴）
var shadow_amp_mult: float = 1.0       ## 影层增伤乘区（影者攒着就生效：Player 在攒层/兑现两写点按 ShadowStepData.amp_mult 维护，落地清空回 1.0）
var buff_damage_mult: float = 1.0      ## 服丹短时全伤害乘区（FloatingWeapon._final_damage 消费，到期由 Player 精确回 1.0）

# 武器羁绊加成（由 recalc_synergies 每回合/换装时重算）
var stat_bonus_pierce: int = 0      ## 升级/道具：弹丸额外穿透基础
var synergy_bonus_pierce: int = 0   ## 符箓羁绊：弹丸额外穿透增量（2026-10-17 起恒 +1，成长走远程伤害）
var synergy_ranged_damage: float = 0.0 ## 符箓羁绊：远程伤害加成幅度（0.06 即 +6%，弹射流第二条成长线）
var bonus_pierce: int = 0           ## 弹丸额外穿透合计（stat + synergy）
var synergy_damage_mult: float = 1.0  ## 广域/离火羁绊：额外伤害乘区
var synergy_range_mult: float = 1.0   ## 剑系羁绊：额外攻击范围乘区
var synergy_haste_mult: float = 1.0   ## 雷法/玄水羁绊：额外攻速乘区
var synergy_max_hp_bonus: float = 0.0 ## 御灵羁绊：额外生命上限
var synergy_engineering_damage: float = 0.0 ## 御灵羁绊：额外召唤伤害
var synergy_crit_rate: float = 0.0    ## 锐金羁绊：额外暴击率
var synergy_crit_mult: float = 0.0    ## 锐金羁绊：额外暴击伤害
var synergy_hp_regen: float = 0.0     ## 青木羁绊：额外生命回复
var synergy_lifesteal: float = 0.0    ## 青木羁绊：额外吸血
var synergy_move_speed_mult: float = 0.0 ## 玄水羁绊：额外移速加成
var synergy_burn_mult: float = 1.0    ## 离火羁绊：额外灼烧伤害倍率
var synergy_armor: float = 0.0        ## 厚土羁绊：额外护甲
var synergy_knockback_mult: float = 1.0 ## 厚土羁绊：额外受击震退力倍率
var synergy_contraption_mult: float = 1.0 ## 机关羁绊：机关武器伤害乘区

var _lifesteal_procs: int = 0
var _lifesteal_window: float = 0.0
var _hud_tick: float = 0.0  ## HUD 计时刷新节流：只走时间显示，事件驱动的数值变化各自单独 emit
var _stats_dirty: bool = false ## 战斗高频事件（经验/金币/击杀）合并 emit 脏标记

# 商店
var shop_offers: Array = []
var reroll_cost: int = 2
var reroll_price_mult: float = 1.0 ## 商人：重掷费用乘区（ShopSystem.roll_shop 在纯函数结果上乘算）
var reroll_count: int = 0          ## 本回合已重掷次数（费用递增，跨回合重置）
var reroll_free_left: int = 0      ## 本回合剩余免费重掷次数（roll_shop(new_wave) 时按 free_rerolls 重置）
var shop_price_mult: float = 1.0   ## 商店价格系数（角色特性用，如散修 8 折）
var shop_tag_filter: Array = []    ## 非空时这些 tag 武器权重大幅提升，其余武器仍以低概率漏出（剑痴等流派偏好）
var _no_main_tag_waves: int = 0    ## 连续未刷出主流派武器的波数（保底计数）

# 回合后悟道结算会话（与商店重掷同一把尺子：免费次数用完才扣金币，价格随回合与已刷次数上升）
var alloc_offers: Array[Dictionary] = []
var alloc_points_total: int = 0   ## 本次结算开局时攒下的点数（面板写「待加点 2/共 3」用）
var alloc_reroll_cost: int = 2
var alloc_reroll_count: int = 0
var alloc_reroll_free_left: int = 0

## 已持有道具（被动道具）的 id 列表：无限持有、买即生效，数据定义见 ItemData
var items: Array = []
## has_still_mechanic 与 item_hook_sum 缓存：结果只在道具变化时变，
## 每物理帧/每命中不重复 O(items) 全表扫描（2026-10-13 掉帧根因之一）
var _still_cache_valid: bool = false
var _still_cached: bool = false
var _hook_cache: Dictionary = {}
var _hook_cache_items_size: int = -1
## 本局购入（或被玉匣送过）的道具 id 账本：出售后 items 里没了这一件，但 unique 道具的
## 「每局限购一件」不许因为退货就解禁 —— 详情卡上「出售后本局不再出现」由这里兑现。
var items_bought: Array = []

## 已持有灵兽（随行伙伴）的 id 列表：上限受 max_pet_slots() 约束，数据定义见 PetData
var pets: Array = []

# 武器库存：上阵 = 悬浮武器节点 + 灵蝶星级数组；背包 = 仅用于合成/出售的仓库
var drones: Array = []   # 上阵灵蝶的星级列表，如 [1, 2]
var stash: Array = []    # 背包，元素 {id: String, star: int}

# 本局历史悟道加点记录
var upgrade_history: Array[Dictionary] = []
var upgrade_counts: Dictionary = {}

func reset_run() -> void:
	# 70+ 单局成员的清零表在 RunReset（显式类型化赋值），新增成员记得去那边补默认值
	RunReset.reset(self)
	_stat_dict_frame = -1  # 属性字典 memo 随之作废，防止同帧后续读旧属性
	_autosave_cd = AUTOSAVE_INTERVAL  # 自动存档计时归位，新开局头几秒不落盘

func _process(delta: float) -> void:
	# 顿帧恢复（零分配轮询）：GameFeel.hit_stop 只写下恢复时刻，到点还原时间轴
	if _hitstop_deadline_ms != 0 and Time.get_ticks_msec() >= _hitstop_deadline_ms:
		_hitstop_deadline_ms = 0
		Engine.time_scale = 1.0

	if on_hit_damage_timer > 0.0:
		on_hit_damage_timer -= delta
		if on_hit_damage_timer <= 0.0:
			on_hit_damage_stacks = 0

	# 狂战士·战意流失：击杀把宽限计时归零，停杀超过宽限后按 FrenzyData 速率泄层
	if frenzy_enabled > 0.0 and frenzy_stacks > 0.0:
		frenzy_idle += delta
		frenzy_stacks = FrenzyData.decay(frenzy_stacks, frenzy_idle, delta)

	# 全局计时 / HUD 节流 / FIGHT 自动存档：所有角色同权（2026-10-15 修复：此块曾被错误
	# 缩进进上面的狂战 if 内 —— 非狂战整局 game_time 恒 0、HUD 计时永远 00:00、
	# 3 秒自动存档从不触发，中断续玩只剩回合边界快照与退游戏兜底）
	if not is_game_over and not get_tree().paused and player != null:
		game_time += delta
		_lifesteal_window += delta
		if _lifesteal_window >= 1.0:
			_lifesteal_window = 0.0
			_lifesteal_procs = 0
		# HUD 只关心「斩妖/金币/计时」三个读数：计时按 0.2s 节流即可（显示精度是整秒），
		# 数值真正变化时由各事件函数自己 emit，不必每帧重画 60 次。
		_hud_tick += delta
		if _hud_tick >= 0.2:
			_hud_tick = 0.0
			stats_updated.emit(kills, game_time, spirit_stones)
		# 中断续玩自动存档：只在 FIGHT 计时（树一暂停就轮不到这里——ALLOC/SHOP 各有
		# 阶段边界钩子），headless 下 RunSave 自拒，判据测试不落盘
		_autosave_cd += delta
		if _autosave_cd >= AUTOSAVE_INTERVAL:
			_autosave_cd = 0.0
			RunSave.autosave_current(self)

# ---------------- 经验 / 金币 ----------------

func add_experience(amount: int, stone_amount: int = -1) -> void:
	if is_game_over:
		return
	# 经验获取只放大经验，金币始终按原价入账（否则经济会双重受益）；
	# stone_amount >= 0 时金币腿改按传入值入账（碎晶档：经验足额、金币折低，见 BalanceEconomy 碎晶段）
	experience += int(round(float(amount) * xp_gain_mult))
	spirit_stones += amount if stone_amount < 0 else maxi(0, stone_amount)
	touch_peak_stones()
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
	_mark_stats_dirty()

func add_spirit_stones(amount: int) -> void:
	spirit_stones += amount
	touch_peak_stones()
	_mark_stats_dirty()

func register_kill(is_elite: bool = false, is_crit: bool = false) -> void:
	kills += 1
	# 击杀里程碑：每 50 杀一条横幅喜报（复用 GameHUD 横幅管线，不配新音，避免刷屏）
	if kills % 50 == 0:
		announcement_triggered.emit("◆ 连破 %d 敌 ◆" % kills)
	# 狂战士·战意：每次击杀 +1 层并把流失宽限计时归零（唯一攒点）
	if frenzy_enabled > 0.0:
		var prev_stacks := frenzy_stacks
		frenzy_stacks = FrenzyData.add_stack(frenzy_stacks)
		frenzy_idle = 0.0
		if prev_stacks < float(FrenzyData.MAX_STACKS) and frenzy_stacks >= float(FrenzyData.MAX_STACKS):
			announcement_triggered.emit("◆ 战意沸腾 ◆")
			if player != null and is_instance_valid(player):
				var pvfx = player.get("skill_vfx")
				if pvfx != null and pvfx.has_method("on_frenzy_max_burst"):
					pvfx.on_frenzy_max_burst()
	# 绝尘·斩灭凝神：击杀按敌人品级返还/预扣技能冷却
	var cd_refund: float = kill_cd_reduction_elite if is_elite else kill_cd_reduction_normal
	if cd_refund > 0.0 and player != null and is_instance_valid(player) and player.has_method("refund_skill_cooldown"):
		player.refund_skill_cooldown(cd_refund)
	# 金芒搜魂令：暴击击杀敌人有概率吸收金币
	if is_crit:
		var stone_chance: float = item_hook_sum("crit_kill_stone_chance")
		if stone_chance > 0.0 and rng.randf() < stone_chance:
			spirit_stones += 1
			touch_peak_stones()
	if is_elite:
		spirit_stones += GameBalance.ELITE_STONE_BONUS
		touch_peak_stones()
	_mark_stats_dirty()

## 战斗高频事件合并 emit：同帧多次改经验/金币/击杀时只 emit 一次（call_deferred 到帧末），
## 避免群杀清场秒内数十次 stats_updated → HUD 重绘。非战斗路径（结息/卖出）仍走即时 emit。
func _mark_stats_dirty() -> void:
	if not _stats_dirty:
		_stats_dirty = true
		call_deferred("_flush_stats")

func _flush_stats() -> void:
	_stats_dirty = false
	stats_updated.emit(kills, game_time, spirit_stones)

## 单局金币峰值记账（成就判定用）：所有改 spirit_stones 后想记峰值的地方都走这个
func touch_peak_stones() -> void:
	if spirit_stones > peak_stones:
		peak_stones = spirit_stones

# ---------------- 属性加点 ----------------

## 加点：幅度全部来自 UpgradeData 每项的 "apply" 表，这里只规定「往哪个字段加、有没有上限」。
## 这样「数值」和「卡片文案」同源，调参只改数据表一处（历史上二者分家，改一项要动两个文件）。
func apply_upgrade(upgrade_id: String) -> void:
	var def := UpgradeData.get_upgrade_def(upgrade_id)
	_apply_stat_fields(def.get("apply", {}), upgrade_id)
	_stat_dict_frame = -1  # 属性字典 memo 立即作废：加点当帧武器就得吃到新数值

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

## 属性字段统一落地入口：悟道加点（apply_upgrade）与道具（add_item）共用同一条链路，
## 白名单与落地规则在 StatSystem（2026-10-11 抽离）
func _apply_stat_fields(apply: Dictionary, source: String) -> void:
	StatSystem.apply_stat_fields(self, apply, source)

## 抽一批悟道候选。UpgradeData 是纯函数层、不读单例，所以这里负责把当前局面打包成 ctx 传过去。
## 默认一次给 UPGRADE_OFFER_COUNT（5）个：候选太少时「刷新」没意义（2026-10-09 用户指令）。
func roll_upgrades(count: int = UPGRADE_OFFER_COUNT) -> Array[Dictionary]:
	return UpgradeData.get_random_upgrades(count, {
		"luck": luck,
		"wave": wave_number,
		"locked_upgrades": locked_upgrades,
		"counts": upgrade_counts,
		"rng": rng,
		"has_pets": (not pets.is_empty() or cultivator_id == "yushou"),
		"gm": self,   # 满穿透闸（PierceLimit）：阵容穿透顶到上限后 pierce_up 停刷
	})

# ---------------- 回合后悟道结算（委托 AllocSession） ----------------

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

## 站定流激活判定（算式在 StatSystem，2026-10-15 迁出；缓存字段留本类，失效点不动）
func has_still_mechanic() -> bool:
	return StatSystem.has_still_mechanic(self)

## 武器伤害乘区有效值：加点/道具/角色累加的 raw 过软顶膝点后收益减半（BalanceCombat 唯一算式）。
## 所有伤害结算与伤害读数都走这里，不许直接乘 raw 字段 weapon_damage_mult。
func get_weapon_damage_mult() -> float:
	return BalanceCombat.effective_weapon_damage_mult(weapon_damage_mult)

## 暴击伤害有效值：加点层 + 锐金羁绊合计后夹总上限（与 get_crit_rate 同款的「合计再夹」口径）
func get_crit_mult() -> float:
	return minf(crit_mult + synergy_crit_mult, CRIT_MULT_CAP)

## 最终施法间隔乘区：装备/加点层 × 羁绊层 × 技能 buff 层 × 站定神像/苦行僧加成（受 ATTACK_SPEED_FLOOR 保底，< 1.0 为更快）。
func get_effective_attack_speed_mult() -> float:
	var base := attack_speed_mult * synergy_haste_mult * buff_attack_speed_mult
	if still_time > 0.0:
		var still_haste: float = item_hook_sum("still_attack_speed") + still_haste_bonus
		if still_haste > 0.0:
			base *= maxf(0.1, 1.0 - still_haste)
	elif player_is_moving and move_haste_penalty > 0.0:
		base *= (1.0 + move_haste_penalty)
	return maxf(ATTACK_SPEED_FLOOR, base)

func get_effective_armor() -> float:
	var extra_still := (item_hook_sum("still_armor") + still_armor_bonus) if still_time > 0.0 else 0.0
	return armor + synergy_armor + extra_still

func get_effective_thorns() -> float:
	var t: float = thorns_pct
	if still_time > 0.0:
		t += item_hook_sum("still_thorns")
	return t

func get_crit_rate() -> float:
	# 算式在 BalanceCombat.crit_rate（悟道卡面的「加后读数」预读共用同一条，不抄第二份）
	return BalanceCombat.crit_rate(
		crit_rate, synergy_crit_rate, item_hook_sum("crit_per_dodge"),
		get_effective_dodge(), CRIT_RATE_CAP)

## 暴击判定唯一出口：冲刺必暴窗口内直接判暴，否则按有效暴击率掷 rng
func roll_crit() -> bool:
	if force_crit_left > 0.0:
		return true
	return rng.randf() < get_crit_rate()

func get_effective_dodge() -> float:
	# 算式在 BalanceCombat.effective_dodge（与卡面预读同源）
	var extra_still := item_hook_sum("still_dodge") if still_time > 0.0 else 0.0
	return BalanceCombat.effective_dodge(dodge + extra_still, buff_dodge, DODGE_CAP, dodge_cap_bonus)

## 上阵武器槽位上限：独臂刀圣这类角色会覆盖（0 = 用 WeaponData.MAX_SLOTS）
func max_weapon_slots() -> int:
	return weapon_slots_override if weapon_slots_override > 0 else WeaponData.MAX_SLOTS

## 多武器神识分流系数：按当前上阵武器总数（悬浮武器 + 环绕灵物）计算单把直击伤害折算。
## 环绕灵宝按半权计入（召唤物自主作战不占神识），机关炮台仍按全额。
func get_multi_weapon_damage_mult() -> float:
	return GameBalance.multi_weapon_damage_mult(slots_used(), drones.size())

## 五行真解：某件武器吃到的元素伤害乘区（按 WeaponData.element_of 取对应元素加成）
func element_damage_mult(w_id: String) -> float:
	if element_damage.is_empty():
		return 1.0
	return 1.0 + float(element_damage.get(WeaponData.element_of(w_id), 0.0))

## 武器击退力度：玩家震退属性 × 厚土羁绊倍率 × 金光护体短时倍率 × 站定加成
func knockback_force(base: float) -> float:
	var still_kb := (1.0 + item_hook_sum("still_knockback")) if still_time > 0.0 else 1.0
	return base * knockback_mult * synergy_knockback_mult * buff_knockback_mult * still_kb

## 武器震退向量：方向走 GameBalance.knock_dir（永不把敌人往玩家身上推），力度走 knockback_force。
## source = 施力点（落雷点 / 武器自身 / 灵宝自身），enemy_pos = 受击敌人位置。
## 玩家不在场（单测、局外预览）时把玩家位置退回施力点 = 纯径向旧行为，不会出 NaN。
## 各武器只许经这一个出口拿方向，别再自己写 (enemy - source).normalized()。
func knockback_vec(source: Vector2, enemy_pos: Vector2, base: float) -> Vector2:
	var player_pos: Vector2 = source if player == null or not is_instance_valid(player) else player.global_position
	return GameBalance.knock_dir(source, enemy_pos, player_pos) * knockback_force(base)

## 斩将：对精英/Boss（is_elite 标记）的额外伤害乘区，普通敌人不受影响
func elite_damage_mult_for(enemy: Variant) -> float:
	if elite_damage <= 0.0 or enemy == null:
		return 1.0
	return 1.0 + elite_damage if enemy.get("is_elite") == true else 1.0

## 20 键属性投影（算式在 StatSystem.player_stat_dict，2026-10-15 迁出）：武器折算与 UI 读数共用
func get_player_stat_dict() -> Dictionary:
	return StatSystem.player_stat_dict(self)

## 属性字典每物理帧 memo：缓存字段留本类（失效点 reset_run/add_item/sell_item 不动），
## memo 重建算式在 StatSystem.stat_dict_for_weapons。
var _stat_dict_frame: int = -1
var _stat_dict_memo: Dictionary = {}

## 武器折算专用的属性快照（每物理帧重建一次，同帧共享；算式在 StatSystem.stat_dict_for_weapons）
func _stat_dict_for_weapons() -> Dictionary:
	return StatSystem.stat_dict_for_weapons(self)

func get_weapon_stat_bonus(w_id: String, star: int = 1) -> float:
	return StatSystem.weapon_stat_bonus(self, w_id, star)

## 命中时尝试噬元回血（每秒最多触发 LIFESTEAL_MAX_PER_SEC 次，防高频武器无限续航）
## behavior：命中武器的攻击方式（WeaponData.Behavior）。吸血概率按武器类型打折：
##   近战/横扫全额、远程/范围 40%、环绕/机关/光束/喷吐 25%（算式见 BalanceTargeting.lifesteal_weapon_mult）。
##   不分类时高频武器会独吞每秒闸，近战反而拿不到几口，与「贴脸换续航」的意图相反。
func try_lifesteal(behavior: int = WeaponData.Behavior.MELEE) -> void:
	var total_ls := (lifesteal + synergy_lifesteal) * BalanceTargeting.lifesteal_weapon_mult(behavior)
	if total_ls <= 0.0 or player == null or not is_instance_valid(player):
		return
	if _lifesteal_procs >= LIFESTEAL_MAX_PER_SEC:
		return
	if rng.randf() < total_ls:
		_lifesteal_procs += 1
		player.heal(1.0, true)

## 回合间收益结算：无偿发放等额金币+经验；蛮兵的杀气让收益每回合流失；随后收益自我复利（增长截止回合见常量区）
## budget_comp_exp：刷怪预算未花完部分的折算经验补差（WaveSpawner 传入，BalanceEconomy.budget_compensation_exp），
## 与收益一并到账、同一句播报 —— 减潮不减收入，购买力与旧口径持平
## early_secs：本回合提前收尾时还剩几秒（WaveSpawner 传入，0 = 表走完）。余时按
## BalanceEconomy.early_clear_stones 折成金币，**只进金币不进经验**（提前清场不该顺手把升级也加速）。
## 三笔并成一句播报：横幅只有一个 Label，同帧发两条只会留下后一条，等于把前一个数吞掉。
func apply_harvest(budget_comp_exp: int = 0, early_secs: float = 0.0) -> void:
	var gain := GameBalance.harvest_gain(harvest)
	var total_gain := gain + maxi(0, budget_comp_exp)
	var early_stones := GameBalance.early_clear_stones(early_secs)
	var clauses: Array[String] = []
	if total_gain > 0:
		add_experience(total_gain)
		clauses.append("金币与经验 +%d" % total_gain)
	if early_stones > 0:
		add_spirit_stones(early_stones)
		clauses.append("提前 %d 秒清场 +%d 金币" % [int(floor(maxf(0.0, early_secs))), early_stones])
	if not clauses.is_empty():
		announcement_triggered.emit("◆ 收益到账 · %s ◆" % " · ".join(clauses))
	if harvest_decay > 0.0:
		harvest = maxf(0.0, harvest - harvest_decay)
	harvest = GameBalance.harvest_next(harvest, wave_number, HARVEST_GROWTH_WAVE_CAP)
	# 守财奴金币结息 hook
	if stone_interest_rate > 0.0 and spirit_stones > 0:
		var interest := mini(stone_interest_cap, int(floor(float(spirit_stones) * stone_interest_rate)))
		if interest > 0:
			spirit_stones += interest
			stats_updated.emit(kills, game_time, spirit_stones)
			announcement_triggered.emit("◆ 金币结息 · 获得 %d 枚金币 ◆" % interest)
	# 回复葫芦等道具的回合末回血 hook（quiet：回合间歇不在战斗画面里，别触发角色挤压抖动）
	var heal_pct := item_hook_sum("wave_heal_pct")
	if heal_pct > 0.0 and player != null and is_instance_valid(player) and player.has_method("heal"):
		player.heal(player.max_health * heal_pct, true)
	# 突破古玉等道具的回合末永久成长 hook：它不是悟道加点、天然绕过 max_stacks，
	# 累计到账按 WAVE_END_*_CAP 封口（2026-10-13：+3血/回合 × 20 回合无对价滚出 +60 血的口子）
	var wave_hp := item_hook_sum("wave_end_max_hp")
	var wave_reg := item_hook_sum("wave_end_regen")
	var wave_ls := item_hook_sum("wave_end_lifesteal")
	if wave_hp > 0.0 or wave_reg > 0.0 or wave_ls > 0.0:
		var wave_apply: Dictionary = {}
		var hp_eff := minf(wave_hp, maxf(0.0, WAVE_END_HP_CAP - float(_wave_end_growth["max_hp"])))
		var reg_eff := minf(wave_reg, maxf(0.0, WAVE_END_REGEN_CAP - float(_wave_end_growth["hp_regen"])))
		var ls_eff := minf(wave_ls, maxf(0.0, WAVE_END_LIFESTEAL_CAP - float(_wave_end_growth["lifesteal"])))
		if hp_eff > 0.0:
			wave_apply["max_hp"] = hp_eff
			wave_apply["hp_heal"] = hp_eff
			_wave_end_growth["max_hp"] = float(_wave_end_growth["max_hp"]) + hp_eff
		if reg_eff > 0.0:
			wave_apply["hp_regen"] = reg_eff
			_wave_end_growth["hp_regen"] = float(_wave_end_growth["hp_regen"]) + reg_eff
		if ls_eff > 0.0:
			wave_apply["lifesteal"] = ls_eff
			_wave_end_growth["lifesteal"] = float(_wave_end_growth["lifesteal"]) + ls_eff
		if not wave_apply.is_empty():
			_apply_stat_fields(wave_apply, "wave_end_growth")
	# 随行灵兽回合末收益（聚宝蟾献金币等）
	PetSystem.on_wave_ended(self)

# ---------------- 灵兽（随行伙伴） ----------------

func max_pet_slots() -> int:
	return PetSystem.max_pet_slots(self)

func has_pet(pet_id: String) -> bool:
	return pet_id in pets

func add_pet(pet_id: String) -> bool:
	return PetSystem.add_pet(self, pet_id)

func sell_pet(pet_id: String) -> bool:
	return PetSystem.sell_pet(self, pet_id)

# ---------------- 道具（被动道具） ----------------

func has_item(item_id: String) -> bool:
	return item_id in items

## 购入道具：属性走 _apply_stat_fields（与悟道同一条链路）；unique 道具本局限一件（卖了也不解禁）
func add_item(item_id: String) -> bool:
	var def := ItemData.get_def(item_id)
	if def.is_empty():
		return false
	if bool(def.get("unique", false)) and item_id in items_bought:
		return false
	# 图鉴种数账本（收藏家）：新种类 +1，重复购买不涨（consume_item 那一路对应回退）
	if not has_item(item_id):
		unique_item_count += 1
	if not (item_id in items_bought):
		items_bought.append(item_id)
	items.append(item_id)
	_still_cache_valid = false
	_hook_cache.clear()
	_stat_dict_frame = -1  # 属性字典 memo 立即作废：道具当帧就得生效
	_apply_stat_fields(def.get("apply", {}), "item:" + item_id)
	return true

## 出售一件道具（2026-10-12 用户：「商店里的这些道具，如果有买到不想要的，也可以卖掉」）：
## 回收金币 + 把这一件加过的属性原样退回去。与 consume_item 的区别是那条只「碎掉」（替身娃娃，
## 不给钱也不回属性，因为它的 apply 是空的），这一条是「退货」，必须回退，否则卖一件
## 全伤害 −18% 的道具反而涨了伤害。
## 灵兽上限这类「退了当场超编」的账先算清楚：不许按下去把灵兽栏搞成 3/2 那种读数为假。
func sell_item(item_id: String) -> bool:
	var def := ItemData.get_def(item_id)
	if def.is_empty():
		return false
	var i: int = items.find(item_id)
	if i < 0:
		return false
	var apply: Dictionary = def.get("apply", {})
	var slots_given := int(apply.get("pet_slots", 0))
	if slots_given > 0 and pets.size() > max_pet_slots() - slots_given:
		announcement_triggered.emit("灵兽栏已超编，先出售灵兽再退【%s】" % String(def.get("name", item_id)))
		AudioManager.play_sfx("ui_error", 0.9)
		return false
	items.remove_at(i)
	_still_cache_valid = false
	_hook_cache.clear()
	_stat_dict_frame = -1  # 属性字典 memo 立即作废：退货当帧就得回退数值
	# 图鉴种数账本（收藏家）：卖掉最后一件同种，种数 −1（与 consume_item 同一条回退）
	if not has_item(item_id):
		unique_item_count = maxi(0, unique_item_count - 1)
	StatSystem.revert_stat_fields(self, apply, "item:" + item_id)
	spirit_stones += ItemData.sell_price(item_id)
	stats_updated.emit(kills, game_time, spirit_stones)
	AudioManager.play_sfx("sell", 1.0)
	return true

## 玉匣破开送道具：与商店同一个 roller（ItemData.pick_id），档位权重、幸运、本局已购 unique
## 去重、未解锁不入池这些口径全部照旧 —— 白送的那件和花钱买的那件必须是同一种东西。
## 每局上限见 BalanceChest.JADE_ITEM_GRANT_CAP：到顶返回 false，由调用方落回退回奖励。
## 公告必发：玩家得知道这口匣子开出了什么，不然"送道具"这条兑现不出来就只能靠猜。
func chest_grant_item() -> bool:
	if chest_item_grants >= GameBalance.CHEST_JADE_ITEM_GRANT_CAP:
		return false
	var id := ItemData.pick_id(luck, wave_number, items_bought, rng, unlocked_items, self)
	if id.is_empty():
		return false
	if not add_item(id):
		return false
	chest_item_grants += 1
	announcement_triggered.emit("◆ 玉匣破开 · 得【%s】◆" % String(ItemData.get_def(id).get("name", id)))
	return true

## 消耗一件道具（替死傀儡这类一次性机制用），返回是否真的消耗了
func consume_item(item_id: String) -> bool:
	var i := items.find(item_id)
	if i < 0:
		return false
	items.remove_at(i)
	_still_cache_valid = false
	_hook_cache.clear()
	# 图鉴种数账本（收藏家）：消耗掉的若是最后一件同种道具，种数 -1
	if not has_item(item_id):
		unique_item_count = maxi(0, unique_item_count - 1)
	return true

## 同名字段 hook 的叠加求和（算式在 StatSystem.item_hook_sum，2026-10-15 迁出）。
## 缓存字段 _hook_cache 留本类：items 增删与 RunReset 三处失效点不动。
func item_hook_sum(hook: String) -> float:
	return StatSystem.item_hook_sum(self, hook)

## 替死傀儡：致死一击时消耗它免死并回半血。Player.take_damage 在扣血归零后调用
func try_revive() -> bool:
	if not consume_item("tisi_kuilei"):
		return false
	if player != null and is_instance_valid(player):
		player.current_health = player.max_health * 0.5
		player.invulnerable_time = 2.0
		player_hp_changed.emit(player.current_health, player.max_health)
	announcement_triggered.emit("◆ 替身娃娃碎裂 · 死里逃生 ◆")
	AudioManager.play_sfx("level_up", 1.0)
	return true

# ---------------- 武器系统 ----------------

func start_run(starter_id: String) -> void:
	run_started = true
	endless_mode = start_in_endless
	_apply_cultivator()
	# 随行技能转正：选择界面写的是 pending_skill_id；id 失效时回退缩地成寸
	active_skill_id = pending_skill_id if SkillData.get_def(pending_skill_id).size() > 0 else "dash"
	# 额外技能随角色绑定（不走选择界面）：按道统查表，没有 extra_skill 键的角色保持空串
	extra_skill_id = CultivatorData.get_extra_skill_id(cultivator_id)
	add_weapon(starter_id)
	if endless_mode:
		announcement_triggered.emit("◆ 无尽模式 · 战至终局 ◆")
	else:
		announcement_triggered.emit("◆ 生存战斗 · 击杀敌人 ◆")

## 开局应用角色流派的正负代偿（规则在 CultivatorSystem，2026-10-11 抽离）
func _apply_cultivator() -> void:
	CultivatorSystem.apply_cultivator(self)

## 角色特性的单武器伤害系数（tag 加成 × 非灵蝶/非机关惩罚 + 受击增伤）
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

func get_weapon_star_distribution(w_id: String) -> Dictionary:
	return WeaponInventory.star_distribution(self, w_id)

func get_weapon_owned_summary(w_id: String) -> String:
	return WeaponInventory.format_owned_summary(self, w_id)

func _count_mergeable_copies(w_id: String, star: int, keep: Dictionary) -> int:
	return WeaponInventory.count_mergeable_copies(self, w_id, star, keep)

func merge_weapon(w_id: String, star: int, keep: Dictionary) -> bool:
	return WeaponInventory.merge_weapon(self, w_id, star, keep)

func get_weapons_summary() -> Array:
	return WeaponInventory.get_weapons_summary(self)

func notify_weapons_updated(weapons: Array) -> void:
	recalc_synergies()
	var cur_summons: int = drones.size()
	var cur_class_counts: Dictionary = {}
	var cur_elements: Dictionary = {}
	if player != null and player.has_method("get_equipped_weapons_data"):
		for w in player.get_equipped_weapons_data():
			var wid := String(w.get("id", ""))
			var beh := int(WeaponData.get_def(wid).get("behavior", -1))
			if beh == WeaponData.Behavior.TURRET or beh == WeaponData.Behavior.DRONE:
				cur_summons += 1
			# 器类峰值账本：多 tag 武器只计入主器类（class_of 口径与羁绊/商店一致）
			var cls := WeaponData.class_of(wid)
			if not cls.is_empty():
				cur_class_counts[cls] = int(cur_class_counts.get(cls, 0)) + 1
			# 五行同阵账本：当前同时上阵的元素种数（element_of 口径与五行真解一致）
			var elem := WeaponData.element_of(wid)
			if not elem.is_empty():
				cur_elements[elem] = true
	max_concurrent_summons = maxi(max_concurrent_summons, cur_summons)
	for cls in cur_class_counts:
		max_class_counts[cls] = maxi(int(max_class_counts.get(cls, 0)), int(cur_class_counts[cls]))
	max_element_spread = maxi(max_element_spread, cur_elements.size())
	weapons_updated.emit(weapons)

func sell_weapon(index: int) -> bool:
	return WeaponInventory.sell_weapon(self, index)

func equip_from_stash(index: int) -> bool:
	return WeaponInventory.equip_from_stash(self, index)

func unequip_to_stash(index: int) -> bool:
	return WeaponInventory.unequip_to_stash(self, index)

## 背包 → 上阵「换装」旧口径（未满＝装备、满＝与该格互换）：保留给既有判据；
## 拖拽落点走 equip_stash_into_slot（空格＝装备、已佩戴格＝替换）
func swap_into_equipped(stash_index: int, equipped_index: int) -> bool:
	return WeaponInventory.swap_into_equipped(self, stash_index, equipped_index)

## 背包 → 上阵指定格（拖拽落点语义）：空格/越界＝直接装备，已占用格＝替换（换下的回背包原位）
func equip_stash_into_slot(stash_index: int, slot_index: int) -> bool:
	return WeaponInventory.equip_stash_into_slot(self, stash_index, slot_index)

## 上阵两格互换位置（summary 下标；同池才换：悬浮武器换悬浮武器、灵宝换灵宝）
func swap_equipped_slots(i: int, j: int) -> bool:
	return WeaponInventory.swap_equipped_slots(self, i, j)

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

# ---------------- 回合间商店（委托 ShopSystem） ----------------

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
## hit_stop 恢复时刻（真实毫秒，Time.get_ticks_msec 口径）：GameFeel.hit_stop 只写这个字段，
## 由 _process 轮询恢复 time_scale（2026-10-14：原实现每次顿帧 create_timer 分配
## SceneTreeTimer + 闭包，受击/登场/落雷等未限流路径高频触发时有分配抖动）。
var _hitstop_deadline_ms: int = 0

func add_trauma(amount: float) -> void:
	GameFeel.add_trauma(self, amount)

func zoom_punch(scale_amount: float = 0.05, duration: float = 0.18) -> void:
	GameFeel.zoom_punch(self, scale_amount, duration)

func shake_camera(intensity: float = 3.5, duration: float = 0.12) -> void:
	GameFeel.shake_camera(self, intensity, duration)

func kick_camera(dir: Vector2, strength: float = 3.0) -> void:
	GameFeel.kick_camera(self, dir, strength)

func focus_camera(pos: Vector2, zoom_mult: float = 1.3, duration: float = 0.55) -> void:
	GameFeel.focus_camera(self, pos, zoom_mult, duration)

func release_camera(duration: float = 0.6) -> void:
	GameFeel.release_camera(self, duration)

func hit_stop(duration: float = 0.045, target_scale: float = 0.05) -> void:
	GameFeel.hit_stop(self, duration, target_scale)

## 暴击命中的微顿帧（GameFeel 内部限流）：防高频暴击锁死节奏
func crit_hit_stop() -> void:
	GameFeel.crit_hit_stop(self)

## 小怪伏诛的微顿帧（GameFeel 内部限流）：只在 EnemyBase 判定致命一刀时调用
func kill_hit_stop() -> void:
	GameFeel.kill_hit_stop(self)

func feedback(tier: int) -> void:
	GameFeel.feedback(self, tier)

func pulse_damage_vignette(color: Color = Color(0.85, 0.12, 0.12, 0.65), duration: float = 0.22) -> void:
	GameFeel.pulse_damage_vignette(self, color, duration)

func trigger_screen_shockwave(pos: Vector2 = Vector2.INF, strength: float = 1.0, duration: float = 0.45) -> void:
	screen_shockwave_triggered.emit(pos, strength, duration)

func trigger_game_over(victory: bool = false) -> void:
	if is_game_over:
		return
	Engine.time_scale = 1.0
	_hitstop_token += 1
	_hitstop_deadline_ms = 0
	is_game_over = true
	# 本局已终结、战报已录入局外进度：中断续玩档随之作废
	RunSave.clear_save()
	_record_run_and_check_achievements(victory)
	game_over_triggered.emit(victory)

func _record_run_and_check_achievements(victory: bool) -> void:
	ProgressStore.record_run_and_check_achievements(self, victory)

func continue_endless() -> void:
	endless_mode = true
	is_game_over = false
	get_tree().paused = false
	if player != null and is_instance_valid(player) and player.has_method("reset_victory_state"):
		player.reset_victory_state()
	if wave_spawner != null and wave_spawner.has_method("open_shop"):
		wave_spawner.open_shop()
