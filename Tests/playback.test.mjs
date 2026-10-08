import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';

// Execute the exact JavaScript shipped in the Swift literal, with a small media/DOM fixture.
const swift = readFileSync(new URL('../Sources/ytZoom/PlaybackScript.swift', import.meta.url), 'utf8');
const source = swift.match(/static let source = """\n([\s\S]*?)\n    """/)[1];
function page(host = 'www.youtube.com') {
  const listeners = new Map(), styles = new Map();
  const video = {
    paused: false, playbackRate: 1, currentTime: 25, pauses: 0,
    seekable: { length: 1, start: () => 0, end: () => 100 },
    pause() { this.paused = true; this.pauses++; },
    play() { this.paused = false; return Promise.resolve(); }
  };
  let currentVideo = video;
  const document = {
    hidden: false,
    querySelector: () => currentVideo,
    querySelectorAll: () => [],
    getElementById: id => styles.get(id),
    createElement: () => ({ textContent: '', remove() { styles.delete(this.id); } }),
    head: { appendChild(style) { styles.set(style.id, style); } },
    addEventListener(name, handler) {
      const handlers = listeners.get(name) ?? [];
      handlers.push(handler); listeners.set(name, handlers);
    }
  };
  const window = {};
  const context = vm.createContext({ window, document, location: { hostname: host } });
  vm.runInContext(source, context);
  return { window, document, video, styles, listeners,
    configure: settings => window.__ytzoom.configure({ css: '', rate: 1, pauseWhenHidden: false, ...settings }),
    command: name => window.__ytzoom.command(name),
    emit: (name, target = currentVideo) => listeners.get(name)?.forEach(fn => fn({ target })),
    replaceVideo: next => { currentVideo = next; },
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
  assert.equal(p.listeners.size, 4);
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
