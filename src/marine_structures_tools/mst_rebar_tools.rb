# frozen_string_literal: true
# v0.49 RT1 — Donatı araçları (çizilmiş 3B donatıdan):
#  RS1 proje donatı ayarları (pas payı BK / döşeme / prekast, bindirme ×Ø, şaşırtma, görünürlük)
#  VZ1 donatı tag'lerini göster / gizle (varsayılan gizli)
#  DM1 donatı metrajı çap çap (hakediş tek poz kalır)
#  BL1 bükme listesi (Excel + krokili HTML)      KS1 kesim planı (stok boydan, fire)
#  KV1 kesit görünüşü (seçili BK, istenen noktada) RV1 revizyon karşılaştırması
#  CK1 elemanlar arası donatı çakışma kontrolü
require 'json'
module MAG
module MarineStructuresTools

MST_RS_DEFAULTS={'cover_bk_mm'=>75.0,'cover_deck_mm'=>50.0,'cover_precast_mm'=>50.0,'lap_d'=>50.0,'stagger'=>1,'rebar_visible'=>0,
 'cover_dolphin_mm'=>75.0,'cover_vk_mm'=>75.0,'cover_pk_mm'=>50.0,'chair_row'=>1}.freeze   # v0.50 RS2: eleman tipine göre pas payı, sehpa satırı
MST_RS_FIELDS=[['cover_bk_mm','Başlık kirişi pas payı (mm) — 50 / 75',20,120],['cover_deck_mm','Döşeme pas payı (mm) — 50 / 75',20,120],
 ['cover_precast_mm','Prekast pas payı (mm) — 50 / 75',20,120],['lap_d','Bindirme boyu (×Ø)',30,80],['stagger','Bindirmeler şaşırtmalı (1 = evet, 0 = hayır)',0,1],
 ['cover_dolphin_mm','Dolfen başlığı pas payı (mm)',20,120],['cover_vk_mm','Vinç / boylama kirişi pas payı (mm)',20,120],['cover_pk_mm','Kanal prekastı pas payı (mm)',20,120],
 ['chair_row','Sehpa metrajda ayrı satır (1 = evet, 0 = hayır)',0,1]].freeze
MST_RT_TAG_PREFIX='MST | DONATI'
MST_RT_HISTORY_MAX=10

# ---------------------------------------------------------------- RS1 ayarlar
def mst_rs_get(k,model=Sketchup.active_model)
 v=model.get_attribute(DICT,"rs_#{k}",nil)
 v.nil? ? MST_RS_DEFAULTS[k] : v
end
def mst_rs_all(model=Sketchup.active_model);Hash[MST_RS_DEFAULTS.keys.map{|k|[k,mst_rs_get(k,model)]}];end
# h: {'cover_bk_mm'=>'75',...} → doğrulanmış değerler (hata: RuntimeError)
def mst_rs_parse(h)
 out={}
 MST_RS_FIELDS.each do |k,lab,lo,hi|
  next unless h.key?(k)
  x=(Float(h[k].to_s.strip.tr(',','.')) rescue nil)
  raise "#{lab}: #{lo}–#{hi} arasında sayı olmalı." unless x && x>=lo && x<=hi
  out[k]=(%w[stagger chair_row].include?(k) ? x.round : x)
 end
 out
end
def mst_rs_save!(h,model=Sketchup.active_model)
 mst_rs_parse(h).each{|k,v|model.set_attribute(DICT,"rs_#{k}",v)}
end
def mst_rs_ui
 model=Sketchup.active_model;cur=mst_rs_all(model)
 r=UI.inputbox(MST_RS_FIELDS.map{|_,l,_,_|l},MST_RS_FIELDS.map{|k,_,_,_|v=cur[k].to_f;v==v.round ? v.round.to_s : v.to_s},'Donatı Ayarları (proje)')
 return 0 unless r
 h=Hash[MST_RS_FIELDS.each_with_index.map{|(k,_,_,_),i|[k,r[i]]}]
 vals=mst_rs_parse(h)
 model.start_operation('MST Donatı Ayarları',true)
 begin
  vals.each{|k,v|model.set_attribute(DICT,"rs_#{k}",v)}
  model.commit_operation
 rescue
  model.abort_operation;raise
 end
 @d.execute_script("window.mstApplyRebarSettings&&mstApplyRebarSettings(#{JSON.generate(mst_rs_all(model))})") if @d rescue nil
 UI.messagebox("Donatı ayarları kaydedildi:\nBK pas payı #{vals['cover_bk_mm'].round} mm · dolfen #{vals['cover_dolphin_mm'].round} mm · VK/BBK #{vals['cover_vk_mm'].round} mm · döşeme #{vals['cover_deck_mm'].round} mm · prekast #{vals['cover_precast_mm'].round} mm · kanal prekastı #{vals['cover_pk_mm'].round} mm\n"+
  "Bindirme #{vals['lap_d'].round}Ø #{vals['stagger'].to_i==1 ? 'şaşırtmalı' : 'aynı kesitte'}.\nYeni çizilen donatılarda geçerli; mevcut donatılar yeniden çizilince güncellenir.")
 1
rescue => ex
 UI.messagebox("Donatı ayarları: #{ex.message}")
 0
end

# ---------------------------------------------------------------- VZ1 görünürlük
def mst_rt_tags(model=Sketchup.active_model)
 model.layers.to_a.select{|l|l.name.to_s.start_with?(MST_RT_TAG_PREFIX)}
end
def mst_rt_visible?(model=Sketchup.active_model);mst_rs_get('rebar_visible',model).to_i!=0;end
def mst_rt_set_visible!(on,model=Sketchup.active_model)
 model.set_attribute(DICT,'rs_rebar_visible',on ? 1 : 0)
 mst_rt_tags(model).each{|l|l.visible=on unless (l.visible?)==on}
 mst_rt_tags(model).length
end
def mst_rt_toggle_ui
 model=Sketchup.active_model;on=!mst_rt_visible?(model)
 model.start_operation(on ? 'MST Donatıyı Göster' : 'MST Donatıyı Gizle',true)
 n=mst_rt_set_visible!(on,model)
 model.commit_operation
 UI.messagebox(n.zero? ? "Modelde donatı tag'i yok. Sonra çizilecek donatı #{on ? 'görünür' : 'gizli'} gelecek." :
  "Donatı #{on ? 'GÖRÜNÜR' : 'GİZLİ'} (#{n} tag: #{MST_RT_TAG_PREFIX} | …). Metraj ve hakediş etkilenmez.")
 on
rescue => ex
 model.abort_operation rescue nil
 UI.messagebox("Donatı göster / gizle: #{ex.message}")
 nil
end
def mst_rt_visible_note
 mst_rt_visible? ? '' : "\n\nDonatı 'MST | DONATI' tag'lerinde GİZLİ (model hafif kalsın diye). Görmek için: Donatıyı Göster / Gizle."
rescue
 ''
end

