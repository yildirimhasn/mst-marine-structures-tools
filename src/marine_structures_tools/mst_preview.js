/* MST — Kesit / Boyuna / 3B önizleme motoru (v0.51.13 ÖN1)
   Kanal Prekastı önizlemesiyle (chDrawSection / chDrawIso) aynı ilke: yalnız SVG (polygon / path / line / text), WebGL yok,
   Ruby geri çağrısı yok, model DEĞİŞMEZ. Form girdileri okunur, şematik ölçekli çizim üretilir; hesap doğrulaması değildir.
   Katmanlar:
     MSTPreview.geom  — saf geometri (profil üretimi, izometrik izdüşüm, yüz sıralama); DOM gerektirmez, node ile test edilir.
     MSTPreview.build — sayfa başına görünüm üreticileri (kazık, fore, jet, BK, prekast, döşeme, kronman, dolgu).
     MSTPreview.ui    — kart / düğme / SVG çizimi ve sayfa bağlantıları (ui.html, bored_pile.html, jet_grout.html).
   Chromium 64 (SketchUp 2020 HtmlDialog) ile uyumlu ES2015. */
(function (global) {
  'use strict';
  var EPS = 1e-9;
  var VIEW_W = 320, VIEW_H = 190;

  /* ---------------------------------------------------------------- sayı yardımcıları */
  function num(v, dflt) {
    if (typeof v === 'number') return isFinite(v) ? v : dflt;
    var s = String(v == null ? '' : v).trim().replace(',', '.');
    if (!s) return dflt;
    var n = Number(s);
    return isFinite(n) ? n : dflt;
  }
  // H/V eğim oranı: "1/6", "1:6", "0,1667" — pile_batter_ratio (Ruby) ile aynı kural
  function ratio(v) {
    if (typeof v === 'number') return Math.abs(v);
    var s = String(v == null ? '' : v).trim().replace(',', '.').replace(':', '/');
    if (!s) return 0;
    if (s.indexOf('/') >= 0) { var p = s.split('/'); var a = Number(p[0]), b = Number(p[1]); return (isFinite(a) && isFinite(b) && Math.abs(b) > EPS) ? Math.abs(a / b) : 0; }
    var n = Number(s); return isFinite(n) ? Math.abs(n) : 0;
  }
  function fmt(v, d) { return (Math.round(v * Math.pow(10, d)) / Math.pow(10, d)).toFixed(d).replace('.', ','); }
  function fmtEl(v) { return (v >= 0 ? '+' : '') + fmt(v, 2); }

  /* ---------------------------------------------------------------- vektörler */
  function add(a, b) { return [a[0] + b[0], a[1] + b[1], a[2] + b[2]]; }
  function sub(a, b) { return [a[0] - b[0], a[1] - b[1], a[2] - b[2]]; }
  function mul(a, k) { return [a[0] * k, a[1] * k, a[2] * k]; }
  function dot(a, b) { return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]; }
  function cross(a, b) { return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]; }
  function len3(a) { return Math.sqrt(dot(a, a)); }
  function unit(a) { var l = len3(a); return l < EPS ? [0, 0, 0] : mul(a, 1 / l); }

  /* ---------------------------------------------------------------- izdüşüm (Kanal Prekastı ile aynı: bakış yönü (-1,1,1)) */
  var C30 = Math.cos(Math.PI / 6);
  var EYE = unit([-1, 1, 1]);
  function proj(p) { return [(p[0] + p[1]) * C30, (p[1] - p[0]) * 0.5 - p[2]]; }

  // Çıkarma ekseni d için yerel çerçeve (profil (u,v) → e1,e2). Çağıran açık çerçeve de verebilir.
  function frame(d) {
    d = unit(d);
    var up = Math.abs(d[2]) > 0.999 ? [1, 0, 0] : [0, 0, 1];
    var e1 = unit(cross(up, d)); var e2 = cross(d, e1);
    return { e1: e1, e2: e2, d: d };
  }
  function circle(r, n, cy, cz) { var pts = []; n = n || 36; for (var i = 0; i < n; i++) { var a = 2 * Math.PI * i / n; pts.push([(cy || 0) + r * Math.cos(a), (cz || 0) + r * Math.sin(a)]); } return pts; }
  function rect(y0, z0, y1, z1) { return [[y0, z0], [y1, z0], [y1, z1], [y0, z1]]; }
  function area2(pts) { var a = 0; for (var i = 0; i < pts.length; i++) { var p = pts[i], q = pts[(i + 1) % pts.length]; a += p[0] * q[1] - q[0] * p[1]; } return a / 2; }
  function bbox2(pts) { var x0 = Infinity, x1 = -Infinity, y0 = Infinity, y1 = -Infinity; pts.forEach(function (p) { x0 = Math.min(x0, p[0]); x1 = Math.max(x1, p[0]); y0 = Math.min(y0, p[1]); y1 = Math.max(y1, p[1]); }); return [x0, y0, x1, y1]; }

  /* Katı: {profile:[[u,v]…], frame:{e1,e2,d}|null, axis:[dx,dy,dz], origin:[x,y,z], L, fill, hole:[[u,v]…]|null, inner:bool}
     → yüzler: {pts:[[x,y,z]…], holes:[[…]], n, c, fill, cap} ; inner=true ise normal ters (içten görünen duvar, ör. boru iç yüzü) */
  function solidFaces(s) {
    var fr = s.frame || frame(s.axis || [1, 0, 0]);
    var o = s.origin || [0, 0, 0];
    var P = function (u, v, t) { return add(add(add(o, mul(fr.e1, u)), mul(fr.e2, v)), mul(fr.d, t)); };
    var prof = s.profile, L = s.L, n = prof.length, i;
    var p0 = [], p1 = [];
    for (i = 0; i < n; i++) { p0.push(P(prof[i][0], prof[i][1], 0)); p1.push(P(prof[i][0], prof[i][1], L)); }
    var winding = area2(prof) < 0 ? -1 : 1;
    var frameSign = dot(cross(fr.e1, fr.e2), fr.d) < 0 ? -1 : 1;
    var faces = [];
    var mk = function (pts, holes, cap, sign) {
      var nn = [0, 0, 0];
      for (var k = 0; k < pts.length; k++) { var a = pts[k], b = pts[(k + 1) % pts.length]; nn[0] += (a[1] - b[1]) * (a[2] + b[2]); nn[1] += (a[2] - b[2]) * (a[0] + b[0]); nn[2] += (a[0] - b[0]) * (a[1] + b[1]); }
      nn = unit(nn);
      var c = [0, 0, 0]; pts.forEach(function (p) { c = add(c, p); }); c = mul(c, 1 / pts.length);
      nn = mul(nn, sign);
      if (s.inner) nn = mul(nn, -1);
      faces.push({ pts: pts, holes: holes || [], n: nn, c: c, fill: s.fill, cap: !!cap, solid: s });
    };
    var h0 = null, h1 = null;
    if (s.hole) { h0 = []; h1 = []; for (i = 0; i < s.hole.length; i++) { h0.push(P(s.hole[i][0], s.hole[i][1], 0)); h1.push(P(s.hole[i][0], s.hole[i][1], L)); } }
    mk(p0, h0 ? [h0] : null, true, -winding * frameSign);
    mk(p1, h1 ? [h1] : null, true, winding * frameSign);
    for (i = 0; i < n; i++) mk([p0[i], p0[(i + 1) % n], p1[(i + 1) % n], p1[i]], null, false, winding * frameSign);
    return faces;
  }
  // Görünür yüzler (n·EYE > 0) uzaktan yakına sıralı; sonraki katılar eşitlikte üstte
  function visibleFaces(solids, eye) {
    eye=eye||EYE;
    var out = [];
    solids.forEach(function (s, si) { solidFaces(s).forEach(function (f) { if (dot(f.n, eye) > 1e-6) { f.depth = dot(f.c, eye) + si * 1e-6; out.push(f); } }); });
    out.sort(function (a, b) { return a.depth - b.depth; });
    return out;
  }
  // Renk: hex → tonlama (üst yüz açık, yan yüz ışığa göre)
  function shade(hex, f) {
    var m = /^#?([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i.exec(hex || '#aeb5ba');
    if (!m) return hex;
    var c = [parseInt(m[1], 16), parseInt(m[2], 16), parseInt(m[3], 16)].map(function (v) { v = Math.round(f >= 1 ? v + (255 - v) * (f - 1) : v * f); return Math.max(0, Math.min(255, v)); });
    return '#' + c.map(function (v) { return ('0' + v.toString(16)).slice(-2); }).join('');
  }
  var LIGHT = unit([-0.4, 0.5, 0.75]);
  function faceColor(f) { var l = 0.72 + 0.4 * Math.max(0, dot(f.n, LIGHT)); return shade(f.fill, f.cap && f.n[2] > 0.5 ? 1.18 : l); }

  /* ---------------------------------------------------------------- SVG yardımcıları (ui katmanı) */
  function svgEl(svg, tag, attrs, text) {
    var e = document.createElementNS('http://www.w3.org/2000/svg', tag);
    for (var k in attrs) if (Object.prototype.hasOwnProperty.call(attrs, k) && attrs[k] != null) e.setAttribute(k, attrs[k]);
    if (text != null) e.textContent = text;
    svg.appendChild(e); return e;
  }
  function clear(svg) { while (svg.firstChild) svg.removeChild(svg.firstChild); }
  function canvasSize(svg) { return svg._mstSize || [VIEW_W, VIEW_H]; }
  function applyViewBox(svg) {
    var size = canvasSize(svg), factor = Number(svg.getAttribute('data-mst-scale') || 1);
    var w = size[0] / factor, h = size[1] / factor;
    svg.setAttribute('viewBox', [(size[0] - w) / 2, (size[1] - h) / 2, w, h].join(' '));
  }
  function msg(svg, t) { var size = canvasSize(svg); svgEl(svg, 'text', { x: size[0] / 2, y: size[1] / 2, 'text-anchor': 'middle', 'class': 'mstpv-msg' }, t); }

  /* Kesit görünümü: shapes [{pts:[[y,z]…], fill, stroke, dash, holes:[[…]], label:'…'}], dims [{a:[y,z], b:[y,z], text, off}],
     labels [{p:[y,z], text, anchor}], notes [str] ; dünya metre, otomatik sığdırma (eş ölçek) */
  function drawPlane(svg, view) {
    clear(svg);
    if (view.error) { msg(svg, view.error); return; }
    var pts = [];
    view.shapes.forEach(function (s) { pts = pts.concat(s.pts); (s.holes || []).forEach(function (h) { pts = pts.concat(h); }); });
    (view.dims || []).forEach(function (d) { pts.push(d.a, d.b); });
    if (!pts.length) { msg(svg, 'Çizilecek geometri yok.'); return; }
    var bb = bbox2(pts), w = Math.max(bb[2] - bb[0], 1e-6), h = Math.max(bb[3] - bb[1], 1e-6);
    var padL = 14, padR = view.padR || 64, padT = view.notes && view.notes.length ? 12 + 11 * view.notes.length : 14, padB = (view.dims || []).some(function (d) { return d.off < 0 || d.horizontal; }) ? 34 : 16;
    var size = canvasSize(svg), viewW = size[0], viewH = size[1];
    var sc = Math.min((viewW - padL - padR) / w, (viewH - padT - padB) / h);
    var ox = padL + ((viewW - padL - padR) - w * sc) / 2 - bb[0] * sc, oy = viewH - padB - ((viewH - padT - padB) - h * sc) / 2 + bb[1] * sc;
    var X = function (y) { return (ox + y * sc).toFixed(1); }, Y = function (z) { return (oy - z * sc).toFixed(1); };
    var pl = function (arr) { return arr.map(function (p) { return X(p[0]) + ',' + Y(p[1]); }).join(' '); };
    view.shapes.forEach(function (s) {
      if (s.holes && s.holes.length) {
        var d = 'M' + pl(s.pts).replace(/ /g, 'L') + 'Z' + s.holes.map(function (hh) { return 'M' + pl(hh).replace(/ /g, 'L') + 'Z'; }).join('');
        svgEl(svg, 'path', { d: d, 'fill-rule': 'evenodd', fill: s.fill || '#aeb5ba', stroke: s.stroke || '#4e5960', 'stroke-width': s.sw || '1', 'stroke-dasharray': s.dash || null, 'fill-opacity': s.opacity || null });
      } else {
        svgEl(svg, s.open ? 'polyline' : 'polygon', { points: pl(s.pts), fill: s.open ? 'none' : (s.fill || '#aeb5ba'), stroke: s.stroke || '#4e5960', 'stroke-width': s.sw || '1', 'stroke-dasharray': s.dash || null, 'fill-opacity': s.opacity || null });
      }
    });
    (view.dims || []).forEach(function (d) {
      var st = { stroke: '#173650', 'stroke-width': '0.8' };
      if (d.horizontal) {
        var yd = +Y(Math.min(d.a[1], d.b[1])) + (d.off || 14);
        svgEl(svg, 'line', { x1: X(d.a[0]), y1: yd, x2: X(d.b[0]), y2: yd, stroke: st.stroke, 'stroke-width': st['stroke-width'] });
        [d.a[0], d.b[0]].forEach(function (yy) { svgEl(svg, 'line', { x1: X(yy), y1: yd - 4, x2: X(yy), y2: yd + 4, stroke: st.stroke, 'stroke-width': st['stroke-width'] }); });
        svgEl(svg, 'text', { x: X((d.a[0] + d.b[0]) / 2), y: yd + 11, 'text-anchor': 'middle', 'class': 'mstpv-dim' }, d.text);
      } else {
        var xd = +X(Math.max(d.a[0], d.b[0])) + (d.off || 12);
        svgEl(svg, 'line', { x1: xd, y1: Y(d.a[1]), x2: xd, y2: Y(d.b[1]), stroke: st.stroke, 'stroke-width': st['stroke-width'] });
        [d.a[1], d.b[1]].forEach(function (zz) { svgEl(svg, 'line', { x1: xd - 4, y1: Y(zz), x2: xd + 4, y2: Y(zz), stroke: st.stroke, 'stroke-width': st['stroke-width'] }); });
        svgEl(svg, 'text', { x: xd + 5, y: (+Y((d.a[1] + d.b[1]) / 2) + 3).toFixed(1), 'class': 'mstpv-dim' }, d.text);
      }
    });
    (view.labels || []).forEach(function (l) { svgEl(svg, 'text', { x: X(l.p[0]), y: Y(l.p[1]), 'text-anchor': l.anchor || 'middle', 'class': 'mstpv-dim' + (l.strong ? ' mstpv-strong' : '') }, l.text); });
    (view.notes || []).forEach(function (t, i) { svgEl(svg, 'text', { x: 8, y: 11 + 11 * i, 'class': 'mstpv-dim' }, t); });
  }

  /* 3B görünüm: view {solids:[…], notes:[…], hidden:bool} — yüzler uzaktan yakına, ışıklı tonlama */
  function drawIso(svg, view) {
    clear(svg);
    if (view.error) { msg(svg, view.error); return; }
    var yaw=svg._mstYaw || 0, cos=Math.cos(yaw), sin=Math.sin(yaw);
    var rotate=function(p){return [cos*p[0]-sin*p[1],sin*p[0]+cos*p[1],p[2]];};
    var eye=[cos*EYE[0]+sin*EYE[1],-sin*EYE[0]+cos*EYE[1],EYE[2]];
    var project=function(p){return proj(rotate(p));};
    var faces = view.faces ? view.faces.filter(function(f){return dot(f.n,eye)>1e-6;}).map(function(f){
      var center=mul(f.pts.reduce(add,[0,0,0]),1/f.pts.length);
      return Object.assign({},f,{depth:dot(center,eye),solid:{}});
    }).sort(function(a,b){return a.depth-b.depth;}) : visibleFaces(view.solids,eye);
    if (!faces.length) { msg(svg, 'Çizilecek geometri yok.'); return; }
    var all = [];
    var boundsFaces=view.faces || view.solids.reduce(function(out,solid){return out.concat(solidFaces(solid));},[]); boundsFaces.forEach(function(f){f.pts.forEach(function(p){all.push(project(p));});});
    var bb = bbox2(all), w = Math.max(bb[2] - bb[0], 1e-9), h = Math.max(bb[3] - bb[1], 1e-9);
    var size = canvasSize(svg), viewW = size[0], viewH = size[1];
    var pT = 12 + 11 * ((view.notes || []).length), pB = 8, pX = 10, sc = Math.min((viewW - 2 * pX) / w, (viewH - pT - pB) / h);
    var ox = pX + ((viewW - 2 * pX) - w * sc) / 2 - bb[0] * sc, oy = pT + ((viewH - pT - pB) - h * sc) / 2 - bb[1] * sc;
    var Q = function (p) { var q = project(p); return (ox + q[0] * sc).toFixed(1) + ',' + (oy + q[1] * sc).toFixed(1); };
    var pl = function (pts) { return pts.map(Q).join(' '); };
    faces.forEach(function (f) {
      var col = faceColor(f);
      if (f.holes.length) {
        var d = 'M' + pl(f.pts).replace(/ /g, 'L') + 'Z' + f.holes.map(function (hh) { return 'M' + pl(hh).replace(/ /g, 'L') + 'Z'; }).join('');
        svgEl(svg, 'path', { d: d, 'fill-rule': 'evenodd', fill: col, stroke: '#3f4a52', 'stroke-width': '0.7', 'stroke-linejoin': 'round' });
      } else {
        svgEl(svg, 'polygon', { points: pl(f.pts), fill: col, stroke: f.solid.edges === false ? col : '#3f4a52', 'stroke-width': f.solid.edges === false ? '0.3' : '0.7', 'stroke-linejoin': 'round' });
      }
    });
    (view.notes || []).forEach(function (t, i) { svgEl(svg, 'text', { x: pX, y: 11 + 11 * i, 'class': 'mstpv-dim' }, t); });
  }

  /* ---------------------------------------------------------------- görünüm üreticileri (saf) */
  var build = {};
  // Gösterim boyu: gerçek boy L, kesit en büyük ölçüsü D → en çok k·D çizilir (Kanal Prekastı kuralı: 6×)
  function dispLen(L, D, k) { var m = (k || 6) * Math.max(D, 0.05); return L > m + EPS ? { L: m, cut: true } : { L: Math.max(L, 0.05), cut: false }; }

  // Çelik boru kazık — f: {d_mm,t_mm,L,top,batter,az,infill,infill_bottom,seabed,plug}
  build.pile = function (f) {
    var D = num(f.d_mm, 0) / 1000, t = num(f.t_mm, 0) / 1000, L = num(f.L, 0), top = num(f.top, 0);
    var r = f.mode === 'BATTERED' ? ratio(f.batter) : 0, az = num(f.az, 0) * Math.PI / 180;
    var err = (!(D > 0 && t > 0 && D > 2 * t)) ? 'Çap ve et kalınlığı geçersiz (Ø > 2·t olmalı).' : (!(L > 0) ? 'Kazık boyu sıfırdan büyük olmalı.' : null);
    if (err) return { kesit: { error: err }, boyuna: { error: err }, iso: { error: err } };
    var di = D - 2 * t, vz = 1 / Math.sqrt(1 + r * r), hz = r * vz;
    var down = [hz * Math.sin(az), hz * Math.cos(az), -vz];
    var calculatedBottom = top - L * vz;
    var bottom = num(f.bottom, calculatedBottom);
    if (!(bottom < top)) bottom = calculatedBottom;
    var infill = !!f.infill, ib = num(f.infill_bottom, NaN);
    var infillOk = infill && isFinite(ib) && ib < top && ib >= bottom - 1e-4;
    var sea = f.seabed == null || String(f.seabed).trim() === '' ? NaN : num(f.seabed, NaN);
    var verticalInGround = isFinite(sea) ? Math.max(0, Math.min(top, sea) - bottom) : null;
    var axisInGround = verticalInGround === null ? null : verticalInGround / vz;
    var soilInfo = axisInGround === null ? '' : 'Zeminde eksen boyu '+fmt(axisInGround,2)+' m'+
      (r > EPS ? ' · düşey derinlik '+fmt(verticalInGround,2)+' m' : '');
    // kesit
    var kes = { shapes: [{ pts: circle(D / 2, 48), holes: [circle(di / 2, 48)], fill: '#6f8ea8', stroke: '#2f4a5f' }], dims: [], labels: [], notes: [] };
    if (infillOk) kes.shapes.push({ pts: circle(di / 2, 48), fill: '#d9d9d9', stroke: '#8a8a8a', opacity: '0.9' });
    kes.dims.push({ a: [-D / 2, -D / 2], b: [D / 2, -D / 2], horizontal: true, text: 'Ø ' + fmt(D * 1000, 1) + ' mm', off: 14 });
    kes.dims.push({ a: [D / 2 - t, 0], b: [D / 2, 0], text: 't ' + fmt(t * 1000, 1) + ' mm', off: 12 });
    kes.labels.push({ p: [0, infillOk ? -di * 0.15 : 0], text: infillOk ? 'iç beton' : 'iç çap Ø ' + fmt(di * 1000, 1), strong: !infillOk });
    kes.notes.push('Enine kesit — çelik π/4·(D²−d²) = ' + fmt(Math.PI / 4 * (D * D - di * di), 4) + ' m²');
    // boyuna (düşey kesit; eğik kazıkta eksen eğik gösterilir)
    var sx = hz / vz; // yatay / düşey
    var ax = function (z) { return (top - z) * sx; }; // z kotundaki eksen yatay konumu (m)
    var strip = function (yOff, w) { return [[ax(top) + yOff, top], [ax(top) + yOff + w, top], [ax(bottom) + yOff + w, bottom], [ax(bottom) + yOff, bottom]]; };
    var boy = { shapes: [strip(-D / 2, t), strip(D / 2 - t, t)].map(function (p) { return { pts: p, fill: '#6f8ea8', stroke: '#2f4a5f' }; }), dims: [], labels: [], notes: [], padR: 88 };
    boy.shapes.unshift({ pts: [[ax(top) - D / 2, top], [ax(top) + D / 2, top], [ax(bottom) + D / 2, bottom], [ax(bottom) - D / 2, bottom]], fill: '#eef2f5', stroke: '#9fb2c0', dash: '3,2' });
    if (infillOk) boy.shapes.push({ pts: [[ax(top) - di / 2, top], [ax(top) + di / 2, top], [ax(ib) + di / 2, ib], [ax(ib) - di / 2, ib]], fill: '#d9d9d9', stroke: '#8a8a8a' });
    if (isFinite(sea)) {
      var groundTop = Math.min(sea,top);
      var minX = Math.min(ax(top),ax(bottom)), maxX = Math.max(ax(top),ax(bottom));
      var side = Math.max(2*D, (top-bottom)*0.08);
      var left = minX-side, right = maxX+side;
      if (sea >= bottom) {
        var groundBottom = bottom - Math.max(D,(top-bottom)*0.05);
        boy.shapes.unshift({pts:rect(left,groundBottom,right,sea),fill:'#eee1ce',stroke:'none'});
        boy.labels.push({p:[left, groundBottom + (sea-groundBottom)*0.25],text:'Zemin',anchor:'start'});
      }
      boy.shapes.push({pts:[[left,sea],[right,sea]],open:true,stroke:'#8b6749',sw:1.4,dash:'5,3'});
      boy.labels.push({p:[left,sea+0.025*(top-bottom)],text:'Deniz tabanı '+fmtEl(sea),anchor:'start'});
      if (verticalInGround > 0) {
        boy.shapes.push({pts:[[ax(groundTop),groundTop],[ax(bottom),bottom]],open:true,stroke:'#137768',sw:2,dash:'4,2'});
        var depthX = right + 0.3*side;
        boy.dims.push({a:[depthX,bottom],b:[depthX,groundTop],off:8,text:fmt(verticalInGround,2)+' m'});
        boy.padR = 110;
      }
    }
    boy.dims.push({ a: [ax(bottom) + D / 2, bottom], b: [ax(top) + D / 2, top], text: 'L ' + fmt(L, 2) + ' m (eksen)', off: 12 });
    boy.labels.push({ p: [ax(top) - D / 2 - 0.02 * L, top], text: 'üst ' + fmtEl(top), anchor: 'end' });
    boy.labels.push({ p: [ax(bottom) - D / 2 - 0.02 * L, bottom], text: 'uç ' + fmtEl(bottom), anchor: 'end' });
    if (infillOk) boy.labels.push({ p: [ax(ib) - D / 2 - 0.02 * L, ib], text: 'beton altı ' + fmtEl(ib), anchor: 'end' });
    boy.notes.push(r > EPS ? 'Boyuna kesit — eğik H/V ' + fmt(r, 4) + ', azimut ' + fmt(num(f.az, 0), 1) + '°, düşey boy ' + fmt(L * vz, 2) + ' m' : 'Boyuna kesit — düşey kazık');
    if (soilInfo) boy.notes.push(soilInfo);
    // 3B
    var dl = dispLen(L, D, 5);
    var fr = frame(down);
    var o = [0, 0, top];
    var solids = [{ profile: circle(D / 2, 28), hole: circle(di / 2, 28), frame: fr, origin: o, L: dl.L, fill: '#6f8ea8' },
                  { profile: circle(di / 2, 28), frame: fr, origin: o, L: dl.L, fill: '#8aa0b2', inner: true, edges: false }];
    if (infillOk) solids.push({ profile: circle(di / 2 * 0.985, 28), frame: fr, origin: o, L: Math.min(dl.L, top - ib), fill: '#d9d9d9', edges: false });
    var iso = { solids: solids, notes: ['3B önizleme — model değişmez' + (dl.cut ? ' · boy ' + fmt(L, 1) + ' m, ' + fmt(dl.L, 1) + ' m olarak kısaltılarak çizildi' : ''),
      'Ø' + fmt(D * 1000, 1) + ' × t' + fmt(t * 1000, 1) + ' mm' + (r > EPS ? ' · eğik H/V ' + fmt(r, 3) : ' · düşey') + (infillOk ? ' · iç beton' : '')] };
    return { kesit: kes, boyuna: boy, iso: iso, soilInfo: soilInfo, info: (soilInfo ? soilInfo+' · ' : '')+'Boru çeliği ' + fmt(Math.PI / 4 * (D * D - di * di) * L * 7850 / 1000, 3) + ' t' + (infillOk ? ' · iç beton ' + fmt(Math.PI / 4 * di * di * (top - ib) / vz, 3) + ' m³' : '') };
  };

  // Dairesel beton kolon (fore kazık / jet grout) — f: {d_mm, top, bottom, drill_top, casing, label, fill}
  build.column = function (f) {
    var D = num(f.d_mm, 0) / 1000, top = num(f.top, NaN), bot = num(f.bottom, NaN), dt = num(f.drill_top, NaN), cas = num(f.casing, 0);
    var err = !(D > 0) ? 'Çap sıfırdan büyük olmalı.' : (!(isFinite(top) && isFinite(bot) && top > bot) ? 'Üst kot alt kottan büyük olmalı.' : null);
    if (err) return { kesit: { error: err }, boyuna: { error: err }, iso: { error: err } };
    var L = top - bot, fill = f.fill || '#c9c0a8';
    var kes = { shapes: [{ pts: circle(D / 2, 48), fill: fill, stroke: '#5a5243' }], dims: [{ a: [-D / 2, -D / 2], b: [D / 2, -D / 2], horizontal: true, text: 'Ø ' + fmt(D * 1000, 0) + ' mm', off: 14 }], labels: [{ p: [0, 0], text: f.label || 'beton', strong: true }], notes: ['Enine kesit — alan ' + fmt(Math.PI / 4 * D * D, 3) + ' m²'] };
    var boy = { shapes: [{ pts: rect(-D / 2, bot, D / 2, top), fill: fill, stroke: '#5a5243' }], dims: [{ a: [D / 2, bot], b: [D / 2, top], text: 'L ' + fmt(L, 2) + ' m', off: 12 }], labels: [{ p: [-D / 2 - 0.1 * D, top], text: 'üst ' + fmtEl(top), anchor: 'end' }, { p: [-D / 2 - 0.1 * D, bot], text: 'uç ' + fmtEl(bot), anchor: 'end' }], notes: ['Boyuna kesit — düşey kolon'], padR: 80 };
    if (isFinite(dt) && dt > top + 1e-6) { boy.shapes.push({ pts: rect(-D / 2, top, D / 2, dt), fill: '#f2f2f2', stroke: '#9a9a9a', dash: '3,2' }); boy.labels.push({ p: [-D / 2 - 0.1 * D, dt], text: 'delgi başı ' + fmtEl(dt), anchor: 'end' }); }
    if (cas > 0) { var ct = isFinite(dt) ? dt : top; boy.shapes.push({ pts: rect(-D / 2 - D * 0.04, ct - Math.min(cas, ct - bot), D / 2 + D * 0.04, ct), open: false, fill: 'none', stroke: '#2f4a5f', sw: '1.4' }); boy.labels.push({ p: [D / 2 + D * 0.3, ct - Math.min(cas, ct - bot) / 2], text: 'muhafaza ' + fmt(cas, 2) + ' m', anchor: 'start' }); }
    var dl = dispLen(L, D, 5);
    var iso = { solids: [{ profile: circle(D / 2, 28), frame: frame([0, 0, -1]), origin: [0, 0, top], L: dl.L, fill: fill }], notes: ['3B önizleme — model değişmez' + (dl.cut ? ' · boy kısaltılarak çizildi' : ''), 'Ø' + fmt(D * 1000, 0) + ' mm · boy ' + fmt(L, 2) + ' m' + (isFinite(dt) && dt > top + 1e-6 ? ' · delgi ' + fmt(dt - bot, 2) + ' m' : '')] };
    if (isFinite(dt) && dt > top + 1e-6) iso.solids.unshift({ profile: circle(D / 2, 28), frame: frame([0, 0, -1]), origin: [0, 0, dt], L: Math.min(dt - top, dl.L), fill: '#e6e6e6', edges: false });
    return { kesit: kes, boyuna: boy, iso: iso, info: 'Hacim ' + fmt(Math.PI / 4 * D * D * L, 3) + ' m³' };
  };

  // BK boyuna profil (x boy, z: ana gövde tabanı = 0) — headbeam_editor.rb recess_profile_points ile aynı kavramlar:
  // diş (tooth): uçta derinlik kadar alçalan taban, slope boyunca normal tabana döner; cep (seat): üstten derinlik kadar oyuk
  function bkProfile(t) {
    var L = t.L, H = t.height;
    var sOn = t.startOn && t.startLen > 0 && t.startDepth > 0, eOn = t.endOn && t.endLen > 0 && t.endDepth > 0;
    var ss = Math.min(Math.max(t.startSlope, 0), sOn ? t.startLen : 0), es = Math.min(Math.max(t.endSlope, 0), eOn ? t.endLen : 0);
    var bottom = [];
    bottom.push([0, sOn ? -t.startDepth : 0]);
    if (sOn) { bottom.push([Math.max(t.startLen - ss, 0), -t.startDepth]); bottom.push([t.startLen, 0]); }
    if (eOn) { bottom.push([L - t.endLen, 0]); bottom.push([L - Math.max(t.endLen - es, 0), -t.endDepth]); }
    bottom.push([L, eOn ? -t.endDepth : 0]);
    var top = [[L, H]];
    if (t.endSeatOn && t.endSeatLen > 0 && t.endSeatDepth > 0) { var e0 = L - t.endSeatOffset, e1 = e0 - t.endSeatLen; top.push([e0, H], [e0, H - t.endSeatDepth], [e1, H - t.endSeatDepth], [e1, H]); }
    if (t.startSeatOn && t.startSeatLen > 0 && t.startSeatDepth > 0) { var s0 = t.startSeatOffset, s1 = s0 + t.startSeatLen; top.push([s1, H], [s1, H - t.startSeatDepth], [s0, H - t.startSeatDepth], [s0, H]); }
    top.push([0, H]);
    var pts = bottom.concat(top), out = [];
    pts.forEach(function (p) { if (!out.length || Math.abs(out[out.length - 1][0] - p[0]) > EPS || Math.abs(out[out.length - 1][1] - p[1]) > EPS) out.push(p); });
    if (out.length > 1 && Math.abs(out[0][0] - out[out.length - 1][0]) < EPS && Math.abs(out[0][1] - out[out.length - 1][1]) < EPS) out.pop();
    return out;
  }
  // Başlık kirişi — t: {width,height,bottom,startOverhang,endOverhang, start/end tooth & seat alanları, span (gösterim), pileD}
  build.beam = function (t) {
    var W = num(t.width, 0), H = num(t.height, 0), b0 = num(t.bottom, 0);
    var err = !(W > 0 && H > 0) ? 'BK genişliği ve yüksekliği sıfırdan büyük olmalı.' : null;
    if (err) return { kesit: { error: err }, boyuna: { error: err }, iso: { error: err } };
    var so = num(t.startOverhang, 0), eo = num(t.endOverhang, 0), span = num(t.span, 0);
    var L = (span > 0 ? span : 4) + so + eo;
    var q = { L: L, height: H, startOn: !!t.startOn, startLen: num(t.startLen, 0), startDepth: num(t.startDepth, 0), startSlope: num(t.startSlope, 0), endOn: !!t.endOn, endLen: num(t.endLen, 0), endDepth: num(t.endDepth, 0), endSlope: num(t.endSlope, 0),
      startSeatOn: !!t.startSeatOn, startSeatOffset: num(t.startSeatOffset, 0), startSeatLen: num(t.startSeatLen, 0), startSeatDepth: num(t.startSeatDepth, 0), endSeatOn: !!t.endSeatOn, endSeatOffset: num(t.endSeatOffset, 0), endSeatLen: num(t.endSeatLen, 0), endSeatDepth: num(t.endSeatDepth, 0) };
    var prof = bkProfile(q);
    var pd = num(t.pileD, 0) / 1000, fill = t.fill || '#b7bec4';
    var kes = { shapes: [{ pts: rect(-W / 2, 0, W / 2, H), fill: fill, stroke: '#4e5960' }], dims: [{ a: [-W / 2, 0], b: [W / 2, 0], horizontal: true, text: 'Genişlik ' + fmt(W, 3) + ' m', off: 14 }, { a: [W / 2, 0], b: [W / 2, H], text: 'H ' + fmt(H, 3) + ' m', off: 12 }], labels: [{ p: [-W / 2 - 0.08 * W, 0], text: 'alt kot ' + fmtEl(b0), anchor: 'end' }, { p: [-W / 2 - 0.08 * W, H], text: 'üst kot ' + fmtEl(b0 + H), anchor: 'end' }], notes: ['Enine kesit — kazık ekseninde'], padR: 90 };
    if (pd > 0 && pd <= W) { var emb = Math.min(0.15, H * 0.3); kes.shapes.push({ pts: rect(-pd / 2, -H * 0.5, pd / 2, emb), fill: '#6f8ea8', stroke: '#2f4a5f', opacity: '0.85' }); kes.labels.push({ p: [0, -H * 0.5 - 0.06 * H], text: 'kazık Ø' + fmt(pd * 1000, 0) }); }
    var boy = { shapes: [{ pts: prof, fill: fill, stroke: '#4e5960' }], dims: [{ a: [0, bbox2(prof)[1]], b: [L, bbox2(prof)[1]], horizontal: true, text: 'Boy ' + fmt(L, 2) + ' m' + (span > 0 ? '' : ' (gösterim)'), off: 14 }], labels: [], notes: ['Boyuna görünüş — diş (alt) ve kanal cebi (üst)'], padR: 60 };
    if (so > 0) boy.labels.push({ p: [so / 2, H + H * 0.12], text: 'taşma ' + fmt(so, 2) });
    if (eo > 0) boy.labels.push({ p: [L - eo / 2, H + H * 0.12], text: 'taşma ' + fmt(eo, 2) });
    if (q.startOn) boy.labels.push({ p: [q.startLen / 2, -q.startDepth - H * 0.1], text: 'diş ' + fmt(q.startDepth, 2) });
    if (q.endOn) boy.labels.push({ p: [L - q.endLen / 2, -q.endDepth - H * 0.1], text: 'diş ' + fmt(q.endDepth, 2) });
    if (q.startSeatOn) boy.labels.push({ p: [q.startSeatOffset + q.startSeatLen / 2, H - q.startSeatDepth / 2], text: 'cep ' + fmt(q.startSeatDepth, 2) });
    if (q.endSeatOn) boy.labels.push({ p: [L - q.endSeatOffset - q.endSeatLen / 2, H - q.endSeatDepth / 2], text: 'cep ' + fmt(q.endSeatDepth, 2) });
    var dl = dispLen(L, Math.max(W, H), 6), k = dl.L / L;
    var prof3 = dl.cut ? bkProfile(Object.assign({}, q, { L: dl.L, startLen: q.startLen * k, startSlope: q.startSlope * k, endLen: q.endLen * k, endSlope: q.endSlope * k, startSeatOffset: q.startSeatOffset * k, startSeatLen: q.startSeatLen * k, endSeatOffset: q.endSeatOffset * k, endSeatLen: q.endSeatLen * k })) : prof;
    var iso = { solids: [{ profile: prof3, frame: { e1: [1, 0, 0], e2: [0, 0, 1], d: [0, 1, 0] }, origin: [0, -W / 2, 0], L: W, fill: fill }], notes: ['3B önizleme — model değişmez' + (dl.cut ? ' · boy kısaltılarak çizildi' : ''), fmt(W, 2) + ' × ' + fmt(H, 2) + ' m, boy ' + fmt(L, 2) + ' m' + (q.startOn || q.endOn ? ' · diş' : '') + (q.startSeatOn || q.endSeatOn ? ' · kanal cebi' : '')] };
    if (pd > 0 && pd <= W) { var pl = Math.min(dl.L * 0.6, 1.5 * H); iso.solids.unshift({ profile: circle(pd / 2, 20), frame: frame([0, 0, -1]), origin: [so + (dl.L - so - eo * k) / 2, 0, -0.02], L: pl, fill: '#6f8ea8', edges: false }); }
    return { kesit: kes, boyuna: boy, iso: iso, info: 'Kesit alanı ' + fmt(W * H, 3) + ' m² · 1 m boy betonu ' + fmt(W * H, 3) + ' m³' };
  };

  // Prekast PD / PDÖ / PV — t: {family, width, height, extra, left, right, L (boy), seat}; PK → sec (mstChSection kesiti)
  build.precast = function (t) {
    var fam = t.family || 'PD', W = num(t.width, 0), H = num(t.height, 0), ex = num(t.extra, 0), lt = num(t.left, 0), rt = num(t.right, 0), L = num(t.L, 0);
    if (fam === 'PK') {
      var S = global.mstChSection, sec = t.sec;
      if (!S || !sec) return { kesit: { error: 'Kanal kesiti okunamadı.' }, iso: { error: 'Kanal kesiti okunamadı.' } };
      var e = S.valid(sec); if (e.length) return { kesit: { error: 'Kesit geçersiz: ' + e[0] }, iso: { error: 'Kesit geçersiz' } };
      var pr = S.profile(sec), tw = S.num(sec.total_width_m), hh = S.height(sec);
      var LL = L > 0 ? L : 2, dk = dispLen(LL, Math.max(tw, hh), 6);
      return { kesit: { shapes: [{ pts: pr, fill: '#aeb5ba', stroke: '#4e5960' }], dims: [{ a: [0, 0], b: [tw, 0], horizontal: true, text: 'Toplam genişlik ' + fmt(tw, 3) + ' m', off: 14 }, { a: [tw, 0], b: [tw, hh], text: fmt(hh, 3) + ' m', off: 12 }], notes: ['Kanal prekastı — kesit alanı ' + fmt(S.area(sec), 3) + ' m²'] },
        iso: { solids: [{ profile: pr, frame: frame([1, 0, 0]), origin: [0, 0, 0], L: dk.L, fill: '#aeb5ba' }], notes: ['3B önizleme — model değişmez' + (dk.cut ? ' · boy kısaltılarak çizildi' : ''), 'Boy ' + fmt(LL, 2) + ' m' + (L > 0 ? '' : ' (gösterim)')] }, info: 'Kesit alanı ' + fmt(S.area(sec), 3) + ' m²' };
    }
    var err = !(W > 0 && H > 0) ? 'Genişlik ve kalınlık sıfırdan büyük olmalı.' : null;
    if (err) return { kesit: { error: err }, boyuna: { error: err }, iso: { error: err } };
    var deep = (fam === 'PDO' || fam === 'PV') && ex > 0, LL2 = L > 0 ? L : 3;
    lt = Math.min(Math.max(lt, 0), LL2 / 2); rt = Math.min(Math.max(rt, 0), LL2 / 2);
    var fill = fam === 'PV' ? '#c9b8a3' : (fam === 'PDO' ? '#b9c7b0' : '#c7cdd1');
    var Ht = H + (deep ? ex : 0);
    var kes = { shapes: [{ pts: rect(-W / 2, 0, W / 2, Ht), fill: fill, stroke: '#4e5960' }], dims: [{ a: [-W / 2, 0], b: [W / 2, 0], horizontal: true, text: 'Genişlik ' + fmt(W, 3) + ' m', off: 14 }, { a: [W / 2, 0], b: [W / 2, Ht], text: (deep ? 'H+diş ' : 'H ') + fmt(Ht, 3) + ' m', off: 12 }], notes: [(fam === 'PV' ? 'Vinç prekastı' : fam === 'PDO' ? 'Dişli / değişken prekast' : 'Normal prekast') + ' — enine kesit' + (deep ? ' (derin orta bölge)' : '')] };
    if (deep) kes.shapes.push({ pts: [[-W / 2, ex], [W / 2, ex]], open: true, stroke: '#4e5960', dash: '3,2', sw: '0.7' });
    // boyuna: üst düz; alt: uçlarda H (diş / oturma), ortada H+ex
    var prof = deep ? [[0, ex], [lt, ex], [lt, 0], [LL2 - rt, 0], [LL2 - rt, ex], [LL2, ex], [LL2, Ht], [0, Ht]] : rect(0, 0, LL2, H);
    var boy = { shapes: [{ pts: prof, fill: fill, stroke: '#4e5960' }], dims: [{ a: [0, 0], b: [LL2, 0], horizontal: true, text: 'Boy ' + fmt(LL2, 2) + ' m' + (L > 0 ? '' : ' (gösterim)'), off: 14 }, { a: [LL2, 0], b: [LL2, Ht], text: fmt(Ht, 3) + ' m', off: 12 }], labels: [], notes: ['Boyuna kesit' + (deep ? ' — uç dişleri BK üstüne oturur, orta bölge derindir' : '')] };
    if (deep) { if (lt > 0) boy.labels.push({ p: [lt / 2, Ht + 0.12 * Ht], text: 'diş ' + fmt(lt, 2) }); if (rt > 0) boy.labels.push({ p: [LL2 - rt / 2, Ht + 0.12 * Ht], text: 'diş ' + fmt(rt, 2) }); }
    var dl = dispLen(LL2, Math.max(W, Ht), 6), k = dl.L / LL2;
    var prof3 = deep ? [[0, ex], [lt * k, ex], [lt * k, 0], [dl.L - rt * k, 0], [dl.L - rt * k, ex], [dl.L, ex], [dl.L, Ht], [0, Ht]] : rect(0, 0, dl.L, H);
    var iso = { solids: [{ profile: prof3, frame: { e1: [1, 0, 0], e2: [0, 0, 1], d: [0, 1, 0] }, origin: [0, -W / 2, 0], L: W, fill: fill }], notes: ['3B önizleme — model değişmez' + (dl.cut ? ' · boy kısaltılarak çizildi' : ''), fmt(W, 2) + ' × ' + fmt(H, 2) + (deep ? ' (+' + fmt(ex, 2) + ' diş)' : '') + ' m · boy ' + fmt(LL2, 2) + ' m'] };
    var vol = deep ? W * (H * LL2 + ex * Math.max(LL2 - lt - rt, 0)) : W * H * LL2;
    return { kesit: kes, boyuna: boy, iso: iso, info: 'Beton ' + fmt(vol, 3) + ' m³ (' + (L > 0 ? 'formdaki boy' : 'gösterim boyu') + ')' };
  };

  // Döşeme — f: {thickness, seat, pdH, bkW, bkH, span, curb:{on1,on2,w,h}, topping:{on,t}}
  build.deck = function (f) {
    var T = num(f.thickness, 0), seat = num(f.seat, 0.15), pdH = num(f.pdH, 0.3), bkW = num(f.bkW, 1.5), bkH = num(f.bkH, 1.8), span = num(f.span, 0);
    var err = !(T > 0) ? 'Döşeme kalınlığı sıfırdan büyük olmalı.' : null;
    if (err) return { kesit: { error: err }, iso: { error: err } };
    var S = span > 0 ? span : 5, cw = num(f.curb.w, 0), ch = num(f.curb.h, 0), tt = f.topping.on ? num(f.topping.t, 0) : 0;
    var x1 = 0, x2 = S;                      // BK eksenleri
    var left = x1 - bkW / 2, right = x2 + bkW / 2;
    var shapes = [], labels = [], dims = [];
    shapes.push({ pts: rect(x1 - bkW / 2, -bkH, x1 + bkW / 2, 0), fill: '#b7bec4', stroke: '#4e5960' });
    shapes.push({ pts: rect(x2 - bkW / 2, -bkH, x2 + bkW / 2, 0), fill: '#b7bec4', stroke: '#4e5960' });
    labels.push({ p: [x1, -bkH / 2], text: 'BK' }, { p: [x2, -bkH / 2], text: 'BK' });
    var pd0 = x1 + bkW / 2 - seat, pd1 = x2 - bkW / 2 + seat;
    if (pd1 > pd0) { shapes.push({ pts: rect(pd0, 0, pd1, pdH), fill: '#c7cdd1', stroke: '#4e5960' }); labels.push({ p: [(pd0 + pd1) / 2, pdH / 2], text: 'prekast ' + fmt(pdH, 2) }); }
    var slabBot = Math.min(pdH, T);
    // BK aralığında prekast üstüne kadar dökülmez; BK üstünde tam kalınlık
    shapes.push({ pts: [[left, 0], [right, 0], [right, T], [left, T]], fill: '#8fa3b1', stroke: '#4e5960', opacity: '0.35' });
    if (T > pdH && pd1 > pd0) shapes.push({ pts: rect(pd0, pdH, pd1, T), fill: '#8fa3b1', stroke: '#4e5960' });
    shapes.push({ pts: rect(left, 0, pd0, T), fill: '#8fa3b1', stroke: '#4e5960' });
    shapes.push({ pts: rect(pd1, 0, right, T), fill: '#8fa3b1', stroke: '#4e5960' });
    labels.push({ p: [(left + right) / 2, T + (tt > 0 ? tt : 0) + 0.12 * T + ch], text: 'döşeme ' + fmt(T, 2) + ' m' + (tt > 0 ? ' + kaplama ' + fmt(tt, 2) : ''), strong: true });
    if (tt > 0) shapes.push({ pts: rect(left + (f.curb.on1 ? cw : 0), T, right - (f.curb.on2 ? cw : 0), T + tt), fill: '#d9d9d9', stroke: '#8a8a8a' });
    if (f.curb.on1 && cw > 0 && ch > 0) shapes.push({ pts: rect(left, T, left + cw, T + ch), fill: '#a9b5bd', stroke: '#4e5960' });
    if (f.curb.on2 && cw > 0 && ch > 0) shapes.push({ pts: rect(right - cw, T, right, T + ch), fill: '#a9b5bd', stroke: '#4e5960' });
    dims.push({ a: [x1, -bkH], b: [x2, -bkH], horizontal: true, text: 'BK aralığı ' + fmt(S, 2) + ' m' + (span > 0 ? '' : ' (gösterim)'), off: 14 });
    dims.push({ a: [right, 0], b: [right, T], text: 'T ' + fmt(T, 2), off: 12 });
    var kes = { shapes: shapes, labels: labels, dims: dims, notes: ['Enine kesit — BK üstünden toplam kalınlık; prekast üstüne kadar olan katman dökülmez (DS1)'], padR: 70 };
    var dl = dispLen(S + bkW, Math.max(T + ch + tt, 0.3), 8);
    var Ld = dl.L, kk = Ld / (S + bkW);
    var solids = [];
    solids.push({ profile: rect(0, -bkH, bkW, 0), frame: frame([1, 0, 0]), origin: [0, 0, 0], L: Ld, fill: '#b7bec4' });
    solids.push({ profile: rect((right - left) - bkW, -bkH, right - left, 0), frame: frame([1, 0, 0]), origin: [0, 0, 0], L: Ld, fill: '#b7bec4' });
    solids.push({ profile: rect(0, 0, right - left, T), frame: frame([1, 0, 0]), origin: [0, 0, 0], L: Ld, fill: '#8fa3b1' });
    if (tt > 0) solids.push({ profile: rect(f.curb.on1 ? cw : 0, T, (right - left) - (f.curb.on2 ? cw : 0), T + tt), frame: frame([1, 0, 0]), origin: [0, 0, 0], L: Ld, fill: '#d9d9d9', edges: false });
    if (f.curb.on1 && cw > 0 && ch > 0) solids.push({ profile: rect(0, T, cw, T + ch), frame: frame([1, 0, 0]), origin: [0, 0, 0], L: Ld, fill: '#a9b5bd' });
    if (f.curb.on2 && cw > 0 && ch > 0) solids.push({ profile: rect((right - left) - cw, T, right - left, T + ch), frame: frame([1, 0, 0]), origin: [0, 0, 0], L: Ld, fill: '#a9b5bd' });
    if (f.curb.on3 && cw > 0 && ch > 0) solids.push({ profile: rect(0, T, right - left, T + ch), frame: frame([1, 0, 0]), origin: [0, 0, 0], L: cw, fill: '#a9b5bd' });
    if (f.curb.on4 && cw > 0 && ch > 0) solids.push({ profile: rect(0, T, right - left, T + ch), frame: frame([1, 0, 0]), origin: [Ld - cw, 0, 0], L: cw, fill: '#a9b5bd' });
    var iso = { solids: solids, notes: ['3B önizleme — model değişmez · BK boyu gösterim ' + fmt(Ld, 1) + ' m', 'Döşeme ' + fmt(T, 2) + ' m' + (tt > 0 ? ' + kaplama ' + fmt(tt, 2) : '') + (f.curb.on1 || f.curb.on2 || f.curb.on3 || f.curb.on4 ? ' · tretuvar ' + fmt(cw, 2) + ' × ' + fmt(ch, 2) : '')] };
    return { kesit: kes, iso: iso, info: 'Alt kot BK üstü · üst kot BK üstü + ' + fmt(T + tt, 2) + ' m' };
  };

  // Kronman — a,b: kesit nokta dizileri (crownPts), intervals [{s,e,t:'A'|'B'}], fill
  build.crown = function (f) {
    var A = f.a, B = f.b, iv = f.intervals || [];
    var valid=function(p){return p && p.length>=3 && p.every(function(q){return q.every(Number.isFinite);}) && Math.abs(area2(p))>EPS;};
    if (!iv.length || iv.some(function(r){return !isFinite(r.s)||!isFinite(r.e)||r.e<=r.s||!valid(r.t==='B'?B:A);})) {
      return {error:'Kronman kesitini ve istasyon aralıklarını kontrol edin.'};
    }
    var bb = bbox2(A.concat(B && B.length >= 3 ? B : [])), D = Math.max(bb[2] - bb[0], bb[3] - bb[1]);
    var total = iv[iv.length - 1].e - iv[0].s, dl = dispLen(total, D, 8), k = dl.L / total;
    var solids = iv.map(function (r) { var pr = (r.t === 'B' && B && B.length >= 3) ? B : A; return { profile: pr, frame: frame([1, 0, 0]), origin: [(r.s - iv[0].s) * k, 0, 0], L: (r.e - r.s) * k, fill: r.t === 'B' ? '#c9b8a3' : '#c7cdd1' }; });
    var first=iv[0].t==='B'?B:A, bounds=bbox2(first);
    var section={shapes:[{pts:first,fill:'#c7cdd1',stroke:'#3f4a52'}],
      dims:[{a:[bounds[0],bounds[1]],b:[bounds[2],bounds[1]],horizontal:true,text:fmt(bounds[2]-bounds[0],2)+' m',off:12},
            {a:[bounds[2],bounds[1]],b:[bounds[2],bounds[3]],text:fmt(bounds[3]-bounds[1],2)+' m',off:9}],
      padR:55,notes:['İlk istasyon · Tip '+iv[0].t,'Üst '+fmtEl(bounds[3])+' m · Alt '+fmtEl(bounds[1])+' m']};
    return { kesit:section, iso: { solids: solids, notes: ['3B önizleme — istasyon aralıklarından (' + iv.length + ' aralık, ' + fmt(total, 1) + ' m)' + (dl.cut ? ' · boy kısaltılarak çizildi' : ''), 'açık ton Tip A · koyu ton Tip B · model değişmez'] } };
  };

  // Dolgu (parametrik şevli taş kesiti) — f: {crest, width, slopeL, slopeR, layers:[{code,t}], base}
  build.rockfill = function (f) {
    var zc = num(f.crest, NaN), W = num(f.width, 0), hL = Math.max(num(f.slopeL, 0), 0), hR = Math.max(num(f.slopeR, 0), 0);
    var err = !(isFinite(zc) && W > 0) ? 'Kret kotu ve genişliği girin.' : null;
    if (err) return { kesit: { error: err }, iso: { error: err } };
    var layers = (f.layers || []).map(function (l) { return { code: l.code || '', t: Math.max(num(l.t, 0), 0) }; });
    var tsum = layers.slice(0, -1).reduce(function (s, l) { return s + l.t; }, 0);
    var zb = isFinite(num(f.base, NaN)) ? num(f.base, NaN) : zc - Math.max(8, 2 * tsum + 3);
    var Hh = zc - zb;
    if (!(Hh > 0)) return { kesit: { error: 'Taban kotu kret kotunun altında olmalı.' }, iso: { error: 'Taban kotu kret kotunun altında olmalı.' } };
    // dış kontur (y: sol negatif ofset şevi hL, sağ pozitif ofset şevi hR); y=0 kret ortası
    // off: kümülatif kalınlık (şeve dik). Kret düşey olarak off kadar alçalır; şev çizgisi dik olarak off içeri alınır
    // (aynı kotta yatay kayma off·√(1+h²)). Dış şev: y = ∓W/2 ∓ h·(zc − z).
    var poly = function (off) {
      var z1 = zc - off; if (z1 <= zb + EPS) return null;
      var dL = off * Math.sqrt(1 + hL * hL), dR = off * Math.sqrt(1 + hR * hR);
      var yL1 = -W / 2 - hL * off + dL, yR1 = W / 2 + hR * off - dR;
      var yLb = -W / 2 - hL * (zc - zb) + dL, yRb = W / 2 + hR * (zc - zb) - dR;
      if (yR1 - yL1 < EPS || yRb - yLb < EPS) return null;
      return [[yLb, zb], [yRb, zb], [yR1, z1], [yL1, z1]];
    };
    var outer = poly(0), shapes = [], cols = ['#9d8f7c', '#b3a690', '#c6bba7', '#d7cfbf', '#e4ddd0', '#eee9df'];
    shapes.push({ pts: outer, fill: cols[Math.min(layers.length, cols.length - 1)], stroke: '#5a5243' });
    var off = 0, labels = [], inner = outer;
    layers.forEach(function (l, i) {
      if (i === layers.length - 1) { labels.push({ p: [0, (zb + (zc - off)) / 2], text: (l.code || 'çekirdek') + ' (çekirdek)', strong: true }); return; }
      labels.push({ p: [-W / 2 - hL * (zc - zb) * 0.55 + off * 0.5, (zc - off) - Math.min(0.55 * Hh, Hh * (0.25 + 0.15 * i))], text: (l.code || 'tabaka') + ' ' + fmt(l.t, 2) + ' m', anchor: 'end' });
      off += l.t; var p = poly(off); if (!p) return;
      shapes.push({ pts: p, fill: cols[Math.max(0, Math.min(layers.length - 1 - i, cols.length - 1))], stroke: '#5a5243' });
      inner = p;
    });
    var dims = [{ a: [-W / 2, zc], b: [W / 2, zc], horizontal: true, text: 'Kret ' + fmt(W, 2) + ' m · kot ' + fmtEl(zc), off: -8 }, { a: [outer[1][0], zb], b: [outer[1][0], zc], text: fmt(Hh, 2) + ' m', off: 12 }];
    var kes = { shapes: shapes, labels: labels, dims: dims, notes: ['Tip kesit (şematik) — sol 1V:' + fmt(hL, 2) + 'H, sağ 1V:' + fmt(hR, 2) + 'H, taban ' + fmtEl(zb) + (isFinite(num(f.base, NaN)) ? '' : ' (gösterim)')], padR: 70 };
    var Ld = Math.max(outer[1][0] - outer[0][0], 1) * 0.8;
    var solids = shapes.map(function (s, i) { return { profile: s.pts, frame: frame([1, 0, 0]), origin: [0, 0, 0], L: Ld, fill: s.fill }; }).reverse();
    var iso = { solids: solids, notes: ['3B önizleme — tip kesit ' + fmt(Ld, 1) + ' m gösterim boyunca · model değişmez', 'Tabakalar dıştan içe; gerçek hacim AEA ile hesaplanır'] };
    return { kesit: kes, iso: iso, info: 'Dış kesit alanı ' + fmt(Math.abs(area2(outer)), 2) + ' m² (taban ' + fmtEl(zb) + ')' };
  };

  /* ---------------------------------------------------------------- ui katmanı */
  var modelPreview = Object.create(null), modelRequestId = 0;
  var modelLabels = {
    pile:'Eksen boyu', beam:'Kiriş boyu', deck:'Plan boyu', crown:'İstasyon boyu',
    bored:'Beton boyu', jet:'İyileştirme boyu'
  };
  function modelControls(kind) {
    if (!modelLabels[kind]) return '';
    return '<div class="mstpv-model" data-model-kind="'+kind+'"><select data-model-instance aria-label="Modeldeki eleman" hidden></select>' +
      '<label>'+modelLabels[kind]+' (m) <input data-model-length readonly aria-label="'+modelLabels[kind]+' (m)"></label>' +
      '<button type="button" data-model-reload>Modelden yenile</button>' +
      '<button type="button" data-model-toggle hidden>Taslağı göster</button></div>';
  }
  function modelFilter(kind) {
    if (kind === 'bored' || kind === 'jet') return V('type_id','').trim();
    if (kind !== 'beam') return '';
    var state = beamState(), types = state.types || [];
    var type = types[Number(V('mstpvBeamType',state.index || 0))] || types[0];
    return type ? type.name : '';
  }
  function requestModel(kind, state, pid) {
    state.pending = true;
    state.error = '';
    state.id = ++modelRequestId;
    var callback = 'mst_preview_model_records' + (kind === 'bored' || kind === 'jet' ? '_'+kind : '');
    if (global.sketchup && global.sketchup[callback]) {
      global.sketchup[callback](JSON.stringify({id:state.id,kind:kind,type:state.filter,pid:pid}));
    } else {
      state.pending = false;
      state.error = 'Model kayıtları okunamadı.';
    }
  }
  global.mstpvModelRecords = function (id, payload) {
    Object.keys(modelPreview).some(function (kind) {
      var state = modelPreview[kind];
      if (id !== state.id) return false;
      state.pending = false;
      state.error = payload.error || '';
      if (payload.rows) {
        state.rows = payload.rows;
        var row = state.rows.find(function (r) { return r.pid === state.pid; }) ||
          state.rows.find(function (r) { return r.selected; }) || state.rows[0];
        state.pid = row ? row.pid : null;
        if (row && !state.draft) requestModel(kind,state,row.pid);
      } else if (!payload.error) state.record = payload;
      ui.update(kind);
      return true;
    });
  };
  function bindModelControls(card,kind) {
    var controls = card.querySelector('.mstpv-model');
    if (!controls) return;
    var state = modelPreview[kind] = {rows:[],filter:null,pid:null,record:null,draft:false};
    controls.querySelector('[data-model-instance]').addEventListener('change', function (event) {
      state.pid = event.target.value;
      state.record = null;
      state.draft = false;
      requestModel(kind,state,state.pid);
      ui.update(kind);
    });
    controls.querySelector('[data-model-reload]').addEventListener('click', function () {
      state.filter = null;
      state.draft = false;
      ui.update(kind);
    });
    controls.querySelector('[data-model-toggle]').addEventListener('click', function () {
      state.draft = !state.draft;
      if (!state.draft && state.pid) requestModel(kind,state,state.pid);
      ui.update(kind);
    });
  }
  function modelPreviewView(cfg,card) {
    var state = modelPreview[cfg.id];
    if (!state) return cfg.read();
    if (cfg.id === 'beam') syncBeamSelector();
    var filter = modelFilter(cfg.id) || '';
    if (cfg.full && !card.getClientRects().length) return {error:'Önizleme sekmesini açın.'};
    if (filter !== state.filter) {
      if (state.filter !== null) {state.pid=null;state.draft=false;}
      state.filter = filter;
      state.rows = [];state.record = null;
      requestModel(cfg.id,state);
    }
    var select = card.querySelector('[data-model-instance]');
    select.textContent = '';
    state.rows.forEach(function (row) {
      var option = document.createElement('option');
      option.value = row.pid;
      option.textContent = [row.structure,row.code,row.axis,'#'+row.pid].filter(Boolean).join(' · ');
      select.appendChild(option);
    });
    select.value = state.pid || '';
    select.hidden = !state.rows.length || state.draft;
    var toggle = card.querySelector('[data-model-toggle]');
    toggle.hidden = !state.rows.length;
    toggle.textContent = state.draft ? 'Modeli göster' : 'Taslağı göster';
    var input = card.querySelector('[data-model-length]');
    var record = state.record;
    input.value = !state.draft && !state.pending && !state.error && record && record.length != null ? fmt(record.length,3) : '';
    input.placeholder = state.draft || (!state.rows.length && !state.pending && !state.error) ? 'Formdan hesaplanır' :
      state.pending ? 'Okunuyor…' : 'Boy kaydı yok';
    if (!state.draft && (state.pending || state.error)) return {error:state.error || 'Model kayıtları okunuyor…'};
    if (state.draft || !state.rows.length) {
      var draft = cfg.read();
      if (draft.info && draft.info.indexOf('Taslak')!==0) draft.info = 'Taslak · '+draft.info;
      return draft;
    }
    if (!record) return {error:'Eleman kaydı okunamadı.'};
    var data = record.data || {}, view;
    if (cfg.id === 'pile') view = build.pile(data);
    else if (cfg.id === 'bored' || cfg.id === 'jet') view = data.enabled ? build.column(data) : {error:'Bu kolonun imalat durumu Yok.'};
    else view = record.geometry ? build.selected(record.geometry) : {error:'Kayıtlı beton yüzleri okunamadı.'};
    view.info = ['Model kaydı',cfg.id === 'pile' ? view.soilInfo : view.info].concat(record.facts.map(function (fact) {
      return fact[0]+' '+(fact[1] == null ? '—' : fmt(fact[1],3)+' '+fact[2]);
    })).filter(Boolean).join(' · ');
    return view;
  }

  var ui = { pages: {}, timers: {} };
  var CSS = '.mstpv-card{margin:8px 0}.mstpv-btns{display:flex;flex-wrap:wrap;gap:4px;padding:2px 0 6px}.mstpv-btns button{padding:5px 10px;border:1px solid #9cc3de;border-radius:5px;background:#fff;color:#0b5f98;font-size:12px;cursor:pointer}.mstpv-btns button[aria-pressed="true"]{background:#0b5f98;color:#fff;border-color:#0b5f98}.mstpv-svg{display:block;width:100%;height:190px;background:#f9fbfc;border:1px solid #e0e9ee;border-radius:4px}.mstpv-dim{font-size:9px;fill:#173650}.mstpv-strong{font-weight:700}.mstpv-msg{font-size:9px;fill:#a1001c}.mstpv-info{font-size:11px;color:#355a73;margin:5px 2px 0;min-height:14px}.mstpv-sel{width:100%;margin:0 0 6px;padding:5px;border:1px solid #bdcbd7;border-radius:4px;font:inherit}';
  CSS += '.mstpv-full{box-sizing:border-box;background:#fff;border:1px solid #d5e2eb;border-radius:8px;padding:12px;width:100%;min-width:0}.mstpv-full .mstpv-svg{height:64vh;min-height:380px;max-height:820px;box-sizing:border-box}.mstpv-full .mstpv-sel{width:auto;max-width:100%}.mstpv-full-actions{display:flex;flex-wrap:wrap;gap:8px;align-items:center;margin-bottom:8px}.mstpv-local-tabs{display:flex;gap:6px;margin:0 0 12px}.mstpv-local-tabs [aria-selected="true"]{background:#0b5f98;color:#fff}.mstpv-local-content[hidden],.mstpv-local-preview[hidden]{display:none!important}';
  CSS += '.mstpv-model{display:flex;flex-wrap:wrap;align-items:end;gap:6px;margin:4px 0}.mstpv-model select{max-width:100%}.mstpv-model input{width:9em}.mstpv-model label{display:flex;flex-direction:column}.mstpv-model [hidden]{display:none!important}';
  function injectCss() { if (document.getElementById('mstpvStyle')) return; var s = document.createElement('style'); s.id = 'mstpvStyle'; s.textContent = CSS; document.head.appendChild(s); }
  var VIEW_LABELS = { kesit: 'Kesit', boyuna: 'Boyuna', plan: 'Plan', iso: '3B' };

  // Kart oluştur: {id, host (eleman), title, views:['kesit','boyuna','iso'], selector:fn|null, read:fn → build sonucu}
  ui.mount = function (cfg) {
    injectCss();
    if (!cfg.host || document.getElementById('mstpv_' + cfg.id)) return null;
    var card = document.createElement('div'); card.className = 'mstpv-card'; card.id = 'mstpv_' + cfg.id;
    var html = (cfg.title ? '<h3 style="margin:0 0 6px">' + cfg.title + '</h3>' : '') + (cfg.selectorHtml || '') + modelControls(cfg.id) + '<div class="mstpv-btns" role="group" aria-label="Önizleme görünümü">' +
      cfg.views.map(function (v, i) { return '<button type="button" data-view="' + v + '" aria-pressed="' + (i === 0 ? 'true' : 'false') + '">' + VIEW_LABELS[v] + '</button>'; }).join('') +
      '<button type="button" data-zoom="in" aria-label="Yakınlaştır">+</button><button type="button" data-zoom="out" aria-label="Uzaklaştır">−</button><button type="button" data-zoom="reset">Sıfırla</button></div>' +
      cfg.views.map(function (v, i) { return '<svg class="mstpv-svg" data-view="' + v + '" viewBox="0 0 ' + VIEW_W + ' ' + VIEW_H + '" preserveAspectRatio="xMidYMid meet" role="img" aria-label="' + (cfg.title || cfg.id) + ' ' + VIEW_LABELS[v] + ' önizlemesi"' + (i === 0 ? '' : ' style="display:none"') + '></svg>'; }).join('') +
      '<div class="mstpv-info" id="mstpvInfo_' + cfg.id + '"></div>';
    card.innerHTML = html;
    if (cfg.before && cfg.before.parentNode === cfg.host) cfg.host.insertBefore(card, cfg.before); else cfg.host.appendChild(card);
    if(cfg.full || cfg.id==='precast'){
      var orbit=card.querySelector('svg[data-view="iso"]'), drag=null;
      if (orbit) {
      orbit.style.cursor='grab';
      orbit.style.touchAction='none';
      orbit.setAttribute('tabindex','0');
      orbit.setAttribute('aria-label','3B önizleme. Sürükleyerek veya ok tuşlarıyla döndürün.');
      function turn(delta){
        orbit._mstYaw=((orbit._mstYaw||0)+delta)%(2*Math.PI);
        if(orbit._mstView)drawIso(orbit,orbit._mstView);
      }
      orbit.addEventListener('pointerdown',function(e){
        if(e.button!==0)return;
        drag=e.clientX;orbit.setPointerCapture(e.pointerId);orbit.style.cursor='grabbing';
      });
      orbit.addEventListener('pointermove',function(e){
        if(drag===null)return;
        var delta=e.clientX-drag;drag=e.clientX;turn(delta*0.012);
      });
      ['pointerup','pointercancel','lostpointercapture'].forEach(function(event){
        orbit.addEventListener(event,function(){drag=null;orbit.style.cursor='grab';});
      });
      orbit.addEventListener('keydown',function(e){
        if(e.key!=='ArrowLeft'&&e.key!=='ArrowRight')return;
        e.preventDefault();turn(e.key==='ArrowLeft'?-0.18:0.18);
      });
    }
      }
    card.querySelectorAll('[data-zoom]').forEach(function (button) {
      button.addEventListener('click', function () {
        var mode=button.getAttribute('data-zoom');
        card.querySelectorAll('svg.mstpv-svg').forEach(function (svg) {
          if(mode==='reset' && svg._mstView){svg._mstYaw=0;drawIso(svg,svg._mstView);}
          var factor=Number(svg.getAttribute('data-mst-scale') || 1);
          factor=mode==='reset'?1:Math.max(0.75,Math.min(4,factor*(mode==='in'?1.25:0.8)));
          svg.setAttribute('data-mst-scale',factor);
          applyViewBox(svg);
        });
      });
    });
    card.querySelectorAll('.mstpv-btns button[data-view]').forEach(function (b) {
      b.addEventListener('click', function () {
        card.querySelectorAll('.mstpv-btns button[data-view]').forEach(function (x) { x.setAttribute('aria-pressed', x === b ? 'true' : 'false'); });
        card.querySelectorAll('svg.mstpv-svg').forEach(function (s) { s.style.display = s.getAttribute('data-view') === b.getAttribute('data-view') ? '' : 'none'; });
        if (cfg.full || cfg.id === 'precast') ui.update(cfg.id);
      });
    });
    ui.pages[cfg.id] = cfg;
    bindModelControls(card,cfg.id);
    if (cfg.full || cfg.id === 'precast') {
      var resize = function () { ui.schedule(cfg.id, 40); };
      if (typeof global.ResizeObserver === 'function') {
        cfg.resizeObserver = new global.ResizeObserver(resize);
        card.querySelectorAll('svg.mstpv-svg').forEach(function (svg) { cfg.resizeObserver.observe(svg); });
      } else {
        global.addEventListener('resize', resize);
        if (typeof global.MutationObserver === 'function') {
          cfg.visibilityObserver = new global.MutationObserver(resize);
          cfg.visibilityObserver.observe(cfg.host.parentNode, {attributes:true});
        }
      }
    }
    ui.update(cfg.id);
    return card;
  };
  ui.update = function (id) {
    var cfg = ui.pages[id]; if (!cfg) return;
    var card = document.getElementById('mstpv_' + id); if (!card) return;
    var res;
    try { res = modelPreviewView(cfg,card); } catch (e) { res = { error: 'Önizleme okunamadı: ' + (e && e.message ? e.message : e) }; }
    card.querySelectorAll('svg.mstpv-svg').forEach(function (svg) {
      if ((cfg.full || id === 'precast') && svg.clientWidth && svg.clientHeight) {
        // Keep drawing labels readable while fitting the geometry to the available panel.
        svg._mstSize = [Math.max(200, svg.clientWidth * 0.75), Math.max(150, svg.clientHeight * 0.75)];
        applyViewBox(svg);
      }
      var v = svg.getAttribute('data-view'), view = res && res[v] ? res[v] : { error: (res && res.error) || 'Bu görünüm için veri yok.' };
      if (v === 'iso') {svg._mstView=view;drawIso(svg,view);} else drawPlane(svg, view);
    });
    var info = document.getElementById('mstpvInfo_' + id); if (info) info.textContent = (res && res.info) || '';
  };
  ui.schedule = function (id, ms) { if (ui.timers[id]) clearTimeout(ui.timers[id]); ui.timers[id] = setTimeout(function () { ui.timers[id] = null; ui.update(id); }, ms == null ? 120 : ms); };
  ui.updateAll = function () { Object.keys(ui.pages).forEach(function (k) { ui.update(k); }); };
  function $(id) { return document.getElementById(id); }
  function V(id, d) { var e = $(id); return e ? e.value : d; }
  function Vn(id, d) { return num(V(id, d), d); }

  /* ---- sayfa okuyucuları (ui.html) ---- */
  function readPile() {
    return build.pile({ d_mm: V('diameter_mm', 1016), t_mm: V('thickness_mm', 14), L: V('length_m', 36), top: V('top_elevation_m', 0), mode: V('orientation_mode', 'VERTICAL'), batter: V('batter_ratio', 0), az: V('azimuth_deg', 0),
      infill: V('infill_enabled_select', '0') === '1', infill_bottom: V('infill_bottom_normal_m', ''), seabed: V('seabed_elevation_m', '') });
  }
  // bkTypes / selectedBKIndex ui.html'de `let` ile tanımlı (window özelliği değil): ui.html sonundaki mstpvBeamState köprüsü okur
  function beamState() { try { if (typeof global.mstpvBeamState === 'function') return global.mstpvBeamState() || {}; } catch (e) { } return { types: global.bkTypes || [], index: global.selectedBKIndex || 0 }; }
  var selectedGeometry={};
  global.mstpvSelectedGeometry=function(kind,payload){selectedGeometry[kind]=payload;ui.update(kind);};
  global.mstpvRequestGeometry=function(kind){
    if(global.sketchup && global.sketchup.mst_preview_selection)global.sketchup.mst_preview_selection(kind);
  };
  build.selected=function(payload){
    if(payload.error)return {error:payload.error};
    var all=payload.objects.reduce(function(out,o){return out.concat(o.faces);},[]);
    var primary=payload.objects[0];
    var xs=primary.faces.reduce(function(out,f){return out.concat(f.pts.map(function(p){return p[0];}));},[]);
    var station=(Math.min.apply(null,xs)+Math.max.apply(null,xs))/2;
    var section=[];
    all.forEach(function(f){
      var hits=[];
      [f.pts].concat(f.holes).forEach(function(loop){
        loop.forEach(function(a,i){
          var b=loop[(i+1)%loop.length];
          if((a[0]<=station)===(b[0]<=station))return;
          var t=(station-a[0])/(b[0]-a[0]);
          hits.push([a[1]+(b[1]-a[1])*t,a[2]+(b[2]-a[2])*t]);
        });
      });
      hits.sort(function(a,b){return a[0]-b[0] || a[1]-b[1];});
      for(var i=0;i+1<hits.length;i+=2)section.push({pts:[hits[i],hits[i+1]],open:true,stroke:'#264c63'});
    });
    var outline=function(f){return {pts:f.pts.map(function(p){return [p[0],p[1]];}),holes:f.holes.map(function(l){return l.map(function(p){return [p[0],p[1]];});}),fill:f.fill};};
    var info=[primary.id,payload.axis,payload.lengths && payload.lengths.length>1?'Boylar '+payload.lengths.map(function(l){return fmt(l,3)+' m';}).join(' / '):payload.length!=null?'Boy '+fmt(payload.length,3)+' m':'',payload.seat!=null?'Oturma '+fmt(payload.seat,2)+' m':'',payload.clear_span!=null?'Net açıklık '+fmt(payload.clear_span,2)+' m':'',payload.joint!=null?'Derz '+fmt(payload.joint,2)+' m':'',
      payload.volume!=null?'Beton '+(payload.concrete||'')+' '+fmt(payload.volume,3)+' m³':'',payload.formwork!=null?'Kalıp '+fmt(payload.formwork,3)+' m²':'',payload.objects.length>1?'Bağlı: '+payload.objects.slice(payload.primary_count||1).map(function(o){return o.id;}).join(', '):''].filter(Boolean).join(' · ');
    return {kesit:{shapes:section,notes:['Model kesiti · X '+fmt(station,2)+' m']},
      boyuna:{shapes:all.filter(function(f){return f.n[1]<-EPS;}).map(function(f){return {pts:f.pts.map(function(p){return [p[0],p[2]];}),fill:f.fill};})},
      plan:{shapes:all.filter(function(f){return f.n[2]>EPS;}).map(outline)},iso:{faces:all},info:info};
  };
  function readBeam() {
    if(selectedGeometry.beam)return build.selected(selectedGeometry.beam);
    var st = beamState(), types = st.types || [], t = types.length ? (types[st.index] || types[0]) : null;
    var q = t ? Object.assign({}, t) : { width: V('hb_width_m', 1.5), height: V('hb_height_m', 1.8), bottom: V('hb_bottom_elevation_m', 0), startOverhang: V('overhang_m', 1), endOverhang: V('overhang_m', 1) };
    var sel = $('mstpvBeamType'); if (sel && types.length) { var idx = Number(sel.value); if (types[idx]) q = Object.assign({}, types[idx]); }
    q.pileD = V('diameter_mm', 0); q.span = global.mstpvBeamSpan || 0; q.fill = '#b7bec4';
    return build.beam(q);
  }
  var precastTypeKey = null, precastLookup = null, precastLookupId = 0;
  var draftLengths = Object.create(null);
  function refreshPrecastLengths(type) {
    precastLookup = null;
    var id = ++precastLookupId;
    if (global.sketchup && global.sketchup.mst_preview_precast_lengths) {
      global.sketchup.mst_preview_precast_lengths(JSON.stringify({id:id, type:type}));
    } else {
      precastLookup = {error:'Model boyları okunamadı.'};
    }
  }
  global.mstpvPrecastLengths = function (id, payload) {
    if (id !== precastLookupId) return;
    precastLookup = payload;
    ui.update('precast');
  };
  function setPrecastLengthField(input, value, disabled, hint) {
    if (!input) return;
    if (input.value !== value) input.value = value;
    input.disabled = disabled;
    input.placeholder = hint;
  }
  var quantityKey=null, quantityResult=null;
  global.mstpvPrecastQuantities=function(key,payload){
    if(key!==quantityKey)return;
    quantityResult=payload;ui.update('precast');
  };
  function readPrecast() {
    var input = $('mstpvPrecastLength'), instance = $('mstpvPrecastInstance');
    var list = global.precastTypes || [], sel = $('mstpvPrecastType'), t = null;
    if (sel) t = list.filter(function (x) { return x.uid === sel.value; })[0];
    t = t || list[0];
    var typeKey = t ? JSON.stringify([t.uid, t.family, t.name]) : null;
    if (typeKey !== precastTypeKey) {
      precastTypeKey = typeKey;
      if (t) refreshPrecastLengths(t);
      else ++precastLookupId;
    }
    if (instance) instance.hidden = true;
    if (selectedGeometry.precast) {
      var selected = selectedGeometry.precast;
      setPrecastLengthField(input, selected.length > 0 ? fmt(selected.length, 3) : '', true,
        selected.lengths && selected.lengths.length > 1 ? 'Birden çok boy' : 'Boy kaydı yok');
      return build.selected(selected);
    }
    if (!t) {
      setPrecastLengthField(input, '', true, 'Tip seçin');
      return {error:'Prekast tipi tanımlı değil.'};
    }
    var q = Object.assign({}, t);
    if (t.family === 'PK') q.sec = typeof global.mstPkSectionOf === 'function' ? global.mstPkSectionOf(t) : null;
    if (!precastLookup || precastLookup.error) {
      setPrecastLengthField(input, '', true, 'Model boyu');
      var pending = build.precast(q);
      pending.info = precastLookup ? precastLookup.error : 'Modeldeki prekast boyları okunuyor…';
      return pending;
    }
    var rows = precastLookup.rows;
    if (rows.length) {
      delete draftLengths[typeKey];
      var row = rows[0];
      if (instance && rows.length > 1) {
        var previous = instance.value;
        instance.textContent = '';
        rows.forEach(function (item) {
          var option = document.createElement('option');
          option.value = item.pid;
          option.textContent = [item.structure,item.code,item.axis,item.length > 0 ? fmt(item.length,3)+' m' : 'Boy kaydı yok'].filter(Boolean).join(' · ');
          instance.appendChild(option);
        });
        row = rows.filter(function (item) { return String(item.pid) === previous; })[0] || row;
        instance.value = String(row.pid);
        instance.hidden = false;
      }
      setPrecastLengthField(input, row.length > 0 ? fmt(row.length, 3) : '', true, 'Boy kaydı yok');
      q.L = row.length || 0;
      var actual = build.precast(q);
      actual.info = ['Model kaydı', row.structure, row.code, row.axis,
        row.length > 0 ? 'Boy '+fmt(row.length,3)+' m' : 'Boy kaydı yok',
        row.volume != null ? 'Beton ('+(row.concrete||'sınıf kaydı yok')+') '+fmt(row.volume,3)+' m³' : 'Beton kaydı yok',
        row.formwork != null ? 'Kalıp '+fmt(row.formwork,3)+' m²' : 'Kalıp kaydı yok'].filter(Boolean).join(' · ');
      return actual;
    }
    var draft = draftLengths[typeKey] || '';
    setPrecastLengthField(input, draft, false, 'Boşsa 1 m');
    var entered = draft.trim();
    var length = entered ? num(entered,NaN) : 1;
    if (!(length>0)) return {error:'Metraj boyu pozitif bir sayı olmalı.'};
    q.L=length;
    var view=build.precast(q);
    var flags={};
    ['pd_fw_bottom','pd_fw_long1','pd_fw_long2','pd_fw_end1','pd_fw_end2','channel_fw_bottom','channel_fw_sides','channel_fw_inner','channel_fw_ends','channel_fw_ledge'].forEach(function(id){
      flags[id]=!!($(id)&&$(id).checked);
    });
    // The type card uses a one-metre piece; model and layout views show actual totals.
    var key=JSON.stringify({type:t,flags:flags,length:length});
    var concrete=t.concrete||'C30/37';
    view.info='Taslak · Beton sınıfı '+concrete;
    if(key!==quantityKey){
      quantityKey=key;quantityResult=null;
      if(global.sketchup && global.sketchup.mst_preview_precast_quantities){
        var request=JSON.parse(key);request.key=key;
        global.sketchup.mst_preview_precast_quantities(JSON.stringify(request));
      }
    }
    if(quantityResult && !quantityResult.error){
      view.info='Taslak · Kesit alanı '+fmt(quantityResult.area,3)+' m² · Beton ('+concrete+') '+fmt(quantityResult.volume,3)+(entered?' m³':' m³/m')+' · Kalıp '+fmt(quantityResult.formwork,3)+' m²'+(entered?' · Boy '+fmt(length,2)+' m':' (1 m parça)');
    }else if(quantityResult) view.info+=' · '+quantityResult.error;
    return view;
  }
  function precastSelectorHtml() {
    return '<div class="mstpv-toolbar"><button type="button" class="secondary" onclick="mstPageStep(\'precast\',1)">‹ Yerleşime dön</button>' +
      '<div class="mstpv-type-fields"><select id="mstpvPrecastType" class="mstpv-sel" aria-label="Önizlenecek prekast tipi"></select>' +
      '<label class="mstpv-length-field">Metraj boyu (m) <input id="mstpvPrecastLength" inputmode="decimal" placeholder="Model boyu" disabled></label><select id="mstpvPrecastInstance" aria-label="Modeldeki prekast örneği" hidden></select></div>' +
      '<button type="button" onclick="createPD(true)">Taslak yerleşimi önizle</button>' +
      '<button type="button" onclick="mstpvRequestGeometry(\'precast\')">Modeldeki prekast ve mesnetleri oku</button></div>';
  }
  function syncPrecastSelector() {
    var sel = $('mstpvPrecastType'); if (!sel) return;
    var list = global.precastTypes || [], cur = sel.value;
    var html = list.map(function (t) { return '<option value="' + t.uid + '">' + (t.family === 'PDO' ? 'PDÖ' : t.family) + ' · ' + String(t.name).replace(/[<>&"]/g, '') + '</option>'; }).join('');
    if (sel.innerHTML !== html) { sel.innerHTML = html; if (list.some(function (t) { return t.uid === cur; })) sel.value = cur; }
  }
  function syncBeamSelector() {
    var sel = $('mstpvBeamType'), state=beamState(), types=state.types || []; if (!sel) return;
    var cur = sel.value, html = types.map(function (t, i) { return '<option value="' + i + '">' + String(t.name).replace(/[<>&"]/g, '') + ' · ' + fmt(num(t.width, 0), 2) + ' × ' + fmt(num(t.height, 0), 2) + '</option>'; }).join('');
    if (sel.innerHTML !== html) { sel.innerHTML = html; sel.value = (cur!=='' && types[Number(cur)] ? cur : String(state.index || 0)); }
  }
  var deckPlan=null;
  build.deckPlan = function (plan) {
    if (!plan || !Array.isArray(plan.boxes) || !plan.boxes.length) return {error:'Modelde başlık kirişlerini seçip Önizle düğmesine basın.'};
    var z0=plan.z0,zt=plan.zt,th=plan.th;
    if (![z0,zt,th,plan.volume].every(Number.isFinite) || th<=0 || Math.abs(zt-z0-th)>1e-6) {
      return {error:'Döşeme kotları ve kalınlığı uyuşmuyor.'};
    }
    var gross=plan.gross;
    var cut=plan.openings && plan.openings[0];
    var v=cut ? (cut.v0+cut.v1)/2 : (gross[2]+gross[3])/2;
    var profile=plan.boxes.filter(function(b){return v>b[2]-EPS && v<b[3]+EPS;});
    var shape=function(pts){return {pts:pts,fill:'#a9c0cc',stroke:'#476375'};};
    var solids=plan.boxes.map(function(b){return {profile:rect(b[2],b[4],b[3],b[5]),axis:[1,0,0],origin:[b[0],0,0],L:b[1]-b[0],fill:'#a9c0cc',edges:false};});
    return {
      kesit:{shapes:profile.map(function(b){return shape(rect(b[0],b[4],b[1],b[5]));}),
       dims:[{a:[gross[1],z0],b:[gross[1],zt],text:fmt(th,2)+' m',off:10}],padR:65,
       notes:['Boyuna kesit · V = '+fmt(v,2)+' m','Üst '+fmtEl(zt)+' m · Alt '+fmtEl(z0)+' m']},
      plan:{shapes:plan.boxes.filter(function(b){return b[5]>=zt-EPS;}).map(function(b){return shape(rect(b[0],b[2],b[1],b[3]));})},
      iso:{solids:solids},
      info:'Alt '+fmtEl(z0)+' m · Üst '+fmtEl(zt)+' m · Kalınlık '+fmt(th,2)+' m · Net beton '+fmt(plan.volume,3)+' m³'
    };
  };
  function readDeck(){return build.deckPlan(deckPlan);}
  global.mstpvDeckPlan=function(plan){deckPlan=plan;if(modelPreview.deck)modelPreview.deck.draft=true;ui.update('deck');};
  var crownPlan=null;
  global.mstpvCrown=function(payload){crownPlan=payload;if(modelPreview.crown)modelPreview.crown.draft=true;ui.update('crown');};
  global.mstpvReadCrown=function(){
    if(global.sketchup && global.sketchup.mst_preview_crown && typeof global.crownData==='function'){
      global.sketchup.mst_preview_crown(JSON.stringify(global.crownData()));
    }
  };
  function readCrown(){
    if(!crownPlan||crownPlan.error)return {error:crownPlan&&crownPlan.error||'Kesit ve istasyonları girip Önizle düğmesine basın.'};
    var view=build.crown(crownPlan);
    view.info='Taslak beton '+fmt(crownPlan.volume,3)+' m³';
    return view;
  }
  function readRockfillArea(){
    if(typeof global.sortedRFSections!=='function')return {error:'Kesit kayıtları okunamadı.'};
    var error=typeof global.rfSectionError==='function' && global.rfSectionError(false);
    if (error || global.rfProjectBad) return {error:error || 'Kayıtlı dolgu verisi okunamadı.'};
    var sections=global.sortedRFSections();
    var points=sections.map(function(sec){
      return [Number(sec.station),Object.keys(sec.areas||{}).reduce(function(sum,key){return sum+Number(sec.areas[key]);},0)];
    });
    if(points.length<2 || points.some(function(p,i){return !p.every(Number.isFinite)||p[1]<0||(i>0&&p[0]<=points[i-1][0]);}))return {error:'Artan istasyonlar ve geçerli kesit alanları girin.'};
    var chart=points.concat([[points[points.length-1][0],0],[points[0][0],0]]);
    return {kesit:{shapes:[{pts:chart,fill:'#bdd6e5'}],notes:['Alan–istasyon grafiği · yatay m / düşey m²','Kesit sınırları ve kotlar bu kayıtta bulunmaz.']},
      iso:{error:'3B için kesit sınırı ve kot verisi gerekir.'},
      info:'İstasyon boyu '+fmt(points[points.length-1][0]-points[0][0],3)+' m · AEA toplamı '+($('rfTotalVol')?$('rfTotalVol').textContent:'—')+
        ' · Tonaj '+($('rfTotalTon')?$('rfTotalTon').textContent:'—')};
  }
  var liveSection=null;
  global.mstpvFillSection=function(payload){liveSection=payload;ui.update('rockfill');};
  global.mstpvReadFillSection=function(){
    if(global.sketchup && global.sketchup.mst_preview_fill_section)global.sketchup.mst_preview_fill_section(Number(V('mstpvLiveSection',V('rflSection',0))));
  };
  build.fillSection=function(data){
    if(!data||data.error)return {error:data&&data.error||'Hesaplanan enkesiti seçip Kesiti Oku düğmesine basın.'};
    var colors=['#94a5b5','#c6a882','#8eb5a8','#a5a0c4'];
    var codes=Object.keys(data.areas||{});
    var shapes=data.cells.map(function(c){return {pts:c.points,fill:colors[Math.max(codes.indexOf(c.code),0)%colors.length],stroke:'#526779'};});
    data.bed.forEach(function(line){shapes.push({pts:line,open:true,stroke:'#147782',sw:2});});
    var faces=(data.triangles||[]).map(function(p){return {pts:p,holes:[],n:unit(cross(sub(p[1],p[0]),sub(p[2],p[0]))),fill:'#aab7a8'};});
    return {kesit:{shapes:shapes,notes:['İstasyon '+fmt(data.station,2)+' m · '+data.type,'Turkuaz · hesapta kullanılan taban profili']},
      iso:faces.length?{faces:faces}:{error:data.iso_note||'Güncel 3B dolgu katısı bulunamadı.'},
      info:codes.map(function(code){return code+' '+fmt(data.areas[code],3)+' m²';}).join(' · ')+
        ' | Model aksı '+fmt(data.length,3)+' m · Toplam '+fmt(data.total,3)+' m³'};
  };
  function readRockfillLive(){return build.fillSection(liveSection);}
  function readBored() { return build.column({ d_mm: V('diameter', 0), top: V('top', NaN), bottom: V('bottom', NaN), drill_top: V('drill_top', NaN), casing: V('casing', 'none') === 'none' ? 0 : V('casing_length', 0), label: 'fore kazık', fill: '#c9c0a8' }); }
  function readJet() { return build.column({ d_mm: V('diameter', 0), top: V('top', NaN), bottom: V('bottom', NaN), drill_top: V('drill_top', NaN), casing: 0, label: 'jet grout', fill: '#c9bde6' }); }

  function readReference() {
    var data = global.mstpvReferenceData;
    if (!data || !data.rows || !data.rows.length) return {error:'Önce referans kesit kübajını yükleyin.'};
    var rows = data.rows.filter(function (r) {
      return Number.isFinite(r.start_m) && Number.isFinite(r.end_m) && r.end_m > r.start_m && r.volumes_m3;
    });
    if (!rows.length) return {error:'Çizilebilecek referans aralığı yok.'};
    var totals = data.totals_m3 || {};
    var start = Math.min.apply(null,rows.map(function (r) {return r.start_m;}));
    var end = Math.max.apply(null,rows.map(function (r) {return r.end_m;}));
    return {plan:{shapes:rows.map(function (r) {
      var volume = Object.keys(r.volumes_m3).reduce(function (v,k) {return v+Number(r.volumes_m3[k]||0);},0);
      return {pts:rect(r.start_m,0,r.end_m,volume/(r.end_m-r.start_m)),fill:'#bdd6e5'};
    }),notes:['Referans aralıkları · yatay istasyon (m) · düşey hacim / aralık boyu (m²)']},
    info:'Çizilen aralık '+fmt(end-start,3)+' m · Referans toplamı '+fmt(Object.keys(totals).reduce(function(v,k){return v+Number(totals[k]||0);},0),3)+' m³'+(data.partial?' · Kısmi kübaj':'')};
  }
  function fullPreview(pageId,cfg) {
    var page = $(pageId);
    if (!page) return;
    var host = document.createElement('div');
    host.className = 'mstpv-full';
    page.appendChild(host);
    cfg.full = true;
    cfg.host = host;
    cfg.selectorHtml = '<div class="mstpv-full-actions"><button type="button" class="secondary" onclick="mstPreviewBack(\''+
      pageId+'\')">‹ Düzenlemeye dön</button>'+(cfg.selectorHtml || '')+'</div>';
    ui.mount(cfg);
  }
  function columnPreview(cfg) {
    var body = document.body, content = document.createElement('div');
    content.className = 'mstpv-local-content';
    Array.prototype.slice.call(body.children).forEach(function (el) {
      if (!/^(SCRIPT|STYLE|LINK)$/.test(el.tagName)) content.appendChild(el);
    });
    var tabs = document.createElement('div');
    tabs.className = 'mstpv-local-tabs';
    tabs.setAttribute('role','tablist');
    tabs.innerHTML = '<button type="button" role="tab" aria-selected="true">Tümü</button><button type="button" role="tab" aria-selected="false">Önizleme</button>';
    var host = document.createElement('div');
    host.className = 'mstpv-full mstpv-local-preview';
    host.hidden = true;
    body.insertBefore(tabs,body.firstChild);
    body.appendChild(content);
    body.appendChild(host);
    cfg.full = true;
    cfg.host = host;
    cfg.selectorHtml = '<div class="mstpv-full-actions"><button type="button" class="secondary">‹ Düzenlemeye dön</button></div>';
    ui.mount(cfg);
    function show(preview) {
      content.hidden = preview;
      host.hidden = !preview;
      tabs.children[0].setAttribute('aria-selected',String(!preview));
      tabs.children[1].setAttribute('aria-selected',String(preview));
      if (preview) {
        modelPreview[cfg.id].filter = null;
        ui.update(cfg.id);
      }
    }
    tabs.children[0].onclick = function () {show(false);};
    tabs.children[1].onclick = function () {show(true);};
    host.querySelector('.mstpv-full-actions button').onclick = function () {show(false);};
  }
  function syncLivePreviewSections() {
    var source = $('rflSection'), select = $('mstpvLiveSection');
    if (!source || !select) return;
    var html = source.innerHTML;
    if (select._mstOptions !== html) {
      select.innerHTML = html;
      select._mstOptions = html;
      select.value = source.value;
    }
  }
  ui.init = function () {
    if (ui.initialized) return;
    ui.initialized = true;
    var m;
    fullPreview('pile',{id:'pile',title:'Çelik Boru Kazık Önizleme',views:['boyuna','kesit','iso'],read:readPile});
    fullPreview('beam',{id:'beam',title:'Başlık Kirişi Önizleme',
      selectorHtml:'<select id="mstpvBeamType" class="mstpv-sel" aria-label="Önizlenecek BK tipi"></select>',
      views:['kesit','boyuna','iso'],read:readBeam});
    if ($('precast') && (m = $('mstPrecastFullPreview'))) ui.mount({ id: 'precast', host: m, title: 'Tip Önizleme (Kesit / Boyuna / 3B)', selectorHtml: precastSelectorHtml(), views: ['kesit', 'boyuna', 'plan', 'iso'], read: function () { syncPrecastSelector(); return readPrecast(); } });
    fullPreview('deck',{id:'deck',title:'Döşeme Önizleme',selectorHtml:'<button type="button" onclick="previewDeck()">Taslağı hesapla</button>',
      views:['kesit','plan','iso'],read:readDeck});
    fullPreview('crown',{id:'crown',title:'Kronman Duvarı Önizleme',selectorHtml:'<button type="button" onclick="mstpvReadCrown()">Taslağı hesapla</button>',
      views:['kesit','iso'],read:readCrown});
    fullPreview('rockfill',{id:'rockfillArea',title:'Alternatif-01 · Alan ve İstasyon',views:['plan'],read:function(){
      var view=readRockfillArea();view.plan=view.kesit;return view;
    }});
    fullPreview('rockfill_live',{id:'rockfill',title:'Alternatif-02 · Kesit ve 3B Önizleme',
      selectorHtml:'<select id="mstpvLiveSection" aria-label="Önizlenecek enkesit"></select><button type="button" onclick="mstpvReadFillSection()">Kesiti oku</button>',
      views:['kesit','iso'],read:function(){syncLivePreviewSections();return readRockfillLive();}});
    fullPreview('rockfill_alt2',{id:'rockfillReference',title:'Alternatif-02 · Referans Kübaj Önizleme',views:['plan'],read:readReference});
    if ($('section') && $('diameter')) {
      $('section').style.display='none';
      columnPreview({id:'bored',title:'Fore Kazık Önizleme',views:['kesit','boyuna','iso'],read:readBored});
    }
    if ($('cement_kg_m') && $('diameter')) columnPreview({id:'jet',title:'Jet Grout Önizleme',views:['kesit','boyuna','iso'],read:readJet});
    // olaylar: sayfa içi her giriş / tıklama → ilgili kartı gecikmeli yenile
    var map = { pile: 'pile', beam: 'beam', precast: 'precast', deck: 'deck', crown: 'crown', rockfill_live: 'rockfill', rockfill: 'rockfillArea' };
    ['input', 'change', 'click'].forEach(function (ev) {
      document.addEventListener(ev, function (e) {
        var t = e.target; if (!t || !t.closest) return;
        if (t.closest('.mstpv-btns,.mstpv-model')) return;
        if (t.id==='mstpvLiveSection' && ev==='change') {
          liveSection=null;
          ui.update('rockfill');
          global.mstpvReadFillSection();
          return;
        }
        var pg = t.closest('.page');
        if (t.id === 'mstpvPrecastLength' && ev === 'input' && !t.disabled && precastTypeKey) draftLengths[precastTypeKey] = t.value;
        if (t.id === 'mstpvPrecastType' && ev === 'change') {
          delete selectedGeometry.precast;
          ui.update('precast');
        }
        if (t.id === 'mstpvPrecastInstance') {
          if (ev === 'change') ui.update('precast');
          return;
        }
        if (pg && (pg.id==='beam'||pg.id==='precast') && ev!=='click') delete selectedGeometry[pg.id];
        if (pg && pg.id==='deck' && ev!=='click' && !t.closest('.mstpv-card')) deckPlan=null;
        if (pg && pg.id==='crown' && ev!=='click') { crownPlan=null; clearTimeout(crownTimer); crownTimer=setTimeout(global.mstpvReadCrown,250); }
        if (pg && pg.id==='rockfill_live' && ev!=='click') liveSection=null;
        if (pg && map[pg.id]) { ui.schedule(map[pg.id]); if (pg.id === 'precast') ui.schedule('deck'); if (pg.id === 'beam') ui.schedule('deck'); return; }
        if (ui.pages.bored) ui.schedule('bored'); if (ui.pages.jet) ui.schedule('jet');
      }, true);
    });
    // tip listeleri yeniden çizilince (renderPrecastTypes / renderTypes) ve Ruby'den gelen yüklemelerde
    ['renderPrecastTypes', 'renderTypes', 'loadPrecastTypeLibrary', 'crownLoaded', 'crownAxisLoaded', 'renderCrownIntervals', 'rfLiveLoaded', 'rfLiveError', 'renderRockfillQTO', 'rfLiveEditType', 'bpEdit', 'jgEdit', 'mstBKMirror', 'loadSelectedBimPile'].forEach(function (fn) {
      var o = global[fn]; if (typeof o !== 'function' || o._mstpv) return;
      var w = function () { if(fn==='rfLiveLoaded'||fn==='rfLiveError')liveSection=null; var r = o.apply(this, arguments); setTimeout(ui.updateAll, 30); return r; }; w._mstpv = true; global[fn] = w;
    });
    var precastPage = $('precast');
    if (precastPage && typeof global.MutationObserver === 'function') {
      new global.MutationObserver(function () {
        if (precastPage.getAttribute('data-pf-preview') !== 'true') return;
        precastTypeKey = null;
        ui.update('precast');
      }).observe(precastPage, {attributes:true, attributeFilter:['data-pf-preview']});
    }
    ['bpLoaded','jgLoaded'].forEach(function (name) {
      var original = global[name];
      if (typeof original !== 'function') return;
      global[name] = function () {
        var result = original.apply(this,arguments);
        var kind = name === 'bpLoaded' ? 'bored' : 'jet';
        if (modelPreview[kind]) modelPreview[kind].filter = null;
        ui.schedule(kind,0);
        return result;
      };
    });
    if (typeof global.MutationObserver === 'function') {
      var ids={pile:'pile',beam:'beam',deck:'deck',crown:'crown',rockfill:'rockfillArea',rockfill_live:'rockfill',rockfill_alt2:'rockfillReference'};
      Object.keys(ids).forEach(function (pageId) {
        var page=$(pageId);
        if (!page) return;
        new global.MutationObserver(function () {
          if(page.getAttribute('data-mst-full-preview')!=='true')return;
          var kind=ids[pageId];
          if(modelPreview[kind])modelPreview[kind].filter=null;
          ui.update(kind);
        }).observe(page,{attributes:true,attributeFilter:['data-mst-full-preview']});
      });
    }
    setTimeout(ui.updateAll, 450);
  };

  var api = { geom: { num: num, ratio: ratio, fmt: fmt, proj: proj, frame: frame, circle: circle, rect: rect, area2: area2, bbox2: bbox2, solidFaces: solidFaces, visibleFaces: visibleFaces, bkProfile: bkProfile, dispLen: dispLen, shade: shade, EYE: EYE }, build: build, ui: ui, draw: { plane: drawPlane, iso: drawIso } };
  global.MSTPreview = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  if (typeof document !== 'undefined') {
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', function () { setTimeout(ui.init, 60); }); else setTimeout(ui.init, 60);
  }
})(typeof window !== 'undefined' ? window : this);

