# frozen_string_literal: true
# v0.47.4 LB2 — Kazık numaraları modelde (sabit 3B yazı) + numarayla eleman bulma.
#  · Numara, yapının üstüne yatay "yapıştırılmış" düz yazıdır (metre cinsinden sabit boy): yaklaşınca büyür, uzaklaşınca
#    küçülür, döndürünce kaymaz. Kazığın tam plan konumunda, en üst BK / döşeme kotunun 5 cm üstünde.
#  · Bütün numaralar tek bir "MST Kazık Numaraları" grubundadır; hiçbir elemanın içine girmez, eleman tipi yoktur →
#    hacim / kalıp / çelik / metraj / BOQ değişmez. Tag "MST | ETİKET | KAZIK". Kaldırınca hiçbir iz kalmaz. Tek Geri Al.
require 'json'
module MAG
module MarineStructuresTools

MST_LABEL_DICT='MAG_MST_Label'.freeze
MST_LABEL_TAG='MST | ETİKET | KAZIK'.freeze
MST_LABEL_PILE_TYPES=%w[steel_pipe_pile bored_pile].freeze
MST_LABEL_TOP_TYPES=%w[head_beam deck_slab crown_wall flat_precast channel_precast crane_precast].freeze

# 0.47.3'ün ekran yazıları (varsa temizlemek için)
def mst_label_texts(model=Sketchup.active_model)
 model.entities.grep(Sketchup::Text).select{|t|t.valid? && t.get_attribute(MST_LABEL_DICT,'kind','').to_s=='pile'}
end
def mst_label_groups(model=Sketchup.active_model)
 model.entities.grep(Sketchup::Group).select{|g|g.valid? && g.get_attribute(MST_LABEL_DICT,'kind','').to_s=='pile_labels'}
end
def mst_label_items(model=Sketchup.active_model)
 mst_label_groups(model).flat_map{|g|g.entities.grep(Sketchup::Group).select{|x|x.get_attribute(MST_LABEL_DICT,'kind','').to_s=='pile_label'}}
end
def mst_label_count(model=Sketchup.active_model);mst_label_items(model).length;end
def mst_label_pile_id(p)
 id=p.get_attribute(DICT,'pile_id','').to_s.strip
 id.empty? ? element_visible_id(p).to_s : id
end
def mst_label_structure(p)
 [p.get_attribute(DICT,'ano',''),p.get_attribute(DICT,'structure','')].map(&:to_s).find{|x|!x.strip.empty?}.to_s
end
# kazığın plan konumu (m): global_x_m / global_y_m; yoksa kutunun merkezi
def mst_label_xy(p)
 gx=p.get_attribute(DICT,'global_x_m',nil);gy=p.get_attribute(DICT,'global_y_m',nil)
 return [gx.to_f,gy.to_f] unless gx.nil? || gy.nil? || gx.to_s.strip.empty? || gy.to_s.strip.empty?
 c=p.bounds.center
 [c.x.to_f*0.0254,c.y.to_f*0.0254]
end
# yazı kotu: modeldeki en yüksek BK / döşeme / prekast / kronman üst kotu + 5 cm (yoksa kazık üstü + 5 cm)
def mst_label_z(all,piles)
 tops=all.select{|e|MST_LABEL_TOP_TYPES.include?(e.get_attribute(DICT,'element_type','').to_s)}.map{|e|e.get_attribute(DICT,'top_elevation_m',nil)}.compact.map(&:to_f)
 tops+=piles.map{|p|p.get_attribute(DICT,'top_elevation_m',nil)}.compact.map(&:to_f)
 (tops.max || 0.0)+0.05
end
# yazı boyu (m): en yakın iki kazık arası × 0.22, 0.25–0.80 m arası (komşu numaralar üst üste binmez)
def mst_label_height(plan)
 d=nil
 plan.each_with_index do |a,i|
  plan[(i+1)..-1].each{|b|x=Math.hypot(a[:x]-b[:x],a[:y]-b[:y]);d=x if x>0.05 && (d.nil? || x<d)}
 end
 return 0.5 if d.nil?
 [[d*0.22,0.25].max,0.8].min
