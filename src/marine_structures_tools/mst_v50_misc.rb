# frozen_string_literal: true
# v0.50 — metraj / ayar ekleri
#  TP1 kaplama (topping) eğimi: en ince kalınlık + eğim % → ortalama kalınlık (tek yöne / sırttan iki yana)
#  SH2 sehpa metrajda ayrı satır (döşeme + dolfen; toplam değişmez)
#  AN1 aksesuar ankraj donatısı (baba, halka, kanca, merdiven, kedi yolu) → döşeme donatısına
#  MS1 malzeme sınıfları: proje beton sınıfı / donatı çeliği (B420C, B500C …) + seçili elemana; çap metrajında çelik sınıfı
#  RS2 pas payı eleman tipine göre (BK, dolfen başlığı, VK / BBK, döşeme, prekast, kanal prekastı)
require 'json'
module MAG
module MarineStructuresTools

MST_V50_RS_EXTRA={'cover_dolphin_mm'=>75.0,'cover_vk_mm'=>75.0,'cover_pk_mm'=>50.0,'chair_row'=>1}.freeze
MST_V50_RS_FIELDS=[['cover_dolphin_mm','Dolfen başlığı pas payı (mm)',20,120],['cover_vk_mm','Vinç / boylama kirişi pas payı (mm)',20,120],
 ['cover_pk_mm','Kanal prekastı pas payı (mm)',20,120],['chair_row','Sehpa metrajda ayrı satır (1 = evet, 0 = döşeme / dolfen içinde)',0,1]].freeze
MST_REBAR_GRADES=%w[B420C B500C B420B S420 S500].freeze

# elemana göre pas payı (mm): BK / dolfen / VK-BBK / döşeme / prekast / PK
def mst_rs_cover_for(e,model=Sketchup.active_model)
 t=e.get_attribute(DICT,'element_type','').to_s
 k=case t
  when 'head_beam'
   if %w[VK BBK].include?(e.get_attribute(DICT,'beam_role','').to_s) then 'cover_vk_mm'
   elsif (mst_hb_system(e,model)=='DOLFEN' rescue false) then 'cover_dolphin_mm'
   else 'cover_bk_mm' end
  when 'deck_slab' then 'cover_deck_mm'
  when 'channel_precast' then 'cover_pk_mm'
  when 'flat_precast','crane_precast' then 'cover_precast_mm'
  else 'cover_bk_mm'
 end
 v=mst_rs_get(k,model)
 (v.nil? ? (MST_V50_RS_EXTRA[k] || 50.0) : v).to_f
end

# ---------------------------------------------------------------- TP1 kaplama eğimi
# tip: 'TEK' (bir kenardan diğerine), 'SIRT' (ortadan iki yana); L: eğim doğrultusundaki genişlik
def mst_tp_avg(tmin,slope_pct,l,tip)
 s=slope_pct.to_f/100.0
 tip.to_s.upcase=='SIRT' ? tmin+s*l/4.0 : tmin+s*l/2.0
end
def mst_tp_width(d)
 b=d.bounds;f=39.37007874015748
 [b.width.to_f/f,b.height.to_f/f].min
