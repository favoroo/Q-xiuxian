extends Node

## MiSans 子集化覆盖判据：两份在用的字重必须覆盖「字集」，且源码里出现的字符必须在
## 「字集 ∪ 豁免账」之内。
## 运行: godot --headless --path . res://tests/FontCoverageCheck.tscn
##       godot --headless --path . res://tests/FontCoverageCheck.tscn -- --selftest
##
## 为什么立这条判据：字体子集化省下的 8.79 MB 是拿「字形覆盖面」换来的 —— 而覆盖面一旦
## 出事，编辑器里看不出来（macOS 拿系统回退字体兜着），只有 Android 真机上才会某一句
## 突然换了字形。这类毛病不崩不报错，只能靠静态账本钉住。
##
## 三个账本（都在 tools/ 下，由 tools/subset_fonts.py 生成）：
##   字集　　　　 charset.txt      两份字重保留的字形清单，也是 pyftsubset 的输入
##   豁免账　　　 exempt_chars.txt 源码里有、但 MiSans 渲染不了的字（⇒ ✦ 这类，靠系统回退）
##   （源码本身） 现场重扫，不落盘
##
## 三段账：
##   A 段 字集 ⊆ 字体：字集里每个码位，两份字重都要有字形（用字体自己的 cmap 说话）
##   B 段 源码 ⊆ 字集 ∪ 豁免账：现场重扫源码文本，源码里每个可渲染字符都要有着落
##        —— 这是**防漂移的牙齿**：以后谁加了一句带生僻字的文案，这条就会红。
##        本项目真事：判据第一次跑就抓到它自己新写的文档注释里那三个字。
##   C 段 字集 ∩ 豁免账 = ∅：同一个字不能既是「字体有」又是「字体没有」
##
## 扫描口径必须与 tools/subset_fonts.py 的 SCAN_EXTS / SKIP_DIRS 一致，改一边要改两边。

const CHARSET_PATH := "res://tools/font_charset.txt"
const EXEMPT_PATH := "res://tools/font_exempt_chars.txt"

const SCAN_EXTS: Array[String] = [".gd", ".tscn", ".tres", ".cfg", ".godot"]
const SKIP_DIRS: Array[String] = ["build", "assets_raw", "android"]

## 子集化的收益全靠「字形数掉下来」兑现，这条上限是防「有人把整份 MiSans 换回去」的静默
## 回归：子集 4558 个码位，整份 MiSans 是三万量级，留一倍余量。
const FONT_GLYPH_CEILING := 8000
## 字集文件的规模下限。文件被清空/截断时 A 段会「零个字符全部通过」，这条是那口牙齿。
const CHARSET_MIN := 3000
## 豁免账上限：它是一份**要人拍板**的例外清单，涨到几十条就说明字集口径该重新谈了
## （多半是文案里混进了一整类 MiSans 没有的符号，该换符号而不是继续加例外）。
const EXEMPT_CEILING := 32
## 源码扫描至少要捞到这么多文件，否则说明目录遍历坏了，B 段同样是假绿。
const SCAN_MIN_FILES := 50

var _c := TestCheck.new()
var _scan_files: int = 0

