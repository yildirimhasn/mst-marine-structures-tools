# Golden-master turu (yeniden calistirilabilir): taban commit kaynagini gecici klasore `git archive` ile acar,
# iki kaynak icin golden_qto.rb, sonra compare.rb calistirir. Ciktilar: docs/duzeltme/golden/
#   golden_<taban>[_<etiket>].csv, golden_HEAD-<kisa>[_<etiket>].csv (calisma agaci src/), fark_<taban>_<kisa>[_<etiket>].csv
# Kullanim (depo kokunden): ruby tools/golden/run_golden.rb [taban=872d3a3] [kural seti: 0514 | Gb | H] [--etiket <ad>]
# Calisma agacindaki src/ kullanilir (commit edilmemis degisiklikler dahil); kisa ad HEAD commit'i + "-dirty" (src kirliyse).
# Koruma: hedef ciktilardan biri git'te IZLENEN bir dosyaysa uzerine yazilmaz, betik durur (--etiket ile ayri ad verin).
require 'tmpdir'
require 'fileutils'
require 'open3'
args = ARGV.dup
etiket = nil
if (i = args.index('--etiket'))
  etiket = args[i + 1].to_s
  abort 'kullanim: --etiket <ad> (harf, rakam, _ . -)' unless etiket =~ /\A[\w.\-]+\z/
  args.slice!(i, 2)
end
base = args[0] || '872d3a3'
root = File.expand_path('../..', __dir__)
outdir = File.join(root, 'docs', 'duzeltme', 'golden')
FileUtils.mkdir_p(outdir)
Dir.chdir(root)
head = `git rev-parse --short HEAD`.strip
dirty = !`git status --porcelain -- src`.strip.empty?
tag = "HEAD-#{head}#{dirty ? '-dirty' : ''}"
sfx = etiket ? "_#{etiket}" : ''
old_csv = File.join(outdir, "golden_#{base}#{sfx}.csv")
new_csv = File.join(outdir, "golden_#{tag}#{sfx}.csv")
diff_csv = File.join(outdir, "fark_#{base}_#{tag}#{sfx}.csv")
tracked = [old_csv, new_csv, diff_csv].select do |f|
  File.exist?(f) && system('git', 'ls-files', '--error-unmatch', f, out: File::NULL, err: File::NULL)
end
abort "İZLENEN dosya, üzerine yazılmaz: #{tracked.map { |f| File.basename(f) }.join(', ')} — --etiket <ad> ile ayrı ad verin" unless tracked.empty?
Dir.mktmpdir('mst_golden') do |tmp|
  tar = File.join(tmp, 'base.tar')
  system('git', 'archive', '-o', tar, base, 'src') or abort "git archive #{base} başarısız"
  Dir.chdir(tmp) { system('tar', '-xf', 'base.tar') } or abort 'tar açma başarısız'   # göreli yol: GNU tar 'C:' önekini uzak makine sanar
  [[File.join(tmp, 'src', 'marine_structures_tools'), old_csv], [File.join(root, 'src', 'marine_structures_tools'), new_csv]].each do |src, csv|
    out, st = Open3.capture2e('ruby', File.join(__dir__, 'golden_qto.rb'), src, csv)
    puts out
    abort "golden_qto başarısız: #{src}" unless st.success?
  end
end
# esleme kural seti: 872d3a3 (0.51.4) tabaninda 0514, diger tabanlarda Parti G-b (Gb); ikinci arguman ile secilebilir
# Parti H: taban 50e5936 / 8d7d431 (Parti H öncesi) → H kural seti (yalnız H4b farkı beklenir)
profile = args[1] || (base.start_with?('872d3a3') ? '0514' : (%w[50e5936 8d7d431].any? { |b| base.start_with?(b) } ? 'H' : 'Gb'))
out, st = Open3.capture2e('ruby', File.join(__dir__, 'compare.rb'), old_csv, new_csv, diff_csv, profile)
puts out
puts "eski=#{old_csv}\nyeni=#{new_csv}\nfark=#{diff_csv}"
exit(st.success? ? 0 : 1)
