import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';

// Execute the exact JavaScript shipped in the Swift literal, with a small media/DOM fixture.
const swift = readFileSync(new URL('../Sources/ytZoom/PlaybackScript.swift', import.meta.url), 'utf8');
const source = swift.match(/static let source = """\n([\s\S]*?)\n    """/)[1];
function page(host = 'www.youtube.com', options = {}) {
  const listeners = new Map(), styles = new Map();
  const stats = { queries: 0, previewScans: 0, styleWrites: 0, appearanceWrites: 0 };
  const messages = [];
  let currentID = options.videoID ?? 'first';
  const mainContainer = {};
  const video = {
    paused: false, ended: false, isConnected: true, duration: 100,
    closest(selector) { return selector === '#movie_player' ? mainContainer : null; },
    playbackRate: 1, currentTime: 25, pauses: 0,
    seekable: { length: 1, start: () => 0, end: () => 100 },
    pause() { this.paused = true; this.pauses++; },
    play() { this.paused = false; return Promise.resolve(); }
  };
  let currentVideo = video;
  const document = {
    hidden: false,
    documentElement: { style: {}, dark: false,
      hasAttribute(name) { return name === 'dark' && this.dark; },
      toggleAttribute(_, value) { this.dark = value; stats.appearanceWrites++; } },
    querySelector: selector => {
      stats.queries++;
      return selector === 'ytd-watch-flexy' ? { getAttribute: () => currentID } : currentVideo;
    },
    querySelectorAll: selector => {
      if (selector === 'video, audio') return currentVideo ? [currentVideo, ...(options.otherMedia ?? [])] : [];
      stats.previewScans++; return [];
    },
    getElementById: id => styles.get(id),
    createElement: () => ({ _text: '',
      get textContent() { return this._text; },
      set textContent(value) { this._text = value; stats.styleWrites++; },
      remove() { styles.delete(this.id); } }),
    head: { appendChild(style) { styles.set(style.id, style); } },
    addEventListener(name, handler) {
      const handlers = listeners.get(name) ?? [];
      handlers.push(handler); listeners.set(name, handlers);
    }
  };
  const window = { __ytzoomResume: options.restore,
    webkit: { messageHandlers: { ytzoomLifecycle: { postMessage: body => messages.push(body) } } } };
  const location = { hostname: host, href: `https://${host}/watch?v=${currentID}` };
  const context = vm.createContext({ window, document, location, URL });
  vm.runInContext(source, context);
  return { window, document, video, styles, listeners, stats, messages,
    setVideoID: id => { currentID = id; location.href = `https://${host}/watch?v=${id}`; },
    configure: settings => window.__ytzoom.configure({ css: '', rate: 1, pauseWhenHidden: false, ...settings }),
    command: name => window.__ytzoom.command(name),
    emit: (name, target = currentVideo) => listeners.get(name)?.forEach(fn => fn({ target })),
    replaceVideo: next => { if (currentVideo) currentVideo.isConnected = false;
      currentVideo = next; if (next) next.isConnected = true; },
    reinject: () => vm.runInContext(source, context)
  };
}

