import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';

const swift = readFileSync(new URL('../Sources/ytZoom/WatchPolicyScript.swift', import.meta.url), 'utf8');
const source = swift.match(/static let source = """\n([\s\S]*?)\n    """/)[1];
const bootstrap = swift.match(/static let bootstrap = """\n([\s\S]*?)\n    """/)[1];
function page(options = {}) {
  const listeners = new Map(), windowListeners = new Map(), observers = [], timers = new Map(), storage = new Map();
  const styles = new Map();
  const location = {};
  const navigate = (id, path = '/watch') => {
    const url = new URL(`https://${options.host ?? 'www.youtube.com'}${path}?v=${id}`);
    Object.assign(location, { href: url.href, pathname: url.pathname, origin: url.origin, hostname: url.hostname });
  };
  navigate('first');
  if (options.previous) storage.set('ytzoom.previousPlayer', JSON.stringify(options.previous));
  const subscribe = (map, name, callback) => map.set(name, [...map.get(name) ?? [], callback]);
  const emit = (name, event = {}) => listeners.get(name)?.forEach(callback => callback(event));
  const emitWindow = (name, event = {}) => windowListeners.get(name)?.forEach(callback => callback(event));
  const notify = (target, type = 'attributes') => observers.filter(o => o.target === target)
    .forEach(o => o.callback([{ type, addedNodes: [{ nodeType: 1, matches: () => true }] }]));
  function element(attrs = []) {
    const attributes = new Map(attrs.map(a => Array.isArray(a) ? a : [a, '']));
    return {
      style: {},
      hasAttribute: a => attributes.has(a),
      getAttribute: a => attributes.get(a) ?? null,
      toggleAttribute(a, value) { if (value) attributes.set(a, ''); else attributes.delete(a); },
      setAttribute(a, value) { attributes.set(a, value); },
      appendChild(style) { styles.set(style.id, style); }
    };
  }
  const root = element();
  const app = element();
  const watch = element([['video-id', 'first'], ...(options.theater ? ['theater'] : []), ...(options.hidden ? ['hidden'] : [])]);
  let mini = options.mini ?? false;
  let hasWatch = true, hasChat = options.chat ?? true, hasControls = options.controls ?? true;
  let hasChatButton = options.chatButton ?? true;
  const chat = element(options.collapsed ? ['collapsed'] : []);
  chat.querySelector = () => hasChatButton ? chatButton : null;
  const chatButton = {
    disabled: false, clicks: 0,
    click() {
      this.clicks++;
      if (!options.asyncChat) {
        chat.toggleAttribute('collapsed', !chat.hasAttribute('collapsed')); notify(chat);
      }
    },
    closest(selector) {
      if (selector.includes('#show-hide-button')) return { closest: () => chat };
      return null;
    }
  };
  let theatreRequests = 0;
  watch.dispatchEvent = event => {
    assert.equal(event.type, 'yt-set-theater-mode-enabled');
    assert.equal(event.detail.enabled, true);
    theatreRequests++;
    if (options.eventTheatre && theatreRequests >= options.eventTheatre) watch.toggleAttribute('theater', true);
  };
  const sizeButton = { disabled: false, clicks: 0, getAttribute: () => null,
    click() {
      this.clicks++;
      if (!options.asyncTheatre && this.clicks > (options.ignoredClicks ?? 0)) {
        watch.toggleAttribute('theater', !watch.hasAttribute('theater'));
      }
    } };
  const miniButton = { disabled: false, clicks: 0, getAttribute: () => null,
    click() { this.clicks++; mini = true; } };
  const document = {
    documentElement: root, body: app, fullscreenElement: null,
    getElementById: id => styles.get(id), createElement: () => ({ style: {} }),
    querySelector(selector) {
      if (selector === 'ytd-app') return app;
      if (selector === 'ytd-watch-flexy') return hasWatch ? watch : null;
      if (selector === 'ytd-live-chat-frame') return hasChat ? chat : null;
      if (selector === '#movie_player .ytp-size-button') return hasControls ? sizeButton : null;
      if (selector === '#movie_player .ytp-miniplayer-button') return hasControls ? miniButton : null;
      if (selector.includes('ytp-player-minimized')) return mini ? {} : null;
      throw new Error('Unexpected selector: ' + selector);
    },
    addEventListener: (name, callback) => subscribe(listeners, name, callback)
  };
  const window = { addEventListener: (name, callback) => subscribe(windowListeners, name, callback) };
  class Observer {
    constructor(callback) { this.callback = callback; this.target = null; observers.push(this); }
    observe(target, options) { this.target = target; this.options = options; }
    disconnect() { this.target = null; }
  }
  const context = vm.createContext({ window, document, location, URL, MutationObserver: Observer,
    CustomEvent: class { constructor(type, options) { this.type = type; Object.assign(this, options); } },
    sessionStorage: { getItem: key => storage.get(key) ?? null, setItem: (k, v) => storage.set(k, v), removeItem: k => storage.delete(k) },
    setTimeout: (callback, delay) => { const key = Symbol(); timers.set(key, { callback, delay }); return key; },
    clearTimeout: key => timers.delete(key)
  });
  const inject = () => { vm.runInContext(bootstrap, context); vm.runInContext(source, context); };
  inject();
  return { root, watch, chat, chatButton, sizeButton, miniButton, document, styles, observers, timers, window, storage,
    emit, emitWindow, notify, inject,
    setMini: value => { mini = value; },
    setControls: value => { hasControls = value; },
    setChatButton: value => { hasChatButton = value; },
    setChat: value => { hasChat = value; },
    setWatch: value => { hasWatch = value; },
    setLocation: navigate,
    next(id = 'second') { emit('yt-navigate-start'); navigate(id); watch.setAttribute('video-id', id); emit('yt-navigate-finish'); },
    clickChat() { emit('click', { isTrusted: true, target: chatButton }); chatButton.click(); },
    advanceLayout() {
      for (const [key, timer] of [...timers]) {
        if (timer.delay === 500) { timers.delete(key); timer.callback(); }
      }
    },
    expireDiscovery() {
      for (const [key, timer] of [...timers]) {
        if (timer.delay === 10000) { timers.delete(key); timer.callback(); }
      }
    }
  };
}

