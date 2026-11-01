# frozen_string_literal: true
require_relative 'axis_chain'
module MAG
module MarineStructuresTools
RF02_KEY='rockfill_geometry_setup_v1'.freeze
def rf02_setup(action,json,dialog)
 model=Sketchup.active_model
 data=JSON.parse(model.get_attribute(DICT,RF02_KEY,'{}'))
 if action=='axis'
  raise 'Grup düzenleme modundan çıkıp aks kenarlarını seçin.' if model.active_path
  edges=model.selection.grep(Sketchup::Edge)
  raise 'Açık ve kesintisiz aksın kenarlarını seçin.' if edges.empty?
  coords=AxisChain.order(edges.map{|e|e.vertices.map{|v|p=v.position;[p.x.to_m,p.y.to_m,p.z.to_m]}})
  length=coords.each_cons(2).sum{|a,b|Math.hypot(b[0]-a[0],b[1]-a[1])}
  raise 'Aksın plandaki uzunluğu sıfır.' unless length>0
  data['axis']={'points'=>coords,'plan_length_m'=>length,'edge_count'=>edges.length,'start_rule'=>'En küçük X/Y uç noktası'}
 elsif action=='save'
  request=JSON.parse(json);step=Float(request.fetch('step').to_s.tr(',','.'))
  raise 'Kesit aralığı pozitif olmalı.' unless step.finite? && step>0
  extra=request['extra'].to_s.split(/[;\s]+/).reject(&:empty?).map{|s|Float(s.tr(',','.'))}
  raise 'İlave istasyonlar negatif olamaz.' unless extra.all?{|x|x.finite?&&x>=0}
  length=data.dig('axis','plan_length_m')
  raise 'İlave istasyon aks boyunu aşıyor.' if length && extra.any?{|x|x>length}
  raise 'Çok fazla kesit; aralığı büyütün.' if length && length/step>10000
  data['step']=step;data['extra']=extra
 elsif action!='load'
  raise 'Bilinmeyen Alternatif-02 işlemi.'
 end
 unless action=='load'
  model.start_operation('Alternatif-02 Hazırlığını Kaydet',true)
  begin;model.set_attribute(DICT,RF02_KEY,JSON.generate(data));model.commit_operation;rescue;model.abort_operation;raise;end
 end
 length=data.dig('axis','plan_length_m');step=data['step']||5.0
 if length && length/step<=10000
  stations=(0..(length/step).floor).map{|i|i*step}+[length]+(data['extra']||[])
  distance=0.0;data['axis']['points'].each_cons(2){|a,b|distance+=Math.hypot(b[0]-a[0],b[1]-a[1]);stations<<distance}
  data['stations']=stations.select{|x|x<=length}.map{|x|x.round(6)}.uniq.sort
 end
 dialog.execute_script("rf02Loaded(#{JSON.generate(data)})")
rescue=>e
 dialog.execute_script("rf02Error(#{JSON.generate(e.message)})")
end
end
end
