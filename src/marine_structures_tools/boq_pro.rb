# frozen_string_literal: true
# v0.47 BQ1 — BOQ ve Hakediş genişletmesi
#  · Proje poz listesi (düzenlenebilir, elle miktarlı poz, dışa/içe aktarım)
#  · Beton sınıfına göre ayrı poz (isteğe bağlı)
#  · Sözleşme para birimi, kur, fiyat tarihi
#  · İş kalemi bazında ilerleme (eleman × poz: beyan + tarihli onay geçmişi)
#  · Dönem tarihi, eksilen miktar uyarısı, fiyat farkı, KDV ve kesintiler, icmal
#  · Modelde ilerleme görünümü (durumuna göre seç / yalnız göster)
#  · Keşif Cetveli ve Hakediş Raporu Excel, revizyonlar arası keşif farkı
# Var olan fonksiyonlar alias ile korunur; eski modeller (eleman durumu "Onaylandı") aynen çalışır.
require 'json'
module MAG
module MarineStructuresTools

BOQ2_DICT='MAG_MST_BOQ2'.freeze
BOQ2_SPLIT_SOURCES=%w[HB_DECK_CONCRETE CROWN_CONCRETE].freeze
BOQ2_CURRENCIES=%w[USD EUR TRY].freeze
BOQ2_CONTRACT_PRESETS={
 'ozel'=>{'type'=>'ozel','vat_pct'=>20.0,'deductions'=>[
   {'name'=>'Avans mahsubu','base'=>'tutar','pct'=>0.0},
   {'name'=>'Teminat kesintisi (retention)','base'=>'tutar','pct'=>5.0}]},
 'kamu'=>{'type'=>'kamu','vat_pct'=>20.0,'deductions'=>[
   {'name'=>'Damga vergisi (binde 9,48)','base'=>'tutar','pct'=>0.948},
   {'name'=>'KDV tevkifatı (4/10)','base'=>'kdv','pct'=>40.0},
   {'name'=>'Teminat kesintisi','base'=>'tutar','pct'=>0.0},
   {'name'=>'Avans mahsubu','base'=>'tutar','pct'=>0.0}]}
}.freeze

# ---------------------------------------------------------------- ayar deposu
def boq2_get(key,default=nil)
 v=Sketchup.active_model.get_attribute(BOQ2_DICT,key,nil)
 v.nil? ? default : v
end
def boq2_json(key,default)
 v=boq2_get(key,nil)
 return default if v.nil? || v.to_s.empty?
 r=(JSON.parse(v.to_s) rescue nil)
 r.nil? ? default : r
end
def boq2_set(key,value)
 Sketchup.active_model.set_attribute(BOQ2_DICT,key,value)
end
def boq2_today;Time.now.strftime('%Y-%m-%d');end
def boq2_user;(ENV['USERNAME'] || ENV['USER'] || 'kullanıcı').to_s;end
def boq2_date_ok?(s);s.to_s.match?(/\A\d{4}-\d{2}-\d{2}\z/);end
def boq2_num(v);(Float(v.to_s.strip.tr(',','.')) rescue nil);end
def boq2_has_history?;!progress_history.empty?;end

# ---------------------------------------------------------------- 3 · poz listesi
def boq2_source_labels
 h={}
 BOQ_TEMPLATE.each{|c,n,u,_,s|h[s]="#{c} · #{n} (#{u})"}
 h
end
def boq2_default_items
 BOQ_TEMPLATE.map{|c,n,u,p,s|{'code'=>c,'name'=>n,'unit'=>u,'price'=>p,'source'=>s,'active'=>true}}
end
def boq2_items
 a=boq2_json('items_json',nil)
 a.is_a?(Array) && !a.empty? ? a : boq2_default_items
end
# fiyatı kütüphaneden gelen kaynaklar (poz listesindeki fiyat kullanılmaz)
def boq2_library_sources
 s=BOQ_LIBRARY_IDS.keys+['PILE_DRILLING']
 s+=(boq_project_mapping.keys rescue [])
 s.uniq
end
def boq2_stored_price(code)
 Sketchup.active_model.get_attribute(DICT,"boq_price_#{code}",nil)
end
# arayüzde gösterilen poz listesi: fiyat = geçerli fiyat (BOQ sayfasında girilen fiyat dahil)
def boq2_items_effective
 lib=boq2_library_sources
 boq2_items.map do |h|
  h=h.dup
  if lib.include?(h['source'].to_s)
   h['library']=true
  else
   sp=boq2_stored_price(h['code'])
   h['price']=sp.to_f unless sp.nil? || sp.to_s.strip.empty?
  end
  h
 end
end
# BOQ_TEMPLATE yerine kullanılan proje poz listesi (yalnız etkin pozlar)
def boq_template
 boq2_items.reject{|h|h['active']==false}.map{|h|[h['code'].to_s,h['name'].to_s,h['unit'].to_s,(h['price'].nil? || h['price'].to_s.strip.empty? ? nil : h['price'].to_f),h['source'].to_s]}
