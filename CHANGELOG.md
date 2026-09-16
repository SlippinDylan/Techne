# 更新日志

这里记录 Techne 各版本的重要变化。

## [Unreleased]

### 新增

- 增加 manifest 驱动的发布门禁、对应版本发布说明校验和拖放安装 DMG 打包。
- 增加仓库活动、CI 结果和版本发布的飞书通知。

### 调整

- 所有 push 和 Pull Request 统一执行测试与无签名构建检查，main 仅在 CI 成功后进入发布判定。