end
def mst_label_plan(model=Sketchup.active_model)
 all=[];collect_elements(model.entities,all)
 piles=all.select{|e|MST_LABEL_PILE_TYPES.include?(e.get_attribute(DICT,'element_type','').to_s)}.uniq
 z=mst_label_z(all,piles)
 dup=piles.group_by{|p|mst_label_pile_id(p)}.select{|_,v|v.map{|p|mst_label_structure(p)}.uniq.length>1}.keys
 plan=piles.map do |p|
  id=mst_label_pile_id(p)
  st=mst_label_structure(p)
  x,y=mst_label_xy(p)
  {pile:p,text:(dup.include?(id) && !st.empty? ? "#{st} · #{id}" : id),x:x,y:y,z:z}
 end
 h=mst_label_height(plan);plan.each{|r|r[:h]=h}
 plan
end
def mst_label_material(model)
 m=model.materials['MST Etiket'] || model.materials.add('MST Etiket')
 m.color=Sketchup::Color.new(12,44,92) if m.respond_to?(:color=)
 m
end
def mst_labels_erase_all(model)
 old=mst_label_groups(model)+mst_label_texts(model)
 model.entities.erase_entities(old) unless old.empty?
 old
end
# oluştur / güncelle: eski numaralar silinir, güncel konumlarla yeniden yazılır (tek Geri Al)
def mst_labels_update!(model=Sketchup.active_model)
 plan=mst_label_plan(model)
 raise 'Modelde kazık yok.' if plan.empty?
 model.start_operation('MST Kazık Numaraları',true)
 begin
  mst_labels_build!(model,plan)
  model.commit_operation
 rescue
  model.abort_operation;raise
 end
 plan.length
end
# operasyon açmadan çizer (çağıran işlemin içinde kalır)
def mst_labels_build!(model,plan)
 begin
  mst_labels_erase_all(model)
  return 0 if plan.empty?
  tag=model.layers[MST_LABEL_TAG] || model.layers.add(MST_LABEL_TAG)
  tag.visible=true if tag.respond_to?(:visible=)
  parent=model.entities.add_group
  parent.name='MST Kazık Numaraları'
  parent.layer=tag
  parent.material=mst_label_material(model)
  parent.set_attribute(MST_LABEL_DICT,'kind','pile_labels')
  parent.set_attribute(MST_LABEL_DICT,'height_m',plan.first[:h])
  plan.each do |h|
   g=parent.entities.add_group
   ok=g.entities.add_3d_text(h[:text],TextAlignCenter,'Arial',true,false,h[:h].m,0.0,0.0,true,0.0)
   raise "Yazı oluşturulamadı: #{h[:text]}" unless ok
   c=g.bounds.center
   g.transform!(Geom::Transformation.translation(Geom::Vector3d.new(h[:x].m-c.x,h[:y].m-c.y,h[:z].m)))
   g.name=h[:text]
   g.set_attribute(MST_LABEL_DICT,'kind','pile_label')
   g.set_attribute(MST_LABEL_DICT,'pid',h[:pile].persistent_id)
  end
 end
 plan.length
end
def mst_labels_remove!(model=Sketchup.active_model)
 n=mst_label_count(model)+mst_label_texts(model).length
 return 0 if n.zero? && mst_label_groups(model).empty?
 model.start_operation('MST Kazık Numaralarını Kaldır',true)
 begin
  mst_labels_erase_all(model)
  tag=model.layers[MST_LABEL_TAG]
  model.layers.remove(tag) if tag && model.layers.respond_to?(:remove)
  model.commit_operation
 rescue
  model.abort_operation;raise
 end
 n
end

# numarayla bul: kazık / BK / prekast / döşeme … (büyük-küçük harf ve boşluk önemsiz; "P-56" = "P-056")
def mst_find_norm(s)
 s.to_s.upcase.gsub(/[\s\-_.\/·]+/,'').gsub(/(?<!\d)0+(?=\d)/,'')
