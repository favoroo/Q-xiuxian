# 驯兽师（fuzhen）形象优化方案

## 摘要

驯兽师当前观感为"骷髅头 + 乌龟壳"。根因全部在程序化渲染参数与两个专属渲染分支上，通过"调参 + 两个新渲染分支 + 重新导出图标"即可修复，不新增 AI 素材，不影响其他 8 名角色与 NPC 配置。

## 现状分析

渲染链路（三端同源，改一处全生效）：
- 选人界面：[CultivatorSelect.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/ui/CultivatorSelect.gd#L206) 直接挂 `ProceduralCultivatorView` 实时渲染
- 游戏内：[Player.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/entities/Player.gd#L105) 同上
- 头像图标：[export_cultivator_icons.gd](file:///Users/a1/Documents/01Code/Godot/t-1/tools/export_cultivator_icons.gd) 从同一视图导出 96×96 PNG

造型定义在 [CultivatorVisualConfig.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/entities/procedural_cultivator/CultivatorVisualConfig.gd#L169) `make_fuzhen()`，绘制在 [HollowKnightCultivatorRenderer.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/entities/procedural_cultivator/HollowKnightCultivatorRenderer.gd)。

**根因 1「骷髅头」**：
- `eye_style: "round_pupil"` 渲染分支用近纯黑 `col_void` 画 r=3.8·hs 的大圆瞳（[L808-815](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/entities/procedural_cultivator/HollowKnightCultivatorRenderer.gd#L808-L815)），叠加 `head_scale 1.14` 的大头，黑圆占比过大 → 读作空洞眼窝
- `horns_style: "dao_bun"` 是"单发髻 + 一根横穿木簪直线"（[L588-600](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/entities/procedural_cultivator/HollowKnightCultivatorRenderer.gd#L588-L600)），横线压在头顶 → 读作"骷髅插箭"

**根因 2「乌龟壳」**：
- `cloak_style: "short_cape"` 正面外袍是圆顶穹壳剪影（[L954-965](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/entities/procedural_cultivator/HollowKnightCultivatorRenderer.gd#L954-L965)）
- 配色浑浊：外袍朱砂赤红 `Color(0.36, 0.16, 0.14)` 在小尺寸下读作褐泥色，内衬杏黄 `Color(0.55, 0.38, 0.18)` 深褐黄 → 整体一个棕壳

**波及面确认（必须零波及）**：`dao_bun` 还被雷法真君/药王使用（[L420](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/entities/procedural_cultivator/CultivatorVisualConfig.gd#L420)、[L476](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/entities/procedural_cultivator/CultivatorVisualConfig.gd#L476)），`round_pupil` 还被多宝道人/灵植夫使用，`short_cape` 还被灵植夫使用。**因此不修改任何共享分支的现有行为，只新增 fuzhen 专属新键值分支 + 改 fuzhen 自己的参数。**

## 改动内容

### A. 参数层 — `scripts/entities/procedural_cultivator/CultivatorVisualConfig.gd`

`make_fuzhen()`（L169-194）：
| 参数 | 旧值 | 新值 | 目的 |
|---|---|---|---|
| `head_scale` | 1.14 | 1.10 | 略缩头壳占比 |
| `horns_style` | `"dao_bun"` | `"twin_buns"`（新） | 双丫髻童子髻，去横簪 |
| `eye_style` | `"round_pupil"` | `"round_bright"`（新） | 小黑瞳大高光，去眼窝感 |
| `eye_color` | `(0.35,0.85,1.0,0.5)` | `(0.35,0.85,1.0,0.65)` | 辉光更亮 |
| `col_outer` | `(0.36,0.16,0.14)` | `(0.60,0.22,0.15)` 明朱红 | 杀"褐壳"感 |
| `col_inner` | `(0.55,0.38,0.18)` | `(0.92,0.84,0.64)` 米杏白 | 领口/内衬亮色对比 |
| `col_edge` | `(0.95,0.78,0.30)` | 保留 | 金符流光 |

同时更新 L19-21 的键值注释文档（加 `twin_buns`、`round_bright` 说明）。

### B. 渲染层 — `scripts/entities/procedural_cultivator/HollowKnightCultivatorRenderer.gd`

1. `_draw_modular_headwear`（L546+）**新增 `"twin_buns"` 分支**（不删 dao_bun）：
   - 正面：左右两个小髻（`±6.5·hs, -10·hs`，r≈3.4·hs，`col_bone` + 骨影描边），髻根一圈红头绳（`col_tassel_red`），无横簪
   - 侧面：前髻为主 + 后髻暗色衬垫
   - 背面：对称双髻照常可见
   - 约 22 行纯矢量几何
2. `_draw_modular_eyes`（L784+）**新增 `"round_bright"` 分支**（不删 round_pupil）：
   - 正面：黑瞳 r 2.7·hs（原 3.8）+ 天青辉光 + 亮核 r 1.5·hs + 左上白色高光点 r 0.8·hs
   - 侧面：黑瞳 r 2.4·hs + 亮核
   - 约 14 行
3. `_draw_forehead_sigil` L510：红 sigil 条件 `horns_style == "dao_bun"` 改为 `"dao_bun" or "twin_buns"`（保留童子朱砂痣）。

### C. 图标点缀 — `tools/export_cultivator_icons.gd`

导出 fuzhen 头像时在肩侧上方加 1 只青蓝小蝴蝶（两片三角翼 + 身点，约 8 行），呼应"开局自带护蝶"的驯兽师身份；其余 8 人不受影响。仅进图标，不进游戏内视图（游戏内本就有真实护蝶召唤物）。

### D. 重新导出与视觉验收

```bash
G=/Applications/Godot.app/Contents/MacOS/Godot
$G --headless --path . --editor --quit                          # 重导入图标 PNG
$G --path . res://tools/ExportCultivatorIcons.tscn              # 重导 9 头像
$G --path . res://tests/CultivatorGalleryPreview.tscn -- --export  # 导画廊三视图
```
用 Read 查看 `tests/styles/cultivator_modular_gallery.png` 与 `assets/art/cultivator_fuzhen_icon.png`：确认正面无骷髅感/无龟壳感、侧面无穿模、背面双髻正常。不满意则迭代配色/尺寸再导（预算 1-2 轮）。

### E. 回归门禁 + 记录

- 核心基线全套 headless：UnitRunner / SmokeRunner / PoolCheck / LayoutCheck / FontCoverageCheck / BalanceSimCheck，退出码 0
- 追加 [CHANGELOG.md](file:///Users/a1/Documents/01Code/Godot/t-1/CHANGELOG.md)（`## 2026-10-10 #序号`，记根因与涉及文件）

## 假设与决策

- **保持统一美术方向**：全员骨白面壳的"空洞冷冽仙侠风"不动，只让 fuzhen 的五官与配色更"活"
- **零波及铁律**：不改 `dao_bun` / `round_pupil` / `short_cape` 现有行为；新增键值分支仅 fuzhen 引用
- **不新增 AI 素材**：纯程序化矢量调整，`cultivator_fuzhen_8dir.png` 等旧 AI 素材不处理
- **备选方向（本次不做）**：兽耳头饰、灵笛法器等强驯兽元素分支，若用户想要可在本次验收后再加
- 数值层无任何改动，玩法/平衡不受影响

## 验证步骤

1. 跑 D 节三条导出命令，Read 画廊图 + 图标，肉眼核对三视图与头像
2. 跑 E 节基线测试，确认全绿（视觉改动不触逻辑，预期无回归）
3. 用户在选人界面实际预览驯兽师新形象做最终确认
