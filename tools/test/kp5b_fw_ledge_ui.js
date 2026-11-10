// ADR-0515-K2 karar 18 (rapor 38 K3) arayüz: taban üstü (BASE_LEDGE) kalıbı seçimi — Kanal Prekastı formu ve kesitli PK tip kartı
// (sahte DOM, SketchUp DIŞINDA). Yalnız JS mantığını sınar: işaretliyken eski girdi birebir (channel_fw_ledge / fw_ledge anahtarı yok),
// kaldırılınca create_flat_precast channel_fw_ledge='0' (main.rb :4615 != '0'), create_channel_precast fw_ledge=false (:4713 key?),
// tip kaydında fw_ledge=false ve kayda giden kütüphanede korunması, genişlik notu. Görünüm, Ruby okuması ve kalıp metrajı kanıtlanmaz.
// Kullanım: node tools/test/kp5b_fw_ledge_ui.js   (çıkış kodu 0 = geçti)
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
const sendCh = () => { js('createChannelPrecast()'); const c = take('create_channel_precast'); return c.length === 1 ? c[0][1] : null; };
const sendPD = () => { js('createPD()'); const c = take('create_flat_precast'); return c.length === 1 ? c[0][1] : null; };
const setLedge = (on) => js("document.getElementById('channel_fw_ledge').checked=" + (on ? 'true' : 'false'));
const note = () => js("document.getElementById('channelFwLedgeNote').textContent");

ok(loadErrors.length === 0, 'sayfa yüklendi (' + loadErrors.join(' | ') + ')');
js('updateChannelPrecastUI()');
D.calls.splice(0); D.errors.splice(0); D.alerts.splice(0);

// 1. Form: onay kutusu var, varsayılan işaretli; gönderimde anahtar yok
ok(js("!!document.getElementById('channel_fw_ledge')") && js("document.getElementById('channel_fw_ledge').checked") === true, 'form: Taban Üstü (Ledge) Kalıbı kutusu var, varsayılan işaretli');
const ch0 = sendCh(), pd0 = sendPD();
ok(ch0 && !own(JSON.parse(ch0), 'fw_ledge'), 'işaretli: create_channel_precast girdisinde fw_ledge yok');
ok(pd0 && !own(JSON.parse(pd0), 'channel_fw_ledge'), 'işaretli: create_flat_precast girdisinde channel_fw_ledge yok');

// 2. Kaldırılınca
setLedge(false);
let ch = sendCh(), pd = sendPD();
ok(ch && JSON.parse(ch).fw_ledge === false, 'kaldırıldı: create_channel_precast fw_ledge=false');
ok(pd && JSON.parse(pd).channel_fw_ledge === '0', 'kaldırıldı: create_flat_precast channel_fw_ledge=\'0\'');
ok(pd && JSON.parse(pd).channel_fw_inner === '1' && JSON.parse(pd).channel_fw_ends === '1', 'kaldırıldı: diğer kalıp alanları değişmedi');
setLedge(true);
ok(sendCh() === ch0 && sendPD() === pd0, 'yeniden işaretli: iki girdi ilk gönderimle birebir aynı');

// 3. Genişlik notu: U'da 0 m → etkisiz; sol çıkıntı Yok → sol 1,000 m
js("chApplyPreset('U')");
ok(/sol 0,000 m · sağ 0,000 m/.test(note()) && /bu kesitte taban üstü yok, seçim etkisizdir/.test(note()), 'form U: genişlik 0 m, seçim etkisiz notu');
js("document.getElementById('channel_left_on').checked=false;chPartToggled()");
ok(/sol 1,000 m · sağ 0,000 m/.test(note()) && /0 m olan tarafta seçim etkisizdir/.test(note()), 'sol çıkıntı Yok: sol 1,000 m, tek taraf notu');
ok(/sol 1,000 m · sağ 0,000 m/.test(js("document.getElementById('channelDeckLedgeNote').textContent")), 'döşeme ledge notu ortak ölçüyle aynı (3af76ef)');
js("document.getElementById('channel_left_on').checked=true;chApplyPreset('U')");

