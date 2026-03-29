# WhisperFly

> 🇬🇧 [English](#english) · 🇷🇺 [Русский](#русский)

---

## English

A macOS menu-bar push-to-talk dictation app with **free** cloud-based speech recognition.  
Fork of [qwenwishper](https://github.com/hukopo/qwenwishper) — replaces all local model inference with lightweight API calls.

### Features

- **Push-to-talk** via ⌘⇧Space global hotkey (configurable)
- **Two free transcription backends:**
  - 🟢 **Groq Whisper Large V3** — dedicated ASR, 100+ languages including Russian
  - 🟢 **Google Gemini 2.5 Flash** (via OpenRouter) — multimodal, free tier
- **AI text rewriting** — cleanup, punctuation fix, or translate-to-English via Gemini
- **Read aloud** — optionally speak back the transcribed text using the system TTS voice
- **Auto-paste** into the focused app (Accessibility API with clipboard fallback)
- **Localized UI** — the app automatically adapts to your system language (English, Russian, German, French, Spanish, Japanese, Chinese, Korean, Italian, Hindi)
- No local model downloads, no GPU required

### Install

**Option 1 — Homebrew (recommended):**
```bash
brew tap dandysuper/tap
brew install --cask whisperfly
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

3. Grant **Microphone** and **Accessibility** permissions when prompted.

### Usage

| Action | Result |
|---|---|
| Press **⌘⇧Space** | Start recording |
| Press **⌘⇧Space** again | Stop and transcribe |
| Click menu bar icon | See status, last result, settings |
| Open **Settings → General** | Change backend, language, rewrite mode, read-aloud |
| Open **Settings → API Keys** | Enter Groq / OpenRouter keys |
| Open **Settings → Advanced** | Tune max recording duration and paste delay |

### Requirements

- macOS 14 (Sonoma) or later
- Swift 6 toolchain
- Internet connection (all recognition is done via API)

### Removing macOS Quarantine (xattr)

> **Not needed if you installed via Homebrew** — Homebrew removes the quarantine flag automatically.

If you installed manually from the DMG, macOS may block the app with an **"app is damaged"** or Gatekeeper warning. Fix it by running:

```bash
xattr -cr /Applications/WhisperFly.app
```

This clears the `com.apple.quarantine` extended attribute recursively from the app bundle. Apple's Gatekeeper applies this flag to any app not signed with an Apple Developer certificate.

### Reinstalling / Updating

When you reinstall or update WhisperFly, macOS **does not** automatically trust the new binary for Accessibility. The old entry becomes stale and the app will silently fail to paste text.

**You must remove and re-add WhisperFly in Accessibility settings:**

1. **Quit** WhisperFly if it's running.
2. Install the new version (Homebrew `brew upgrade whisperfly`, or drag the new `.app` to `/Applications`).
3. Open **System Settings → Privacy & Security → Accessibility**.
4. Find **WhisperFly** in the list — **select it and click the "−" (minus) button** to remove it entirely.
5. Click **"+" (plus)**, navigate to `/Applications/WhisperFly.app`, and add it back.
6. Make sure the toggle is **on**.
7. Launch WhisperFly.

> **Why?** macOS ties Accessibility permissions to the app's code signature / binary hash. After an update the old permission entry points to a binary that no longer matches, so the system revokes access silently. Toggling the switch off/on is **not enough** — you must fully remove and re-add the entry.

### Architecture

```
Sources/WhisperFly/
├── App/
│   ├── AppController.swift      # Main coordinator (recording → transcribe → rewrite → paste → TTS)
│   ├── FloatingPanel.swift      # Floating status pill near the cursor
│   └── WhisperFlyApp.swift      # SwiftUI entry point / menu bar extra
├── Core/
│   ├── PipelineStatus.swift     # Enum: idle / recording / transcribing / rewriting / pasting / error
│   └── Protocols.swift          # SpeechRecognizer, TextRewriter, TextInjector, …
├── Models/
│   └── AppSettings.swift        # Codable settings + UserDefaults persistence
├── Resources/
│   ├── en.lproj/Localizable.strings
│   └── ru.lproj/Localizable.strings
├── Services/
│   ├── AudioCaptureService.swift
│   ├── AudioConverter.swift     # Shared CAF → 16 kHz WAV conversion
│   ├── GeminiRewriter.swift
│   ├── GeminiTranscriber.swift
│   ├── GroqWhisperRecognizer.swift
│   ├── HotkeyMonitor.swift
│   └── PasteService.swift
└── Views/
    ├── FloatingStatusView.swift
    ├── MenuBarContentView.swift
    └── SettingsView.swift
```

---

## Русский

Приложение для macOS — диктовка нажатием клавиши с **бесплатным** облачным распознаванием речи.  
Форк [qwenwishper](https://github.com/hukopo/qwenwishper) — вся локальная модельная инференция заменена лёгкими API-вызовами.

### Возможности

- **Запись нажатием клавиши** через глобальное сочетание ⌘⇧Space (настраивается)
- **Два бесплатных бэкенда транскрипции:**
  - 🟢 **Groq Whisper Large V3** — специализированный ASR, 100+ языков, включая русский
  - 🟢 **Google Gemini 2.5 Flash** (через OpenRouter) — мультимодальный, бесплатный тариф
- **AI-переформулировка текста** — исправление, пунктуация или перевод на английский через Gemini
- **Прочитать вслух** — озвучить распознанный текст системным голосом TTS
- **Автовставка** в активное поле ввода (Accessibility API, при неудаче — через буфер обмена)
- **Локализованный интерфейс** — приложение автоматически адаптируется к языку системы (английский, русский, немецкий, французский, испанский, японский, китайский, корейский, итальянский, хинди)
- Не требует загрузки локальных моделей и GPU

### Установка

**Вариант 1 — Homebrew (рекомендуется):**
```bash
brew tap dandysuper/tap
brew install --cask whisperfly
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

3. Разрешите доступ к **Микрофону** и **Специальным возможностям** при запросе.

### Использование

| Действие | Результат |
|---|---|
| Нажать **⌘⇧Space** | Начать запись |
| Нажать **⌘⇧Space** ещё раз | Остановить и транскрибировать |
| Кликнуть иконку в строке меню | Статус, последний результат, настройки |
| **Настройки → Основные** | Бэкенд, язык, режим переформулировки, чтение вслух |
| **Настройки → API-ключи** | Ввести ключи Groq / OpenRouter |
| **Настройки → Дополнительно** | Макс. длительность записи и задержка вставки |

### Требования

- macOS 14 (Sonoma) или новее
- Инструментарий Swift 6
- Подключение к интернету (распознавание выполняется через API)

### Снятие карантина macOS (xattr)

> **Не нужно при установке через Homebrew** — Homebrew снимает флаг карантина автоматически.

Если вы установили приложение вручную из DMG, macOS может заблокировать его с предупреждением **«приложение повреждено»** или от Gatekeeper. Исправьте, выполнив:

```bash
xattr -cr /Applications/WhisperFly.app
```

Это рекурсивно удаляет атрибут `com.apple.quarantine` из пакета приложения. Gatekeeper Apple устанавливает этот флаг на любое приложение, не подписанное сертификатом Apple Developer.

### Переустановка / Обновление

При переустановке или обновлении WhisperFly macOS **не** доверяет новому бинарнику автоматически для Специальных возможностей (Accessibility). Старая запись становится недействительной, и приложение молча перестаёт вставлять текст.

**Необходимо удалить и заново добавить WhisperFly в настройках Accessibility:**

1. **Закройте** WhisperFly, если он запущен.
2. Установите новую версию (Homebrew: `brew upgrade whisperfly`, или перетащите новый `.app` в `/Applications`).
3. Откройте **Системные настройки → Конфиденциальность и безопасность → Специальные возможности** (Accessibility).
4. Найдите **WhisperFly** в списке — **выделите его и нажмите кнопку «−» (минус)**, чтобы полностью удалить.
5. Нажмите **«+» (плюс)**, перейдите к `/Applications/WhisperFly.app` и добавьте его заново.
6. Убедитесь, что переключатель **включён**.
7. Запустите WhisperFly.

> **Почему?** macOS привязывает разрешения Accessibility к подписи / хешу бинарника приложения. После обновления старая запись ссылается на бинарник, который больше не совпадает, и система молча отзывает доступ. Переключение тумблера выкл/вкл **недостаточно** — нужно полностью удалить и заново добавить запись.

### Архитектура

```
Sources/WhisperFly/
├── App/
│   ├── AppController.swift      # Главный координатор (запись → транскрипция → переформулировка → вставка → TTS)
│   ├── FloatingPanel.swift      # Плавающая таблетка статуса рядом с курсором
│   └── WhisperFlyApp.swift      # Точка входа SwiftUI / элемент строки меню
├── Core/
│   ├── PipelineStatus.swift     # Enum: idle / recording / transcribing / rewriting / pasting / error
│   └── Protocols.swift          # SpeechRecognizer, TextRewriter, TextInjector, …
├── Models/
│   └── AppSettings.swift        # Настройки (Codable) + сохранение в UserDefaults
├── Resources/
│   ├── en.lproj/Localizable.strings
│   └── ru.lproj/Localizable.strings
├── Services/
│   ├── AudioCaptureService.swift
│   ├── AudioConverter.swift     # Общая конвертация CAF → WAV 16 кГц
│   ├── GeminiRewriter.swift
│   ├── GeminiTranscriber.swift
│   ├── GroqWhisperRecognizer.swift
│   ├── HotkeyMonitor.swift
│   └── PasteService.swift
└── Views/
    ├── FloatingStatusView.swift
    ├── MenuBarContentView.swift
    └── SettingsView.swift
```
