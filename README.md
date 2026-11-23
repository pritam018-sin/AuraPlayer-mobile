<p align="center">
  <h1 align="center">🎬 AuraPlayer Mobile</h1>
  <p align="center">
    <strong>Ultra-Sleek, Hardware-Accelerated 4K Video Player for Android.</strong><br>
    Swipe gestures • Subtitle track switcher • PiP mode • 100% Free & Open-Source
  </p>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/Dart-%230175C2.svg?style=for-the-badge&logo=dart&logoColor=white" alt="Dart" />
  <img src="https://img.shields.io/badge/License-MIT-blue.svg?style=for-the-badge" alt="License" />
  <img src="https://img.shields.io/badge/Platform-Android-brightgreen.svg?style=for-the-badge" alt="Platforms" />
</p>

---

## 🌟 Overview

**AuraPlayer Mobile** is a modern, lightweight, privacy-first mobile video player designed as a clean alternative to bloated media players like MX Player and VLC. 

Powered by Flutter and the native `media_kit` (libmpv backend), it renders crisp 4K 60FPS video with zero advertisements, zero background tracking, and smooth touch gestures.

---

## 🚀 Key Features

- **⚡ Hardware Decoding:** Smooth 4K HDR playback using native hardware video decoders.
- **👆 Intuitive Touch Gestures:**
  - Swipe left side vertically for brightness control.
  - Swipe right side vertically for volume control.
  - Swipe horizontally for seeking.
  - Double-tap to pause / play.
- **💬 Multi-Track Subtitles & Audio:** Switch between embedded subtitle tracks (SRT, ASS, VTT) and dual-audio tracks seamlessly.
- **🪟 Picture-in-Picture (PiP):** Keep watching while multitasking on your phone.
- **📁 Smart Media Library:** Auto-indexes device videos with thumbnail generation and resume playback markers.
- **🚫 100% Ad-Free:** Zero telemetry, zero banner ads, pure video watching.

---

## 🏗️ Tech Stack

- **Framework:** [Flutter](https://flutter.dev) (Dart)
- **Media Engine:** `media_kit` (libmpv hardware decoder)
- **UI:** Custom frosted glass & modern dark aesthetic

---

## 🛠️ Getting Started

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (v3.0+)
- Android Studio / VS Code
- Android Device or Emulator

### Installation & Run

1. **Clone the repository:**
   ```bash
   git clone https://github.com/pritam018-sin/AuraPlayer-mobile.git
   cd AuraPlayer-mobile
   ```

2. **Get dependencies:**
   ```bash
   flutter pub get
   ```

3. **Run on Android:**
   ```bash
   flutter run -d android
   ```

4. **Build Release APK:**
   ```bash
   flutter build apk --release
   ```

---

## 🤝 Contributing

Contributions, feedback, and feature requests are welcome! Open an issue on the [GitHub Issues](https://github.com/pritam018-sin/AuraPlayer-mobile/issues) page.

---

## 📄 License

This project is licensed under the **MIT License**.
