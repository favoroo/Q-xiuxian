extends Node

## 应用内更新管理器
## 对标 dudu-cocos 的 update-service.ts：国内 Gitee 优先、GitHub 备选、代理镜像兜底
## 继承 Node，支持 HTTPRequest 子节点异步通信

signal update_available(info: Dictionary)
signal no_update_found()
signal check_failed(error_msg: String)
signal download_progress(loaded: int, total: int, percent: float, speed: float, eta_sec: float)
signal download_completed(file_path: String)
signal download_failed(error_msg: String)

const LAST_CHECK_FILE: String = "user://last_update_check.json"
const TWENTY_FOUR_HOURS_MSEC: int = 24 * 60 * 60 * 1000
const APK_FILE_NAME: String = "q_xiuxian_update.apk"

var pending_update: Dictionary = {}
var is_checking: bool = false
var is_downloading: bool = false
var _last_check_manual: bool = false

var _check_http: HTTPRequest
var _download_http: HTTPRequest
var _download_file_path: String = ""
var _download_candidates: Array[String] = []
var _current_candidate_idx: int = 0
var _expected_file_size: int = 0

var _download_start_time: float = 0.0
var _last_sample_time: float = 0.0
var _last_sample_bytes: int = 0
var _smooth_speed: float = 0.0
var _is_cancelled: bool = false

const UpdateDialogScript = preload("res://scripts/ui/UpdateDialog.gd")

var _dialog_canvas: CanvasLayer
var _dialog_instance: Control

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_check_http = HTTPRequest.new()
	_check_http.timeout = 8.0
	add_child(_check_http)

	_download_http = HTTPRequest.new()
	_download_http.timeout = 300.0
	_download_http.request_completed.connect(_on_download_request_completed)
	add_child(_download_http)

	_init_dialog()

var _toast_canvas: CanvasLayer
var _toast_band: CenterContainer
var _toast_panel: PanelContainer
var _toast_label: Label
var _toast_tween: Tween

## 浮层几何。宽度跟着文案算、横向由居中容器摆，滑移走 CanvasLayer.offset。
## 三条各管一段，别再互相依赖：
##  · x  —— CenterContainer（旧写法手拍 position.x = -160，把锚点当原点，整块推到屏外）
##  · 宽 —— _fit_toast 量文案（旧写法固定 320，长一句失败原因被裁）
##  · y  —— 画布偏移（旧写法 tween 节点 position，会把入树前算好的 offset_bottom 烘成脏值，
##          实测浮层会从 y=36 掉到 y=197：容器按一个过期的巨大 min height 垂直居中了子节点。
##          另记一笔：CanvasLayer.offset 只在绘制时生效，不折进子控件的 get_global_rect()，
##          所以判据量的是「布局 rect + 层偏移」= 屏幕上那格，见 tests/toast_check.gd）
const TOAST_FONT_SIZE: int = 13       # 与 _init_toast 里 GameStyle.label 的字号同源
const TOAST_PAD_X: float = 16.0       # 与 MarginContainer 左右内边距同源
const TOAST_PAD_Y: float = 6.0        # 与 MarginContainer 上下内边距同源
const TOAST_MIN_W: float = 240.0      # 短句也留个体面宽度，不缩成一条签
const TOAST_MAX_W: float = 620.0      # 长文案到此折行，不铺成通宽横幅
const TOAST_MIN_H: float = 38.0
const TOAST_EDGE_MARGIN: float = 12.0 # 屏边留白：文案再长也不贴屏沿
const TOAST_TOP: float = 36.0         # 浮层顶缘（画布坐标）
const TOAST_SLIDE: float = 16.0       # 入场/退场滑移量