end
def mst_find_elements(query,model=Sketchup.active_model)
 q=mst_find_norm(query);return [] if q.empty?
 all=[];collect_elements(model.entities,all)
 keys=%w[pile_id head_beam_id deck_id precast_id id]
 exact=all.select{|e|([element_visible_id(e)]+keys.map{|k|e.get_attribute(DICT,k,nil)}).compact.map{|v|mst_find_norm(v)}.include?(q)}
 return exact.uniq unless exact.empty?
 all.select{|e|([element_visible_id(e)]+keys.map{|k|e.get_attribute(DICT,k,nil)}).compact.any?{|v|mst_find_norm(v).include?(q)}}.uniq
end
def mst_find_and_select(query,model=Sketchup.active_model)
 hit=mst_find_elements(query,model)
 model.selection.clear
 hit.each{|e|model.selection.add(e) rescue nil}
 model.active_view.zoom(model.selection) unless hit.empty?
 hit
end
def mst_find_ui
 r=UI.inputbox(['Kazık / eleman numarası'],[@mst_last_find.to_s],'MST — Numarayla Bul')
 return unless r
 @mst_last_find=r[0].to_s
 hit=mst_find_and_select(@mst_last_find)
 if hit.empty?
  UI.messagebox("'#{@mst_last_find}' bulunamadı.\nNumarayı kontrol edin (ör. P-56, HB-YD-02-A1-BK-01).")
 elsif hit.length>1
  UI.messagebox("#{hit.length} eleman seçildi ve gösterildi:\n"+hit.first(12).map{|e|"  #{element_visible_id(e)} (#{mst_label_structure(e).empty? ? e.get_attribute(DICT,'element_type','') : mst_label_structure(e)})"}.join("\n"))
 end
 hit.length
end
def mst_labels_ui(on)
 if on
  n=mst_labels_update!
  UI.messagebox("#{n} kazığın numarası modele yazıldı (Tag: #{MST_LABEL_TAG}).\nNumaralar ayrı bir grupta düz yazıdır, hiçbir elemana dahil değildir; metraj değişmez. Kazık oluşturup güncelleyince ve aks / yapı taşıyınca kendiliğinden yenilenir; elle silip taşıdıysanız yeniden 'Göster / Güncelle'.\nGizlemek için Tags panelinden kapatın; tamamen silmek için 'Kazık Numaralarını Kaldır'.")
 else
  n=mst_labels_remove!
  UI.messagebox(n>0 ? "#{n} kazık numarası kaldırıldı." : 'Modelde kazık numarası yok.')
 end
 n
rescue => e
 UI.messagebox("Kazık numaraları: #{e.message}")
end

# ===================================================================== v0.47.5 PE1 — PE kaplama görünümü
# Kazığın PE kaplamalı bölümü (kazık başından aşağı "PE boyu" kadar) farklı renkte, kazığın 1 % dışında ince bir
# kılıf yüzeyi olarak gösterilir. Kılıflar tek bir "MST PE Kaplama Görünümü" grubundadır: kazığın içine girmez,
# eleman sayılmaz, taramaya girmez → PE m² dahil hiçbir metraj değişmez (PE metrajı yine π·D·L özniteliğinden).
# Kazık oluşturma / güncelleme sonrası (görünüm açıksa) kendiliğinden yenilenir. Renk: Materials → "MST PE Kaplama".
MST_PE_TAG='MST | GÖRÜNÜM | PE KAPLAMA'.freeze
MST_PE_COLOR=[46,125,50].freeze   # koyu yeşil
MST_VIEW_DICT='MAG_MST_View'.freeze   # yalnız görünüm bilgisi (metraj / tip / kimlik okumaz)