# ---------------------------------------------------------------- DM1 çap çap metraj
# BIM elemanların donatı tablosu (rebar_schedule_json, anahtar "… Ø32") çaplara bölünür; kalan (pursantaj, kazık kafesi,
# kaplama) "Ø ayrımsız" satırına. Toplam = BOQ ÖBF-004 (mst_boq_rebar_breakdown) — hakediş tek poz.
def mst_rt_dia_rows(all)
 total=mst_boq_rebar_breakdown(all).sum{|r|r[:kg]}
 by=Hash.new(0.0)
 grade=->(e){respond_to?(:mst_rebar_grade) ? mst_rebar_grade(e) : 'B420C'}   # v0.50 MS1: çelik sınıfı
 all.each do |e|
  r=mst_element_rebar(e);next unless r['source']=='BIM'
  g=grade.(e)
  sch=(JSON.parse(e.get_attribute(DICT,'rebar_schedule_json','').to_s) rescue nil)
  next unless sch.is_a?(Hash) && !sch.empty?
  part=Hash.new(0.0)
  sch.each{|k,v|d=k.to_s[/Ø\s*(\d+)/,1];part[d.to_i]+=v['kg'].to_f if d && v.is_a?(Hash)}
  s=part.values.sum;next if s<=0
  f=r['kg']/s   # tablo toplamı elemanın tonajına eşitlenir (güvence)
  part.each{|d,kg|by[[d,g]]+=kg*f}
 end
 multi=by.keys.map{|_,g|g}.uniq.length>1
 rows=by.sort_by{|(d,g),_|[d,g]}.map{|(d,g),kg|{'d'=>d,'grade'=>g,'label'=>multi ? "Ø#{d} · #{g}" : "Ø#{d}",'kg'=>kg}}
 rest=total-by.values.sum
 rows << {'d'=>nil,'label'=>'Ø ayrımsız (pursantaj / kazık kafesi / kaplama)','kg'=>rest} if rest.abs>0.5
 {'rows'=>rows,'total_kg'=>total}
end

# ---------------------------------------------------------------- donatı okuma (çizilmiş 3B)
def mst_rt_m(v);v.to_f/39.37007874015748;end
def mst_rt_xf(tr,q)
 p=Geom::Point3d.new(q[0]*39.37007874015748,q[1]*39.37007874015748,q[2]*39.37007874015748).transform(tr)
 [mst_rt_m(p.x),mst_rt_m(p.y),mst_rt_m(p.z)]
end
def mst_rt_sets(e)
 mst_dr_ents(e).to_a.select{|x|x.is_a?(Sketchup::Group) && MST_REBAR_SET_TYPES.include?(x.get_attribute(DICT,'element_type','').to_s)}
end
# eleman → çubuklar [{poz:, d:, pts:(eleman koordinatı, m, keskin köşeli), len:(açınım), stir:, key:, inst:}]
# poz: çizimden / otomatik donatıda poz numarası; eklentinin BIM donatısında rol adı
def mst_rt_bars(e)
 out=[]
 mst_rt_sets(e).each do |set|
  st=set.transformation
  if set.get_attribute(DICT,'element_type','').to_s==MST_DR_SET
   set.entities.grep(Sketchup::Group).each do |pg|
    poz=pg.get_attribute(MST_DR_DICT,'poz');tr=st*pg.transformation
    pg.entities.grep(Sketchup::ComponentInstance).each do |i|
     df=i.definition
     rel=(JSON.parse(df.get_attribute(MST_DR_DICT,'path_json','').to_s) rescue nil)
     next unless rel.is_a?(Array) && rel.length>=2
     t=tr*i.transformation
     out << {poz:poz.to_i,d:df.get_attribute(MST_DR_DICT,'diameter_mm',0).to_f,pts:rel.map{|q|mst_rt_xf(t,q)},rel:rel,
             len:(df.get_attribute(MST_DR_DICT,'dev_length_m') || df.get_attribute(MST_DR_DICT,'length_m',0)).to_f,
             stir:df.get_attribute(MST_DR_DICT,'stirrup',0).to_i==1,key:df,inst:i,group:pg.name.to_s}
    end
   end
  else
   walk=lambda do |ents,tr|
    ents.grep(Sketchup::Group).each do |g|
     t=tr*g.transformation
     if %w[rebar_bar rebar_stirrup].include?(g.get_attribute(DICT,'element_type','').to_s)
      pj=(JSON.parse(g.get_attribute(DICT,'path_json','').to_s) rescue nil)
      role=g.get_attribute(DICT,'rebar_role','').to_s;role=g.name.to_s.split(' ').first.to_s if role.empty?
      pts=pj.is_a?(Array) && pj.length>=2 ? pj.map{|q|mst_rt_xf(st,q)} : nil
      out << {poz:role,d:g.get_attribute(DICT,'diameter_mm',0).to_f,pts:pts,rel:pts,len:g.get_attribute(DICT,'length_m',0).to_f,
              stir:g.get_attribute(DICT,'element_type','')=='rebar_stirrup',key:[role,g.get_attribute(DICT,'diameter_mm',0).to_f.round,(g.get_attribute(DICT,'length_m',0).to_f*100).round],inst:g,group:role}
     else
      walk.(g.entities,t)
     end
    end
   end
   walk.(set.entities,st)
  end
 end
 out
end
# kesik / bükülü çubuğun ölçüleri: düz parçaların boyları (cm) "20/125/20"
def mst_rt_dims(pts)
 return '' unless pts && pts.length>=2
 pts.each_cons(2).map{|a,b|(Math.sqrt((0..2).sum{|k|(b[k]-a[k])**2})*100).round}.reject(&:zero?).join('/')
end

# ---------------------------------------------------------------- UP1 eski (v0.48) donatı → yeni kurallar
# v0.48'de çizilen çizimden / otomatik donatının çubuk tanımlarında şekil bilgisi (eksen yolu, büküm, açınım) yok:
# bükme listesi, kesit, çakışma onları okuyamaz. Kayıtlı parametrelerle (otomatik: rebar_auto_json; çizimden: paket +
# çizilmiş paketler) yeni kurallarla (oval büküm, 50Ø şaşırtmalı bindirme, parapet) yeniden çizilir.
def mst_rt_legacy?(e)
 mst_dr_set_of(e).any?{|g|g.entities.grep(Sketchup::Group).any?{|pg|pg.entities.grep(Sketchup::ComponentInstance).any?{|i|i.definition.get_attribute(MST_DR_DICT,'path_json').nil?}}}
end
def mst_rt_legacy_elems(model=Sketchup.active_model)
 all=[];collect_elements(model.entities,all)
 all.select{|x|(mst_rt_legacy?(x) rescue false)}
