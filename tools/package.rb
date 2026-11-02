# MST RBZ paketleme betigi (tekrarlanabilir). Yalniz src/ icerigi pakete girer: kok `marine_structures_tools.rb` +
# `marine_structures_tools/`. tools/, docs/, .git, CLAUDE.md vb. girmez. Var olan paketin/manifestin USTUNE YAZMAZ.
# Zip: deflate, giris sirasi ada gore, tum girislerin zamani HEAD commit zamani (ayni commit → ayni bayt dizisi).
#
# Kullanim (depo kokunden):
#   ruby tools/package.rb <cikti.rbz> [--ref <karsilastirma.rbz>] [--src <src klasoru>]
#   ruby tools/package.rb --list <paket.rbz>            # paket dosya listesi + SHA-256 (yalniz okur)
# Uretim adimlari: (1) src listesi + SHA-256, (2) --ref paketinin listesiyle eklenen/cikan dosyalar, (3) zip yazimi,
# (4) paketi bellekte acip src ile N/N SHA-256 karsilastirmasi, (5) manifest <cikti>.manifest.txt
# (surum adi, kaynak commit, uretim tarihi, dosya basina SHA-256, paket SHA-256, dogrulama sonucu).
# Dogrulama basarisizsa paket ve manifest silinmez ama cikis kodu 1 olur ve manifestte BASARISIZ yazar.
require 'zlib'
require 'digest'
require 'fileutils'
require 'time'

module MstZip
  module_function

  def dos_time(t)
    t = Time.at(t).localtime
    [((t.hour << 11) | (t.min << 5) | (t.sec / 2)), (((t.year - 1980) << 9) | (t.month << 5) | t.day)]
  end

  # entries: [[ad, bayt]] → zip baytlari
  def build(entries, mtime)
    tm, dt = dos_time(mtime)
    out = String.new(encoding: 'BINARY')
    cd = String.new(encoding: 'BINARY')
    entries.each do |name, data|
      nm = name.dup.force_encoding('BINARY')
      data = data.dup.force_encoding('BINARY')
      crc = Zlib.crc32(data)
      z = Zlib::Deflate.new(Zlib::BEST_COMPRESSION, -Zlib::MAX_WBITS)
      comp = z.deflate(data, Zlib::FINISH); z.close
      method = 8
      if comp.bytesize >= data.bytesize then comp = data; method = 0 end
      flags = nm.unpack('C*').any? { |b| b > 127 } ? 0x0800 : 0   # UTF-8 ad bayragi
      off = out.bytesize
      out << [0x04034b50, 20, flags, method, tm, dt, crc, comp.bytesize, data.bytesize, nm.bytesize, 0].pack('VvvvvvVVVvv') << nm << comp
      cd << [0x02014b50, 20, 20, flags, method, tm, dt, crc, comp.bytesize, data.bytesize, nm.bytesize, 0, 0, 0, 0, 0, off].pack('VvvvvvvVVVvvvvvVV') << nm
    end
    cd_off = out.bytesize   # merkez dizin ofseti = yerel girislerin toplam boyu
    out << cd << [0x06054b50, 0, 0, entries.size, entries.size, cd.bytesize, cd_off, 0].pack('VvvvvVVv')
    out
  end

  # zip baytlari → [[ad, bayt]] (merkez dizinden; deflate ve store)
  def read(bytes)
    bytes = bytes.b
    eo = bytes.rindex([0x06054b50].pack('V')) or raise 'zip sonu (EOCD) yok'
    n, cd_size, cd_off = bytes[eo + 10, 10].unpack('vVV')
    pos = cd_off
    list = []
    n.times do
      sig, _vm, _vn, _fl, method, _t, _d, crc, csz, usz, nl, el, cl, _ds, _ia, _ea, lo = bytes[pos, 46].unpack('VvvvvvvVVVvvvvvVV')
      raise 'merkez dizin bozuk' unless sig == 0x02014b50
      name = bytes[pos + 46, nl].force_encoding('UTF-8')
      pos += 46 + nl + el + cl
      lnl, lel = bytes[lo + 26, 4].unpack('vv')
      raw = bytes[lo + 30 + lnl + lel, csz]
      data = case method
             when 0 then raw
             when 8 then Zlib::Inflate.new(-Zlib::MAX_WBITS).inflate(raw)
             else raise "desteklenmeyen sikistirma #{method}: #{name}"
             end
      raise "CRC uyusmuyor: #{name}" unless Zlib.crc32(data) == crc && data.bytesize == usz
      list << [name, data] unless name.end_with?('/')
    end
    list
  end
end

def sha(b); Digest::SHA256.hexdigest(b); end
# tools/package_runner.rb bu dosyayi `require` ile yalniz MstZip ve sha icin yukler; asagidaki paketleme yalniz dogrudan calistirmada.
return unless File.expand_path(__FILE__) == File.expand_path($PROGRAM_NAME)

