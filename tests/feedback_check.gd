extends Node

## 意见反馈判据（2026-10-23）
##
## 覆盖不依赖真实网络的纯逻辑：字段校验、诊断拼装、multipart 结构、
## 日志尾部截断、截图压缩、文件名清洗。
## 运行: godot --headless --path . res://tests/FeedbackCheck.tscn
##
## 为什么不发真邮件：判据要能在 CI/本地反复跑，不能依赖外网与邮箱激活状态。
## 真机验收项（相册权限、软键盘避让、FormSubmit 收信）见 CHANGELOG 与交付说明。

var _c := TestCheck.new()

func _ready() -> void:
	_c.set_min_checks(50)
	_run()
	_finish()

func _finish() -> void:
	if _c.report("FEEDBACK_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)

func _run() -> void:
	_test_validate()
	_test_subject_and_fields()
	_test_multipart()
	_test_filename()
	_test_log_tail()
	_test_image_compress()
	_test_decode_headers()
	_test_diagnostics()
	_test_report_text()
	_test_cocreate_fields()
	_test_cocreate_draft_isolation()

func _test_validate() -> void:
	_c.check(FeedbackSender.validate_message("") != "", "空反馈被拦下")
	_c.check(FeedbackSender.validate_message("   \n\t ") != "", "纯空白反馈被拦下")
	_c.check(FeedbackSender.validate_message("打不开商店") == "", "正常反馈通过")
	var long_msg := ""
	for i in range(FeedbackSender.MAX_MESSAGE_CHARS + 1):
		long_msg += "字"
	_c.check(FeedbackSender.validate_message(long_msg) != "", "超长反馈被拦下（%d 字上限）" % FeedbackSender.MAX_MESSAGE_CHARS)

func _test_subject_and_fields() -> void:
	var subject := FeedbackSender.build_subject("第一行是问题摘要\n第二行补充")
	_c.check(subject.contains(Version.APP_VERSION_NAME) and subject.contains("第一行是问题摘要"),
		"邮件主题带版本与反馈首行（实得「%s」）" % subject)
	var long_line := ""
	for i in range(80):
		long_line += "长"
	_c.check(FeedbackSender.build_subject(long_line).length() < 80, "超长首行在主题里被截断")

	var fields := FeedbackSender.build_fields("测试反馈", "12345@qq.com")
	_c.check(fields.get("_subject", "") != "" and fields.get("message", "") == "测试反馈",
		"表单字段包含 _subject 与 message")
	_c.check(fields.get("_captcha", "") == "false", "关闭 FormSubmit 验证码（_captcha=false）")
	_c.check(fields.get("_replyto", "") == "12345@qq.com", "联系方式是邮箱时自动设 Reply-To")
	var fields2 := FeedbackSender.build_fields("测试反馈", "QQ:12345")
	_c.check(not fields2.has("_replyto"), "联系方式不是邮箱时不设 Reply-To")

func _test_multipart() -> void:
	var fields := {"message": "你好", "contact": "abc@qq.com"}
	var file_bytes := PackedByteArray([0x89, 0x50, 0x4E, 0x47, 0x00, 0xFF])
	var boundary := "----TestBoundary123"
	var body := FeedbackSender.build_multipart(fields, "attachment", "截图 1.png", "image/png", file_bytes, boundary)
	var text := body.get_string_from_utf8()
	_c.check(text.contains("--" + boundary + "\r\n"), "multipart 以 boundary 分段")
	_c.check(text.contains("name=\"message\"") and text.contains("你好"), "文本字段按 UTF-8 写入")
	_c.check(text.contains("filename=\"截图 1.png\"") and text.contains("Content-Type: image/png"),
		"文件段带文件名与 MIME")
	_c.check(_ends_with_bytes(body, ("--" + boundary + "--\r\n").to_utf8_buffer()),
		"multipart 以结束 boundary 收尾")
	# 二进制原样保留：PNG 头与 0xFF 不能被 UTF-8 转码破坏
	_c.check(_contains_bytes(body, file_bytes), "文件字节原样嵌入（不被字符串转码破坏）")
	var no_file := FeedbackSender.build_multipart(fields, "attachment", "", "", PackedByteArray(), boundary)
	_c.check(not no_file.get_string_from_utf8().contains("filename="), "无截图时不写文件段")

## PackedByteArray 只有单字节 find，这里手写子串查找
func _contains_bytes(haystack: PackedByteArray, needle: PackedByteArray) -> bool:
	if needle.is_empty() or haystack.size() < needle.size():
		return false
	for i in range(haystack.size() - needle.size() + 1):
		var hit := true
		for j in range(needle.size()):
			if haystack[i + j] != needle[j]:
				hit = false
				break
		if hit:
			return true
	return false

func _ends_with_bytes(haystack: PackedByteArray, needle: PackedByteArray) -> bool:
	if needle.is_empty() or haystack.size() < needle.size():
		return false
	var off := haystack.size() - needle.size()
	for j in range(needle.size()):
		if haystack[off + j] != needle[j]:
			return false
	return true

func _test_filename() -> void:
	_c.check(FeedbackSender.sanitize_filename("a\"b/c\\d\ne.jpg") == "abcde.jpg",
		"文件名清洗引号/斜杠/换行")
	_c.check(FeedbackSender.sanitize_filename("") == "feedback.jpg", "空文件名回退默认名")
	var name := FeedbackSender.build_attachment_filename()
	_c.check(name.begins_with("feedback_") and name.ends_with(".jpg"), "附件名是时间戳 jpg（%s）" % name)

func _test_log_tail() -> void:
	var path := "user://feedback_check_log.txt"
	var f := FileAccess.open(path, FileAccess.WRITE)
	_c.check(f != null, "测试日志文件可写")
	if f == null:
		return
	for i in range(300):
		f.store_line("line_%03d_abcdefghijklmnopqrstuvwxyz" % i)
	f.close()
	var tail := FeedbackSender.read_log_tail(path, 1024)
	_c.check(not tail.is_empty() and tail.length() <= 1024, "日志尾部按字节上限截断（实得 %d 字节）" % tail.length())
	_c.check(tail.contains("line_299_"), "日志尾部保留最新一行")
	# 从中间截断时丢掉首行残片：剩下第一行必须是完整的一行（长度与原行一致）
	var first_line := tail.split("\n")[0]
	var sample_len := "line_000_abcdefghijklmnopqrstuvwxyz".length()
	_c.check(first_line.length() == sample_len,
		"从中间截断时丢掉首行残片（首行完整，长 %d / 原行 %d）" % [first_line.length(), sample_len])
	_c.check(FeedbackSender.read_log_tail("user://not_exists_xyz.log", 1024) == "", "日志不存在返回空串")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _test_image_compress() -> void:
	var img := Image.create(2400, 1200, false, Image.FORMAT_RGB8)
	img.fill(Color(0.9, 0.2, 0.1))
	var src := "user://feedback_check_img.png"
	var err := img.save_png(src)
	_c.check(err == OK, "测试图片落盘")
	var result := FeedbackSender.compress_image_for_upload(src)
	_c.check(bool(result.get("ok", false)), "截图压缩成功（%s）" % String(result.get("error", "")))
	if bool(result.get("ok", false)):
		_c.check(int(result.get("width", 0)) <= FeedbackSender.MAX_IMAGE_DIM,
			"长边压到 %d 以内（实得 %d）" % [FeedbackSender.MAX_IMAGE_DIM, int(result.get("width", 0))])
		var bytes: PackedByteArray = result.get("bytes", PackedByteArray())
		_c.check(bytes.size() > 0 and bytes.size() < FeedbackSender.MAX_ATTACHMENT_BYTES,
			"压缩后字节数在上限内（%s）" % Version.format_bytes(bytes.size()))
		_c.check(String(result.get("mime", "")) == "image/jpeg", "统一转 JPEG")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(src))
	var bad := FeedbackSender.compress_image_for_upload("user://not_exists_img.png")
	_c.check(not bool(bad.get("ok", true)), "不存在的图片给出失败原因")