end
def mst_tp_ui
 model=Sketchup.active_model
 ds=model.selection.to_a.select{|e|e.respond_to?(:get_attribute) && e.get_attribute(DICT,'element_type','').to_s=='deck_slab'}
 raise 'Döşeme(ler) seçin.' if ds.empty?
 d0=ds[0];cur=(JSON.parse(d0.get_attribute(DICT,'topping_slope_json','{}').to_s) rescue {})
 r=UI.inputbox(['En ince kalınlık (m)','Eğim (%)','Eğim doğrultusundaki genişlik (m; 0 = döşemenin dar kenarı)','Tip: TEK (tek yöne) / SIRT (ortadan iki yana)'],
  [(cur['tmin'] || d0.get_attribute(DICT,'topping_thickness_m',0.10)).to_s,(cur['slope'] || 1.0).to_s,(cur['l'] || 0).to_s,(cur['tip'] || 'TEK').to_s],"Kaplama Eğimi — #{ds.length} döşeme")
 return 0 unless r
 tmin=mst_v50_num(r[0],'En ince kalınlık',0.02,1.0);sl=mst_v50_num(r[1],'Eğim',0,10);l0=mst_v50_num(r[2],'Genişlik',0,500);tip=r[3].to_s.strip.upcase=='SIRT' ? 'SIRT' : 'TEK'
 rows=ds.map{|d|l=l0>0 ? l0 : mst_tp_width(d);[d,l,mst_tp_avg(tmin,sl,l,tip)]}
 txt=rows.first(8).map{|d,l,a|ar=d.get_attribute(DICT,'topping_area_m2',0).to_f;format('%s: genişlik %.2f m → ortalama %.3f m (en kalın %.3f) · %.2f m² → %.2f m³',element_visible_id(d),l,a,tip=='SIRT' ? tmin+sl/100.0*l/2 : tmin+sl/100.0*l,ar,ar*a)}.join("\n")
 return 0 unless UI.messagebox("Kaplama eğimi (#{tip=='SIRT' ? 'ortadan iki yana' : 'tek yöne'}, %#{sl}):\n#{txt}\n\nKaplama kalınlığı ortalamaya ayarlansın mı? (tek Geri Al)",MB_YESNO)==IDYES
 model.start_operation('MST Kaplama Eğimi',true)
 begin
  rows.each do |d,l,a|
   d.set_attribute(DICT,'topping_enabled','1')
   d.set_attribute(DICT,'topping_thickness_m',a)
   d.set_attribute(DICT,'topping_volume_m3',d.get_attribute(DICT,'topping_area_m2',0).to_f*a)
   d.set_attribute(DICT,'topping_slope_json',JSON.generate({'tmin'=>tmin,'slope'=>sl,'l'=>l,'tip'=>tip,'avg'=>a}))
  end
  model.commit_operation
 rescue
  model.abort_operation;raise
 end
 rows.length
rescue => ex
 UI.messagebox("Kaplama eğimi: #{ex.message}")
 0
end

# ---------------------------------------------------------------- SH2 sehpa satırı / AN1 aksesuar ankrajı
# BIM elemanın tablosundaki sehpa (CHAIR) ağırlığı, elemanın tonajına oranlı
def mst_v50_chair_kg(e)
 r=mst_element_rebar(e);return 0.0 unless r['source']=='BIM'
 sch=(JSON.parse(e.get_attribute(DICT,'rebar_schedule_json','').to_s) rescue nil)
 return 0.0 unless sch.is_a?(Hash)
 tot=sch.values.sum{|v|v.is_a?(Hash) ? v['kg'].to_f : 0.0};ch=sch.select{|k,_|k.to_s=~/CHAIR|SEHPA/i}.values.sum{|v|v['kg'].to_f}
 tot>0 ? r['kg']*ch/tot : 0.0
end
def mst_v50_acc_anchor_kg
 # v0.51.5 K21 (S8): okuma hatası sessiz 0 kg değil — konsola yazılır; Model Kontrolü aynı okumayı HATA olarak gösterir
 rows=begin
  accessory_rows
 rescue => ex
  warn("MST aksesuar ankraj donatısı: #{ex.message}");[]
 end
 rows.sum{|r|r['quantity'].to_f*r['anchor_rebar_kg'].to_f}
end
# mst_boq_rebar_breakdown satırlarına: sehpa ayrı satır (taşındığı satırdan düşülür) + aksesuar ankrajı
def mst_v50_breakdown_extras(rows,all)
 if mst_rs_get('chair_row').to_s!='0'
  tot=0.0
  rows.each do |r|
   next unless %w[head_beam deck_slab].include?(r[:key].to_s)
   kg=all.select{|e|e.get_attribute(DICT,'element_type','').to_s==r[:key].to_s}.sum{|e|mst_v50_chair_kg(e)}
   next if kg<=0
   r[:kg]-=kg;tot+=kg
  end
  rows << {key:'chair',name:'Sehpa (döşeme + dolfen)',count:0,kg:tot,label:'BIM'} if tot>0
 end
 an=mst_v50_acc_anchor_kg
 if an>0
  i=rows.index{|r|r[:key].to_s=='deck_slab'} || rows.length-1
  rows.insert(i+1,{key:'acc_anchor',name:'Döşeme — aksesuar ankraj donatısı',count:0,kg:an,label:'aksesuar çizelgesi'})
 end
 rows
