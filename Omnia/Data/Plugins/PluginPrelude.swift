//
//  PluginPrelude.swift
//  Omnia
//

import Foundation

/// The JavaScript environment a plugin expects: the browser and Node APIs
/// Nuvio's scrapers use (fetch, URL, timers, base64, TextEncoder, crypto,
/// `require('cheerio')` and `require('crypto-js')`). JavaScriptCore supplies
/// the language; these fill in the rest on top of the `__omnia_*` functions
/// PluginRuntime installs.
nonisolated enum PluginPrelude {
    static let source = #"""
    (function (global) {
      'use strict';
      global.global = global;
      global.window = global;
      global.self = global;
      global.globalThis = global;
      global.SCRAPER_ID = __omnia_scraper_id;
      try { global.SCRAPER_SETTINGS = JSON.parse(__omnia_scraper_settings || '{}'); } catch (e) { global.SCRAPER_SETTINGS = {}; }
      if (__omnia_tmdb_key) global.TMDB_API_KEY = __omnia_tmdb_key;
      global.process = { env: {}, platform: 'darwin', version: 'v18.0.0', versions: {}, nextTick: function (callback) { Promise.resolve().then(callback); } };

      // MARK: console
      function describe(value) {
        if (typeof value === 'string') return value;
        if (value instanceof Error) return value.message + (value.stack ? '\n' + value.stack : '');
        try { return JSON.stringify(value); } catch (e) { return String(value); }
      }
      var consoleLevels = ['log', 'info', 'warn', 'error', 'debug', 'trace'];
      global.console = {};
      consoleLevels.forEach(function (level) {
        global.console[level] = function () {
          __omnia_log(level, Array.prototype.map.call(arguments, describe).join(' '));
        };
      });

      // MARK: timers
      var timers = {};
      var nextTimer = 1;
      function schedule(callback, delay, args, repeat) {
        if (typeof callback !== 'function') throw new TypeError('Timer callback must be a function');
        var id = nextTimer++;
        var wait = Math.max(0, Math.min(Number(delay) || 0, 60000));
        if (repeat && wait < 1) wait = 1;
        timers[id] = true;
        (function tick() {
          __omnia_sleep(wait).then(function () {
            if (!timers[id]) return;
            if (!repeat) delete timers[id];
            try { callback.apply(global, args); } catch (error) { console.error('Timer callback failed:', error); }
            if (repeat && timers[id]) tick();
          });
        })();
        return id;
      }
      global.setTimeout = function (callback, delay) { return schedule(callback, delay, Array.prototype.slice.call(arguments, 2), false); };
      global.setInterval = function (callback, delay) { return schedule(callback, delay, Array.prototype.slice.call(arguments, 2), true); };
      global.setImmediate = function (callback) { return schedule(callback, 0, Array.prototype.slice.call(arguments, 1), false); };
      global.clearTimeout = global.clearInterval = global.clearImmediate = function (id) { delete timers[id]; };
      if (typeof global.queueMicrotask !== 'function') {
        global.queueMicrotask = function (callback) { Promise.resolve().then(callback); };
      }

      // MARK: bytes
      function latin1ToBytes(text) {
        var bytes = new Uint8Array(text.length);
        for (var i = 0; i < text.length; i++) bytes[i] = text.charCodeAt(i) & 0xff;
        return bytes;
      }
      function bytesToLatin1(bytes) {
        var out = '';
        for (var i = 0; i < bytes.length; i += 0x8000) {
          out += String.fromCharCode.apply(null, Array.prototype.slice.call(bytes, i, i + 0x8000));
        }
        return out;
      }
      function utf8Encode(text) {
        text = String(text);
        var out = [];
        for (var i = 0; i < text.length; i++) {
          var code = text.charCodeAt(i);
          if (code >= 0xd800 && code <= 0xdbff && i + 1 < text.length) {
            var low = text.charCodeAt(i + 1);
            if (low >= 0xdc00 && low <= 0xdfff) { code = 0x10000 + ((code - 0xd800) << 10) + (low - 0xdc00); i++; }
          }
          if (code < 0x80) out.push(code);
          else if (code < 0x800) out.push(0xc0 | (code >> 6), 0x80 | (code & 63));
          else if (code < 0x10000) out.push(0xe0 | (code >> 12), 0x80 | ((code >> 6) & 63), 0x80 | (code & 63));
          else out.push(0xf0 | (code >> 18), 0x80 | ((code >> 12) & 63), 0x80 | ((code >> 6) & 63), 0x80 | (code & 63));
        }
        return new Uint8Array(out);
      }
      function utf8Decode(bytes) {
        var out = '';
        for (var i = 0; i < bytes.length;) {
          var byte = bytes[i++], code;
          if (byte < 0x80) code = byte;
          else if (byte >= 0xf0) { code = ((byte & 7) << 18) | ((bytes[i++] & 63) << 12) | ((bytes[i++] & 63) << 6) | (bytes[i++] & 63); }
          else if (byte >= 0xe0) { code = ((byte & 15) << 12) | ((bytes[i++] & 63) << 6) | (bytes[i++] & 63); }
          else if (byte >= 0xc0) { code = ((byte & 31) << 6) | (bytes[i++] & 63); }
          else code = 0xfffd;
          if (code > 0xffff) { code -= 0x10000; out += String.fromCharCode(0xd800 + (code >> 10), 0xdc00 + (code & 1023)); }
          else out += String.fromCharCode(code);
        }
        return out;
      }
      function toBytes(value) {
        if (value == null) return new Uint8Array(0);
        if (value instanceof Uint8Array) return value;
        if (value instanceof ArrayBuffer) return new Uint8Array(value);
        if (ArrayBuffer.isView(value)) return new Uint8Array(value.buffer, value.byteOffset, value.byteLength);
        if (Array.isArray(value)) return new Uint8Array(value);
        return utf8Encode(String(value));
      }
      var hexDigits = '0123456789abcdef';
      function bytesToHex(bytes) {
        var out = '';
        for (var i = 0; i < bytes.length; i++) out += hexDigits[bytes[i] >> 4] + hexDigits[bytes[i] & 15];
        return out;
      }
      function hexToBytes(hex) {
        hex = String(hex || '');
        var bytes = new Uint8Array(hex.length >> 1);
        for (var i = 0; i < bytes.length; i++) bytes[i] = parseInt(hex.substr(i * 2, 2), 16);
        return bytes;
      }

      // MARK: base64 and text
      global.atob = function (text) { return __omnia_atob(String(text)); };
      global.btoa = function (text) {
        text = String(text);
        for (var i = 0; i < text.length; i++) {
          if (text.charCodeAt(i) > 255) throw new Error('btoa: the string contains characters outside of the Latin1 range');
        }
        return __omnia_btoa(text);
      };
      function TextEncoder() { this.encoding = 'utf-8'; }
      TextEncoder.prototype.encode = function (text) { return utf8Encode(text === undefined ? '' : text); };
      function TextDecoder(label) { this.encoding = String(label || 'utf-8').toLowerCase(); }
      TextDecoder.prototype.decode = function (value) {
        var bytes = toBytes(value);
        return this.encoding === 'latin1' || this.encoding === 'iso-8859-1' || this.encoding === 'ascii'
          ? bytesToLatin1(bytes) : utf8Decode(bytes);
      };
      global.TextEncoder = TextEncoder;
      global.TextDecoder = TextDecoder;

      function Buffer() {}
      Buffer.from = function (value, encoding) {
        var bytes;
        if (typeof value === 'string') {
          if (encoding === 'base64') bytes = latin1ToBytes(atob(value.replace(/-/g, '+').replace(/_/g, '/')));
          else if (encoding === 'hex') bytes = hexToBytes(value);
          else if (encoding === 'latin1' || encoding === 'binary' || encoding === 'ascii') bytes = latin1ToBytes(value);
          else bytes = utf8Encode(value);
        } else {
          bytes = new Uint8Array(toBytes(value));
        }
        bytes.toString = function (outEncoding) {
          if (outEncoding === 'base64') return btoa(bytesToLatin1(this));
          if (outEncoding === 'hex') return bytesToHex(this);
          if (outEncoding === 'latin1' || outEncoding === 'binary' || outEncoding === 'ascii') return bytesToLatin1(this);
          return utf8Decode(this);
        };
        return bytes;
      };
      Buffer.isBuffer = function (value) { return value instanceof Uint8Array; };
      Buffer.alloc = function (size) { return Buffer.from(new Uint8Array(size)); };
      Buffer.concat = function (list) {
        var total = 0;
        list.forEach(function (part) { total += part.length; });
        var out = new Uint8Array(total), offset = 0;
        list.forEach(function (part) { out.set(part, offset); offset += part.length; });
        return Buffer.from(out);
      };
      global.Buffer = Buffer;

      // MARK: URL
      function URLSearchParams(init) {
        this._pairs = [];
        var self = this;
        if (init instanceof URLSearchParams) {
          this._pairs = init._pairs.slice();
        } else if (Array.isArray(init)) {
          init.forEach(function (pair) { self._pairs.push([String(pair[0]), String(pair[1])]); });
        } else if (init && typeof init === 'object') {
          Object.keys(init).forEach(function (key) { self._pairs.push([key, String(init[key])]); });
        } else if (init != null) {
          String(init).replace(/^\?/, '').split('&').forEach(function (part) {
            if (!part) return;
            var index = part.indexOf('=');
            var key = index < 0 ? part : part.slice(0, index);
            var value = index < 0 ? '' : part.slice(index + 1);
            self._pairs.push([decodeQuery(key), decodeQuery(value)]);
          });
        }
      }
      function decodeQuery(text) {
        try { return decodeURIComponent(text.replace(/\+/g, ' ')); } catch (e) { return text; }
      }
      function encodeQuery(text) {
        return encodeURIComponent(text).replace(/%20/g, '+');
      }
      URLSearchParams.prototype = {
        append: function (key, value) { this._pairs.push([String(key), String(value)]); this._update(); },
        set: function (key, value) {
          key = String(key);
          var found = false;
          this._pairs = this._pairs.filter(function (pair) {
            if (pair[0] !== key) return true;
            if (found) return false;
            pair[1] = String(value);
            found = true;
            return true;
          });
          if (!found) this._pairs.push([key, String(value)]);
          this._update();
        },
        get: function (key) {
          for (var i = 0; i < this._pairs.length; i++) if (this._pairs[i][0] === String(key)) return this._pairs[i][1];
          return null;
        },
        getAll: function (key) {
          return this._pairs.filter(function (pair) { return pair[0] === String(key); }).map(function (pair) { return pair[1]; });
        },
        has: function (key) { return this.get(key) !== null; },
        delete: function (key) {
          this._pairs = this._pairs.filter(function (pair) { return pair[0] !== String(key); });
          this._update();
        },
        sort: function () { this._pairs.sort(function (a, b) { return a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0; }); this._update(); },
        forEach: function (callback, thisArg) {
          var self = this;
          this._pairs.forEach(function (pair) { callback.call(thisArg, pair[1], pair[0], self); });
        },
        keys: function () { return this._pairs.map(function (pair) { return pair[0]; })[Symbol.iterator](); },
        values: function () { return this._pairs.map(function (pair) { return pair[1]; })[Symbol.iterator](); },
        entries: function () { return this._pairs.map(function (pair) { return [pair[0], pair[1]]; })[Symbol.iterator](); },
        toString: function () {
          return this._pairs.map(function (pair) { return encodeQuery(pair[0]) + '=' + encodeQuery(pair[1]); }).join('&');
        },
        _update: function () {
          if (this._url) {
            var query = this.toString();
            this._url._search = query ? '?' + query : '';
          }
        }
      };
      URLSearchParams.prototype[Symbol.iterator] = function () { return this.entries(); };
      Object.defineProperty(URLSearchParams.prototype, 'size', { get: function () { return this._pairs.length; } });
      global.URLSearchParams = URLSearchParams;

      var urlPattern = /^([a-zA-Z][a-zA-Z0-9+.\-]*:)(?:\/\/(?:([^:@\/?#]*)(?::([^@\/?#]*))?@)?(\[[^\]]*\]|[^:\/?#]*)(?::(\d*))?)?([^?#]*)(\?[^#]*)?(#.*)?$/;
      var defaultPorts = { 'http:': '80', 'https:': '443', 'ws:': '80', 'wss:': '443', 'ftp:': '21' };

      function normalizePath(path) {
        var segments = path.split('/'), out = [];
        for (var i = 0; i < segments.length; i++) {
          var segment = segments[i];
          if (segment === '..') { if (out.length > 1) out.pop(); if (i === segments.length - 1) out.push(''); }
          else if (segment === '.') { if (i === segments.length - 1) out.push(''); }
          else out.push(segment);
        }
        var joined = out.join('/');
        return joined.charAt(0) === '/' ? joined : '/' + joined;
      }

      function resolveURL(input, base) {
        input = String(input).trim();
        if (/^[a-zA-Z][a-zA-Z0-9+.\-]*:/.test(input)) return input;
        if (base === undefined || base === null) throw new TypeError('Invalid URL: ' + input);
        var b = base instanceof URL ? base : new URL(String(base));
        if (input.indexOf('//') === 0) return b.protocol + input;
        if (input === '') return b.origin + b.pathname + b.search;
        if (input.charAt(0) === '#') return b.origin + b.pathname + b.search + input;
        if (input.charAt(0) === '?') return b.origin + b.pathname + input;
        if (input.charAt(0) === '/') return b.origin + input;
        var directory = b.pathname.replace(/[^\/]*$/, '');
        return b.origin + directory + input;
      }

      function URL(input, base) {
        if (!(this instanceof URL)) throw new TypeError("Constructor URL requires 'new'");
        var href = resolveURL(input, base);
        var match = urlPattern.exec(href);
        if (!match) throw new TypeError('Invalid URL: ' + input);
        this._protocol = match[1].toLowerCase();
        this.username = match[2] || '';
        this.password = match[3] || '';
        this._hostname = (match[4] || '').toLowerCase();
        var port = match[5] || '';
        this._port = defaultPorts[this._protocol] === port ? '' : port;
        var special = defaultPorts.hasOwnProperty(this._protocol) || this._protocol === 'file:';
        var path = match[6] || '';
        this._pathname = special ? normalizePath(path || '/') : path;
        this._search = match[7] && match[7] !== '?' ? match[7] : '';
        this.hash = match[8] && match[8] !== '#' ? match[8] : '';
        if (special && this._protocol !== 'file:' && !this._hostname) throw new TypeError('Invalid URL: ' + input);
        this._params = null;
      }
      Object.defineProperties(URL.prototype, {
        protocol: { get: function () { return this._protocol; }, set: function (value) { this._protocol = String(value).replace(/:?$/, ':').toLowerCase(); } },
        hostname: { get: function () { return this._hostname; }, set: function (value) { this._hostname = String(value).toLowerCase(); } },
        port: { get: function () { return this._port; }, set: function (value) { this._port = String(value); } },
        host: {
          get: function () { return this._hostname + (this._port ? ':' + this._port : ''); },
          set: function (value) { var parts = String(value).split(':'); this._hostname = parts[0].toLowerCase(); this._port = parts[1] || ''; }
        },
        origin: { get: function () { return this._protocol + '//' + this.host; } },
        pathname: { get: function () { return this._pathname; }, set: function (value) { value = String(value); this._pathname = value.charAt(0) === '/' ? value : '/' + value; } },
        search: {
          get: function () { return this._search; },
          set: function (value) { value = String(value); this._search = value && value !== '?' ? (value.charAt(0) === '?' ? value : '?' + value) : ''; this._params = null; }
        },
        searchParams: {
          get: function () {
            if (!this._params) { this._params = new URLSearchParams(this._search); this._params._url = this; }
            return this._params;
          }
        },
        href: {
          get: function () {
            var auth = this.username ? this.username + (this.password ? ':' + this.password : '') + '@' : '';
            var authority = this._hostname || this._protocol === 'file:' ? '//' + auth + this.host : '';
            return this._protocol + authority + this._pathname + this._search + this.hash;
          },
          set: function (value) { var other = new URL(value); for (var key in other) if (other.hasOwnProperty(key)) this[key] = other[key]; }
        }
      });
      URL.prototype.toString = function () { return this.href; };
      URL.prototype.toJSON = function () { return this.href; };
      URL.canParse = function (input, base) { try { new URL(input, base); return true; } catch (e) { return false; } };
      global.URL = URL;

      // MARK: AbortController
      function AbortSignal() { this.aborted = false; this.reason = undefined; this.onabort = null; this._listeners = []; }
      AbortSignal.prototype.addEventListener = function (type, listener) { if (type === 'abort') this._listeners.push(listener); };
      AbortSignal.prototype.removeEventListener = function (type, listener) {
        this._listeners = this._listeners.filter(function (existing) { return existing !== listener; });
      };
      AbortSignal.prototype.throwIfAborted = function () { if (this.aborted) throw this.reason; };
      AbortSignal.prototype._abort = function (reason) {
        if (this.aborted) return;
        this.aborted = true;
        this.reason = reason !== undefined ? reason : new Error('The operation was aborted.');
        var event = { type: 'abort', target: this };
        if (typeof this.onabort === 'function') try { this.onabort(event); } catch (e) {}
        this._listeners.forEach(function (listener) { try { listener(event); } catch (e) {} });
      };
      AbortSignal.timeout = function (ms) {
        var signal = new AbortSignal();
        setTimeout(function () { signal._abort(new Error('The operation timed out.')); }, ms);
        return signal;
      };
      AbortSignal.abort = function (reason) { var signal = new AbortSignal(); signal._abort(reason); return signal; };
      function AbortController() { this.signal = new AbortSignal(); }
      AbortController.prototype.abort = function (reason) { this.signal._abort(reason); };
      global.AbortSignal = AbortSignal;
      global.AbortController = AbortController;

      // MARK: fetch
      function Headers(init) {
        this._map = {};
        var self = this;
        if (init instanceof Headers) init.forEach(function (value, key) { self.append(key, value); });
        else if (Array.isArray(init)) init.forEach(function (pair) { self.append(pair[0], pair[1]); });
        else if (init) Object.keys(init).forEach(function (key) { if (init[key] != null) self.append(key, init[key]); });
      }
      Headers.prototype = {
        append: function (key, value) {
          key = String(key).toLowerCase();
          this._map[key] = this._map.hasOwnProperty(key) ? this._map[key] + ', ' + value : String(value);
        },
        set: function (key, value) { this._map[String(key).toLowerCase()] = String(value); },
        get: function (key) { key = String(key).toLowerCase(); return this._map.hasOwnProperty(key) ? this._map[key] : null; },
        has: function (key) { return this._map.hasOwnProperty(String(key).toLowerCase()); },
        delete: function (key) { delete this._map[String(key).toLowerCase()]; },
        forEach: function (callback, thisArg) {
          var self = this;
          Object.keys(this._map).forEach(function (key) { callback.call(thisArg, self._map[key], key, self); });
        },
        keys: function () { return Object.keys(this._map)[Symbol.iterator](); },
        entries: function () { var self = this; return Object.keys(this._map).map(function (key) { return [key, self._map[key]]; })[Symbol.iterator](); },
        raw: function () { return this._map; }
      };
      Headers.prototype[Symbol.iterator] = function () { return this.entries(); };
      global.Headers = Headers;

      function Response(body, init) {
        init = init || {};
        this.status = init.status === undefined ? 200 : init.status;
        this.statusText = init.statusText || '';
        this.ok = this.status >= 200 && this.status < 300;
        this.headers = init.headers instanceof Headers ? init.headers : new Headers(init.headers);
        this.url = init.url || '';
        this.redirected = !!init.redirected;
        this.type = 'basic';
        // Text stays text until a plugin asks for bytes.
        this._bytes = typeof body === 'string' ? null : toBytes(body);
        this._text = typeof body === 'string' ? body : null;
        this.bodyUsed = false;
      }
      Response.prototype = {
        text: function () {
          this.bodyUsed = true;
          if (this._text === null) this._text = utf8Decode(this._bytes);
          return Promise.resolve(this._text);
        },
        json: function () {
          var self = this;
          return this.text().then(function (text) { return JSON.parse(text); });
        },
        arrayBuffer: function () {
          this.bodyUsed = true;
          if (this._bytes === null) this._bytes = utf8Encode(this._text);
          return Promise.resolve(this._bytes.buffer.slice(this._bytes.byteOffset, this._bytes.byteOffset + this._bytes.byteLength));
        },
        blob: function () { return this.arrayBuffer(); },
        clone: function () {
          return new Response(this._bytes === null ? this._text : this._bytes, { status: this.status, statusText: this.statusText, headers: this.headers, url: this.url });
        }
      };
      global.Response = Response;

      function Request(input, init) {
        init = init || {};
        this.url = input instanceof Request ? input.url : String(input);
        this.method = String(init.method || (input instanceof Request ? input.method : 'GET')).toUpperCase();
        this.headers = new Headers(init.headers || (input instanceof Request ? input.headers : undefined));
        this.body = init.body !== undefined ? init.body : (input instanceof Request ? input.body : undefined);
        this.redirect = init.redirect || 'follow';
        this.signal = init.signal;
      }
      global.Request = Request;

      global.fetch = function (input, init) {
        var request = new Request(input, init);
        if (request.signal && request.signal.aborted) return Promise.reject(request.signal.reason);
        var headers = {};
        request.headers.forEach(function (value, key) { headers[key] = value; });
        var body = request.body, bodyBase64 = null;
        if (body instanceof URLSearchParams) {
          body = body.toString();
          if (!headers['content-type']) headers['content-type'] = 'application/x-www-form-urlencoded;charset=UTF-8';
        } else if (body !== undefined && body !== null && typeof body !== 'string') {
          if (body instanceof ArrayBuffer || ArrayBuffer.isView(body)) bodyBase64 = btoa(bytesToLatin1(toBytes(body)));
          else body = JSON.stringify(body);
        }
        var payload = JSON.stringify({
          url: request.url,
          method: request.method,
          headers: headers,
          body: bodyBase64 === null && body != null ? String(body) : null,
          bodyBase64: bodyBase64,
          followRedirects: request.redirect !== 'manual'
        });
        var pending = __omnia_fetch(payload).then(function (resultJSON) {
          var result = JSON.parse(resultJSON);
          if (result.error) throw new TypeError('fetch failed: ' + result.error);
          var body = typeof result.text === 'string' ? result.text : latin1ToBytes(atob(result.bodyBase64 || ''));
          return new Response(body, {
            status: result.status, statusText: result.statusText, headers: result.headers, url: result.url,
            redirected: result.redirected
          });
        });
        if (!request.signal) return pending;
        return new Promise(function (resolve, reject) {
          request.signal.addEventListener('abort', function () { reject(request.signal.reason); });
          pending.then(resolve, reject);
        });
      };

      // MARK: crypto-js
      function WordArray(words, sigBytes) {
        this.words = words || [];
        this.sigBytes = sigBytes !== undefined ? sigBytes : this.words.length * 4;
      }
      WordArray.prototype = {
        toString: function (encoder) { return (encoder || Hex).stringify(this); },
        concat: function (other) {
          var bytes = wordsToBytes(this), more = wordsToBytes(other);
          var joined = new Uint8Array(bytes.length + more.length);
          joined.set(bytes); joined.set(more, bytes.length);
          var result = bytesToWords(joined);
          this.words = result.words; this.sigBytes = result.sigBytes;
          return this;
        },
        clamp: function () {
          var result = bytesToWords(wordsToBytes(this));
          this.words = result.words;
          return this;
        },
        clone: function () { return new WordArray(this.words.slice(), this.sigBytes); }
      };
      WordArray.create = function (words, sigBytes) {
        if (words instanceof ArrayBuffer || ArrayBuffer.isView(words)) return bytesToWords(toBytes(words));
        return new WordArray(words, sigBytes);
      };
      WordArray.random = function (count) { return bytesToWords(hexToBytes(__omnia_random(count))); };
      WordArray.init = WordArray;
      function bytesToWords(bytes) {
        var words = [];
        for (var i = 0; i < bytes.length; i++) words[i >>> 2] |= bytes[i] << (24 - (i % 4) * 8);
        for (var j = 0; j < words.length; j++) words[j] = words[j] | 0;
        return new WordArray(words, bytes.length);
      }
      function wordsToBytes(wordArray) {
        var bytes = new Uint8Array(wordArray.sigBytes);
        for (var i = 0; i < wordArray.sigBytes; i++) bytes[i] = (wordArray.words[i >>> 2] >>> (24 - (i % 4) * 8)) & 0xff;
        return bytes;
      }
      function asBytes(value) {
        if (value instanceof WordArray) return wordsToBytes(value);
        return utf8Encode(String(value));
      }
      var Hex = {
        stringify: function (wordArray) { return bytesToHex(wordsToBytes(wordArray)); },
        parse: function (text) { return bytesToWords(hexToBytes(text)); }
      };
      var Latin1 = {
        stringify: function (wordArray) { return bytesToLatin1(wordsToBytes(wordArray)); },
        parse: function (text) { return bytesToWords(latin1ToBytes(text)); }
      };
      var Utf8 = {
        stringify: function (wordArray) { return utf8Decode(wordsToBytes(wordArray)); },
        parse: function (text) { return bytesToWords(utf8Encode(text)); }
      };
      var Base64 = {
        stringify: function (wordArray) { return btoa(bytesToLatin1(wordsToBytes(wordArray))); },
        parse: function (text) { return bytesToWords(latin1ToBytes(atob(String(text).replace(/\s/g, '')))); }
      };
      var Base64url = {
        stringify: function (wordArray) { return Base64.stringify(wordArray).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, ''); },
        parse: function (text) {
          text = String(text).replace(/-/g, '+').replace(/_/g, '/');
          while (text.length % 4) text += '=';
          return Base64.parse(text);
        }
      };
      function hasher(name) {
        var fn = function (message) { return bytesToWords(hexToBytes(__omnia_digest(name, bytesToHex(asBytes(message))))); };
        fn._name = name;
        return fn;
      }
      function hmac(name) {
        return function (message, key) {
          return bytesToWords(hexToBytes(__omnia_hmac(name, bytesToHex(asBytes(key)), bytesToHex(asBytes(message)))));
        };
      }
      function evpKDF(password, salt, keyBytes, ivBytes) {
        var total = keyBytes + ivBytes, derived = new Uint8Array(0), block = new Uint8Array(0);
        while (derived.length < total) {
          var input = new Uint8Array(block.length + password.length + salt.length);
          input.set(block); input.set(password, block.length); input.set(salt, block.length + password.length);
          block = hexToBytes(__omnia_digest('MD5', bytesToHex(input)));
          var next = new Uint8Array(derived.length + block.length);
          next.set(derived); next.set(block, derived.length);
          derived = next;
        }
        return { key: derived.slice(0, keyBytes), iv: derived.slice(keyBytes, total) };
      }
      function CipherParams(params) { for (var key in params) this[key] = params[key]; }
      CipherParams.prototype.toString = function (formatter) { return (formatter || OpenSSLFormat).stringify(this); };
      var OpenSSLFormat = {
        stringify: function (params) {
          var ciphertext = wordsToBytes(params.ciphertext);
          if (!params.salt) return btoa(bytesToLatin1(ciphertext));
          var salt = wordsToBytes(params.salt);
          var out = new Uint8Array(16 + ciphertext.length);
          out.set(latin1ToBytes('Salted__')); out.set(salt, 8); out.set(ciphertext, 16);
          return btoa(bytesToLatin1(out));
        },
        parse: function (text) {
          var bytes = latin1ToBytes(atob(String(text).replace(/\s/g, '')));
          if (bytesToLatin1(bytes.slice(0, 8)) === 'Salted__') {
            return new CipherParams({ ciphertext: bytesToWords(bytes.slice(16)), salt: bytesToWords(bytes.slice(8, 16)) });
          }
          return new CipherParams({ ciphertext: bytesToWords(bytes) });
        }
      };
      var HexFormat = {
        stringify: function (params) { return Hex.stringify(params.ciphertext); },
        parse: function (text) { return new CipherParams({ ciphertext: Hex.parse(text) }); }
      };
      var modes = { CBC: { _name: 'CBC' }, ECB: { _name: 'ECB' }, CTR: { _name: 'CTR' }, CFB: { _name: 'CFB' }, OFB: { _name: 'OFB' } };
      var pads = { Pkcs7: { _name: 'Pkcs7' }, NoPadding: { _name: 'NoPadding' }, ZeroPadding: { _name: 'ZeroPadding' } };
      function cipher(algorithm, encrypt, data, key, cfg) {
        cfg = cfg || {};
        var mode = (cfg.mode || modes.CBC)._name, padding = (cfg.padding || pads.Pkcs7)._name;
        var keyBytes, ivBytes, salt = null;
        if (typeof key === 'string') {
          // A passphrase: OpenSSL's EVP_BytesToKey with MD5, as CryptoJS does.
          var saltBytes = encrypt ? hexToBytes(__omnia_random(8)) : (data.salt ? wordsToBytes(data.salt) : new Uint8Array(0));
          var keySize = algorithm === 'DES' ? 8 : algorithm === 'TripleDES' ? 24 : 32;
          var derived = evpKDF(utf8Encode(key), saltBytes, keySize, algorithm === 'AES' ? 16 : 8);
          keyBytes = derived.key; ivBytes = derived.iv;
          salt = bytesToWords(saltBytes);
        } else {
          keyBytes = wordsToBytes(key);
          ivBytes = cfg.iv ? wordsToBytes(cfg.iv) : new Uint8Array(algorithm === 'AES' ? 16 : 8);
        }
        var input = encrypt ? asBytes(data) : wordsToBytes(data.ciphertext);
        if (padding === 'ZeroPadding' && encrypt) {
          var blockSize = algorithm === 'AES' ? 16 : 8, padded = new Uint8Array(Math.ceil(input.length / blockSize) * blockSize || blockSize);
          padded.set(input); input = padded; padding = 'NoPadding';
        }
        var resultHex = __omnia_cipher(algorithm, encrypt, mode, padding === 'Pkcs7', bytesToHex(keyBytes), bytesToHex(ivBytes), bytesToHex(input));
        if (resultHex === null || resultHex === undefined) throw new Error('Malformed UTF-8 data');
        var output = hexToBytes(resultHex);
        if (cfg.padding && cfg.padding._name === 'ZeroPadding' && !encrypt) {
          var end = output.length;
          while (end > 0 && output[end - 1] === 0) end--;
          output = output.slice(0, end);
        }
        if (!encrypt) return bytesToWords(output);
        return new CipherParams({
          ciphertext: bytesToWords(output), key: bytesToWords(keyBytes), iv: bytesToWords(ivBytes), salt: salt,
          formatter: cfg.format || OpenSSLFormat
        });
      }
      function cipherFamily(algorithm) {
        return {
          encrypt: function (message, key, cfg) { return cipher(algorithm, true, message, key, cfg); },
          decrypt: function (ciphertext, key, cfg) {
            var params = typeof ciphertext === 'string' ? ((cfg && cfg.format) || OpenSSLFormat).parse(ciphertext) : ciphertext;
            return cipher(algorithm, false, params, key, cfg);
          }
        };
      }
      var CryptoJS = {
        lib: { WordArray: WordArray, CipherParams: CipherParams },
        enc: { Hex: Hex, Latin1: Latin1, Utf8: Utf8, Base64: Base64, Base64url: Base64url },
        format: { OpenSSL: OpenSSLFormat, Hex: HexFormat },
        mode: modes,
        pad: pads,
        algo: {},
        MD5: hasher('MD5'), SHA1: hasher('SHA1'), SHA224: hasher('SHA224'), SHA256: hasher('SHA256'),
        SHA384: hasher('SHA384'), SHA512: hasher('SHA512'),
        HmacMD5: hmac('MD5'), HmacSHA1: hmac('SHA1'), HmacSHA224: hmac('SHA224'), HmacSHA256: hmac('SHA256'),
        HmacSHA384: hmac('SHA384'), HmacSHA512: hmac('SHA512'),
        PBKDF2: function (password, salt, cfg) {
          cfg = cfg || {};
          var keyWords = cfg.keySize || 4, iterations = cfg.iterations || 250000;
          var hash = cfg.hasher && cfg.hasher._name ? cfg.hasher._name : 'SHA256';
          return bytesToWords(hexToBytes(__omnia_pbkdf2(bytesToHex(asBytes(password)), bytesToHex(asBytes(salt)), iterations, keyWords * 4, hash)));
        },
        EvpKDF: function (password, salt, cfg) {
          var derived = evpKDF(asBytes(password), asBytes(salt), ((cfg && cfg.keySize) || 4) * 4, 0);
          return bytesToWords(derived.key);
        },
        AES: cipherFamily('AES'), DES: cipherFamily('DES'), TripleDES: cipherFamily('TripleDES')
      };
      ['MD5', 'SHA1', 'SHA224', 'SHA256', 'SHA384', 'SHA512'].forEach(function (name) { CryptoJS.algo[name] = CryptoJS[name]; });
      global.CryptoJS = CryptoJS;

      // MARK: Web Crypto
      function digestName(algorithm) {
        var name = String(algorithm && algorithm.name ? algorithm.name : algorithm).toUpperCase().replace(/[^A-Z0-9]/g, '');
        return name;
      }
      function asBuffer(bytes) { return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength); }
      function CryptoKey(algorithm, raw, usages) { this.type = 'secret'; this.algorithm = algorithm; this._raw = raw; this.usages = usages || []; this.extractable = true; }
      var subtle = {
        digest: function (algorithm, data) {
          return Promise.resolve(asBuffer(hexToBytes(__omnia_digest(digestName(algorithm), bytesToHex(toBytes(data))))));
        },
        importKey: function (format, keyData, algorithm, extractable, usages) {
          if (format !== 'raw') return Promise.reject(new Error('Only raw keys are supported'));
          var normalized = typeof algorithm === 'string' ? { name: algorithm } : algorithm;
          return Promise.resolve(new CryptoKey(normalized, toBytes(keyData), usages));
        },
        exportKey: function (format, key) { return Promise.resolve(asBuffer(key._raw)); },
        sign: function (algorithm, key, data) {
          var hash = digestName(key.algorithm.hash || 'SHA-256');
          return Promise.resolve(asBuffer(hexToBytes(__omnia_hmac(hash, bytesToHex(key._raw), bytesToHex(toBytes(data))))));
        },
        verify: function (algorithm, key, signature, data) {
          return subtle.sign(algorithm, key, data).then(function (expected) {
            return bytesToHex(new Uint8Array(expected)) === bytesToHex(toBytes(signature));
          });
        },
        encrypt: function (algorithm, key, data) { return webCipher(true, algorithm, key, data); },
        decrypt: function (algorithm, key, data) { return webCipher(false, algorithm, key, data); },
        deriveBits: function (algorithm, key, length) {
          var hash = digestName(algorithm.hash || 'SHA-256');
          return Promise.resolve(asBuffer(hexToBytes(__omnia_pbkdf2(bytesToHex(key._raw), bytesToHex(toBytes(algorithm.salt)), algorithm.iterations, length / 8, hash))));
        },
        deriveKey: function (algorithm, key, derived, extractable, usages) {
          return subtle.deriveBits(algorithm, key, derived.length || 256).then(function (bits) {
            return new CryptoKey(derived, new Uint8Array(bits), usages);
          });
        }
      };
      function webCipher(encrypt, algorithm, key, data) {
        var name = String(algorithm.name).toUpperCase();
        var iv = bytesToHex(toBytes(algorithm.iv || algorithm.counter || new Uint8Array(16)));
        var result;
        if (name === 'AES-GCM') {
          result = __omnia_aes_gcm(encrypt, bytesToHex(key._raw), iv, bytesToHex(toBytes(data)), bytesToHex(toBytes(algorithm.additionalData)));
        } else {
          var mode = name === 'AES-CTR' ? 'CTR' : name === 'AES-ECB' ? 'ECB' : 'CBC';
          result = __omnia_cipher('AES', encrypt, mode, mode === 'CBC', bytesToHex(key._raw), iv, bytesToHex(toBytes(data)));
        }
        if (result === null || result === undefined) return Promise.reject(new Error('The operation failed for an operation-specific reason'));
        return Promise.resolve(asBuffer(hexToBytes(result)));
      }
      global.crypto = {
        subtle: subtle,
        getRandomValues: function (array) {
          var bytes = hexToBytes(__omnia_random(array.byteLength));
          new Uint8Array(array.buffer, array.byteOffset, array.byteLength).set(bytes);
          return array;
        },
        randomUUID: function () { return __omnia_uuid(); }
      };

      // MARK: cheerio
      function wrapNode(doc, id) {
        return {
          _omniaDoc: doc, _omniaNode: id, type: 'tag',
          get name() { return __omnia_html_tag(doc, id); },
          get tagName() { return __omnia_html_tag(doc, id); },
          get attribs() { return JSON.parse(__omnia_html_attrs(doc, id)); },
          get children() { return JSON.parse(__omnia_html_relation(doc, '[' + id + ']', 'children')).map(function (child) { return wrapNode(doc, child); }); },
          get parent() { var ids = JSON.parse(__omnia_html_relation(doc, '[' + id + ']', 'parent')); return ids.length ? wrapNode(doc, ids[0]) : null; }
        };
      }
      function loadDocument(html) {
        var doc = __omnia_html_load(String(html == null ? '' : html));
        function selection(ids) {
          var result = Object.create(Selection.prototype);
          result._ids = ids;
          result.length = ids.length;
          for (var i = 0; i < ids.length; i++) result[i] = wrapNode(doc, ids[i]);
          return result;
        }
        function idsOf(value) {
          if (value == null) return [];
          if (value instanceof Selection) return value._ids;
          if (value._omniaNode !== undefined) return [value._omniaNode];
          if (Array.isArray(value)) return value.reduce(function (all, item) { return all.concat(idsOf(item)); }, []);
          return [];
        }
        function relation(ids, kind, selector) {
          var found = JSON.parse(__omnia_html_relation(doc, JSON.stringify(ids), kind));
          return selector ? found.filter(function (id) { return __omnia_html_matches(doc, id, selector); }) : found;
        }
        function Selection() {}
        Selection.prototype = {
          each: function (callback) {
            for (var i = 0; i < this._ids.length; i++) {
              if (callback.call(this[i], i, this[i]) === false) break;
            }
            return this;
          },
          map: function (callback) {
            var out = [];
            for (var i = 0; i < this._ids.length; i++) {
              var value = callback.call(this[i], i, this[i]);
              if (value === null || value === undefined) continue;
              if (Array.isArray(value)) out = out.concat(value); else out.push(value);
            }
            var wrapped = Object.create(MappedSelection.prototype);
            for (var j = 0; j < out.length; j++) wrapped[j] = out[j];
            wrapped.length = out.length;
            wrapped._items = out;
            return wrapped;
          },
          filter: function (test) {
            var self = this;
            return selection(this._ids.filter(function (id, index) {
              if (typeof test === 'function') return test.call(self[index], index, self[index]);
              if (typeof test === 'string') return __omnia_html_matches(doc, id, test);
              return idsOf(test).indexOf(id) >= 0;
            }));
          },
          not: function (test) {
            var keep = this.filter(test)._ids;
            return selection(this._ids.filter(function (id) { return keep.indexOf(id) < 0; }));
          },
          is: function (test) { return this.filter(test).length > 0; },
          has: function (selector) {
            return selection(this._ids.filter(function (id) { return JSON.parse(__omnia_html_select(doc, '[' + id + ']', selector)).length > 0; }));
          },
          find: function (selector) {
            if (typeof selector !== 'string') {
              var wanted = idsOf(selector), within = this._ids;
              return selection(wanted.filter(function (id) {
                return JSON.parse(__omnia_html_relation(doc, '[' + id + ']', 'parents')).some(function (parent) { return within.indexOf(parent) >= 0; });
              }));
            }
            return selection(JSON.parse(__omnia_html_select(doc, JSON.stringify(this._ids), selector)));
          },
          children: function (selector) { return selection(relation(this._ids, 'children', selector)); },
          contents: function () { return this.children(); },
          parent: function (selector) { return selection(relation(this._ids, 'parent', selector)); },
          parents: function (selector) { return selection(relation(this._ids, 'parents', selector)); },
          closest: function (selector) {
            var out = [];
            this._ids.forEach(function (id) {
              if (__omnia_html_matches(doc, id, selector)) { if (out.indexOf(id) < 0) out.push(id); return; }
              var parents = JSON.parse(__omnia_html_relation(doc, '[' + id + ']', 'parents'));
              for (var i = 0; i < parents.length; i++) {
                if (__omnia_html_matches(doc, parents[i], selector)) { if (out.indexOf(parents[i]) < 0) out.push(parents[i]); return; }
              }
            });
            return selection(out);
          },
          next: function (selector) { return selection(relation(this._ids, 'next', selector)); },
          prev: function (selector) { return selection(relation(this._ids, 'prev', selector)); },
          nextAll: function (selector) { return selection(relation(this._ids, 'nextAll', selector)); },
          prevAll: function (selector) { return selection(relation(this._ids, 'prevAll', selector)); },
          siblings: function (selector) { return selection(relation(this._ids, 'siblings', selector)); },
          first: function () { return selection(this._ids.slice(0, 1)); },
          last: function () { return selection(this._ids.slice(-1)); },
          eq: function (index) { var id = this._ids[index < 0 ? this._ids.length + index : index]; return selection(id === undefined ? [] : [id]); },
          slice: function (start, end) { return selection(this._ids.slice(start, end)); },
          get: function (index) {
            if (index === undefined) return this.toArray();
            return this[index < 0 ? this._ids.length + index : index];
          },
          toArray: function () { var out = []; for (var i = 0; i < this._ids.length; i++) out.push(this[i]); return out; },
          index: function () { return this._ids.length ? JSON.parse(__omnia_html_relation(doc, '[' + this._ids[0] + ']', 'prevAll')).length : -1; },
          add: function (other) {
            var merged = this._ids.concat(typeof other === 'string' ? JSON.parse(__omnia_html_select(doc, null, other)) : idsOf(other));
            return selection(merged.filter(function (id, index) { return merged.indexOf(id) === index; }).sort(function (a, b) { return a - b; }));
          },
          text: function () { return this._ids.length ? __omnia_html_text(doc, JSON.stringify(this._ids)) : ''; },
          html: function () { return this._ids.length ? __omnia_html_inner(doc, this._ids[0]) : null; },
          attr: function (name) {
            if (!this._ids.length) return undefined;
            if (name === undefined) return JSON.parse(__omnia_html_attrs(doc, this._ids[0]));
            var value = __omnia_html_attr(doc, this._ids[0], String(name));
            return value === null ? undefined : value;
          },
          prop: function (name) {
            if (name === 'outerHTML') return this._ids.length ? __omnia_html_outer(doc, this._ids[0]) : undefined;
            if (name === 'innerHTML') return this.html();
            if (name === 'textContent' || name === 'innerText') return this.text();
            if (name === 'tagName' || name === 'nodeName') return this._ids.length ? __omnia_html_tag(doc, this._ids[0]).toUpperCase() : undefined;
            return this.attr(name);
          },
          data: function (name) {
            var attributes = this.attr() || {}, data = {};
            Object.keys(attributes).forEach(function (key) {
              if (key.indexOf('data-') !== 0) return;
              var camel = key.slice(5).replace(/-([a-z])/g, function (m, c) { return c.toUpperCase(); });
              var raw = attributes[key], value = raw;
              try { if (/^[\[{]|^(true|false|null|-?\d+(\.\d+)?)$/.test(raw)) value = JSON.parse(raw); } catch (e) {}
              data[camel] = value;
            });
            return name === undefined ? data : data[name];
          },
          val: function () {
            if (!this._ids.length) return undefined;
            var tag = __omnia_html_tag(doc, this._ids[0]);
            if (tag === 'textarea') return this.text();
            if (tag === 'select') {
              var chosen = this.find('option[selected]');
              return (chosen.length ? chosen : this.find('option').first()).val();
            }
            var value = this.attr('value');
            return value === undefined && tag === 'option' ? this.text() : value;
          },
          hasClass: function (name) {
            return this._ids.some(function (id) {
              return (' ' + (__omnia_html_attr(doc, id, 'class') || '') + ' ').replace(/\s+/g, ' ').indexOf(' ' + name + ' ') >= 0;
            });
          },
          end: function () { return this; }
        };
        Selection.prototype[Symbol.iterator] = function () { return this.toArray()[Symbol.iterator](); };
        function MappedSelection() {}
        MappedSelection.prototype = {
          get: function (index) { return index === undefined ? this._items.slice() : this._items[index < 0 ? this._items.length + index : index]; },
          toArray: function () { return this._items.slice(); },
          each: function (callback) { this._items.forEach(function (item, index) { callback.call(item, index, item); }); return this; },
          join: function (separator) { return this._items.join(separator); }
        };

        var $ = function (selector, context) {
          if (selector == null || selector === '') return selection([]);
          if (selector instanceof Selection) return selector;
          if (typeof selector !== 'string') return selection(idsOf(selector));
          if (/^\s*</.test(selector)) {
            var fragment = loadDocument(selector);
            return fragment.root().children();
          }
          if (context !== undefined) {
            var scope = typeof context === 'string' ? JSON.parse(__omnia_html_select(doc, null, context)) : idsOf(context);
            return selection(JSON.parse(__omnia_html_select(doc, JSON.stringify(scope), selector)));
          }
          return selection(JSON.parse(__omnia_html_select(doc, null, selector)));
        };
        $.html = function (value) {
          if (value === undefined) return __omnia_html_inner(doc, 0);
          var ids = idsOf(typeof value === 'string' ? $(value) : value);
          return ids.map(function (id) { return __omnia_html_outer(doc, id); }).join('');
        };
        $.text = function (value) {
          if (value === undefined) return __omnia_html_text(doc, '[0]');
          return __omnia_html_text(doc, JSON.stringify(idsOf(value)));
        };
        $.root = function () {
          var root = Object.create(Selection.prototype);
          root._ids = [0]; root.length = 1; root[0] = wrapNode(doc, 0);
          return root;
        };
        $.load = loadDocument;
        $.contains = function (container, contained) {
          return JSON.parse(__omnia_html_relation(doc, '[' + contained._omniaNode + ']', 'parents')).indexOf(container._omniaNode) >= 0;
        };
        return $;
      }
      var cheerio = { load: loadDocument };
      global.cheerio = cheerio;

      // MARK: require
      var modules = {
        'cheerio': cheerio,
        'cheerio-without-node-native': cheerio,
        'react-native-cheerio': cheerio,
        'crypto-js': CryptoJS,
        'buffer': { Buffer: Buffer },
        'url': { URL: URL, URLSearchParams: URLSearchParams }
      };
      global.require = function (name) {
        name = String(name).replace(/^node:/, '');
        if (name.indexOf('crypto-js/') === 0) return CryptoJS;
        if (modules.hasOwnProperty(name)) return modules[name];
        throw new Error("Module '" + name + "' is not available in Omnia");
      };
    })(this);
    """#

    /// Runs the plugin's file as a CommonJS module, so `module.exports`,
    /// `exports` and top-level functions all work.
    static func module(wrapping code: String) -> String {
        // A byte-order mark is only allowed at the very start of a script;
        // inside the wrapper JavaScriptCore rejects it as an invalid
        // character.
        let code = code.hasPrefix("\u{FEFF}") ? String(code.dropFirst()) : code
        return """
        var module = { exports: {} };
        var exports = module.exports;
        (function (module, exports) {
        \(code)
        ;
        if (typeof getStreams === 'function' && !module.exports.getStreams) module.exports.getStreams = getStreams;
        if (typeof onSettings === 'function' && !module.exports.onSettings) module.exports.onSettings = onSettings;
        })(module, exports);
        """
    }

    /// Calls `getStreams` and hands its result back through `__omnia_result`.
    static let streamsCall = #"""
    (function () {
      var args = JSON.parse(__omnia_call_arguments);
      var exported = module.exports && typeof module.exports === 'object' ? module.exports : {};
      var getStreams = exported.getStreams || (typeof module.exports === 'function' ? module.exports : null) || globalThis.getStreams;
      if (typeof getStreams !== 'function') {
        __omnia_fail('This plugin has no getStreams function.');
        return;
      }
      Promise.resolve()
        .then(function () {
          return getStreams(args.tmdbId, args.mediaType, args.season == null ? undefined : args.season, args.episode == null ? undefined : args.episode);
        })
        .then(function (result) { __omnia_result(JSON.stringify(Array.isArray(result) ? result : [])); })
        .catch(function (error) { __omnia_fail(error && error.message ? error.message : String(error)); });
    })();
    """#

    /// Calls `onSettings` for the plugin's settings layout.
    static let settingsCall = #"""
    (function () {
      var onSettings = (module.exports && module.exports.onSettings) || globalThis.onSettings;
      if (typeof onSettings !== 'function') { __omnia_result('[]'); return; }
      Promise.resolve()
        .then(function () { return onSettings(); })
        .then(function (layout) { __omnia_result(JSON.stringify(layout || [])); })
        .catch(function (error) { __omnia_fail(error && error.message ? error.message : String(error)); });
    })();
    """#
}
