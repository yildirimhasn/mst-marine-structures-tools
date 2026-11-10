// ADR-0515-K3 kod incelemesi 42, arayüz yarısı (kullanıcı kararı 10): E1 liste_bayat / kutuphane_json birleştirmesi (yerel
// kaydedilmemiş korunur, aynı uid'de model kazanır, kaydedilmiş-silinmiş PK düşer), Ö3 plan_pids + plan_degisti, K6 PK Sil
// önizlemesi (pk_delete_preview → confirm metni; ok=false silmez), K1 yuvarlama, K2 eski kayıt metni, K3 boş oturma (sahte DOM,
// SketchUp DIŞINDA). Yanıt payload'ları sözleşmeye göre elle yazıldı; Ruby denetimi, Geri Al ve görünüm kanıtlanmaz.
// Kullanım: node tools/test/kq6b_inceleme_42_ui.js   (çıkış kodu 0 = geçti)
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
const dis = (id) => js("!!(document.getElementById('" + id + "')||{disabled:true}).disabled");
const setv = (id, v) => js("document.getElementById('" + id + "').value=" + JSON.stringify(v) + ';updateChannelPrecastUI()');
const pick = (uid) => js("var s=document.getElementById('pk_form_type');s.value=" + JSON.stringify(uid) + ';mstPkFormPick(s.value)');
const clickId = (id) => js("(function(){var b=document.getElementById('" + id + "');if(!b)return 'yok';if(b.disabled)return 'pasif';b.click();return 'tik'})()");
const sendCh = () => { js('createChannelPrecast()'); const c = take('create_channel_precast'); return c.length === 1 ? JSON.parse(c[0][1]) : null; };
const uids = () => js("precastTypes.map(function(t){return t.uid}).join(',')");

ok(loadErrors.length === 0, 'sayfa yüklendi (' + loadErrors.join(' | ') + ')');
js('updateChannelPrecastUI()');
D.calls.splice(0); D.errors.splice(0); D.alerts.splice(0);

// 1. K1 yuvarlama: yarım değer sıfırdan uzağa, kayan nokta hatasına dayanıklı
ok(js('mstPkN4(1.00005)') === '1.0001' && js('mstPkN4(-1.00005)') === '-1.0001' && js('mstPkN4(2.00004)') === '2.0000' && js('mstPkN4(-0.00004)') === '0.0000', 'K1: 1.00005 → "1.0001", -1.00005 → "-1.0001", 2.00004 → "2.0000", -0 → 0');

// 2. K3 boş dize oturma = oturmasız; K2 eski kayıt metni
const secU = { v: 1, preset: 'U', total_width_m: 1.2, base_m: 0.2, left: { on: true, width_m: 0.2, height_m: 0.6, offset_m: 0 }, mid: { on: false, width_m: 0.15, height_m: 0.3, offset_m: 0.525 }, right: { on: true, width_m: 0.2, height_m: 0.6, offset_m: 0 } };
const secU4 = Object.assign({}, secU, { total_width_m: 1.4 });
const recOld = { uid: 'pt_pk_old', family: 'PK', name: 'PK-OLD', concrete: 'C30/37', section: secU };
const recBlank = { uid: 'pt_pk_bl', family: 'PK', name: 'PK-BL', concrete: 'C30/37', section: secU4, seat_left_m: '', seat_right_m: ' ' };
js('precastTypes.push(' + JSON.stringify(recOld) + ',' + JSON.stringify(recBlank) + ');renderPrecastTypes();refreshAllPDRowOptions()');
const S = JSON.stringify(secU);
ok(js('mstPkGeomSig(' + S + ",'',null)") === js('mstPkGeomSig(' + S + ',null,null)') && /\|oturma:-\/-$/.test(js('mstPkGeomSig(' + S + ",' ',undefined)")), 'K3: boş / boşluk dize oturma imzada "-" (null ile aynı)');
ok(/\|oturma:-\/-$/.test(js("mstPkRecSig(typeByUid('pt_pk_bl'))") || ''), 'K3: boş dize oturmalı kaydın imzası "-/-"');
pick('pt_pk_bl');
setv('channel_seat_left_m', '0.33');
let r = sendCh();
ok(r && r.tip_uid === 'pt_pk_bl' && /KAYITLI TİP/.test(txt('pkFormTypeNote')) && /yalnız kesit karşılaştırılır/.test(txt('pkFormTypeNote')), 'K3: boş dize oturmalı kayıt oturmasız sayılır → yalnız kesit, tip bağı kurulur');
pick('pt_pk_old');
const nt = txt('pkFormTypeNote');
ok(!/kurulamaz/.test(nt) && /oturma payı yok \(eski kayıt\): formdaki değer korundu/.test(nt) && /yalnız kesit karşılaştırılır/.test(nt) && /bu tipe bağlanır/.test(nt), 'K2: oturmasız eski kayıtta "tip bağı kurulamaz" yok; tek metin: kesitle bağ kurulur');
ok((sendCh() || {}).tip_uid === 'pt_pk_old', 'K2: eski kayıtta kesit aynı → tip_uid gönderilir');
pick('');

