// ADR-0515-K3 P1 arayüz: "PK Tipi Olarak Kaydet" (Kanal Prekastı formu), dört yanıt durumu, 2b "Tip kütüphanesine ekle",
// tip kartı özeti, "+ Yeni PK Kanal Tipi Oluştur" yönlendirmesi (sahte DOM, SketchUp DIŞINDA). Yalnız JS mantığını sınar:
// sketchup.pk_type_save(json) istek alanları ve window.mstPkTypeSaved(p) yanıt işleme. Yanıt payload'ları sözleşmeye göre elle
// yazıldı (main.rb tarafı bu test yazılırken okunmadı). Ruby kaydı, Geri Al ve görünüm kanıtlanmaz.
// Kullanım: node tools/test/kq1b_pk_type_save_ui.js   (çıkış kodu 0 = geçti)
'use strict';
const path = require('path');
const { loadPage } = require('./u_fakedom');
const dir = path.join(__dirname, '..', '..', 'src', 'marine_structures_tools');
const { D, loadErrors } = loadPage(dir);
const vm = require('vm');
const js = (c) => vm.runInContext(c, D.ctx);
let fail = 0;
const ok = (c, m) => { if (c) console.log('OK   ' + m); else { fail++; console.log('HATA ' + m); } };
const take = (name) => D.calls.splice(0).filter((x) => x[0] === name);
const own = (o, k) => Object.prototype.hasOwnProperty.call(o, k);
const txt = (id) => js("(document.getElementById('" + id + "')||{textContent:''}).textContent");
const click = (scope, label) => js("(function(){var r=" + scope + ",b=Array.prototype.slice.call(r.querySelectorAll('button')).filter(function(x){return x.textContent.indexOf(" + JSON.stringify(label) + ")>=0})[0];if(!b)return 'yok';if(b.disabled)return 'pasif';b.click();return 'tik'})()");
const send = () => { const r = click("document.getElementById('pkSaveCard')", 'PK Tipi Olarak Kaydet'); const c = take('pk_type_save'); return { r, q: c.length === 1 ? JSON.parse(c[0][1]) : null, n: c.length }; };
const reply = (p) => js('mstPkTypeSaved(' + JSON.stringify(p) + ')');
const sendCh = () => { js('createChannelPrecast()'); const c = take('create_channel_precast'); return c.length === 1 ? c[0][1] : null; };
const sendPD = () => { js('createPD()'); const c = take('create_flat_precast'); return c.length === 1 ? c[0][1] : null; };

ok(loadErrors.length === 0, 'sayfa yüklendi (' + loadErrors.join(' | ') + ')');
js('updateChannelPrecastUI()');
D.calls.splice(0); D.errors.splice(0); D.alerts.splice(0);
const ch0 = sendCh(), pd0 = sendPD();

// 1. Form bölümü ve öneriler
ok(js("!!document.getElementById('pk_save_kod')&&!!document.getElementById('pk_save_ad')&&!!document.getElementById('pkSaveBtn')"), 'formda PK kodu, tip adı ve "PK Tipi Olarak Kaydet" var');
ok(js("document.getElementById('pk_save_kod').value") === 'PK-002', 'kod önerisi sıradaki PK-002 (kütüphanede PK-01)');
ok(js("document.getElementById('pk_save_ad').value") === 'U Kanal 1200', 'ad önerisi ön ayar + toplam genişlik (U Kanal 1200)');
ok(js("document.getElementById('pkSaveBtn').disabled") === false, 'geçerli kesitte düğme etkin');
js("chApplyPreset('L');document.getElementById('channel_total_width_m').value='1.00';updateChannelPrecastUI()");
ok(js("document.getElementById('pk_save_ad').value") === 'L Kanal 1000', 'ön ayar / genişlik değişince ad önerisi güncellendi (L Kanal 1000)');

