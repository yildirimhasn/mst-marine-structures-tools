# U2 (03.11.2026, entegre sürüm regresyonu; senaryo 6–7) — kaydet / yeniden aç ve eski kayıtlar (sahte nesne, ayrı süreçler).
#  6  Yeni kodla gerçek Aks Yöneticisi kaydı (yapı + aks görünen adı) ve Anlık Kayıt (revizyon) → bütün öznitelikler dosyaya (Marshal) →
#     YENİ süreçte aynı geometrili fikstüre geri yüklenir → görünen adlar, üst bar, kazık etiketi / ızgara, metraj hiyerarşisi, Çalışma Alanı,
#     kazık raporu, Excel Keşif / Hakediş "Yapı"+"Yapı Kodu", bağımlılık ağı, revizyon imzaları, BOQ özeti, metraj ve revizyon karşılaştırması
#     kayıttan önceki süreçle birebir aynı; okuma yolunda yazım yok; görünen ad anahtarları yalnız modelde.
#  7a Eski model (yeni anahtarlar yok) yeni kodla: gösterim = kod, okumada yazım 0, metraj / bağlantılar adlı modelle aynı.
#  7b 0.51.4 (872d3a3) kaynağıyla oluşturulmuş öznitelik dökümü (eski kodun Aks Yöneticisi kaydı + Anlık Kayıt + Keşif yenilemesi) yeni kodla
#     açılır: okumada yazım 0, gösterim = kod, metraj / bağlantılar / revizyon imzaları 7a ile aynı, eski revizyon arşivi okunur.
# Kanıt düzeyi: sahte nesne. Gerçek .skp kaydetme / açma ve SketchUp'ın öznitelik serileştirmesi KANITLANMAZ.
# Kullanim: ruby tools/test/u2_persist_legacy.rb <src/marine_structures_tools> [0.51.4 kaynak klasörü | commit=872d3a3]
#   (iç kullanım: --dump <dosya> named|plain|legacy  /  --reopen <dosya>)
require 'stringio'
require 'tmpdir'
require 'open3'
require 'json'
SELF = File.expand_path(__FILE__)
dir = ARGV[0] or abort 'kullanim: ruby tools/test/u2_persist_legacy.rb <marine_structures_tools klasoru> [taban]'
mode = ARGV[1]

