# frozen_string_literal: true
require_relative 'record_repair'
module MAG
 module MarineStructuresTools
  module BatchRecordRepair
   extend self
   MAX_RECORDS=100
   def resolve(model,request)
    keys=request['keys']
    raise 'Toplu tamamlama için 1–100 farklı eleman seçin; filtreyle kapsamı daraltın.' unless keys.is_a?(Array)&&!keys.empty?&&keys.size<=MAX_RECORDS&&keys.uniq==keys
    ProjectWorkspace.validate_request(model,request,ProjectWorkspace.entries(model))
   end
   def health_request(model,report,raw)
    keys=JSON.parse(raw)
    allowed=report[:records].select{|r|r[:checks].any?{|c|%w[MISSING_PROJECT MISSING_STRUCTURE].include?(c[:code])}}.map{|r|r[:key]}
    raise 'Eleman kontrolün eksik proje/yapı kayıtları kapsamında değil.' unless keys.is_a?(Array)&&keys.all?{|key|allowed.include?(key)}
    request={'model_token'=>report[:model_token],'keys'=>keys};resolve(model,request);request
   end
   def subset_request(request,keys)
    raise 'Başlangıç kapsamından 1–100 farklı eleman seçin.' unless keys.is_a?(Array)&&!keys.empty?&&keys.size<=MAX_RECORDS&&keys.uniq==keys&&keys.all?{|key|key.is_a?(String)&&request['keys'].include?(key)}
    request.merge('keys'=>keys)
   end
   def plan(model,request,values)
    entries=resolve(model,request)
    raise 'Yalnız proje/yapı önerisi girilebilir.' unless values.is_a?(Hash)&&values.keys.sort==%w[project structure]
    raise 'Proje/yapı önerileri metin olmalı.' unless values.values.all?{|value|value.is_a?(String)}
    raise 'Alanlar kontrol karakteri içermemeli.' if values.values.any?{|value|value.match?(/\p{Cc}/)}
    values=values.transform_values(&:strip)
    raise 'Alanlar en fazla 120 karakter olmalı.' if values.values.any?{|v|v.length>120}
    results=[];skipped=[]
    entries.each do |entry|
     e=entry[:entity];current=%w[project structure].each_with_object({}){|key,h|h[key]=e.get_attribute(DICT,key,'').to_s.strip}
     if current.none?{|key,value|value.empty?&&!values[key].empty?}
      skipped<<MarineStructuresTools.element_visible_id(e);next
     end
     proposed=current.dup
     current.each{|key,value|proposed[key]=value.empty? ? values[key] : value}
     result=RecordRepair.plan(model,request.merge('keys'=>[entry[:key]],'values'=>proposed.merge('fill_uid'=>false)))
     results<<result
    rescue=>error
     raise "#{MarineStructuresTools.element_visible_id(e)}: #{error.message} Hiçbir kayıt değiştirilmedi."
    end
    raise 'Bu önerilerle tamamlanacak boş kayıt yok.' if results.empty?
    {results:results,skipped:skipped,request:request,values:values,fingerprint:RecordRepair.fingerprint(model)}
   end
   def apply(model,pending)
    raise 'Önizlemeden sonra model değişti; yeniden önizleyin.' unless pending[:fingerprint]==RecordRepair.fingerprint(model)
    fresh=plan(model,pending[:request],pending[:values]);snapshots=fresh[:results].map do |result|
     e=result[:entry][:entity];{entity:e,attrs:MarineStructuresTools.mst_attr_hash(e),shape:MarineStructuresTools.revision_geometry_signature(e),values:result[:values]}
    end
    opened=false
    begin
     model.start_operation('MST Toplu Eksik Proje/Yapı Tamamlama',true);opened=true
     snapshots.each do |item|
      item[:values].each{|key,value|item[:entity].set_attribute(DICT,key,value)}
      item[:entity].set_attribute(DICT,'revision',VERSION)
     end
     snapshots.each do |item|
      e=item[:entity];after=MarineStructuresTools.mst_attr_hash(e)
      raise 'Geometri beklenmedik biçimde değişti.' unless item[:shape]==MarineStructuresTools.revision_geometry_signature(e)
      raise 'Plan dışındaki kayıt değişti.' unless (item[:attrs].keys|after.keys).all?{|key|item[:values].key?(key)||key=='revision'||item[:attrs][key]==after[key]}
     end
     model.commit_operation;opened=false
    rescue
     model.abort_operation if opened;raise
    end
    {count:snapshots.size,skipped:fresh[:skipped].size}
   end
  end
  def batch_record_repair_show(request)
   model=Sketchup.active_model;entries=BatchRecordRepair.resolve(model,request)
   @batch_repair_dialog.close if @batch_repair_dialog&&@batch_repair_dialog.visible?
   d=UI::HtmlDialog.new(dialog_title:'MST — Toplu Proje/Yapı Tamamlama',width:850,height:700,resizable:true)
   d.set_file(File.join(__dir__,'batch_record_repair.html'));pending=nil
   d.set_on_closed{pending=nil} if d.respond_to?(:set_on_closed)
   rows=entries.map do |entry|
    e=entry[:entity];{key:entry[:key],id:element_visible_id(e),label:ProjectWorkspace::TYPES[e.get_attribute(DICT,'element_type')],project:e.get_attribute(DICT,'project',''),structure:e.get_attribute(DICT,'structure','')}
   end
   d.add_action_callback('batch_ready'){|_|pending=nil;d.execute_script("batchLoaded(#{JSON.generate(rows)})")}
   d.add_action_callback('batch_locate'){|_,key|
    begin
     selected=BatchRecordRepair.subset_request(request,[key])
     ProjectWorkspace.select(Sketchup.active_model,selected.merge('zoom'=>true))
     d.execute_script("batchLocated(#{JSON.generate(key)})")
    rescue=>error;d.execute_script("batchLocationStatus(#{JSON.generate(error.message)})");end
   }
   d.add_action_callback('batch_cancel'){|_|pending=nil}
   d.add_action_callback('batch_preview'){|_,raw|
    pending=nil
    begin
     input=JSON.parse(raw);selected=BatchRecordRepair.subset_request(request,input.fetch('keys'));result=BatchRecordRepair.plan(Sketchup.active_model,selected,input.fetch('values'))
     token=SecureRandom.hex(16);pending=result.merge(token:token)
     changes=result[:results].map{|row|{id:element_visible_id(row[:entry][:entity]),changes:row[:changes]}}
     d.execute_script("batchPreview(#{JSON.generate({token:token,request_id:input['request_id'],changes:changes,skipped:result[:skipped]})})")
    rescue=>error;d.execute_script("batchError(#{JSON.generate(error.message)})");end
   }
   d.add_action_callback('batch_apply'){|_,token|
    saved=pending;pending=nil
    begin
     raise 'Geçerli bir önizleme gerekiyor.' unless saved&&saved[:token]==token
     result=BatchRecordRepair.apply(Sketchup.active_model,saved)
     d.execute_script("batchDone(#{JSON.generate(result)})");project_workspace_refresh if @d
    rescue=>error;d.execute_script("batchError(#{JSON.generate(error.message)})");end
   }
   @batch_repair_dialog=d;d.show
  rescue=>error;UI.messagebox("Toplu kayıt tamamlama açılamadı: #{error.message}");end
 end
end
