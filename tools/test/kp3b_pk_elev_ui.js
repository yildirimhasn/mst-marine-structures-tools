// ADR-0515-K2 P3 arayüz: PK kot yöntemi (TOP / POCKET / MANUAL), salt okuma kot önizlemesi, tipte üst yüzey çıkıntısı
// (channel_top_ref), cep uyumunda bk_ust_m (sahte DOM, SketchUp DIŞINDA). Yalnız JS mantığını sınar (gönderilen alanlar, TOP'ta
// eski girdinin aynen kalması, metinler). Görünüm ve gerçek HtmlDialog davranışı kanıtlanmaz. Payload'lar main.rb
// mst_pk_elevation_preview / mst_pk_pocket_candidates biçiminde elle yazıldı.
// Kullanım: node tools/test/kp3b_pk_elev_ui.js   (çıkış kodu 0 = geçti)
'use strict';
const path = require('path');
const { loadPage } = require('./u_fakedom');
const dir = path.join(__dirname, '..', '..', 'src', 'marine_structures_tools');
const { D, loadErrors } = loadPage(dir);
const vm = require('vm');
const js = (c) => vm.runInContext(c, D.ctx);
let fail = 0;
const ok = (c, m) => { if (c) console.log('OK   ' + m); else { fail++; console.log('HATA ' + m); } };
const near = (a, b) => typeof a === 'number' && Math.abs(a - b) < 1e-9;
const take = (name) => D.calls.splice(0).filter((x) => x[0] === name);
const setv = (id, v) => js("document.getElementById('" + id + "').value=" + JSON.stringify(v));

ok(loadErrors.length === 0, 'sayfa yüklendi (' + loadErrors.join(' | ') + ')');
ok(js("!!document.getElementById('pkElevPanel')"), '2c kot yöntemi paneli var');
ok(js("document.getElementById('pk_elev_mode').value") === 'TOP', 'varsayılan yöntem Üst kot (TOP)');
ok(js("document.getElementById('pk_elev_ref_m').disabled") === true, 'TOP: referans kotu alanı devre dışı');
D.calls.splice(0); D.errors.splice(0); D.alerts.splice(0);

// 1. TOP: create_flat_precast ve kn_place girdisi eskisiyle aynı (pk_elevation_* yok; kn_place argümansız)
js('createPD()');
let c = take('create_flat_precast');
const topRaw = c.length === 1 ? c[0][1] : '';
const topD = topRaw ? JSON.parse(topRaw) : {};
ok(c.length === 1 && !Object.keys(topD).some((k) => /^pk_elevation/.test(k)), 'TOP: create_flat_precast girdisinde pk_elevation_* anahtarı yok');
js('mstPkKnPlace()');
c = take('kn_place');
ok(c.length === 1 && c[0].length === 1, 'TOP: sketchup.kn_place() argümansız (eski çağrı)');

// 2. POCKET
setv('pk_elev_mode', 'POCKET'); js('mstPkElevChanged()');
c = take('pk_elevation_preview');
let pv = c.length === 1 ? JSON.parse(c[0][1]) : {};
ok(c.length === 1 && pv.elevation_mode === 'POCKET' && pv.kod === 'PK-01' && !('section' in pv) && !('ref_top_m' in pv) && !('elevation_ref_m' in pv), 'POCKET: önizleme çağrıldı (eski PK kaydı → kod, ref_top_m yok)');
ok(/okunuyor/.test(js("document.getElementById('pkElevStatus').textContent")), 'önizleme bekleme durumu görünür');
js('createPD()');
c = take('create_flat_precast');
let d = c.length === 1 ? JSON.parse(c[0][1]) : {};
ok(d.pk_elevation_mode === 'POCKET' && !('pk_elevation_ref_m' in d) && !('pk_elevation_ref_face' in d), 'POCKET: create_flat_precast pk_elevation_mode=POCKET (ref/yüz yok)');
js('mstPkKnPlace()');
c = take('kn_place');
ok(c.length === 1 && c[0][1] === JSON.stringify({ elevation_mode: 'POCKET' }), 'POCKET: kn_place JSON {elevation_mode:POCKET}');

