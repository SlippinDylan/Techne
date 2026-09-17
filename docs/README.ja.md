<div align="center">
  <img src="images/readme/app-icon.png" width="160" height="160" alt="Techne のアプリアイコン">
  <h1>Techne</h1>
</div>

---

<div align="center">
  <p>ローカルプロジェクト、開発サーバー、WeChat ミニプログラムのコマンド、Android APK の配布作業をまとめるネイティブ macOS アプリです。</p>
  <p>
    <a href="README.zh-CN.md">简体中文</a> ·
    <a href="README.zh-TW.md">繁體中文</a> ·
    <a href="../README.md">English</a> ·
    <strong>日本語</strong> ·
    <a href="README.ru.md">Русский</a>
  </p>
</div>

## Techne でできること

Techne は、いつも同じローカルプロジェクトを扱う開発者向けのアプリです。プロジェクトを一度追加すれば、Git のブランチと作業ツリーの確認、プロジェクト固有コマンドの実行、待受中の開発サーバーの検索、サーバーを開くブラウザの起動ができます。

次の二つの作業も同じアプリで扱えます。

- WeChat ミニプログラムでは、依存関係の導入、起動、ビルド、クリーン、停止の各コマンドをプロジェクトごとに設定できます。
- Android 配布では、APK を選択し、接続済みデバイスを見つけ、ADB でインストールして出力を確認できます。

## 主な画面

<table>
  <tr>
    <td width="32%">
      <strong>プロジェクト、Git、サーバー</strong><br><br>
      現在のブランチと未コミットのファイルを表示し、作業ツリーがクリーンならブランチを切り替えられます。サービスの開始と停止もプロジェクトごとの設定に従います。Techne は Node、Bun、Deno のプロセスに関連するローカル待受サービスを検出します。
    </td>
    <td width="68%"><img src="images/readme/development-environment.png" alt="Techne のプロジェクトとサーバーの状態"></td>
  </tr>
  <tr>
    <td>
      <strong>WeChat ミニプログラム</strong><br><br>
      コマンドはプロジェクトごとに保存され、特定のビルドシステムには固定されません。npm と pnpm の WeChat ミニプログラム用テンプレートが含まれます。
    </td>
    <td><img src="images/readme/mini-program-build.png" alt="Techne の WeChat ミニプログラムビルド画面"></td>
  </tr>
  <tr>
    <td>
      <strong>Android APK 配布</strong><br><br>
      APK と接続済みの Android デバイスを選択します。Techne はパッケージ名を読み取り、ADB で APK を再インストールし、パッケージの更新時刻を確認してからアプリを起動します。
    </td>
    <td><img src="images/readme/android-deployment.png" alt="Techne の Android APK 配布画面"></td>
  </tr>
</table>

## インストール

### Homebrew

```bash
brew tap slippindylan/tap
brew trust --tap slippindylan/tap
brew install --cask techne@beta
```

### DMG

[Techne Releases](https://github.com/SlippinDylan/Techne/releases) から DMG をダウンロードし、開いて `Techne.app` を `Applications` へドラッグします。公開 DMG は Apple Silicon Mac 向けです。

現在のリリースは Apple Development 証明書で署名されていますが、Apple の公証は受けていません。そのため macOS が初回起動を止めたり、開発元を確認できないと表示したりします。公式 Releases から DMG を取得し、アプリを `Applications` に移動済みで、起動してよいと判断した場合は、ダウンロード隔離属性を削除してください。

```bash
sudo xattr -rd com.apple.quarantine /Applications/Techne.app
```

## クイックスタート

1. Techne を開き、ローカルプロジェクトを追加します。開発サービスまたは WeChat ミニプログラムを選びます。
2. コマンドテンプレートを選ぶか、そのプロジェクトですでに動くコマンドを入力します。Techne はプロジェクトディレクトリでログイン Bash shell を通して実行します。
3. Web プロジェクトではサービスを起動し、開発環境を更新して、検出されたサーバーをインストール済みブラウザで開きます。
4. Android 配布画面ではデバイスを接続し、APK を選んで配布します。

### ブラウザと独立プロファイル

インストール済みの Safari、Google Chrome、Chrome Beta、Chromium、Microsoft Edge、Brave、Arc を検出します。Safari は通常どおり URL を開きます。Chrome、Chrome Beta、Chromium、Edge、Brave、Arc は Chromium ベースです。管理対象の各インスタンスは別のプロファイルディレクトリと新しいウインドウで起動し、`9222` から利用可能なリモートデバッグポートを割り当てます。普段使いのブラウザや別の管理対象インスタンスの Cookie とサイトデータは共有しません。

### WeChat ミニプログラムのコマンド

Techne にはミニプログラム用ツールチェーンは含まれません。プロジェクトが必要とする依存関係を導入し、そのリポジトリで動くコマンドを設定してください。組み込み例は次のとおりです。

```bash
npm run dev:mp-weixin
npm run build:mp-weixin
pnpm dev:mp-weixin
pnpm build:mp-weixin
```

プロジェクト独自の npm、pnpm、その他の shell コマンドに置き換えられます。必要なパッケージマネージャーとプロジェクト用ツールは、ログイン shell の `PATH` に必要です。

### Android APK 配布

Android SDK Platform-Tools を導入して `adb` を `PATH` から使えるようにし、USB デバッグを有効にした Android デバイスを接続してください。Android SDK Build Tools も必要です。Techne は `aapt2` または `aapt` で APK のパッケージ名を読み取ります。まず `PATH`、次に `~/Library/Android/sdk/build-tools` を検索します。

## 動作条件

| 項目 | 条件 |
|---|---|
| macOS | macOS 26 Tahoe 以降 |
| ハードウェア | 公開 DMG は Apple Silicon のみ |
| Git 操作 | 状態とブランチ操作用の `git` が `PATH` にあること |
| 開発サーバー検出 | macOS の `lsof`。Techne は TCP の待受ポート 3000–9999 を走査 |
| ブラウザ起動 | 対応ブラウザが一つ以上インストール済み |
| ミニプログラムとプロジェクトのコマンド | プロジェクト依存関係と CLI がログイン shell から利用可能 |
| Android 配布 | `adb`、Android SDK Build Tools（`aapt2` または `aapt`）、USB デバッグ有効なデバイス |

## データの保存先

プロジェクト、コマンド設定、ログは次に保存されます。

```bash
~/Library/Application Support/studio.slippindylan.Techne/
```

管理対象 Chromium インスタンスのプロファイルと追跡ファイルは次に保存されます。

```bash
~/.techne-browsers/
```

## ソースからビルド

macOS 26 以降と Xcode 26 以降が必要です。リポジトリを clone し、Xcode で `Techne.xcodeproj` を開いて `Techne` scheme を実行します。Terminal では次を実行できます。

```bash
git clone https://github.com/SlippinDylan/Techne.git
cd Techne
xcodebuild -project Techne.xcodeproj -scheme Techne -configuration Debug build
```

上記の外部ツールは、それぞれの機能を使う場合だけ必要です。

## ライセンス

Copyright © 2025–2026 SlippinDylan Studio. Techne は [Apache License 2.0](../LICENSE) で提供されています。
