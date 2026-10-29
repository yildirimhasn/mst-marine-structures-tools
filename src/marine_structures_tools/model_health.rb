require_relative 'batch_record_repair'
require_relative 'health_freshness'
require_relative 'health_history_import'
# frozen_string_literal: true
require 'time'
require_relative 'safe_report_file'
module MAG
 module MarineStructuresTools
  module ModelHealth
   extend self
   ID_KEYS={'steel_pipe_pile'=>'pile_id','bored_pile'=>'id','head_beam'=>'head_beam_id','flat_precast'=>'precast_id','channel_precast'=>'precast_id','crane_precast'=>'precast_id','deck_slab'=>'deck_id','curb'=>'curb_id','crown_wall'=>'id'}.freeze
   PROFILE_TYPES=%w[head_beam flat_precast channel_precast].freeze
   QUANTITY_LABELS={steel_t:'Boru çeliği',concrete_m3:'Beton hacmi',formwork_m2:'Kalıp alanı',rebar_t:'Donatı'}.freeze
   def api;MarineStructuresTools;end
   def issue(list,severity,category,code,message)
    list<<{severity:severity,category:category,code:code,message:message}
   end
   def attempt(list,category,code)
    yield
   rescue StandardError=>error
    issue(list,'error',category,code,error.message)
   end
   def analyze(model,keys:nil)
    entries=ProjectWorkspace.entries(model)
    by_key=entries.each_with_object({}){|entry,h|h[entry[:key]]=entry}
    relationships=RelationshipAudit.analyze(model)[:records].each_with_object({}){|row,h|h[row[:key]]=row}
    identifiers=entries.group_by do |entry|
     e=entry[:entity];type=e.get_attribute(DICT,'element_type','')
     [type,e.get_attribute(DICT,ID_KEYS[type],'').to_s.strip]
    end
    if keys
     raise 'Kontrol kapsamı boş veya geçersiz.' unless keys.is_a?(Array)&&!keys.empty?&&keys.uniq==keys&&keys.all?{|key|by_key.key?(key)}
    end
    selected_keys=keys&&keys.each_with_object({}){|key,h|h[key]=true}
    records=(keys ? entries.select{|entry|selected_keys[entry[:key]]} : entries).map do |entry|
     e=entry[:entity];type=e.get_attribute(DICT,'element_type','');checks=[];geometry='not_checked'
     relation=relationships.fetch(entry[:key])
     relation[:checks].each{|c|issue(checks,'error',c[:code].include?('UID') ? 'identity' : 'relationship',c[:code],c[:message])}
     id=e.get_attribute(DICT,ID_KEYS[type],'').to_s.strip
     issue(checks,'error','identity','MISSING_ID','Görünür eleman kimliği eksik.') if id.empty?
     issue(checks,'error','identity','DUPLICATE_ID','Aynı eleman türünde görünür kimlik birden fazla yerleşimde kullanılıyor.') if !id.empty?&&identifiers[[type,id]].size>1
     %w[project structure library_type_id].each do |key|
      issue(checks,'warning','metadata',"MISSING_#{key.upcase}","#{ProjectWorkspace::FIELDS[key]} kaydı eksik.") if e.get_attribute(DICT,key,'').to_s.strip.empty?
     end
     material_key=type=='steel_pipe_pile' ? 'steel_grade' : 'concrete_class'
     issue(checks,'warning','metadata','MISSING_MATERIAL_CLASS','Malzeme sınıfı kaydı eksik.') if e.get_attribute(DICT,material_key,'').to_s.strip.empty?
     if type=='steel_pipe_pile'
      attempt(checks,'geometry','PILE_DIMENSIONS') do
       d=QuantityService.number(e.get_attribute(DICT,'diameter_mm',nil),'Kazık çapı')
       t=QuantityService.number(e.get_attribute(DICT,'thickness_mm',nil),'Et kalınlığı')
       l=QuantityService.number(e.get_attribute(DICT,'actual_length_m',e.get_attribute(DICT,'length_m',nil)),'Kazık boyu')
       raise 'Kazık çapı/boyu/et kalınlığı pozitif ve et kalınlığı çapın yarısından küçük olmalı.' unless d>0&&l>0&&t>0&&2*t<d
      end
     elsif PROFILE_TYPES.include?(type)
      attempt(checks,'geometry','PROFILE_GEOMETRY') do
       raise 'Bu kesit kontrolü yalnız grup geometrisini destekler.' unless e.is_a?(Sketchup::Group)
       ElevationSync.placement(entry)
       if type=='head_beam'
        HeadBeamEditor.validate_geometry(e,api.mst_attr_hash(e))
       else
        ControlledEditor.validate_geometry(e,type)
       end
       geometry='profile_checked'
      end
      attempt(checks,'geometry','ELEVATION_MISMATCH'){ElevationSync.placement(entry);ElevationSync.verify_levels(entry)}
     end
     if geometry=='not_checked'
      issue(checks,'info','geometry','GEOMETRY_NOT_CHECKED','Bu yerleşimin fiziksel kesit/katı geometrisi doğrulanmadı; rapor geometri uygunluğu onayı değildir.')
     end
     quantities={}
     quantity_keys=type=='steel_pipe_pile' ? [:steel_t] : type=='bored_pile' ? [:concrete_m3,:rebar_t] : [:concrete_m3,:formwork_m2,:rebar_t]
     quantity_keys.each do |key|
      attempt(checks,'quantity',"QUANTITY_CHECK_FAILED_#{key.to_s.upcase}") do
       r=QuantityService.record(e,key);quantities[key]=r
       label=QUANTITY_LABELS.fetch(key)
       if %w[missing invalid].include?(r[:state])
        issue(checks,'error','quantity',"#{r[:state].upcase}_#{key.to_s.upcase}","#{label}: metraj kaydı #{r[:state]=='missing' ? 'eksik' : 'geçersiz'}.")
       elsif r[:state]=='estimated'
        issue(checks,'info','quantity',"ESTIMATED_#{key.to_s.upcase}","#{label}: yaklaşık oran hesabıdır; detay donatı/metraj onayı değildir.")
       elsif [:concrete_m3,:steel_t].include?(key)&&r[:value]==0
        issue(checks,'warning','quantity',"ZERO_#{key.to_s.upcase}","#{label}: miktar sıfır; kayıt ve kapsamı inceleyin.")
       end
      end
     end
     if geometry=='profile_checked'&&quantities[:concrete_m3]&&quantities[:concrete_m3][:value]
      attempt(checks,'quantity','SOLID_VOLUME_MISMATCH') do
       stored=quantities[:concrete_m3][:value];actual=e.volume.to_f/(api.m(1).to_f**3)
       raise 'Kayıtlı beton hacmi katı geometrisinin hacmiyle uyuşmuyor.' unless actual.finite?&&(actual-stored).abs<=[1e-6,actual.abs*1e-6].max
      end
     end
     if geometry=='profile_checked'
      attempt(checks,'quantity','FORMWORK_FACE_MISMATCH') do
       faces=e.entities.grep(Sketchup::Face)
       raise 'Yüzlerin kalıp seçimleri eksik veya geçersiz.' unless faces.all?{|f|[true,false].include?(f.get_attribute(DICT,'formwork',nil))}
       actual=faces.sum{|f|f.get_attribute(DICT,'formwork',false) ? f.area.to_f/(api.m(1).to_f**2) : 0.0}
       raise 'Yüz kalıp alanı geçersiz.' unless actual.finite?&&actual>=0
       stored=QuantityService.number(e.get_attribute(DICT,'formwork_area_m2',nil),'Kayıtlı brüt kalıp')
       raise 'Kayıtlı kalıp alanı, seçili yüzlerin alanıyla uyuşmuyor.' unless (actual-stored).abs<=[1e-6,actual*1e-6].max
      end
     end
     if type=='head_beam'&&relation[:checks].empty?&&!relation[:supports].empty?
      attempt(checks,'quantity','PILE_OPENING_MISMATCH') do
       actual=relation[:supports].sum do |support|
        pile=by_key.fetch(support[:key])[:entity]
        diameter=QuantityService.number(pile.get_attribute(DICT,'diameter_mm',nil),'Mesnet kazık çapı')/1000.0
        raise 'Mesnet kazık çapı sıfırdan büyük olmalı.' unless diameter>0
        Math::PI*diameter**2/4
       end
       stored=QuantityService.number(e.get_attribute(DICT,'pile_opening_area_m2',nil),'Kayıtlı kazık açıklığı')
       raise 'Kayıtlı kazık açıklığı mevcut mesnet kazıklarının çaplarıyla uyuşmuyor.' unless (actual-stored).abs<=1e-6
      end
     end
     severity=checks.any?{|c|c[:severity]=='error'} ? 'error' : checks.any?{|c|c[:severity]=='warning'} ? 'warning' : geometry=='not_checked' ? 'limited' : 'checked'
     {key:entry[:key],id:api.element_visible_id(e),label:ProjectWorkspace::TYPES[type],uid:e.get_attribute(DICT,'element_uid','').to_s.strip,type:type,state:severity,geometry:geometry,checks:checks,quantities:quantities}
    end
    result={schema:'mst.model-health/1',version:VERSION,created_at:Time.now.utc.iso8601,model_token:model.object_id.to_s,
     summary:{elements:records.size,errors:records.count{|r|r[:state]=='error'},warnings:records.count{|r|r[:state]=='warning'},limited:records.count{|r|r[:state]=='limited'},checked:records.count{|r|r[:state]=='checked'},geometry_unchecked:records.count{|r|r[:geometry]=='not_checked'}},records:records,
     limitation:'Proje ağacındaki ana yapı elemanları denetlenir. Dolgu/Taş, kazık içi beton, fiziksel kaplama ve aksesuarların ayrı kontrolleri bu raporun kapsamı dışındadır. Çakışma, mesnet teması, taşıma kapasitesi, tasarım/mevzuat veya teslim uygunluğu onayı verilmez. Tahmini donatı miktarları ayrı işaretlenir.'}
    if keys
     result[:scope]={kind:'selected',selected:records.size,model_elements:entries.size,keys:keys}
     result[:limitation]="SEÇİLİ KAPSAM: #{records.size} / #{entries.size} eleman raporlanır; tüm model kontrolü değildir. Kimlik ve bağlantı kontrollerinde kapsam dışındaki elemanlar da bağlam olarak dikkate alınır. "+result[:limitation]
    end
    result
   end
  end
  def model_health_show
   data=ModelHealth.analyze(Sketchup.active_model)
   @model_health_dialog.close if @model_health_dialog&&@model_health_dialog.visible?
   d=UI::HtmlDialog.new(dialog_title:'MST — Model Sağlığı',width:1080,height:760,resizable:true)
   d.set_file(File.join(__dir__,'model_health.html'))
   watch=HealthFreshness.new(d);watch.capture(data);d.set_on_closed{watch.close} if d.respond_to?(:set_on_closed)
   d.add_action_callback('health_ready'){|_|watch.publish(data)}
   d.add_action_callback('health_refresh'){|_|
    begin
     data=ModelHealth.analyze(Sketchup.active_model);watch.publish(data)
    rescue=>error;d.execute_script("modelHealthError(#{JSON.generate(error.message)})");end
   }
   d.add_action_callback('health_select'){|_,key|
    begin
     ProjectWorkspace.select(Sketchup.active_model,{'model_token'=>data[:model_token],'keys'=>[key],'zoom'=>true})
    rescue=>error;d.execute_script("modelHealthError(#{JSON.generate(error.message)})");end
   }
   d.add_action_callback('health_repair'){|_,key|record_repair_show(JSON.generate({'model_token'=>data[:model_token],'keys'=>[key]}))}
   d.add_action_callback('health_batch_repair'){|_,raw|
    begin
     request=BatchRecordRepair.health_request(Sketchup.active_model,data,raw)
     batch_record_repair_show(request)
    rescue=>error;d.execute_script("modelHealthError(#{JSON.generate(error.message)})");end
   }
   d.add_action_callback('health_report'){|_|
    begin
     revision=watch.revision
     fresh=HealthReport.export(Sketchup.active_model)
     if fresh
      data=fresh;watch.publish(data,revision:revision);d.execute_script("modelHealthError(#{JSON.generate('HTML kontrol raporu kaydedildi.')})")
     end
    rescue=>error;d.execute_script("modelHealthError(#{JSON.generate(error.message)})");end
   }
   d.add_action_callback('history_list'){|_|
    begin
     raise 'Aktif model değişti; raporu yenileyin.' unless data[:model_token]==Sketchup.active_model.object_id.to_s
     d.execute_script("healthHistoryLoaded(#{JSON.generate(HealthHistory.list(Sketchup.active_model))})")
    rescue=>error;d.execute_script("healthHistoryError(#{JSON.generate(error.message)})");end
   }
   d.add_action_callback('history_save'){|_,label|
    begin
     raise 'Aktif model değişti; raporu yenileyin.' unless data[:model_token]==Sketchup.active_model.object_id.to_s
     item=HealthHistory.save(Sketchup.active_model,label);data=item[:report]
     watch.publish(data);d.execute_script("healthHistoryError(#{JSON.generate('Kontrol model içinde kaydedildi. Kalıcı olması için SketchUp dosyasını da kaydedin.')})")
    rescue=>error;d.execute_script("healthHistoryError(#{JSON.generate(error.message)})");end
   }
   d.add_action_callback('history_report'){|_,number|
    begin
     raise 'Aktif model değişti; raporu yenileyin.' unless data[:model_token]==Sketchup.active_model.object_id.to_s
     exported=HealthHistory.export_baseline(Sketchup.active_model,number)
     message=exported ? 'Seçili eski kontrol HTML olarak kaydedildi; güncel model raporu değiştirilmedi.' : 'Kaydetme iptal edildi.'
     d.execute_script("healthHistoryError(#{JSON.generate(message)})")
    rescue=>error;d.execute_script("healthHistoryError(#{JSON.generate(error.message)})");end
   }
   d.add_action_callback('history_archive'){|_|
    begin
     raise 'Aktif model değişti; raporu yenileyin.' unless data[:model_token]==Sketchup.active_model.object_id.to_s
     exported=HealthHistory.export_archive(Sketchup.active_model)
     message=exported ? "#{exported[:count]} kontrol JSON arşivine kaydedildi. Model içindeki kayıtlar korundu." : 'Kaydetme iptal edildi.'
     d.execute_script("healthHistoryError(#{JSON.generate(message)})")
    rescue=>error;d.execute_script("healthHistoryError(#{JSON.generate(error.message)})");end
   }
   d.add_action_callback('history_rename'){|_,number,label|
    begin
     raise 'Aktif model değişti; raporu yenileyin.' unless data[:model_token]==Sketchup.active_model.object_id.to_s
     HealthHistory.rename(Sketchup.active_model,number,label)
     d.execute_script("healthHistoryLoaded(#{JSON.generate(HealthHistory.list(Sketchup.active_model))})")
     d.execute_script("healthHistoryError(#{JSON.generate('Kontrol adı güncellendi. Kalıcılık için model dosyasını kaydedin.')})")
    rescue=>error;d.execute_script("healthHistoryError(#{JSON.generate(error.message)})");end
   }
   d.add_action_callback('history_delete'){|_,number|
    begin
     model=Sketchup.active_model
     raise 'Aktif model değişti; raporu yenileyin.' unless data[:model_token]==model.object_id.to_s
     item=HealthHistory.list(model).find{|s|s[:number].to_s==number.to_s}
     raise 'Silmek için kayıt seçin.' unless item
     previous=model.get_attribute(HealthHistory::DICTIONARY,HealthHistory::KEY,nil)
     if UI.messagebox("Kayıtlı kontrol ##{item[:number]} — #{item[:label]} silinsin mi?\nİsterseniz önce tüm geçmişi JSON olarak arşivleyin. Silme SketchUp Geri Al ile geri alınabilir.",MB_YESNO)==IDYES
      raise 'Aktif model değişti; raporu yenileyin.' unless Sketchup.active_model.equal?(model)
      raise 'Kontrol geçmişi değişti; listeyi yenileyip tekrar deneyin.' unless previous==model.get_attribute(HealthHistory::DICTIONARY,HealthHistory::KEY,nil)
      HealthHistory.delete(model,number)
      d.execute_script("healthHistoryLoaded(#{JSON.generate(HealthHistory.list(model))})")
      d.execute_script("healthHistoryError(#{JSON.generate('Seçili kontrol silindi. Kalıcılık için model dosyasını kaydedin.')})")
     else
      d.execute_script("healthHistoryError(#{JSON.generate('Silme iptal edildi.')})")
     end
    rescue=>error;d.execute_script("healthHistoryError(#{JSON.generate(error.message)})");end
   }
   import_plan=nil
   d.add_action_callback('history_import_preview'){|_|
    begin
     import_plan=nil
     model=Sketchup.active_model
     raise 'Aktif model değişti; raporu yenileyin.' unless data[:model_token]==model.object_id.to_s
     path=UI.openpanel('Kontrol Geçmişi Arşivi Seç','','JSON|*.json||')
     if path
      raise 'Aktif model değişti; raporu yenileyin.' unless Sketchup.active_model.equal?(model)
      import_plan=HealthHistoryImport.preview(model,path)
      d.execute_script("healthHistoryImportPreview(#{JSON.generate(HealthHistoryImport.view(import_plan))})")
     else
      d.execute_script("healthHistoryError(#{JSON.generate('Dosya seçimi iptal edildi.')})")
     end
    rescue=>error;d.execute_script("healthHistoryError(#{JSON.generate(error.message)})");end
   }
   d.add_action_callback('history_import_apply'){|_,token,selection|
    begin
     plan=import_plan;import_plan=nil
     result=HealthHistoryImport.apply(Sketchup.active_model,plan,token,JSON.parse(selection))
     d.execute_script("healthHistoryLoaded(#{JSON.generate(HealthHistory.list(Sketchup.active_model))})")
     d.execute_script("healthHistoryError(#{JSON.generate("#{result[:count]} kayıt içe aktarıldı. Model dosyasını kaydedin.")})")
    rescue=>error;d.execute_script("healthHistoryError(#{JSON.generate(error.message)})");end
   }
   d.add_action_callback('history_compare'){|_,number|
    begin
     raise 'Aktif model değişti; raporu yenileyin.' unless data[:model_token]==Sketchup.active_model.object_id.to_s
     d.execute_script("healthHistoryCompared(#{JSON.generate(HealthHistory.compare(Sketchup.active_model,number))})")
    rescue=>error;d.execute_script("healthHistoryError(#{JSON.generate(error.message)})");end
   }
   d.add_action_callback('health_export'){|_|
    begin
     fresh=ModelHealth.analyze(Sketchup.active_model)
     revision=watch.revision
     path=UI.savepanel('Model Sağlığı Raporunu Kaydet','','MST_Model_Sagligi.json')
     if path
      path+='.json' unless path.downcase.end_with?('.json')
      SafeReportFile.write(path,JSON.pretty_generate(fresh))
      data=fresh;watch.publish(data,revision:revision);d.execute_script("modelHealthError(#{JSON.generate('Kontrol anının raporu kaydedildi.')})")
     end
    rescue=>error;d.execute_script("modelHealthError(#{JSON.generate(error.message)})");end
   }
   @model_health_dialog=d;d.show
  rescue=>error;UI.messagebox("Model sağlığı kontrolü açılamadı: #{error.message}");end
 end
end