if ARGV[0] == '--list'
  MstZip.read(File.binread(ARGV[1])).sort_by(&:first).each { |n, d| puts "#{sha(d)}  #{n}" }
  exit 0
end

out = ARGV[0] or abort 'kullanim: ruby tools/package.rb <cikti.rbz> [--ref <paket.rbz>] [--src <src>]'
opt = ->(k) { i = ARGV.index(k); i && ARGV[i + 1] }
root = File.expand_path('..', __dir__)
src = File.expand_path(opt.('--src') || File.join(root, 'src'))
ref = opt.('--ref')
man = out.sub(/\.rbz\z/i, '') + '.manifest.txt'
abort "VAR: #{out} — üzerine yazılmaz" if File.exist?(out)
abort "VAR: #{man} — üzerine yazılmaz" if File.exist?(man)
abort "src yok: #{src}" unless File.file?(File.join(src, 'marine_structures_tools.rb')) && File.directory?(File.join(src, 'marine_structures_tools'))

# 1) kaynak listesi (yalniz src; gizli dosya ve bos klasor yok)
files = Dir.glob('**/*', File::FNM_DOTMATCH, base: src).select { |f| File.file?(File.join(src, f)) }
files.reject! { |f| f.split('/').any? { |p| p.start_with?('.') } }
files.sort!
bad_root = files.reject { |f| f == 'marine_structures_tools.rb' || f.start_with?('marine_structures_tools/') }
abort "src kökünde beklenmeyen dosya: #{bad_root.join(', ')}" unless bad_root.empty?
entries = files.map { |f| [f, File.binread(File.join(src, f))] }
src_sha = entries.to_h { |n, d| [n, sha(d)] }

Dir.chdir(root)
commit = `git rev-parse HEAD`.strip
dirty = !`git status --porcelain -- src`.strip.empty?
mtime = `git log -1 --format=%ct`.strip.to_i
mtime = Time.now.to_i if mtime.zero?
main = File.read(File.join(src, 'marine_structures_tools', 'main.rb'), encoding: 'UTF-8')
qw = File.read(File.join(src, 'marine_structures_tools', 'qto_workspace.rb'), encoding: 'UTF-8')
build = main[/^MST_BUILD\s*=\s*'([^']*)'/, 1]
version = qw[/VERSION\s*=\s*'([^']*)'/, 1]

# 2) referans paketle liste farki
ref_lines = []
if ref
  rl = MstZip.read(File.binread(ref)).map(&:first).sort
  added = files - rl
  removed = rl - files
  ref_lines << "Referans paket: #{File.basename(ref)} (SHA-256 #{sha(File.binread(ref))}, #{rl.size} dosya)"
  ref_lines << "Eklenen (#{added.size}): #{added.empty? ? '-' : added.join(', ')}"
  ref_lines << "Çıkan (#{removed.size}): #{removed.empty? ? '-' : removed.join(', ')}"
  puts ref_lines
end

# 3) zip
bytes = MstZip.build(entries, mtime)
FileUtils.mkdir_p(File.dirname(File.expand_path(out)))
File.binwrite(out, bytes)
pkg_sha = sha(File.binread(out))

# 4) dogrulama: paketi ac, src ile karsilastir
got = MstZip.read(File.binread(out)).to_h { |n, d| [n, sha(d)] }
same = src_sha.count { |n, s| got[n] == s }
extra = got.keys - src_sha.keys
ok = same == src_sha.size && extra.empty? && got.size == src_sha.size
verdict = "Paket ↔ src: #{same}/#{src_sha.size} aynı, pakette fazla #{extra.size}, pakette dosya #{got.size} → #{ok ? 'AYNI' : 'BAŞARISIZ'}"

# 5) manifest
File.open(man, 'w:UTF-8') do |f|
  f.puts "MST paket manifesti"
  f.puts "Paket: #{File.basename(out)}"
  f.puts "Sürüm adı: MST_BUILD='#{build}', VERSION='#{version}'"
  f.puts "Kaynak commit: #{commit}#{dirty ? ' (src commit edilmemiş değişiklik içeriyor)' : ''}"
  f.puts "Üretim tarihi: #{Time.now.iso8601}"
  f.puts "Dosya sayısı: #{files.size}"
  f.puts "Paket boyutu: #{File.size(out)} bayt"
  f.puts "Paket SHA-256: #{pkg_sha}"
  f.puts verdict
  ref_lines.each { |l| f.puts l }
  f.puts
  f.puts 'SHA-256  dosya'
  files.each { |n| f.puts "#{src_sha[n]}  #{n}" }
end
puts "paket=#{out} boyut=#{File.size(out)} sha256=#{pkg_sha} dosya=#{files.size}"
puts verdict
puts "manifest=#{man}"
exit(ok ? 0 : 1)
