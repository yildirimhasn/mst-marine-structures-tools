# frozen_string_literal: true
require 'json'
require 'securerandom'
require_relative 'column_geometry'
require_relative 'jet_grout_union'
module MAG
module MarineStructuresTools
JG_TYPES='jet_grout_types_v1'.freeze
def jg_defaults
 {'type_id'=>'JG-01','diameter'=>800,'top'=>0,'bottom'=>-10,'drill_top'=>0,'system'=>'single','enabled'=>true,'cement_kg_m'=>'','grout_l_m'=>'','steel_kg'=>'','color'=>'#9B83CF','project'=>'','ano'=>'','axis'=>''}
end
def jg_validate(raw)
 raise 'Jet grout verisi geçersiz.' unless raw.is_a?(Hash)
 d=jg_defaults.merge(raw)
 %w[diameter top bottom drill_top cement_kg_m grout_l_m steel_kg].each do |k|
  if %w[cement_kg_m grout_l_m steel_kg].include?(k) && (d[k].nil? || d[k].to_s.strip.empty?);d[k]=nil;next;end
  d[k]=Float(d[k].to_s.tr(',','.'));raise "#{k}: sonlu sayı girin." unless d[k].finite?
 end
 raise 'Tip kodu boş olamaz.' if d['type_id'].to_s.strip.empty?
 d['type_id']=d['type_id'].to_s.strip
 raise 'Çap ve kolon boyu pozitif olmalı; delgi başlangıcı kolon üst kotundan aşağıda olamaz.' unless d['diameter']>0 && d['top']>d['bottom'] && d['drill_top']>=d['top']
 raise 'Tüketim ve çelik miktarı negatif olamaz.' if %w[cement_kg_m grout_l_m steel_kg].any?{|k|d[k] && d[k]<0}
 raise 'Jet sistemi geçersiz.' unless %w[single double triple].include?(d['system'])
 raise 'Var/Yok seçimi geçersiz.' unless [true,false].include?(d['enabled'])
 raise 'Renk geçersiz.' unless d['color'].to_s.match?(/\A#[0-9a-fA-F]{6}\z/)
 d
end
def jg_metrics(d)
 len=d['top']-d['bottom'];on=d['enabled'] ? 1.0 : 0.0
 result={length:len*on,drilling:(d['drill_top']-d['bottom'])*on,volume:Math::PI*(d['diameter']/1000.0)**2/4*len*on,cement:d['cement_kg_m'] && len*d['cement_kg_m']/1000*on,grout:d['grout_l_m'] && len*d['grout_l_m']/1000*on,steel:d['steel_kg'] && d['steel_kg']/1000*on}
 raise 'Jet grout miktarı sayısal sınırı aşıyor.' unless result.values.compact.all?{|v|v.finite?}
 result
end
# v0.51.5 P5: dünya dönüşümü yalnız jet grout öğesinde hesaplanır: parent (başlangıç dünyası) üzerine ata kapsayıcılar ve öğe
# kökten aynı sırayla, aynı formülle çarpılır → eski düğüm düğüm hesapla bit düzeyinde aynı. Gezinti kapsamı değişmedi.
def jg_walk(entities)
 mst_column_walk(entities,'jet_grout','jet_grout_data',:jg_validate)
end
# v0.51.5 P5: okuma batch'inde (mst_read_batch) sonuç batch boyunca bir kez hesaplanır; hata önbelleğe alınmaz (sonraki çağrı yeniden
# gezer ve aynı hatayı verir). Yazma batch'inde ve batch dışında eskisi gibi. Her çağrı yeni dizi alır; geçersiz öğe süzülür.
def jg_elements
 rb=@mst_read_batch_on
 c=@mst_jg_elements_cache
 return c[:list].select(&:valid?) if rb && c && c[:rb]==rb
 list=jg_walk(Sketchup.active_model.entities)
 @mst_jg_elements_cache={rb:rb,list:list.dup.freeze} if rb
 list
end
def jg_net_ground_volume
 columns=[]
 mst_column_walk(Sketchup.active_model.entities,'jet_grout','jet_grout_data',:jg_validate) do |d,world|
  next unless d['enabled']
  point=world.origin
  columns << [point.x.to_m,point.y.to_m,d['diameter']/2000.0,d['bottom'],d['top']]
 end
 JetGroutUnion.volume(columns)
end
def jg_rows
 jg_elements.group_by{|e|e.get_attribute(DICT,'jet_grout_data','{}')}.map do |raw,els|
  d=jg_validate(JSON.parse(raw));q=jg_metrics(d)
  {data:d,count:els.size,active_count:d['enabled'] ? els.size : 0,quantities:q.transform_values{|v|v && v*els.size}}
 end
end
def jg_write(group,data,x,y)
 d=jg_validate(data);group.entities.clear!
 if d['enabled']
  edges=group.entities.add_circle(ORIGIN,Z_AXIS,(d['diameter']/2).mm,64);face=group.entities.add_face(edges)
  raise 'Jet grout yüzeyi oluşturulamadı.' unless face
  face.reverse! if face.normal.z<0;face.pushpull(-(d['top']-d['bottom']).m)
 else
  group.entities.add_cpoint(ORIGIN) # Keep a persistent hidden marker for Var/Yok restoration.
 end
 group.transformation=Geom::Transformation.translation([x,y,d['top'].m]);group.hidden=!d['enabled']
 group.name="#{d['type_id']} · Jet Grout Ø#{d['diameter']}"
 group.material=material_for(Sketchup.active_model,"MAG Jet Grout #{d['color']}",d['color'])
 {'element_type'=>'jet_grout','element_uid'=>group.get_attribute(DICT,'element_uid',SecureRandom.uuid),'jet_grout_data'=>JSON.generate(d),'type_id'=>d['type_id'],'project'=>d['project'],'ano'=>d['ano'],'axis'=>d['axis']}.each{|k,v|group.set_attribute(DICT,k,v)}
end
class JetGroutPlacement
 def initialize(d);@model_token=Sketchup.active_model.object_id;@data=d;@ip=Sketchup::InputPoint.new;end
 def activate;Sketchup.status_text='Jet grout merkezi seçin; Esc ile bitirin.';end
 def onMouseMove(flags,x,y,v);@ip.pick(v,x,y);v.invalidate;end
 def draw(v);@ip.draw(v) if @ip.valid?;end
 def onLButtonDown(flags,x,y,v)
  @ip.pick(v,x,y);return unless @ip.valid?;m=Sketchup.active_model
  return UI.messagebox('Proje değişti; Jet Grout penceresini yenileyin.') unless m.object_id==@model_token
  return UI.messagebox('Önce grup düzenleme modundan çıkın.') if m.active_path
  m.start_operation('Jet Grout Yerleştir',true)
  committed=false
  begin;g=m.entities.add_group;MarineStructuresTools.jg_write(g,@data,@ip.position.x,@ip.position.y);m.commit_operation;committed=true
  rescue=>e;m.abort_operation;UI.messagebox(e.message);end
  # 0.52.18 ADAY: işlem kapandıktan sonra arayüz yenileme hatası kapanmış işleme abort çağırmaz (bored_pile.rb ile aynı düzeltme)
  if committed
   begin;MarineStructuresTools.jg_send;rescue=>e;UI.messagebox("Jet Grout yerleştirildi; liste yenilenemedi: #{e.message}");end
  end
 end
 def onCancel(reason,v);Sketchup.active_model.select_tool(nil);end
end
def jg_sources
 jg_rows.select{|r|r[:active_count]>0}.flat_map do |r|
  d=r[:data];q=r[:quantities];prefix="JETGROUT:#{d['type_id']}:#{d['diameter']}:#{d['system']}"
  [['length','İyileştirme boyu','m'],['drilling','Delgi boyu','m'],['cement','Girilen çimento tüketimi','ton'],['grout','Girilen enjeksiyon hacmi','m³'],['steel','Girilen çelik','ton']].map do |key,name,unit|
   v=q[key.to_sym];next unless v && v>0
   {key:"#{prefix}:#{key}",name:"#{d['type_id']} Ø#{d['diameter']} Jet Grout · #{name}",unit:unit,quantity:v}
  end.compact
 end.group_by{|r|r[:key]}.map{|k,rs|rs.first.merge(quantity:rs.sum{|r|r[:quantity]})}
end
def jg_boq_rows(library,map)
 jg_sources.map{|r|map.key?(r[:key]) ? boq_mapped_row(r[:key],r[:unit],r[:quantity],map[r[:key]],library) : {code:'—',name:r[:name],unit:r[:unit],quantity:r[:quantity],unit_price:nil,total:nil,source:r[:key],status:'ÖBF EŞLEŞTİRİLMELİ',library_price:true}}
end
def jg_export_rows
 jg_rows.map do |r|
  d=r[:data];q=r[:quantities]
  [d['type_id'],d['diameter'],d['system'],d['top'],d['bottom'],d['drill_top'],r[:count],r[:active_count],q[:length],q[:drilling],q[:volume],q[:cement],q[:grout],q[:steel],d['project'],d['ano'],d['axis']]
 end
end
def jg_export_headers
 ['Tip','Çap mm','Sistem','Üst kot m','Alt kot m','Delgi üst kot m','Adet','Aktif adet','İyileştirme m','Delgi m','Nominal zemin m³','Çimento t','Enjeksiyon m³','Çelik t','Proje','Ano','Aks']
end
def jg_report_html
 rows=jg_export_rows;return '' if rows.empty?
 '<h3>Jet Grout — Bağımsız Metraj</h3><p>Net iyileştirilmiş zemin (model geneli): '+format('%.3f',jg_net_ground_volume)+' m³.</p><p>Nominal zemin hacmi geometrik kolon toplamıdır; çakışmalar düşülmez. Beton hacmi değildir. Çimento, enjeksiyon ve çelik kullanıcı tüketim girdileridir. Boş alan belirtilmemiştir.</p><table><tr>'+jg_export_headers.map{|h|"<th>#{html_escape(h)}</th>"}.join+'</tr>'+rows.map{|row|'<tr>'+row.map{|v|"<td>#{v.nil? ? '—' : html_escape(v.is_a?(Float) ? format('%.3f',v) : v.to_s)}</td>"}.join+'</tr>'}.join+'</table>'
end
def jg_send(message='')
 return unless @jg_dialog
 m=Sketchup.active_model
 @jg_dialog.execute_script("jgLoaded(#{JSON.generate({types:JSON.parse(m.get_attribute(DICT,JG_TYPES,'{}')),defaults:jg_defaults,rows:jg_rows,net_ground_m3:jg_net_ground_volume,model_token:m.object_id.to_s,message:message})})")
end
def show_jet_grout
 if @jg_dialog && @jg_dialog.visible?;@jg_dialog.bring_to_front;jg_send;return;end
 @jg_dialog=mst_html_dialog('jet_grout',dialog_title:'Jet Grout · Tip, Model ve Metraj',preferences_key:'MAG_MST_JetGrout',width:1380,height:900,resizable:true)
 @jg_dialog.set_file(File.join(__dir__,'jet_grout.html'))
 mst_register_model_preview(@jg_dialog, 'jet')
 @jg_dialog.add_action_callback('jg_action') do |_,action,json|
  begin
   p=JSON.parse(json||'{}');m=Sketchup.active_model
   raise 'Proje değişti; Modelden Yenile kullanın.' unless action=='refresh' || p['model_token']==m.object_id.to_s
   case action
   when 'refresh';jg_send
   when 'mapping';show_boq_mapping
   when 'read'
    e=m.selection.to_a;raise 'Tek jet grout grubu seçin.' unless e.size==1 && e.first.get_attribute(DICT,'element_type')=='jet_grout'
    @jg_dialog.execute_script("jgEdit(#{JSON.generate(jg_validate(JSON.parse(e.first.get_attribute(DICT,'jet_grout_data'))))})")
   when 'save','place','update'
    d=jg_validate(p.fetch('data'));raise 'Ana model düzeyine çıkın.' if m.active_path
    if action=='place'
     raise 'Yerleştirmek için Var seçin.' unless d['enabled'];m.select_tool(JetGroutPlacement.new(d))
    else
     targets=action=='update' ? m.selection.to_a : []
     raise 'Yalnız kilitsiz jet grout grupları seçin.' if action=='update' && (targets.empty? || targets.any?{|e|!e.is_a?(Sketchup::Group) || e.locked? || e.get_attribute(DICT,'element_type')!='jet_grout'})
     m.start_operation('Jet Grout Tip / Geometri Güncelle',true)
     begin
      types=JSON.parse(m.get_attribute(DICT,JG_TYPES,'{}'));types[d['type_id']]=d;m.set_attribute(DICT,JG_TYPES,JSON.generate(types))
      targets.each{|e|o=e.transformation.origin;jg_write(e,d,o.x,o.y)};m.commit_operation
     rescue;m.abort_operation;raise;end
     jg_send('Kaydedildi. Kalıcılık için SKP dosyasını kaydedin.')
    end
   else;raise 'Bilinmeyen işlem.'
   end
  rescue=>e;@jg_dialog.execute_script("jgError(#{JSON.generate(e.message)})");end
 end
 @jg_dialog.show
end
end
end
