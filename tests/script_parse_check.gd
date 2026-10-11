extends Node

## 全量 GDScript 解析与实例化判据：递归扫描 scripts/ 目录下全部 .gd 脚本，
## 逐一通过 ResourceLoader 加载并校验 can_instantiate()。
## 运行: godot --headless --path . res://tests/ScriptParseCheck.tscn
##       godot --headless --path . res://tests/ScriptParseCheck.tscn -- --selftest
##
## 为什么立这条判据：Godot 4.7 的 --check-only 与部分 headless 模式在遇到 GDScript
## 块级作用域等 Parse Error 时，进程退出码仍返回 0，仅在 stderr 打印错误日志，
## 导致 v0.0.18 中 ProceduralProjectileRenderer._draw_spirit_pellet 的缩进解析错误
## 漏过自动化回归，进而使整份渲染器脚本加载失败、全远程法器飞行弹丸隐形。
## 本判据实载全部运行期脚本并断言 can_instantiate()，从根本上防止语法解析错误流入发行包。

const SCAN_ROOTS: Array[String] = ["res://scripts"]
const MIN_SCRIPTS := 100

var _c := TestCheck.new()

func _ready() -> void:
	if "--selftest" in OS.get_cmdline_user_args():
		_selftest()
		if _c.report("SCRIPT_PARSE_SELFTEST_RESULT"):
			get_tree().quit(0)
		else:
			get_tree().quit(1)
		return
	_run_all()
	if _c.report("SCRIPT_PARSE_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)

func _run_all() -> void:
	var paths: Array[String] = []
	for root in SCAN_ROOTS:
		_collect_gd_files(root, paths)
	paths.sort()

	_c.check(_count_ok(paths.size()),
		"脚本扫描数量正常（实扫 %d 份，下限 %d）" % [paths.size(), MIN_SCRIPTS])

	var broken: Array[String] = []
	for path in paths:
		var scr := load(path) as GDScript
		if not _is_script_valid(scr):
			broken.append(path)

	_c.check(broken.is_empty(),
		"全部 %d 份 GDScript 均可正常解析并实例化%s" % [paths.size(), _format_broken(broken)])

	# 专项钉住曾出事的弹丸矢量渲染器与弹丸宿主：不仅能解析，还能 new() 出非空节点
	var renderer_scr := load("res://scripts/weapons/ProceduralProjectileRenderer.gd") as GDScript
	var renderer_inst: Object = renderer_scr.new() if _is_script_valid(renderer_scr) else null
	_c.check(renderer_inst != null and renderer_inst is Node2D,
		"ProceduralProjectileRenderer 可解析并实例化为 Node2D")
	if renderer_inst is Node:
		(renderer_inst as Node).free()

	var proj_scr := load("res://scripts/weapons/BladeProjectile.gd") as GDScript
	var proj_inst: Object = proj_scr.new() if _is_script_valid(proj_scr) else null
	_c.check(proj_inst != null and proj_inst is Area2D,
		"BladeProjectile 可解析并实例化为 Area2D")
	if proj_inst is Node:
		(proj_inst as Node).free()

	var drone_scr := load("res://scripts/weapons/ProceduralDroneRenderer.gd") as GDScript
	var drone_inst: Object = drone_scr.new() if _is_script_valid(drone_scr) else null
	_c.check(drone_inst != null and drone_inst is Node2D,
		"ProceduralDroneRenderer 可解析并实例化为 Node2D")
	if drone_inst is Node:
		(drone_inst as Node).free()

	var orb_scr := load("res://scripts/weapons/SunOrb.gd") as GDScript
	var orb_inst: Object = orb_scr.new() if _is_script_valid(orb_scr) else null
	_c.check(orb_inst != null and orb_inst is Area2D,
		"SunOrb 可解析并实例化为 Area2D")
	if orb_inst is Node:
		(orb_inst as Node).free()

static func _is_script_valid(scr: GDScript) -> bool:
	return scr != null and scr.can_instantiate()

static func _count_ok(n: int) -> bool:
	return n >= MIN_SCRIPTS

static func _format_broken(broken: Array[String]) -> String:
	if broken.is_empty():
		return ""
	return "，失败 %d 份：%s" % [broken.size(), str(broken)]

func _collect_gd_files(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	while true:
		var entry := dir.get_next()
		if entry == "":
			break
		if entry.begins_with("."):
			continue
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			_collect_gd_files(full, out)
		elif entry.ends_with(".gd"):
			out.append(full)
	dir.list_dir_end()

func _selftest() -> void:
	# 正例：循环内变量在循环内使用，reload 应返回 OK 且可实例化
	var good := GDScript.new()
	good.source_code = "extends RefCounted\nfunc f() -> int:\n\tvar s := 0\n\tfor i in range(3):\n\t\tvar t := i * 2\n\t\ts += t\n\treturn s\n"
	var good_err := good.reload()
	_c.check(good_err == OK and _is_script_valid(good),
		"selftest 正例：合法块级作用域脚本 reload()==OK 且可实例化")

	# 反例：复现 v0.0.18 的 for 循环变量越界引用，_is_script_valid 必须拦截（返回 false）
	var bad := GDScript.new()
	bad.source_code = "extends RefCounted\nfunc f() -> float:\n\tfor i in range(3):\n\t\tvar t := float(i)\n\tvar pt := t * 2.0\n\treturn pt\n"
	var bad_err := bad.reload()
	_c.check(bad_err != OK and not _is_script_valid(bad),
		"selftest 反例：for 循环变量越界脚本被拦截（reload err=%d, valid=%s）" % [
			bad_err, str(_is_script_valid(bad))
		])

	# 数量下限门禁反例
	_c.check(not _count_ok(0) and not _count_ok(MIN_SCRIPTS - 1) and _count_ok(MIN_SCRIPTS),
		"selftest 数量门禁：低于 %d 份判失败" % MIN_SCRIPTS)
	_c.check(not _is_script_valid(null),
		"selftest 空引用门禁：null 脚本判失败")