# PE üst kotu: boşsa kazık başı. s0 = kazık başından PE başlangıcına eksen boyunca mesafe (m)
def mst_pe_vz(p)
 mode=p.get_attribute(DICT,'orientation_mode','VERTICAL').to_s.upcase
 r=mode=='BATTERED' ? pile_batter_ratio(p.get_attribute(DICT,'batter_ratio',0)) : 0.0
 1.0/Math.sqrt(1.0+r*r)
end
def mst_pe_offset(p,top,len)
 v=p.get_attribute(MST_VIEW_DICT,'pe_top_elevation_m',nil)
 return {pe_top:top,s0:0.0} if v.nil? || v.to_s.strip.empty?
 pt=[v.to_f,top].min
 {pe_top:pt,s0:[(top-pt)/mst_pe_vz(p),0.0].max}
end

def mst_pe_groups(model=Sketchup.active_model)
 model.entities.grep(Sketchup::Group).select{|g|g.valid? && g.get_attribute(MST_LABEL_DICT,'kind','').to_s=='pe_visual'}
end
def mst_pe_items(model=Sketchup.active_model)
 mst_pe_groups(model).flat_map{|g|g.entities.grep(Sketchup::Group).select{|x|x.get_attribute(MST_LABEL_DICT,'kind','').to_s=='pe_sleeve'}}
end
def mst_pe_plan(model=Sketchup.active_model)
 all=[];collect_elements(model.entities,all)
 all.select{|p|p.get_attribute(DICT,'element_type','').to_s=='steel_pipe_pile'}.uniq.map do |p|
  next nil unless p.get_attribute(DICT,'pe_enabled','0').to_s=='1'
  d=p.get_attribute(DICT,'diameter_mm',0).to_f;len=p.get_attribute(DICT,'length_m',0).to_f
  pe=[[p.get_attribute(DICT,'pe_length_m',0).to_f,0.0].max,len].min
  top=p.get_attribute(DICT,'top_elevation_m',nil)
  next nil if d<=0 || pe<=1e-6 || top.nil?
  x,y=mst_label_xy(p)
  o=mst_pe_offset(p,top.to_f,len)
  pe=[pe,[len-o[:s0],0.0].max].min
  next nil if pe<=1e-6
  {pile:p,d_mm:d,pe_m:pe,top:top.to_f,pe_top:o[:pe_top],s0:o[:s0],x:x,y:y,
   orient:{'orientation_mode'=>p.get_attribute(DICT,'orientation_mode','VERTICAL').to_s,'batter_ratio'=>p.get_attribute(DICT,'batter_ratio',0),'azimuth_deg'=>p.get_attribute(DICT,'azimuth_deg',0)}}
 end.compact
end
def mst_pe_material(model)
 m=model.materials['MST PE Kaplama']
 unless m
  m=model.materials.add('MST PE Kaplama')
  m.color=Sketchup::Color.new(*MST_PE_COLOR) if m.respond_to?(:color=)
 end
 m
end
# operasyon açmadan çizer (çağıran işlemin içinde kalır)
def mst_pe_build!(model,plan)
 mst_pe_groups(model).each{|g|g.erase! if g.valid?}
 return 0 if plan.empty?
 tag=model.layers[MST_PE_TAG] || model.layers.add(MST_PE_TAG)
 parent=model.entities.add_group
 parent.name='MST PE Kaplama Görünümü'
 parent.layer=tag
 parent.material=mst_pe_material(model)
 parent.set_attribute(MST_LABEL_DICT,'kind','pe_visual')
 plan.each do |h|
  r=h[:d_mm]/2.0+[h[:d_mm]*0.01,6.0].max          # kazık yüzeyinin dışında, mm
  g=parent.entities.add_group
  c=g.entities.add_circle(ORIGIN,Z_AXIS,mm(r),SEG)
  f=g.entities.add_face(c);f.reverse! if f.normal.z<0
  f.pushpull(-m(h[:pe_m]))
  g.transform!(Geom::Transformation.translation([0,0,-m(h[:s0].to_f)])) if h[:s0].to_f>1e-9   # PE üst kotu kazık başının altındaysa
  g.entities.grep(Sketchup::Face).select{|x|x.normal.parallel?(Z_AXIS)}.each{|x|x.erase! if x.valid?}   # yalnız kılıf yüzeyi
  rot=pile_rotation_transform(h[:orient])[0]
  g.transform!(rot)
  g.transform!(Geom::Transformation.translation([m(h[:x]),m(h[:y]),m(h[:top])]))
  g.name="PE #{mst_label_pile_id(h[:pile])}"
  g.set_attribute(MST_LABEL_DICT,'kind','pe_sleeve')
  g.set_attribute(MST_LABEL_DICT,'pid',h[:pile].persistent_id)
  g.set_attribute(MST_LABEL_DICT,'pe_m',h[:pe_m])
 end
 plan.length
