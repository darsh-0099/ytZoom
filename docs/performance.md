# Performance validation

Use a release build on the same Mac, with the same window size, account, video, playback quality, and power source. Allow YouTube to finish loading before recording. Record the macOS version, build revision, codec/resolution, and selected mode with each result.

In Activity Monitor, include ytZoom and its associated WebKit WebContent, networking, and GPU processes. Main-process memory alone does not represent the browser's footprint. For Instruments runs, inspect allocations, CPU samples, and wakeups over the same intervals.

Compare the baseline and the changed build in these scenarios:

| Scenario | Procedure | What to observe |
| --- | --- | --- |
| Idle home | Stay on Home for 60 seconds after loading | CPU, memory, wakeups, preview playback |
| Playback | Play the same video for two minutes at a fixed resolution | CPU, memory, buffering, dropped frames in YouTube's Stats for nerds |
| Hidden | Enable Pause when hidden, then minimize for 60 seconds | Media pauses; background CPU compared with the option disabled |
| Unloaded | Choose Unload page, then wait 60 seconds | Page disappears; no audio; eventual resource reclamation |
| Repeated lifecycle | Navigate, unload, and resume 20 times | No accumulation of web views/observers; memory trend after settling |

Repeat each scenario at least three times and report the median and range. This repository does not yet include measured before/after results. WebKit retains caches and may reuse helper processes; immediate process exit is not a success criterion.

## Functional checks on macOS

- Hide with Command-H and minimize with Command-M. With Pause when hidden enabled, audio stops and remains paused on return. With the option disabled, background listening continues according to YouTube/WebKit behavior.
- Change speed, then navigate within YouTube to another video. The saved speed applies to the new player. Confirm normal playback, ads, fullscreen, and live streams still work.
- Seek near the start/end of an ordinary video and the edge of a live DVR window. Confirm seeking stays inside the seekable range.
- Switch Balanced → Eco → Compatibility while a preview is playing. Compatibility removes injected styles and allows future previews; stopped previews are not forcibly restarted.
- Unload during playback and during navigation. Confirm the page is removed, audio stops, and no stale navigation errors appear. Resume, search, and Home should load the expected address. Cookies remain available; back/forward history and playback position reset.
- Close/reopen the window and quit/relaunch. Confirm stored mode, background option, and speed persist. The app offers one browsing window.
- Visit a Google sign-in page or an unrelated address. Playback scripts should have no effect there.