// 3. Ö3 plan_pids ve plan_degisti
const secL = { v: 1, preset: 'L', total_width_m: 1.0, base_m: 0.2, left: { on: false, width_m: 0.2, height_m: 0.6, offset_m: 0 }, mid: { on: false, width_m: 0.15, height_m: 0.3, offset_m: 0.425 }, right: { on: true, width_m: 0.2, height_m: 0.6, offset_m: 0 } };
const recL = { uid: 'pt_pk_L', family: 'PK', name: 'PK-005', title: 'L Kanal 1000', pk_rev: 2, concrete: 'C30/37', section: secL, fw_bottom: true, fw_sides: true, fw_inner: true, fw_ends: true, fw_ledge: true, seat_left_m: 0.1, seat_right_m: 0.1 };
js('precastTypes.push(' + JSON.stringify(recL) + ');renderPrecastTypes();refreshAllPDRowOptions()');
pick('pt_pk_L');
setv('channel_right_height_m', '0.65');
D.calls.splice(0);
ok(clickId('pkUpdPlanBtn') === 'tik' && take('pk_type_update_plan').length === 1, 'Ö3: plan istendi');
const plan = { ok: true, tip: { uid: 'pt_pk_L', kod: 'PK-005', rev: 2 }, yeni_rev: 3, kapsam: 'yapi', yapi: 'ANO-01', baslatilabilir: true, neden: null, geom_degisti: true, kapsam_disi: [],
  ornekler: [{ pid: 11, uid: 'u1', kod: 'PK-005', uygun: true, nedenler: [] }, { pid: 12, uid: 'u2', kod: 'PK-005', uygun: true, nedenler: [] }, { uid: 'u3', kod: 'PK-005', uygun: true, nedenler: [] }], yapi_ozet: [{ yapi: 'ANO-01', adet: 3, uygun_degil: 0 }] };
