# frozen_string_literal: true
module MAG
module MarineStructuresTools
def system_export_sheets
 boq=boq_rows
 priced=boq.sum{|r|r[:total].to_f};missing=boq.count{|r|r[:total].nil?}
 boq_data=boq.map{|r|[r[:code],r[:name],r[:quantity],r[:unit],r[:unit_price],r[:total],'USD',r[:source],r[:status]]}
 boq_data<<['',missing>0 ? "KISMİ TOPLAM — #{missing} satır fiyatlandırılmadı" : 'TOPLAM',nil,nil,nil,priced,'USD',nil,nil]
 fore=bp_rows.map do |r|
  d=r[:data]
  [d['type_id'],d['diameter'],d['top'],d['bottom'],d['concrete'],r[:count],r[:total_length],r[:drilling],r[:concrete],r[:order],r[:rebar],d['casing'],r[:casing]]
 end
 accessories=accessory_rows.select{|r|r['quantity'].to_f>0}.map{|r|[r['type'],accessory_description(r),r['location'],r['quantity'],r['unit'],r['capacity'],r['hooks'],r['scope']]}
 rf=rockfill_qto_data
 rock=rf[:materials].map{|r|[r[:code],r[:name],r[:volume_m3],r[:density],r[:tonnage_t],rf[:source_label]||'Alternatif-01']}
 cut=rf.fetch(:geometry_result,{}).fetch('excavation_m3',0).to_f
 rock<<['KAZI','Kazı — taş toplamından ayrı',cut,nil,nil,rf[:source_label]] if cut>0
 [
  ['Keşif USD',['ÖBF','İş kalemi','Miktar','Birim','Birim fiyat USD','Tutar USD','Para','Kaynak','Durum'],boq_data,[16,65,16,12,20,20,12,32,30]],
  ['Jet Grout',jg_export_headers,jg_export_rows,Array.new(17,20)],
  ['Fore Kazık',['Tip','Çap mm','Üst kot m','Alt kot m','Beton','Adet','Boy m','Delgi m','Beton m³','Sipariş m³','Donatı t','Muhafaza','Muhafaza m'],fore,[18,14,14,14,14,10,16,16,16,16,16,18,16]],
  ['Aksesuarlar',['Tip','Tanım','Konum','Miktar','Birim','Kapasite t/kanca','Kanca/set','Kapsam'],accessories,[18,65,25,16,12,20,16,24]],
  ['Taş Dolgu',['Kod','Malzeme','Hacim m³','Yoğunluk t/m³','Tonaj t','Aktif hesap kaynağı'],rock,[18,55,18,20,18,40]]
 ]
end
end
end
