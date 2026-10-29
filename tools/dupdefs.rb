require 'parser/ruby25'
defs=Hash.new{|h,k|h[k]=[]}
order=ARGV
order.each do |f|
  src=File.binread(f).force_encoding('UTF-8')
  ast=Parser::Ruby25.new.tap{|p|p.diagnostics.ignore_warnings=true}.parse(Parser::Source::Buffer.new(f,source:src))
  walk=lambda do |n,ctx|
    return unless n.is_a?(Parser::AST::Node)
    case n.type
    when :module,:class
      name=n.children[0].loc.expression.source
      n.children[1..-1].each{|c|walk.(c,ctx+[name])}; return
    when :sclass
      n.children.each{|c|walk.(c,ctx+['<<self'])}; return
    when :def
      defs["#{ctx.join('::')}##{n.children[0]}"]<<"#{File.basename(f)}:#{n.loc.line}"
    when :defs
      defs["#{ctx.join('::')}.#{n.children[1]}"]<<"#{File.basename(f)}:#{n.loc.line}"
    end
    n.children.each{|c|walk.(c,ctx)}
  end
  walk.(ast,[])
end
d=defs.select{|_,v|v.size>1}
puts "total_defs=#{defs.size} redefined=#{d.size} cross_file=#{d.count{|_,v|v.map{|x|x.split(':')[0]}.uniq.size>1}}"
d.sort_by{|k,v|-v.size}.each{|k,v|puts "#{k}  <= #{v.join(', ')}"}
