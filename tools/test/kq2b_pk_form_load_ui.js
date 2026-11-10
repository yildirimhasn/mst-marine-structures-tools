// ADR-0515-K3 P2 arayüz: Kanal Prekastı formunda "Kayıtlı PK tipinden başla" (tip yükleme, alan doldurma), tip_uid gönderimi
// (yalnız geometri yüklenen tiple aynıyken), JS geometri imzası ↔ main.rb mst_pk_geom_sig kuralı (beklenen dizgiler main.rb
// :13282-13291 ve channel_section.rb :144-151 kuralından elle türetildi; Ruby bu testte çalıştırılmaz), 3B izometrik SVG ve
// "Kullanıldığı yapılar" (sahte DOM, SketchUp DIŞINDA). Ruby tarafındaki tip_uid doğrulaması, görünüm ve modelleme kanıtlanmaz.
// Kullanım: node tools/test/kq2b_pk_form_load_ui.js   (çıkış kodu 0 = geçti)
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
const val = (id) => js("(document.getElementById('" + id + "')||{value:null}).value");
const chk = (id) => js("!!(document.getElementById('" + id + "')||{}).checked");
const txt = (id) => js("(document.getElementById('" + id + "')||{textContent:''}).textContent");
const setv = (id, v) => js("document.getElementById('" + id + "').value=" + JSON.stringify(v) + ';updateChannelPrecastUI()');
const pick = (uid) => js("var s=document.getElementById('pk_form_type');s.value=" + JSON.stringify(uid) + ';mstPkFormPick(s.value)');
const sendCh = () => { js('createChannelPrecast()'); const c = take('create_channel_precast'); return c.length === 1 ? JSON.parse(c[0][1]) : null; };

ok(loadErrors.length === 0, 'sayfa yüklendi (' + loadErrors.join(' | ') + ')');
js('updateChannelPrecastUI()');
D.calls.splice(0); D.errors.splice(0); D.alerts.splice(0);
const r0 = sendCh();
ok(r0 && !own(r0, 'tip_uid'), 'tip yüklenmeden create_channel_precast isteğinde tip_uid yok');

// Kütüphane: kesitli L kaydı (P1 biçimi), oturmasız eski kesitli U kaydı; varsayılan PK-01 (kesitsiz) listeye girmez
const secL = { v: 1, preset: 'L', total_width_m: 1.0, base_m: 0.2, left: { on: false, width_m: 0.2, height_m: 0.6, offset_m: 0 }, mid: { on: false, width_m: 0.15, height_m: 0.3, offset_m: 0.425 }, right: { on: true, width_m: 0.2, height_m: 0.6, offset_m: 0 }, deck_ledge_left: 'fill' };
const recL = { uid: 'pt_pk_L', family: 'PK', name: 'PK-005', title: 'L Kanal 1000', pk_rev: 2, concrete: 'C50/60', section: secL, fw_bottom: false, fw_sides: true, fw_inner: true, fw_ends: false, fw_ledge: false, seat_left_m: 0.1, seat_right_m: 0.12, channel_top_ref: 'right', created_at: '2026-11-10T09:00:00+03:00' };
const secU = { v: 1, preset: 'U', total_width_m: 1.2, base_m: 0.2, left: { on: true, width_m: 0.2, height_m: 0.6, offset_m: 0 }, mid: { on: false, width_m: 0.15, height_m: 0.3, offset_m: 0.525 }, right: { on: true, width_m: 0.2, height_m: 0.6, offset_m: 0 } };
const recOld = { uid: 'pt_pk_old', family: 'PK', name: 'PK-OLD', concrete: 'C30/37', section: secU };
js('precastTypes.push(' + JSON.stringify(recL) + ',' + JSON.stringify(recOld) + ');renderPrecastTypes();refreshAllPDRowOptions()');

