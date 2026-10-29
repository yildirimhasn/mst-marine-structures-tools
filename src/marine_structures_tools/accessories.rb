# frozen_string_literal: true
require 'securerandom'
require 'fileutils'
module MAG
module MarineStructuresTools
ACCESSORY_KEY='accessory_schedule_v1'.freeze
ACCESSORY_NAMES={'bollard'=>'Baba','fender'=>'Usturmaça','ring'=>'Halat Halkası','hook'=>'Çabuk Bırakma Kancası','ladder'=>'Merdiven','catwalk'=>'Kedi Yolu','railing'=>'Korkuluk','stop'=>'Tekerlek Stoperi','lifebuoy'=>'Can Simidi İstasyonu','capstan'=>'Irgat / Kapstan','other'=>'Diğer Aksesuar'}.freeze
def accessory_rows
 raw=Sketchup.active_model.get_attribute(DICT,ACCESSORY_KEY,'[]')
 rows=JSON.parse(raw)
 raise 'Aksesuar kayıtları okunamadı.' unless rows.is_a?(Array)
 rows
end
def accessory_validate(rows)
 raise 'Aksesuar listesi geçersiz.' unless rows.is_a?(Array) && rows.length<=1000
 ids=[];types=[]
 rows.map do |raw|
  raise 'Geçersiz satır.' unless raw.is_a?(Hash)
  d=raw.slice('id','category','type','variant','unit','quantity','capacity','hooks','length','height','width','energy','reaction','manufacturer','model','location','scope','release','capstan','loadcell','material','notes','anchor_type','anchor_count','anchor_dia','elevation','panel','facepad','chain_set','standard','drawing_ref','family','catalog_model','catalog_source','weight_kg','catalog_verified','geometry_source','geometry_note','geometry_shape','dim_D_mm','dim_d_mm','dim_t_mm','dim_E_mm','bolt_circle_outer_mm','bolt_circle_inner_mm','anchor_rebar_kg')
  %w[id category type variant unit scope].each{|key|raise "Eksik alan: #{key}" if d[key].to_s.strip.empty?}
  raise 'Aksesuar türü geçersiz.' unless ACCESSORY_NAMES.key?(d['category'])
  raise 'Birim ad veya m olmalı.' unless %w[ad m].include?(d['unit'])
  raise 'Bu aksesuar adet olarak izlenir.' if !%w[railing stop other catwalk].include?(d['category']) && d['unit']!='ad'
  raise 'Aynı satır kimliği tekrarlandı.' if ids.include?(d['id']);ids<<d['id']
  type=d['type'].strip;raise 'Tip kodları benzersiz olmalı.' if types.include?(type);types<<type;d['type']=type
  %w[quantity capacity length height width energy reaction anchor_count anchor_dia elevation weight_kg anchor_rebar_kg].each do |key|
   val=d[key];d[key]=val.nil? || val.to_s.strip.empty? ? nil : Float(val.to_s.tr(',','.'))
   raise "#{type}: #{key} negatif veya geçersiz." if d[key] && (!d[key].finite? || d[key]<0)
  end
  raise 'Miktar girin; kullanılmayan tip için 0 yazın.' unless d['quantity']
  raise 'Adet tam sayı olmalı.' if d['unit']=='ad' && d['quantity']%1!=0
  raise "#{type}: ankraj adedi tam sayı olmalı." if d['anchor_count'] && d['anchor_count']%1!=0
  if %w[bollard ring hook].include?(d['category'])
   raise "#{type}: kapasite sıfırdan büyük olmalı." unless d['capacity'] && d['capacity']>0
  end
  if d['category']=='hook'
   d['hooks']=Integer(d['hooks'].to_s)
   raise 'Kanca sayısı 1–4 olmalı.' unless (1..4).include?(d['hooks'])
  end
  d
 end