end
def boq2_manual?(src);src.to_s.start_with?('MANUAL:');end
def boq2_validate_items(items)
 err=[]
 raise 'Poz listesi okunamadı.' unless items.is_a?(Array)
 err << 'Poz listesi boş olamaz.' if items.empty?
 known=BOQ_TEMPLATE.map{|r|r[4]}
 codes={};srcs={};manual={}
 items.each_with_index do |h,i|
  n="Satır #{i+1}"
  unless h.is_a?(Hash);err << "#{n}: geçersiz.";next;end
  code=h['code'].to_s.strip;src=h['source'].to_s.strip
  err << "#{n}: poz no boş." if code.empty?
  err << "#{n}: birim boş." if h['unit'].to_s.strip.empty?
  err << "#{n}: tanım boş." if h['name'].to_s.strip.empty?
  err << "#{n}: poz no '#{code}' tekrarlanıyor." if !code.empty? && codes[code]
  err << "#{n}: poz no '#', '@' içeremez." if code.match?(/[#@]/)
  codes[code]=true
  if boq2_manual?(src)
   q=boq2_num(h['qty'])
   err << "#{n}: elle miktar sayı olmalı." if q.nil? || q<0
   err << "#{n}: elle miktar kimliği tekrarlanıyor (#{src})." if manual[src]
   err << "#{n}: elle miktar kimliği geçersiz." if src.match?(/[#@]/) || src.length<8
   manual[src]=true
  elsif !known.include?(src)
   err << "#{n}: miktar kaynağı tanınmıyor (#{src})."
  elsif h['active']!=false
   err << "#{n}: '#{src}' kaynağı başka bir pozda da kullanılıyor; aynı miktar iki kez sayılır." if srcs[src]
   srcs[src]=true
  end
  pr=h['price'].to_s.strip
  err << "#{n}: birim fiyat sayı olmalı." unless pr.empty? || boq2_num(pr)
  err << "#{n}: birim fiyat negatif olamaz." if !pr.empty? && boq2_num(pr).to_f<0
 end
 err
end
def boq2_clean_items(items)
 items.map do |h|
  pr=h['price'].to_s.strip
  r={'code'=>h['code'].to_s.strip,'name'=>h['name'].to_s.strip,'unit'=>h['unit'].to_s.strip,'source'=>h['source'].to_s.strip,
     'price'=>(pr.empty? ? nil : boq2_num(pr)),'active'=>h['active']!=false}
  r['qty']=boq2_num(h['qty']).to_f if boq2_manual?(r['source'])
  r
 end
end
# poz listesindeki fiyat = BOQ fiyatı: boq_price_<kod> özniteliği yazılır / silinir; kodu değişen pozun eski fiyatı temizlenir
def boq2_write_prices(old_items,new_items)
 model=Sketchup.active_model
 lib=boq2_library_sources
 new_codes={};new_items.each{|h|new_codes[h['code']]=true}
 old_items.each do |o|
  nw=new_items.find{|h|h['source']==o['source']}
  next unless nw && nw['code']!=o['code'] && !new_codes[o['code']]
  ad=model.attribute_dictionary(DICT,false) rescue nil
  ad.delete_key("boq_price_#{o['code']}") if ad && ad.respond_to?(:delete_key)
 end
 new_items.each do |h|
  next if lib.include?(h['source'])
  if h['price'].nil?
   ad=model.attribute_dictionary(DICT,false) rescue nil
   ad.delete_key("boq_price_#{h['code']}") if ad && ad.respond_to?(:delete_key)
  else
   model.set_attribute(DICT,"boq_price_#{h['code']}",h['price'].to_f)
  end
 end
end
def boq2_save_items(raw)
 items=raw.is_a?(String) ? JSON.parse(raw) : raw
 items=items['items'] if items.is_a?(Hash)
 err=boq2_validate_items(items)
 raise err.first(12).join("\n") unless err.empty?
 clean=boq2_clean_items(items)
 old=boq2_items
 model=Sketchup.active_model
 model.start_operation('MST Poz Listesi',true)
 begin
  boq2_set('items_json',JSON.generate(clean))
  boq2_write_prices(old,clean)
  pile_boq_codes_persist!(model) if respond_to?(:pile_boq_codes_persist!)   # v0.51.5 K35
  model.commit_operation
 rescue
  model.abort_operation;raise
 end
 true
end
def boq2_reset_items
 model=Sketchup.active_model
 model.start_operation('MST Poz Listesi Sıfırla',true)
 begin
  ad=model.attribute_dictionary(BOQ2_DICT,true)
  ad.respond_to?(:delete_key) ? ad.delete_key('items_json') : boq2_set('items_json','')
  model.commit_operation
 rescue
  model.abort_operation;raise
 end
 true
end
def boq2_items_export
 path=UI.savepanel('Poz Listesini Dışa Aktar','','MST_Poz_Listesi.json');return unless path
 path+='.json' unless path.downcase.end_with?('.json')
 File.write(path,JSON.pretty_generate({'schema'=>'mst.boq.items.v1','items'=>boq2_items_effective.map{|h|h.reject{|k,_|k=='library'}}}),encoding:'UTF-8')
 UI.messagebox("Poz listesi kaydedildi:\n#{path}")
end
def boq2_items_import
 path=UI.openpanel('Poz Listesi JSON','','JSON|*.json||');return unless path
 d=JSON.parse(File.read(path,encoding:'UTF-8'))
 items=d.is_a?(Hash) ? d['items'] : d
 boq2_save_items(items)
 UI.messagebox("#{items.length} poz içe aktarıldı (tek Geri Al).")
end

# ---------------------------------------------------------------- 4 · para birimi
def boq2_currency
 c=boq2_get('currency','USD').to_s
 BOQ2_CURRENCIES.include?(c) ? c : 'USD'
end
def boq2_fx
 f=boq2_json('fx_json',{})
 {'TRY'=>1.0,'USD'=>(f['USD']||1.0).to_f,'EUR'=>(f['EUR']||1.0).to_f}
end
# 1 'from' kaç 'to' eder (kurlar TL karşılığıdır)
def boq2_convert(v,from,to)
 from='TRY' if from.to_s=='TL';to='TRY' if to.to_s=='TL'
 return v if from==to || v.nil?
 fx=boq2_fx;a=fx[from].to_f;b=fx[to].to_f
 raise "#{from}/#{to} kuru tanımlı değil." unless a>0 && b>0
 v*a/b
end
def boq2_settings
 {'currency'=>boq2_currency,'fx'=>boq2_fx,'price_date'=>boq2_get('price_date','').to_s,'split_concrete'=>boq2_split?,
  'split_locked'=>boq2_has_history?}
end
def boq2_save_settings(raw)
 d=raw.is_a?(String) ? JSON.parse(raw) : raw
 cur=d['currency'].to_s;raise 'Para birimi USD / EUR / TRY olmalı.' unless BOQ2_CURRENCIES.include?(cur)
 fx={};%w[USD EUR].each do |k|
  v=boq2_num(d.dig('fx',k));raise "#{k} kuru pozitif sayı olmalı." unless v && v>0
  fx[k]=v
 end
 pd=d['price_date'].to_s.strip;raise 'Fiyat tarihi YYYY-AA-GG olmalı.' unless pd.empty? || boq2_date_ok?(pd)
 split=d['split_concrete'] ? true : false
 if split!=boq2_split? && boq2_has_history?
  raise "Kaydedilmiş hakediş varken beton sınıf ayrımı değiştirilemez:\nönceki hakedişte ödenen miktarlar poz bazında eşleşmez.\n(Ayrım: #{boq2_split? ? 'açık' : 'kapalı'} kalır.)"
 end
 model=Sketchup.active_model
 model.start_operation('MST BOQ Ayarları',true)
 begin
  boq2_set('currency',cur);boq2_set('fx_json',JSON.generate(fx));boq2_set('price_date',pd)
  boq2_set('split_concrete',split ? '1' : '0')
  model.commit_operation
 rescue
  model.abort_operation;raise
 end
 true
end
# kazık poz gruplaması da hakediş geçmişi varken değiştirilemez (aynı neden)
if method_defined?(:boq_set_pile_modes)
 alias_method :boq_set_pile_modes_base, :boq_set_pile_modes unless method_defined?(:boq_set_pile_modes_base)
 def boq_set_pile_modes(payload)
  data=payload.is_a?(String) ? (JSON.parse(payload) rescue {}) : (payload || {})
  changed=data.any?{|k,m|PILE_BOQ_GROUP_KEYS.include?(k.to_s) && %w[combined separate].include?(m.to_s) && pile_boq_mode(k.to_s)!=m.to_s}
  if changed && boq2_has_history?
   UI.messagebox("Kaydedilmiş hakediş varken kazık poz gruplaması değiştirilemez:\nönceki hakedişte ödenen miktarlar poz bazında eşleşmez.")
   if @d && @d.visible?
    send_boq(@d)
    @d.execute_script("pileBoqSaved(#{JSON.generate(Hash[PILE_BOQ_GROUP_KEYS.map{|k|[k,pile_boq_mode(k)]}])});")
   end
   return
  end
  boq_set_pile_modes_base(payload)
 end
end

# ---------------------------------------------------------------- 2 · beton sınıfı
def boq2_split?;boq2_get('split_concrete','0').to_s=='1';end
def boq2_class_of(e)
 c=(qto_material_class(e).to_s rescue '').strip
 c.empty? || c=='-' ? 'Sınıfsız' : c
end
def boq2_split_rows(rows)
 out=[]
 rows.each do |r|
  base=r[:source].to_s
  unless BOQ2_SPLIT_SOURCES.include?(base) && r[:quantity].to_f>0
   out << r;next
  end
  by=Hash.new(0.0)
  boq_trace_entities_base(base).each{|e|q=progress_entity_quantity_base(e,base).to_f;by[boq2_class_of(e)]+=q if q>0}
  sum=by.values.sum
  if by.empty? || sum<=0
   out << r;next
  end
  # eleman toplamı BOQ miktarından farklıysa (yuvarlama / toplu hesap) sınıflar oransal ölçeklenir
  f=r[:quantity].to_f/sum
  by.sort.each do |cls,q0|
   q=q0*f
   code="#{r[:code]}/#{cls}"
   price=if r[:library_price] then r[:unit_price]
         elsif r[:unit_price].nil? then (sp=boq2_stored_price(code)).nil? ? nil : sp.to_f
         else boq_price(code,r[:unit_price])
         end
   out << r.merge(code:code,name:"#{r[:name]} — #{cls}",quantity:q,unit_price:price,total:(price.nil? ? nil : q*price.to_f),
                  status:(price.nil? ? 'FİYAT YOK' : r[:status]),source:"#{base}##{cls}",split_parent:r[:code])
  end
 end
 out
end

# ---------------------------------------------------------------- kütüphane fiyatı → sözleşme para birimi
def boq2_fx_row!(r,cur=boq2_currency)
 return r if r[:fx_done] || !r[:library_price]
 r[:fx_done]=true
 return r if cur=='USD' || r[:unit_price].nil?
 r[:unit_price]=boq2_convert(r[:unit_price].to_f,'USD',cur)
 r[:price_note]="Kütüphane fiyatı USD → #{cur} (kur #{format('%.4f',boq2_convert(1.0,'USD',cur))})"
 r[:total]=r[:quantity].to_f*r[:unit_price].to_f
 r
end
# kazık "ayrı poz" genişletmesi kütüphane fiyatını kopyalar → genişletmeden ÖNCE çevrilir
alias_method :pile_boq_expand_rows_base, :pile_boq_expand_rows unless method_defined?(:pile_boq_expand_rows_base)
def pile_boq_expand_rows(rows)
 cur=boq2_currency
 rows.each{|r|boq2_fx_row!(r,cur)}
 pile_boq_expand_rows_base(rows)
end

# ---------------------------------------------------------------- boq_rows (2 + 3 + 4 birlikte)
alias_method :boq_rows_base, :boq_rows unless method_defined?(:boq_rows_base)
def boq_rows(include_inactive=false)
 rows=boq_rows_base(true)
 items=boq2_items.reject{|h|h['active']==false}
 cur=boq2_currency
 tmpl={};boq_template.each{|c,_,_,p,s|tmpl[s]=[c,p]}
 rows.each do |r|
  src=r[:source].to_s
  if boq2_manual?(src)
   it=items.find{|h|h['source']==src}
   r[:quantity]=it ? it['qty'].to_f : 0.0;r[:manual]=true
  end
  # boş fiyat = fiyat yok (0 değil)
  lib=r[:library_price] || r[:fx_done]   # kazık ayrı poz satırı kütüphane kökenini fx_done ile taşır
  if !lib && tmpl[src] && tmpl[src][1].nil? &&
     boq2_stored_price(r[:code]).nil? && (r[:split_parent_code].nil? || boq2_stored_price(r[:split_parent_code]).nil?)
   r[:unit_price]=nil
  end
  if r[:manual] || (!lib && tmpl[src])
   r[:total]=r[:unit_price].nil? ? nil : r[:quantity].to_f*r[:unit_price].to_f
   r[:status]=if r[:quantity].to_f<=0 then 'YOK'
              elsif r[:unit_price].nil? then 'FİYAT YOK'
              elsif r[:manual] then 'ELLE'
              else r[:status]
              end
  end
 end
 rows=boq2_split_rows(rows) if boq2_split?
 rows.each{|r|boq2_fx_row!(r,cur);r[:currency]=cur}
 include_inactive ? rows : rows.select{|r|r[:quantity].to_f>0}
end

# kaynak anahtarı "HB_DECK_CONCRETE#C30/37" → sınıfa göre süzülmüş elemanlar
alias_method :boq_trace_entities_base, :boq_trace_entities unless method_defined?(:boq_trace_entities_base)
def boq_trace_entities(source)
 base,cls=source.to_s.split('#',2)
 base=base.to_s.split('@',2)[0]
 es=boq_trace_entities_base(base)
 cls ? es.select{|e|boq2_class_of(e)==cls} : es
end
alias_method :progress_entity_quantity_base, :progress_entity_quantity unless method_defined?(:progress_entity_quantity_base)
def progress_entity_quantity(e,source)
 base=prog2_base(source)
 if base=='PILE_INFILL' && e.get_attribute(DICT,'element_type','').to_s=='steel_pipe_pile'
  # v0.51.5 K21 (S7): hata sessiz 0 değil — konsola yazılır; Model Kontrolü (mst_audit_v0515) aynı hesabı HATA olarak gösterir
  begin
   return pile_bim_qto_item(e)[:concrete_m3].to_f
  rescue => ex
   warn("MST ilerleme miktarı (kazık iç betonu, #{element_visible_id(e)}): #{ex.message}")
   return 0.0
  end
 end
 progress_entity_quantity_base(e,base)
end

# send_boq: para birimi ve ayarlar
alias_method :send_boq_base, :send_boq unless method_defined?(:send_boq_base)
def send_boq(dialog=@d)
 send_boq_base(dialog)
 dialog.execute_script("boq2Loaded(#{JSON.generate(boq2_payload)})") if dialog
rescue => e
 puts "MST BOQ2: #{e.message}"
end
def boq2_payload
 {items:boq2_items_effective,custom:!boq2_get('items_json',nil).to_s.empty?,sources:boq2_source_labels,settings:boq2_settings,
  contract:boq2_contract,library_sources:boq2_library_sources}
end

# ---------------------------------------------------------------- 5–7 · iş kalemi bazında ilerleme
# Satır anahtarı: normal satır = kaynak (eski "previous_<kaynak>" ile uyumlu); kazık "ayrı poz" satırı = kaynak@poz;
# beton sınıf satırı = kaynak#sınıf. İlerleme kaydı elemanda TEMEL kaynak altında tutulur (ayrım açılıp kapansa da kaybolmaz).
PROG2_KEY='progress_items_json'.freeze
def prog2_base(src);src.to_s.split('#',2)[0].to_s.split('@',2)[0].to_s;end
def prog2_row_key(r)
 src=r[:source].to_s
 r[:trace_pids] ? "#{src}@#{r[:code]}" : src
end
def prog2_row_entities(r)
 es=boq_trace_entities(r[:source].to_s)
 if r[:trace_pids]
  ids={};Array(r[:trace_pids]).each{|i|ids[i]=true}
  es=es.select{|e|ids[e.persistent_id]}
 end
 es
end
def prog2_find_row(key,rows=boq_rows(true))
 rows.find{|r|prog2_row_key(r)==key.to_s}
end
def prog2_items(e)
 h=(JSON.parse(e.get_attribute(DICT,PROG2_KEY,'{}').to_s) rescue {})
 h.is_a?(Hash) ? h : {}
end
# R-4 / K19: yazmadan önce okuma — yok/boş → {}, bozuk → hata (onay geçmişinin üzerine yazılmaz)
def prog2_items_for_write(e)
 raw=e.get_attribute(DICT,PROG2_KEY,nil)
 return {} if raw.nil? || raw.to_s.strip.empty?
 h=(JSON.parse(raw.to_s) rescue nil)
 raise "#{element_visible_id(e)}: ilerleme kaydı (#{PROG2_KEY}) okunamadı; onay geçmişinin üzerine yazılmadı. Bu elemana ilerleme girilmeden önce kayıt düzeltilmelidir." unless h.is_a?(Hash)
 h
end
# kayıt: {'claim'=>%, 'claim_date', 'claim_by', 'ok'=>[[tarih,%,kişi], …]} — onay geçmişi tarihe göre okunur
def prog2_norm(r)
 return nil unless r.is_a?(Hash)
 return r if r['ok'].is_a?(Array)
 {'claim'=>r['pct'].to_f,'claim_date'=>r['date'],'claim_by'=>r['by'],'ok'=>(r['ok'] ? [[r['date'].to_s,r['pct'].to_f,r['by'].to_s]] : [])}
end
def prog2_rec(e,src)
 h=prog2_items(e)
 prog2_norm(h[prog2_base(src)])
end
def prog2_clamp(p);[[p.to_f/100.0,0.0].max,1.0].min;end
# tarihe kadar geçerli son onay (aynı tarihte sonra girilen geçerli)
def prog2_ok_entry(rec,date=nil)
 list=Array(rec && rec['ok']).each_with_index.select{|x,_|x.is_a?(Array) && (date.nil? || x[0].to_s<=date.to_s)}
 return nil if list.empty?
 list.max_by{|x,i|[x[0].to_s,i]}[0]
end
def prog2_rec_frac(rec,date=nil)
 x=prog2_ok_entry(rec,date)
 x ? prog2_clamp(x[1]) : 0.0
end
def prog2_legacy_ok?(e);e.get_attribute(DICT,'progress_status','Planlandı').to_s=='Onaylandı';end
# onaylı oran: iş kalemi kaydı varsa onun geçmişi, yoksa eski eleman durumu ("Onaylandı" = %100)
def prog2_frac(e,src,date=nil)
 rec=prog2_rec(e,src)
 return prog2_rec_frac(rec,date) if rec
 prog2_legacy_ok?(e) ? 1.0 : 0.0
end
# yüklenici beyanı (onaysız dahil)
def prog2_claim(e,src)
 rec=prog2_rec(e,src)
 return [prog2_clamp(rec['claim']),prog2_rec_frac(rec)].max if rec
 %w[Tamamlandı Onaylandı].include?(e.get_attribute(DICT,'progress_status','Planlandı').to_s) ? 1.0 : 0.0
end
# yeni giriş: beyan her zaman güncellenir; "onaylı" ise onay geçmişine eklenir (aynı tarih → değiştirilir)
def prog2_rec_apply(rec,pct,ok,date,legacy_full=false)
 rec=rec ? JSON.parse(JSON.generate(rec)) : {'claim'=>0.0,'ok'=>(legacy_full ? [['0000-00-00',100.0,'eski durum']] : [])}
 rec['claim']=pct.to_f;rec['claim_date']=date;rec['claim_by']=boq2_user
 if ok
  rec['ok']=Array(rec['ok']).reject{|x|x[0].to_s==date.to_s}
  rec['ok'] << [date,pct.to_f,boq2_user]
 end
 rec
end
def prog2_manual
 h=(JSON.parse(Sketchup.active_model.get_attribute(PROGRESS_DICT,'manual_progress_json','{}').to_s) rescue {})
 h.is_a?(Hash) ? h : {}
end
# satırın onaylı miktarı (tarih verilirse o tarihe kadar onaylananlar)
def prog2_quantities(row,date=nil)
 src=row[:source].to_s;qty=row[:quantity].to_f;key=prog2_row_key(row)
 es=prog2_row_entities(row)
 if es.empty?
  m=prog2_norm(prog2_manual[key])
  a=m ? prog2_rec_frac(m,date) : 0.0
  c=m ? [prog2_clamp(m['claim']),prog2_rec_frac(m)].max : 0.0
  return {approved:qty*a,claimed:qty*c,manual:true,count:0}
 end
 # yalnız ilerlemesi olan elemanların miktarı hesaplanır (büyük modelde hızlı); eski kuralla aynı:
 # tam miktar varsa min(Σ, BOQ), yoksa eleman sayısı oranı
 fr=es.map{|e|[e,prog2_frac(e,src,date),prog2_claim(e,src)]}.select{|_,f,c|f>0 || c>0}
 return {approved:0.0,claimed:0.0,manual:false,count:es.length} if fr.empty?
 q=Hash[fr.map{|e,_,_|[e,progress_entity_quantity(e,src).to_f]}]
 ex_a=fr.sum{|e,f,_|q[e]*f};ex_c=fr.sum{|e,_,c|q[e]*c}
 if fr.any?{|e,_,_|q[e]>0}
  {approved:[ex_a,qty].min,claimed:[ex_c,qty].min,manual:false,count:es.length}
 elsif es.any?{|e|!q.key?(e) && progress_entity_quantity(e,src).to_f>0}
  # v0.51.5 08-R3: yedek yol miktar ağırlıklı — ilerlemeli elemanların miktarı 0, satırın miktarı başka elemanlarda:
  # eleman adedi oranı bu elemanlara pay vermez (ör. REBAR satırında donatısı 0 olan kazık)
  {approved:0.0,claimed:0.0,manual:false,count:es.length}
 else
  {approved:qty*fr.sum{|_,f,_|f}/es.length,claimed:qty*fr.sum{|_,_,c|c}/es.length,manual:false,count:es.length}
 end
end
def progress_approved_quantity(row,date=nil)
 prog2_quantities(row,date)[:approved]
end

def prog2_last_period(hist=progress_history)
 hist.max_by{|h|h['no'].to_i}
end
def prog2_rec_currency(rec);(rec && rec['currency']) || 'USD';end
def prog2_view_date;@prog2_view_date || boq2_today;end
def prog2_view_pd;@prog2_view_pd.to_f;end
def progress_live_rows(date=nil)
 model=Sketchup.active_model
 date||=prog2_view_date
 cur=boq2_currency
 seen={};out=[]
 last=prog2_last_period
 # önceki hakedişte ödenen tutar (kaydın para biriminden güncele): fiyatı sonradan silinen satırda gösterilir
 paid={}
 Array(last && last['rows']).each do |lr|
  k=(lr['key'] || lr['source']).to_s;next if k.empty? || lr['unit_price'].nil?
  paid[k]=boq2_convert((lr['approved_quantity'] || lr['previous'].to_f+lr['current_period'].to_f).to_f*lr['unit_price'].to_f,prog2_rec_currency(last),cur)
 end
 boq_rows(true).each do |r|
  key=prog2_row_key(r);next if seen[key]
  seen[key]=true
  previous=model.get_attribute(PROGRESS_DICT,"previous_#{key}",0).to_f
  q=prog2_quantities(r,date)
  next if r[:quantity].to_f<=0 && previous.abs<1e-12 && q[:approved]<=0
  current=q[:approved]-previous
  # v0.51.5 K34: REBAR tavanı (min Σ eleman, BOQ) değişmez; eleman eşlemesi olmayan donatı görünür kılınır
  k34=nil
  if prog2_base(r[:source])=='REBAR' && !r[:trace_pids] && r[:quantity].to_f>0
   begin
    gap=r[:quantity].to_f-prog2_row_entities(r).sum{|e|progress_entity_quantity(e,r[:source].to_s).to_f}
    k34="Hakedişe eleman bazında girmeyen donatı: #{format('%.3f',gap)} t (kaplama, aksesuar ankrajı, kazık kafesi; eleman ilerlemesiyle ödenmez)" if gap>1e-6
   rescue => ex
    k34="Eleman bazında donatı karşılaştırılamadı: #{ex.message}"
   end
  end
  w=(current< -1e-9 ? 'Önceki hakedişte ödenen miktar modelde azaldı' : (r[:unit_price].nil? && (current.abs>1e-9 || paid[key]) ? 'Birim fiyat yok'+(paid[key] ? ' · önceki tutar son hakedişten' : '') : nil))
  w=[w,k34].compact.join(' · ') if k34
  out << {key:key,code:r[:code],name:r[:name],source:r[:source].to_s,unit:r[:unit],quantity:r[:quantity].to_f,
          unit_price:(r[:unit_price].nil? ? nil : r[:unit_price].to_f),price_missing:r[:unit_price].nil?,
          previous:previous,current_period:current,approved_quantity:q[:approved],claimed_quantity:q[:claimed],manual:q[:manual],
          previous_amount:(r[:unit_price].nil? ? paid[key] : nil),
          warning:w}
 end
 # önceki hakedişte ödenmiş fakat artık keşifte olmayan (pasif / silinen / sıfırlanan) pozlar → alacak satırı
 Array(last && last['rows']).each do |lr|
  key=(lr['key'] || lr['source']).to_s;next if key.empty? || seen[key]
  seen[key]=true
  pv=model.get_attribute(PROGRESS_DICT,"previous_#{key}",nil)
  previous=pv.nil? ? (lr['approved_quantity'] || lr['previous'].to_f+lr['current_period'].to_f).to_f : pv.to_f
  next if previous.abs<1e-12
  up=lr['unit_price'].nil? ? nil : boq2_convert(lr['unit_price'].to_f,prog2_rec_currency(last),cur)
  out << {key:key,code:lr['code'],name:lr['name'],source:lr['source'].to_s,unit:lr['unit'],quantity:0.0,unit_price:up,price_missing:up.nil?,
          previous:previous,current_period:-previous,approved_quantity:0.0,claimed_quantity:0.0,manual:false,removed:true,
          warning:'Poz keşiften çıkarıldı / sıfırlandı; önceki ödeme alacak olarak döner'}
 end
 out
end

# ---------------------------------------------------------------- 8 · sözleşme, kesintiler, icmal
def boq2_contract
 c=boq2_json('contract_json',nil)
 c.is_a?(Hash) && c['deductions'].is_a?(Array) ? c : JSON.parse(JSON.generate(BOQ2_CONTRACT_PRESETS['ozel']))
end
def boq2_save_contract(raw)
 d=raw.is_a?(String) ? JSON.parse(raw) : raw
 raise 'Sözleşme tipi özel veya kamu olmalı.' unless %w[ozel kamu].include?(d['type'].to_s)
 vat=boq2_num(d['vat_pct']);raise 'KDV oranı 0–100 arasında olmalı.' unless vat && vat>=0 && vat<=100
 ded=(d['deductions']||[]).map do |x|
  pct=boq2_num(x['pct'])
  raise "Kesinti oranı geçersiz: #{x['name']}" unless pct && pct>=0 && pct<=100
  raise 'Kesinti adı boş olamaz.' if x['name'].to_s.strip.empty?
  raise 'Kesinti tabanı tutar veya kdv olmalı.' unless %w[tutar kdv].include?(x['base'].to_s)
  {'name'=>x['name'].to_s.strip,'base'=>x['base'].to_s,'pct'=>pct}
 end
 model=Sketchup.active_model
 model.start_operation('MST Sözleşme / Kesintiler',true)
 begin
  boq2_set('contract_json',JSON.generate({'type'=>d['type'],'vat_pct'=>vat,'deductions'=>ded}))
  model.commit_operation
 rescue
  model.abort_operation;raise
 end
 true
end
# kümülatif tutar + kümülatif fiyat farkı → icmal satırları; prev: önceki dönemin kümülatif değerleri
def boq2_icmal(cum_amount,cum_pd,prev=nil,contract=boq2_contract)
 vat=contract['vat_pct'].to_f/100.0
 c=cum_amount.to_f+cum_pd.to_f
 kdv=c*vat
 lines=[['A','Sözleşme fiyatlarıyla yapılan iş tutarı',cum_amount.to_f],['B','Fiyat farkı',cum_pd.to_f],['C','Toplam (A + B)',c],
        ['D',"KDV (%#{format('%g',contract['vat_pct'].to_f)})",kdv]]
 kes=0.0
 Array(contract['deductions']).each_with_index do |x,i|
  v=(x['base']=='kdv' ? kdv : c)*x['pct'].to_f/100.0;kes+=v
  lines << ["E#{i+1}","#{x['name']} (%#{format('%g',x['pct'].to_f)} × #{x['base']=='kdv' ? 'KDV' : 'tutar'})",v]
 end
 lines << ['E','Kesintiler toplamı',kes]
 lines << ['F','Ödenecek tutar (C + D − E)',c+kdv-kes]
 pv=prev.is_a?(Hash) ? prev : {}
 lines.map{|k,n,v|p=pv[k].to_f;{'key'=>k,'name'=>n,'cum'=>v,'prev'=>p,'cur'=>v-p}}
end
def boq2_icmal_cum(lines);Hash[Array(lines).map{|l|[l['key'],l['cum'].to_f]}];end
# kayıtlı dönemin icmali (BQ1 öncesi kayıtlarda satırlardan yeniden kurulur); kaydın kendi para biriminde
def prog2_rec_icmal(rec,hist=progress_history)
 return rec['icmal'] if rec['icmal'].is_a?(Array) && !rec['icmal'].empty?
 prior=hist.select{|h|h['no'].to_i<rec['no'].to_i}.max_by{|h|h['no'].to_i}
 prev=nil
 if prior
  pc=boq2_icmal_cum(prog2_rec_icmal(prior,hist))
  prev=Hash[pc.map{|k,v|[k,boq2_convert(v,prog2_rec_currency(prior),prog2_rec_currency(rec))]}]
 end
 amount=Array(rec['rows']).sum{|r|(r['approved_quantity'] || r['previous'].to_f+r['current_period'].to_f).to_f*r['unit_price'].to_f}
 boq2_icmal(amount,rec['cum_price_diff'].to_f,prev,rec['contract'].is_a?(Hash) ? rec['contract'] : boq2_contract)
end
# son kaydın kümülatifleri, güncel para birimine çevrilmiş
def prog2_prev_cum(last=prog2_last_period,cur=boq2_currency)
 return nil unless last
 pc=boq2_icmal_cum(prog2_rec_icmal(last))
 Hash[pc.map{|k,v|[k,boq2_convert(v,prog2_rec_currency(last),cur)]}]
end
# v0.51.5 K38: icmal A kümülatifi (önceki A + Σ bu dönem × güncel fiyat) ile Hakediş Cetveli kümülatif tutarı
# (Σ kümülatif × güncel fiyat; fiyatsız satırda önceki tutar) fiyat/kur dönemler arasında değişince ayrışır.
# İki kural değiştirilmez (sözleşme belgesi gerekli); fark varsa [ileti, fark] döner, yoksa nil. Salt okuma.
def prog2_icmal_cetvel_warning(rows,icmal,cur='')
 a=Array(icmal).find{|l|l.is_a?(Hash) && l['key']=='A'};return nil unless a
 rs=Array(rows).map{|r|Hash[r.map{|k,v|[k.to_sym,v]}]}
 l=rs.sum{|r|r[:unit_price].nil? ? r[:previous_amount].to_f : (r[:previous].to_f+r[:current_period].to_f)*r[:unit_price].to_f}
 d=a['cum'].to_f-l
 return nil if d.abs<=[0.01,l.abs*1e-9].max
 [format('UYARI: İcmal A kümülatifi %.2f %s, Hakediş Cetveli kümülatif tutarı %.2f %s (fark %.2f %s). Fiyat veya kur dönemler arasında değişmiş olabilir; iki hesap kuralı değiştirilmedi — sözleşmedeki fiyat farkı kuralına göre kontrol edin.',a['cum'].to_f,cur,l,cur,d,cur),d]
end
# A kümülatif = önceki A + Σ(bu dönem × birim fiyat) → icmal "bu dönem" = cetvel "bu dönem tutar" toplamı
def prog2_live_icmal(rows,price_diff=prog2_view_pd)
 prev=prog2_prev_cum
 a=(prev ? prev['A'].to_f : 0.0)+rows.sum{|r|r[:current_period].to_f*r[:unit_price].to_f}
 b=(prev ? prev['B'].to_f : 0.0)+price_diff.to_f
 boq2_icmal(a,b,prev)
end

# ---------------------------------------------------------------- dönem kaydet / göster / sil
alias_method :progress_payload_base, :progress_payload unless method_defined?(:progress_payload_base)
def progress_payload(period_no=nil)
 p=progress_payload_base(period_no)
 hist=progress_history
 last=prog2_last_period(hist)
 if p[:archived]
  rec=hist.find{|h|h['no'].to_i==period_no.to_i}
  p[:icmal]=rec && prog2_rec_icmal(rec,hist)
  p[:period_date]=rec && rec['date']
  p[:price_diff]=rec ? rec['price_diff'].to_f : 0.0
  p[:currency]=prog2_rec_currency(rec)
 else
  p[:icmal]=prog2_live_icmal(p[:rows])
  p[:period_date]=prog2_view_date
  p[:price_diff]=prog2_view_pd
  p[:currency]=boq2_currency
 end
 # v0.51.5 K38: icmal ↔ cetvel kümülatif tutarı farklıysa uyarı (yalnız gösterim satırı; kayıt ve kurallar değişmez)
 if (wk=prog2_icmal_cetvel_warning(p[:rows],p[:icmal],p[:currency]))
  p[:icmal_warning]=wk[0]
  p[:icmal]=Array(p[:icmal])+[{'key'=>'!','name'=>wk[0],'cum'=>wk[1],'prev'=>0.0,'cur'=>0.0}]
 end
 p[:last_date]=last && last['date']
 p[:contract]=boq2_contract
 p[:history]=hist.map{|h|{'no'=>h['no'],'saved_at'=>h['saved_at'],'date'=>h['date']}}
 p
end

# ADR-0515 §1(c) / K06: mükerrer UID (kopyalanmış eleman) varsa revizyon/hakediş öncesi sorulur; yazmaz
def mst_dup_uid_continue?
 a=[];collect_elements(Sketchup.active_model.entities,a)
 n=a.select{|e|e.respond_to?(:get_attribute) && %w[steel_pipe_pile pile_infill_concrete head_beam flat_precast channel_precast crane_precast deck_slab deck_topping curb crown_wall bored_pile accessory].include?(e.get_attribute(DICT,'element_type','').to_s)}.group_by{|e|e.get_attribute(DICT,'element_uid','').to_s.strip}.count{|k,v|!k.empty? && v.length>1}
 n.zero? || UI.messagebox("Modelde #{n} mükerrer UID var (kopyalanmış eleman). Revizyon/hakediş farkı yanıltıcı olabilir. Önce Model Kontrolü → BIM Identity Repair önerilir. Yine de devam edilsin mi?",MB_YESNO)==IDYES
end
def progress_save(raw=nil,dialog=@d)
 d=(raw.is_a?(String) && !raw.strip.empty? ? (JSON.parse(raw) rescue {}) : (raw.is_a?(Hash) ? raw : {}))
 date=d['date'].to_s.strip;date=boq2_today if date.empty?
 raise 'Dönem sonu tarihi YYYY-AA-GG olmalı.' unless boq2_date_ok?(date)
 last=prog2_last_period
 raise "Dönem sonu tarihi bir önceki hakedişten (#{last['date']}) önce olamaz." if last && last['date'] && date<last['date'].to_s
 pd=d.key?('price_diff') ? boq2_num(d['price_diff']) : 0.0
 raise 'Fiyat farkı sayı olmalı.' if pd.nil?
 model=Sketchup.active_model
 unless mst_dup_uid_continue?
  progress_send(dialog)
  return nil
 end
 rows=progress_live_rows(date)
 neg=rows.select{|r|r[:current_period]< -1e-9}
 if !neg.empty? && !d['accept_negative']
  ans=UI.messagebox("#{neg.length} pozda önceki hakedişte ödenen miktar modelde AZALMIŞ:\n"+neg.first(8).map{|r|"  #{r[:code]}: #{format('%.3f',r[:current_period])} #{r[:unit]}"}.join("\n")+"\n\nBu dönem eksi (alacak) olarak kaydedilsin mi?",MB_YESNO)
  unless ans==IDYES
   progress_send(dialog)
   return nil
  end
 end
 icmal=prog2_live_icmal(rows,pd)
 model.start_operation('MST Hakediş Dönemini Kaydet',true)
 begin
  pile_boq_codes_persist!(model) if respond_to?(:pile_boq_codes_persist!)   # v0.51.5 K35: satır anahtarlarındaki NN kalıcı
  hist=progress_history
  no=(hist.map{|h|h['no'].to_i}.max||0)+1
  rec={'no'=>no,'saved_at'=>Time.now.strftime('%d.%m.%Y %H:%M'),'date'=>date,'by'=>boq2_user,'currency'=>boq2_currency,
       'rows'=>rows.map{|r|Hash[r.map{|k,v|[k.to_s,v]}]},'status_summary'=>progress_status_summary,
       'price_diff'=>pd,'cum_price_diff'=>icmal.find{|l|l['key']=='B'}['cum'],
       'icmal'=>icmal,'icmal_cum'=>boq2_icmal_cum(icmal),'contract'=>boq2_contract,'note'=>d['note'].to_s}
  hist << rec
  model.set_attribute(PROGRESS_DICT,PROGRESS_HISTORY_KEY,JSON.generate(hist))
  rows.each do |r|
   model.set_attribute(PROGRESS_DICT,"previous_#{r[:key]}",r[:approved_quantity])
   model.set_attribute(PROGRESS_DICT,"cumulative_#{r[:key]}",r[:approved_quantity])
  end
  model.set_attribute(PROGRESS_DICT,'last_saved_at',rec['saved_at'])
  commit_with_dependencies(model)
 rescue
  model.abort_operation;raise
 end
 @prog2_view_pd=0.0
 progress_send(dialog,no)
 no
rescue => ex
 UI.messagebox("Hakediş kaydedilemedi: #{ex.message}")
 nil
end

def progress_delete_period(period_no,dialog=@d)
 n=period_no.to_i
 return if n<=0
 model=Sketchup.active_model
 hist=progress_history
 rec=hist.find{|h|h['no'].to_i==n}
 unless rec
  UI.messagebox("Hakediş #{format('%02d',n)} bulunamadı.")
  progress_send(dialog)
  return
 end
 answer=UI.messagebox("Hakediş #{format('%02d',n)} arşiv kaydı kalıcı olarak silinsin mi?\n\nBu işlem model geometrisini veya BIM imalat durumlarını değiştirmez.",MB_YESNO)
 return unless answer==IDYES
 model.start_operation('MST Hakediş Kaydını Sil',true)
 begin
  hist.reject!{|h|h['no'].to_i==n}
  model.set_attribute(PROGRESS_DICT,PROGRESS_HISTORY_KEY,JSON.generate(hist))
  latest=prog2_last_period(hist)
  latest_rows=latest ? Array(latest['rows']) : []
  rk=->(x){(x['key'] || x['source']).to_s}
  keys=(boq_rows(true).map{|r|prog2_row_key(r)}+Array(rec['rows']).map(&rk)+latest_rows.map(&rk)).uniq
  keys.each do |k|
   rr=latest_rows.find{|x|rk.(x)==k}
   approved=rr ? (rr['approved_quantity'] || rr['previous'].to_f+rr['current_period'].to_f).to_f : 0.0
   model.set_attribute(PROGRESS_DICT,"previous_#{k}",approved)
   model.set_attribute(PROGRESS_DICT,"cumulative_#{k}",approved)
  end
  model.set_attribute(PROGRESS_DICT,'last_saved_at',latest ? latest['saved_at'].to_s : '')
  commit_with_dependencies(model)
 rescue
  model.abort_operation;raise
 end
 progress_send(dialog)
rescue=>ex
 UI.messagebox("Hakediş silinemedi: #{ex.message}")
end

# ---------------------------------------------------------------- iş kalemi girişi (seçim)
def prog2_selected_elements(model=Sketchup.active_model)
 out=[]
 model.selection.to_a.each do |e|
  next unless e.respond_to?(:get_attribute)
  out << e unless e.get_attribute(DICT,'element_type','').to_s.empty?
  collect_elements(e.entities,out) if e.respond_to?(:entities)
  collect_elements(e.definition.entities,out) if e.is_a?(Sketchup::ComponentInstance)
 end
 out.uniq
end
def prog2_selection_info
 sel=prog2_selected_elements
 pids={};sel.each{|e|pids[e.persistent_id]=true}
 rows=[];manual=[]
 boq_rows.each do |r|
  src=r[:source].to_s;key=prog2_row_key(r)
  all=prog2_row_entities(r)
  if all.empty?
   m=prog2_norm(prog2_manual[key]) || {}
   x=prog2_ok_entry(m)
   manual << {key:key,source:src,code:r[:code],name:r[:name],unit:r[:unit],quantity:r[:quantity],pct:m['claim'].to_f,
              approved_pct:(x ? x[1].to_f : 0.0),ok:!x.nil?,date:(m['claim_date'] || (x && x[0]))}
   next
  end
  es=all.select{|e|pids[e.persistent_id]}
  next if es.empty?
  q=es.sum{|e|progress_entity_quantity(e,src).to_f}
  ap=es.sum{|e|prog2_frac(e,src)}/es.length;cl=es.sum{|e|prog2_claim(e,src)}/es.length
  rows << {key:key,source:src,code:r[:code],name:r[:name],unit:r[:unit],count:es.length,quantity:q,approved_pct:ap*100.0,claimed_pct:cl*100.0}
 end
 {selected:sel.length,rows:rows,manual:manual}
end
def prog2_apply(raw)
 d=raw.is_a?(String) ? JSON.parse(raw) : raw
 keys=Array(d['sources']).map(&:to_s).uniq;raise 'En az bir iş kalemi seçin.' if keys.empty?
 clear=!!d['clear']
 pct=boq2_num(d['pct'])
 raise 'İlerleme yüzdesi 0–100 olmalı.' unless clear || (pct && pct>=0 && pct<=100)
 date=d['date'].to_s.strip;date=boq2_today if date.empty?
 raise 'Tarih YYYY-AA-GG olmalı.' unless boq2_date_ok?(date)
 sel=prog2_selected_elements;raise 'Önce modelde eleman seçin.' if sel.empty?
 pids={};sel.each{|e|pids[e.persistent_id]=true}
 rows=boq_rows(true)
 model=Sketchup.active_model;n=0
 model.start_operation('MST Hakediş İlerlemesi',true)
 begin
  keys.each do |key|
   row=prog2_find_row(key,rows)
   base=prog2_base(key)
   es=(row ? prog2_row_entities(row) : boq_trace_entities(key)).select{|e|pids[e.persistent_id]}
   es.each do |e|
    h=prog2_items_for_write(e)
    if clear
     h.delete(base)
    else
     h[base]=prog2_rec_apply(prog2_norm(h[base]),pct,!!d['ok'],date,prog2_legacy_ok?(e))
    end
    h.empty? ? e.delete_attribute(DICT,PROG2_KEY) : e.set_attribute(DICT,PROG2_KEY,JSON.generate(h))
    n+=1
   end
  end
  commit_with_dependencies(model)
 rescue
  model.abort_operation;raise
 end
 n
end
def prog2_manual_set(raw)
 d=raw.is_a?(String) ? JSON.parse(raw) : raw
 key=d['source'].to_s;raise 'Poz seçilmedi.' if key.empty?
 pct=boq2_num(d['pct']);raise 'İlerleme yüzdesi 0–100 olmalı.' unless pct && pct>=0 && pct<=100
 date=d['date'].to_s.strip;date=boq2_today if date.empty?
 raise 'Tarih YYYY-AA-GG olmalı.' unless boq2_date_ok?(date)
 model=Sketchup.active_model
 # v0.51.5 R-4: bozuk elle ilerleme kaydı boş sayılıp üzerine yazılmaz
 raw=model.get_attribute(PROGRESS_DICT,'manual_progress_json','').to_s
 raise 'Elle ilerleme kaydı (manual_progress_json) okunamadı; mevcut kaydın üzerine yazılmadı, değişiklik kaydedilmedi.' unless raw.strip.empty? || (JSON.parse(raw) rescue nil).is_a?(Hash)
 model.start_operation('MST Elle Hakediş İlerlemesi',true)
 begin
  h=prog2_manual;h[key]=prog2_rec_apply(prog2_norm(h[key]),pct,!!d['ok'],date)
  model.set_attribute(PROGRESS_DICT,'manual_progress_json',JSON.generate(h))
  model.commit_operation
 rescue
  model.abort_operation;raise
 end
 true
end

# ---------------------------------------------------------------- 9 · modelde ilerleme görünümü
def prog2_state(e,src=nil)
 srcs=src.to_s.empty? ? (prog2_items(e).keys+['*']) : [src]
 fr=srcs.map{|s|s=='*' ? (prog2_legacy_ok?(e) ? 1.0 : 0.0) : prog2_frac(e,s)}
 cl=srcs.map{|s|s=='*' ? (%w[İmalatta Tamamlandı Onaylandı].include?(e.get_attribute(DICT,'progress_status','').to_s) ? 1.0 : 0.0) : prog2_claim(e,s)}
 return 'ok' if fr.max.to_f>=0.999
 return 'partial' if fr.max.to_f>0 || cl.max.to_f>0
 'none'
end
def prog2_select(raw)
 d=raw.is_a?(String) ? JSON.parse(raw) : raw
 key=d['source'].to_s;state=d['state'].to_s
 raise 'Durum ok / partial / none olmalı.' unless %w[ok partial none].include?(state)
 model=Sketchup.active_model
 pool=if key.empty?
  all=[];collect_elements(model.entities,all);all.select{|e|%w[steel_pipe_pile bored_pile head_beam flat_precast channel_precast crane_precast deck_slab crown_wall].include?(e.get_attribute(DICT,'element_type','').to_s)}
 else
  row=prog2_find_row(key)
  row ? prog2_row_entities(row) : boq_trace_entities(key)
 end
 hit=pool.select{|e|prog2_state(e,key)==state}
 model.selection.clear;hit.each{|e|model.selection.add(e) rescue nil}
 model.active_view.zoom(model.selection) unless hit.empty?
 hit.length
end
# yalnız seçili elemanları göster (diğer MST elemanlarını gizle) / hepsini geri göster
def prog2_isolate(on)
 model=Sketchup.active_model;all=[];collect_elements(model.entities,all)
 top=all.select{|e|e.parent.is_a?(Sketchup::Model) rescue false}
 keep={};model.selection.each{|e|keep[e]=true}
 raise 'Önce modelde gösterilecek elemanları seçin.' if on && keep.empty?
 model.start_operation('MST İlerleme Görünümü',true)
 n=0
 begin
  if on
   top.each{|e|next if keep[e] || e.hidden?;e.hidden=true;e.set_attribute(DICT,'mst_prog_hidden',true);n+=1}
  else
   top.each{|e|next unless e.get_attribute(DICT,'mst_prog_hidden',false);e.hidden=false;e.delete_attribute(DICT,'mst_prog_hidden');n+=1}
  end
  model.commit_operation
 rescue
  model.abort_operation;raise
 end
 n
end

# ---------------------------------------------------------------- 12 · revizyon → keşif farkı
def boq2_boq_digest
 boq_rows(true).map{|r|{'source'=>prog2_row_key(r),'code'=>r[:code].to_s,'name'=>r[:name].to_s,'unit'=>r[:unit].to_s,'quantity'=>r[:quantity].to_f,
                        'unit_price'=>(r[:unit_price].nil? ? nil : r[:unit_price].to_f)}}
end
alias_method :revision_create_snapshot_base, :revision_create_snapshot unless method_defined?(:revision_create_snapshot_base)
# R-1 (K02, K03, K26): arşiv okunamazsa işlem açılmaz; fark yoksa revizyon oluşmaz; snapshot + keşif + last_revision tek işlem (tek Ctrl+Z)
def revision_create_snapshot(dialog=@d)
 model=Sketchup.active_model;op=false
 snaps=begin;revision_snapshots;rescue => ex;UI.messagebox("Revizyon kaydedilemedi: #{ex.message}");return nil;end
 return nil unless mst_dup_uid_continue?
 curr=revision_current_snapshot;boq=boq2_boq_digest;prev=snaps.last
 if prev
  df=revision_diff(prev['elements'],curr)
  if df[:added].empty? && df[:deleted].empty? && df[:changed].empty? && (prev['boq'].nil? || boq2_boq_diff(prev['boq'],boq).empty?)
   UI.messagebox("Son revizyondan (#{prev['revision']}) bu yana modelde ve keşif miktarlarında değişiklik yok; yeni revizyon oluşturulmadı.")
   revision_send(dialog)
   return nil
  end
 end
 model.start_operation('MST Revizyon Kaydı',true);op=true
 snap=revision_create_snapshot_base(snaps,curr)
 snap['boq']=boq;snap['currency']=boq2_currency
 snaps << snap;revision_save_snapshots(snaps)
 model.set_attribute(REVISION_DICT,'last_revision',snap['revision'])
 model.commit_operation;op=false
 mb=model.get_attribute(REVISION_DICT,'snapshots','').to_s.bytesize/1048576.0
 UI.messagebox(format("Revizyon arşivi büyüdü (%d kayıt, %.1f MB); eski kayıtlar otomatik silinmez.",snaps.length,mb)) if snaps.length>20 || mb>5.0
 revision_send(dialog)
 snap['revision']
rescue => ex
 model.abort_operation if op
 UI.messagebox("Revizyon kaydedilemedi: #{ex.message}")
 nil
end
def boq2_boq_diff(prev_boq,curr_boq)
 pm=Hash[Array(prev_boq).map{|r|[r['source'],r]}];cm=Hash[Array(curr_boq).map{|r|[r['source'],r]}]
 (pm.keys|cm.keys).map do |k|
  a=pm[k];b=cm[k];pq=a ? a['quantity'].to_f : 0.0;cq=b ? b['quantity'].to_f : 0.0
  price=(b || a)['unit_price'].to_f
  next nil if (cq-pq).abs<1e-9
  {'source'=>k,'code'=>(b || a)['code'],'name'=>(b || a)['name'],'unit'=>(b || a)['unit'],'prev'=>pq,'curr'=>cq,'delta'=>cq-pq,'unit_price'=>price,'delta_amount'=>(cq-pq)*price}
 end.compact.sort_by{|r|-r['delta_amount'].abs}
end
alias_method :revision_payload_base, :revision_payload unless method_defined?(:revision_payload_base)
def revision_payload
 p=revision_payload_base
 prev=revision_snapshots.last
 p[:boq_diff]=prev && prev['boq'] ? boq2_boq_diff(prev['boq'],boq2_boq_digest) : nil
 p[:boq_diff_note]=prev.nil? ? 'Henüz snapshot yok.' : (prev['boq'] ? "#{prev['revision']} ile güncel model" : "#{prev['revision']} keşif içermiyor; yeni snapshot alın (bundan sonrakiler keşfi de saklar).")
 p[:currency]=boq2_currency
 p
end

# ---------------------------------------------------------------- 10 · Keşif Cetveli Excel
def boq2_xl_write(path,sheets)
 st=sheets[:styles]
 list=sheets[:list]
 ct='<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'+
  list.each_index.map{|i|"<Override PartName=\"/xl/worksheets/sheet#{i+1}.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"}.join+'</Types>'
 rels='<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'
 wb='<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>'+
  list.each_with_index.map{|(n,_),i|"<sheet name=\"#{xml_escape(n)}\" sheetId=\"#{i+1}\" r:id=\"rId#{i+1}\"/>"}.join+'</sheets><calcPr calcId="0" fullCalcOnLoad="1"/></workbook>'
 wbr='<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'+
  list.each_index.map{|i|"<Relationship Id=\"rId#{i+1}\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet#{i+1}.xml\"/>"}.join+
  "<Relationship Id=\"rId#{list.length+1}\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/></Relationships>"
 entries={'[Content_Types].xml'=>ct,'_rels/.rels'=>rels,'xl/workbook.xml'=>wb,'xl/_rels/workbook.xml.rels'=>wbr}
 list.each_with_index{|(_,rows),i|entries["xl/worksheets/sheet#{i+1}.xml"]=mst_xl_sheet_xml(rows)}
 entries['xl/styles.xml']=st.xml
 write_simple_zip(path,entries)
 list.map(&:first)
end
def boq2_money_fmt(cur);"#,##0.00\" #{cur}\"";end
def boq2_qty_fmt(unit);"#,##0.000\" #{unit}\"";end
def boq2_info_rows(st,title,extra=[])
 model=Sketchup.active_model;s=boq2_settings
 rows=[[{v:title,s:st.id(:title)}],[]]
 info=[['Proje',model.get_attribute(DICT,'project_name','').to_s],['Model',(File.basename(model.path.to_s) rescue '')],
       ['Tarih',Time.now.strftime('%d.%m.%Y %H:%M')],['Sürüm',(defined?(MST_BUILD) ? MST_BUILD : '').to_s],
       ['Para birimi',s['currency']],['Kur (TL)',"1 USD = #{s['fx']['USD']} TL · 1 EUR = #{s['fx']['EUR']} TL"],
       ['Fiyat tarihi',s['price_date'].to_s.empty? ? '—' : s['price_date']]]+extra
 info.each{|k,v|rows << [{v:k,s:st.id(:h3)},{v:(v.to_s.empty? ? '—' : v.to_s),s:st.id(:cell)}]}
 rows
end
def boq2_kesif_xlsx_write(path)
 st=MSTXLStyles.new;cur=boq2_currency
 rows=boq_rows
 raise 'Keşifte aktif poz yok.' if rows.empty?
 k=[[{v:'Keşif Cetveli',s:st.id(:title)}],[{v:"Para birimi: #{cur}#{boq2_split? ? ' · beton sınıfa göre ayrı' : ''}",s:st.id(:note)}],[]]
 hdr=['Poz No','İşin Tanımı','Birim','Miktar','Birim Fiyat','Tutar','Durum / Not']
 k << hdr.map{|h|{v:h,s:st.id(:header)}}
 first=k.length+1
 rows.each do |r|
  rn=k.length+1
  k << [{v:r[:code].to_s,s:st.id(:cell)},{v:r[:name].to_s,s:st.id(:cell)},{v:r[:unit].to_s,s:st.id(:cell)},
        {v:r[:quantity].to_f,s:st.id(:cell,'#,##0.000')},
        (r[:unit_price].nil? ? {v:'FİYAT YOK',s:st.id(:cell)} : {v:r[:unit_price].to_f,s:st.id(:cell,boq2_money_fmt(cur))}),
        (r[:unit_price].nil? ? {v:'',s:st.id(:cell)} : {v:r[:quantity].to_f*r[:unit_price].to_f,f:"D#{rn}*E#{rn}",s:st.id(:cell,boq2_money_fmt(cur))}),
        {v:[r[:status],r[:price_note]].compact.join(' · '),s:st.id(:note)}]
 end
 last=k.length
 tot=rows.sum{|r|r[:unit_price].nil? ? 0.0 : r[:quantity].to_f*r[:unit_price].to_f}
 k << [{v:'GENEL TOPLAM',s:st.id(:total)},{v:'',s:st.id(:total)},{v:'',s:st.id(:total)},{v:'',s:st.id(:total)},{v:'',s:st.id(:total)},
       {v:tot,f:"SUM(F#{first}:F#{last})",s:st.id(:total,boq2_money_fmt(cur))},{v:(rows.any?{|r|r[:unit_price].nil?} ? 'Fiyatı eksik poz var' : ''),s:st.id(:total)}]
 if cur!='TRY'
  fx=boq2_fx[cur]
  k << [{v:"TL karşılığı (1 #{cur} = #{fx} TL)",s:st.id(:sub)},{v:'',s:st.id(:sub)},{v:'',s:st.id(:sub)},{v:'',s:st.id(:sub)},{v:fx,s:st.id(:sub,'#,##0.0000')},
        {v:tot*fx,f:"F#{last+1}*E#{last+2}",s:st.id(:sub,boq2_money_fmt('TL'))},{v:'',s:st.id(:sub)}]
 end
 # poz metrajları: her pozun elemanları
 m=[[{v:'Poz Metrajları — eleman bazında',s:st.id(:title)}],[{v:'Her pozun miktarını oluşturan BIM elemanları. Toplu hesaplanan pozlarda (kazık imalat / ek / çarık vb.) eleman toplamı BOQ miktarına ölçeklenmiştir.',s:st.id(:note)}],[]]
 rows.each do |r|
  src=r[:source].to_s
  m << [{v:"#{r[:code]} · #{r[:name]}",s:st.id(:h3)}]
  es=prog2_row_entities(r)
  if es.empty?
   m << [{v:(boq2_manual?(src) ? 'Elle girilen miktar' : 'Modelde eleman yok (götürü / elle)'),s:st.id(:note)},{v:r[:quantity].to_f,s:st.id(:cell,boq2_qty_fmt(r[:unit]))}];m << [];next
  end
  m << ['Eleman','Tip','Yapı','Miktar'].map{|h|{v:h,s:st.id(:header)}}
  per=es.map{|e|[e,progress_entity_quantity(e,src).to_f]}
  sum=per.sum{|_,q|q}
  per.select{|_,q|q>0}.sort_by{|e,_|element_visible_id(e).to_s}.each do |e,q|
   m << [{v:element_visible_id(e).to_s,s:st.id(:cell)},{v:e.get_attribute(DICT,'element_type','').to_s,s:st.id(:cell)},
         {v:(e.get_attribute(DICT,'ano','').to_s.empty? ? e.get_attribute(DICT,'structure','').to_s : e.get_attribute(DICT,'ano','').to_s),s:st.id(:cell)},
         {v:q,s:st.id(:cell,boq2_qty_fmt(r[:unit]))}]
  end
  m << [{v:"Eleman toplamı#{(sum-r[:quantity].to_f).abs>1e-6 && sum>0 ? " (BOQ: #{format('%.3f',r[:quantity])})" : ''}",s:st.id(:sub)},{v:'',s:st.id(:sub)},{v:es.length,s:st.id(:sub,'#,##0')},{v:sum,s:st.id(:sub,boq2_qty_fmt(r[:unit]))}]
  m << []
 end
 boq2_xl_write(path,{styles:st,list:[['Keşif Cetveli',k],['Poz Metrajları',m],['Bilgi',boq2_info_rows(st,'Keşif Bilgileri')]]})
end

# ---------------------------------------------------------------- 11 · Hakediş Raporu Excel
def boq2_hakedis_xlsx_write(path,period_no=nil)
 st=MSTXLStyles.new
 hist=progress_history
 rec=period_no.to_i>0 ? hist.find{|h|h['no'].to_i==period_no.to_i} : nil
 raise "Hakediş #{format('%02d',period_no.to_i)} bulunamadı." if period_no.to_i>0 && rec.nil?
 vdate=prog2_view_date
 if rec
  rows=Array(rec['rows']).map{|r|Hash[r.map{|k,v|[k.to_sym,v]}]}
  icmal=prog2_rec_icmal(rec,hist)
  title="Hakediş #{format('%02d',rec['no'].to_i)} — dönem sonu #{rec['date'] || rec['saved_at']}";cur=prog2_rec_currency(rec)
 else
  rows=progress_live_rows(vdate)
  icmal=prog2_live_icmal(rows,prog2_view_pd)
  title="Hakediş önizleme (kaydedilmemiş) — dönem sonu #{vdate}";cur=boq2_currency
 end
 ic=[[{v:title,s:st.id(:title)}],[{v:"İcmal · #{cur}",s:st.id(:h3)}],[]]
 ic << ['','Kalem','Kümülatif','Önceki','Bu Dönem'].map{|h|{v:h,s:st.id(:header)}}
 icmal.each do |l|
  role=%w[C F].include?(l['key']) ? :total : (l['key']=='E' ? :sub : :cell)
  ic << [{v:l['key'],s:st.id(role)},{v:l['name'],s:st.id(role)},{v:l['cum'].to_f,s:st.id(role,boq2_money_fmt(cur))},{v:l['prev'].to_f,s:st.id(role,boq2_money_fmt(cur))},{v:l['cur'].to_f,s:st.id(role,boq2_money_fmt(cur))}]
 end
 ic << [] << [{v:'A "Bu Dönem" = Hakediş Cetveli "Bu Dönem Tutar" toplamı. Kesinti oranları sözleşme ayarlarından gelir; resmi hakediş öncesi sözleşmenizle kontrol edin.',s:st.id(:note)}]
 (wk=prog2_icmal_cetvel_warning(rows,icmal,cur)) && ic << [{v:wk[0],s:st.id(:note)}]   # v0.51.5 K38
 hc=[[{v:'Hakediş Cetveli',s:st.id(:title)}],[{v:"Para birimi: #{cur}",s:st.id(:note)}],[]]
 hdr=['Poz No','İşin Tanımı','Birim','Sözleşme Miktarı','Önceki','Bu Dönem','Kümülatif','İlerleme','Birim Fiyat','Önceki Tutar','Bu Dönem Tutar','Kümülatif Tutar','Uyarı']
 hc << hdr.map{|h|{v:h,s:st.id(:header)}}
 first=hc.length+1
 rows.each do |r|
  n=hc.length+1;q=r[:quantity].to_f;pr=r[:previous].to_f;cu=r[:current_period].to_f
  nop=r[:unit_price].nil?;up=r[:unit_price].to_f
  role=r[:warning] ? :sub : :cell
  mf=st.id(role,boq2_money_fmt(cur))
  amt=->(val,f){nop ? {v:0.0,s:mf} : {v:val,f:f,s:mf}}
  pa=r[:previous_amount].to_f   # fiyatı silinen poz: önceki hakedişte ödenen tutar
  hc << [{v:r[:code].to_s,s:st.id(role)},{v:r[:name].to_s,s:st.id(role)},{v:r[:unit].to_s,s:st.id(role)},
         {v:q,s:st.id(role,'#,##0.000')},{v:pr,s:st.id(role,'#,##0.000')},{v:cu,s:st.id(role,'#,##0.000')},
         {v:pr+cu,f:"E#{n}+F#{n}",s:st.id(role,'#,##0.000')},{v:(q>0 ? (pr+cu)/q : 0.0),f:"IF(D#{n}>0,G#{n}/D#{n},0)",s:st.id(role,'0.0%')},
         (nop ? {v:'FİYAT YOK',s:st.id(role)} : {v:up,s:mf}),
         (nop ? {v:pa,s:mf} : amt.(pr*up,"E#{n}*I#{n}")),amt.(cu*up,"F#{n}*I#{n}"),(nop ? {v:pa,s:mf} : amt.((pr+cu)*up,"G#{n}*I#{n}")),
         {v:r[:warning].to_s,s:st.id(:note)}]
 end
 last=hc.length
 tr=->(col,val){{v:val,f:"SUM(#{col}#{first}:#{col}#{last})",s:st.id(:total,boq2_money_fmt(cur))}}
 ps=->(f){rows.sum{|r|r[:unit_price].nil? ? 0.0 : f.(r)*r[:unit_price].to_f}}
 hc << [{v:'TOPLAM',s:st.id(:total)}]+Array.new(8){{v:'',s:st.id(:total)}}+
       [tr.('J',ps.(->(r){r[:previous].to_f})+rows.sum{|r|r[:unit_price].nil? ? r[:previous_amount].to_f : 0.0}),tr.('K',ps.(->(r){r[:current_period].to_f})),
        tr.('L',ps.(->(r){r[:previous].to_f+r[:current_period].to_f})+rows.sum{|r|r[:unit_price].nil? ? r[:previous_amount].to_f : 0.0}),{v:'',s:st.id(:total)}]
 list=[['İcmal',ic],['Hakediş Cetveli',hc]]
 unless rec
  mt=[[{v:"Onaylı Metraj — eleman bazında (#{vdate} itibarıyla, kümülatif)",s:st.id(:title)}],
      [{v:'Dönem sonu tarihine kadar onaylanmış iş kalemleri. Eski "Onaylandı" eleman durumu tüm kalemler için %100 sayılır. Satır toplamı poz miktarıyla sınırlandırılır.',s:st.id(:note)}],[]]
  mt << ['Poz No','Eleman','Tip','Yapı','Eleman Miktarı','Onaylı %','Onay Tarihi','Onaylayan','Onaylı Miktar'].map{|h|{v:h,s:st.id(:header)}}
  brows=boq_rows(true)
  rows.each do |r|
   next if r[:removed] || r[:manual]
   row=prog2_find_row(r[:key],brows);next unless row
   src=r[:source].to_s
   prog2_row_entities(row).each do |e|
    f=prog2_frac(e,src,vdate);next unless f>0
    q=progress_entity_quantity(e,src).to_f
    rc=prog2_rec(e,src);x=rc ? prog2_ok_entry(rc,vdate) : nil
    when_s=x ? (x[0].to_s=='0000-00-00' ? 'eski durum' : x[0].to_s) : 'eski durum'
    mt << [{v:r[:code].to_s,s:st.id(:cell)},{v:element_visible_id(e).to_s,s:st.id(:cell)},{v:e.get_attribute(DICT,'element_type','').to_s,s:st.id(:cell)},
           {v:(e.get_attribute(DICT,'ano','').to_s.empty? ? e.get_attribute(DICT,'structure','').to_s : e.get_attribute(DICT,'ano','').to_s),s:st.id(:cell)},
           {v:q,s:st.id(:cell,boq2_qty_fmt(r[:unit]))},{v:f,s:st.id(:cell,'0%')},{v:when_s,s:st.id(:cell)},{v:(x ? x[2] : '').to_s,s:st.id(:cell)},
           {v:q*f,s:st.id(:cell,boq2_qty_fmt(r[:unit]))}]
   end
  end
  list << ['Onaylı Metraj',mt]
 end
 extra=[['Dönem',title]]
 extra << ['Fiyat farkı (bu dönem)',format('%.2f %s',(rec ? rec['price_diff'] : prog2_view_pd).to_f,cur)]
 extra << ['Not',rec['note'].to_s] if rec && !rec['note'].to_s.empty?
 list << ['Bilgi',boq2_info_rows(st,'Hakediş Bilgileri',extra)]
 boq2_xl_write(path,{styles:st,list:list})
end

def boq2_excel_ui(kind,period=nil)
 model=Sketchup.active_model
 proj=model.get_attribute(DICT,'project_name','').to_s.strip
 base=proj.empty? ? 'MST' : proj.gsub(/[^\p{Alnum}\-_ ]/,'').strip.tr(' ','_')
 name=kind=='kesif' ? "#{base}_Kesif_Cetveli_#{Time.now.strftime('%Y%m%d')}.xlsx" : "#{base}_Hakedis_#{period.to_i>0 ? format('%02d',period.to_i) : 'onizleme'}_#{Time.now.strftime('%Y%m%d')}.xlsx"
 path=UI.savepanel(kind=='kesif' ? 'Keşif Cetveli — Excel' : 'Hakediş Raporu — Excel',(File.dirname(model.path) rescue ''),name)
 return unless path
 path+='.xlsx' unless path.downcase.end_with?('.xlsx')
 names=kind=='kesif' ? boq2_kesif_xlsx_write(path) : boq2_hakedis_xlsx_write(path,period)
 if UI.messagebox("Excel hazır (#{names.join(' · ')}):\n#{path}\n\nDosya açılsın mı?",MB_YESNO)==IDYES
  UI.openURL('file:///'+path.tr('\\','/').sub(%r{\A/+},''))
 end
rescue => e
 UI.messagebox("Excel'e aktarılamadı:\n#{e.message}")
end

# ---------------------------------------------------------------- arayüz bağlantıları
def boq2_set_view(raw)
 d=raw.is_a?(String) ? (JSON.parse(raw) rescue {'date'=>raw}) : (raw || {})
 x=d['date'].to_s.strip
 @prog2_view_date=(boq2_date_ok?(x) ? x : nil)
 if d.key?('price_diff')
  pd=boq2_num(d['price_diff'])
  raise 'Fiyat farkı sayı olmalı.' if pd.nil? && !d['price_diff'].to_s.strip.empty?
  @prog2_view_pd=pd.to_f
 end
 true
end
def boq2_register_callbacks(d)
 wrap=->(name,&blk){d.add_action_callback(name){|_,*a|begin;blk.call(*a);rescue => e
   d.execute_script("window.bq2Error&&bq2Error(#{JSON.generate(e.message.to_s)})") rescue nil
   UI.messagebox(e.message);end}}
 wrap.('boq2_get'){d.execute_script("boq2Loaded(#{JSON.generate(boq2_payload)})")}
 wrap.('boq2_save_items'){|j|boq2_save_items(j);send_boq(d)}
 wrap.('boq2_reset_items'){boq2_reset_items;send_boq(d)}
 wrap.('boq2_items_export'){boq2_items_export}
 wrap.('boq2_items_import'){boq2_items_import;send_boq(d)}
 wrap.('boq2_save_settings'){|j|boq2_save_settings(j);send_boq(d)}
 wrap.('boq2_save_contract'){|j|boq2_save_contract(j);progress_send(d)}
 wrap.('boq2_contract_preset'){|t|c=BOQ2_CONTRACT_PRESETS[t.to_s] or raise('Bilinmeyen sözleşme tipi.');boq2_save_contract(c);progress_send(d)}
 wrap.('boq2_kesif_excel'){boq2_excel_ui('kesif')}
 wrap.('prog2_excel'){|n|boq2_excel_ui('hakedis',n.to_i)}
 wrap.('mst_find'){n=(respond_to?(:mst_find_ui) ? mst_find_ui.to_i : 0);d.execute_script("prog2SelectionLoaded(#{JSON.generate(prog2_selection_info)})")}   # v0.47.3 LB1
 wrap.('prog2_selection'){d.execute_script("prog2SelectionLoaded(#{JSON.generate(prog2_selection_info)})")}
 wrap.('prog2_apply'){|j|n=prog2_apply(j);d.execute_script("prog2Applied(#{JSON.generate({count:n})})");d.execute_script("prog2SelectionLoaded(#{JSON.generate(prog2_selection_info)})");progress_send(d)}
 wrap.('prog2_manual'){|j|prog2_manual_set(j);d.execute_script("prog2SelectionLoaded(#{JSON.generate(prog2_selection_info)})");progress_send(d)}
 wrap.('prog2_select'){|j|n=prog2_select(j);d.execute_script("prog2Selected(#{n})")}
 wrap.('prog2_isolate'){|on|n=prog2_isolate(on.to_s=='1');d.execute_script("prog2Isolated(#{JSON.generate({on:on.to_s=='1',count:n})})")}
 wrap.('prog2_save'){|j|progress_save(j,d)}
 wrap.('prog2_view'){|j|boq2_set_view(j);progress_send(d)}
 wrap.('prog2_view_date'){|dt|boq2_set_view({'date'=>dt.to_s});progress_send(d)}
end

end
end
