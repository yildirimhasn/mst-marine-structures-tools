# P5 / D5 (0.51.5 donma düzeltmesi, 3. aşama) — sonuç birebir aynı kalan hızlandırmalar:
#  R  — revision_geometry_signature: anlık kayıt hesabı (revision_current_snapshot) süresince alt ağaç şekli varlık başına, Component
#       iç kısmı tanım başına bir kez (revision_shape_memo). revision_create_snapshot ekran yenilemesinde aynı anlık kaydı yeniden kullanır.
#  J  — jg_walk dünya dönüşümünü yalnız jet grout öğesinde hesaplar (jg_world, aynı çarpım sırası); jg_elements okuma batch'inde bir kez.
# Eklenti golden-master sahtesiyle yüklenir; model tools/golden/fixture.rb + ek geometri:
#   yüz/kenarları köşeli (loops/vertices) Component kazık tanımı, iki örnek (biri ölçekli + aynalı), iç içe grup; jet grout grupları
#   (kökte, döndürülmüş ve ötelenmiş grup içinde, paylaşılan Component tanımı içinde).
# Sınanan:
#  1) Tüm öğelerin imzası önbellekli (tek kapsam) = önbelleksiz (her öğe ayrı), Component paylaşılan tanım, iç içe grup, ölçekli/aynalı
#     örnek, kazık + iç beton dahil; revision_current_snapshot / revision_payload / revision_send çıktısı ve yazımlar aynı.
#  2) Önbellekte yüz geometrisi okuması (Face#loops) yüz başına ≤ 1; kapsam bitince önbellek silinir (hata yolunda da).
#  3) revision_create_snapshot (değişiklik yok yolu ve kayıt yolu): diyalog çıktısı, iletiler, yazımlar, işlemler, kayıtlı arşiv aynı;
#     anlık kayıt bir kez hesaplanır.
#  4) jg_elements / jg_rows / dünya dönüşümleri eski düğüm düğüm hesapla bit düzeyinde aynı; send_boq, qto_summary, boq_rows,
#     send_boq_mapping batch'li = batch'siz (jet grout içeren ve içermeyen fikstür); okuma batch'inde tam jg gezintisi ≤ 1;
#     hata (ölçekli jet grout) önbelleğe alınmaz, iki çağrıda da aynı hata.
# Kullanim: ruby tools/test/p4_revision_jg.rb <src/marine_structures_tools>
require 'digest'
require_relative '../golden/sketchup_stub'
dir = ARGV[0] or abort 'kullanim: ruby tools/test/p4_revision_jg.rb <marine_structures_tools klasoru>'
$model = Sketchup::Model.new
require File.expand_path(File.join(dir, 'main.rb'))
require_relative '../golden/fixture'
M = MAG::MarineStructuresTools
D = 'MAG_MarineStructures'.freeze unless defined?(D)
$now = 1_800_000_000.0
class << Time; def now; Time.at($now); end; end

$ok = 0; $bad = 0
def t(label, got, exp)
  g = got == exp
  g ? $ok += 1 : $bad += 1
  puts "#{g ? 'GEÇTİ' : 'KALDI'}  #{label}: #{got.inspect[0, 160]} (beklenen #{exp.inspect[0, 160]})"
end

class RecDialog
  attr_reader :out
  def initialize; @out = []; end
  def execute_script(j); @out << j; true; end
  def set_html(h); @out << "HTML:#{h}"; true; end
  def visible?; true; end
  def method_missing(*_a); nil; end
  def respond_to_missing?(*) true end
end

# köşeli geometri (sahte): yüz döngüleri ve kenar köşeleri
P4V = Struct.new(:position)
class P4Loop; def initialize(pts); @v = pts.map { |p| P4V.new(Geom::Point3d.new(*p)) }; end; def vertices; @v; end; end
$loops_calls = Hash.new(0)
class P4Face < Sketchup::Face
  def initialize(pts); super(nil, {}); @lp = [P4Loop.new(pts)]; end
  def loops; $loops_calls[object_id] += 1; @lp; end
  undef_method :transformation   # gerçek SketchUp: yüz ve kenar dönüşüm taşımaz (imza yüz/kenar dalına girer)
end
class P4Edge < Sketchup::Edge
  def initialize(a, b); super(nil, {}); @v = [P4V.new(Geom::Point3d.new(*a)), P4V.new(Geom::Point3d.new(*b))]; end
  undef_method :transformation
  def vertices; @v; end
