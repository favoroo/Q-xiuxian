class_name ElixirData
extends RefCounted

## 药池·服丹（药王治疗出口）数据表：满血时溢出的治疗不再白费——一半存进药池，
## 危机关头点「服丹」一口喝掉：立刻按池量回血，并带一小段全伤害增益反打窗口。
## 药王的回复珠/回血从「顶满就浪费」变成存款，「挨打再吃药」是一个完整的攒/放节奏。
##
## 三条口径（同 ShadowStepData 规约）：
## 1. 全 static 纯函数，不读 autoload、不碰节点，数值只在本表；
## 2. 药池账单在 GameManager.elixir_pool（单局字段，RunReset 复位），写入点只有两处：
##    Player.heal 的溢出部分与自然回血 tick 的顶满溢出；兑现点只有 _release_elixir 一处；
## 3. 卡面/详解里出现的药池数字一律现读本表（card_lines），别处不抄。
## 服丹是免冷却 BURST（SkillData），门控是药池本身——池空按不动（按钮侧给拒绝抖动）。

const STORE_RATIO := 0.5    ## 溢出治疗入池比例：回血珠顶满部分、自然回血顶满部分都按此折算
const CAP_HP_RATIO := 0.30  ## 药池上限 = 最大气血 ×30%：攒得动但不至于一口回满翻盘
const BUFF_DURATION := 5.0  ## 服丹后全伤害增益持续（秒）
const BUFF_DAMAGE := 0.25   ## 服丹后全伤害加成（服丹=反打信号，不只是奶瓶）

## 池上限（气血变化时现算，不缓存）
static func cap_of(max_health: float) -> float:
	return maxf(1.0, max_health * CAP_HP_RATIO)

## 入池：溢出的治疗按 STORE_RATIO 折算存入，顶到上限为止
static func add_pool(pool: float, overflow: float, max_health: float) -> float:
	return minf(cap_of(max_health), pool + maxf(0.0, overflow) * STORE_RATIO)

## 有没有东西可喝：空池时按钮按不动（与影爆「没影按不动」同一把尺子）
static func has_charge(pool: float) -> bool:
	return pool > 0.01

## 服丹后全伤害乘区（Player._release_elixir 写 GameManager.buff_damage_mult，到期回 1.0）
static func buff_mult() -> float:
	return 1.0 + BUFF_DAMAGE

## 卡面文案：选角/详解/图鉴同读这一份，数字现读本表（口径 3）。
## 每条一行，按详解卡最窄列宽（404）量过：加字先量宽。
static func card_lines() -> Array[String]:
	return [
		"攒：治疗溢出的部分 %d%% 存入药池（至多 %d%% 气血）" % [
			int(roundf(STORE_RATIO * 100.0)), int(roundf(CAP_HP_RATIO * 100.0))],
		"放：随时点「服丹」按药池回血，%d 秒内全伤害 +%d%%" % [
			int(roundf(BUFF_DURATION)), int(roundf(BUFF_DAMAGE * 100.0))],
	]
