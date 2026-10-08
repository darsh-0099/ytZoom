# ytZoom

**ytZoom** is an experimental lightweight macOS desktop client for YouTube. It wraps YouTube in a native SwiftUI window using Apple's WebKit, without bundling Electron or a Chromium runtime.

The project explores whether avoiding a full standalone browser framework and reducing unnecessary website animation can offer a leaner experience. No particular CPU, RAM, or battery-life savings are guaranteed.

## Features

- Native macOS window with history, home, reload, URL/search field, and system-browser handoff
- One persistent WKWebView with saved website data and cookies
- Three display modes: **Balanced**, **Eco**, and **Compatibility**
- Keyboard shortcuts: Command-L, Command-R, Command-[, and Command-]
- Intel macOS 13 Ventura and newer
- No third-party application dependencies

### Performance modes

| Mode | Behavior |
| --- | --- |
| Balanced | Hide selected animated thumbnail previews |
| Eco | Also reduce some non-player interface transitions |
| Compatibility | Leave YouTube's webpage styling unchanged |

These modes make cosmetic changes only. They do not replace the YouTube player, disable website scripts, or guarantee lower CPU or RAM usage.

## Download

Get the latest Intel macOS ZIP on the [Releases page](../../releases/latest). After extracting the ZIP, drag **ytZoom.app** to Applications and open it in Finder. A successful prebuilt release does **not** require Xcode or Terminal.

The app is ad-hoc signed, **not Developer ID signed or notarized**. macOS may initially block it. If you trust the release, right-click and choose Open; if needed, use System Settings → Privacy & Security → Open Anyway. Production distribution should use Developer ID signing and notarization.

## Building from source

The [GitHub Actions workflow](.github/workflows/build-macos.yml) builds on a hosted Intel macOS runner and publishes a downloadable application ZIP after a successful build.

Source files are in Sources/ytZoom. Developers with a compatible Swift toolchain and macOS SDK can build using the following command:

    swift build --configuration release --arch x86_64

## Architecture

- SwiftUI provides the desktop toolbar, modes, navigation, and search.
- WebKit loads the standard YouTube website in one persistent web view.
- Standard WebKit website storage preserves cookies and preferences.
- A small CSS adjustment minimizes selected preview/transition effects.

## Limitations

- Google sign-in may not work in embedded web browsers.
- WebKit spawns helper processes; evaluate total CPU and RAM usage rather than only the application's main process.
- YouTube controls its website, streaming codecs, playback behavior, and advertisements.
- The first build is experimental. Actual device testing and performance benchmarking are still required.
- Only Intel macOS is currently packaged in automated releases.

## Contributing

Issue reports and pull requests are welcome, particularly for compatibility fixes, accessibility improvements, and reproducible performance benchmarks. Include the macOS version, steps to reproduce problems, and measurable before/after comparisons when appropriate.

## License

Licensed under the [MIT License](LICENSE).

ytZoom is an independent project and is not affiliated with or endorsed by YouTube or Google.