test('restricts page integration to YouTube hosts', () => {
  for (const host of ['accounts.google.com', 'youtube.com.evil.test', 'notyoutube.com']) {
    assert.equal(page(host).window.__ytzoom, undefined);
  }
  assert.ok(page('youtube.com').window.__ytzoom);
});
test('installs listeners once and never starts background timers', () => {
  const p = page(); p.reinject();
  assert.equal(p.listeners.size, 8);
  for (const handlers of p.listeners.values()) assert.equal(handlers.length, 1);
  assert.doesNotMatch(source, /setInterval|setTimeout|MutationObserver/);
});
test('applies speed on settings change and media replacement during SPA navigation', () => {
  const p = page(); p.configure({ rate: 1.5 });
  assert.equal(p.video.playbackRate, 1.5);
  const next = { ...p.video, playbackRate: 1 };
  p.replaceVideo(next); p.emit('loadedmetadata');
  assert.equal(next.playbackRate, 1.5);
  next.playbackRate = 1; p.emit('yt-navigate-finish');
  assert.equal(next.playbackRate, 1.5);
});
test('does not change unrelated preview media speed', () => {
  const p = page(); p.configure({ rate: 2 });
  const preview = { ...p.video, playbackRate: 1 };
  p.emit('loadedmetadata', preview);
  assert.equal(preview.playbackRate, 1);
});
test('invalid playback rates fall back to normal speed', () => {
  const p = page();
  for (const rate of [0, -1, 9, NaN, '2']) {
    p.configure({ rate }); assert.equal(p.video.playbackRate, 1);
  }
});
test('style updates reuse one element and Compatibility removes it', () => {
  const p = page(); p.configure({ css: 'first' });
  const style = p.styles.get('ytzoom-style');
  p.configure({ css: 'second' });
  assert.equal(p.styles.size, 1);
  assert.equal(p.styles.get('ytzoom-style'), style);
  assert.equal(style.textContent, 'second');
  p.configure({ css: '' }); assert.equal(p.styles.size, 0);
});
test('hidden playback is opt-in and showing the page never autoplays', () => {
  const p = page(); p.document.hidden = true; p.emit('visibilitychange');
  assert.equal(p.video.paused, false);
  p.configure({ pauseWhenHidden: true }); assert.equal(p.video.paused, true);
  p.video.pauses = 0; p.emit('play'); assert.equal(p.video.pauses, 1);
  p.document.hidden = false; p.emit('visibilitychange');
  assert.equal(p.video.paused, true);
});
test('disabling hidden pause permits continued background playback', () => {
  const p = page(); p.configure({ pauseWhenHidden: true });
  p.configure({ pauseWhenHidden: false });
  p.document.hidden = true; p.emit('play');
  assert.equal(p.video.pauses, 0);
});
test('play/pause controls toggle only the player', () => {
  const p = page(); p.command('toggle'); assert.equal(p.video.paused, true);
  p.command('toggle'); assert.equal(p.video.paused, false);
});
test('seeking clamps to media boundaries', () => {
  const p = page(); p.video.currentTime = 3; p.command('backward');
  assert.equal(p.video.currentTime, 0);
  p.video.currentTime = 95; p.command('forward'); assert.equal(p.video.currentTime, 100);
});
test('live seeking respects the DVR window and unavailable ranges', () => {
  const p = page();
  p.video.seekable = { length: 1, start: () => 100, end: () => 200 };
  p.video.currentTime = 105; p.command('backward'); assert.equal(p.video.currentTime, 100);
  p.video.seekable.length = 0; p.command('forward'); assert.equal(p.video.currentTime, 100);
});
test('missing player and unknown commands are harmless', () => {
  const p = page(); p.command('unknown'); assert.equal(p.video.currentTime, 25);
  p.replaceVideo(null);
  p.configure({ rate: 2 }); p.command('toggle'); p.emit('yt-navigate-finish');
});

test('Balanced/Eco pauses existing and newly playing thumbnail previews', () => {
  const p = page();
  const preview = { pauses: 0, closest: () => ({}), pause() { this.pauses++; } };
  p.document.querySelectorAll = () => [preview];
  p.configure({ suppressPreviews: true }); assert.equal(preview.pauses, 1);
  p.emit('play', preview); assert.equal(preview.pauses, 2);
  p.configure({ suppressPreviews: false }); p.emit('play', preview);
  assert.equal(preview.pauses, 2);
  assert.equal(p.video.pauses, 0);
});