func _init_dialog() -> void:
	# 顶层 CanvasLayer 保证弹窗覆盖在全部 UI 与操作之上
	_dialog_canvas = CanvasLayer.new()
	_dialog_canvas.layer = 100
	add_child(_dialog_canvas)

	_dialog_instance = UpdateDialogScript.new()
	_dialog_canvas.add_child(_dialog_instance)

	_init_toast()

	update_available.connect(func(info: Dictionary):
		_last_check_manual = false
		show_update_dialog(info)
	)
	no_update_found.connect(func():
		if _last_check_manual:
			_last_check_manual = false
			show_toast("✦ 当前已是最新版本 (%s) ✦" % Version.APP_VERSION_NAME, GameStyle.GOOD)
	)
	check_failed.connect(func(err_msg: String):
		if _last_check_manual:
			_last_check_manual = false
			show_toast("检查更新失败（%s），请稍后重试" % err_msg, GameStyle.BAD)
	)

func _init_toast() -> void:
	# 浮层单独一层：滑移只动这一层的 offset，不碰任何控件的锚点/偏移
	_toast_canvas = CanvasLayer.new()
	_toast_canvas.layer = 101
	add_child(_toast_canvas)

	# 顶部整幅宽的居中容器：横向位置由布局系统算，不再手拍 x
	_toast_band = CenterContainer.new()
	_toast_band.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_toast_band.offset_top = TOAST_TOP
	_toast_band.offset_bottom = TOAST_TOP
	_toast_band.grow_vertical = Control.GROW_DIRECTION_END
	_toast_band.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_toast_panel = PanelContainer.new()
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := GameStyle.panel(GameStyle.NAVY, GameStyle.SLANT_BUTTON, Vector2(3, 4))
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 4
	style.border_color = GameStyle.JADE
	_toast_panel.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", int(TOAST_PAD_X))
	margin.add_theme_constant_override("margin_right", int(TOAST_PAD_X))
	margin.add_theme_constant_override("margin_top", int(TOAST_PAD_Y))
	margin.add_theme_constant_override("margin_bottom", int(TOAST_PAD_Y))
	_toast_panel.add_child(margin)

	_toast_label = Label.new()
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.text = ""
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	GameStyle.label(_toast_label, TOAST_FONT_SIZE, GameStyle.PAPER, 0, GameStyle.INK, true)
	margin.add_child(_toast_label)

	_toast_band.add_child(_toast_panel)

	_toast_band.visible = false
	_toast_band.modulate.a = 0.0
	_toast_canvas.add_child(_toast_band)

## 量文案定宽度：一行放得下就贴着文案走，放不下才折到上限宽。
## 只量**宽度**——高度交给 Label 自己（autowrap + 钉住内宽）：PanelContainer 的
## custom_minimum_size 是地板不是天花板（容器恒取 max(自己, 子节点所需)），
## 所以折几行都不会被裁。反过来若在这里按 get_string_size 猜行高就坏了 ——
## 那个 API 传了 width 也只回一行高（判据 --selftest 反例②就是这么露出来的）。
func _fit_toast(text: String) -> void:
	var font: Font = _toast_label.get_theme_font("font")
	var size: int = _toast_label.get_theme_font_size("font_size")
	var style: StyleBoxFlat = _toast_panel.get_theme_stylebox("panel") as StyleBoxFlat
	# 描边也占宽度：只按内边距算会少 4 单位，620 的上限实得 624（判据 ③ 抓到过）
	var chrome := Vector2(
		TOAST_PAD_X * 2.0 + style.border_width_left + style.border_width_right,
		TOAST_PAD_Y * 2.0 + style.border_width_top + style.border_width_bottom)
	var screen_w: float = get_viewport().get_visible_rect().size.x
	var cap: float = minf(TOAST_MAX_W, maxf(TOAST_MIN_W, screen_w - TOAST_EDGE_MARGIN * 2.0))
	var text_w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var w: float = clampf(text_w + chrome.x, minf(TOAST_MIN_W, cap), cap)
	# 钉住 Label 的折行宽 = 它实际拿到的内宽，容器才不会拿 0 宽去量高度
	_toast_label.custom_minimum_size = Vector2(maxf(0.0, w - chrome.x), 0.0)
	_toast_panel.custom_minimum_size = Vector2(w, maxf(TOAST_MIN_H, chrome.y))