// 3. MANUAL: kot boşsa uyarı, çağrı yok
setv('pk_elev_mode', 'MANUAL'); js('mstPkElevChanged()');
ok(take('pk_elevation_preview').length === 0 && /referans kotunu \(m\) girin/.test(js("document.getElementById('pkElevStatus').textContent")), 'MANUAL kot boş: önizleme çağrılmadı, Türkçe uyarı');
ok(js("document.getElementById('pk_elev_ref_m').disabled") === false, 'MANUAL: referans kotu alanı açık');
js('createPD()'); js('mstPkKnPlace()');
ok(take('create_flat_precast').length === 0 && take('kn_place').length === 0 && D.alerts.splice(0).length === 2, 'MANUAL kot boş: oluşturma / yerleştirme gönderilmedi, uyarı verildi');
setv('pk_elev_ref_m', '2,45'); setv('pk_elev_ref_face', 'BOTTOM'); js('mstPkElevChanged()');
c = take('pk_elevation_preview'); pv = c.length === 1 ? JSON.parse(c[0][1]) : {};
ok(pv.elevation_mode === 'MANUAL' && near(pv.elevation_ref_m, 2.45) && pv.elevation_ref_face === 'BOTTOM', 'MANUAL: önizleme girdisi (2,45 m, alt yüzey)');
js('createPD()');
c = take('create_flat_precast'); d = c.length === 1 ? JSON.parse(c[0][1]) : {};
ok(d.pk_elevation_mode === 'MANUAL' && near(d.pk_elevation_ref_m, 2.45) && d.pk_elevation_ref_face === 'BOTTOM', 'MANUAL: create_flat_precast pk_elevation_ref_m=2,45 / BOTTOM');
js('mstPkKnPlace()');
c = take('kn_place'); const kn = c.length === 1 ? JSON.parse(c[0][1]) : {};
ok(kn.elevation_mode === 'MANUAL' && near(kn.elevation_ref_m, 2.45) && kn.elevation_ref_face === 'BOTTOM', 'MANUAL: kn_place JSON');

// 4. Önizleme sonucu gösterimi
js('mstPkElevation(' + JSON.stringify({ ok: true, neden: null, mod: 'MANUAL', yuz: 'BOTTOM', referans_m: 2.45, uyarilar: ['kanal cebe oturmuyor (alt 2,450 m, cep tabanı 2,000 m)'], alt_kot_m: 2.45, ust_kot_m: 3.25, referans_ust_kot_m: 3.25, ust_yuzey: null, toplam_yukseklik_m: 0.8, referans_yuksekligi_m: 0.8, cep_tabani_m: 2.0, karsi_cep_tabani_m: 2.0, taraf: 'start', pd_ust_m: null }) + ')');
let t = js("document.getElementById('pkElevInfo').textContent");
ok(/Alt kot 2,450 m · üst kot 3,250 m · toplam yükseklik 0,800 m/.test(t), 'alt / üst kot virgüllü ve birimli');
ok(/ÖNİZLEME — MODEL DEĞİŞMEZ/.test(t), 'önizlemenin modeli değiştirmediği belirtiliyor');
ok(/Kullanıcı girdisi: 2,450 m \(alt yüzey\)/.test(t) && /Cep tabanı 2,000 m \/ karşı cep 2,000 m \(başlangıç cebi\)/.test(t), 'kaynak (kullanıcı girdisi) ve cep tabanı görünür');
ok(/kanal cebe oturmuyor/.test(t) && /UYARI/.test(t) && /en yüksek açık çıkıntı üstü \(varsayılan\)/.test(t), 'uyarı ve varsayılan üst yüzey görünür');
js('mstPkElevation(' + JSON.stringify({ ok: false, neden: "Cebe oturtma için PK altında iki BK'da hizalı kanal cebi bulunamadı.", mod: 'POCKET', uyarilar: ["BK-01'de kanal cebi yok"], cep_tabani_m: null }) + ')');
t = js("document.getElementById('pkElevInfo').textContent");
ok(/KOT HESAPLANAMADI/.test(t) && /hizalı kanal cebi bulunamadı/.test(t) && /Cep tabanı: bulunamadı/.test(t), 'hesaplanamayan önizleme: neden ve eksik cep görünür');

