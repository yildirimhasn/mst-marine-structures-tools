# ADR-0515-I (isimlendirme) — yapı / aks görünen adı ve C seçeneği (kullanılmayan yapı kodu değişikliği), Ruby tarafı.
# Yardımcılar (anahtar, doğrulama, sonraki kod, etiket), okuma (eski / bozuk kayıt, yazım yok), Aks Yöneticisi kayıt
# geri çağrısı uçtan uca (gerçek project_ano_axis_manager + sahte diyalog): tek normal işlem, doğrulama işlem açılmadan,
# değişikliksiz kayıtta ad anahtarı yazılmaz, eleman öznitelikleri değişmez, kaydet-yeniden aç.
# Gömülü JS senaryoları: n_isim_js.js (bu test gerçek HTML'i üretip node ile çalıştırır).
# Kullanim: ruby tools/test/n_isim_ruby.rb <src/marine_structures_tools>
require_relative 'b_helper'
require 'tmpdir'
require 'open3'
main = A1.src('main.rb')
D = A1::DICT

class FakeModel
  def active_view; o = Object.new; def o.invalidate; end; o; end
end
class FakeDlg
  attr_reader :cb, :html, :scripts
  def initialize; @cb = {}; @scripts = []; end
  def set_html(h); @html = h; end
  def add_action_callback(n, &b); @cb[n] = b; end
  def show; end
  def execute_script(s); @scripts << s; end
end
class Host
  VERSION = 't'.freeze
  def mst_html_dialog(*_a, **_k); $dlg = FakeDlg.new; end
  def mst_find_pile_layouts(_e, out = []); out; end
  def mst_axis_move_plan_for_payload(_x, _m); []; end
  def mst_structure_move_plans(_x, _m); []; end
  def mst_axis_move_confirm(_p, _s); :axes_only; end
  def mst_grid_visual_snapshot(_x, _m); {}; end
  def mst_refresh_changed_grid_visuals(_b, _m); []; end
  def mst_placement_key(system, name); "#{system.to_s.upcase}::#{name}"; end
end
NEW = A1.load_opt(Host, main, 'def mst_name_key(')
t('ADR-0515-I yardımcıları tanımlı (mst_name_key)', NEW, true)
unless NEW
  a1_finish
end
consts = main[/^MST_NAME_MAX_STRUCTURE=.*?\n(?=\n)/m] or abort('sabitler yok')
Host.class_eval(consts)
A1.load(Host, main, 'def html_escape(', 'def mst_json_attr_bad?(', 'def mst_json_attr_guard!(', 'def mst_default_structure_name(',
        'def mst_name_clean(', 'def mst_name_validate(', 'def mst_structure_display_names(', 'def mst_axis_display_names(',
        'def mst_structure_display(', 'def mst_structure_label(', 'def mst_axis_display(', 'def mst_next_structure_code(',
        'def mst_code_allowed_in_system?(', 'def mst_placement_links(', 'def mst_code_usage(', 'def mst_structure_code_lock(',
        'def mst_axis_code_locks(', 'def mst_structure_label_maps(', 'def mst_display_names_forget!(',
        'def mst_axis_manager_names_plan(', 'def mst_axis_manager_apply_names!(', 'def mst_axis_grid_key(',
        'def mst_structure_zones(', 'def mst_structure_zones_for(', 'def mst_active_structure_zone(', 'def mst_axis_grids(',
        'def mst_default_axis_grid', 'def mst_normalize_axis_rows(', 'def mst_axis_grid_for(', 'def mst_save_axis_grid(',
        'def mst_ano_layouts(', 'def mst_system_structures(', 'def mst_structures_for_system(', 'def mst_structure_placements(',
        'def mst_axis_manager_save_payload(')
# Aks Yöneticisi: dosyada iki tanım var; yüklemede sonuncusu geçerli
a = main.rindex("\ndef project_ano_axis_manager\n") + 1
e = main.index("\nend\n", a)
Host.class_eval(main[a..e + 4])
h = Host.new