end
# yeniden çizer (çağıranın işlemi içinde); [true/false, açıklama]
def mst_rt_upgrade!(e)
 eid=element_visible_id(e);kg0=mst_element_rebar(e)['kg']
 case e.get_attribute(DICT,'rebar_mode','').to_s
 when 'auto_detail'
  prm=(JSON.parse(e.get_attribute(DICT,'rebar_auto_json','{}').to_s) rescue {})
  pl=mst_ar_plan(*mst_dr_geometry(e),prm)
  return [false,"#{eid}: otomatik donatı çıkmadı"] if pl[:bars].empty?
  mst_ar_draw!(e,pl)
 when MST_DR_MODE
  spec=mst_dr_load(e.get_attribute(DICT,'rebar_drawing','').to_s)
  bt=e.get_attribute(DICT,'rebar_drawing_batches','').to_s.split(',').map(&:to_i).reject(&:zero?)
  pl=mst_dr_plan(spec,*mst_dr_geometry(e),bt.empty? ? nil : bt)
  return [false,"#{eid}: #{mst_dr_blockers(pl,spec).first || 'çizim uymuyor'}"] unless pl[:bad].empty? && pl[:dims_ok] && pl[:probes_ok]
  mst_dr_draw!(e,spec,pl)
 else
  return [false,"#{eid}: donatı türü tanınmadı"]
 end
 [true,format('%s: %.3f t → %.3f t',eid,kg0/1000.0,mst_element_rebar(e)['kg']/1000.0)]
end
def mst_rt_upgrade_ui
 model=Sketchup.active_model
 es=mst_rt_legacy_elems(model)
 return UI.messagebox('Eski (v0.48) kurallarla çizilmiş donatı yok: hepsi güncel.') && 0 if es.empty?
 return 0 unless UI.messagebox("#{es.length} BK'nın donatısı eski kurallarla çizilmiş (#{es.first(10).map{|x|element_visible_id(x)}.join(', ')}).
"+
  "Kayıtlı çap / aralık / çizim paketiyle yeni kurallarla (oval büküm, 50Ø şaşırtmalı bindirme, parapet) yeniden çizilsin mi? (tek Geri Al)",MB_YESNO)==IDYES
 res=[]
 model.start_operation('MST Donatıyı Yeni Kurallarla Yeniden Çiz',true)
 begin
  es.each{|e|res << mst_rt_upgrade!(e)}
  model.commit_operation
 rescue
  model.abort_operation;raise
 end
 send_boq(@d) if @d rescue nil
 UI.messagebox("Yeniden çizildi: #{res.count{|ok,_|ok}} / #{res.length}
#{res.map{|_,m|m}.first(20).join("
")}#{mst_rt_visible_note}")
 res.count{|ok,_|ok}
rescue => ex
 UI.messagebox("Donatıyı yeni kurallarla çiz: #{ex.message}")
 0
end
def mst_rt_legacy_note(es)
 lg=es.select{|x|(mst_rt_legacy?(x) rescue false)}
 lg.empty? ? '' : "\n#{lg.length} BK'nın donatısı eski (v0.48) kurallarla çizilmiş, şekil bilgisi yok (#{lg.first(6).map{|x|element_visible_id(x)}.join(', ')}). Önce: Model Bakımı → Donatı → Eski Donatıyı Yeni Kurallarla Yeniden Çiz."
end

# ---------------------------------------------------------------- BL1 bükme listesi
# satır: aynı eleman + aynı poz + aynı şekil (tanım) → adet
def mst_rt_bending_rows(elems)
 rows=[]
 elems.each do |e|
  eid=element_visible_id(e)
  mst_rt_bars(e).group_by{|b|b[:key]}.each do |_,bs|
   b=bs.first
   rows << {'eid'=>eid,'poz'=>b[:poz],'d'=>b[:d].round,'n'=>bs.length,'shape'=>mst_rt_dims(b[:rel] || b[:pts]),'len'=>b[:len],
            'bends'=>[(b[:rel] || []).length-2,0].max,'stir'=>b[:stir],'kg'=>bs.length*b[:len]*mst_dr_kgm(b[:d]),'group'=>b[:group],'rel'=>b[:rel]}
  end
 end
 # aynı poz içinde şekiller a, b, c … (sahada ayrı demet)
 rows.group_by{|r|[r['eid'],r['poz']]}.each_value do |rs|
  next if rs.length<2
  rs.sort_by{|r|-r['n']}.each_with_index{|r,i|r['sub']=i<26 ? (97+i).chr : (i+1).to_s}
 end
 rows.sort_by{|r|[r['eid'],r['poz'].is_a?(Integer) ? format('%04d',r['poz']) : r['poz'].to_s,r['sub'].to_s]}
end
def mst_rt_poz_label(r);"#{r['poz'].is_a?(Integer) ? format('%02d',r['poz']) : r['poz']}#{r['sub'] ? "-#{r['sub']}" : ''}";end

# ---------------------------------------------------------------- KS1 kesim planı (en iyi uyum, azalan sıra)
# parçalar: {Ø => [[boy_m, adet], ...]} ; stok boyu (m). Stoktan uzun parça "özel boy" sayılır.
def mst_rt_cut_plan(pieces,stock=12.0)
 out={}
 pieces.each do |d,list|
  sc=(stock*1000).round;rem=Array.new(sc+1,0);bars=0;special=0;sp_len=0.0;net=0.0   # mm
  list.map{|l,n|[(l*1000).round,n]}.sort_by{|l,_|-l}.each do |lc,n|
   next if n<=0 || lc<=0
   net+=lc*n/1000.0
   if lc>sc then special+=n;sp_len+=lc*n/1000.0;next end
   n.times do
    k=lc;k+=1 while k<=sc && rem[k].zero?
    if k<=sc then rem[k]-=1;rem[k-lc]+=1
    else bars+=1;rem[sc-lc]+=1 end
   end
  end
  ordered=bars*stock+sp_len
  usable=(300..sc).sum{|r|rem[r]*r/1000.0}   # ≥ 30 cm artıklar yeniden kullanılabilir
  out[d]={'d'=>d,'net_m'=>net,'stock_bars'=>bars,'special'=>special,'special_m'=>sp_len,'ordered_m'=>ordered,
          'net_kg'=>net*mst_dr_kgm(d),'ordered_kg'=>ordered*mst_dr_kgm(d),'waste_pct'=>(ordered>0 ? 100.0*(1-net/ordered) : 0.0),'reusable_m'=>usable}
 end
 out
end
def mst_rt_cut_from_rows(rows,stock=12.0)
 pc=Hash.new{|h,k|h[k]=Hash.new(0)}
 rows.each{|r|pc[r['d']][r['len'].round(3)]+=r['n']}
 mst_rt_cut_plan(pc.transform_values{|h|h.to_a},stock)
end

