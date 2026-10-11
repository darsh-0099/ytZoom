// Event-driven integration: no polling, timers, or DOM mutation observers.
enum PlaybackScript {
    static let source = """
    (() => {
      const host = location.hostname.toLowerCase();
      if (!(host === 'youtube.com' || host.endsWith('.youtube.com')) || window.__ytzoom) return;
      let settings = null, cachedVideo = null, lastReportedPlaying = null;
      let pendingRestore = window.__ytzoomResume || null;
      let restorePaused = pendingRestore?.paused === true;
      const restoreID = pendingRestore?.videoID;
      const focusCSS = 'ytd-watch-flexy #related, ytd-watch-flexy #comments { display: none !important; }';
      const playerVideo = () => {
        if (cachedVideo?.isConnected && cachedVideo.closest('#movie_player')) return cachedVideo;
        cachedVideo = document.querySelector('#movie_player video');
        return cachedVideo;
      };
      const isPlayer = video => {
        if (!video || (typeof video.closest === 'function' && !video.closest('#movie_player'))) return false;
        return video === playerVideo();
      };
      const videoID = () => new URL(location.href).searchParams.get('v');
      const isAd = video => !!video?.closest?.('.ytp-ad-showing');
      const applyRate = video => {
        if (settings && isPlayer(video) && video.playbackRate !== settings.rate) video.playbackRate = settings.rate;
      };
      const pausePreview = video => {
        if (settings?.suppressPreviews && video?.closest?.('ytd-moving-thumbnail-renderer, ytd-video-preview')) video.pause();
      };
      const pauseHidden = video => {
        if (settings?.pauseWhenHidden && document.hidden && isPlayer(video)) video.pause();
      };
      const reportPlayback = video => {
        if (!isPlayer(video)) return;
        const playing = !video.paused && !video.ended;
        if (playing === lastReportedPlaying) return;
        lastReportedPlaying = playing;
        window.webkit?.messageHandlers?.ytzoomLifecycle?.postMessage({ playing });
      };
      const applyRestore = video => {
        if (!restoreID || (!pendingRestore && !restorePaused)) return;
        if (videoID() !== restoreID) { pendingRestore = null; restorePaused = false; return; }
        if (!isPlayer(video) || isAd(video)) return;
        if (restorePaused && !video.paused) video.pause();
        if (!pendingRestore || !Number.isFinite(video.duration) || video.duration <= 0) return;
        const target = Math.min(Math.max(0, pendingRestore.time), Math.max(0, video.duration - 0.1));
        const ranges = video.seekable;
        for (let i = 0; ranges && i < ranges.length; i++) {
          if (target >= ranges.start(i) && target <= ranges.end(i)) {
            video.currentTime = target;
            pendingRestore = null;
            break;
          }
        }
      };
      const applyAppearance = () => {
        if (!settings) return;
        const root = document.documentElement;
        if (root.hasAttribute('dark') !== settings.darkMode) root.toggleAttribute('dark', settings.darkMode);
        const scheme = settings.darkMode ? 'dark' : 'light';
        if (root.style.colorScheme !== scheme) root.style.colorScheme = scheme;
      };
      const configure = next => {
        const previous = settings;
        const normalized = {
          css: typeof next.css === 'string' ? next.css : '',
          rate: [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2].includes(next.rate) ? next.rate : 1,
          pauseWhenHidden: next.pauseWhenHidden === true,
          suppressPreviews: next.suppressPreviews === true,
          darkMode: next.darkMode === true,
          focusViewing: next.focusViewing === true
        };
        if (previous && Object.keys(normalized).every(key => previous[key] === normalized[key])) return;
        settings = normalized;
        if (!previous || previous.darkMode !== settings.darkMode) applyAppearance();
        if (!previous || previous.css !== settings.css || previous.focusViewing !== settings.focusViewing) {
          const css = settings.css + (settings.focusViewing ? focusCSS : '');
          let style = document.getElementById('ytzoom-style');
          if (!css) {
            if (style) style.remove();
          } else {
            if (!style) {
              style = document.createElement('style');
              style.id = 'ytzoom-style';
              (document.head || document.documentElement).appendChild(style);
            }
            if (style.textContent !== css) style.textContent = css;
          }
        }
        if (settings.suppressPreviews && (!previous || !previous.suppressPreviews)) {
          document.querySelectorAll('ytd-moving-thumbnail-renderer video, ytd-video-preview video').forEach(pausePreview);
        }
        const video = playerVideo();
        if (!previous || previous.rate !== settings.rate) applyRate(video);
        if (!previous || previous.pauseWhenHidden !== settings.pauseWhenHidden) pauseHidden(video);
        applyRestore(video);
        reportPlayback(video);
      };
      const snapshot = () => {
        const video = playerVideo();
        const playing = Array.from(document.querySelectorAll('video, audio')).some(media =>
          !media.paused && !media.ended && !media.closest('ytd-moving-thumbnail-renderer, ytd-video-preview'));
        const hasDraft = document.documentElement.hasAttribute('data-ytzoom-chat-open') ||
          Array.from(document.querySelectorAll('textarea, input, [contenteditable="true"]')).some(field => {
            if (field.closest('ytd-searchbox')) return false;
            if (field.isContentEditable) return field.textContent.trim().length > 0;
            return typeof field.value === 'string' && field.value.trim().length > 0 && field.value !== field.defaultValue;
          });
        return { url: location.href, playing, hasDraft,
          videoID: document.querySelector('ytd-watch-flexy')?.getAttribute('video-id') || videoID(),
          time: video && Number.isFinite(video.currentTime) ? video.currentTime : null,
          live: !video || !Number.isFinite(video.duration), ad: isAd(video) };
      };
      const command = name => {
        const video = playerVideo();
        if (!video) return;
        if (name === 'toggle') {
          restorePaused = false;
          if (video.paused) { const result = video.play(); if (result) result.catch(() => {}); }
          else video.pause();
        } else if (name === 'backward' || name === 'forward') {
          const ranges = video.seekable;
          if (!ranges || !ranges.length || !Number.isFinite(video.currentTime)) return;
          const target = video.currentTime + (name === 'backward' ? -10 : 10);
          for (let i = 0; i < ranges.length; i++) {
            const start = ranges.start(i), end = ranges.end(i);
            if (target <= end || i === ranges.length - 1) {
              video.currentTime = Math.min(end, Math.max(start, target)); break;
            }
          }
        }
      };
      const mediaReady = event => {
        if (!isPlayer(event.target)) return;
        applyRate(event.target); applyRestore(event.target); pauseHidden(event.target); reportPlayback(event.target);
      };
      document.addEventListener('loadedmetadata', mediaReady, true);
      document.addEventListener('canplay', mediaReady, true);
      document.addEventListener('play', event => {
        pausePreview(event.target);
        mediaReady(event);
      }, true);
      document.addEventListener('pause', event => reportPlayback(event.target), true);
      document.addEventListener('visibilitychange', () => pauseHidden(playerVideo()));
      document.addEventListener('yt-navigate-finish', () => {
        cachedVideo = null;
        applyAppearance();
        const video = playerVideo();
        applyRate(video); applyRestore(video); pauseHidden(video); reportPlayback(video);
      });
      document.addEventListener('click', event => {
        if (event.isTrusted && event.target?.closest?.('.ytp-play-button, .ytp-large-play-button, .html5-video-container')) restorePaused = false;
      }, true);
      document.addEventListener('keydown', event => {
        if (event.isTrusted && !event.metaKey && !event.ctrlKey && !event.altKey &&
            [' ', 'k', 'K'].includes(event.key) &&
            !event.target?.closest?.('input, textarea, [contenteditable="true"]')) restorePaused = false;
      }, true);
      const goHome = () => {
        if (!['youtube.com', 'www.youtube.com'].includes(location.hostname)) return false;
        const link = document.querySelector('ytd-masthead a#logo[href]');
        if (!link?.href || new URL(link.href, location.href).pathname !== '/') return false;
        link.click(); // YouTube's existing link preserves its client-side navigation.
        return true;
      };
      window.__ytzoom = { configure, command, snapshot, goHome };
    })();
    """
}