// 2. Geçersiz kesit / boş kod: pasif + neden
js("document.getElementById('channel_base_m').value='0';updateChannelPrecastUI()");
ok(js("document.getElementById('pkSaveBtn').disabled") === true && /Kesit geçersiz/.test(txt('pkSaveWhy')), 'geçersiz kesitte düğme pasif, neden görünür');
ok(send().n === 0, 'geçersiz kesitte istek gönderilmez');
js("document.getElementById('channel_base_m').value='0.20';updateChannelPrecastUI()");
js("var k=document.getElementById('pk_save_kod');k.value='  ';mstPkSaveEdited('kod')");
ok(js("document.getElementById('pkSaveBtn').disabled") === true && /PK kodunu girin/.test(txt('pkSaveWhy')), 'boş kodda pasif + neden');
js("var k=document.getElementById('pk_save_kod');k.value='PK-010';mstPkSaveEdited('kod')");
ok(js("document.getElementById('pkSaveBtn').disabled") === false && txt('pkSaveWhy') === '', 'kod girilince etkin, neden temizlendi');
js("updateChannelPrecastUI()");
ok(js("document.getElementById('pk_save_kod').value") === 'PK-010', 'elle girilen kod form güncellemesinde korunur');

// 3. İstek alanları (sözleşme)
js("document.getElementById('channel_fw_inner').checked=false;document.getElementById('channel_fw_ledge').checked=false;document.getElementById('channel_seat_left_m').value='0,20'");
let s = send(), q = s.q || {};
ok(s.n === 1, 'sketchup.pk_type_save bir kez çağrıldı');
ok(q.kod === 'PK-010' && q.ad === 'L Kanal 1000' && q.section && q.section.preset === 'L' && q.section.total_width_m === 1 && q.concrete === 'C30/37', 'kod, ad, section (L, 1,000 m), concrete');
ok(q.fw && q.fw.bottom === true && q.fw.sides === true && q.fw.inner === false && q.fw.ends === true && q.fw.ledge === false && Object.keys(q.fw).length === 5, 'fw: bottom/sides/inner/ends/ledge bool (inner, ledge kaldırıldı)');
ok(q.seat_left_m === 0.2 && q.seat_right_m === 0.15, 'oturma payları sayı (ondalık virgül okundu)');
ok(q.karar === null && own(q, 'karar') && !own(q, 'kaynak_pid') && !own(q, 'channel_top_ref'), 'karar null; kaynak_pid ve channel_top_ref yok (varsayılan üst yüzey)');
ok(Array.isArray(q.kutuphane) && q.kutuphane.some((t) => t.uid === 'pt_pk_1'), 'kutuphane = mstPkLibraryForSave(precastTypes) dizisi');
ok(/Kaydediliyor/.test(txt('pkSaveResult')) && js("document.getElementById('pkSaveBtn').disabled") === true, 'yanıt beklenirken durum satırı + düğme pasif');
ok(send().n === 0, 'yanıt gelmeden ikinci istek yok');

// 4. ayni_geometri → Mevcut tipi kullan (karar "mevcut") → mevcut_secildi
reply({ ok: false, durum: 'ayni_geometri', mevcut: { uid: 'pt_pk_old', kod: 'PK-007', ad: 'L Kanal Eski' } });
ok(/Bu geometri zaten PK-007 \(L Kanal Eski\) olarak kayıtlı/.test(txt('pkSaveResult')), 'aynı geometri: mevcut tip kodu ve adı görünür');
ok(click("document.getElementById('pkSaveResult')", 'Mevcut tipi kullan') === 'tik', '"Mevcut tipi kullan" düğmesi var');
let c = take('pk_type_save'), q2 = c.length === 1 ? JSON.parse(c[0][1]) : {};
ok(q2.karar === 'mevcut' && q2.kod === 'PK-010' && q2.section && q2.section.preset === 'L' && Array.isArray(q2.kutuphane), 'karar "mevcut" ile aynı istek yeniden gönderildi');
const libA = [{ uid: 'pt_pk_1', family: 'PK', name: 'PK-01', inner_width: 0.8, inner_depth: 0.6, base: 0.2, wall: 0.2, concrete: 'C30/37' },
  { uid: 'pt_pk_old', family: 'PK', name: 'PK-007', title: 'L Kanal Eski', pk_rev: 1, created_at: '2026-11-10T09:00:00+03:00', concrete: 'C30/37', section: q.section }];
