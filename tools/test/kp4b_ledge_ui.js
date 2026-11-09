// ADR-0515-K2 karar 16 arayüz: döşemede sol / sağ taban üstü (ledge) Açık / Dolu seçimi — Kanal Prekastı formu ve kesitli PK tip
// kartı (sahte DOM, SketchUp DIŞINDA). Yalnız JS mantığını sınar: varsayılanda deck_ledge_* anahtarı yok, seçimde open / fill,
// varsayılan metni channel_section.rb mst_ch_deck_ledges kuralıyla (U, L, UU açık; K, OZEL dolu), tip kaydı ve kayda giden kütüphane.
// Görünüm, gerçek HtmlDialog ve döşeme geometrisi kanıtlanmaz.
// Kullanım: node tools/test/kp4b_ledge_ui.js   (çıkış kodu 0 = geçti)
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
const setv = (id, v) => js("document.getElementById('" + id + "').value=" + JSON.stringify(v));
const own = (o, k) => Object.prototype.hasOwnProperty.call(o, k);
const sendForm = () => { js('createChannelPrecast()'); const c = take('create_channel_precast'); return c.length === 1 ? JSON.parse(c[0][1]) : null; };

ok(loadErrors.length === 0, 'sayfa yüklendi (' + loadErrors.join(' | ') + ')');
js('updateChannelPrecastUI()');
D.calls.splice(0); D.errors.splice(0); D.alerts.splice(0);
const opt0 = (id) => js("document.getElementById('" + id + "').options[0].textContent");

// 1. Varsayılan metin kuralı (channel_section.rb:23, :332-335)
ok(['U', 'L', 'UU'].every((p) => js("chDeckDefault('" + p + "')") === 'open') && ['K', 'OZEL', 'X', ''].every((p) => js("chDeckDefault('" + p + "')") === 'fill'), 'varsayılan: U/L/UU açık, K/OZEL (ve bilinmeyen → OZEL) dolu');
ok(['open', 'acik', 'Açık'].every((v) => js('chDeckFlag(' + JSON.stringify(v) + ')') === 'open') && ['fill', 'DOLU'].every((v) => js('chDeckFlag(' + JSON.stringify(v) + ')') === 'fill') && js("chDeckFlag('xyz')") === '', 'chDeckFlag mst_ch_deck_flag ile aynı');

// 2. Form: varsayılanda anahtar yok
ok(js("document.getElementById('channel_deck_ledge_left').value") === '' && js("document.getElementById('channel_deck_ledge_right').value") === '', 'form: iki seçim varsayılanda');
ok(/ön ayara göre: Açık/.test(opt0('channel_deck_ledge_left')), 'form U: varsayılan metni Açık');
let d = sendForm();
ok(d && d.section && !own(d.section, 'deck_ledge_left') && !own(d.section, 'deck_ledge_right'), 'form varsayılan: section içinde deck_ledge_* yok');
const keys0 = d ? JSON.stringify(Object.keys(d.section)) : '';

js("chApplyPreset('K')");
ok(/ön ayara göre: Dolu/.test(opt0('channel_deck_ledge_right')), 'form K: varsayılan metni Dolu');
js("chApplyPreset('U')");
ok(/ön ayara göre: Açık/.test(opt0('channel_deck_ledge_right')), 'form U\'ya dönüş: Açık');
ok(/sol 0,000 m · sağ 0,000 m/.test(js("document.getElementById('channelDeckLedgeNote').textContent")), 'form U: taban üstü genişlikleri 0 m (etkisiz notu)');

// 3. Form: seçim open / fill
setv('channel_deck_ledge_left', 'fill'); setv('channel_deck_ledge_right', 'open');
d = sendForm();
ok(d && d.section.deck_ledge_left === 'fill' && d.section.deck_ledge_right === 'open', 'form seçim: deck_ledge_left=fill, deck_ledge_right=open');
ok(d && d.section.preset === 'U' && d.section.left.on === true, 'form seçim: kesit alanları değişmedi');
setv('channel_deck_ledge_left', ''); setv('channel_deck_ledge_right', '');
d = sendForm();
ok(d && JSON.stringify(Object.keys(d.section)) === keys0, 'varsayılana dönüş: anahtar listesi ilk gönderimle aynı');

