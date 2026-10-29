# frozen_string_literal: true
module MAG
 module MarineStructuresTools
  module MaterialChange
   extend self
   TYPES=%w[head_beam flat_precast channel_precast crane_precast deck_slab curb].freeze
   def api;MarineStructuresTools;end
   def targets(model,request)
    raise 'Geçerli kapsam seçin.' unless %w[selected connected].include?(request['scope'])
    entries=ProjectWorkspace.entries(model)
    roots=ProjectWorkspace.validate_request(model,request,entries)
    raise 'Bu işlem yalnız başlık kirişi, prekast, döşeme ve bordür için kullanılabilir.' unless roots.all?{|entry|TYPES.include?(entry[:entity].get_attribute(DICT,'element_type',''))}
    chosen=roots.map{|entry|entry[:entity]}
    if request['scope']=='connected'
     # Traverse by entity identity, never merge ambiguous UIDs during traversal.
     _all,children,=api.dependency_graph(model)
     queue=chosen.dup;seen=chosen.each_with_object({}){|e,h|h[e]=true}
     until queue.empty?
      current=queue.shift
      children[current].each do |child|
       next if seen[child]
       seen[child]=true;chosen<<child;queue<<child
      end
     end
    end
    list=entries.select{|entry|chosen.include?(entry[:entity])}
    raise 'Bağlı eleman türü henüz desteklenmiyor.' unless list.all?{|entry|TYPES.include?(entry[:entity].get_attribute(DICT,'element_type',''))}
    raise 'En fazla 1000 fiziksel eleman güncellenebilir; kapsamı daraltın.' if list.size>1000
    audit=RelationshipAudit.analyze(model)[:records].each_with_object({}){|r,h|h[r[:key]]=r}
    list.each do |entry|
     e=entry[:entity]
     (entry[:path]+[e]).each do |node|
      raise "#{api.element_visible_id(e)}: kilitli eleman veya üst grup." if node.locked?
      raise "#{api.element_visible_id(e)}: paylaşılan tanım önce bağımsızlaştırılmalı." if node.definition.instances.size>1
     end
     issues=audit.fetch(entry[:key])[:checks]
     issues=issues.select{|c|%w[MISSING_UID DUPLICATE_UID].include?(c[:code])} if request['scope']=='selected'
     raise "#{api.element_visible_id(e)}: #{issues.first[:message]} Önce bağlantı/kimlik kontrolünü tamamlayın." unless issues.empty?
    end
    list
   end
   def plan(model,request)
    cls=request['concrete_class'].to_s.strip
    raise 'Geçerli beton sınıfı seçin.' unless ControlledEditor::CLASSES.include?(cls)
    list=targets(model,request)
    records=list.map do |entry|
     e=entry[:entity];before=e.get_attribute(DICT,'concrete_class','').to_s
     quantity=QuantityService.record(e,:concrete_m3)
     raise "#{api.element_visible_id(e)}: beton hacmi eksik veya geçersiz." if %w[invalid missing].include?(quantity[:state])
     {key:entry[:key],id:api.element_visible_id(e),label:ProjectWorkspace::TYPES[e.get_attribute(DICT,'element_type','')],before:before,after:cls,
      concrete_m3:quantity[:value],changed:before!=cls}
    end
    raise 'Seçilen kapsam zaten bu beton sınıfında.' unless records.any?{|r|r[:changed]}
    {entries:list,records:records,class:cls,changed_count:records.count{|r|r[:changed]},total_concrete_m3:records.sum{|r|r[:concrete_m3]},
     changed_concrete_m3:records.select{|r|r[:changed]}.sum{|r|r[:concrete_m3]}}
   end
   def apply(model,pending)
    raise 'Önizlemeden sonra model değişti; yeniden önizleyin.' unless pending[:fingerprint]==ControlledEditor.fingerprint(model)
    data=plan(model,pending[:request]);opened=false
    begin
     model.start_operation('MST Bağlı Beton Sınıfı Güncellemesi',true);opened=true
     data[:entries].each do |entry|
      e=entry[:entity];next if e.get_attribute(DICT,'concrete_class','').to_s==data[:class]
      uid=e.get_attribute(DICT,'element_uid','');id=api.element_visible_id(e);shape=api.revision_geometry_signature(e)
      e.set_attribute(DICT,'concrete_class',data[:class]);ControlledEditor.sync_type(e,model)
      e.set_attribute(DICT,'revision',VERSION)
      raise 'Eleman kimliği veya geometri beklenmedik biçimde değişti.' unless uid==e.get_attribute(DICT,'element_uid','')&&id==api.element_visible_id(e)&&shape==api.revision_geometry_signature(e)
     end
     api.commit_with_dependencies(model);opened=false
    rescue
     model.abort_operation if opened
     raise
    end
    {count:data[:changed_count],message:"#{data[:changed_count]} elemanın beton sınıfı güncellendi. Geometri ve fiziksel kimlikler korundu."}
   end
  end
  def material_change_show(raw)
   request=JSON.parse(raw);request['scope']='selected'
   roots=MaterialChange.targets(Sketchup.active_model,request)
   @material_change_dialog.close if @material_change_dialog&&@material_change_dialog.visible?
   d=UI::HtmlDialog.new(dialog_title:'MST — Bağlı Beton Sınıfı Güncellemesi',width:1050,height:760,resizable:true)
   d.set_file(File.join(__dir__,'material_change.html'));pending=nil
   init={roots:roots.map{|entry|element_visible_id(entry[:entity])},classes:ControlledEditor::CLASSES}
   d.add_action_callback('material_ready'){|_|d.execute_script("materialChangeLoaded(#{JSON.generate(init)})")}
   d.add_action_callback('material_cancel'){|_|pending=nil}
   d.add_action_callback('material_preview'){|_,raw_values|
    pending=nil
    begin
     values=JSON.parse(raw_values)
     selected=request.merge('scope'=>values['scope'],'concrete_class'=>values['concrete_class'])
     data=MaterialChange.plan(Sketchup.active_model,selected);token=SecureRandom.hex(16)
     pending={token:token,request:selected,fingerprint:ControlledEditor.fingerprint(Sketchup.active_model)}
     preview=data.reject{|k,v|k==:entries}.merge(token:token,request_id:values['request_id'])
     d.execute_script("materialChangePreview(#{JSON.generate(preview)})")
    rescue=>error;pending=nil;d.execute_script("materialChangeError(#{JSON.generate(error.message)})");end
   }
   d.add_action_callback('material_apply'){|_,token|
    saved=pending;pending=nil
    begin
     raise 'Geçerli önizleme gerekiyor.' unless saved&&saved[:token]==token
     result=MaterialChange.apply(Sketchup.active_model,saved)
     d.execute_script("materialChangeDone(#{JSON.generate(result)})");project_workspace_refresh
    rescue=>error;d.execute_script("materialChangeError(#{JSON.generate(error.message)})");end
   }
   d.set_on_closed{pending=nil};@material_change_dialog=d;d.show
  rescue=>error
   @d.execute_script("projectWorkspaceError(#{JSON.generate(error.message)})") if @d&&@d.visible?
  end
 end
end
