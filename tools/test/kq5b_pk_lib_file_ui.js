// ADR-0515-K3 P5 arayüz: kişisel PK kütüphanesi (dışa ver / içe al) — dört dosya durumu, içe al seçilebilirlik kuralı
// (yalnız modelde:"yok"), gönderim alanları, sonuç metinleri ve içe al sonrası kütüphane yenileme (sahte DOM, SketchUp DIŞINDA).
// Yanıt payload'ları sözleşmeye göre elle yazıldı (main.rb P5 tarafı bu test yazılırken depoda yoktu). Dosya yazımı, atomiklik,
// Ruby çakışma denetimi ve görünüm kanıtlanmaz.
// Kullanım: node tools/test/kq5b_pk_lib_file_ui.js   (çıkış kodu 0 = geçti)
'use strict';
const path = require('path');
const vm = require('vm');
const { loadPage } = require('./u_fakedom');
const dir = path.join(__dirname, '..', '..', 'src', 'marine_structures_tools');
const { D, loadErrors } = loadPage(dir);
const js = (c) => vm.runInContext(c, D.ctx);
let fail = 0;
const ok = (c, m) => { if (c) console.log('OK   ' + m); else { fail++; console.log('HATA ' + m); } };
const take = (name) => D.calls.splice(0).filter((x) => x[0] === name);
const txt = (id) => js("(document.getElementById('" + id + "')||{textContent:''}).textContent");
const dis = (id) => js("!!(document.getElementById('" + id + "')||{disabled:true}).disabled");
const boxes = (id) => js("Array.prototype.map.call(document.querySelectorAll('#" + id + " input[type=\"checkbox\"]'),function(b){return b.value+':'+(b.disabled?'pasif':'etkin')}).join(',')");
const check = (id, uid) => js("Array.prototype.forEach.call(document.querySelectorAll('#" + id + " input[type=\"checkbox\"]'),function(b){if(b.value===" + JSON.stringify(uid) + ")b.checked=true})");
const clickId = (id) => js("(function(){var b=document.getElementById('" + id + "');if(!b)return 'yok';if(b.disabled)return 'pasif';b.click();return 'tik'})()");

ok(loadErrors.length === 0, 'sayfa yüklendi (' + loadErrors.join(' | ') + ')');
ok(!!js("document.getElementById('pkLibFilePanel')") && js("document.getElementById('pkLibFilePanel').tagName") === 'DETAILS', 'katlanır bölüm var');
ok(/Bu bilgisayardaki kişisel kütüphane dosyası; model kendi tiplerini ayrıca saklar\. Aktarma yalnız elle yapılır\./.test(txt('pkLibFilePanel')), 'açıklama metni');
D.calls.splice(0); D.errors.splice(0); D.alerts.splice(0);
ok(take('pk_lib_file_list').length === 0, 'sayfa açılışında dosya okunmaz');

const sec = { v: 1, preset: 'U', total_width_m: 1.2, base_m: 0.2, left: { on: true, width_m: 0.2, height_m: 0.6, offset_m: 0 }, mid: { on: false, width_m: 0.15, height_m: 0.3, offset_m: 0.5 }, right: { on: true, width_m: 0.2, height_m: 0.6, offset_m: 0 } };
const recA = { uid: 'pt_pk_A', family: 'PK', name: 'PK-001', title: 'U Kanal 800', pk_rev: 2, concrete: 'C30/37', section: sec };
const recB = { uid: 'pt_pk_B', family: 'PK', name: 'PK-002', title: 'U Kanal 900', pk_rev: 1, concrete: 'C30/37', section: Object.assign({}, sec, { total_width_m: 1.3 }) };
js('precastTypes.push(' + JSON.stringify(recA) + ',' + JSON.stringify(recB) + ');renderPrecastTypes();refreshAllPDRowOptions()');