## 展示全局轻提示浮层（Toast）
func show_toast(text: String, accent_color: Color = GameStyle.JADE, duration: float = 2.2) -> void:
	if _toast_band == null or _toast_panel == null or _toast_label == null:
		return
	_toast_label.text = text
	var style: StyleBoxFlat = _toast_panel.get_theme_stylebox("panel") as StyleBoxFlat
	if style:
		style.border_color = accent_color
	_toast_label.add_theme_color_override("font_color", GameStyle.PAPER if accent_color != GameStyle.BAD else GameStyle.BAD)
	_fit_toast(text)

	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()

	_toast_band.visible = true
	_toast_band.modulate.a = 0.0
	_toast_canvas.offset = Vector2.ZERO

	_toast_tween = create_tween()
	_toast_tween.set_parallel(true)
	_toast_tween.tween_property(_toast_band, "modulate:a", 1.0, 0.18)
	_toast_tween.tween_property(_toast_canvas, "offset:y", TOAST_SLIDE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_toast_tween.chain().tween_interval(duration)
	_toast_tween.chain().tween_property(_toast_band, "modulate:a", 0.0, 0.2)
	_toast_tween.tween_property(_toast_canvas, "offset:y", 0.0, 0.2)
	_toast_tween.chain().tween_callback(func():
		_toast_band.visible = false
	)

## 浮层当前占位、文案所需尺寸与屏幕可视尺寸
## （供 tests/ToastCheck 量「在屏内 + 居中 + 装得下」，不参与任何逻辑）
func toast_probe() -> Dictionary:
	if _toast_panel == null or _toast_label == null or not is_instance_valid(_toast_panel):
		return {}
	return {
		"rect": _toast_panel.get_global_rect(),
		"label_min": _toast_label.get_combined_minimum_size(),
		"offset": _toast_canvas.offset,
		"screen": get_viewport().get_visible_rect().size,
	}

## 主动弹出更新对话框
func show_update_dialog(info: Dictionary) -> void:
	if _dialog_instance:
		_dialog_instance.popup_update(info)

func _process(delta: float) -> void:
	if not is_downloading or _download_http == null:
		return

	var loaded: int = _download_http.get_downloaded_bytes()
	var body_size: int = _download_http.get_body_size()
	var total: int = body_size if body_size > 0 else _expected_file_size

	var now: float = Time.get_ticks_msec() / 1000.0
	var dt: float = now - _last_sample_time
	if dt >= 0.25 and loaded >= _last_sample_bytes:
		var instant_speed: float = float(loaded - _last_sample_bytes) / dt
		if _smooth_speed > 0.0:
			_smooth_speed = _smooth_speed * 0.65 + instant_speed * 0.35
		else:
			_smooth_speed = instant_speed
		_last_sample_time = now
		_last_sample_bytes = loaded

	var percent: float = 0.0
	var eta_sec: float = 0.0
	if total > 0 and loaded > 0:
		percent = clampf(float(loaded) / float(total) * 100.0, 0.0, 99.0)
		if _smooth_speed > 0.0:
			eta_sec = float(total - loaded) / _smooth_speed

	download_progress.emit(loaded, total, percent, _smooth_speed, eta_sec)

## 判断是否需要启动冷检测（24小时节流）
func should_run_startup_check() -> bool:
	if not FileAccess.file_exists(LAST_CHECK_FILE):
		return true
	var file := FileAccess.open(LAST_CHECK_FILE, FileAccess.READ)
	if not file:
		return true
	var json_str := file.get_as_text()
	var data = JSON.parse_string(json_str)
	if not (data is Dictionary) or not data.has("last_check_msec"):
		return true
	var last_time: int = int(data.get("last_check_msec", 0))
	var cur_time: int = int(Time.get_unix_time_from_system() * 1000)
	return (cur_time - last_time) >= TWENTY_FOUR_HOURS_MSEC

func record_check_time() -> void:
	var file := FileAccess.open(LAST_CHECK_FILE, FileAccess.WRITE)
	if file:
		var cur_time: int = int(Time.get_unix_time_from_system() * 1000)
		file.store_string(JSON.stringify({"last_check_msec": cur_time}))

## 执行更新检测
func check_for_update(manual: bool = false) -> void:
	if is_checking:
		if manual:
			_last_check_manual = true
		return
	if not manual and not should_run_startup_check():
		return

	_last_check_manual = manual
	is_checking = true
	_do_check_async()

func _do_check_async() -> void:
	var gitee_url := "https://gitee.com/api/v5/repos/%s/%s/releases/latest" % [Version.GITEE_OWNER, Version.GITEE_REPO]
	var github_url := "https://api.github.com/repos/%s/%s/releases/latest" % [Version.GITHUB_OWNER, Version.GITHUB_REPO]

	var endpoints: Array[String] = [gitee_url, github_url]
	for p in Version.GH_PROXIES:
		endpoints.append(p + github_url)

	var release_data = null
	var last_err := ""

	for ep in endpoints:
		var result = await _fetch_json(ep)
		if result is Dictionary and (result.has("tag_name") or result.has("name")):
			release_data = result
			break
		elif result is Dictionary and result.has("error"):
			last_err = result["error"]

	is_checking = false
	if release_data == null:
		var err_msg := last_err if not last_err.is_empty() else "无法连接到更新服务器"
		check_failed.emit(err_msg)
		return

	record_check_time()

	if release_data.get("draft", false) or release_data.get("prerelease", false):
		pending_update = {}
		no_update_found.emit()
		return

	var tag_name: String = str(release_data.get("tag_name", "")).strip_edges()
	if tag_name.is_empty():
		tag_name = str(release_data.get("name", "")).strip_edges()

	if not Version.is_version_newer(tag_name, Version.APP_VERSION):
		pending_update = {}
		no_update_found.emit()
		return

	# 提取 APK 附件
	var raw_apk_url: String = ""
	var apk_size: int = 0
	var assets = release_data.get("assets", [])
	if assets is Array:
		for item in assets:
			if item is Dictionary:
				var asset_name: String = str(item.get("name", "")).to_lower()
				if asset_name.ends_with(".apk"):
					raw_apk_url = str(item.get("browser_download_url", ""))
					apk_size = int(item.get("size", 0))
					break

	var release_url: String = str(release_data.get("html_url", ""))
	if release_url.is_empty():
		release_url = Version.get_release_page_url(tag_name)

	# 候选下载直链排序
	var candidate_urls: Array[String] = []
	if not raw_apk_url.is_empty():
		if "gitee.com" in raw_apk_url:
			candidate_urls.append(raw_apk_url)
			var file_name: String = raw_apk_url.get_file()
			var gh_direct: String = "https://github.com/%s/%s/releases/download/%s/%s" % [
				Version.GITHUB_OWNER, Version.GITHUB_REPO, tag_name, file_name
			]
			for p in Version.GH_PROXIES:
				candidate_urls.append(p + gh_direct)
			candidate_urls.append(gh_direct)
		elif raw_apk_url.begins_with("https://github.com/"):
			for p in Version.GH_PROXIES:
				candidate_urls.append(p + raw_apk_url)
			candidate_urls.append(raw_apk_url)
		else:
			candidate_urls.append(raw_apk_url)
	else:
		candidate_urls.append(release_url)

	var info := {
		"version": tag_name.trim_prefix("v").trim_prefix("V"),
		"tag_name": tag_name,
		"release_name": str(release_data.get("name", tag_name)),
		"release_notes": str(release_data.get("body", "暂无更新说明")),
		"download_url": candidate_urls[0] if candidate_urls.size() > 0 else release_url,
		"original_download_url": raw_apk_url if not raw_apk_url.is_empty() else release_url,
		"candidate_download_urls": candidate_urls,
		"release_url": release_url,
		"file_size": apk_size,
		"file_size_text": Version.format_bytes(apk_size),
		"has_apk": not raw_apk_url.is_empty(),
	}

	pending_update = info
	update_available.emit(info)

func _fetch_json(url: String) -> Variant:
	var headers: PackedStringArray = [
		"User-Agent: QXiuxian-GodotClient",
		"Accept: application/vnd.github+json, application/json"
	]
	var err := _check_http.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		return {"error": "发起请求失败: %d" % err}

	var res = await _check_http.request_completed
	var result: int = res[0]
	var response_code: int = res[1]
	var body: PackedByteArray = res[3]

	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		return {"error": "HTTP %d" % response_code}

	var json_str := body.get_string_from_utf8()
	var parsed = JSON.parse_string(json_str)
	if parsed == null:
		return {"error": "JSON解析失败"}
	return parsed

## 获取下载保存路径
func get_apk_save_path() -> String:
	return ProjectSettings.globalize_path("user://" + APK_FILE_NAME)

## 开始下载 APK
func start_download(info: Dictionary) -> void:
	if is_downloading:
		return

	_is_cancelled = false
	is_downloading = true
	_download_candidates.clear()
	var list = info.get("candidate_download_urls", [])
	if list is Array:
		for u in list:
			_download_candidates.append(str(u))
	if _download_candidates.is_empty() and info.has("download_url"):
		_download_candidates.append(str(info["download_url"]))

	_current_candidate_idx = 0
	_expected_file_size = int(info.get("file_size", 0))
	_download_file_path = get_apk_save_path()

	_download_start_time = Time.get_ticks_msec() / 1000.0
	_last_sample_time = _download_start_time
	_last_sample_bytes = 0
	_smooth_speed = 0.0

	_try_download_current_candidate()

func _try_download_current_candidate() -> void:
	if _is_cancelled:
		return
	if _current_candidate_idx >= _download_candidates.size():
		is_downloading = false
		download_failed.emit("全部候选下载源均失败")
		return

	var url := _download_candidates[_current_candidate_idx]
	_download_http.download_file = _download_file_path
	var headers: PackedStringArray = [
		"User-Agent: QXiuxian-GodotClient",
		"Accept: application/octet-stream, */*"
	]
	var err := _download_http.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		_on_candidate_failed("请求发起失败: %d" % err)

func _on_download_request_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if _is_cancelled:
		return
	if result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300:
		is_downloading = false
		download_progress.emit(_expected_file_size, _expected_file_size, 100.0, _smooth_speed, 0.0)
		download_completed.emit(_download_file_path)
	else:
		_on_candidate_failed("HTTP %d (result: %d)" % [response_code, result])

func _on_candidate_failed(reason: String) -> void:
	push_warning("[UpdateManager] 下载候选源 %d 失败: %s" % [_current_candidate_idx + 1, reason])
	_current_candidate_idx += 1
	if _current_candidate_idx < _download_candidates.size():
		_try_download_current_candidate()
	else:
		is_downloading = false
		download_failed.emit("下载失败: %s" % reason)

## 取消下载
func cancel_download() -> void:
	if not is_downloading:
		return
	_is_cancelled = true
	is_downloading = false
	if _download_http:
		_download_http.cancel_request()

## 调起安装 APK
func install_apk(file_path: String) -> bool:
	if OS.get_name() == "Android":
		# 尝试通过 Android 原生桥梁调起安装
		if Engine.has_singleton("ApkInstaller"):
			var plugin = Engine.get_singleton("ApkInstaller")
			if plugin.has_method("installApk"):
				return bool(plugin.call("installApk", file_path))

		# 尝试 Engine JavaClassWrapper 单例调起
		if Engine.has_singleton("JavaClassWrapper"):
			var wrapper = Engine.get_singleton("JavaClassWrapper")
			var godot_runtime = Engine.get_singleton("AndroidRuntime") if Engine.has_singleton("AndroidRuntime") else null
			var activity = godot_runtime.getActivity() if godot_runtime else null
			if wrapper and activity:
				var apk_installer = wrapper.wrap("com.favo.qxiuxian.ApkInstaller")
				if apk_installer:
					return bool(apk_installer.installApk(activity, file_path))

		# 备用方案：通过 ACTION_VIEW 打开 file URI
		var uri := "file://" + file_path
		return OS.shell_open(uri) == OK

	# 桌面环境打开存放目录
	var dir := file_path.get_base_dir()
	OS.shell_open(dir)
	return true
