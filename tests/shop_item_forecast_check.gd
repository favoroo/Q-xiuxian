extends Node

## 商店道具卡「当前 → 购买后」预览的判据（2026-10-21 用户：「商店物品也要加个提示，
## 加成之后属性会是多少，和悟道加点界面类似」）。卡面承诺的数必须就是点下购买之后
## 真长出来的数 —— 与 StatForecastCheck 同一条铁律，现场换到灵石阁货架。
##
## 五条口径：
## ① 模型同源：全量 ItemData 逐件装配货架卡，有预读的行必须与 StatForecast.shop_lines_for
##    对上（pair 或 "→after" 兜底档），颜色按「变化=幅度语义色 / 未变化=GREY」；
## ② 该有就有、不该有就没有：面板有行的字段行内含「→」，机制项（灵兽三件/宝箱/元素/技能冷却）
##    保持幅度行——不给属性面板里找不到的数硬凑读数；
## ③ 宽度：最窄档 124 卡内宽下，每件道具每行「行名+数值+列缝」都装得下（BonusRows 不换行）；
## ④ 真实到账链条：残血样本下记卡上 after → add_item 真买一件 → 重算 before 必须接上
##    （上限夹顶/满血回血全在这条链里被真实结算复核）；
## ⑤ 真上屏：960 开真 WaveShop 钉三件道具，卡面 Label 与装配数据逐行同源、真画出了「→」。
##
## 运行方式：
##   godot --headless --path . res://tests/ShopItemForecastCheck.tscn
##   godot --headless --path . res://tests/ShopItemForecastCheck.tscn -- --selftest

## 到账链条的代表样本：六字段最坏卡 / 攻速乘算两个方向 / 负代偿 / max_hp+hp_heal 成对 /
## 物价乘算 / 5 字长行名（宽度兜底档）/ 有预读+机制项混排
const CHAIN_IDS: Array[String] = [
	"taiyi_jindan", "qingxin_cha", "xuewen_fu", "hupi_qun",
	"zhekou_yufu", "pojia_zhui", "wanling_fan",
]
## 满血/GREY 与夹顶样本：闪避顶到 DODGE_CAP 后幻纱的闪避行必须「买了等于没买」
const DODGE_CAP_PROBE_ID := "huansha"

var _c := TestCheck.new()
var _player: Player

func _ready() -> void:
	call_deferred("_boot")

func _boot() -> void:
	await _setup_run()
	if "--selftest" in OS.get_cmdline_user_args():
		_run_selftest()
	else:
		await _run_model_matches_all_items()
		await _run_chain_against_real_purchase()
		await _run_card_renders_forecast()
	get_tree().paused = false
	get_tree().quit(0 if _c.report("SHOPFORECAST_RESULT") else 1)

func _setup_run() -> void:
	GameManager.reset_run()
	GameManager.cultivator_id = "jianchi"
	GameManager.start_run("qingyun_sword")
	if GameManager.player == null or not is_instance_valid(GameManager.player):
		_player = (load("res://scenes/entities/Player.tscn") as PackedScene).instantiate() as Player
		add_child(_player)
		GameManager.player = _player
	else:
		_player = GameManager.player as Player
	await _settle(3)
	# 探针值：互不相同的非默认值，影子少抄哪一层就露在哪一行的读数上（StatForecastCheck 同一思路）
	GameManager.weapon_damage_mult = 1.25
	GameManager.attack_speed_mult = 0.72
	GameManager.armor = 18.0
	GameManager.crit_rate = 0.15
	GameManager.crit_mult = 1.8
	GameManager.lifesteal = 0.05
	GameManager.hp_regen = 1.2
	GameManager.elite_damage = 0.30
	GameManager.shop_price_mult = 0.9
	GameManager.luck = 6.0
	GameManager.harvest = 9.0
	GameManager.xp_gain_mult = 1.2
	GameManager.attack_range_mult = 1.15
	GameManager.move_speed_mult = 1.1
	GameManager.melee_damage = 4.0
	GameManager.ranged_damage = 3.0
	GameManager.elemental_damage = 2.0
	await _settle(2)

