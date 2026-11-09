// Sahte DOM (SketchUp / Chromium DIŞINDA): HTML ayrıştırıcı + küçük seçici motoru + vm bağlamı.
// Amaç: ui.html ve src/*.js betiklerini kaynak değiştirmeden node içinde çalıştırıp menü / geri çağrı bağlantılarını sınamak.
// Yalnız mantığı sınar; görünüm, CSS, gerçek HtmlDialog davranışı kanıtlanmaz. Kaynak dosyalar yalnız okunur.
'use strict';
const vm = require('vm');
const VOID = new Set(['area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'source', 'track', 'wbr']);
const RAW = new Set(['script', 'style', 'textarea', 'title']);
const AUTOCLOSE = { option: ['option'], li: ['li'], tr: ['tr', 'td', 'th'], td: ['td', 'th'], th: ['td', 'th'], p: ['p'] };

class Node {
  constructor(doc) { this.ownerDocument = doc; this.parentNode = null; this.childNodes = []; }
  get firstChild() { return this.childNodes[0] || null; }
  get lastChild() { return this.childNodes[this.childNodes.length - 1] || null; }
  get nextSibling() { const p = this.parentNode; if (!p) return null; const i = p.childNodes.indexOf(this); return p.childNodes[i + 1] || null; }
  get previousSibling() { const p = this.parentNode; if (!p) return null; const i = p.childNodes.indexOf(this); return i > 0 ? p.childNodes[i - 1] : null; }
  get parentElement() { return this.parentNode && this.parentNode.nodeType === 1 ? this.parentNode : null; }
  appendChild(c) { return this.insertBefore(c, null); }
  insertBefore(c, ref) {
    if (c.nodeType === 11) { c.childNodes.slice().forEach((x) => this.insertBefore(x, ref)); return c; }
    if (c.parentNode) c.parentNode.removeChild(c);
    const i = ref ? this.childNodes.indexOf(ref) : -1;
    if (i < 0) this.childNodes.push(c); else this.childNodes.splice(i, 0, c);
    c.parentNode = this; return c;
  }
  removeChild(c) { const i = this.childNodes.indexOf(c); if (i >= 0) this.childNodes.splice(i, 1); c.parentNode = null; return c; }
  remove() { if (this.parentNode) this.parentNode.removeChild(this); }
  contains(n) { while (n) { if (n === this) return true; n = n.parentNode; } return false; }
  get textContent() { return this.nodeType === 3 ? this.data : this.childNodes.map((c) => c.textContent).join(''); }
  set textContent(v) { if (this.nodeType === 3) { this.data = String(v); return; } this.childNodes.forEach((c) => { c.parentNode = null; }); this.childNodes = []; if (v !== '' && v !== null && v !== undefined) this.appendChild(this.ownerDocument.createTextNode(String(v))); }
}
class Text extends Node { constructor(doc, s) { super(doc); this.nodeType = 3; this.data = s; } get nodeName() { return '#text'; } }
class ClassList {
  constructor(el) { this.el = el; }
  _l() { return (this.el.getAttribute('class') || '').split(/\s+/).filter(Boolean); }
  _s(l) { this.el.setAttribute('class', l.join(' ')); }
  add(...c) { const l = this._l(); c.forEach((x) => { if (!l.includes(x)) l.push(x); }); this._s(l); }
  remove(...c) { this._s(this._l().filter((x) => !c.includes(x))); }
  contains(c) { return this._l().includes(c); }
  toggle(c, f) { const has = this.contains(c); const want = f === undefined ? !has : !!f; if (want) this.add(c); else this.remove(c); return want; }
  get length() { return this._l().length; }
}
class Element extends Node {
  constructor(doc, tag) {
    super(doc); this.nodeType = 1; this.tagName = String(tag).toUpperCase(); this.attrs = new Map(); this.listeners = {};
    this.style = {}; this.classList = new ClassList(this); this.dataset = {}; this._props = {}; this.scrollTop = 0;
  }
  get nodeName() { return this.tagName; }
  get localName() { return this.tagName.toLowerCase(); }
  getAttribute(n) { return this.attrs.has(n) ? this.attrs.get(n) : null; }
  setAttribute(n, v) { this.attrs.set(n, String(v)); }
  hasAttribute(n) { return this.attrs.has(n); }
  removeAttribute(n) { this.attrs.delete(n); }
  get id() { return this.getAttribute('id') || ''; } set id(v) { this.setAttribute('id', v); }
  get className() { return this.getAttribute('class') || ''; } set className(v) { this.setAttribute('class', v); }
  get children() { return this.childNodes.filter((c) => c.nodeType === 1); }
  get firstElementChild() { return this.children[0] || null; }
  get options() { return this.querySelectorAll('option'); }
  _prop(n, attr, dflt) { return Object.prototype.hasOwnProperty.call(this._props, n) ? this._props[n] : (this.hasAttribute(attr) ? this.getAttribute(attr) : dflt); }
  get value() {
    if (this.tagName === 'SELECT' && !Object.prototype.hasOwnProperty.call(this._props, 'value')) { const o = this.options; const s = o.find((x) => x.hasAttribute('selected')) || o[0]; return s ? s.value : ''; }
    if (this.tagName === 'OPTION' && !this.hasAttribute('value') && !Object.prototype.hasOwnProperty.call(this._props, 'value')) return this.textContent;
    if (this.tagName === 'TEXTAREA' && !Object.prototype.hasOwnProperty.call(this._props, 'value')) return this.textContent;
    return this._prop('value', 'value', '');
  }
  set value(v) { this._props.value = String(v); }
  get disabled() { return !!this._prop('disabled', 'disabled', false) || this._prop('disabled', 'disabled', false) === ''; } set disabled(v) { this._props.disabled = !!v; }
  get hidden() { return Object.prototype.hasOwnProperty.call(this._props, 'hidden') ? this._props.hidden : this.hasAttribute('hidden'); } set hidden(v) { this._props.hidden = !!v; }
  get checked() { return Object.prototype.hasOwnProperty.call(this._props, 'checked') ? this._props.checked : this.hasAttribute('checked'); } set checked(v) { this._props.checked = !!v; }
  get title() { return this._prop('title', 'title', ''); } set title(v) { this._props.title = String(v); }
  get type() { return this._prop('type', 'type', this.tagName === 'BUTTON' ? 'submit' : ''); } set type(v) { this._props.type = String(v); }
  get src() { return this.getAttribute('src') || ''; } set src(v) { this.setAttribute('src', v); }
  get alt() { return this.getAttribute('alt') || ''; } set alt(v) { this.setAttribute('alt', v); }
  get innerHTML() { return this.childNodes.map(serialize).join(''); }
  set innerHTML(h) { this.childNodes.forEach((c) => { c.parentNode = null; }); this.childNodes = []; parseInto(this.ownerDocument, String(h), this); }
  addEventListener(t, f) { (this.listeners[t] = this.listeners[t] || []).push(f); }
  removeEventListener(t, f) { this.listeners[t] = (this.listeners[t] || []).filter((x) => x !== f); }
  dispatchEvent(ev) { (this.listeners[ev.type] || []).forEach((f) => f.call(this, ev)); return true; }
  click() {
    if (this.disabled) return; // tarayıcıda devre dışı düğme tıklanmaz
    const ev = { type: 'click', target: this, preventDefault() {}, stopPropagation() {} };
    if (typeof this.onclick === 'function') this.onclick(ev);
    else if (this.hasAttribute('onclick') && this.ownerDocument._ctx) this.ownerDocument._ctx.__runAttr(this, this.getAttribute('onclick'));
    this.dispatchEvent(ev);
  }
  focus() { this.ownerDocument.activeElement = this; } blur() {} select() {}
  scrollIntoView() { this.ownerDocument._scrolled.push(this.id || this.tagName); }
  getContext() { return new Proxy({}, { get: () => function () { return { width: 0 }; } }); }
  getBoundingClientRect() { return { top: 0, left: 0, width: 0, height: 0, bottom: 0, right: 0 }; }
  matches(sel) { return matchSel(this, parseSel(sel), null); }
  closest(sel) { const s = parseSel(sel); let n = this; while (n && n.nodeType === 1) { if (matchSel(n, s, null)) return n; n = n.parentNode; } return null; }
  querySelectorAll(sel) { const s = parseSel(sel); const out = []; walk(this, (e) => { if (e !== this && matchSel(e, s, this)) out.push(e); }); return out; }
  querySelector(sel) { return this.querySelectorAll(sel)[0] || null; }
  getElementsByTagName(t) { return this.querySelectorAll(t); }
  get offsetParent() { return this.parentNode; }
}
function walk(root, f) { root.childNodes.forEach((c) => { if (c.nodeType === 1) { f(c); walk(c, f); } }); }
function esc(s) { return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); }
function serialize(n) {
  if (n.nodeType === 3) return esc(n.data);
  const a = Array.from(n.attrs).map(([k, v]) => ` ${k}="${String(v).replace(/"/g, '&quot;')}"`).join('');
  const t = n.tagName.toLowerCase();
  return VOID.has(t) ? `<${t}${a}>` : `<${t}${a}>${n.childNodes.map(serialize).join('')}</${t}>`;
}
function decode(s) {
  return s.replace(/&(#x[0-9a-f]+|#\d+|amp|lt|gt|quot|apos|nbsp);/gi, (m, e) => {
    const l = e.toLowerCase();
    if (l[0] === '#') return String.fromCodePoint(l[1] === 'x' ? parseInt(l.slice(2), 16) : parseInt(l.slice(1), 10));
    return { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ' }[l];
  });
}
// Hoşgörülü HTML ayrıştırıcı (yalnız test): yorum, doctype, ham metin öğeleri, boş öğeler, eşleşmeyen kapanış.
function parseInto(doc, html, root) {
  const stack = [root];
  const top = () => stack[stack.length - 1];
  let i = 0;
  const n = html.length;
  while (i < n) {
    const lt = html.indexOf('<', i);
    if (lt < 0) { top().appendChild(doc.createTextNode(decode(html.slice(i)))); break; }
    if (lt > i) top().appendChild(doc.createTextNode(decode(html.slice(i, lt))));
    if (html.startsWith('<!--', lt)) { const e = html.indexOf('-->', lt + 4); i = e < 0 ? n : e + 3; continue; }
    if (html[lt + 1] === '!' || html[lt + 1] === '?') { const e = html.indexOf('>', lt); i = e < 0 ? n : e + 1; continue; }
    if (html[lt + 1] === '/') {
      const e = html.indexOf('>', lt); const tag = html.slice(lt + 2, e).trim().toLowerCase();
      const k = stack.map((x) => x.localName).lastIndexOf(tag);
      if (k > 0) stack.length = k;
      i = e + 1; continue;
    }
    const m = /^<([a-zA-Z][\w-]*)/.exec(html.slice(lt, lt + 40));
    if (!m) { top().appendChild(doc.createTextNode('<')); i = lt + 1; continue; }
    const tag = m[1].toLowerCase();
    // öznitelikler (tırnaklı değerlerdeki '>' atlanır)
    let j = lt + m[0].length; const attrs = [];
    const re = /\s*([^\s=>\/"']+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+)))?|\s*\/(?=>)|\s+/y;
    while (j < n && html[j] !== '>') {
      re.lastIndex = j; const a = re.exec(html);
      if (!a || a[0] === '') { j++; continue; }
      if (a[1]) attrs.push([a[1].toLowerCase(), decode(a[2] !== undefined ? a[2] : a[3] !== undefined ? a[3] : a[4] !== undefined ? a[4] : '')]);
      j = re.lastIndex;
    }
    i = j + 1;
    const ac = AUTOCLOSE[tag];
    if (ac) while (stack.length > 1 && ac.includes(top().localName)) stack.pop();
    const el = doc.createElement(tag); attrs.forEach(([k, v]) => el.setAttribute(k, v));
    top().appendChild(el);
    if (RAW.has(tag)) {
      // toLowerCase() kullanılmaz: 'İ' gibi harflerde dizin kayar
      const rx = new RegExp('</' + tag, 'ig'); rx.lastIndex = i; const mm = rx.exec(html); const e = mm ? mm.index : -1; const body = html.slice(i, e < 0 ? n : e);
      if (body) el.appendChild(doc.createTextNode(tag === 'textarea' || tag === 'title' ? decode(body) : body));
      const g = e < 0 ? n : html.indexOf('>', e); i = g < 0 ? n : g + 1; continue;
    }
    if (!VOID.has(tag)) stack.push(el);
  }
}
// Seçici: virgül grupları; birleştirici ' ' ve '>'; bileşik: etiket, *, #id, .sınıf, [öz], [öz="d"], :scope, :not(bileşik)
const SELCACHE = new Map();
function parseSel(sel) {
  if (SELCACHE.has(sel)) return SELCACHE.get(sel);
  const groups = splitTop(sel, ',').map((g) => {
    const parts = []; let comb = ' '; let s = g.trim();
    while (s.length) {
      if (s[0] === '>') { comb = '>'; s = s.slice(1).trim(); continue; }
      const k = scanCompound(s); parts.push({ comb, c: parseCompound(s.slice(0, k)) }); comb = ' '; s = s.slice(k);
      const ws = /^\s*/.exec(s)[0]; s = s.slice(ws.length);
    }
    return parts;
  });
  SELCACHE.set(sel, groups); return groups;
}
function splitTop(s, ch) { const out = []; let d = 0, q = null, cur = ''; for (const c of s) { if (q) { if (c === q) q = null; } else if (c === '"' || c === "'") q = c; else if (c === '(' || c === '[') d++; else if (c === ')' || c === ']') d--; else if (c === ch && d === 0) { out.push(cur); cur = ''; continue; } cur += c; } out.push(cur); return out; }
function scanCompound(s) { let d = 0, q = null; for (let i = 0; i < s.length; i++) { const c = s[i]; if (q) { if (c === q) q = null; continue; } if (c === '"' || c === "'") q = c; else if (c === '(' || c === '[') d++; else if (c === ')' || c === ']') d--; else if (d === 0 && (c === ' ' || c === '>' || c === '\t' || c === '\n')) return i; } return s.length; }
function parseCompound(s) {
  const c = { tag: null, id: null, cls: [], attrs: [], scope: false, not: [] };
  const re = /^(\*|[a-zA-Z][\w-]*)|^#([\w-]+)|^\.([\w-]+)|^\[([\w-]+)(?:([~^$*|]?=)["']?([^"'\]]*)["']?)?\]|^:scope|^:not\(([^)]*)\)|^:([\w-]+)/;
  while (s.length) {
    const m = re.exec(s); if (!m) throw new Error('seçici desteklenmiyor: ' + s);
    if (m[1]) c.tag = m[1] === '*' ? null : m[1].toUpperCase();
    else if (m[2]) c.id = m[2]; else if (m[3]) c.cls.push(m[3]);
    else if (m[4]) c.attrs.push([m[4], m[5], m[6]]);
    else if (m[0] === ':scope') c.scope = true;
    else if (m[7] !== undefined) c.not.push(parseCompound(m[7].trim()));
    else if (m[8]) { if (m[8] === 'checked') c.attrs.push(['checked']); }
    s = s.slice(m[0].length);
  }
  return c;
}
function matchCompound(e, c, scope) {
  if (c.scope) return e === scope;
  if (c.tag && e.tagName !== c.tag) return false;
  if (c.id && e.id !== c.id) return false;
  if (c.cls.length && !c.cls.every((x) => e.classList.contains(x))) return false;
  for (const [n, op, v] of c.attrs) {
    if (n === 'checked' && !op) { if (!e.checked) return false; continue; }
    if (!e.hasAttribute(n)) return false; const a = e.getAttribute(n);
    if (op === '=' && a !== v) return false; if (op === '^=' && !a.startsWith(v)) return false;
    if (op === '*=' && !a.includes(v)) return false; if (op === '$=' && !a.endsWith(v)) return false;
    if (op === '~=' && !a.split(/\s+/).includes(v)) return false;
  }
  if (c.not.some((x) => matchCompound(e, x, scope))) return false;
  return true;
}
function matchParts(e, parts, k, scope) {
  if (!matchCompound(e, parts[k].c, scope)) return false;
  if (k === 0) return true;
  const comb = parts[k].comb;
  if (comb === '>') return !!e.parentNode && e.parentNode.nodeType === 1 && matchParts(e.parentNode, parts, k - 1, scope);
  let p = e.parentNode; while (p && p.nodeType === 1) { if (matchParts(p, parts, k - 1, scope)) return true; p = p.parentNode; }
  return false;
}
function matchSel(e, groups, scope) { return groups.some((g) => matchParts(e, g, g.length - 1, scope)); }

class Document extends Element {
  constructor() { super(null, '#document'); this.ownerDocument = this; this.nodeType = 9; this.readyState = 'complete'; this.visibilityState = 'visible'; this._scrolled = []; this.activeElement = null; }
  createElement(t) { return new Element(this, t); }
  createElementNS(_ns, t) { return new Element(this, t); }   // SVG (Kanal Prekastı kesit önizlemesi; Chromium 64 destekler)
  createTextNode(s) { return new Text(this, String(s)); }
  createDocumentFragment() { const f = new Element(this, '#fragment'); f.nodeType = 11; return f; }
  getElementById(id) { let r = null; walk(this, (e) => { if (!r && e.id === id) r = e; }); return r; }
  get body() { return this.querySelector('body') || this; }
  get head() { return this.querySelector('head') || this; }
  get documentElement() { return this.querySelector('html') || this; }
}

// vm bağlamı: window = global; sahte zamanlayıcılar (elle çalıştırılır), sketchup kaydedici.
function makeContext(html, opts = {}) {
  const doc = new Document();
  parseInto(doc, html, doc);
  const timers = []; const calls = []; const errors = []; const alerts = [];
  const sk = new Proxy({}, {
    get(t, k) { if (k in t) return t[k]; if (typeof k !== 'string') return undefined; return function (...a) { calls.push([k, ...a]); }; },
    has() { return true; }
  });
  const ctx = {
    document: doc, sketchup: sk, console: { log() {}, warn() {}, info() {}, error(...a) { errors.push(a.map(String).join(' ')); } },
    setTimeout(f, ms) { timers.push({ f, ms: ms || 0 }); return timers.length; }, clearTimeout(id) { if (timers[id - 1]) timers[id - 1].f = null; },
    setInterval() { return 0; }, clearInterval() {}, requestAnimationFrame(f) { timers.push({ f, ms: 0 }); return timers.length; },
    alert(m) { alerts.push(String(m)); }, confirm() { return opts.confirm !== false; }, prompt() { return null; },
    navigator: { userAgent: 'node-fakedom' }, location: { hash: '', href: 'file:///ui.html' }, getComputedStyle() { return { display: '' }; },
    scrollTo() {}, addEventListener(t, f) { (ctx.__winL[t] = ctx.__winL[t] || []).push(f); }, removeEventListener() {}, __winL: {},
    JSON, Math, Date, Object, Array, String, Number, Boolean, RegExp, Error, Set, Map, Promise, parseInt, parseFloat, isFinite, isNaN, Intl, Symbol, encodeURIComponent, decodeURIComponent
  };
  ctx.window = ctx; ctx.self = ctx; ctx.globalThis = ctx;
  vm.createContext(ctx);
  ctx.__runAttr = function (el, code) { ctx.__el = el; vm.runInContext('(function(){' + code + '\n}).call(__el)', ctx); };
  doc._ctx = ctx;
  return {
    ctx, doc, calls, errors, alerts, timers,
    run(code, name) { try { vm.runInContext(code, ctx, { filename: name || 'betik.js' }); return null; } catch (e) { return (name || '') + ': ' + e.message; } },
    flush(max = 500) { let k = 0; for (;;) { const i = timers.findIndex((x) => x.f); if (i < 0 || k++ > max) break; const f = timers[i].f; timers[i].f = null; try { f(); } catch (e) { errors.push('zamanlayıcı: ' + e.message + ' @ ' + String(e.stack).split(/\n/)[1]); } } },
    fireDCL() { (doc.listeners.DOMContentLoaded || []).forEach((f) => f()); }
  };
}
// ui.html içinden üst düzey `function ad(` gövdesini (dengeli süslü parantez; dizgi / şablon / yorum atlanır) çıkarır.
function extractFunction(src, name) {
  const a = src.search(new RegExp('(^|[\\s;}])function ' + name + '\\('));
  if (a < 0) return null;
  const s = src.indexOf('function ' + name + '(', a);
  let i = src.indexOf('{', s), d = 0, q = null;
  for (; i < src.length; i++) {
    const c = src[i];
    if (q) { if (c === '\\') { i++; continue; } if (c === q) q = null; continue; }
    if (c === '/' && src[i + 1] === '/') { i = src.indexOf('\n', i); continue; }
    if (c === '/' && src[i + 1] === '*') { i = src.indexOf('*/', i) + 1; continue; }
    if (c === '"' || c === "'" || c === '`') { q = c; continue; }
    if (c === '{') d++; else if (c === '}') { d--; if (d === 0) return src.slice(s, i + 1); }
  }
  return null;
}
module.exports = { makeContext, extractFunction, parseSel };
// ui.html'i tarayıcı sırasıyla yükler: ayrıştırma sırasında readyState='loading'; defer'siz betikler belge sırasıyla,
// defer'li dış betikler ayrıştırmadan sonra; ardından DOMContentLoaded ve zamanlayıcılar. Dönen: { D, loadErrors }.
function loadPage(dir, opts = {}) {
  const fs = require('fs'); const path = require('path');
  const html = fs.readFileSync(path.join(dir, opts.file || 'ui.html'), 'utf8');
  const D = makeContext(html, opts);
  D.ctx.MutationObserver = function () { this.observe = function () {}; this.disconnect = function () {}; };
  D.doc.readyState = 'loading';
  if (opts.before) opts.before(D);
  const loadErrors = [];
  const scripts = D.doc.querySelectorAll('script');
  const deferred = [];
  const runOne = (s, i) => {
    const src = s.getAttribute('src');
    const type = s.getAttribute('type');
    if (type && !/javascript|module/i.test(type)) return;
    const code = src ? fs.readFileSync(path.join(dir, src), 'utf8') : s.textContent;
    const e = D.run(code, src || ('ui.html satır içi #' + i));
    if (e) loadErrors.push(e);
  };
  scripts.forEach((s, i) => { if (s.getAttribute('src') && s.hasAttribute('defer')) deferred.push([s, i]); else runOne(s, i); });
  D.doc.readyState = 'interactive';
  deferred.forEach(([s, i]) => runOne(s, i));
  try { D.fireDCL(); } catch (e) { loadErrors.push('DOMContentLoaded: ' + e.message); }
  D.doc.readyState = 'complete';
  D.flush();
  return { D, loadErrors };
}
module.exports.loadPage = loadPage;
