class_name FeedbackSender
extends RefCounted

## 意见反馈发送器（2026-10-23）
##
## 职责：把「玩家写的反馈 + 设备诊断 + 最近日志 + 可选截图」打包成
## multipart/form-data，POST 到 FormSubmit 免费表单服务，最终以邮件形式送到作者邮箱。
##
## 为什么走 FormSubmit：
## - 游戏是纯客户端 APK，没有自建服务器；SMTP 密码写进客户端等于公开泄露。
## - FormSubmit 只需一个收件邮箱即可收信，免费额度 250 封/月，支持 10MB 以内的附件。
## - 主端点用 /ajax/ 拿 JSON 结果；失败再退普通表单端点（会 302 到感谢页，HTTPRequest 自动跟随）。
##
## 安全口径：客户端只暴露「收件邮箱」这一个公开信息，不保存任何密钥。
## 诊断信息只用于排查问题，不采集通讯录、位置、账号等隐私数据。

const FEEDBACK_EMAIL := "favoro@qq.com"
const AJAX_ENDPOINT := "https://formsubmit.co/ajax/" + FEEDBACK_EMAIL
const FORM_ENDPOINT := "https://formsubmit.co/" + FEEDBACK_EMAIL
## FormSubmit 会校验来源页：没有 Referer 时直接回
## 「Make sure you open this page through a web server」（实测 2026-10-23）。
## 游戏不是浏览器，必须显式带上项目主页作为来源。
const REFERER := "https://favoroo.github.io/Q-xiuxian/"
const ORIGIN := "https://favoroo.github.io"

## 反馈正文上限（与 FeedbackDialog 的字数计数同源）
const MAX_MESSAGE_CHARS := 1000
## FormSubmit 所有附件合计上限 10MB；这里留 1MB 余量给 multipart 头与字段
const MAX_ATTACHMENT_BYTES := 9 * 1024 * 1024
## 手机截图长边压到 1600 再转 JPEG，通常 200~500KB，真机流量与邮箱附件都轻松
const MAX_IMAGE_DIM := 1600
const JPEG_QUALITY := 0.85
## 单个日志文件只带尾部 16KB：排查够用，也不会让邮件正文被服务端截断
const LOG_TAIL_BYTES := 16384
const GODOT_LOG_PATH := "user://logs/godot.log"
const FLICKER_LOG_PATH := "user://flicker_log.csv"
const USER_AGENT := "QXiuxian-GodotClient"

static var _boundary_seq: int = 0

# ---------------- 文本与诊断 ----------------

