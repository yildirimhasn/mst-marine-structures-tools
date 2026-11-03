# U2 / U3 ortak yardımcıları (03.11.2026): eklenti golden sahtesiyle yüklendikten ve r_helper require edildikten sonra kullanılır.
#  uv_main_dialog       gerçek show_dialog'u sahte HtmlDialog ile çalıştırır (tüm geri çağrılar)
#  uv_entities          modelden erişilebilen bütün varlıklar (Group iç varlıkları, Component tanımları; Group#definition çağrılmaz)
#  uv_dump / uv_restore öznitelik dökümü (Marshal: tip korunur) ↔ aynı geometrili fikstüre geri yükleme (kaydet / yeniden aç benzetimi)
#  uv_views             görünen ad + bağlantı + metraj çıktıları (yalnız yeni kodda; okuma yolları)
# Kanıt düzeyi: sahte nesne. .skp dosya biçimi, SketchUp'ın öznitelik serileştirmesi KANITLANMAZ (yalnız öznitelik durumu ↔ çıktı ilişkisi).
require 'digest'

def uv_main_dialog
  hd = Class.new(RDlg) { def initialize(*_a, **_k); super(); end }
  UI.send(:remove_const, :HtmlDialog) if UI.const_defined?(:HtmlDialog, false)
  UI.const_set(:HtmlDialog, hd); hd.const_set(:STYLE_DIALOG, 0)
  $msgs = []
  UI.define_singleton_method(:messagebox) { |*a| $msgs << a.first.to_s; 6 }
  M.instance_variable_set(:@d, nil)
  M.show_dialog
  M.instance_variable_get(:@d)
end

def uv_entities
  seen = {}; out = []
  visit = lambda do |e|
    return unless e.is_a?(Sketchup::Entity)
    return if seen[e.object_id]
    seen[e.object_id] = true; out << e
    e.entities.each { |c| visit.(c) } if (e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentDefinition)) && e.entities.respond_to?(:each)
    visit.(e.definition) if e.is_a?(Sketchup::ComponentInstance) && e.definition
  end
  $model.entities.each { |e| visit.(e) }
  Array($model.definitions).each { |e| visit.(e) }
  out
end

def uv_dump
  ents = uv_entities
  { 'model' => $model.instance_variable_get(:@attrs).dup,
    'ents' => ents.map { |e| [e.persistent_id, e.class.name, e.instance_variable_get(:@attrs).dup] } }
end

# Aynı geometriyle kurulmuş fikstüre dökümdeki öznitelikleri yazar (yazım sayılmaz; $writes sıfırlanır). Dönen: eşleşmeyen varlık sayısı.
def uv_restore(dump)
  $model.instance_variable_set(:@attrs, dump['model'].dup)
  by = uv_entities.group_by(&:persistent_id)
  miss = 0
  dump['ents'].each do |pid, cls, attrs|
    list = (by[pid] || []).select { |e| e.class.name == cls }
    if list.size == 1 then list.first.instance_variable_set(:@attrs, attrs.dup) else miss += 1 end
  end
  extra = by.keys - dump['ents'].map(&:first)
  $writes = []
  miss + extra.size
end

def uv_elem_sig
  rows = uv_entities.sort_by(&:persistent_id).map { |e| [e.persistent_id, e.instance_variable_get(:@attrs).sort_by { |k, _| k }.map { |k, v| [k, v.to_s] }] }
  Digest::SHA256.hexdigest(Marshal.dump(rows))[0, 16]
end

# Excel kitapları: boq2_xl_write yakalanır (dosya yazılmaz)
def uv_xl(kind)
  book = nil
  M.define_singleton_method(:boq2_xl_write) { |_p, sheets| book = sheets }
  begin
    kind == :kesif ? M.boq2_kesif_xlsx_write('x.xlsx') : M.boq2_hakedis_xlsx_write('x.xlsx')
  rescue StandardError => e
    return { 'hata' => "#{e.class}: #{e.message}" }
  end
  sheet = book[:list].find { |n, _| n == (kind == :kesif ? 'Poz Metrajları' : 'Onaylı Metraj') }
  return { 'hata' => 'sayfa yok' } unless sheet
  rows = sheet[1].map { |r| r.map { |c| c.is_a?(Hash) ? c[:v] : c } }
  hdr = rows.find { |r| r.include?('Yapı Kodu') }
  return { 'hata' => 'Yapı Kodu başlığı yok' } unless hdr
  iy = hdr.index('Yapı'); ik = hdr.index('Yapı Kodu')
  data = rows.select { |r| r.size == hdr.size && r != hdr && !r[0].to_s.start_with?('Eleman toplamı') }
  { 'header' => hdr, 'pairs' => data.map { |r| [r[iy].to_s, r[ik].to_s] }.uniq.sort }
