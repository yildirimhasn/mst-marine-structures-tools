# frozen_string_literal: true
module MAG
 module MarineStructuresTools
  module ElevationSync
   extend self
   ROOTS=%w[head_beam flat_precast channel_precast crane_precast deck_slab].freeze
   PRECAST=%w[flat_precast channel_precast crane_precast].freeze
   TOL=0.001
   def api;MarineStructuresTools;end
   def number(value,label)
    n=Float(value.to_s.tr(',','.'))
    raise "#{label}: sonlu bir kot gerekli." unless n.finite?
    n
   rescue ArgumentError,TypeError;raise "#{label}: kot eksik veya geçersiz.";end
   def attr(e,key);number(e.get_attribute(DICT,key,nil),"#{api.element_visible_id(e)} / #{key}");end
   def instances(model)
    result=[];walk=nil
    walk=lambda do |entities,path|
     entities.each do |e|
      next unless e.is_a?(Sketchup::Group)||e.is_a?(Sketchup::ComponentInstance)
      next unless e.valid?
      result<<{entity:e,path:path,key:JSON.generate(path.map(&:persistent_id)+[e.persistent_id])}
      children=e.is_a?(Sketchup::Group) ? e.entities : e.definition.entities
      walk.call(children,path+[e])
     end
    end
    walk.call(model.entities,[]);result
   end
   def placement(entry)
    (entry[:path]+[entry[:entity]]).each do |node|
     a=node.transformation.to_a
     planar=[a[2],a[6],a[8],a[9]].all?{|v|v.abs<1e-8}&&(a[10]-1).abs<1e-8
     unit=(a[0]**2+a[1]**2-1).abs<1e-8&&(a[4]**2+a[5]**2-1).abs<1e-8&&(a[0]*a[4]+a[1]*a[5]).abs<1e-8
     raise "#{api.element_visible_id(entry[:entity])}: eğik veya ölçeklenmiş yerleşim bu akışta desteklenmiyor." unless planar&&unit
    end
   end
   def world_levels(entry)
    placement(entry);tr=Geom::Transformation.new
    entry[:path].each{|node|tr=tr*node.transformation}
    bounds=entry[:entity].bounds
    points=(0..7).map{|i|bounds.corner(i).transform(tr)}
    levels=points.map{|p|p.z.to_f/api.m(1).to_f}
    raise 'Geometri kotları geçersiz.' unless levels.all?(&:finite?)
    [levels.min,levels.max]
   end
   def verify_levels(entry)
    e=entry[:entity];actual_bottom,actual_top=world_levels(entry)
    bottom=attr(e,'bottom_elevation_m');top=attr(e,'top_elevation_m')
    expected_bottom=bottom
    if e.get_attribute(DICT,'element_type')=='head_beam'
     depths=%w[start_tooth end_tooth].map do |prefix|
      e.get_attribute(DICT,"#{prefix}_enabled",'0').to_s=='1' ? QuantityService.number(e.get_attribute(DICT,"#{prefix}_depth_m",nil),'kiriş diş derinliği') : 0.0
     end
     expected_bottom-=depths.max
    end
    raise "#{api.element_visible_id(e)}: geometri ile kayıtlı kotlar uyuşmuyor; önce elemanın kot metadata bilgisini düzeltin." unless (actual_bottom-expected_bottom).abs<=TOL&&(actual_top-top).abs<=TOL
    [bottom,top]
   end
   def uniform(values,label)
    raise "#{label}: mesnet kotları bulunamadı." if values.empty?
    raise "#{label}: mesnetler farklı kotlarda; tek düşey taşıma uygulanamaz." if values.max-values.min>TOL
    values.first
   end
   def local_shape(e)
    root=Struct.new(:entities,:transformation,:persistent_id).new(e.entities,Geom::Transformation.new,e.persistent_id)
    api.revision_geometry_signature(root)
   end
   def fingerprint(model)
    extra=instances(model).map{|entry|e=entry[:entity];[entry[:key],api.mst_attr_hash(e).sort_by{|k,v|k},e.locked?,e.definition.instances.size,api.revision_geometry_signature(e)]}
    api.revision_digest([ControlledEditor.fingerprint(model),extra])
   end
   def plan(model,request)
    original=ProjectWorkspace.validate_request(model,request,ProjectWorkspace.entries(model))
    raise 'Başlık kirişi, prekast veya döşeme seçin.' unless original.all?{|entry|ROOTS.include?(entry[:entity].get_attribute(DICT,'element_type',''))}
    req=request.merge('scope'=>'connected')
    targets=MaterialChange.targets(model,req)
    all,children,parents=api.dependency_graph(model)
    index=ProjectWorkspace.entries(model).group_by{|entry|entry[:entity]}
    # Deck cuts must keep their relative position to every supporting precast.
    added=targets.select{|entry|entry[:entity].get_attribute(DICT,'element_type')=='deck_slab'}.flat_map do |entry|
     parents[entry[:entity]].select{|e|PRECAST.include?(e.get_attribute(DICT,'element_type',''))}.flat_map{|e|index.fetch(e,[])}
    end
    targets.select{|entry|entry[:entity].get_attribute(DICT,'element_type')=='channel_precast'}.each do |entry|
     pair=%w[support_left_pid support_right_pid].map{|key|entry[:entity].get_attribute(DICT,key,0).to_i}.sort
     mates=all.select{|e|%w[flat_precast crane_precast].include?(e.get_attribute(DICT,'element_type',''))&&%w[support_left_pid support_right_pid].map{|key|e.get_attribute(DICT,key,0).to_i}.sort==pair}
     added.concat(mates.flat_map{|e|index.fetch(e,[])})
    end
    keys=(targets+added).map{|entry|entry[:key]}.uniq
    targets=MaterialChange.targets(model,req.merge('keys'=>keys))
    moving=targets.reject{|entry|entry[:entity].get_attribute(DICT,'element_type')=='head_beam'}
    raise 'Bu kapsamda kotu güncellenecek bağlı eleman yok.' if moving.empty?
    affected=moving.map{|entry|entry[:entity]}
    by_pid=index.keys.group_by{|e|e.persistent_id.to_s}
    beam_top=lambda do |value|
     candidates=by_pid[value.to_s]||[]
     raise 'Mesnet fiziksel yerleşimi belirsiz.' unless candidates.size==1&&index[candidates.first].size==1
     beam=candidates.first
     raise 'Mesnet başlık kirişi değil.' unless beam.get_attribute(DICT,'element_type')=='head_beam'
     verify_levels(index[beam].first).last
    end
    # External physical topping/accessory layers are not in the legacy graph.
    attached=instances(model)
    affected_uids=affected.map{|e|e.get_attribute(DICT,'element_uid','')}
    deck_ids=affected.select{|e|e.get_attribute(DICT,'element_type')=='deck_slab'}.map{|e|api.element_visible_id(e)}
    attached.each do |entry|
     e=entry[:entity];next if affected.include?(e)
     uid=e.get_attribute(DICT,'parent_uid','').to_s;deck=e.get_attribute(DICT,'parent_deck_id','').to_s
     nested=entry[:path].any?{|parent|affected.include?(parent)}
     typed=!e.get_attribute(DICT,'element_type','').to_s.empty?
     linked=(!uid.empty?&&affected_uids.include?(uid))||(!deck.empty?&&deck_ids.include?(deck))
     raise 'Fiziksel kaplama/aksesuar veya iç BIM elemanı var; kotu birlikte güncelleyen akış henüz desteklenmiyor.' if typed&&(linked||nested)
    end
    plans={};levels={}
    moving.each do |entry|
     e=entry[:entity]
     raise 'Taşınacak BIM elemanı özgün bir grup olmalı.' unless e.is_a?(Sketchup::Group)
     levels[e]=verify_levels(entry)
     %i[concrete_m3 formwork_m2].each do |key|
      q=QuantityService.record(e,key)
      raise "#{api.element_visible_id(e)}: #{key} eksik veya geçersiz." if %w[missing invalid].include?(q[:state])
     end
    end
    moving.select{|entry|PRECAST.include?(entry[:entity].get_attribute(DICT,'element_type'))}.each do |entry|
     e=entry[:entity];type=e.get_attribute(DICT,'element_type');support_keys=%w[support_left_pid support_right_pid].map{|key|e.get_attribute(DICT,key,nil)}
     base=uniform(support_keys.map{|pid|beam_top.call(pid)},api.element_visible_id(e))
     if type=='channel_precast'
      mates=all.select do |other|
       %w[flat_precast crane_precast].include?(other.get_attribute(DICT,'element_type',''))&&%w[support_left_pid support_right_pid].map{|key|other.get_attribute(DICT,key,0).to_i}.sort==support_keys.map(&:to_i).sort
      end
      raise "#{api.element_visible_id(e)}: kanal üst kotu için aynı mesnetli normal/dişli prekast referansı yok." if mates.empty?
      heights=mates.map{|mate|QuantityService.number(mate.get_attribute(DICT,'height_m',mate.get_attribute(DICT,'thickness_m',nil)),'referans kalınlığı')}
      raise 'Referans prekast kalınlığı sıfır olamaz.' unless heights.all?{|h|h>0}
      desired_top=base+heights.max
      delta=desired_top-levels[e].last
     elsif type=='crane_precast'
      main=e.get_attribute(DICT,'main_bottom_elevation_m',nil)
      main=levels[e].first+QuantityService.number(e.get_attribute(DICT,'extra_depth_m',nil),'diş derinliği') if main.nil?
      delta=base-number(main,'ana alt kot')
     else
      delta=base-levels[e].first
     end
     plans[e]={entry:entry,delta:delta,reason:'Mesnet kotuna uyum'}
    end
    moving.select{|entry|entry[:entity].get_attribute(DICT,'element_type')=='deck_slab'}.each do |entry|
     e=entry[:entity];supports=RelationshipAudit.tokens(e.get_attribute(DICT,'support_pids',''))
     base=uniform(supports.map{|pid|beam_top.call(pid)},api.element_visible_id(e));delta=base-levels[e].first
     precasts=parents[e].select{|p|PRECAST.include?(p.get_attribute(DICT,'element_type',''))}
     raise 'Döşeme için doğrulanmış prekast bağlantısı yok.' if precasts.empty?
     raise 'Prekast ve döşeme farklı miktarda taşınmalı. Kesimleri birlikte yeniden oluşturmak gerekiyor.' unless precasts.all?{|p|plans[p]&&(plans[p][:delta]-delta).abs<=1e-7}
     plans[e]={entry:entry,delta:delta,reason:'Prekast kesimleriyle aynı düşey taşıma'}
    end
    moving.select{|entry|entry[:entity].get_attribute(DICT,'element_type')=='curb'}.each do |entry|
     e=entry[:entity];decks=parents[e].select{|p|p.get_attribute(DICT,'element_type')=='deck_slab'}
     raise 'Bordür için tek ana döşeme gerekiyor.' unless decks.size==1&&plans[decks.first]
     deck=decks.first;delta=levels[deck].last+plans[deck][:delta]-levels[e].first
     raise 'Bordür döşemeyle aynı miktarda taşınamıyor; yerleşim ilişkisini düzeltin.' if (delta-plans[deck][:delta]).abs>1e-7
     plans[e]={entry:entry,delta:delta,reason:'Ana döşemeyle aynı düşey taşıma'}
    end
    raise 'Desteklenmeyen bağlı eleman var.' unless plans.size==moving.size
    records=plans.values.map do |item|
     e=item[:entry][:entity];bottom,top=levels[e]
     {key:item[:entry][:key],id:api.element_visible_id(e),label:ProjectWorkspace::TYPES[e.get_attribute(DICT,'element_type')],
      before_bottom:bottom,after_bottom:bottom+item[:delta],before_top:top,after_top:top+item[:delta],delta:item[:delta],changed:item[:delta].abs>1e-7,reason:item[:reason]}
    end
    raise 'Elemanlar zaten mesnet kotlarına uyumlu.' unless records.any?{|r|r[:changed]}
    {plans:plans.values,records:records,changed_count:records.count{|r|r[:changed]}}
   end
   def apply(model,pending)
    raise 'Model önizlemeden sonra değişti; yeniden önizleyin.' unless fingerprint(model)==pending[:fingerprint]
    data=plan(model,pending[:request]);opened=false
    begin
     model.start_operation('MST Bağlı Mesnet Kotlarına Uyum',true);opened=true
     data[:plans].each do |item|
      next if item[:delta].abs<=1e-7
      e=item[:entry][:entity];identity=[e.get_attribute(DICT,'element_uid'),api.element_visible_id(e),e.get_attribute(DICT,'library_type_id')]
      shape=local_shape(e);quantities=%i[concrete_m3 formwork_m2].map{|key|QuantityService.value(e,key)}
      e.transform!(Geom::Transformation.translation([0,0,api.m(item[:delta])]))
      %w[bottom_elevation_m top_elevation_m main_bottom_elevation_m].each do |key|
       raw=e.get_attribute(DICT,key,nil);e.set_attribute(DICT,key,number(raw,key)+item[:delta]) unless raw.nil?
      end
      e.set_attribute(DICT,'revision',VERSION);verify_levels(item[:entry])
      raise 'Geometri, kimlik veya metraj beklenmedik biçimde değişti.' unless local_shape(e)==shape&&identity==[e.get_attribute(DICT,'element_uid'),api.element_visible_id(e),e.get_attribute(DICT,'library_type_id')]&&quantities==%i[concrete_m3 formwork_m2].map{|key|QuantityService.value(e,key)}
     end
     api.commit_with_dependencies(model);opened=false
    rescue
     model.abort_operation if opened
     raise
    end
    {message:"#{data[:changed_count]} elemanın kotu güncellendi. Mesnetler, kesitler ve miktarlar korundu."}
   end
  end
  def elevation_sync_from_selection
   model=Sketchup.active_model;entries=ProjectWorkspace.entries(model)
   roots=ProjectWorkspace.selected_entries(model,entries).select{|entry|ElevationSync::ROOTS.include?(entry[:entity].get_attribute(DICT,'element_type',''))}
   if roots.empty?
    UI.messagebox('Önce modelden başlık kirişi, prekast veya döşeme seçin. Kot güncellemesi önizlemeyle açılacak.');return
   end
   elevation_sync_show(JSON.generate('model_token'=>model.object_id.to_s,'keys'=>roots.map{|entry|entry[:key]}))
  end
  def elevation_sync_show(raw)
   request=JSON.parse(raw)
   roots=ProjectWorkspace.validate_request(Sketchup.active_model,request,ProjectWorkspace.entries(Sketchup.active_model))
   @elevation_sync_dialog.close if @elevation_sync_dialog&&@elevation_sync_dialog.visible?
   d=UI::HtmlDialog.new(dialog_title:'MST — Bağlı Mesnet Kotlarına Uyum',width:1100,height:760,resizable:true)
   d.set_file(File.join(__dir__,'elevation_sync.html'));pending=nil
   d.add_action_callback('elevation_ready'){|_|d.execute_script("elevationSyncLoaded(#{JSON.generate(roots.map{|entry|element_visible_id(entry[:entity])})})")}
   d.add_action_callback('elevation_preview'){|_,generation|
    pending=nil
    begin
     data=ElevationSync.plan(Sketchup.active_model,request);token=SecureRandom.hex(16)
     pending={token:token,request:request,fingerprint:ElevationSync.fingerprint(Sketchup.active_model)}
     preview=data.reject{|key,value|key==:plans}.merge(token:token,request_id:generation)
     d.execute_script("elevationSyncPreview(#{JSON.generate(preview)})")
    rescue=>error;pending=nil;d.execute_script("elevationSyncError(#{JSON.generate(error.message)})");end
   }
   d.add_action_callback('elevation_apply'){|_,token|
    saved=pending;pending=nil
    begin
     raise 'Geçerli önizleme gerekiyor.' unless saved&&saved[:token]==token
     result=ElevationSync.apply(Sketchup.active_model,saved)
     d.execute_script("elevationSyncDone(#{JSON.generate(result)})");project_workspace_refresh
    rescue=>error;d.execute_script("elevationSyncError(#{JSON.generate(error.message)})");end
   }
   d.set_on_closed{pending=nil};@elevation_sync_dialog=d;d.show
  rescue=>error
   @d.execute_script("projectWorkspaceError(#{JSON.generate(error.message)})") if @d&&@d.visible?
  end
 end
end