# ---------------------------------------------------------------- Excel / HTML yazıcıları
def mst_rt_xl_sheet(rows)
 esc=->(v){v.to_s.gsub('&','&amp;').gsub('<','&lt;').gsub('>','&gt;').gsub('"','&quot;')}
 col=->(n){s=+'';n+=1;while n>0;n-=1;s.prepend((65+n%26).chr);n/=26;end;s}
 body=rows.each_with_index.map do |row,ri|
  cells=row.each_with_index.map do |v,ci|
   ref="#{col.(ci)}#{ri+1}";st=ri.zero? ? ' s="1"' : ''
   v.is_a?(Numeric) ? "<c r=\"#{ref}\"#{ri.zero? ? st : ' s="2"'}><v>#{v.is_a?(Float) ? v.round(4) : v}</v></c>" : "<c r=\"#{ref}\" t=\"inlineStr\"#{st}><is><t>#{esc.(v)}</t></is></c>"
  end.join
  "<row r=\"#{ri+1}\">#{cells}</row>"
 end.join
 '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'+
  '<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>'+
  "<sheetData>#{body}</sheetData></worksheet>"
end
def mst_rt_write_xlsx(path,sheets)
 ct='<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'+
  sheets.each_index.map{|i|"<Override PartName=\"/xl/worksheets/sheet#{i+1}.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"}.join+'</Types>'
 rr='<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'
 wb='<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>'+
  sheets.each_with_index.map{|(n,_),i|"<sheet name=\"#{n.to_s.gsub('&','&amp;')[0,31]}\" sheetId=\"#{i+1}\" r:id=\"rId#{i+1}\"/>"}.join+'</sheets></workbook>'
 wr='<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'+
  sheets.each_index.map{|i|"<Relationship Id=\"rId#{i+1}\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet#{i+1}.xml\"/>"}.join+
  "<Relationship Id=\"rId#{sheets.length+1}\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/></Relationships>"
 sty='<?xml version="1.0" encoding="UTF-8" standalone="yes"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><numFmts count="1"><numFmt numFmtId="164" formatCode="#,##0.###"/></numFmts><fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font></fonts><fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF073F73"/><bgColor indexed="64"/></patternFill></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="3"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/><xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/></cellXfs></styleSheet>'
 ent={'[Content_Types].xml'=>ct,'_rels/.rels'=>rr,'xl/workbook.xml'=>wb,'xl/_rels/workbook.xml.rels'=>wr,'xl/styles.xml'=>sty}
 sheets.each_with_index{|(_,rows),i|ent["xl/worksheets/sheet#{i+1}.xml"]=mst_rt_xl_sheet(rows)}
 write_simple_zip(path,ent)
 path
end
def mst_rt_out_dir(model=Sketchup.active_model)
 mp=model.path.to_s
 mp.empty? ? (Sketchup.respond_to?(:temp_dir) ? Sketchup.temp_dir : Dir.pwd) : File.dirname(mp)
end
def mst_rt_out_name(suffix,ext,model=Sketchup.active_model)
 base=File.basename(model.path.to_s,'.skp');base='Model' if base.empty?
 File.join(mst_rt_out_dir(model),"#{base}_MST_#{suffix}.#{ext}")
end
def mst_rt_h(s);s.to_s.gsub('&','&amp;').gsub('<','&lt;').gsub('>','&gt;');end
def mst_rt_dia_color(d)
 return mst_rebar_dia_hex(d) if respond_to?(:mst_rebar_dia_hex)   # eklentinin çap renkleri (MST Donatı Ø..)
 h=((d.to_i*47)%360)/60.0;c=0.75*0.9;x=c*(1-((h%2)-1).abs);m=0.9-c
 r,g,b=[[c,x,0],[x,c,0],[0,c,x],[0,x,c],[x,0,c],[c,0,x]][h.floor%6]
 format('#%02X%02X%02X',((r+m)*200).round,((g+m)*200).round,((b+m)*200).round)
end
def mst_rt_html_page(title,body)
 "<!doctype html><html lang='tr'><head><meta charset='utf-8'><title>#{mst_rt_h(title)}</title><style>"+
 "body{font:13px Segoe UI,Arial,sans-serif;margin:18px;color:#1d2b3a;background:#fff}h1{font-size:19px;color:#073f73}h2{font-size:15px;color:#073f73;margin-top:22px}"+
 "table{border-collapse:collapse;margin:8px 0}td,th{border:1px solid #cdd6e0;padding:3px 7px;text-align:right}th{background:#073f73;color:#fff}td.l,th.l{text-align:left}"+
 "tr.tot td{font-weight:bold;background:#eef3f8}.small{color:#5b6b7b;font-size:12px}svg text{font:10px Segoe UI,Arial}</style></head><body><h1>#{mst_rt_h(title)}</h1>#{body}</body></html>"
end
# şekil krokisi (SVG): eğilmiş çubuğun düzlemine izdüşüm + parça ölçüleri (cm)
def mst_rt_sketch_svg(rel,d,w=150,h=70)
 return '' unless rel && rel.length>=2
 p0=rel[0];vs=rel.map{|q|[q[0]-p0[0],q[1]-p0[1],q[2]-p0[2]]}
 dir=->(v){l=Math.sqrt(v.sum{|x|x*x});l<1e-9 ? nil : v.map{|x|x/l}}
 e1=vs.each_cons(2).map{|a,b|[b[0]-a[0],b[1]-a[1],b[2]-a[2]]}.max_by{|v|v.sum{|x|x*x}};e1=dir.(e1)   # en uzun parça yatay
 return '' unless e1
 e2=nil
 vs.each do |v|
  dt=v.zip(e1).sum{|a,b|a*b};o=v.zip(e1).map{|a,b|a-b*dt};x=dir.(o);(e2=x;break) if x && Math.sqrt(o.sum{|q|q*q})>1e-4
 end
 e2||=[0,0,1]
 q2=vs.map{|v|[v.zip(e1).sum{|a,b|a*b},v.zip(e2).sum{|a,b|a*b}]}
 xs=q2.map(&:first);ys=q2.map(&:last);sx=[xs.max-xs.min,1e-6].max;sy=[ys.max-ys.min,1e-6].max
 k=[(w-24)/sx,(h-24)/sy].min
 pt=q2.map{|x,y|[12+(x-xs.min)*k,h-12-(y-ys.min)*k]}
 lab=q2.each_cons(2).each_with_index.map do |(a,b),i|
  l=(Math.sqrt((b[0]-a[0])**2+(b[1]-a[1])**2)*100).round;next '' if l.zero?
  mx=(pt[i][0]+pt[i+1][0])/2;my=(pt[i][1]+pt[i+1][1])/2
  "<text x='#{mx.round(1)}' y='#{(my-3).round(1)}' text-anchor='middle'>#{l}</text>"
 end.join
 "<svg width='#{w}' height='#{h}' viewBox='0 0 #{w} #{h}'><polyline points='#{pt.map{|x,y|"#{x.round(1)},#{y.round(1)}"}.join(' ')}' fill='none' stroke='#{mst_rt_dia_color(d)}' stroke-width='3' stroke-linejoin='round'/>#{lab}</svg>"
