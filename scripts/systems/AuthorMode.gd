class_name AuthorMode
extends RefCounted

## 作者模式（Author Mode）—— 会话级测试开关，**不写任何存档**。
##
## 设计口径：
## - 开关本体是 `GameManager.author_mode`（普通成员，不进 ProgressStore / RunSave），
##   下次启动游戏自然是普通模式；关掉开关时本文件里的作弊状态一并复位。
## - 所有"作弊动作"集中在这里，GameManager / 面板 / 实体只留一行调用，
##   避免把测试逻辑散进战斗热路径。
## - 解锁类改动只做"读侧短路"（GameManager.is_*_unlocked），绝不往
##   unlocked_cultivators / unlocked_items 里写数据 —— 那是存档污染。

## 无敌：Player.take_damage 入口直接返回
static var god_mode: bool = false
## 一击必杀：EnemyBase.take_damage 入口把伤害抬到必死
static var one_hit_kill: bool = false
## 时间加速倍率（1.0 / 2.0 / 4.0），由 GameManager 顿帧恢复与跳关共同读
static var time_scale: float = 1.0
## 图鉴直购的武器星级（1~3），面板顶部切换
static var grant_star: int = 1

## 关闭作者模式时把所有作弊状态复位（时间轴必须拉回 1.0，否则退出后整局慢/快放）
static func reset() -> void:
	god_mode = false
	one_hit_kill = false
	time_scale = 1.0
	grant_star = 1
	Engine.time_scale = 1.0

## 当前应有的基础时间倍率：GameManager 顿帧结束、跳关落地都读它，
## 否则一次暴击顿帧就会把 2x/4x 打回 1x。
static func base_time_scale() -> float:
	return time_scale

## 循环切档 1x → 2x → 4x → 1x，返回切换后的倍率
static func cycle_time_scale() -> float:
	if time_scale < 1.5:
		time_scale = 2.0
	elif time_scale < 3.0:
		time_scale = 4.0
	else:
		time_scale = 1.0
	Engine.time_scale = time_scale
	return time_scale

## 直接把人物等级设为 target，并重算经验门槛链（与 add_experience 的升级链同源）。
## 上调的级数折算成待加点：回合末照常走悟道面板，属性收益与正常升级一致；
## 下调只改等级读数，不回收已获得的属性（测试时方便反复试构筑）。
static func set_level(gm: Node, target: int) -> void:
	var t := clampi(target, 1, 999)
	var old_level: int = int(gm.level)
	var chain: int = GameBalance.EXP_FIRST_LEVEL
	for _i in range(t - 1):
		chain = GameBalance.exp_to_next(chain)
	gm.level = t
	gm._exp_chain = chain
	gm.experience = 0
	gm.experience_to_next = maxi(1, int(round(float(chain) * float(gm.xp_require_mult))))
	if t > old_level:
		var gained := t - old_level
		gm.pending_upgrade_points += gained
		gm.pending_points_changed.emit(gm.pending_upgrade_points)
		for i in range(gained):
			gm.player_leveled_up.emit(old_level + i + 1)
	gm.player_exp_changed.emit(gm.experience, gm.experience_to_next, gm.level)
	gm._mark_stats_dirty()

## 图鉴直购（免费）：kind = weapon / item / pet。
## 复用正常获得链路（武器满栏自动进背包、道具走属性 apply、灵兽走 PetSystem），
## 只跳过扣金币这一步 —— 作者模式的面板另有「金币 +1000/+10000」按钮供经济测试。
static func grant(gm: Node, kind: String, id: String, star: int = 1) -> bool:
	if gm == null or not gm.run_started or gm.player == null:
		return false
	var ok := false
	match kind:
		"weapon":
			ok = WeaponInventory.add_weapon(gm, id, clampi(star, 1, WeaponData.MAX_STAR))
		"item":
			ok = gm.add_item(id)
		"pet":
			ok = gm.add_pet(id)
		_:
			ok = false
	if ok:
		gm.stats_updated.emit(gm.kills, gm.game_time, gm.spirit_stones)
		AudioManager.play_sfx("shop_buy", 1.0)
	return ok
