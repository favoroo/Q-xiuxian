# 法器「攻击范围」显性化 + 远程射程收紧

## Summary

1. **UI**：武器详情卡（人物属性面板点武器）新增独立「攻击范围」行，显示含加成的实际生效值；不再藏在「攻击间隔」括号里。
2. **数值**：8 把远程法器的 `range` 按「视野内优先」口径收紧（弹丸 300~340、落雷 280~300），近战/环绕不动。改一个字段即可，索敌、目标分配、图鉴展示全部同源。

## Current State Analysis（Phase 1 探索结论）

- 攻击范围属性**已存在**：[WeaponData.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/data/WeaponData.gd) `DEFS` 每把法器都有 `range` 字段（近战 150~185 / 环绕 120~136 / 弹丸 420~460 / 落雷 360~390），是唯一真话。
- 运行时链路全部同源，改表即全生效：
  - [FloatingWeapon.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/weapons/FloatingWeapon.gd) L72 读入 `attack_range`；L419 `_find_target` 以**玩家为圆心**做半径 = `attack_range × _range_mult()` 的索敌圆；L158 脱离射程 1.2 倍才换目标。
  - [Player.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/entities/Player.gd) L460/L512 用同一乘区算 `w_range` 传给 `GameBalance.assign_weapon_targets`。
- 用户没看到它的原因：武器详情把射程塞在「攻击间隔」行括号里（[PlayerStatsDialog.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/ui/PlayerStatsDialog.gd) L1650 `"%.2f 秒 (射程 %.0f)"`）；图鉴已有独立行「射程/范围」（[ManualDialog.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/ui/ManualDialog.gd) L407，显示基础值）。
- 觉得打太远的根因：相机 `zoom = 1.2`（[Main.tscn](file:///Users/a1/Documents/01Code/Godot/t-1/scenes/main/Main.tscn) L75）× 视口 960×540 ⇒ 可见世界 800×450，**半宽 400 / 半高 225**。弹丸射程 420~460 ≈ 半对角线（459），上下方向敌人要走到约 2 倍半屏高，武器却已开火。
- 测试安全面：`tests/` 无钉死远程射程的判据（仅 unit_runner.gd L1498 钉「御灵射程 ≥ 120」，环绕类不动即安全）；BalanceSimCheck 不依赖 range。

## Proposed Changes

### 1. [WeaponData.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/data/WeaponData.gd) — `DEFS` 数值表改 8 处 `range`

| 法器 | id | 旧 | 新 | 档位理由 |
|------|----|----|----|---------|
| 庚金飞剑 | `gengjin_feijian` | 460 | **340** | 点杀单体，远程最远档 |
| 柳叶飞刀 | `liuye_feidao` | 440 | **310** | 扇形多发清群 |
| 玄冰飞针 | `xuanbing_feizhen` | 430 | **310** | 扇形多发清群 |
| 万木灵符 | `wanmu_lingfu` | 420 | **300** | 弹射连锁清群 |
| 火焰符 | `huoyan_fu` | 420 | **300** | 双发掷符 |
| 焚天宝灯 | `fentian_baodeng` | 390 | **300** | 落雷区域 |
| 五雷法牌 | `wulei_paizi` | 380 | **290** | 落雷区域 |
| 番天镇岳印 | `fantian_yin` | 360 | **280** | 落雷区域，最强单发最近档 |

- **不动**：近战（青云剑 150 / 赤焰刀 165 / 藤鞭 175 / 芭蕉扇 185）、环绕（灵蝶 120 / 玉莲 128 / 古钟 136，保持 ≥120 测试约束）。
- 梯度保持原有相对关系：点杀 > 扇形多发 > 弹射 > 落雷；远程全面长于近战（280 vs 185 起）。
- 弹丸 `lifetime`/`speed`/转向**不改**：索敌是闸门，漏网子弹飞出屏属正常表现。
- 攻击范围词条（+12%/层）与剑系羁绊（+15/30/50%）继续乘算新基础值——满羁绊飞剑 510 再出屏属玩家主动选择的成长奖励，不处理。

### 2. [PlayerStatsDialog.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/ui/PlayerStatsDialog.gd) `_open_weapon_tip`（L1643-1651）— 射程独立成行

现：`["攻击间隔", "%.2f 秒 (射程 %.0f)" % [cd, float(def.get("range", 0.0))]]`

改为两行：
```gdscript
var eff_range: float = float(def.get("range", 0.0)) * GameManager.attack_range_mult * GameManager.synergy_range_mult
var range_txt: String = "%.0f（基础 %.0f）" % [eff_range, float(def.get("range", 0.0))] if not is_equal_approx(eff_range, float(def.get("range", 0.0))) else "%.0f" % eff_range
rows 里：
["攻击范围", range_txt, YELLOW if 有加成 else PAPER 色],
["攻击间隔", "%.2f 秒" % cd],
```
- 口径与「单发伤害」等行一致：显示最终生效值，有加成时附基础值并用黄色提示。
- 图鉴（ManualDialog）不动：已有「射程/范围」行显示基础值。
- 商店货架不加：详情卡是统一入口，避免重复。

### 3. [CHANGELOG.md](file:///Users/a1/Documents/01Code/Godot/t-1/CHANGELOG.md) — 追加 `## 2026-10-09 #52`（今日已有 #51，新的在上）

## Assumptions & Decisions

- 用户已确认口径：**视野内优先**（弹丸 300~340 / 落雷 280~300）。
- 只改 `WeaponData.range` 数值 + 详情 UI 一处，不新增字段、不改索敌逻辑、不改弹丸物理。
- 纵向半屏只有 225，300+ 的射程上下方向仍会略出屏——这是口径内接受的取舍（保证远程身份）。

## Verification

```bash
G=/Applications/Godot.app/Contents/MacOS/Godot
$G --headless --path . res://tests/UnitRunner.tscn        # 数值单测（御灵 ≥120 约束不受影响）
$G --headless --path . res://tests/SmokeRunner.tscn       # 全流程冒烟
$G --headless --path . res://tests/PoolCheck.tscn
$G --headless --path . res://tests/LayoutCheck.tscn
$G --headless --path . res://tests/FontCoverageCheck.tscn # UI 文案改动（「攻击范围」字样已在 charset，跑一遍确认）
$G --headless --path . res://tests/BalanceSimCheck.tscn
```
全部 exit 0 且打印 `*_RESULT: ALL PASS`；无需编辑器扫描（无新 class_name/素材）。
