# 🔍 Offline Search Engine


[![License](https://img.shields.io/github/license/Ohrest88/offline-search-engine.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.29.x-blue?logo=flutter)](https://flutter.dev/)
[![Android](https://img.shields.io/badge/Platform-Android-green?logo=android)](https://play.google.com/store/apps/details?id=com.pocketsearchengine.app)
[![Linux](https://img.shields.io/badge/Platform-Linux-orange?logo=linux)](#)

---

## 🌐 Overview

**Offline Search Engine** (formerly *Pocket Search Engine*) is an on-device search engine app, a "mini Google" that works without the Internet.

Load your **PDF** and **HTML** files, search by **meaning** or **exact text**, and find what you need, offline.

Use-case:
> 🏔️ Hikers • 🚙 Off-roaders • 🧭 Mountaineers • 🚑 Emergency use • 🛠️ Anyone who might need to search information without Internet

Optionally, you can download a **pre-populated database** with essential survival info (car manuals, first aid, water purification, etc).

---

## 📱 Download (Android | Linux)

<a href="https://play.google.com/store/apps/details?id=com.pocketsearchengine.app">
  <img alt="Get it on Google Play"
       src="https://play.google.com/intl/en_us/badges/static/images/badges/en_badge_web_generic.png"
       height="80"/>
</a>

**Pre-built for Android**  
📦 [Google Play Store →](https://play.google.com/store/apps/details?id=com.pocketsearchengine.app)

**Linux App Image**  
[⬇️ Download AppImage (latest)](https://github.com/Ohrest88/offlinesearchengine/releases/latest/download/PocketSearchEngine-x86_64.AppImage)


---

## 🎥 Demo

[![Watch the demo](https://img.youtube.com/vi/MHIDt42Gxs0/hqdefault.jpg)](https://www.youtube.com/watch?v=MHIDt42Gxs0)

---

## 💡 Features

- **Completely offline & private:** No network calls or telemetry. All inference, embeddings, and indexing are done on-device.
- **Local PDF/HTML indexing:** Add files manually — the app only scans what you load, not your entire filesystem.
- **Semantic + exact search:** Search by *meaning* (via vector embeddings) or use quotes for exact text.
- **Optional preloaded DB:** Includes useful offline references like first aid, water purification, and car manuals.
- **Cross-platform support:**  
  - ✅ Android (fully supported)  
  - 🐧 Linux (Supported, with caveat: HTML opens in default browser rather than inbuild web viewer)
- 💾 **Export/import database:** Backup or share your offline knowledge base easily.

---

## 🧩 Pre-built Executables Platform Support

| Platform | Status | Notes |
|-----------|---------|-------|
| **Android** | ✅ Supported | Available on Google Play |
| **Linux** | ✅ Supported AppImage | Download Linux App image from release link | In-app HTML viewer fallback to system browser |
| **Windows / iOS** | Not attempted, but possible | Flutter and the choice of packages used makes this feasible |

---

## 🛠️ Requirements (for local build)

- **Flutter (stable)** — Recommended: `3.29.x`
- **Linux dependencies:**
  - `cmake`, `ninja-build`, `clang`, `pkg-config`, `libgtk-3-dev`
  - (See Dockerfile for full list)
- **Rust toolchain (stable)** — for native bridge code
- **Android SDK + NDK** — for Android builds

---

## 🚀 Quick Start

### 🐧 Run on Linux (Desktop)
```bash
flutter pub get
flutter run -d linux
```

### Run on Android (device)
1) Enable Developer Options + USB debugging on your phone and set USB mode to "File transfer (MTP)".
```bash
yes | flutter doctor --android-licenses
flutter doctor -v
adb devices -l
```
2) Run:
```bash
flutter run
```

## Building

### Build Linux AppImage via Docker (reproducible)
```bash
docker build -t pocketsearch-builder .
docker create --name temp pocketsearch-builder
docker cp temp:/home/builder/app/PocketSearchEngine-x86_64.AppImage .
docker rm temp
```


### Run on Android (Device)

1. **Enable Developer Options + USB Debugging**  
   Set USB mode to **File transfer (MTP)**.

   ```bash
   yes | flutter doctor --android-licenses
   flutter doctor -v
   adb devices -l


2.  **Run the app:**
    ```bash
    flutter run
    ```


## 📄 License
This project is open source under **GNU GPLv3**. See [`LICENSE.md`](./LICENSE.md) and [`CONTRIBUTING.md`](./CONTRIBUTING.md) for details.

© 2025 Orest Sota

Licensed under the GNU General Public License version 3 (GPLv3).
See the LICENSE and CONTRIBUTING file for details.