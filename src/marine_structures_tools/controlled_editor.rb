# frozen_string_literal: true
require 'securerandom'
module MAG
 module MarineStructuresTools
  module ControlledEditor
   extend self
   FIELDS={
    'head_beam'=>{'length_m'=>'Boy (m)','width_m'=>'Genişlik (m)','height_m'=>'Yükseklik (m)'},
    'flat_precast'=>{'length_m'=>'Boy (m)','width_m'=>'Genişlik (m)','height_m'=>'Kalınlık (m)'},
    'channel_precast'=>{'length_m'=>'Boy (m)','inner_width_m'=>'İç genişlik (m)','inner_depth_m'=>'İç derinlik (m)','base_thickness_m'=>'Taban kalınlığı (m)','wall_thickness_m'=>'Duvar kalınlığı (m)'}
   }.freeze
   CLASSES=%w[C20/25 C25/30 C30/37 C35/45 C40/50 C45/55 C50/60 C55/67 C60/75].freeze
   def api;MarineStructuresTools;end
   def validate_geometry(e,type)
    dimensions=FIELDS[type].keys.each_with_object({}){|key,h|h[key]=QuantityService.number(e.get_attribute(DICT,key,nil),key)}
    l=dimensions['length_m']
    if type=='flat_precast'
     w=dimensions['width_m'];h=dimensions['height_m']
     points=[0,l].product([0,w],[0,h])
     volume=l*w*h
    else
     w=dimensions['inner_width_m'];d=dimensions['inner_depth_m'];b=dimensions['base_thickness_m'];t=dimensions['wall_thickness_m'];outer=w+2*t;height=d+b
     profile=[[0,0],[outer,0],[outer,height],[outer-t,height],[outer-t,b],[t,b],[t,height],[0,height]]
     points=[0,l].flat_map{|x|profile.map{|y,z|[x,y,z]}}
     volume=(outer*b+2*t*d)*l
    end
    expected=points.map{|p|p.map{|v|api.m(v).to_f.round(6)}}.uniq.sort
    actual=e.entities.grep(Sketchup::Face).flat_map{|face|face.vertices.map{|v|v.position.to_a.map{|n|n.to_f.round(6)}}}.uniq.sort
    raise 'Geometri standart parametrik profille eşleşmiyor. Elle değiştirilmiş kesit korunması için işlem durduruldu.' unless actual==expected
    actual_volume=e.volume.to_f/(api.m(1).to_f**3)
    raise 'Geometri kapalı bir katı değil veya hacmi standart kesitle eşleşmiyor.' unless e.manifold?&&actual_volume.finite?&&(actual_volume-volume).abs<[1e-7,volume*1e-7].max
   end
   def formwork_flags(e,type)
    roles=type=='channel_precast' ? [%w[OUTER_BOTTOM],%w[OUTER_SIDE],%w[INNER_FLOOR INNER_SIDE],%w[END_FACE]] : [%w[BOTTOM],%w[LONG_SIDE_1],%w[LONG_SIDE_2],%w[END_1],%w[END_2]]
    flags=e.get_attribute(DICT,'editor_formwork_flags',nil)
    valid=flags.is_a?(Array)&&flags.size==roles.size&&flags.all?{|v|v==true||v==false}
    return flags if valid
    faces=e.entities.grep(Sketchup::Face)
    if !faces.empty?&&faces.all?{|f|[true,false].include?(f.get_attribute(DICT,'formwork',nil))}
     return roles.map{|names|faces.any?{|f|f.get_attribute(DICT,'formwork',false)==true&&names.include?(f.get_attribute(DICT,'formwork_type',''))}}
    end
    if type=='channel_precast'
     flags=%w[bottom sides inner ends].map{|k|e.get_attribute(DICT,"formwork_#{k}",nil)}
     return flags if flags.all?{|v|v==true||v==false}
    end
    raise 'Kalıp yüzü seçimleri eksik. Önce elemanın kalıp verisini düzeltin.'
   end
   def resolve(model,request)
    targets=ProjectWorkspace.validate_request(model,request,ProjectWorkspace.entries(model))
    raise 'Tek bir eleman seçin.' unless targets.size==1
    entry=targets.first;e=entry[:entity]
    raise 'Bu eleman türü için kontrollü düzenleme hazır değil.' unless FIELDS.key?(e.get_attribute(DICT,'element_type',''))
    raise 'Yalnız özgün grup geometrisi düzenlenebilir.' unless e.is_a?(Sketchup::Group)
    (entry[:path]+[e]).each do |node|
     raise 'Kilitli eleman veya üst grup düzenlenemez.' if node.locked?
     raise 'Paylaşılan bileşen/grup önce bağımsızlaştırılmalıdır.' if node.definition.instances.size>1
     a=node.transformation.to_a
     vectors=[a[0,3],a[4,3],a[8,3]]
     unit=vectors.all?{|v|(v.sum{|n|n*n}-1).abs<1e-8}
     orthogonal=[[0,1],[0,2],[1,2]].all?{|i,j|vectors[i].zip(vectors[j]).sum{|x,y|x*y}.abs<1e-8}
     raise 'Ölçeklenmiş veya kesme uygulanmış geometri önce normalize edilmelidir.' unless unit&&orthogonal
    end
    raise 'Alt grup içeren geometri bu düzenleyiciyle yeniden kurulamaz.' if e.entities.any?{|part|part.is_a?(Sketchup::Group)||part.is_a?(Sketchup::ComponentInstance)}
    raise 'Eleman kimliği eksik; önce BIM kimlik kontrolünü tamamlayın.' if e.get_attribute(DICT,'element_uid','').to_s.empty?
    uid=e.get_attribute(DICT,'element_uid','').to_s
    occurrences=ProjectWorkspace.entries(model).count{|item|item[:entity].get_attribute(DICT,'element_uid','').to_s==uid}
    raise 'Eleman kimliği birden fazla fiziksel yerleşimde kullanılıyor; önce kimlik kontrolünü tamamlayın.' if occurrences>1
    entry
   end
   # Önizleme ile uygulama arasında model değişti mi (bayat önizleme). Her Çalışma Alanı elemanı için öznitelikler, alt varlık
   # öznitelik/malzemeleri, kendi dönüşümü ve üst yol; model öznitelikleri. G2 (03.11.2026): iç geometri imzası
   # (revision_geometry_signature: yüz/kenar köşeleri) yalnız düzenlenen eleman ve bağımlılık ağacı (mst_dependency_tree) için
   # hesaplanır — uygulama (plan, validate_geometry, yeniden kurma, sync_type) başka elemanın yalnız özniteliklerini okur.
   # request yoksa ya da hedef çözülemezse (silinmiş / taşınmış) eski tam imza → önizleme imzasıyla eşleşmez, aynı ileti.
   def fingerprint(model,request=nil)
    list=ProjectWorkspace.entries(model)
    focus=nil
    if request
     t=(ProjectWorkspace.validate_request(model,request,list) rescue nil)
     if t&&t.size==1
      root=t.first[:entity];focus={root=>true}
      api.mst_dependency_tree(root).each{|child,_depth|focus[child]=true}
     end
    end
    records=api.revision_shape_memo do
     list.map do |entry|
      e=entry[:entity]
      attrs=api.mst_attr_hash(e).sort_by{|k,v|k}
      entities=e.is_a?(Sketchup::Group) ? e.entities : e.definition.entities
      surface=entities.map{|part|[api.mst_attr_hash(part),part.respond_to?(:material)&&part.material ? part.material.name : nil,part.respond_to?(:back_material)&&part.back_material ? part.back_material.name : nil]}
      shape=(focus.nil?||focus[e]) ? api.revision_geometry_signature(e) : ['T',e.transformation.to_a]
      [entry[:key],attrs,surface,shape,entry[:path].map{|n|[n.transformation.to_a,n.locked?,n.definition.instances.size]}]
     end
    end
    api.revision_digest([api.mst_attr_hash(model).sort_by{|k,v|k},records])
   end
   def open(model,request)
    entry=resolve(model,request);e=entry[:entity];type=e.get_attribute(DICT,'element_type','')
    type=='head_beam' ? HeadBeamEditor.flags(e) : formwork_flags(e,type)
    {model_token:model.object_id.to_s,keys:[entry[:key]],id:api.element_visible_id(e),label:ProjectWorkspace::TYPES[type],
     fields:FIELDS[type].map{|key,label|{key:key,label:label,value:e.get_attribute(DICT,key,nil)}},concrete_class:e.get_attribute(DICT,'concrete_class',''),classes:CLASSES,note:type=='head_beam' ? 'Diş ve oturma detayları korunur. Genişlik merkezi ve normal alt kot sabittir. Bağlı elemanları etkileyen ölçü değişiklikleri engellenir.' : nil}
   end
   def plan(model,request)
    entry=resolve(model,request);e=entry[:entity];type=e.get_attribute(DICT,'element_type','');values=request['values']
    return HeadBeamEditor.plan(model,request,entry) if type=='head_beam'
    raise 'Ölçü verisi geçersiz.' unless values.is_a?(Hash)
    expected=FIELDS[type].keys+['concrete_class']
    raise 'Desteklenmeyen veya eksik alan gönderildi.' unless values.keys.sort==expected.sort
    normalized={};changes=[]
    FIELDS[type].each do |key,label|
     n=QuantityService.number(values[key],key)
     raise "#{label}: sıfırdan büyük bir ölçü girin." unless n>0
     old=QuantityService.number(e.get_attribute(DICT,key,nil),key)
     normalized[key]=n
     changes<<{label:label,before:old,after:n} if (n-old).abs>1e-9
    end
    cls=values['concrete_class'].to_s.strip
    raise 'Desteklenen bir beton sınıfı seçin.' unless CLASSES.include?(cls)
    normalized['concrete_class']=cls
    old_cls=e.get_attribute(DICT,'concrete_class','').to_s
    material_changed=cls!=old_cls
    changes<<{label:'Beton sınıfı',before:old_cls,after:cls} if material_changed
    geometry_changed=normalized.any?{|k,v|k!='concrete_class'&&(v-e.get_attribute(DICT,k,0).to_f).abs>1e-9}
    raise 'Değişiklik bulunamadı.' if changes.empty?
    validate_geometry(e,type) if geometry_changed
    dependencies=api.mst_dependency_tree(e)
    raise 'Bu prekast bağlı elemanları etkiliyor. Geometri değişikliği için bağlantılı yeniden oluşturma akışı gerekiyor.' if geometry_changed&&!dependencies.empty?
    if geometry_changed
     has_support=%w[support_left_pid support_right_pid].any?{|k|e.get_attribute(DICT,k,0).to_i>0}||!e.get_attribute(DICT,'support_uids','').to_s.empty?
     raise 'Mesnetlere bağlı prekastın geometrisi bu akıştan değiştirilemez; yerleşim ve kotlar birlikte yeniden kurulmalıdır.' if has_support
    end
    flags=formwork_flags(e,type)
    n=normalized;l=n['length_m']
    if type=='flat_precast'
     w=n['width_m'];h=n['height_m'];volume=l*w*h
     areas=[l*w,l*h,l*h,w*h,w*h]
    else
     w=n['inner_width_m'];d=n['inner_depth_m'];b=n['base_thickness_m'];t=n['wall_thickness_m'];outer=w+2*t;height=d+b
     volume=(outer*b+2*t*d)*l
     areas=[l*outer,2*l*height,l*(w+2*d),2*(outer*b+2*t*d)]
    end
    formwork=areas.each_with_index.sum{|area,i|flags[i] ? area : 0.0}
    unless geometry_changed
     volume=QuantityService.value(e,:concrete_m3);formwork=QuantityService.value(e,:formwork_m2)
    end
    new_type,base_type=geometry_changed ? precast_type_after(model,e,type,normalized) : nil
    changes<<{label:'Prekast tipi',before:api.mst_precast_type_id(e),after:new_type} if new_type
    {entry:entry,values:normalized,geometry_changed:geometry_changed,changes:changes,volume:volume,
     formwork:formwork,dependencies:dependencies.size,new_type:new_type,base_type:base_type}
   end
   # 03.11.2026 (kullanıcı kararı): geometri değişince prekast tip adı, BK'ye bağlı boyutlandırmayla aynı kuralla
   # (mst_precast_new_type_name: aynı tür + temel tip + ölçüde kayıtlı tip varsa o ad, yoksa "<temel>-B…"). Salt okuma.
   # => [yeni ad, temel tip] ya da nil (tip adı yok / değişmiyor). Mevcut anahtarlar: precast_type_id, precast_type, precast_base_type_id.
   def precast_type_after(model,e,type,values)
    old=api.mst_precast_type_id(e);return nil if old.empty?
    others=ProjectWorkspace.entries(model).map{|x|x[:entity]}.uniq.reject{|x|x==e}
    reg=api.mst_precast_type_registry(others,model);reg['used'][old.upcase]=true
    mm=->(k){(values[k].to_f*1000.0).round}
    dims=type=='channel_precast' ? %w[length_m inner_width_m inner_depth_m base_thickness_m wall_thickness_m].map(&mm) : %w[length_m width_m height_m].map(&mm)
    name=api.mst_precast_new_type_name(e,nil,reg,dims)
    name==old ? nil : [name,api.mst_precast_base_type(e)]
   end
   def sync_type(e,model)
    signature=api.element_signature(e)
    peers=ProjectWorkspace.entries(model).map{|entry|entry[:entity]}.uniq
    mate=peers.find{|other|other!=e&&api.element_signature(other)==signature&&!other.get_attribute(DICT,'library_type_id','').to_s.empty?}
    if mate
     type=mate.get_attribute(DICT,'library_type_id')
    else
     used=peers.flat_map{|other|%w[library_type_id type_id].map{|key|other.get_attribute(DICT,key,'').to_s}}
     begin
      type=api.next_library_type_id(model,api.bim_type_prefix(e.get_attribute(DICT,'element_type')))
     end while used.include?(type)
    end
    e.set_attribute(DICT,'type_signature',signature);e.set_attribute(DICT,'library_type_id',type);e.set_attribute(DICT,'type_id',type)
    api.mst_assign_tag(e,model)
   end
   def apply(model,pending)
    plan=nil
    # G2: işlem öncesi denetim salt okuma — tek tarama, Çalışma Alanı ağacı bir kez (yeniden kurma / sync_type kapsam dışında)
    api.mst_read_batch(model) do
     ProjectWorkspace.entries_memo(model) do
      raise 'Önizlemeden sonra model değişti; yeniden önizleyin.' unless pending[:fingerprint]==fingerprint(model,pending[:request])
      plan=plan(model,pending[:request])
     end
    end
    e=plan[:entry][:entity];opened=false
    begin
     model.start_operation('MST Kontrollü Eleman Düzenleme',true);opened=true
     if plan[:geometry_changed]
      method={'head_beam'=>:rebuild_head_beam_parametric,'flat_precast'=>:rebuild_flat_precast_parametric,'channel_precast'=>:rebuild_channel_parametric}.fetch(e.get_attribute(DICT,'element_type'))
      if e.get_attribute(DICT,'element_type')=='head_beam'
       HeadBeamEditor.rebuild(e,plan[:values])
      else
       api.public_send(method,e,plan[:values])
      end
      raise 'Beton metrajı önizleme ile uyuşmadı.' if (QuantityService.value(e,:concrete_m3)-plan[:volume]).abs>1e-8
      raise 'Kalıp metrajı önizleme ile uyuşmadı.' if (QuantityService.value(e,:formwork_m2)-plan[:formwork]).abs>1e-8
      if plan[:new_type]
       e.set_attribute(DICT,'precast_base_type_id',plan[:base_type])
       api.mst_set_precast_type!(e,plan[:new_type])
      end
     else
      e.set_attribute(DICT,'concrete_class',plan[:values]['concrete_class'])
     end
     sync_type(e,model)
     e.set_attribute(DICT,'revision',VERSION)
     api.commit_with_dependencies(model);opened=false
    rescue
     model.abort_operation if opened
     raise
    end
    {id:api.element_visible_id(e),message:'Eleman, metraj ve tip kimliği güncellendi. Tek geri alma işlemiyle geri dönebilirsiniz.'}
   end
  end
  def controlled_editor_open(request,dialog=@d)
   @controlled_editor_pending=nil
   dialog.execute_script('controlledEditorReset()')
   model=Sketchup.active_model
   data=ProjectWorkspace.entries_memo(model){ControlledEditor.open(model,request)}   # G2: resolve içinde ağaç bir kez
   dialog.execute_script("controlledEditorLoaded(#{JSON.generate(data)})")
  rescue=>error
   dialog.execute_script("controlledEditorError(#{JSON.generate(error.message)})")
  end
  def controlled_editor_preview(raw,dialog=@d)
   @controlled_editor_pending=nil;request=JSON.parse(raw);model=Sketchup.active_model
   data=nil;token=nil;fp=nil
   # G2 (03.11.2026): salt okuma — tek model taraması, Çalışma Alanı ağacı bir kez
   mst_read_batch(model) do
    ProjectWorkspace.entries_memo(model) do
     plan=ControlledEditor.plan(model,request);token=SecureRandom.hex(16)
     fp=ControlledEditor.fingerprint(model,request)
     e=plan[:entry][:entity]
     data={token:token,request_id:request['request_id'],changes:plan[:changes],before_concrete:QuantityService.value(e,:concrete_m3),after_concrete:plan[:volume],
      before_formwork:QuantityService.value(e,:formwork_m2),after_formwork:plan[:formwork],dependencies:plan[:dependencies]}
    end
   end
   @controlled_editor_pending={token:token,request:request,fingerprint:fp}
   dialog.execute_script("controlledEditorPreview(#{JSON.generate(data)})")
  rescue=>error
   @controlled_editor_pending=nil;dialog.execute_script("controlledEditorError(#{JSON.generate(error.message)})")
  end
  def controlled_editor_apply(raw,dialog=@d)
   token=JSON.parse(raw)['token'];pending=@controlled_editor_pending
   @controlled_editor_pending=nil
   raise 'Geçerli bir önizleme gerekiyor.' unless pending&&pending[:token]==token
   result=ControlledEditor.apply(Sketchup.active_model,pending)
   dialog.execute_script("controlledEditorDone(#{JSON.generate(result)})")
   project_workspace_refresh(dialog)   # G1: bu tam yenileme işlem sonrası bekleyen gözlemci yenilemesini iptal eder (tek yenileme)
  rescue=>error
   dialog.execute_script("controlledEditorError(#{JSON.generate(error.message)})")
  end
 end
end
