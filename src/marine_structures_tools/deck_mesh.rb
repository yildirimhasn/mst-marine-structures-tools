# frozen_string_literal: true
# DS3: one watertight union boundary, including form/contact subdivisions.
module MAG
module MarineStructuresTools
def mst_deck_boundary_mesh(pl,ux,uy)
 boxes=pl.fetch('boxes').map{|b|b.map{|v|Float(v).round(5)}}
 raise 'Döşeme planında pozitif hacimli kutu yok.' if boxes.empty?
 raise 'Döşeme kutusu geçersiz.' unless boxes.all?{|b|b.size==6&&b.all?(&:finite?)&&b[1]>b[0]&&b[3]>b[2]&&b[5]>b[4]}
 xs=boxes.flat_map{|b|b[0..1]};ys=boxes.flat_map{|b|b[2..3]};zs=boxes.flat_map{|b|b[4..5]}
 zs+=pl.fetch('split_z',[]).map{|v|Float(v).round(5)}
 raise 'Döşeme yükseklik bölme kotu sonlu olmalı.' unless zs.all?(&:finite?)
 pl.fetch('faces').each do |f|
  if f['u'];xs+=f['u'];ys+=f['v']
  elsif f['ax']==0;xs<<f['pl'];ys+=f['t']
  else;ys<<f['pl'];xs+=f['t'];end
 end
 xs=xs.map{|n|n.round(5)}.uniq.sort;ys=ys.map{|n|n.round(5)}.uniq.sort;zs=zs.uniq.sort
 xi=xs.each_with_index.to_h;yi=ys.each_with_index.to_h;zi=zs.each_with_index.to_h
 occupied={}
 boxes.each do |b|
  (xi.fetch(b[0])...xi.fetch(b[1])).each do |i|
   (yi.fetch(b[2])...yi.fetch(b[3])).each do |j|
    (zi.fetch(b[4])...zi.fetch(b[5])).each do |k|
     occupied[[i,j,k]]=true
     raise 'Döşeme ağı iki milyon hücre sınırını aşıyor; yapıyı döküm bölgelerine ayırın.' if occupied.size>2_000_000
    end
   end
  end
 end
 mesh=Geom::PolygonMesh.new;points={};vx=-uy;vy=ux
 point=lambda{|i,j,k|points[[i,j,k]]||=mesh.add_point(Geom::Point3d.new((xs[i]*ux+ys[j]*vx).m,(xs[i]*uy+ys[j]*vy).m,zs[k].m))}
 occupied.each_key do |i,j,k|
  [ [[-1,0,0],[[i,j,k],[i,j,k+1],[i,j+1,k+1],[i,j+1,k]]],
    [[1,0,0],[[i+1,j,k],[i+1,j+1,k],[i+1,j+1,k+1],[i+1,j,k+1]]],
    [[0,-1,0],[[i,j,k],[i+1,j,k],[i+1,j,k+1],[i,j,k+1]]],
    [[0,1,0],[[i,j+1,k],[i,j+1,k+1],[i+1,j+1,k+1],[i+1,j+1,k]]],
    [[0,0,-1],[[i,j,k],[i,j+1,k],[i+1,j+1,k],[i+1,j,k]]],
    [[0,0,1],[[i,j,k+1],[i+1,j,k+1],[i+1,j+1,k+1],[i,j+1,k+1]]] ].each do |delta,quad|
   next if occupied[[i+delta[0],j+delta[1],k+delta[2]]]
   mesh.add_polygon(quad.map{|q|point.call(*q)})
  end
 end
 [mesh,occupied.size]
end

def mst_deck_draw!(ents,pl,ux,uy,form_mat)
 mesh,cells=mst_deck_boundary_mesh(pl,ux,uy)
 ents.fill_from_mesh(mesh,true,0)
 vx=-uy;vy=ux
 faces=ents.grep(Sketchup::Face)
 faces.each do |f|
  c=f.bounds.center;u=c.x.to_m*ux+c.y.to_m*uy;v=c.x.to_m*vx+c.y.to_m*vy;z=c.z.to_m;n=f.normal
  matches=pl['faces'].select do |pf|
   if pf['u']
    n.z.abs>0.999&&(pf['z']-z).abs<1e-5&&u>pf['u'][0]-1e-5&&u<pf['u'][1]+1e-5&&v>pf['v'][0]-1e-5&&v<pf['v'][1]+1e-5
   else
    ax=pf['ax'];plane=ax==0 ? u:v;along=ax==0 ? v:u
    direction=ax==0 ? n.x*ux+n.y*uy : n.x*vx+n.y*vy
    direction.abs>0.999&&(pf['pl']-plane).abs<1e-5&&along>pf['t'][0]-1e-5&&along<pf['t'][1]+1e-5&&z>pf['z'][0]-1e-5&&z<pf['z'][1]+1e-5
   end
  end
  raise 'Döşeme sınır yüzünün kalıp/temas kaydı bulunamadı.' if matches.empty?
  form=matches.any?{|pf|%w[side_form bottom_form].include?(pf['kind'])}
  mark_formwork_face(f,form,form_mat,nil,form ? (n.z < -0.999 ? 'BOTTOM_FORM':'FREE_EDGE'):'CONTACT_OR_TOP')
 end
 ents.parent.set_attribute(DICT,'deck_boundary_schema','DS3')
 ents.parent.set_attribute(DICT,'deck_boundary_cells',cells)
 [faces.size,0]
end
end
end
