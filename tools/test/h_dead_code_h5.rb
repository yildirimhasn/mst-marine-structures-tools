# Parti H / K30 ölü kod (yalnız Ruby tarafındaki GÜVENLE SİLİNEBİLİR kalemler, 18_olu_kod_analizi.md) ve H5 Ruby kısmı.
# Silinen: pile_update_selected_bim kaydı + mst_update_selected_bim_pile; pile_edit_v2, pile_batch_details_from_page, formwork_yes,
# formwork_no, bk_formwork_face_tool, select_pile_qto_id kayıtları; audit_repair_* dört kayıt; boq_pro.rb wrap.('prog2_view_date').
# Kalan (silinmemeli): işlevler ve bakım listesi / menü yolları.
# Kullanim: ruby tools/test/h_dead_code_h5.rb <src/marine_structures_tools>
require_relative 'a2_helper'
dir = A1.dir
main = A1.src('main.rb')
bq = A1.src('boq_pro.rb')
all_src = Dir[File.join(dir, '**', '*.{rb,js,html,json}')].map { |f| File.binread(f).force_encoding('UTF-8') }.join("\n")
gone = %w[pile_update_selected_bim pile_edit_v2 pile_batch_details_from_page formwork_yes formwork_no bk_formwork_face_tool select_pile_qto_id
          audit_repair_pile_types audit_repair_pipe_weights audit_repair_bk_types audit_repair_precast_types]
t('K30 silinen callback kayıtları yok', gone.select { |n| main.include?("add_action_callback('#{n}')") }, [])
t('K30 boq_pro.rb wrap.(\'prog2_view_date\') kaydı yok', bq.include?("wrap.('prog2_view_date')"), false)
t('K30 mst_update_selected_bim_pile ve selectedBimPileUpdated başvurusu yok', [all_src.include?('mst_update_selected_bim_pile'), all_src.include?('selectedBimPileUpdated')], [false, false])
t('K30 silinen adlara JS / HTML çağrısı yok (sketchup.<ad> / call(\'<ad>\'))',
  (gone + ['prog2_view_date']).select { |n| all_src =~ /sketchup\.#{n}\s*\(|call\('#{n}'|sketchup\[['"]#{n}['"]\]/ }, [])
kept = ['def edit_selected_pile_v2', 'def batch_update_selected_pile_details', 'def set_selected_faces_formwork(', 'def activate_bk_formwork_face_tool',
        'def select_pile_qto_id(', 'def mst_repair_pile_type_library', 'def mst_reconcile_pile_weights!', 'def mst_repair_bk_type_library',
        'def mst_repair_precast_type_library', 'def mst_selected_bim_pile_payload']
t('K30 işlevler kalır', kept.reject { |k| main.include?(k) }, [])
t('K30 prog2_view_date Ruby yöntemi kalır', bq.include?('def prog2_view_date;'), true)
t('K30 bakım listesi / eski menü yolları kalır', [main.include?("when 'pile_edit_v2' then edit_selected_pile_v2"), main.include?("{batch_update_selected_pile_details}"),
                                                    main.include?("{mst_repair_pile_type_library}"), main.include?("{mst_reconcile_pile_weights!}")], [true, true, true, true])
t('K30 KOŞULLU / SİLİNMEMELİ kalemler duruyor', [main.include?("add_action_callback('pile_load_selected_bim')"), main.include?("add_action_callback('drilling_edit')"),
                                                main.include?("add_action_callback('universal_edit')"), main.include?("add_action_callback('boq_element_detail')"),
                                                main.include?("add_action_callback('pile_mfg_edit')")], [true, true, true, true, true])

# H5 (Ruby): kazık yükleme yükü boş deniz tabanı kotu / çakım anahtarını '' olarak gönderir (ui.html boş değeri alana yazar)
A1.load(Host, main, 'def mst_bim_pile_payload(')
g = Sketchup::Group.new(5, 'element_type' => 'steel_pipe_pile', 'pile_id' => 'P-5')
pl = Host.new.mst_bim_pile_payload(g)
t('H5 kayıtsız seabed_elevation_m / driving_length_m: anahtar var, değer ""', [pl.key?('seabed_elevation_m'), pl['seabed_elevation_m'], pl.key?('driving_length_m'), pl['driving_length_m']], [true, '', true, ''])
a1_finish
