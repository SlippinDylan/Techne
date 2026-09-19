<div align="center">
  <img src="images/readme/app-icon.png" width="160" height="160" alt="Techne App 圖示">
  <h1>Techne</h1>
</div>

<div align="center">
  <p>將本機專案、開發服務、微信小程式命令與 Android APK 部署放在一起的原生 macOS App。</p>
  <p>
    <a href="README.zh-CN.md">简体中文</a> ·
    <strong>繁體中文</strong> ·
    <a href="../README.md">English</a> ·
    <a href="README.ja.md">日本語</a> ·
    <a href="README.ru.md">Русский</a>
  </p>
</div>

## Techne 可以做什麼

Techne 適合經常處理同一批本機專案的開發者。明確加入一次專案後，就能查看 Git 分支和工作目錄、執行專案實際宣告的命令、尋找其監聽中的開發服務，或直接開啟瀏覽器。連接埠掃描只會關聯已管理的專案，不會把未知專案自動加入清單。

主要工作流程包括：

- Web 與需要編譯的微信小程式會根據清單和腳本進行分析，啟動前可自動準備缺少的相依套件。
- 原生微信小程式透過微信開發者工具 CLI 開啟和關閉，不需要 Shell 啟動命令。
- Android 部署可選取 APK、尋找已連線裝置、透過 ADB 安裝，並顯示命令輸出。

## App 內功能

<table>
  <tr>
    <td width="32%">
      <strong>專案、Git 與服務</strong><br><br>
      查看目前分支和未提交檔案；工作目錄乾淨時可切換分支；啟動、停止或重新啟動服務。Techne 會尋找與已管理 Node、Bun 或 Deno 專案相關的本機監聽服務。
    </td>
    <td width="68%"><img src="images/readme/development-environment.png" alt="Techne 的專案與服務狀態"></td>
  </tr>
  <tr>
    <td>
      <strong>微信小程式</strong><br><br>
      執行專案宣告的 Taro、UniApp 或 Mpx 開發腳本，也可在微信開發者工具中開啟原生小程式。新增頁面未被辨識時，可要求開發者工具重建檔案監聽。
    </td>
    <td><img src="images/readme/mini-program-build.png" alt="Techne 微信小程式建置工作區"></td>
  </tr>
  <tr>
    <td>
      <strong>Android APK 部署</strong><br><br>
      選取 APK 與已連線 Android 裝置。Techne 讀取套件名稱，透過 ADB 重新安裝 APK、核對套件更新時間，接著啟動 App。
    </td>
    <td><img src="images/readme/android-deployment.png" alt="Techne Android APK 部署工作區"></td>
  </tr>
</table>

## 安裝

### Homebrew

```bash
brew tap slippindylan/tap
brew trust --tap slippindylan/tap
brew install --cask techne@beta
```

### DMG

