# frozen_string_literal: true
require 'date'
module MAG
module MarineStructuresTools
module PaymentValidation
 extend self
 def date?(value)
  return false unless value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}\z/)
  Date.iso8601(value).year>0
 rescue ArgumentError
  false
 end
 # A missing price is not a free item. A draft may show missing prices, but a
 # frozen payment period cannot silently record payable quantities at zero.
 def period_rows!(rows)
  raise 'Hakediş satırları okunamadı.' unless rows.is_a?(Array)
  missing=[]
  rows.each do |row|
   raise 'Hakediş satırı geçersiz.' unless row.is_a?(Hash)
   label=row[:code].to_s.strip
   label=(row[:source] || '?').to_s if label.empty? || label=='—'
   quantities=%i[quantity previous current_period approved_quantity claimed_quantity].map do |key|
    value=row.fetch(key)
    n=Float(value) rescue nil
    raise "#{label}: #{key} sonlu sayı olmalı." unless n && n.finite?
    raise "#{label}: #{key} negatif olamaz." if key!=:current_period && n<0
    n
   end
   price=row[:unit_price]
   if price.nil? || row[:price_missing]==true
    # Zero-progress, never-paid rows may remain explicitly unpriced in a draft
    # or period. Claimed-only quantities are not approved for payment yet.
    missing<<label if quantities[1].abs>1e-9 || quantities[2].abs>1e-9 || quantities[3].abs>1e-9
   else
    n=Float(price) rescue nil
    raise "#{label}: birim fiyat sonlu ve negatif olmayan sayı olmalı." unless n && n.finite? && n>=0
    raise "#{label}: dönem veya kümülatif bedel sayısal sınırı aşıyor." unless (quantities[2]*n).finite? && (quantities[3]*n).finite?
   end
  end
  unless missing.empty?
   raise "Ödemeye giren #{missing.size} pozda birim fiyat eksik: #{missing.first(6).join(', ')}. Fiyatları eşleştirin; eksik fiyat sıfır kabul edilerek dönem kaydedilemez."
  end
  true
 end
end
end
end
