# frozen_string_literal: true
# Read explicit, already modelled net solids. Does not infer ambiguous section topology.
module MAG
module MarineStructuresTools
module SpecialSolidGeometry
 extend self
 G=RockfillGeometry
 def box(tris);(0..2).map{|i|tris.flatten(1).map{|p|p[i]}.minmax};end
 def overlap_box(a,b);3.times.all?{|i|a[i][1]>=b[i][0]-1e-8 && b[i][1]>=a[i][0]-1e-8};end
 def on_triangle(p,t)
  n=G.vcross(G.vsub(t[1],t[0]),G.vsub(t[2],t[0]));length=Math.sqrt(G.vdot(n,n));return false if length<1e-14
  return false if G.vdot(n,G.vsub(p,t[0])).abs>length*1e-8
  drop=(0..2).max_by{|i|n[i].abs};xy=lambda{|q|q.each_with_index.reject{|v,i|i==drop}.map(&:first)}
  a=t.map{|q|xy.call(q)};q=xy.call(p);v=G.edges(a).map{|u,w|G.cross(u,w,q)}
  v.all?{|x|x>=-1e-9} || v.all?{|x|x<=1e-9}
 end
 # Oriented solid angle handles enclosed cavities as well as disconnected shells.
 def winding(p,tris,bounds=nil)
  return 0.0 if bounds && 3.times.any?{|i|p[i]<bounds[i][0]-1e-8 || p[i]>bounds[i][1]+1e-8}
  total=0.0
  tris.each do |t|
   return nil if on_triangle(p,t)
   a,b,c=t.map{|q|G.vsub(q,p)};la,lb,lc=[a,b,c].map{|v|Math.sqrt(G.vdot(v,v))}
   total+=2*Math.atan2(G.vdot(a,G.vcross(b,c)),la*lb*lc+G.vdot(a,b)*lc+G.vdot(b,c)*la+G.vdot(c,a)*lb)
  end
  total/(4*Math::PI)
 end
 def inside(p,tris,bounds=nil)
  w=winding(p,tris,bounds);w.nil? ? nil : w.abs>0.5
 end
 def crossing(a,b)
  return false unless overlap_box(box([a]),box([b]))
  # Proper edge-through-face crossing; shared vertices/edges and coplanar contacts are allowed.
  [[a,b],[b,a]].any? do |edge_tri,face|
   n=G.vcross(G.vsub(face[1],face[0]),G.vsub(face[2],face[0]));len=Math.sqrt(G.vdot(n,n));next false if len<1e-14
   G.edges(edge_tri).any? do |u,v|
    d1=G.vdot(n,G.vsub(u,face[0]))/len;d2=G.vdot(n,G.vsub(v,face[0]))/len
    next false unless d1*d2<0 && d1.abs>1e-8 && d2.abs>1e-8
    f=d1/(d1-d2);p=3.times.map{|i|u[i]+f*(v[i]-u[i])};on_triangle(p,face)
   end
  end
 end
 def check(tris)
  raise 'Özel katı en fazla 6000 üçgen olabilir; modeli bölgelere ayırın.' if tris.size>6000
  volume=G.closed_mesh_volume(tris)
  tris.each do |t|
   n=G.vcross(G.vsub(t[1],t[0]),G.vsub(t[2],t[0]));raise 'Sıfır alanlı katı yüzeyi.' if G.vdot(n,n)<1e-20
  end
  indexed=tris.map{|t|[t,box([t])]}.sort_by{|t,b|b[0][0]}
  indexed.each_with_index do |(a,ab),i|
   (i+1...indexed.size).each do |j|
    c,cb=indexed[j];break if cb[0][0]>ab[0][1]+1e-8
    next unless overlap_box(ab,cb)
    raise 'Katı yüzeyleri kendiyle kesişiyor; önce model geometrisini düzeltin.' if crossing(a,c)
   end
  end
  # One representative per connected shell detects inverted independent shells
  # and nested solids that would otherwise add the same space twice.
  links=Hash.new{|h,k|h[k]=[]};tris.each_with_index{|t,i|t.each{|p|links[p.map{|v|v.round(7)}]<<i}}
  visited={};levels=[];bounds=box(tris);epsilon=[bounds.map{|lo,hi|hi-lo}.max*1e-6,1e-6].max
  tris.each_with_index do |t,i|
   next if visited[i]
   queue=[i];visited[i]=true
   until queue.empty?
    j=queue.pop;tris[j].each{|p|links[p.map{|v|v.round(7)}].each{|k|unless visited[k];visited[k]=true;queue<<k;end}}
   end
   mid=3.times.map{|k|t.sum{|p|p[k]}/3.0};n=G.vcross(G.vsub(t[1],t[0]),G.vsub(t[2],t[0]));len=Math.sqrt(G.vdot(n,n))
   [-1,1].each{|sign|w=winding(3.times.map{|k|mid[k]+sign*epsilon*n[k]/len},tris,bounds);levels<<w if w && w.abs>0.5}
  end
  raise 'Katının iç kabukları çakışıyor veya yönleri tutarsız; net katıyı düzeltin.' if levels.empty? || levels.any?{|w|w.abs>1.5} || (levels.any?{|w|w>0} && levels.any?{|w|w<0})
  volume
 end
 def disjoint!(a,b)
  ab=box(a);bb=box(b);return unless overlap_box(ab,bb)
  a.each{|t|b.each{|s|raise 'Malzeme katıları kesişiyor; ortak hacimleri modelde çıkarın.' if crossing(t,s)}}
  [[a,b,ab,bb],[b,a,bb,ab]].each do |own,other,ob,tb|
   own.flatten(1).uniq.each{|p|raise 'Malzeme katıları iç içe / çakışıyor; net katıları tanımlayın.' if inside(p,other,tb)}
   scale=ob.map{|lo,hi|hi-lo}.max;epsilon=[scale*1e-7,1e-7].max
   own.each do |t|
    mid=3.times.map{|i|t.sum{|p|p[i]}/3.0};n=G.vcross(G.vsub(t[1],t[0]),G.vsub(t[2],t[0]));len=Math.sqrt(G.vdot(n,n))
    [-1,1].each do |sign|
     p=3.times.map{|i|mid[i]+sign*epsilon*n[i]/len}
     raise 'Malzeme katıları ortak hacim içeriyor; net katıları tanımlayın.' if inside(p,own,ob) && inside(p,other,tb)
    end
   end
  end
 end