if mode == '--dump' || mode == '--reopen'
  require_relative '../golden/sketchup_stub'
  $model = Sketchup::Model.new
  $stderr_keep = $stderr; $stderr = StringIO.new
  require File.join(File.expand_path(dir), 'main.rb')
  $stderr = $stderr_keep
  require_relative '../golden/fixture'
  require_relative 'r_helper'
  require_relative 'u_views'
  M = MAG::MarineStructuresTools
  file = ARGV[2]
  r_setup(names: false)
  d = (uv_main_dialog rescue $!)
  out = { 'dialog' => d.is_a?(Exception) ? "HATA: #{d.class}: #{d.message[0, 120]}" : 'tamam', 'ops' => [] }
  if mode == '--dump'
    kind = ARGV[3]
    if kind == 'named' || kind == 'legacy'
      ax = r_axis_open
      pl = if M.respond_to?(:mst_structure_display_names)
             r_axis_payload
           else
             # 0.51.4: görünen ad alanları yok; aynı biçimde değişikliksiz yük
             systems = {}; grids = {}; active = {}
             %w[DOLFEN ISKELE RIHTIM].each do |s|
               systems[s] = M.mst_structures_for_system(s, $model)
               systems[s].each { |n| g = M.mst_axis_grid_for(n, $model, n); grids["#{s}::#{n}"] = { 'x' => g['x'], 'y' => g['y'], 'system_axis_x' => '', 'system_axis_y' => '', 'x_dir' => g['x_dir'], 'y_dir' => g['y_dir'] } }
               active[s] = $model.get_attribute(D, "active_structure__#{s}", '').to_s
             end
             { 'project' => 'GOLDEN-0514', 'system' => 'ISKELE', 'systems' => systems, 'active' => active, 'grids' => grids, 'placements' => M.mst_structure_placements($model) }
           end
      if kind == 'named'
        pl['structure_names'] = { 'ANO-01' => 'Ana İskele' }
        pl['grids']['ISKELE::ANO-01']['x'][0]['display'] = 'Kıyı Aksı'
        pl['grids']['ISKELE::ANO-01']['y'][0]['display'] = 'Ön Sıra'
      end
      $msgs = []; $model.ops.clear
      ax.cb['axis_manager_v2_save'].call(nil, JSON.generate(pl))
      out['ops'] << ['Aks Yöneticisi kaydı', $model.ops.map(&:first), $msgs.dup]
    end
    if kind == 'named' || kind == 'legacy'
      $model.ops.clear; $msgs = []
      begin
        if d.respond_to?(:cb) && d.cb['boq_refresh'] then d.cb['boq_refresh'].call(nil) end
        if d.respond_to?(:cb) && d.cb['revision_snapshot'] then d.cb['revision_snapshot'].call(nil) else M.revision_create_snapshot end
        out['ops'] << ['Keşif yenile + Anlık Kayıt', $model.ops.map(&:first), $msgs.dup, d.out.last.to_s[0, 80]]
      rescue StandardError => e
        out['ops'] << ['Anlık Kayıt', "HATA: #{e.class}: #{e.message[0, 120]}"]
      end
    end
    dump = uv_dump
    File.binwrite(file, Marshal.dump(dump))
    out['views'] = uv_views(d) if M.respond_to?(:mst_structure_display_names)
    out['old_boq_rows'] = (M.boq_rows(true).map { |r| [r[:code], r[:source], r[:unit], format('%.9f', r[:quantity].to_f)] } rescue "HATA: #{$!.message}")
    out['model_keys'] = dump['model'].keys.map { |dd, k| "#{dd}/#{k}" }.sort
    out['elem_keys_with_names'] = dump['ents'].flat_map { |pid, _c, a| a.keys.select { |_dd, k| k.to_s.include?('display_name') }.map { |dd, k| "#{pid}:#{dd}/#{k}" } }
  else
    dump = Marshal.load(File.binread(file))
    out['unmatched'] = uv_restore(dump)
    out['views'] = uv_views(d)
  end
  puts 'U2JSON ' + JSON.generate(out)
  exit 0
end

# ---------------- düzenleyici ----------------
$ok = 0; $bad = 0
def t(label, got, exp)
  g = got == exp
  g ? $ok += 1 : $bad += 1
  puts "#{g ? 'GEÇTİ' : 'KALDI'}  #{label}: #{got.inspect[0, 240]} (beklenen #{exp.inspect[0, 240]})"
end
def obs(label, v); puts "GÖZLEM #{label}: #{v.inspect[0, 400]}"; end
root = File.expand_path('../..', __dir__)
newdir = File.expand_path(dir)
ref = ARGV[1] || '872d3a3'
VIEW_KEYS = %w[names systems label_maps axis_display pile_labels qto_hierarchy workspace topbar pile_grid takeoff_html takeoff_pile_html relationship_audit excel_kesif excel_hakedis
               dependency_graph revision_signatures boq_digest boq_rows qto3_totals revision_payload].freeze
