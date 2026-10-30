# Parti B / K51 (kalip yuz anahtari; G1), K56 (Alt-1 ayni istasyon; G1), K61 (tam donusum zinciri; G1),
# K16/K17/K18 (menfez kaydi, net kalip), K29 (JSON callback, N8 tip, aks adi / </script> kacisi), K45 (TB_HIDDEN),
# DXF birim (paftadan donati "L =" ve otomatik pafta toleransi), A2 aktarimlari (id_groups asil oge, pile_owned_concrete sirasi).
# Kullanim: ruby tools/test/b_misc.rb <src/marine_structures_tools>
require_relative 'b_helper'
main = A1.src('main.rb')
bm = A1.src('mst_v50_beams.rb')
rt = A1.src('mst_rebar_tools.rb')
dxr = A1.src('mst_dx_rebar.rb')
dra = A1.src('mst_dr_auto.rb')
dxf = A1.src('mst_dxf.rb')
qs = A1.src('quantity_service.rb')
D = A1::DICT
class Host
  def element_visible_id(e); e.get_attribute(DICT, 'id', "PID-#{e.persistent_id}").to_s; end
end
h = nil

# ------------------------------------------------------------------ K51
A1.load(Host, main, 'def bk_formwork_face_key(', 'def bk_formwork_override_map(', 'def bk_store_formwork_override_map(', 'def bk_apply_formwork_overrides(',
        'def head_beam_formwork_area(', 'def face_area_m2(', 'def mst_hb_ents(')
K51 = A1.load_opt(Host, main, 'def bk_formwork_face_keys(')
h = Host.new
faces = -> { [FakeFace.new(101, 'BOTTOM', [0, 0, -1], [0.0, 0.0, 0.0], 18.0), FakeFace.new(102, 'BOTTOM', [0, 0, -1], [18.0, 0.0, -0.5], 1.2)] }
a1_reset!
hb = Sketchup::Group.new(1, 'element_type' => 'head_beam'); hb.entities = faces.()
tooth = hb.entities[1]
# BK Kalip Yuzeyi araci: dis tabanini kaliptan cikar (yuklenen surumun anahtariyla)
key = K51 ? h.bk_formwork_face_keys(hb)[tooth][0] : h.bk_formwork_face_key(tooth)
obs('K51 araç anahtarı', key)
hb.set_attribute(D, 'formwork_face_overrides', JSON.generate(key => 'exclude'))
# BK revizyonu: yuzler yeniden kurulur (yeni Face nesneleri, hepsi kalipta)
hb.entities = faces.(); hb.entities.each { |f| f.set_attribute(D, 'formwork', true) }
ov = h.bk_formwork_override_map(hb, true); h.bk_apply_formwork_overrides(hb, ov, :m)
t('K51 G1/düzeltme: yalnız diş tabanı kalıp dışı kalır, ana taban kalıpta', hb.entities.map { |f| f.a('formwork') }, [true, false])
hb.set_attribute(D, 'formwork_face_overrides', JSON.generate('BOTTOM' => 'exclude'))   # eski surumden kalmis kayit
hb.entities = faces.(); hb.entities.each { |f| f.set_attribute(D, 'formwork', true) }
h.bk_apply_formwork_overrides(hb, h.bk_formwork_override_map(hb, true), :m)
obs('K51 eski (konumsuz) kayıt: bütün BOTTOM yüzlere uygulanır (bilinen sınır)', hb.entities.map { |f| f.a('formwork') })
hb.entities = faces.(); hb.entities[1].set_attribute(D, 'formwork_manual_override', 'exclude')
cap = h.bk_formwork_override_map(hb, true)
t('K51 yüz yakalama yalnız konumlu anahtar yazar', K51 ? cap.keys.include?('BOTTOM@1/2') : cap.keys, K51 ? true : ['BOTTOM@1/2'])

# ------------------------------------------------------------------ K56
class Host
  ROCKFILL_PROJECT_KEY = 'rockfill_section_chain_json'.freeze
  ROCKFILL_PROJECT_KEY_ALT2 = 'rockfill_section_chain_alt02_json'.freeze
  ROCKFILL_ACTIVE_ALT_KEY = 'rockfill_active_alternative'.freeze
  def rockfill_library; [{ 'code' => 'A', 'name' => 'Taş', 'density' => 2.0 }]; end
