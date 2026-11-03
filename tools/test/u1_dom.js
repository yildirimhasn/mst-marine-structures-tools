// U1 / U2 adım çalıştırıcı: ui.html + bütün betikleri (u_fakedom.js sahte DOM'unda, tarayıcı sırasıyla) yükler, sonra
// adımları sırayla uygular ve her adım için sonucu tek JSON satırı olarak basar ("RES {...}"). Doğrulama Ruby tarafındadır.
// Adım: {label, js} (değer döner) | {label, click: '<seçici>'} | {label, clickNav: '<onclick parçası>'} | {label, onclickOf: '<seçici>'}.
// Sonuç: label, value, err (betik / zamanlayıcı / console.error hataları), calls (bu adımda yapılan sketchup.* çağrıları),
//        alerts, page (açık sayfa), nav (menüde 'on' düğmesinin metni).
// Kullanim: node tools/test/u1_dom.js <klasör> <adimlar.json> [html dosyası=ui.html]
'use strict';
const fs = require('fs');
const path = require('path');
const { loadPage } = require('./u_fakedom');
const dir = process.argv[2];
const steps = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'));
const { D, loadErrors } = loadPage(dir, process.argv[4] ? { file: process.argv[4] } : {});
console.log('RES ' + JSON.stringify({ label: '__load__', err: loadErrors.concat(D.errors.splice(0)), calls: D.calls.splice(0), alerts: D.alerts.splice(0) }));
const vm = require('vm');
function safe(v) { try { return v === undefined ? null : JSON.parse(JSON.stringify(v)); } catch (e) { return String(v); } }
steps.forEach((s) => {
  const res = { label: s.label, value: null, err: [] };
  try {
    if (s.js !== undefined) res.value = safe(vm.runInContext(s.js, D.ctx, { filename: s.label }));
    else if (s.click) { const e = D.doc.querySelector(s.click); if (!e) res.err.push('öğe yok: ' + s.click); else if (e.disabled) res.value = 'devre dışı'; else { e.click(); res.value = 'tıklandı'; } }
    else if (s.clickNav) { const e = D.doc.querySelectorAll('.tabs button').find((b) => (b.getAttribute('onclick') || '').includes(s.clickNav)); if (!e) res.err.push('menü düğmesi yok: ' + s.clickNav); else { e.click(); res.value = e.textContent.trim(); } }
    else if (s.onclickOf) { const e = D.doc.querySelector(s.onclickOf); res.value = e ? e.getAttribute('onclick') : null; }
  } catch (e) { res.err.push(e.message); }
  if (!s.noflush) D.flush();
  res.err = res.err.concat(D.errors.splice(0));
  res.calls = D.calls.splice(0);
  res.alerts = D.alerts.splice(0);
  const pg = D.doc.querySelector('.page.on'); res.page = pg ? pg.id : null;
  const nb = D.doc.querySelector('.tabs button.on'); res.nav = nb ? nb.textContent.trim() : null;
  console.log('RES ' + JSON.stringify(res));
});