end
def accessory_description(r)
 parts=[ACCESSORY_NAMES[r['category']],r['type'],r['variant']]
 parts<<"#{r['capacity']} t#{r['category']=='hook' ? '/kanca' : ''}" if r['capacity']
 parts<<"#{r['hooks']} kanca/set" if r['category']=='hook'
 parts<<r['model'] unless r['model'].to_s.empty?
 parts<<"#{r['anchor_count'].to_i} ankraj" if r['anchor_count'].to_f>0
 parts<<"ankraj donatısı #{r['anchor_rebar_kg'].to_f.round(1)} kg/#{r['unit']}" if r['anchor_rebar_kg'].to_f>0   # v0.50 AN1 (döşeme donatısına eklenir)
 parts<<r['scope']
 parts.join(' · ')
end
def accessory_sources
 accessory_rows.select{|r|r['quantity'].to_f>0}.map{|r|{key:"ACCESSORY:#{r['id']}",name:accessory_description(r),unit:r['unit'],quantity:r['quantity'].to_f}}
end
def accessory_boq_rows(library,map)
 accessory_sources.map do |r|
  if map.key?(r[:key])
   boq_mapped_row(r[:key],r[:unit],r[:quantity],map[r[:key]],library)
  else
   {code:'—',name:r[:name],unit:r[:unit],quantity:r[:quantity],unit_price:nil,total:nil,source:r[:key],status:'ÖBF EŞLEŞTİRİLMELİ',library_price:true}
  end
 end
end
def accessory_report_html
 rows=accessory_rows.select{|r|r['quantity'].to_f>0};return '' if rows.empty?
 body=rows.map{|r|"<tr><td>#{html_escape(r['type'])}</td><td>#{html_escape(accessory_description(r))}</td><td>#{html_escape(r['location'])}</td><td>#{format(r['unit']=='ad' ? '%.0f' : '%.2f',r['quantity'])}</td><td>#{html_escape(r['unit'])}</td></tr>"}.join
 "<h3>İskele Aksesuarları</h3><p>Proje çizelgesine girilen miktarlar; model geometrisinden sayılmaz.</p><table><tr><th>Tip</th><th>Teknik tanım / kapsam</th><th>Konum</th><th>Miktar</th><th>Birim</th></tr>#{body}</table>"
end

# v0.34.3/4 — Smart placement + equipment system components
def accessory_apply_metadata(group,row,index)
  group.set_attribute(DICT,'element_type','accessory')
  group.set_attribute(DICT,'element_uid',SecureRandom.uuid)
  group.set_attribute(DICT,'accessory_schedule_id',row['id'])
  group.set_attribute(DICT,'accessory_category',row['category'])
  group.set_attribute(DICT,'accessory_type',row['type'])
  group.set_attribute(DICT,'accessory_variant',row['variant'])
  group.set_attribute(DICT,'manufacturer',row['manufacturer'].to_s)
  group.set_attribute(DICT,'catalog_model',row['catalog_model'].to_s)
  group.set_attribute(DICT,'geometry_source',row['geometry_source'].to_s)
  group.set_attribute(DICT,'geometry_note',row['geometry_note'].to_s)
  group.set_attribute(DICT,'capacity_t',row['capacity'].to_f) if row['capacity']
  group.set_attribute(DICT,'energy_kNm',row['energy'].to_f) if row['energy']
  group.set_attribute(DICT,'reaction_kN',row['reaction'].to_f) if row['reaction']
  group.set_attribute(DICT,'placement_index',index)
  group.name="#{row['type']}-#{format('%03d',index)}"
  mst_assign_tag(group,Sketchup.active_model) if respond_to?(:mst_assign_tag)
end

def accessory_add_box(ents,x,y,z)
  x=[x.to_f,0.10].max.m; y=[y.to_f,0.10].max.m; z=[z.to_f,0.10].max.m
  pts=[[0,0,0],[x,0,0],[x,y,0],[0,y,0]]
  face=ents.add_face(pts); face.pushpull(z) if face
end

def accessory_add_cylinder(ents,d,h)
  d=[d.to_f,0.10].max.m; h=[h.to_f,0.10].max.m
  edges=ents.add_circle(ORIGIN,Z_AXIS,d/2.0,24)
  face=ents.add_face(edges); face.pushpull(h) if face
end

