class_name UnitInfraTests
extends UnitTestsBase

## 单测模块：音频接线 / 设置模块 / 开局无尽 / 成就与元进度存档 / 生涯里程碑（从 tests/unit_runner.gd 拆出，2026-10-11）。
## 调用顺序与判据契约（UNIT_RESULT: ALL PASS / 退出码）由 UnitRunner 统一保证；
## _c 与 EPS 继承自 UnitTestsBase，函数体与拆分前逐字一致。
func _test_audio_wiring() -> void:
	var missing: Array = AudioManager.missing_paths()
	_c.check(missing.is_empty(), "注册表里的音效文件全部就位（缺: %s）" % str(missing))

	var needed := [
		"blade_shoot", "enemy_hit", "enemy_hit_crit", "enemy_hit_heavy", "orb_hit", "gem_pickup", "level_up", "obelisk_blessing",
		"enemy_death", "enemy_death_elite", "talisman_throw", "thunder_strike",
		"fan_gust", "shop_buy", "shop_reroll", "shop_lock", "sell", "equip", "unequip",
		"merge_success", "ui_click", "ui_back", "ui_error", "wave_start", "wave_clear",
		"boss_raid", "dodge", "heal", "victory", "defeat",
		# 器型族（2026-10-10）：原 sword_swing 已彻底删除（配方是纯空气破空、零金属泛音，
		# 剑与木棍听起来同一个声；敌我分源后再无人引用）
		"whoosh_light", "whoosh_heavy", "impact_blade", "impact_blunt", "impact_crack",
		"metal_dart", "flame_jet", "drum_boom", "flute_wave", "drone_flutter", "drone_chime",
		"enemy_claw", "enemy_bolt", "enemy_fuse", "enemy_slam", "enemy_blink",
	]
	var silent: Array = []
	for k in needed:
		if not AudioManager.has_sfx(k):
			silent.append(k)
	_c.check(silent.is_empty(), "游戏会用到的 %d 个音效 key 都能播（哑的: %s）" % [needed.size(), str(silent)])

	# 数据表里配的 sfx 必须是已注册 key，否则 WeaponData 改了名而 AudioManager 没跟上。
	# 第二层 sfx_impact 只许近战与雷法配：弹丸的入肉声由被击敌人的 enemy_hit 承担，
	# 环绕只有触敌一层 —— 配了就是白配（取音方根本不读），必须当场报红。
	var bad_table: Array = []
	var bad_impact: Array = []
	var missing_impact: Array = []
	for w_id in WeaponData.SHOP_POOL:
		var k: String = WeaponData.sfx_for(w_id)
		if not AudioManager.has_sfx(k):
			bad_table.append("%s→%s" % [w_id, k])
		var beh := int(WeaponData.DEFS[w_id].get("behavior", -1))
		var ik: String = WeaponData.sfx_impact_for(w_id)
		if beh == WeaponData.Behavior.MELEE or beh == WeaponData.Behavior.BURST or beh == WeaponData.Behavior.SWEEP:
			if ik == "":
				missing_impact.append(w_id)
			elif not AudioManager.has_sfx(ik):
				bad_impact.append("%s→%s" % [w_id, ik])
		elif ik != "":
			bad_impact.append("%s 配了第二层 %s（该行为没有命中帧）" % [w_id, ik])
	_c.check(bad_table.is_empty(), "每件法器的第一层音都注册过（异常: %s）" % str(bad_table))
	_c.check(bad_impact.is_empty(), "命中/落点音注册过且只给近战与雷法配（异常: %s）" % str(bad_impact))
	_c.check(missing_impact.is_empty(), "近战与雷法都配了第二层，双层不许漏一层（漏配: %s）" % str(missing_impact))
	_c.equals(WeaponData.sfx_for("qingyun_sword"), "whoosh_light", "长剑前摇走破空族，不再一声打到底")
	_c.equals(WeaponData.sfx_impact_for("qingyun_sword"), "impact_blade", "长剑命中走刃金族（这才是「像剑」的那一声）")
	_c.equals(WeaponData.sfx_impact_for("benlang_chui"), "impact_blunt", "崩浪锤是钝器，不许跟着风扇吹")
	_c.equals(WeaponData.sfx_for("sanmei_huohu"), "flame_jet", "火葫芦喷焰，不再是甩飞剑那一声")
	_c.equals(WeaponData.sfx_for("wulei_paizi"), "whoosh_light", "落雷系施法与落点分两层，落点才配 thunder_strike")
	_c.equals(WeaponData.sfx_impact_for("wulei_paizi"), "thunder_strike", "雷牌落点听的是雷，不是钟和铃")
	_c.equals(WeaponData.sfx_for("不存在的法器"), "blade_shoot", "未知 id 回落到通用开火音")

	for bus in ["Master", "BGM", "SFX", "Voice"]:
		_c.check(AudioServer.get_bus_index(StringName(bus)) >= 0, "总线 %s 存在" % bus)

	# 音量读写往返 + 落盘（测完还原成原值，不弄脏用户的设置）
	var before := AudioManager.get_bus_linear(&"SFX")
	AudioManager.set_bus_linear(&"SFX", 0.5)
	_c.near(AudioManager.get_bus_linear(&"SFX"), 0.5, 0.01, "SFX 音量设 50% 后读回一致")
	AudioManager.set_bus_linear(&"SFX", 0.0)
	_c.check(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"SFX")), "拉到 0 真静音（不留 -inf 残响）")
	AudioManager.set_bus_linear(&"SFX", before)
	_c.near(AudioManager.get_bus_linear(&"SFX"), before, 0.01, "音量已还原为 %.2f" % before)

	# BGM 状态机：素材齐备 + 真能切换 + 未知 key 不打断当前播放
	for key in AudioManager.BGM_TABLE.keys():
		var path: String = AudioManager.BGM_TABLE[key].get("path", "")
		_c.check(ResourceLoader.exists(path), "BGM 素材就位：%s (%s)" % [key, path.get_file()])
	AudioManager.play_bgm_key("menu")
	_c.equals(String(AudioManager.bgm_key), "menu", "主菜单切到 menu")
	AudioManager.play_bgm_key("battle")
	_c.equals(String(AudioManager.bgm_key), "battle", "battle 在播")
	AudioManager.play_bgm_key("shop")
	_c.equals(String(AudioManager.bgm_key), "shop", "商店阶段切到 shop")
	AudioManager.play_bgm_key("trial")
	_c.equals(String(AudioManager.bgm_key), "trial", "Boss阶段切到 trial")
	AudioManager.play_bgm_key("victory")
	_c.equals(String(AudioManager.bgm_key), "victory", "胜利结算切到 victory")
	AudioManager.play_bgm_key("defeat")
	_c.equals(String(AudioManager.bgm_key), "defeat", "失败结算切到 defeat")
	AudioManager.play_bgm_key("defeat")
	_c.equals(String(AudioManager.bgm_players[AudioManager.bgm_next].stream.resource_path),
		AudioManager.BGM_TABLE["defeat"]["path"], "重复调同一 key 不会重头播")
	AudioManager.play_bgm_key("这个 key 不存在")
	_c.equals(String(AudioManager.bgm_key), "defeat", "未知 BGM key 不影响当前播放")
	AudioManager.play_bgm_key("menu")

