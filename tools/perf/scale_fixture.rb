# Olceklenebilir sahte model (SketchUp DISINDA, sahte nesne). Golden-master fiksturundeki (tools/golden/fixture.rb) oge
# kaliplari "blok" halinde cogaltilir; her blok 20 collect_elements ogesi + 2 kaplama (collect disi) icerir:
#   6 kazik Group (Ø1016×16, L=30; her birinde fiziksel ic beton cocugu pile_infill_concrete → 12 oge; 6. kazik egik 1:6,
#     BIM kafes donatisi), 3 BK Group (10×1.2×1.0, 6 yuz, her biri 2 kaziga bagli, kayitli 2 daire aciklik),
#   2 doseme (kaplama VAR, BK destekli; ilki BIM donati, ikincisi pursantaj) + 2 fiziksel kaplama Group (deck_topping),
#   2 bordur (parent_deck_id), 1 prekast (iki BK arasi; her 3. blokta kanal prekasti Component, her 5. blokta vinc prekasti).
# Oran (kazik + ic beton %60) gercek modele benzer olsun diye secildi; olcu/miktar degerleri golden fikstur degerleridir.
# Ham geometri: gercek modelde kazik/ic beton/BK gruplarinin icinde cok sayida kenar/yuz vardir. PERF_RAW="kazik,ic_beton,bk"
# ortam degiskeni (varsayilan 0,0,0) ile her gruba o kadar oznitelik siz Sketchup::Edge eklenir (metraj degerini degistirmez;
# yalniz grup icini tarayan cagrilarin maliyetini gorunur yapar).
# Kullanim: require_relative 'scale_fixture'; perf_build_fixture(blok_sayisi) → collect_elements oge sayisi = 20 × blok
D = 'MAG_MarineStructures'.freeze unless defined?(D)
PF_V_INFILL = Math::PI / 4 * 0.984**2 * 12.0
PF_CIRCLE = Math::PI / 4 * 1.016**2
PF_RAW = (ENV["PERF_RAW"] || "0,0,0").split(",").map(&:to_i)
def pf_raw(k); Array.new(k) { Sketchup::Edge.new }; end

def pf_face(type, fw, area)
  f = Sketchup::Face.new(nil, 'formwork_type' => type, 'formwork' => fw)
  f.area_m2 = area
  f.normal = Geom::Vector3d.new(0, 0, type == 'BOTTOM' ? -1 : 1)
  f
end

def pf_bk_faces
  [pf_face('BOTTOM', true, 12.0), pf_face('LONG_SIDE', true, 10.0), pf_face('LONG_SIDE', true, 10.0),
   pf_face('END_FACE', true, 1.2), pf_face('END_FACE', true, 1.2), pf_face('TOP_OR_CONTACT', false, 12.0)]
end

def pf_pile_attrs(id, pid, extra = {})
  { 'element_type' => 'steel_pipe_pile', 'pile_id' => id, 'diameter_mm' => 1016.0, 'thickness_mm' => 16.0,
    'length_m' => 30.0, 'actual_length_m' => 30.0, 'top_elevation_m' => 1.2, 'bottom_elevation_m' => -28.8,
    'seabed_elevation_m' => -8.0, 'steel_grade' => 'S355', 'system' => 'S1', 'structure' => 'ISKELE', 'ano' => 'A1',
    'project' => 'PERF', 'element_uid' => "MST-#{pid}-1700000000-P", 'type_id' => 'PILE-1016', 'infill_concrete_class' => 'C30/37',
    'infill_enabled' => '1', 'plug_enabled' => '1', 'upper_ring_enabled' => '1', 'pe_enabled' => '1', 'pe_length_m' => 10.0 }.merge(extra)
end