js('mstPkTypePlan(' + JSON.stringify(plan) + ')');
ok(!dis('pkUpdApplyBtn'), 'Ö3: geçerli planda onay etkin');
ok(clickId('pkUpdApplyBtn') === 'tik', 'Ö3: Onayla ve güncelle tıklandı');
let c = take('pk_type_update_apply');
const aq = c.length === 1 ? JSON.parse(c[0][1]) : null;
ok(aq && aq.onay === true && JSON.stringify(aq.plan_pids) === '[11,12]', 'Ö3: apply isteğinde plan_pids = plandaki pid listesi (pid\'siz örnek atlanır)');
js("mstPkTypeUpdated({ok:false,durum:'plan_degisti',neden:'Kapsama plan sonrası 1 PK eklendi.',kutuphane_json:null})");
ok(/TİP GÜNCELLENMEDİ/.test(txt('pkUpdResult')) && /Kapsama plan sonrası 1 PK eklendi/.test(txt('pkUpdResult')) && /Model değişti; planı yeniden alın/.test(txt('pkUpdResult')), 'Ö3: plan_degisti → neden + "Model değişti; planı yeniden alın"');
ok(dis('pkUpdApplyBtn') && /Model değişti; planı yeniden alın/.test(txt('pkUpdPlan')), 'Ö3: plan bayat, onay pasif');
D.calls.splice(0); js('mstPkUpdApply()');
ok(take('pk_type_update_apply').length === 0, 'Ö3: bayat planla apply gönderilmez (otomatik yeniden deneme yok)');
clickId('pkUpdPlanBtn'); take('pk_type_update_plan');
js('mstPkTypePlan(' + JSON.stringify(plan) + ')');
ok(!dis('pkUpdApplyBtn'), 'Ö3: plan yeniden alınınca onay yeniden etkin');

// 4. K6 PK Sil önizlemesi
js('window.__cf=[];window.confirm=function(m){__cf.push(m);return true}');
D.calls.splice(0);
clickId('pkDeleteBtn');
ok(take('pk_delete_preview').length === 1 && js('__cf.length') === 0 && dis('pkDeleteBtn') && /denetleniyor/.test(txt('pkDeleteResult')), 'K6: önce pk_delete_preview, onay henüz sorulmaz, düğme pasif');
js("mstPkDeletePreview({ok:false,neden:'Seçim kilitli gruptaki PK\\'ları içeriyor.',adet:0,kodlar:[],dosemeler:0})");
ok(js('__cf.length') === 0 && take('pk_delete').length === 0 && /SİLİNMEDİ/.test(txt('pkDeleteResult')) && /kilitli grup/.test(txt('pkDeleteResult')) && !dis('pkDeleteBtn'), 'K6: ok=false → onay yok, silme yok, neden görünür');
clickId('pkDeleteBtn'); take('pk_delete_preview');
js('mstPkDeletePreview({ok:true,neden:null,adet:0,kodlar:[],dosemeler:0})');
ok(js('__cf.length') === 0 && take('pk_delete').length === 0 && /Seçimde kanal prekastı \(PK\) yok/.test(txt('pkDeleteResult')), 'K6: adet 0 → onay yok, silme yok');
clickId('pkDeleteBtn'); take('pk_delete_preview');
js("mstPkDeletePreview({ok:true,neden:null,kodlar:['PK-005']})");
ok(js('__cf.length') === 0 && take('pk_delete').length === 0 && /PK sayısı okunamadı/.test(txt('pkDeleteResult')), 'K6: adet yoksa silme yok');
js('window.confirm=function(m){__cf.push(m);return false}');
clickId('pkDeleteBtn'); take('pk_delete_preview');
js("mstPkDeletePreview({ok:true,neden:null,adet:3,kodlar:['PK-005','PK-005','PK-007'],dosemeler:2})");
ok(js('__cf.length') === 1 && /^3 adet PK \(PK-005, PK-005, PK-007\) silinecek, 2 döşeme yeniden kurulacak\./.test(js('__cf[0]')) && /Ctrl\+Z/.test(js('__cf[0]')), 'K6: onay iletisi "3 adet PK (kodlar) silinecek, 2 döşeme yeniden kurulacak"');
ok(take('pk_delete').length === 0 && !dis('pkDeleteBtn'), 'K6: onay "hayır" → silme yok');
js('window.confirm=function(m){__cf.push(m);return true}');
clickId('pkDeleteBtn'); take('pk_delete_preview');
js("mstPkDeletePreview({ok:true,neden:null,adet:1,kodlar:['PK-005'],dosemeler:[{uid:'d1'}]})");
c = take('pk_delete');
ok(c.length === 1 && c[0].length === 1 && /^1 adet PK \(PK-005\) silinecek, 1 döşeme yeniden kurulacak/.test(js('__cf[__cf.length-1]')), 'K6: onay "evet" → mevcut pk_delete() (dosemeler dizi de sayılır)');
js("mstPkDeletePreview({ok:true,adet:5,kodlar:[],dosemeler:0})");
ok(js('__cf.length') === 2 && take('pk_delete').length === 0, 'K6: istenmemiş / geç önizleme yok sayılır');
js("mstPkDeleted({ok:true,silinen:1,dosemeler:1})");
D.calls.splice(0);

