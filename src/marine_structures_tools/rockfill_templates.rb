# frozen_string_literal: true
module MAG
module MarineStructuresTools
 RF_TEMPLATE_SCHEMA='mst.rf02.templates.v1'.freeze
 def rf_template_code(value)
  raise 'Şablonda malzeme kodu geçersiz.' unless value.is_a?(String) && !value.strip.empty? && value.size<=80
  value.strip
 end
 def rf_template_spec(raw)
  raise 'Tip şablonu nesne olmalı.' unless raw.is_a?(Hash)
  name=raw['name'].to_s.strip;raise 'Tip adı 1–120 karakter olmalı.' unless name.size.between?(1,120)
  spec={'name'=>name,'mode'=>raw['mode']}
  if spec['mode']=='parametric'
   %w[crest width slope_left slope_right].each{|k|spec[k]=RockfillGeometry.number(raw.fetch(k))}
   layers=raw['layers'];raise 'Şablonda 1–30 tabaka gerekli.' unless layers.is_a?(Array) && layers.size.between?(1,30)
   spec['layers']=layers.each_with_index.map do |l,i|
    raise 'Tabaka tanımı geçersiz.' unless l.is_a?(Hash)
    x={'code'=>rf_template_code(l['code'])};raise 'Beton düşümü parametrik tabaka olamaz.' if x['code']=='__CONCRETE__'
    x['thickness']=RockfillGeometry.number(l.fetch('thickness')) if i<layers.size-1;x
   end
   RockfillGeometry.parametric(spec,[[[-100,spec['crest']-100],[100,spec['crest']-100]]])
  elsif spec['mode']=='portable_faces'
   parts=raw['parts'];raise 'Şablonda 1–100 kapalı bölge gerekli.' unless parts.is_a?(Array) && parts.size.between?(1,100)
   count=0
   spec['parts']=parts.map do |part|
    raise 'Bölge tanımı geçersiz.' unless part.is_a?(Hash)
    loops=part['loops'];raise 'Bölge 1–20 sınır içermeli.' unless loops.is_a?(Array) && loops.size.between?(1,20)
    clean=loops.map do |loop|
     raise 'Sınır 3–200 köşe içermeli.' unless loop.is_a?(Array) && loop.size.between?(3,200)
     points=loop.map do |p|
      raise 'Kesit noktası [ofset, kot] olmalı.' unless p.is_a?(Array) && p.size==2
      p.map{|v|RockfillGeometry.number(v)}
     end
     count+=points.size;raise 'Şablon en fazla 2000 köşe içerebilir.' if count>2000
     raise 'Şablonda sıfır alanlı veya tekrarlı sınır var.' if points.uniq.size!=points.size || RockfillGeometry.polygon_area(points).abs<1e-9
     edges=RockfillGeometry.edges(points)
     edges.each_with_index{|(a,b),i|edges.each_with_index{|(c,d),j|raise 'Şablon sınırı kendini kesiyor.' if j>i+1 && !(i==0 && j==edges.size-1) && RockfillGeometry.segments_touch(a,b,c,d)}}
     points
    end
    clean[1..-1].each{|hole|raise 'Şablon boşluğu dış sınırdan çıkıyor.' unless hole.all?{|p|RockfillGeometry.inside_polygon(p,clean.first)}}
    clean.each_with_index do |a,i|
     clean[i+1..-1].each do |b|
      raise 'Şablon sınırları birbirine değiyor.' if RockfillGeometry.edges(a).any?{|u,v|RockfillGeometry.edges(b).any?{|x,y|RockfillGeometry.segments_touch(u,v,x,y)}}
      raise 'Şablon boşlukları iç içe.' if i>0 && (RockfillGeometry.inside_polygon(a.first,b)||RockfillGeometry.inside_polygon(b.first,a))
     end
    end
    {'code'=>rf_template_code(part['code']),'loops'=>clean}
   end
   points=spec['parts'].flat_map{|p|p['loops'].flatten(1)};lo,hi=points.map(&:first).minmax;bottom=points.map(&:last).min-1
   areas=RockfillGeometry.section(spec['parts'],[[[lo-1,bottom],[hi+1,bottom]]])['areas']
   raise 'Şablonda net taş alanı yok.' unless areas.values.sum>1e-9
  else
   raise 'Şablon yöntemi desteklenmiyor.'
  end
  spec
 end
 def rf_template_materials!(spec)
  codes=(spec['mode']=='parametric' ? spec['layers'] : spec['parts']).map{|x|x['code']}.uniq-['__CONCRETE__']
  bad=codes.reject{|code|rockfill_library.count{|m|m['code']==code}==1}
  raise 'Hedef malzeme kütüphanesinde tek kayıt gerekli: '+bad.join(', ') unless bad.empty?
 end
 def rf_templates_document(state)
  types=state['types'].values.map do |spec|
   raw=spec['mode']=='faces' ? rf_live_faces(spec).merge('mode'=>'portable_faces','name'=>spec['name']) : spec
   rf_template_spec(raw)
  end
  raise 'Dışa aktarılacak 1–100 tip gerekli.' unless types.size.between?(1,100)
  {'schema'=>RF_TEMPLATE_SCHEMA,'units'=>'m','types'=>types}
 end
 def rf_templates_parse(text)
  raise 'Şablon dosyası en fazla 2 MB olabilir.' if text.bytesize>2*1024*1024
  data=JSON.parse(text.sub(/\A\uFEFF/,''),max_nesting:30)
  raise 'Şablon biçimi/sürümü veya birimi desteklenmiyor; metre gerekli.' unless data.is_a?(Hash) && data['schema']==RF_TEMPLATE_SCHEMA && data['units']=='m'
  types=data['types'];raise 'Dosyada 1–100 tip gerekli.' unless types.is_a?(Array) && types.size.between?(1,100)
  types.map{|raw|rf_template_spec(raw)}
 end
 def rf_live_templates_file(action,state,dialog)
  if action=='templates_export'
   text=JSON.pretty_generate(rf_templates_document(state))
   raise 'Şablon dosyası 2 MB sınırını aşıyor; tip sayısını azaltın.' if text.bytesize>2*1024*1024
   path=UI.savepanel('Tip Kesit Şablonlarını Kaydet',nil,'Alternatif02_Tip_Kesitleri.json');unless path;dialog.execute_script('rfLiveReportSaved("Şablon işlemi iptal edildi; model değiştirilmedi.")');return;end
   path+='.json' unless File.extname(path).downcase=='.json'
   File.write(path,text,mode:'w',encoding:'UTF-8')
   dialog.execute_script("rfLiveReportSaved(#{JSON.generate('Tip kesitleri kaydedildi: '+path)})")
  else
   path=UI.openpanel('Tip Kesit Şablonu Aç',nil,'JSON|*.json||');unless path;dialog.execute_script('rfLiveReportSaved("Şablon işlemi iptal edildi; model değiştirilmedi.")');return;end
   raise 'Şablon dosyası en fazla 2 MB olabilir.' if File.size(path)>2*1024*1024
   types=rf_templates_parse(File.read(path,encoding:'UTF-8'))
   dialog.execute_script("rfLiveTemplatesLoaded(#{JSON.generate(types)})")
  end
 end
end
end
