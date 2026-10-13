class_name UnitCombatTests
extends UnitTestsBase

## 单测模块：护甲受伤 / 敌方火球口径 / 震屏创伤 / 震退方向 / 妖狼长扑几何（从 tests/unit_runner.gd 拆出，2026-10-11）。
## 调用顺序与判据契约（UNIT_RESULT: ALL PASS / 退出码）由 UnitRunner 统一保证；
## _c 与 EPS 继承自 UnitTestsBase，函数体与拆分前逐字一致。
func _test_armor() -> void:
	_c.near(GameBalance.armor_reduction(0.0), 0.0, EPS, "0 护甲无减伤")
	_c.near(GameBalance.armor_reduction(10.0), 1.0 - 1.0 / 1.8, EPS, "10 护甲减伤 44.4%")
	_c.near(GameBalance.incoming_damage(100.0, 10.0), 100.0 * (1.0 - GameBalance.armor_reduction(10.0)), 0.01, "面板减伤与实伤同源")
	_c.near(GameBalance.incoming_damage(1.0, 5000.0), GameBalance.DAMAGE_FLOOR, EPS, "极高护甲仍保底 1 点实伤")
	_c.near(GameBalance.incoming_damage(50.0, -20.0), 50.0, EPS, "负护甲不会被当成增益")
	var last := 999.0
	var decreasing := true
	for a in range(0, 60):
		var v := GameBalance.incoming_damage(100.0, float(a))
		if v > last + EPS:
			decreasing = false
		last = v
	_c.check(decreasing, "护甲越高实伤单调不增")
	_c.check(GameBalance.armor_reduction(100000.0) < 1.0, "减伤永远达不到 100%")

func _test_enemy_bolt() -> void:
	# 用户口径 2026-10-08：「火球怎么这么大…不要这种透明/虚化的效果，攻击范围多大就显示多大」
	# 旧写法把 128px 的 light_radial 当 additive 外焰套在核心外面，糊开约 70~100px，
	# 而判定半径只有 8px ⇒ 看到的威胁是真实的 4~8 倍。判据钉三件事：
	# 判定半径只由 RADIUS × scale_factor 决定；碰撞与外观共用同一份 radius；不再长出辉光子节点。
	var bolt := EnemyBolt.new()
	_c.near(bolt.radius, EnemyBolt.RADIUS, EPS, "普通火球判定半径 = RADIUS 常数")
	bolt.scale_factor = GameBalance.BOSS_BOLT_SCALE
	add_child(bolt)
	_c.near(bolt.radius, EnemyBolt.RADIUS * GameBalance.BOSS_BOLT_SCALE, EPS, "Boss 环弹按 scale_factor 同步放大")
	var shape := bolt.get_child(0) as CollisionShape2D
	_c.check(shape != null and shape.shape is CircleShape2D, "火球第一个子节点是碰撞体")
	if shape != null and shape.shape is CircleShape2D:
		_c.near((shape.shape as CircleShape2D).radius, bolt.radius, EPS, "判定圆半径 == 画出来的圆半径（同一份 radius）")
	_c.equals(bolt.get_child_count(), 1, "火球没有外焰/尾迹辉光子节点（外观不会超出判定范围）")
	bolt.free()

