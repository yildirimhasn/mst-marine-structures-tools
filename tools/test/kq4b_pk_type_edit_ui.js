// ADR-0515-K3 P4 arayüz: kayıtlı PK tipini düzenleme — üç ayrı eylem (yeni tip / yalnız seçili PK'lar / tipi güncelle), plan
// gösterimi, onay düğmesinin pasif-aktif durumu, pk_type_update_apply gönderimi (onay:true), PK Sil (confirm + gönderim) ve
// katalog eski_rev gösterimi (sahte DOM, SketchUp DIŞINDA). Yanıt payload'ları sözleşmeye göre elle yazıldı (main.rb P4 tarafı
// bu test yazılırken depoda yoktu). Ruby denetimi, Geri Al, döşeme güncellemesi ve görünüm kanıtlanmaz.
// Kullanım: node tools/test/kq4b_pk_type_edit_ui.js   (çıkış kodu 0 = geçti)
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
const shown = (id) => js("(document.getElementById('" + id + "')||{style:{display:'none'}}).style.display") !== 'none';
const dis = (id) => js("!!(document.getElementById('" + id + "')||{disabled:true}).disabled");
const setv = (id, v) => js("document.getElementById('" + id + "').value=" + JSON.stringify(v) + ';updateChannelPrecastUI()');
const pick = (uid) => js("var s=document.getElementById('pk_form_type');s.value=" + JSON.stringify(uid) + ';mstPkFormPick(s.value)');
const clickId = (id) => js("(function(){var b=document.getElementById('" + id + "');if(!b)return 'yok';if(b.disabled)return 'pasif';b.click();return 'tik'})()");

ok(loadErrors.length === 0, 'sayfa yüklendi (' + loadErrors.join(' | ') + ')');
js('updateChannelPrecastUI()');
D.calls.splice(0); D.errors.splice(0); D.alerts.splice(0);

const secL = { v: 1, preset: 'L', total_width_m: 1.0, base_m: 0.2, left: { on: false, width_m: 0.2, height_m: 0.6, offset_m: 0 }, mid: { on: false, width_m: 0.15, height_m: 0.3, offset_m: 0.425 }, right: { on: true, width_m: 0.2, height_m: 0.6, offset_m: 0 } };
const recL = { uid: 'pt_pk_L', family: 'PK', name: 'PK-005', title: 'L Kanal 1000', pk_rev: 2, concrete: 'C30/37', section: secL, fw_bottom: true, fw_sides: true, fw_inner: true, fw_ends: true, fw_ledge: true, seat_left_m: 0.1, seat_right_m: 0.12, channel_top_ref: 'right' };
js('precastTypes.push(' + JSON.stringify(recL) + ');renderPrecastTypes();refreshAllPDRowOptions()');

// 1. Görünürlük: tip yüklenmeden ve geometri kayıtla aynıyken eylemler gizli
ok(!shown('pkEditBox') && txt('pkSaveBtn') === 'PK Tipi Olarak Kaydet', 'tip yüklenmeden üç eylem bölümü gizli');
pick('pt_pk_L');
ok(!shown('pkEditBox'), 'kayıtlı tip yüklü, geometri aynı (KAYITLI TİP): eylemler gizli');
js("var e=document.getElementById('channel_concrete_class');e.value='C35/45';e.dispatchEvent({type:'change'})");
ok(!shown('pkEditBox'), 'yalnız beton farkı (geometri aynı): eylemler gizli');
setv('channel_right_height_m', '0.65');
ok(shown('pkEditBox') && /KAYITSIZ TASARIM/.test(txt('pkFormTypeNote')), 'geometri değişti (KAYITSIZ TASARIM): üç eylem görünür');
ok(txt('pkSaveBtn') === 'Yeni PK Tipi Olarak Kaydet', '(a) düğmesi "Yeni PK Tipi Olarak Kaydet"');
ok(/Seçili PK elemanlarına uygula \(yeni tip olarak\)/.test(txt('pkApplySelBtn')) && /Yalnız SketchUp'ta seçili PK'lar değişir; diğer örnekler eski tipte kalır/.test(txt('pkEditBox')), '(b) düğmesi ve açıklaması');
ok(txt('pkUpdTitle') === '3) Tipi güncelle: PK-005 (rev 2 → 3)', '(c) başlık: kod + rev 2 → 3');
ok(/Etkin yapı \(varsayılan\)/.test(txt('pkEditBox')) && /Tüm model/.test(txt('pkEditBox')) && js("document.getElementById('pk_upd_kapsam_yapi').checked") === true, 'kapsam seçimi: Etkin yapı varsayılan');
ok(/metrajı değişir/.test(txt('pkEditBox')), 'metrajın değişeceği uyarısı');
ok(D.calls.filter((c) => c[0] !== 'pk_type_catalog').length === 0, 'görünürlük değişimi callback çağırmadı');