test('normal watch videos open in theatre mode once, allowing later manual changes', () => {
  const p = page(); assert.equal(p.sizeButton.clicks, 1);
  p.watch.toggleAttribute('theater', false);
  p.emit('loadedmetadata'); p.emit('yt-player-updated');
  assert.equal(p.sizeButton.clicks, 1);
  p.next(); assert.equal(p.sizeButton.clicks, 2);
});
test('already-theatre and fullscreen videos are not toggled out of their mode', () => {
  const p = page({ theater: true }); assert.equal(p.sizeButton.clicks, 0);
  p.watch.toggleAttribute('fullscreen', true); p.watch.toggleAttribute('theater', false);
  p.next(); assert.equal(p.sizeButton.clicks, 0);
});
test('new video stays in an active miniplayer', () => {
  const p = page({ mini: true }); p.next();
  assert.equal(p.sizeButton.clicks, 0); assert.equal(p.miniButton.clicks, 0);
});
test('miniplayer navigation returns the replacement video to miniplayer if YouTube expands it', () => {
  const p = page(); p.setMini(true); p.emit('yt-navigate-start');
  p.setLocation('second'); p.watch.setAttribute('video-id', 'second'); p.setMini(false);
  p.emit('yt-navigate-finish'); p.emit('loadedmetadata');
  assert.equal(p.miniButton.clicks, 1); assert.equal(p.sizeButton.clicks, 1);
});
test('click capture retains mini intent if navigation clears mini before navigate-start', () => {
  const p = page(); p.setMini(true);
  const link = { href: locationURL('second') };
  p.emit('click', { isTrusted: true, target: { closest: selector => selector === 'a[href]' ? link : null } });
  p.setMini(false); p.next();
  assert.equal(p.miniButton.clicks, 1);
});
function locationURL(id) { return `https://www.youtube.com/watch?v=${id}`; }
test('full document navigation can carry mini intent to a different video', () => {
  const p = page({ previous: { id: 'previous', mini: true } });
  assert.equal(p.miniButton.clicks, 1); assert.equal(p.sizeButton.clicks, 0);
  assert.equal(p.storage.has('ytzoom.previousPlayer'), false);
});
test('live chat and replay start collapsed and only open after a trusted click', () => {
  const p = page(); assert.equal(p.chat.hasAttribute('collapsed'), true);
  assert.equal(p.root.hasAttribute('data-ytzoom-chat-open'), false);
  p.clickChat(); assert.equal(p.root.hasAttribute('data-ytzoom-chat-open'), true);
  assert.equal(p.chat.hasAttribute('collapsed'), false);
  p.emit('loadedmetadata'); assert.equal(p.chat.hasAttribute('collapsed'), false);
  p.clickChat(); assert.equal(p.root.hasAttribute('data-ytzoom-chat-open'), false);
  assert.equal(p.chat.hasAttribute('collapsed'), true);
});
test('chat permission resets for the next video and ignores programmatic clicks', () => {
  const p = page(); p.clickChat(); p.next();
  assert.equal(p.chat.hasAttribute('collapsed'), true);
  assert.equal(p.root.hasAttribute('data-ytzoom-chat-open'), false);
  p.emit('click', { isTrusted: false, target: p.chatButton });
  assert.equal(p.root.hasAttribute('data-ytzoom-chat-open'), false);
});
test('unexpected chat auto-expansion is collapsed again', () => {
  const p = page({ collapsed: true });
  p.chat.toggleAttribute('collapsed', false); p.notify(p.chat);
  assert.equal(p.chat.hasAttribute('collapsed'), true);
});
test('asynchronous chat collapse is not repeatedly toggled', () => {
  const p = page({ asyncChat: true });
  p.emit('loadedmetadata'); p.emit('yt-player-updated'); p.notify(p.chat);
  assert.equal(p.chatButton.clicks, 1);
});
test('late chat controls are handled by the scoped chat observer', () => {
  const p = page({ chatButton: false }); assert.equal(p.chatButton.clicks, 0);
  p.setChatButton(true); p.notify(p.chat, 'childList');
  assert.equal(p.chat.hasAttribute('collapsed'), true);
});
test('delayed player controls and mismatched old player IDs wait for readiness', () => {
  const p = page({ controls: false }); assert.equal(p.sizeButton.clicks, 0);
  p.setControls(true); p.watch.setAttribute('video-id', 'old'); p.emit('loadedmetadata');
  assert.equal(p.sizeButton.clicks, 0);
  p.watch.setAttribute('video-id', 'first'); p.notify(p.document.body, 'childList');
  p.advanceLayout();
  assert.equal(p.sizeButton.clicks, 1);
});
test('discovery expires without ongoing polling, and teardown disconnects all observers', () => {
  const p = page({ chat: false }); assert.equal(p.timers.size, 1);
  p.expireDiscovery(); assert.equal(p.timers.size, 0);
  assert.equal(p.observers.filter(o => o.target).length, 0);
  p.setChat(true); p.emit('yt-navigate-finish'); p.setMini(true); p.emitWindow('pagehide');
  assert.equal(p.observers.filter(o => o.target).length, 0);
  assert.equal(JSON.parse(p.storage.get('ytzoom.previousPlayer')).mini, true);
  p.emitWindow('pageshow', { persisted: true });
  assert.equal(p.observers.filter(o => o.target).length, 1);
  assert.doesNotMatch(source, /setInterval/);
});
test('non-watch routes never trigger layout and reinjection installs no duplicate policy', () => {
  const p = page(); p.setLocation('', '/results'); p.emit('yt-navigate-finish');
  assert.equal(p.sizeButton.clicks, 1); const count = p.observers.length; p.inject();
  assert.equal(p.observers.length, count); assert.equal(p.styles.size, 1);
});
test('chat policy and player changes are restricted to YouTube domains', () => {
  for (const host of ['accounts.google.com', 'youtube.com.evil.test']) {
    const p = page({ host }); assert.equal(p.window.__ytzoomWatch, undefined);
    assert.equal(p.styles.size, 0); assert.equal(p.observers.length, 0);
  }
});

