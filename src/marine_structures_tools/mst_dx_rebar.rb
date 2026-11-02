# frozen_string_literal: true
# v0.50 DX1 — Paftadan donatı metrajı (DXF): proje donatı paftasının bükme krokilerinden poz tablosu.
#  Her kroki satırı: poz balonu (numara) + "adet Ø çap / aralık" yazısı + "L = boy" yazısı (MAG katman adları; katmandan bağımsız
#  da çalışır: yazıların biçiminden ve yan yana duruşundan bulunur). "16+6Ø32" → 22, "2x25Ø12/20" → 50, "Ø16/15" (adetsiz) atlanır.
#  Aynı poz birden çok krokide (kesit kesit) → adetler toplanır. Boylar yazıdan (alan kodlu ölçüler okunmaz, toplam boy yeterli).
#  Sonuç: seçili elemanın donatı metrajı paftadan (Ø ve poz bazında; BOQ / hakediş / çap metrajı bunu kullanır) ya da yalnız
#  karşılaştırma (modeldeki 3B / pursantaj donatı ↔ pafta). 3B yerleşim parametrik araçlarla (BK / prekast / döşeme donatısı).
require 'json'
module MAG
module MarineStructuresTools

MST_DXR_TYPES=%w[head_beam deck_slab flat_precast channel_precast crane_precast crown_wall].freeze

# "13Ø16", "2x25Ø12/20 - A/Ü", "18+4Ø32", "Ø16/15", "147Ø16/15" → {'n','d','s'}
def mst_dxr_parse_cd(t)
 s=t.to_s.tr('×','x').gsub(/\s+/,'')
 m=s.match(/\A(?:(\d+)x)?(\d+(?:\+\d+)*)?Ø(\d+(?:[.,]\d+)?)(?:\/(\d+(?:[.,]\d+)?))?/i)
 return nil unless m
 k=(m[1] || '1').to_i;n=m[2] ? m[2].split('+').map(&:to_i).sum : nil
 {'n'=>n ? k*n : nil,'d'=>m[3].tr(',','.').to_f,'s'=>m[4] ? m[4].tr(',','.').to_f : nil,'raw'=>t.to_s}
end
# lu: birimsiz "L = …" değerinin 1 biriminin metre karşılığı (v0.51.5: $INSUNITS ya da kullanıcı; varsayılan 1.0 = m, eski davranış)
def mst_dxr_parse_l(t,lu=1.0)
 m=t.to_s.match(/L\s*=\s*(\d+(?:[.,]\d+)?)\s*(mm|cm|m)?/i)
 return nil unless m
 v=m[1].tr(',','.').to_f
 return v*lu if m[2].nil?
 v=v/100.0 if m[2].to_s.downcase=='cm';v=v/1000.0 if m[2].to_s.downcase=='mm'
 v
end
# v0.51.5 DXF birim: paftada birimsiz "L = …" yazısı var mı
def mst_dxr_unitless_l?(fl)
 fl.any?{|e|%w[TEXT MTEXT ATTRIB].include?(e['t']) && e['text'].to_s=~/\AL\s*=\s*\d/i && e['text'].to_s.match(/L\s*=\s*\d+(?:[.,]\d+)?\s*(mm|cm|m)?/i)[1].nil?}
end
# Birimsiz "L =" boylarının birimi: $INSUNITS biliniyorsa o (mst_dxf.rb MST_DXF_INSUNITS), yoksa kullanıcıya sorulur.
# => [metre/birim, açıklama] | nil (kullanıcı vazgeçti). Varsayım önizleme metninde gösterilir.
def mst_dxr_l_unit(dx,fl)
 return [1.0,'yok (bütün L yazıları birimli)'] unless mst_dxr_unitless_l?(fl)
 u=MST_DXF_INSUNITS[dx['insunits'].to_i]
 return [u,"#{mst_dxf_unit_name(u)} ($INSUNITS #{dx['insunits'].to_i})"] if u
 # v0.51.5 H6: ön seçim yok (önceden m); seçilmezse nil (iptal)
 u=mst_dxf_ask_unit('Birimsiz "L = …" boyları hangi birimde?',"Paftadan Donatı — birim ($INSUNITS #{dx['insunits'].to_i}: tanımsız)")
 return nil unless u
 [u,"#{mst_dxf_unit_name(u)} (kullanıcı seçimi; $INSUNITS tanımsız)"]
