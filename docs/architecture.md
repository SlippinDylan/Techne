# Techne 架构

本文记录 Techne 当前的系统边界和长期约束。具体类型和调用关系以源码为准；尚未完成或已经结束的方案保留在 `docs/superpowers/`，不作为当前架构依据。

## 系统定位

Techne 是单一 GUI 的原生 macOS 应用，没有常驻服务端或辅助守护进程。界面使用 SwiftUI，结构化日志表格、进程检查等少数能力通过 AppKit 或系统工具完成。应用会按用户操作启动 Shell、微信开发者工具 CLI、ADB 和浏览器等外部进程，但不内置这些工具。

应用管理的是用户明确选择的本地资源：项目目录、项目命令、开发进程、浏览器实例、APK 和连接中的 Android 设备。自动检测用于补充状态，不改变资源所有权。

## 代码结构

```text
App/
├── TechneApp.swift        Scene、应用级依赖、系统命令
├── AppDelegate.swift      启动方式和应用生命周期
├── ContentView.swift      主窗口导航和页面组合
├── Models/                领域数据、持久化模型、纯规则
├── Services/              业务编排和外部系统边界
├── Views/                 页面、组件和 AppKit bridge
├── Config/                应用内常量
└── Utils/                 无状态通用工具

Tests/TechneTests/         与上述职责对应的回归测试
```

`TechneApp` 创建长期存活的 `ProjectService`、`CommandConfigService`、`ApplicationUpdateController` 和主窗口导航协调器。视图通过初始化参数或 environment 使用这些实例，不在页面切换时重新创建业务状态。

## 窗口与导航

应用只有一个业务主窗口。`ContentView` 的侧边栏包含开发服务、微信小程序、Android 部署，以及固定在底部的设置和日志。设置页通过顶部 Pane 在通用设置与关于页面之间切换。

`MainWindowNavigationCoordinator` 接收菜单栏、系统菜单和应用重新激活产生的导航意图。它优先聚焦已存在的主窗口，只在窗口不存在时调用 SwiftUI `openWindow`，并在窗口创建后将其置于前台。新增入口应复用该路径，不能直接创建另一份主窗口状态。

应用以 accessory 形态运行，不显示 Dock 图标。菜单栏由 AppKit `NSStatusItem` 管理：左键显示或聚焦主窗口，右键打开业务菜单。`Command-Q` 只关闭主窗口并保留菜单栏进程与项目任务；右键菜单中的退出项会等待受管理项目安全停止，再彻底退出应用。停止失败时保留应用进程并向用户显示失败信息。

菜单栏是快速入口，不承载设置、日志或更新业务。更新检查由关于页调用同一个长期存活的 `ApplicationUpdateController`。

## 语言与区域设置

Techne 提供英文、简体中文和繁体中文界面。默认跟随 macOS；用户也可以在设置的“通用”区域指定应用语言。指定语言只写入 Techne 自身的 `UserDefaults` 与应用域 `AppleLanguages`，切回跟随系统时删除该覆盖，不修改系统全局语言。

语言变化在完整重启后生效，保证 SwiftUI、AppKit、菜单栏和系统命令使用同一语言。界面语言不改变数字、日期和文件大小所使用的系统区域设置，也不翻译 Shell、Git、ADB、包管理器及微信开发者工具的原始输出。

语言偏好不进入项目、命令配置或备份 schema。`ProjectType.rawValue`、启动模式名称、命令快照及既有日志中的持久化文本保持原值；展示层通过本地化名称呈现，历史数据不随语言切换重写。

## 项目模型与持久化

`Project` 是项目运行契约的持久化快照，包含规范化路径、项目类型、运行时类型、命令、依赖策略和启动模式。进程 PID、终端输出和过渡状态属于运行时数据，不持久化。已添加项目不应在运行时重新依赖一个可能已经变化或删除的命令模板。

`ProjectService` 负责加载、保存和迁移项目，协调刷新、启动、停止、分支切换与导入。`CommandConfigService` 管理用户定义的命令配置。通用 `PersistenceService` 将 Codable 数据原子写入：

```text
~/Library/Application Support/studio.slippindylan.Techne/
├── projects.json
├── commandconfigs.json
└── logs.json
```

`ContentView` Preview 通过注入 `PersistenceRoot` 使用隔离临时目录。涉及持久化写入的测试也必须注入临时目录，不得读写真实应用数据。持久化结构发生变化时，需要保持旧数据可解码，或提供显式迁移，并用测试锁定兼容行为。

