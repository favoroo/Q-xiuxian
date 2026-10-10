class_name ShopWeaponTip
extends RefCounted

## 灵石阁法器悬浮详情卡：全部属性 + 流派进度 + 快捷操作（三合一 / 装备卸换 / 出售）。
## 从 WaveShop 拆出：宿主仍是 shop（DetailTip 判据按宿主收卡），操作回调经 shop 门面刷新。

static func open(shop: WaveShop, item: Dictionary, pool: String, index: int, anchor: Control) -> void:
	var id: String = String(item.get("id", ""))
	var def := WeaponData.get_def(id)
	if def.is_empty():
		return
	var star := clampi(int(item.get("star", 1)), 1, WeaponData.MAX_STAR)
	var in_stash := pool == "stash"
	var mergeable: bool = star < WeaponData.MAX_STAR and GameManager.count_copies(id, star) >= 3

	var base_dmg: float = float(def.get("damage", 0.0))
	var star_mul: float = pow(WeaponData.STAR_DAMAGE_MULT, float(star - 1))
	var bonus: float = GameManager.get_weapon_stat_bonus(id, star)
	var gm_dmg: float = GameManager.weapon_damage_mult
	var syn_dmg: float = GameManager.synergy_damage_mult
	var cult_dmg: float = GameManager.cultivator_damage_mult(id)
	var elem_dmg: float = GameManager.element_damage_mult(id)
	var per_hit: float = (base_dmg * star_mul + bonus) * gm_dmg * syn_dmg * cult_dmg * elem_dmg
	var cd: float = WeaponData.cooldown_for(id, star) * GameManager.attack_speed_mult * GameManager.synergy_haste_mult
	var base_range: float = float(def.get("range", 0.0))
	var eff_range: float = base_range * GameManager.attack_range_mult * GameManager.synergy_range_mult
	var range_buffed: bool = not is_equal_approx(eff_range, base_range)
	var range_txt: String = "%.0f" % eff_range
	if range_buffed:
		range_txt = "%.0f（基础 %.0f）" % [eff_range, base_range]

	var syn_parts: Array[String] = []
	for t in def.get("tags", []):
		var sinfo: Dictionary = WeaponData.SYNERGIES.get(t, {})
		if not sinfo.is_empty():
			var cnt: int = GameManager.get_tag_count(String(t))
			syn_parts.append("%s(%d/6)" % [sinfo.get("name", t), cnt])

	var max_slots: int = GameManager.max_weapon_slots()
	var slots_full: bool = GameManager.slots_used() >= max_slots
	var loc_txt := "背包中" if in_stash else "装备中"
	if in_stash and slots_full:
		loc_txt = "背包中（装备已满 %d/%d）" % [GameManager.slots_used(), max_slots]

	var bonus_col: Color = GameStyle.GOOD if bonus > 0.0001 else (GameStyle.BAD if bonus < -0.0001 else GameStyle.PAPER)
	var rows: Array = [
		["当前位置", loc_txt, GameStyle.PAPER_DIM if in_stash else GameStyle.GOOD],
		["单发伤害", "%.1f" % per_hit, GameStyle.JADE],
		["流派进度", " · ".join(syn_parts) if not syn_parts.is_empty() else "—", GameStyle.GOOD],
		["基础 × 星级", "%.0f × %.1f" % [base_dmg, star_mul]],
		["属性转化", "+%.1f" % bonus, bonus_col],
		["攻击间隔", "%.2f 秒" % cd],
		["攻击范围", range_txt, GameStyle.JADE if range_buffed else GameStyle.PAPER],
	]
	var feats := StatsTipFactory.weapon_feats(def)
	if not feats.is_empty():
		rows.append(["特性", feats])

	var copies_total := GameManager.count_copies(id, star)
	var price := WeaponData.sell_price(id, star)
	var notes: Array[String] = [
		"%s（每星效率 +25%%）。" % WeaponData.scaling_desc(id),
	]
	if mergeable:
		notes.append("已集齐 3 件同名同星，可点击下方【三合一】升至 %s！" % WeaponData.star_text(star + 1))
	else:
		notes.append("三合一升星：同名同星集满 3 件可合成升星（当前持有 %d/3 件）。" % copies_total)

	var foot := "同名同星 %d 件 · 出售可得 %d 金币" % [copies_total, price]
	if in_stash:
		foot += "\n在背包中：未装备、不参与攻击，可用于三合一升星或换装装备。"

	var actions: Array = []
	if mergeable:
		actions.append([{
			"text": "✦ 三合一 · 升至 %s ✦" % WeaponData.star_text(star + 1),
			"color": GameStyle.JADE,
			"edge_color": GameStyle.JADE_EDGE,
			"text_color": GameStyle.INK_TEXT,
			"callback": func() -> void:
				var keep := {"pool": "equipped", "index": index}
				if in_stash:
					keep["pool"] = "stash"
				elif item.get("is_drone", false):
					keep["pool"] = "drone"
					keep["index"] = int(item.get("drone_index", -1))
				if not GameManager.merge_weapon(id, star, keep):
					AudioManager.play_sfx("ui_error", 0.9)
				shop.selected = {}
				shop.refresh(false)
		}])

	var row_ops: Array = []
	if in_stash:
		var move_disabled := slots_full
		var move_text := "装备已满(%d/%d)" % [GameManager.slots_used(), max_slots] if slots_full else "装  备"
		row_ops.append({
			"text": move_text,
			"disabled": move_disabled,
			"color": GameStyle.GOOD if not move_disabled else GameStyle.NAVY2,
			"edge_color": GameStyle.GOOD_DK if not move_disabled else GameStyle.LINE,
			"text_color": GameStyle.INK_TEXT if not move_disabled else GameStyle.GREY,
			"callback": func() -> void:
				if GameManager.equip_from_stash(index):
					shop.selected = {}
					shop.refresh(false)
		})
	else:
		var unequip_disabled := GameManager.stash.size() >= WeaponData.MAX_STASH_SLOTS
		var unequip_text := "背包已满" if unequip_disabled else "卸入背包"
		row_ops.append({
			"text": unequip_text,
			"disabled": unequip_disabled,
			"color": GameStyle.NAVY2,
			"edge_color": GameStyle.LINE,
			"text_color": GameStyle.PAPER if not unequip_disabled else GameStyle.GREY,
			"callback": func() -> void:
				if GameManager.unequip_to_stash(index):
					shop.selected = {}
					shop.refresh(false)
		})

	row_ops.append({
		"text": "售 %d 金币" % price,
		"color": GameStyle.BAD,
		"edge_color": GameStyle.BAD_DK,
		"text_color": GameStyle.CHALK,
		"callback": func() -> void:
			var ok := false
			if in_stash:
				ok = GameManager.sell_stash(index)
			else:
				ok = GameManager.sell_weapon(index)
			if ok:
				shop.selected = {}
				shop.refresh(false)
	})
	actions.append(row_ops)

	var tip_data := {
		"title": "%s %s" % [String(def.get("name", "武器")), WeaponData.star_text(star)],
		"chip": " · ".join(syn_parts) if not syn_parts.is_empty() else String(def.get("tag", "")),
		"chip_color": GameStyle.JADE_DK if in_stash else GameStyle.GOLD_DK,
		"rows": rows,
		"body": String(def.get("desc", "")),
		"notes": notes,
		"foot": foot,
		"actions": actions,
	}

	var tip := DetailTip.show_over(shop, anchor, tip_data)
	if tip != null:
		tip.closed.connect(func() -> void:
			if shop.selected.get("pool", "") == pool and int(shop.selected.get("index", -1)) == index:
				shop.selected = {}
				shop._refresh_inventory()
		)