end

# fl: mst_dxf_flatten → {'rows'=>[kroki], 'table'=>[poz], 'unmatched'=>[L yazısı], 'no_count'=>[...]}
def mst_dxr_scan(fl,lu=1.0)
 tx=fl.select{|e|%w[TEXT MTEXT ATTRIB].include?(e['t']) && e['text'].to_s.strip!='' && e['x'] && e['y']}
 ls=tx.select{|e|e['text']=~/\AL\s*=\s*\d/i}
 cds=tx.select{|e|e['text']=~/Ø\s*\d/ && mst_dxr_parse_cd(e['text'])}
 pzs=tx.select{|e|e['text'].strip=~/\A\d{1,3}\z/}
 rows=[];un=[];nocount=[]
 used=Hash.new(false)
 ls.each do |l|
  h=[l['h'].to_f,1e-6].max
  c=cds.select{|q|(q['y']-l['y']).abs<2.0*h && q['x']<l['x']+0.5*h && l['x']-q['x']<60*h}.min_by{|q|[(l['x']-q['x']).abs,(q['y']-l['y']).abs]}
  (un << l['text'];next) unless c
  hc=[c['h'].to_f,h].max
  pz=pzs.select{|q|(q['y']-c['y']).abs<1.5*hc && q['x']<c['x']+0.5*hc && c['x']-q['x']<6*hc}.min_by{|q|c['x']-q['x']}
  cd=mst_dxr_parse_cd(c['text']);len=mst_dxr_parse_l(l['text'],lu)
  (nocount << "#{pz ? pz['text'] : '?'}: #{c['text']} #{l['text']}";next) if cd['n'].nil? || cd['n']<=0
  rows << {'poz'=>(pz ? pz['text'].strip.to_i : 0),'n'=>cd['n'],'d'=>cd['d'],'s'=>cd['s'],'len'=>len,'cd'=>c['text'],'l'=>l['text'],'x'=>l['x'],'y'=>l['y']}
 end
 tab=rows.group_by{|r|[r['poz'],r['d'],r['len'].round(3)]}.map do |(pz,d,len),rs|
  n=rs.sum{|r|r['n']}
  {'poz'=>pz,'d'=>d,'len'=>len,'n'=>n,'sketches'=>rs.length,'kg'=>n*len*d*d/162.0,'texts'=>rs.map{|r|r['cd']}.uniq}
 end.sort_by{|r|[r['poz'],r['d'],r['len']]}
 {'rows'=>rows,'table'=>tab,'unmatched'=>un,'no_count'=>nocount}
end
def mst_dxr_by_d(tab)
 h=Hash.new(0.0);tab.each{|r|h[r['d'].round]+=r['kg']};h.sort.to_h
end
# modeldeki donatı Ø bazında (rebar_schedule_json; yoksa toplam)
def mst_dxr_model_by_d(e)
 sch=(JSON.parse(e.get_attribute(DICT,'rebar_schedule_json','').to_s) rescue nil)
 h=Hash.new(0.0)
 sch.each{|k,v|d=k.to_s[/Ø\s*(\d+)/,1];h[d.to_i]+=v['kg'].to_f if d && v.is_a?(Hash)} if sch.is_a?(Hash)
 h
