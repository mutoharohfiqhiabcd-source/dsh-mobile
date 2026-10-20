(function () {
  try {
    if (window.__dshInstrumented) return;
    window.__dshInstrumented = true;
    var bridge = window.DshNative;
    function send(kind, msg) {
      try { if (bridge && bridge.log) bridge.log(kind + ': ' + msg); } catch (e) { }
    }
    // 捕获 console
    ['log', 'info', 'warn', 'error', 'debug'].forEach(function (k) {
      var orig = console[k] ? console[k].bind(console) : function () { };
      console[k] = function () {
        try {
          var parts = [];
          for (var i = 0; i < arguments.length; i++) {
            var a = arguments[i];
            try { parts.push(typeof a === 'string' ? a : JSON.stringify(a)); }
            catch (e) { parts.push(String(a)); }
          }
          send('console.' + k, parts.join(' '));
        } catch (e) { }
        return orig.apply(console, arguments);
      };
    });
    // 捕获未处理异常
    window.addEventListener('error', function (e) {
      try {
        send('window.onerror', (e && e.message) + ' @ ' + (e && e.filename) + ':' + (e && e.lineno) + ':' + (e && e.colno));
      } catch (x) { }
    });
    window.addEventListener('unhandledrejection', function (e) {
      try {
        var r = e && e.reason;
        send('unhandledrejection', (r && (r.stack || r.message)) || String(r));
      } catch (x) { }
    });
    // 捕获 WebSocket 状态（关键：实时通道）
    var OrigWS = window.WebSocket;
    if (OrigWS) {
      window.WebSocket = function (url, protocols) {
        send('ws.open', String(url));
        var ws = protocols === undefined ? new OrigWS(url) : new OrigWS(url, protocols);
        ws.addEventListener('open', function () { send('ws.open.ok', String(url)); });
        ws.addEventListener('close', function (ev) {
          send('ws.close', String(url) + ' code=' + ev.code + ' reason=' + ev.reason + ' clean=' + ev.wasClean);
        });
        ws.addEventListener('error', function () { send('ws.error', String(url)); });
        return ws;
      };
      window.WebSocket.prototype = OrigWS.prototype;
      window.WebSocket.CONNECTING = 0;
      window.WebSocket.OPEN = 1;
      window.WebSocket.CLOSING = 2;
      window.WebSocket.CLOSED = 3;
    }
    send('instrument', 'installed');
  } catch (e) { }
})();
