# encoding: utf-8
# MST KOŞU 12 — G-130 temiz kurulum doğrulaması: Plugins altındaki tüm NİHAİ (ADAY17) dosyalarının SHA-256'sı manifestle karşılaştırılır.
# Kullanım: RBZ kurulumu + SketchUp yeniden başlatma sonrası Ruby Console'da load. Salt okuma; dosya değiştirmez.
require 'json'
require 'digest'
module MSTKosu12
  MAN = File.join(File.dirname(__FILE__), 'kosu_12_manifest_nihai.json')
  def self.calistir
    man = JSON.parse(File.read(MAN, encoding: 'UTF-8'))
    plug = Sketchup.find_support_file('Plugins')
    eksik = []; fark = []; tamam = 0
    man.each do |rel, sha|
      p = File.join(plug, rel)
      if !File.exist?(p) then eksik << rel
      elsif Digest::SHA256.file(p).hexdigest.upcase != sha then fark << rel
      else tamam += 1
      end
    end
    kok = File.join(plug, 'marine_structures_tools')
    fazla = Dir.glob(File.join(kok, '**', '*')).select { |f| File.file?(f) }.map { |f| f.sub(plug + '/', '') }.reject { |r| man.key?(r) }
    a = MAG::MarineStructuresTools rescue nil
    ver = a ? a::VERSION : 'yok'
    ok = eksik.empty? && fark.empty? && ver == '0.52.18'
    sonuc = {'sketchup'=>Sketchup.version, 'ruby'=>RUBY_VERSION, 'mst_surum'=>ver, 'manifest'=>man.size, 'ayni'=>tamam, 'eksik'=>eksik, 'farkli'=>fark, 'fazla_dosya'=>fazla.first(20), 'fazla_adet'=>fazla.size, 'eklenti_yuklu'=>!a.nil?, 'tarih'=>Time.now.strftime('%d.%m.%Y %H:%M:%S')}
    File.write(File.join(File.dirname(__FILE__), 'kosu12_sonuc.json'), JSON.pretty_generate(sonuc))
    puts "KOŞU 12 #{ok ? 'PASS' : 'FAIL'}: manifest=#{man.size} aynı=#{tamam} eksik=#{eksik.size} farklı=#{fark.size} fazla=#{fazla.size} sürüm=#{ver}"
  rescue Exception => e
    puts "KOŞU 12 HATA: #{e.class}: #{e.message}"
  end
end
MSTKosu12.calistir
