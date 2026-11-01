# frozen_string_literal: true
require 'cgi'
module MAG
module MarineStructuresTools
 def rf_report_escape(value);CGI.escapeHTML(value.to_s);end
 def rf_report_number(value)
  return '—' if value.nil?
  whole,decimal=format('%.3f',value).split('.')
  whole.reverse.gsub(/(\d{3})(?=\d)/,'\\1.').reverse+','+decimal
 end
 def rf_report_table(headers,rows)
  '<div class="table-wrap"><table><thead><tr>'+headers.map{|h|'<th>'+rf_report_escape(h)+'</th>'}.join+'</tr></thead><tbody>'+rows.map{|row|'<tr>'+row.map{|v|'<td'+(v.to_s.match?(/\A-?[0-9][0-9.,]*\z/) ? ' class="number"' : '')+'>'+rf_report_escape(v)+'</td>'}.join+'</tr>'}.join+'</tbody></table></div>'
 end
 def rf_live_report_html(state,result,library,project,loft=nil,created=Time.now)
  e=method(:rf_report_escape);n=method(:rf_report_number)
  sections=[];tonnage=0.0;complete=true
  rows=result['totals'].sort.map do |code,volume|
   matches=library.select{|m|m['code']==code};material=matches.size==1 ? matches.first : nil
   density=begin;Float(material['density']) if material;rescue ArgumentError,TypeError;nil;end
   density=nil unless density && density.finite? && density>0
   ton=density ? volume*density : nil
   ton=nil if ton && !ton.finite?
   complete=false unless ton;tonnage+=ton if ton
   [code,material ? material['name'] : 'Kütüphane kaydı eksik / tekrarlı',n.call(volume),density ? n.call(density) : 'Eksik / geçersiz',n.call(ton)]
  end
  rows<<['TOPLAM TAŞ','',n.call(result['total']),'',complete ? n.call(tonnage) : 'Eksik yoğunluk — toplam verilmedi']
  sections<<'<h2>1. Malzeme toplamları</h2>'+rf_report_table(['Kod','Malzeme','Hacim (m³)','Yoğunluk (t/m³)','Tonaj (t)'],rows)
  sections<<'<p><b>Kazı — taş toplamından ayrı: '+n.call(result['excavation_m3']||0)+' m³.</b></p>'
  settings=[['Kesit aralığı (m)',n.call(state['step'])],['Aks boyu (m)',n.call(result['total_length'])],['Tip / istasyon kaydı',result['sections'].size],['İlave istasyonlar (m)',(state['extra']||[]).map{|v|n.call(v)}.join('; ')],['Aks yönü',state['reverse'] ? 'Ters' : 'Normal'],['Taban kaynağı',state['surface_mode']=='contours' ? '3B kot eğrilerinden TIN' : 'Seçilmiş yüzey'],['Tip geçişi',state['type_transition']=='linear' ? 'Doğrusal' : 'Ani'],['Boşluk kapanışı',state['void_transition']=='point' ? 'Noktasal kapanış' : 'Sayısı değişirse durdur'],['Kazı',state.dig('excavation','enabled') ? 'Var' : 'Yok'],['Baş',state.dig('head','enabled') ? "Var — parametrik #{state.dig('head','angle') || 180}°" : 'Yok']]
  if state.dig('excavation','enabled')
   settings<<['Kazı sol / sağ koridor (m)',n.call(state['excavation']['left'])+' / '+n.call(state['excavation']['right'])]
  end
  sections<<'<h2>2. Girdiler ve hesap kabulleri</h2>'+rf_report_table(['Girdi','Değer'],settings)
  sections<<'<p>Gövde yöntemi: ortalama uç alanları, V = (A₁ + A₂) / 2 × L. Tonaj = hacim × kütüphane yoğunluğu. Beton olarak işaretlenmiş kesit alanları taş hesabından düşülür. Alternatif-01 miktarları bu rapora eklenmez.</p>'
  (result['assumptions']||[]).each{|a|sections<<'<p>'+e.call(a)+'</p>'}
  state['reaches'].sort_by{|r|r['from']}.each do |reach|
   spec=state['types'].fetch(reach['type'])
   sections<<'<h3>'+e.call(spec['name']||reach['type'])+' — başlangıç '+n.call(reach['from'])+' m</h3>'
   if spec['mode']=='parametric'
    details=[['Tepe kotu (m)',n.call(spec['crest'])],['Tepe genişliği (m)',n.call(spec['width'])],['Sol şev (1V:H)',n.call(spec['slope_left'])],['Sağ şev (1V:H)',n.call(spec['slope_right'])]]
    sections<<rf_report_table(['Parametre','Değer'],details)
    layers=spec['layers'].each_with_index.map{|l,i|[i+1,l['code'],i==spec['layers'].size-1 ? 'Çekirdek — kalan bölge' : n.call(l['thickness'])+' m (şeve dik)']}
    sections<<rf_report_table(['Dıştan içe sıra','Malzeme','Kalınlık'],layers)
   elsif spec['mode']=='portable_faces'
    sections<<'<p>Dosyadan alınmış sabit kesit şablonu. Ofset/kot koordinatları metre cinsindedir. Kaynak çizime canlı bağlı değildir; kaynak çizimdeki değişiklik için yeniden aktarılmalıdır.</p>'
   else
    sections<<'<p>Çizilmiş kapalı kesit; düzlem '+e.call(spec['plane'])+'; açı '+n.call(spec['angle'])+'°; kot referansı '+n.call(spec['datum'])+' m; köken XYZ '+e.call((spec['origin']||[]).map{|v|n.call(v)}.join(' / '))+' m.</p>'
   end
  end
  if result['head']
   h=result['head'];sections<<'<h2>3. Baş hesabı — toplamların içinde</h2>'
   sections<<rf_report_table(['Malzeme','Gövde (m³)','Baş (m³)'],(result['totals'].keys).sort.map{|code|[code,n.call(result['body_totals'][code]||0),n.call(h['totals'][code]||0)]})
   sections<<'<p>Baş açısal aralığı: '+n.call(h['step'])+'°; sıklaştırma farkı: '+n.call(h['refinement_difference_m3'])+' m³. Baş kazısı '+n.call(h['excavation_m3'])+' m³, kazı toplamına dahildir. Sıklaştırma farkı kesin hata sınırı değildir.</p>'
  end
  sections<<'<h2>4. Gövde aralık kübajı</h2><p>Baş bu tabloya eklenmez. Aynı aralığın malzemeleri ayrı satırlardadır; kazı ayrı sütunda yalnız ilk satırda gösterilir.</p>'
  intervals=result['rows'].flat_map do |r|
   codes=r['volumes'].keys.sort;codes=['—'] if codes.empty?
   codes.each_with_index.map{|code,i|[n.call(r['start']),n.call(r['end']),r['type'],code,n.call(r['a1'][code]||0),n.call(r['a2'][code]||0),n.call(r['end']-r['start']),n.call(r['volumes'][code]||0),i==0 ? n.call(r['excavation_m3']||0) : '—']}
  end
  sections<<rf_report_table(['Başlangıç (m)','Bitiş (m)','Tip','Malzeme','A₁ (m²)','A₂ (m²)','L (m)','Taş (m³)','Kazı (m³)'],intervals)
  sections<<'<h2>5. İstasyon alanları</h2>'+rf_report_table(['İstasyon (m)','Tip','Malzeme','Net alan (m²)','Kazı alanı (m²)'],result['sections'].sort_by{|s|[s['station'],s['type']]}.flat_map{|s|codes=s['areas'].keys.sort;codes=['—'] if codes.empty?;codes.each_with_index.map{|code,i|[n.call(s['station']),s['type'],code,n.call(s['areas'][code]||0),i==0 ? n.call(s['cut_area']||0) : '—']}})
  sections<<'<h2>6. Katı kontrolü</h2>'
  if loft && loft['current']
   sections<<rf_report_table(['Malzeme','Katı (m³)','AEA / radyal (m³)','Fark (m³)'],loft['rows'].map{|r|[r['code'],n.call(r['solid_m3']),n.call(r['quantity_m3']),n.call(r['difference_m3'])]})
  else
   sections<<'<p>'+ (loft ? 'Önceki üretilmiş katılar güncel değil; hacimleri rapora alınmadı.' : 'Güncel otomatik katı kontrolü bulunmuyor.') +'</p>'
  end
  (result['solid_comparison']||[]).each{|r|sections<<'<p>Bağlı bağımsız katı '+e.call(r['code'])+': '+n.call(r['solid_m3'])+' m³; hesapla fark '+n.call(r['difference_m3'])+' m³.</p>'}
  sections<<'<h2>7. İzlenebilirlik</h2><p>Hesap girdisi özeti: <code>'+e.call(result['fingerprint'])+'</code></p><p>Model içi kaynak kimlikleri — aks: '+e.call((state['axis_ids']||[]).join(', '))+'; taban: '+e.call((state['surface_ids']||[]).join(', '))+'</p><p>Rapor anlık çıktıdır; model değişince yenilenmelidir. Formdaki girdilerle hazırlanmıştır; rapor alma işlemi kayıtlı metrajı ve aktif keşif kaynağını değiştirmez. Gösterimde üç ondalığa yuvarlama yapılır; toplamlar yuvarlanmamış değerlerden hesaplanır.</p>'
  '<!doctype html><html lang="tr"><meta charset="utf-8"><title>Alternatif-02 Kübaj — '+e.call(project)+'</title><style>body{font:14px/1.5 Arial,sans-serif;color:#183748;margin:0;background:#edf3f6}main{max-width:1200px;margin:auto;padding:32px;background:white}h1{font-size:28px}h2{margin-top:32px;border-bottom:2px solid #08788c;padding-bottom:8px}table{border-collapse:collapse;width:100%;font-size:12px;margin:14px 0}th,td{padding:8px;border:1px solid #ccdbe2;text-align:left}th{background:#e8f1f5}td.number{text-align:right;font-variant-numeric:tabular-nums}td{overflow-wrap:anywhere}code{overflow-wrap:anywhere}.table-wrap{overflow:auto}thead{display:table-header-group}tr{break-inside:avoid}@media print{@page{size:A4 landscape;margin:12mm}body{background:white}main{padding:0;max-width:none}.table-wrap{overflow:visible}h2,h3{break-after:avoid}th,td{padding:5px}table{font-size:10px}}</style><main><small>DENİZ YAPILARI ARAÇLARI (MST) v'+VERSION.to_s+' · ALTERNATİF-02</small><h1>Dolgu / Taş Kübaj Hesap Raporu</h1><p><b>Proje:</b> '+e.call(project)+' · <b>Oluşturma:</b> '+e.call(created.strftime('%d.%m.%Y %H:%M:%S %z'))+'</p>'+sections.join+'</main></html>'
 end
 def rf_live_export_report(state,dialog)
  result=rf_live_result(state)
  project=Sketchup.active_model.get_attribute(DICT,'project_name','').to_s.strip
  project='İsimsiz proje' if project.empty?
  html=rf_live_report_html(state,result,rockfill_library,project,rf_live_loft_status(state,result))
  path=UI.savepanel('Alternatif-02 Kübaj Raporu',nil,'Alternatif02_Kubaj_'+Time.now.strftime('%Y%m%d_%H%M%S')+'.html')
  unless path
   dialog.execute_script('rfLiveReportSaved("Rapor kaydı iptal edildi; model değiştirilmedi.")');return
  end
  path+='.html' unless File.extname(path).downcase=='.html'
  File.write(path,html,mode:'w',encoding:'UTF-8')
  dialog.execute_script("rfLiveReportSaved(#{JSON.generate('Kübaj raporu kaydedildi: '+path+' — model ve keşif değiştirilmedi.')})")
 end
end
end