// 1. Dışa ver listesi: yalnız kesitli PK tipleri (eski U kaydı pt_pk_1 ve PD/PDÖ/PV yok)
ok(boxes('pkLibExpList') === 'pt_pk_A:etkin,pt_pk_B:etkin', 'dışa ver listesi yalnız kesitli PK tipleri');
ok(/PK-001 — U Kanal 800 · rev 2/.test(txt('pkLibExpList')), 'dışa ver satırı: kod — ad · rev');

// 2. Bölüm açılınca / Listeyi Yenile: pk_lib_file_list
js("var p=document.getElementById('pkLibFilePanel');p.open=true;mstPkLibToggle(p)");
let c = take('pk_lib_file_list');
ok(c.length === 1 && c[0].length === 1, 'ilk açılışta sketchup.pk_lib_file_list() bağımsız değişkensiz');
ok(/okunuyor/.test(txt('pkLibFileInfo')) && dis('pkLibExpBtn') && dis('pkLibImpBtn'), 'okunurken durum + düğmeler pasif');
js("mstPkLibToggle(document.getElementById('pkLibFilePanel'))");
ok(take('pk_lib_file_list').length === 0, 'ikinci açılışta kendiliğinden yeniden okunmaz');

// 3. Dört durum
const yol = 'C:\\Users\\x\\AppData\\Roaming\\MarineStructuresTools\\PKLibrary\\pk_types.json';
js('mstPkLibFile(' + JSON.stringify({ ok: true, durum: 'yok', yol, tipler: [] }) + ')');
ok(/DOSYA YOK/.test(txt('pkLibFileInfo')) && txt('pkLibFileInfo').indexOf(yol) >= 0, 'durum yok: etiket + dosya yolu');
ok(dis('pkLibImpBtn') && !dis('pkLibExpBtn') && boxes('pkLibImpList') === '', 'durum yok: içe al pasif, dışa ver etkin');
js('mstPkLibFile(' + JSON.stringify({ ok: true, durum: 'bos', yol, tipler: [] }) + ')');
ok(/DOSYA BOŞ/.test(txt('pkLibFileInfo')) && dis('pkLibImpBtn') && !dis('pkLibExpBtn'), 'durum boş: etiket, içe al pasif');
js('mstPkLibFile(' + JSON.stringify({ ok: false, durum: 'bozuk', neden: 'JSON ayrıştırılamadı', yol, tipler: [] }) + ')');
ok(/DOSYA BOZUK/.test(txt('pkLibFileInfo')) && /dosya değiştirilmez/.test(txt('pkLibFileInfo')) && /JSON ayrıştırılamadı/.test(txt('pkLibFileInfo')), 'durum bozuk: "dosya değiştirilmez" + neden');
ok(dis('pkLibExpBtn') && dis('pkLibImpBtn'), 'durum bozuk: dışa ver ve içe al pasif');
D.calls.splice(0); js('mstPkLibExport()');
ok(take('pk_lib_file_export').length === 0, 'bozuk dosyada dışa ver gönderilmez');
js("mstPkLibFile({ok:false,neden:'Klasöre erişilemedi.'})");
ok(/OKUNAMADI/.test(txt('pkLibFileInfo')) && /Klasöre erişilemedi/.test(txt('pkLibFileInfo')), 'ok:false: neden görünür');

const tipler = [
  { uid: 'f1', kod: 'PK-010', ad: 'Kanal A', rev: 1, geom_sig: 'g1', section: sec, created_at: '2026-11-01', modelde: 'yok' },
  { uid: 'f2', kod: 'PK-001', ad: 'U Kanal 800', rev: 2, geom_sig: 'g2', section: sec, created_at: '2026-11-02', modelde: 'ayni' },
  { uid: 'f3', kod: 'PK-002', ad: 'Başka', rev: 1, geom_sig: 'g3', section: sec, modelde: 'kod_cakisma' },
  { uid: 'f4', kod: 'PK-020', ad: 'Kopya', rev: 3, geom_sig: 'g2', section: sec, modelde: 'geom_ayni_kod_farkli', modeldeki_kod: 'PK-001' },
  { uid: 'f5', kod: 'PK-030', ad: 'Bozuk kesit', rev: 1, geom_sig: 'g5', section: null, modelde: 'yok' }
];
js('mstPkLibFile(' + JSON.stringify({ ok: true, durum: 'tamam', yol, tipler }) + ')');
ok(/DOSYA OKUNDU/.test(txt('pkLibFileInfo')) && /5 tip/.test(txt('pkLibFileInfo')), 'durum tamam: tip sayısı');

