# WhisperFly

> 🇬🇧 [English](#english) · 🇷🇺 [Русский](#русский)

---

## English

A macOS menu-bar dictation app with **free** cloud speech recognition. Hold **fn**,
speak, let go — polished text appears in whatever app you are typing in.
Fork of [qwenwishper](https://github.com/hukopo/qwenwishper) — replaces all local
model inference with lightweight API calls.

### What's new in 3.1

- **Runs on older Macs** — the minimum is now **macOS 13 Ventura** (was 14), and
  the app ships as a **universal binary**, native on both Intel and Apple silicon.
  That covers Intel Macs from 2017 onward.
- **Classic look** — on macOS 13–15 WhisperFly uses translucent materials in
  place of Liquid Glass. On macOS 26 you can choose the classic look in
  **Settings → Advanced → Appearance**, which can feel lighter on older Intel Macs.
- **Safe updates on old Macs** — before replacing the installed app, the updater
  checks that the new version supports this Mac's macOS and processor. A future
  release that drops Intel or an old macOS is refused instead of leaving you with
  an app that will not open.
- **Builds with Xcode 16** — building from source no longer needs the macOS 26 SDK;
  Liquid Glass is compiled in only when the SDK has it.
- **Fix:** every recording failed with "OSStatus error -39" in 3.0.

### What's new in 3.0

- **Liquid Glass design** (macOS 26) — floating pill with a live waveform, menu,
  settings, history and result windows.
- **fn-key dictation** — hold **fn** to talk and release to transcribe, or tap to
  start and stop. **Esc** cancels from any app. fn+Delete, fn+arrows and other
  fn shortcuts keep working.
- **New speech engines** — Groq **Whisper Large v3 Turbo** (free), Google
  **Gemini 3.5 Transcribe** called directly with an AI Studio key (free tier, with
  smart formatting), OpenRouter, and any **OpenAI-compatible** server, including
  a local whisper.cpp. When one engine fails or hits its limit, the next one you
  have a key for is tried.
- **AI rewrite modes** — Cleanup, Punctuate, Professional, Translate (into any
  language) and Custom instructions, through Groq, Gemini, OpenRouter or a custom
  server. A **custom vocabulary** keeps names and jargon spelled right.
- **Smoother flow** — welcome guide with key check, Retry after a failed dictation,
  silent recordings caught before upload, drag a file onto the menu to transcribe,
  searchable history with original and polished text, and "Open at login".

<details>
<summary>2.1 and 2.0</summary>

- **2.1** — permissions that survive updates (stable signing + Permissions tab with
  one-click reset), commit-based in-app updates, settings that never reset
  themselves, correct multi-display placement, working hotkey presets.
- **2.0** — system audio capture, file transcription, transcription history,
  result window, macOS 26 fixes.

</details>

### Features

- **Dictation into any app** with **fn** (or ⌘⇧Space and other chords for
  keyboards without fn)
- **Two audio sources:** 🎙 **Microphone** types into the focused app;
  🔊 **System Audio** captures everything playing on the Mac via ScreenCaptureKit
- **Speech engines:** Groq Whisper (free) · Gemini 3.5 Transcribe (free tier) ·
  OpenRouter · OpenAI-compatible servers — with automatic fallback
- **AI rewriting:** cleanup, punctuation, professional tone, translation, custom
  instructions; custom vocabulary
- **File transcription** — MP3, M4A, WAV, FLAC, OGG, MP4, MOV and more; drop a
  file on the menu
- **History** — search, copy, compare original and polished text, save as text
- **Read aloud**, sound cues, "Always paste" mode for apps that ignore
  Accessibility writes
- **In-app updater** and **permission center**
- **Localized UI** — English, Russian, German, French, Spanish, Japanese, Chinese,
  Korean, Italian, Hindi, Kazakh (new 3.x text is in English and Russian)
- No model downloads, no GPU required; Intel and Apple silicon

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
Grab `WhisperFly.dmg` from the [latest release](https://github.com/dandysuper/WhisperFly/releases/latest),
open it, and drag the app to `/Applications`. The same DMG works on Intel and
Apple silicon.

**Option 3 — Build from source:**
```bash
git clone https://github.com/dandysuper/WhisperFly.git
cd WhisperFly
./scripts/build-app.sh               # this Mac's architecture
./scripts/build-app.sh --universal   # Intel + Apple silicon
open WhisperFly.app
```

If the checkout lives in an iCloud-synced folder (Desktop or Documents) and the
build stops with `disk I/O error`, build outside it:
`WHISPERFLY_SCRATCH_PATH=/tmp/wf ./scripts/build-app.sh`.

A plain `swift run WhisperFly` also works for development, but produces an
unstamped, ad-hoc-signed build — the updater and permission-persistence
guarantees need the packaged app. Run tests with `scripts/test.sh`.

### Configure

On first launch the **welcome guide** walks you through it:

1. **Pick a free engine and paste its key.**
   - Groq: [console.groq.com/keys](https://console.groq.com/keys) — key starts with `gsk_`
   - Gemini: [aistudio.google.com/apikey](https://aistudio.google.com/apikey)

   One key covers both transcription and AI rewriting. Add the other later in
   **Settings → Speech Engines** to get automatic fallback.
2. **Grant permissions** — Microphone, Accessibility (typing text and seeing the
   fn key) and, only for system audio, Screen Recording.
3. **Try it** in the practice box.

**If fn opens the emoji picker or switches the input source:** open
**System Settings → Keyboard** and set **"Press 🌐 key to"** to **"Do Nothing"**.
WhisperFly shows a reminder with a button until you do.

*Building from source? A `.env` in the project root is read on first run:*
```
GROQ_API_KEY=gsk_xxx
GEMINI_API_KEY=AIza_xxx
OPENROUTER_API_KEY=sk-or-v1-xxx
```

### Usage

| Action | Result |
|---|---|
| Hold **fn**, speak, release | Dictate from the microphone into the focused app |
| Tap **fn**, speak, tap **fn** | Same, hands-free |
| **Esc** | Cancel recording or transcription |
| Menu → record button | Record from the selected source (microphone or system audio) |
| Menu → **File…**, or drop a file on the menu | Transcribe a file — result goes to the clipboard |
| Menu → **AI rewrite → Change** | Switch rewrite mode or turn it off |
| Menu → **History** | Browse, search and copy past results |
| **Settings → General** | Source, language, shortcut, hold-to-talk, insertion, sounds, login item |
| **Settings → Speech Engines** | Engine, model, keys, fallback, custom server |
| **Settings → AI Rewriting** | Mode, engine, translation target, instructions, vocabulary |
| **Settings → Permissions** | Live status, signature diagnosis, reset & relaunch |
| **Settings → Updates** | Check for newer commits; install DMG or rebuild from source |
| **Settings → Advanced** | Recording limit, paste delay, classic look, history |

### Permissions

| Permission | Required for |
|---|---|
| Microphone | Voice recording |
| Accessibility | Typing text into other apps, the fn shortcut, placing the pill at the caret |
| Screen Recording | System audio capture only |

If System Settings shows a permission as enabled but WhisperFly still cannot use
it — the usual result of running a build signed differently — use
**Settings → Permissions → Reset and Relaunch**: it clears the stale grant rows
with `tccutil` and restarts the app so macOS asks again cleanly.

### Requirements

- **macOS 13 Ventura or later**, Intel or Apple silicon
- Liquid Glass appears on macOS 26 and later; earlier systems get the classic look
- System audio capture: macOS 13 or later with Screen Recording permission
- fn dictation: built-in or Apple keyboards (most other keyboards handle fn
  internally — pick a key combination instead)
- Internet connection (recognition is done through APIs)
- Building from source: Swift 6 toolchain — Xcode 16 or later, or its Command Line
  Tools. Liquid Glass is included when built with Xcode 26 or later.

### macOS 26 (Tahoe) notes

ScreenCaptureKit has known issues on macOS 26:

- **Silent audio dropouts** — SCStream may start but deliver zero-valued samples.
  WhisperFly detects this and tells you how to recover (quit other screen-recording
  apps, toggle the source off and on, or restart the app).
- **Permission false negatives** — `CGPreflightScreenCaptureAccess` can return
  `false` even when permission is granted, so the actual `SCShareableContent` call
  is the authoritative check.
- **Panel lifecycle crash** — the floating pill is kept alive and only hidden, never
  released mid-layout.

### Removing macOS Quarantine (xattr)

> **Not needed if you installed via Homebrew.**

If you installed from the DMG and see an **"app is damaged"** or Gatekeeper warning:

```bash
xattr -cr /Applications/WhisperFly.app
```

### Updating

**From inside the app:** **Settings → Updates → Check Now**, then **Update Now**.
It either downloads the release disk image and swaps the installed app, or pulls
and rebuilds a source checkout, then relaunches. Before installing, it checks
that the new version supports your macOS and processor.

**Via Homebrew:** `brew update && brew upgrade --cask whisperfly`

Updates keep your permissions: builds are signed with a stable designated
requirement anchored to the developer team. Coming from a build signed
differently, run **Settings → Permissions → Reset and Relaunch** once.

### Architecture

```
Sources/WhisperFly/
├── App/
│   ├── AppController.swift             # Pipeline: record → transcribe (with fallback) → rewrite → insert
│   ├── FloatingPanel.swift             # Floating pill near the caret (any display)
│   ├── TranscriptionResultPanel.swift  # Glass result and history windows
│   ├── Windows.swift                   # Settings and welcome windows, settings sections
│   └── WhisperFlyApp.swift             # SwiftUI entry point / menu bar extra
├── Core/
│   ├── AudioMeter.swift                # Throttled level history for the waveform
│   ├── BuildInfo.swift                 # Stamped build metadata (commit, version, repo)
│   ├── CodeSignatureInfo.swift         # Own code signature / designated requirement
│   ├── Compatibility.swift             # macOS 13 shims, Mac info, update compatibility check
│   ├── LocalState.swift                # @State replacement for CLT-only toolchains
│   ├── PermissionKind.swift / PermissionState.swift
│   ├── PipelineStatus.swift            # idle / recording / transcribing / rewriting / pasting / done / error
│   ├── Protocols.swift                 # SpeechRecognizer, TextRewriter, RewriteMode, …
│   ├── ScreenPlacement.swift           # Multi-display placement & AX coordinates
│   ├── UpdateModels.swift              # Update status / install-phase models
│   └── L10n.swift                      # Localization helper
├── Models/
│   ├── AIProvider.swift                # Groq / Gemini / OpenRouter / custom, models
│   ├── AppSettings.swift               # Hand-written Codable settings with 2.x migration
│   ├── AppSettingsTypes.swift          # Audio source, insertion method, shortcut presets
│   ├── DictationLanguage.swift         # Languages and per-engine codes
│   ├── SettingsStore.swift             # Decode-resilient persistence + .env fallback
│   └── TranscriptionHistory.swift      # Lossy-decoded history store
├── Resources/                          # AppIcon, *.lproj/Localizable.strings
├── Services/
│   ├── Providers/                      # Groq, Gemini (Interactions API), OpenRouter, OpenAI-compatible,
│   │                                   # shared HTTP transport, errors, rewrite prompts
│   ├── AudioCaptureService.swift       # Microphone recording
│   ├── SystemAudioCaptureService.swift # System audio via ScreenCaptureKit
│   ├── AudioConverter.swift            # Streaming conversion to 16 kHz WAV / AAC, peak level
│   ├── FnKeyMonitor.swift              # fn-only shortcut, system fn-action check
│   ├── HotkeyMonitor.swift             # Carbon chord shortcuts and Esc
│   ├── PasteService.swift              # Accessibility insert + clipboard fallback
│   ├── ClipboardWriter.swift
│   ├── PermissionService.swift / PermissionRepair.swift
│   └── GitHubClient.swift / UpdateDownloader.swift / UpdateInstaller.swift / UpdateService.swift
└── Views/
    ├── Glass/LiquidGlass.swift         # Liquid Glass helpers with classic fallback (only file using glass APIs)
    ├── FloatingStatusView.swift, MenuBarContentView.swift, OnboardingView.swift
    ├── SettingsView.swift, ProvidersSettingsView.swift, RewritingSettingsView.swift
    └── HistoryView.swift, TranscriptionResultView.swift, PermissionsView.swift, PermissionRow.swift, UpdatesView.swift
```

Build and release tooling lives in `scripts/`: `build-app.sh` (assemble, stamp,
check architectures and minimum macOS, sign), `build-dev.sh`, `sign-app.sh`,
`release.sh` (universal DMG + GitHub release + tap) and `test.sh`. The version
comes from the `VERSION` file. A deeper write-up of the permission and updater
work is in [docs/permissions-audit.md](docs/permissions-audit.md).

---

## Русский

Приложение для диктовки в строке меню macOS с **бесплатным** облачным
распознаванием речи. Удерживайте **fn**, говорите, отпустите — аккуратный текст
появится в приложении, где вы печатаете.
Форк [qwenwishper](https://github.com/hukopo/qwenwishper) — вся локальная
инференция моделей заменена лёгкими API-вызовами.

### Что нового в 3.1

- **Работает на старых Mac** — минимальная версия теперь **macOS 13 Ventura**
  (была 14), а приложение собирается **универсальным**: нативно на Intel и на
  Apple silicon. Это Mac на Intel с 2017 года и новее.
- **Классический вид** — на macOS 13–15 вместо Liquid Glass используются
  полупрозрачные материалы. На macOS 26 классический вид можно выбрать в
  **Настройки → Дополнительно → Оформление** — на старых Mac с Intel он легче.
- **Безопасные обновления на старых Mac** — перед заменой приложения встроенный
  обновлятор проверяет, что новая версия поддерживает macOS и процессор этого Mac.
  Будущий релиз без поддержки Intel или старой macOS будет отклонён, а не
  установлен в виде приложения, которое не откроется.
- **Сборка в Xcode 16** — для сборки из исходников больше не нужен SDK macOS 26;
  Liquid Glass включается, только если SDK его поддерживает.
- **Исправление:** в 3.0 любая запись завершалась ошибкой «OSStatus error -39».

### Что нового в 3.0

- **Дизайн Liquid Glass** (macOS 26) — плавающая «таблетка» с живой
  звуковой волной, меню, настройки, окна истории и результата.
- **Диктовка клавишей fn** — удерживайте **fn** и отпустите для расшифровки, или
  нажмите для старта и остановки. **Esc** отменяет из любого приложения. fn+Delete,
  fn+стрелки и другие сочетания с fn продолжают работать.
- **Новые движки речи** — Groq **Whisper Large v3 Turbo** (бесплатно), Google
  **Gemini 3.5 Transcribe** напрямую по ключу AI Studio (бесплатный тариф, умное
  форматирование), OpenRouter и любой **OpenAI-совместимый** сервер, включая
  локальный whisper.cpp. Если движок не сработал или упёрся в лимит, пробуется
  следующий, для которого есть ключ.
- **Режимы AI-переформулировки** — Очистка, Пунктуация, Деловой стиль, Перевод (на
  любой язык) и Свои инструкции, через Groq, Gemini, OpenRouter или свой сервер.
  **Свой словарь** сохраняет правильное написание имён и терминов.
- **Удобнее в работе** — приветственный гид с проверкой ключа, «Повторить» после
  неудачной диктовки, тихие записи отсекаются до отправки, перетаскивание файла
  в меню для расшифровки, поиск по истории с исходным и обработанным текстом,
  «Открывать при входе в систему».

<details>
<summary>2.1 и 2.0</summary>

- **2.1** — разрешения, которые переживают обновления (стабильная подпись и
  вкладка «Разрешения» со сбросом в один клик), обновления по коммитам из
  приложения, настройки, которые не сбрасываются сами, правильная работа с
  несколькими мониторами, рабочие пресеты горячих клавиш.
- **2.0** — захват системного звука, расшифровка файлов, история, окно
  результата, исправления для macOS 26.

</details>

### Возможности

- **Диктовка в любое приложение** клавишей **fn** (или ⌘⇧Space и другими
  сочетаниями для клавиатур без fn)
- **Два источника звука:** 🎙 **Микрофон** печатает в активное приложение;
  🔊 **Системный звук** захватывает всё, что играет на Mac, через ScreenCaptureKit
- **Движки речи:** Groq Whisper (бесплатно) · Gemini 3.5 Transcribe (бесплатный
  тариф) · OpenRouter · OpenAI-совместимые серверы — с автоматическим резервом
- **AI-переформулировка:** очистка, пунктуация, деловой стиль, перевод, свои
  инструкции; свой словарь
- **Расшифровка файлов** — MP3, M4A, WAV, FLAC, OGG, MP4, MOV и другие; можно
  перетащить файл в меню
- **История** — поиск, копирование, сравнение исходного и обработанного текста,
  сохранение в текстовый файл
- **Чтение вслух**, звуковые сигналы, режим «Всегда вставлять» для приложений,
  которые игнорируют запись через Accessibility
- **Обновление из приложения** и **центр разрешений**
- **Локализованный интерфейс** — английский, русский, немецкий, французский,
  испанский, японский, китайский, корейский, итальянский, хинди, казахский
  (новые тексты 3.x — на английском и русском)
- Без загрузки моделей и GPU; Intel и Apple silicon

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
Скачайте `WhisperFly.dmg` с [последнего релиза](https://github.com/dandysuper/WhisperFly/releases/latest),
откройте и перетащите приложение в `/Applications`. Один и тот же DMG работает на
Intel и Apple silicon.

**Вариант 3 — Собрать из исходников:**
```bash
git clone https://github.com/dandysuper/WhisperFly.git
cd WhisperFly
./scripts/build-app.sh               # под архитектуру этого Mac
./scripts/build-app.sh --universal   # Intel + Apple silicon
open WhisperFly.app
```

Если репозиторий лежит в папке, синхронизируемой с iCloud (Рабочий стол или
Документы), и сборка останавливается с `disk I/O error`, собирайте вне её:
`WHISPERFLY_SCRATCH_PATH=/tmp/wf ./scripts/build-app.sh`.

Простой `swift run WhisperFly` тоже работает для разработки, но даёт сборку без
метаданных и с ad-hoc подписью — обновление и сохранность разрешений
гарантируются только для упакованного приложения. Тесты: `scripts/test.sh`.

### Настройка

При первом запуске **приветственный гид** проведёт по шагам:

1. **Выберите бесплатный движок и вставьте ключ.**
   - Groq: [console.groq.com/keys](https://console.groq.com/keys) — ключ начинается с `gsk_`
   - Gemini: [aistudio.google.com/apikey](https://aistudio.google.com/apikey)

   Одного ключа хватает и на расшифровку, и на AI-переформулировку. Второй можно
   добавить позже в **Настройки → Движки речи** для автоматического резерва.
2. **Выдайте разрешения** — Микрофон, Универсальный доступ (ввод текста и клавиша
   fn) и, только для системного звука, Запись экрана.
3. **Попробуйте** в поле для практики.

**Если fn открывает эмодзи или переключает раскладку:** откройте
**Системные настройки → Клавиатура** и выберите **«Нажатие 🌐: Ничего не делать»**.
WhisperFly показывает напоминание с кнопкой, пока это не сделано.

*Собираете из исходников? При первом запуске читается `.env` в корне проекта:*
```
GROQ_API_KEY=gsk_xxx
GEMINI_API_KEY=AIza_xxx
OPENROUTER_API_KEY=sk-or-v1-xxx
```

### Использование

| Действие | Результат |
|---|---|
| Удерживать **fn**, говорить, отпустить | Диктовка с микрофона в активное приложение |
| Нажать **fn**, говорить, нажать **fn** | То же, без удержания |
| **Esc** | Отменить запись или расшифровку |
| Меню → кнопка записи | Запись с выбранного источника (микрофон или системный звук) |
| Меню → **Файл…** или перетащить файл в меню | Расшифровать файл — результат в буфере обмена |
| Меню → **AI-переформулировка → Изменить** | Сменить режим или выключить его |
| Меню → **История** | Просмотр, поиск и копирование прошлых результатов |
| **Настройки → Основные** | Источник, язык, сочетание, удержание, способ вставки, звуки, автозапуск |
| **Настройки → Движки речи** | Движок, модель, ключи, резерв, свой сервер |
| **Настройки → AI-переформулировка** | Режим, движок, язык перевода, инструкции, словарь |
| **Настройки → Разрешения** | Живой статус, диагностика подписи, сброс и перезапуск |
| **Настройки → Обновления** | Проверка новых коммитов; установка DMG или пересборка из исходников |
| **Настройки → Дополнительно** | Лимит записи, задержка вставки, классический вид, история |

### Разрешения

| Разрешение | Для чего |
|---|---|
| Микрофон | Запись голоса |
| Универсальный доступ | Ввод текста в другие приложения, клавиша fn, «таблетка» у курсора |
| Запись экрана | Только захват системного звука |

Если в Системных настройках разрешение включено, но WhisperFly им не может
воспользоваться (обычно после сборки с другой подписью), используйте
**Настройки → Разрешения → Сбросить и перезапустить**: приложение очистит
устаревшие строки TCC через `tccutil` и перезапустится.

### Требования

- **macOS 13 Ventura или новее**, Intel или Apple silicon
- Liquid Glass — на macOS 26 и новее; на более ранних системах классический вид
- Захват системного звука: macOS 13 или новее с разрешением «Запись экрана»
- Диктовка fn: встроенные клавиатуры и клавиатуры Apple (большинство других
  обрабатывают fn внутри себя — выберите сочетание клавиш)
- Подключение к интернету (распознавание выполняется через API)
- Сборка из исходников: инструментарий Swift 6 — Xcode 16 или новее либо его
  Command Line Tools. Liquid Glass включается при сборке в Xcode 26 и новее.

### Заметки для macOS 26 (Tahoe)

У ScreenCaptureKit в macOS 26 есть известные проблемы:

- **Тихие выпадения звука** — SCStream может запуститься, но отдавать нулевые
  сэмплы. WhisperFly замечает это и подсказывает, что делать (закрыть другие
  приложения записи экрана, переключить источник туда-обратно или перезапустить).
- **Ложные отказы в разрешениях** — `CGPreflightScreenCaptureAccess` может
  возвращать `false` при выданном разрешении, поэтому решающей проверкой служит
  реальный вызов `SCShareableContent`.
- **Крэш жизненного цикла панели** — «таблетка» не освобождается посреди
  layout-прохода, а только скрывается.

### Снятие карантина macOS (xattr)

> **Не нужно при установке через Homebrew.**

Если вы установили приложение из DMG и видите предупреждение **«приложение
повреждено»** или от Gatekeeper:

```bash
xattr -cr /Applications/WhisperFly.app
```

### Обновление

**Из приложения:** **Настройки → Обновления → Проверить сейчас**, затем
**Обновить сейчас**. Приложение скачает релизный образ и заменит установленную
копию или подтянет и пересоберёт исходники, после чего перезапустится. Перед
установкой проверяется, что новая версия поддерживает вашу macOS и процессор.

**Через Homebrew:** `brew update && brew upgrade --cask whisperfly`

Обновления сохраняют разрешения: сборки подписываются стабильным designated
requirement, привязанным к команде разработчика. При переходе со сборки с другой
подписью один раз выполните **Настройки → Разрешения → Сбросить и перезапустить**.

### Архитектура

Структура исходников описана в [английском разделе](#architecture). Инструменты
сборки и релиза — в `scripts/`: `build-app.sh` (сборка, метаданные, проверка
архитектур и минимальной macOS, подпись), `build-dev.sh`, `sign-app.sh`,
`release.sh` (универсальный DMG + релиз на GitHub + tap) и `test.sh`. Версия
берётся из файла `VERSION`. Подробный разбор работы с разрешениями и
обновлениями — в [docs/permissions-audit.md](docs/permissions-audit.md).