rescue
 rows
end

# ---------------------------------------------------------------- MS1 malzeme sınıfları
def mst_rebar_grade(e,model=Sketchup.active_model)
 g=e.get_attribute(DICT,'rebar_grade','').to_s
 g=(mst_rs_get('rebar_grade',model) rescue nil).to_s if g.empty?
 g.empty? ? 'B420C' : g
end
def mst_ms_ui
 model=Sketchup.active_model
 all=[];collect_elements(model.entities,all)
 sel=[];mst_collect_elements_raw(model.selection,sel)
 sel=sel.select{|x|x.valid? && !x.get_attribute(DICT,'element_type','').to_s.empty?}.uniq
 types={'head_beam'=>'Başlık kirişi','deck_slab'=>'Döşeme','flat_precast'=>'Prekast','channel_precast'=>'Kanal prekastı','crane_precast'=>'Vinç prekastı','curb'=>'Tretuvar','crown_wall'=>'Kronman','pile_infill_concrete'=>'Kazık içi'}
 cur=types.map do |t,n|
  es=all.select{|e|e.get_attribute(DICT,'element_type','').to_s==t};next nil if es.empty?
  cs=es.map{|e|e.get_attribute(DICT,'concrete_class','-').to_s}.group_by{|x|x}.map{|k,v|"#{k} ×#{v.length}"}
  gs=es.map{|e|mst_rebar_grade(e,model)}.group_by{|x|x}.map{|k,v|"#{k} ×#{v.length}"}
  "#{n}: beton #{cs.join(', ')} · çelik #{gs.join(', ')}"
 end.compact
 pg=(mst_rs_get('rebar_grade',model) rescue nil).to_s;pg='B420C' if pg.empty?
 r=UI.inputbox(['Proje donatı çeliği (varsayılan)',"Seçili #{sel.length} eleman: beton sınıfı (boş = değişmez)","Seçili #{sel.length} eleman: donatı çeliği (boş = proje)"],
  [pg,'',''],[MST_REBAR_GRADES.join('|'),'','|'+MST_REBAR_GRADES.join('|')],"Malzeme Sınıfları\n#{cur.first(6).join("\n")}")
 return 0 unless r
 g=r[0].to_s.strip.upcase;cc=r[1].to_s.strip.upcase.gsub(' ','');eg=r[2].to_s.strip.upcase
 raise 'Beton sınıfı biçimi: C30/37' unless cc.empty? || cc=~/\AC\d{2}\/\d{2}\z/
 model.start_operation('MST Malzeme Sınıfları',true)
 begin
  model.set_attribute(DICT,'rs_rebar_grade',g) unless g.empty?
  sel.each{|e|e.set_attribute(DICT,'concrete_class',cc) unless cc.empty?;eg.empty? ? e.delete_attribute(DICT,'rebar_grade') : e.set_attribute(DICT,'rebar_grade',eg)} unless cc.empty? && r[2].to_s.strip.empty? && sel.empty?
  model.commit_operation
 rescue
  model.abort_operation;raise
 end
 UI.messagebox("Proje donatı çeliği: #{g}#{sel.empty? ? '' : "\n#{sel.length} eleman güncellendi#{cc.empty? ? '' : " (beton #{cc})"}#{eg.empty? ? '' : " (çelik #{eg})"}"}.\nBeton sınıfı keşifte sınıfa göre ayrılır (Keşif sayfası, 'beton sınıfına göre ayrı poz'); çap metrajında çelik sınıfı yazılır.")
 1
rescue => ex
 UI.messagebox("Malzeme sınıfları: #{ex.message}")
 0
end

end
end