end
def mst_rt_bending_export(elems,base_path=nil,stock=nil)
 stock||=12.0
 rows=mst_rt_bending_rows(elems)
 raise "Seçili / modeldeki elemanlarda okunabilir 3B donatı yok.#{mst_rt_legacy_note(elems)}" if rows.empty?
 cut=mst_rt_cut_from_rows(rows,stock)
 base_path||=mst_rt_out_name('Bukme_Listesi','xlsx')
 hdr=['Eleman','Poz','Ø (mm)','Adet','Şekil — parça ölçüleri (cm)','Büküm','Boy (m)','Toplam boy (m)','Birim (kg/m)','Ağırlık (kg)','Grup']
 sh1=[hdr]+rows.map{|r|[r['eid'],mst_rt_poz_label(r),r['d'],r['n'],r['shape'],r['bends'].zero? ? 'düz' : "#{r['bends']}#{r['stir'] ? ' (etriye 4Ø)' : ''}",r['len'].round(3),(r['n']*r['len']).round(2),mst_dr_kgm(r['d']).round(3),r['kg'].round(1),r['group']]}
 dsum=rows.group_by{|r|r['d']}.sort.map{|d,rs|[d,rs.sum{|r|r['n']},rs.sum{|r|r['n']*r['len']},rs.sum{|r|r['kg']}]}
 sh2=[['Ø (mm)','Adet','Toplam boy (m)','Ağırlık (t)']]+dsum.map{|d,n,m,kg|["Ø#{d}",n,m.round(1),(kg/1000.0).round(3)]}+[['TOPLAM',dsum.sum{|x|x[1]},dsum.sum{|x|x[2]}.round(1),(dsum.sum{|x|x[3]}/1000.0).round(3)]]
 sh3=[['Ø (mm)','Net boy (m)',"#{stock.round} m stok çubuk",'Özel boy (adet)','Sipariş boy (m)','Net (t)','Sipariş (t)','Fire %','Yeniden kullanılabilir artık ≥30 cm (m)']]+
  cut.sort.map{|d,c|["Ø#{d}",c['net_m'].round(1),c['stock_bars'],c['special'],c['ordered_m'].round(1),(c['net_kg']/1000.0).round(3),(c['ordered_kg']/1000.0).round(3),c['waste_pct'].round(1),c['reusable_m'].round(1)]}
 tn=cut.values.sum{|c|c['net_kg']};to=cut.values.sum{|c|c['ordered_kg']}
 sh3 << ['TOPLAM',cut.values.sum{|c|c['net_m']}.round(1),cut.values.sum{|c|c['stock_bars']},cut.values.sum{|c|c['special']},cut.values.sum{|c|c['ordered_m']}.round(1),(tn/1000.0).round(3),(to/1000.0).round(3),(to>0 ? 100.0*(1-tn/to) : 0).round(1),cut.values.sum{|c|c['reusable_m']}.round(1)]
 mst_rt_write_xlsx(base_path,[['Bükme Listesi',sh1],['Çap Özeti',sh2],['Kesim Planı',sh3]])
 # krokili HTML
 trs=rows.map{|r|"<tr><td class='l'>#{mst_rt_h(r['eid'])}</td><td class='l'><b>#{mst_rt_h(mst_rt_poz_label(r))}</b></td><td>Ø#{r['d']}</td><td>#{r['n']}</td><td>#{mst_rt_sketch_svg(r['rel'],r['d'])}</td><td class='l'>#{mst_rt_h(r['shape'])}</td><td>#{format('%.3f',r['len'])}</td><td>#{format('%.1f',r['kg'])}</td></tr>"}.join
 dtr=dsum.map{|d,n,m,kg|"<tr><td class='l'>Ø#{d}</td><td>#{n}</td><td>#{format('%.1f',m)}</td><td>#{format('%.3f',kg/1000.0)}</td></tr>"}.join
 ctr=cut.sort.map{|d,c|"<tr><td class='l'>Ø#{d}</td><td>#{format('%.1f',c['net_m'])}</td><td>#{c['stock_bars']}</td><td>#{c['special']}</td><td>#{format('%.3f',c['net_kg']/1000.0)}</td><td>#{format('%.3f',c['ordered_kg']/1000.0)}</td><td>#{format('%.1f',c['waste_pct'])}</td></tr>"}.join
 html=mst_rt_html_page('Donatı Bükme Listesi ve Kesim Planı',
  "<p class='small'>3B çizilmiş donatıdan · #{elems.length} eleman · #{rows.sum{|r|r['n']}} çubuk · bükümler oval (etriye 4Ø, Ø≤16 6Ø, Ø>16 7Ø); boy açınım (eksen) boyu.</p>"+
  "<h2>Çap özeti</h2><table><tr><th class='l'>Ø</th><th>Adet</th><th>Boy (m)</th><th>Ağırlık (t)</th></tr>#{dtr}<tr class='tot'><td class='l'>TOPLAM</td><td>#{dsum.sum{|x|x[1]}}</td><td>#{format('%.1f',dsum.sum{|x|x[2]})}</td><td>#{format('%.3f',dsum.sum{|x|x[3]}/1000.0)}</td></tr></table>"+
  "<h2>Kesim planı (#{stock.round} m stok, en iyi uyum)</h2><table><tr><th class='l'>Ø</th><th>Net boy (m)</th><th>Stok çubuk</th><th>Özel boy</th><th>Net (t)</th><th>Sipariş (t)</th><th>Fire %</th></tr>#{ctr}<tr class='tot'><td class='l'>TOPLAM</td><td></td><td>#{cut.values.sum{|c|c['stock_bars']}}</td><td>#{cut.values.sum{|c|c['special']}}</td><td>#{format('%.3f',tn/1000.0)}</td><td>#{format('%.3f',to/1000.0)}</td><td>#{format('%.1f',to>0 ? 100.0*(1-tn/to) : 0)}</td></tr></table>"+
  "<h2>Bükme listesi</h2><table><tr><th class='l'>Eleman</th><th class='l'>Poz</th><th>Ø</th><th>Adet</th><th>Kroki</th><th class='l'>Ölçüler (cm)</th><th>Boy (m)</th><th>Ağırlık (kg)</th></tr>#{trs}</table>")
 hp=base_path.sub(/\.xlsx\z/,'.html');File.write(hp,html)
 {xlsx:base_path,html:hp,rows:rows,cut:cut,net_kg:tn,ordered_kg:to}
end
def mst_rt_target_elems(model=Sketchup.active_model)
 sel=model.selection.to_a.select{|x|x.respond_to?(:get_attribute) && !mst_rt_sets(x).empty? rescue false}
 return sel unless sel.empty?
 all=[];collect_elements(model.entities,all)
 all.select{|x|(!mst_rt_sets(x).empty? rescue false)}
