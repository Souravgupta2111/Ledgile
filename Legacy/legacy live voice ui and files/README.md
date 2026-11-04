# Legacy Live Voice Assistant UI & Files

This directory contains the disconnected files and UI components for the **Live Voice Assistant** feature, archived to optimize cloud API costs while preserving all code and architecture for future reintroduction.

## Overview of Components

1. **`LiveVoiceViewController.swift`**
   - Full-screen modal live voice interaction interface.
   - Hosts the glowing animated visualizer (`LiveOrbView`), mute/interrupt controls, real-time transcript bubbles, and conversation lifecycle management.
   - Coordinates the turn-taking loop: listening -> speech recognition -> reasoning with shop ledger SQL -> voice synthesis playback -> re-listening for follow-up questions.

2. **`LiveAssistantEngine.swift`**
   - Real-time streaming audio capture engine utilizing `AVAudioEngine` input node tap (16kHz / 48kHz).
   - Manages the streaming WebSocket connection to Deepgram Nova-2 STT (`wss://api.deepgram.com/v1/listen`).
   - Implements speech onset detection, vocal barge-in detection during assistant speech, and audio session management (`playAndRecord`).

3. **`SarvamBulbulSpeaker.swift`**
   - Text-to-speech audio speaker supporting Deepgram Aura voice (`aura-asteria-en`) with fallback to Sarvam Bulbul and native iOS `AVSpeechSynthesizer`.
   - Features sentence-by-sentence streaming, prefetching the next sentence while the current one is speaking, currency normalization (converting ₹ symbols to spoken amounts), and playback queue management via `AVAudioPlayer`.

4. **`LiveOrbView.swift`**
   - Interactive animated 3D-styled pulsing orb with distinct states:
     - `listening`: gentle floating pulse
     - `thinking`: fast color cycling & radial expansion
     - `speaking`: amplitude-reactive energetic waveform pulse
     - `idle`: dormant slow breathing

5. **`LiveWaveformView.swift`**
   - Live multi-bar audio equalizer visualizer tracking real-time microphone RMS audio amplitude.

6. **`LiveLog.swift`**
   - Specialized logging utility tagging console output across the voice pipeline (`[Live][mic]`, `[Live][tts]`, `[Live][ui]`, `[Live][qwen]`).

---

## How to Reconnect in the Future

If you want to re-enable the Live Voice Assistant:

1. **In `ShopAssistantViewController.swift`**:
   - Re-add the `liveButton` (mic button) next to the composer or in the navigation bar:
     ```swift
     let liveButton = UIButton(type: .system)
     // add target: liveTapped
     ```
   - Re-add the presentation action:
     ```swift
     @objc private func liveTapped() {
         let pack = ShopLedgerLookup.assistantPack()
         let vc = LiveVoiceViewController(shopPack: pack)
         vc.onExit = { [weak self] turns in
             guard let self, !turns.isEmpty else { return }
             for t in turns {
                 self.lines.append(Line(isUser: true, text: t.user))
                 self.lines.append(Line(isUser: false, text: t.assistant))
             }
             self.tableView.reloadData()
             self.scrollToEnd()
         }
         present(vc, animated: true)
     }
     ```

2. **In `SceneDelegate.swift`**:
   - Include `LiveVoiceViewController` in the top view controller hotword guard so "Hey Beasy" does not present over an active live voice turn:
     ```swift
     if topVC is VoiceEntryViewController || topVC is LiveVoiceViewController || topVC is VoicePurchaseEntryViewController { return }
     ```

3. **Environment & API Keys**:
   - Ensure `DEEPGRAM_API_KEY` (and optionally `SARVAM_API_KEY`) is configured in the environment / Info.plist for STT WebSocket and TTS playback.