## 拼装设备/运行/进度诊断信息。只读全局状态，不依赖节点，便于单测直接调用。
static func build_diagnostics() -> String:
	var lines: Array[String] = []
	lines.append("【剑士反馈诊断信息】")
	lines.append("游戏版本: %s (%s)" % [Version.APP_VERSION_NAME, Version.APP_VERSION])
	lines.append("运行平台: %s %s" % [OS.get_name(), OS.get_version()])
	lines.append("设备型号: %s" % _safe_str(OS.get_model_name(), "未知"))
	lines.append("处理器: %s" % _safe_str(OS.get_processor_name(), "未知"))
	lines.append("架构: %s" % Engine.get_architecture_name())
	lines.append("引擎版本: %s" % String(Engine.get_version_info().get("string", "Godot 4.7")))

	var screen_size := DisplayServer.screen_get_size()
	var dpi := DisplayServer.screen_get_dpi()
	var win_size := Vector2i.ZERO
	var main_loop := Engine.get_main_loop()
	if main_loop is SceneTree:
		win_size = (main_loop as SceneTree).root.size
	lines.append("屏幕: %dx%d @ %.0f DPI / 窗口: %dx%d" % [
		screen_size.x, screen_size.y, dpi, win_size.x, win_size.y])
	lines.append("语言: %s" % OS.get_locale())

	var theme_name := GameStyle.theme_name(SettingsManager.theme_color())
	lines.append("界面主题: %s / 画质档: %s" % [theme_name, SettingsManager.render_quality_label()])
	lines.append("画面设置: 伤害跳字=%s / 震屏=%s / 顿帧=%s / 受击红晕=%s / 辉光=%s / FPS显示=%s" % [
		_on_off(SettingsManager.get_val(&"display", &"damage_numbers", true)),
		SettingsManager.shake_level_label(),
		_on_off(SettingsManager.get_val(&"display", &"hit_stop", true)),
		_on_off(SettingsManager.get_val(&"display", &"screen_flash", true)),
		_on_off(SettingsManager.get_val(&"display", &"glow", true)),
		_on_off(SettingsManager.get_val(&"display", &"show_fps", false)),
	])

	if GameManager.run_started:
		var cname := "未知"
		var cdef := CultivatorData.get_def(GameManager.cultivator_id)
		if not cdef.is_empty():
			cname = String(cdef.get("name", GameManager.cultivator_id))
		var secs := int(GameManager.game_time)
		lines.append("局内进度: 第 %d 波 / Lv.%d / 击杀 %d / 时长 %02d:%02d / 角色 %s / 难度 %s / 无尽 %s" % [
			GameManager.wave_number, GameManager.level, GameManager.kills,
			int(secs / 60.0), secs % 60, cname,
			AchievementData.danger_name(GameManager.danger_level),
			"是" if GameManager.endless_mode else "否",
		])
	else:
		lines.append("局内进度: 未在局内（主菜单或结算界面）")

	var stats: Dictionary = GameManager.career_stats
	lines.append("生涯统计: 局数 %d / 通关 %d / 最高波次 %d / 总击杀 %d" % [
		int(stats.get("total_runs", 0)),
		int(stats.get("total_wins", 0)),
		int(stats.get("best_wave", 0)),
		int(stats.get("total_kills", 0)),
	])
	lines.append("提交时间: %s" % Time.get_datetime_string_from_system(false, true))
	return "\n".join(lines)

## 反馈正文（复制到剪贴板用）：反馈内容 + 联系方式 + 诊断 + 最近日志
static func build_report_text(message: String, contact: String) -> String:
	var out := "【反馈内容】\n" + message.strip_edges()
	if not contact.strip_edges().is_empty():
		out += "\n\n【联系方式】\n" + contact.strip_edges()
	out += "\n\n" + build_diagnostics()
	var logs := collect_recent_logs()
	if not logs.is_empty():
		out += "\n\n" + logs
	return out

## 反馈内容校验：返回空串表示通过，否则返回给玩家看的原因
static func validate_message(message: String) -> String:
	var trimmed := message.strip_edges()
	if trimmed.is_empty():
		return "请先填写反馈内容"
	if trimmed.length() > MAX_MESSAGE_CHARS:
		return "反馈内容不能超过 %d 字" % MAX_MESSAGE_CHARS
	return ""

## 邮件主题：版本 / 平台 / 反馈首行（过长截断）
static func build_subject(message: String) -> String:
	var first := ""
	for line in message.strip_edges().split("\n"):
		var t := line.strip_edges()
		if not t.is_empty():
			first = t
			break
	if first.is_empty():
		first = "无标题"
	if first.length() > 40:
		first = first.substr(0, 40) + "…"
	return "【剑士反馈】%s / %s / %s" % [Version.APP_VERSION_NAME, OS.get_name(), first]

## FormSubmit 表单字段（含隐藏控制字段）
static func build_fields(message: String, contact: String) -> Dictionary:
	var diagnostics := build_diagnostics()
	var logs := collect_recent_logs()
	if not logs.is_empty():
		diagnostics += "\n\n" + logs
	var fields := {
		"_subject": build_subject(message),
		"_template": "table",
		"_captcha": "false",
		"message": message.strip_edges(),
		"diagnostics": diagnostics,
		"contact": contact.strip_edges(),
		"client_time": Time.get_datetime_string_from_system(false, true),
	}
	# 联系方式是邮箱时顺手设为 Reply-To，作者点回复就能直接回到玩家邮箱
	if contact.contains("@"):
		fields["_replyto"] = contact.strip_edges()
	return fields

# ---------------- 日志尾部 ----------------