test('unchanged settings perform zero DOM queries, preview scans, or appearance writes', () => {
  const p = page(); const settings = { css: 'test', rate: 1.5, suppressPreviews: true };
  p.configure(settings); const before = { ...p.stats };
  for (let i = 0; i < 1000; i++) p.configure(settings);
  assert.deepEqual(p.stats, before);
});
test('speed-only changes do not rebuild styling or rescan previews', () => {
  const p = page(); p.configure({ css: 'test', suppressPreviews: true });
  const before = { ...p.stats };
  p.configure({ css: 'test', suppressPreviews: true, rate: 2 });
  assert.equal(p.stats.previewScans, before.previewScans);
  assert.equal(p.stats.styleWrites, before.styleWrites);
  assert.equal(p.stats.appearanceWrites, before.appearanceWrites);
});
test('connected main-player references are reused across media events', () => {
  const p = page(); p.configure({}); const queries = p.stats.queries;
  for (let i = 0; i < 1000; i++) p.emit('canplay');
  assert.equal(p.stats.queries, queries);
});
test('playback messages are emitted only on a state change', () => {
  const p = page(); p.configure({});
  for (let i = 0; i < 100; i++) p.emit('play');
  assert.equal(p.messages.length, 1);
  p.video.paused = true; p.emit('pause'); p.emit('pause');
  assert.equal(p.messages.length, 2);
  assert.equal(p.messages[1].playing, false);
});
test('snapshot detects other media and buffering before idle unloading', () => {
  const other = { paused: false, ended: false, closest: () => null };
  const p = page('www.youtube.com', { otherMedia: [other] }); p.video.paused = true;
  assert.equal(p.window.__ytzoom.snapshot().playing, true);
  other.paused = true; assert.equal(p.window.__ytzoom.snapshot().playing, false);
  p.video.paused = false; assert.equal(p.window.__ytzoom.snapshot().playing, true);
});
test('saved position is restored paused, and explicit play remains usable', () => {
  const p = page('www.youtube.com', { restore: { videoID: 'first', time: 60, paused: true } });
  p.configure({}); assert.equal(p.video.currentTime, 60); assert.equal(p.video.paused, true);
  p.video.paused = false; p.emit('play'); assert.equal(p.video.paused, true);
  p.command('toggle'); assert.equal(p.video.paused, false);
});
test('restore waits for a seekable range and does not seek advertisements', () => {
  const p = page('www.youtube.com', { restore: { videoID: 'first', time: 60, paused: true } });
  p.video.seekable.length = 0; p.configure({}); assert.equal(p.video.currentTime, 25);
  p.video.seekable.length = 1;
  p.video.closest = selector => selector === '.ytp-ad-showing' ? {} : selector === '#movie_player' ? {} : null;
  p.emit('canplay'); assert.equal(p.video.currentTime, 25);
  p.video.closest = selector => selector === '#movie_player' ? {} : null;
  p.emit('canplay'); assert.equal(p.video.currentTime, 60);
});
test('saved timestamp does not affect a different video', () => {
  const p = page('www.youtube.com', { restore: { videoID: 'previous', time: 60, paused: true } });
  p.configure({}); assert.equal(p.video.currentTime, 25); assert.equal(p.video.paused, false);
});
test('Focus viewing is independently reversible in Compatibility mode', () => {
  const p = page(); p.configure({ css: '', focusViewing: true });
  assert.match(p.styles.get('ytzoom-style').textContent, /#related/);
  p.configure({ css: '', focusViewing: false }); assert.equal(p.styles.size, 0);
});

test('unsubmitted comments prevent automatic idle unloading', () => {
  const p = page(); p.video.paused = true;
  const originalQuery = p.document.querySelectorAll;
  p.document.querySelectorAll = selector => selector.startsWith('textarea')
    ? [{ closest: () => null, isContentEditable: true, textContent: 'unfinished comment' }]
    : originalQuery(selector);
  assert.equal(p.window.__ytzoom.snapshot().hasDraft, true);
});

test('Home uses the existing native YouTube link, with an explicit fallback if missing', () => {
  const p = page(); const originalQuery = p.document.querySelector;
  assert.equal(p.window.__ytzoom.goHome(), false);
  let clicks = 0;
  p.document.querySelector = selector => selector.startsWith('ytd-masthead')
    ? { href: 'https://www.youtube.com/', click: () => clicks++ } : originalQuery(selector);
  assert.equal(p.window.__ytzoom.goHome(), true);
  assert.equal(clicks, 1);
});
