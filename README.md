# WhisperFly

> 🇬🇧 [English](#english) · 🇷🇺 [Русский](#русский)

---

## English

A macOS menu-bar push-to-talk dictation app with **free** cloud-based speech recognition.  
Fork of [qwenwishper](https://github.com/hukopo/qwenwishper) — replaces all local model inference with lightweight API calls.

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
swift run WhisperFly
```

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

### Permissions

| Permission | Required for |
|---|---|
| Microphone | Voice recording |
| Screen Recording | System audio capture via ScreenCaptureKit |
| Accessibility | Typing transcribed text into other apps |

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

Current WhisperFly builds are signed with a stable designated requirement, so **Microphone**, **Screen Recording**, and **Accessibility** permissions should persist across normal in-place updates and reinstalls as long as the app keeps the same bundle identifier and Apple developer team.

If you are updating from an older build that was signed differently, macOS may still treat it as a different app once. In that case, do a one-time reset:

1. Quit WhisperFly.
2. Install the new version (`brew upgrade whisperfly` or drag the new `.app` to `/Applications`).
3. Open **System Settings → Privacy & Security → Accessibility**.
4. Select **WhisperFly** and click **−** to remove it.
5. Click **+**, navigate to `/Applications/WhisperFly.app`, and add it back.
6. Make sure the toggle is **on**.
7. Launch WhisperFly.

### Architecture

```
Sources/WhisperFly/
├── App/
│   ├── AppController.swift             # Main pipeline: record → transcribe → rewrite → paste → TTS
│   ├── FloatingPanel.swift             # Floating status pill near the cursor
│   ├── HistoryPanel.swift              # Transcription history window
│   ├── TranscriptionResultPanel.swift  # Single result HUD window
│   └── WhisperFlyApp.swift             # SwiftUI entry point / menu bar extra
├── Core/
│   ├── PipelineStatus.swift            # Enum: idle / recording / transcribing / rewriting / pasting / error
│   ├── Protocols.swift                 # SpeechRecognizer, TextRewriter, TextInjector, …
│   └── L10n.swift                      # Localization helper
├── Models/
│   ├── AppSettings.swift               # Codable settings + UserDefaults persistence
│   └── TranscriptionHistory.swift      # In-memory history store
├── Resources/
│   └── *.lproj/Localizable.strings     # en, ru, de, fr, es, ja, zh, ko, it, hi
├── Services/
│   ├── AudioCaptureService.swift       # Microphone recording
│   ├── SystemAudioCaptureService.swift # System audio via ScreenCaptureKit
│   ├── AudioConverter.swift            # CAF → 16 kHz WAV conversion
│   ├── GeminiRewriter.swift            # AI text rewriting via OpenRouter
│   ├── GeminiTranscriber.swift         # Gemini transcription backend
│   ├── GroqWhisperRecognizer.swift     # Groq Whisper transcription backend
│   ├── HotkeyMonitor.swift             # Global ⌘⇧Space hotkey (Carbon)
│   └── PasteService.swift              # Text injection (Accessibility API + clipboard fallback)
└── Views/
    ├── FloatingStatusView.swift
    ├── HistoryView.swift
    ├── MenuBarContentView.swift
    ├── SettingsView.swift
    └── TranscriptionResultView.swift
```

---

## Русский

Приложение для macOS — диктовка нажатием клавиши с **бесплатным** облачным распознаванием речи.  
Форк [qwenwishper](https://github.com/hukopo/qwenwishper) — вся локальная модельная инференция заменена лёгкими API-вызовами.

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
swift run WhisperFly
```

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

### Разрешения

| Разрешение | Для чего |
|---|---|
| Микрофон | Запись голоса |
| Захват экрана | Захват системного звука через ScreenCaptureKit |
| Специальные возможности | Ввод текста в другие приложения |

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

Текущие сборки WhisperFly подписываются со стабильным designated requirement, поэтому разрешения **Микрофон**, **Захват экрана** и **Специальные возможности** должны сохраняться при обычном обновлении и переустановке, пока у приложения остаются тот же bundle identifier и та же команда Apple Developer.

Если вы обновляетесь со старой сборки, подписанной иначе, macOS может один раз посчитать её другим приложением. В таком случае сделайте одноразовый сброс:

1. Закройте WhisperFly.
2. Установите новую версию (`brew upgrade whisperfly` или перетащите новый `.app` в `/Applications`).
3. Откройте **Системные настройки → Конфиденциальность и безопасность → Специальные возможности**.
4. Выделите **WhisperFly** и нажмите **−**, чтобы удалить.
5. Нажмите **+**, перейдите к `/Applications/WhisperFly.app` и добавьте заново.
6. Убедитесь, что переключатель **включён**.
7. Запустите WhisperFly.

### Архитектура

```
Sources/WhisperFly/
├── App/
│   ├── AppController.swift             # Главный координатор: запись → транскрипция → переформулировка → вставка → TTS
│   ├── FloatingPanel.swift             # Плавающая таблетка статуса рядом с курсором
│   ├── HistoryPanel.swift              # Окно истории транскрипций
│   ├── TranscriptionResultPanel.swift  # HUD-окно отдельного результата
│   └── WhisperFlyApp.swift             # Точка входа SwiftUI / элемент строки меню
├── Core/
│   ├── PipelineStatus.swift            # Enum: idle / recording / transcribing / rewriting / pasting / error
│   ├── Protocols.swift                 # SpeechRecognizer, TextRewriter, TextInjector, …
│   └── L10n.swift                      # Вспомогательный модуль локализации
├── Models/
│   ├── AppSettings.swift               # Настройки (Codable) + сохранение в UserDefaults
│   └── TranscriptionHistory.swift      # Хранилище истории в памяти
├── Resources/
│   └── *.lproj/Localizable.strings     # en, ru, de, fr, es, ja, zh, ko, it, hi
├── Services/
│   ├── AudioCaptureService.swift       # Запись с микрофона
│   ├── SystemAudioCaptureService.swift # Системный звук через ScreenCaptureKit
│   ├── AudioConverter.swift            # Конвертация CAF → WAV 16 кГц
│   ├── GeminiRewriter.swift            # AI-переформулировка через OpenRouter
│   ├── GeminiTranscriber.swift         # Бэкенд транскрипции Gemini
│   ├── GroqWhisperRecognizer.swift     # Бэкенд транскрипции Groq Whisper
│   ├── HotkeyMonitor.swift             # Глобальная клавиша ⌘⇧Space (Carbon)
│   └── PasteService.swift              # Вставка текста (Accessibility API + буфер обмена)
└── Views/
    ├── FloatingStatusView.swift
    ├── HistoryView.swift
    ├── MenuBarContentView.swift
    ├── SettingsView.swift
    └── TranscriptionResultView.swift
```
