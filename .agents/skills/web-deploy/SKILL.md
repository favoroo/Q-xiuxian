---
name: web-deploy
description: 剑士游戏的 Web (HTML5) 导出与 GitHub Pages 部署流程。当用户要求部署网页版/发布到 GitHub Pages/让朋友在浏览器中试玩/web部署/更新网页版/部署 web 版时使用。涵盖 Godot 4.7 Web 导出、gh-pages 孤儿分支管理、一键部署脚本 tools/deploy_web.py。位于 .agents/skills/web-deploy/SKILL.md。
---

# 剑士 Web 版导出与 GitHub Pages 部署

## 与 xiuxian-release 的关系

- **xiuxian-release**：管 Android APK 的构建、双端 Tag/Release 发布、应用内更新。
- **web-deploy**（本 skill）：管 Web (HTML5) 导出与 GitHub Pages 部署，让朋友在浏览器中试玩。
- 两者互不干扰：Android 预设 `[preset.0]` 与 Web 预设 `[preset.1]` 完全独立，代码守卫用 `OS.has_feature("web")` 隔离，不影响 Android 和桌面行为。

## 前置条件

| 项 | 要求 |
|----|------|
| Godot 导出模板 | 4.7 Web 模板已安装（编辑器 → 管理器 → 导出模板 → 下载） |
| Git 远端 | `origin` 指向 `https://github.com/favoroo/Q-xiuxian.git` |
| GitHub Pages | 仓库 Settings → Pages → Source 选 `gh-pages` 分支 / root（一次性设置） |

## 一次性设置（首次使用前）

### 1. 安装 Godot Web 导出模板

在 Godot 编辑器中：编辑器 → 管理器 → 导出模板 → 下载 4.7 模板。

### 2. 开启 GitHub Pages

在 GitHub 仓库 `favoroo/Q-xiuxian` → Settings → Pages → Source → 选 `gh-pages` 分支 / root。
（首次部署脚本会自动创建 `gh-pages` 分支，但需要在 GitHub 网页上手动选一次 Source。）

## 部署流程

```bash
# 一键导出 Web 版与宣传站并部署到 GitHub Pages
python3 tools/deploy_web.py
```

脚本自动完成：
1. 自动同步游戏数据到宣传站 `site/dist/data.js`
2. 调用 Godot CLI 导出 Web 版到 `build/web/`
3. 创建或切换到 `gh-pages` 孤儿分支
4. 将 `build/web/` 内容复制到分支根目录（游戏本体）
5. 将 `site/dist/` 内容复制到分支 `site/` 目录（宣传站官网）
6. 提交并推送到 `origin`
7. 切回原工作分支
8. 打印访问 URL

部署后访问：
- **游戏本体**：`https://favoroo.github.io/Q-xiuxian/`
- **宣传官网**：`https://favoroo.github.io/Q-xiuxian/site/`

首次生效需等待 1-2 分钟（GitHub Pages 缓存刷新）。

## 更新流程

改完代码后重跑同一脚本即可，URL 不变，覆盖旧版本：

```bash
python3 tools/deploy_web.py
```

如果已有 `build/web/` 产物且只改了宣传站或部署逻辑，可跳过 Godot 导出：

```bash
python3 tools/deploy_web.py --skip-export
```

如果只想部署游戏版不包含宣传站，可传：

```bash
python3 tools/deploy_web.py --skip-site
```

## 技术细节

### Web 导出预设

`export_presets.cfg` 中 `[preset.1]` 为 Web 预设：
- 关闭线程（`html/click_to_play=true`），不需要 COOP/COEP 跨域隔离头
- GitHub Pages 正确返回 `.wasm` / `.js` / `.html` 的 MIME 类型
- Godot 4.7 Web 模板使用相对路径加载资源，放在 `https://favoroo.github.io/Q-xiuxian/` 子目录下正常工作

### 代码守卫

以下三处 `OS.has_feature("web")` 守卫仅影响 Web 平台，Android 和桌面行为不变：

1. **`UpdateManager.gd`** — `check_for_update()` 入口直接 return，浏览器无法下载安装 APK
2. **`Main.gd`** — BGM 延迟到首次用户交互后播放（浏览器自动播放策略）
3. **`html/click_to_play=true`** — 导出预设显示「Click to Play」覆盖层，用户点击后游戏才开始

### 包体积

资源约 22MB + 字体 1.2MB + Godot Web 引擎约 30-40MB，总共约 55-65MB。首次加载需等待，之后浏览器缓存生效。

## 故障排查

| 问题 | 原因 | 解决 |
|------|------|------|
| 页面空白 | Godot Web 导出模板未安装 | 编辑器 → 管理器 → 导出模板 → 下载 4.7 模板 |
| `.wasm` 加载失败 | MIME 类型不对 | GitHub Pages 自动处理，检查是否用了其他静态托管 |
| 音频不播放 | 浏览器自动播放策略 | `html/click_to_play=true` + 代码守卫已处理，用户先点击即可 |
| 更新弹窗报错 | CORS 拦截 GitHub API | 已用 `OS.has_feature("web")` 跳过，不应出现 |
| 页面不变 | GitHub Pages 缓存 | 等待 1-2 分钟，或用浏览器无痕模式 |
| 推送被拒 | gh-pages 分支远端有新提交 | `git push origin gh-pages --force`（孤儿分支可直接覆盖） |