// 4. Seçilebilirlik: yalnız modelde:"yok"
ok(boxes('pkLibImpList') === 'f1:etkin,f2:pasif,f3:pasif,f4:pasif,f5:etkin', 'yalnız "modelde yok" olanlar seçilebilir');
const il = txt('pkLibImpList');
ok(/MODELDE YOK/.test(il) && /MODELDE AYNI/.test(il) && /KOD ÇAKIŞMASI/.test(il) && /AYNI GEOMETRİ FARKLI KODLA MODELDE/.test(il), 'modelde durumu etiketleri');
ok(/AYNI GEOMETRİ FARKLI KODLA MODELDE: PK-001/.test(il), 'aynı geometri farklı kod: modeldeki kod gösterilir (modeldeki_kod)');
ok(/PK-010 — Kanal A · rev 1/.test(il) && /kişisel dosya/.test(il), 'içe al satırı: kod — ad · rev + kaynak');
ok(js("document.getElementById('pkLibMini0').childNodes.length") > 0 && /Kesit geçersiz/.test(js("document.getElementById('pkLibMini4').textContent")), 'mini kesit önizlemesi (geçersiz kesitte uyarı)');
ok(!dis('pkLibImpBtn') && !dis('pkLibExpBtn'), 'tamam: düğmeler etkin');

// 5. İçe al: seçim yok → gönderilmez; pasif kutu zorla işaretlense de gönderilmez
D.calls.splice(0); clickId('pkLibImpBtn');
ok(take('pk_lib_file_import').length === 0 && /SEÇİM YOK/.test(txt('pkLibImpResult')), 'seçimsiz içe al gönderilmez, uyarı görünür');
js("Array.prototype.forEach.call(document.querySelectorAll('#pkLibImpList input[type=\"checkbox\"]'),function(b){if(b.value==='f2'){b.disabled=false;b.checked=true}})");
check('pkLibImpList', 'f1');
D.calls.splice(0); clickId('pkLibImpBtn');
c = take('pk_lib_file_import');
const iq = c.length === 1 ? JSON.parse(c[0][1]) : null;
ok(iq && JSON.stringify(iq.uids) === '["f1"]', 'içe al: uids yalnız "modelde yok" (f2 süzüldü)');
ok(iq && Array.isArray(iq.kutuphane) && iq.kutuphane.some((t) => t.uid === 'pt_pk_A') && iq.kutuphane.length === js('precastTypes.length'), 'içe al: kutuphane = mstPkLibraryForSave(precastTypes)');
ok(dis('pkLibImpBtn') && dis('pkLibExpBtn') && /alınıyor/.test(txt('pkLibImpResult')), 'yanıt beklenirken düğmeler pasif');