func _test_screen_shake_budget() -> void:
	# 0. 击退高阻尼急刹与硬直常量（空洞骑士/死亡细胞风格）
	_c.check(GameBalance.HIT_FREEZE_NORMAL > 0.02 and GameBalance.HIT_FREEZE_NORMAL < 0.05, "普通命中局部卡肉冻结为 2~3 帧 (0.035s)")
	_c.check(GameBalance.HIT_FREEZE_CRIT > GameBalance.HIT_FREEZE_NORMAL, "暴击局部卡肉冻结长于普通命中")
	_c.check(GameBalance.KNOCKBACK_DECAY_STUN >= 10.0 and GameBalance.KNOCKBACK_DECAY_STUN <= 16.0, "击退衰减为适度高阻尼急刹 (10~16)")
	_c.check(GameBalance.KNOCKBACK_MAX_SPEED_NORMAL >= 500.0, "普通击退初速允许各法器展现差异")
	_c.check(GameBalance.KNOCKBACK_MAX_SPEED_CRIT > GameBalance.KNOCKBACK_MAX_SPEED_NORMAL, "暴击击退上限高于普通命中")
	_c.check(GameBalance.KNOCKBACK_IMPULSE_SCALE > 1.0, "击退冲量折算系数大于 1.0")
	_c.check(GameBalance.HIT_STUN_NORMAL >= 0.12, "普通硬直至少 0.12s 保证急刹后有原地僵直定身")

	# 1. 纯函数层：预算夹制
	_c.near(GameBalance.trauma_grant(0.09, 0.75), 0.09, EPS, "预算充足时全额发放")
	_c.near(GameBalance.trauma_grant(0.90, 0.75), 0.75, EPS, "单笔被剩余预算夹住")
	_c.near(GameBalance.trauma_grant(0.30, 0.0), 0.0, EPS, "预算耗尽则一分不给")
	_c.near(GameBalance.trauma_grant(-0.2, 0.5), 0.0, EPS, "负数请求按 0 处理")
	_c.near(GameBalance.shake_amount(0.5), 0.25, EPS, "创伤 0.5 → 震幅 0.25（平方关系）")
	_c.near(GameBalance.shake_amount(0.2), 0.04, EPS, "创伤 0.2 → 震幅 0.04（小击只轻颤）")
	_c.near(GameBalance.shake_amount(1.4), 1.0, EPS, "创伤越界夹到 1.0")
	_c.near(GameBalance.shake_duration(0.7), 0.7 / GameBalance.TRAUMA_DECAY, EPS, "震停时长 = 创伤 / 衰减速率")

	# 2. 尸潮模拟：每秒 20 次「小怪死亡」级别的 0.09，一秒内最多只能叠到预算
	var left := GameBalance.TRAUMA_BUDGET
	var got := 0.0
	for i in range(20):
		var grant := GameBalance.trauma_grant(0.09, left)
		left -= grant
		got += grant
	_c.near(got, GameBalance.TRAUMA_BUDGET, 0.001, "高频击杀被夹到每秒 0.75 上限")
	_c.near(left, 0.0, 0.001, "一秒的预算已被刷光")

	# 3. 真相机：连打 3 秒（60 次/秒）也只能停在稳态轻颤，且停手后必定向零；方向性冲击快速回正
	var orig_level := SettingsManager.shake_level()
	SettingsManager.set_val(&"display", &"shake_intensity", &"standard")
	var cam := SmoothCamera.new()
	add_child(cam)
	cam.kick_directional(Vector2.RIGHT, 4.0)
	_c.check(cam.offset.x > 0.5, "方向性冲击即时产生正向位移")
	for i in range(20):
		cam._physics_process(1.0 / 60.0)
	_c.near(cam.offset.x, 0.0, 0.05, "方向性冲击 0.33s 内衰减归零")
	for i in range(180):
		cam.add_trauma(0.09)
		cam._physics_process(1.0 / 60.0)
	var steady := GameBalance.trauma_steady_state()
	_c.check(cam.trauma <= steady + 0.05, "刷满 3 秒创伤仍不超过稳态值 %.2f" % steady)
	# 2026-10-11 震幅上调一档后：最坏稳态位移上限 = 稳态震幅 0.116 × |(14,10)| ≈ 1.99px
	_c.check(cam.offset.length() <= 2.0, "最坏稳态位移不超过 ±2.0px（不再整局猛摇）")
	for i in range(40):
		cam._physics_process(1.0 / 60.0)
	_c.near(cam.trauma, 0.0, EPS, "停手 0.66 秒后创伤归零")
	_c.near(cam.offset.length(), 0.0, EPS, "归零后相机不再偏移")
	# 预算按秒回血：过了窗口就又是满的
	for i in range(70):
		cam._physics_process(1.0 / 60.0)
	_c.near(cam.trauma_budget_left(), GameBalance.TRAUMA_BUDGET, EPS, "一秒窗口过后预算回满")
	cam.queue_free()

	# 4. 档位：关闭 / 轻 / 标准 / 强，且与历史布尔总开关同源
	SettingsManager.set_val(&"display", &"shake_intensity", &"off")
	_c.near(SettingsManager.shake_mult(), 0.0, EPS, "档位「关闭」= 完全不震")
	_c.equals(bool(SettingsManager.get_val(&"display", &"screen_shake", true)), false, "关闭档位同步带动旧总开关")
	SettingsManager.set_val(&"display", &"shake_intensity", &"heavy")
	_c.near(SettingsManager.shake_mult(), 1.7, EPS, "档位「强」= 1.7 倍幅度")
	_c.equals(SettingsManager.shake_level_label(), "强", "档位读数是人话不是系数")
	_c.equals(SettingsManager.shake_level_next(), &"off", "「强」再点一次回到关闭")
	SettingsManager.set_val(&"display", &"screen_shake", false)
	_c.equals(SettingsManager.shake_level(), &"off", "直接关总开关时档位跟着变关闭")
	SettingsManager.set_val(&"display", &"screen_shake", true)
	_c.equals(SettingsManager.shake_level(), &"standard", "重新开启时落回有手感的默认档")
	SettingsManager.set_val(&"display", &"shake_intensity", orig_level)

	# 5. 暴击打击感常量口径（2026-10-11 暴击创伤/击杀特写；全屏金闪已删——高频事件不发整屏脉冲）
	_c.check(GameBalance.CRIT_TRAUMA_NORMAL >= 0.18 and GameBalance.CRIT_TRAUMA_NORMAL < GameBalance.TRAUMA_BUDGET, "普通暴击创伤大于等于 0.18 保证轻颤可见且不破每秒预算")
	_c.check(GameBalance.CRIT_TRAUMA_ELITE > GameBalance.CRIT_TRAUMA_NORMAL, "精英暴击创伤大于普通暴击")
	_c.check(GameBalance.CRIT_KILL_HITSTOP_DURATION > GameBalance.KILL_HITSTOP_DURATION, "暴击击杀顿帧比普通击杀更实")
	_c.check(GameBalance.CRIT_KILL_HITSTOP_MIN_INTERVAL >= GameBalance.KILL_HITSTOP_MIN_INTERVAL, "暴击击杀顿帧限流不宽于普通击杀")
	_c.check(GameBalance.CRIT_KILL_HITSTOP_SCALE <= GameBalance.KILL_HITSTOP_SCALE, "暴击击杀顿帧时间倍率更强/更凝滞")
	_c.check(GameBalance.CRIT_KILL_HITSTOP_SCALE >= 0.12 and GameBalance.KILL_HITSTOP_SCALE >= 0.12, "各级顿帧时间倍率均不低于 0.12 安全地板")

	# 6. 跳字模式档位：智能合并 / 全部显示 / 仅暴击 / 关闭，且与布尔总开关双向同步
	var orig_num_mode: StringName = SettingsManager.damage_number_mode()
	SettingsManager.set_val(&"display", &"damage_number_mode", &"off")
	_c.equals(SettingsManager.damage_number_mode(), &"off", "跳字模式「关闭」设置成功")
	_c.equals(bool(SettingsManager.get_val(&"display", &"damage_numbers", true)), false, "关闭跳字模式带动布尔开关关闭")
	SettingsManager.set_val(&"display", &"damage_number_mode", &"smart")
	_c.equals(SettingsManager.damage_number_mode_label(), "智能合并", "智能合并人话标签正确")
	_c.equals(bool(SettingsManager.get_val(&"display", &"damage_numbers", false)), true, "非关闭跳字模式带动布尔开关开启")
	SettingsManager.set_val(&"display", &"damage_numbers", false)
	_c.equals(SettingsManager.damage_number_mode(), &"off", "关闭布尔开关带动跳字模式切为 off")
	SettingsManager.set_val(&"display", &"damage_numbers", true)
	_c.equals(SettingsManager.damage_number_mode(), &"smart", "开启布尔开关时恢复智能合并模式")
	_c.equals(SettingsManager.damage_number_mode_next(), &"all", "智能合并下一档为全部显示")
	SettingsManager.set_val(&"display", &"damage_number_mode", orig_num_mode)

