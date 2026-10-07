# WhisperFly

> 🇬🇧 [English](#english) · 🇷🇺 [Русский](#русский)

---

## English

A macOS menu-bar push-to-talk dictation app with **free** cloud-based speech recognition.  
Fork of [qwenwishper](https://github.com/hukopo/qwenwishper) — replaces all local model inference with lightweight API calls.

### What's new in 2.1

- **Permissions that stick** — every build is signed with a stable designated requirement anchored to the developer team, so Microphone, Screen Recording and Accessibility survive updates and reinstalls. The new **Settings → Permissions** tab shows live status per permission, diagnoses your code signature in plain language, and offers a one-click **Reset and Relaunch** for the stale-TCC-row case that toggling cannot fix.
- **In-app updates by commit** — WhisperFly compares its stamped commit against the tracked GitHub branch and can update itself: download the release DMG and swap the bundle in place, or `git pull` and rebuild a source checkout. Configurable repository, branch, token and check interval in **Settings → Updates**.
- **Settings that never reset themselves** — a failed decode used to wipe all preferences (API keys included). Settings and history now decode field-by-field with defaults, bounds re-clamping and legacy-value migration, and an unreadable blob is backed up rather than destroyed.
- **Correct multi-display behaviour** — the status pill follows the caret on any display, result/history windows open on the display you are working on.
- **Working hotkey presets** — the shortcut picker now actually changes the registered global hotkey.

### What's new in 2.0

- **System audio capture** — transcribe anything playing on your Mac, not just the microphone
- **File transcription** — drop any audio or video file and get text on the clipboard
- **Transcription history** — every result is saved and browsable in a floating history panel
- **Result window** — system audio and file transcriptions open in a dedicated HUD window
- **macOS 26 (Tahoe) fixes** — panel lifecycle crash resolved, SCStream false-negative permission workaround, silent-audio dropout detection
- **Hotkey parity** — ⌘⇧Space starts and stops recording in both Microphone and System Audio modes

### Features

- **Push-to-talk** via ⌘⇧Space global hotkey
- **Two audio sources:**
  - 🎙 **Microphone** — records your voice and types the result into the focused app
  - 🔊 **System Audio** — captures everything playing on the Mac via ScreenCaptureKit
- **Two free transcription backends:**
  - 🟢 **Groq Whisper Large V3** — dedicated ASR, 100+ languages including Russian
  - 🟢 **Google Gemini 2.5 Flash** (via OpenRouter) — multimodal, free tier
- **File transcription** — transcribe any MP3, M4A, WAV, FLAC, MP4, MOV, and more
- **AI text rewriting** — cleanup, punctuation fix, or translate-to-English via Gemini
- **Read aloud** — optionally speak back the transcribed text using the system TTS voice
- **Auto-paste** into the focused app (Accessibility API with clipboard fallback)
- **Transcription history** — browse, copy, and re-open any past result
- **In-app updater** — check against GitHub commits and install release DMGs or rebuild from source without leaving the app
- **Permission center** — live status, signature diagnosis and one-click TCC repair
- **Localized UI** — English, Russian, German, French, Spanish, Japanese, Chinese, Korean, Italian, Hindi
- No local model downloads, no GPU required

### Install

**Option 1 — Homebrew (recommended):**
```bash
brew tap dandysuper/tap
brew install --cask whisperfly
```

To update later:
```bash
brew update && brew upgrade --cask whisperfly
```

**Option 2 — Download DMG:**  
Grab `WhisperFly.dmg` from the [latest release](https://github.com/dandysuper/WhisperFly/releases/latest), open it, and drag the app to `/Applications`.

**Option 3 — Build from source:**
```bash
git clone https://github.com/dandysuper/WhisperFly.git
cd WhisperFly
./scripts/build-app.sh   # assemble + stamp + sign WhisperFly.app
open WhisperFly.app
```

A plain `swift run WhisperFly` also works for development, but produces an
unstamped, ad-hoc-signed build — the updater and permission-persistence
guarantees need the packaged app. Run tests with `scripts/test.sh`.

### Configure

1. Get free API keys:
   - Groq: [console.groq.com](https://console.groq.com) → API Keys
   - OpenRouter: [openrouter.ai/keys](https://openrouter.ai/keys)

2. Open **Settings → API Keys** in the app and paste them in.

   *(Building from source? Create `.env` in the project root instead:*
   ```
   GROQ_API_KEY=gsk_xxx
   OPENROUTER_API_KEY=sk-or-v1-xxx
   ```
   *)*

3. Grant permissions when prompted — **Microphone**, **Screen Recording** (for system audio), and **Accessibility** (for text injection).

### Usage

| Action | Result |
|---|---|
| Press **⌘⇧Space** | Start recording (mic or system audio, whichever is selected) |
| Press **⌘⇧Space** again | Stop and transcribe |
| Click **Transcribe File…** | Pick an audio/video file — result goes to clipboard |
| Click **History** | Browse all past transcriptions |
| Switch source in menu | Toggle between Microphone and System Audio |
| Click menu bar icon | See status, last result, settings |
| **Settings → General** | Backend, language, rewrite mode, read-aloud |
| **Settings → API Keys** | Enter Groq / OpenRouter keys |
| **Settings → Advanced** | Max recording duration and paste delay |
| **Settings → Permissions** | Live permission status, signature diagnosis, reset & relaunch |
| **Settings → Updates** | Check for newer commits now or automatically; install DMG or rebuild from source |

### Permissions

| Permission | Required for |
|---|---|
| Microphone | Voice recording |
| Screen Recording | System audio capture via ScreenCaptureKit |
| Accessibility | Typing transcribed text into other apps |

WhisperFly asks macOS for each permission the first time it needs it and shows
the current state of all three in **Settings → Permissions**. If System
Settings shows a permission as enabled but WhisperFly still cannot use it —
the usual result of running a build signed differently — use **Reset
Permissions → Reset and Relaunch** in the same tab: it clears the stale grant
rows with `tccutil` and restarts the app so macOS asks again cleanly.

### Requirements

- macOS 14 (Sonoma) or later
- Swift 6 toolchain (build from source only)
- Internet connection (all recognition is done via API)

### macOS 26 (Tahoe) notes

ScreenCaptureKit has known issues on macOS 26 beta builds:

- **Silent audio dropouts** — SCStream may start successfully but deliver zero-valued samples. WhisperFly detects this and notifies you immediately with remediation steps (quit other screen-recording apps, toggle the source off/on, or restart the app).
- **Permission false negatives** — `CGPreflightScreenCaptureAccess` can return `false` even when permission is granted. WhisperFly works around this by letting the actual `SCShareableContent` API call be the authoritative check, so recording proceeds even when the preflight says no.
- **Panel lifecycle crash** — the floating status pill no longer crashes with `EXC_BREAKPOINT` on `_postWindowNeedsUpdateConstraints` when dismissed. The NSPanel is kept alive and only hidden, never released mid-layout.

### Removing macOS Quarantine (xattr)

> **Not needed if you installed via Homebrew** — Homebrew removes the quarantine flag automatically.

If you installed manually from the DMG and see an **"app is damaged"** or Gatekeeper warning, run:

```bash
xattr -cr /Applications/WhisperFly.app
```

### Reinstalling / Updating

**From inside the app (recommended):** open **Settings → Updates** and click
**Check Now**. If the tracked branch has a newer commit, **Update Now** either
downloads the release disk image and swaps the installed app in place, or pulls
and rebuilds a source checkout — then relaunches. Enable *Check automatically*
to have this happen in the background.

**Via Homebrew:**
```bash
brew update && brew upgrade --cask whisperfly
```

Both paths replace the bundle without touching your permissions: current
WhisperFly builds are signed with a stable designated requirement anchored to
the developer team, so macOS keeps recognising new versions as the same app as
long as the bundle identifier and team stay the same.

If you are coming from an older build that was signed differently, macOS may
still treat it as a different app once. Run **Settings → Permissions → Reset
and Relaunch** — WhisperFly clears its own stale grant rows and reopens, and
you grant the permissions again. The manual equivalent, if you prefer System
Settings:

1. Quit WhisperFly.
2. Install the new version.
3. Open **System Settings → Privacy & Security** and remove WhisperFly from the
   Microphone, Screen Recording and Accessibility lists (**−**).
4. Launch WhisperFly and grant the permissions again when prompted.

### Architecture

```
Sources/WhisperFly/
├── App/
│   ├── AppController.swift             # Main pipeline: record → transcribe → rewrite → paste → TTS
│   ├── FloatingPanel.swift             # Floating status pill near the caret (any display)
│   ├── HistoryPanel.swift              # Transcription history window
│   ├── TranscriptionResultPanel.swift  # Single result HUD window
│   └── WhisperFlyApp.swift             # SwiftUI entry point / menu bar extra
├── Core/
│   ├── BuildInfo.swift                 # Stamped build metadata (commit, version, repo)
│   ├── CodeSignatureInfo.swift         # Reads own code signature / designated requirement
│   ├── LocalState.swift                # @State replacement for CLT-only toolchains
│   ├── PermissionKind.swift            # Microphone / Screen Recording / Accessibility model
│   ├── PermissionState.swift           # granted / denied / notDetermined / restricted / unknown
│   ├── PipelineStatus.swift            # Enum: idle / recording / transcribing / rewriting / pasting / error
│   ├── Protocols.swift                 # SpeechRecognizer, TextRewriter, TextInjector, …
│   ├── ScreenPlacement.swift           # Multi-display placement & AX coordinate conversion
│   ├── UpdateModels.swift              # Update status / install-phase models
│   └── L10n.swift                      # Localization helper
├── Models/
│   ├── AppSettings.swift               # Hand-written Codable settings with legacy migration
│   ├── AppSettingsTypes.swift          # AudioSource / backend / hotkey presets
│   ├── SettingsStore.swift             # Decode-resilient persistence + .env fallback
│   └── TranscriptionHistory.swift      # Lossy-decoded history store
├── Resources/
│   └── *.lproj/Localizable.strings     # en, ru, de, fr, es, ja, zh, ko, it, hi
├── Services/
│   ├── AudioCaptureService.swift       # Microphone recording
│   ├── SystemAudioCaptureService.swift # System audio via ScreenCaptureKit
│   ├── AudioConverter.swift            # CAF → 16 kHz WAV conversion
│   ├── ClipboardWriter.swift           # NSPasteboard helper
│   ├── GeminiRewriter.swift            # AI text rewriting via OpenRouter
│   ├── GeminiTranscriber.swift         # Gemini transcription backend
│   ├── GitHubClient.swift              # GitHub REST: branch head, releases, compare
│   ├── GroqWhisperRecognizer.swift     # Groq Whisper transcription backend
│   ├── HotkeyMonitor.swift             # Global hotkey (Carbon), preset-driven
│   ├── PasteService.swift              # Text injection (Accessibility API + clipboard fallback)
│   ├── PermissionRepair.swift          # tccutil reset + safe relaunch
│   ├── PermissionService.swift         # Single permission probing authority
│   ├── UpdateDownloader.swift          # Streaming DMG download with progress
│   ├── UpdateInstaller.swift           # Verified in-place bundle replacement / source rebuild
│   └── UpdateService.swift             # Commit-based update state machine
└── Views/
    ├── FloatingStatusView.swift
    ├── HistoryView.swift
    ├── MenuBarContentView.swift
    ├── PermissionRow.swift
    ├── PermissionsView.swift
    ├── SettingsView.swift
    ├── TranscriptionResultView.swift
    └── UpdatesView.swift
```

Build and release tooling lives in `scripts/`: `build-app.sh` (assemble, stamp,
sign), `build-dev.sh` (debug rebuild of the local bundle), `sign-app.sh`
(stable designated requirement), `release.sh` (DMG + GitHub release + tap) and
`test.sh`. A deeper write-up of the permission and updater work is in
[docs/permissions-audit.md](docs/permissions-audit.md).

---

## Русский

Приложение для macOS — диктовка нажатием клавиши с **бесплатным** облачным распознаванием речи.  
Форк [qwenwishper](https://github.com/hukopo/qwenwishper) — вся локальная модельная инференция заменена лёгкими API-вызовами.

### Что нового в 2.1

- **Разрешения, которые больше не сбрасываются** — каждая сборка подписывается со стабильным designated requirement, привязанным к команде разработчика, поэтому Микрофон, Захват экрана и Специальные возможности переживают обновления и переустановки. Новая вкладка **Настройки → Разрешения** показывает живой статус по каждому разрешению, объясняет состояние кодовой подписи простым языком и даёт кнопку **Сбросить и перезапустить** для случая устаревших строк TCC, который переключателями не лечится.
- **Обновления по коммитам из приложения** — WhisperFly сравнивает свой зафиксированный коммит с отслеживаемой веткой GitHub и умеет обновлять себя: скачать релизный DMG и заменить бандл на месте либо сделать `git pull` и пересобрать исходники. Репозиторий, ветка, токен и период проверки настраиваются в **Настройки → Обновления**.
- **Настройки больше не сбрасываются сами** — раньше неудачное декодирование стирало все настройки (включая API-ключи). Теперь настройки и история декодируются по полям с значениями по умолчанию, повторным ограничением диапазонов и миграцией старых значений, а нечитаемый файл резервируется, а не уничтожается.
- **Корректная работа с несколькими мониторами** — индикатор записи следует за курсором на любом дисплее, окна результата и истории открываются на том дисплее, где вы работаете.
- **Рабочие пресеты горячей клавиши** — выбор сочетания теперь действительно меняет зарегистрированный глобальный шорткат.

### Что нового в 2.0

- **Захват системного звука** — транскрибируйте всё, что звучит на Mac, а не только микрофон
- **Транскрипция файлов** — откройте любой аудио/видеофайл и получите текст в буфере обмена
- **История транскрипций** — все результаты сохраняются и доступны в плавающей панели истории
- **Окно результата** — системный звук и файлы открывают результат в отдельном HUD-окне
- **Исправления для macOS 26 (Tahoe)** — устранён крэш панели, обход ложных отказов прав ScreenCaptureKit, детектирование тихой записи
- **Единая горячая клавиша** — ⌘⇧Space запускает и останавливает запись в обоих режимах: микрофон и системный звук

### Возможности

- **Запись нажатием клавиши** через глобальное сочетание ⌘⇧Space
- **Два источника звука:**
  - 🎙 **Микрофон** — записывает голос и вставляет текст в активное поле ввода
  - 🔊 **Системный звук** — захватывает всё, что играет на Mac, через ScreenCaptureKit
- **Два бесплатных бэкенда транскрипции:**
  - 🟢 **Groq Whisper Large V3** — специализированный ASR, 100+ языков, включая русский
  - 🟢 **Google Gemini 2.5 Flash** (через OpenRouter) — мультимодальный, бесплатный тариф
- **Транскрипция файлов** — MP3, M4A, WAV, FLAC, MP4, MOV и другие форматы
- **AI-переформулировка текста** — исправление, пунктуация или перевод на английский через Gemini
- **Прочитать вслух** — озвучить распознанный текст системным голосом TTS
- **Автовставка** в активное поле ввода (Accessibility API, при неудаче — через буфер обмена)
- **История транскрипций** — просматривайте, копируйте и заново открывайте любой прошлый результат
- **Обновление из приложения** — проверка по коммитам GitHub и установка релизного DMG или пересборка из исходников, не выходя из приложения
- **Центр разрешений** — живой статус, диагностика подписи и сброс TCC в один клик
- **Локализованный интерфейс** — английский, русский, немецкий, французский, испанский, японский, китайский, корейский, итальянский, хинди
- Не требует загрузки локальных моделей и GPU

### Установка

**Вариант 1 — Homebrew (рекомендуется):**
```bash
brew tap dandysuper/tap
brew install --cask whisperfly
```

Для обновления:
```bash
brew update && brew upgrade --cask whisperfly
```

**Вариант 2 — Скачать DMG:**  
Скачайте `WhisperFly.dmg` с [последнего релиза](https://github.com/dandysuper/WhisperFly/releases/latest), откройте и перетащите приложение в `/Applications`.

**Вариант 3 — Собрать из исходников:**
```bash
git clone https://github.com/dandysuper/WhisperFly.git
cd WhisperFly
./scripts/build-app.sh   # сборка + метаданные + подпись WhisperFly.app
open WhisperFly.app
```

Простой `swift run WhisperFly` тоже работает для разработки, но даёт сборку без
метаданных и с ad-hoc подписью — самостоятельное обновление и сохранность
разрешений гарантируются только для упакованного приложения.
Тесты запускаются через `scripts/test.sh`.

### Настройка

1. Получите бесплатные API-ключи:
   - Groq: [console.groq.com](https://console.groq.com) → API Keys
   - OpenRouter: [openrouter.ai/keys](https://openrouter.ai/keys)

2. Откройте **Настройки → API-ключи** в приложении и вставьте их.

   *(При сборке из исходников создайте `.env` в корне проекта:*
   ```
   GROQ_API_KEY=gsk_xxx
   OPENROUTER_API_KEY=sk-or-v1-xxx
   ```
   *)*

3. Разрешите доступ при запросе — **Микрофон**, **Захват экрана** (для системного звука) и **Специальные возможности** (для вставки текста).

### Использование

| Действие | Результат |
|---|---|
| Нажать **⌘⇧Space** | Начать запись (микрофон или системный звук — в зависимости от выбора) |
| Нажать **⌘⇧Space** ещё раз | Остановить и транскрибировать |
| Нажать **Transcribe File…** | Выбрать аудио/видеофайл — результат идёт в буфер обмена |
| Нажать **History** | История всех транскрипций |
| Переключить источник в меню | Переключиться между микрофоном и системным звуком |
| Кликнуть иконку в строке меню | Статус, последний результат, настройки |
| **Настройки → Основные** | Бэкенд, язык, режим переформулировки, чтение вслух |
| **Настройки → API-ключи** | Ввести ключи Groq / OpenRouter |
| **Настройки → Дополнительно** | Макс. длительность записи и задержка вставки |
| **Настройки → Разрешения** | Живой статус разрешений, диагностика подписи, сброс и перезапуск |
| **Настройки → Обновления** | Проверка новых коммитов вручную или автоматически; установка DMG или пересборка из исходников |

### Разрешения

| Разрешение | Для чего |
|---|---|
| Микрофон | Запись голоса |
| Захват экрана | Захват системного звука через ScreenCaptureKit |
| Специальные возможности | Ввод текста в другие приложения |

WhisperFly запрашивает каждое разрешение, когда оно впервые понадобится, и
показывает статус всех трёх во вкладке **Настройки → Разрешения**. Если в
Системных настройках разрешение включено, но WhisperFly им всё равно не может
воспользоваться (обычное последствие сборки с другой подписью), используйте
**Сброс разрешений → Сбросить и перезапустить** там же: приложение очистит
устаревшие строки TCC через `tccutil` и перезапустится, чтобы macOS запросил
доступ заново.

### Требования

- macOS 14 (Sonoma) или новее
- Инструментарий Swift 6 (только при сборке из исходников)
- Подключение к интернету (распознавание выполняется через API)

### Заметки для macOS 26 (Tahoe)

В бета-версиях macOS 26 у ScreenCaptureKit есть известные проблемы:

- **Тихие выпадения звука** — SCStream может запуститься, но отдавать нулевые сэмплы. WhisperFly определяет это и сразу уведомляет вас с советами по устранению (закройте другие приложения записи экрана, переключите источник звука туда-обратно или перезапустите приложение).
- **Ложные отказы в разрешениях** — `CGPreflightScreenCaptureAccess` может возвращать `false`, даже когда доступ разрешён. WhisperFly обходит это, используя реальный вызов `SCShareableContent` как авторитетную проверку, и не блокирует запись на основе префлайта.
- **Крэш жизненного цикла панели** — плавающая статусная таблетка больше не падает с `EXC_BREAKPOINT` при скрытии. NSPanel сохраняется в памяти и только скрывается через `orderOut`, не освобождаясь в середине layout-прохода.

### Снятие карантина macOS (xattr)

> **Не нужно при установке через Homebrew** — Homebrew снимает флаг карантина автоматически.

Если вы установили приложение вручную из DMG и видите предупреждение **«приложение повреждено»** или от Gatekeeper, выполните:

```bash
xattr -cr /Applications/WhisperFly.app
```

### Переустановка / Обновление

**Изнутри приложения (рекомендуется):** откройте **Настройки → Обновления** и
нажмите **Проверить сейчас**. Если в отслеживаемой ветке появился более новый
коммит, кнопка **Обновить сейчас** либо скачает релизный образ диска и заменит
установленное приложение, либо подтянет и пересоберёт исходники — после чего
перезапустит приложение. Включите «Проверять автоматически», чтобы это
происходило само.

**Через Homebrew:**
```bash
brew update && brew upgrade --cask whisperfly
```

Оба способа заменяют бандл, не трогая разрешения: сборки WhisperFly
подписываются со стабильным designated requirement, привязанным к команде
разработчика, поэтому macOS продолжает считать новые версии тем же приложением,
пока не меняются bundle identifier и команда.

Если вы приходите со старой сборки с иной подписью, macOS может один раз
посчитать её другим приложением. Запустите **Настройки → Разрешения → Сбросить
и перезапустить** — WhisperFly сам очистит устаревшие строки доступов и
откроется заново, после чего выдайте разрешения ещё раз. Ручной вариант через
Системные настройки, если так привычнее:

1. Закройте WhisperFly.
2. Установите новую версию.
3. Откройте **Системные настройки → Конфиденциальность и безопасность** и
   удалите WhisperFly из списков Микрофона, Захвата экрана и Специальных
   возможностей (**−**).
4. Запустите WhisperFly и выдайте разрешения при запросе.

### Архитектура

```
Sources/WhisperFly/
├── App/
│   ├── AppController.swift             # Главный координатор: запись → транскрипция → переформулировка → вставка → TTS
│   ├── FloatingPanel.swift             # Плавающая таблетка статуса рядом с курсором (любой дисплей)
│   ├── HistoryPanel.swift              # Окно истории транскрипций
│   ├── TranscriptionResultPanel.swift  # HUD-окно отдельного результата
│   └── WhisperFlyApp.swift             # Точка входа SwiftUI / элемент строки меню
├── Core/
│   ├── BuildInfo.swift                 # Метаданные сборки (коммит, версия, репозиторий)
│   ├── CodeSignatureInfo.swift         # Чтение собственной подписи / designated requirement
│   ├── LocalState.swift                # Замена @State для тулчейна без полного Xcode
│   ├── PermissionKind.swift            # Модель Микрофон / Захват экрана / Спец. возможности
│   ├── PermissionState.swift           # granted / denied / notDetermined / restricted / unknown
│   ├── PipelineStatus.swift            # Enum: idle / recording / transcribing / rewriting / pasting / error
│   ├── Protocols.swift                 # SpeechRecognizer, TextRewriter, TextInjector, …
│   ├── ScreenPlacement.swift           # Расположение панелей на нескольких дисплеях
│   ├── UpdateModels.swift              # Модели статуса и фаз обновления
│   └── L10n.swift                      # Вспомогательный модуль локализации
├── Models/
│   ├── AppSettings.swift               # Настройки с ручным Codable и миграцией старых значений
│   ├── AppSettingsTypes.swift          # AudioSource / бэкенды / пресеты горячих клавиш
│   ├── SettingsStore.swift             # Устойчивое к сбоям декодирования хранилище + .env
│   └── TranscriptionHistory.swift      # История с побайтово устойчивым декодированием
├── Resources/
│   └── *.lproj/Localizable.strings     # en, ru, de, fr, es, ja, zh, ko, it, hi
├── Services/
│   ├── AudioCaptureService.swift       # Запись с микрофона
│   ├── SystemAudioCaptureService.swift # Системный звук через ScreenCaptureKit
│   ├── AudioConverter.swift            # Конвертация CAF → WAV 16 кГц
│   ├── ClipboardWriter.swift           # Работа с NSPasteboard
│   ├── GeminiRewriter.swift            # AI-переформулировка через OpenRouter
│   ├── GeminiTranscriber.swift         # Бэкенд транскрипции Gemini
│   ├── GitHubClient.swift              # GitHub REST: ветка, релизы, сравнение коммитов
│   ├── GroqWhisperRecognizer.swift     # Бэкенд транскрипции Groq Whisper
│   ├── HotkeyMonitor.swift             # Глобальная клавиша (Carbon) по пресету
│   ├── PasteService.swift              # Вставка текста (Accessibility API + буфер обмена)
│   ├── PermissionRepair.swift          # tccutil reset + безопасный перезапуск
│   ├── PermissionService.swift         # Единый источник проверки разрешений
│   ├── UpdateDownloader.swift          # Потоковая загрузка DMG с прогрессом
│   ├── UpdateInstaller.swift           # Проверенная замена бандла / пересборка из исходников
│   └── UpdateService.swift             # Машина состояний обновления по коммитам
└── Views/
    ├── FloatingStatusView.swift
    ├── HistoryView.swift
    ├── MenuBarContentView.swift
    ├── PermissionRow.swift
    ├── PermissionsView.swift
    ├── SettingsView.swift
    ├── TranscriptionResultView.swift
    └── UpdatesView.swift
```

Инструменты сборки и релиза живут в `scripts/`: `build-app.sh` (сборка, метаданные,
подпись), `build-dev.sh` (отладочная пересборка локального бандла),
`sign-app.sh` (стабильный designated requirement), `release.sh` (DMG + релиз на
GitHub + tap) и `test.sh`. Подробный разбор работы с разрешениями и
обновлениями — в [docs/permissions-audit.md](docs/permissions-audit.md).