// 5. E1 birleştirme: loadPrecastTypeLibrary (Geri Al / Yinele yolu da bu)
const bi = (u) => js('mstPtBuiltin[' + JSON.stringify(u) + ']');
const userPD = { uid: 'pt_pd_user', family: 'PD', name: 'PD-07', width: 1.1, height: 0.3, concrete: 'C30/37' };
const oldU = { uid: 'pt_pk_u2', family: 'PK', name: 'PK-02', inner_width: 0.8, inner_depth: 0.6, base: 0.2, wall: 0.2, concrete: 'C30/37' };
const savedA = { uid: 'pt_pk_A', family: 'PK', name: 'PK-001', pk_rev: 1, concrete: 'C30/37', section: secU };
const savedG = { uid: 'pt_pk_G', family: 'PK', name: 'PK-009', geom_sig: 'pk1|x', concrete: 'C30/37', section: secU4 };
const localL = Object.assign({}, recL, { pk_rev: 2 });
const local = [JSON.parse(bi('pt_pd_1')), JSON.parse(bi('pt_pv_1')), userPD, oldU, savedA, savedG, localL];
js('precastTypes=' + JSON.stringify(local) + ';renderPrecastTypes();refreshAllPDRowOptions()');
const modelPD = JSON.parse(bi('pt_pd_1')); modelPD.name = 'PD-01M';
const model = [modelPD, Object.assign({}, recL, { pk_rev: 1, title: 'L Kanal (model)' }), { uid: 'pt_pk_M', family: 'PK', name: 'PK-010', pk_rev: 1, concrete: 'C30/37', section: secU }];
ok(js('loadPrecastTypeLibrary(' + JSON.stringify(JSON.stringify(model)) + ')') === true, 'E1: model listesi yüklendi');
ok(uids() === 'pt_pd_1,pt_pd_user,pt_pk_u2,pt_pk_L,pt_pk_M', 'E1: yerel kaydedilmemiş (PD-07, eski U PK-02) korundu, kaydedilmiş-modelde olmayan PK (pk_rev / geom_sig) düştü, dokunulmamış varsayılan düştü, yeni model kaydı eklendi (' + uids() + ')');
ok(js("typeByUid('pt_pd_1').name") === 'PD-01M' && js("typeByUid('pt_pk_L').pk_rev") === 1 && js("typeByUid('pt_pk_L').title") === 'L Kanal (model)', 'E1: aynı uid\'de model kazanır (PD-01M, PK-005 rev 1)');
const before = uids();
ok(js("loadPrecastTypeLibrary('bozuk{')") === false && js("loadPrecastTypeLibrary('{}')") === false && js('loadPrecastTypeLibrary(null)') === false && uids() === before, 'E1: okunamayan / dizi olmayan / null liste değiştirmez');
ok(js("loadPrecastTypeLibrary('')") === true && uids() === 'pt_pd_1,pt_pd_user,pt_pk_u2', 'E1: model kütüphanesi boş (\'\') → kaydedilmiş PK\'lar düşer, kaydedilmemişler kalır');
js('precastTypes=' + JSON.stringify(local) + ';renderPrecastTypes()');
ok(js("loadPrecastTypeLibrary('[]')") === true && uids() === 'pt_pd_1,pt_pv_1,pt_pd_user,pt_pk_u2', 'E1: boş dizi → varsayılanlar ve kaydedilmemişler kalır, kaydedilmiş PK\'lar düşer');

