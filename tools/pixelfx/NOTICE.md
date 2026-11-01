# pixelfx 第三方组件说明与许可声明 (NOTICE)

- 上游开源仓库：https://github.com/patch-gg/pixelfx
- 依赖版本：v0.3.0 (Commit 64ba774ac893a8d8feaf, 2026-10-31)
- 软件许可：MIT License (见同目录下 LICENSE 文件)
- 原作者/贡献者署名：
  - Copyright (c) 2026 Patch
  - Copyright (c) 2026 Hugo Duprez (Sprite Fusion)
  - 部分算法参考 Hollow Crown MIT 源码

## 本项目集成与裁剪说明
1. 本目录为纯离线导出工具与代码驱动特效模型，仅包含 `src/` 核心算法、`tools/` 渲染工具、`package.json` 及 `LICENSE`，不参与移动端游戏打包运行。
2. 剥离了原仓库的 `gallery/` 网页画廊与 `fonts/`（明确不随附且不使用未开源商用的 Patch Pixel 字体）。
3. 游戏运行时使用 `tools/export_pixelfx.py` 离线预烘焙生成的精灵表（SpriteSheet PNG）与 Godot 资源定义（SpriteFrames .tres），由 `scripts/systems/FxFlipbookPool.gd` 池化调度。
