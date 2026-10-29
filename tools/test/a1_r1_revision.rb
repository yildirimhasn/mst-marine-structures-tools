# A1 / R-1 (K02, K03, K26) + K06(c): revizyon snapshot'i. docs/denetim/.../t_h1_snapshot.rb'nin uyarlamasi;
# ilk 6 kontrol H1 ile ayni (0.51.4'te 3 geçti, 3 kaldı).
# Kullanim: ruby tools/test/a1_r1_revision.rb <src/marine_structures_tools>
require_relative 'a1_helper'
main = A1.src('main.rb')
boq = A1.src('boq_pro.rb')

class Host
  attr_accessor :curr, :digest, :cur_raise
  def revision_current_snapshot; @curr || []; end
  def revision_send(_d = nil); $log << [:send]; end
  def boq2_boq_digest; @digest || [{ 'source' => 'S1', 'quantity' => 1.0, 'unit_price' => 10.0 }]; end
  def boq2_currency; raise 'kur okunamadı (test)' if @cur_raise; 'TRY'; end
end
A1.load(Host, main, 'def revision_snapshots', 'def revision_save_snapshots', 'def revision_diff(', 'def revision_create_snapshot(')
Host.class_eval('alias_method :revision_create_snapshot_base, :revision_create_snapshot unless method_defined?(:revision_create_snapshot_base)')
A1.load(Host, boq, 'def revision_create_snapshot(', 'def boq2_boq_diff(')
has_dup = A1.load_opt(Host, boq, 'def mst_dup_uid_continue?')
obs('mst_dup_uid_continue? tanımlı', has_dup)
snaps = -> { JSON.parse($model.get_attribute('MAG_MST_RevisionLog', 'snapshots', '[]')) }
snap = lambda do |h|
  begin
    h.revision_create_snapshot(nil)
  rescue => e
    $msgs << "YAKALANMAYAN HATA: #{e.message}"
    :exception
  end
end

h = Host.new
# ---- H1 (aynı 6 kontrol)
a1_reset!
20.times { |i| h.curr = [{ uid: "U#{i}", pid: i + 1 }]; snap.(h) }
s = snaps.()
t('H1 20 kayıt sonrası adet', s.size, 20)
t('H1 20 kayıt adları Rev.01..Rev.20', s.map { |x| x['revision'] }, (1..20).map { |n| format('Rev.%02d', n) })
t('H1 20. kayıtta keşif (boq) var', s.last.key?('boq'), true)
h.curr = [{ uid: 'U20', pid: 21 }]; snap.(h)
h.curr = [{ uid: 'U21', pid: 22 }]; snap.(h)
t('H1 21. kayıt: Rev.01 korunur (geçmiş silinmez)', snaps.().any? { |x| x['revision'] == 'Rev.01' }, true)
t('H1 22. kayıt: ad tekil (Rev.22)', snaps.().last['revision'], 'Rev.22')
t('H1 22. kayıtta keşif (boq) eklenir', snaps.().last.key?('boq'), true)
obs('22 kayıt sonrası adet', snaps.().size)

# ---- K03: tek işlem
a1_reset!
h.curr = [{ uid: 'A', pid: 1 }]; snap.(h)
t('K03 bir snapshot = tek start + tek commit', ops, [:start, :commit])
t('K03 yazmalar işlem içinde (start..commit arasında)', $log.index { |x| x[0] == :start }.to_i < $log.index { |x| x[0] == :set }.to_i && $log.rindex { |x| x[0] == :set }.to_i < ($log.index { |x| x[0] == :commit } || -1), true)
t('K03 last_revision', $model.get_attribute('MAG_MST_RevisionLog', 'last_revision'), 'Rev.01')

# ---- R-1: fark yoksa revizyon oluşmaz; yalnız fiyat değişikliği revizyon üretmez; miktar değişikliği üretir
$log = []; $msgs = []
snap.(h)
t('R-1 değişiklik yok → yeni kayıt yok', snaps.().size, 1)
t('R-1 değişiklik yok → işlem açılmaz', ops, [])
t('R-1 değişiklik yok iletisi', $msgs.any? { |m| m.include?('değişiklik yok; yeni revizyon oluşturulmadı') }, true)
h.digest = [{ 'source' => 'S1', 'quantity' => 1.0, 'unit_price' => 99.0 }]
snap.(h)
t('R-1 yalnız fiyat değişti → yeni kayıt yok', snaps.().size, 1)
h.digest = [{ 'source' => 'S1', 'quantity' => 2.0, 'unit_price' => 99.0 }]
snap.(h)
t('R-1 keşif miktarı değişti → Rev.02', snaps.().last['revision'], 'Rev.02')

