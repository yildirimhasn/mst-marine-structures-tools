# frozen_string_literal: true
module MAG
 module MarineStructuresTools
  module ProjectWorkspace
   extend self
   TYPES={'steel_pipe_pile'=>'Çelik boru kazık','head_beam'=>'Başlık kirişi','flat_precast'=>'Normal prekast','channel_precast'=>'Kanal prekastı','crane_precast'=>'Vinç prekastı','deck_slab'=>'Döşeme','curb'=>'Bordür / tretuvar','crown_wall'=>'Kronman','bored_pile'=>'Fore kazık'}.freeze
   FIELDS={'project'=>'Proje','system'=>'Sistem','structure'=>'Yapı','axis'=>'Aks','library_type_id'=>'Tip kimliği','concrete_class'=>'Beton sınıfı','steel_grade'=>'Çelik kalitesi','diameter_mm'=>'Çap (mm)','thickness_mm'=>'Et kalınlığı (mm)','length_m'=>'Boy (m)','width_m'=>'Genişlik (m)','height_m'=>'Yükseklik (m)'}.freeze
   def api;MarineStructuresTools;end
   def entries(model)
    result=[];walk=nil
    walk=lambda do |entities,path|
     entities.each do |e|
      next unless e.is_a?(Sketchup::Group)||e.is_a?(Sketchup::ComponentInstance)
      next unless e.valid?
      type=e.get_attribute(DICT,'element_type','').to_s
      if TYPES.key?(type)
       result<<{entity:e,path:path.dup,key:JSON.generate(path.map(&:persistent_id)+[e.persistent_id])}
      elsif !%w[pile_infill_concrete deck_topping].include?(type)
       children=e.is_a?(Sketchup::Group) ? e.entities : e.definition.entities
       walk.call(children,path+[e])
      end
     end
    end
    walk.call(model.entities,[])
    result
   end
   def quantity(e,key)
    if e.get_attribute(DICT,'element_type','')=='steel_pipe_pile'
     if key==:concrete_m3
      return {value:api.pile_qto_concrete(e),state:api.pile_qto_infill_children(e).empty? ? 'estimated' : 'calculated',unit:'m³'}
     elsif key==:rebar_t
      children=api.pile_qto_infill_children(e)
      return {value:children.sum{|c|QuantityService.value(c,:rebar_t)},state:'estimated',unit:'t'} unless children.empty?
     end
    elsif key==:steel_t
     return {value:0.0,state:'not_applicable',unit:'t'}
    end
    QuantityService.record(e,key)
   rescue=>error
    {value:nil,state:'invalid',message:error.message,unit:QuantityService::UNITS[key]}
   end
   def row(entry)
    e=entry[:entity];type=e.get_attribute(DICT,'element_type','').to_s
    fields=FIELDS.keys.each_with_object({}){|key,h|h[key]=e.get_attribute(DICT,key,nil)}
    fields['structure']=e.get_attribute(DICT,'ano',nil) if fields['structure'].to_s.strip.empty?
    fields['library_type_id']=e.get_attribute(DICT,'type_id',nil) if fields['library_type_id'].to_s.strip.empty?
    fields['length_m']=e.get_attribute(DICT,'actual_length_m',fields['length_m']) if type=='steel_pipe_pile'
    fields['concrete_class']=api.pile_report_concrete_class(e) if type=='steel_pipe_pile'
    quantities=%i[concrete_m3 steel_t rebar_t formwork_m2].each_with_object({}){|key,h|h[key]=quantity(e,key)}
    uid=e.get_attribute(DICT,'element_uid','').to_s
    issues=[]
    issues<<'Eleman kimliği eksik.' if uid.empty?
    issues<<'Proje atanmamış.' if fields['project'].to_s.strip.empty?
    issues<<'Tip kimliği eksik.' if fields['library_type_id'].to_s.strip.empty?
    quantities.each{|key,r|issues<<"#{key}: #{r[:message]}" if r[:state]=='invalid'}
    {key:entry[:key],pid:e.persistent_id,uid:uid,id:api.element_visible_id(e),type:type,label:TYPES[type],
     fields:fields,quantities:quantities,issues:issues,nested:!entry[:path].empty?}
   end
   def selected_entries(model,list)
    context=Array(model.active_path).map(&:persistent_id)
    selected=model.selection.to_a.map(&:persistent_id)
    list.select do |entry|
     chain=entry[:path].map(&:persistent_id)+[entry[:entity].persistent_id]
     chain[0,context.size]==context && selected.include?(chain[context.size])
    end
   end
   def quantity_summary(values,unit)
    counts={calculated:0,estimated:0,missing:0,invalid:0,not_applicable:0};sums={calculated:0.0,estimated:0.0}
    values.each do |quantity|
     state=quantity.is_a?(Hash) ? quantity[:state] : 'missing'
     state='invalid' unless state.is_a?(String)&&counts.key?(state.to_sym)
     if %w[calculated estimated not_applicable].include?(state)
      value=quantity[:value]
      state='invalid' unless value.is_a?(Numeric)&&value.finite?&&value>=0&&(state!='not_applicable'||value==0)
     end
     counts[state.to_sym]+=1
     sums[state.to_sym]+=quantity[:value] if %w[calculated estimated].include?(state)
    end
    total=sums.values.sum;overflow=!total.finite?
    incomplete=counts[:missing]>0||counts[:invalid]>0||overflow
    {value:incomplete ? nil : total,unit:unit,incomplete:incomplete,estimated:counts[:estimated]>0,counts:counts,
     calculated_value:sums[:calculated].finite? ? sums[:calculated] : nil,estimated_value:sums[:estimated].finite? ? sums[:estimated] : nil,overflow:overflow}
   end
   def properties(rows)
    common=FIELDS.map do |key,label|
     values=rows.map{|r|r[:fields][key]}
     mixed=!values.empty? && !values.all?{|v|v==values.first}
     {key:key,label:label,value:mixed ? nil : values.first,mixed:mixed}
    end
    totals=%i[concrete_m3 steel_t rebar_t formwork_m2].each_with_object({}) do |key,h|
     values=rows.map{|r|r[:quantities][key]}
     h[key]=quantity_summary(values,QuantityService::UNITS[key])
    end
    {count:rows.size,keys:rows.map{|r|r[:key]},common:common,totals:totals,issues:rows.flat_map{|r|r[:issues]}.uniq}
   end
   def payload(model,list=entries(model))
    rows=list.map{|entry|row(entry)}
    duplicates=rows.reject{|r|r[:uid].empty?}.group_by{|r|r[:uid]}.select{|uid,records|records.size>1}
    duplicates.each_value{|records|records.each{|r|r[:issues]<<'Kimlik başka bir fiziksel örnekte de kullanılıyor; kimlik kontrolü gerekli.'}}
    index=rows.each_with_object({}){|r,h|h[r[:key]]=r}
    chosen=selected_entries(model,list).map{|entry|index.fetch(entry[:key])}
    {model_token:model.object_id.to_s,version:VERSION,records:rows,selection:properties(chosen),duplicate_uid_count:duplicates.size}
   end
   def validate_request(model,request,list)
    raise 'Aktif model değişti. Çalışma alanını yenileyin.' unless request['model_token']==model.object_id.to_s
    keys=request['keys']
    raise 'Geçerli bir eleman seçin.' unless keys.is_a?(Array)&&!keys.empty?&&keys.size<=10000
    index=list.each_with_object({}){|entry,h|h[entry[:key]]=entry}
    raise 'Seçilen eleman silinmiş veya taşınmış. Çalışma alanını yenileyin.' unless keys.all?{|key|index.key?(key)}
    keys.uniq.map{|key|index.fetch(key)}
   end
   def select(model,request,list=entries(model))
    targets=validate_request(model,request,list)
    contexts=targets.map{|e|e[:path].map(&:persistent_id)}.uniq
    raise 'Bu kapsam farklı grup/bileşenlerin içinde. Kesin seçim için tek eleman veya aynı grup içindeki bir kapsamı seçin.' unless contexts.size==1
    path=targets.first[:path]
    unless Array(model.active_path)==path
     raise 'Bu SketchUp sürümünde iç grup seçimi desteklenmiyor.' unless model.respond_to?(:active_path=)
     model.active_path=path.empty? ? nil : path
    end
    model.selection.clear
    targets.each{|entry|model.selection.add(entry[:entity])}
    raise 'Eleman seçilemedi; görünürlük ve kilit durumunu kontrol edin.' unless targets.all?{|entry|model.selection.include?(entry[:entity])}
    model.active_view.zoom(model.selection) if request['zoom']
    targets
   end
  end
  def project_workspace_refresh(dialog=@d)
  mst_read_batch do   # v0.51.5 P2: salt okuma, tek model taraması
   return unless dialog&&dialog.visible?
   project_workspace_attach(Sketchup.active_model)
   @workspace_entries=ProjectWorkspace.entries(Sketchup.active_model)
   data=ProjectWorkspace.payload(Sketchup.active_model,@workspace_entries)
   @workspace_rows=data[:records].each_with_object({}){|r,h|h[r[:key]]=r}
   dialog.execute_script("projectWorkspaceLoaded(#{JSON.generate(data)})")
  end # mst_read_batch
  rescue=>error
   dialog.execute_script("projectWorkspaceError(#{JSON.generate(error.message)},true)") if dialog
  end
  def project_workspace_selection(dialog=@d)
   return unless dialog&&dialog.visible?
   return project_workspace_refresh(dialog) unless @workspace_entries&&@workspace_rows&&@workspace_model==Sketchup.active_model
   selected=ProjectWorkspace.selected_entries(Sketchup.active_model,@workspace_entries).map{|entry|@workspace_rows.fetch(entry[:key])}
   dialog.execute_script("projectWorkspaceSelection(#{JSON.generate(ProjectWorkspace.properties(selected))},#{JSON.generate(Sketchup.active_model.object_id.to_s)})")
  rescue=>error
   dialog.execute_script("projectWorkspaceError(#{JSON.generate(error.message)},true)") if dialog
  end
  def project_workspace_action(raw,dialog=@d)
   request=JSON.parse(raw)
   raise 'Düzenlemek için yalnız bir eleman seçin.' if request['edit'] && (!request['keys'].is_a?(Array)||request['keys'].uniq.size!=1)
   targets=ProjectWorkspace.validate_request(Sketchup.active_model,request,ProjectWorkspace.entries(Sketchup.active_model))
   if request['edit'] && !(['steel_pipe_pile']+ControlledEditor::FIELDS.keys).include?(targets.first[:entity].get_attribute(DICT,'element_type',''))
    raise 'Bu eleman türü için kontrollü düzenleme henüz hazır değil.'
   end
   ProjectWorkspace.select(Sketchup.active_model,request)
   if request['edit']
    if targets.first[:entity].get_attribute(DICT,'element_type','')=='steel_pipe_pile'
     dialog.execute_script('projectWorkspaceOpenPileEditor()')
    else
     controlled_editor_open(request,dialog)
    end
   end
   project_workspace_selection(dialog)
  rescue=>error
   dialog.execute_script("projectWorkspaceError(#{JSON.generate(error.message)})") if dialog
  end
  class WorkspaceSelectionObserver < Sketchup::SelectionObserver
   def onSelectionBulkChange(selection);MarineStructuresTools.project_workspace_schedule(false);end
   def onSelectionCleared(selection);MarineStructuresTools.project_workspace_schedule(false);end
  end
  class WorkspaceModelObserver < Sketchup::ModelObserver
   def onTransactionCommit(model);MarineStructuresTools.project_workspace_schedule(true);end
   def onTransactionUndo(model);MarineStructuresTools.project_workspace_schedule(true);end
   def onTransactionRedo(model);MarineStructuresTools.project_workspace_schedule(true);end
   def onTransactionAbort(model);MarineStructuresTools.project_workspace_schedule(true);end
  end
  def project_workspace_schedule(full)
   @workspace_pending_full=full||@workspace_pending_full
   UI.stop_timer(@workspace_timer) if @workspace_timer
   @workspace_timer=UI.start_timer(0.08,false) do
    @workspace_timer=nil
    refresh=@workspace_pending_full;@workspace_pending_full=false
    if @workspace_model==Sketchup.active_model
     refresh ? project_workspace_refresh : project_workspace_selection
    end
   end
  end
  def project_workspace_detach
   @controlled_editor_pending=nil
   UI.stop_timer(@workspace_timer) if @workspace_timer
   @workspace_timer=nil;@workspace_pending_full=false
   if @workspace_model
    @workspace_model.selection.remove_observer(@workspace_selection_observer) if @workspace_selection_observer
    @workspace_model.remove_observer(@workspace_model_observer) if @workspace_model_observer
   end
   @workspace_model=nil;@workspace_entries=nil;@workspace_rows=nil
  end
  def project_workspace_attach(model)
   return if @workspace_model==model
   project_workspace_detach
   @workspace_model=model
   @workspace_selection_observer=WorkspaceSelectionObserver.new
   @workspace_model_observer=WorkspaceModelObserver.new
   model.selection.add_observer(@workspace_selection_observer)
   model.add_observer(@workspace_model_observer)
  end
 end
end
