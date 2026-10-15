# assets_raw — 素材源目录

本目录是 AI 生成素材的「源」，`assets/` 是切图/压缩后的「产物」。

## images 源图已外迁（2026-10-15 仓库瘦身）

原 `assets_raw/images/`（805 张源图 + raw 原始捕获，约 276 MB）已整体移出仓库：

**现在位置：`~/AssetsLibrary/qxiuxian-raw/images/`**
（`manifest.jsonl` 与 `style/` 锚图的同期副本也在 `~/AssetsLibrary/qxiuxian-raw/`）

- 运行时零引用：Godot 只加载 `assets/art/` 产物，`assets_raw/.gdignore` 让引擎忽略本目录
- 工具脚本（`tools/reexport_all_icons_128.py` 等重切图脚本）读的是本目录路径，
  **需要重切图/重生成时**，把对应源图拷回 `assets_raw/images/` 再跑脚本：
  ```bash
  cp ~/AssetsLibrary/qxiuxian-raw/images/<名字>.png assets_raw/images/
  ```
- 新生成的素材照旧先落 `assets_raw/images/`（进本地库同步一份），切片产物进 `assets/art/`

## 仍留在仓库的源

- `style/` — 画风锚图与 STYLE.md（media-gen 技能路径强依赖，仅 3.6 MB）
- `sfx/` — bake_sfx.py 的音效源（2.4 MB）
- `tutorial_shots/` — 教程截图源（876 KB）
- `voice/` — 语音源（308 KB）
- `manifest.jsonl` — 素材台账（480 KB，新增素材仍须补记）
