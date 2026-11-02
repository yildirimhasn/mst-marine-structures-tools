# Golden-master sahte model fikstur (SketchUp DISINDA). Iki kaynak surumune AYNI durum verilir; yalniz okuyucular calisir.
# Ogeler (SI birim; oznitelikler m / mm / m³ / m²):
#  P1  Group kazik Ø1016×16, L=30, dusey, ust +1.20; fiziksel ic beton cocugu (Group pile_infill_concrete, 9.126 m³, C30/37);
#      tapa + ust cember + PE 10 m; BK1 ekseninde BK basindan a=9.5 m (son dis bolgesi)
#  P2  Component kazik Ø1016×16, "ic beton YOK" (infill_enabled=0), tanimi P2B ile paylasir; tanimda ic beton cocugu (9.126 m³)
#  P2B Component kazik, ayni tanim, ic beton VAR (infill_concrete_volume_m3 = 9.126)
#  P3  Group kazik Ø1016×16, egik 1:6 (BATTERED), ic beton parametreden (infill_concrete_volume_m3 = 8.0, C35/45),
#      BIM kafes donatisi (pile_rebar_mode=bim_detail, pile_cage_rebar_kg=1500, hata kaydi yok); BK1'de a=5.0 m
#  P4  Group kazik Ø914×14, L=24, ic beton yok, foraj 6 m, alt cember
#  BK1 Group BK 10×1.2×1.0, taban +1.00 ust +2.00, son dis 1.5/0.3/0.5, 30° donuk; bagli kaziklar P1, P3 (persistent id);
#      yuzler: alt kalipta; kayitli kazik acikligi 2 daire
#  BK2 Group BK ayni olcu, alt yuz KALIPTA DEGIL; kayitli kazik acikligi 2 daire; bagli kazik yok
#  D1  Doseme 10×5, beton 15 m³, kalip 20 m², kaplama VAR 50 m² × 0.12 m; donati BIM (rebar_t 1.8)
#  T1  Kaplama ogesi (deck_topping, parent_deck_id D1) — collect_elements disi
#  C1  Bordur (parent_deck_id D1) C35/45, beton 1.2 m³, kalip 6 m²
#  CW1 Kronman C30/37, beton 20 m³, kalip 40 m²
#  PD1 Group normal prekast C35/45, 2.0 m³, kalip 8 m²
#  PD2 Group normal prekast C30/37 (poz eslenmemis sinif), 1.5 m³, kalip 6 m²
#  PK1 Component kanal prekasti C35/45, 3.0 m³, kalip 10 m²; tanimda pc_rebar_attrs_json rebar_t 0.12
#  PV1 Group vinc prekasti C35/45, 4.0 m³, kalip 12 m²
# Parti G-b eklemeleri (ADR 13 "Golden-master gerekli"; G4/G5/G6 ve kopyanin kopyasi hakedisi):
#  D1  ek: hakedis kaydi HB_DECK_CONCRETE %100 onayli (2026-10-01)
#  C1  ek: eski durum alani progress_status=Onaylandi (onceki donemde onaylanmis bordur)
#  D2  Eski tip doseme (topping_enabled YOK → kaplama 0.10 m, alan = brut 20 − bordur 1.5 = 18.5 m²), beton 10 m³, kalip 8 m²,
#      C30/37, donati pursantaj (rebar_mode yok); kaplama sinifi yok
#  C2  Ayri bordur (parent_deck_id D2) 5×0.3, C35/45, beton 0.6 m³, kalip 3 m² — donatisi hacim × rebar_rate('deck')
#  D3  DS2 doseme (bordur govdede, curb_volume_m3 0.4), kaplama yok, beton 5 m³, kalip 4 m², C30/37, pursantaj
#  C3  Ayri bordur (parent_deck_id D3) C30/37, beton 0.3 m³, kalip 1.5 m² (Model Kontrolu G4 uyarisi: cift sayim olasi)
#  D1K D1'in kopyasinin kopyasi, BIM Kimlik Onarimi sonrasi durum: yeni UID, copied_from_uid, devralinmis ilerleme +
#      progress_inherited_history_json (1 kayit), progress_items_json YOK, durum Planlandi; kaplama yok, beton 15 m³, kalip 20 m²
# Model: pile_boq_mode_PILE_STEEL = separate (K35 kod-NN atamasi gorunur), hakedis gecmisi yok.
D = 'MAG_MarineStructures'.freeze unless defined?(D)
V_INFILL = Math::PI / 4 * 0.984**2 * 12.0
GB_PJ = '{"HB_DECK_CONCRETE":{"claim":100,"ok":[["2026-10-01",100,"golden"]]}}'.freeze