end
def mst_pe_update!(model=Sketchup.active_model)
 plan=mst_pe_plan(model)
 raise 'PE kaplamalı kazık yok (Kazık → Detaylar: Polietilen Kaplama = Var ve PE boyu > 0).' if plan.empty?
 model.start_operation('MST PE Kaplama Görünümü',true)
 begin
  n=mst_pe_build!(model,plan)
  model.commit_operation
 rescue
  model.abort_operation;raise
 end
 n
end
def mst_pe_remove!(model=Sketchup.active_model)
 gs=mst_pe_groups(model);return 0 if gs.empty?
 n=mst_pe_items(model).length
 model.start_operation('MST PE Kaplama Görünümünü Kaldır',true)
 begin
  gs.each{|g|g.erase! if g.valid?}
  tag=model.layers[MST_PE_TAG];model.layers.remove(tag) if tag && model.layers.respond_to?(:remove)
  model.commit_operation
 rescue
  model.abort_operation;raise
 end
 n
end
def mst_pe_ui(on)
 if on
  n=mst_pe_update!
  UI.messagebox("#{n} kazıkta PE kaplamalı bölüm renkli gösteriliyor (PE üst kotundan — tanımlı değilse kazık başından — aşağı PE boyu kadar).\nTag: #{MST_PE_TAG} · Renk: Materials → 'MST PE Kaplama'.\nYalnız görünümdür: kazık geometrisi ve hiçbir metraj (PE m² dahil) değişmez. Kazık oluşturup güncelleyince ve aks / yapı taşıyınca kendiliğinden yenilenir.")
 else
  n=mst_pe_remove!
  UI.messagebox(n>0 ? "#{n} kazığın PE görünümü kaldırıldı." : 'Modelde PE görünümü yok.')
 end
 n
rescue => e
 UI.messagebox("PE kaplama görünümü: #{e.message}")
end
# PE üst kotunu ayarla (seçili / PE'li bütün kazıklar) — tek Geri Al; görünüm açıksa yenilenir
def mst_pe_set_top!(piles,pe_top,model=Sketchup.active_model)
 raise 'Kazık seçilmedi.' if piles.empty?
 errs=[]
 unless pe_top.nil?
  piles.each do |p|
   top=p.get_attribute(DICT,'top_elevation_m',nil).to_f
   len=p.get_attribute(DICT,'length_m',0).to_f
   bot=top-len*mst_pe_vz(p)
   pid=mst_label_pile_id(p)
   errs << "#{pid}: PE üst kotu (#{format('%.2f',pe_top)}) kazık başının (#{format('%.2f',top)}) üstünde." if pe_top>top+1e-6
   errs << "#{pid}: PE üst kotu (#{format('%.2f',pe_top)}) kazık ucunun (#{format('%.2f',bot)}) altında." if pe_top<=bot+1e-6
  end
  raise "PE üst kotu uygulanamadı:\n"+errs.first(10).join("\n")+(errs.length>10 ? "\n… (+#{errs.length-10})" : '') unless errs.empty?
 end
 model.start_operation('MST PE Üst Kotu',true)
 begin
  piles.each do |p|
   if pe_top.nil?
    p.delete_attribute(MST_VIEW_DICT,'pe_top_elevation_m')
   else
    p.set_attribute(MST_VIEW_DICT,'pe_top_elevation_m',pe_top.to_f)
   end
  end
  mst_views_refresh!(model)
  model.commit_operation
 rescue
  model.abort_operation;raise
 end
 piles.length