// 6. E1 liste_bayat yanıtları: liste model gerçeğiyle yenilenir, neden görünür, yeniden gönderilmez
js('precastTypes=' + JSON.stringify(local) + ';renderPrecastTypes()');
js("mstPkSaveSend({kod:'PK-090',ad:'Deneme',section:chReadSection(),karar:null},'form')");
take('pk_type_save');
D.calls.splice(0);
js('mstPkTypeSaved(' + JSON.stringify({ ok: false, durum: 'liste_bayat', neden: 'Tip listesi model kütüphanesiyle uyuşmuyor (Geri Al sonrası).', kutuphane_json: JSON.stringify(model) }) + ')');
let after = D.calls.splice(0).map((x) => x[0]);
ok(uids() === 'pt_pd_1,pt_pd_user,pt_pk_u2,pt_pk_L,pt_pk_M', 'E1 kayıt: liste_bayat → liste birleştirilerek yenilendi');
ok(/KAYDEDİLMEDİ/.test(txt('pkSaveResult')) && /Geri Al sonrası/.test(txt('pkSaveResult')) && /modeldeki kütüphaneden yenilendi/.test(txt('pkSaveResult')), 'E1 kayıt: neden + "yenilendi" notu görünür');
ok(after.indexOf('pk_type_save') < 0 && after.indexOf('pk_type_catalog') >= 0 && js('mstPkSave.busy') === false, 'E1 kayıt: otomatik yeniden gönderim yok, PK listesi yenilendi, bekleme bitti');
js('precastTypes=' + JSON.stringify(local) + ';renderPrecastTypes()');
js("mstPkTypeSaved({ok:false,durum:'hata',neden:'Yazım hatası.',kutuphane_json:'[]'})");
ok(uids() === local.map((t) => t.uid).join(','), 'E1 kayıt: diğer hatalarda liste değişmez (önceki davranış)');
js('mstPkLibFileImported(' + JSON.stringify({ ok: false, durum: 'liste_bayat', neden: 'Liste eski.', atlanan: [], kutuphane_json: model }) + ')');
ok(uids() === 'pt_pd_1,pt_pd_user,pt_pk_u2,pt_pk_L,pt_pk_M' && /İÇE ALINMADI/.test(txt('pkLibImpResult')) && /modeldeki kütüphaneden yenilendi/.test(txt('pkLibImpResult')), 'E1 içe al: liste_bayat → liste yenilendi (dizi biçimi), neden + not');
js('precastTypes=' + JSON.stringify(local) + ';renderPrecastTypes()');
pick('pt_pk_L'); setv('channel_right_height_m', '0.65');
clickId('pkUpdPlanBtn'); take('pk_type_update_plan');
js('mstPkTypePlan(' + JSON.stringify(plan) + ')');
clickId('pkUpdApplyBtn'); take('pk_type_update_apply');
js('mstPkTypeUpdated(' + JSON.stringify({ ok: false, durum: 'liste_bayat', neden: 'Tip revizyonu modelde farklı.', kutuphane_json: JSON.stringify(model) }) + ')');
ok(uids() === 'pt_pd_1,pt_pd_user,pt_pk_u2,pt_pk_L,pt_pk_M' && /Tip revizyonu modelde farklı/.test(txt('pkUpdResult')) && /modeldeki kütüphaneden yenilendi/.test(txt('pkUpdResult')), 'E1 güncelle: liste_bayat → liste yenilendi, neden + not');
ok(js('document.getElementById(\'channel_right_height_m\').value') === '0.65', 'E1 güncelle: formdaki kesit korunur');

ok(D.alerts.length === 0, 'alert yok (' + D.alerts.join(' | ') + ')');
ok(D.errors.length === 0, 'console.error / zamanlayıcı hatası yok (' + D.errors.join(' | ') + ')');
console.log(fail ? 'SONUÇ: ' + fail + ' HATA' : 'SONUÇ: hepsi geçti');
process.exit(fail ? 1 : 0);
