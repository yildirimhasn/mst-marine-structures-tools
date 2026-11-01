# Parti C statik kontrol — JS → Ruby callback kayitlari ve Ruby → JS execute_script islevleri (SketchUp disinda, kaynak yalniz okunur).
# 1) Ana pencere (ui.html + ui.html'in yukledigi .js): her `sketchup.<ad>(`, boq_pro.js `call('<ad>'`, mst_workflow.js `emb:/open:'<ad>'`
#    icin src/*.rb'de kayit: add_action_callback('<ad>'|"<ad>") veya boq_pro.rb wrap.('<ad>').
# 2) Gomulu sayfalar (diger .html + yukledikleri .js; Ruby icindeki HTML dizgileri): ayni kontrol, ayri liste
#    (embed.rb koprusu: MSTEmbedDialog#add_action_callback ayni literal adla kaydeder).
# 3) Ruby execute_script("<islev>(" / mst_host_exec("<islev>(" ile cagrilan her JS isleminin src icinde tanimli olmasi
#    (function ad( / ad=function / window|global|self|root.ad= / ad:function / var|let|const ad=). Kapsam sinirlamasi: tanimin hedef sayfada
#    oldugu degil, src icinde var oldugu sinanir. `window.ad&&ad(` korumali cagrilar ayri listelenir (tanimsizsa sessiz, hata degil).
# Kullanim: ruby tools/test/c_callbacks.rb <src/marine_structures_tools>
require_relative 'a1_helper'
dir = A1.dir
rd = ->(f) { File.binread(File.join(dir, f)).force_encoding('UTF-8') }
rbs = Dir[File.join(dir, '**', '*.rb')].sort
rb_text = rbs.map { |f| File.binread(f).force_encoding('UTF-8') }.join("\n")
registered = rb_text.scan(/add_action_callback\(\s*['"]([A-Za-z_0-9]+)['"]/).flatten +
             rb_text.scan(/wrap\.\(\s*['"]([A-Za-z_0-9]+)['"]/).flatten
registered = registered.uniq
obs('Ruby callback kaydi (literal ad)', registered.size)

def js_calls(text)
  text.scan(/\bsketchup\.([A-Za-z_][A-Za-z_0-9]*)\s*\(/).flatten
end

check = lambda do |label, names, reg|
  missing = names.uniq.sort - reg
  t("#{label}: #{names.uniq.size} ad, kaydi olmayan", missing, [])
end

# ---- 1) ana pencere
ui = rd.('ui.html')
ui_js = ui.scan(/<script\s+src="([^"]+)"/).flatten
main_names = js_calls(ui)
check.('ui.html sketchup.<ad>(', js_calls(ui), registered)
ui_js.each do |js|
  next unless File.exist?(File.join(dir, js))
  s = rd.(js)
  n = js_calls(s)
  n += s.scan(/\bcall\('([A-Za-z_0-9]+)'/).flatten if js == 'boq_pro.js'
  n += s.scan(/\b(?:emb|open):'([A-Za-z_0-9]+)'/).flatten if js == 'mst_workflow.js'
  next if n.empty?
  main_names += n
  check.("ui.html → #{js}", n, registered)
end
obs('ana pencere toplam farkli ad', main_names.uniq.size)

# ---- 2) gomulu sayfalar
Dir[File.join(dir, '*.html')].sort.map { |f| File.basename(f) }.reject { |f| f == 'ui.html' }.each do |h|
  s = rd.(h)
  n = js_calls(s)
  s.scan(/<script\s+src="([^"]+)"/).flatten.each do |js|
    n += js_calls(rd.(js)) if File.exist?(File.join(dir, js)) && !ui_js.include?(js)
  end
  next if n.empty?
  check.("gömülü #{h}", n, registered)
end
rbs.each do |f|
  s = File.binread(f).force_encoding('UTF-8')
  n = js_calls(s)
  next if n.empty?
  check.("gömülü (Ruby HTML dizgisi) #{File.basename(f)}", n, registered)
end

# ---- 3) execute_script → JS islevi
js_all = Dir[File.join(dir, '**', '*.{js,html}')].sort.map { |f| File.binread(f).force_encoding('UTF-8') }.join("\n") + "\n" + rb_text
defined_js = lambda do |nm|
  q = Regexp.escape(nm)
  js_all =~ /function\s+#{q}\s*\(/ || js_all =~ /(?<![\w.$])#{q}\s*=\s*(?:async\s+)?function\b/ ||
    js_all =~ /\b(?:window|global|self|root)\.#{q}\s*=/ || js_all =~ /(?<![\w.$])#{q}\s*:\s*function\b/ ||
    js_all =~ /\b(?:var|let|const)\s+#{q}\s*=/ || js_all =~ /(?<![\w.$])#{q}\s*=\s*\([^)]*\)\s*=>/
end
JS_KW = %w[if for while switch return typeof try].freeze
# 872d3a3 (0.51.4 TB1) kaynaginda da tanimsiz olan islevler: tabandan devralinan bulgu, bu partinin hatasi sayilmaz;
# listeden cikarlarsa (tanim eklendiyse) test bunu da gosterir.
BASE_UNDEFINED = %w[drillingEditError loadSelectedBimPile setDrillingEditor].freeze
direct = rb_text.scan(/(?:execute_script|mst_host_exec)\(\s*(?:"|'|%Q?[{(])\s*(?:window\.)?([A-Za-z_$][A-Za-z0-9_$]*)\(/).flatten.uniq.sort - JS_KW
guarded = (rb_text.scan(/(?:execute_script|mst_host_exec)\(\s*["']\s*(?:if\s*\()?window\.([A-Za-z_$][A-Za-z0-9_$]*)\s*(?:&&|\))/).flatten +
           rb_text.scan(/(?:execute_script|mst_host_exec)\(\s*["'][^"'\n]*?\bif\s*\(\s*window\.([A-Za-z_$][A-Za-z0-9_$]*)\s*\)/).flatten +
           # Parti F / F2: `if(typeof ad==='function'){ad(...)}else{...}` korumasi — islev yoksa cagrilmaz (ReferenceError yok)
           rb_text.scan(/(?:execute_script|mst_host_exec)\(\s*["']\s*if\s*\(\s*typeof\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*===?\s*['"]function['"]\s*\)/).flatten).uniq.sort
undef_direct = direct.reject { |n| defined_js.(n) }
obs('execute_script doğrudan çağrılan farklı işlev', direct.size)
obs('tanımsız ve 872d3a3 tabanında da tanımsız (devralınan)', undef_direct & BASE_UNDEFINED)
t('execute_script doğrudan çağrılan, src içinde tanımsız YENİ JS işlevi', undef_direct - BASE_UNDEFINED, [])
t('F2: tabandan devralınan tanımsız işlevler artık korumasız çağrılmıyor (f7046b5: 3 işlev)', undef_direct & BASE_UNDEFINED, [])
t('F2: üç işlev typeof korumalı çağrılıyor', BASE_UNDEFINED - guarded, [])
obs('execute_script window.<ad> / typeof korumalı çağrı', guarded)
obs('korumalı çağrılardan tanımsız olan (sessiz atlanır; hata sayılmaz)', guarded.reject { |n| defined_js.(n) })
a1_finish