# --- 1) Anahtar / doğrulama / sonraki kod / etiket ---
k = ->(s) { h.mst_name_key(s) }
t('Anahtar: Türkçe büyük / küçük harf (yanaşma dolfeni = YANAŞMA DOLFENİ)', k.('yanaşma dolfeni'), k.('YANAŞMA DOLFENİ'))
t('Anahtar: I / İ / ı / i aynı', %w[KIYI kıyı Kiyi KİYİ kiyi].map { |s| k.(s) }.uniq.size, 1)
t('Anahtar: NFC (ş ayrışık = ş birleşik)', k.("şehir"), k.("şehir"))
t('Anahtar: kırpma + çoklu boşluk', k.("  BD   01 "), k.('bd 01'))
err = ->(&b) { begin; b.call; nil; rescue => x; x.message; end }
t('Doğrulama: yasak karakter (/) reddedilir', err.() { h.mst_name_validate('A/B', 40, 'Ad') }.to_s.include?('izin verilmeyen'), true)
t('Doğrulama: iki nokta (:) reddedilir', err.() { h.mst_name_validate('A:B', 40, 'Ad') }.to_s.include?("':'"), true)
t('Doğrulama: denetim karakteri reddedilir', err.() { h.mst_name_validate("A\u0007B", 40, 'Ad') }.to_s.include?('denetim karakteri'), true)
t('Doğrulama: izinli karakterler (harf, rakam, boşluk, - _ . ( ) # + &)', h.mst_name_validate(' İskele  Kolu-1_(A).#2+&B ', 40, 'Ad'), 'İskele Kolu-1_(A).#2+&B')
t('Doğrulama: yapı 40 karakter kabul, 41 red', [h.mst_name_validate('A' * 40, 40, 'Ad').size, err.() { h.mst_name_validate('A' * 41, 40, 'Ad') }.to_s.include?('en fazla 40')], [40, true])
t('Doğrulama: aks 20 karakter kabul, 21 red', [h.mst_name_validate('A' * 20, 20, 'Ad').size, err.() { h.mst_name_validate('A' * 21, 20, 'Ad') }.to_s.include?('en fazla 20')], [20, true])
t('Doğrulama: boş → "" (ad temizlenir)', h.mst_name_validate('   ', 40, 'Ad'), '')
t('Sonraki kod: ANO-01, ANO-03 → ANO-04', h.mst_next_structure_code('ISKELE', %w[ANO-01 ANO-03]), 'ANO-04')
t('Sonraki kod: DOLFEN boş → BD-01; BD-02, bd-05 → BD-06', [h.mst_next_structure_code('DOLFEN', []), h.mst_next_structure_code('DOLFEN', %w[BD-02 bd-05 YD-09])], %w[BD-01 BD-06])
t('Sonraki kod: RIHTIM-01 → RIHTIM-02 (görünen ad okunmaz)', h.mst_next_structure_code('RIHTIM', %w[RIHTIM-01]), 'RIHTIM-02')
t('Varsayılan ad tutarlı (mst_default_structure_name)', %w[DOLFEN ISKELE RIHTIM].map { |s| h.mst_default_structure_name(s, 1) }, %w[BD-01 ANO-01 RIHTIM-01])
nm = { 'BD-01' => 'YANAŞMA DOLFENİ-01' }
t('"(kod)" eki: "YANAŞMA DOLFENİ-01 (BD-01)"; adsız yapı yalnız kod', [h.mst_structure_label('BD-01', nm), h.mst_structure_label('BD-02', nm)], ['YANAŞMA DOLFENİ-01 (BD-01)', 'BD-02'])
t('Görünen ad koda eşitse yalnız kod', h.mst_structure_label('BD-03', { 'BD-03' => 'BD-03' }), 'BD-03')

# --- 2) Okuma: eski model / bozuk kayıt, yazım yok ---
a1_reset!
t('Eski model (anahtar yok): boş harita, yazım 0', [h.mst_structure_display_names($model), h.mst_axis_display_names($model), sets.size], [{}, {}, 0])
$model.set_attribute(D, 'structure_display_names_json', '{bozuk'); $model.set_attribute(D, 'axis_display_names_json', '[1,2]'); $log = []
t('Bozuk kayıt: boş harita, yazım 0', [h.mst_structure_display_names($model), h.mst_axis_display_names($model), h.mst_structure_display('BD-01', nil, $model), sets.size], [{}, {}, 'BD-01', 0])