func _test_knock_direction() -> void:
	var p := Vector2.ZERO
	var src := Vector2(300.0, 0.0)                 # 落点：玩家正东 300 的敌人（正是分配位，不是最近位）
	var e := Vector2(220.0, 0.0)                   # 夹在玩家与落点之间的那个敌人
	var d := GameBalance.knock_dir(src, e, p)
	_c.check(d.dot((e - p).normalized()) >= -EPS * 100.0, "共线对撞不往玩家身上推（得 %s）" % str(d))
	_c.near(d.length(), 1.0, EPS * 100.0, "输出恒为单位向量（各法器击退力度数值不受影响）")
	# 反例自证：旧写法此刻确实在往玩家推 ⇒ 上面那条判据不是空转
	var old_dir := (e - src).normalized()
	_c.check(old_dir.dot((e - p).normalized()) < 0.0, "反例成立：旧写法把落点内侧的敌人推向玩家")
	# 落点外侧维持径向（大印外扩的爽感不许丢）
	_c.check(GameBalance.knock_dir(src, Vector2(380.0, 0.0), p).is_equal_approx(Vector2.RIGHT), "落点外侧原样外炸")
	# 以落点为心、震退半径 95 一整圈，逐个方位都不朝玩家
	for i in range(12):
		var q: Vector2 = src + Vector2(95.0, 0.0).rotated(TAU * float(i) / 12.0)
		var dd := GameBalance.knock_dir(src, q, p)
		_c.check(dd.dot((q - p).normalized()) >= -EPS * 100.0, "落点周围第 %d/12 方位不推向玩家" % (i + 1))
	# 退化输入不许出 NaN / 零长度
	_c.check(GameBalance.knock_dir(e, e, p).is_equal_approx(Vector2.RIGHT), "施力点压在敌人身上→按远离玩家推")
	_c.check(GameBalance.knock_dir(src, p, p).is_equal_approx(Vector2.LEFT), "敌人正贴在玩家身上→维持径向")
	# 玩家位置退回施力点（局外预览、单测）时，方向与纯径向逐位相同
	_c.check(GameBalance.knock_dir(src, e, src).is_equal_approx(old_dir), "玩家位置退回施力点=旧行为")
	# 调用点不许再自己抄径向：那等于把「往玩家身上推」写回去
	for path in ["res://scripts/weapons/ThunderBurst.gd", "res://scripts/weapons/FloatingWeapon.gd", "res://scripts/weapons/SunOrb.gd", "res://scripts/entities/BlessingObelisk.gd"]:
		var text := ""
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			text = f.get_as_text()
		_c.check(not text.contains("(enemy.global_position - global_position).normalized()"), "%s 的震退方向走统一出口" % path)

	# 15 把法器皆有定义合法击退力，且芭蕉扇与番天镇岳印击退力突出
	for w_id in WeaponData.SHOP_POOL:
		var kb := WeaponData.knockback_for(w_id, 0.0)
		_c.check(kb >= 80.0, "法器 %s 配置了有效击退力 (%.0f)" % [w_id, kb])
	_c.check(WeaponData.knockback_for("bajiao_fan") >= 350.0, "芭蕉扇击退力 >= 350（兑现文案‘击退极远’）")
	_c.check(WeaponData.knockback_for("fantian_yin") >= 350.0, "番天镇岳印击退力 >= 350（兑现文案‘强击退’）")

	# 敌人受击定向形变与受击硬直验证
	var test_enemy := EnemyBase.new()
	var squash_horiz := test_enemy._calculate_hit_squash(Vector2(200.0, 10.0), false)
	_c.check(squash_horiz.x < 1.0 and squash_horiz.y > 1.0, "横向受击水平压扁垂直拉伸")
	var squash_vert := test_enemy._calculate_hit_squash(Vector2(10.0, 200.0), false)
	_c.check(squash_vert.x > 1.0 and squash_vert.y < 1.0, "纵向受击垂直压扁水平拉伸")
	test_enemy.free()