// 2. (a) mevcut akış değişmedi: uygula yok
D.calls.splice(0);
ok(clickId('pkSaveBtn') === 'tik', '(a) tıklandı');
let c = take('pk_type_save');
let q = c.length === 1 ? JSON.parse(c[0][1]) : null;
ok(q && !own(q, 'uygula') && q.karar === null && q.kod === 'PK-006', '(a) pk_type_save: uygula yok, öneri kodu PK-006');
js("mstPkTypeSaved({ok:false,durum:'hata',neden:'deneme'})");

// 3. (b) yalnız seçili: uygula:"secim"; yanıt guncellenen + uyarilar
D.calls.splice(0);
ok(!dis('pkApplySelBtn'), '(b) geçerli kesitte etkin');
ok(clickId('pkApplySelBtn') === 'tik', '(b) tıklandı');
c = take('pk_type_save');
q = c.length === 1 ? JSON.parse(c[0][1]) : null;
ok(q && q.uygula === 'secim' && q.kod === 'PK-006' && q.ad && q.section && q.section.right.height_m === 0.65 && !own(q, 'tip_uid'), '(b) pk_type_save: uygula "secim", yeni kod / ad, formdaki kesit');
ok(dis('pkApplySelBtn') && dis('pkUpdPlanBtn'), '(b) yanıt beklenirken (b) ve Planı göster pasif');
js("mstPkTypeSaved({ok:true,durum:'ayni_geometri',mevcut:{uid:'pt_x',kod:'PK-009'}})");
js('mstPkSaveDecide("yeni")');
c = take('pk_type_save');
q = c.length === 1 ? JSON.parse(c[0][1]) : null;
ok(q && q.uygula === 'secim' && q.karar === 'yeni', '(b) aynı geometri kararında uygula korunur');
js("mstPkTypeSaved({ok:true,durum:'kaydedildi',tip:{uid:'pt_new',kod:'PK-006',ad:'L Kanal 1000'},guncellenen:2,uyarilar:['PK-3: yapı belirtilmemiş']})");
ok(/KAYDEDİLDİ/.test(txt('pkSaveResult')) && /2 adet seçili PK bu tipe geçirildi; diğer örnekler eski tipte kaldı/.test(txt('pkSaveResult')) && /PK-3: yapı belirtilmemiş/.test(txt('pkSaveResult')), '(b) sonuç: güncellenen adet + uyarılar');
js("mstPkTypeSaved({ok:false,durum:'hata',neden:'Seçimde PK yok.',uyarilar:['seçim boş']})");

// 4. (b) boş kodda pasif + neden
js("document.getElementById('pk_save_kod').value='';mstPkSaveEdited('kod')");
ok(dis('pkApplySelBtn') && /PK kodunu girin/.test(txt('pkApplySelWhy')), '(b) boş kodda pasif, neden görünür');
js("document.getElementById('pk_save_kod').value='PK-006';mstPkSaveEdited('kod')");
ok(!dis('pkApplySelBtn'), '(b) kod girilince etkin');

