# ytZoom

**ytZoom** is an experimental lightweight macOS desktop client for YouTube. It wraps YouTube in a native SwiftUI window using Apple's WebKit, without bundling Electron or a Chromium runtime.

The project explores whether avoiding a full standalone browser framework and reducing unnecessary website animation can offer a leaner experience. No particular CPU, RAM, or battery-life savings are guaranteed.

## Features

- Native macOS window with history, home, reload, URL/search field, and system-browser handoff
- One app window and one WKWebView, with saved website data and cookies
- Unload/resume preserves on-demand video position and resumes paused
- Hidden idle YouTube pages unload after 5 minutes, configurable to 15/30 minutes or Never
- Active playback, unfinished comments, and open chat prevent automatic unloading
- Optional native media suspension when hidden or minimized, without automatic playback on return
- Optional Focus viewing hides recommendations and comments
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

Balanced and Eco pause video elements in recognized thumbnail preview containers and block animated WebP preview images using a cached WebKit content rule. Video streams, standard thumbnails, and player API requests are outside that rule. They also defer rendering of offscreen video cards and comment threads when the installed WebKit supports `content-visibility`. Eco additionally reduces selected interface motion. Compatibility removes the preview/style adjustments; playback controls and the independently selected background pause option remain available. These modes do not replace the YouTube player or disable website scripts.

**Pause when hidden** is off by default so background listening keeps working. Enable it to pause when the app is hidden, minimized, or WebKit reports the page as hidden. Returning to the window leaves playback paused until manually resumed. WebKit's public media suspension API prevents media from restarting while hidden. Website scripts can still run until the page is unloaded.

**Unload page**, available in the toolbar’s Playback options menu, stops media and navigation, detaches observers, and destroys the web view. Resume creates a new view at the last address using the same persistent cookies and website data. On-demand video position is captured and restored paused when available. Ads and live streams do not produce saved seek positions. Navigation history and unsaved page state are reset. Searching or choosing Home while unloaded also resumes the page. WebKit decides when to reclaim helper-process memory, so memory usage may not fall immediately.

**Idle unloading** applies only to hidden/minimized YouTube pages and uses a single delayed task. The final decision checks native media playback, buffering media, unfinished text input, and the current URL. Automatically unloaded pages restore when the window returns; manually unloaded pages wait for Resume. Cookie and disk caches are retained. Set the timeout to Never to keep paused pages loaded.

**Focus viewing** hides recommendations and comments independently of performance mode. It reduces their rendering; it does not claim to prevent YouTube from fetching or constructing those sections.

No particular CPU or RAM reduction is guaranteed; measure the whole app and its WebKit processes on the target device.

## Download

Published Intel macOS ZIPs are on the [Releases page](../../releases/latest). Development builds are downloadable artifacts from the [Verify workflow](.github/workflows/verify.yml). After extracting the ZIP, drag **ytZoom.app** to Applications and open it in Finder. A successful prebuilt release does **not** require Xcode or Terminal.

The app is ad-hoc signed, **not Developer ID signed or notarized**. macOS may initially block it. If you trust the release, right-click and choose Open; if needed, use System Settings → Privacy & Security → Open Anyway. Production distribution should use Developer ID signing and notarization.

## Building from source

The [GitHub Actions workflow](.github/workflows/build-macos.yml) builds on a hosted Intel macOS runner and publishes a downloadable application ZIP after a successful build.

Source files are in Sources/ytZoom. Developers with a compatible Swift toolchain and macOS SDK can build using the following command:

    swift build --configuration release --arch x86_64

## Architecture

- SwiftUI provides the desktop toolbar, modes, navigation, and search.
- WebKit loads the standard YouTube website in one persistent web view.
- Standard WebKit website storage preserves cookies and preferences.
- Native navigation state is coalesced into one snapshot. Loading-progress updates affect only a small progress view.
- Immutable integration scripts and serialized settings are cached. Unchanged settings do not touch the DOM.
- Main-player references and playback-state messages are cached/deduplicated; no media polling is used.
- The Home control tries YouTube's existing link for client-side navigation, with a bounded full-load fallback.
- Playback integration uses media and navigation events without polling. Watch-page controls use a filtered discovery observer and bounded startup retries for at most 10 seconds, confirming the requested layout before stopping. Scoped attribute observation handles reused player elements; only chat observation remains after the layout is confirmed.
- Small document-start configuration scripts initialize cached integration scripts for future navigation.
- A weak script-message handler prevents the content controller from retaining the browser coordinator.
- Instruments signposts record navigation, unload, and resume without URLs or browsing data.
- Teardown stops playback/loading and removes KVO, notification observers, and user scripts.

## Validation

Run the dependency-free playback regression tests with Node.js 22 or newer:

    node --test Tests/*.test.mjs

The tests execute the JavaScript embedded in the Swift source and cover preview pausing, style cleanup, speed persistence across media replacement, background pause behavior, seeking boundaries, chat consent, theatre/miniplayer transitions, delayed controls, and script lifecycle. They use DOM/media fixtures; they do not validate the live YouTube website or native window behavior. The Verify workflow also runs Swift tests for idle/restore policies, compiles the preview rule in WebKit, and executes playback integration inside a native WKWebView fixture before packaging the Intel app.

Run native checks with `swift test --configuration release --arch x86_64` on a compatible macOS development host.

[Settings operation counts](Benchmarks/settings-operation-counts.json) compare version 0.1.1 and this version under 1,000 identical settings updates. The new implementation makes zero repeated player queries, preview scans, style lookups, or appearance changes in that fixture. This measures script operations, not real YouTube CPU, memory, or frame rate. Reproduce the current check with `node Benchmarks/playback.mjs`.

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