end
A1.load(Host, main, 'def rockfill_project_key(', 'def rockfill_section_areas(', 'def rockfill_qto_alt1_data')
a1_reset!
secs = [{ 'id' => 'S0', 'station' => 0, 'areas' => { 'A' => 10.0 } }, { 'id' => 'S1', 'station' => 0, 'areas' => { 'A' => 20.0 } }, { 'id' => 'S2', 'station' => 10, 'areas' => { 'A' => 30.0 } }]
$model.set_attribute(D, 'rockfill_section_chain_json', JSON.generate('sections' => secs))
q = Host.new.rockfill_qto_alt1_data
obs("K56 Ruby #{RUBY_VERSION} aralıklar", q[:intervals].map { |i| ["#{i[:from_id]}→#{i[:to_id]}", i[:volume_m3]] })
t('K56 aynı istasyonda kayıt sırası korunur: S1→S2, (20+30)/2×10 = 250 m³ / 500 t', [q[:intervals].map { |i| "#{i[:from_id]}→#{i[:to_id]}" }, q[:total_volume_m3], q[:total_tonnage_t]], [['S1→S2'], 250.0, 500.0])

# ------------------------------------------------------------------ K61
A1.load(Host, rt, 'def mst_rt_world_tr(', 'def mst_rt_clashes(', 'def mst_rt_segdist(', 'def mst_rt_xf(', 'def mst_rt_m(')
class Host; def mst_rt_bars(_e); [{ pts: [[0, 0, 0], [1.0, 0, 0]], d: 20 }]; end; end
grp = Sketchup::Group.new(200, {}); grp.transformation = Geom::Transformation.translation([10 * INCH, 0, 0])
gdef = Sketchup::ComponentDefinition.new(201); gdef.instances << grp
ea = Sketchup::Group.new(202, 'id' => 'BK-A'); ea.transformation = Geom::Transformation.new
eb = Sketchup::Group.new(203, 'id' => 'BK-B'); eb.transformation = Geom::Transformation.new; eb.parent = gdef
t('K61 üst grup içindeki elemanın dünya dönüşümü (x = 10 m)', (h.mst_rt_world_tr(eb).origin.x / INCH).round(6), 10.0)
t('K61 çakışma: yerel koordinatı aynı ama 10 m uzaktaki iki eleman çakışmaz (yanlış pozitif yok)', h.mst_rt_clashes([ea, eb]).length, 0)

# ------------------------------------------------------------------ K16 / K17 / K18
class Host
  def mst_attr_hash(e); e.raw_attrs.select { |(d, _), _| d == DICT }.map { |(_, k), v| [k, v] }.to_h; end
  def mst_cv_draw!(_hb, s); $log << [:draw, s['a0']]; raise 'Menfez BK\'nın dışında.' if s['a0'].to_f > 50; end
  def mst_shared_def_prompt(*_a); :not_shared; end
  def commit_with_dependencies(m); m.commit_operation; end
  def head_beam_formwork_area(_h); 10.0; end
  def head_beam_net_formwork_area(_h); raise 'yüz okunamadı' if $net_raise; 9.0; end
  def mst_hb_rebar_build!(*_a); end
end
A1.load(Host, bm, 'def mst_cv_specs(', 'def mst_cv_redraw!(', 'def mst_hb_culvert_groups(', 'def mst_cv_ui', 'def mst_cv_plan(', 'def mst_cv_bk_dims(',
        'def mst_v50_after_bk_change!(', 'def mst_v50_num(')
A1.load_opt(Host, bm, 'def mst_cv_specs_bad?(')
a2_const(Host, bm, 'MST_CV_FIELDS')
h = Host.new
mk_hb = lambda do |cj|
  b = Sketchup::Group.new(300, 'element_type' => 'head_beam', 'id' => 'BK-M', 'length_m' => 20.0, 'width_m' => 1.5, 'height_m' => 1.2, 'culverts_json' => cj)
  cv = Sketchup::Group.new(301, 'element_type' => 'bk_culvert'); b.entities = [cv]; [b, cv]