// 5. Cep uyumu: bk_ust_m sayıysa ref_top_m = bk_ust_m + en kalın PD/PDÖ/PV; değilse cep tabanı + derinlik (TÜRETİLDİ)
setv('pk_elev_mode', 'TOP'); js('mstPkElevSync()');
const pair = (bkUst, ref, uy) => Object.assign({ bk_ust_uyari: uy == null ? null : uy, aciklik: 'BK-01 → BK-02', taraf: 'start', taraf_ad: 'başlangıç', cep_genisligi_m: 1.24, cep_derinligi_m: 0.5, cep_tabani_m: 2.0, karsi_cep_tabani_m: 2.0, derz_m: 0.02, derz_kaynagi: 'model', referans_ust_m: ref, referans_kaynagi: ref == null ? null : 'girdi', beklenen: { dis_genislik_m: 1.2, toplam_yukseklik_m: 0.8 }, uyarilar: [], cep_uygun: true, adaylar: [] }, bkUst == null ? {} : { bk_ust_m: bkUst });
js('mstPkCheckPockets()'); take('pk_pocket_candidates');
js('mstPkCandidates(' + JSON.stringify({ ok: true, ciftler: [pair(2.6, null)] }) + ')');
c = take('pk_pocket_candidates'); let s = c.length === 1 ? JSON.parse(c[0][1]) : {};
ok(near(s.ref_top_m, 2.9), 'bk_ust_m 2,600: ref_top_m = 2,6 + 0,30 = 2,9 (gönderilen ' + s.ref_top_m + ')');
js('mstPkCandidates(' + JSON.stringify({ ok: true, ciftler: [pair(2.6, 2.9)] }) + ')');
c = take('pk_elevation_preview'); pv = c.length === 1 ? JSON.parse(c[0][1]) : {};
ok(c.length === 1 && pv.elevation_mode === 'TOP' && near(pv.ref_top_m, 2.9), 'önizleme açıkken cep uyumu sonrası TOP önizlemesi ref_top_m ile yenilendi');
t = js("document.getElementById('pkPocketInfo').textContent");
ok(/BK üstü 2,600 m \(BK üst kotu\)/.test(t) && !/TÜRETİLDİ/.test(t), 'bk_ust_m kaynağı: BK üst kotu, TÜRETİLDİ yok');
js('mstPkElevation(' + JSON.stringify({ ok: true, mod: 'TOP', yuz: 'TOP', uyarilar: [], alt_kot_m: 2.1, ust_kot_m: 2.9, referans_ust_kot_m: 2.9, ust_yuzey: null, toplam_yukseklik_m: 0.8, referans_yuksekligi_m: 0.8, cep_tabani_m: 2.0, karsi_cep_tabani_m: 2.0, taraf: 'start', pd_ust_m: 2.9 }) + ')');
t = js("document.getElementById('pkElevInfo').textContent");
ok(/Üst kot 2,900 m = BK üstü 2,600 m \(BK üst kotu\) \+ yerleşimdeki en kalın PD\/PDÖ\/PV 0,300 m/.test(t) && /KOT HESAPLANDI/.test(t), 'TOP önizleme kaynağı görünür');
js('mstPkCheckPockets()'); take('pk_pocket_candidates');
const UY = 'iki BK üst kotu farklı (2,600 / 2,610 m)';
js('mstPkCandidates(' + JSON.stringify({ ok: true, ciftler: [pair(null, null, UY)] }) + ')');
c = take('pk_pocket_candidates'); s = c.length === 1 ? JSON.parse(c[0][1]) : {};
ok(near(s.ref_top_m, 2.8), 'bk_ust_m null: ref_top_m = 2,0 + 0,5 + 0,30 = 2,8 (gönderilen ' + s.ref_top_m + ')');
js('mstPkCandidates(' + JSON.stringify({ ok: true, ciftler: [pair(null, 2.8, UY)] }) + ')'); take('pk_elevation_preview');
t = js("document.getElementById('pkPocketInfo').textContent");
ok(/BK üstü 2,500 m \(cep tabanı \+ cep derinliği\) TÜRETİLDİ \(iki BK üst kotu farklı \(2,600 \/ 2,610 m\)\)/.test(t), 'bk_ust_m null: türetildi işareti + bk_ust_uyari metni görünür');
js('mstPkElevation(' + JSON.stringify({ ok: true, mod: 'TOP', yuz: 'TOP', uyarilar: [], alt_kot_m: 2.0, ust_kot_m: 2.8, referans_ust_kot_m: 2.8, ust_yuzey: null, toplam_yukseklik_m: 0.8, referans_yuksekligi_m: 0.8, cep_tabani_m: 2.0, karsi_cep_tabani_m: 2.0, taraf: 'start', pd_ust_m: 2.8 }) + ')');
ok(/TÜRETİLDİ \(iki BK üst kotu farklı/.test(js("document.getElementById('pkElevInfo').textContent")), 'kot önizlemesinde de türetildi + neden görünür');
js('mstPkCheckPockets()'); take('pk_pocket_candidates');
js('mstPkCandidates(' + JSON.stringify({ ok: true, ciftler: [pair(null, null)] }) + ')'); take('pk_pocket_candidates');
js('mstPkCandidates(' + JSON.stringify({ ok: true, ciftler: [pair(null, 2.8)] }) + ')'); take('pk_elevation_preview');
t = js("document.getElementById('pkPocketInfo').textContent");
ok(/cep derinliği\) TÜRETİLDİ \+/.test(t), 'bk_ust_uyari null: yalnız türetildi işareti (boş neden yok)');

