# Parti C statik kontrol — K24: kod dosyalarinda (.rb .js .html) eski `skp:` URL semasi kalmamali (SketchUp disinda).
# Metin dosyalari (.txt) ayrica sayilir; belge icindeki anma hata degildir.
# Kullanim: ruby tools/test/c_skp_scheme.rb <src/marine_structures_tools>
require_relative 'a1_helper'
dir = A1.dir
root = File.dirname(File.expand_path(dir))   # src/ (yukleyici dahil)
code = Dir[File.join(root, '**', '*.{rb,js,html}')].sort
hits = code.flat_map do |f|
  File.binread(f).force_encoding('UTF-8').lines.each_with_index.select { |l, _| l.include?('skp:') }.map { |_, i| "#{f.sub(root + '/', '')}:#{i + 1}" }
end
obs('taranan kod dosyası', code.size)
t('kod dosyalarında `skp:` sayısı', hits, [])
txt = Dir[File.join(root, '**', '*.txt')].sort.flat_map do |f|
  File.binread(f).force_encoding('UTF-8').lines.each_with_index.select { |l, _| l.include?('skp:') }.map { |_, i| "#{f.sub(root + '/', '')}:#{i + 1}" }
end
obs('metin dosyalarında `skp:` anması (hata değil)', txt)
a1_finish
