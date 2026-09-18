# Techne Agent 指南

本文件是仓库导航和工作契约，不是完整手册。只读取与当前任务相关的链接；更具体、稳定的信息写入对应文档，不在这里重复维护。

## 项目概述

Techne 是面向 macOS 26 及以上版本的原生开发工具，使用 Swift、SwiftUI 和少量 AppKit bridge。它管理用户明确添加的本地项目、开发进程、Git 状态、浏览器实例、微信小程序和 Android APK 部署。

产品行为以 [README.md](README.md) 为入口，当前架构见 [docs/architecture.md](docs/architecture.md)，开发与验证命令见 [docs/development.md](docs/development.md)。

## 开始工作

1. 检查 Git 状态，保留已有未提交改动。
2. 阅读本文件和当前任务涉及的文档，不批量加载历史计划。
3. 搜索现有类型、服务和测试，确认已有设计后再修改。
4. 将改动限制在需求范围内；需求或公共契约存在实质歧义时先确认。

## 仓库地图

- `App/TechneApp.swift`：Scene 组合、长期存活的应用级依赖和系统命令。
- `App/ContentView.swift`：主窗口导航和页面组合。
- `App/Models/`：持久化模型、领域值类型和纯解析规则。
- `App/Services/`：项目、进程、Git、浏览器、微信开发者工具、ADB、备份和更新等能力。
- `App/Views/`：SwiftUI 页面及共享视图组件。
- `Tests/TechneTests/`：按 App、Models、Services、Startup、Views 等职责组织的测试。
- `Config/Release/manifest.json`：发布版本和发布开关的唯一配置入口。
- `.github/`、`Scripts/`：CI、发布、DMG 打包和分发元数据。
- `docs/superpowers/`：历史设计与实施记录，只用于理解背景，不代表当前实现。

## 产品与架构边界

- 项目必须由用户明确添加。端口扫描只能关联已管理项目，不得自动创建项目记录。
- Shell 项目只运行仓库实际声明或用户明确配置的命令；无法识别时返回错误，不猜测命令。
- 依赖安装在识别到的 workspace 根目录执行，开发命令仍在用户选择的项目目录执行。
- 原生微信小程序由微信开发者工具 CLI 管理，不得伪造 Shell 启动流程。
- 普通停止和重启不得隐式清理构建缓存，也不得顺带关闭项目的受管理浏览器。
- Chromium 实例使用独立 profile；不要退化为复用用户日常浏览器 profile。
- 主界面使用单一可复用窗口。菜单栏和系统命令通过 `MainWindowNavigationCoordinator` 聚焦该窗口并切换页面，不创建重复主窗口。
- 进程停止必须保持项目目录作用域，不得因缓存 PID 失效而扩大到无关系统进程。

## 实现约定

- 在用户输入、文件系统、外部进程和工具输出等边界完成校验；内部类型应表达已经成立的不变量。
- `ProjectService` 负责项目状态和业务编排；进程执行、依赖准备、Git、浏览器等细节留在对应服务或模型中。
- `Project`、备份 payload 等持久化结构变更必须考虑旧数据解码和迁移，并增加兼容性测试。
- `PersistenceService` 的读取失败回退和备份 schema 校验是已知缺口，见架构文档。不要复制或扩大这些行为；任务触及相关路径时应修复根因并补回归测试。
- SwiftUI 页面负责展示和触发动作，不复制服务层业务判断。AppKit bridge 只处理 SwiftUI 无法可靠表达的 macOS 行为。
- 共享可观察状态遵守现有 `@MainActor` 和 Observation 设计；不要用 `@unchecked Sendable`、宽泛转换或空 catch 绕过并发和错误问题。
- 错误在能够恢复或向用户说明的层级处理。不要吞掉启动、部署、导入或持久化失败。
- 代码注释使用英文，只解释约束、原因或非显而易见的决策。

## 常用命令

优先使用可用的 Xcode 项目工具执行 macOS 构建和测试；不可用时使用下面的等价命令。详细参数见 [docs/development.md](docs/development.md)。

```bash
xcodebuild test -project Techne.xcodeproj -scheme Techne -destination 'platform=macOS,arch=arm64'
xcodebuild build -project Techne.xcodeproj -scheme Techne -configuration Debug -destination 'platform=macOS,arch=arm64'
node .github/scripts/release-manifest.mjs validate
node .github/scripts/sync-version.mjs --check
node --test .github/scripts/*.test.mjs
```

不要为了常规验证启动应用、浏览器、模拟器或 watch 进程。UI 改动由用户验收；只有用户明确要求或提供待分析截图时才做视觉验证。

## 验证与完成标准

- 先运行覆盖改动的最小测试，再根据失败或风险扩大范围。
- 模型、持久化、进程或窗口导航变更应补充直接回归测试。
- 应用级改动至少完成相关测试和一次 macOS 构建；仅文档改动运行引用、链接和 diff 检查。
- 发布自动化改动必须运行清单校验、Node 测试和 Shell 语法检查。
- 完成前检查 `git diff --check`、改动文件列表和残留引用，确认没有调试输出或无关修改。
- 未执行的必要验证必须说明原因和剩余风险。

## 文档规则

- README 记录用户可见能力、安装方法、系统要求和数据位置。
- `docs/architecture.md` 记录当前系统边界和稳定不变量；`docs/development.md` 记录开发、验证、发布和清理流程。
- 实现变化导致这些文档失效时同步更新。源码已经能清晰表达的成员列表或调用细节不要复制进文档。
- 新设计尚未实现时写计划或设计文档；实现完成后以当前文档和代码为准。
- 新增和维护的仓库内部文档使用中文。README 沿用现有多语言结构，用户可见事实需要同步维护对应版本。

## 开发产物与清理

- 只有用户明确要求清理时，才删除可安全重新生成的构建产物、测试结果和临时目录。
- 删除前先确认路径归属并统计占用。不得删除源码、Git 数据、项目配置、用户数据或用途不明的系统文件。
- 清理仓库外的 `/tmp`、`/private/tmp` 或 `/private/var/folders` 需要用户明确授权，并且目标必须能可靠归因于 Techne 或本次开发流程。

## 信息冲突

`AGENTS.md` 规定工作方式，README 和当前文档描述产品与架构，代码和测试说明实际实现。三者不一致且会影响需求或公共契约时，不自行选择其一：说明冲突、影响和建议处理方式，等待确认。
