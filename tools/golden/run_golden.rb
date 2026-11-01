# Golden-master turu (yeniden calistirilabilir): taban commit kaynagini gecici klasore `git archive` ile acar,
# iki kaynak icin golden_qto.rb, sonra compare.rb calistirir. Ciktilar: docs/duzeltme/golden/
#   golden_<taban>.csv, golden_HEAD-<kisa>.csv (calisma agaci src/), fark_<taban>_<kisa>.csv
# Kullanim (depo kokunden): ruby tools/golden/run_golden.rb [taban=872d3a3]
# Calisma agacindaki src/ kullanilir (commit edilmemis degisiklikler dahil); kisa ad HEAD commit'i + "-dirty" (src kirliyse).
require 'tmpdir'
require 'fileutils'
require 'open3'
base = ARGV[0] || '872d3a3'
root = File.expand_path('../..', __dir__)
outdir = File.join(root, 'docs', 'duzeltme', 'golden')
FileUtils.mkdir_p(outdir)
Dir.chdir(root)
head = `git rev-parse --short HEAD`.strip
dirty = !`git status --porcelain -- src`.strip.empty?
tag = "HEAD-#{head}#{dirty ? '-dirty' : ''}"
old_csv = File.join(outdir, "golden_#{base}.csv")
new_csv = File.join(outdir, "golden_#{tag}.csv")
diff_csv = File.join(outdir, "fark_#{base}_#{tag}.csv")
rc = 0
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
out, st = Open3.capture2e('ruby', File.join(__dir__, 'compare.rb'), old_csv, new_csv, diff_csv)
puts out
puts "eski=#{old_csv}\nyeni=#{new_csv}\nfark=#{diff_csv}"
exit(st.success? ? 0 : 1)