end
a1_reset!
b, cv = mk_hb.('[{"a0":1')   # bozuk kayit
h.mst_cv_redraw!(b)
t('K17 bozuk menfez kaydı: mevcut menfez silinmez, culvert_error yazılır', [cv.erased.nil?, b.a('culvert_error').to_s.include?('okunamadı')], [true, true])
a1_reset!
b, = mk_hb.('[{"a0":1')
$ib_queue = [['EKLE'], %w[0.5 1.0 0 1.5 0.4 0.6 10 C]]; $ui_answer = IDYES
$model.selection = [b]; h.mst_cv_ui; obs("menfez iletileri", $msgs)
t('K17 bozuk kayıtta EKLE: kayıt ezilmez, Türkçe ileti', [b.a('culverts_json'), $msgs.last.to_s.include?('okunamadı; mevcut kaydın üzerine yazılmadı')], ['[{"a0":1', true])
a1_reset!
bad = { 'a0' => 60, 'la' => 1, 'c0' => 0, 'lc' => 1.5, 'z0' => 0.4, 'h' => 0.6, 't_mm' => 10, 'axis' => 'C' }
b, = mk_hb.(JSON.generate([bad])); b.set_attribute(D, 'culvert_error', '1 menfez çizilemedi: Menfez BK\'nın dışında.')
$ib_queue = [['EKLE'], %w[0.5 1.0 0 1.5 0.4 0.6 10 C]]
$model.selection = [b]; h.mst_cv_ui; obs("menfez iletileri", $msgs)
t('K16 EKLE başka (geçersiz) menfez kaydının hatasını silmez', b.a('culvert_error').to_s.include?('çizilemedi'), true)
a1_reset!
b, = mk_hb.('[]'); $net_raise = true; b.set_attribute(D, 'formwork_net_area_m2', 7.0)
h.mst_v50_after_bk_change!(b)
t('K18 net kalıp yazım hatası yutulmaz: formwork_net_error (eski değer işaretli)', [b.a('formwork_net_area_m2'), b.a('formwork_net_error')], [7.0, 'yüz okunamadı'])
$net_raise = false; h.mst_v50_after_bk_change!(b)
t('K18 başarılı yenilemede bayrak silinir', [b.a('formwork_net_area_m2'), b.a('formwork_net_error')], [9.0, nil])

# ------------------------------------------------------------------ K29
CB = A1.load_opt(Host, main, 'def mst_cb_json(')
a1_reset!
if CB
  t('K29 bozuk callback JSON: nil + Türkçe ileti (sessiz istisna yok)', [h.mst_cb_json('{bozuk', 'Döşeme'), $msgs.last.to_s.start_with?('Döşeme: arayüzden gelen veri okunamadı')], [nil, true])
  t('K29 geçerli callback JSON', h.mst_cb_json('{"a":1}', 'X'), { 'a' => 1 })
end
cbs = %w[autoHeadBeam autoHeadBeamsBulk create_flat_precast create_channel_precast create_crane_precast create_deck_slab deck_preview deck_rebar_bim create_existing_deck_topping]
t('K29 (statik) 9 callback rescue\'suz JSON.parse kullanmıyor', cbs.count { |c| (main[/add_action_callback\('#{c}'\)[^\n]*/] || '').include?('JSON.parse') }, 0)
norm = main[/^  changes=changes\.map\{.*\}\.to_h$/]
obs('K29 N8 normalleştirme satırı var', !norm.nil?)
if norm
  changes = { 'drilling_length_m' => 5, 'plug_count_per_pile' => 2.0, 'pe_enabled' => '1', 'infill_concrete_class' => 'C35/45', 'infill_bottom_elevation_m' => -12 }
  changes = eval(norm.strip.sub('changes=', ''))
  t('K29 N8 toplu kazık: ölçü Float, adet Integer, durum / sınıf String', changes.values.map(&:class), [Float, Integer, String, String, Float])
else
  t('K29 N8 toplu kazık tip normalleştirmesi', false, true)
end
t('K29 (statik) aks adı HTML kaçışı ve </script> kaçışı', [main.include?("<span>\#{html_escape(payload['axis_name'])}</span>"), main.include?("const payload=\#{JSON.generate(payload).gsub('</','<\\/')}")], [true, true])
t('K29 </script> kaçışı çalışır', JSON.generate('axis_name' => 'A</script><b>').gsub('</', '<\/').include?('</script>'), false)

# ------------------------------------------------------------------ K45
line = main[/^  tb\.show.*$/].to_s.strip
obs('K45 araç çubuğu satırı', line)
TB_HIDDEN = 0 unless defined?(TB_HIDDEN)
class FTB; attr_reader :shown; def initialize(s); @s = s; end; def get_last_state; @s; end; def show; @shown = true; end; end
res = [0, 1, -1].map { |s| tb = FTB.new(s); eval(line); tb.shown ? 'göster' : 'gizli' }
t('K45 kapatılmış (TB_HIDDEN) araç çubuğu açılışta gösterilmez; görünür / hiç gösterilmemiş gösterilir', res, %w[gizli göster göster])

# ------------------------------------------------------------------ DXF birim
A1.load(Host, dxr, 'def mst_dxr_parse_l(', 'def mst_dxr_parse_cd(', 'def mst_dxr_scan(')
A1.load(Host, dxf, 'def mst_dxf_unit_name(')
DXU = A1.load_opt(Host, dxr, 'def mst_dxr_l_unit(') & A1.load_opt(Host, dxr, 'def mst_dxr_unitless_l?(')
a2_const(Host, dxf, 'MST_DXF_INSUNITS')
fl = [{ 't' => 'TEXT', 'text' => '1', 'x' => 0.0, 'y' => 0.0, 'h' => 2.5 }, { 't' => 'TEXT', 'text' => '10Ø16', 'x' => 5.0, 'y' => 0.0, 'h' => 2.5 },
      { 't' => 'TEXT', 'text' => 'L=250', 'x' => 20.0, 'y' => 0.0, 'h' => 2.5 }]