# ---------------- 妖狼长扑：位移闭式解与走廊扫掠几何 ----------------

## 真实帧的兑现由 WolfAiCheck 量（⑧⑨⑩），这里只钉公式自己：纸面位移与点到线段最近距离

func _test_charge_geometry() -> void:
	# 匀速冲刺段 + 线性收势段（梯形取一半）；数值与 LeiBeastEnemy.tscn 对齐 384 × (0.75 + 0.25/2)
	_c.near(GameBalance.charge_reach(384.0, 0.75, 0.25), 336.0, EPS, "长扑位移 = 冲刺段 + 收势段一半")
	_c.near(GameBalance.charge_reach(402.5, 0.8, 0.28), 378.35, 0.01, "精英烈雷兽走同一条式子")
	_c.near(GameBalance.charge_reach(384.0, 0.0, 0.0), 0.0, EPS, "零时长 = 零位移（预警线不会凭空画长）")
	_c.check(GameBalance.charge_reach(-100.0, 0.75, 0.25) >= 0.0, "负入参不许出负位移")
	# 走廊：玩家中心到「本帧扫过的那一段」的最近点
	var tail := Vector2(0.0, 0.0)
	var head := Vector2(320.0, 0.0)
	_c.check(GameBalance.seg_closest_point(head, tail, Vector2(160.0, 30.0)).is_equal_approx(Vector2(160.0, 0.0)), "走廊内侧投影回线上")
	_c.check(GameBalance.seg_closest_point(head, tail, Vector2(500.0, 5.0)).is_equal_approx(head), "起跑点之外钳到线段起点")
	_c.check(GameBalance.seg_closest_point(head, tail, Vector2(-40.0, 5.0)).is_equal_approx(tail), "冲过头钳到线段终点（不许穿透继续判）")
	_c.check(GameBalance.seg_closest_point(Vector2(50.0, 50.0), Vector2(50.0, 50.0), Vector2(50.0, 90.0)).is_equal_approx(Vector2(50.0, 50.0)), "零长线段退化成点距（贴边界 clamp 那一帧不炸）")

