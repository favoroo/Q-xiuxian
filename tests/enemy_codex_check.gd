extends Node

## 敌人图鉴判据（2026-10-13）：数据表对账 → 收录存档往返 → 四路刷怪埋点 → 图鉴页建卡 → 图标捕获。
##
## 为什么这几枪必须打在真链路上：
##  ① catalog 与 EnemyData 对账：改表加怪忘进图鉴（或反过来）都是「图鉴撒谎」，
##     表序切片（常规 11 / 精英 3）写死在 ManualDialog 分组里，两边必须同时钉住。
##  ② 存档往返走真 ConfigFile 读盘：record_seen 写的是 user://codex.cfg，
##     只量内存数组等于没量持久化 —— 关游戏丢收录是最蠢的回归。
##     跑本判据会清 user://codex.cfg（reset_for_test），真机收录会被抹掉，开发者知悉即可。
##  ③ 四路埋点走真 WaveSpawner：常规口在派发时记 key（不是落地 callback，预警亮起即遭遇），
##     精英/魔君/金蟾各一记 —— 任何一路接线断了，那一种就永远进不了图鉴。
##  ④ 建卡走真 ManualDialog._rebuild_enemies_page：headless 无真渲染，图标捕到 null 是预期，
##     但 16 张卡、分组标题、未遭遇灰显必须立得住（灰显与遭遇判据同源 EnemyCodex）。
##  ⑤ 图标捕获去重：同一 eid 并发两枪只许建一个宿主（_pending 闸），捕完缓存命中同对象。
##
## 运行: $G --headless --path . res://tests/EnemyCodexCheck.tscn