func _set_hp_ratio(ratio: float) -> void:
	_player.current_health = _player.max_health * ratio
	GameManager.player_hp_changed.emit(_player.current_health, _player.max_health)

# ============================ ① 全量道具 · 模型同源 ============================

func _run_model_matches_all_items() -> void:
	var checked := 0
	var forecast_rows := 0
	var bad: Array[String] = []
	for id in ItemData.all_ids():
		var iid := String(id)
		var apply: Dictionary = ItemData.get_def(iid).get("apply", {})
		if apply.is_empty():
			continue
		var data: Dictionary = ShopOfferCardFactory.resolve_offer_data({"kind": "item", "id": iid})
		var rows: Array = data.get("stat_rows", [])
		if rows.size() != apply.size():
			bad.append("%s 行数 %d ≠ apply 字段数 %d" % [iid, rows.size(), apply.size()])
			continue
		var model := _model_index(StatForecast.open().shop_lines_for(apply))
		for r in rows:
			var k := _key_of_name(String(r[0]), apply)
			checked += 1
			if model.has(k):
				forecast_rows += 1
				var err := _row_vs_model(String(r[1]), r[2], model[k], k, float(apply[k]))
				if not err.is_empty():
					bad.append("%s %s" % [iid, err])
			elif String(r[1]) != StatInfoData.format_amount(k, float(apply[k])):
				bad.append("%s 的机制项 %s 应保持幅度行，实得「%s」" % [
					iid, k, String(r[1])])
	_check_sweep_prerequisites(checked, forecast_rows)
	_c.check(bad.is_empty(), "全量道具卡逐行与预读模型同源（%d 件）：%s" % [
		ItemData.all_ids().size(), " | ".join(bad)])

## 前提守卫：行数太少或一行预读都没有 = 判据空转（同「ALL PASS 但 0 项」那类假绿）
func _check_sweep_prerequisites(checked: int, forecast_rows: int) -> void:
	_c.check(checked >= 60, "前提：本轮对了 %d 行（少于 60 行就是空判）" % checked)
	_c.check(forecast_rows >= 20, "前提：其中 %d 行是预读行（0 行 = 预览没接上）" % forecast_rows)

## 行名反查 apply key（StatInfoData.field_name 是唯一名字来源，这里不抄第二份表）
func _key_of_name(name_txt: String, apply: Dictionary) -> String:
	for key in apply.keys():
		if StatInfoData.field_name(String(key)) == name_txt:
			return String(key)
	return ""

func _model_index(lines: Array[Dictionary]) -> Dictionary:
	var by_key: Dictionary = {}
	for l in lines:
		by_key[String(l["key"])] = l
	return by_key

## 一行卡值 vs 模型行：返回空串=对上，否则人话错误（selftest 也用它验牙齿）
static func _row_vs_model(val_txt: String, val_col, line: Dictionary, k: String, v: float) -> String:
	var want_col: Color = BonusRows.stat_color(k, v) if bool(line["changed"]) else GameStyle.GREY
	if not (val_col as Color).is_equal_approx(want_col):
		return "%s 颜色不符（实得 %s / 应得 %s）" % [k, val_col, want_col]
	if val_txt == String(line["text"]):
		return ""
	if val_txt == "→" + String(line["after"]):
		return ""
	return "%s 行值「%s」对不上模型（pair「%s」/ after「%s」）" % [
		k, val_txt, String(line["text"]), String(line["after"])]

# ============================ ④ 真实到账链条 ============================

