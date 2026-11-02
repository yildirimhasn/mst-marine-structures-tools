// ADR-0515-I — Aks Yöneticisi gömülü betiği (main.rb project_ano_axis_manager) sahte DOM ile.
// Girdi: n_isim_ruby.rb'nin gerçek project_ano_axis_manager çıktısından ayırdığı <script> gövdesi (model: DOLFEN BD-01 kullanılıyor
// (1 kazık, X-01 / A), BD-02 boş; İSKELE ANO-01, ANO-03 (görünen ad "ANO-02"); BD-01 / X-02 görünen adı "AKS İKİ").
// Çıktı: GEÇTİ/KALDI satırları + PAYLOAD / NKEYS / NEXTCODE (Ruby testi karşılaştırır). Kullanim: node n_isim_js.js <betik.js>
'use strict';
const fs = require('fs');
const code = fs.readFileSync(process.argv[2], 'utf8');
let ok = 0, bad = 0;
function t(l, g, e) { const G = JSON.stringify(g), E = JSON.stringify(e); if (G === E) { ok++; console.log('GEÇTİ  ' + l); } else { bad++; console.log('KALDI  ' + l + ': ' + G + ' (beklenen ' + E + ')'); } }
const alerts = [], confirms = [], sent = [];
let answer = true;
function node(tag, id) {
  return {
    tagName: String(tag).toUpperCase(), id: id || '', value: '', textContent: '', className: '', title: '', placeholder: '',
    readOnly: false, disabled: false, maxLength: -1, inputMode: '', children: [], options: [], listeners: {}, _html: '',
    appendChild(c) { this.children.push(c); if (this.tagName === 'SELECT') this.options.push(c); return c; },
    addEventListener(t, f) { (this.listeners[t] = this.listeners[t] || []).push(f); },
    querySelector() { return node('span'); },
    get innerHTML() { return this._html; }, set innerHTML(v) { this._html = v; this.children = []; this.options = []; }
  };
}
const els = {};
const init = { project: 'P', xprefix: 'X-', xcount: '6', xspacing: '5.60', yprefix: '', ycount: '3', yspacing: '2.50', xMode: 'INDEPENDENT', yMode: 'INDEPENDENT',
  xRefSystem: 'DOLFEN', yRefSystem: 'DOLFEN', xDirection: '+X', yDirection: '+Y', xDistance: '0.00', yDistance: '0.00' };
const selects = ['structure', 'system', 'xRefStructure', 'yRefStructure', 'xRefAxis', 'yRefAxis', 'xTargetAxis', 'yTargetAxis', 'xMode', 'yMode', 'xRefSystem', 'yRefSystem', 'xLocalDir', 'yLocalDir', 'xDirection', 'yDirection'];
global.document = {
  readyState: 'complete',
  getElementById(id) { if (!els[id]) { els[id] = node(selects.includes(id) ? 'select' : 'div', id); if (init[id] !== undefined) els[id].value = init[id]; } return els[id]; },
  createElement(t) { return node(t); }, addEventListener() {}
};
const jsErrors = [];
global.window = { addEventListener(t, f) { if (t === 'error') global.window._err = f; } };
global.alert = (m) => alerts.push(String(m));
global.confirm = (m) => { confirms.push(String(m)); return answer; };
global.sketchup = { axis_manager_v2_save(j) { sent.push(JSON.parse(j)); }, axis_manager_v2_show() {} };
const E = (id) => document.getElementById(id);
const fire = (e, t) => (e.listeners[t] || []).forEach((f) => f.call(e, { target: e }));
const opts = (id) => E(id).options.map((o) => o.textContent);
const cell = (d, i, c) => E(d + 'body').children[i].children[c].children[0];
const codes = (d) => E(d + 'body').children.map((tr) => tr.children[0].children[0].value);
try { new Function(code)(); } catch (e) { jsErrors.push(e.message); }
t('Betik hatasız çalışır', jsErrors, []);