var _c := TestCheck.new()

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_data()
	await _test_persistence()
	await _test_spawn_hooks()
	await _test_manual_page()
	await _test_icon_capture()
	await _test_detail_tip_large_icon()
	if _c.report("ENEMYCODEX_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)

# ---------------- ① 数据表对账 ----------------
func _test_data() -> void:
	var ids: Array = EnemyGuideData.catalog_ids()
	var mob_n := EnemyData.MOBS.size()
	var elite_n := EnemyData.ELITE_POOL.size()
	var total_n := mob_n + elite_n + 2
	_c.equals(ids.size(), total_n, "catalog 收录 %d 种（%d 常规 + %d 精英 + 魔君 + 金蟾）" % [total_n, mob_n, elite_n])
	_c.equals(ids.slice(0, mob_n), EnemyData.mob_keys(), "常规 %d 种与 EnemyData.MOBS 表序一致" % mob_n)
	var elite_ids: Array = []
	for e in EnemyData.ELITE_POOL:
		elite_ids.append(String(e["id"]))
	_c.equals(ids.slice(mob_n, mob_n + elite_n), elite_ids, "精英 %d 种与 EnemyData.ELITE_POOL 对账" % elite_n)
	_c.check(ids[total_n - 2] == "boss" and ids[total_n - 1] == "jinchan", "魔君/金蟾在表尾")
	var missing: Array[String] = []
	for eid in ids:
		if not EnemyGuideData.GUIDE.has(eid):
			missing.append(eid)
	_c.check(missing.is_empty(), "GUIDE 文案覆盖全部 catalog（缺 %s）" % str(missing))
	var bad_name: Array[String] = []
	var bad_seen: Array[String] = []
	for eid in ids:
		if EnemyGuideData.display_name(String(eid)).is_empty():
			bad_name.append(String(eid))
		if EnemyGuideData.first_seen_text(String(eid)).is_empty():
			bad_seen.append(String(eid))
	_c.check(bad_name.is_empty(), "每种都有显示名（缺 %s）" % str(bad_name))
	_c.check(bad_seen.is_empty(), "每种都有出没文案（缺 %s）" % str(bad_seen))
	# 文案不许复读数据表名字的变体却漏掉行为词：desc 必须是一句可读威胁（≥6 字）
	var thin: Array[String] = []
	for eid in EnemyGuideData.GUIDE.keys():
		var d := String(EnemyGuideData.GUIDE[eid].get("desc", ""))
		if d.length() < 6:
			thin.append(String(eid))
	_c.check(thin.is_empty(), "威胁描述都是完整一句话（过短 %s）" % str(thin))
	# 详情卡强度行（2026-10-13）：attack/tough/swift/counter 四字段必须齐，
	# 且 tough/swift 必须落在档位词表里 —— 造新词会把 ManualDialog 的色档字典打穿（取不到色走兜底纸白，等于档位撒谎）
	var missing_field: Array[String] = []
	var bad_tier: Array[String] = []
	for eid in ids:
		var g: Dictionary = EnemyGuideData.GUIDE[eid]
		for key in ["attack", "tough", "swift", "counter"]:
			if String(g.get(key, "")).is_empty():
				missing_field.append("%s.%s" % [eid, key])
		if not g.get("tough", "") in EnemyGuideData.TOUGH_TIERS:
			bad_tier.append("%s.tough=%s" % [eid, g.get("tough", "")])
		if not g.get("swift", "") in EnemyGuideData.SPEED_TIERS:
			bad_tier.append("%s.swift=%s" % [eid, g.get("swift", "")])
	_c.check(missing_field.is_empty(), "每种都有攻击方式/皮实度/移速/应对（缺 %s）" % str(missing_field))
	_c.check(bad_tier.is_empty(), "强度档位都在词表内（越界 %s）" % str(bad_tier))

# ---------------- ② 收录存档往返 ----------------
func _test_persistence() -> void:
	EnemyCodex.reset_for_test()
	_c.check(not EnemyCodex.is_seen("slime"), "清档后未遭遇")
	EnemyCodex.record_seen("slime")
	EnemyCodex.record_seen("slime")  # 幂等：第二次不许重复落盘/追加
	_c.check(EnemyCodex.is_seen("slime"), "record_seen 后 is_seen 立即可见")
	_c.check(not EnemyCodex.is_seen("golem"), "别的种不被误标")
	var cfg := ConfigFile.new()
	var err := cfg.load(EnemyCodex.CODEX_PATH)
	_c.check(err == OK, "codex.cfg 落盘可读（err=%d）" % err)
	var raw = cfg.get_value("codex", "seen_enemies", [])
	_c.check(Array(raw).count("slime") == 1,
		"盘上 slime 恰好一条（重复 record 未放大：%s）" % str(raw))
	# 读回不丢：清内存后从盘重载，slime 仍在（is Array 对 PackedStringArray 为假那条坑）
	EnemyCodex._loaded = false
	EnemyCodex._seen.clear()
	EnemyCodex.ensure_loaded()
	_c.check(EnemyCodex.is_seen("slime"), "重启读档后 slime 仍在图鉴")
	_c.equals(EnemyCodex.seen_count_in(EnemyGuideData.catalog_ids()), 1, "目录内计数 = 1")

# ---------------- ③ 四路刷怪埋点（真 WaveSpawner） ----------------
func _test_spawn_hooks() -> void:
	var main: Node = load("res://scenes/main/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	GameManager.cultivator_id = "jianchi"
	GameManager.start_run("qingyun_sword")
	get_tree().paused = false
	await get_tree().process_frame
	await get_tree().process_frame
	var spawner: WaveSpawner = GameManager.wave_spawner
	_c.check(spawner != null and GameManager.player != null, "真现场就位（spawner+player）")
	var player: Node2D = GameManager.player

	# 常规口：直接派一批（预算内），记录发生在派发当刻、不等预警落地
	spawner._budget_total = 6
	spawner._budget_used = 0
	spawner._spawn_regular(player)
	await get_tree().process_frame
	var catalog: Array = EnemyGuideData.catalog_ids()
	var hit_regular := false
	for eid in catalog:
		if EnemyCodex.is_seen(String(eid)):
			hit_regular = true
	_c.check(hit_regular, "_spawn_regular 把刷出的种记进图鉴")

	spawner._spawn_elite(player)
	spawner._spawn_looter(player)
	spawner._spawn_boss(player)
	await get_tree().process_frame
	_c.check(EnemyCodex.is_seen("jinchan"), "金蟾口埋点接线")
	_c.check(EnemyCodex.is_seen("boss"), "魔君口埋点接线")
	var any_elite := EnemyCodex.is_seen("golem") or EnemyCodex.is_seen("chilei") or EnemyCodex.is_seen("jiansha")
	_c.check(any_elite, "精英口按轮换种埋点接线")
	main.queue_free()
	await get_tree().process_frame

# ---------------- ④ 图鉴页建卡（真 ManualDialog） ----------------
func _test_manual_page() -> void:
	# ManualDialog.new() 入树 → _ready → _build_body 会自动建六页壳并置 _enemies_box，
	# 这里只显式铺一次卡（懒建页正常要切过去才铺，测试直接调重建）
	var manual: ManualDialog = ManualDialog.new()
	get_tree().root.add_child(manual)
	await get_tree().process_frame
	manual._rebuild_enemies_page()
	await get_tree().process_frame
	var box := manual._enemies_box
	_c.check(box != null and box.get_child_count() == 9, "页头 1 + 4 组 ×(标题+网格) = 9")
	var grids: Array[GridContainer] = []
	for c in box.get_children():
		if c is GridContainer:
			grids.append(c as GridContainer)
	var cards := 0
	for g in grids:
		cards += g.get_child_count()
	_c.equals(grids.size(), 4, "四个分组网格都建出来")
	_c.equals(cards, 22, "22 张卡全部就位（14 常规 + 6 精英 + 魔君 + 金蟾）")
		# 遭遇/未遭遇与 EnemyCodex 同源：slime(②记)/boss、jinchan(③记) 卡不该灰显，guyao 该灰
	_c.check(_icon_mod(grids[0], 0) == Color.WHITE, "slime 已遭遇 ⇒ 图标不灰")
	_c.check(_icon_mod(grids[2], 0) == Color.WHITE, "魔君已遭遇 ⇒ 图标不灰")
	_c.check(_icon_mod(grids[3], 0) == Color.WHITE, "金蟾已遭遇 ⇒ 图标不灰")
	_c.check(_icon_mod(grids[0], 9) != Color.WHITE, "鼓妖（第9波，本局没打到）⇒ 灰显未收录")
	manual.queue_free()
	await get_tree().process_frame

## 取分组网格里第 idx 张卡的图标 TextureRect modulate（判据与卡面渲染同源，不另算）
func _icon_mod(grid: GridContainer, idx: int) -> Color:
	var card := grid.get_child(idx) as PanelContainer
	var tex := card.get_meta("icon_tex") as TextureRect
	return tex.modulate

# ---------------- ⑤ 图标捕获去重与缓存 ----------------
func _test_icon_capture() -> void:
	# 用一个没被 ④ 捕过的种（zhumu 大概率未遭遇）：两枪并发必须只建一个离屏宿主
	var eid := "zhumu"
	if EnemyIconCapture._cache.has(eid):
		eid = "yingmei"
	var before := _count_codex_hosts()
	EnemyIconCapture.capture(eid)          # fire-and-forget：建宿主，3 帧后落缓存
	EnemyIconCapture.capture(eid)          # 撞 _pending：去重轮询，不建第二个宿主
	var mid := _count_codex_hosts()
	for i in range(6):
		await get_tree().process_frame
	_c.check(EnemyIconCapture._cache.has(eid), "%s 捕获完成落缓存" % eid)
	_c.check(not EnemyIconCapture._pending.has(eid), "%s 完成后摘 pending" % eid)
	_c.check(mid - before <= 1, "并发去重：两枪只建一个宿主（新增 %d）" % (mid - before))
	var again: Texture2D = await EnemyIconCapture.capture(eid)
	_c.check(EnemyIconCapture.peek(eid) == again, "缓存命中：peek 与 capture 同对象")
	# 视觉 id 映射对账（headless 取不到像素，但 config 对象是纯数据可比）：
	# 每个 catalog id 经 EnemyIconCapture 的映射喂进 get_config，必须拿到自己那套外观，
	# 不许落 `_` 兜底（赤雷/剑煞不带 _elite 后缀会被画成 golem）。
	var wrong: Array[String] = []
	for cid in EnemyGuideData.catalog_ids():
		var eid2 := String(cid)
		var is_elite := eid2 in ["golem", "chilei", "jiansha", "xuanming", "xingpan", "wandu"]
		var visual := String(EnemyIconCapture.VISUAL_ID.get(eid2, eid2))
		var cfg := EnemyVisualConfig.get_config(visual, is_elite, eid2 == "boss", false)
		# 工厂的 enemy_id 与键同形（make_boss 也对 "boss"）⇒ 期望就是映射后的 visual id
		if cfg == null or cfg.enemy_id != visual:
			wrong.append("%s→实得%s" % [eid2, cfg.enemy_id if cfg != null else "null"])
	_c.check(wrong.is_empty(), "每种图鉴 id 都拿到自己的外观配置（串味 %s）" % str(wrong))

## 数一下场景树里挂着多少个离屏捕获宿主（Node2D 且唯一孩子是 SubViewport）
func _count_codex_hosts() -> int:
	var n := 0
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for ch in node.get_children():
			stack.append(ch)
			if ch is Node2D and ch.get_child_count() == 1 and ch.get_child(0) is SubViewport:
				n += 1
	return n

# ---------------- ⑥ 详情大图与按尺寸捕获 ----------------
func _test_detail_tip_large_icon() -> void:
	# 尺寸 key 格式隔离
	_c.equals(EnemyIconCapture._key("slime", false, 96), "slime", "默认尺寸 96 key 不带后缀")
	_c.equals(EnemyIconCapture._key("slime", false, 128), "slime#s128", "自定义尺寸 128 key 带 #s128")
	_c.equals(EnemyIconCapture._key("golem", true, 128), "golem#e#s128", "精英 128 key 组合正确")

	# DetailTip 大图渲染挂载测试
	var host := Control.new()
	host.custom_minimum_size = Vector2(960, 540)
	get_tree().root.add_child(host)

	var anchor := Control.new()
	anchor.position = Vector2(100, 100)
	anchor.size = Vector2(40, 40)
	host.add_child(anchor)

	# 1. 带 icon 的 payload（武器/道具）
	var w_payload := CodexTipData.weapon_payload("qingyun_sword")
	_c.check(w_payload.has("icon") and not String(w_payload["icon"]).is_empty(), "武器 payload 包含 icon 路径")
	var tip1 := DetailTip.show_over(host, anchor, w_payload)
	_c.check(tip1 != null, "DetailTip 打开成功")
	await get_tree().process_frame

	var found_icon1 := false
	var icon_size1 := Vector2.ZERO
	for node in _find_all_texture_rects(tip1):
		if node.custom_minimum_size.x >= 128.0:
			found_icon1 = true
			icon_size1 = node.custom_minimum_size
			break
	_c.check(found_icon1, "武器详情卡内包含 128x128 大图 TextureRect（实得 %s）" % str(icon_size1))
	tip1.queue_free()

	# 2. 纯文字 payload（如属性说明）不生成大图槽
	var text_payload := {"title": "纯文本", "rows": [["测试", "值"]]}
	var tip2 := DetailTip.show_over(host, anchor, text_payload)
	await get_tree().process_frame
	var found_icon2 := false
	for node in _find_all_texture_rects(tip2):
		if node.custom_minimum_size.x >= 128.0:
			found_icon2 = true
			break
	_c.check(not found_icon2, "纯文字 payload 不会虚占大图槽")
	tip2.queue_free()

	host.queue_free()
	for i in range(3):
		await get_tree().process_frame

func _find_all_texture_rects(root: Node) -> Array[TextureRect]:
	var res: Array[TextureRect] = []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is TextureRect:
			res.append(n as TextureRect)
		for ch in n.get_children():
			stack.append(ch)
	return res