end
def mst_rt_bending_ui
 es=mst_rt_target_elems
 raise '3B çizilmiş donatısı olan eleman yok (önce donatı çizin).' if es.empty?
 r=mst_rt_bending_export(es)
 UI.messagebox(format("Bükme listesi + kesim planı hazır (%d eleman · %d satır).%s\nNet %.3f t · sipariş (stok çubuk) %.3f t · fire %%%.1f\n\n%s\n%s",
  es.length,r[:rows].length,mst_rt_legacy_note(es),r[:net_kg]/1000.0,r[:ordered_kg]/1000.0,r[:ordered_kg]>0 ? 100*(1-r[:net_kg]/r[:ordered_kg]) : 0,r[:xlsx],r[:html]))
 UI.openURL("file:///#{r[:html].tr('\\','/')}") rescue nil
 r[:rows].length
rescue => ex
 UI.messagebox("Bükme listesi: #{ex.message}")
 0
end

# ---------------------------------------------------------------- KV1 kesit görünüşü
# e: BK; v: BK boyunca konum (m, yerel çerçeve). Beton kesiti (üçgen dilimleri) + kesitten geçen çubuklar (daire) +
# kesit düzleminde yatan çubuklar (± tol içinde, çizgi). SVG döner.
def mst_rt_section(e,v,tol=nil)
 pts,edges,tris=mst_dr_geometry(e)
 raise 'Eleman yüzeyi okunamadı.' if tris.empty?
 fr=mst_ar_frame(pts,edges);loc=->(p){mst_ar_to_local(fr,p)}
 segs=[]
 tris.each do |t|
  q=t.map{|p|loc.(p)};x=[]
  3.times do |i|
   a=q[i];b=q[(i+1)%3];da=a[1]-v;db=b[1]-v
   next if (da>0 && db>0) || (da<0 && db<0) || (da-db).abs<1e-12
   s=da/(da-db);x << [a[0]+(b[0]-a[0])*s,a[2]+(b[2]-a[2])*s]
  end
  segs << [x[0],x[1]] if x.length>=2 && (x[0][0]-x[1][0]).abs+(x[0][1]-x[1][1]).abs>1e-6
 end
 bars=mst_rt_bars(e).select{|b|b[:pts]}
 tol||=0.075
 dots=[];lines=[]
 bars.each do |b|
  lp=b[:pts].map{|p|loc.(p)}
  lp.each_cons(2) do |a,c|
   da=a[1]-v;dc=c[1]-v
   if (da.abs<tol && dc.abs<tol)
    lines << [[a[0],a[2]],[c[0],c[2]],b[:d]]
   elsif !((da>0 && dc>0) || (da<0 && dc<0)) && (da-dc).abs>1e-9
    s=da/(da-dc);dots << [a[0]+(c[0]-a[0])*s,a[2]+(c[2]-a[2])*s,b[:d]]
   end
  end
 end
 {frame:fr,v:v,concrete:segs,dots:dots,lines:lines}
end
def mst_rt_section_svg(sec,title='')
 fr=sec[:frame];w=fr['W'];h=fr['H'];sw=900.0;k=(sw-60)/[w,h*1.6].max;sh=h*k+70
 x=->(u){30+u*k};y=->(z){sh-40-z*k}
 g=+"<svg xmlns='http://www.w3.org/2000/svg' width='#{sw.round}' height='#{sh.round}' viewBox='0 0 #{sw.round} #{sh.round}' style='background:#fff'>"
 sec[:concrete].each{|a,b|g << "<line x1='#{x.(a[0]).round(1)}' y1='#{y.(a[1]).round(1)}' x2='#{x.(b[0]).round(1)}' y2='#{y.(b[1]).round(1)}' stroke='#7a8794' stroke-width='1.6'/>"}
 sec[:lines].each{|a,b,d|g << "<line x1='#{x.(a[0]).round(1)}' y1='#{y.(a[1]).round(1)}' x2='#{x.(b[0]).round(1)}' y2='#{y.(b[1]).round(1)}' stroke='#{mst_rt_dia_color(d)}' stroke-width='#{[d/1000.0*k,1.2].max.round(2)}' stroke-linecap='round'/>"}
 sec[:dots].each{|u,z,d|g << "<circle cx='#{x.(u).round(1)}' cy='#{y.(z).round(1)}' r='#{[d/2000.0*k,1.5].max.round(2)}' fill='#{mst_rt_dia_color(d)}'/>"}
 ds=(sec[:dots].map{|q|q[2]}+sec[:lines].map{|q|q[2]}).map(&:round).uniq.sort
 ds.each_with_index{|d,i|g << "<circle cx='#{40+i*70}' cy='16' r='5' fill='#{mst_rt_dia_color(d)}'/><text x='#{50+i*70}' y='20'>Ø#{d}</text>"}
 g << "<text x='#{sw-20}' y='20' text-anchor='end'>#{mst_rt_h(title)}</text>"
 g << "<text x='30' y='#{(sh-12).round}'>Genişlik #{format('%.2f',w)} m · yükseklik #{format('%.2f',h)} m · kesit v = #{format('%.2f',sec[:v])} m · kesilen çubuk #{sec[:dots].length} · düzlemdeki çubuk parçası #{sec[:lines].length}</text></svg>"
 g
end
def mst_rt_section_ui
 model=Sketchup.active_model
 sel=model.selection.to_a.select{|x|x.respond_to?(:get_attribute) && x.get_attribute(DICT,'element_type','').to_s=='head_beam'}
 raise 'Kesiti alınacak tek bir Başlık Kirişi seçin.' unless sel.length==1
 e=sel.first;raise "#{element_visible_id(e)}: 3B donatı çizilmemiş." if mst_rt_sets(e).empty?
 raise mst_rt_legacy_note([e]).strip if mst_rt_legacy?(e)
 pts,edges,_=mst_dr_geometry(e);fr=mst_ar_frame(pts,edges)
 r=UI.inputbox(["Kesit konumu — BK boyunca (m, 0–#{format('%.2f',fr['L'])})"],[format('%.2f',fr['L']/2)],"Donatı Kesiti — #{element_visible_id(e)}")
 return 0 unless r
 v=Float(r[0].to_s.tr(',','.')) rescue raise('Konum sayı olmalı.')
 raise "Konum 0–#{format('%.2f',fr['L'])} arasında olmalı." unless v>0 && v<fr['L']
 sec=mst_rt_section(e,v)
 svg=mst_rt_section_svg(sec,"#{element_visible_id(e)} — kesit v = #{format('%.2f',v)} m")
 f=mst_rt_out_name("Kesit_#{element_visible_id(e).gsub(/[^0-9A-Za-z_-]/,'_')}_#{format('%.2f',v).tr('.','_')}",'html')
 File.write(f,mst_rt_html_page("#{element_visible_id(e)} donatı kesiti",svg+"<p class='small'>Gri: beton kesiti. Daire: kesitten geçen çubuk (renk çapa göre). Çizgi: kesit düzleminin ±7.5 cm yakınında yatan çubuk (etriye, C, U bacakları).</p>"))
 UI.openURL("file:///#{f.tr('\\','/')}") rescue nil
 UI.messagebox("Kesit: #{sec[:dots].length} kesilen çubuk, #{sec[:lines].length} düzlem parçası.\n#{f}")
 1
