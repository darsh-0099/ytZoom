# ytZoom

**ytZoom** is an experimental lightweight macOS desktop client for YouTube. It wraps YouTube in a native SwiftUI window using Apple's WebKit, without bundling Electron or a Chromium runtime.

The project explores whether avoiding a full standalone browser framework and reducing unnecessary website animation can offer a leaner experience. No particular CPU, RAM, or battery-life savings are guaranteed.

## Features

- Native macOS window with history, home, reload, URL/search field, and system-browser handoff
- One app window and one WKWebView, with saved website data and cookies
- Unload/resume page control to release the web view during long idle periods
- Optional pause when hidden or minimized, without automatic playback on return
- One-click dark/light appearance toggle for the toolbar and YouTube, saved between launches (Command-Shift-D)
- Compact playback menu with saved speed from 0.5× to 2×, play/pause, 10-second seeking, background pause, and unload/resume
- Videos default to theatre mode; selecting a new video while using miniplayer preserves miniplayer
- Live chat and replay stay collapsed until Show chat is clicked, resetting for each video
- Three display modes: **Balanced**, **Eco**, and **Compatibility**
- Keyboard shortcuts: Command-L, Command-R, Command-[, Command-], Command-P (play/pause), and Command-Left/Right (seek)
- Intel macOS 13 Ventura and newer
- No third-party application dependencies

### Performance modes

| Mode | Behavior |
| --- | --- |
| Balanced | Hide and pause selected animated thumbnail previews |
| Eco | Also reduce some non-player interface transitions |
| Compatibility | Leave YouTube's webpage styling unchanged |

Balanced and Eco pause video elements in recognized thumbnail preview containers when they start playing, as well as hiding those containers. Eco also reduces selected interface motion. Compatibility removes the preview/style adjustments; playback controls and the independently selected background pause option remain available. These modes do not replace the YouTube player or disable website scripts.

**Pause when hidden** is off by default so background listening keeps working. Enable it to pause when the app is hidden, minimized, or WebKit reports the page as hidden. Returning to the window leaves playback paused until manually resumed. This pauses media rather than suspending all website work.

**Unload page**, available in the toolbar’s Playback options menu, stops media and navigation, detaches observers, and destroys the web view. Resume creates a new view at the last address using the same persistent cookies and website data. Navigation history, playback position, and unsaved page state are reset. Searching or choosing Home while unloaded also resumes the page. WebKit decides when to reclaim helper-process memory, so memory usage may not fall immediately.

No particular CPU or RAM reduction is guaranteed; measure the whole app and its WebKit processes on the target device.

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
- Native state changes are coalesced per main queue turn; unchanged values do not trigger UI publication.
- Playback integration uses media and navigation events without polling. Watch-page controls use a filtered discovery observer and bounded startup retries for at most 10 seconds, confirming the requested layout before stopping. Scoped attribute observation handles reused player elements; only chat observation remains after the layout is confirmed.
- One document-end script applies saved settings, and mode changes update it for future navigation.
- Teardown stops playback/loading and removes KVO, notification observers, and user scripts.

## Validation

Run the dependency-free playback regression tests with Node.js 22 or newer:

    node --test Tests/*.test.mjs

The tests execute the JavaScript embedded in the Swift source and cover preview pausing, style cleanup, speed persistence across media replacement, background pause behavior, seeking boundaries, chat consent, theatre/miniplayer transitions, delayed controls, and script lifecycle. They use DOM/media fixtures; they do not validate the live YouTube website or native window behavior. The Verify workflow also compiles the Intel app with a macOS SDK.

For device checks and a repeatable resource measurement procedure, see [Performance validation](docs/performance.md).

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
