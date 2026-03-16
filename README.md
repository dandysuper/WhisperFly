# WhisperFly

A macOS menu-bar push-to-talk dictation app with **free** cloud-based speech recognition. Fork of [qwenwishper](https://github.com/hukopo/qwenwishper) — replaces all local model inference with lightweight API calls.

## Features

- **Push-to-talk** via ⌘⇧Space global hotkey
- **Two free transcription backends:**
  - 🟢 **Groq Whisper Large V3** — dedicated ASR, 100+ languages including Russian
  - 🟢 **Google Gemini 2.5 Flash** (OpenRouter) — multimodal, free tier
- **AI text rewriting** — cleanup, punctuation, or translate-to-English via Gemini
- **Auto-paste** into focused app (Accessibility API with clipboard fallback)
- No local model downloads, no GPU required

## Setup

1. Get free API keys:
   - Groq: [console.groq.com](https://console.groq.com) → API Keys
   - OpenRouter: [openrouter.ai/keys](https://openrouter.ai/keys)

2. Create `.env` in the project root:
   ```
   GROQ_API_KEY=gsk_xxx
   OPENROUTER_API_KEY=sk-or-v1-xxx
   ```

3. Build & run:
   ```bash
   swift build
   swift run WhisperFly
   ```

4. Grant **Microphone** and **Accessibility** permissions when prompted.

## Usage

- Press **⌘⇧Space** to start recording
- Press again to stop and transcribe
- Text is automatically pasted into the focused text field
- Click the menu bar icon to see status, results, and settings

## Requirements

- macOS 14+
- Swift 6 toolchain
- Internet connection (API calls)
