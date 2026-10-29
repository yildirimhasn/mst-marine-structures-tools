# frozen_string_literal: true
require 'cgi'
require 'json'
require 'digest'
require 'base64'
require 'tempfile'
require_relative 'safe_report_file'
module MAG
 module MarineStructuresTools
  module HealthReport
   extend self
   STATES={'error'=>'Hata var','warning'=>'Uyarı var','limited'=>'Sınırlı kontrol','checked'=>'Uygulanan kontroller geçti'}.freeze
   CATEGORIES={'identity'=>'Kimlik','relationship'=>'Bağlantı','metadata'=>'Kayıt','geometry'=>'Geometri / kot','quantity'=>'Metraj'}.freeze
   SEVERITIES={'error'=>'Hata','warning'=>'Uyarı','info'=>'Bilgi'}.freeze
   def esc(value);CGI.escapeHTML(value.to_s);end
   def quantity(record)
    return '—' unless record
    return 'Eksik kayıt' if record[:state]=='missing'
    return 'Geçersiz kayıt' if record[:state]=='invalid'
    return 'Uygulanmaz' if record[:state]=='not_applicable'
    number=Float(record[:value]);raise 'Rapor miktarı sonlu olmalı.' unless number.finite?
    "#{format('%.3f',number).tr('.',',')} #{record[:unit]}#{record[:state]=='estimated' ? ' (tahmini)' : ''}"
   end
   def render(snapshot,model_name:'Adsız model')
    raise 'Desteklenmeyen model kontrol raporu.' unless snapshot[:schema]=='mst.model-health/1'&&snapshot[:records].is_a?(Array)
    source=JSON.generate(snapshot);digest=Digest::SHA256.hexdigest(source);records=snapshot[:records]
    cards=[['Eleman',:elements],['Hatalı eleman',:errors],['Uyarılı eleman',:warnings],['Sınırlı kontrol',:limited],['Kontroller geçti',:checked]].map{|label,key|"<div>#{label}<strong>#{esc(snapshot[:summary][key])}</strong></div>"}.join
    findings=records.flat_map do |r|
     r[:checks].map do |c|
      "<tr><td>#{esc(r[:id])}<br><small>#{esc(r[:label])}</small></td><td>#{esc(SEVERITIES.fetch(c[:severity]))}</td><td>#{esc(CATEGORIES.fetch(c[:category],c[:category]))}</td><td>#{esc(c[:message])}</td></tr>"
     end
    end.join
    findings='<tr><td colspan="4">Bu rapor kapsamında bulgu kaydı yok. Denetlenmeyen geometri kapsamını ayrıca inceleyin.</td></tr>' if findings.empty?
    rows=records.map do |r|
     quantities=[:concrete_m3,:steel_t,:rebar_t,:formwork_m2].map{|key|"<td>#{esc(quantity(r[:quantities][key]))}</td>"}.join
     "<tr><td>#{esc(r[:id])}<br><small>#{esc(r[:label])}</small></td><td>#{esc(STATES.fetch(r[:state]))}</td><td>#{r[:geometry]=='profile_checked' ? 'Kesit kontrolü uygulandı' : 'Fiziksel kesit doğrulanmadı'}</td>#{quantities}</tr>"
    end.join
    rows='<tr><td colspan="7">Bu kapsamda yapı elemanı bulunamadı. Boş rapor teslim onayı değildir.</td></tr>' if rows.empty?
    <<~HTML
     <!doctype html><html lang="tr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>MST Model Kontrol Raporu — #{esc(model_name)}</title><style>
     *{box-sizing:border-box}body{margin:0;background:#edf3f6;color:#19394d;font:14px Arial;line-height:1.5}main{max-width:1200px;margin:auto;padding:30px}header{padding:24px;background:#173749;color:white;border-radius:8px}h1{margin:0;font-size:26px}h2{font-size:20px;margin:26px 0 12px}.metrics{display:grid;grid-template-columns:repeat(5,1fr);gap:10px;margin:20px 0}.metrics div{padding:16px;background:white;border-radius:6px}.metrics strong{display:block;font-size:25px}.note{padding:14px;background:#fff4dc;border-left:4px solid #ac6a13}.table-wrap{overflow:auto}table{width:100%;border-collapse:collapse;background:white;font-size:12px}th,td{padding:10px;text-align:left;border:1px solid #d5e1e9;vertical-align:top}th{background:#dfeaf0}small{color:#526878}code,pre{overflow-wrap:anywhere;white-space:pre-wrap;font-size:11px}a{color:#12667b}footer{margin-top:24px;font-size:12px}@media(max-width:750px){main{padding:16px}.metrics{grid-template-columns:1fr 1fr}}@page{size:A4 landscape;margin:12mm}@media print{body{background:white}main{max-width:none;padding:0}header{color:#19394d;background:white;border:1px solid #b5cbd9}.metrics{grid-template-columns:repeat(5,1fr)}thead{display:table-header-group}tr{break-inside:avoid}h2{break-after:avoid}details,.download{display:none}.table-wrap{overflow:visible}table{font-size:9px}th,td{padding:6px}.note{background:white;border:1px solid #ac6a13}}
     </style></head><body><main><header><h1>Model Kontrol Raporu</h1><p>#{esc(model_name)}</p><p>Kontrol anı (UTC): #{esc(snapshot[:created_at])} · MST v#{esc(snapshot[:version])}</p></header>
     <div class="metrics">#{cards}</div><p class="note"><strong>Fiziksel kesit geometrisi doğrulanmayan eleman: #{esc(snapshot[:summary][:geometry_unchecked])} / #{esc(snapshot[:summary][:elements])}.</strong> Hata/uyarı bulunmaması, denetlenmeyen geometrilerin doğrulandığı anlamına gelmez. Bu belge tasarım veya teslim uygunluğu onayı değildir.</p>
     <h2>Kontrol kapsamı ve sınırlar</h2><p>#{esc(snapshot[:limitation])}</p><p>Eleman durumları hata, uyarı, sınırlı kontrol veya uygulanan kontroller geçti olarak gösterilir. Özet sayıları eleman sayılarıdır; bir elemanda birden fazla bulgu olabilir. Bu rapor oluşturma anının görüntüsüdür; sonraki model değişikliklerini izlemez. Tablo miktarları kaynak bazında verilmiştir; farklı kapsamlardaki miktarlar genel keşif toplamı olarak toplanmamıştır.</p>
     <h2>Bulgular</h2><div class="table-wrap"><table><thead><tr><th>Eleman</th><th>Önem</th><th>Kategori</th><th>Bulgu</th></tr></thead><tbody>#{findings}</tbody></table></div>
     <h2>Elemanlar ve kayıtlı miktarlar</h2><p>Başlık kirişindeki kalıp miktarı net kalıptır. Diğer elemanlarda mevcut metraj servisinin miktarı gösterilir. “—”, bu raporda sunulmayan miktarı belirtir; sıfır değildir. Eksik ve geçersiz kayıtlar ayrı yazılır.</p><div class="table-wrap"><table><thead><tr><th>Eleman</th><th>Kontrol sonucu</th><th>Geometri kapsamı</th><th>Beton</th><th>Boru çeliği</th><th>Donatı</th><th>Kalıp</th></tr></thead><tbody>#{rows}</tbody></table></div>
     <footer><p><strong>Kaynak verinin SHA-256 parmak izi</strong><br><code>#{digest}</code></p><p>Parmak izi, aşağıdaki kaynak JSON metninin UTF-8 baytlarından hesaplanmıştır. Veri karşılaştırması içindir; dijital imza, onaylı referans veya mühendislik onayı değildir.</p><p class="download"><a download="MST_Model_Kontrol_Kaynak.json" href="data:application/json;base64,#{Base64.strict_encode64(source)}">Kaynak JSON verisini indir</a></p><details><summary>Kaynak JSON verisini göster</summary><pre id="mst-source">#{esc(source)}</pre></details><p>Rapor çevrimdışı açılabilir; harici yazı tipi, ağ kaynağı veya çalışan betik içermez. Tarayıcının Yazdır komutuyla PDF olarak kaydedilebilir.</p></footer>
     </main></body></html>
    HTML
   end
   def export(model)
    snapshot=ModelHealth.analyze(model)
    name=model.respond_to?(:title) ? model.title.to_s.strip : ''
    name='Adsız model' if name.empty?
    export_snapshot(snapshot,model_name:name)
   end
   def export_snapshot(snapshot,model_name:,filename:'MST_Model_Kontrol_Raporu.html')
    html=render(snapshot,model_name:model_name)
    path=UI.savepanel('Model Kontrol Raporunu Kaydet','',filename)
    return nil unless path
    path+='.html' unless path.downcase.end_with?('.html')
    SafeReportFile.write(path,html)
    snapshot
   end
  end
 end
end
