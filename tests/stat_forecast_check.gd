extends Node

## 悟道卡面「当前 X → 加后 Y」的判据（2026-10-12 用户指令：「加一条显示当前属性是多少，
## 增加后是多少」）。这张卡承诺的数字必须就是点下「确认选择」之后属性面板长出来的数，
## 所以判据不按「算得像不像」放行，只按「真到账之后逐键对表」放行。
##
## 五条口径：
## ① 影子 == 真身：StatShadow 抄出来的读数逐键等于 GameManager.get_stat_breakdown()。
##    开局故意把每一层羁绊/神通乘区都设成互不相同的非默认值 —— 影子少抄哪个字段，
##    那个键就会从探针值掉回默认值，这一枪立刻空响。再补一枪「上限吃得住」的状态
##    （闪避 0.9、暴击 0.9、攻速 0.1），免得夹顶的算式漂了没人管。
## ② 预读 == 真到账：对 UpgradeData 每一条悟道，先用影子算出加后读数（不碰真身），
##    再走生产入口 GameManager.apply_upgrade 真的加一次，两边逐键对表；并把「到账前
##    承诺的加后文本」与「到账后重算的当前文本」串成一条链 —— 上限、地板、气血夹顶、
##    金币当场到账，全在这一枪里被真实结算复核。
## ③ 该不该有注脚：属性面板有对应行的 apply 字段，一条不许漏（漏了=卡面少一句承诺）；
##    面板没有行的机制项（宝箱数量/品质、开箱省击、单系元素伤）一条不许多（多了=硬凑
##    一个玩家在面板里找不到的数）。
## ④ 卡面装得下：最窄一档（720）的悟道卡内宽，逐条注脚按 wrap_cjk 切完不许有一行破格。
## ⑤ 卡面真的画出来了：从 LevelUpDialog 的生产入口开一屏真候选，按节点名数注脚，
##    并逐条核对注脚文本 == 模型算出来的文本（UI 不许自己另编一句数）。
##
## 运行方式：
##   godot --headless --path . res://tests/StatForecastCheck.tscn
##   godot --headless --path . res://tests/StatForecastCheck.tscn -- --selftest

## 羁绊与神通各层的探针值：互不相同、且都不是默认值，影子漏抄哪一层就露在哪一行的读数上
const PROBE: Dictionary = {
	"weapon_damage_mult": 1.45, "melee_damage": 6.0, "ranged_damage": 5.0,
	"elemental_damage": 4.0, "engineering_damage": 3.0, "attack_speed_mult": 0.72,
	"armor": 18.0, "move_speed_mult": 1.24, "attack_range_mult": 1.3,
	"pickup_range_mult": 1.6, "hp_regen": 2.5, "crit_rate": 0.23, "crit_mult": 1.85,
	"dodge": 0.18, "lifesteal": 0.09, "luck": 4.0, "harvest": 7.0, "xp_gain_mult": 1.35,
	"knockback_mult": 1.5, "elite_damage": 0.25, "free_rerolls": 2, "shop_price_mult": 0.85,
	"stat_bonus_pierce": 2, "bonus_pierce": 3, "thorns_pct": 0.15,
	"chest_count_bonus": 1, "chest_quality": 0.5, "chest_reward_mult": 1.75,
	"spirit_stones": 233,
	"synergy_damage_mult": 1.18, "synergy_range_mult": 1.12, "synergy_haste_mult": 1.06,
	"synergy_crit_rate": 0.07, "synergy_crit_mult": 0.11, "synergy_hp_regen": 1.5,
	"synergy_lifesteal": 0.03, "synergy_move_speed_mult": 0.08, "synergy_armor": 5.0,
	"synergy_knockback_mult": 1.09, "synergy_bonus_pierce": 1, "shadow_amp_mult": 1.14,
	"buff_attack_speed_mult": 0.9, "buff_move_speed_mult": 1.1, "buff_dodge": 0.04,
	"dodge_cap_bonus": 0.1,
}

## 上限吃得住的那一档：夹顶的三条算式（闪避硬上限、暴击软上限、攻速地板）在这里才分得出对错
const AT_CAP: Dictionary = {"dodge": 0.9, "crit_rate": 0.9, "attack_speed_mult": 0.1}

