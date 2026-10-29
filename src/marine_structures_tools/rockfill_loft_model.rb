# frozen_string_literal: true
module MAG
module MarineStructuresTools
def rf_live_create_loft(state,dialog)
 model=Sketchup.active_model
 raise 'Önce grup düzenleme modundan çıkın.' if model.active_path
 input=rf_live_input(state);result=rf_live_result(state,true)
 output=RockfillGeometry.loft_all(input,result)
 raise 'Üretilecek kapalı katı yok.' if output['pieces'].empty?
 count=output['pieces'].sum{|p|p['triangles'].size}
 raise '200000 yüzey sınırı aşıldı; bölgeyi ayırın veya aralığı büyütün.' if count>200000
 model.start_operation('Alternatif-02 Kapalı Katılar Oluştur',true)
 begin
  parent=model.entities.add_group;parent.name="ALT02 KATILAR #{Time.now.strftime('%Y%m%d %H%M%S')}"
  parent.set_attribute(DICT,'rf02_generated_snapshot',result['fingerprint'])
  output['pieces'].each do |piece|
   group=parent.entities.add_group;code=piece['code'];unit=piece['region']=='head' ? '° BAŞ' : 'm GÖVDE'
   group.name="#{code=='__EXCAVATION__' ? 'KAZI' : code} #{format('%.3f',piece['start'])}–#{format('%.3f',piece['end'])} #{unit}"
   group.set_attribute(DICT,RF_LIVE_MATERIAL,code)
   color=code.each_byte.sum;group.material=Sketchup::Color.new(70+color%150,70+(color*3)%150,70+(color*7)%150)
   piece['triangles'].each do |tri|
    pts=tri.map{|p|Geom::Point3d.new(*p.map{|v|v.m})};face=group.entities.add_face(pts)
    raise 'SketchUp küçük/dejenere yüzeyi oluşturamadı; daha geniş hesap aralığı deneyin.' unless face
    intended=(pts[1]-pts[0]).cross(pts[2]-pts[0]);face.reverse! if face.normal.dot(intended)<0
   end
   raise "#{group.name}: SketchUp kapalı katı doğrulaması geçmedi." unless group.manifold?
   native=group.volume*0.0254**3
   tolerance=[1e-5,piece['volume']*1e-6].max
   raise "#{group.name}: model hacmi ile hesap ağı uyuşmuyor." unless (native-piece['volume']).abs<=tolerance
  end
  geometry_hash=Digest::SHA256.hexdigest(JSON.generate(rf_live_surface([parent.persistent_id],'surface')))
  summary={'geometry_fingerprint'=>geometry_hash,'fingerprint'=>result['fingerprint'],'group_id'=>parent.persistent_id,'tapered_voids'=>output['tapered_voids'],'type_transition'=>input['type_transition'],'void_transition'=>input['void_transition'],'void_pieces'=>output['void_pieces'],'resampled_pairs'=>output['resampled_pairs'],'scope'=>output['scope'],'pieces'=>output['pieces'].size,'rows'=>output['totals'].map do |code,v|
   a=output['reference'][code]||0
   {'code'=>code,'solid_m3'=>v,'quantity_m3'=>a,'difference_m3'=>v-a,'difference_percent'=>a>0 ? 100*(v-a)/a : nil}
  end}
  if input['excavation']
   v=output['excavation_solid_m3'];a=output['excavation_reference_m3']
   summary['rows']<<{'code'=>'KAZI (taştan ayrı)','solid_m3'=>v,'quantity_m3'=>a,'difference_m3'=>v-a,'difference_percent'=>a>0 ? 100*(v-a)/a : nil}
  end
  state['loft_summary']=summary
  state['last_result']=result.merge('sections'=>result['sections'].map{|s|s.reject{|k,v|k=='cells'}})
  model.set_attribute(DICT,RF_LIVE_KEY,JSON.generate(state));model.commit_operation
  model.selection.clear;model.selection.add(parent);model.active_view.zoom(parent)
 rescue
  model.abort_operation;raise
 end
 rf_live_send(dialog,state,'Kapalı katılar oluşturuldu. Malzeme/aralık grupları anlık geometri kopyasıdır; BOQ kaynağı değiştirilmedi.')
end
end
end
