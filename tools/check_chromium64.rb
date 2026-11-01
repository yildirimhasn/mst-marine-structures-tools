# Chromium 64 (SketchUp 2020 HtmlDialog) ile uyumsuz JS sozdizimi taramasi — yalniz tabana gore EKLENEN satirlar.
# Kapsam: src altindaki .js, .html ve .rb (Ruby dizgisi icindeki JS) dosyalarinin `git diff -U0 <taban>` eklenen satirlari.
# Kullanim: ruby tools/check_chromium64.rb [taban_commit=872d3a3]   (depo kokunden calistirilir)
# Cikti: her eslesme "HIT <dosya>:<satir> <desen> | <satir>"; sonda "added_lines=N hits=H". .rb dosyasinda `.at(` Ruby Array#at
# olabilecegi icin ayrica "RB?" etiketiyle yazilir ve hits sayisina katilir (elle bakilmali).
require 'open3'
base = ARGV[0] || '872d3a3'
PATS = {
  'optional chaining ?.' => /\?\.(?!\d)/,
  'nullish ??' => /\?\?/,
  'catch{ (baglamsiz)' => /\bcatch\s*\{/,
  '.flat(' => /\.flat\(/,
  '.flatMap(' => /\.flatMap\(/,
  '.replaceAll(' => /\.replaceAll\(/,
  '.at(' => /\.at\(/,
  'Object.fromEntries' => /Object\.fromEntries/,
  'globalThis' => /\bglobalThis\b/
}.freeze
out, st = Open3.capture2('git', '-c', 'core.quotepath=false', 'diff', '-U0', base, '--', 'src')
abort "git diff basarisiz" unless st.success?
file = nil
line = 0
added = 0
hits = 0
out.force_encoding('UTF-8').each_line do |l|
  if l.start_with?('+++ ')
    file = l[4..-1].strip.sub(%r{\Ab/}, '')
  elsif l =~ /\A@@ -\S+ \+(\d+)/
    line = Regexp.last_match(1).to_i
  elsif l.start_with?('+') && file && file =~ /\.(js|html|rb)\z/
    added += 1
    txt = l[1..-1]
    PATS.each do |name, re|
      next unless txt =~ re
      hits += 1
      tag = file.end_with?('.rb') ? 'HIT RB?' : 'HIT'
      puts "#{tag} #{file}:#{line} #{name} | #{txt.strip[0, 160]}"
    end
    line += 1
  end
end
puts "base=#{base} added_lines=#{added} hits=#{hits}"
exit(hits.zero? ? 0 : 1)