end
def p4_box(w)
  [P4Face.new([[0, 0, 0], [w, 0, 0], [w, w, 0]]), P4Face.new([[0, 0, 1], [w, 0, 1], [w, w, 1]]), P4Edge.new([0, 0, 0], [0, 0, 1]), P4Edge.new([w, 0, 0], [w, 0, 1])]
end
def jg_data(top, extra = {})
  JSON.generate({ 'type_id' => 'JG-01', 'diameter' => 800, 'top' => top, 'bottom' => top - 10, 'drill_top' => top, 'system' => 'single',
                  'enabled' => true, 'cement_kg_m' => 250, 'grout_l_m' => nil, 'steel_kg' => nil, 'color' => '#9B83CF',
                  'project' => 'GOLDEN', 'ano' => 'A1', 'axis' => '' }.merge(extra))
end
def jg_group(pid, tr, top, extra = {})
  g = Sketchup::Group.new(pid, 'element_type' => 'jet_grout', 'element_uid' => "JG-#{pid}", 'jet_grout_data' => jg_data(top, extra), 'type_id' => 'JG-01')
  g.entities = p4_box(0.4)
  g.transformation = tr
  g
end

def build(with_jg: true, bad_jg: false)
  golden_build_fixture
  add = []
  # Component kazık tanımı: köşeli yüzler + iç beton + iç içe grup (grup içinde grup)
  cdef = Sketchup::ComponentDefinition.new(7100)
  inf = Sketchup::Group.new(7101, 'element_type' => 'pile_infill_concrete', 'concrete_volume_m3' => V_INFILL, 'concrete_class' => 'C30/37')
  inf.entities = p4_box(0.9)
  nest_in = Sketchup::Group.new(7103); nest_in.entities = p4_box(0.2); nest_in.transformation = Geom::Transformation.translation([0.1, 0.2, 0.3])
  nest = Sketchup::Group.new(7102); nest.entities = [nest_in] + p4_box(0.5)
  nest.transformation = Geom::Transformation.rotation(ORIGIN, Z_AXIS, 0.3)
  cdef.entities = Sketchup::Entities.new([inf, nest] + p4_box(1.0))
  cp1 = Sketchup::ComponentInstance.new(7201, gf_pile_attrs('PC1', 'infill_enabled' => '1'))
  cp1.definition = cdef; cp1.transformation = Geom::Transformation.translation([50.m, 0, 1.2.m])
  cp2 = Sketchup::ComponentInstance.new(7202, gf_pile_attrs('PC2', 'infill_enabled' => '1'))
  cp2.definition = cdef
  cp2.transformation = Geom::Transformation.translation([55.m, 0, 1.2.m]) * Geom::Transformation.scaling(-1.0, 1.0, 1.25)   # aynalı + ölçekli
  # Group kazık P1'e köşeli geometri (iç beton çocuğuna da)
  p1 = $model.entities.find { |e| e.persistent_id == 1001 }
  p1.entities.first.entities = p4_box(0.8)
  p1.entities = p1.entities.to_a + p4_box(1.1)
  add.push(cp1, cp2)
  if with_jg
    j1 = jg_group(7301, Geom::Transformation.translation([60.m, 0, 0]), 0)
    holder = Sketchup::Group.new(7310)
    j2 = jg_group(7302, Geom::Transformation.translation([1.m, 2.m, -3.m]), -2, 'diameter' => 600)
    holder.entities = [j2] + p4_box(0.3)
    holder.transformation = Geom::Transformation.translation([70.m, 5.m, 1.m]) * Geom::Transformation.rotation(ORIGIN, Z_AXIS, Math::PI / 5)
    jdef = Sketchup::ComponentDefinition.new(7320)
    j3 = jg_group(7303, Geom::Transformation.translation([0, 0, 0.5.m]), 0.5)
    jdef.entities = Sketchup::Entities.new([j3])
    ji1 = Sketchup::ComponentInstance.new(7321); ji1.definition = jdef; ji1.transformation = Geom::Transformation.translation([80.m, 0, 0])
    ji2 = Sketchup::ComponentInstance.new(7322); ji2.definition = jdef; ji2.transformation = Geom::Transformation.translation([85.m, 3.m, 0])
    add.push(j1, holder, ji1, ji2)
    add << jg_group(7330, Geom::Transformation.translation([90.m, 0, 0]) * Geom::Transformation.scaling(1.0, 1.0, 1.5), 0) if bad_jg
    $model.definitions = Sketchup::Entities.new($model.definitions.to_a + [jdef])
  end
  add.each { |e| $model.entities << e; e.parent = $model.entities }
  $model.definitions = Sketchup::Entities.new($model.definitions.to_a + [cdef])
  walk = lambda do |list|
    list.each do |e|
      $all_ents[e.persistent_id] = e
      walk.(e.entities) if e.is_a?(Sketchup::Group)
      walk.(e.definition.entities) if e.is_a?(Sketchup::ComponentInstance)
    end
  end
  walk.($model.entities)
  M.instance_variable_set(:@mst_pile_idx_cache, nil)
  $now = 1_800_000_000.0
  $writes = []
