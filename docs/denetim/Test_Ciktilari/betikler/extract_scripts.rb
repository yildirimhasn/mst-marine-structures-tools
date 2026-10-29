# Paket kopyasindaki <script> bloklarini cikarir (html + Ruby string/heredoc).
# Kullanim: ruby extract_scripts.rb <paket_kok> <cikti_klasoru>
require 'parser/ruby25'
require 'fileutils'
root, outdir = ARGV
FileUtils.mkdir_p(outdir)
idx = []
SCRIPT_RE = /<script\b([^>]*)>(.*?)<\/script\s*>/mi

def emit(outdir, idx, origin, attrs, body)
  return if attrs =~ /\bsrc\s*=/i
  return if attrs =~ /type\s*=\s*["']?(text\/template|application\/json|text\/html)/i
  return if body.strip.empty?
  name = format('s%04d.js', idx.size + 1)
  File.write(File.join(outdir, name), body)
  idx << "#{name}\t#{origin}"
end

Dir.chdir(root) do
  Dir['**/*.html'].sort.each do |f|
    s = File.read(f, encoding: 'utf-8')
    s.to_enum(:scan, SCRIPT_RE).each do
      m = Regexp.last_match
      line = s[0...m.begin(0)].count("\n") + 1
      emit(outdir, idx, "#{f}:#{line}", m[1], m[2])
    end
  end
  partial = []
  Dir['**/*.rb'].sort.each do |f|
    src = File.binread(f).force_encoding('UTF-8')
    buf = Parser::Source::Buffer.new(f, source: src)
    pr = Parser::Ruby25.new; pr.diagnostics.ignore_warnings = true
    ast = pr.parse(buf)
    walk = lambda do |n|
      next unless n.is_a?(Parser::AST::Node)
      if n.type == :dstr || n.type == :str
        text = if n.type == :str
                 n.children[0].to_s
               else
                 n.children.map { |c| c.type == :str ? c.children[0].to_s : '__RB__' }.join
               end
        if text =~ /<script/i
          found = false
          text.to_enum(:scan, SCRIPT_RE).each do
            m = Regexp.last_match; found = true
            emit(outdir, idx, "#{f}:#{n.loc.line}", m[1], m[2])
          end
          partial << "#{f}:#{n.loc.line}" unless found
        end
        next if n.type == :str
        n.children.each { |c| walk.call(c) unless c.type == :str }
      else
        n.children.each { |c| walk.call(c) }
      end
    end
    walk.call(ast)
  end
  File.write(File.join(outdir, '_partial.txt'), partial.join("\n"))
end
File.write(File.join(outdir, '_index.tsv'), idx.join("\n"))
puts "extracted=#{idx.size}"