def accessory_add_frustum(ents,d1,d2,h,segments=48)
  d1=[d1.to_f,0.10].max.m; d2=[d2.to_f,0.10].max.m; h=[h.to_f,0.10].max.m
  n=[segments.to_i,12].max
  bottom=[]; top=[]
  n.times do |i|
    a=2.0*Math::PI*i/n
    bottom << Geom::Point3d.new((d1/2.0)*Math.cos(a),(d1/2.0)*Math.sin(a),0)
    top << Geom::Point3d.new((d2/2.0)*Math.cos(a),(d2/2.0)*Math.sin(a),h)
  end
  n.times do |i|
    j=(i+1)%n
    ents.add_face(bottom[i],bottom[j],top[j],top[i])
  end
end

def accessory_add_bolt_pattern(ents,pcd_mm,count,bolt_mm,z=0.0)
  return if pcd_mm.to_f<=0 || count.to_i<=0
  r=pcd_mm.to_f/2000.0
  dia=(bolt_mm.to_f>0 ? bolt_mm.to_f/1000.0 : 0.03)
  count.to_i.times do |i|
    a=2.0*Math::PI*i/count.to_i
    g=ents.add_group; g.name='Anchor/Bolt'
    accessory_add_cylinder(g.entities,dia,0.08)
    g.transform!(Geom::Transformation.translation([(r*Math.cos(a)).m,(r*Math.sin(a)).m,z.to_f.m]))
  end
end

def accessory_build_geometry(group,row)
  ents=group.entities
  cat=row['category']
  if cat=='bollard'
    d=(row['width'].to_f>0 ? row['width'].to_f : 0.55)
    h=(row['height'].to_f>0 ? row['height'].to_f : 0.75)
    accessory_add_cylinder(ents,d,h)
    # symbolic head
    head=ents.add_group; accessory_add_box(head.entities,d*1.25,d*0.38,d*0.22)
    head.transform!(Geom::Transformation.translation([-d*0.625.m,-d*0.19.m,(h*0.78).m]))
    n=row['anchor_count'].to_i
    if n>0
      ag=ents.add_group; ag.name='Anchor System'; ag.set_attribute(DICT,'component_role','anchors')
      r=d*0.42
      n.times do |i|
        a=2.0*Math::PI*i/n; bolt=ag.entities.add_group
        accessory_add_cylinder(bolt.entities,(row['anchor_dia'].to_f>0 ? row['anchor_dia'].to_f/1000.0 : 0.04),0.12)
        bolt.transform!(Geom::Transformation.translation([(r*Math.cos(a)).m,(r*Math.sin(a)).m,-0.12.m]))
      end
    end
  elsif cat=='fender'
    w=(row['width'].to_f>0 ? row['width'].to_f : 0.80)
    h=(row['height'].to_f>0 ? row['height'].to_f : 0.80)
    l=(row['length'].to_f>0 ? row['length'].to_f : 0.80)
    rubber=ents.add_group; rubber.name='Rubber Fender'; rubber.set_attribute(DICT,'component_role','rubber')
    if row['geometry_shape'].to_s=='cone' && row['dim_D_mm'].to_f>0 && row['dim_d_mm'].to_f>0
      accessory_add_frustum(rubber.entities,row['dim_D_mm'].to_f/1000.0,row['dim_d_mm'].to_f/1000.0,h,48)
      accessory_add_bolt_pattern(rubber.entities,row['bolt_circle_outer_mm'],row['anchor_count'],row['anchor_dia'],0.0)
      rubber.set_attribute(DICT,'geometry_source',row['geometry_source'].to_s)
    else
      accessory_add_box(rubber.entities,l,w,h)
    end
    panel=ents.add_group; panel.name='Frontal Panel'; panel.set_attribute(DICT,'component_role','panel')
    accessory_add_box(panel.entities,0.12,w*1.35,h*1.35); panel.transform!(Geom::Transformation.translation([l.m,(-w*0.175).m,(-h*0.175).m]))
    if !row['facepad'].to_s.empty?
      pad=ents.add_group; pad.name='UHMW-PE Face Pad'; pad.set_attribute(DICT,'component_role','facepad')
      accessory_add_box(pad.entities,0.04,w*1.30,h*1.30); pad.transform!(Geom::Transformation.translation([(l+0.12).m,(-w*0.15).m,(-h*0.15).m]))
    end
    if !row['chain_set'].to_s.empty?
      cg=ents.add_group; cg.name='Chain / Connection Set'; cg.set_attribute(DICT,'component_role','chain_set')
      2.times do |i|
        y=(i==0 ? -w*0.15 : w*1.15)
        cg.entities.add_line([l.m,(w*0.5).m,(h*0.75).m],[(l+0.65).m,y.m,(h*1.25).m])
      end
    end
  else
    accessory_add_box(ents,(row['length'].to_f>0 ? row['length'].to_f : 0.50),(row['width'].to_f>0 ? row['width'].to_f : 0.30),(row['height'].to_f>0 ? row['height'].to_f : 0.50))
  end