def perf_build_fixture(blocks)
  $model = Sketchup::Model.new
  $pid_seq = 50_000_000
  ents = []
  defs = []
  blocks.times do |b|
    base = 1_000_000 + b * 1000
    bks = []
    3.times do |k|
      bk_tr = Geom::Transformation.translation([(b * 40 + k * 12).m, 0, 1.0.m])
      piles = []
      2.times do |j|
        pi = k * 2 + j
        pid = base + 10 + pi
        battered = pi == 5
        extra = if battered
                  { 'orientation_mode' => 'BATTERED', 'batter_ratio' => 1.0 / 6.0, 'pile_rebar_mode' => 'bim_detail',
                    'pile_rebar_json' => '{"long_dia_mm":25}', 'pile_cage_rebar_kg' => 1500.0 }
                else
                  {}
                end
        p = Sketchup::Group.new(pid, pf_pile_attrs("P#{b}-#{pi}", pid, extra))
        cpid = base + 100 + pi
        ch = Sketchup::Group.new(cpid, 'element_type' => 'pile_infill_concrete', 'concrete_volume_m3' => PF_V_INFILL,
                                       'concrete_class' => 'C30/37', 'element_uid' => "MST-#{cpid}-1700000000-I")
        p.entities = [ch] + pf_raw(PF_RAW[0])
        ch.entities = pf_raw(PF_RAW[1])
        p.transformation = bk_tr * Geom::Transformation.translation([(2.5 + j * 5.0).m, 0.6.m, 0.2.m])
        piles << p
      end
      bkpid = base + 200 + k
      bk = Sketchup::Group.new(bkpid, 'element_type' => 'head_beam', 'head_beam_id' => "BK#{b}-#{k}", 'length_m' => 10.0, 'width_m' => 1.2,
                                      'height_m' => 1.0, 'bottom_elevation_m' => 1.0, 'top_elevation_m' => 2.0, 'concrete_volume_m3' => 11.85,
                                      'concrete_class' => 'C30/37', 'pile_opening_area_m2' => 2 * PF_CIRCLE, 'ano' => 'A1', 'project' => 'PERF',
                                      'connected_pile_persistent_ids' => piles.map(&:persistent_id).join(','),
                                      'connected_pile_ids' => piles.map { |p| p.get_attribute(D, 'pile_id') }.join(','),
                                      'element_uid' => "MST-#{bkpid}-1700000000-B")
      bk.entities = pf_bk_faces + pf_raw(PF_RAW[2])
      bk.transformation = bk_tr
      bks << bk
      ents.concat(piles)
      ents << bk
    end
    2.times do |k|
      dpid = base + 300 + k
      duid = "MST-#{dpid}-1700000000-D"
      d = Sketchup::Group.new(dpid, 'element_type' => 'deck_slab', 'deck_id' => "D#{b}-#{k}", 'concrete_volume_m3' => 15.0, 'formwork_area_m2' => 20.0,
                                    'concrete_class' => 'C30/37', 'topping_enabled' => '1', 'topping_area_m2' => 50.0, 'topping_thickness_m' => 0.12,
                                    'topping_concrete_class' => 'C30/37', 'gross_area_m2' => 50.0, 'element_uid' => duid,
                                    'support_pids' => "#{bks[k].persistent_id},#{bks[k + 1].persistent_id}", 'ano' => 'A1', 'project' => 'PERF')
      if k.zero?
        d.set_attribute(D, 'rebar_mode', 'bim_detail')
        d.set_attribute(D, 'rebar_t', 1.8)
      end
      t = Sketchup::Group.new(base + 400 + k, 'element_type' => 'deck_topping', 'parent_deck_id' => "D#{b}-#{k}", 'parent_uid' => duid,
                                              'concrete_volume_m3' => 6.0, 'net_area_m2' => 50.0)
      c = Sketchup::Group.new(base + 500 + k, 'element_type' => 'curb', 'curb_id' => "B#{b}-#{k}", 'parent_deck_id' => "D#{b}-#{k}", 'length_m' => 10.0,
                                              'width_m' => 0.4, 'concrete_volume_m3' => 1.2, 'formwork_area_m2' => 6.0, 'concrete_class' => 'C35/45',
                                              'ano' => 'A1', 'project' => 'PERF')
      ents.push(d, t, c)
    end
    sup = { 'support_left_pid' => bks[0].persistent_id, 'support_right_pid' => bks[1].persistent_id, 'ano' => 'A1', 'project' => 'PERF' }
    if (b % 3) == 2
      pkd = Sketchup::ComponentDefinition.new(base + 610, { 'pc_rebar_attrs_json' => JSON.generate('rebar_t' => 0.12) })
      pk = Sketchup::ComponentInstance.new(base + 600, sup.merge('element_type' => 'channel_precast', 'concrete_volume_m3' => 3.0,
                                                                 'formwork_area_m2' => 10.0, 'concrete_class' => 'C35/45'))
      pk.definition = pkd
      defs << pkd
      ents << pk
    elsif (b % 5) == 4
      ents << Sketchup::Group.new(base + 600, sup.merge('element_type' => 'crane_precast', 'concrete_volume_m3' => 4.0,
                                                        'formwork_area_m2' => 12.0, 'concrete_class' => 'C35/45'))
    else
      ents << Sketchup::Group.new(base + 600, sup.merge('element_type' => 'flat_precast', 'precast_id' => "PD#{b}", 'concrete_volume_m3' => 2.0,
                                                        'formwork_area_m2' => 8.0, 'concrete_class' => 'C35/45'))
    end
  end
  $model.entities = Sketchup::Entities.new(ents)
  $model.entities.parent = $model
  ents.each { |e| e.parent = $model.entities }
  $model.definitions = Sketchup::Entities.new(defs)
  $model.set_attribute(D, 'pile_boq_mode_PILE_STEEL', 'separate')
  $all_ents = {}
  walk = lambda do |list|
    list.each do |e|
      $all_ents[e.persistent_id] = e
      walk.(e.entities) if e.is_a?(Sketchup::Group)
    end
  end
  walk.(ents)
  $writes = []
  ents
end
