class_name MenuNightmareFog
extends ColorRect

## 首页噩梦氛围雾：夜里在整屏缓慢缭绕的紫灰云团 + 血朱雾脊，压在卡片矩阵之上。
##
## 与局内 NightmareFogOverlay 不是一套东西（那边是遮视野的判定雾，见其头注释）；
## 首页层与 MenuMeteorShower / MenuNightmareChrome 同属「噩梦四件套」的装饰件：
##   底色（深紫黑舞台）+ 血雨流星 + 四周画框 + 本层迷雾。
## 之所以压在最上层而不是垫在卡片下面（另三层都在矩阵之下）：矩阵铺满整屏、卡片又是实底，
## 垫下面就只剩 43px 边缝和 14~16px 卡缝里能看见雾，读起来像给屏幕镶了一圈，不是"雾"。
## 压在上面时浓度按「云团 + 贴边」两档控住（整屏 ≤0.35，见 shader 的 alpha_scale），
## 卡面字色只被薄薄压一层，仍读得清；顶栏徽章与角落按钮也在雾下，同样只轻微压暗。
##
## 动画走 shader 内置 TIME，本脚本不跑 _process；night=0 时 visible=false 直接不绘制。
## 颜色一律从 GameStyle 现取（唯一取色入口），shader 里的默认值只是兜底。

const FOG_SHADER := preload("res://assets/shaders/menu_night_fog.gdshader")
## 进出场时长（s）：比画框（0.55）略慢，雾要"漫上来"，不是开关灯
const ANIM_TIME := 0.7
## 整层浓度封顶：出图调参台比对过 0.40 / 0.55 / 0.70 三档，
## 0.70 云团压过卡面字、0.40 只剩一层灰纱，0.50 是「看得见流动 + 字仍清楚」的折中
const ALPHA_SCALE := 0.58

var _mat: ShaderMaterial = null
var _night := 0.0
var _tween: Tween

## 装到宿主（StartMenu）最上层：矩阵与徽章都压在它下面，雾才是"在屏幕前飘"
static func install(host: Control) -> MenuNightmareFog:
	var fog := MenuNightmareFog.new()
	fog.name = "MenuNightmareFog"
	fog.set_anchors_preset(Control.PRESET_FULL_RECT)
	fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fog.process_mode = Node.PROCESS_MODE_ALWAYS
	# 装饰层非布局内容，判据放行（同 ResultFx / MenuMeteorShower / MenuNightmareChrome 惯例）
	fog.set_meta("layout_bleed", true)
	host.add_child(fog)
	return fog

func _ready() -> void:
	# ColorRect 的底色会乘进 shader 输出，显式刷白让 shader 的 COLOR 原样落地
	color = Color.WHITE
	_mat = ShaderMaterial.new()
	_mat.shader = FOG_SHADER
	# 雾体 = 夜色舞台提亮一档，雾脊 = 血朱微暗，瘴气 = 夜色压暗：全从 GameStyle 派生
	_mat.set_shader_parameter("fog_col", GameStyle.NIGHT_STAGE.lightened(0.16))
	_mat.set_shader_parameter("fog_tint", GameStyle.NIGHT_SEAL.darkened(0.15))
	_mat.set_shader_parameter("miasma_col", GameStyle.NIGHT_STAGE.darkened(0.55))
	_mat.set_shader_parameter("alpha_scale", ALPHA_SCALE)
	_mat.set_shader_parameter("night", 0.0)
	material = _mat
	visible = false
	_apply_aspect()
	resized.connect(_apply_aspect)

## 宽高比只在换分辨率/横竖屏时回写；噪声按屏高取坐标，云团物理尺寸不随屏幕变形
func _apply_aspect() -> void:
	if _mat == null:
		return
	var sz := size
	if sz.x <= 0.0 or sz.y <= 0.0:
		if get_viewport() != null:
			sz = get_viewport().get_visible_rect().size
		else:
			sz = Vector2(960, 540)
	if sz.x > 0.0 and sz.y > 0.0:
		_mat.set_shader_parameter("aspect_ratio", sz.x / sz.y)

## 切氛围：animate=false 用于开菜单时静默同步（不闪不补间）
func set_nightmare(active: bool, animate: bool = true) -> void:
	var target := 1.0 if active else 0.0
	if _tween != null and _tween.is_valid():
		_tween.kill()
		_tween = null
	if not animate or absf(_night - target) < 0.001:
		_set_night(target)
		return
	visible = true
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_method(_set_night, _night, target, ANIM_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _set_night(v: float) -> void:
	_night = v
	if _mat != null:
		_mat.set_shader_parameter("night", v)
	# 淡到看不见就整层下线：不绘制 == 不跑噪声，普通难度首页零成本
	visible = v > 0.002