end

def state_sig
  rows = ([$model] + $all_ents.values.sort_by(&:persistent_id)).map do |e|
    [e.persistent_id, e.attribute_dictionaries.compact.flat_map { |dd| dd.keys.sort.map { |k| [dd.name, k, dd[k].to_s] } }]
  end
  Digest::SHA256.hexdigest(Marshal.dump(rows))[0, 16]
end
def jsonish(v); JSON.generate(v); rescue StandardError; v.inspect; end

HAS_MEMO = M.respond_to?(:revision_shape_memo)
ORIG_MEMO = HAS_MEMO ? M.method(:revision_shape_memo) : nil
HAS_REUSE = M.respond_to?(:revision_send_reuse)
ORIG_REUSE = HAS_REUSE ? M.method(:revision_send_reuse) : nil
HAS_RB = M.respond_to?(:mst_read_batch)
ORIG_RB = HAS_RB ? M.method(:mst_read_batch) : nil
def speedups(on)
  if on
    M.define_singleton_method(:revision_shape_memo, &ORIG_MEMO) if HAS_MEMO
    M.define_singleton_method(:revision_send_reuse, &ORIG_REUSE) if HAS_REUSE
    M.define_singleton_method(:mst_read_batch, &ORIG_RB) if HAS_RB
  else
    M.define_singleton_method(:revision_shape_memo) { |&b| b.call } if HAS_MEMO
    M.define_singleton_method(:revision_send_reuse) { |d, _c, *_r| M.revision_send(d) } if HAS_REUSE   # G3 (03.11.2026): keşif özeti argümanı da yok sayılır
    M.define_singleton_method(:mst_read_batch) { |*_a, &b| b.call } if HAS_RB
  end
end
# sayaçlar
$occ = 0
o_occ = M.method(:revision_occurrence_signatures)
M.define_singleton_method(:revision_occurrence_signatures) { |*a| $occ += 1; o_occ.call(*a) }
$jg_top = 0
o_jg = M.method(:jg_walk)
M.define_singleton_method(:jg_walk) { |ents, *r| $jg_top += 1 if ents.respond_to?(:parent) && ents.parent.is_a?(Sketchup::Model); o_jg.call(ents, *r) }

puts "revision_shape_memo: #{HAS_MEMO}, revision_send_reuse: #{HAS_REUSE}, jg_world: #{M.respond_to?(:jg_world)}"

# 1) imzalar
build
all = []; M.collect_elements($model.entities, all)
elems = all.select { |e| !e.get_attribute(D, 'element_type', '').to_s.empty? }
occ = M.revision_occurrence_signatures($model.entities)
speedups(false)
plain = elems.map { |e| [e.persistent_id, M.revision_geometry_signature(e, occ)] }
$loops_calls.clear
speedups(true)
memo = nil
M.revision_shape_memo { memo = elems.map { |e| [e.persistent_id, M.revision_geometry_signature(e, occ)] } } if HAS_MEMO
memo ||= plain
t("imza: #{plain.size} öğe önbellekli = önbelleksiz", memo, plain)
%w[7201 7202 1001 2001].each do |pid|
  t("imza: PID #{pid} (#{{ '7201' => 'Component', '7202' => 'aynalı/ölçekli örnek', '1001' => 'Group kazık', '2001' => 'iç beton' }[pid]}) aynı",
    memo.assoc(pid.to_i), plain.assoc(pid.to_i))