const EPS := 0.0001
## 面板有行的字段 = StatInfoData.STAT_FIELDS 的 value 摊平；hp_heal 另算 —— 它落在
## 「生命值」那一行的当前值上（满血时当场夹顶，正是要写实的例子）
const EXTRA_PANEL_FIELDS: Array[String] = ["hp_heal"]
## 钉进一屏真候选的四条：夹顶那条、双字段那条、面板无行那条（不许长注脚）、当场到账那条
const PINNED: Array[String] = ["crit_up", "hp_up", "chest_count_up", "coins_up"]

var _c := TestCheck.new()
var _player: Player

func _ready() -> void:
	call_deferred("_boot")

func _boot() -> void:
	await _setup_run()
	if "--selftest" in OS.get_cmdline_user_args():
		_run_selftest()
	else:
		await _run_shadow_equals_panel()
		await _run_forecast_matches_real_apply()
		_run_registration_table()
		await _run_notes_fit_narrowest_card()
		await _run_card_renders_notes()
	get_tree().quit(0 if _c.report("STATFORECAST_RESULT") else 1)

func _setup_run() -> void:
	GameManager.reset_run()
	GameManager.cultivator_id = "jianchi"
	_player = (load("res://scenes/entities/Player.tscn") as PackedScene).instantiate() as Player
	add_child(_player)
	GameManager.player = _player
	await _settle(3)
	_set_fields(PROBE)
	await _settle(2)

func _set_fields(table: Dictionary) -> void:
	for key in table.keys():
		GameManager.set(String(key), table[key])

## 夹顶状态开/关：关掉时退回探针值，不留夹顶读数污染后面的判据
func _set_at_cap(on: bool) -> void:
	for key in AT_CAP.keys():
		GameManager.set(String(key), AT_CAP[key] if on else PROBE[key])

# ============================ ① 影子 == 真身 ============================

func _run_shadow_equals_panel() -> void:
	var n := GameManager.get_stat_breakdown().size()
	_c.check(n >= 30, "前提：面板读数有 %d 个键可比（少于 30 条就是空判）" % n)
	_c.check(_shadow_vs_panel().is_empty(), "影子读数逐键等于属性面板")
	_set_at_cap(true)
	await _settle(1)
	_c.check(_shadow_vs_panel().is_empty(),
		"上限吃得住那一档（闪避 0.9 / 暴击 0.9 / 攻速 0.1）影子仍逐键等于面板")
	_player.current_health = _player.max_health
	await _settle(1)
	_c.check(_shadow_vs_panel().is_empty(), "满血时影子等于面板")
	_player.current_health = _player.max_health * 0.4
	await _settle(1)
	_c.check(_shadow_vs_panel().is_empty(), "四成血时影子等于面板")
	_set_at_cap(false)
	await _settle(1)

## 影子抄一份真身、原样读回来，与真身自己的读数逐键比：一个字段没抄就是一条差值
func _shadow_vs_panel() -> Array[String]:
	var real_bd := GameManager.get_stat_breakdown()
	var shadow_bd := StatBreakdown.breakdown(StatShadow.from_gm(GameManager))
	var bad: Array[String] = []
	for key in real_bd.keys():
		var k := String(key)
		if not shadow_bd.has(k):
			bad.append("%s 影子读不出来" % k)
			continue
		var a := float(real_bd[key])
		var b := float(shadow_bd[k])
		if absf(a - b) > EPS:
			bad.append("%s 面板 %.4f / 影子 %.4f" % [k, a, b])
	if not bad.is_empty():
		print("[INFO] 影子对表差异：%s" % " | ".join(bad))
	return bad

# ======================= ② 预读 == 真实到账 =======================