Dir.mktmpdir('mst_u2') do |tmp|
  olddir = if File.directory?(ref.to_s)
             File.expand_path(ref)
           else
             tar = File.join(tmp, 'ref.tar')
             ok = system('git', '-C', root, 'archive', '-o', tar, ref, 'src', out: File::NULL, err: File::NULL) && Dir.chdir(tmp) { system('tar', '-xf', 'ref.tar') }
             ok ? File.join(tmp, 'src', 'marine_structures_tools') : nil
           end
  run = lambda do |src, *args|
    o, st = Open3.capture2e('ruby', SELF, src, *args)
    line = o.lines.grep(/\AU2JSON /).last
    line ? JSON.parse(line.sub('U2JSON ', '')) : { 'hata' => "çıkış #{st.exitstatus}: #{o.lines.last(4).join}" }
  end
  fa = File.join(tmp, 'named.bin'); fe = File.join(tmp, 'plain.bin'); fc = File.join(tmp, 'legacy.bin')
  a = run.(newdir, '--dump', fa, 'named')
  b = run.(newdir, '--reopen', fa)
  e = run.(newdir, '--dump', fe, 'plain')
  c = olddir ? run.(olddir, '--dump', fc, 'legacy') : { 'hata' => "taban #{ref} açılamadı" }
  dd = File.exist?(fc) ? run.(newdir, '--reopen', fc) : { 'hata' => 'eski döküm yok' }
  [['A adlı (yeni kod)', a], ['B yeniden açılış', b], ['E eski biçim (yeni kod)', e], ['C 0.51.4 dökümü', c], ['D 0.51.4 → yeni kod', dd]].each do |n, x|
    t("Süreç #{n} tamamlandı", x['hata'], nil)
  end
  av = a['views'] || {}; bv = b['views'] || {}; ev = e['views'] || {}; dv = dd['views'] || {}

  # --- 6: kaydet / yeniden aç ---
  obs('A işlemleri', a['ops'])
  t('6 A: Aks Yöneticisi kaydı tek işlem, ileti yok', (a['ops'] || [])[0].to_a[1..2], [%w[start commit], []])
  t('6 A: Anlık Kayıt hatasız', (a['ops'] || [])[1].to_a[1].to_s.start_with?('HATA'), false)
  t('6 A: görünen adlar yazıldı', av['names'], [{ 'ANO-01' => 'Ana İskele' }, { 'ANO-01::ANO-01' => { 'x' => { 'X-01' => 'Kıyı Aksı' }, 'y' => { 'A' => 'Ön Sıra' } } }])
  t('6 A: görünen ad anahtarları yalnız modelde (elemanlarda yok)', [a['model_keys'].to_a.include?('MAG_MarineStructures/structure_display_names_json'), a['model_keys'].to_a.include?('MAG_MarineStructures/axis_display_names_json'), a['elem_keys_with_names']], [true, true, []])
  t('6 B: döküm fikstüre tam eşleşti', b['unmatched'], 0)
  VIEW_KEYS.each do |k|
    t("6 yeniden açılış: #{k} = kayıt öncesi", bv[k], av[k])
  end
  t('6 B: hiçbir görünüm HATA vermedi', bv.select { |_, x| x.to_s.start_with?('HATA') }.keys, [])
  t('6 B: yeniden açılışta okuma yolunda yazım yok', bv['__writes'], [])
  t('6 B: eleman öznitelikleri = kayıt öncesi', bv['__elem_sig'], av['__elem_sig'])
  lm = (bv['label_maps'] || {})['structure_labels'] || {}
  t('6 B: üst bar "Ana İskele (ANO-01)"', [lm['ANO-01'], bv['topbar'].to_s.include?('"ANO-01":"Ana İskele (ANO-01)"')], ['Ana İskele (ANO-01)', true])
  t('6 B: kazık ızgarası görünen aks / nokta adı', [bv['pile_grid'].to_s.include?('"display_label":"Kıyı Aksı"'), bv['pile_grid'].to_s.include?('"display_label":"Ön Sıra"')], [true, true])
  t('6 B: Çalışma Alanı / Excel / kazık raporu görünen adı içerir (kazık etiketi yalnız yinelenen numarada; U3)',
    [bv['workspace'].to_s.include?('Ana İskele (ANO-01)'), (bv['excel_kesif'] || {})['pairs'].to_a.include?(['Ana İskele', 'ANO-01']), bv['takeoff_html'].to_s.include?('Ana İskele')],
    [true, true, true])

  # --- isim metrajı ve bağlantıları değiştirmez (A adlı ↔ E adsız) ---
  %w[boq_rows qto3_totals boq_digest dependency_graph revision_signatures].each do |k|
    t("6/7 #{k}: adlı model = adsız model (isim metrajı / bağlantıyı değiştirmez)", av[k], ev[k])
  end

  # --- 7a: eski biçim (yeni anahtar yok), yeni kod ---
  t('7a E: görünen ad kaydı yok → boş harita', ev['names'], [{}, {}])
  t('7a E: üst bar etiketleri = kod', ((ev['label_maps'] || {})['structure_labels'] || {}).select { |k, x| k != x }, {})
  t('7a E: kazık etiketi / Çalışma Alanı / Excel adları = kod', [ev['pile_labels'].to_s.include?('Ana İskele'), ev['workspace'].to_s.include?('Ana İskele'), (ev['excel_kesif'] || {})['pairs'].to_a.select { |n, k| n != k }],
    [false, false, []])
  t('7a E: okuma yolunda yazım yok', ev['__writes'], [])
  t('7a E: hiçbir görünüm HATA vermedi', ev.select { |_, x| x.to_s.start_with?('HATA') }.keys, [])

  # --- 7b: 0.51.4 dökümü ---
  obs('C (0.51.4) işlemleri', c['ops'])
  t('7b C: eski kodla Aks Yöneticisi kaydı ve Anlık Kayıt yapıldı', [(c['ops'] || [])[0].to_a[1], (c['ops'] || [])[1].to_a[1].to_s.start_with?('HATA')], [%w[start commit], false])
  t('7b C: eski dökümde görünen ad anahtarı yok', c['model_keys'].to_a.grep(/display_names/), [])
  t('7b C: eski dökümde revizyon arşivi var', c['model_keys'].to_a.include?('MAG_MST_RevisionLog/snapshots'), true)
  t('7b D: döküm fikstüre tam eşleşti', dd['unmatched'], 0)
  t('7b D: yeni kodla okuma yolunda yazım yok', dv['__writes'], [])
  t('7b D: hiçbir görünüm HATA vermedi', dv.select { |_, x| x.to_s.start_with?('HATA') }.keys, [])
  t('7b D: gösterim = kod (görünen ad yok)', [dv['names'], ((dv['label_maps'] || {})['structure_labels'] || {}).select { |k, x| k != x }], [[{}, {}], {}])
  %w[boq_rows qto3_totals dependency_graph revision_signatures boq_digest pile_labels qto_hierarchy workspace axis_display].each do |k|
    t("7b D: #{k} = 7a (yeni kod, aynı model)", dv[k], ev[k])
  end
  t('7b D: eski revizyon arşivi yeni kodla okunur (revisionLoaded, revisionError değil)', [dv['revision_payload'].to_s.start_with?('revisionLoaded('), dv['revision_payload'].to_s.include?('revisionError')], [true, false])
  t('7b D: eleman öznitelikleri açılışta değişmedi', dv['__writes'].to_a.reject { |p, _, _| p == 'model' }, [])
  obs('7b eski kodun metrajı (0.51.4) ↔ yeni kod aynı dökümde: farklı satır sayısı', ((c['old_boq_rows'] || []) - (dv['boq_rows'] || [])).size)
  rp = (JSON.parse(dv['revision_payload'].to_s[/\ArevisionLoaded\((.*)\);?\z/m, 1]) rescue nil)
  obs('7b eski arşiv ↔ güncel model karşılaştırma özeti (yeni kod)', rp && rp.select { |k, _| k.to_s =~ /count|summary|changed|added|removed|stale|latest/ })
end
puts "\nSONUÇ: #{$ok} geçti, #{$bad} kaldı"
exit($bad.zero? ? 0 : 1)