// 5. (c) plan isteği
D.calls.splice(0);
js("var r=document.getElementById('pk_upd_kapsam_model');r.checked=true;mstPkUpdScope(r.value)");
ok(clickId('pkUpdPlanBtn') === 'tik', 'Planı göster tıklandı');
c = take('pk_type_update_plan');
let pq = c.length === 1 ? JSON.parse(c[0][1]) : null;
ok(pq && pq.tip_uid === 'pt_pk_L' && pq.kapsam === 'model' && pq.section.right.height_m === 0.65 && pq.seat_left_m === 0.1 && pq.seat_right_m === 0.12 && pq.concrete === 'C35/45', 'plan isteği: tip_uid, kapsam model, kesit, oturma, beton');
ok(pq && pq.fw && ['bottom', 'sides', 'inner', 'ends', 'ledge'].every((k) => typeof pq.fw[k] === 'boolean') && own(pq, 'channel_top_ref') && !own(pq, 'onay') && !own(pq, 'kod'), 'plan isteği: fw beş alan, channel_top_ref var, onay / kod yok');
ok(/Plan hazırlanıyor/.test(txt('pkUpdPlan')) && dis('pkUpdPlanBtn'), 'plan beklenirken durum + düğme pasif');

// 6. baslatilabilir=false: onay pasif + neden; uymayanlar, kapsam dışı
const planBad = { ok: true, tip: { uid: 'pt_pk_L', kod: 'PK-005', ad: 'L Kanal 1000', rev: 2 }, yeni_rev: 3, kapsam: 'yapi', yapi: 'ANO-01',
  ornekler: [{ pid: 11, uid: 'u1', kod: 'PK-005', yapi: 'ANO-01', uygun: true, nedenler: [] }, { pid: 12, uid: 'u2', kod: 'PK-005', yapi: 'ANO-01', uygun: false, nedenler: ['Sağ cep genişliği yetersiz (0,20 m < 0,25 m)'] }],
  yapi_ozet: [{ yapi: 'ANO-01', yapi_ad: 'Ano 1', adet: 2, uygun_degil: 1 }], kapsam_disi: [{ yapi: 'ANO-02', adet: 4 }], baslatilabilir: false, neden: 'Uymayan 1 örnek var; güncelleme başlatılmadı.', geom_degisti: true };
js('mstPkTypePlan(' + JSON.stringify(planBad) + ')');
const pt = txt('pkUpdPlan');
ok(/revizyon 2 → 3/.test(pt) && /Etkin yapı — Ano 1/.test(pt), 'plan: revizyon 2 → 3, kapsam etkin yapı (yanıttan)');
ok(/Ano 1: 2 adet/.test(pt) && /1 adet uygun değil/.test(pt), 'plan: yapı başına adet + uygun değil');
ok(/Uymayan örnekler/.test(pt) && /u2/.test(pt) && /Sağ cep genişliği yetersiz/.test(pt) && !/\[u1\]/.test(pt), 'plan: yalnız uymayan örnek ve nedeni');
ok(/Kapsam dışında kalan yapılar \(eski revizyonda kalır\)/.test(pt) && /ANO-02 4 adet/.test(pt), 'plan: kapsam dışı yapılar eski revizyonda kalır');
ok(/METRAJ DEĞİŞİR/.test(pt), 'plan: metraj uyarısı');
ok(dis('pkUpdApplyBtn') && /Uymayan 1 örnek var/.test(pt) && /Onayla ve güncelle \(tek Ctrl\+Z ile geri alınır\)/.test(pt), 'baslatilabilir=false: onay pasif + neden');
D.calls.splice(0);
js('mstPkUpdApply()');
ok(take('pk_type_update_apply').length === 0, 'pasif planda apply gönderilmez');

