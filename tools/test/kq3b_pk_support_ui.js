// ADR-0515-K3 P3 arayüz: PK kot yöntemi SUPPORT (Alt kottan yerleştir — BK üstüne otur). Sahte DOM, SketchUp DIŞINDA.
// Yalnız JS mantığını sınar: SUPPORT gönderimi (create_flat_precast / kn_place / pk_elevation_preview), TOP girdisinin
// eskisiyle aynı kalması, seçenek ve açıklama metinleri, SUPPORT önizleme metni. Önizleme payload'ları main.rb
// mst_pk_elevation_preview biçiminde elle yazıldı (SUPPORT yanıtında bk_ust_m / bk_ust_uyari varsayıldı).
// Kullanım: node tools/test/kq3b_pk_support_ui.js   (çıkış kodu 0 = geçti)
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
const setv = (id, v) => js("document.getElementById('" + id + "').value=" + JSON.stringify(v));
const txt = (id) => js("document.getElementById('" + id + "').textContent");

ok(loadErrors.length === 0, 'sayfa yüklendi (' + loadErrors.join(' | ') + ')');
const opts = js("Array.prototype.map.call(document.getElementById('pk_elev_mode').options,function(o){return o.value+'|'+o.textContent}).join('\\n')");
ok(/TOP\|Üst kottan yerleştir \(PD üstüne hizalı\)/.test(opts), 'TOP seçeneği: Üst kottan yerleştir (PD üstüne hizalı)');
ok(/SUPPORT\|Alt kottan yerleştir — BK üstüne otur \(BK kotu değişince izler\)/.test(opts), 'SUPPORT seçeneği talimat diliyle');
ok(/POCKET\|BK kanal cebine oturt/.test(opts) && /MANUAL\|Manuel kot/.test(opts), 'POCKET / MANUAL seçenekleri duruyor');
ok(js("document.getElementById('pk_elev_mode').value") === 'TOP', 'varsayılan yöntem TOP');
ok(/en kalın PD\/PDÖ\/PV üstüne hizalanır/.test(txt('pkElevHelp')), 'TOP açıklama satırı görünür');
ok(/Prekast Yerleşimi 2c/.test(txt('channelElevMethodNote')), 'Kanal Prekastı formunda 2c notu var');
D.calls.splice(0); D.errors.splice(0); D.alerts.splice(0);

// 1. TOP: eski gönderim
js('createPD()');
let c = take('create_flat_precast');
const topD = c.length === 1 ? JSON.parse(c[0][1]) : {};
ok(c.length === 1 && !Object.keys(topD).some((k) => /^pk_elevation/.test(k)), 'TOP: create_flat_precast girdisinde pk_elevation_* yok');
js('mstPkKnPlace()');
c = take('kn_place');
ok(c.length === 1 && c[0].length === 1, 'TOP: sketchup.kn_place() argümansız');

// 2. SUPPORT gönderimi
setv('pk_elev_mode', 'SUPPORT'); js('mstPkElevChanged()');
ok(/alt yüzü iki BK üstüne oturur/.test(txt('pkElevHelp')) && /BK kotu değişince PK alt kotu BK üstünü izler/.test(txt('pkElevHelp')), 'SUPPORT açıklama satırı');
ok(js("document.getElementById('pk_elev_ref_m').disabled") === true, 'SUPPORT: referans kotu alanı devre dışı');
c = take('pk_elevation_preview');
let pv = c.length === 1 ? JSON.parse(c[0][1]) : {};
ok(c.length === 1 && pv.elevation_mode === 'SUPPORT' && !('elevation_ref_m' in pv) && !('elevation_ref_face' in pv), 'SUPPORT: önizleme {elevation_mode:SUPPORT} (ref/yüz yok)');
js('createPD()');
c = take('create_flat_precast');
const d = c.length === 1 ? JSON.parse(c[0][1]) : {};
ok(d.pk_elevation_mode === 'SUPPORT' && !('pk_elevation_ref_m' in d) && !('pk_elevation_ref_face' in d), 'SUPPORT: create_flat_precast pk_elevation_mode=SUPPORT (ref/yüz yok)');
ok(JSON.stringify(Object.keys(d).filter((k) => k !== 'pk_elevation_mode')) === JSON.stringify(Object.keys(topD)), 'SUPPORT: diğer anahtarlar TOP ile aynı');
js('mstPkKnPlace()');
c = take('kn_place');
ok(c.length === 1 && c[0][1] === JSON.stringify({ elevation_mode: 'SUPPORT' }), 'SUPPORT: kn_place JSON {elevation_mode:SUPPORT}');
ok(D.alerts.splice(0).length === 0, 'SUPPORT: uyarı penceresi açılmadı');

// 3. SUPPORT önizleme metni
const base = { ok: true, neden: null, mod: 'SUPPORT', yuz: 'TOP', referans_m: null, alt_kot_m: 2.6, ust_kot_m: 3.4, referans_ust_kot_m: 3.4, ust_yuzey: null, toplam_yukseklik_m: 0.8, referans_yuksekligi_m: 0.8, cep_tabani_m: null, karsi_cep_tabani_m: null, taraf: null, pd_ust_m: null };
js('mstPkElevation(' + JSON.stringify(Object.assign({}, base, { bk_ust_m: 2.6, bk_ust_uyari: null, uyarilar: [] })) + ')');
let t = txt('pkElevInfo');
ok(/Alt kottan yerleştirme \(BK üstüne otur\)/.test(t) && /KOT HESAPLANDI/.test(t), 'SUPPORT başlığı ve KOT HESAPLANDI');
ok(/Alt kot 2,600 m · üst kot 3,400 m · toplam yükseklik 0,800 m/.test(t), 'alt / üst kot virgüllü ve birimli');
ok(/Alt kot = BK üstü 2,600 m \(model geometrisi; BK kotu değişince izler\)/.test(t), 'kaynak: BK üstü (model geometrisi)');
const UY = 'iki BK üst kotu farklı (2,600 / 2,650 m); BK üst kotu belirlenemedi';   // kesme işareti yok: sahte DOM &#39; çözümü sınanmaz
js('mstPkElevation(' + JSON.stringify({ ok: false, neden: 'BK üst kotu belirlenemedi.', mod: 'SUPPORT', uyarilar: [], bk_ust_m: null, bk_ust_uyari: UY, cep_tabani_m: null }) + ')');
t = txt('pkElevInfo');
ok(/KOT HESAPLANAMADI/.test(t) && t.indexOf(UY) >= 0, 'iki BK üstü farklı: KOT HESAPLANAMADI + uyarı metni');
js('mstPkElevation(' + JSON.stringify(Object.assign({}, base, { bk_ust_m: 2.6, bk_ust_uyari: UY, uyarilar: [UY] })) + ')');
t = txt('pkElevInfo');
ok(/UYARI/.test(t) && t.split(UY).length === 2, 'uyarı hem uyarilar hem bk_ust_uyari içinde: bir kez gösterilir');

// 4. TOP'a dönünce gönderim birebir
setv('pk_elev_mode', 'TOP'); js('mstPkElevSync()'); D.calls.splice(0);
js('createPD()');
c = take('create_flat_precast');
ok(c.length === 1 && c[0][1] === JSON.stringify(topD), 'TOP: create_flat_precast girdisi ilk TOP girdisiyle birebir');

ok(D.errors.length === 0, 'console.error / zamanlayıcı hatası yok (' + D.errors.join(' | ') + ')');
console.log(fail ? 'SONUÇ: ' + fail + ' HATA' : 'SONUÇ: hepsi geçti');
process.exit(fail ? 1 : 0);