def gf_face(type, fw, area)
  f = Sketchup::Face.new(nil, 'formwork_type' => type, 'formwork' => fw)
  f.area_m2 = area
  f.normal = Geom::Vector3d.new(0, 0, type == 'BOTTOM' ? -1 : 1)
  f
end

def gf_bk_faces(bottom_fw)
  [gf_face('BOTTOM', bottom_fw, 12.0), gf_face('LONG_SIDE', true, 10.0), gf_face('LONG_SIDE', true, 10.0),
   gf_face('END_FACE', true, 1.2), gf_face('END_FACE', true, 1.2), gf_face('TOP_OR_CONTACT', false, 12.0)]
end

def gf_pile_attrs(id, extra = {})
  { 'element_type' => 'steel_pipe_pile', 'pile_id' => id, 'diameter_mm' => 1016.0, 'thickness_mm' => 16.0,
    'length_m' => 30.0, 'actual_length_m' => 30.0, 'top_elevation_m' => 1.2, 'bottom_elevation_m' => -28.8,
    'seabed_elevation_m' => -8.0, 'steel_grade' => 'S355', 'system' => 'S1', 'structure' => 'ISKELE', 'ano' => 'A1',
    'project' => 'GOLDEN', 'element_uid' => "MST-GOLD-#{id}", 'type_id' => 'PILE-1016', 'infill_concrete_class' => 'C30/37' }.merge(extra)
end

