class_name StrikeFx
extends RefCounted

## 近战/横扫共用的命中反馈小件（2026-10-24 自 FloatingWeapon 拆出）：
## 命中火花与土系地面裂痕。两者都被 MELEE 与 SWEEP 结算路径使用，单独成文件避免
## 两个 handler 互相引用。
##
## 纪律：武器侧 handler 一律鸭类型访问武器（参数 w 不标 FloatingWeapon 类型）——
## 武器脚本硬类型引用会触发循环类依赖，把弹丸 preload 打成空 PackedScene（项目坑 12）。

## 近战/横扫命中火花（2026-10-22）：远程弹丸命中已有 FxParticlePool.HIT_SPARK，
## 但近战/横扫命中点此前一粒火花都没有（小怪只有暴击才给方向环），「刀咬进肉里」缺一个落点读数。
## 这里补上，且刻意与当年下线的旧火花区分：近战天然低频（1.1s 一挥、一次至多几只）、
## 火花锚在敌人受击侧、顺击退方向喷溅，再受四道闸兜底（帧预算/视口门控/致命不发/单挥封顶），
## 不空地乱闪也不糊屏；精英/Boss 已有专属火花，这里不重复发。
const MELEE_SPARK_MAX := 2         ## 近战单次命中火花上限（前 N 个目标）
const SWEEP_SPARK_MAX := 3         ## 横扫单次命中火花上限（扫一片也不全冒）
const MELEE_SPARK_SCALE := 0.75    ## 火花缩放（比弹丸非暴击 0.85 更克制一档）
const CRIT_SPARK_SCALE := 1.5      ## 暴击火花缩放（与 BladeProjectile 暴击 1.5 同档，重击感知靠对比）
const MELEE_SPARK_EDGE := 14.0     ## 火花由敌人中心向攻击来向偏移，落在体表而非几何中心

## 土系重击地面裂痕全局限频（2026-10-16）：旧写法每把武器各自 0.85s 一道，
## 多把土系武器 × 高攻速下几乎每次命中都裂、满屏裂纹。裂痕是「重击砸地」的
## 偶发留痕而非常规命中反馈，改全武器共享一道时间闸：任一武器留痕后
## EARTH_CRACK_MIN_GAP_MS 内所有武器（含自己）的后续命中都不再出新裂痕。
## 用时间戳而非倒计时——_process 每实例各跑一遍，共享倒计时会被多把武器重复扣减。
const EARTH_CRACK_MIN_GAP_MS := 5000   ## 2026-10-19 风格统一：玉面战台去裂痕化，留痕间隔再翻倍
static var _last_earth_crack_ms: int = -999999  ## 上次留痕时间戳（负初值 = 从未留痕；GDScript 的 << 不吃负操作数）

## 命中火花——单目标发射。业务门控（精英非暴击不重复 / 致命不发 / 屏外不发）
## 全部收在 FxParticlePool.weapon_hit_spark 内部，本处只报「打中了谁、是否暴击」。
## 位置落敌人受击侧，方向顺击退。必须在 enemy.take_damage 之后调用：致命/精英状态那时才更新到位。
## 暴击规格与弹丸侧对齐（2026-10-23）：scale 1.5 + "crit" 绯金，与非暴击 0.75 拉开重击对比。
static func spawn_hit_spark(w, enemy: Node, knock: Vector2, is_crit: bool = false) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	var epos: Vector2 = enemy.global_position
	var kb_dir: Vector2 = knock.normalized() if knock.length_squared() > 1.0 else Vector2.ZERO
	var spark_pos: Vector2 = epos - kb_dir * MELEE_SPARK_EDGE if kb_dir != Vector2.ZERO else epos
	var spark_scale: float = CRIT_SPARK_SCALE if is_crit else MELEE_SPARK_SCALE
	var spark_elem: Variant = "crit" if is_crit else w._arc_element()
	FxParticlePool.weapon_hit_spark(enemy, spark_pos, spark_elem, spark_scale, is_crit, kb_dir)

## 土系重击地面贴花接入（开山斧/崩山剑/奔浪锤等命中敌群时克制留痕）
## 全武器共享一道全局时间闸（静态时间戳，非逐实例倒计时）——裂痕是重击砸地的
## 偶发留痕，不是每次命中的常规反馈；命中演出本身（月牙/扇面/闪光/材质声）不受影响
static func try_spawn_earth_crack(w, hit_pos: Vector2, hit_radius: float) -> void:
	var tags: Array = WeaponData.tags_of(w.weapon_def_id)
	if not tags.has("earth"):
		return
	var now_ms := Time.get_ticks_msec()
	if now_ms - _last_earth_crack_ms < EARTH_CRACK_MIN_GAP_MS:
		return
	_last_earth_crack_ms = now_ms
	var player: Node2D = GameManager.player
	var battle_layer: Node = player.get_parent() if (player != null and player.get_parent() != null) else (w.get_tree().current_scene if w.get_tree() != null else w)
	if battle_layer != null and w.is_inside_tree():
		GroundDecal.spawn(battle_layer, hit_pos, GroundDecal.Kind.CRACK, hit_radius)
