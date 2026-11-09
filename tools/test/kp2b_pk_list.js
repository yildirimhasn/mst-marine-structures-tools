// ADR-0515-K2 P2 arayüz: Prekast Yerleşimi PK seçim listesi + cep uyumu + karar 13 kayıt eşitlemesi (sahte DOM, SketchUp DIŞINDA).
// Yalnız JS mantığını sınar (callback adları, iki adımlı ref_top_m, liste / etiket / neden metni, kayıt kopyası). Görünüm ve
// gerçek HtmlDialog davranışı kanıtlanmaz. Payload'lar main.rb mst_pk_type_catalog / mst_pk_pocket_candidates biçiminde elle yazıldı.
// Kullanım: node tools/test/kp2b_pk_list.js   (çıkış kodu 0 = geçti)
'use strict';
const path = require('path');
const { loadPage } = require('./u_fakedom');
const dir = path.join(__dirname, '..', '..', 'src', 'marine_structures_tools');
const { D, loadErrors } = loadPage(dir);
const vm = require('vm');
const js = (c) => vm.runInContext(c, D.ctx);
let fail = 0;
const ok = (c, m) => { if (c) console.log('OK   ' + m); else { fail++; console.log('HATA ' + m); } };

ok(loadErrors.length === 0, 'sayfa yüklendi (' + loadErrors.join(' | ') + ')');
ok(D.calls.some((c) => c[0] === 'pk_type_catalog'), 'açılışta sketchup.pk_type_catalog çağrıldı');
D.calls.splice(0); D.errors.splice(0);

const secU = { v: 1, preset: 'U', total_width_m: 1.2, base_m: 0.2, left: { on: true, width_m: 0.2, height_m: 0.6, offset_m: 0 }, mid: { on: false, width_m: 0.15, height_m: 0.3, offset_m: 0.525 }, right: { on: true, width_m: 0.2, height_m: 0.6, offset_m: 0 } };
const secL = { v: 1, preset: 'L', total_width_m: 1.0, base_m: 0.25, left: { on: false, width_m: 0.2, height_m: 0.6, offset_m: 0 }, mid: { on: false, width_m: 0.15, height_m: 0.3, offset_m: 0.4 }, right: { on: true, width_m: 0.2, height_m: 0.5, offset_m: 0 } };
const cat = { ok: true, neden: null, tipler: [
  { kod: 'PK-01', precast_type_id: 'PK-01', kaynak: 'kütüphane', kaynak_ad: 'kütüphane', uid: 'pt_pk_1', beton: 'C30/37', adet_modelde: 0, section: secU, on_ayar: 'U', eski_kayit: true, toplam_genislik_m: 1.2, toplam_yukseklik_m: 0.8, taban_m: 0.2, cikintilar: [], cikinti_ozet: 'Sol 0,200 × 0,600 m (ofset 0,000); Sağ 0,200 × 0,600 m (ofset 0,000)', kesit_alani_m2: 0.48, gecerli: true, hatalar: [], profil: [] },
  { kod: 'PK-L1', precast_type_id: 'PK-L1', kaynak: 'model', kaynak_ad: 'modelde kullanılan', uid: null, beton: 'C30/37', adet_modelde: 2, section: secL, on_ayar: 'L', eski_kayit: false, toplam_genislik_m: 1.0, toplam_yukseklik_m: 0.75, taban_m: 0.25, cikintilar: [], cikinti_ozet: '', kesit_alani_m2: 0.35, gecerli: true, hatalar: [], profil: [] }] };
const mainSvgBefore = js("document.getElementById('channelSectionSvg').innerHTML");
js('mstPkCatalog(' + JSON.stringify(cat) + ')');
ok(js("document.querySelectorAll('#pkPickList .pk-item').length") === 2, 'listede 2 PK satırı');
ok(js("document.getElementById('pkMini0').querySelectorAll('polygon').length") === 1, 'küçük kesit önizlemesi çizildi (PK-01)');
ok(js("document.getElementById('pkMini1').querySelectorAll('polygon').length") === 1, 'küçük kesit önizlemesi çizildi (PK-L1)');
ok(js("document.getElementById('channelSectionSvg').innerHTML") === mainSvgBefore, 'Kanal Prekastı ana önizlemesi değişmedi');
const txt = js("document.getElementById('pkPickList').textContent");
ok(/kütüphane/.test(txt) && /modelde kullanılan · modelde 2 adet/.test(txt), 'kaynak bilgisi görünür');
ok(/Toplam genişlik 1,200 m · toplam yükseklik 0,800 m · taban 0,200 m/.test(txt), 'ana ölçüler virgüllü ve birimli');
ok(/U kesit \(U\)/.test(txt) && /L kesit \(L\)/.test(txt), 'ön ayar görünür');