# --- 3) Uçtan uca: Aks Yöneticisi aç / kaydet ---
def grid_rows(*n); n.map { |x| { 'name' => x, 'gap_m' => 5.0 } }; end
$pile = nil
fresh = lambda do
  a1_reset!
  $model.set_attribute(D, 'project_name', 'P'); $model.set_attribute(D, 'project_system_type', 'DOLFEN')
  $model.set_attribute(D, 'system_structures_json', JSON.generate('DOLFEN' => %w[BD-01 BD-02], 'ISKELE' => %w[ANO-01 ANO-03], 'RIHTIM' => %w[RIHTIM-01]))
  $model.set_attribute(D, 'active_structure__DOLFEN', 'BD-01')
  $model.set_attribute(D, 'axis_grids_json', JSON.generate('BD-01::BD-01' => { 'x' => grid_rows('X-01', 'X-02'), 'y' => grid_rows('A', 'B') },
                                                          'BD-02::BD-02' => { 'x' => grid_rows('X-01'), 'y' => grid_rows('A') }))
  $model.set_attribute(D, 'structure_zones_json', JSON.generate('BD-02' => ['ANA YAPI', 'BD-02']))
  $model.set_attribute(D, 'active_structure_zone__BD-02', 'BD-02')
  $model.set_attribute(D, 'structure_display_names_json', JSON.generate('ANO-03' => 'ANO-02'))
  $model.set_attribute(D, 'axis_display_names_json', JSON.generate('BD-01::BD-01' => { 'x' => { 'X-02' => 'AKS İKİ' }, 'y' => {} }))
  $pile = Sketchup::Group.new(11, 'element_type' => 'steel_pipe_pile', 'ano' => 'BD-01', 'zone' => 'BD-01', 'structure' => 'BD-01', 'system' => 'DOLFEN',
                              'grid_x_axis' => 'X-01', 'grid_y_axis' => 'A', 'axis' => 'X-01', 'element_uid' => 'U-11', 'pile_id' => 'P-01')
  $model.entities = [$pile]
  $log = []
end
open_dlg = lambda do
  h.project_ano_axis_manager
  $log = []
  $dlg
end
save = lambda do |payload|
  $log = []; $msgs = []
  $dlg.cb['axis_manager_v2_save'].call(nil, JSON.generate(payload))
end
fresh.()
before_pile = $pile.raw_attrs
dlg = open_dlg.()
html = dlg.html
t('Açılış: görünen adlar ve kilitler sayfaya gider', [html.include?('var names={"ANO-03":"ANO-02"}'), html.include?('"DOLFEN::BD-01":"Kod değiştirilemez: 1 eleman bu koda bağlı."')], [true, true])
t('Açılış: kullanılan aks kilidi (BD-01 / X-01), kullanılmayan X-02 kilitsiz', [html.include?('"X-01":"Aks kodu değiştirilemez: 1 eleman bu aksa bağlı."'), html.include?('"X-02":"Aks kodu')], [true, false])
t('Açılış: aks satırı display alanı (AKS İKİ)', html.include?('"name":"X-02","gap_m":5.0,"coord_m":5.0') && html.include?('"display":"AKS İKİ"'), true)

# Gömülü JS: gerçek HTML ile node senaryoları (n_isim_js.js)
js_out = ''
js_ok = false
Dir.mktmpdir do |dir|
  f = File.join(dir, 'ax.js')
  File.binwrite(f, html[/<script>(.*)<\/script>/m, 1])
  out, st = Open3.capture2e('node', File.join(__dir__, 'n_isim_js.js'), f)
  js_out = out; js_ok = st.success?
end
puts js_out.lines.map { |l| "  js| #{l}" }.join
t('Gömülü JS senaryoları (node): 0 kaldı', js_ok && js_out.include?(' 0 kaldı'), true)
payload = (JSON.parse(js_out[/^PAYLOAD (.*)$/, 1]) rescue nil)
keys = (JSON.parse(js_out[/^NKEYS (.*)$/, 1]) rescue {})
t('JS nkey = Ruby mst_name_key (örnek dizgiler)', keys.map { |s, v| [s, v == h.mst_name_key(s)] }.reject { |_, ok| ok }, [])
t('JS nextCode = Ruby mst_next_structure_code', (js_out[/^NEXTCODE (.*)$/, 1] || '').split(','), [h.mst_next_structure_code('DOLFEN', %w[BD-01 BD-02 ANO-01 ANO-03 RIHTIM-01]), h.mst_next_structure_code('ISKELE', %w[BD-01 BD-02 ANO-01 ANO-03 RIHTIM-01])])