## 残血 50%：max_hp/hp_heal 两行才各自有独立读数（满血时两行会撞成同一串）。
## 同步执行、中间不 await：生命回复不再偷跑，链条才量得出「承诺 == 到账」。
func _run_chain_against_real_purchase() -> void:
	_set_hp_ratio(0.5)
	var bad: Array[String] = []
	var chained := 0
	for id in CHAIN_IDS:
		var iid := String(id)
		var apply: Dictionary = ItemData.get_def(iid).get("apply", {})
		if apply.is_empty():
			continue
		var data: Dictionary = ShopOfferCardFactory.resolve_offer_data({"kind": "item", "id": iid})
		var promised := _promised_after(data.get("stat_rows", []), apply)
		chained += promised.size()
		GameManager.add_item(iid)
		# 到账后重算：它的「当前」必须就是刚才卡面承诺的「购买后」
		var now := _model_index(StatForecast.open().shop_lines_for(apply))
		for k in promised.keys():
			var line: Dictionary = now.get(k, {})
			if line.is_empty():
				bad.append("%s 到账后 %s 没了预读" % [iid, k])
				continue
			if String(line["before"]) != String(promised[k]):
				bad.append("%s 的 %s 买前承诺「%s」，买后当前是「%s」" % [
					iid, k, String(promised[k]), String(line["before"])])
	_c.check(chained >= 15, "前提：本轮串了 %d 条到账链（少于 15 条就是空判）" % chained)
	_c.check(bad.is_empty(), "卡面承诺的购买后 == 真买一件后长出来的数：%s" % " | ".join(bad))

	# 夹顶档：闪避顶满后再买幻纱，闪避行必须「买了等于没买」——文本两数相同、颜色退 GREY
	GameManager.dodge = GameManager.DODGE_CAP
	var cap_apply: Dictionary = ItemData.get_def(DODGE_CAP_PROBE_ID).get("apply", {})
	var cap_rows: Array = ShopOfferCardFactory.resolve_offer_data(
			{"kind": "item", "id": DODGE_CAP_PROBE_ID}).get("stat_rows", [])
	var cap_line: Dictionary = _model_index(
			StatForecast.open().shop_lines_for(cap_apply)).get("dodge", {})
	_c.check(not cap_line.is_empty() and not bool(cap_line["changed"]),
			"闪避夹顶时预读 changed=false（实得 %s）" % str(cap_line))
	var cap_row := _row_of_name(cap_rows, "闪避率")
	_c.check(cap_row.size() == 3 and (cap_row[2] as Color).is_equal_approx(GameStyle.GREY),
			"闪避夹顶行退 GREY（实得 %s）" % str(cap_row))

