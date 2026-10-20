/* DSH Mobile —— 旧版 Android WebView 的现代 JS API polyfill
 * 目标：让 DSH 前端（面向 Chrome 119+ 构建）在旧内核上也能跑。
 * 必须在页面脚本执行前注入（App 在 onPageStarted 里注入）。
 */
(function () {
  'use strict';
  try {

    // ── Promise.withResolvers (ES2024, Chrome 119) ────────────────────
    if (typeof Promise.withResolvers !== 'function') {
      Promise.withResolvers = function () {
        var resolve, reject;
        var promise = new Promise(function (res, rej) { resolve = res; reject = rej; });
        return { promise: promise, resolve: resolve, reject: reject };
      };
    }

    // ── Promise.try (Chrome 128) ──────────────────────────────────────
    if (typeof Promise.try !== 'function') {
      Promise.try = function (fn) {
        var args = Array.prototype.slice.call(arguments, 1);
        return new Promise(function (resolve) { resolve(fn.apply(undefined, args)); });
      };
    }

    // ── AbortSignal.any / timeout (Chrome 116 / 103) ──────────────────
    if (typeof AbortSignal !== 'undefined') {
      if (typeof AbortSignal.any !== 'function') {
        AbortSignal.any = function (signals) {
          var ctrl = new AbortController();
          try {
            (signals || []).forEach(function (s) {
              if (!s) return;
              if (s.aborted) { ctrl.abort(s.reason); }
              else { s.addEventListener('abort', function () { ctrl.abort(s.reason); }, { once: true }); }
            });
          } catch (e) { }
          return ctrl.signal;
        };
      }
      if (typeof AbortSignal.timeout !== 'function') {
        AbortSignal.timeout = function (ms) {
          var ctrl = new AbortController();
          setTimeout(function () {
            try { ctrl.abort(new DOMException('TimeoutError', 'TimeoutError')); }
            catch (e) { ctrl.abort(); }
          }, ms);
          return ctrl.signal;
        };
      }
    }

    // ── Object.groupBy / Map.groupBy (Chrome 117) ─────────────────────
    if (typeof Object.groupBy !== 'function') {
      Object.groupBy = function (items, fn) {
        var out = {};
        var i = 0;
        for (var item of items) {
          var k = String(fn(item, i++));
          (out[k] || (out[k] = [])).push(item);
        }
        return out;
      };
    }
    if (typeof Map.groupBy !== 'function') {
      Map.groupBy = function (items, fn) {
        var out = new Map();
        var i = 0;
        for (var item of items) {
          var k = fn(item, i++);
          if (!out.has(k)) out.set(k, []);
          out.get(k).push(item);
        }
        return out;
      };
    }

    // ── Array.prototype: findLast / findLastIndex / toSorted / toReversed / toSpliced / with ──
    var ap = Array.prototype;
    if (typeof ap.findLast !== 'function') {
      ap.findLast = function (fn, thisArg) {
        for (var i = this.length - 1; i >= 0; i--) { if (fn.call(thisArg, this[i], i, this)) return this[i]; }
        return undefined;
      };
    }
    if (typeof ap.findLastIndex !== 'function') {
      ap.findLastIndex = function (fn, thisArg) {
        for (var i = this.length - 1; i >= 0; i--) { if (fn.call(thisArg, this[i], i, this)) return i; }
        return -1;
      };
    }
    if (typeof ap.toSorted !== 'function') {
      ap.toSorted = function (cmp) { return this.slice().sort(cmp); };
    }
    if (typeof ap.toReversed !== 'function') {
      ap.toReversed = function () { return this.slice().reverse(); };
    }
    if (typeof ap.toSpliced !== 'function') {
      ap.toSpliced = function (start, del) {
        var copy = this.slice();
        copy.splice.apply(copy, arguments);
        return copy;
      };
    }
    if (typeof ap.with !== 'function') {
      ap.with = function (idx, value) {
        var copy = this.slice();
        var i = idx < 0 ? copy.length + idx : idx;
        copy[i] = value;
        return copy;
      };
    }

    // ── Array.fromAsync (Chrome 121) ──────────────────────────────────
    if (typeof Array.fromAsync !== 'function') {
      Array.fromAsync = function (iterable, mapFn, thisArg) {
        return (async function () {
          var out = [];
          var i = 0;
          for await (var v of iterable) {
            out.push(mapFn ? await mapFn.call(thisArg, v, i++) : v);
          }
          return out;
        })();
      };
    }

    // ── String.prototype.isWellFormed / toWellFormed (Chrome 111) ─────
    if (typeof String.prototype.isWellFormed !== 'function') {
      String.prototype.isWellFormed = function () { return !/[\uD800-\uDFFF]/.test(this); };
    }
    if (typeof String.prototype.toWellFormed !== 'function') {
      String.prototype.toWellFormed = function () {
        return this.replace(/[\uD800-\uDFFF]/g, '\uFFFD');
      };
    }

    // ── Object.hasOwn (Chrome 93) ─────────────────────────────────────
    if (typeof Object.hasOwn !== 'function') {
      Object.hasOwn = function (obj, key) { return Object.prototype.hasOwnProperty.call(obj, key); };
    }

    // ── URL.canParse (Chrome 120) ─────────────────────────────────────
    if (typeof URL.canParse !== 'function') {
      URL.canParse = function (input, base) {
        try { new URL(input, base); return true; } catch (e) { return false; }
      };
    }

    // ── structuredClone (Chrome 98) ───────────────────────────────────
    if (typeof window.structuredClone !== 'function') {
      window.structuredClone = function (v) { return JSON.parse(JSON.stringify(v)); };
    }

    // ── Set 集合运算 (Chrome 122) ─────────────────────────────────────
    if (typeof Set.prototype.union !== 'function') {
      Set.prototype.union = function (other) {
        var out = new Set(this);
        for (var v of other) out.add(v);
        return out;
      };
      Set.prototype.intersection = function (other) {
        var out = new Set();
        for (var v of this) if (other.has(v)) out.add(v);
        return out;
      };
      Set.prototype.difference = function (other) {
        var out = new Set();
        for (var v of this) if (!other.has(v)) out.add(v);
        return out;
      };
      Set.prototype.symmetricDifference = function (other) {
        var out = new Set(this);
        for (var v of other) { if (out.has(v)) out.delete(v); else out.add(v); }
        return out;
      };
      Set.prototype.isSubsetOf = function (other) {
        for (var v of this) if (!other.has(v)) return false;
        return true;
      };
      Set.prototype.isSupersetOf = function (other) {
        for (var v of other) if (!this.has(v)) return false;
        return true;
      };
      Set.prototype.isDisjointFrom = function (other) {
        for (var v of this) if (other.has(v)) return false;
        return true;
      };
    }

    // ── RegExp 转义 (Chrome 73) ───────────────────────────────────────
    if (typeof RegExp.escape !== 'function') {
      RegExp.escape = function (s) { return String(s).replace(/[.*+?^${}()|[\]\\]/g, '\\$&'); };
    }

  } catch (e) { /* ignore */ }
})();