// S1 açılış
t('S1 seçici etiketleri (DOLFEN)', opts('structure'), ['BD-01', 'BD-02']);
t('S1 yeni kod önerisi (sonraki boş)', E('newStructure').value, 'BD-03');
t('S1 BD-01 kodu kilitli + açıklama', [E('structCode').readOnly, E('codeNote').textContent], [true, 'Kod değiştirilemez: 1 eleman bu koda bağlı.']);
t('S1 X-01 kodu salt okunur (kullanılıyor), X-02 düzenlenebilir', [cell('x', 0, 0).readOnly, cell('x', 1, 0).readOnly, cell('x', 0, 0).title], [true, false, 'Aks kodu değiştirilemez: 1 eleman bu aksa bağlı.']);
t('S1 Y / A kodu salt okunur (grid_y_axis)', cell('y', 0, 0).readOnly, true);
t('S1 X-02 görünen ad sütunu', cell('x', 1, 1).value, 'AKS İKİ');
t('S1 aks tablosu 9 sütun', E('xbody').children[0].children.length, 9);
t('S1 referans aks seçicisinde "(kod)" eki', opts('xTargetAxis'), ['X-01', 'AKS İKİ (X-02)']);
const lockedChange = cell('x', 0, 0); lockedChange.value = 'X-09'; fire(lockedChange, 'change');
t('S1 kilitli aks kodu değişikliği dinlenmez (eski kusur kapandı)', Object.keys(lockedChange.listeners), []);
E('system').value = 'ISKELE'; fire(E('system'), 'change');
const nextIskele = E('newStructure').value;
t('S1 İSKELE: "(kod)" eki ve sonraki kod ANO-04 (görünen ad ANO-02 hesaba girmez)', [opts('structure'), nextIskele], [['ANO-01', 'ANO-02 (ANO-03)'], 'ANO-04']);
E('system').value = 'DOLFEN'; fire(E('system'), 'change');
console.log('NEXTCODE ' + E('newStructure').value + ',' + nextIskele);

// S2 görünen ad (aktif BD-01)
const setName = (v) => { E('structName').value = v; fire(E('structName'), 'change'); };
const a0 = alerts.length;
['bd-02', 'ANO-02', 'ano-01', 'A/B', 'Ç'.repeat(41)].forEach(setName);
t('S2 5 red: başka kod / başka sistemin adı / başka sistemin kodu / yasak karakter / 41 karakter', alerts.length - a0, 5);
t('S2 red sonrası ad yok', opts('structure')[0], 'BD-01');
setName('yanaşma dolfeni-01');
t('S2 ad verildi: seçici ve başlık "(kod)" ekli', [opts('structure')[0], E('axisTitle').textContent], ['yanaşma dolfeni-01 (BD-01)', 'AKS SİSTEMİ — yanaşma dolfeni-01 (BD-01)']);

// S3 C seçeneği: boş yapı BD-02 kodu
E('structure').value = 'BD-02'; fire(E('structure'), 'change');
t('S3 BD-02 kodu düzenlenebilir + açıklama', [E('structCode').readOnly, E('codeNote').textContent.indexOf('Kod değiştirilebilir') === 0], [false, true]);
const a1 = alerts.length;
E('structCode').value = 'bd-01'; fire(E('structCode'), 'change');
t('S3 başka kodla çakışan kod reddedilir', [alerts.length - a1, E('structCode').value], [1, 'BD-02']);
E('structCode').value = 'BD-07'; fire(E('structCode'), 'change');
t('S3 kod BD-02 → BD-07 (yerel)', opts('structure'), ['yanaşma dolfeni-01 (BD-01)', 'BD-07']);