reply({ ok: true, durum: 'mevcut_secildi', mevcut: { uid: 'pt_pk_old', kod: 'PK-007', ad: 'L Kanal Eski' }, kutuphane_json: JSON.stringify(libA) });
ok(js("!!typeByUid('pt_pk_old')"), 'kutuphane_json ile tip listesi yenilendi');
ok(take('pk_type_catalog').length === 1, 'PK listesi yeniden istendi (pk_type_catalog)');
ok(/MEVCUT TİP SEÇİLDİ/.test(txt('pkSaveResult')) && /PK-007 \(L Kanal Eski\)/.test(txt('pkSaveResult')), 'mevcut_secildi durum satırı');
ok(js("document.getElementById('pk_save_kod').value") === 'PK-008', 'kayıttan sonra kod önerisi yeniden: PK-008');
D.doc._scrolled.splice(0);
ok(click("document.getElementById('pkSaveResult')", "Prekast Yerleşimi'nde kullan") === 'tik', '"Prekast Yerleşimi\'nde kullan" kısayolu');
ok(js("Array.prototype.slice.call(document.querySelectorAll('.pd-layout-row')).filter(function(r){return r.querySelector('.pd-family').value==='PK'})[0].querySelector('.pd-type').value") === 'pt_pk_old', 'tip ilk PK yerleşim satırına atandı (mstPkUseType)');
ok(js("document.getElementById('precast').classList.contains('on')") === true && D.doc._scrolled.indexOf('pdLayoutRows') >= 0, 'Prekast sayfası açık, yerleşim satırlarına gidildi');
D.calls.splice(0);

