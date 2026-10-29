# frozen_string_literal: true
require 'securerandom'
module MAG
 module MarineStructuresTools
  module RecordRepair
   extend self
   RELATIONS=%w[parent_uid parent_deck_id support_uids support_left_uid support_right_uid support_pids support_left_pid support_right_pid connected_pile_ids pile_ids].freeze
   def api;MarineStructuresTools;end
   def resolve(model,request)
    entries=ProjectWorkspace.validate_request(model,request,ProjectWorkspace.entries(model))
    raise 'Tek eleman seçin.' unless entries.size==1
    entry=entries.first;e=entry[:entity]
    raise 'Bu akış yalnız özgün grupları destekler.' unless e.is_a?(Sketchup::Group)
    (entry[:path]+[e]).each do |node|
     raise 'Kilitli veya paylaşılan yerleşim önce bağımsızlaştırılmalı.' if node.locked?||node.definition.instances.size!=1
    end
    raise 'İç grup/bileşen kayıtları birlikte ele alınmalı; bu akış durduruldu.' if e.entities.any?{|part|part.is_a?(Sketchup::Group)||part.is_a?(Sketchup::ComponentInstance)}
    all=ElevationSync.instances(model)
    uid=e.get_attribute(DICT,'element_uid','').to_s.strip
    raise 'Tekrarlanmış UID onarımı ayrı bir bağlantı eşleştirme akışı gerektirir.' if !uid.empty?&&all.count{|r|r[:entity].get_attribute(DICT,'element_uid','').to_s.strip==uid}>1
    [entry,all]
   end
   def references(e)
    RELATIONS.flat_map{|key|RelationshipAudit.tokens(e.get_attribute(DICT,key,'')).reject{|value|value=='0'}}
   end
   def related(entry,all)
    e=entry[:entity];keys=[e.persistent_id.to_s,api.element_visible_id(e).to_s,e.get_attribute(DICT,'element_uid','').to_s].map(&:strip).reject(&:empty?)
    own=references(e)
    all.reject{|r|r[:entity]==e}.select do |r|
     other=r[:entity];identifiers=[other.persistent_id.to_s,api.element_visible_id(other).to_s,other.get_attribute(DICT,'element_uid','').to_s].map(&:strip).reject(&:empty?)
     !(references(other)&keys).empty?||!(own&identifiers).empty?
    end
   end
   def fingerprint(model)
    all=ElevationSync.instances(model).map do |entry|
     e=entry[:entity]
     [entry[:key],api.mst_attr_hash(e).sort_by{|k,v|k},e.locked?,e.definition.instances.size]
    end
    api.revision_digest([ControlledEditor.fingerprint(model),all])
   end
   def plan(model,request,proposed_uid:nil)
    entry,all=resolve(model,request);e=entry[:entity];raw=request['values']
    raise 'Kayıt alanları geçersiz.' unless raw.is_a?(Hash)&&raw.keys.sort==%w[fill_uid project structure].sort&&[true,false].include?(raw['fill_uid'])
    neighbors=related(entry,all);values={};changes=[]
    %w[project structure].each do |key|
     value=raw[key].to_s.strip
     raise 'Proje/yapı kaydı en fazla 120 karakter olmalı ve kontrol karakteri içermemeli.' if value.length>120||value.match?(/\p{Cc}/)
     current=e.get_attribute(DICT,key,'').to_s.strip
     raise 'Dolu proje/yapı kaydı bu tamamlama akışından değiştirilemez.' if !current.empty?&&value!=current
     next if !current.empty?||value.empty?
     related_values=(entry[:path]+neighbors.map{|r|r[:entity]}).map do |other|
      v=other.get_attribute(DICT,key,'').to_s.strip
      v=other.get_attribute(DICT,'ano','').to_s.strip if key=='structure'&&v.empty?
      v
     end.reject(&:empty?).uniq
     raise 'Girilen proje/yapı kaydı üst grup veya bağlı elemanlarla uyuşmuyor.' unless related_values.all?{|v|v==value}
     values[key]=value;changes<<{label:ProjectWorkspace::FIELDS[key],before:'',after:value}
    end
    if raw['fill_uid']
     raise 'Dolu UID değiştirilmez.' unless e.get_attribute(DICT,'element_uid','').to_s.strip.empty?
     raise 'UID yalnız bağlantısız çelik boru kazıkta tamamlanabilir.' unless e.get_attribute(DICT,'element_type')=='steel_pipe_pile'&&neighbors.empty?&&references(e).empty?
     id=e.get_attribute(DICT,'pile_id','').to_s.strip
     raise 'Yeni UID için mevcut görünür kazık kimliği gerekli.' if id.empty?
     raise 'Görünür kazık kimliği başka yerleşimde de kullanılıyor.' unless all.count{|r|r[:entity].get_attribute(DICT,'element_type')=='steel_pipe_pile'&&r[:entity].get_attribute(DICT,'pile_id','').to_s.strip==id}==1
     uid=proposed_uid||SecureRandom.uuid
     raise 'Önerilen UID geçersiz veya kullanılıyor.' unless uid.match?(/\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/)&&all.none?{|r|r[:entity].get_attribute(DICT,'element_uid','').to_s.strip==uid}
     values['element_uid']=uid;changes<<{label:'Eleman UID',before:'',after:uid}
    end
    raise 'Tamamlanacak kayıt bulunamadı.' if changes.empty?
    {entry:entry,values:values,changes:changes,neighbors:neighbors.size}
   end
   def apply(model,pending)
    raise 'Önizlemeden sonra model değişti; yeniden önizleyin.' unless pending[:fingerprint]==fingerprint(model)
    result=plan(model,pending[:request],proposed_uid:pending[:uid]);e=result[:entry][:entity];opened=false
    before=api.mst_attr_hash(e);shape=api.revision_geometry_signature(e)
    begin
     model.start_operation('MST Eksik Kayıtları Tamamlama',true);opened=true
     result[:values].each{|key,value|e.set_attribute(DICT,key,value)}
     e.set_attribute(DICT,'revision',VERSION)
     raise 'Geometri beklenmedik biçimde değişti.' unless shape==api.revision_geometry_signature(e)
     after=api.mst_attr_hash(e)
     raise 'Plan dışındaki eleman kayıtları değişti.' unless (before.keys|after.keys).all?{|key|result[:values].key?(key)||key=='revision'||before[key]==after[key]}
     # Organization/UID completion does not create, move, or rewrite relationships.
     model.commit_operation;opened=false
    rescue
     model.abort_operation if opened;raise
    end
    {message:'Eksik kayıtlar tamamlandı. Geometri, görünür kimlik, tip ve bağlantı kayıtları korundu. Model Sağlığı raporunu yenileyin.'}
   end
  end
  def record_repair_show(raw)
   request=JSON.parse(raw);entry,all=RecordRepair.resolve(Sketchup.active_model,request);e=entry[:entity]
   @record_repair_dialog.close if @record_repair_dialog&&@record_repair_dialog.visible?
   d=UI::HtmlDialog.new(dialog_title:'MST — Eksik Kayıtları Tamamla',width:800,height:640,resizable:true)
   d.set_file(File.join(__dir__,'record_repair.html'));pending=nil
   data={id:element_visible_id(e),project:e.get_attribute(DICT,'project',''),structure:e.get_attribute(DICT,'structure',''),uid_missing:e.get_attribute(DICT,'element_uid','').to_s.strip.empty?}
   d.add_action_callback('repair_ready'){|_|d.execute_script("recordRepairLoaded(#{JSON.generate(data)})")}
   d.add_action_callback('repair_cancel'){|_|pending=nil}
   d.add_action_callback('repair_preview'){|_,payload|
    pending=nil
    begin
     input=JSON.parse(payload);combined=request.merge('values'=>input.fetch('values'));model=Sketchup.active_model;result=RecordRepair.plan(model,combined)
     token=SecureRandom.hex(16);pending={token:token,request:combined,fingerprint:RecordRepair.fingerprint(model),uid:result[:values]['element_uid']}
     d.execute_script("recordRepairPreview(#{JSON.generate({token:token,request_id:input['request_id'],changes:result[:changes],neighbors:result[:neighbors]})})")
    rescue=>error;d.execute_script("recordRepairError(#{JSON.generate(error.message)})");end
   }
   d.add_action_callback('repair_apply'){|_,payload|
    saved=pending;pending=nil
    begin
     raise 'Geçerli bir önizleme gerekiyor.' unless saved&&saved[:token]==JSON.parse(payload)['token']
     result=RecordRepair.apply(Sketchup.active_model,saved);d.execute_script("recordRepairDone(#{JSON.generate(result)})")
     project_workspace_refresh if @d
    rescue=>error;d.execute_script("recordRepairError(#{JSON.generate(error.message)})");end
   }
   @record_repair_dialog=d;d.show
  rescue=>error;UI.messagebox("Kayıt tamamlama açılamadı: #{error.message}");end
 end
end