end

def accessory_place_on_selected_edge(row,spacing)
  model=Sketchup.active_model
  edge=model.selection.grep(Sketchup::Edge).first
  raise 'Önce yerleşim hattı olarak bir kenar (Edge) seçin.' unless edge
  spacing=spacing.to_f
  raise 'Yerleşim aralığı 0’dan büyük olmalı.' unless spacing>0
  a=edge.start.position; b=edge.end.position; vec=b-a; len=vec.length
  raise 'Seçilen kenarın uzunluğu sıfır.' if len<=0
  count=(len/spacing.m).floor+1
  count=[count,500].min
  dir=vec.clone; dir.length=1.0
  parent=model.active_entities
  created=[]
  model.start_operation('Marine Equipment Akıllı Yerleşim',true)
  begin
    count.times do |i|
      dist=[i*spacing.m,len].min
      pt=a.offset(dir,dist)
      g=parent.add_group
      accessory_build_geometry(g,row)
      accessory_apply_metadata(g,row,i+1)
      g.transform!(Geom::Transformation.translation(pt.to_a))
      created<<g
    end
    model.commit_operation
  rescue
    model.abort_operation; raise
  end
  model.selection.clear; created.each{|g|model.selection.add(g)}
  model.active_view.zoom(model.selection) unless created.empty?
  {count:created.length,spacing:spacing,length_m:len.to_m}
end

# v0.34.6 — Persistent User Accessory Library
USER_ACCESSORY_CATEGORIES={'bollard'=>'Baba','fender'=>'Usturmaça','ring'=>'Halat Halkası','hook'=>'Çabuk Bırakma Kancası','ladder'=>'Merdiven','railing'=>'Korkuluk','stop'=>'Tekerlek Stoperi','lifebuoy'=>'Can Simidi İstasyonu','capstan'=>'Irgat / Kapstan','other'=>'Diğer Aksesuar'}.freeze

def user_accessory_library_dir
  base=ENV['APPDATA'].to_s.strip
  base=File.expand_path('~') if base.empty?
  dir=File.join(base,'MAG_MarineStructuresTools','UserAccessoryLibrary')
  FileUtils.mkdir_p(dir)
  dir
end

def user_accessory_index_path
  File.join(user_accessory_library_dir,'library.json')
end

def user_accessory_items
  path=user_accessory_index_path
  return [] unless File.exist?(path)
  data=JSON.parse(File.read(path,encoding:'UTF-8'))
  data.is_a?(Array) ? data : []
rescue
  []
end

# R-4 / K27: yazmadan önce okuma — dosya yok/boş → [], bozuk → hata (dosyanın üzerine yazılmaz)
def user_accessory_items_for_write
  path=user_accessory_index_path
  return [] unless File.exist?(path)
  raw=File.read(path,encoding:'UTF-8')
  return [] if raw.strip.empty?
  data=(JSON.parse(raw) rescue nil)
  raise "Aksesuar kütüphanesi dosyası okunamadı; mevcut dosyanın üzerine yazılmadı.\n#{path}\nDosyayı yedekleyip düzeltin veya taşıyın, sonra yeniden deneyin." unless data.is_a?(Array)
  data
end

