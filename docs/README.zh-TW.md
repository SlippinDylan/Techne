<div align="center">
  <img src="images/readme/app-icon.png" width="160" height="160" alt="Techne App 圖示">
  <h1>Techne</h1>
  <p>將本機開發環境、微信小程式建置與 Android 部署整合在同一個原生 macOS App，並提供選單列入口。</p>
  <p>
    <a href="README.zh-CN.md">简体中文</a> ·
    <strong>繁體中文</strong> ·
    <a href="../README.md">English</a> ·
    <a href="README.ja.md">日本語</a> ·
    <a href="README.ru.md">Русский</a>
  </p>
</div>

## Techne 是什麼

Techne 將前端本機開發常見的零散工作集中在一個地方：管理專案與 Git 狀態、尋找正在執行的 dev server、啟動隔離的 Chrome 偵錯執行個體、建置微信小程式，以及透過 ADB 部署 Android App。將常用專案加入後，就能從同一個介面啟動服務、切換分支、查看日誌及執行部署。

## 功能

<table>
  <tr>
    <td width="32%">
      <strong>開發環境與偵錯</strong><br><br>
      集中管理專案，顯示 Git 分支、未提交變更與服務狀態。自動偵測本機 dev server，並可為指定服務啟動使用隔離 profile 與遠端偵錯連接埠的 Chrome。
    </td>
    <td width="68%"><img src="images/readme/development-environment.png" alt="Techne 的開發環境與偵錯介面"></td>
  </tr>
  <tr>
    <td>
      <strong>微信小程式建置</strong><br><br>
      儲存小程式專案路徑及建置、清理、停止命令。一鍵執行建置、清理快取或切換分支，並在日誌面板即時查看輸出。
    </td>
    <td><img src="images/readme/mini-program-build.png" alt="Techne 的微信小程式建置介面"></td>
  </tr>
  <tr>
    <td>
      <strong>Android App 部署</strong><br><br>
      選取 APK 並連接裝置後，即可執行 <code>adb install</code> 與日誌擷取。介面提供裝置連線檢查、安裝進度及時間戳記驗證。
    </td>
    <td><img src="images/readme/android-deployment.png" alt="Techne 的 Android App 部署介面"></td>
  </tr>
</table>

## 目前狀態

> **持續開發中**

核心工作流程已經完成。main push 與 Pull Request 都會執行輕量自動化檢查；僅修改 `README.md`、`docs/`、`LICENSE` 或 `AGENTS.md` 時會略過 macOS 建置，但啟用發布時仍會執行完整檢查。其他變更會執行 `TechneTests` 與未簽署的 Release 建置。目前的發布清單已關閉發布。

## 平台需求

| 項目 | 需求 |
|---|---|
| 最低系統 | macOS 26.0 Tahoe |
| 從原始碼建置 | macOS 26.0 以上與 Xcode 26+ |
| 發佈架構 | Apple Silicon（`arm64`） |
| App 類型 | 非沙盒的原生 macOS App，提供選單列入口 |
| 本機開發 | 可偵測本機開發服務，並啟動隔離的 Chrome 偵錯執行個體 |
| 發佈方式 | GitHub Releases 提供由 Apple Development 簽署、未經公證的 DMG |

## 安裝與發佈

每個 GitHub Release 只包含一個 `Techne-<版本號>.dmg`。開啟 DMG 後，將 `Techne.app` 拖入 `Applications`。目前版本使用 Apple Development 憑證簽署，但未經 Apple 公證；首次開啟前請移除下載隔離屬性：

```bash
sudo xattr -rd com.apple.quarantine /Applications/Techne.app
```

發布設定位於 [`Config/Release/manifest.json`](../Config/Release/manifest.json)。只有 `main` 的 push CI 成功、`release` 為 `true`、版本尚未發布，且 [CHANGELOG.md](../CHANGELOG.md) 有唯一、非空且完全同名的版本章節時，Release workflow 才會簽署、打包並發佈 DMG。

版本格式支援 `x.y.z`、`x.y.z-alpha.n` 和 `x.y.z-beta.n`。Alpha／Beta 後綴會用於 Release、tag、DMG 與 CHANGELOG；App 的 `CFBundleShortVersionString` 則使用對應的純數字 `x.y.z`。

## 設計要點

- 以專案為核心管理本機開發流程，在同一個介面中顯示 Git 狀態、服務狀態與常用操作。
- 以隔離的 Chrome profile 啟動偵錯執行個體，避免多個前端專案的 cookie 與儲存空間互相影響。
- 將小程式的建置、清理與停止命令，以及不同專案類型的命令範本集中管理。
- 將啟動、停止、建置、部署與切換分支等關鍵操作寫入可依分類篩選的時間序日誌。

## 資料位置

應用程式狀態儲存在：

```bash
~/Library/Application Support/studio.slippindylan.Techne/
```

瀏覽器偵錯執行個體的暫存資訊儲存在：

```bash
~/.techne-browsers/
```

## 授權條款

Copyright © 2025–2026 SlippinDylan Studio。Techne 採用 [Apache License 2.0](../LICENSE) 開放原始碼授權條款。
