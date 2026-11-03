# frozen_string_literal: true
require 'sketchup.rb'
require 'extensions.rb'
unless file_loaded?(__FILE__)
  extension=SketchupExtension.new('MST 0.51.5 — Birleşim Testi (Salt Okunur)','mst_tb1_integration_runner/main')
  extension.description='MST 0.51.5 TB1 FIX1 birleşimi için yükleme, kaynak, Ruby ve saf hesap testleri. Otomatik çalışmaz; model geometrisi oluşturmaz.'
  extension.version='1.2.7'
  extension.creator='MST'
  Sketchup.register_extension(extension,true)
  file_loaded(__FILE__)
end