end
t('imza: aynı tanımı paylaşan iki örneğin imzası farklı (örnek dönüşümü dahil)', plain.assoc(7201)[1] != plain.assoc(7202)[1], true)
faces = $loops_calls.size
t("imza: önbellekte yüz okuması yüz başına ≤ 1 (#{faces} yüz, #{$loops_calls.values.sum} okuma)", $loops_calls.values.max.to_i <= 1, true)
t('imza: kapsam sonrası önbellek silindi', M.instance_variable_get(:@mst_rev_shape_memo), nil)
if HAS_MEMO
  begin
    M.revision_shape_memo { raise 'deneme' }
  rescue StandardError
    nil
  end
  t('imza: hata yolunda önbellek silindi', M.instance_variable_get(:@mst_rev_shape_memo), nil)
end

# 1b) anlık kayıt / payload / send
def run_rev(on, kind)
  build
  snap = nil
  speedups(false)
  snap = M.revision_create_snapshot_base(M.revision_snapshots, M.revision_current_snapshot)
  $model.set_attribute(M::REVISION_DICT, 'snapshots', JSON.generate([snap]))
  $all_ents[1004].set_attribute(D, 'length_m', 26.0)
  speedups(on)
  $writes = []; $ui_msgs = []; $occ = 0; $loops_calls.clear
  d = RecDialog.new
  case kind
  when 'snapshot' then d.out << jsonish(M.revision_current_snapshot)
  when 'payload' then d.out << jsonish(M.revision_payload)
  when 'send' then M.revision_send(d)
  end
  { out: d.out, writes: $writes.dup, sig: state_sig, occ: $occ, loops: $loops_calls.values.sum }
end
%w[snapshot payload send].each do |k|
  a = run_rev(false, k); b = run_rev(true, k)
  t("revision_#{k}: çıktı aynı (#{b[:out].sum(&:bytesize)} bayt)", Digest::SHA256.hexdigest(b[:out].join), Digest::SHA256.hexdigest(a[:out].join))
  t("revision_#{k}: yazımlar ve son durum aynı", [b[:writes], b[:sig]], [a[:writes], a[:sig]])
  puts "      yüz geometrisi okuması: önbelleksiz=#{a[:loops]} önbellekli=#{b[:loops]}"
  t("revision_#{k}: yüz geometrisi okuması azaldı", b[:loops] < a[:loops], true)
end

# 3) revision_create_snapshot
def run_create(on, changed)
  build
  speedups(false)
  M.revision_create_snapshot(RecDialog.new)   # Rev.01
  $all_ents[1004].set_attribute(D, 'length_m', 26.0) if changed
  speedups(on)
  $now += 60
  $writes = []; $ui_msgs = []; $occ = 0; ops0 = $model.ops.size
  d = RecDialog.new
  r = M.revision_create_snapshot(d)
  { r: r, out: d.out, msgs: $ui_msgs.dup, writes: $writes.dup, ops: $model.ops[ops0..], arc: $model.get_attribute(M::REVISION_DICT, 'snapshots'), occ: $occ,
    reuse: M.instance_variable_get(:@mst_revision_curr_reuse) }
end
[[false, 'değişiklik yok'], [true, 'kayıt']].each do |changed, lbl|
  a = run_create(false, changed); b = run_create(true, changed)
  t("create_snapshot (#{lbl}): dönüş, iletiler, işlemler aynı", [b[:r], b[:msgs], b[:ops]], [a[:r], a[:msgs], a[:ops]])
  t("create_snapshot (#{lbl}): diyalog çıktısı aynı", Digest::SHA256.hexdigest(b[:out].join), Digest::SHA256.hexdigest(a[:out].join))
  t("create_snapshot (#{lbl}): yazımlar ve arşiv aynı", [b[:writes], Digest::SHA256.hexdigest(b[:arc].to_s)], [a[:writes], Digest::SHA256.hexdigest(a[:arc].to_s)])
  puts "      anlık kayıt hesabı: eski yol=#{a[:occ]} yeni=#{b[:occ]}"
  t("create_snapshot (#{lbl}): anlık kayıt bir kez hesaplandı", b[:occ], 1)
  t("create_snapshot (#{lbl}): yeniden kullanım bayrağı temizlendi", b[:reuse], nil)
end

# 4) jet grout
def old_jg_walk(entities, out = [], parent = nil)
  entities.each do |e|
    next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
    tr = e.transformation.to_a if e.respond_to?(:transformation)
    world = parent && tr ? (0...16).map { |i| r = i % 4; c = i / 4; 4.times.sum { |k| parent[k * 4 + r] * tr[c * 4 + k] } } : tr
    if e.get_attribute(D, 'element_type') == 'jet_grout'
      out << [e.persistent_id, world]
    else
      old_jg_walk(e.is_a?(Sketchup::Group) ? e.entities : e.definition.entities, out, world)
    end
  end
  out