end

def uv_capture_dialog
  html = nil
  orig = M.method(:mst_html_dialog)
  M.define_singleton_method(:mst_html_dialog) { |*_a, **_k| r = RDlg.new; r.define_singleton_method(:set_html) { |h| html = h }; r }
  yield
  M.define_singleton_method(:mst_html_dialog, &orig)
  html.to_s
end

def uv_views(d)
  v = {}
  w0 = ($writes || []).size
  safe = lambda do |k, &blk|
    v[k] = begin; blk.call; rescue StandardError => e; "HATA: #{e.class}: #{e.message[0, 160]}"; end
  end
  safe.('names') { [M.mst_structure_display_names($model), M.mst_axis_display_names($model)] }
  systems = (JSON.parse($model.get_attribute(D, 'system_structures_json', '{}')) rescue {})
  safe.('systems') { systems }
  safe.('label_maps') { M.mst_structure_label_maps(systems, $model) }
  safe.('axis_display') do
    amap = M.mst_axis_display_names($model)
    systems.values.flatten.map do |s|
      g = M.mst_axis_grid_for(s, $model, s)
      [s, %w[x y].map { |dir| g[dir].map { |r| [r['name'], M.mst_axis_display(s, s, dir, r['name'], amap)] } }]
    end
  end
  # Sahte sınırlayıcı kutu boş olabilir: konum / kot işlevleri sabitlenir (yalnız etiket METNİ sınanır)
  M.define_singleton_method(:mst_label_xy) { |_p| [0.0, 0.0] }
  M.define_singleton_method(:mst_label_z) { |*_a| 0.0 }
  safe.('pile_labels') { M.mst_label_plan($model).map { |r| r[:text] }.sort }
  safe.('qto_hierarchy') do
    piles = M.collect_piles($model.entities).map { |p, _| p }
    M.pile_qto_hierarchy(piles).select { |r| r[:level] == 'structure' }.map { |r| [r[:label], r[:structure], r[:key]] }
  end
  safe.('workspace') { M::ProjectWorkspace.payload($model)[:records].map { |r| [r[:id], r[:type], r[:fields]['structure'], r[:structure_label]] }.sort_by(&:to_s) }
  safe.('topbar') { n = d.out.size; d.cb['mstBKProjectContext'].call(nil); d.out[n..-1].grep(/\AmstBKProjectLoaded\(/).last.to_s }
  safe.('pile_grid') { n = d.out.size; d.cb['pile_load_central_grid'].call(nil); d.out[n..-1].grep(/\AloadCentralGridIntoPile\(/).last.to_s }
  safe.('takeoff_html') { uv_capture_dialog { M.takeoff } }
  safe.('takeoff_pile_html') { uv_capture_dialog { M.takeoff('pile') } }
  safe.('relationship_audit') { M::RelationshipAudit.analyze($model)[:records].flat_map { |r| r[:checks].map { |c| c[:message] } }.sort }
  safe.('excel_kesif') { uv_xl(:kesif) }
  safe.('excel_hakedis') { uv_xl(:hakedis) }
  safe.('dependency_graph') do
    all, ch, = M.dependency_graph($model)
    [all.map(&:persistent_id), ch.map { |a, bs| [a.persistent_id, bs.map(&:persistent_id).sort] }.sort]
  end
  safe.('revision_signatures') do
    a = []; M.collect_elements($model.entities, a)
    a.sort_by(&:persistent_id).map { |e| [e.persistent_id, M.revision_geometry_signature(e)] }
  end
  safe.('boq_digest') { M.boq2_boq_digest }
  safe.('boq_rows') { M.boq_rows(true).map { |r| [r[:code], r[:source], r[:unit], format('%.9f', r[:quantity].to_f)] } }
  safe.('qto3_totals') { M.qto3_snapshot[:totals].map { |k, x| [k.to_s, format('%.9f', x.to_f)] }.sort }
  safe.('revision_payload') { n = d.out.size; M.revision_send(d); d.out[n..-1].last.to_s.gsub(/"model_token":"\d+"/, '"model_token":"*"') }
  v['__writes'] = ($writes || [])[w0..-1].map { |p, dd, k| [p == $model.persistent_id ? 'model' : p, dd, k] }
  v['__elem_sig'] = uv_elem_sig
  v
end
