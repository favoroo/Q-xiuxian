extends Node

## 游戏版本定义与语义化版本比较工具
## 对应 dudu-cocos 的 core/version.ts

const APP_VERSION: String = "0.0.9"
const APP_VERSION_NAME: String = "v" + APP_VERSION

const GITHUB_OWNER: String = "favoroo"
const GITHUB_REPO: String = "Q-xiuxian"
const GITEE_OWNER: String = "favo9"
const GITEE_REPO: String = "q-xiuxian"

const GH_PROXIES: Array[String] = [
	"https://ghfast.top/",
	"https://gh-proxy.com/",
	"https://ghproxy.net/",
]

## 解析语义化版本字符串为数字数组，如 "v0.1.2-beta" -> [0, 1, 2]
static func parse_version(version_str: String) -> Array[int]:
	if version_str.is_empty():
		return [0, 0, 0]
	var clean := version_str.strip_edges()
	if clean.begins_with("v") or clean.begins_with("V"):
		clean = clean.substr(1)
	clean = clean.split("-")[0].split("+")[0]
	var parts := clean.split(".")
	var nums: Array[int] = []
	for p in parts:
		if p.is_valid_int():
			nums.append(p.to_int())
		else:
			nums.append(0)
	while nums.size() < 3:
		nums.append(0)
	return nums

## 比较候选版本 candidate 是否高于基准版本 current
static func is_version_newer(candidate: String, current: String = APP_VERSION) -> bool:
	var v1 := parse_version(candidate)
	var v2 := parse_version(current)
	var max_len := maxi(v1.size(), v2.size())
	for i in range(max_len):
		var n1: int = v1[i] if i < v1.size() else 0
		var n2: int = v2[i] if i < v2.size() else 0
		if n1 > n2:
			return true
		if n1 < n2:
			return false
	return false

## 获取发布页面直链（浏览器逃生通道）
static func get_release_page_url(tag_name: String = "") -> String:
	var base := "https://gitee.com/%s/%s/releases" % [GITEE_OWNER, GITEE_REPO]
	if not tag_name.is_empty():
		return "%s/tag/%s" % [base, tag_name]
	return "%s/latest" % base

## 格式化字节大小为可读文本
static func format_bytes(bytes: int) -> String:
	if bytes <= 0:
		return ""
	if bytes < 1024:
		return "%d B" % bytes
	elif bytes < 1024 * 1024:
		return "%.0f KB" % (float(bytes) / 1024.0)
	else:
		return "%.1f MB" % (float(bytes) / (1024.0 * 1024.0))
