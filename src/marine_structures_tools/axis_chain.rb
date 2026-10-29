# frozen_string_literal: true
module MAG
 module MarineStructuresTools
  module AxisChain
   extend self
   def order(segments)
    edges=segments.map do |pair|
     raise 'Aks kenarı geçersiz.' unless pair.is_a?(Array)&&pair.size==2
     pair.map do |point|
      raise 'Aks noktası geçersiz.' unless point.is_a?(Array)&&point.size==3
      point.map{|v|n=Float(v);raise 'Aks koordinatları sonlu olmalı.' unless n.finite?;n}
     end
    end.uniq{|a,b|[a,b].sort}
    raise 'Aks seçiminde kenar yok.' if edges.empty?
    positions={};links=Hash.new{|h,k|h[k]=[]}
    edges.each_with_index do |pair,i|
     keys=pair.map{|p|p.map{|v|v.round(6)}}
     raise 'Aksın sıfır boylu kenarı var.' if keys[0]==keys[1]
     pair.zip(keys).each{|p,k|positions[k]||=p;links[k]<<i}
    end
    ends=links.keys.select{|k|links[k].size==1}
    raise 'Aks açık, tek parça ve dalsız olmalı.' unless ends.size==2 && links.values.all?{|v|v.size<=2}
    here=ends.min;points=[positions[here]];visited={}
    loop do
     index=links[here].find{|i|!visited[i]};break unless index
     visited[index]=true
     here=edges[index].map{|p|p.map{|v|v.round(6)}}.find{|k|k!=here}
     points<<positions[here]
    end
    raise 'Aks seçiminde bağlantısız kenarlar var.' unless visited.size==edges.size
    points
   end
  end
 end
end