if payload
  # JS yükü: BD-01 görünen adı, BD-02 → BD-07 (boş yapı), X-02 görünen adı korunur
  save.(payload)
  t('Kayıt: tek normal işlem "MST Aks Kaydı" (tek Geri Al)', [ops, $log.select { |x| x[0] == :start }.map { |x| x[1] }, $model.open_ops], [[:start, :commit], ['MST Aks Kaydı'], 0])
  t('Kayıt: hata iletisi yok', $msgs, [])
  t('Kayıt: yapı görünen adları', JSON.parse($model.a('structure_display_names_json')), { 'BD-01' => 'yanaşma dolfeni-01', 'ANO-03' => 'ANO-02' })
  t('C: liste BD-02 → BD-07', JSON.parse($model.a('system_structures_json'))['DOLFEN'], %w[BD-01 BD-07])
  g = JSON.parse($model.a('axis_grids_json'))
  t('C: aks ağı anahtarı BD-07::BD-07 yazıldı, BD-02::BD-02 silindi', [g.key?('BD-07::BD-07'), g.key?('BD-02::BD-02')], [true, false])
  t('C: bölge listesi ve etkin bölge yeni koda taşındı', [JSON.parse($model.a('structure_zones_json')), $model.a('active_structure_zone__BD-07')], [{ 'BD-07' => ['ANA YAPI', 'BD-07'] }, 'BD-07'])
  t('Aks görünen adı korundu (BD-01 / X-02)', JSON.parse($model.a('axis_display_names_json')), { 'BD-01::BD-01' => { 'x' => { 'X-02' => 'AKS İKİ' }, 'y' => {} } })
  t('Eleman öznitelikleri değişmedi (ano / structure / axis / UID)', $pile.raw_attrs, before_pile)
  t('Elemana yazım yok (yalnız model)', sets.reject { |s| s[1] == $model }.size, 0)
  t('Durum iletisi "(kod)" ekli ve mstNamesSaved çağrısı', dlg.scripts.last.to_s.include?('yanaşma dolfeni-01 (BD-01)') && dlg.scripts.last.to_s.include?('mstNamesSaved'), true)
  # Kaydet - yeniden aç
  dlg2 = open_dlg.()
  t('Yeniden aç: ad ve yeni kod sayfada', [dlg2.html.include?('"BD-01":"yanaşma dolfeni-01"'), dlg2.html.include?('"DOLFEN":["BD-01","BD-07"]')], [true, true])
  # Değişikliksiz kayıt: ad anahtarlarına yazım yok
  pl2 = JSON.parse(JSON.generate(payload)); pl2['code_changes'] = []
  pl2['systems']['DOLFEN'] = %w[BD-01 BD-07]
  save.(pl2)
  t('Değişikliksiz kayıt: görünen ad anahtarlarına yazım 0', sets.count { |s| %w[structure_display_names_json axis_display_names_json].include?(s[3]) }, 0)
  t('Değişikliksiz kayıt: hata yok, tek işlem', [$msgs, ops], [[], [:start, :commit]])
end

# --- 4) Red durumları: işlem açılmaz, yazım yok ---
base = lambda do
  { 'project' => 'P', 'system' => 'DOLFEN', 'systems' => { 'DOLFEN' => %w[BD-01 BD-02], 'ISKELE' => %w[ANO-01 ANO-03], 'RIHTIM' => %w[RIHTIM-01] },
    'active' => { 'DOLFEN' => 'BD-01', 'ISKELE' => 'ANO-01', 'RIHTIM' => 'RIHTIM-01' },
    'grids' => { 'DOLFEN::BD-01' => { 'x' => [{ 'name' => 'X-01', 'display' => '' }, { 'name' => 'X-02', 'display' => 'AKS İKİ', 'gap_m' => 5 }], 'y' => [{ 'name' => 'A' }, { 'name' => 'B', 'gap_m' => 5 }] } },
    'placements' => {}, 'structure_names' => { 'ANO-03' => 'ANO-02' }, 'code_changes' => [] }