rescue => ex
 UI.messagebox("Donatı kesiti: #{ex.message}")
 0
end

# ---------------------------------------------------------------- RV1 revizyon
def mst_rt_history(e)
 h=(JSON.parse(e.get_attribute(DICT,'rebar_history_json','[]').to_s) rescue [])
 h.is_a?(Array) ? h : []
end
# donatı değişmeden önce çağrılır (çizimden / otomatik / eklenti BIM yeniden çizim, silme)
def mst_rt_history_push!(e)
 sj=e.get_attribute(DICT,'rebar_schedule_json','').to_s
 return false if sj.empty?
 # v0.51.5 R-4: bozuk geçmiş kaydı boş sayılıp üzerine yazılmaz (geçmiş yalnız ileri yazılır)
 raw=e.get_attribute(DICT,'rebar_history_json','').to_s
 raise "#{element_visible_id(e)}: donatı revizyon geçmişi (rebar_history_json) okunamadı; üzerine yazılmadı, işlem yapılmadı." unless raw.strip.empty? || (JSON.parse(raw) rescue nil).is_a?(Array)
 h=mst_rt_history(e)
 ent={'at'=>Time.now.strftime('%Y-%m-%d %H:%M'),'mode'=>e.get_attribute(DICT,'rebar_mode','').to_s,'source'=>(e.get_attribute(DICT,'rebar_source','').to_s.empty? ? e.get_attribute(DICT,'rebar_mode','').to_s : e.get_attribute(DICT,'rebar_source','').to_s),
      'kg'=>e.get_attribute(DICT,'rebar_kg',e.get_attribute(DICT,'rebar_t',0).to_f*1000.0).to_f,'sched'=>sj}
 return false if h.last && h.last['sched']==sj && (h.last['kg']-ent['kg']).abs<0.01
 h << ent   # R-1: geçmiş kırpılmaz (MST_RT_HISTORY_MAX yalnız sabit olarak kalır)
 e.set_attribute(DICT,'rebar_history_json',JSON.generate(h))
 true
end
def mst_rt_sched_hash(js)
 h=(JSON.parse(js.to_s) rescue {});h.is_a?(Hash) ? h : {}
end
# eski ↔ yeni tablo: satır satır (anahtar "Poz 9 Ø32" / "TOP Ø25"), Ø özeti
def mst_rt_compare(old_js,new_js)
 a=mst_rt_sched_hash(old_js);b=mst_rt_sched_hash(new_js)
 keys=(a.keys+b.keys).uniq.sort_by{|k|[k[/\d+/].to_i,k]}
 rows=keys.map do |k|
  x=a[k] || {};y=b[k] || {}
  n0=x['count'].to_i;n1=y['count'].to_i;k0=x['kg'].to_f;k1=y['kg'].to_f
  st=if x.empty? then 'YENİ' elsif y.empty? then 'KALDIRILDI' elsif n0!=n1 || (k1-k0).abs>0.5 then 'DEĞİŞTİ' else 'aynı' end
  {'key'=>k,'n0'=>n0,'n1'=>n1,'kg0'=>k0,'kg1'=>k1,'dkg'=>k1-k0,'state'=>st}
 end
 dia=Hash.new{|h,k|h[k]=[0.0,0.0]}
 rows.each{|r|d=r['key'][/Ø\s*(\d+)/,1].to_i;dia[d][0]+=r['kg0'];dia[d][1]+=r['kg1']}
 {'rows'=>rows,'dia'=>dia.sort.map{|d,(x,y)|{'d'=>d,'kg0'=>x,'kg1'=>y,'dkg'=>y-x}},'kg0'=>rows.sum{|r|r['kg0']},'kg1'=>rows.sum{|r|r['kg1']}}
end
def mst_rt_revision_ui
 model=Sketchup.active_model
 sel=model.selection.to_a.select{|x|x.respond_to?(:get_attribute) && !mst_rt_history(x).empty?}
 raise 'Revizyon geçmişi olan bir eleman seçin (donatısı en az bir kez yeniden çizilmiş / silinmiş BK veya döşeme).' if sel.empty?
 e=sel.first;h=mst_rt_history(e)
 opts=h.each_with_index.map{|x,i|"#{i+1}: #{x['at']} · #{x['source']} · #{format('%.3f',x['kg'].to_f/1000.0)} t"}.reverse
 r=UI.inputbox(['Karşılaştırılacak önceki donatı'],[opts.first],[opts.join('|')],"Revizyon — #{element_visible_id(e)}")
 return 0 unless r
 old=h[r[0].to_i-1] or raise 'Seçim okunamadı.'
 cur=e.get_attribute(DICT,'rebar_schedule_json','').to_s
 c=mst_rt_compare(old['sched'],cur)
 ch=c['rows'].reject{|x|x['state']=='aynı'}
 tr=c['rows'].map{|x|"<tr#{x['state']=='aynı' ? '' : " style='background:#fff6dc'"}><td class='l'>#{mst_rt_h(x['key'])}</td><td>#{x['n0']}</td><td>#{x['n1']}</td><td>#{format('%.1f',x['kg0'])}</td><td>#{format('%.1f',x['kg1'])}</td><td>#{format('%+.1f',x['dkg'])}</td><td class='l'>#{x['state']}</td></tr>"}.join
 dt=c['dia'].map{|x|"<tr><td class='l'>Ø#{x['d']}</td><td>#{format('%.3f',x['kg0']/1000.0)}</td><td>#{format('%.3f',x['kg1']/1000.0)}</td><td>#{format('%+.3f',x['dkg']/1000.0)}</td></tr>"}.join
 f=mst_rt_out_name("Revizyon_#{element_visible_id(e).gsub(/[^0-9A-Za-z_-]/,'_')}",'html')
 File.write(f,mst_rt_html_page("#{element_visible_id(e)} donatı revizyonu",
  "<p>Önceki: <b>#{mst_rt_h(old['at'])}</b> · #{mst_rt_h(old['source'])} → Şimdiki: #{mst_rt_h(e.get_attribute(DICT,'rebar_source','').to_s)}</p>"+
  "<h2>Çap özeti</h2><table><tr><th class='l'>Ø</th><th>Önce (t)</th><th>Şimdi (t)</th><th>Fark (t)</th></tr>#{dt}<tr class='tot'><td class='l'>TOPLAM</td><td>#{format('%.3f',c['kg0']/1000.0)}</td><td>#{format('%.3f',c['kg1']/1000.0)}</td><td>#{format('%+.3f',(c['kg1']-c['kg0'])/1000.0)}</td></tr></table>"+
  "<h2>Poz poz (#{ch.length} değişen)</h2><table><tr><th class='l'>Poz</th><th>Adet önce</th><th>Adet şimdi</th><th>kg önce</th><th>kg şimdi</th><th>Fark kg</th><th class='l'>Durum</th></tr>#{tr}</table>"))
 UI.openURL("file:///#{f.tr('\\','/')}") rescue nil
 UI.messagebox(format("%s: önce %.3f t → şimdi %.3f t (%+.3f t), %d poz değişti.\n%s",element_visible_id(e),c['kg0']/1000.0,c['kg1']/1000.0,(c['kg1']-c['kg0'])/1000.0,ch.length,f))
 ch.length
