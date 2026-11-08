// K1 (ADR-0515-K1): Aks Yöneticisi "Yapıyı Kopyala" düğmesi — kaydedilmemiş değişiklik denetimi (sahte DOM, node).
// Girdi: k1_structure_copy.rb'nin K1_HTML_OUT ile yazdığı gerçek project_ano_axis_manager HTML'i.
// Kullanim: node tools/test/k1_axis_dirty.js <html dosyası>
'use strict';
const fs = require('fs');
const { makeContext } = require('./u_fakedom');
const html = fs.readFileSync(process.argv[2], 'utf8');
let ok = 0, bad = 0;
function t(label, got, exp) { const g = JSON.stringify(got) === JSON.stringify(exp); g ? ok++ : bad++; console.log((g ? 'GEÇTİ' : 'KALDI') + '  ' + label + ': ' + JSON.stringify(got) + ' (beklenen ' + JSON.stringify(exp) + ')'); }
function page() {
  const D = makeContext(html);
  D.doc.readyState = 'complete';
  const code = html.match(/<script>([\s\S]*)<\/script>/)[1];
  const e = D.run(code, 'aks_yoneticisi.js');
  return { D, e };
}
const copies = (D) => D.calls.filter((c) => c[0] === 'axis_manager_structure_copy');
const fire = (el, type) => el.dispatchEvent({ type, target: el, preventDefault() {}, stopPropagation() {} });

let { D, e } = page();
t('betik hatasız yüklendi', [e, D.errors], [null, []]);
const el = (id) => D.doc.getElementById(id);
el('copyStructure').click();
t('değişiklik yokken: sketchup.axis_manager_structure_copy çağrılır, dirty=false', copies(D).map((c) => JSON.parse(c[1])), [{ system: 'ISKELE', structure: 'ANO-01', dirty: false }]);
t('uyarı yok', D.alerts, []);
// yapı değiştirme (yalnız görünüm) kirli sayılmaz
el('structure').value = 'ANO-05'; fire(el('structure'), 'change');
el('copyStructure').click();
t('aktif yapı değiştirmek kirli sayılmaz; kaynak = aktif yapı', copies(D).map((c) => JSON.parse(c[1]).structure), ['ANO-01', 'ANO-05']);
// aks ekleme → kirli
el('addX').click();
el('copyStructure').click();
t('aks eklendikten sonra: çağrı yok, uyarı var', [copies(D).length, D.alerts.length, (D.alerts[0] || '').indexOf('kaydedilmemiş') >= 0], [2, 1, true]);
// kayıt sonrası (mstNamesSaved) yeniden temiz
D.ctx.mstNamesSaved();
el('copyStructure').click();
t('kayıt sonrası (mstNamesSaved) temiz: çağrı yapılır', copies(D).length, 3);
// yeni yapı (kaydedilmemiş) → kirli
({ D } = page());
el('newStructure').value = 'ANO-09'; el('addStructure').click();
el('copyStructure').click();
t('kaydedilmemiş yeni yapı: çağrı yok, uyarı var', [copies(D).length, D.alerts.length], [0, 1]);
// 32/8: başarılı kopyadan sonra (Ruby mstStructureCopied çağırır) pencere yenilenmezse eski durum kaydedilemez / kopyalanamaz
({ D } = page());
t('32/8 mstStructureCopied tanımlı', typeof D.ctx.mstStructureCopied, 'function');
if (typeof D.ctx.mstStructureCopied === 'function') D.ctx.mstStructureCopied();
const saves = () => D.calls.filter((c) => c[0] === 'axis_manager_v2_save').length;
el('saveAll').click(); el('saveGrid').click(); el('showGrid').click(); el('copyStructure').click();
t('32/8 kopya sonrası eski pencere: Projeyi Kaydet / Aks Kaydet / Göster ve Yapıyı Kopyala çağrı yapmaz, uyarı verir',
  [saves(), copies(D).length, D.calls.filter((c) => c[0] === 'axis_manager_v2_show').length, D.alerts.length >= 4, (D.alerts[0] || '').indexOf('yeniden açın') >= 0], [0, 0, 0, true, true]);
console.log(ok + ' geçti, ' + bad + ' kaldı');
process.exit(bad ? 1 : 0);