## 从装配行里拎出每条预读的 after（按行名反查 key）
func _promised_after(rows: Array, apply: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var model := _model_index(StatForecast.open().shop_lines_for(apply))
	for r in rows:
		var k := _key_of_name(String(r[0]), apply)
		if not model.has(k):
			continue
		var val := String(r[1])
		if val.begins_with("→"):
			out[k] = val.trim_prefix("→")
		elif val == String(model[k]["text"]):
			out[k] = String(model[k]["after"])
	return out

func _row_of_name(rows: Array, name_txt: String) -> Array:
	for r in rows:
		if String(r[0]) == name_txt:
			return r
	return []

# ============================ ⑤ 卡面真的画出来了 ============================

func _run_card_renders_forecast() -> void:
	_set_hp_ratio(0.5)
	GameManager.spirit_stones = 500
	GameManager.shop_slots_bonus = 0
	GameManager.roll_shop(true)
	var offers: Array = GameManager.shop_offers
	offers[0] = {"kind": "item", "id": "taiyi_jindan", "price": 88, "sold": false, "locked": false}
	offers[1] = {"kind": "item", "id": "qingxin_cha", "price": 14, "sold": false, "locked": false}
	offers[2] = {"kind": "item", "id": "huansha", "price": 26, "sold": false, "locked": false}
	var shop: Control = (load("res://scenes/ui/WaveShop.tscn") as PackedScene).instantiate()
	shop.visible = true
	add_child(shop)
	await _settle(2)
	shop._on_shop_opened()
	await get_tree().create_timer(0.7).timeout
	await _settle(2)

	var total_rows := 0
	var arrow_rows := 0
	var bad: Array[String] = []
	var body := GameStyle.body_font()
	var cards: Array = shop.offers_container.get_children()
	for ci in range(3):
		if ci >= cards.size():
			bad.append("第 %d 张卡没上屏" % ci)
			continue
		var assembled: Array = ShopOfferCardFactory.resolve_offer_data(
				{"kind": "item", "id": String(offers[ci]["id"])}).get("stat_rows", [])
		var drawn := _screen_rows(cards[ci])
		if drawn.size() != assembled.size():
			bad.append("卡 %d 画出 %d 行（装配 %d 行）" % [ci, drawn.size(), assembled.size()])
			continue
		for ri in range(drawn.size()):
			total_rows += 1
			var want := String(assembled[ri][1])
			var got := String(drawn[ri][1])
			if got != want:
				bad.append("卡 %d 行 %s 画「%s」≠ 装配「%s」" % [ci, String(assembled[ri][0]), got, want])
			if got.contains("→"):
				arrow_rows += 1
			# 真字体的行宽也要装得下这一档卡（960 五格档，比 124 下限宽，但仍要量）
			var inner: float = WaveShop.card_inner_w(
					WaveShop.offer_card_w(shop._screen, GameManager.shop_offers.size()))
			var need := GameStyle.line_max_w(String(drawn[ri][0]), body, 12) \
					+ GameStyle.line_max_w(got, body, 12) + 4.0
			if need > inner + 0.5:
				bad.append("卡 %d 行「%s」%.0f > 卡内宽 %.0f" % [ci, String(drawn[ri][0]), need, inner])
	_c.check(total_rows >= 8, "前提：三张道具卡真画出 %d 行（少了就是没量到）" % total_rows)
	_c.check(arrow_rows >= 4, "前提：其中 %d 行是「→」预览行（0 行 = 预览没上屏）" % arrow_rows)
	_c.check(bad.is_empty(), "货架卡面与装配逐行同源、行宽装得下：%s" % " | ".join(bad))
	shop.queue_free()
	await _settle(2)

## 把一张卡面上 BonusRowsBlock 的行捞出来：[[行名, 数值], …]
func _screen_rows(card: Control) -> Array:
	var out: Array = []
	var vbox := card.get_child(0) as VBoxContainer
	if vbox == null:
		return out
	for ch in vbox.get_children():
		if String(ch.name) != "BonusRowsBlock":
			continue
		for row in (ch as Container).get_children():
			var labels: Array[String] = []
			for sub in (row as Container).get_children():
				if sub is Label:
					labels.append((sub as Label).text)
			if labels.size() >= 2:
				out.append([labels[0], labels[1]])
	return out

# ============================ 反例 selftest ============================

## 尺子必须有牙齿：篡改的行值、机制项的预读、破格的宽度，各须被抓一次
func _run_selftest() -> void:
	var line: Dictionary = {"key": "armor", "text": "18→21", "before": "18", "after": "21", "changed": true}
	var err := _row_vs_model("18→22", GameStyle.GOOD_DK, line, "armor", 3.0)
	_c.check(not err.is_empty(), "反例① 篡改行值（18→22 ≠ 18→21）被抓（实得：%s）" % err)
	var ok := _row_vs_model("18→21", BonusRows.stat_color("armor", 3.0), line, "armor", 3.0)
	_c.check(ok.is_empty(), "正例 原样 pair 放行")
	var grey := _row_vs_model("18→21", GameStyle.GOOD_DK,
			{"key": "armor", "text": "18→21", "before": "18", "after": "21", "changed": false},
			"armor", 3.0)
	_c.check(not grey.is_empty(), "反例② 未变化却上了幅度色被抓（实得：%s）" % grey)
	_c.check(StatForecast.has_reading("armor") and not StatForecast.has_reading("pet_damage_mult"),
			"反例③ 登记表分得清面板有行与机制项")
	_c.check(not ShopOfferCardFactory._row_fits("最大生命", "99999→199999"),
			"反例④ 破格宽度被抓（兜底退档有牙齿）")
	_c.check(ShopOfferCardFactory._row_fits("最大生命", "120→132"), "正例 正常读数放行")

## 过几帧让布局与信号落定（只用来等排版，不做任何「几帧=几秒」的时间换算）
func _settle(frames: int) -> void:
	for i in range(frames):
		await get_tree().process_frame