## 读文件尾部最多 max_bytes 字节。从中间截断时丢掉第一行残片，避免日志首行缺头。
static func read_log_tail(path: String, max_bytes: int = LOG_TAIL_BYTES) -> String:
	if path.is_empty() or max_bytes <= 0:
		return ""
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var total := f.get_length()
	var start := maxi(0, total - max_bytes)
	f.seek(start)
	var text := f.get_buffer(total - start).get_string_from_utf8()
	f.close()
	if start > 0:
		var nl := text.find("\n")
		if nl >= 0:
			text = text.substr(nl + 1)
	return text

## 收集最近日志：Godot 运行日志 + 闪屏探针日志（存在才带）
static func collect_recent_logs() -> String:
	var parts: Array[String] = []
	var godot_tail := read_log_tail(GODOT_LOG_PATH, LOG_TAIL_BYTES).strip_edges()
	if not godot_tail.is_empty():
		parts.append("【最近运行日志】\n" + godot_tail)
	var flicker_tail := read_log_tail(FLICKER_LOG_PATH, LOG_TAIL_BYTES).strip_edges()
	if not flicker_tail.is_empty():
		parts.append("【闪屏探针日志（最近）】\n" + flicker_tail)
	return "\n\n".join(parts)

# ---------------- 截图压缩 ----------------

## 从相册路径读图，长边压到 max_dim，转 JPEG 字节。
## 返回 { ok, bytes, width, height, mime } 或 { ok:false, error }。
static func compress_image_for_upload(path: String, max_dim: int = MAX_IMAGE_DIM,
		quality: float = JPEG_QUALITY) -> Dictionary:
	if path.is_empty():
		return {"ok": false, "error": "没有选择图片"}
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "图片不存在或无法访问"}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "error": "无法读取图片文件"}
	var src_size := f.get_length()
	f.close()
	if src_size <= 0:
		return {"ok": false, "error": "图片文件为空"}
	# 先按文件大小挡一道：40MB 的图解码就可能把手机内存顶爆
	if src_size > 40 * 1024 * 1024:
		return {"ok": false, "error": "图片过大（超过 40MB），请换一张"}

	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return {"ok": false, "error": "无法解码这张图片，请换一张"}
	var w := img.get_width()
	var h := img.get_height()
	if w <= 0 or h <= 0:
		return {"ok": false, "error": "图片尺寸无效"}
	var longest := maxi(w, h)
	if longest > max_dim:
		var scale := float(max_dim) / float(longest)
		var nw := maxi(1, int(round(float(w) * scale)))
		var nh := maxi(1, int(round(float(h) * scale)))
		img.resize(nw, nh, Image.INTERPOLATE_BILINEAR)
	var bytes := img.save_jpg_to_buffer(clampf(quality, 0.1, 1.0))
	if bytes.is_empty():
		return {"ok": false, "error": "图片压缩失败，请换一张"}
	if bytes.size() > MAX_ATTACHMENT_BYTES:
		return {"ok": false, "error": "压缩后截图仍然过大，请换一张"}
	return {
		"ok": true,
		"bytes": bytes,
		"width": img.get_width(),
		"height": img.get_height(),
		"mime": "image/jpeg",
	}

## 附件文件名统一用时间戳，避免相册原名里的空格/中文/引号污染 multipart 头
static func build_attachment_filename() -> String:
	var t := Time.get_datetime_dict_from_system()
	return "feedback_%04d%02d%02d_%02d%02d%02d.jpg" % [
		int(t.get("year", 0)), int(t.get("month", 0)), int(t.get("day", 0)),
		int(t.get("hour", 0)), int(t.get("minute", 0)), int(t.get("second", 0)),
	]

# ---------------- multipart / HTTP ----------------

static func make_boundary() -> String:
	_boundary_seq += 1
	return "----QXFeedbackBoundary%d%d" % [Time.get_ticks_usec(), _boundary_seq]