// 7. baslatilabilir=true: onay etkin; form değişirse eskir
D.calls.splice(0);
clickId('pkUpdPlanBtn');
c = take('pk_type_update_plan');
pq = c.length === 1 ? JSON.parse(c[0][1]) : null;
const planOk = Object.assign({}, planBad, { kapsam: 'model', yapi: null, ornekler: [planBad.ornekler[0]], yapi_ozet: [{ yapi: 'ANO-01', yapi_ad: 'Ano 1', adet: 1, uygun_degil: 0 }], kapsam_disi: [], baslatilabilir: true, neden: null });
js('mstPkTypePlan(' + JSON.stringify(planOk) + ')');
ok(!dis('pkUpdApplyBtn') && /Tüm model/.test(txt('pkUpdPlan')) && !/BAŞLATILAMAZ/.test(txt('pkUpdPlan')), 'baslatilabilir=true: onay etkin');
clickId('pkUpdPlanBtn'); take('pk_type_update_plan');   // yanıt yalnız istenmiş plana kabul edilir
js('mstPkTypePlan(' + JSON.stringify(Object.assign({}, planOk, { ornekler: [Object.assign({}, planOk.ornekler[0], { uygun: true, nedenler: [], uyarilar: ["komşu PD-03 ile derz 5 mm'ye düşer (kayıtlı derz 20 mm)"] })] })) + ')');
ok(/Uyarılar \(güncellemeyi engellemez\)/.test(txt('pkUpdPlan')) && /derz 5 mm/.test(txt('pkUpdPlan')) && !dis('pkUpdApplyBtn'), 'karar 9: derz uyarısı planda görünür, onayı engellemez');
clickId('pkUpdPlanBtn'); take('pk_type_update_plan');
js('mstPkTypePlan(' + JSON.stringify(planOk) + ')');
setv('channel_right_height_m', '0.70');
ok(dis('pkUpdApplyBtn') && /plan alındıktan sonra değişti/.test(txt('pkUpdPlan')), 'form değişince plan eskir, onay pasif');
setv('channel_right_height_m', '0.65');
ok(!dis('pkUpdApplyBtn'), 'form plan anındaki haline dönünce onay yeniden etkin');
js("mstPkUpdScope('yapi')");
ok(dis('pkUpdApplyBtn'), 'kapsam değişince onay pasif');
js("mstPkUpdScope('model')");

// 8. apply gönderimi: plan isteği + onay:true
D.calls.splice(0);
ok(clickId('pkUpdApplyBtn') === 'tik', 'Onayla ve güncelle tıklandı');
c = take('pk_type_update_apply');
const aq = c.length === 1 ? JSON.parse(c[0][1]) : null;
ok(aq && pq && aq.onay === true && JSON.stringify(Object.assign({}, aq, { onay: undefined })) === JSON.stringify(Object.assign({}, pq, { onay: undefined })), 'apply isteği = plan isteği + onay:true');
ok(dis('pkUpdApplyBtn') && dis('pkApplySelBtn'), 'güncelleme beklenirken onay ve (b) pasif');
const lib2 = JSON.stringify([Object.assign({}, recL, { pk_rev: 3, concrete: 'C35/45', section: Object.assign({}, secL, { right: { on: true, width_m: 0.2, height_m: 0.65, offset_m: 0 } }) })]);
D.calls.splice(0);
js('mstPkTypeUpdated(' + JSON.stringify({ ok: true, guncellenen: 1, tip: { uid: 'pt_pk_L', kod: 'PK-005', rev: 3 }, kutuphane_json: lib2, uyarilar: ['ANO-02: 4 adet eski revizyonda kaldı'] }) + ')');
ok(/TİP GÜNCELLENDİ/.test(txt('pkUpdResult')) && /PK-005 revizyon 3/.test(txt('pkUpdResult')) && /1 adet PK güncellendi/.test(txt('pkUpdResult')) && /ANO-02: 4 adet eski revizyonda kaldı/.test(txt('pkUpdResult')), 'güncelleme sonucu + uyarılar');
ok(js("typeByUid('pt_pk_L').pk_rev") === 3 && /KAYITLI TİP/.test(txt('pkFormTypeNote')) && /rev 3/.test(txt('pkFormTypeNote')) && !shown('pkEditBox'), 'kütüphane yüklendi, form güncel tipte (KAYITLI TİP rev 3), eylemler gizli');
ok(take('pk_type_catalog').length === 1, 'güncellemeden sonra PK listesi yenilendi (pk_type_catalog)');
js("mstPkTypeUpdated({ok:false,neden:'Onay eksik.'})");
ok(/TİP GÜNCELLENMEDİ/.test(txt('pkUpdResult')) && /Onay eksik/.test(txt('pkUpdResult')), 'hata yanıtı: neden görünür');
js('mstPkTypePlan({ok:true})');
ok(txt('pkUpdPlan') === '', 'istenmemiş plan yanıtı gösterilmez');