## 逐条悟道：先用影子算加后，再从生产入口真加一次，两边对表；
## 再把「到账前承诺的加后文本」与「到账后重算的当前文本」串成一条链。
func _run_forecast_matches_real_apply() -> void:
	var notes_checked := 0
	var bad: Array[String] = []
	for u in UpgradeData.UPGRADES:
		var uid := String(u.get("id", "?"))
		var apply: Dictionary = u.get("apply", {})
		if apply.is_empty():
			continue
		var expected_bd := StatForecast.after_breakdown(apply)
		var promised := _notes_index(StatForecast.open().lines_for(apply))
		notes_checked += promised.size()
		# 真到账：走 apply_upgrade（含 upgrade_counts 记账与 upgrade_applied 信号），不是自己 set
		GameManager.apply_upgrade(uid)
		var actual_bd := GameManager.get_stat_breakdown()
		for key in expected_bd.keys():
			var k := String(key)
			if not actual_bd.has(k):
				continue
			var e := float(expected_bd[k])
			var a := float(actual_bd[k])
			if absf(a - e) > EPS:
				bad.append("%s 的 %s 预读 %.4f / 实得 %.4f" % [uid, k, e, a])
		# 链条：到账后重算一遍，它的「当前」必须就是刚才承诺的「加后」
		for line in StatForecast.open().lines_for(apply):
			var lk := String(line["key"])
			if not promised.has(lk):
				bad.append("%s 的 %s 两次算的不是同一条" % [uid, lk])
				continue
			if String(line["before"]) != String(promised[lk]["after"]):
				bad.append("%s 的 %s 到账前承诺「%s」，到账后当前是「%s」" % [
					uid, lk, String(promised[lk]["after"]), String(line["before"])])
	_c.check(notes_checked >= 20, "前提：本轮真对表了 %d 条注脚（少于 20 条就是空判）" % notes_checked)
	_c.check(bad.is_empty(), "每条悟道的加后预读与真实到账一致，差异：%s" % " | ".join(bad))

func _notes_index(lines: Array[Dictionary]) -> Dictionary:
	var by_key: Dictionary = {}
	for l in lines:
		by_key[String(l["key"])] = l
	return by_key

# ========================== ③ 该不该有注脚 ==========================

func _run_registration_table() -> void:
	var panel_fields: Array[String] = []
	for fields in StatInfoData.STAT_FIELDS.values():
		for f in fields:
			panel_fields.append(String(f))
	panel_fields.append_array(EXTRA_PANEL_FIELDS)
	var missing: Array[String] = []
	var extra: Array[String] = []
	var seen: Array[String] = []
	for u in UpgradeData.UPGRADES:
		for key in (u.get("apply", {}) as Dictionary).keys():
			var k := String(key)
			if k in seen:
				continue
			seen.append(k)
			var want_row: bool = k in panel_fields
			if want_row and not StatForecast.has_reading(k):
				missing.append(k)
			if not want_row and StatForecast.has_reading(k):
				extra.append(k)
	_c.check(seen.size() >= 25, "前提：悟道表里出现过 %d 个不同字段（过少就是空判）" % seen.size())
	_c.check(missing.is_empty(), "面板有行的字段全部登记了预读，漏登记：%s" % str(missing))
	_c.check(extra.is_empty(), "面板没有行的机制项不硬凑读数，多登记：%s" % str(extra))

# ======================= ④ 最窄卡装得下 =======================

func _run_notes_fit_narrowest_card() -> void:
	var screen := Vector2(720.0, 540.0)
	var inner_w: float = LevelUpDialog.card_inner_w(
		LevelUpDialog.card_w_for(screen, GameManager.UPGRADE_OFFER_COUNT))
	var body := GameStyle.body_font()
	var fc := StatForecast.open()
	var bad: Array[String] = []
	var measured := 0
	for u in UpgradeData.UPGRADES:
		for line in fc.lines_for(u.get("apply", {})):
			var txt := String(line["text"])
			measured += 1
			var wrapped := GameStyle.wrap_cjk(txt, body, LevelUpDialog.FORECAST_FONT, inner_w)
			if GameStyle.line_max_w(wrapped, body, LevelUpDialog.FORECAST_FONT) > inner_w + 0.5:
				bad.append("%s「%s」" % [String(u.get("id", "?")), txt])
	_c.check(measured >= 20, "前提：量了 %d 条注脚（少于 20 就是空判）" % measured)
	_c.check(bad.is_empty(), "720 档 %.1f 卡内宽下，注脚切完仍不许有一行破格：%s" % [
		inner_w, " / ".join(bad)])

# ================== ⑤ 卡面真的画出来了、且与模型同源 ==================