def golden_build_fixture
  $model = Sketchup::Model.new
  $pid_seq = 100_000
  ents = []
  bk_tr = Geom::Transformation.translation([5.0.m, 7.0.m, 1.0.m]) * Geom::Transformation.rotation(ORIGIN, Z_AXIS, Math::PI / 6)
  at = ->(a) { bk_tr * Geom::Transformation.translation([a.m, 0.6.m, 0.2.m]) }

  child1 = Sketchup::Group.new(2001, 'element_type' => 'pile_infill_concrete', 'concrete_volume_m3' => V_INFILL, 'concrete_class' => 'C30/37', 'element_uid' => 'MST-GOLD-P1-INF')
  p1 = Sketchup::Group.new(1001, gf_pile_attrs('P1', 'infill_enabled' => '1', 'plug_enabled' => '1', 'upper_ring_enabled' => '1',
                                                    'pe_enabled' => '1', 'pe_length_m' => 10.0))
  p1.entities = [child1]
  p1.transformation = at.(9.5)

  defn = Sketchup::ComponentDefinition.new(3001)
  child2 = Sketchup::Group.new(2002, 'element_type' => 'pile_infill_concrete', 'concrete_volume_m3' => V_INFILL, 'concrete_class' => 'C30/37')
  defn.entities = Sketchup::Entities.new([child2])
  p2 = Sketchup::ComponentInstance.new(1002, gf_pile_attrs('P2', 'infill_enabled' => '0', 'infill_concrete_volume_m3' => 0.0))
  p2.definition = defn
  p2.transformation = Geom::Transformation.translation([30.m, 0, 1.2.m])
  p2b = Sketchup::ComponentInstance.new(1005, gf_pile_attrs('P2B', 'infill_enabled' => '1', 'infill_concrete_volume_m3' => V_INFILL))
  p2b.definition = defn
  p2b.transformation = Geom::Transformation.translation([33.m, 0, 1.2.m])

  p3 = Sketchup::Group.new(1003, gf_pile_attrs('P3', 'orientation_mode' => 'BATTERED', 'batter_ratio' => 1.0 / 6.0, 'infill_enabled' => '1',
                                                    'infill_concrete_volume_m3' => 8.0, 'infill_concrete_class' => 'C35/45',
                                                    'pile_rebar_mode' => 'bim_detail', 'pile_rebar_json' => '{"long_dia_mm":25}', 'pile_cage_rebar_kg' => 1500.0))
  p3.transformation = at.(5.0)

  p4 = Sketchup::Group.new(1004, gf_pile_attrs('P4', 'diameter_mm' => 914.0, 'thickness_mm' => 14.0, 'length_m' => 24.0, 'actual_length_m' => 24.0,
                                                    'bottom_elevation_m' => -22.8, 'infill_enabled' => '0', 'drilling_enabled' => '1', 'drilling_length_m' => 6.0,
                                                    'lower_ring_enabled' => '1', 'infill_concrete_class' => ''))
  p4.transformation = Geom::Transformation.translation([40.m, 0, 1.2.m])

  circle = Math::PI / 4 * 1.016**2
  bk_attrs = { 'element_type' => 'head_beam', 'length_m' => 10.0, 'width_m' => 1.2, 'height_m' => 1.0,
               'bottom_elevation_m' => 1.0, 'top_elevation_m' => 2.0, 'concrete_volume_m3' => 11.85, 'concrete_class' => 'C30/37',
               'end_tooth_enabled' => '1', 'end_tooth_length_m' => 1.5, 'end_tooth_slope_m' => 0.3, 'end_tooth_depth_m' => 0.5,
               'pile_opening_area_m2' => 2 * circle, 'ano' => 'A1', 'project' => 'GOLDEN' }
  bk1 = Sketchup::Group.new(4001, bk_attrs.merge('head_beam_id' => 'BK1', 'connected_pile_persistent_ids' => '1001,1003', 'connected_pile_ids' => 'P1,P3', 'element_uid' => 'MST-GOLD-BK1'))
  bk1.entities = gf_bk_faces(true)
  bk1.transformation = bk_tr
  bk2 = Sketchup::Group.new(4002, bk_attrs.merge('head_beam_id' => 'BK2', 'element_uid' => 'MST-GOLD-BK2'))
  bk2.entities = gf_bk_faces(false)
  bk2.transformation = Geom::Transformation.translation([5.0.m, 20.0.m, 1.0.m])

  d1 = Sketchup::Group.new(5001, 'element_type' => 'deck_slab', 'deck_id' => 'D1', 'concrete_volume_m3' => 15.0, 'formwork_area_m2' => 20.0,
                                 'concrete_class' => 'C30/37', 'topping_enabled' => '1', 'topping_area_m2' => 50.0, 'topping_thickness_m' => 0.12,
                                 'topping_concrete_class' => 'C30/37', 'gross_area_m2' => 50.0, 'rebar_mode' => 'bim_detail', 'rebar_t' => 1.8, 'element_uid' => 'MST-GOLD-D1',
                                 'progress_items_json' => GB_PJ)
  t1 = Sketchup::Group.new(5002, 'element_type' => 'deck_topping', 'parent_deck_id' => 'D1', 'parent_uid' => 'MST-GOLD-D1', 'concrete_volume_m3' => 6.0, 'net_area_m2' => 50.0)
  c1 = Sketchup::Group.new(5003, 'element_type' => 'curb', 'parent_deck_id' => 'D1', 'length_m' => 10.0, 'width_m' => 0.4,
                                 'concrete_volume_m3' => 1.2, 'formwork_area_m2' => 6.0, 'concrete_class' => 'C35/45', 'progress_status' => 'Onaylandı')
  cw1 = Sketchup::Group.new(5004, 'element_type' => 'crown_wall', 'concrete_volume_m3' => 20.0, 'formwork_area_m2' => 40.0, 'concrete_class' => 'C30/37')
  pd1 = Sketchup::Group.new(6001, 'element_type' => 'flat_precast', 'concrete_volume_m3' => 2.0, 'formwork_area_m2' => 8.0, 'concrete_class' => 'C35/45')
  pd2 = Sketchup::Group.new(6002, 'element_type' => 'flat_precast', 'concrete_volume_m3' => 1.5, 'formwork_area_m2' => 6.0, 'concrete_class' => 'C30/37')
  pkd = Sketchup::ComponentDefinition.new(6100, { 'pc_rebar_attrs_json' => JSON.generate('rebar_t' => 0.12) })
  pk1 = Sketchup::ComponentInstance.new(6003, 'element_type' => 'channel_precast', 'concrete_volume_m3' => 3.0, 'formwork_area_m2' => 10.0, 'concrete_class' => 'C35/45')
  pk1.definition = pkd
  pv1 = Sketchup::Group.new(6004, 'element_type' => 'crane_precast', 'concrete_volume_m3' => 4.0, 'formwork_area_m2' => 12.0, 'concrete_class' => 'C35/45')

  # Parti G-b eklemeleri
  d2 = Sketchup::Group.new(5011, 'element_type' => 'deck_slab', 'deck_id' => 'D2', 'concrete_volume_m3' => 10.0, 'formwork_area_m2' => 8.0,
                                 'concrete_class' => 'C30/37', 'gross_area_m2' => 20.0, 'element_uid' => 'MST-GOLD-D2')
  c2 = Sketchup::Group.new(5012, 'element_type' => 'curb', 'curb_id' => 'B-D2-1', 'parent_deck_id' => 'D2', 'length_m' => 5.0, 'width_m' => 0.3,
                                 'concrete_volume_m3' => 0.6, 'formwork_area_m2' => 3.0, 'concrete_class' => 'C35/45')
  d3 = Sketchup::Group.new(5013, 'element_type' => 'deck_slab', 'deck_id' => 'D3', 'concrete_volume_m3' => 5.0, 'formwork_area_m2' => 4.0,
                                 'concrete_class' => 'C30/37', 'topping_enabled' => '0', 'curb_volume_m3' => 0.4, 'element_uid' => 'MST-GOLD-D3')
  c3 = Sketchup::Group.new(5014, 'element_type' => 'curb', 'curb_id' => 'B-D3-1', 'parent_deck_id' => 'D3', 'length_m' => 3.0, 'width_m' => 0.25,
                                 'concrete_volume_m3' => 0.3, 'formwork_area_m2' => 1.5, 'concrete_class' => 'C30/37')
  hist = JSON.generate([{ 'v' => 1, 'at' => '2026-10-20T10:00:00+0300', 'source' => 'repair_bim_identity', 'from_uid' => 'MST-5009-1790000000-R',
                          'new_uid' => 'MST-5015-1800000000-R', 'items_json' => GB_PJ, 'status' => nil, 'prev_copied_from_uid' => 'MST-GOLD-D1',
                          'prev_uid_owner_pid' => 5009 }])
  d1k = Sketchup::Group.new(5015, 'element_type' => 'deck_slab', 'deck_id' => 'D1-K', 'concrete_volume_m3' => 15.0, 'formwork_area_m2' => 20.0,
                                  'concrete_class' => 'C30/37', 'topping_enabled' => '0', 'element_uid' => 'MST-5015-1800000000-R', 'uid_owner_pid' => 5015,
                                  'copied_from_uid' => 'MST-5009-1790000000-R', 'progress_inherited_json' => GB_PJ,
                                  'progress_inherited_history_json' => hist, 'progress_status' => 'Planlandı')

  ents = [p1, p2, p2b, p3, p4, bk1, bk2, d1, t1, c1, cw1, pd1, pd2, pk1, pv1, d2, c2, d3, c3, d1k]
  $model.entities = Sketchup::Entities.new(ents)
  $model.entities.parent = $model
  ents.each { |e| e.parent = $model.entities }
  $model.definitions = Sketchup::Entities.new([defn, pkd])
  $model.set_attribute(D, 'pile_boq_mode_PILE_STEEL', 'separate')
  $all_ents = {}
  walk = lambda do |list|
    list.each do |e|
      $all_ents[e.persistent_id] = e
      walk.(e.entities) if e.is_a?(Sketchup::Group)
    end
  end
  walk.(ents)
  ents
end