// 1. Seçim listesi
const opts = js("Array.prototype.slice.call(document.getElementById('pk_form_type').options).map(function(o){return o.value+'='+o.textContent})");
ok(opts[0] === '=Yeni / kayıtsız tasarım', 'ilk seçenek "Yeni / kayıtsız tasarım"');
ok(opts.indexOf('pt_pk_L=PK-005 — L Kanal 1000, rev 2') >= 0 && opts.indexOf('pt_pk_old=PK-OLD') >= 0, 'kesitli tipler "kod — ad, rev" biçiminde listede');
ok(!opts.some((o) => /^pt_pk_1=/.test(o)), 'kesitsiz eski U kaydı (pt_pk_1) listede yok');

// 2. Tip yükleme: tüm alanlar
pick('pt_pk_L');
ok(val('channel_total_width_m') === '1' && val('channel_base_m') === '0.2', 'toplam genişlik ve taban dolduruldu');
ok(chk('channel_left_on') === false && chk('channel_mid_on') === false && chk('channel_right_on') === true, 'Sol / Orta / Sağ Var-Yok kayıttan');
ok(val('channel_right_width_m') === '0.2' && val('channel_right_height_m') === '0.6' && val('channel_right_offset_m') === '0' && val('channel_mid_offset_m') === '0.425' && val('channel_left_height_m') === '0.6', 'çıkıntı ölçüleri (pasif çıkıntınınki de) dolduruldu');
ok(js('chSectionPreset') === 'L' && /L kesit/.test(txt('channelPresetLabel')), 'ön ayar L');
ok(val('channel_deck_ledge_left') === 'fill' && val('channel_deck_ledge_right') === '', 'ledge: sol Dolu, sağ Varsayılan');
ok(val('channel_seat_left_m') === '0.1' && val('channel_seat_right_m') === '0.12', 'oturma payları dolduruldu');
ok(val('channel_concrete_class') === 'C50/60' && js("Array.prototype.slice.call(document.getElementById('channel_concrete_class').options).some(function(o){return o.value==='C50/60'})"), 'beton sınıfı (listede yoktu, seçenek eklendi)');
ok(chk('channel_fw_bottom') === false && chk('channel_fw_sides') === true && chk('channel_fw_inner') === true && chk('channel_fw_ends') === false && chk('channel_fw_ledge') === false, 'kalıp kutuları kayıttaki fw_* değerlerinden');
ok(val('pk_save_kod') === 'PK-005' && val('pk_save_ad') === 'L Kanal 1000', 'PK Tip Kaydı alanlarında kod / ad');
ok(val('pk_save_top_ref') === 'right', 'üst yüzey seçimi kayıttan (Sağ)');
ok(/KAYITLI TİP/.test(txt('pkFormTypeNote')) && /PK-005 — L Kanal 1000 \(rev 2\)/.test(txt('pkFormTypeNote')) && /P4/.test(txt('pkFormTypeNote')), 'durum: KAYITLI TİP + P4 notu');
let r = sendCh();
ok(r && r.tip_uid === 'pt_pk_L' && r.section.preset === 'L' && r.concrete_class === 'C50/60' && r.seat_left_m === 0.1 && r.fw_ledge === false, 'geometri aynı: tip_uid gönderildi, diğer alanlar formdan');

