extends Node

## 随行神通系统判据（真实 Main 场景，不打 mock）：
##   1. SkillData.final_stats 基础值与道统的强化合并（数值唯一真话）
##   2. 冲刺真实产生位移且途中无敌；神行/疾风 buff 写入 GameManager 乘区并精确回滚
##   3. 冷却两段式流转：施放先开效果活跃窗口（冷却不走、再按被拒），窗口走完才进冷却；
##      CD 中拒绝释放、CD 归零可再放；reset_run 后技能字段全清零
## 运行: godot --headless --path . res://tests/SkillCheck.tscn
## 退出码 0 且末行 SKILL_CHECK_RESULT: ALL PASS

var _c := TestCheck.new()

func _ready() -> void:
	call_deferred("_run")

func _dismiss() -> void:
	for node_name in ["LevelUpDialog", "WaveShop", "PlayerStatsDialog", "PauseMenu", "SettingsDialog"]:
		var n := get_node_or_null("/root/Main/UILayer/" + node_name)
		if n != null and n.visible:
			n.visible = false
	get_tree().paused = false

func _check_data() -> void:
	# 基础值（2026-10-11 技能改版：冷却整体下调 + 效果结束才进冷却 + 弱技能附加效果）
	var dash := SkillData.final_stats("dash", "")
	_c.near(float(dash["cooldown"]), 4.0, 0.001, "冲刺基础冷却 4 秒")
	_c.near(float(dash["crit_window"]), 1.0, 0.001, "冲刺必暴窗口 1 秒")
	_c.near(float(dash["distance"]), 95.0, 0.001, "缩地成寸基础距离 95")
	_c.near(float(dash["iframe"]), 0.30, 0.001, "缩地成寸无敌窗口 0.3 秒（位移全程+落地余量）")
	_c.near(float(dash["duration"]), 0.16, 0.001, "冲刺位移耗时 0.16 秒（duration_add 不改位移时长）")
	var gale := SkillData.final_stats("gale", "")
	_c.near(float(gale["cooldown"]), 9.0, 0.001, "神行术基础冷却 9 秒")
	_c.near(float(gale["dodge_add"]), 0.50, 0.001, "神行术期间闪避提升 50%")
	var haste := SkillData.final_stats("haste", "")
	_c.near(float(haste["cooldown"]), 11.0, 0.001, "疾风咒基础冷却 11 秒")
	_c.near(float(haste["power"]), 0.30, 0.001, "疾风咒间隔缩减 30%")
	var aegis := SkillData.final_stats("aegis", "")
	_c.near(float(aegis["cooldown"]), 10.0, 0.001, "金光护体基础冷却 10 秒")
	_c.near(float(aegis["knockback_boost"]), 3.0, 0.001, "金光护体期间击退力度 ×3")
	var renewal := SkillData.final_stats("renewal", "")
	_c.near(float(renewal["cooldown"]), 20.0, 0.001, "回春术基础冷却 20 秒")
	_c.near(float(renewal["pet_heal_pct"]), 0.02, 0.001, "治疗灵兽每拍回复 2% 最大气血")
	_c.near(float(renewal["pet_duration"]), 8.0, 0.001, "治疗灵兽存活 8 秒")
	# 道统强化合并（抽查三个代表：加算/乘算/冷却）
	var jianchi_haste := SkillData.final_stats("haste", "jianchi")
	_c.near(float(jianchi_haste["duration"]), 7.5, 0.001, "剑痴疾风咒持续 5+2.5=7.5 秒")
	var meiying_dash := SkillData.final_stats("dash", "meiying")
	_c.near(float(meiying_dash["distance"]), 95.0 * 1.55, 0.5, "魅影缩地成寸距离 95×1.55=147.25")
	var shiyue_aegis := SkillData.final_stats("aegis", "shiyue")
	_c.near(float(shiyue_aegis["duration"]), 3.0, 0.001, "石岳金光护体 2.0+1.0=3.0 秒")
	var duobao_aegis := SkillData.final_stats("aegis", "duobao")
	_c.near(float(duobao_aegis["cooldown"]), 6.5, 0.001, "多宝金光护体冷却 10×0.65=6.5 秒")
	var jinsuanpan_renewal := SkillData.final_stats("renewal", "jinsuanpan")
	_c.near(float(jinsuanpan_renewal["power"]), 0.56, 0.001, "商人回春术回复 0.35×1.6=0.56")
	# 契合判定：无强化的组合不许误判
	_c.check(SkillData.is_enhanced_for_cultivator("haste", "jianchi"), "剑痴契合疾风咒")
	_c.check(not SkillData.is_enhanced_for_cultivator("dash", "jianchi"), "剑痴不契合缩地成寸")
	_c.check(not SkillData.enhance_desc("haste", "dubi").is_empty(), "独臂刀圣疾风咒有强化文案")
	_c.check(SkillData.enhance_desc("gale", "jianchi").is_empty(), "剑痴神行术无强化文案")