end
def mst_dxr_text(e,sc,file)
 tab=sc['table'];kg=tab.sum{|r|r['kg']}
 vol=(qto3_quantity(e,:concrete_m3) rescue 0.0).to_f
 cur=(mst_element_rebar(e) rescue {'kg'=>0.0,'source'=>'-'})
 l=["PAFTADAN DONATI — #{File.basename(file.to_s)} → #{element_visible_id(e)} (önizleme)",
    "Kroki: #{sc['rows'].length} · poz satırı: #{tab.length}#{sc['unmatched'].empty? ? '' : " · eşleşmeyen L yazısı: #{sc['unmatched'].length}"}#{sc['no_count'].empty? ? '' : " · adetsiz: #{sc['no_count'].length}"}",'',
    'Poz   Ø     Adet     Boy (m)     Ağırlık (kg)']
 tab.first(60).each{|r|l << format('%-4s Ø%-3d %6d  %9.3f  %12.1f%s',r['poz']>0 ? format('%02d',r['poz']) : '?',r['d'].round,r['n'],r['len'],r['kg'],r['sketches']>1 ? "  (#{r['sketches']} kroki)" : '')}
 l << "  … (#{tab.length-60} satır daha)" if tab.length>60
 l << '' << 'Ø bazında:   pafta         model'
 md=mst_dxr_model_by_d(e)
 (mst_dxr_by_d(tab).keys|md.keys).sort.each{|d|l << format('  Ø%-3d %10.1f kg %10.1f kg',d,mst_dxr_by_d(tab)[d].to_f,md[d].to_f)}
 l << format('TOPLAM pafta %.3f t%s · modelde şimdi %.3f t (%s)',kg/1000.0,vol>0 ? format(' (%.0f kg/m³)',kg/vol) : '',cur['kg'].to_f/1000.0,cur['source'])
 l << "Birimsiz \"L =\" boyları: #{sc['l_unit']}" if sc['l_unit']   # v0.51.5 DXF birim varsayımı görünür
 sc['no_count'].first(4).each{|x|l << "  adetsiz (atlandı): #{x}"}
 sc['unmatched'].first(4).each{|x|l << "  eşleşmeyen: #{x}"}
 l.join("\n")
end
# elemanın metrajı paftadan (çağıranın işlemi içinde). 3B donatı varsa görsel kalır, metraj paftadan.
def mst_dxr_apply!(e,sc,file)
 tab=sc['table'];kg=tab.sum{|r|r['kg']}
 mst_rt_history_push!(e) if respond_to?(:mst_rt_history_push!)
 if e.get_attribute(DICT,'rebar_prev_pafta_json','').to_s.empty? && e.get_attribute(DICT,'rebar_kind','').to_s!='PAFTA'
  prev=Hash[%w[rebar_mode rebar_t rebar_kg rebar_kind rebar_drawing rebar_schedule_json rebar_source rebar_bar_count].map{|k|[k,e.get_attribute(DICT,k)]}]
  e.set_attribute(DICT,'rebar_prev_pafta_json',JSON.generate(prev))
 end
 sch={}
 tab.each{|r|k=format('Poz %s Ø%d',r['poz']>0 ? format('%02d',r['poz']) : '?',r['d'].round);k+=" L#{r['len']}" if sch.key?(k);sch[k]={'count'=>r['n'],'length_m'=>r['n']*r['len'],'kg'=>r['kg'],'shape'=>r['texts'].first.to_s}}
 {'rebar_mode'=>'drawing_detail','rebar_t'=>kg/1000.0,'rebar_kg'=>kg,'rebar_kind'=>'PAFTA','rebar_drawing'=>File.basename(file.to_s),
  'rebar_schedule_json'=>JSON.generate(sch),'rebar_source'=>"Pafta (DXF): #{File.basename(file.to_s)}",'rebar_bar_count'=>tab.sum{|r|r['n']},
  'rebar_pafta_json'=>JSON.generate(tab.map{|r|r.reject{|k,_|k=='texts'}})}.each{|k,v|e.set_attribute(DICT,k,v)}
 kg
