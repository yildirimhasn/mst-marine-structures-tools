# MST TB1 entegrasyon test eklentisi (runner) paketleme betigi. Runner kaynagi depo kokundeki runner/ klasorudur (src DISI;
# tools/package.rb'ye girmez). Var olan paketin/manifestin USTUNE YAZMAZ. Zip yazimi tools/package.rb MstZip ile ayni
# (deflate, ada gore sira); tum girislerin zamani = hedef MST kaynak commit'inin zamani (ayni girdi → ayni bayt dizisi).
#
# Kullanim (depo kokunden):
#   ruby tools/package_runner.rb --expected [--src src] [--runner runner]
#       runner/mst_tb1_integration_runner/expected_sources.json dosyasini src'den yeniden uretir (dosya listesi + SHA-256;
#       bicim 1.1.0 ile ayni: schema/version/build/files, alt klasor dosyalari buyuk-kucuk harf duyarsiz sirada, kok dosya en sonda).
#       src'de commit edilmemis degisiklik varsa durur.
#   ruby tools/package_runner.rb <cikti.rbz> [--src src] [--runner runner] [--commit <mst kaynak commit>]
#       Uretimden once denetler: expected_sources.json ↔ src (dosya kumesi ve SHA-256 birebir), runner EXPECTED_VERSION /
#       EXPECTED_BUILD ↔ src VERSION / MST_BUILD ↔ expected_sources version/build, runner VERSION ↔ yukleyici extension.version.
#       Sonra zip, paketi bellekte acip runner dosyalariyla N/N SHA-256 karsilastirmasi, manifest <cikti>.manifest.txt.
require 'json'
require 'time'
require 'fileutils'
require_relative 'package'   # MstZip, sha (package.rb dogrudan calistirilmadiginda paketleme yapmaz)

opt = ->(k) { i = ARGV.index(k); i && ARGV[i + 1] }
root = File.expand_path('..', __dir__)
src = File.expand_path(opt.('--src') || File.join(root, 'src'))
runner = File.expand_path(opt.('--runner') || File.join(root, 'runner'))
exp_path = File.join(runner, 'mst_tb1_integration_runner', 'expected_sources.json')
main_rb = File.join(runner, 'mst_tb1_integration_runner', 'main.rb')
loader_rb = File.join(runner, 'mst_tb1_integration_runner.rb')
abort "src yok: #{src}" unless File.file?(File.join(src, 'marine_structures_tools.rb'))
abort "runner yok: #{runner}" unless File.file?(main_rb) && File.file?(loader_rb)
Dir.chdir(root)

src_files = lambda do
  fs = Dir.glob('**/*', File::FNM_DOTMATCH, base: src).select { |f| File.file?(File.join(src, f)) }
  fs.reject { |f| f.split('/').any? { |p| p.start_with?('.') } }
end
src_ver = lambda do
  m = File.read(File.join(src, 'marine_structures_tools', 'main.rb'), encoding: 'UTF-8')[/^MST_BUILD\s*=\s*'([^']*)'/, 1]
  v = File.read(File.join(src, 'marine_structures_tools', 'qto_workspace.rb'), encoding: 'UTF-8')[/VERSION\s*=\s*'([^']*)'/, 1]
  [v, m]
end

if ARGV[0] == '--expected'
  abort 'src commit edilmemiş değişiklik içeriyor; expected_sources.json üretilmedi' unless `git status --porcelain -- "#{src}"`.strip.empty?
  fs = src_files.()
  sub = fs.select { |f| f.start_with?('marine_structures_tools/') }.sort_by { |f| [f.upcase, f] }
  rest = fs - sub
  abort "src kökünde beklenmeyen dosya: #{rest.join(', ')}" unless rest == ['marine_structures_tools.rb']
  v, b = src_ver.()
  files = (sub + rest).to_h { |f| [f, sha(File.binread(File.join(src, f)))] }
  data = { 'schema' => 'mst.tb1.expected-sources/1', 'version' => v, 'build' => b, 'files' => files }
  File.binwrite(exp_path, JSON.pretty_generate(data))
  puts "expected_sources.json yazıldı: dosya=#{files.size} version=#{v} build=#{b} kaynak_commit=#{`git rev-parse HEAD`.strip} sha256=#{sha(File.binread(exp_path))}"
  exit 0
end

out = ARGV[0] or abort 'kullanim: ruby tools/package_runner.rb <cikti.rbz> | --expected'
man = out.sub(/\.rbz\z/i, '') + '.manifest.txt'
abort "VAR: #{out} — üzerine yazılmaz" if File.exist?(out)
abort "VAR: #{man} — üzerine yazılmaz" if File.exist?(man)