func _ready() -> void:
	if "--selftest" in OS.get_cmdline_user_args():
		_selftest()
		if _c.report("FONT_COVERAGE_SELFTEST_RESULT"):
			get_tree().quit(0)
		else:
			get_tree().quit(1)
		return
	_run_all()
	if _c.report("FONT_COVERAGE_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)

func _run_all() -> void:
	# ---- A 段：字集 ⊆ 字体 ----
	var charset := _load_char_file(CHARSET_PATH)
	_c.check(_charset_ok(charset.size()),
		"字集规模正常（%d 个码位，下限 %d）" % [charset.size(), CHARSET_MIN])
	for item in [[GameStyle.FONT_BODY, "正文"], [GameStyle.FONT_DISPLAY, "标题"]]:
		var path: String = item[0]
		var label: String = item[1]
		var font: Font = load(path)
		if not _c.check(font != null, "%s字重可加载（%s）" % [label, path.get_file()]):
			continue
		var supported := _supported_set(font)
		# 尺子对照：先证这把尺子既不是空的、也不会走去系统回退字体。真走了回退，A 段的账
		# 就不是这两份字体的账了，全绿也是假的。U+2726（✦）不在 MiSans 里，正好当反例。
		_c.check(supported.size() > 0 and not supported.has(0x2726),
			"%s字重尺子对照：能读到 cmap 且不含 U+2726 ✦（实得字形 %d）" % [label, supported.size()])
		var missing: Array = _drift(charset, supported)
		_c.check(missing.is_empty(),
			"%s字重覆盖字集全部 %d 个码位%s" % [label, charset.size(), _sample(missing)])
		_c.check(_font_size_ok(supported.size()),
			"%s字重确实是子集（字形 %d，上限 %d）" % [label, supported.size(), FONT_GLYPH_CEILING])

	# ---- C 段：字集与豁免账不相交 ----
	var exempt := _load_char_file(EXEMPT_PATH)
	_c.check(_exempt_ok(exempt.size()),
		"豁免账规模正常（%d 个码位，上限 %d）" % [exempt.size(), EXEMPT_CEILING])
	var overlap: Array = _intersection(charset, exempt)
	_c.check(overlap.is_empty(),
		"字集与豁免账无交集（同一个字不能既算「字体有」又算「字体没有」）%s" % _sample(overlap))

	# ---- B 段：源码 ⊆ 字集 ∪ 豁免账 ----
	var scan := _scan_source_chars()
	_c.check(int(scan["files"]) >= SCAN_MIN_FILES,
		"源码扫描到 %d 个文本文件（下限 %d）" % [int(scan["files"]), SCAN_MIN_FILES])
	var allowed := charset.duplicate()
	for cp in exempt.keys():
		allowed[cp] = true
	var drift: Array = _drift(scan["chars"], allowed)
	_c.check(drift.is_empty(), "源码里出现的字符全在「字集 ∪ 豁免账」内%s" % _sample(drift))

## 反例必须被拦住（判据自己有牙齿）
func _selftest() -> void:
	var font: Font = load(GameStyle.FONT_BODY)
	var supported := _supported_set(font)
	_c.check(supported.size() > 0, "正例① 尺子读到 %d 个字形" % supported.size())
	_c.check(_drift({0x4FEE: true}, supported).is_empty(),
		"正例① 字体有的字（修 U+4FEE）不误报")
	_c.check(not _drift({0x2726: true}, supported).is_empty(),
		"反例① 字体缺的字（✦ U+2726）被 _drift 抓到")

	_c.check(not _charset_ok(0) and not _charset_ok(CHARSET_MIN - 1) and _charset_ok(CHARSET_MIN),
		"反例② 空/截断字集过不了规模守卫，刚好达标才放行")
	_c.check(not _font_size_ok(FONT_GLYPH_CEILING + 1) and _font_size_ok(FONT_GLYPH_CEILING),
		"反例② 整份 MiSans（三万字形）过不了子集上限")
	_c.check(not _exempt_ok(EXEMPT_CEILING + 1) and _exempt_ok(EXEMPT_CEILING),
		"反例② 豁免账涨过头会碰上限")

	var charset := _load_char_file(CHARSET_PATH)
	var exempt := _load_char_file(EXEMPT_PATH)
	var allowed := charset.duplicate()
	for cp in exempt.keys():
		allowed[cp] = true
	_c.check(_drift(charset, charset).is_empty(), "正例③ 字集对自己无漂移")
	_c.check(_drift({0x2726: true}, allowed).is_empty(),
		"正例③ 豁免账里的字（✦ U+2726）被 B 段放行")
	_c.check(_intersection({0x4FEE: true, 0x2726: true}, {0x2726: true, 0x9F98: true}) == [0x2726],
		"正例⑤ _intersection 找出共同元素")
	_c.check(_intersection({0x4FEE: true}, {0x2726: true}).is_empty(),
		"反例⑤ 不相交的集合返回空")
	# 这个怪字必须用 char(0x…) 拼出来，不能写成字面量：判据扫的是整棵源码树（含它自己），
	# 写成语面量就等于自己往源码里塞了个字集外的字，B 段会红给自己看（第一版就是这么栽的）。
	var weird := char(0x2000B)
	_c.check(not _drift({weird.unicode_at(0): true}, allowed).is_empty(),
		"反例③ 字集与豁免账之外的字（U+2000B）会被 B 段抓到")

	var scan := _scan_source_chars()
	var found: int = int(scan["files"])
	var chars: Dictionary = scan["chars"]
	_c.check(found >= SCAN_MIN_FILES, "正例④ 扫描器捞到 %d 个文本文件" % found)
	_c.check(chars.size() > 100, "正例④ 扫描器捞到 %d 个不同字符" % chars.size())
	_c.check(not _has_scan_ext("x.png") and _has_scan_ext("Main.gd") and _has_scan_ext("project.godot"),
		"正例④ 文件后缀筛选只放行文本资源")


# ---------------- 纯判据（真跑与 selftest 走同一份代码） ----------------

func _charset_ok(count: int) -> bool:
	return count >= CHARSET_MIN

func _font_size_ok(glyphs: int) -> bool:
	return glyphs <= FONT_GLYPH_CEILING

func _exempt_ok(count: int) -> bool:
	return count <= EXEMPT_CEILING

## 在 source 里但不在 allowed 里的码位（升序）。两边都是「码位字典当集合」。
func _drift(source: Dictionary, allowed: Dictionary) -> Array:
	var out: Array = []
	for cp in source.keys():
		if not allowed.has(cp):
			out.append(cp)
	out.sort()
	return out

## 两个集合的交集（升序）。
func _intersection(a: Dictionary, b: Dictionary) -> Array:
	var out: Array = []
	for cp in a.keys():
		if b.has(cp):
			out.append(cp)
	out.sort()
	return out


# ---------------- 取数与扫描 ----------------

## 字体自己的 cmap。用 get_supported_chars 而不是逐个 has_char：一次调用拿到全集，
## 4557 次查表变集合差，而且不会被 Font.has_char 的「含 fallback」口径混淆。
## （实测这个数字就是 cmap 项数：子集 4558，原件 29571 —— 差值正好卡住「换字体没重导」那种假绿。）
func _supported_set(font: Font) -> Dictionary:
	var out: Dictionary = {}
	var s := font.get_supported_chars()
	for i in s.length():
		out[s.unicode_at(i)] = true
	return out

## 账本文件就是一个字符集合，怎么折行无所谓；控制字符（折行的 \n）要滤掉，
## 它们不在任何字体的 cmap 里，留着账永远对不上。
func _load_char_file(path: String) -> Dictionary:
	var out: Dictionary = {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("[FontCoverageCheck] 读不到 %s，先跑 tools/subset_fonts.py" % path)
		return out
	var text := f.get_as_text()
	for i in text.length():
		var cp := text.unicode_at(i)
		if _renderable(cp):
			out[cp] = true
	return out

func _scan_source_chars() -> Dictionary:
	_scan_files = 0
	var chars: Dictionary = {}
	_walk_dir("res://", chars)
	return {"files": _scan_files, "chars": chars}

func _walk_dir(path: String, chars: Dictionary) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		# 点开头的目录/文件一律跳过：.godot/.git/.agents… 与 subset_fonts.py 的 SKIP_DIRS 同口径
		if not name.begins_with("."):
			var full := path.path_join(name)
			if dir.current_is_dir():
				if not SKIP_DIRS.has(name):
					_walk_dir(full, chars)
			elif _has_scan_ext(name):
				_scan_files += 1
				var f := FileAccess.open(full, FileAccess.READ)
				if f != null:
					var text := f.get_as_text()
					for i in text.length():
						var cp := text.unicode_at(i)
						if _renderable(cp):
							chars[cp] = true
		name = dir.get_next()
	dir.list_dir_end()

func _has_scan_ext(name: String) -> bool:
	for e in SCAN_EXTS:
		if name.ends_with(e):
			return true
	return false

## 控制字符没有字形（\n \t 也不在任何字体的 cmap 里），两边扫描都得滤掉，否则账永远对不上
func _renderable(cp: int) -> bool:
	if cp < 0x20 or cp == 0x7F:
		return false
	return cp < 0x80 or cp > 0x9F

## 缺字样本：空集返回空串，否则打出前 20 个字符，失败原因一眼可见
func _sample(missing: Array) -> String:
	if missing.is_empty():
		return ""
	var shown := ""
	for i in mini(missing.size(), 20):
		shown += char(int(missing[i]))
	return "，缺 %d 个：前 %d「%s」" % [missing.size(), mini(missing.size(), 20), shown]