rescue => ex
 UI.messagebox("Revizyon karşılaştırması: #{ex.message}")
 0
end

# ---------------------------------------------------------------- CK1 elemanlar arası çakışma
def mst_rt_segdist(p1,q1,p2,q2)
 d1=[q1[0]-p1[0],q1[1]-p1[1],q1[2]-p1[2]];d2=[q2[0]-p2[0],q2[1]-p2[1],q2[2]-p2[2]];r=[p1[0]-p2[0],p1[1]-p2[1],p1[2]-p2[2]]
 dot=->(x,y){x[0]*y[0]+x[1]*y[1]+x[2]*y[2]}
 a=dot.(d1,d1);e=dot.(d2,d2);f=dot.(d2,r);c=dot.(d1,r);b=dot.(d1,d2);den=a*e-b*b
 s=den>1e-12 ? [[(b*f-c*e)/den,0.0].max,1.0].min : 0.0
 t=e>1e-12 ? (b*s+f)/e : 0.0
 if t<0 then t=0.0;s=a>1e-12 ? [[-c/a,0.0].max,1.0].min : 0.0
 elsif t>1 then t=1.0;s=a>1e-12 ? [[(b-c)/a,0.0].max,1.0].min : 0.0 end
 [Math.sqrt((0..2).sum{|k|(p1[k]+d1[k]*s-p2[k]-d2[k]*t)**2}),(0..2).map{|k|p1[k]+d1[k]*s}]
end
def mst_rt_world_tr(e);e.respond_to?(:transformation) ? e.transformation : Geom::Transformation.new;end
# elems: donatılı elemanlar; çubuklar dünya koordinatında; yalnız farklı elemanların çubukları karşılaştırılır
def mst_rt_clashes(elems,cell=0.5,tol=0.002)
 data=elems.map do |e|
  tr=mst_rt_world_tr(e)
  bs=mst_rt_bars(e).select{|b|b[:pts]}.map{|b|b.merge(w:b[:pts].map{|q|mst_rt_xf(tr,q)})}
  next nil if bs.empty?
  all=bs.flat_map{|b|b[:w]};lo=(0..2).map{|k|all.map{|q|q[k]}.min-0.1};hi=(0..2).map{|k|all.map{|q|q[k]}.max+0.1}
  {e:e,id:element_visible_id(e),bars:bs,lo:lo,hi:hi}
 end.compact
 hits=[]
 data.combination(2).each do |a,b|
  next unless (0..2).all?{|k|a[:lo][k]<=b[:hi][k] && b[:lo][k]<=a[:hi][k]}
  lo=(0..2).map{|k|[a[:lo][k],b[:lo][k]].max};hi=(0..2).map{|k|[a[:hi][k],b[:hi][k]].min}
  inb=->(p,q){(0..2).all?{|k|[p[k],q[k]].max>=lo[k] && [p[k],q[k]].min<=hi[k]}}
  grid=Hash.new{|h,k|h[k]=[]}
  cells=->(p,q){l=(0..2).map{|k|(([p[k],q[k]].min-0.05)/cell).floor};h=(0..2).map{|k|(([p[k],q[k]].max+0.05)/cell).floor}
   o=[];(l[0]..h[0]).each{|x|(l[1]..h[1]).each{|y|(l[2]..h[2]).each{|z|o << [x,y,z]}}};o}
  b[:bars].each_with_index{|br,i|br[:w].each_cons(2){|p,q|next unless inb.(p,q);cells.(p,q).each{|c|grid[c] << [i,p,q]}}}
  a[:bars].each do |ar|
   hit=nil
   ar[:w].each_cons(2) do |p,q|
    next unless inb.(p,q)
    seen={}
    cells.(p,q).each do |c|
     grid.fetch(c,[]).each do |i,p2,q2|
      next if seen[[i,p2]];seen[[i,p2]]=true
      br=b[:bars][i];dd,at=mst_rt_segdist(p,q,p2,q2)
      if dd<(ar[:d]+br[:d])/2000.0-tol
       hit=[br,at,dd];break
      end
     end
     break if hit
    end
    break if hit
   end
   hits << {a:a[:id],b:b[:id],bar_a:ar,bar_b:hit[0],at:hit[1],dist:hit[2]} if hit
  end
 end
 hits
end
def mst_rt_clash_ui
 model=Sketchup.active_model
 all=[];collect_elements(model.entities,all)
 es=all.select{|x|(!mst_rt_sets(x).empty? rescue false)}
 raise 'Donatısı 3B çizilmiş en az iki eleman gerekli.' if es.length<2
 hits=mst_rt_clashes(es)
 if hits.empty?
  UI.messagebox("Elemanlar arası donatı çakışması yok (#{es.length} eleman tarandı).");return 0
 end
 pairs=hits.group_by{|h|[h[:a],h[:b]]}.map{|(a,b),hs|"#{a} ↔ #{b}: #{hs.length} çubuk"}
 msg="#{hits.length} çakışan çubuk (#{es.length} eleman):\n#{pairs.first(15).join("\n")}\n\nÇakışan çubuklar kırmızıya boyansın mı? (tek Geri Al; 'Çakışma Renklerini Temizle' ile geri döner)"
 return hits.length unless UI.messagebox(msg,MB_YESNO)==IDYES
 model.start_operation('MST Donatı Çakışması Boya',true)
 begin
  mat=(material_for(model,'MST Çakışma','#E00000') rescue nil)
  hits.each{|h|[h[:bar_a][:inst],h[:bar_b][:inst]].each{|i|next unless i && i.valid?;i.set_attribute(DICT,'clash',1);i.material=mat if mat}}
  model.commit_operation
 rescue
  model.abort_operation;raise
 end
 mst_rt_set_visible!(true,model) unless mst_rt_visible?(model)
 hits.length
rescue => ex
 UI.messagebox("Çakışma kontrolü: #{ex.message}")
 0
end
def mst_rt_clash_clear_ui
 model=Sketchup.active_model
 all=[];collect_elements(model.entities,all);n=0
 model.start_operation('MST Çakışma Renklerini Temizle',true)
 all.each do |e|
  mst_rt_bars(e).each do |b|
   i=b[:inst];next unless i && i.valid? && i.get_attribute(DICT,'clash')
   i.delete_attribute(DICT,'clash');i.material=(mst_rebar_dia_material(model,b[:d]) rescue nil);n+=1
  end
 end
 model.commit_operation
 UI.messagebox("#{n} çubuğun çakışma rengi temizlendi.")
 n
rescue => ex
 model.abort_operation rescue nil
 UI.messagebox("Çakışma renkleri: #{ex.message}")
 0
end

end
end
