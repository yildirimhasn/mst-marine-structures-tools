# Gömülü sayfa köprüsü (mstEmbedShim): srcdoc iframe'de "#bölüm" bağlantısı ana arayüzü yüklememeli.
# Kullanim: ruby tools/test/q1_embed_anchor_run.rb src/marine_structures_tools
require 'tmpdir'
src=ARGV[0] or abort('kullanim: ruby q1_embed_anchor_run.rb <src/marine_structures_tools>')
h=File.read(File.join(src,'ui.html'),encoding:'utf-8')
f=h[/function mstEmbedShim\(key\)\{.*?\n\}/m] or abort('mstEmbedShim yok')
Dir.mktmpdir do |d|
 File.write(File.join(d,'shim.js'),f+"\nmodule.exports=mstEmbedShim;")
 out=`node #{File.join(__dir__,'q1_embed_anchor.js')} #{File.join(d,'shim.js')}`
 ok=$?.success? && out.include?('ic_baglanti: engellendi=true kaydirildi=group-fender') && out.include?('dis_baglanti: engellendi=false') && out.include?('dugme: engellendi=false')
 puts out
 puts ok ? '3 geçti, 0 kaldı' : '0 geçti, 3 kaldı'
 exit(ok ? 0 : 1)
end