end
RF_SPECIAL_KEY='rockfill_special_solids_v1'.freeze
def rf_special_state
 value=JSON.parse(Sketchup.active_model.get_attribute(DICT,RF_SPECIAL_KEY,'{}'))
 raise 'Özel katı bağları bozuk.' unless value.is_a?(Hash) && value.all?{|k,v|k.is_a?(String) && v.is_a?(Integer)}
 value
end
def rf_special_qto(state=rf_special_state)
 raise 'Önce malzemeleri kapalı katılara bağlayın.' if state.empty?
 raise 'Aynı katı iki malzemeye bağlanamaz.' unless state.values.uniq.size==state.size
 solids=state.map do |code,id|
  root=rf_live_roots([id]).first
  raise 'Tek bir katı grup/bileşen gerekli.' unless root.is_a?(Sketchup::Group)||root.is_a?(Sketchup::ComponentInstance)
  tris=rf_live_surface([id],'surface');volume=SpecialSolidGeometry.check(tris)
  # A material must be an actual net solid. Nested material assemblies must be united/subtracted first.
  native=root.respond_to?(:manifold?) ? root.manifold? : false
  raise "#{code}: SketchUp kapalı katı denetimi geçmedi; iç grupları birleştirin, beton boşluklarını çıkarın." unless native
  {code:code,id:id,triangles:tris,volume:volume}
 end
 solids.each_with_index{|s,i|solids[i+1..-1].each{|t|SpecialSolidGeometry.disjoint!(s[:triangles],t[:triangles])}}
 lib=rockfill_library
 materials=solids.map do |s|
  found=lib.select{|m|m['code']==s[:code]};raise "#{s[:code]}: tek kütüphane kaydı gerekli." unless found.size==1
  m=found.first;density=RockfillGeometry.number(m['density']);raise 'Yoğunluk pozitif olmalı.' unless density>0
  ton=s[:volume]*density;raise 'Tonaj sonlu değil.' unless ton.finite?
  {code:s[:code],name:m['name'],density:density,volume_m3:s[:volume],tonnage_t:ton,entity_id:s[:id]}
 end
 {sections:[],intervals:[],materials:materials,total_volume_m3:materials.sum{|m|m[:volume_m3]},total_tonnage_t:materials.sum{|m|m[:tonnage_t]},source_label:'Alternatif-02 — modellenmiş net katılar',solid_count:solids.size}
