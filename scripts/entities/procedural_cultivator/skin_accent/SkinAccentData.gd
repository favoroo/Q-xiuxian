extends RefCounted

## 角色皮肤「辨识挂件」数据表（唯一真话源）
##
## 2026-11-04 新增。背景：6 套皮肤此前只换配色 + 叠族特效，造型键（面壳/斗篷/头饰/武器）不随
## 皮肤变化，147 个组合里 126 个是「同骨架换色」。本表为每个角色补一件**身份挂件**，
## 由 SkinAccentLibrary 按皮肤系列取 6 种形制/材质（count/len/width/curl 参数不同），
## 让「哪个角色」与「哪套皮肤」在 1 倍尺寸下都能第一眼认出。
##
## 字段：
##   motif   挂件原型（SkinAccentDraw 里的分支名）
##   anchor  挂点（局部坐标，x 向右；对称件写 x=0 由绘制函数自行左右铺开）
##   len     主结构长度（px，1 倍尺寸）
##   count   主结构基数（皮肤形制会 ±1~2）
##   width   笔画宽度
##   rate    摆动速度倍率（叠加在统一相位上）
##   amp     摆动幅度倍率（克制：1.0 ≈ 2px 摆幅）
##   flutter 是否有偶发抖动（0 无 / 1 有；发丝、布条、符纸才给）
##   note    设计意图（不参与绘制，供后续维护）
##
## 挂点纪律（2026-11-04 实抓后修正）：角色头部很宽（±12px）且盖到 y≈+2，
## 挂点若落在 y<3 会被头部完全吃掉。除头顶饰外，一律挂 y≥2.2 的肩/胸/腰层。
##
## 配色不写死：形制材质色一律从渲染器现有皮肤色（col_cloak_edge / col_eye_core / col_gold /
## col_bone）与 GameStyle 材质常量派生，见 SkinAccentLibrary.palette()。

