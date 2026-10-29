require 'parser/ruby25'
bad=0
ARGV.each do |f|
  src=File.binread(f).force_encoding('UTF-8')
  buf=Parser::Source::Buffer.new(f, source: src)
  p=Parser::Ruby25.new; p.diagnostics.all_errors_are_fatal=true; p.diagnostics.ignore_warnings=true
  begin; p.parse(buf); rescue Parser::SyntaxError => e; bad+=1; puts "R25 FAIL #{f}: #{e.diagnostic.render.first(2).join(' | ')}"; end
end
puts "files=#{ARGV.size} ruby25_failures=#{bad}"