old_kg = Host.new.mst_dxr_scan(fl)['table'].sum { |r| r['kg'] }
obs('DXF "L=250" birimsiz, varsayılan (metre) — 10Ø16 kg', old_kg.round(1))
if DXU
  a1_reset!
  u5 = h.mst_dxr_l_unit({ 'insunits' => 5 }, fl)
  t('DXF $INSUNITS=5 (cm): birimsiz L cm okunur, varsayım metinde', u5, [0.01, 'cm ($INSUNITS 5)'])
  $ib_queue = [['cm']]
  u0 = h.mst_dxr_l_unit({ 'insunits' => 0 }, fl)
  t('DXF $INSUNITS=0: kullanıcıya sorulur (mm/cm/m)', u0, [0.01, 'cm (kullanıcı seçimi; $INSUNITS tanımsız)'])
  $ib_queue = [nil]
  t('DXF birim sorusu iptal: işlem yok (nil)', h.mst_dxr_l_unit({ 'insunits' => 0 }, fl), nil)
  t('DXF bütün L yazıları birimliyse soru yok', h.mst_dxr_l_unit({ 'insunits' => 0 }, [{ 't' => 'TEXT', 'text' => 'L=250 cm' }])[0], 1.0)
  new_kg = h.mst_dxr_scan(fl, 0.01)['table'].sum { |r| r['kg'] }
  t('DXF metraj: 10Ø16 L=250 (cm) → 10 × 2.50 m × 16²/162 = 39.5 kg (0.51.4: 3950.6 kg)', [new_kg.round(1), old_kg.round(1)], [39.5, 3950.6])
end
t('DXF "L = 2500 mm" mm okunur (0.51.4 düzenli ifade "m" ile eşleşiyordu)', h.mst_dxr_parse_l('L = 2500 mm'), 2.5)
t('DXF birimli L değişmez ("L=2.5 m", "L=250cm")', [h.mst_dxr_parse_l('L=2.5 m'), h.mst_dxr_parse_l('L=250cm')], [2.5, 2.5])
ui = b_slice(dra, 'def mst_dra_ui', "\nend\n")
t('DXF otomatik pafta: tolerans = 0.006 m / çizim birimi (cm → 0.6 = eski sabit), kurucuya iletilir',
  [ui.include?('ftol=0.006/u'), ui.include?('mst_dra_build(reg,"#{d[\'name\']} · #{File.basename(path,\'.*\')}",ftol,unote)'), (0.006 / 0.01).round(6), dra.include?(" ftol=0.6\n")], [true, true, 0.6, false])

# ------------------------------------------------------------------ A2 aktarimlari
pq = qs[/def pile_owned_concrete\(e\).*?\n   end/m].to_s
t('A2→B pile_owned_concrete: "iç beton YOK" çocuk kontrolünden önce', pq.index('infill_disabled').to_i < pq.index('physical_child_owner').to_i, true)
class Host
  def mst_pile_ids_for_beam(_b); []; end
  def mst_identity_id_key(_t); 'id'; end
  def bim_type_prefix(_t); 'D'; end
  def mst_next_unique_physical_id(_p, _u); 'D-YENİ'; end
  def mst_all_elements; []; end
  def model_audit; end
  def mst_world_box(e); e.box; end
  def collect_elements(ents, out); out.concat(ents.to_a); end
end
A1.load(Host, main, 'def ensure_uid(', 'def repair_bim_identity', 'def mst_world_box_center(')
A1.load_opt(Host, A1.src('dependency_rebuild.rb'), 'def mst_uid_owner(')
a1_reset!
orig = FakeEnt.new(100, 'element_type' => 'deck_slab', 'element_uid' => 'MST-100-1', 'uid_owner_pid' => 100, 'id' => 'D1')
copy = FakeEnt.new(200, 'element_type' => 'deck_slab', 'element_uid' => 'MST-100-1', 'uid_owner_pid' => 100, 'id' => 'D1')
$model.entities = [copy, orig]   # kopya toplama sirasinda once
Host.new.repair_bim_identity
t('A2→B repair_bim_identity: fiziksel ID asıl öğede kalır, kopya yeniden numaralanır', [orig.a('id'), copy.a('id')], ['D1', 'D-YENİ'])
a1_finish
