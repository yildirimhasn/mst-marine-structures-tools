# Parti G-a / G3-#12: revision_diff — PID'siz eski revizyon kayitlarinda mukerrer UID eslemesi (saf islev).
# Kullanim: ruby tools/test/g3_revision_pidless.rb <src/marine_structures_tools>
require_relative 'a1_helper'
main = A1.src('main.rb')
A1.load(Host, main, 'def revision_diff(')
h = Host.new
sz = ->(r) { [r[:added].size, r[:deleted].size, r[:changed].size] }

# 1) önceki: PID'siz tek kayıt; güncel: asıl (UID-PID 100) + kopya
prev = [{ 'uid' => 'MST-100-1', 'concrete_m3' => 1.0 }]
curr = [{ uid: 'MST-100-1', pid: 250, concrete_m3: 1.0 }, { uid: 'MST-100-1', pid: 100, concrete_m3: 1.0 }]
r = h.revision_diff(prev, curr)
t('#12 PID\'siz tek kayıt → UID-PID\'e eşit kayıtla eşleşir; kopya eklendi', [sz.(r), r[:added].map { |x| x[:uid] }], [[1, 0, 0], ['MST-100-1~PID-250']])
t('#12 beton farkı yalnız kopya (+1.0)', r[:delta][:concrete_m3], 1.0)
# 2) UID-PID eşleşmesi yok → en küçük PID UID'yi taşır
r = h.revision_diff([{ 'uid' => 'ABC', 'concrete_m3' => 2.0 }], [{ uid: 'ABC', pid: 30, concrete_m3: 2.0 }, { uid: 'ABC', pid: 20, concrete_m3: 2.5 }])
t('#12 UID-PID yok → en küçük PID (20) eşleşir, değişti; 30 eklendi', [sz.(r), r[:changed].map { |x| x[:pid] }, r[:added].map { |x| x[:uid] }], [[1, 0, 1], [20], ['ABC~PID-30']])
# 3) önceki tarafta PID'siz çok kayıt → anahtar çakışması yok (UID~REC-n), hepsi silindi
prev = [{ 'uid' => 'U', 'concrete_m3' => 1.0 }, { 'uid' => 'U', 'concrete_m3' => 3.0 }]
r = h.revision_diff(prev, [{ uid: 'U', pid: 7, concrete_m3: 1.0 }, { uid: 'U', pid: 8, concrete_m3: 3.0 }])
t('#12 PID\'siz çok kayıt: ikisi de silindi (kayıt kaybolmaz), ikisi eklendi', [sz.(r), r[:deleted].map { |x| x['concrete_m3'] }.sort], [[2, 2, 0], [1.0, 3.0]])
t('#12 PID\'siz çok kayıt: beton farkı 0 (çakışmada biri kaybolup fark +3 / +1 çıkmaz)', r[:delta][:concrete_m3], 0.0)
# 4) önceki çok kayıt PID'li ama ortak yok → UID~PID-n
r = h.revision_diff([{ 'uid' => 'U', 'pid' => 1, 'concrete_m3' => 1.0 }, { 'uid' => 'U', 'pid' => 2, 'concrete_m3' => 1.0 }],
                    [{ uid: 'U', pid: 5, concrete_m3: 1.0 }, { uid: 'U', pid: 6, concrete_m3: 1.0 }])
t('#12 ortak PID yok, önceki çok kayıt → 2 silindi 2 eklendi', sz.(r), [2, 2, 0])
# 5) mevcut davranış korunur
r = h.revision_diff([{ 'uid' => 'U', 'pid' => 1, 'concrete_m3' => 1.0 }], [{ uid: 'U', pid: 1, concrete_m3: 1.0 }, { uid: 'U', pid: 2, concrete_m3: 1.0 }])
t('mevcut: ortak PID → kopya U~PID-2 eklendi', r[:added].map { |x| x[:uid] }, ['U~PID-2'])
r = h.revision_diff([{ 'uid' => 'U', 'pid' => 1 }], [{ uid: 'U', pid: 9 }])
t('mevcut: tek kayıt PID değişimi UID ile eşleşir', sz.(r), [0, 0, 0])
r = h.revision_diff([{ 'uid' => 'U', 'pid' => 1, 'concrete_m3' => 1.0 }, { 'uid' => 'U', 'pid' => 2, 'concrete_m3' => 1.0 }], [{ uid: 'U', pid: 1, concrete_m3: 1.0 }, { uid: 'U', pid: 2, concrete_m3: 1.0 }])
t('mevcut: iki tarafta aynı mükerrer → fark yok', sz.(r), [0, 0, 0])
a1_finish
