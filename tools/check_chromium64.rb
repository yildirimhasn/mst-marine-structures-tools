# Chromium 64 (SketchUp 2020 HtmlDialog) ile uyumsuz JS sozdizimi ve CSS taramasi — yalniz tabana gore EKLENEN satirlar.
# Kapsam: src altindaki .js, .html, .css ve .rb (Ruby dizgisi icindeki JS/CSS) dosyalarinin `git diff -U0 <taban>` eklenen satirlari.
# Kullanim: ruby tools/check_chromium64.rb [taban_commit=872d3a3]   (depo kokunden calistirilir)
# Cikti (JS): her eslesme "HIT <dosya>:<satir> <desen> | <satir>". .rb dosyasinda `.at(` Ruby Array#at olabilecegi icin
# "HIT RB?" etiketiyle yazilir ve hits sayisina katilir (elle bakilmali).
# CSS (Parti H / ADR 17 H2): `inset:`, `min(`, `max(`, `clamp(` (JS `Math.min(` vb. ve `minmax(` haric). Her eslesme
#   "CSS <dosya>:<satir> <desen> <YEDEKLİ|YEDEKSİZ> <yeni|eski> | <baglam>":
#   YEDEKLİ  = ayni kural/stil icinde asil bildirimden ONCE yedek var (inset → top/right/bottom/left; min()/max()/clamp() → ayni
#              ozellik fonksiyonsuz degerle). YEDEKSİZ = yedek yok.
#   eski     = ayni diff parcasinin (hunk) silinen satirlarinda ayni desen en az ayni sayida var (taban satirindan tasinan);
#   yeni     = parcada net artis var.
#   hits'e yalniz "YEDEKSİZ yeni" CSS eslesmeleri katilir.
# Flex `gap:` (grid-gap/row-gap/column-gap haric) yalniz BILGI: hits'e katilmaz; baglamina gore flex/grid/belirsiz ve yeni/eski
#   ayri sayilir; ayrica taban ve calisma agacindaki toplam `gap:` sayisi yazilir. Yalniz yeni olanlar "INFO gap" satiri olarak listelenir.
# Sonda: CSS/INFO ozet satirlari ve "base=… added_lines=N hits=H". Cikis kodu: hits=0 ise 0.
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
CSS_PATS = {
  'inset:' => /(?<![-\w])inset\s*:/,
  'min(' => /(?<![\w.$-])min\(/,
  'max(' => /(?<![\w.$-])max\(/,
  'clamp(' => /(?<![\w.$-])clamp\(/
}.freeze
GAP = /(?<![-\w])gap\s*:/
CSS_FILES = /\.(html|css|rb)\z/
JS_FILES = /\.(js|html|rb)\z/

# eslesmenin kural/stil baglami: son '{' ya da style= ile baslar, sonraki '}' ya da tirnakta biter
def css_ctx(txt, pos)
  i = txt.rindex(/style\s*=\s*["']/, pos)
  st = [txt.rindex('{', pos), i && txt.index(/["']/, i) + 1].compact.max || 0
  en = txt.index(/[}"']/, pos) || txt.length
  [txt[st...pos], txt[st...en]]
end

def css_fallback?(name, before)
  if name == 'inset:'
    %w[top right bottom left].all? { |p| before =~ /(?<![-\w])#{p}\s*:/ }
  else
    prop = before[/([-a-z]+)\s*:\s*[^;{}]*\z/, 1]
    return false unless prop
    head = before[0...before.rindex(/(?<![-\w])#{Regexp.escape(prop)}\s*:/)]
    head.scan(/(?<![-\w])#{Regexp.escape(prop)}\s*:\s*([^;{}]*)/).any? { |(v)| v !~ /(?<![\w.$-])(min|max|clamp)\(/ }
  end
end

out, st = Open3.capture2('git', '-c', 'core.quotepath=false', 'diff', '-U0', base, '--', 'src')
abort "git diff basarisiz" unless st.success?
file = nil
line = 0
added = 0
hits = 0
css = Hash.new(0)
gap = Hash.new(0)
hunks = []   # [{file:, minus: [txt], plus: [[satir, txt]]}]
out.force_encoding('UTF-8').each_line do |l|
  if l.start_with?('+++ ')
    file = l[4..-1].strip.sub(%r{\Ab/}, '')
  elsif l.start_with?('--- ')
    next
  elsif l =~ /\A@@ -\S+ \+(\d+)/
    line = Regexp.last_match(1).to_i
    hunks << { file: file, minus: [], plus: [] }
  elsif l.start_with?('-') && hunks.last
    hunks.last[:minus] << l[1..-1]
  elsif l.start_with?('+') && file
    txt = l[1..-1]
    hunks.last[:plus] << [line, txt] if hunks.last
    if file =~ JS_FILES
      added += 1
      PATS.each do |name, re|
        next unless txt =~ re
        hits += 1
        tag = file.end_with?('.rb') ? 'HIT RB?' : 'HIT'
        puts "#{tag} #{file}:#{line} #{name} | #{txt.strip[0, 160]}"
      end
    end
    line += 1
  end
end

hunks.each do |h|
  next unless h[:file] =~ CSS_FILES
  CSS_PATS.each do |name, re|
    old_n = h[:minus].sum { |m| m.scan(re).size }
    new_n = h[:plus].sum { |_, p| p.scan(re).size }
    age = new_n > old_n ? 'yeni' : 'eski'
    h[:plus].each do |ln, txt|
      txt.to_enum(:scan, re).each do
        pos = Regexp.last_match.begin(0)
        before, ctx = css_ctx(txt, pos)
        fb = css_fallback?(name, before) ? 'YEDEKLİ' : 'YEDEKSİZ'
        css["#{fb} #{age}"] += 1
        hits += 1 if fb == 'YEDEKSİZ' && age == 'yeni'
        puts "CSS #{h[:file]}:#{ln} #{name} #{fb} #{age} | #{ctx.strip[0, 200]}"
      end
    end
  end
  old_g = h[:minus].sum { |m| m.scan(GAP).size }
  new_g = h[:plus].sum { |_, p| p.scan(GAP).size }
  age = new_g > old_g ? 'yeni' : 'eski'
  h[:plus].each do |ln, txt|
    txt.to_enum(:scan, GAP).each do
      _, ctx = css_ctx(txt, Regexp.last_match.begin(0))
      kind = ctx =~ /display\s*:\s*(inline-)?flex/ ? 'flex' : (ctx =~ /display\s*:\s*(inline-)?grid/ ? 'grid' : 'belirsiz')
      gap["#{kind} #{age}"] += 1
      puts "INFO gap #{h[:file]}:#{ln} #{kind} | #{ctx.strip[0, 160]}" if age == 'yeni'
    end
  end
end

tree_gap = lambda do |rev|
  o, = Open3.capture2('git', 'grep', '-o', '-P', '(?<![-\w])gap\s*:', rev, '--', 'src')
  o.lines.size
end
work_gap = Dir[File.join('src', '**', '*.{html,css,rb,js}')].sum { |f| File.read(f, encoding: 'UTF-8').scan(GAP).size }
fmt = ->(h) { h.empty? ? '-' : h.sort.map { |k, v| "#{k}=#{v}" }.join(' ') }
puts "CSS eşleşme (inset:/min(/max(/clamp() eklenen satırlarda: #{fmt.(css)}"
puts "INFO flex gap (yalnız bilgi, hits dışı) eklenen satırlarda: #{fmt.(gap)}; toplam gap: taban #{base}=#{tree_gap.(base)} çalışma ağacı=#{work_gap}"
puts "base=#{base} added_lines=#{added} hits=#{hits}"
exit(hits.zero? ? 0 : 1)