func _test_settings_manager() -> void:
	# 1. 保存当前用户状态以便测试后恢复
	var orig_master := SettingsManager.get_bus_volume(&"Master")
	var orig_master_mute := SettingsManager.is_bus_muted(&"Master")
	var orig_dmg_num := bool(SettingsManager.get_val(&"display", &"damage_numbers", true))
	var orig_shake := bool(SettingsManager.get_val(&"display", &"screen_shake", true))

	# 2. 音量与静音切换
	SettingsManager.set_bus_volume(&"Master", 0.65)
	_c.near(SettingsManager.get_bus_volume(&"Master"), 0.65, 0.01, "主音量设定 65% 读取一致")
	SettingsManager.set_bus_muted(&"Master", true)
	_c.check(SettingsManager.is_bus_muted(&"Master"), "主音量静音状态生效")
	_c.check(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Master")), "AudioServer Master 总线已同步静音")
	# 拖动音量大于 0 应自动解除静音
	SettingsManager.set_bus_volume(&"Master", 0.8)
	_c.check(not SettingsManager.is_bus_muted(&"Master"), "调高音量自动解除静音状态")

	# 3. 画面与战斗反馈开关读写
	SettingsManager.set_val(&"display", &"damage_numbers", false)
	_c.equals(bool(SettingsManager.get_val(&"display", &"damage_numbers", true)), false, "关闭伤害跳字配置生效")
	SettingsManager.set_val(&"display", &"screen_shake", false)
	_c.equals(bool(SettingsManager.get_val(&"display", &"screen_shake", true)), false, "关闭屏幕震动配置生效")

	# 4. 恢复默认设置
	SettingsManager.reset_to_defaults()
	_c.near(SettingsManager.get_bus_volume(&"Master"), 1.0, 0.01, "重置默认后主音量恢复 100%")
	_c.equals(bool(SettingsManager.get_val(&"display", &"damage_numbers", false)), true, "重置默认后伤害跳字恢复开启")
	_c.equals(bool(SettingsManager.get_val(&"display", &"screen_shake", false)), true, "重置默认后屏幕震动恢复开启")
	_test_floating_btn_defaults()
	_test_settings_and_reset_robustness()

	# 5. 还原测试前状态
	SettingsManager.set_bus_volume(&"Master", orig_master)
	SettingsManager.set_bus_muted(&"Master", orig_master_mute)
	SettingsManager.set_val(&"display", &"damage_numbers", orig_dmg_num)
	SettingsManager.set_val(&"display", &"screen_shake", orig_shake)

## 三颗浮动键的出厂摆位与键面文案（用户 2026-10-11 真机图：祭坛键和技能键贴在一起，
## 看着就是两颗压成一颗；键面只写「祭坛」也看不出按下去是干什么的）。
## 只在 reset_to_defaults() 之后跑：那时读到的就是出厂位，不受玩家自己拖过的存档影响。
## 位置是归一化的、键径是设计像素定值，所以两圆间距在 960×540 这一档最小
## （视口更高只会更开），拿它当尺子量到的是最坏情况。
func _test_floating_btn_defaults() -> void:
	var design_h := 540.0
	var d := SkillButtonView.SKILL_BTN_SIZE
	# 一、SCHEMA 里的 default 与常量同源：抄两份数字，早晚会「设置页显示 A、实际生效 B」
	_c.equals(SettingsManager.obelisk_btn_xy(), SettingsManager.OBELISK_BTN_XY_DEFAULT,
			"祭坛键出厂位取自 OBELISK_BTN_XY_DEFAULT（不是 SCHEMA 里另抄的一份）")
	_c.equals(SettingsManager.skill_btn_xy(), SettingsManager.SKILL_BTN_XY_DEFAULT,
			"技能键出厂位取自 SKILL_BTN_XY_DEFAULT")
	_c.equals(SettingsManager.extra_btn_xy(), SettingsManager.EXTRA_BTN_XY_DEFAULT,
			"额外技能键出厂位取自 EXTRA_BTN_XY_DEFAULT（不是 SCHEMA 里另抄的一份）")
	# 二、相邻两圆之间必须留得开：旧写法 0 空隙相切，量出来正好 0（三键两两同列检查）
	var gap := (SettingsManager.skill_btn_xy().y - SettingsManager.obelisk_btn_xy().y) * design_h - d
	_c.check(gap >= SettingsManager.BTN_DEFAULT_EDGE_GAP - 0.01,
			"出厂摆位两圆圆边之间留 %.1f 设计像素（要求 >= %.0f；0 空隙时两圈描边贴成一颗）" % [
					gap, SettingsManager.BTN_DEFAULT_EDGE_GAP])
	_c.check(gap <= d, "两圆也没开成一里地（%.1f <= 键径 %.0f，同列叠放还要一眼看出是一对）" % [gap, d])
	var gap_extra := (SettingsManager.obelisk_btn_xy().y - SettingsManager.extra_btn_xy().y) * design_h - d
	_c.check(gap_extra >= SettingsManager.BTN_DEFAULT_EDGE_GAP - 0.01,
			"额外技能键与祭坛键出厂圆边间距 %.1f（要求 >= %.0f，第三颗键进同列不挤堆）" % [
					gap_extra, SettingsManager.BTN_DEFAULT_EDGE_GAP])
	_c.check(gap_extra <= d, "额外技能键与祭坛键也没开成一里地（%.1f <= 键径 %.0f）" % [gap_extra, d])
	# 三、键面文案收在圆面之内：量的是「画出来的那一圈」——文案外接框的对角半径
	#     要小于圆面内缘（键径一半再收掉 _circle_box 那 2 像素描边）。
	#     三颗浮动键的文案进同一张表，用同一把尺子（额外技能键的占位字面也走这里，
	#     用户 2026-10-11：原先写英文 "extra"，改中文四字后必须证明它收得进圆面不漏字）
	var f := GameStyle.display_font()
	var inner_r := d * 0.5 - 2.0
	var faces: Array[Array] = [
		["祭坛键", HudObeliskButton.BTN_TEXT, HudObeliskButton.BTN_FONT],
		["额外技能键", HudSkillButton.EXTRA_BTN_TEXT, HudSkillButton.EXTRA_BTN_FONT],
	]
	for face in faces:
		var label: String = String(face[1])
		var font_px: int = int(face[2])
		var box: Vector2 = f.get_multiline_string_size(label,
				HORIZONTAL_ALIGNMENT_CENTER, -1.0, font_px)
		var corner := box.length() * 0.5
		_c.check(not label.contains("extra"),
				"%s：键面不再写英文占位「%s」（玩家看不出那是颗什么键）" % [face[0], label])
		_c.check(box.x <= inner_r * 2.0,
				"%s：文案「%s」每一行都收得进圆面（最长行 %.0f <= 内切宽 %.0f，一行排下去字会探出圆面）" % [
						face[0], label, box.x, inner_r * 2.0])
		_c.check(corner <= inner_r,
				"%s：键面文案收在圆键之内（%.0f×%.0f 外接框角半径 %.1f <= 内缘 %.1f）" % [
						face[0], box.x, box.y, corner, inner_r])
		# 四、也不许压在走针那一圈上：按住充能时那一圈正是拇指盯着的读数
		var ov := SkillButtonView.CircleProgressOverlay.new()
		ov.size = Vector2(d, d)   # 三颗键同径（外观基准钉在 SKILL_BTN_SIZE 一个数上）
		var arc_r := ov.arc_radius()
		ov.free()
		_c.check(corner <= arc_r,
				"%s：键面文案收在走针环之内（角半径 %.1f <= 走针半径 %.1f，按住时那一圈不压在字上）" % [
						face[0], corner, arc_r])

## 存档损坏容错与 RunReset 清理契约（2026-10-13 健壮性优化）：
## 钉住非法类型不崩、_btn_scale 非数值回退 1.0、RunReset 对 live_allies/ally_count/last_run_new_records 清零。
func _test_settings_and_reset_robustness() -> void:
	var fb := SettingsManager.SKILL_BTN_XY_DEFAULT
	_c.equals(SettingsManager._norm_xy("corrupt_str", fb), fb, "非法字符串传入 _norm_xy 安全回退默认值")
	_c.equals(SettingsManager._norm_xy(999, fb), fb, "整数传入 _norm_xy 安全回退默认值")
	_c.near(SettingsManager._btn_scale("corrupt_scale"), 1.0, 0.001, "非法文本传入 _btn_scale 回落 1.0")
	_c.equals(SettingsManager._to_bool("corrupt_bool", false), false, "非法文本传入 _to_bool 回退默认 false")
	_c.equals(SettingsManager._to_bool("true", false), true, "文本 'true' 传入 _to_bool 解析为 true")

	var dummy := Node2D.new()
	add_child(dummy)
	GameManager.register_ally(dummy)
	GameManager.last_run_new_records.append("测试残留纪录")
	GameManager.reset_run()
	_c.check(GameManager.live_allies.is_empty(), "reset_run 清空 live_allies")
	_c.equals(GameManager.ally_count, 0, "reset_run 清零 ally_count")
	_c.check(GameManager.last_run_new_records.is_empty(), "reset_run 清空 last_run_new_records")
	dummy.queue_free()

# ---------------- 震屏：创伤预算与强度档位 ----------------

## 判据的由来：镜头曾经整局在摇（普通命中与小怪死亡每次都发创伤，累加起来永远归不了零）。
## 修完之后靠两条钉住：① 创伤只发给"值得看的节点"（口径写在 GameBalance 段注释里）；
## ② 就算将来有人再拿高频事件乱发，每秒预算也把最坏震幅钉在轻颤级别。

func _test_start_in_endless() -> void:
	GameManager.reset_run()
	_c.check(not GameManager.endless_mode, "默认开局非无尽模式")
	_c.check(not GameManager.start_in_endless, "默认 start_in_endless 为 false")

	# 设置从主菜单直接进入无尽试炼
	GameManager.set_start_in_endless(true)
	_c.check(GameManager.start_in_endless, "set_start_in_endless 生效")
	GameManager.reset_run()
	_c.check(GameManager.start_in_endless, "reset_run 保留主菜单无尽开关状态")

	GameManager.cultivator_id = "jianchi"
	GameManager.start_run("qingyun_sword")
	_c.check(GameManager.endless_mode, "开启无尽开关后 start_run 自动激活 endless_mode")

	# 恢复默认
	GameManager.set_start_in_endless(false)
	GameManager.reset_run()
	GameManager.cultivator_id = "jianchi"
	GameManager.start_run("qingyun_sword")
	_c.check(not GameManager.endless_mode, "关闭后恢复普通模式")
	GameManager.reset_run()

func _test_achievement_and_meta_save() -> void:
	# 1. 数据表完整性与反查自洽
	_c.equals(AchievementData.ACHIEVEMENTS.size(), 24, "成就共配置 24 条（16 奖励型 + 8 纯荣誉型）")
	for aid in AchievementData.all_ids():
		var adef := AchievementData.get_def(aid)
		_c.check(not adef.is_empty(), "成就 %s 定义存在" % aid)
		_c.check(String(adef.get("category", "")) in AchievementData.CATEGORY_ORDER,
			"成就 %s 分类归属四大类之一" % aid)
		var rtype := String(adef.get("reward_type", ""))
		var rid := String(adef.get("reward_id", ""))
		if rtype == "cultivator":
			_c.check(not CultivatorData.get_def(rid).is_empty(), "成就 %s 奖励修士 %s 在修士表中存在" % [aid, rid])
			_c.equals(AchievementData.cultivator_unlock_achievement(rid).get("id", ""), aid, "反查修士 %s 解锁成就一致" % rid)
		elif rtype == "item":
			_c.check(not ItemData.get_def(rid).is_empty(), "成就 %s 奖励法宝 %s 在法宝表中存在" % [aid, rid])
			_c.equals(AchievementData.item_unlock_achievement(rid).get("id", ""), aid, "反查法宝 %s 解锁成就一致" % rid)
		else:
			_c.equals(rtype, "none", "成就 %s 非角色/法宝奖励时必须为纯荣誉 none 型" % aid)
			_c.equals(AchievementData.DEFAULT_CULTIVATORS.size(), 8, "初始默认开放 8 名基础修士")
		_c.equals(AchievementData.DEFAULT_ITEMS.size(), 83, "初始默认开放 83 件基础法宝（全 87 件除去 4 件成就解锁）")

	# 1.1 解锁覆盖：每名角色都必须有途径——要么默认解锁，要么反查得到成就。
	# 御兽师曾两处都没列（7 默认 + 12 成就 = 19），选角页永远「暂无收录途径」，
	# 这条断言就是钉住这种「加了角色但忘了给门」的回归。
	var no_way: Array = []
	for cid in CultivatorData.all_ids():
		var is_default: bool = cid in AchievementData.DEFAULT_CULTIVATORS
		if not is_default and AchievementData.cultivator_unlock_achievement(cid).is_empty():
			no_way.append(cid)
	_c.check(no_way.is_empty(), "所有角色均有解锁途径（无途径: %s）" % str(no_way))

	# 2. 法宝过滤入池：未解锁法宝绝不上架
	var rng := RandomNumberGenerator.new()
	rng.seed = 8888
	# 替死傀儡（tisi_kuilei）与混元珠（hunyuan_zhu）未在 unlocked 列表中
	var restricted_unlocked: Array = ["jubaopen", "mibao_luopan", "qiankun_dai", "wujian_shi"]
	for i in range(40):
		var picked := ItemData.pick_id(50.0, 16, [], rng, restricted_unlocked)
		_c.check(picked in restricted_unlocked, "抽出的法宝 %s 必在已解锁集合中" % picked)
	# 缺省空数组参数时保持向下兼容（全池开放）
	var fallback_picked := ItemData.pick_id(0.0, 1, [], rng)
	_c.check(not fallback_picked.is_empty(), "未传 unlocked_items 时全池开放向下兼容")

	# 备份当前玩家真实进度
	var orig_cults := GameManager.unlocked_cultivators.duplicate()
	var orig_items := GameManager.unlocked_items.duplicate()
	var orig_achs := GameManager.unlocked_achievements.duplicate()
	var orig_stats := GameManager.career_stats.duplicate()
	var orig_records := GameManager.cultivator_best_danger.duplicate()
	var orig_clears := GameManager.cultivator_danger_clears.duplicate()
	var orig_hist := GameManager.run_history.duplicate()

	# 3. 模拟结算与成就达成触发
	GameManager.unlocked_cultivators = AchievementData.DEFAULT_CULTIVATORS.duplicate()
	GameManager.unlocked_items = AchievementData.DEFAULT_ITEMS.duplicate()
	GameManager.unlocked_achievements = []
	GameManager.career_stats = {
		"total_runs": 0, "total_wins": 0, "total_kills": 0,
		"best_wave": 0, "best_kills": 0, "total_stones": 0, "total_time": 0.0,
	}
	GameManager.cultivator_best_danger = {}
	GameManager.cultivator_danger_clears = {}
	GameManager.run_history = []

	# 模拟一局：斩妖 600 只，单局持有 260 灵石，第 16 波战败
	GameManager.reset_run()
	GameManager.cultivator_id = "jianchi"
	GameManager.danger_level = 0
	GameManager.kills = 600
	GameManager.spirit_stones = 260
	GameManager.wave_number = 16
	GameManager.game_time = 320.0
	GameManager.trigger_game_over(false)

	_c.check("ach_cult_meiying" in GameManager.unlocked_achievements, "累计斩妖达到 500 解锁【踏雪无痕】成就")
	_c.check("meiying" in GameManager.unlocked_cultivators, "魅影修士已解锁")
	_c.check("ach_cult_duobao" in GameManager.unlocked_achievements, "灵石达到 250 解锁【富甲一方】成就")
	_c.check("duobao" in GameManager.unlocked_cultivators, "多宝道人已解锁")
	_c.check("ach_item_pojia" in GameManager.unlocked_achievements, "抵御到第 16 波解锁【斩将夺旗】成就")
	_c.check("pojia_zhui" in GameManager.unlocked_items, "破甲锥法宝已入池")
	_c.equals(int(GameManager.career_stats["total_runs"]), 1, "生涯修行场次 +1")
	_c.equals(int(GameManager.career_stats["total_kills"]), 600, "生涯斩妖累计 600")
	_c.equals(int(GameManager.career_stats["best_wave"]), 16, "最高波次更新为 16")
	_c.equals(GameManager.run_history.size(), 1, "战报记录增加 1 条")
	_c.equals(GameManager.is_cultivator_unlocked("meiying"), true, "is_cultivator_unlocked 接口自洽")

	# 再模拟一局：独臂刀圣在 D1 渡劫成功
	GameManager.reset_run()
	GameManager.cultivator_id = "jianchi"
	GameManager.danger_level = 1
	GameManager.kills = 300
	GameManager.spirit_stones = 150
	GameManager.wave_number = 20
	GameManager.trigger_game_over(true)

	_c.check("ach_cult_dubi" in GameManager.unlocked_achievements, "通关 D1 解锁【孤峰问剑】成就")
	_c.check("dubi" in GameManager.unlocked_cultivators, "独臂刀圣已解锁")
	_c.check("ach_cult_duoshe" in GameManager.unlocked_achievements, "任意通关解锁【渡劫初成】成就")
	_c.check("duoshe" in GameManager.unlocked_cultivators, "夺舍散人已解锁")
	_c.equals(GameManager.get_cultivator_best_danger("jianchi"), 1, "剑痴通关印记更新为 D1")
	_c.check(GameManager.is_cultivator_danger_cleared("jianchi", 1), "剑痴 D1 难度封印点亮")
	_c.check(not GameManager.is_cultivator_danger_cleared("jianchi", 0), "剑痴 D0 未打过不点亮（封印按实际通关档位记账）")

	# 4. 存档往返恢复校验：修改 → 存盘 → 清内存 → 读回
	GameManager._save_progress()
	GameManager.unlocked_cultivators = []
	GameManager.unlocked_items = []
	GameManager.unlocked_achievements = []
	GameManager.career_stats = {}
	GameManager.cultivator_best_danger = {}
	GameManager.cultivator_danger_clears = {}
	GameManager.run_history = []
	GameManager._load_progress()

	_c.check("meiying" in GameManager.unlocked_cultivators and "dubi" in GameManager.unlocked_cultivators, "读档后解锁修士保持完整")
	_c.check("pojia_zhui" in GameManager.unlocked_items, "读档后解锁法宝保持完整")
	_c.equals(int(GameManager.career_stats.get("total_runs", 0)), 2, "读档后生涯局数恢复")
	_c.equals(int(GameManager.cultivator_best_danger.get("jianchi", -1)), 1, "读档后剑痴 D1 印记恢复")
	_c.check(GameManager.is_cultivator_danger_cleared("jianchi", 1), "读档后剑痴 D1 封印恢复")
	_c.equals(GameManager.run_history.size(), 2, "读档后战报恢复")

	# 还原测试前的玩家真实进度
	GameManager.unlocked_cultivators = orig_cults
	GameManager.unlocked_items = orig_items
	GameManager.unlocked_achievements = orig_achs
	GameManager.career_stats = orig_stats
	GameManager.cultivator_best_danger = orig_records
	GameManager.cultivator_danger_clears = orig_clears
	GameManager.run_history = orig_hist
	GameManager._save_progress()
	GameManager.reset_run()

# ---------------- 道统功名与渡劫实录（2026-10-10 修仙志升级） ----------------

## 覆盖：每角色生涯档案累加、无尽终局不双计生涯总量、渡劫快照白名单序列化、
## 里程碑称号达标点亮（纯展示无奖励）、新字段落盘往返。

func _test_career_milestones() -> void:
	# 备份真实进度（含本轮新增的局外字段）
	var orig_stats := GameManager.career_stats.duplicate()
	var orig_best_danger := GameManager.cultivator_best_danger.duplicate()
	var orig_clears := GameManager.cultivator_danger_clears.duplicate()
	var orig_records := GameManager.cultivator_records.duplicate()
	var orig_vlog := GameManager.victory_log.duplicate()
	var orig_hist := GameManager.run_history.duplicate()
	var orig_cults := GameManager.unlocked_cultivators.duplicate()
	var orig_items := GameManager.unlocked_items.duplicate()
	var orig_achs := GameManager.unlocked_achievements.duplicate()
	var orig_danger_max := GameManager.max_danger_unlocked

	# 清场
	GameManager.career_stats = {
		"total_runs": 0, "total_wins": 0, "total_kills": 0,
		"best_wave": 0, "best_kills": 0, "total_stones": 0, "total_time": 0.0,
	}
	GameManager.cultivator_best_danger = {}
	GameManager.cultivator_danger_clears = {}
	GameManager.cultivator_records = {}
	GameManager.victory_log = []
	GameManager.run_history = []
	GameManager.unlocked_achievements = []
	GameManager.last_run_new_records = []

	# 1. 渡劫成功（20 波）：档案累加 + 快照落库 + 首胜纪录文案
	GameManager.reset_run()
	GameManager.cultivator_id = "shiyue"
	GameManager.danger_level = 0
	GameManager.kills = 420
	GameManager.spirit_stones = 130
	GameManager.wave_number = 20
	GameManager.trigger_game_over(true)

	var rec := GameManager.get_cultivator_record("shiyue")
	_c.equals(int(rec["runs"]), 1, "石岳生涯局数 +1")
	_c.equals(int(rec["wins"]), 1, "石岳渡劫成功 +1")
	_c.equals(int(rec["best_kills"]), 420, "石岳斩妖之最 420")
	_c.equals(GameManager.victory_log.size(), 1, "渡劫实录新增 1 条快照")
	var snap: Dictionary = GameManager.victory_log[0]
	_c.check(not snap.has("node"), "快照顶层不含节点引用")
	_c.equals(int(snap["kills"]), 420, "快照记录本局斩妖数")
	_c.equals(int(snap["wave"]), GameManager.VICTORY_WAVE, "快照记录渡劫波次 20")
	_c.check(snap.has("weapons") and snap.has("items") and snap.has("stats"), "快照含法器/法宝/属性三段")
	_c.check(String(snap.get("datetime", "")) != "", "快照带结算时刻")
	_c.check(GameManager.last_run_new_records.any(
		func(s: Variant) -> bool: return String(s).contains("首胜")), "首胜生成新纪录文案")
	_c.check(GameManager.last_run_new_records.any(
		func(s: Variant) -> bool: return String(s).contains("境界突破")), "首次通关 D0 生成境界突破文案")
	_c.check(GameManager.last_run_new_records.any(
		func(s: Variant) -> bool: return String(s).contains("炼气")), "D0 通关境界晋入「炼气」")
	_c.check(GameManager.last_run_new_records.all(
		func(s: Variant) -> bool: return not String(s).contains("领取")), "境界突破文案不承诺领取奖励")
	_c.check(GameManager.is_cultivator_danger_cleared("shiyue", 0), "石岳 D0 难度封印点亮")
	_c.check(not GameManager.is_cultivator_danger_cleared("shiyue", 1), "石岳 D1 未通关不点亮")

	# 2. 继续无尽 → 第 25 波道殒：生涯总量不双计，只补无尽纪录与战报
	GameManager.continue_endless()
	GameManager.wave_number = 25
	GameManager.kills = 700
	GameManager.trigger_game_over(false)

	_c.equals(int(GameManager.career_stats["total_runs"]), 1, "无尽终局不再累计生涯局数（无双计）")
	_c.equals(int(GameManager.career_stats["total_kills"]), 420, "无尽终局不再重复累计斩妖")
	_c.equals(int(GameManager.career_stats["best_wave"]), 25, "生涯最高波次更新为 25")
	rec = GameManager.get_cultivator_record("shiyue")
	_c.equals(int(rec["endless_best_wave"]), 25, "石岳无尽最高关数 25")
	_c.equals(int(rec["best_kills"]), 700, "石岳斩妖之最抬升到 700")
	_c.equals(GameManager.run_history.size(), 2, "渡劫与无尽道殒各留一条战报")
	_c.check(bool(GameManager.run_history[0].get("endless", false)), "最新战报标记无尽道殒")
	_c.check(GameManager.last_run_new_records.any(
		func(s: Variant) -> bool: return String(s).contains("无尽")), "无尽新纪录文案生成")
	_c.equals(GameManager.victory_log.size(), 1, "无尽道殒不进渡劫实录")
	_c.check("ach_feat_endless" in GameManager.unlocked_achievements, "无尽抵达第 25 波达成【无尽行者】（无尽路径也判定成就）")

	# 3. 境界称号：按通关过的最高难度点亮，纯展示、不发放任何奖励
	_c.equals(AchievementData.realm_for_danger(-1), "", "未通关无境界称号")
	_c.equals(AchievementData.realm_for_danger(0), "炼气", "通关 D0 晋入炼气")
	_c.equals(AchievementData.realm_for_danger(1), "筑基", "通关 D1 晋入筑基")
	_c.equals(AchievementData.realm_for_danger(3), "元婴", "通关 D3 晋入元婴")
	_c.equals(AchievementData.realm_for_danger(5), "渡劫", "通关 D5 晋入渡劫")
	_c.equals(AchievementData.realm_for_danger(184), "渡劫", "超档仍取最高一档境界")

	# 4. 存档往返：新字段落盘恢复无损
	GameManager._save_progress()
	GameManager.cultivator_records = {}
	GameManager.cultivator_danger_clears = {}
	GameManager.victory_log = []
	GameManager._load_progress()
	_c.equals(GameManager.victory_log.size(), 1, "读档后渡劫实录恢复")
	rec = GameManager.get_cultivator_record("shiyue")
	_c.equals(int(rec["wins"]), 1, "读档后石岳渡劫次数恢复")
	_c.equals(int(rec["endless_best_wave"]), 25, "读档后无尽最高关数恢复")
	_c.check(GameManager.is_cultivator_danger_cleared("shiyue", 0), "读档后石岳 D0 封印恢复（位掩码落盘）")

	# 还原测试前的玩家真实进度
	GameManager.career_stats = orig_stats
	GameManager.cultivator_best_danger = orig_best_danger
	GameManager.cultivator_danger_clears = orig_clears
	GameManager.cultivator_records = orig_records
	GameManager.victory_log = orig_vlog
	GameManager.run_history = orig_hist
	GameManager.unlocked_cultivators = orig_cults
	GameManager.unlocked_items = orig_items
	GameManager.unlocked_achievements = orig_achs
	GameManager.max_danger_unlocked = orig_danger_max
	GameManager.last_run_new_records = []
	GameManager._save_progress()
	GameManager.reset_run()

## 加点与商店顶栏暂停/属性入口及暂停状态恢复防偷跑校验（2026-10-12）
func _test_modal_pause_buttons() -> void:
	var holder := Control.new()
	add_child(holder)

	var lvl_dlg: LevelUpDialog = (load("res://scenes/ui/LevelUpDialog.tscn") as PackedScene).instantiate() as LevelUpDialog
	lvl_dlg.name = "LevelUpDialog"
	holder.add_child(lvl_dlg)

	var shop_dlg: WaveShop = (load("res://scenes/ui/WaveShop.tscn") as PackedScene).instantiate() as WaveShop
	shop_dlg.name = "WaveShop"
	holder.add_child(shop_dlg)

	var pause_menu := PauseMenu.new()
	pause_menu.name = "PauseMenu"
	holder.add_child(pause_menu)

	# 1. LevelUpDialog 顶栏按钮与信号校验
	_c.check(lvl_dlg.has_signal("pause_requested"), "加点面板具备 pause_requested 信号")
	_c.check(lvl_dlg.has_signal("stats_requested"), "加点面板具备 stats_requested 信号")
	var lvl_stats_btn := lvl_dlg.get_node_or_null("CenterContainer/Panel/MarginContainer/VBox/TopBar/StatsButton") as Button
	var lvl_pause_btn := lvl_dlg.get_node_or_null("CenterContainer/Panel/MarginContainer/VBox/TopBar/PauseButton") as Button
	_c.check(lvl_stats_btn != null and lvl_stats_btn.text == "属 性", "加点面板顶栏含「属 性」按钮")
	_c.check(lvl_pause_btn != null and lvl_pause_btn.text == "暂 停", "加点面板顶栏含「暂 停」按钮")

	var state := {"lvl_pause": 0, "lvl_stats": 0, "shop_pause": 0}
	lvl_dlg.pause_requested.connect(func(): state["lvl_pause"] += 1)
	lvl_dlg.stats_requested.connect(func(): state["lvl_stats"] += 1)
	lvl_pause_btn.pressed.emit()
	lvl_stats_btn.pressed.emit()
	_c.equals(int(state["lvl_pause"]), 1, "点击加点面板暂停按钮触发 pause_requested")
	_c.equals(int(state["lvl_stats"]), 1, "点击加点面板属性按钮触发 stats_requested")

	# 1.1 LevelUpDialog 顶栏圆形待加点徽记与连升文案校验（2026-10-12）
	var points_badge := lvl_dlg.get_node_or_null("CenterContainer/Panel/MarginContainer/VBox/TopBar/PointsBadge") as PanelContainer
	_c.check(points_badge != null, "加点面板顶栏含待加点圆形徽记 PointsBadge")
	var points_label := points_badge.get_node_or_null("PointsLabel") as Label if points_badge != null else null
	_c.check(points_label != null, "徽记内含 PointsLabel 显示剩余点数")

	var orig_pending := GameManager.pending_upgrade_points
	var orig_total := GameManager.alloc_points_total
	GameManager.pending_upgrade_points = 3
	GameManager.alloc_points_total = 3
	lvl_dlg._refresh_bars()
	if points_label != null:
		_c.equals(points_label.text, "3", "初始待加点徽记数字为 3")
	_c.check("连升 3 级" in lvl_dlg.info_label.text, "连升多级时 InfoLabel 明确提示连升等级")
	_c.check("剩余加点 3 次" in lvl_dlg.info_label.text, "连升多级时提示剩余加点 3 次")

	GameManager.pending_upgrade_points = 2
	lvl_dlg._refresh_bars()
	if points_label != null:
		_c.equals(points_label.text, "2", "加点后徽记数字扣减为 2")
	_c.check("剩余加点 2 次" in lvl_dlg.info_label.text, "加点后提示剩余加点 2 次")
	GameManager.pending_upgrade_points = orig_pending
	GameManager.alloc_points_total = orig_total

	# 2. WaveShop 顶栏暂停按钮与信号校验
	_c.check(shop_dlg.has_signal("pause_requested"), "商店面板具备 pause_requested 信号")
	var shop_pause_btn := shop_dlg.get_node_or_null("CenterContainer/Panel/MarginContainer/VBox/TopBar/PauseButton") as Button
	_c.check(shop_pause_btn != null and shop_pause_btn.text == "暂 停", "商店面板顶栏含「暂 停」按钮")
	shop_dlg.pause_requested.connect(func(): state["shop_pause"] += 1)
	shop_pause_btn.pressed.emit()
	_c.equals(int(state["shop_pause"]), 1, "点击商店面板暂停按钮触发 pause_requested")

	# 3. PauseMenu 暂停状态恢复互斥校验（防止加点/商店背后战斗偷跑）
	lvl_dlg.visible = false
	shop_dlg.visible = false
	_c.check(not pause_menu._has_paused_modal_behind(), "普通战斗下背后无模态暂停窗")
	pause_menu.open()
	_c.check(pause_menu._unpause_on_close, "普通战斗打开暂停菜单后关闭应解暂停")
	pause_menu.visible = false

	lvl_dlg.visible = true
	_c.check(pause_menu._has_paused_modal_behind(), "加点面板显示时识别出背后有模态暂停窗")
	pause_menu.open()
	_c.check(not pause_menu._unpause_on_close, "加点面板下打开暂停菜单关闭时保持暂停")
	pause_menu.visible = false
	lvl_dlg.visible = false

	shop_dlg.visible = true
	_c.check(pause_menu._has_paused_modal_behind(), "商店面板显示时识别出背后有模态暂停窗")
	pause_menu.open(false)
	_c.check(not pause_menu._unpause_on_close, "商店面板下打开暂停菜单关闭时保持暂停")
	pause_menu.visible = false
	shop_dlg.visible = false

	get_tree().paused = false
	holder.free()


# ---------------- 换色皮肤系统（2026-10-14） ----------------

## 覆盖：主题表完整性、跨难度向下补齐解锁（最高通关难度 >= tier 口径）、
## apply_to_config 副本换色不污染原配置、选择与落盘往返、锁定皮肤惰性回落、视图装配换色生效
func _test_skin_system() -> void:
	# 1. 主题表完整性
	_c.equals(SkinData.count(), 6, "皮肤主题共 6 套（对应 6 档难度）")
	for i in range(SkinData.count()):
		var t := SkinData.get_theme(i)
		_c.equals(int(t.get("tier", -1)), i, "皮肤 %d tier 与难度档位一一对应" % i)
		_c.check(not String(t.get("name", "")).is_empty(), "皮肤 %d 有名号" % i)
		_c.check(t.get("cloak_outer") is Color and t.get("cloak_edge") is Color, "皮肤 %d 配色完整" % i)
	_c.check(SkinData.get_theme(-1).is_empty() and SkinData.get_theme(99).is_empty(), "越界皮肤序号返回空")

	# 备份玩家真实进度
	var orig_records := GameManager.cultivator_best_danger.duplicate()
	var orig_skins := GameManager.skin_selections.duplicate()

	# 2. 跨难度向下补齐：直接通关 D4 ⇒ tier 0~4 全解锁，D5 仍锁
	GameManager.cultivator_best_danger = {"shiyue": 4}
	GameManager.skin_selections = {}
	_c.check(GameManager.is_skin_unlocked("shiyue", -1), "原色皮肤恒可用")
	for i in range(5):
		_c.check(GameManager.is_skin_unlocked("shiyue", i), "通关 D4 ⇒ 皮肤 %d 解锁（跨档补齐）" % i)
	_c.check(not GameManager.is_skin_unlocked("shiyue", 5), "通关 D4 ⇒ D5 皮肤仍锁")
	_c.check(not GameManager.is_skin_unlocked("meiying", 0), "未通关角色皮肤全锁")
	_c.check(not GameManager.is_skin_unlocked("shiyue", 99), "越界皮肤序号判锁")

	# 3. apply_to_config：副本换色，原配置零污染，造型样式键不动
	var base := CultivatorVisualConfig.get_config("jianchi")
	var orig_outer: Color = base.cloak["col_outer"]
	var skinned := SkinData.apply_to_config(base, 1)
	_c.check(skinned != base, "换色返回副本而非原配置")
	_c.equals(base.cloak["col_outer"], orig_outer, "原配置斗篷色未被污染")
	_c.equals(skinned.cloak["col_outer"], SkinData.get_theme(1)["cloak_outer"], "副本斗篷外色已换为主题色")
	_c.equals(skinned.cloak["col_edge"], SkinData.get_theme(1)["cloak_edge"], "副本斗篷缘色已换为主题色")
	_c.equals(String(skinned.cloak.get("cloak_style", "")), String(base.cloak.get("cloak_style", "")), "造型样式键保持角色本相")
	_c.equals(skinned.palette.get("cloak_outer"), skinned.cloak["col_outer"], "派生色盘已同步")
	_c.check(SkinData.apply_to_config(base, -1) == base, "非法皮肤序号原样返回")

	# 4. 选择与落盘往返 + 锁定皮肤惰性回落
	GameManager.set_selected_skin("shiyue", 3)
	_c.equals(GameManager.get_selected_skin("shiyue"), 3, "皮肤选择生效")
	GameManager.set_selected_skin("shiyue", 5)
	_c.equals(GameManager.get_selected_skin("shiyue"), 3, "锁定皮肤选择被拒绝")
	GameManager._save_progress()
	GameManager.skin_selections = {}
	GameManager.cultivator_best_danger = {}
	GameManager._load_progress()
	_c.equals(GameManager.get_selected_skin("shiyue"), 3, "读档后皮肤选择恢复")
	GameManager.cultivator_best_danger = {"shiyue": 1}
	_c.equals(GameManager.get_selected_skin("shiyue"), -1, "解锁记录回退 ⇒ 已选皮肤惰性回落原色")
	GameManager.set_selected_skin("shiyue", -1)
	_c.check(not GameManager.skin_selections.has("shiyue"), "选回原色后存档键擦除")

	# 5. 视图装配：缺省走存档选择，显式 -1 回原色
	var view := ProceduralCultivatorView.new()
	add_child(view)
	GameManager.cultivator_best_danger = {"shiyue": 4}
	GameManager.skin_selections = {"shiyue": 2}
	view.setup_character_id("shiyue")
	_c.equals(view.renderer.config.cloak["col_outer"], SkinData.get_theme(2)["cloak_outer"], "视图按存档选择装配皮肤色")
	view.setup_character_id("shiyue", -1)
	_c.equals(view.renderer.config.cloak["col_outer"], CultivatorVisualConfig.get_config("shiyue").cloak["col_outer"], "显式 -1 回到原色")
	view.queue_free()

	# 还原玩家真实进度
	GameManager.cultivator_best_danger = orig_records
	GameManager.skin_selections = orig_skins
	GameManager._save_progress()
