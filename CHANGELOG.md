# 更新日志

这里记录 Techne 各版本的重要变化。

## [Unreleased]

### 新增

- 增加 manifest 驱动的发布门禁、对应版本发布说明校验和拖放安装 DMG 打包。
- 增加仓库活动、CI 结果和版本发布的飞书通知。

### 调整

- 最低支持版本提升至 macOS 26.0，并在 CI 与发布流程中校验构建产物的最低系统版本。
- CI 与发布制品统一为 Apple Silicon（`arm64`），不再生成 Intel slice。
- 所有 push 和 Pull Request 统一执行测试与无签名构建检查，main 仅在 CI 成功后进入发布判定。
- README 改为包含功能截图的多语言版本，并展示新的应用图标。
- 项目许可证由 MIT License 改为 Apache License 2.0。
- 应用源码目录由 `Techne/` 调整为 `Apps/`，产品名、target、scheme 和数据路径保持不变。
- 主应用源码由 `Apps/` 归并到 `App/`，测试 target 移入 `Tests/TechneTests/`；target、scheme 和产品行为保持不变。
