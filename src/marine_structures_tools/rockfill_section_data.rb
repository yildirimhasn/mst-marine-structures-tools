# frozen_string_literal: true
module MAG
 module MarineStructuresTools
  # Shared input boundary for persisted section-area chains and material data.
  # No SketchUp calls; it must never coerce corrupt data to a zero quantity.
  module RockfillSectionData
   extend self
   def number(value,label,positive=false)
    raise "#{label}: sayısal değer gerekli." if value.nil? || value==true || value==false || value.to_s.strip.empty?
    n=Float(value.to_s.strip.tr(',', '.')) rescue nil
    raise "#{label}: sonlu #{positive ? 'pozitif' : 'negatif olmayan'} sayı gerekli." unless n && n.finite? && (positive ? n>0 : n>=0)
    n
   end
   def library(value)
    raise 'Dolgu malzeme kütüphanesi boş veya bozuk.' unless value.is_a?(Array) && !value.empty?
    seen={}
    value.map do |m|
     raise 'Dolgu malzeme kaydı geçersiz.' unless m.is_a?(Hash)
     code=m['code'].to_s.strip;name=m['name'].to_s.strip
     raise 'Malzeme kodu ve adı boş olamaz.' if code.empty? || name.empty?
     raise "#{code}: malzeme kodu birden fazla kullanılmış." if seen[code]
     seen[code]=true;row=m.merge('code'=>code,'name'=>name,'density'=>number(m['density'],"#{code} yoğunluk (t/m³)",true))
     row['area']=number(m['area'],"#{code} varsayılan alan (m²)") if m.key?('area')
     row
    end
   end
   def sections(value,materials,allow_empty=false)
    raise 'Dolgu kesit zinciri liste olmalı.' unless value.is_a?(Array)
    return [] if allow_empty && value.empty?
    raise 'En az iki dolgu kesiti gerekli.' if value.size<2
    codes=library(materials).map{|m|m['code']};ids={};stations={}
    value.map do |s|
     raise 'Dolgu kesit kaydı geçersiz.' unless s.is_a?(Hash)
     id=s['id'].to_s.strip;raise 'Kesit ID boş olamaz.' if id.empty?
     raise "#{id}: kesit ID birden fazla kullanılmış." if ids[id];ids[id]=true
     station=number(s['station'],"#{id} istasyon (m)")
     raise 'Kesit istasyonları aynı olamaz.' if stations[station];stations[station]=true
     areas=s['areas']
     if areas.nil? && s.key?('materials')
      raise "#{id}: eski malzeme alan listesi geçersiz." unless s['materials'].is_a?(Array)
      areas={};s['materials'].each do |m|
       raise "#{id}: eski malzeme alan kaydı geçersiz." unless m.is_a?(Hash)
       code=m['code'].to_s;raise "#{id}: aynı malzeme iki kez girilmiş." if areas.key?(code)
       areas[code]=m['area']
      end
     end
     areas={} if areas.nil? && !s.key?('areas')
     raise "#{id}: alanlar kod/alan eşleştirmesi olmalı." unless areas.is_a?(Hash)
     normalized={};areas.each do |code,area|
      code=code.to_s.strip
      raise "#{id} / #{code}: malzeme kütüphanesinde kayıt yok; alan silinmedi." unless codes.include?(code)
      raise "#{id} / #{code}: malzeme alanı iki kez girilmiş." if normalized.key?(code)
      normalized[code]=number(area,"#{id} / #{code} alan (m²)")
     end
     s.merge('id'=>id,'station'=>station,'areas'=>normalized)
    end.sort_by{|s|s['station']}
   end
   def parse(raw,label)
    JSON.parse(raw)
   rescue JSON::ParserError,TypeError
    raise "#{label} okunamadı; bozuk kayıt sıfır metraj olarak kullanılmadı."
   end
  end
 end
end