// S4 Düzenli Oluştur (BD-01; X-01 kullanılıyor) ve aks ekleme
E('structure').value = 'BD-01'; fire(E('structure'), 'change');
E('xcount').value = '3';
answer = false; const c0 = confirms.length; fire(E('genX'), 'click');
t('S4 kullanılan aks varsa önizleme + onay; vazgeç → değişmez', [confirms.length - c0, confirms[confirms.length - 1].indexOf('Kullanılan akslar: X-01') >= 0, codes('x')], [1, true, ['X-01', 'X-02']]);
answer = true; fire(E('genX'), 'click');
t('S4 onay → X-01..X-03; aynı koddaki görünen ad korunur', [codes('x'), cell('x', 1, 1).value], [['X-01', 'X-02', 'X-03'], 'AKS İKİ']);
fire(E('addX'), 'click');
t('S4 aks ekleme sonraki boş kod (X-04)', codes('x'), ['X-01', 'X-02', 'X-03', 'X-04']);
const a2 = alerts.length;
const x3 = cell('x', 2, 0); x3.value = 'x-02'; fire(x3, 'change');
t('S4 kullanılmayan aks kodu: aynı yöndeki kodla çakışma reddi', [alerts.length - a2, codes('x')[2]], [1, 'X-03']);
cell('x', 2, 0).value = 'X-05'; fire(cell('x', 2, 0), 'change');
t('S4 kullanılmayan aks kodu değiştirilebilir', codes('x'), ['X-01', 'X-02', 'X-05', 'X-04']);
const d3 = cell('x', 2, 1); d3.value = 'x-01'; fire(d3, 'change');
t('S4 aks görünen adı aynı yöndeki kodla çakışma reddi', [alerts.length - a2, cell('x', 2, 1).value], [2, '']);

// S5 kayıt önizlemesi + onay
answer = false; const c1 = confirms.length; fire(E('saveAll'), 'click');
t('S5 önizleme vazgeç → gönderim yok', [confirms.length - c1, sent.length, E('status').textContent], [1, 0, 'Kaydetme iptal edildi; hiçbir şey değişmedi.']);
const pv = confirms[confirms.length - 1];
t('S5 önizleme metni (eski → yeni, kod, eleman verisi değişmez)', ['Yapı BD-01: (ad yok) → "yanaşma dolfeni-01"', 'Kod: BD-02 → BD-07', 'Eleman verisi değişmez'].map((s) => pv.indexOf(s) >= 0), [true, true, true]);
answer = true; fire(E('saveAll'), 'click');
const p = sent[0] || {};
t('S5 yük: structure_names / code_changes / sistem listesi / aks ağı anahtarı', [p.structure_names, p.code_changes, p.systems && p.systems.DOLFEN, !!(p.grids && p.grids['DOLFEN::BD-07']), !!(p.grids && p.grids['DOLFEN::BD-02'])],
  [{ 'ANO-03': 'ANO-02', 'BD-01': 'yanaşma dolfeni-01' }, [{ system: 'DOLFEN', from: 'BD-02', to: 'BD-07' }], ['BD-01', 'BD-07'], true, false]);
console.log('PAYLOAD ' + JSON.stringify(p));
window.mstNamesSaved();
const c2 = confirms.length; fire(E('saveAll'), 'click');
t('S6 kayıttan sonra değişikliksiz kayıt onay istemez, kod değişikliği yok', [confirms.length - c2, sent.length, sent[1] && sent[1].code_changes], [0, 2, []]);

// S7 yeni yapı
const a3 = alerts.length;
E('newStructure').value = 'bd-01'; fire(E('addStructure'), 'click');
t('S7 mevcut kodla çakışan yeni yapı reddi', alerts.length - a3, 1);
E('newStructure').value = 'BD-03'; E('newStructureName').value = 'Yeni Dolfen'; fire(E('addStructure'), 'click');
t('S7 yeni yapı kod + görünen ad; sonraki öneri BD-08', [opts('structure'), E('newStructure').value, E('structCode').readOnly], [['yanaşma dolfeni-01 (BD-01)', 'BD-07', 'Yeni Dolfen (BD-03)'], 'BD-08', false]);

// JS anahtarı (Ruby mst_name_key ile karşılaştırılır)
const fnSrc = code.split('\n').filter((l) => l.indexOf('function clean(') === 0 || l.indexOf('function nkey(') === 0).join('\n');
const nkey = new Function(fnSrc + '\nreturn nkey;')();
const samples = ['yanaşma dolfeni', 'KIYI', 'kıyı', 'Kiyi', 'KİYİ', 'şehir', '  BD   01 ', 'İskele', 'ışık', 'IŞIK', 'çağ öğün'];
const out = {}; samples.forEach((s) => { out[s] = nkey(s); });
console.log('NKEYS ' + JSON.stringify(out));
console.log(ok + ' geçti, ' + bad + ' kaldı');
process.exit(bad ? 1 : 0);