func _run() -> void:
	_check_data()

	var main = load("res://scenes/main/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	_c.check(is_instance_valid(main), "主场景已进树")

	GameManager.cultivator_id = "jianchi"
	GameManager.pending_skill_id = "gale"
	GameManager.start_run("qingyun_sword")
	get_tree().paused = false
	_dismiss()
	# 等 WaveSpawner 从 WAITING 进 FIGHT（技能只允许战斗中释放）
	for i in range(12):
		await get_tree().process_frame
		_dismiss()
	var player: Player = GameManager.player
	_c.check(player != null, "玩家已生成")
	_c.equals(GameManager.active_skill_id, "gale", "start_run 后 pending 神通转正")

	var spawner: WaveSpawner = GameManager.wave_spawner
	_c.check(spawner != null and int(spawner.phase) == int(WaveSpawner.Phase.FIGHT), "已进入战斗阶段（技能才可释放）")

	var vfx: PlayerSkillVfx = player.skill_vfx
	_c.check(vfx != null, "玩家 SkillVfx 特效控制器节点已挂载")
	# 尺寸包裹判据：程序化角色实际身形宽 ±12、头顶 y≈-18、脚底 y≈+24（PlayerSkillVfx 常量区注释）
	var shield_top: float = PlayerSkillVfx.SHIELD_CENTER.y - PlayerSkillVfx.SHIELD_RY
	var shield_bot: float = PlayerSkillVfx.SHIELD_CENTER.y + PlayerSkillVfx.SHIELD_RY
	_c.check(shield_top <= -18.0 and shield_bot >= 24.0 and PlayerSkillVfx.SHIELD_RX >= 12.0,
		"金光护体椭球罩罩住程序化身形头顶至脚底（Y:[%.0f, %.0f], RX:%.0f）" % [shield_top, shield_bot, PlayerSkillVfx.SHIELD_RX])
	_c.check(absf(PlayerSkillVfx.HASTE_FEET.y - 22.0) <= 4.0 and PlayerSkillVfx.HASTE_WHEEL_RX >= 20.0,
		"疾风咒脚下风轮锚定真实脚底且覆盖身宽（feet y:%.0f, RX:%.0f）" % [PlayerSkillVfx.HASTE_FEET.y, PlayerSkillVfx.HASTE_WHEEL_RX])

	# ---- 神行术：移速/闪避双乘区 + 效果活跃窗口（冷却不走、活跃中拒绝再放）+ 到期精确回滚 ----
	_c.check(player.try_activate_skill(), "神行术首次释放成功")
	_c.near(GameManager.buff_move_speed_mult, 1.6, 0.001, "神行术写入移速乘区 1.6")
	_c.near(GameManager.buff_dodge, 0.5, 0.001, "神行术写入闪避加成 0.5")
	_c.check(vfx.gale_active, "神行术激活角色足底御风特效")
	_c.check(player.skill_active_left > 0.0, "释放后进入效果活跃窗口")
	_c.near(player.skill_cd_left, 0.0, 0.001, "活跃窗口内冷却尚未起转（效果结束才计冷却）")
	_c.check(not player.try_activate_skill(), "效果活跃中再次释放被拒绝")
	# buff 到期精确回滚（拨快倒计时，不等满 4 秒）
	player._skill_buffs["gale"] = 0.02
	vfx.gale_timer = 0.02
	player.skill_active_left = 0.02
	for i in range(6):
		await get_tree().physics_frame
	_c.near(GameManager.buff_move_speed_mult, 1.0, 0.001, "神行术到期后移速乘区精确回滚 1.0")
	_c.near(GameManager.buff_dodge, 0.0, 0.001, "神行术到期后闪避加成精确归零")
	_c.check(not vfx.gale_active, "神行术到期后角色足底御风特效关闭")
	_c.check(player._skill_buffs.is_empty(), "buff 表已清空")
	_c.near(player.skill_cd_left, 9.0, 0.3, "效果结束此刻才进冷却（9 秒档）")

	# ---- 疾风咒：写入攻速乘区（剑痴契合 → 持续 7.5 秒） ----
	GameManager.active_skill_id = "haste"
	player.skill_cd_left = 0.0
	player.skill_active_left = 0.0
	_c.check(player.try_activate_skill(), "疾风咒释放成功")
	_c.near(GameManager.buff_attack_speed_mult, 0.7, 0.001, "疾风咒写入攻速乘区 0.7（间隔缩短 30%）")
	_c.near(float(player._skill_buffs.get("haste", 0.0)), 7.5, 0.05, "剑痴契合：疾风咒持续 7.5 秒")
	_c.check(vfx.haste_active, "疾风咒激活角色脚底八卦风环特效")
	player._skill_buffs["haste"] = 0.02
	vfx.haste_timer = 0.02
	player.skill_active_left = 0.02
	for i in range(6):
		await get_tree().physics_frame
	_c.near(GameManager.buff_attack_speed_mult, 1.0, 0.001, "疾风咒到期后攻速乘区精确回滚 1.0")
	_c.check(not vfx.haste_active, "疾风咒到期后角色脚底八卦风环特效关闭")

	# ---- 金光护体：无敌计时起 + 击退乘区 + 效果结束才进冷却 ----
	GameManager.active_skill_id = "aegis"
	player.skill_cd_left = 0.0
	player.skill_active_left = 0.0
	player.invulnerable_time = 0.0
	_c.check(player.try_activate_skill(), "金光护体释放成功")
	_c.near(player.invulnerable_time, 2.0, 0.1, "金光护体起 2.0 秒无敌")
	_c.near(GameManager.buff_knockback_mult, 3.0, 0.001, "金光护体期间法器击退力度 ×3")
	_c.near(player.skill_cd_left, 0.0, 0.001, "无敌进行中冷却尚未起转")
	_c.check(vfx.aegis_active, "金光护体激活六方法印结界与金芒护罩")
	vfx.aegis_timer = 0.02
	player.skill_active_left = 0.02
	for i in range(6):
		await get_tree().physics_frame
	_c.near(GameManager.buff_knockback_mult, 1.0, 0.001, "金光护体到期后击退乘区回 1.0")
	_c.check(not vfx.aegis_active, "金光护体到期后结界转入碎灭散逸")
	_c.near(player.skill_cd_left, 10.0, 0.3, "无敌效果结束此刻才进冷却（10 秒档）")

	# ---- 回春术：按最大气血比例回复 + 瞬发即进冷却 + 治疗灵兽召唤与节拍 ----
	GameManager.active_skill_id = "renewal"
	player.skill_cd_left = 0.0
	player.skill_active_left = 0.0
	player.invulnerable_time = 0.0
	player.current_health = player.max_health * 0.4
	_c.check(player.try_activate_skill(), "回春术释放成功")
	_c.near(player.current_health, player.max_health * 0.75, 1.0, "回春术回复 35% 最大气血")
	_c.check(vfx.renewal_progress >= 0.0, "回春术激活甘露莲花阵与旋升青芒光柱")
	_c.near(player.skill_cd_left, 20.0, 0.3, "瞬发治疗按下当帧直接进冷却（20 秒档）")
	var healer: SpiritHealer = get_tree().get_first_node_in_group("spirit_healers")
	_c.check(healer != null, "回春术召出治疗灵兽")
	if healer != null:
		_c.check(healer.target == player, "灵兽跟随玩家（target 指向玩家）")
		_c.near(healer.heal_pct, 0.02, 0.001, "灵兽每拍回复 2% 最大气血")
		# 重施替换旧灵
		player.skill_cd_left = 0.0
		player.skill_active_left = 0.0
		_c.check(player.try_activate_skill(), "回春术可再次释放（瞬发冷却已清）")
		var healer2: SpiritHealer = get_tree().get_first_node_in_group("spirit_healers")
		_c.check(healer2 != null and healer2 != healer, "重施治疗替换旧灵兽")
		# 节拍生效：拨快首拍倒计时，等它把气血灌回来
		player.current_health = player.max_health * 0.5
		healer2._pulse_timer = 0.02
		for i in range(12):
			await get_tree().physics_frame
		_c.check(player.current_health > player.max_health * 0.5 + 0.01, "灵兽节拍生效：气血回升（现 %.0f/%.0f）" % [player.current_health, player.max_health])

	# ---- 缩地成寸：真实位移 + 途中无敌 + 必暴窗口 + 无敌窗口走完才进冷却 ----
	GameManager.active_skill_id = "dash"
	player.skill_cd_left = 0.0
	player.skill_active_left = 0.0
	GameManager.force_crit_left = 0.0
	player.invulnerable_time = 0.0
	player.velocity = Vector2.ZERO
	player.facing = "s"
	var dash_nominal: float = float(SkillData.final_stats("dash", GameManager.cultivator_id)["distance"])
	var before: Vector2 = player.global_position
	_c.check(player.try_activate_skill(), "缩地成寸释放成功")
	_c.check(vfx.dash_flash_timer > 0.0, "缩地成寸激活瞬身刀光与破空灵芒锥")
	_c.check(vfx.dash_crit_timer > 0.0, "缩地成寸激活必暴期间双眸发光视觉")
	_c.near(player.invulnerable_time, 0.30, 0.01, "冲刺起即无敌 0.30 秒（实测 %.2f s）" % player.invulnerable_time)
	_c.near(GameManager.force_crit_left, 1.0, 0.1, "冲刺起跳开 1 秒必暴窗口")
	_c.check(GameManager.roll_crit(), "必暴窗口内 roll_crit 恒真")
	_c.near(player.skill_cd_left, 0.0, 0.001, "冲刺无敌窗口内冷却尚未起转")
	# 跑到冲刺段结束（逐帧盯 _dash_time，不靠猜帧数：headless 的 delta 不保证正好 1/60）
	var dash_frames := 0
	while player._dash_time > 0.0 and dash_frames < 40:
		await get_tree().physics_frame
		_dismiss()
		dash_frames += 1
	var dash_moved: float = player.global_position.distance_to(before)
	_c.near(dash_moved, dash_nominal * 0.94, dash_nominal * 0.14,
			"冲刺段位移与数据表同源（实测 %.0f px，纸面 %.0f）" % [dash_moved, dash_nominal])
	_c.check(player.invulnerable_time > 0.0, "冲刺落地后仍有无敌余量（剩余 %.2f s）" % player.invulnerable_time)
	# 落地收速判据：旧写法这里会再滑出去 590px（峰值 1625px/s 慢慢掉回常速），纸面 260 实际 830+
	for i in range(60):
		await get_tree().physics_frame
		_dismiss()
	var total_moved: float = player.global_position.distance_to(before)
	_c.check(total_moved <= dash_nominal * 1.35,
			"落地即收速：1 秒内总位移 ≤ 纸面 1.35 倍（实测 %.0f px，纸面 %.0f）" % [total_moved, dash_nominal])
	# 60 帧已把 0.3s 无敌窗口走完：此刻冷却应在 4 秒档起转（已走过约 0.7s）
	_c.check(player.skill_active_left <= 0.0, "冲刺无敌窗口走完，活跃状态结束")
	_c.check(player.skill_cd_left > 3.0 and player.skill_cd_left <= 4.0,
			"无敌窗口走完才进冷却（4 秒档起转，实测 %.2f s）" % player.skill_cd_left)
	player.skill_cd_left = 0.0
	player.skill_active_left = 0.0
	await get_tree().physics_frame
	_c.check(player.try_activate_skill(), "冷却归零后可再次释放")

	# ---- HUD 技能按钮交互判据：圆形半透明 + 触控双指响应 + 按下即放 ----
	var hud: GameHUD = main.get_node_or_null("UILayer/GameHUD")
	_c.check(hud != null, "HUD 节点存在")
	await get_tree().process_frame
	var skill_box: Control = hud.get("_skill_box")
	var skill_btn: Button = hud.get("_skill_btn")
	_c.check(skill_box != null and skill_btn != null, "HUD 技能按钮节点已构建")
	_c.check(skill_box.visible, "战斗中技能按钮处于可见态")
	_c.near(skill_btn.size.x, GameHUD.SKILL_BTN_SIZE, 1.0, "技能按钮尺寸符合规范 76px")

	# 测试点按 HUD 按钮（鼠标模拟单点）触发释放：按下先开活跃窗口，冷却不走
	player.skill_cd_left = 0.0
	player.skill_active_left = 0.0
	var mouse_ev := InputEventMouseButton.new()
	mouse_ev.button_index = MOUSE_BUTTON_LEFT
	mouse_ev.pressed = true
	mouse_ev.position = skill_btn.size * 0.5
	hud._on_skill_btn_input(mouse_ev)
	await get_tree().process_frame
	_c.check(player.skill_active_left > 0.0 and player.skill_cd_left <= 0.0,
			"点击 HUD 按钮按下即放触发技能（先活跃后冷却）")

	# 测试第二根手指（触屏双指拉摇杆时 index = 1）触控直通
	player.skill_cd_left = 0.0
	player.skill_active_left = 0.0
	var touch_ev := InputEventScreenTouch.new()
	touch_ev.index = 1
	touch_ev.pressed = true
	touch_ev.position = skill_btn.global_position + skill_btn.size * 0.5
	hud._input(touch_ev)
	await get_tree().process_frame
	_c.check(player.skill_active_left > 0.0 and player.skill_cd_left <= 0.0,
			"第二根手指触控直通触发技能（解决移动中点技能无反应）")

	# 测试活跃/冷却中点击：产生抖动反馈
	await get_tree().process_frame
	hud._trigger_skill_press()
	_c.check(bool(hud.get("_skill_shaking")), "活跃或冷却中点击触发震颤反馈")

	# ---- 额外技能按钮（影爆）：第二颗键独立触发、无冷却、随角色显隐 ----
	var extra_box: Control = hud.get("_extra_skill_box")
	var extra_btn: Button = hud.get("_extra_skill_btn")
	_c.check(extra_box != null and extra_btn != null, "HUD 额外技能按钮节点已构建")
	GameManager.extra_skill_id = "shadowburst"
	player.shadow_ring = []
	player.shadow_ring = ShadowStepData.push_ring(player.shadow_ring, 40.0)
	GameManager.shadow_amp_mult = ShadowStepData.amp_mult(player.shadow_ring)
	await get_tree().process_frame
	_c.check(extra_box.visible, "有额外技能时额外按钮处于可见态")
	_c.equals(extra_btn.text, "爆", "额外按钮键面用影爆字面（图标未出图时走字面兜底）")
	var cd_before: float = player.skill_cd_left
	_c.check(player.try_activate_extra_skill(), "影爆走额外技能入口释放成功")
	_c.check(player.shadow_ring.is_empty(), "影爆兑现后影层清空")
	_c.near(player.skill_cd_left, cd_before, 0.001, "影爆释放不动主键冷却账（资源门控而非 CD，两颗键各记各的）")
	# 无额外技能的角色：额外按钮整颗隐藏
	GameManager.extra_skill_id = ""
	await get_tree().process_frame
	_c.check(not extra_box.visible, "无额外技能时额外按钮隐藏（多数角色看不到这颗键）")

	# ---- reset_run 清零 ----
	GameManager.reset_run()
	_c.equals(GameManager.active_skill_id, "", "reset_run 清空本局技能")
	_c.equals(GameManager.extra_skill_id, "", "reset_run 清空本局额外技能")
	_c.near(GameManager.buff_move_speed_mult, 1.0, 0.001, "reset_run 回滚移速 buff 乘区")
	_c.near(GameManager.buff_attack_speed_mult, 1.0, 0.001, "reset_run 回滚攻速 buff 乘区")
	_c.near(GameManager.buff_dodge, 0.0, 0.001, "reset_run 归零闪避 buff")
	_c.near(GameManager.buff_knockback_mult, 1.0, 0.001, "reset_run 回滚击退 buff 乘区")
	_c.near(GameManager.force_crit_left, 0.0, 0.001, "reset_run 清零必暴窗口")

	if _c.report("SKILL_CHECK_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)
