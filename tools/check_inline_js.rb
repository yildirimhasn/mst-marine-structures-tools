# HTML dosyalarindaki satir ici <script> bloklarini cikarir ve her birini `node --check` ile sinar.
# src= ve JS olmayan type'li bloklar atlanir. Kaynak dosyalar yalniz okunur; gecici dosyalar Dir.mktmpdir icinde.
# Kullanim: ruby tools/check_inline_js.rb <marine_structures_tools klasoru> [dosya.html ...]
# Cikti: her blok icin "OK|FAIL <dosya>:<satir> (<n> satir)" ve sonda "inline_blocks=N ok=K fail=F".
require 'tmpdir'
require 'open3'

dir = ARGV[0] or abort 'kullanim: ruby tools/check_inline_js.rb <klasor> [dosya.html ...]'
files = ARGV[1..-1].to_a
files = Dir[File.join(dir, '**', '*.html')].sort.map { |f| f.sub(dir.chomp('/') + '/', '') } if files.empty?
RE = /<script\b([^>]*)>(.*?)<\/script\s*>/mi
ok = 0
fail = 0
Dir.mktmpdir('mst_inline_js') do |tmp|
  files.each do |rel|
    s = File.binread(File.join(dir, rel)).force_encoding('UTF-8')
    s.to_enum(:scan, RE).each do
      m = Regexp.last_match
      next if m[1] =~ /\bsrc\s*=/i
      next if m[1] =~ /type\s*=\s*["']?(text\/template|application\/json|text\/html)/i
      body = m[2]
      next if body.strip.empty?
      line = s[0...m.begin(2)].count("\n") + 1
      f = File.join(tmp, "b#{ok + fail}.js")
      File.binwrite(f, body)
      out, st = Open3.capture2e('node', '--check', f)
      if st.success?
        ok += 1
        puts "OK   #{rel}:#{line} (#{body.count("\n") + 1} satir)"
      else
        fail += 1
        first = out.lines.find { |l| l =~ /Error/ }.to_s.strip
        puts "FAIL #{rel}:#{line} (#{body.count("\n") + 1} satir) #{first}"
      end
    end
  end
end
puts "inline_blocks=#{ok + fail} ok=#{ok} fail=#{fail}"
exit(fail.zero? ? 0 : 1)