end
reject = lambda do |label, pl, frag|
  fresh.(); open_dlg.(); before = $pile.raw_attrs
  save.(pl)
  t("Red: #{label} (işlem açılmaz, yazım 0)", [$msgs.last.to_s.include?(frag), ops, sets.size, $pile.raw_attrs == before], [true, [], 0, true])
  obs("ileti #{label}", $msgs.last)
end
pl = base.(); pl['structure_names']['BD-02'] = 'bd-01'
reject.('ad başka yapının koduyla çakışıyor (küçük harf)', pl, 'yapısının koduyla çakışıyor')
pl = base.(); pl['structure_names']['BD-02'] = 'ano-0İ'.sub('İ', '1')
reject.('ad başka sistemin koduyla çakışıyor', pl, 'ANO-01 yapısının koduyla')
pl = base.(); pl['structure_names']['BD-02'] = 'Kıyı'; pl['structure_names']['BD-01'] = 'KIYI'
reject.('iki yapıda aynı ad (I / ı)', pl, 'birden fazla yapıda')
pl = base.(); pl['structure_names']['BD-01'] = 'ano-02'
reject.('başka sistemdeki görünen adla çakışma', pl, 'birden fazla yapıda')
pl = base.(); pl['structure_names']['BD-01'] = 'A/B'
reject.('yasak karakter', pl, 'izin verilmeyen')
pl = base.(); pl['structure_names']['BD-01'] = 'Ç' * 41
reject.('uzunluk 41', pl, 'en fazla 40')
pl = base.(); pl['grids']['DOLFEN::BD-01']['x'][0]['display'] = 'x-02'
reject.('aks görünen adı aynı yöndeki kodla çakışıyor', pl, 'aynı yöndeki X-02')
pl = base.(); pl['grids']['DOLFEN::BD-01']['x'][0]['display'] = 'A' * 21
reject.('aks görünen adı 21 karakter', pl, 'en fazla 20')
pl = base.(); pl['systems']['DOLFEN'] = %w[BD-01 BD-09]; pl['code_changes'] = [{ 'system' => 'DOLFEN', 'from' => 'BD-01', 'to' => 'BD-09' }]
pl['systems']['DOLFEN'] = %w[BD-09 BD-02]; pl['grids'] = { 'DOLFEN::BD-09' => pl['grids']['DOLFEN::BD-01'] }
reject.('C: kullanılan yapının kodu (1 eleman)', pl, 'Kod değiştirilemez: 1 eleman')
pl = base.(); pl['systems']['DOLFEN'] = %w[BD-01 ANO-01]
reject.('yeni kod başka sistemin biçiminde (DOLFEN içinde ANO-01)', pl, 'ANO-01 DOLFEN sisteminde kullanılamaz')
pl = base.(); pl['systems']['DOLFEN'] = %w[BD-01 BD-02 ortak]; pl['systems']['ISKELE'] = %w[ANO-01 ANO-03 ORTAK]
reject.('yeni kod başka sistemdeki kodla aynı (ortak / ORTAK)', pl, 'koduyla çakışıyor')
pl = base.(); pl['systems']['ISKELE'] = %w[ANO-01 ANO-03 BD-05]
reject.('yeni kod sistem biçimine uymuyor (İSKELE içinde BD-05)', pl, 'İSKELE sisteminde kullanılamaz')
pl = base.(); pl['systems']['ISKELE'] = %w[ANO-01 ANO-03 ANO-02]
reject.('yeni kod başka yapının görünen adıyla çakışıyor (ANO-03 = "ANO-02")', pl, 'ANO-02 yapısının koduyla')
# C: yerleşim bağlantısı olan boş yapı
fresh.(); $model.set_attribute(D, 'structure_placements_json', JSON.generate('DOLFEN::BD-01' => { 'x_link' => { 'mode' => 'SAME_SYSTEM', 'ref_structure' => 'BD-02', 'ref_axis' => 'X-01', 'target_axis' => 'X-01' }, 'y_link' => nil }))
open_dlg.(); bf = $pile.raw_attrs
pl = base.(); pl['systems']['DOLFEN'] = %w[BD-01 BD-08]; pl['code_changes'] = [{ 'system' => 'DOLFEN', 'from' => 'BD-02', 'to' => 'BD-08' }]
pl['placements'] = JSON.parse($model.a('structure_placements_json'))
save.(pl)
t('Red: C — yerleşim bağlantısı olan yapının kodu (işlem açılmaz)', [$msgs.last.to_s.include?('yerleşim bağlantısı (BD-01)'), ops, sets.size, $pile.raw_attrs == bf], [true, [], 0, true])
t('Açılış kilidi: bağlantılı aks (BD-01 / X-01 hedef, BD-02 / X-01 referans)', [$dlg.html.include?('"DOLFEN::BD-02":"Kod değiştirilemez: yerleşim bağlantısı (BD-01) bu koda bağlı."'), $dlg.html.scan('yerleşim bağlantısı (BD-01) bu aksa bağlı.').size], [true, 2])

