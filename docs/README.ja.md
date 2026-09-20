<div align="center">
  <img src="images/readme/app-icon.png" width="160" height="160" alt="Techne のアプリアイコン">
  <h1>Techne</h1>
</div>

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

Techne は、いつも同じローカルプロジェクトを扱う開発者向けのアプリです。プロジェクトを明示的に一度追加すれば、Git のブランチと作業ツリーの確認、リポジトリで実際に宣言されたコマンドの実行、待受中の開発サーバーの検索、ブラウザの起動ができます。ポート走査は管理済みプロジェクトとの関連付けだけに使われ、未知のプロジェクトを自動追加しません。

主なプロジェクトワークフローは次のとおりです。

- Web とビルド型ミニプログラムはマニフェストとスクリプトから解析され、起動前に不足している依存関係を準備できます。
- ネイティブ WeChat ミニプログラムは Shell の起動コマンドを使わず、WeChat DevTools CLI で開閉します。
- Android 配布では、APK を選択し、接続済みデバイスを見つけ、ADB でインストールして出力を確認できます。

## 主な画面

<table>
  <tr>
    <td width="32%">
      <strong>プロジェクト、Git、サーバー</strong><br><br>
      現在のブランチと未コミットのファイルを表示し、作業ツリーがクリーンならブランチを切り替えられます。サービスの開始、停止、再起動もできます。Techne は管理済みの Node、Bun、Deno プロジェクトに関連するローカル待受サービスを検出します。
    </td>
    <td width="68%"><img src="images/readme/development-environment.png" alt="Techne のプロジェクトとサーバーの状態"></td>
  </tr>
  <tr>
    <td>
      <strong>WeChat ミニプログラム</strong><br><br>
      リポジトリで宣言された Taro、UniApp、Mpx の開発スクリプトを実行するほか、ネイティブミニプログラムを WeChat DevTools で開けます。追加したページが認識されない場合は、DevTools のファイル監視を再構築できます。
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

1. Techne を開き、ローカルプロジェクトを明示的に追加します。開発サービスまたは WeChat ミニプログラムを選びます。
2. Techne は実際のマニフェスト、スクリプト、パッケージマネージャー情報、ロックファイルを読み取ります。実行可能なプロジェクトを特定できない場合、コマンドを推測せず追加を拒否します。
3. プロジェクトを起動します。npm、pnpm、Yarn、Bun の依存関係がなければ自動導入し、後でマニフェストやロックファイルが変われば再度準備します。コマンドは設定済みの zsh、Bash、fish の login shell で実行します。
4. 必要に応じて停止または再起動します。通常の停止と再起動ではビルドキャッシュを消去せず、管理対象ブラウザも閉じません。
5. Web プロジェクトでは、検出されたサーバーをインストール済みブラウザで開けます。
6. Android 配布画面ではデバイスを接続し、APK を選んで配布します。

メインウインドウを閉じても、プロジェクトはメニューバーで実行を継続します。ステータスメニューから「Techne を終了」を選ぶと、管理対象のプロジェクトプロセスを安全に停止してから終了します。Techne の起動時には存続している Shell プロジェクトの状態を復元し、開始操作では同じプロジェクトディレクトリの既存プロセスグループを先に置き換えて重複実行を防ぎます。

### 言語

Techne は英語、簡体字中国語、繁体字中国語に対応し、初期設定では macOS の言語に従います。「設定 > 一般」で言語を指定し、案内に従って Techne を再起動すると変更が反映されます。

### ブラウザと独立プロファイル

インストール済みの Safari、Google Chrome、Chrome Beta、Chromium、Microsoft Edge、Brave、Arc を検出します。Safari は通常どおり URL を開きます。Chrome、Chrome Beta、Chromium、Edge、Brave、Arc は Chromium ベースです。管理対象の各インスタンスは別のプロファイルディレクトリと新しいウインドウで起動し、`9222` から利用可能なリモートデバッグポートを割り当てます。普段使いのブラウザや別の管理対象インスタンスの Cookie とサイトデータは共有しません。

### Web と WeChat ミニプログラム

Shell ベースのプロジェクトでは、Techne はリポジトリで実際に宣言されたスクリプトだけを実行します。一般的な Web 開発スクリプトと、Taro、UniApp、Mpx の WeChat ターゲットを認識し、npm、pnpm、Yarn、Bun に対応します。依存関係は検出した workspace ルートで導入し、開発コマンドは選択したプロジェクトディレクトリで実行します。

ルートに有効な `project.config.json` があるネイティブミニプログラムは、インストール済み WeChat DevTools の CLI で開閉し、ファイル監視を復旧します。ビルド型ミニプログラムも、DevTools 用プロジェクトディレクトリが生成された後はそれを使ってファイル監視を復旧します。Techne に Node.js、パッケージマネージャー、フレームワーク CLI、WeChat DevTools は同梱されません。必要なランタイムとツールはインストールし、login shell から利用できるようにしてください。

### Android APK 配布

Android SDK Platform-Tools を導入して `adb` を `PATH` から使えるようにし、USB デバッグを有効にした Android デバイスを接続してください。Android SDK Build Tools も必要です。Techne は `aapt2` または `aapt` で APK のパッケージ名を読み取ります。まず `PATH`、次に `~/Library/Android/sdk/build-tools` を検索します。

## 動作条件

| 項目 | 条件 |
|---|---|
| macOS | macOS 26 Tahoe 以降 |
| ハードウェア | 公開 DMG は Apple Silicon のみ |
| Git 操作 | 状態とブランチ操作用の `git` が `PATH` にあること |
| 管理済みサーバーの関連付け | macOS の `lsof`。Techne は TCP の待受ポート 3000–9999 を走査し、追加済みプロジェクトだけに関連付ける |
| ブラウザ起動 | 対応ブラウザが一つ以上インストール済み |
| Web とビルド型ミニプログラム | Node.js、使用するパッケージマネージャー、フレームワークツールが login shell から利用可能。依存関係自体は Techne で準備可能 |
| ネイティブ WeChat ミニプログラム | WeChat DevTools がインストール済みで、アプリケーションバンドル内に CLI があること |
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
