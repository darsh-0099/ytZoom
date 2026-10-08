// Event-driven page integration: no timers, polling, or DOM-wide observers.
enum PlaybackScript {
    static let source = """
    (() => {
      const host = location.hostname.toLowerCase();
      if (!(host === 'youtube.com' || host.endsWith('.youtube.com'))) return;
      if (window.__ytzoom) return;
      let settings = { css: '', rate: 1, pauseWhenHidden: false, suppressPreviews: false };
      const playerVideo = () => document.querySelector('#movie_player video');
      const isPlayer = video => video && video === playerVideo();
      const applyRate = video => {
        if (isPlayer(video) && video.playbackRate !== settings.rate) {
          video.playbackRate = settings.rate;
        }
      };
      const pausePreview = video => {
        if (settings.suppressPreviews && video && typeof video.closest === 'function' &&
            video.closest('ytd-moving-thumbnail-renderer, ytd-video-preview')) video.pause();
      };
      const pauseHidden = video => {
        if (settings.pauseWhenHidden && document.hidden && isPlayer(video)) video.pause();
      };
      const configure = next => {
        settings = {
          css: typeof next.css === 'string' ? next.css : '',
          rate: [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2].includes(next.rate) ? next.rate : 1,
          pauseWhenHidden: next.pauseWhenHidden === true,
          suppressPreviews: next.suppressPreviews === true
        };
        let style = document.getElementById('ytzoom-style');
        if (!settings.css) {
          if (style) style.remove();
        } else {
          if (!style) {
            style = document.createElement('style');
            style.id = 'ytzoom-style';
            (document.head || document.documentElement).appendChild(style);
          }
          if (style.textContent !== settings.css) style.textContent = settings.css;
        }
        if (settings.suppressPreviews) {
          document.querySelectorAll('ytd-moving-thumbnail-renderer video, ytd-video-preview video')
            .forEach(pausePreview);
        }
        const video = playerVideo();
        applyRate(video);
        pauseHidden(video);
      };
      const command = name => {
        const video = playerVideo();
        if (!video) return;
        if (name === 'toggle') {
          if (video.paused) {
            const result = video.play();
            if (result) result.catch(() => {});
          } else video.pause();
        } else if (name === 'backward' || name === 'forward') {
          const ranges = video.seekable;
          if (!ranges || !ranges.length || !Number.isFinite(video.currentTime)) return;
          const target = video.currentTime + (name === 'backward' ? -10 : 10);
          // Respect live/DVR seek windows, including streams with infinite duration.
          for (let i = 0; i < ranges.length; i++) {
            const start = ranges.start(i), end = ranges.end(i);
            if (target <= end || i === ranges.length - 1) {
              video.currentTime = Math.min(end, Math.max(start, target));
              break;
            }
          }
        }
      };
      document.addEventListener('loadedmetadata', event => {
        applyRate(event.target);
        pauseHidden(event.target);
      }, true);
      document.addEventListener('play', event => {
        pausePreview(event.target);
        applyRate(event.target);
        pauseHidden(event.target);
      }, true);
      document.addEventListener('visibilitychange', () => pauseHidden(playerVideo()));
      document.addEventListener('yt-navigate-finish', () => {
        applyRate(playerVideo());
        pauseHidden(playerVideo());
      });
      window.__ytzoom = { configure, command };
    })();
    """
}