const MOTIFS: Dictionary = {
	"jianchi": {
		"motif": "sword_tassel", "anchor": Vector2(14.2, 5.4), "len": 13.0, "count": 3,
		"width": 1.9, "rate": 1.05, "amp": 1.0, "flutter": 1.0,
		"note": "剑穗：挂在剑柄侧的短穗，剑士身份锚点；六套形制从竹叶到赤缨到冰棱",
	},
	"shiyue": {
		"motif": "shoulder_slabs", "anchor": Vector2(0.0, 3.0), "len": 7.0, "count": 2,
		"width": 2.9, "rate": 0.55, "amp": 0.55, "flutter": 0.0,
		"note": "双肩岩甲：体修石岳的厚重肩片 + 岩缝金线；奔跑时只做 0.6px 踏震",
	},
	"fuzhen": {
		"motif": "butterflies", "anchor": Vector2(0.0, 4.0), "len": 5.0, "count": 2,
		"width": 1.1, "rate": 1.35, "amp": 0.8, "flutter": 1.0,
		"note": "灵蝶：绕身慢飞的两三只小蝶（翅膀张合），灵蝶使唯一身份件",
	},
	"jinsuanpan": {
		"motif": "abacus", "anchor": Vector2(10.6, 7.6), "len": 9.0, "count": 5,
		"width": 1.6, "rate": 0.85, "amp": 1.0, "flutter": 0.0,
		"note": "腰间算珠：掌柜算盘的一列珠子，走路时逐颗错相轻摆",
	},
	"meiying": {
		"motif": "fox_tail", "anchor": Vector2(10.6, 8.4), "len": 12.5, "count": 1,
		"width": 4.4, "rate": 1.1, "amp": 1.35, "flutter": 1.0,
		"note": "狐尾：影者的 S 形长尾，末端随主题换毛色/结晶",
	},
	"dubi": {
		"motif": "arm_wrap", "anchor": Vector2(-11.0, 3.4), "len": 9.0, "count": 3,
		"width": 1.5, "rate": 1.0, "amp": 1.1, "flutter": 1.0,
		"note": "断臂缠布：残臂上的三道布条，独臂刀圣的残缺感",
	},
	"kuangzhan": {
		"motif": "tooth_necklace", "anchor": Vector2(0.0, 2.8), "len": 4.4, "count": 3,
		"width": 1.3, "rate": 0.95, "amp": 1.0, "flutter": 0.0,
		"note": "兽牙项链：蛮兵颈前三颗牙 + 皮绳，跑动时整串上下颠",
	},
	"duoshe": {
		"motif": "soul_flame", "anchor": Vector2(-12.4, 3.2), "len": 8.0, "count": 2,
		"width": 2.6, "rate": 1.25, "amp": 0.6, "flutter": 1.0,
		"note": "幽魂火：夺舍散人左肩悬浮的魂火，主题改火焰色/冰焰/墨烟",
	},
	"duobao": {
		"motif": "treasure_pouch", "anchor": Vector2(9.6, 7.8), "len": 7.0, "count": 3,
		"width": 1.4, "rate": 0.95, "amp": 1.15, "flutter": 0.0,
		"note": "百宝囊：多宝道人腰侧锦囊 + 三枚挂件，走路叮当摆",
	},
	"lingzhifu": {
		"motif": "wheat", "anchor": Vector2(9.2, 8.4), "len": 10.0, "count": 3,
		"width": 1.2, "rate": 0.9, "amp": 1.1, "flutter": 1.0,
		"note": "灵植穗：灵植夫腰后三根麦穗，穗尖随主题变竹叶/冰芒/金穗",
	},
	"leifa": {
		"motif": "thunder_arcs", "anchor": Vector2(0.0, 2.2), "len": 13.0, "count": 2,
		"width": 1.15, "rate": 1.6, "amp": 0.5, "flutter": 1.0,
		"note": "肩后雷弧：雷法真君双肩两道断续电弧，频率高但幅度极小",
	},
	"jiguan": {
		"motif": "gear", "anchor": Vector2(-10.6, 4.8), "len": 3.8, "count": 8,
		"width": 1.1, "rate": 0.6, "amp": 0.3, "flutter": 0.0,
		"note": "胸侧齿轮：机关师的 8 齿铜轮，恒速慢转（唯一旋转件）",
	},
	"yaowang": {
		"motif": "gourd", "anchor": Vector2(9.4, 7.8), "len": 8.0, "count": 1,
		"width": 3.0, "rate": 0.95, "amp": 1.2, "flutter": 0.0,
		"note": "药葫芦：药王腰侧悬壶 + 两片药叶，摆幅最大",
	},
	"shoucainu": {
		"motif": "coin_purse", "anchor": Vector2(9.4, 8.0), "len": 7.0, "count": 3,
		"width": 2.3, "rate": 0.9, "amp": 1.1, "flutter": 0.0,
		"note": "钱袋与钱串：守财奴腰侧鼓钱袋 + 三枚叠钱，走路沉甸甸地晃",
	},
	"shixue": {
		"motif": "blood_runes", "anchor": Vector2(0.0, 4.8), "len": 8.0, "count": 2,
		"width": 1.3, "rate": 1.35, "amp": 0.5, "flutter": 1.0,
		"note": "胸前血纹：嗜血魔修两道脉动血纹 + 一滴垂血，随主题变赤/冰/金",
	},
	"fuxiu": {
		"motif": "talisman_strip", "anchor": Vector2(9.6, 4.2), "len": 9.0, "count": 3,
		"width": 1.8, "rate": 1.15, "amp": 1.2, "flutter": 1.0,
		"note": "腰悬符纸：灵符子三道垂符，符面一横一竖，风大时翻卷",
	},
	"bawang": {
		"motif": "fur_collar", "anchor": Vector2(0.0, 2.8), "len": 6.0, "count": 5,
		"width": 2.8, "rate": 0.6, "amp": 0.45, "flutter": 0.0,
		"note": "兽毛肩领：霸王四簇立毛，只做呼吸起伏、不做左右甩",
	},
	"juechen": {
		"motif": "sash_ribbons", "anchor": Vector2(-9.4, 7.8), "len": 14.0, "count": 2,
		"width": 2.4, "rate": 1.25, "amp": 1.6, "flutter": 1.0,
		"note": "双飘带：绝尘的两条长飘带，全角色摆幅最大，奔跑时拖成 45°",
	},
	"yushou": {
		"motif": "beast_bell", "anchor": Vector2(9.2, 7.8), "len": 6.0, "count": 1,
		"width": 2.7, "rate": 1.0, "amp": 1.2, "flutter": 0.0,
		"note": "御兽铃：御兽师腰侧兽铃，钟摆式左右荡，铃心有一点高光",
	},
	"kuxingseng": {
		"motif": "prayer_beads", "anchor": Vector2(0.0, 3.6), "len": 6.4, "count": 6,
		"width": 1.25, "rate": 0.8, "amp": 0.7, "flutter": 0.0,
		"note": "佛珠：苦行僧胸前六颗念珠弧，逐颗按相位微摆",
	},
	"sanxiu": {
		"motif": "wine_gourd", "anchor": Vector2(9.4, 8.0), "len": 7.0, "count": 1,
		"width": 3.0, "rate": 0.95, "amp": 1.3, "flutter": 0.0,
		"note": "酒葫芦：散修腰侧粗陶酒壶 + 麻绳结，摆幅大且带瓶口小气团",
	},
}

## 皮肤系列形制：count/len/width/curl 让同一挂件在 6 套皮肤下轮廓不同，
## 不是「换色」而是「换材质与剪影」。tag 决定材质画法（见 SkinAccentDraw.material()）。
const FORMS: Array[Dictionary] = [
	{"tag": "origin", "count": 0, "len": 1.00, "width": 1.00, "curl": 0.28, "rate": 0.85, "flare": 0.40},
	{"tag": "jade", "count": 0, "len": 1.00, "width": 1.00, "curl": 0.42, "rate": 1.00, "flare": 0.55},
	{"tag": "ember", "count": -1, "len": 1.10, "width": 1.15, "curl": 0.26, "rate": 1.15, "flare": 0.35},
	{"tag": "crystal", "count": 1, "len": 0.86, "width": 0.82, "curl": 0.00, "rate": 0.72, "flare": 0.85},
	{"tag": "ink", "count": -1, "len": 1.22, "width": 1.40, "curl": 0.55, "rate": 0.82, "flare": 0.70},
	{"tag": "gold", "count": 0, "len": 0.90, "width": 1.30, "curl": 0.18, "rate": 1.28, "flare": 0.30},
	{"tag": "prism", "count": 1, "len": 1.02, "width": 1.00, "curl": 0.38, "rate": 1.55, "flare": 0.45},
]

## fx kind → FORMS 下标（原色 fx 为空，取 0 号「本相」形制；肤色仍用角色本色）
const KIND_INDEX: Dictionary = {
	"jade": 1, "bloodlust": 2, "snow": 3, "ink": 4, "gold": 5, "chroma": 6,
}