# denetimler
issues = []
exp = JSON.parse(File.read(exp_path, encoding: 'UTF-8'))
fs = src_files.()
src_sha = fs.to_h { |f| [f, sha(File.binread(File.join(src, f)))] }
same = src_sha.count { |f, s| exp['files'][f] == s }
issues << "expected_sources ↔ src: #{same}/#{src_sha.size} aynı, beklenen dosya #{exp['files'].size}" unless same == src_sha.size && exp['files'].size == src_sha.size
v, b = src_ver.()
mr = File.read(main_rb, encoding: 'UTF-8')
rv = mr[/^\s*VERSION='([^']*)'/, 1]
ev = mr[/EXPECTED_VERSION='([^']*)'/, 1]
eb = mr[/EXPECTED_BUILD='([^']*)'/, 1]
lv = File.read(loader_rb, encoding: 'UTF-8')[/extension\.version='([^']*)'/, 1]
issues << "sürüm: runner EXPECTED_VERSION=#{ev} src VERSION=#{v} expected_sources=#{exp['version']}" unless ev == v && exp['version'] == v
issues << "yapı: runner EXPECTED_BUILD=#{eb} src MST_BUILD=#{b} expected_sources=#{exp['build']}" unless eb == b && exp['build'] == b
issues << "runner sürümü: main.rb VERSION=#{rv} yükleyici=#{lv}" unless rv == lv
abort "DENETİM BAŞARISIZ, paket üretilmedi:\n#{issues.join("\n")}" unless issues.empty?
puts "denetim: expected_sources ↔ src #{same}/#{src_sha.size} aynı; runner #{rv}; beklenen MST #{eb} / #{ev}"

# zip
commit = opt.('--commit') || `git rev-parse HEAD`.strip
mtime = `git log -1 --format=%ct #{commit}`.strip.to_i
abort "commit zamanı okunamadı: #{commit}" if mtime.zero?
rfiles = Dir.glob('**/*', base: runner).select { |f| File.file?(File.join(runner, f)) }.sort
entries = rfiles.map { |f| [f, File.binread(File.join(runner, f))] }
r_sha = entries.to_h { |n, d| [n, sha(d)] }
FileUtils.mkdir_p(File.dirname(File.expand_path(out)))
File.binwrite(out, MstZip.build(entries, mtime))
pkg_sha = sha(File.binread(out))
got = MstZip.read(File.binread(out)).to_h { |n, d| [n, sha(d)] }
ok = got == r_sha
verdict = "Paket ↔ runner/: #{r_sha.count { |n, s| got[n] == s }}/#{r_sha.size} aynı, pakette dosya #{got.size} → #{ok ? 'AYNI' : 'BAŞARISIZ'}"
dirty = !`git status --porcelain -- runner`.strip.empty?
File.open(man, 'w:UTF-8') do |f|
  f.puts 'MST TB1 entegrasyon test eklentisi (runner) paket manifesti'
  f.puts "Paket: #{File.basename(out)}"
  f.puts "Runner sürümü: #{rv}; beklenen MST: MST_BUILD='#{eb}', VERSION='#{ev}'"
  f.puts "Hedef MST kaynak commit: #{`git rev-parse #{commit}`.strip} (expected_sources.json bu src'den; #{exp['files'].size} dosya, src ile #{same}/#{src_sha.size} aynı)"
  f.puts "Runner kaynağı: runner/ (depo HEAD #{`git rev-parse HEAD`.strip}#{dirty ? ', runner/ commit edilmemiş değişiklik içeriyor' : ''}); temel: MST_TB1_Integration_TestRunner_v1.1.0.rbz"
  f.puts "Zip giriş zamanı: #{Time.at(mtime).localtime.iso8601} (hedef MST kaynak commit zamanı)"
  f.puts "Üretim tarihi: #{Time.now.iso8601}"
  f.puts "Dosya sayısı: #{rfiles.size}"
  f.puts "Paket boyutu: #{File.size(out)} bayt"
  f.puts "Paket SHA-256: #{pkg_sha}"
  f.puts verdict
  f.puts
  f.puts 'SHA-256  dosya'
  rfiles.each { |n| f.puts "#{r_sha[n]}  #{n}" }
end
puts "paket=#{out} boyut=#{File.size(out)} sha256=#{pkg_sha} dosya=#{rfiles.size}"
puts verdict
puts "manifest=#{man}"
exit(ok ? 0 : 1)