// 9. PK Sil: confirm + gönderim + sonuç
ok(/Seçili PK'yı Sil \(döşeme boşluğu da güncellenir\)/.test(txt('pkDeleteBtn')) && /SketchUp'ın Sil tuşuyla silinirse döşeme kendiliğinden güncellenmez; Model Kontrolü uyarır/.test(txt('pkPickPanel')), 'PK Sil düğmesi ve Sil tuşu notu');
js('window.__cf=[];window.confirm=function(m){__cf.push(m);return false}');
D.calls.splice(0);
clickId('pkDeleteBtn');
ok(take('pk_delete').length === 0 && js('__cf.length') === 1 && /seçili kanal prekastları/.test(js('__cf[0]')) && /Ctrl\+Z/.test(js('__cf[0]')), 'confirm "hayır": pk_delete gönderilmez');
js('window.confirm=function(m){__cf.push(m);return true}');
clickId('pkDeleteBtn');
c = take('pk_delete');
ok(c.length === 1 && c[0].length === 1, 'confirm "evet": sketchup.pk_delete() bağımsız değişkensiz');
ok(dis('pkDeleteBtn') && /Siliniyor/.test(txt('pkDeleteResult')), 'yanıt beklenirken düğme pasif');
js("mstPkDeleted({ok:true,silinen:2,dosemeler:1,uyarilar:['DS-04 yeniden kuruldu']})");
ok(!dis('pkDeleteBtn') && /SİLİNDİ/.test(txt('pkDeleteResult')) && /2 adet PK silindi; 1 döşemenin PK boşluğu güncellendi/.test(txt('pkDeleteResult')) && /DS-04/.test(txt('pkDeleteResult')), 'silme sonucu: adet, döşeme, uyarı');
ok(take('pk_type_catalog').length === 1, 'silmeden sonra PK listesi yenilendi');
js("mstPkDeleted({ok:false,neden:'Seçimde PK yok.'})");
ok(/SİLİNMEDİ/.test(txt('pkDeleteResult')) && /Seçimde PK yok/.test(txt('pkDeleteResult')), 'silme hatası: neden görünür');

// 10. eski_rev: tip kartı ve 2b
const cat = { ok: true, tipler: [{ kod: 'PK-005', kaynak: 'kütüphane', kaynak_ad: 'kütüphane', uid: 'pt_pk_L', beton: 'C35/45', adet_modelde: 5, section: secL, on_ayar: 'L', toplam_genislik_m: 1, toplam_yukseklik_m: 0.8, taban_m: 0.2, gecerli: true, hatalar: [], title: 'L Kanal 1000', pk_rev: 3,
  kullanim: [{ yapi: 'ANO-01', yapi_ad: 'Ano 1', adet: 1, eski_rev: 0 }, { yapi: 'ANO-02', yapi_ad: 'Ano 2', adet: 4, eski_rev: 4 }] }] };
js('mstPkCatalog(' + JSON.stringify(cat) + ')');
ok(/Ano 2 4 adet 4 adet eski revizyonda/.test(txt('precastTypeLibrary')) && !/Ano 1 1 adet 0 adet/.test(txt('precastTypeLibrary')), 'tip kartı: "4 adet eski revizyonda" (0 gösterilmez)');
ok(/Ano 2 4 adet 4 adet eski revizyonda/.test(js("document.getElementById('pkPickList').textContent")), '2b: "4 adet eski revizyonda"');

ok(D.alerts.length === 0, 'alert yok (' + D.alerts.join(' | ') + ')');
ok(D.errors.length === 0, 'console.error / zamanlayıcı hatası yok (' + D.errors.join(' | ') + ')');
console.log(fail ? 'SONUÇ: ' + fail + ' HATA' : 'SONUÇ: hepsi geçti');
process.exit(fail ? 1 : 0);