当前 `PersistenceService.load()` 无法区分“文件不存在”和“读取或解码失败”，两者都会返回空数组；后续保存可能覆盖原文件。这是已知的数据安全缺口，不是可依赖的容错契约。涉及持久化读取的改动应先让失败显式传递，并覆盖损坏文件、旧 schema 和禁止覆盖原数据的测试。

## 项目识别与命令

项目只能由用户明确添加。自动识别时，`ProjectService` 根据目录中的真实清单、脚本、锁文件和微信项目配置生成项目快照；自动识别失败时，只有用户明确选择了有效的 `CommandConfig` 才允许创建项目。除此之外不得猜测命令。

Shell 项目的依赖准备与启动分开处理：

1. `ProjectDependencyResolver` 确定 workspace 根目录、安装产物和依赖指纹。
2. `ProjectStartupCoordinator` 根据策略生成 install、clean、start 阶段。
3. `ProcessManager` 执行计划并把输出及结构化阶段事件回传给项目状态。

依赖安装在 workspace 根目录执行，启动命令在用户选择的项目目录执行。普通启动、停止和重启不会自动运行清理命令；只有明确要求清理的流程才包含 clean 阶段。

原生微信小程序是独立运行时。它通过 `WeChatDevToolsService` 调用已安装开发者工具的 CLI 打开、关闭或恢复文件监听，不进入 Shell 项目的依赖和启动流水线。

## 进程和服务检测

Techne 对自己启动的任务保留受管执行记录。停止时先取消当前受管任务，再扫描并清理同项目目录的残留进程组。应用启动和全局刷新只获取一次系统进程快照，并通过项目工作目录与当前启动命令特征恢复 Shell 项目的运行状态；不得为每个项目重复执行全系统扫描。

项目的启动与重新启动共享 replace-and-start 语义：先确认该项目作用域内的旧进程组全部停止，停止失败时禁止新启动。原生微信小程序不参与系统进程推断；启动时通过微信开发者工具 CLI 执行 close/open，应用退出时按项目执行 close，不得终止共享的微信开发者工具进程。

缓存 PID 只是提示，不能作为跨项目终止进程的充分依据。停止范围必须限定在目标项目，无法建立归属时返回失败，不扩大扫描或发送全局信号。

`DevServerDetectionService` 扫描 3000–9999 的监听端口，并通过 `DevServerProjectMatcher` 关联已管理项目。检测到未知服务时可以展示状态，但不能因此写入新的项目记录。

## 浏览器实例

Safari 使用系统打开 URL。Chromium 系浏览器由 `ManagedBrowserInstanceService` 启动独立实例，每个实例拥有单独的 profile 目录和可用的远程调试端口。跟踪信息和 profile 位于：

```text
~/.techne-browsers/
```

项目停止和重启不关闭这些实例。只有明确的浏览器关闭操作才能终止实例并删除对应跟踪记录和 profile。

## Android 部署

`ADBDeployViewModel` 协调 APK 选择、设备选择、包名读取、安装校验和启动。外部工具查找与命令失败属于系统边界错误，应保留可读输出并向界面报告，不能伪造成功状态。

## 日志、备份与更新

`LogService` 是主 actor 上的共享日志源，最多保留 500 条记录并持久化到 `logs.json`。终端流输出与结构化操作日志职责不同：终端展示连续文本，日志页展示可筛选、可选择的记录。

备份文档包含项目快照和命令配置，字段中记录 schema 版本。导入采用合并语义：项目按规范化路径去重，命令配置按名称去重。

当前导入路径尚未在写入前拒绝未知 `schemaVersion`，因此版本字段还不是完整的兼容边界。这是已知缺口。修改 payload 或导入流程时，必须先验证支持的 schema，未知版本不得合并或写入本地数据，并补充兼容性测试。

`ApplicationUpdateController` 封装 Sparkle。Release 构建启用更新，Debug 构建禁用；stable、beta、alpha 构建只接收各自允许的更新频道。Feed URL、公钥和签名要求由 `Info.plist` 与 CI 的产物检查共同约束。

## 关键不变量

- 未经用户选择，不创建项目记录。
- 不猜测项目命令，不静默修复无效配置。
- 不把外部工具缺失或命令失败解释为成功。
- 不因停止一个项目而影响其他项目或浏览器实例。
- 不让 Preview 和测试访问真实持久化目录。
- 不创建第二个业务主窗口或第二份应用级服务状态。