func _test_decode_headers() -> void:
	var img := Image.create(32, 32, false, Image.FORMAT_RGB8)
	img.fill(Color(0.2, 0.6, 0.3))
	var png := img.save_png_to_buffer()
	var jpg := img.save_jpg_to_buffer(0.9)
	_c.check(FeedbackSender.decode_image_bytes(png) != null, "PNG 字节按文件头解码成功")
	_c.check(FeedbackSender.decode_image_bytes(jpg) != null, "JPEG 字节按文件头解码成功")
	_c.check(FeedbackSender.decode_image_bytes(PackedByteArray([1, 2, 3])) == null, "未知/过短字节返回 null")
	_c.check(FeedbackSender.decode_image_bytes(PackedByteArray()) == null, "空字节返回 null")

func _test_diagnostics() -> void:
	var info := FeedbackSender.build_diagnostics()
	_c.check(info.contains("游戏版本") and info.contains(Version.APP_VERSION_NAME), "诊断信息带游戏版本")
	_c.check(info.contains("运行平台") and info.contains(OS.get_name()), "诊断信息带运行平台")
	_c.check(info.contains("设备型号") and info.contains("画面设置"), "诊断信息带设备型号与画面设置")
	_c.check(info.contains("提交时间"), "诊断信息带提交时间")