// 5. ayni_geometri → Yine de yeni tip kaydet (karar "yeni") → kaydedildi (kutuphane_json dizi olarak da okunur)
s = send();
reply({ ok: false, durum: 'ayni_geometri', mevcut: { uid: 'pt_pk_old', kod: 'PK-007', ad: 'L Kanal Eski' } });
ok(click("document.getElementById('pkSaveResult')", 'Yine de yeni tip kaydet') === 'tik', '"Yine de yeni tip kaydet" düğmesi var');
c = take('pk_type_save'); q2 = c.length === 1 ? JSON.parse(c[0][1]) : {};
ok(q2.karar === 'yeni' && q2.kod === 'PK-008', 'karar "yeni" ile yeniden gönderildi');
const libB = libA.concat([{ uid: 'pt_pk_new', family: 'PK', name: 'PK-008', title: 'L Kanal 1000', pk_rev: 1, created_at: '2026-11-10', concrete: 'C30/37', section: q.section }]);
reply({ ok: true, durum: 'kaydedildi', tip: { uid: 'pt_pk_new', kod: 'PK-008', ad: 'L Kanal 1000' }, kutuphane_json: libB });
ok(js("!!typeByUid('pt_pk_new')") && /KAYDEDİLDİ/.test(txt('pkSaveResult')) && /PK-008 \(L Kanal 1000\) tip kütüphanesine kaydedildi/.test(txt('pkSaveResult')), 'kaydedildi: liste yenilendi, durum satırı');
ok(/Prekast Yerleşimi'nde kullan/.test(txt('pkSaveResult')), 'kaydedildi: yerleşim kısayolu var');
ok(js("Array.prototype.slice.call(document.querySelectorAll('#pdLayoutRows .pd-type')).some(function(s){return Array.prototype.slice.call(s.options).some(function(o){return o.value==='pt_pk_new'})})"), 'yeni tip yerleşim satırı seçeneklerinde (Prekast Yerleşimi\'nde seçilebilir)');
D.calls.splice(0);

// 6. kod_cakisma: kod alanı işaretlenir; düzeltilince işaret kalkar
js("var k=document.getElementById('pk_save_kod');k.value='PK-01';mstPkSaveEdited('kod')");
s = send();
reply({ ok: false, durum: 'kod_cakisma', neden: 'PK-01 kodu başka geometride kayıtlı.', mevcut: { uid: 'pt_pk_1', kod: 'PK-01', ad: '' } });
ok(js("document.getElementById('pk_save_kod').getAttribute('aria-invalid')") === 'true' && js("document.activeElement&&document.activeElement.id") === 'pk_save_kod', 'kod çakışması: kod alanı işaretli ve odakta');
ok(/farklı bir kod verin/.test(txt('pkSaveResult')), 'kod çakışması: "farklı bir kod verin" metni');
js("var k=document.getElementById('pk_save_kod');k.value='PK-020';mstPkSaveEdited('kod')");
ok(js("document.getElementById('pk_save_kod').getAttribute('aria-invalid')") === null, 'kod değişince işaret kalktı');

// 7. Üst yüzey seçimi gönderilir; genel hata
js("chApplyPreset('U');var t=document.getElementById('pk_save_top_ref');t.value='left'");
s = send();
ok(s.q && s.q.channel_top_ref === 'left', 'üst yüzey seçimi channel_top_ref olarak gönderildi');
reply({ ok: false, neden: 'Model kaydı yazılamadı.' });
ok(/KAYDEDİLMEDİ/.test(txt('pkSaveResult')) && /Model kaydı yazılamadı/.test(txt('pkSaveResult')) && js("document.getElementById('pkSaveBtn').disabled") === false, 'genel hata: neden görünür, düğme yeniden etkin');
reply(null);
ok(/Kayıt yanıtı okunamadı/.test(txt('pkSaveResult')), 'boş yanıtta arayüz kırılmaz');
D.calls.splice(0);

// 8. Mevcut girdiler bozulmadı (yeni alanlar create_channel_precast / create_flat_precast'e girmez)
js("document.getElementById('channel_fw_inner').checked=true;document.getElementById('channel_fw_ledge').checked=true;document.getElementById('channel_seat_left_m').value='0.15';document.getElementById('channel_total_width_m').value='1.20';chApplyPreset('U')");
ok(sendCh() === ch0, 'create_channel_precast girdisi ilk gönderimle birebir aynı');
const pd1 = sendPD();
const strip = (x) => { const o = JSON.parse(x); delete o.precast_type_library; delete o.pd_layout_rows; return JSON.stringify(o); };
ok(pd1 && strip(pd1) === strip(pd0) && JSON.parse(pd0).precast_type_library !== undefined, 'create_flat_precast girdisi (kütüphane ve yerleşim satırları dışında; PK satırına tip atandı) aynı');

// 9. 2b listesi: tip adı / revizyon / kullanım; "Tip kütüphanesine ekle"
const secL = q.section;
const cat = { ok: true, tipler: [
  { kod: 'PK-008', kaynak: 'kütüphane', kaynak_ad: 'kütüphane', uid: 'pt_pk_new', beton: 'C30/37', adet_modelde: 3, section: secL, on_ayar: 'L', eski_kayit: false, toplam_genislik_m: 1, toplam_yukseklik_m: 0.8, taban_m: 0.2, gecerli: true, hatalar: [], title: 'L Kanal 1000', pk_rev: 2, created_at: '2026-11-10T09:00:00Z', kullanim: [{ yapi: 'ANO-01', adet: 2 }, { yapi: 'RIHTIM-01', adet: 1 }] },
  { kod: 'KANAL_PREKASTI_L', kaynak: 'model', kaynak_ad: 'modelde kullanılan', uid: null, beton: 'C35/45', adet_modelde: 1, section: secL, on_ayar: 'L', eski_kayit: false, toplam_genislik_m: 1, toplam_yukseklik_m: 0.8, taban_m: 0.2, gecerli: true, hatalar: [], kaynak_pid: 4321, kullanim: [{ yapi: 'BD-01', adet: 1 }] },
  { kod: 'PK-X', kaynak: 'model', kaynak_ad: 'modelde kullanılan', uid: null, beton: 'C30/37', adet_modelde: 1, section: secL, on_ayar: 'L', eski_kayit: false, toplam_genislik_m: 1, toplam_yukseklik_m: 0.8, taban_m: 0.2, gecerli: true, hatalar: [] }] };
js('mstPkCatalog(' + JSON.stringify(cat) + ')');
const item = (i) => "document.querySelectorAll('#pkPickList .pk-item')[" + i + ']';
const it0 = js(item(0) + '.textContent');
ok(/Tip adı: L Kanal 1000 · revizyon 2 · oluşturma 10\.11\.2026 · kullanım \(modeldeki PK'lar\): ANO-01 2 adet; RIHTIM-01 1 adet/.test(it0), '2b satırı: tip adı, revizyon, tarih, yapı bazlı kullanım');
ok(!/Tip kütüphanesine ekle/.test(it0) && /Yerleşimde kullan/.test(it0), 'kütüphane satırında yalnız "Yerleşimde kullan"');
ok(/Yalnız modelde var/.test(js(item(1) + '.textContent')) && click(item(1), 'Tip kütüphanesine ekle') === 'tik', 'modeldeki satırda "Tip kütüphanesine ekle"');
ok(js("document.getElementById('pkAddKod').value") === 'PK-009' && js("document.getElementById('pkAddAd').value") === 'L Kanal 1000', 'kod / ad önerildi (PK-009, L Kanal 1000)');
ok(click(item(2), 'Tip kütüphanesine ekle') === 'pasif' && /kimlik bilgisi yok/.test(js(item(2) + '.textContent')), 'kaynak_pid yoksa düğme pasif + neden');
js("var k=document.getElementById('pkAddKod');k.value='PK-030';k.oninput=null;mstPkSave.add.kod=k.value");
ok(click(item(1), 'Tip kütüphanesine kaydet') === 'tik', 'ekleme kaydı gönderildi');
c = take('pk_type_save'); q2 = c.length === 1 ? JSON.parse(c[0][1]) : {};
ok(q2.kaynak_pid === 4321 && q2.kod === 'PK-030' && q2.ad === 'L Kanal 1000' && q2.karar === null && q2.section && q2.section.preset === 'L' && q2.concrete === 'C35/45' && Array.isArray(q2.kutuphane), '2b isteği: kaynak_pid, kod, ad, section, concrete, karar null, kutuphane');
reply({ ok: false, durum: 'kod_cakisma', mevcut: { uid: 'pt_pk_1', kod: 'PK-030', ad: 'X' } });
ok(js("document.getElementById('pkAddKod').getAttribute('aria-invalid')") === 'true' && /farklı bir kod verin/.test(txt('pkPickSave')) && txt('pkSaveResult') === '', '2b kod çakışması: satırdaki kod alanı işaretli, sonuç 2b panelinde');
reply({ ok: true, durum: 'kaydedildi', tip: { uid: 'pt_pk_m', kod: 'PK-031', ad: 'L Kanal 1000' }, kutuphane_json: JSON.stringify(libB.concat([{ uid: 'pt_pk_m', family: 'PK', name: 'PK-031', concrete: 'C35/45', section: secL }])) });
ok(js('mstPkSave.add') === null && /KAYDEDİLDİ/.test(txt('pkPickSave')) && take('pk_type_catalog').length === 1, '2b kaydedildi: düzenleyici kapandı, liste yeniden istendi');

// 10. "+ Yeni PK Kanal Tipi Oluştur" → forma; eski U kartı açılmaz
const nPK = js("typesOfFamily('PK').length");
D.doc._scrolled.splice(0);
ok(click("document.getElementById('precast')", 'Yeni PK Kanal Tipi Oluştur') === 'tik', '"+ Yeni PK Kanal Tipi Oluştur" düğmesi var');
ok(js("typesOfFamily('PK').length") === nPK, 'yeni eski U kaydı eklenmedi');
ok(D.doc._scrolled.indexOf('channelPrecastForm') >= 0 && js('document.activeElement.id') === 'channel_total_width_m', 'Kanal Prekastı formuna gidildi, toplam genişlik odakta');
ok(!/addPrecastType\('PK'\)/.test(js("document.getElementById('precast').innerHTML")), 'sayfada addPrecastType(\'PK\') düğmesi kalmadı');

// 11. Tip kartı: kesitli PK özeti; eski kesitsiz U kaydı düzenlenebilir
js('renderPrecastTypes()');
const lt = js("document.getElementById('precastTypeLibrary').textContent");
ok(/L kesit · toplam genişlik 1,000 m × yükseklik 0,800 m · taban 0,200 m/.test(lt) && /Tip adı: L Kanal Eski · revizyon 1 · oluşturma 10\.11\.2026/.test(lt), 'kesitli kart: ön ayar, ölçüler, tip adı, revizyon, tarih');
ok(/Kesit Kanal Prekastı formundan tasarlanır/.test(lt), 'kesitli kart: form notu');
const lh = js("document.getElementById('precastTypeLibrary').innerHTML");
ok(/onchange="setPT\('pt_pk_1','inner_width',this.value\)"/.test(lh) && /onchange="setPT\('pt_pk_1','wall',this.value\)"/.test(lh), 'eski U kaydı (pt_pk_1) kartta düzenlenebilir');
ok(!/setPT\('pt_pk_old','inner_width'/.test(lh), 'kesitli kayıtta eski U alanı düzenlenmez');

ok(D.alerts.length === 0, 'alert yok (' + D.alerts.join(' | ') + ')');
ok(D.errors.length === 0, 'console.error / zamanlayıcı hatası yok (' + D.errors.join(' | ') + ')');
console.log(fail ? 'SONUÇ: ' + fail + ' HATA' : 'SONUÇ: hepsi geçti');
process.exit(fail ? 1 : 0);