end
def rf_special_report(q=rf_special_qto)
 rows=q[:materials].map{|m|'<tr>'+[m[:code],m[:name],m[:entity_id],format('%.3f',m[:volume_m3]),format('%.3f',m[:density]),format('%.3f',m[:tonnage_t])].map{|v|"<td>#{html_escape(v.to_s)}</td>"}.join+'</tr>'}.join
 '<h3>Alternatif-02 — Özel Katı Geometrisi</h3><p>Hesap yöntemi: modelde seçilmiş, beton boşlukları önceden çıkarılmış kapalı katıların hacmi. Kesitlerden otomatik bölünme/birleşme üretilmez. AEA ve Alternatif-01 bu toplama eklenmez. Kaynak geometri her hesapta yeniden okunur. Birimler m³ ve t.</p><table><tr><th>Kod</th><th>Malzeme</th><th>Model kaynak ID</th><th>Hacim m³</th><th>Yoğunluk t/m³</th><th>Tonaj t</th></tr>'+rows+"<tr><td colspan='3'>TOPLAM</td><td>#{format('%.3f',q[:total_volume_m3])}</td><td></td><td>#{format('%.3f',q[:total_tonnage_t])}</td></tr></table>"
end
def rf_special_send(message='')
 data={library:rockfill_library,bindings:rf_special_state,model_token:Sketchup.active_model.object_id.to_s,active:rockfill_source_selection['mode']=='special',message:message}
 @rf_special_dialog.execute_script("specialLoaded(#{JSON.generate(data)})")
end
def show_special_solids
 if @rf_special_dialog && @rf_special_dialog.visible?;@rf_special_dialog.bring_to_front;rf_special_send;return;end
 @rf_special_dialog=mst_html_dialog('special_solids',dialog_title:'Alternatif-02 — Özel Katı Geometrisi',preferences_key:'MAG_MST_SpecialSolids',width:1100,height:800,resizable:true)
 @rf_special_dialog.set_file(File.join(__dir__,'special_solids.html'))
 @rf_special_dialog.add_action_callback('special_action') do |_,action,json|
  begin
   p=JSON.parse(json||'{}');m=Sketchup.active_model;state=rf_special_state
   raise 'Proje değişti; Modelden Yenile kullanın.' unless action=='refresh' || p['model_token']==m.object_id.to_s
   case action
   when 'refresh';rf_special_send
   when 'calculate','activate'
    q=rf_special_qto(state)
    if action=='activate'
     m.start_operation('Özel Katı Miktar Kaynağı',true)
     begin;m.set_attribute(DICT,ROCKFILL_SOURCE_KEY,JSON.generate({'mode'=>'special'}));m.commit_operation;rescue;m.abort_operation;raise;end
    end
    rf_special_send(action=='activate' ? 'Metraj / keşif kaynağı: Alternatif-02 özel katılar.' : 'Hacimler güncel modelden hesaplandı.')
    @rf_special_dialog.execute_script("specialReport(#{JSON.generate(rf_special_report(q))})")
   when 'alt1'
    m.start_operation('Alternatif-01 Miktar Kaynağı',true)
    begin;m.set_attribute(DICT,ROCKFILL_SOURCE_KEY,JSON.generate({'mode'=>'alt1'}));m.commit_operation;rescue;m.abort_operation;raise;end
    rf_special_send('Alternatif-01 etkin.')
   when 'bind','remove'
    code=p.fetch('code');raise 'Malzeme kodu geçersiz.' unless rockfill_library.count{|r|r['code']==code}==1
    if action=='bind'
     roots=rf_live_selection;raise 'Ana modelde tek kapalı katı seçin.' unless roots.size==1 && (roots.first.is_a?(Sketchup::Group)||roots.first.is_a?(Sketchup::ComponentInstance))
     id=roots.first.persistent_id;state[code]=id;rf_special_qto(state)
    else;state.delete(code);end
    m.start_operation('Özel Katı Malzeme Bağı',true)
    begin;m.set_attribute(DICT,RF_SPECIAL_KEY,JSON.generate(state));m.commit_operation;rescue;m.abort_operation;raise;end
    rf_special_send('Bağlar kaydedildi. Kalıcılık için SKP dosyasını kaydedin.')
   else;raise 'Bilinmeyen işlem.'
   end
  rescue=>e;@rf_special_dialog.execute_script("specialError(#{JSON.generate(e.message)})");end
 end
 @rf_special_dialog.show
end
end
end
