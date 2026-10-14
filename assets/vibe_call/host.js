// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Vibe call host. Like Sable, Vibe runs Element Call as a Matrix widget:
// this page holds the Element Call iframe and matrix-widget-api's
// ClientWidgetApi. Every Matrix request the widget makes (send an event,
// read state, to-device keys, OpenID for the call server) is forwarded to
// Vibe's Dart code over the "VibeHost" channel, which answers with the
// Matrix Dart SDK. Nothing here talks to the homeserver directly.
(function () {
  'use strict';

  const mx = window.mxwidgets;
  const pending = new Map();
  let seq = 0;
  let api = null;
  let iframe = null;
  let knownRooms = [];
  let soundOn = true;
  let soundTimer = null;

  function applySound() {
    try {
      const doc = iframe && (iframe.contentDocument || iframe.contentWindow.document);
      if (!doc) return;
      doc.querySelectorAll('audio').forEach(function (el) {
        el.muted = !soundOn;
      });
    } catch (e) {
      console.warn('Could not change call sound', e);
    }
  }

  function post(obj) {
    try {
      window.VibeHost.postMessage(JSON.stringify(obj));
    } catch (e) {
      console.error('VibeHost unavailable', e);
    }
  }

  function call(method, args) {
    return new Promise(function (resolve, reject) {
      const id = ++seq;
      pending.set(id, { resolve: resolve, reject: reject });
      post({ kind: 'rpc', id: id, method: method, args: args || {} });
    });
  }

  function notify(kind, data) {
    post({ kind: kind, data: data || {} });
  }

  // Anything that goes wrong ends up in Vibe's call log.
  function report(where, err) {
    const msg = err && (err.stack || err.message) ? (err.stack || err.message) : String(err);
    notify('error', { where: where, message: msg.slice(0, 2000) });
  }
  window.addEventListener('error', function (e) {
    report('host', e.error || e.message);
  });
  window.addEventListener('unhandledrejection', function (e) {
    report('host promise', e.reason);
  });
  if (!mx) report('host', 'matrix-widget-api did not load');

  // Vibe draws its own call controls, so Element Call's header and footer
  // (mute, camera, hang up, settings) are hidden inside the call view.
  const HIDE_CSS =
    '[class*="_footer_"], [class*="_header_"], [data-testid="incall_leave"],' +
    '[class*="_toggleLayout_"], [class*="_layoutToggle_"] {' +
    ' display: none !important; }';

  function styleCall() {
    try {
      const doc = iframe && (iframe.contentDocument || iframe.contentWindow.document);
      if (!doc || !doc.head || doc.getElementById('vibe-style')) return;
      const st = doc.createElement('style');
      st.id = 'vibe-style';
      st.textContent = HIDE_CSS;
      doc.head.appendChild(st);
      // forward Element Call's own errors too
      const w = iframe.contentWindow;
      w.addEventListener('error', function (e) {
        report('call', e.error || e.message);
      });
      w.addEventListener('unhandledrejection', function (e) {
        report('call promise', e.reason);
      });
    } catch (e) {
      report('style', e);
    }
  }

  class VibeDriver extends mx.WidgetDriver {
    // Vibe ships this Element Call build itself, so it gets what it asks for
    // (it only asks for its own room and call events).
    async validateCapabilities(requested) {
      return new Set(requested);
    }

    sendEvent(eventType, content, stateKey, roomId) {
      return call('sendEvent', {
        type: eventType,
        content: content,
        stateKey: stateKey === undefined ? null : stateKey,
        roomId: roomId || null,
      });
    }

    sendDelayedEvent(delay, parentDelayId, eventType, content, stateKey, roomId) {
      return call('sendDelayedEvent', {
        delay: delay === undefined ? null : delay,
        parentDelayId: parentDelayId === undefined ? null : parentDelayId,
        type: eventType,
        content: content,
        stateKey: stateKey === undefined ? null : stateKey,
        roomId: roomId || null,
      });
    }

    updateDelayedEvent(delayId, action) {
      return call('updateDelayedEvent', { delayId: delayId, action: action });
    }

    sendToDevice(eventType, encrypted, contentMap) {
      return call('sendToDevice', {
        type: eventType,
        encrypted: !!encrypted,
        contentMap: contentMap,
      });
    }

    readRoomTimeline(roomId, eventType, msgtype, stateKey, limit, since) {
      return call('readRoomTimeline', {
        roomId: roomId,
        type: eventType,
        msgtype: msgtype === undefined ? null : msgtype,
        stateKey: stateKey === undefined ? null : stateKey,
        limit: limit,
        since: since === undefined ? null : since,
      });
    }

    readRoomState(roomId, eventType, stateKey) {
      return call('readRoomState', {
        roomId: roomId,
        type: eventType,
        stateKey: stateKey === undefined ? null : stateKey,
      });
    }

    // Older widget API names, kept for safety.
    async readRoomEvents(eventType, msgtype, limit, roomIds, since) {
      const rooms = roomIds || [];
      const out = [];
      for (const r of rooms) {
        out.push(...(await this.readRoomTimeline(r, eventType, msgtype, undefined, limit, since)));
      }
      return out;
    }

    async readStateEvents(eventType, stateKey, limit, roomIds) {
      const rooms = roomIds || [];
      const out = [];
      for (const r of rooms) {
        out.push(...(await this.readRoomState(r, eventType, stateKey)));
      }
      return out.slice(0, limit > 0 ? limit : undefined);
    }

    readEventRelations(eventId, roomId, relationType, eventType, from, to, limit, direction) {
      return call('readEventRelations', {
        eventId: eventId,
        roomId: roomId || null,
        relationType: relationType || null,
        eventType: eventType || null,
        from: from || null,
        to: to || null,
        limit: limit || null,
        direction: direction || null,
      });
    }

    async askOpenID(observer) {
      try {
        const token = await call('openId', {});
        observer.update({ state: mx.OpenIDRequestState.Allowed, token: token });
      } catch (e) {
        observer.update({ state: mx.OpenIDRequestState.Blocked });
      }
    }

    async *getTurnServers() {
      try {
        const turn = await call('turnServers', {});
        if (turn && turn.uris && turn.uris.length) yield turn;
      } catch (e) {
        // LiveKit brings its own TURN; nothing to do.
      }
    }

    searchUserDirectory(searchTerm, limit) {
      return call('searchUserDirectory', { term: searchTerm, limit: limit || null });
    }

    getMediaConfig() {
      return call('getMediaConfig', {});
    }

    async uploadFile() {
      throw new Error('Uploads are not available in calls');
    }

    async downloadFile() {
      throw new Error('Downloads are not available in calls');
    }

    getKnownRooms() {
      return knownRooms;
    }

    processError(error) {
      if (error && error.matrixApiError) {
        return { matrix_api_error: error.matrixApiError };
      }
      return undefined;
    }
  }

  // Widget actions Element Call sends to its host. Each needs an answer,
  // otherwise the widget API reports "unsupported action".
  const handled = [
    'io.element.join',
    'im.vector.hangup',
    'io.element.close',
    'io.element.device_mute',
    'io.element.tile_layout',
    'io.element.spotlight_layout',
    'set_always_on_screen',
    'io.element.minimize',
  ];

  window.vibe = {
    reply: function (id, ok, value) {
      const p = pending.get(id);
      if (!p) return;
      pending.delete(id);
      if (ok) {
        p.resolve(value);
      } else {
        const err = new Error((value && value.message) || 'Request failed');
        if (value && value.matrix_api_error) err.matrixApiError = value.matrix_api_error;
        p.reject(err);
      }
    },

    start: function (cfg) {
      try {
        this._start(cfg);
      } catch (e) {
        report('start', e);
      }
    },

    _start: function (cfg) {
      knownRooms = cfg.knownRooms || [cfg.roomId];
      const widget = new mx.Widget({
        id: cfg.widgetId,
        creatorUserId: cfg.userId,
        name: 'Call',
        type: 'm.call',
        url: cfg.url,
        waitForIframeLoad: false,
        data: {},
      });
      iframe = document.createElement('iframe');
      iframe.title = 'Call';
      iframe.allow = 'microphone; camera; display-capture; autoplay; clipboard-write;';
      iframe.src = widget.getCompleteUrl({ currentUserId: cfg.userId });
      iframe.addEventListener('load', function () {
        notify('frame_loaded');
        styleCall();
      });
      document.body.appendChild(iframe);

      api = new mx.ClientWidgetApi(widget, iframe, new VibeDriver());
      api.setViewedRoomId(cfg.roomId);
      api.on('ready', function () {
        notify('ready');
        styleCall();
      });
      api.on('preparing', function () {
        notify('preparing');
      });
      handled.forEach(function (action) {
        api.on('action:' + action, function (ev) {
          ev.preventDefault();
          api.transport.reply(ev.detail, {});
          const data = (ev.detail && ev.detail.data) || {};
          if (action === 'io.element.join') notify('joined', data);
          else if (action === 'im.vector.hangup') notify('hangup', data);
          else if (action === 'io.element.close') notify('close', data);
          else if (action === 'io.element.device_mute') notify('media', data);
        });
      });
    },

    feedEvent: function (ev) {
      if (api) api.feedEvent(ev).catch(function () {});
    },

    feedState: function (ev) {
      if (api && api.feedStateUpdate) api.feedStateUpdate(ev).catch(function () {});
    },

    feedToDevice: function (ev, encrypted) {
      if (api) api.feedToDevice(ev, encrypted).catch(function () {});
    },

    // Vibe's own buttons drive the call through the widget API.
    action: function (name, data) {
      if (!api) return;
      api.transport.send(name, data || {}).catch(function (e) {
        console.warn('Call action failed', name, e);
      });
    },

    // Deafen: mute everyone else's audio (same origin, so we can reach in).
    // People who join later get muted too, while deafened.
    setSound: function (on) {
      soundOn = !!on;
      applySound();
      if (soundTimer) clearInterval(soundTimer);
      soundTimer = soundOn ? null : setInterval(applySound, 800);
    },
  };

  notify('host_ready');
})();