# ---- R-1: numara = en büyük Rev.NN + 1 (boşluklu arşiv)
a1_reset!
$model.set_attribute('MAG_MST_RevisionLog', 'snapshots', JSON.generate([{ 'revision' => 'Rev.01', 'elements' => [] }, { 'revision' => 'Rev.05', 'elements' => [] }]))
h.curr = [{ uid: 'B', pid: 2 }]; snap.(h)
t('R-1 boşluklu arşivde yeni ad Rev.06', snaps.().last['revision'], 'Rev.06')
t('R-1 önceki kayıtlar değişmedi', snaps.().first(2).map { |x| x['revision'] }, %w[Rev.01 Rev.05])

# ---- K26: bozuk arşiv → Türkçe ileti, işlem açılmaz, bayt değişmez
a1_reset!
bad = '{bozuk'
$model.set_attribute('MAG_MST_RevisionLog', 'snapshots', bad); $log = []
r = snap.(h)
t('K26 bozuk arşiv: yakalanmamış hata yok', r == :exception, false)
t('K26 bozuk arşiv: "Revizyon kaydedilemedi" iletisi', $msgs.any? { |m| m.start_with?('Revizyon kaydedilemedi') }, true)
t('K26 bozuk arşiv: işlem açılmaz', ops, [])
t('K26 bozuk arşiv: kayıt baytları aynı', $model.get_attribute('MAG_MST_RevisionLog', 'snapshots'), bad)

# ---- K26: işlem içinde hata → abort
a1_reset!
h.curr = [{ uid: 'C', pid: 3 }]; h.cur_raise = true
r = snap.(h); h.cur_raise = false
t('K26 işlem içi hata: start + abort', ops, [:start, :abort])
t('K26 işlem içi hata: ileti', $msgs.any? { |m| m.include?('kur okunamadı') }, true)

# ---- R-1 boyut uyarısı (>20 kayıt)
a1_reset!
$model.set_attribute('MAG_MST_RevisionLog', 'snapshots', JSON.generate((1..20).map { |n| { 'revision' => format('Rev.%02d', n), 'elements' => [] } }))
h.curr = [{ uid: 'D', pid: 4 }]; snap.(h)
t('R-1 21. kayıtta arşiv büyüdü uyarısı', $msgs.any? { |m| m.start_with?('Revizyon arşivi büyüdü (21 kayıt') }, true)
t('R-1 21 kayıt saklandı', snaps.().size, 21)

# ---- K06(c): mükerrer UID sorusu, Hayır → kayıt yok
a1_reset!
$model.entities = [FakeEnt.new(10, 'element_type' => 'deck_slab', 'element_uid' => 'MST-10-1'), FakeEnt.new(11, 'element_type' => 'deck_slab', 'element_uid' => 'MST-10-1')]
$ui_answer = IDNO
h.curr = [{ uid: 'E', pid: 5 }]; snap.(h)
t('K06(c) mükerrer UID sorusu soruldu', $msgs.any? { |m| m.start_with?('Modelde 1 mükerrer UID var') }, true)
t('K06(c) Hayır → snapshot yok', snaps.().size, 0)
# ---- R-1 donatı revizyon geçmişi kırpılmaz (mst_rebar_tools.rb mst_rt_history_push!)
rt = A1.src('mst_rebar_tools.rb')
Host.const_set(:MST_RT_HISTORY_MAX, 10) unless Host.const_defined?(:MST_RT_HISTORY_MAX)
A1.load(Host, rt, 'def mst_rt_history(e)', 'def mst_rt_history_push!(')
a1_reset!; bk = FakeEnt.new(40, 'element_type' => 'head_beam', 'rebar_mode' => 'auto_detail')
12.times { |i| bk.set_attribute(A1::DICT, 'rebar_schedule_json', "{\"P#{i}\":{}}"); bk.set_attribute(A1::DICT, 'rebar_kg', i.to_f); h.mst_rt_history_push!(bk) }
t('R-1 donatı geçmişi 12 kayıt korunur (kırpma yok)', JSON.parse(bk.a('rebar_history_json')).size, 12)
a1_finish