// 6. Tipte üst yüzey çıkıntısı (channel_top_ref)
const secUU = { v: 1, preset: 'UU', total_width_m: 1.5, base_m: 0.2, left: { on: true, width_m: 0.2, height_m: 0.6, offset_m: 0 }, mid: { on: true, width_m: 0.15, height_m: 0.4, offset_m: 0.675 }, right: { on: true, width_m: 0.2, height_m: 0.6, offset_m: 0 } };
js("precastTypes.push({uid:'pt_pk_uu',family:'PK',name:'PK-UU',concrete:'C30/37',section:" + JSON.stringify(secUU) + "});renderPrecastTypes();refreshAllPDRowOptions()");
const lt = js("document.getElementById('precastTypeLibrary').textContent");
ok(/En yüksek açık çıkıntı \(varsayılan, 0,800 m\)/.test(lt) && /Orta çıkıntı üstü \(alttan 0,600 m\)/.test(lt), 'kesitli tipte üst yüzey seçimi (varsayılan + açık çıkıntılar)');
js("mstPkSetTopRef('pt_pk_uu','mid')");
ok(js("typeByUid('pt_pk_uu').channel_top_ref") === 'mid', 'seçim tip kaydına yazıldı (channel_top_ref=mid)');
ok(js("mstPkLibraryForSave(precastTypes).filter(function(t){return t.uid==='pt_pk_uu'})[0].channel_top_ref") === 'mid', 'kayda giden kütüphanede channel_top_ref var');
js("mstPkUseType('pt_pk_uu')"); take('pk_elevation_preview');
js('mstPkElevPreview()');
c = take('pk_elevation_preview'); pv = c.length === 1 ? JSON.parse(c[0][1]) : {};
ok(pv.channel_top_ref === 'mid' && pv.section && pv.section.preset === 'UU' && !('kod' in pv), 'kesitli tipte önizleme: section + channel_top_ref');
js("mstPkSetTopRef('pt_pk_uu','')");
ok(js("Object.prototype.hasOwnProperty.call(typeByUid('pt_pk_uu'),'channel_top_ref')") === false, 'varsayılana dönünce anahtar silindi');
ok(js("Object.prototype.hasOwnProperty.call(typeByUid('pt_pk_1'),'channel_top_ref')") === false, 'kesitsiz eski kayda anahtar eklenmedi');

// 7. TOP'a dönünce create_flat_precast girdisi ilk TOP girdisiyle aynı anahtarlar (pk_elevation_* yok)
setv('pk_elev_mode', 'TOP'); js('mstPkElevSync()'); D.calls.splice(0);
js('createPD()');
c = take('create_flat_precast'); d = c.length === 1 ? JSON.parse(c[0][1]) : {};
ok(JSON.stringify(Object.keys(d)) === JSON.stringify(Object.keys(topD)), 'TOP: anahtar listesi ilk TOP girdisiyle birebir aynı');

ok(D.errors.length === 0, 'console.error / zamanlayıcı hatası yok (' + D.errors.join(' | ') + ')');
console.log(fail ? 'SONUÇ: ' + fail + ' HATA' : 'SONUÇ: hepsi geçti');
process.exit(fail ? 1 : 0);