## 构造 multipart/form-data 请求体。字段值按 UTF-8 写；文件段按原始字节写。
static func build_multipart(fields: Dictionary, file_field: String, file_name: String,
		file_mime: String, file_bytes: PackedByteArray, boundary: String) -> PackedByteArray:
	var body := PackedByteArray()
	for key in fields.keys():
		var head := "--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n" % [
			boundary, String(key)]
		body.append_array(head.to_utf8_buffer())
		body.append_array(String(fields[key]).to_utf8_buffer())
		body.append_array("\r\n".to_utf8_buffer())
	if not file_bytes.is_empty():
		var safe_name := sanitize_filename(file_name)
		var file_head := "--%s\r\nContent-Disposition: form-data; name=\"%s\"; filename=\"%s\"\r\nContent-Type: %s\r\n\r\n" % [
			boundary, file_field, safe_name, file_mime]
		body.append_array(file_head.to_utf8_buffer())
		body.append_array(file_bytes)
		body.append_array("\r\n".to_utf8_buffer())
	body.append_array(("--%s--\r\n" % boundary).to_utf8_buffer())
	return body

## 文件名去引号/斜杠/换行，防止破坏 Content-Disposition 头
static func sanitize_filename(name: String) -> String:
	var out := ""
	for i in name.length():
		var ch := name[i]
		if ch == "\"" or ch == "\\" or ch == "/" or ch == "\r" or ch == "\n":
			continue
		out += ch
	out = out.strip_edges()
	return out if not out.is_empty() else "feedback.jpg"

## 发送反馈：先试 /ajax/（JSON 返回），失败再试普通表单端点。
## 返回值 { ok:true, activation_required?:bool } 或 { ok:false, error:String }。
static func send_feedback(http: HTTPRequest, fields: Dictionary, attachment: Dictionary) -> Dictionary:
	if http == null:
		return {"ok": false, "error": "网络组件未初始化"}
	var file_bytes: PackedByteArray = attachment.get("bytes", PackedByteArray())
	var file_name := String(attachment.get("name", ""))
	var file_mime := String(attachment.get("mime", "image/jpeg"))
	var last_error := "发送失败"
	for endpoint in [AJAX_ENDPOINT, FORM_ENDPOINT]:
		var boundary := make_boundary()
		var body := build_multipart(fields, "attachment", file_name, file_mime, file_bytes, boundary)
		var headers := PackedStringArray([
			"User-Agent: " + USER_AGENT,
			"Accept: application/json, text/html",
			"Content-Type: multipart/form-data; boundary=" + boundary,
			"Referer: " + REFERER,
			"Origin: " + ORIGIN,
		])
		var err := http.request_raw(endpoint, headers, HTTPClient.METHOD_POST, body)
		if err != OK:
			last_error = "无法发起网络请求（错误码 %d）" % err
			continue
		var res: Array = await http.request_completed
		var result := int(res[0])
		var code := int(res[1])
		var resp_body: PackedByteArray = res[3]
		if result != HTTPRequest.RESULT_SUCCESS:
			last_error = "网络连接失败（错误码 %d）" % result
			continue
		if code >= 200 and code < 300:
			var text := resp_body.get_string_from_utf8()
			var lower := text.to_lower()
			# 首次提交会先收到激活邮件：这不等于发送失败，要明确告诉玩家去邮箱点确认
			if lower.contains("activation") or lower.contains("activate"):
				return {"ok": true, "activation_required": true}
			var parsed = JSON.parse_string(text)
			if parsed is Dictionary:
				var pd := parsed as Dictionary
				var success_val := String(pd.get("success", "true")).to_lower()
				if success_val == "false":
					var msg := String(pd.get("message", "服务器拒绝了本次提交"))
					if msg.to_lower().contains("activation") or msg.to_lower().contains("activate"):
						return {"ok": true, "activation_required": true}
					last_error = msg
					continue
			return {"ok": true}
		last_error = "服务器返回 HTTP %d" % code
	return {"ok": false, "error": last_error}

# ---------------- 小工具 ----------------

static func _on_off(v: Variant) -> String:
	return "开" if bool(v) else "关"

static func _safe_str(v: Variant, fallback: String) -> String:
	var s := String(v).strip_edges()
	return s if not s.is_empty() else fallback
