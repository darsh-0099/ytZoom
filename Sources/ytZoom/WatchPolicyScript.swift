// A bounded discovery observer handles YouTube's asynchronously mounted controls.
// Once settled, only the chat's collapsed attribute is observed; there is no polling.
enum WatchPolicyScript {
    static let bootstrap = """
    (() => {
      const host = location.hostname.toLowerCase();
      if (!(host === 'youtube.com' || host.endsWith('.youtube.com'))) return;
      const root = document.documentElement;
      if (!root || document.getElementById('ytzoom-chat-policy')) return;
      const style = document.createElement('style');
      style.id = 'ytzoom-chat-policy';
      style.textContent = 'html:not([data-ytzoom-chat-open]) ytd-live-chat-frame #chatframe { display: none !important; }';
      root.appendChild(style);
    })();
    """

    static let source = """
    (() => {
      const host = location.hostname.toLowerCase();
      if (!(host === 'youtube.com' || host.endsWith('.youtube.com')) || window.__ytzoomWatch) return;
      const relevant = 'ytd-watch-flexy, ytd-live-chat-frame, #movie_player, .ytp-size-button, .ytp-miniplayer-button';
      const videoID = () => location.pathname === '/watch' ? new URL(location.href).searchParams.get('v') : null;
      const isMini = () => !!document.querySelector(
        '#movie_player.ytp-player-minimized, ytd-miniplayer[active], ytd-app[miniplayer-is-active]');
      let currentID = null, preferMini = null, clickedMini = null, layoutApplied = false;
      let chat = null, chatObserver = null, chatAllowed = false, collapsePending = false;
      let discovery = null, discoveryTimer = null;
      try {
        const previous = JSON.parse(sessionStorage.getItem('ytzoom.previousPlayer') || 'null');
        sessionStorage.removeItem('ytzoom.previousPlayer');
        if (previous && previous.id !== videoID()) preferMini = previous.mini === true;
      } catch (_) {}
      const gateChat = () => document.documentElement.toggleAttribute('data-ytzoom-chat-open', chatAllowed);
      const stopDiscovery = () => {
        if (discovery) discovery.disconnect();
        discovery = null;
        if (discoveryTimer !== null) clearTimeout(discoveryTimer);
        discoveryTimer = null;
      };
      const releaseChat = () => {
        if (chatObserver) chatObserver.disconnect();
        chatObserver = null; chat = null; collapsePending = false;
      };
      const collapseChat = () => {
        if (!chat || chatAllowed) return;
        if (chat.hasAttribute('collapsed')) { collapsePending = false; return; }
        if (collapsePending) return;
        const button = chat.querySelector('#show-hide-button button');
        if (!button || button.disabled) return;
        collapsePending = true;
        // Use YouTube's own collapse action so it can dispose of the chat iframe.
        button.click();
      };
      const bindChat = () => {
        const next = document.querySelector('ytd-live-chat-frame');
        if (next !== chat) {
          releaseChat(); chat = next;
          if (chat) {
            chatObserver = new MutationObserver(collapseChat);
            chatObserver.observe(chat, { attributes: true, attributeFilter: ['collapsed'], childList: true, subtree: true });
          }
        }
        collapseChat();
      };
      const applyLayout = () => {
        if (layoutApplied || !videoID()) return;
        const watch = document.querySelector('ytd-watch-flexy');
        if (!watch || watch.hasAttribute('hidden')) return;
        const renderedID = watch.getAttribute('video-id');
        if (renderedID && renderedID !== videoID()) return;
        // Keep explicit fullscreen/miniplayer choices made by the user.
        if (document.fullscreenElement || watch.hasAttribute('fullscreen') || isMini()) {
          layoutApplied = true; return;
        }
        if (preferMini !== true && watch.hasAttribute('theater')) {
          layoutApplied = true; return;
        }
        const selector = preferMini === true ? '.ytp-miniplayer-button' : '.ytp-size-button';
        const button = document.querySelector('#movie_player ' + selector);
        if (!button || button.disabled || button.getAttribute('aria-disabled') === 'true') return;
        layoutApplied = true; // Mark before click: YouTube may synchronously navigate.
        button.click();
      };
      const reconcile = () => {
        const id = videoID();
        if (id !== currentID) {
          currentID = id; layoutApplied = false;
          chatAllowed = false; collapsePending = false;
          gateChat();
        }
        bindChat(); applyLayout();
        if (layoutApplied && chat) stopDiscovery();
      };
      const discover = () => {
        stopDiscovery();
        reconcile();
        if (layoutApplied && chat) return;
        const root = document.querySelector('ytd-app') || document.body;
        if (!root) return;
        discovery = new MutationObserver(records => {
          // Ignore comment/recommendation churn unrelated to player/chat controls.
          if (records.some(record => Array.from(record.addedNodes).some(node =>
              node.nodeType === 1 && (node.matches(relevant) || node.querySelector(relevant))))) reconcile();
        });
        discovery.observe(root, { childList: true, subtree: true });
        discoveryTimer = setTimeout(stopDiscovery, 10000);
      };
      document.addEventListener('click', event => {
        if (!event.isTrusted || !event.target || typeof event.target.closest !== 'function') return;
        const toggle = event.target.closest('ytd-live-chat-frame #show-hide-button');
        if (toggle) {
          const frame = toggle.closest('ytd-live-chat-frame');
          chatAllowed = frame.hasAttribute('collapsed');
          gateChat();
        }
        const link = event.target.closest('a[href]');
        if (link) {
          const target = new URL(link.href, location.href);
          if (target.origin === location.origin && target.pathname === '/watch' &&
              target.searchParams.get('v') !== currentID) clickedMini = isMini();
        }
      }, true);
      document.addEventListener('yt-navigate-start', () => {
        preferMini = clickedMini === null ? isMini() : clickedMini;
        clickedMini = null;
        stopDiscovery(); releaseChat();
        chatAllowed = false; gateChat();
      });
      document.addEventListener('yt-navigate-finish', discover);
      document.addEventListener('yt-player-updated', reconcile);
      document.addEventListener('yt-page-data-updated', reconcile);
      document.addEventListener('loadedmetadata', reconcile, true);
      window.addEventListener('pagehide', () => {
        try { sessionStorage.setItem('ytzoom.previousPlayer', JSON.stringify({ id: currentID, mini: isMini() })); } catch (_) {}
        stopDiscovery(); releaseChat();
      });
      // Restore observers if WebKit returns this document from its history cache.
      window.addEventListener('pageshow', event => { if (event.persisted) discover(); });
      window.__ytzoomWatch = true;
      gateChat(); discover();
    })();
    """
}
