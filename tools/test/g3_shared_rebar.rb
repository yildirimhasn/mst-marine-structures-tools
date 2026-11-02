# Parti G-a / G3-#11: paylasilan Component BK'da cizimden / otomatik donati silme ve eski donatiyi yeniden cizme.
# Soru islemden once (mst_shared_def_prompt), "ayir" islem icinde (mst_make_unique_keep_data!); 383 gecmis kosulu;
# #6: mst_dr_remove_ui hata yolunda Turkce ileti.
# Kullanim: ruby tools/test/g3_shared_rebar.rb <src/marine_structures_tools>
require_relative 'a2_helper'
main = A1.src('main.rb')
dw = A1.src('mst_dwg_rebar.rb')
rt = A1.src('mst_rebar_tools.rb')
$answers = []
module UI
  def self.messagebox(m, _t = nil); $msgs << m.to_s; $answers.empty? ? $ui_answer : $answers.shift; end
end
class Host
  MST_DR_MODE = 'drawing_detail'.freeze
  def mst_dr_clear!(x); raise 'sahte silme hatası' if $clear_fail; $log << [:clear, x]; true; end
  def send_boq(*_a); end
  def collect_elements(_ents, out); out.concat($all); end
  def mst_rt_legacy_elems(_m = nil); $legacy; end
  def mst_rt_upgrade!(e); $log << [:upgrade, e]; [true, 'ok']; end
  def mst_rt_visible_note; ''; end
end
A1.load(Host, main, 'def mst_shared_def_prompt(', 'def mst_make_unique_keep_data!(')
A1.load(Host, dw, 'def mst_dr_remove_ui')
A1.load(Host, rt, 'def mst_rt_upgrade_ui')
h = Host.new
D = A1::DICT
seq = -> { $log.map(&:first).select { |x| %i[start make_unique clear upgrade commit abort].include?(x) } }
def shared(n, mode = 'drawing_detail')
  d = Sketchup::ComponentDefinition.new(50, 'mst_def_key' => 'hb-1')
  (1..n).map do |i|
    x = Sketchup::ComponentInstance.new(60 + i, 'element_type' => 'head_beam', 'id' => "BK-#{i}", 'rebar_mode' => mode, 'rebar_kind' => 'DRAWING')
    x.definition = d
    x
  end
end

# ---- mst_dr_remove_ui
a1_reset!; i1, i2, i3 = shared(3); $model.selection = [i1]; $all = [i1, i2, i3]
$answers = [IDYES, IDNO]
r = h.mst_dr_remove_ui
t('#11 paylaşılan tanım, Hayır → iptal, işlem açılmaz, silme yok', [r, seq.()], [0, []])
t('#11 soru metni (tanım 3 yerde)', $msgs.last.to_s.include?('BK-1: bu eleman Component; tanımı 3 yerde kullanılıyor. Çizimden donatı silme'), true)
a1_reset!; $model.selection = [i1]; $answers = [IDYES, IDYES]
r = h.mst_dr_remove_ui
t('#11 Evet → işlem içinde önce ayır sonra sil, tek işlem', [r, seq.()], [1, %i[start make_unique clear commit]])
t('#11 Evet → seçili parça yeni tanımda, diğer 2 parça eski tanımda', [i1.definition.count_instances, i2.definition.count_instances, i2.definition == i3.definition], [1, 2, true])
t('#11 ayrılan tanım verisi korunur (mst_def_unique_of)', i1.definition.get_attribute(D, 'mst_def_unique_of'), 'hb-1')
a1_reset!; j1, j2 = shared(2); $model.selection = [j1, j2]; $all = [j1, j2]; $answers = [IDYES]
r = h.mst_dr_remove_ui
t('#11 tanımın tüm örnekleri seçili → soru yok, ayırma yok', [r, $msgs.length, seq.()], [2, 1, %i[start clear clear commit]])
a1_reset!; g = Sketchup::Group.new(70, 'element_type' => 'head_beam', 'id' => 'BK-G', 'rebar_mode' => 'drawing_detail'); $model.selection = [g]; $all = [g]
h.mst_dr_remove_ui
t('#11 Group → soru yok', [$msgs.length, seq.()], [1, %i[start clear commit]])
# ---- #6 hata yolu
a1_reset!; $model.selection = [g]; $clear_fail = true
r = h.mst_dr_remove_ui
$clear_fail = false
t('#6 silme hatası → işlem geri alınır, Türkçe ileti, dönüş 0', [r, seq.(), $msgs.last], [0, %i[start abort], 'Donatı silinemedi: sahte silme hatası'])

# ---- mst_rt_upgrade_ui (ayrı öneri: aynı paylaşım koruması)
a1_reset!; k1, k2, k3 = shared(3, 'auto_detail'); $legacy = [k1]; $answers = [IDYES, IDNO]
r = h.mst_rt_upgrade_ui
t('upgrade: paylaşılan tanım, Hayır → iptal, işlem açılmaz', [r, seq.()], [0, []])
t('upgrade: soru metni', $msgs.last.to_s.include?('Donatıyı yeni kurallarla yeniden çizme'), true)
a1_reset!; $legacy = [k1]; $answers = [IDYES, IDYES]
h.mst_rt_upgrade_ui
t('upgrade: Evet → işlem içinde ayır, sonra yeniden çiz', seq.(), %i[start make_unique upgrade commit])
t('upgrade: diğer 2 parça eski tanımda', [k1.definition.count_instances, k2.definition.count_instances], [1, 2])
a1_reset!; m1, m2 = shared(2, 'auto_detail'); $legacy = [m1, m2]; $answers = [IDYES]
h.mst_rt_upgrade_ui
t('upgrade: tüm örnekler listede → soru yok', seq.(), %i[start upgrade upgrade commit])

# ---- 383 geçmiş koşulu (mst_dr_clear! gerçek işlev)
class Host
  def mst_rt_history_push!(e); $log << [:hist, e]; end
  def mst_dr_set_of(e); e.get_attribute(DICT, 'fake_set', false) ? [:set] : []; end
  def mst_dr_erase_set!(_g); end
  def qto3_quantity(_e, _k); 10.0; end
  def rebar_rate(_k); 150.0; end
  def mst_dr_purge_defs!(_m); end
end
A1.load(Host, dw, 'def mst_dr_clear!(')
hist = ->(e) { $log = []; h.mst_dr_clear!(e); $log.count { |x| x[0] == :hist } }
t('383: set var → geçmişe alınır', hist.(Sketchup::Group.new(80, 'element_type' => 'head_beam', 'fake_set' => true, 'rebar_mode' => 'drawing_detail')), 1)
t('383: set yok (paylaşılan tanımda önceki örnek sildi), drawing_detail → geçmişe alınır', hist.(Sketchup::Group.new(81, 'element_type' => 'head_beam', 'rebar_mode' => 'drawing_detail')), 1)
t('383: set yok, auto_detail → geçmişe alınır', hist.(Sketchup::Group.new(82, 'element_type' => 'head_beam', 'rebar_mode' => 'auto_detail')), 1)
t('383: set yok, kayıt yok → geçmiş yok', hist.(Sketchup::Group.new(83, 'element_type' => 'head_beam')), 0)
a1_finish
