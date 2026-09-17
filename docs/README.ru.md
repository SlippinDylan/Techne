<div align="center">
  <img src="images/readme/app-icon.png" width="160" height="160" alt="Значок приложения Techne">
  <h1>Techne</h1>
</div>

---

<div align="center">
  <p>Нативное приложение macOS, в котором собраны локальные проекты, dev-серверы, команды для мини-приложений WeChat и развёртывание Android APK.</p>
  <p>
    <a href="README.zh-CN.md">简体中文</a> ·
    <a href="README.zh-TW.md">繁體中文</a> ·
    <a href="../README.md">English</a> ·
    <a href="README.ja.md">日本語</a> ·
    <strong>Русский</strong>
  </p>
</div>

## Что делает Techne

Techne предназначен для разработчиков, которые постоянно возвращаются к одним и тем же локальным проектам. Добавьте проект один раз, а затем проверяйте ветку Git и рабочее дерево, запускайте его команды, находите слушающие dev-серверы или открывайте сервер в браузере.

В приложении есть и два отдельных сценария:

- Для мини-приложений WeChat можно настроить команды установки зависимостей, запуска, сборки, очистки и остановки.
- В Android-развёртывании можно выбрать APK, найти подключённое устройство, установить APK через ADB и посмотреть вывод команд.

## В приложении

<table>
  <tr>
    <td width="32%">
      <strong>Проекты, Git и серверы</strong><br><br>
      Текущая ветка и незакоммиченные файлы видны сразу; ветку можно сменить, когда рабочее дерево чистое. Сервисы запускаются и останавливаются по настройке проекта. Techne находит локальные слушающие сервисы, связанные с процессами Node, Bun или Deno.
    </td>
    <td width="68%"><img src="images/readme/development-environment.png" alt="Состояние проектов и серверов в Techne"></td>
  </tr>
  <tr>
    <td>
      <strong>Мини-приложения WeChat</strong><br><br>
      Команды сохраняются для каждого проекта, а не привязаны к одной системе сборки. Встроенные шаблоны содержат примеры npm и pnpm для WeChat.
    </td>
    <td><img src="images/readme/mini-program-build.png" alt="Рабочее место сборки мини-приложения WeChat в Techne"></td>
  </tr>
  <tr>
    <td>
      <strong>Развёртывание Android APK</strong><br><br>
      Выберите APK и подключённое Android-устройство. Techne читает имя пакета, переустанавливает APK через ADB, сверяет время обновления пакета и запускает приложение.
    </td>
    <td><img src="images/readme/android-deployment.png" alt="Развёртывание Android APK в Techne"></td>
  </tr>
</table>

## Установка

### Homebrew

```bash
brew tap slippindylan/tap
brew trust --tap slippindylan/tap
brew install --cask techne@beta
```

### DMG

Скачайте DMG со страницы [Techne Releases](https://github.com/SlippinDylan/Techne/releases), откройте его и перетащите `Techne.app` в `Applications`. Опубликованные DMG предназначены для Mac с Apple Silicon.

Текущие релизы подписаны сертификатом Apple Development, но не нотариально заверены Apple. Поэтому macOS может заблокировать первый запуск или сообщить, что разработчика невозможно проверить. Если DMG получен с официальной страницы Releases, приложение перенесено в `Applications` и вы решили продолжить, снимите атрибут карантина:

```bash
sudo xattr -rd com.apple.quarantine /Applications/Techne.app
```

## Быстрый старт

1. Откройте Techne, добавьте локальный проект и выберите проект с dev-сервисом или мини-приложение WeChat.
2. Выберите шаблон команд либо укажите команды, которые уже работают в этом проекте. Techne запускает их в каталоге проекта через Bash, запущенный как login shell.
3. Для Web-проекта запустите сервис, обновите среду разработки и откройте найденный сервер в установленном браузере.
4. Для Android откройте экран развёртывания, подключите устройство, выберите APK и запустите развёртывание.

### Браузеры и отдельные профили

Techne обнаруживает установленные Safari, Google Chrome, Chrome Beta, Chromium, Microsoft Edge, Brave и Arc. Safari открывает адрес обычным способом. Chrome, Chrome Beta, Chromium, Edge, Brave и Arc основаны на Chromium: для каждого управляемого экземпляра Techne создаёт отдельный каталог профиля, новое окно и назначает свободный порт удалённой отладки, начиная с `9222`. Файлы cookie и данные сайтов не смешиваются с обычным профилем браузера или другими управляемыми экземплярами.

### Команды мини-приложений WeChat

Techne не включает инструменты для мини-приложений. Сначала установите зависимости проекта, затем задайте команды, которые работают в этом репозитории. Встроенные примеры:

```bash
npm run dev:mp-weixin
npm run build:mp-weixin
pnpm dev:mp-weixin
pnpm build:mp-weixin
```

Их можно заменить собственными командами npm, pnpm или другими shell-командами. Нужный менеджер пакетов и инструменты проекта должны быть доступны в `PATH` login shell.

### Развёртывание Android APK

Установите Android SDK Platform-Tools, чтобы `adb` был доступен в `PATH`, подключите Android-устройство с включённой USB-отладкой и установите Android SDK Build Tools. Techne использует `aapt2` или `aapt` для чтения имени пакета APK: сначала ищет в `PATH`, затем в `~/Library/Android/sdk/build-tools`.

## Требования

| Что нужно | Подробнее |
|---|---|
| macOS | macOS 26 Tahoe или новее |
| Оборудование | Опубликованный DMG только для Apple Silicon |
| Работа с Git | `git` в `PATH` для статуса и операций с ветками |
| Поиск dev-серверов | Системный `lsof`; Techne сканирует слушающие TCP-порты 3000–9999 |
| Запуск браузера | Хотя бы один поддерживаемый установленный браузер |
| Команды проекта и мини-приложения | Зависимости проекта и CLI-инструменты доступны из login shell |
| Android-развёртывание | `adb`, Android SDK Build Tools (`aapt2` или `aapt`) и устройство с включённой USB-отладкой |

## Где хранятся данные

Записи проектов, настройки команд и журналы хранятся в:

```bash
~/Library/Application Support/studio.slippindylan.Techne/
```

Profile и файлы отслеживания управляемых экземпляров Chromium хранятся в:

```bash
~/.techne-browsers/
```

## Сборка из исходников

Нужны macOS 26 или новее и Xcode 26 или новее. Клонируйте репозиторий, откройте `Techne.xcodeproj` в Xcode и запустите схему `Techne`. В Terminal можно выполнить:

```bash
git clone https://github.com/SlippinDylan/Techne.git
cd Techne
xcodebuild -project Techne.xcodeproj -scheme Techne -configuration Debug build
```

Внешние инструменты выше нужны только для функций, которые их используют.

## Лицензия

Copyright © 2025–2026 SlippinDylan Studio. Techne распространяется по [Apache License 2.0](../LICENSE).