# Atomik yazım (boq_library.rb write_storage deseni): geçici dosya + doğrulama + rename
def user_accessory_write(items)
  raw=JSON.pretty_generate(items)
  path=user_accessory_index_path
  temporary=path+'.'+SecureRandom.uuid+'.tmp'
  begin
    File.open(temporary,'wb') { |f| f.write(raw); f.flush; f.fsync }
    raise 'Aksesuar kütüphanesi yazılırken doğrulama başarısız.' unless File.binread(temporary)==raw.b
    File.rename(temporary,path)
    raise 'Aksesuar kütüphanesi geri okunamadı.' unless File.binread(path)==raw.b
  ensure
    File.delete(temporary) if File.exist?(temporary)
  end
end

def user_accessory_register_selected
  model=Sketchup.active_model
  obj=model.selection.find{|e|e.is_a?(Sketchup::ComponentInstance)||e.is_a?(Sketchup::Group)}
  raise 'Önce kütüphaneye kaydedilecek bir Component veya Group seçin.' unless obj
  items=user_accessory_items_for_write   # K27: bozuk kütüphanede SKP kaydedilmeden durulur
  cats=USER_ACCESSORY_CATEGORIES.keys
  labels=USER_ACCESSORY_CATEGORIES.values
  defaults=[labels.first,obj.name.to_s.empty? ? (obj.respond_to?(:definition) ? obj.definition.name.to_s : 'Aksesuar') : obj.name.to_s,'','','','','']
  prompts=['Aksesuar türü','Kütüphane adı','Üretici','Model / Tip','Kapasite / SWL (t)','EA (kNm)','RF (kN)']
  lists=[labels.join('|'),'','','','','','']
  ans=UI.inputbox(prompts,defaults,lists,'Aksesuar Kütüphaneme Tanıt')
  raise 'İşlem iptal edildi.' unless ans
  category=cats[labels.index(ans[0].to_s) || 0]
  name=ans[1].to_s.strip
  raise 'Kütüphane adı boş olamaz.' if name.empty?
  id=SecureRandom.uuid
  safe=name.gsub(/[^0-9A-Za-zÀ-ž_-]+/,'_')[0,60]
  path=File.join(user_accessory_library_dir,"#{safe}_#{id[0,8]}.skp")
  definition=obj.is_a?(Sketchup::ComponentInstance) ? obj.definition : obj.entities.parent
  raise 'Seçili nesnenin ComponentDefinition bilgisi alınamadı.' unless definition.respond_to?(:save_as)
  ok=definition.save_as(path)
  raise 'SketchUp component dosyası kaydedilemedi.' unless ok && File.exist?(path)
  item={'id'=>id,'name'=>name,'category'=>category,'category_name'=>USER_ACCESSORY_CATEGORIES[category],
        'manufacturer'=>ans[2].to_s.strip,'model'=>ans[3].to_s.strip,'capacity'=>ans[4].to_s.strip,
        'energy'=>ans[5].to_s.strip,'reaction'=>ans[6].to_s.strip,'file'=>path,'created_at'=>Time.now.strftime('%Y-%m-%d %H:%M')}
  items << item; user_accessory_write(items); item
end

def user_accessory_place(id)
  item=user_accessory_items.find{|x|x['id'].to_s==id.to_s}
  raise 'Kütüphane kaydı bulunamadı.' unless item
  raise 'Kayıtlı SKP dosyası bulunamadı. Kütüphane kaydını yeniden oluşturun.' unless File.exist?(item['file'].to_s)
  model=Sketchup.active_model
  definition=model.definitions.load(item['file'].to_s)
  raise 'Kütüphane modeli yüklenemedi.' unless definition
  model.start_operation('Kütüphaneden Aksesuar Yerleştir',true)
  begin
    inst=model.active_entities.add_instance(definition,Geom::Transformation.new)
    inst.name=item['name'].to_s
    inst.set_attribute(DICT,'element_type','accessory')
    inst.set_attribute(DICT,'element_uid',SecureRandom.uuid)
    inst.set_attribute(DICT,'accessory_category',item['category'].to_s)
    inst.set_attribute(DICT,'accessory_type',item['name'].to_s)
    inst.set_attribute(DICT,'manufacturer',item['manufacturer'].to_s)
    inst.set_attribute(DICT,'catalog_model',item['model'].to_s)
    inst.set_attribute(DICT,'capacity_t',item['capacity'].to_f) unless item['capacity'].to_s.empty?
    inst.set_attribute(DICT,'energy_kNm',item['energy'].to_f) unless item['energy'].to_s.empty?
    inst.set_attribute(DICT,'reaction_kN',item['reaction'].to_f) unless item['reaction'].to_s.empty?
    inst.set_attribute(DICT,'user_library_id',item['id'].to_s)
    mst_assign_tag(inst,model) if respond_to?(:mst_assign_tag)
    model.commit_operation
  rescue
    model.abort_operation; raise
  end
  model.selection.clear; model.selection.add(inst); model.active_view.zoom(inst); true