// 3. JS imzası ↔ main.rb kuralı (elle türetilmiş beklenen dizgiler)
ok(js('mstPkGeomSig(' + JSON.stringify(secL) + ',0.1,0.12)') === 'pk1|W1.0000|B0.2000|0.8000-1.0000:0.6000|oturma:0.1000/0.1200', 'L kaydı: pk1|W1.0000|B0.2000|0.8000-1.0000:0.6000|oturma:0.1000/0.1200');
const secUU = { v: 1, preset: 'UU', total_width_m: 1.23456, base_m: 0.2, left: { on: true, width_m: 0.15, height_m: 0.5, offset_m: 0.05 }, mid: { on: true, width_m: 0.1, height_m: 0.3, offset_m: 0.6 }, right: { on: true, width_m: 0.15, height_m: 0.5, offset_m: 0 } };
ok(js('mstPkGeomSig(' + JSON.stringify(secUU) + ',-0.00004,null)') === 'pk1|W1.2346|B0.2000|0.0500-0.2000:0.5000|0.6000-0.7000:0.3000|1.0846-1.2346:0.5000|oturma:0.0000/-', 'UU: soldan sağa sıra, 4 ondalık, -0 → 0, oturma yoksa "-"');
ok(js('mstPkSectionSig(' + JSON.stringify(Object.assign({}, secL, { preset: 'OZEL', deck_ledge_left: 'open', channel_top_ref: 'right', left: { on: false, width_m: 9, height_m: 9, offset_m: 9 } })) + ')') === js('mstPkSectionSig(' + JSON.stringify(secL) + ')'), 'ön ayar etiketi, pasif çıkıntı, deck_ledge, channel_top_ref imzaya girmez');
ok(js("mstPkRecSig(typeByUid('pt_pk_old'))") === 'pk1|W1.2000|B0.2000|0.0000-0.2000:0.6000|1.0000-1.2000:0.6000|oturma:-/-', 'oturmasız eski kayıt imzası "-/-"');

// 4. Geometri değişince uyarı, tip_uid düşer; kod / ad yeniden öneriye
setv('channel_right_height_m', '0.65');
ok(/Yüklenen tipten \(PK-005 — L Kanal 1000 \(rev 2\)\) farklı — kayıtsız tasarım \(yeni tip olarak kaydedebilirsiniz\)/.test(txt('pkFormTypeNote')), 'geometri değişti: "Yüklenen tipten farklı — kayıtsız tasarım" uyarısı');
r = sendCh();
ok(r && !own(r, 'tip_uid'), 'geometri farklı: tip_uid gönderilmedi');
ok(val('pk_save_kod') === 'PK-006' && val('pk_save_ad') === 'L Kanal 1000', 'kod / ad yeniden öneri (PK-006): yeni tip olarak kaydedilebilir');
setv('channel_right_height_m', '0.60');
r = sendCh();
ok(r && r.tip_uid === 'pt_pk_L' && /KAYITLI TİP/.test(txt('pkFormTypeNote')), 'geometri kayıtla yeniden aynı: tip_uid tekrar gönderilir');

// 5. İmzaya girmeyen değişiklikler tip_uid'i düşürmez; oturma değişikliği düşürür
setv('channel_mid_width_m', '0.33');
setv('channel_deck_ledge_right', 'open');
js("document.getElementById('pk_save_top_ref').value=''");
r = sendCh();
ok(r && r.tip_uid === 'pt_pk_L', 'pasif çıkıntı, ledge, üst yüzey değişince tip_uid korunur');
js("var e=document.getElementById('channel_concrete_class');e.value='C30/37';e.dispatchEvent({type:'change'})");
ok(/KAYITTAN FARKLI/.test(txt('pkFormTypeNote')) && /beton sınıfı/.test(txt('pkFormTypeNote')), 'beton değişince bilgi notu (KAYITTAN FARKLI), bağ geometriye göre');
ok((sendCh() || {}).tip_uid === 'pt_pk_L', 'beton farkı tip_uid\'i düşürmez (sözleşme: kesit + oturma)');
setv('channel_seat_left_m', '0,11');
ok(!own(sendCh() || { tip_uid: 1 }, 'tip_uid'), 'oturma payı değişince tip_uid gönderilmez');
setv('channel_seat_left_m', '0.1');

