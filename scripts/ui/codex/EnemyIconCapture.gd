class_name EnemyIconCapture
extends RefCounted

## 敌人图鉴图标捕获：把 ProceduralEnemyView（纯矢量 _draw）挂进离屏 SubViewport
## 渲几帧取 ImageTexture，按 eid 静态缓存。
##
## 为什么现渲而不是出素材位图（2026-10-13）：敌人形象已是程序化矢量（无位图可抄），
## 现渲保证图鉴与战场形象永远同源；16 张 96×96 RGBA ≈ 0.6MB，远低于 v0.0.28 #02
## 那组 960 图集 70MB 的教训线，且只在敌人页第一次被看到时懒捕。
##
## 取回失败/全空图一律缓存 null，调用方（ManualDialog）回落占位，不反复重试。
## 空图检测只查「有没有画过东西」（get_used_rect 非空），不查像素内容——headless 下
## 渲染后端可能给出无效纹理，判据据此只断言「不崩、占位在、重试不放大」。

const CAP_SIZE := 96
const DETAIL_SIZE := 128
## catalog id → EnemyVisualConfig 视觉 id：赤雷/剑煞的渲染分支认 `_elite` 后缀
## （EnemyBase 运行时 id 同形，见 EnemyData.ID_PREFIXES）；直接用 catalog id 会落进
## get_config 的 `_` 兜底臂被画成 golem（画多大==判多大级别的形象撒谎）。
const VISUAL_ID := {
	"chilei": "chilei_elite",
	"jiansha": "jiansha_elite",
	"xuanming": "xuanming_elite",
	"xingpan": "xingpan_elite",
	"wandu": "wandu_elite",
}
static var _cache: Dictionary = {}   ## eid(+#+elite) -> Texture2D | null（null 也缓存）
static var _pending: Dictionary = {} ## 捕获中的 key：并发 await 同一张，不叠 SubViewport

static func _key(eid: String, is_elite: bool, size: int = CAP_SIZE) -> String:
	var k := eid if not is_elite else eid + "#e"
	if size != CAP_SIZE:
		k += "#s%d" % size
	return k

## 异步捕一张：调用方 await。已缓存直接返回（含失败缓存）。
## 并发去重：同 key 捕获中（_pending）时轮询等兄弟任务落缓存（捕一张约 3 帧，
## 120 帧封顶防挂死），不叠 SubViewport。
static func capture(eid: String, is_elite: bool = false, size: int = CAP_SIZE) -> Texture2D:
	var key := _key(eid, is_elite, size)
	if _cache.has(key):
		return _cache[key]
	if _pending.has(key):
		var tree := Engine.get_main_loop() as SceneTree
		for i in range(120):
			await tree.process_frame
			if _cache.has(key):
				break
		return _cache.get(key)
	_pending[key] = true
	var result := await _capture_uncached(eid, is_elite, size)
	_pending.erase(key)
	_cache[key] = result
	return result

## 页重建前的同步查询：捕过才给图，没捕过给 null（调用方先铺占位再逐张异步补）
static func peek(eid: String, is_elite: bool = false, size: int = CAP_SIZE) -> Texture2D:
	return _cache.get(_key(eid, is_elite, size))

static func _capture_uncached(eid: String, is_elite: bool, size: int = CAP_SIZE) -> Texture2D:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	# headless 用 dummy 渲染后端，SubViewport 纹理读不回像素（每次 get_image 刷一条
	# "Parameter t is null" ERROR）：直接判定捕获不可用，缓存 null，真机才有图。
	if DisplayServer.get_name() == "headless":
		return null
	var host := Node2D.new()
	var vp := SubViewport.new()
	vp.size = Vector2i(size, size)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	host.add_child(vp)
	var view := ProceduralEnemyView.new()
	var is_boss := eid == "boss"
	# 先换成视觉 id 再 setup：get_config 认 "chilei_elite"/"jiansha_elite"，
	# 传裸 catalog id 会落 `_` 兜底被画成 golem
	view.setup(String(VISUAL_ID.get(eid, eid)), is_elite, is_boss, false)
	view.position = Vector2(size, size) * 0.5
	# 魔君/精英体型是杂兵的数倍，画框装不下原尺寸 → 缩进画框；按 size/CAP_SIZE 等比放缩保证画框占比稳定且矢量锐利
	var scale_mul := float(size) / float(CAP_SIZE)
	if is_boss:
		view.scale = Vector2(0.55 * scale_mul, 0.55 * scale_mul)
	elif is_elite:
		view.scale = Vector2(0.8 * scale_mul, 0.8 * scale_mul)
	elif scale_mul != 1.0:
		view.scale = Vector2(scale_mul, scale_mul)
	vp.add_child(view)
	tree.root.add_child(host)
	# 渲染在帧尾：等三帧让 UPDATE_ONCE 的绘制落进纹理
	for i in range(3):
		await tree.process_frame
	var img := vp.get_texture().get_image()
	var out: Texture2D = null
	if img != null and not img.is_empty() and img.get_used_rect().has_area():
		out = ImageTexture.create_from_image(img)
	host.queue_free()
	return out