從 [Techne Releases](https://github.com/SlippinDylan/Techne/releases) 下載 DMG，開啟後將 `Techne.app` 拖到 `Applications`。已發佈的 DMG 適用於 Apple Silicon Mac。

目前版本使用 Apple Development 憑證簽署，但未經 Apple 公證。macOS 因此可能阻擋首次開啟，或顯示無法驗證開發者的提示。若 DMG 來自官方 Releases、App 已移至 `Applications`，且你決定繼續使用，可移除下載隔離屬性：

```bash
sudo xattr -rd com.apple.quarantine /Applications/Techne.app
```

## 快速開始

1. 開啟 Techne，明確加入一個本機專案，選擇開發服務或微信小程式專案。
2. Techne 會讀取專案實際的清單、腳本、套件管理器資訊和鎖定檔；無法辨識可執行專案時會明確拒絕，不會猜測命令。
3. 啟動專案。npm、pnpm、Yarn 或 Bun 專案缺少相依套件時會自動安裝；清單或鎖定檔之後變更時會再次準備。命令透過已設定的 zsh、Bash 或 fish 登入 shell 執行。
4. 視需要停止或重新啟動。一般停止和重新啟動不會清除建置快取，也不會關閉受管理的瀏覽器視窗。
5. Web 專案可選擇已安裝的瀏覽器開啟偵測到的服務。
6. 在 Android 部署頁連線裝置、選取 APK，然後部署。

### 語言

Techne 支援英文、簡體中文和繁體中文，預設跟隨 macOS。你也可以在「設定 > 一般」中指定語言，並依提示重新啟動 Techne 以套用變更。

### 瀏覽器與獨立 profile

Techne 會偵測已安裝的 Safari、Google Chrome、Chrome Beta、Chromium、Microsoft Edge、Brave 和 Arc。Safari 以一般方式開啟網址。Chrome、Chrome Beta、Chromium、Edge、Brave 和 Arc 使用 Chromium 核心：每個受管理實例都有獨立 profile、新視窗與遠端偵錯連接埠，連接埠從 `9222` 起自動尋找可用值。這不會重用日常瀏覽器或其他受管理實例的 cookie 與網站儲存空間。

### Web 與微信小程式專案

對於以 Shell 執行的專案，Techne 只執行倉庫實際宣告的腳本。它能辨識常見 Web 開發腳本，以及 Taro、UniApp、Mpx 的微信目標，並支援 npm、pnpm、Yarn 和 Bun。相依套件會在辨識到的 workspace 根目錄安裝，開發命令仍在所選專案目錄執行。

根目錄具有有效 `project.config.json` 的原生小程式，會透過已安裝的微信開發者工具 CLI 開啟、關閉和恢復檔案監聽。需要編譯的小程式在產生開發者工具專案目錄後，也會使用該目錄恢復檔案監聽。Techne 不內建 Node.js、套件管理器、框架 CLI 或微信開發者工具；專案需要的執行環境和工具仍須安裝，且能由登入 shell 找到。

### Android APK 部署

安裝 Android SDK Platform-Tools，使 `adb` 可從 `PATH` 使用；連接已啟用 USB 偵錯的 Android 裝置；並安裝 Android SDK Build Tools。Techne 使用 `aapt2` 或 `aapt` 讀取 APK 套件名稱，先從 `PATH` 尋找，再查看 `~/Library/Android/sdk/build-tools`。

## 系統需求

| 項目 | 需求 |
|---|---|
| macOS | macOS 26 Tahoe 或以上 |
| 硬體 | 已發佈 DMG 僅支援 Apple Silicon |
| Git 功能 | `git` 位於 `PATH`，供狀態與分支操作使用 |
| 已管理服務關聯 | macOS 內建 `lsof`；Techne 掃描 3000–9999 的 TCP 監聽連接埠，只關聯已加入的專案 |
| 瀏覽器啟動 | 至少安裝一個受支援瀏覽器 |
| Web 與編譯型小程式 | Node.js、專案使用的套件管理器和框架工具能由登入 shell 找到；專案相依套件可由 Techne 準備 |
| 原生微信小程式 | 已安裝微信開發者工具，且 App 套件內含 CLI |
| Android 部署 | `adb`、Android SDK Build Tools（`aapt2` 或 `aapt`）及已啟用 USB 偵錯的裝置 |

## 資料位置

專案記錄、命令設定和日誌儲存在：

```bash
~/Library/Application Support/studio.slippindylan.Techne/
```

受管理 Chromium 實例的 profile 與追蹤檔案儲存在：

```bash
~/.techne-browsers/
```

## 從原始碼建置

需要 macOS 26 以上與 Xcode 26 以上。複製倉庫後，在 Xcode 開啟 `Techne.xcodeproj` 並執行 `Techne` scheme；也可在終端執行：

```bash
git clone https://github.com/SlippinDylan/Techne.git
cd Techne
xcodebuild -project Techne.xcodeproj -scheme Techne -configuration Debug build
```

以上列出的外部工具只在使用對應功能時需要。

## 授權條款

Copyright © 2025–2026 SlippinDylan Studio。Techne 採用 [Apache License 2.0](../LICENSE) 授權。