# --- 5) Bozuk kayıt: değişiklik varsa işlem açılmadan red, yoksa yazım yok ---
fresh.(); $model.set_attribute(D, 'structure_display_names_json', '{bozuk'); open_dlg.()
pl = base.(); pl['structure_names'] = {}
save.(pl)
t('Bozuk ad kaydı + değişiklik yok: hata yok, ad anahtarına yazım 0', [$msgs, sets.count { |s| s[3] == 'structure_display_names_json' }], [[], 0])
pl = base.(); pl['structure_names'] = { 'BD-01' => 'YENİ' }
save.(pl)
t('Bozuk ad kaydı + yeni ad: işlem açılmadan red, kayıt ezilmez', [$msgs.last.to_s.include?('okunamadı'), ops, $model.a('structure_display_names_json')], [true, [], '{bozuk'])

# --- 6) Silinen yapının ad kaydı aynı işlemde silinir; ad temizleme ---
fresh.(); $model.set_attribute(D, 'structure_display_names_json', JSON.generate('ANO-03' => 'ANO-02', 'BD-02' => 'BOŞ')); open_dlg.()
pl = base.(); pl['systems']['DOLFEN'] = %w[BD-01]; pl['structure_names'] = { 'ANO-03' => '', 'BD-02' => 'BOŞ' }
save.(pl)
t('Silinen yapı (BD-02) ve temizlenen ad (ANO-03): harita boşaldı, tek işlem', [JSON.parse($model.a('structure_display_names_json')), ops], [{}, [:start, :commit]])
fresh.(); $model.set_attribute(D, 'structure_display_names_json', JSON.generate('BD-02' => 'BOŞ'))
h.mst_display_names_forget!($model, 'BD-02')
t('mst_display_names_forget!: ad ve aks kaydı silinir', JSON.parse($model.a('structure_display_names_json')), {})
fresh.(); $model.set_attribute(D, 'structure_display_names_json', '{bozuk'); $log = []
h.mst_display_names_forget!($model, 'BD-02')
t('mst_display_names_forget!: bozuk kayıt ezilmez', [sets.size, $model.a('structure_display_names_json')], [0, '{bozuk'])

# --- 7) Global üst bar ek alanları ---
fresh.()
mp = h.mst_structure_label_maps({ 'DOLFEN' => %w[BD-01], 'ISKELE' => %w[ANO-03] }, $model)
t('Üst bar: structure_labels / structure_names', mp, { 'structure_labels' => { 'BD-01' => 'BD-01', 'ANO-03' => 'ANO-02 (ANO-03)' }, 'structure_names' => { 'BD-01' => 'BD-01', 'ANO-03' => 'ANO-02' } })
t('Üst bar: 4 yükte (Loaded + 3 Saved) ek alanlar', main.scan('.merge(mst_structure_label_maps(systems,model))').size, 4)

# --- 8) Dokunulmazlar (statik) ---
rs = A1.src('revision_signatures.rb')
t('REVISION_PARAMETER_KEYS görünen ad anahtarlarını içermez', rs.include?('display_names'), false)
t('dependency_rebuild.rb görünen ad okumaz', A1.src('dependency_rebuild.rb').include?('display_name'), false)
t('Süzgeç ve üyelik işlevleri görünen ad okumaz', %w[def\ mst_structures_for_system( def\ mst_pile_in_structure?( def\ mst_element_in_structure?(].map { |s| A1.grab(main, s).include?('display') }, [false, false, false])
a1_finish
