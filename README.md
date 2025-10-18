# Offline Search Engine

## Offline Search Engine (formerly Pocket Search Engine)

**Offline Search Engine** is a on-device "mini-Google" running on device, for PDF and HTML files. Load your PDFs and saved web pages, search by meaning or exact text, get results, and choose which results to view.

It's an install-and-forget-until-needed App, for Hikers, mountaineers, off-roaders, emergencies or anyone who might need to search for information when there's no internet. 

There's an optional download of a pre-populated DB with essential info (car manuals, first-aid, water purification, et-cetera)


Pre-built for Adroid
In Google Play store: https://play.google.com/store/apps/details?id=com.pocketsearchengine.app


[![Get it on Google Play](https://play.google.com/intl/en_us/badges/static/images/badges/en_badge_web_generic.png)](https://play.google.com/store/apps/details?id=com.pocketsearchengine.app)

## Demo

[![Watch the demo](https://img.youtube.com/vi/MHIDt42Gxs0/hqdefault.jpg)](https://www.youtube.com/watch?v=MHIDt42Gxs0)



## Support

- **Android**: Supported (available on Google Play).
- **Linux**: AppImage creation supported from source.
  - Caveat: The in-app viewer will not work for HTML files; the app will open the local HTML file using the OS's default browser instead.


### What it does & how it works

- **Offline, private search:** Everything runs locally with inbuilt sentence-embedder models, inference engines, database; no servers or network calls.
- **Local PDF/HTML indexing:** You explicitly load .pdf or .html files; the app indexes them and stores embeddings + keywords in its own internal database (no access to the rest of the system).
- **Semantic + exact:** Your search query will be processed based on its meaning (aka semantic search, like most search engines), use quotes if you want exact keyword search. Internally, this involves vector search.
- **Optional pre-populated DB:** Optionally download a pre-populated demo DB (car manuals, first aid, water purification, etc.)
- **Cross-platform:** Current code supports Android and Linux. But being built in flutter, it is possible do build for Windows and IOS 
- **Export/import DB feature**



## Requirements (build/run from local)
- Flutter (stable). Recommended: 3.29.x
- For Linux desktop:
  - Ubuntu: cmake, ninja-build, clang, pkg-config, libgtk-3-dev (see Dockerfile for full list)
- For Rust bridge (already configured): Rust toolchain (stable) on dev machines building native code
- Android SDK + NDK (if building for Android)

## Quick Start

### Run on Linux (desktop)
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


### Contributions and merge requests welcome.