end
build
ref = old_jg_walk($model.entities)
if M.respond_to?(:jg_world)
  got = []
  w = lambda do |ents, chain|
    ents.each do |e|
      next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
      if e.get_attribute(D, 'element_type') == 'jet_grout' then got << [e.persistent_id, M.jg_world(nil, chain + [e])]
      else w.(e.is_a?(Sketchup::Group) ? e.entities : e.definition.entities, chain + [e])
      end
    end
  end
  w.($model.entities, [])
  t("jg_world: #{ref.size} jet grout dünya dönüşümü bit düzeyinde aynı", got.map { |p, a| [p, a.pack('G*')] }, ref.map { |p, a| [p, a.pack('G*')] })
end
speedups(true)
t('jg_elements: sıra ve öğeler eski gezintiyle aynı', M.jg_elements.map(&:persistent_id), ref.map(&:first))
t('jg_rows: değerler (4 jet grout; veri grubu başına adet, çap)', M.jg_rows.map { |r| [r[:count], r[:data]['diameter']] }.sort, [[1, 600.0], [1, 800.0], [2, 800.0]])

JG_ENTRIES = {
  'send_boq' => ->(d) { M.send_boq(d) },
  'qto_summary' => ->(d) { M.qto_summary(d) },
  'boq_rows' => ->(d) { M.mst_read_batch { d.out << jsonish(M.boq_rows(true)); d.out << jsonish(M.boq_rows(true)) } },
  'send_boq_mapping' => ->(d) { M.send_boq_mapping(d) },
  'jg_rows' => ->(d) { M.mst_read_batch { d.out << jsonish(M.jg_rows); d.out << jsonish(M.jg_export_rows) } }
}.freeze
[true, false].each do |with_jg|
  JG_ENTRIES.each do |name, fn|
    res = [false, true].map do |on|
      build(with_jg: with_jg)
      speedups(on)
      $ui_msgs = []; $jg_top = 0; $writes = []
      d = RecDialog.new
      fn.(d)
      { out: d.out.map { |s| s.gsub(/"model_token":"\d+"/, '"model_token":"*"') }, msgs: $ui_msgs.dup, top: $jg_top, writes: $writes.dup }
    end
    a, b = res
    lbl = "#{name} (jet grout #{with_jg ? 'VAR' : 'YOK'})"
    t("#{lbl}: çıktı batch'li = batch'siz (#{b[:out].sum(&:bytesize)} bayt)", Digest::SHA256.hexdigest(b[:out].join("\n")), Digest::SHA256.hexdigest(a[:out].join("\n")))
    t("#{lbl}: iletiler ve yazımlar aynı", [b[:msgs], b[:writes]], [a[:msgs], a[:writes]])
    t("#{lbl}: jet grout satırı var/yok", b[:out].join.include?('Jet Grout') || b[:out].join.include?('JETGROUT'), with_jg) unless name == 'jg_rows'
    puts "      tam jg gezintisi: batch'siz=#{a[:top]} batch'li=#{b[:top]}"
    t("#{lbl}: okuma batch'inde tam jg gezintisi ≤ 1", b[:top] <= 1, true)
  end
end
# hata önbelleğe alınmaz
build(bad_jg: true)
speedups(true)
errs = []
$jg_top = 0
M.mst_read_batch do
  2.times do
    begin
      M.jg_elements
      errs << nil
    rescue StandardError => e
      errs << e.message
    end
  end
end
t('hata: ölçekli jet grout iki çağrıda da aynı hata (önbelleğe alınmadı)', [errs.uniq.size, errs.first.to_s.include?('ölçeklenmiş'), $jg_top], [1, true, 2])
t('batch sonrası jg önbelleği silindi', M.instance_variable_get(:@mst_jg_elements_cache), nil)
build
$jg_top = 0
M.mst_scan_batch($model) { M.jg_elements; M.jg_elements }
t('yazma batch\'i: jg önbelleği yok (iki gezinti)', $jg_top, 2)
$jg_top = 0
M.jg_elements; M.jg_elements
t('batch dışı: iki gezinti', $jg_top, 2)

puts "\n#{$ok} geçti, #{$bad} kaldı"
exit($bad.zero? ? 0 : 1)