test('ignored early click is not success; idempotent theatre request retries until confirmed', () => {
  const p = page({ ignoredClicks: 1, eventTheatre: 1 });
  assert.equal(p.sizeButton.clicks, 1);
  assert.equal(p.watch.hasAttribute('theater'), false);
  p.advanceLayout();
  assert.equal(p.watch.hasAttribute('theater'), true);
  assert.equal(p.sizeButton.clicks, 1);
  assert.equal(p.timers.size, 0);
});
test('a native button whose handler binds late is retried after initialization', () => {
  const p = page({ ignoredClicks: 1 });
  for (let i = 0; i < 4; i++) p.advanceLayout();
  assert.equal(p.watch.hasAttribute('theater'), true);
  assert.equal(p.sizeButton.clicks, 2);
  assert.equal(p.timers.size, 0);
});
test('asynchronous theatre confirmation cancels retries before another toggle', () => {
  const p = page({ asyncTheatre: true });
  assert.equal(p.watch.hasAttribute('theater'), false);
  p.watch.toggleAttribute('theater', true); p.notify(p.watch);
  p.advanceLayout();
  assert.equal(p.sizeButton.clicks, 1);
  assert.equal(p.timers.size, 0);
  p.watch.toggleAttribute('theater', false); p.emit('loadedmetadata');
  assert.equal(p.sizeButton.clicks, 1);
});
test('reused hidden watch container is retried when attributes change without new DOM nodes', () => {
  const p = page({ hidden: true }); assert.equal(p.sizeButton.clicks, 0);
  p.watch.toggleAttribute('hidden', false); p.notify(p.watch); p.advanceLayout();
  assert.equal(p.watch.hasAttribute('theater'), true);
});
test('startup retries are bounded and navigation teardown cancels pending work', () => {
  const p = page({ controls: false });
  for (let i = 0; i < 25; i++) p.advanceLayout();
  p.expireDiscovery();
  assert.equal(p.timers.size, 0);
  assert.equal(p.observers.filter(o => o.target).length, 1); // Chat only.
  const next = page({ asyncTheatre: true });
  next.emit('yt-navigate-start');
  assert.equal(next.timers.size, 0);
  assert.equal(next.observers.filter(o => o.target).length, 0);
});
test('bootstrap seeds the native wide-player preference', () => {
  const p = page(); assert.match(p.document.cookie, /^wide=1;/);
});