// 4. Yan çıkıntı Yok: seçim etkin kalır (ledge = en dış açık çıkıntının dışı), elle değişiklik → OZEL → Dolu
js("document.getElementById('channel_left_on').checked=false;chPartToggled()");
ok(js("document.getElementById('channel_deck_ledge_left').disabled") === false, 'sol çıkıntı Yok: sol ledge seçimi pasif değil');
ok(/ön ayara göre: Dolu/.test(opt0('channel_deck_ledge_left')), 'elle Var/Yok → Özel: varsayılan metni Dolu');
ok(/sol 1,000 m · sağ 0,000 m/.test(js("document.getElementById('channelDeckLedgeNote').textContent")), 'sol çıkıntı Yok: sol taban üstü 1,000 m');
js("document.getElementById('channel_left_on').checked=true;chApplyPreset('U')");

// 5. Tip kartı: section nesnesi
const secL = { v: 1, preset: 'L', total_width_m: 1.2, base_m: 0.2, left: { on: false, width_m: 0.2, height_m: 0.6, offset_m: 0 }, mid: { on: false, width_m: 0.15, height_m: 0.3, offset_m: 0.525 }, right: { on: true, width_m: 0.2, height_m: 0.6, offset_m: 0 } };
js("precastTypes.push({uid:'pt_pk_l',family:'PK',name:'PK-L',concrete:'C30/37',zz_bilinmeyen:7,section:" + JSON.stringify(secL) + "});renderPrecastTypes();refreshAllPDRowOptions()");
let lt = js("document.getElementById('precastTypeLibrary').textContent");
ok(/Döşemede sol taban üstü \(ledge\)/.test(lt) && /Varsayılan \(ön ayara göre: Açık\)/.test(lt), 'tip kartı L: seçim ve Açık varsayılanı görünür');
ok((lt.match(/Döşemede sol taban üstü/g) || []).length === 1, 'yalnız kesitli PK kartında seçim var (kesitsiz PK-01\'de yok)');
const before = js("JSON.stringify(typeByUid('pt_pk_l'))");
js("mstPkSetDeck('pt_pk_l','left','')");
ok(js("JSON.stringify(typeByUid('pt_pk_l'))") === before, 'varsayılan seçimi kaydı değiştirmez');
js("mstPkSetDeck('pt_pk_l','right','fill')");
ok(js("typeByUid('pt_pk_l').section.deck_ledge_right") === 'fill' && !own(JSON.parse(js("JSON.stringify(typeByUid('pt_pk_l').section)")), 'deck_ledge_left'), 'tip: section.deck_ledge_right=fill, sol yazılmadı');
let sv = JSON.parse(js("JSON.stringify(mstPkLibraryForSave(precastTypes).filter(function(t){return t.uid==='pt_pk_l'})[0])"));
ok(sv.section.deck_ledge_right === 'fill' && sv.zz_bilinmeyen === 7, 'kayda giden kütüphanede seçim ve bilinmeyen alan var');
js('renderPrecastTypes()');
ok(/value="fill" selected/.test(js("document.getElementById('precastTypeLibrary').innerHTML")), 'yeniden çizimde kayıtlı seçim seçili');
js("mstPkSetDeck('pt_pk_l','right','')");
ok(!own(JSON.parse(js("JSON.stringify(typeByUid('pt_pk_l').section)")), 'deck_ledge_right'), 'varsayılana dönünce anahtar silindi');

// 6. Tip kartı: channel_section_json metni (K) — yalnız değişince yeniden yazılır
const secK = Object.assign({}, secL, { preset: 'K' });
const rawK = JSON.stringify(secK, null, 1);
js("precastTypes.push({uid:'pt_pk_k',family:'PK',name:'PK-K',concrete:'C30/37',channel_section_json:" + JSON.stringify(rawK) + "});renderPrecastTypes()");
ok(/Varsayılan \(ön ayara göre: Dolu\)/.test(js("document.getElementById('precastTypeLibrary').textContent")), 'tip kartı K: Dolu varsayılanı');
js("mstPkSetDeck('pt_pk_k','left','')");
ok(js("typeByUid('pt_pk_k').channel_section_json") === rawK, 'JSON metni: varsayılanda metin birebir aynı');
js("mstPkSetDeck('pt_pk_k','left','open')");
ok(JSON.parse(js("typeByUid('pt_pk_k').channel_section_json")).deck_ledge_left === 'open', 'JSON metni: deck_ledge_left=open yazıldı');
ok(!own(JSON.parse(js("JSON.stringify(typeByUid('pt_pk_1'))")), 'deck_ledge_left'), 'kesitsiz eski kayda anahtar eklenmedi');

ok(D.errors.length === 0, 'console.error / zamanlayıcı hatası yok (' + D.errors.join(' | ') + ')');
console.log(fail ? 'SONUÇ: ' + fail + ' HATA' : 'SONUÇ: hepsi geçti');
process.exit(fail ? 1 : 0);