// cep uyumu: 1. adım {} → 2. adım ref_top_m = cep tabanı + cep derinliği + en kalın PD/PDÖ/PV (varsayılan satırlar 0,30)
js('mstPkCheckPockets()');
let c = D.calls.splice(0).filter((x) => x[0] === 'pk_pocket_candidates');
ok(c.length === 1 && c[0][1] === '{}', '1. adım pk_pocket_candidates("{}")');
const pair = (ref, src, ads) => ({ aciklik: 'BK-01 → BK-02', sol_bk: 'BK-01', sag_bk: 'BK-02', taraf: 'start', taraf_ad: 'başlangıç', cep_genisligi_m: 1.24, cep_derinligi_m: 0.5, cep_tabani_m: 2.0, karsi_cep_tabani_m: 2.0, derz_m: 0.02, derz_kaynagi: 'varsayılan', referans_ust_m: ref, referans_kaynagi: src, beklenen: { dis_genislik_m: 1.2, toplam_yukseklik_m: ref == null ? null : ref - 2.0 }, uyarilar: ref == null ? ['referans üst kotu belirlenemedi (açıklıkta PD yok, referans üst girilmedi); toplam yükseklik denetlenemedi'] : [], cep_uygun: ref != null, adaylar: ads });
js('mstPkCandidates(' + JSON.stringify({ ok: true, neden: null, ciftler: [pair(null, null, [])] }) + ')');
c = D.calls.splice(0).filter((x) => x[0] === 'pk_pocket_candidates');
const sent = c.length === 1 ? JSON.parse(c[0][1]) : {};
ok(c.length === 1 && Math.abs(sent.ref_top_m - 2.8) < 1e-9, '2. adım ref_top_m = 2,0 + 0,5 + 0,30 = 2,8 (gönderilen ' + sent.ref_top_m + ')');
const ads = [
  { kod: 'PK-01', kaynak: 'kütüphane', uyumlu: true, nedenler: [], secilecek: true },
  { kod: 'PK-L1', kaynak: 'model', uyumlu: false, nedenler: ['dış genişlik 1,200 ≠ 1,000 m', 'toplam yükseklik 0,800 ≠ 0,750 m'], secilecek: false }];
js('mstPkCandidates(' + JSON.stringify({ ok: true, neden: null, ciftler: [pair(2.8, 'girdi', ads)] }) + ')');
ok(D.calls.splice(0).filter((x) => x[0] === 'pk_pocket_candidates').length === 0, 'üçüncü çağrı yok (döngü yok)');
const it0 = js("document.querySelectorAll('#pkPickList .pk-item')[0].textContent"), it1 = js("document.querySelectorAll('#pkPickList .pk-item')[1].textContent");
ok(/UYUMLU/.test(it0) && /OTOMATİK YERLEŞTİRMENİN SEÇTİĞİ/.test(it0), 'PK-01 uyumlu + otomatik seçim etiketi');
ok(/UYUMSUZ/.test(it1) && /dış genişlik 1,200 ≠ 1,000 m/.test(it1), 'PK-L1 uyumsuz + Türkçe neden');
const pinfo = js("document.getElementById('pkPocketInfo').textContent");
ok(/BK üstü 2,500 m/.test(pinfo) && /VARSAYILAN/.test(pinfo), 'referans üst kaynağı ve varsayılan derz işareti görünür');

// seçim: kütüphane tipi ilk PK satırına atanır; model tipinde düğme yok
js("mstPkUseType('pt_pk_1')");
ok(js("Array.prototype.slice.call(document.querySelectorAll('.pd-layout-row')).filter(function(r){return r.querySelector('.pd-family').value==='PK'})[0].querySelector('.pd-type').value") === 'pt_pk_1', 'PK satırına tip atandı');
ok(js("document.querySelectorAll('#pkPickList .pk-item')[1].querySelectorAll('button').length") === 0, 'yalnız modeldeki tipte yerleşim düğmesi yok');

// karar 13: kayıt kopyasında eski alanlar kesitle eşit; bilinmeyen alan korunur; kesitsiz kayıt aynı nesne
const lib = js("(function(){var a=[{uid:'u1',family:'PK',name:'PK-X',inner_width:9,inner_depth:9,base:9,wall:9,concrete:'C30/37',section:" + JSON.stringify(secL) + ",ozel_alan:'kalsin'},{uid:'u2',family:'PK',name:'PK-Y',inner_width:.8,inner_depth:.6,base:.2,wall:.2},{uid:'u3',family:'PK',name:'PK-Z',inner_width:1,inner_depth:1,base:1,wall:1,section:" + JSON.stringify(secU) + "}];var s=mstPkLibraryForSave(a);return {s:s,same:s[1]===a[1],orig:a[0].inner_width}})()");
ok(lib.s[0].inner_width === 0 && lib.s[0].wall === 0 && lib.s[0].ozel_alan === 'kalsin' && lib.orig === 9, 'U dışı kesit: eski alanlar 0, bilinmeyen alan korundu, bellekteki kayıt değişmedi');
ok(lib.same, 'kesitsiz eski kayıt aynen gider');
ok(Math.abs(lib.s[2].inner_width - 0.8) < 1e-9 && lib.s[2].inner_depth === 0.6 && lib.s[2].base === 0.2 && lib.s[2].wall === 0.2, 'U-eşdeğeri kesit: eski alanlar uDims');
ok(js("typeWidth({family:'PK',section:" + JSON.stringify(secL) + "})") === 1.0, 'kesitli PK genişliği toplam genişlik');
ok(js("typeWidth({family:'PK',inner_width:.8,wall:.2})") === (0.8 + 2 * 0.2), 'eski PK genişliği değişmedi (eski formülle birebir)');

ok(D.errors.length === 0, 'console.error / zamanlayıcı hatası yok (' + D.errors.join(' | ') + ')');
console.log(fail ? 'SONUÇ: ' + fail + ' HATA' : 'SONUÇ: hepsi geçti');
process.exit(fail ? 1 : 0);