// 6. Oturmasız eski kayıt: doldurulur; Ruby kuralı (mst_pk_form_type_link / mst_pk_rec_same_geom?) gibi yalnız kesit karşılaştırılır → tip bağı kurulur
pick('pt_pk_old');
ok(js('chSectionPreset') === 'U' && val('channel_total_width_m') === '1.2' && chk('channel_left_on') === true, 'eski kayıt kesiti dolduruldu');
ok(!/TİP BAĞI YOK/.test(txt('pkFormTypeNote')) && /KAYITLI TİP/.test(txt('pkFormTypeNote')) && /yalnız kesit karşılaştırılır/.test(txt('pkFormTypeNote')) && /Kayıtta kalıp seçimi yok/.test(txt('pkFormTypeNote')), 'eski kayıt: KAYITLI TİP, yalnız kesit karşılaştırılır, eksik kalıp bilgisi açık');
ok((sendCh() || {}).tip_uid === 'pt_pk_old', 'eski kayıt: kesit aynı → tip_uid gönderilir');
setv('channel_total_width_m', '1.3');
ok(!own(sendCh() || { tip_uid: 1 }, 'tip_uid') && /KAYITSIZ TASARIM/.test(txt('pkFormTypeNote')), 'eski kayıt: kesit değişince tip_uid gönderilmez');
setv('channel_total_width_m', '1.2');
// 6b. fw_ledge null → kalıplı (channel_section.rb:154 mst_ch_ledge_off? ile aynı)
ok(js("mstPkFwLedgeOn({fw_ledge:null})") === true && js("mstPkFwLedgeOn({})") === true && js("mstPkFwLedgeOn({fw_ledge:false})") === false && js("mstPkFwLedgeOn({fw_ledge:'0'})") === false && js("mstPkFwLedgeOn({fw_ledge:'false'})") === false && js("mstPkFwLedgeOn({fw_ledge:true})") === true, 'fw_ledge: yalnız false / "0" / "false" kalıpsız');

// 7. "Yeni / kayıtsız tasarım": form değişmez, bağ yok
pick('');
ok(val('channel_total_width_m') === '1.2' && !own(sendCh() || { tip_uid: 1 }, 'tip_uid') && /Kayıtlı bir PK tipi seçilince/.test(txt('pkFormTypeNote')), 'kayıtsız seçim: form aynı, tip_uid yok');

// 8. Yüklenen tip kütüphaneden kalkarsa bağ düşer
pick('pt_pk_L');
js("precastTypes=precastTypes.filter(function(t){return t.uid!=='pt_pk_L'});renderPrecastTypes()");
ok(val('pk_form_type') === '' && /artık yok/.test(txt('pkFormTypeNote')) && !own(sendCh() || { tip_uid: 1 }, 'tip_uid'), 'tip silinince seçim kalktı, uyarı, tip_uid yok');
js('precastTypes.push(' + JSON.stringify(recL) + ');renderPrecastTypes()');