// 4. Tip kartı: yalnız kesitli PK
const secL = { v: 1, preset: 'L', total_width_m: 1.2, base_m: 0.2, left: { on: false, width_m: 0.2, height_m: 0.6, offset_m: 0 }, mid: { on: false, width_m: 0.15, height_m: 0.3, offset_m: 0.525 }, right: { on: true, width_m: 0.2, height_m: 0.6, offset_m: 0 } };
js("precastTypes.push({uid:'pt_pk_l',family:'PK',name:'PK-L',concrete:'C30/37',zz_bilinmeyen:7,section:" + JSON.stringify(secL) + "});renderPrecastTypes();refreshAllPDRowOptions()");
let lt = js("document.getElementById('precastTypeLibrary').textContent");
ok((lt.match(/Taban üstü \(ledge\) kalıbı/g) || []).length === 1, 'yalnız kesitli PK kartında kalıp seçimi var (kesitsiz PK-01\'de yok)');
ok(/sol 1,000 m · sağ 0,000 m/.test(lt), 'tip kartı L: kesitten genişlik notu');
const fieldL = () => js("mstPkFwLedgeField(typeByUid('pt_pk_l'),mstPkSectionOf(typeByUid('pt_pk_l')))");
ok(/<input type="checkbox" checked onchange="mstPkSetFwLedge\('pt_pk_l',this.checked\)"/.test(fieldL()), 'tip kartı: varsayılan işaretli');
const before = js("JSON.stringify(typeByUid('pt_pk_l'))");
js("mstPkSetFwLedge('pt_pk_l',true)");
ok(js("JSON.stringify(typeByUid('pt_pk_l'))") === before, 'işaretli seçimi kaydı değiştirmez (anahtar yok)');
js("mstPkSetFwLedge('pt_pk_l',false)");
ok(js("typeByUid('pt_pk_l').fw_ledge") === false && !own(JSON.parse(js("JSON.stringify(typeByUid('pt_pk_l').section)")), 'fw_ledge'), 'kaldırıldı: tipte fw_ledge=false (kesite yazılmadı)');
let sv = JSON.parse(js("JSON.stringify(mstPkLibraryForSave(precastTypes).filter(function(t){return t.uid==='pt_pk_l'})[0])"));
ok(sv.fw_ledge === false && sv.zz_bilinmeyen === 7, 'kayda giden kütüphanede fw_ledge=false ve bilinmeyen alan var');
pd = sendPD();
const lib = pd ? JSON.parse(JSON.parse(pd).precast_type_library) : [];
ok(lib.some((t) => t.uid === 'pt_pk_l' && t.fw_ledge === false), 'create_flat_precast precast_type_library içinde fw_ledge=false');
js('renderPrecastTypes()');
ok(/<input type="checkbox" onchange="mstPkSetFwLedge\('pt_pk_l'/.test(fieldL()), 'yeniden çizimde işaretsiz');
js("mstPkSetFwLedge('pt_pk_l',true)");
ok(js("JSON.stringify(typeByUid('pt_pk_l'))") === before, 'yeniden işaretli: anahtar silindi, kayıt ilk haliyle aynı');
ok(js("mstPkFwLedgeOn({fw_ledge:null})") === true && js("mstPkFwLedgeOn({fw_ledge:false})") === false && js("mstPkFwLedgeOn({fw_ledge:true})") === true && js("mstPkFwLedgeOn({})") === true, 'okuma (tip kaydı, channel_section.rb:154 mst_ch_ledge_off?): yok/true/null kalıplı, false kalıpsız');

// 5. Tip kartı U (channel_section_json metni): genişlik 0 → etkisiz
const secU = { v: 1, preset: 'U', total_width_m: 1.2, base_m: 0.2, left: { on: true, width_m: 0.2, height_m: 0.6, offset_m: 0 }, mid: { on: false, width_m: 0.15, height_m: 0.3, offset_m: 0.525 }, right: { on: true, width_m: 0.2, height_m: 0.6, offset_m: 0 } };
js("precastTypes.push({uid:'pt_pk_u',family:'PK',name:'PK-U',concrete:'C30/37',channel_section_json:" + JSON.stringify(JSON.stringify(secU)) + "});renderPrecastTypes()");
ok(/Tip kesitinden genişlik: sol 0,000 m · sağ 0,000 m — bu kesitte taban üstü yok, seçim etkisizdir/.test(js("document.getElementById('precastTypeLibrary').textContent")), 'tip kartı U: 0 m, etkisiz notu');
ok(!own(JSON.parse(js("JSON.stringify(typeByUid('pt_pk_1'))")), 'fw_ledge'), 'kesitsiz eski kayda anahtar eklenmedi');

ok(D.errors.length === 0, 'console.error / zamanlayıcı hatası yok (' + D.errors.join(' | ') + ')');
console.log(fail ? 'SONUÇ: ' + fail + ' HATA' : 'SONUÇ: hepsi geçti');
process.exit(fail ? 1 : 0);