end
def mst_pe_top_ui
 model=Sketchup.active_model
 sel=[];model.selection.to_a.each{|e|collect_elements([e],sel)} rescue nil
 sel=sel.select{|e|e.get_attribute(DICT,'element_type','').to_s=='steel_pipe_pile'}.uniq
 all=[];collect_elements(model.entities,all)
 pe_all=all.select{|e|e.get_attribute(DICT,'element_type','').to_s=='steel_pipe_pile' && e.get_attribute(DICT,'pe_enabled','0').to_s=='1'}.uniq
 scope_opts="Seçili kazıklar (#{sel.length})|PE'li bütün kazıklar (#{pe_all.length})"
 r=UI.inputbox(['Uygula','PE başlangıcı','PE üst kotu (m, mutlak)'],[sel.empty? ? scope_opts.split('|')[1] : scope_opts.split('|')[0],'Kazık başı',''],[scope_opts,'Kazık başı|Belirli kot',''],'MST — PE Üst Kotu')
 return unless r
 piles=r[0].start_with?('Seçili') ? sel : pe_all
 pe_top=nil
 if r[1]=='Belirli kot'
  pe_top=(Float(r[2].to_s.strip.tr(',','.')) rescue nil)
  raise 'PE üst kotu sayı olmalı (ör. 2.50 ya da -1.00).' if pe_top.nil?
 end
 n=mst_pe_set_top!(piles,pe_top,model)
 UI.messagebox("#{n} kazıkta PE başlangıcı: #{pe_top.nil? ? 'kazık başı' : format('%+.2f m',pe_top)}.\nPE boyu ve PE m² metrajı değişmez; yalnız renkli bölümün yeri değişir.#{mst_pe_groups(model).empty? ? "\nGörmek için 'PE Kaplama Görünümü'." : ''}")
 n
rescue => e
 UI.messagebox("PE üst kotu: #{e.message}")
end

# Görünümleri (kazık numaraları, PE) yenile — açık olanlar, çağıran işlemin içinde
def mst_views_refresh!(model=Sketchup.active_model)
 mst_labels_build!(model,mst_label_plan(model)) unless mst_label_groups(model).empty?
 mst_pe_build!(model,mst_pe_plan(model)) unless mst_pe_groups(model).empty?
 true
rescue => e
 puts "MST görünüm yenilenemedi: #{e.message}"
 false
end
# kazık oluştur / güncelle sonrası ve aks / yapı taşıma sonrası: açık görünümler aynı işlemin içinde yenilenir
if method_defined?(:mst_sync_pile_type_library)
 alias_method :mst_sync_pile_type_library_base_pe, :mst_sync_pile_type_library unless method_defined?(:mst_sync_pile_type_library_base_pe)
 def mst_sync_pile_type_library(model=Sketchup.active_model)
  r=mst_sync_pile_type_library_base_pe(model)
  mst_views_refresh!(model)
  r
 end
end
if method_defined?(:mst_apply_axis_move_plans)
 alias_method :mst_apply_axis_move_plans_base_vw, :mst_apply_axis_move_plans unless method_defined?(:mst_apply_axis_move_plans_base_vw)
 def mst_apply_axis_move_plans(plans)
  r=mst_apply_axis_move_plans_base_vw(plans)
  mst_views_refresh!(Sketchup.active_model)
  r
 end
end
if method_defined?(:mst_apply_structure_move_plans)
 alias_method :mst_apply_structure_move_plans_base_vw, :mst_apply_structure_move_plans unless method_defined?(:mst_apply_structure_move_plans_base_vw)
 def mst_apply_structure_move_plans(splans)
  r=mst_apply_structure_move_plans_base_vw(splans)
  mst_views_refresh!(Sketchup.active_model)
  r
 end
end

end
end