// 6. İçe al sonucu: kütüphane yüklenir, PK listesi ve dosya listesi yenilenir
const lib2 = JSON.stringify(JSON.parse(js('JSON.stringify(precastTypes)')).concat([{ uid: 'pt_pk_new', family: 'PK', name: 'PK-010', title: 'Kanal A', pk_rev: 1, concrete: 'C30/37', section: sec }]));
D.calls.splice(0);
js('mstPkLibFileImported(' + JSON.stringify({ ok: true, eklenen: 1, atlanan: [{ kod: 'PK-030', neden: 'Kesit geçersiz' }], kutuphane_json: lib2 }) + ')');
const after = D.calls.splice(0).map((x) => x[0]);
ok(js("!!typeByUid('pt_pk_new')"), 'içe al sonrası kütüphane yüklendi (loadPrecastTypeLibrary)');
ok(after.filter((n) => n === 'pk_type_catalog').length === 1, 'içe al sonrası PK listesi yenilendi (mstPkRefresh)');
ok(after.filter((n) => n === 'pk_lib_file_list').length === 1, 'içe al sonrası dosya listesi yenilendi');
const ir = txt('pkLibImpResult');
ok(/MODELE ALINDI/.test(ir) && /Eklenen 1 tip · atlanan 1 tip/.test(ir) && /PK-030: Kesit geçersiz/.test(ir) && /modele PK konmadı/.test(ir), 'içe al sonucu: eklenen / atlanan + neden');
ok(/pt_pk_new/.test(boxes('pkLibExpList')), 'yeni tip dışa ver listesine girdi');
D.calls.splice(0);
js("mstPkLibFileImported({ok:false,neden:'Model tip kütüphanesi okunamadı.',atlanan:[]})");
ok(/İÇE ALINMADI/.test(txt('pkLibImpResult')) && /Model tip kütüphanesi okunamadı/.test(txt('pkLibImpResult')) && take('pk_type_catalog').length === 0, 'içe al hatası: neden görünür, kütüphane yenilenmez');
js('mstPkLibFile(' + JSON.stringify({ ok: true, durum: 'tamam', yol, tipler }) + ')');

// 7. Dışa ver gönderimi ve sonucu
js("Array.prototype.forEach.call(document.querySelectorAll('#pkLibExpList input[type=\"checkbox\"]'),function(b){b.checked=false})");
D.calls.splice(0); clickId('pkLibExpBtn');
ok(take('pk_lib_file_export').length === 0 && /SEÇİM YOK/.test(txt('pkLibExpResult')), 'seçimsiz dışa ver gönderilmez');
check('pkLibExpList', 'pt_pk_A'); check('pkLibExpList', 'pt_pk_B');
D.calls.splice(0); clickId('pkLibExpBtn');
c = take('pk_lib_file_export');
const eq = c.length === 1 ? JSON.parse(c[0][1]) : null;
ok(eq && JSON.stringify(Object.keys(eq)) === '["uids"]' && JSON.stringify(eq.uids) === '["pt_pk_A","pt_pk_B"]', 'dışa ver: yalnız {uids}');
ok(dis('pkLibExpBtn') && /yazılıyor/.test(txt('pkLibExpResult')), 'dışa ver beklenirken pasif');
D.calls.splice(0);
js('mstPkLibFileExported(' + JSON.stringify({ ok: true, eklenen: 1, guncellenen: 0, atlanan: [{ kod: 'PK-002', neden: 'Dosyada aynı kodlu farklı geometri var' }], yol }) + ')');
const er = txt('pkLibExpResult');
ok(/DOSYAYA VERİLDİ/.test(er) && /Eklenen 1 tip · güncellenen 0 tip · atlanan 1 tip/.test(er) && /PK-002: Dosyada aynı kodlu farklı geometri var/.test(er) && er.indexOf(yol) >= 0, 'dışa ver sonucu: eklenen / güncellenen / atlanan + neden + yol');
ok(take('pk_lib_file_list').length === 1, 'dışa ver sonrası dosya listesi yenilendi');
js("mstPkLibFileExported({ok:false,neden:'Dosya bozuk; değiştirilmedi.'})");
ok(/DIŞA VERİLMEDİ/.test(txt('pkLibExpResult')) && /Dosya bozuk; değiştirilmedi/.test(txt('pkLibExpResult')), 'dışa ver hatası: neden görünür');

ok(D.alerts.length === 0, 'alert yok (' + D.alerts.join(' | ') + ')');
ok(D.errors.length === 0, 'console.error / zamanlayıcı hatası yok (' + D.errors.join(' | ') + ')');
console.log(fail ? 'SONUÇ: ' + fail + ' HATA' : 'SONUÇ: hepsi geçti');
process.exit(fail ? 1 : 0);