# ---------------- 属性面板读数：与 Player 实际口径同源 ----------------

## 疾风/神行在身时开面板，移速/攻速读数必须含神通 buff 层（2026-10-11 补漏：
## 旧写法漏乘 buff_*，技能期间面板纹丝不动，报数与实际不符）

func _test_stat_breakdown_buff() -> void:
	GameManager.reset_run()
	var base := StatBreakdown.breakdown(GameManager)
	_c.near(float(base["attack_speed_mult"]), 1.0, EPS, "无 buff 时面板攻速乘区为 1.0")
	GameManager.buff_attack_speed_mult = 0.6
	GameManager.buff_move_speed_mult = 1.6
	var buffed := StatBreakdown.breakdown(GameManager)
	# 移速用比值断言：不依赖测试环境里 player 是否在场/加点残留
	_c.near(float(buffed["attack_speed_mult"]), 0.6, EPS, "疾风在身时面板攻速乘区 0.6")
	_c.near(float(buffed["move_speed"]) / float(base["move_speed"]), 1.6, EPS, "神行在身时面板移速等比 ×1.6")
	_c.near(float(buffed["cdr_pct"]), (1.0 - 0.6) * 100.0, 0.01, "面板冷却缩减随攻速乘区同源")
	GameManager.reset_run()

# ---------------- 命中反馈全局限流闸：死亡爆散 / 镜头微冲击 ----------------

## 微冲击闸判据（2026-10-11 频闪治理）：间隔内普通档拒绝、间隔过后放行。
## 时间戳以真实 t0 为基注入，闸的窗口基线始终落在真实时间轴上，不污染后续走真实时钟的调用。
## （受击火花 / 死亡爆散已整体下线，其 hit_spark_gate / kill_burst_gate 判据随之移除。）
func _test_feel_gates() -> void:
	var t0 := Time.get_ticks_msec()

	var kick_iv := int(GameBalance.MICRO_KICK_MIN_INTERVAL * 1000.0)
	_c.check(GameFeel.micro_kick_gate(t0), "首个普通命中镜头微冲击放行")
	_c.check(not GameFeel.micro_kick_gate(t0 + kick_iv - 1), "间隔内的镜头微冲击被拒")
	_c.check(GameFeel.micro_kick_gate(t0 + kick_iv), "间隔过后微冲击重新放行")