func _run_card_renders_notes() -> void:
	_pin_offers()
	var dlg: LevelUpDialog = (load("res://scenes/ui/LevelUpDialog.tscn") as PackedScene)\
		.instantiate() as LevelUpDialog
	dlg.visible = true
	add_child(dlg)
	await _settle(2)
	dlg._on_alloc_opened()
	get_tree().paused = false
	await _settle(3)
	var fc := StatForecast.open()
	var total_notes := 0
	for ci in range(dlg._card_entries.size()):
		var offer: Dictionary = GameManager.alloc_offers[ci]
		var title := String(offer.get("title", "?"))
		var want := _notes_index(fc.lines_for(offer.get("apply", {})))
		var got := _notes_of(dlg._card_entries[ci]["root"])
		total_notes += got.size()
		_c.check(got.size() == want.size(),
			"卡「%s」画出 %d 行注脚（模型算出 %d 行）" % [title, got.size(), want.size()])
		for pair in got:
			var k := String(pair[0])
			_c.check(want.has(k), "卡「%s」的注脚 %s 在模型里查得到" % [title, k])
			_c.check(String(pair[1]) == String((want.get(k, {}) as Dictionary).get("text", "")),
				"卡「%s」注脚 %s 与模型同源（卡面「%s」/ 模型「%s」）" % [
					title, k, String(pair[1]),
					String((want.get(k, {}) as Dictionary).get("text", ""))])
	_c.check(total_notes >= 3, "前提：这一屏真画出了 %d 行注脚（0 行就是整判据空跑）" % total_notes)
	dlg.queue_free()
	await _settle(2)

## 按节点名把卡面上的注脚捞出来：[字段名, 文本]
func _notes_of(card: Control) -> Array:
	var out: Array = []
	var vbox := card.get_child(0) as VBoxContainer
	if vbox == null:
		return out
	for ch in vbox.get_children():
		if String(ch.name) != "ApplyRowsBlock":
			continue
		for group in (ch as Container).get_children():
			var gid := String(group.name)
			if not gid.begins_with("ApplyGroup_"):
				continue
			for sub in (group as Container).get_children():
				if String(sub.name) == "ForecastNote":
					out.append([gid.trim_prefix("ApplyGroup_"), (sub as Label).text])
	return out

## 钉一屏真候选：夹顶那条、双字段那条、面板无行那条、当场到账那条
func _pin_offers() -> void:
	var offers: Array[Dictionary] = []
	for uid in PINNED:
		var d: Dictionary = UpgradeData.get_upgrade_def(uid).duplicate()
		if d.is_empty():
			continue
		d["border_color"] = UpgradeData.RARITY_COLORS.get(d.get("rarity", "common"), Color.WHITE)
		offers.append(d)
	GameManager.alloc_offers = offers

# ============================ 反例 selftest ============================

## 这几把尺子得抓得住假账：抓不住就说明判据在空转（历史上「ALL PASS 但 0 项」这么溜过去的）。
func _run_selftest() -> void:
	# 反例①：抹掉一层羁绊乘区 ⇒ 影子读数必须与面板分家
	var shadow := StatShadow.from_gm(GameManager)
	shadow.synergy_damage_mult = 1.0
	var delta: float = absf(
		float(StatBreakdown.breakdown(shadow)["damage_bonus_pct"])
		- float(GameManager.get_stat_breakdown()["damage_bonus_pct"]))
	_c.check(delta > 1.0, "反例① 影子少抄一层羁绊，读数对表抓得住（差 %.2f）" % delta)
	# 反例②：暴击夹顶时，「当前 + 幅度」的线性近似必须与影子预读分家
	_set_at_cap(true)
	var projected := float(StatForecast.after_breakdown({"crit_rate": 0.08})["crit_rate_pct"])
	var naive := float(GameManager.get_stat_breakdown()["crit_rate_pct"]) + 8.0
	_c.check(absf(projected - naive) > 1.0,
		"反例② 到顶时拿「当前+8%%」近似，判据抓得住（预读 %.1f / 近似 %.1f）" % [projected, naive])
	# 反例③：登记表区分得出「面板有行」与「机制项」
	_c.check(StatForecast.has_reading("crit_rate") and not StatForecast.has_reading("chest_quality"),
		"反例③ 面板有行的字段有预读、机制项没有")
	_set_at_cap(false)

## 过几帧让布局与信号落定（只用来等排版，不做任何「几帧=几秒」的时间换算）
func _settle(frames: int) -> void:
	for i in range(frames):
		await get_tree().process_frame