end
def mst_dxr_clear!(e)
 return false unless e.get_attribute(DICT,'rebar_kind','').to_s=='PAFTA'
 mst_rt_history_push!(e) if respond_to?(:mst_rt_history_push!)
 %w[rebar_mode rebar_kg rebar_kind rebar_drawing rebar_schedule_json rebar_source rebar_bar_count rebar_pafta_json].each{|k|e.delete_attribute(DICT,k)}
 prev=(JSON.parse(e.get_attribute(DICT,'rebar_prev_pafta_json','').to_s) rescue nil)
 e.delete_attribute(DICT,'rebar_prev_pafta_json')
 if prev.is_a?(Hash) && !prev['rebar_mode'].to_s.empty?
  prev.each{|k,v|v.nil? ? e.delete_attribute(DICT,k) : e.set_attribute(DICT,k,v)}   # önceki 3B / BIM donatı metrajına dön
 else
  key=MST_REBAR_RATE_KEYS[e.get_attribute(DICT,'element_type','').to_s]
  e.set_attribute(DICT,'rebar_t',qto3_quantity(e,:concrete_m3)*rebar_rate(key)/1000.0) if key
 end
 true
end
def mst_dxr_ui(path=nil)
 model=Sketchup.active_model
 sel=[];mst_collect_elements_raw(model.selection,sel)
 es=sel.select{|x|x.valid? && MST_DXR_TYPES.include?(x.get_attribute(DICT,'element_type','').to_s)}.uniq
 raise "Paftanın ait olduğu eleman(lar)ı seçin (BK / döşeme / prekast / kronman). Aynı tipteki bütün elemanlar seçilebilir; metraj her birine yazılır." if es.empty?
 path||=UI.openpanel('Donatı paftası (DXF)',nil,'DXF|*.dxf||')
 return 0 unless path && File.file?(path)
 t0=Time.now
 dx=mst_dxf_read(path,%w[TEXT MTEXT INSERT ATTRIB])
 fl=mst_dxf_flatten(dx)
 lu,lnote=mst_dxr_l_unit(dx,fl)   # v0.51.5: birimsiz L → $INSUNITS ya da kullanıcı (önceden hep metre)
 return 0 unless lu
 sc=mst_dxr_scan(fl,lu);sc['l_unit']=lnote
 raise 'Paftada "L = …" boylu kroki satırı bulunamadı (poz balonu + "adet Ø" + "L =" yazıları).' if sc['table'].empty?
 txt=mst_dxr_text(es[0],sc,path)+format("\n(okuma %.1f s)",Time.now-t0);puts txt
 r=UI.messagebox("#{txt[0,2800]}\n\nEVET: #{es.length} elemanın donatı metrajı bu paftadan alınsın (3B donatı varsa görsel kalır).\nHAYIR: yalnız karşılaştırma (model değişmez).",MB_YESNO)
 return 0 unless r==IDYES
 model.start_operation('MST Paftadan Donatı Metrajı',true)
 begin
  es.each{|e|mst_dxr_apply!(e,sc,path)}
  model.commit_operation
 rescue
  model.abort_operation;raise
 end
 send_boq(@d) if @d rescue nil
 UI.messagebox(format("%d elemanın donatısı paftadan: %.3f t / eleman. Silmek için yine bu araç → seçili elemanlarda 'Paftadan donatıyı kaldır'.",es.length,sc['table'].sum{|x|x['kg']}/1000.0))
 es.length
rescue => ex
 UI.messagebox("Paftadan donatı: #{ex.message}")
 0
end
def mst_dxr_remove_ui
 model=Sketchup.active_model
 sel=[];mst_collect_elements_raw(model.selection,sel)
 es=sel.select{|x|x.valid? && x.get_attribute(DICT,'rebar_kind','').to_s=='PAFTA'}.uniq
 raise 'Paftadan metrajı olan eleman seçin.' if es.empty?
 return 0 unless UI.messagebox("#{es.length} elemanda paftadan donatı metrajı kaldırılsın mı? (pursantaja / 3B donatıya döner)",MB_YESNO)==IDYES
 model.start_operation('MST Paftadan Donatıyı Kaldır',true)
 begin;es.each{|e|mst_dxr_clear!(e)};model.commit_operation;rescue;model.abort_operation;raise;end
 es.length
rescue => ex
 UI.messagebox("Paftadan donatı: #{ex.message}")
 0
end

end
end