end

def user_accessory_delete(id)
  items=user_accessory_items_for_write
  item=items.find{|x|x['id'].to_s==id.to_s}
  raise 'Kütüphane kaydı bulunamadı.' unless item
  File.delete(item['file'].to_s) if File.exist?(item['file'].to_s)
  items.reject!{|x|x['id'].to_s==id.to_s}; user_accessory_write(items); true
end

def show_accessories
 if @accessory_dialog && @accessory_dialog.visible?;@accessory_dialog.bring_to_front;return;end
 d=mst_html_dialog('accessories',dialog_title:'Marine Accessories BIM • Ekipman, QTO ve BOQ',preferences_key:'MAG_MST_Accessories',width:1450,height:920,resizable:true)
 @accessory_dialog=d
 d.set_file(File.join(__dir__,'accessories.html'))
 d.add_action_callback('accessory_action') do |_,action,json|
  begin
   p=JSON.parse(json||'{}');model=Sketchup.active_model
   if action=='load'
    lib=JSON.parse(File.read(File.join(__dir__,'marine_equipment_library.json'),encoding:'UTF-8'))
    d.execute_script("accessoryLoaded(#{JSON.generate({rows:accessory_rows,model_token:model.object_id.to_s,library:lib,user_library:user_accessory_items})})")
   else
    raise 'Aktif proje değişti. Yenile düğmesiyle modelden okuyun.' unless p['model_token']==model.object_id.to_s
    if action=='library_register'
     item=user_accessory_register_selected
     d.execute_script("userLibraryUpdated(#{JSON.generate({items:user_accessory_items,message:"#{item['name']} kütüphaneye kaydedildi."})})")
     next
    elsif action=='library_place'
     user_accessory_place(p['id'])
     d.execute_script("userLibraryMessage(#{JSON.generate('Kütüphane aksesuarı modele yerleştirildi ve seçildi.')})")
     next
    elsif action=='library_delete'
     answer=UI.messagebox('Seçili aksesuarı kalıcı kullanıcı kütüphanesinden silmek istiyor musunuz?',MB_YESNO)
     if answer==IDYES
      user_accessory_delete(p['id']); d.execute_script("userLibraryUpdated(#{JSON.generate({items:user_accessory_items,message:'Kütüphane kaydı silindi.'})})")
     end
     next
    end
    raise 'Bilinmeyen işlem.' unless %w[save mapping place].include?(action)
    rows=accessory_validate(p['rows'])
    encoded=JSON.generate(rows)
    if model.get_attribute(DICT,ACCESSORY_KEY,'[]')!=encoded
     model.start_operation('Aksesuar Çizelgesini Kaydet',true)
     begin
      model.set_attribute(DICT,ACCESSORY_KEY,encoded);model.commit_operation
     rescue;model.abort_operation;raise;end
    end
    if action=='place'
     row=rows.find{|r|r['id']==p['row_id']}
     raise 'Yerleştirilecek aksesuar satırı bulunamadı.' unless row
     result=accessory_place_on_selected_edge(row,p['spacing'])
     d.execute_script("accessoryPlaced(#{JSON.generate(result)})")
    else
     d.execute_script("accessorySaved(#{JSON.generate(p['revision'])})")
     show_boq_mapping if action=='mapping'
    end
   end
  rescue=>e;d.execute_script("accessoryError(#{JSON.generate(e.message)})");end
 end
 d.show
end
end
end