func _test_report_text() -> void:
	var text := FeedbackSender.build_report_text("商店打不开", "QQ:12345")
	_c.check(text.contains("【反馈内容】") and text.contains("商店打不开"), "复制文本含反馈内容")
	_c.check(text.contains("【联系方式】") and text.contains("QQ:12345"), "复制文本含联系方式")
	_c.check(text.contains("【剑士反馈诊断信息】"), "复制文本含诊断信息")

## 共创复用同一发送链路，靠 tag/category 区分来件
func _test_cocreate_fields() -> void:
	var subject := FeedbackSender.build_subject("想要一把会喷火的扇子",
		FeedbackSender.TAG_COCREATE, "武器")
	_c.check(subject.contains("【剑士共创·武器】"), "共创主题带分类（实得「%s」）" % subject)
	_c.check(subject.contains(Version.APP_VERSION_NAME) and subject.contains("想要一把会喷火的扇子"),
		"共创主题带版本与想法首行")
	var no_cat := FeedbackSender.build_subject("随便一个想法", FeedbackSender.TAG_COCREATE)
	_c.check(no_cat.contains("【剑士共创】") and not no_cat.contains("·"), "不选分类时主题不带分类段")

	var fields := FeedbackSender.build_fields("想要新角色", "", FeedbackSender.TAG_COCREATE, "角色", false)
	_c.check(fields.get("category", "") == "角色", "共创表单带 category 字段")
	_c.check(String(fields.get("diagnostics", "")).contains("【剑士共创诊断信息】"),
		"共创诊断抬头用共创口径")
	_c.check(not String(fields.get("_subject", "")).contains("剑士反馈"), "共创件不会混进反馈主题")
	_c.check(FeedbackSender.build_fields("纯反馈", "").get("category", null) == null,
		"反馈件不带 category 字段（默认空）")
	_c.check(FeedbackSender.validate_message("", "想法") == "请先填写想法", "共创校验文案用「想法」")
	_c.check(FeedbackSender.validate_message("有内容", "想法") == "", "共创正文通过校验")

## 两个窗口的草稿互不覆盖
func _test_cocreate_draft_isolation() -> void:
	FeedbackSender.clear_draft()
	FeedbackSender.clear_draft(FeedbackSender.COCREATE_DRAFT_PATH)
	FeedbackSender.save_draft("反馈草稿", "fb@qq.com")
	FeedbackSender.save_draft("共创草稿", "cc@qq.com", FeedbackSender.COCREATE_DRAFT_PATH)
	_c.check(String(FeedbackSender.load_draft().get("message", "")) == "反馈草稿", "反馈草稿不受共创影响")
	_c.check(String(FeedbackSender.load_draft(FeedbackSender.COCREATE_DRAFT_PATH).get("message", "")) == "共创草稿",
		"共创草稿独立读取")
	FeedbackSender.clear_draft(FeedbackSender.COCREATE_DRAFT_PATH)
	_c.check(FeedbackSender.load_draft(FeedbackSender.COCREATE_DRAFT_PATH).is_empty(), "共创草稿可独立清除")
	_c.check(not FeedbackSender.load_draft().is_empty(), "清共创草稿不会误删反馈草稿")
	FeedbackSender.clear_draft()