// 9. 3B izometrik SVG; ana kesit önizlemesi değişmez
pick('pt_pk_L');
const secNow = js('JSON.stringify(chReadSection())');
const secSvg0 = js("document.getElementById('channelSectionSvg').innerHTML");
js("var el=document.createElementNS('http://www.w3.org/2000/svg','svg');chDrawSection(JSON.parse(" + JSON.stringify(secNow) + "),true,el);window.__ref=el.innerHTML");
ok(secSvg0 === js('__ref') && secSvg0.length > 0, 'ana kesit önizlemesi tek başına chDrawSection çıktısıyla birebir aynı');
js('chDrawIso(chReadSection(),true)');
ok(js("document.getElementById('channelSectionSvg').innerHTML") === secSvg0, '3B çizimi ana kesit SVG\'sine dokunmuyor');
const iso = () => js("document.getElementById('channelIsoSvg').innerHTML");
const nPoly = js("document.getElementById('channelIsoSvg').querySelectorAll('polygon').length");
const nProf = js('mstChSection.profile(chReadSection()).length');
ok(nPoly >= 4 && /stroke-dasharray/.test(iso()), '3B: yan yüzler + kesikli arka yüz + ön yüz poligonları (' + nPoly + ')');
ok(js("(function(){var p=document.getElementById('channelIsoSvg').querySelectorAll('polygon');return p[p.length-1].getAttribute('points').split(' ').length})()") === nProf, '3B: ön yüz aynı profilin ' + nProf + ' noktası');
ok(/Boy 2,000 m — gösterim boyu \(otomatik: BK arası\)/.test(js("document.getElementById('channelIsoSvg').textContent")) && /model değişmez/.test(js("document.getElementById('channelIsoSvg').textContent")), '3B: otomatik boyda 2,000 m gösterim boyu etiketi');
setv('channel_length_mode', 'MANUAL'); setv('channel_manual_length_m', '3.30');
ok(/Boy 3,300 m \(manuel boy\)/.test(js("document.getElementById('channelIsoSvg').textContent")), '3B: manuel boy 3,300 m');
setv('channel_manual_length_m', '50');
ok(/kısaltılarak çizildi/.test(js("document.getElementById('channelIsoSvg').textContent")), '3B: çok uzun boy kısaltıldı (etiketli)');
setv('channel_length_mode', 'AUTO');
js('chSetView("iso")');
ok(js("document.getElementById('channelIsoSvg').style.display") === '' && js("document.getElementById('channelSectionSvg').style.display") === 'none' && js("document.getElementById('chViewIso').getAttribute('aria-pressed')") === 'true', 'Kesit / 3B geçişi: 3B görünür');
js('chSetView("sec")');
ok(js("document.getElementById('channelIsoSvg').style.display") === 'none' && js("document.getElementById('channelSectionSvg').style.display") === '', 'Kesit / 3B geçişi: kesit görünür');
setv('channel_base_m', '0');
ok(/Kesit geçersiz/.test(js("document.getElementById('channelIsoSvg').textContent")), '3B: geçersiz kesitte mesaj');
setv('channel_base_m', '0.2');
const cb9 = D.calls.splice(0).map((c) => c[0]).filter((n) => n !== 'pk_type_catalog');
ok(cb9.length === 0, 'önizleme / tip yükleme callback çağırmadı (' + cb9.join(', ') + ')');

// 10. Kullanıldığı yapılar: tip kartı ve 2b
ok(/Kullanıldığı yapılar: PK listesi henüz okunmadı/.test(txt('precastTypeLibrary')), 'katalog gelmeden tip kartında "henüz okunmadı"');
const cat = { ok: true, tipler: [{ kod: 'PK-005', kaynak: 'kütüphane', kaynak_ad: 'kütüphane', uid: 'pt_pk_L', beton: 'C50/60', adet_modelde: 3, section: secL, on_ayar: 'L', eski_kayit: false, toplam_genislik_m: 1, toplam_yukseklik_m: 0.8, taban_m: 0.2, gecerli: true, hatalar: [], title: 'L Kanal 1000', pk_rev: 2, kullanim: [{ yapi: 'ANO-01', yapi_ad: 'Ano 1', adet: 2 }, { yapi: '', yapi_ad: 'Yapı belirtilmemiş', adet: 1, yapi_turu: 'İskele' }] }] };
js('mstPkCatalog(' + JSON.stringify(cat) + ')');
ok(/Kullanıldığı yapılar \(modeldeki PK'lar\): Ano 1 2 adet; Yapı belirtilmemiş \(İskele\) 1 adet/.test(txt('precastTypeLibrary')), 'tip kartında yapı bazlı kullanım (uid ile, yapı türü varsa)');
ok(/Kullanıldığı yapılar: bilgi yok/.test(txt('precastTypeLibrary')), 'katalogda olmayan kesitli tip (PK-OLD): "bilgi yok"');
ok(/Kullanıldığı yapılar: Ano 1 2 adet/.test(js("document.getElementById('pkPickList').textContent")), '2b satırında kullanım listesi (tek terim: Kullanıldığı yapılar)');
js('renderPrecastTypes()');
ok(/Ano 1 2 adet/.test(txt('precastTypeLibrary')), 'kart yeniden çizilince kullanım korunur');

ok(D.alerts.length === 0, 'alert yok (' + D.alerts.join(' | ') + ')');
ok(D.errors.length === 0, 'console.error / zamanlayıcı hatası yok (' + D.errors.join(' | ') + ')');
console.log(fail ? 'SONUÇ: ' + fail + ' HATA' : 'SONUÇ: hepsi geçti');
process.exit(fail ? 1 : 0);
