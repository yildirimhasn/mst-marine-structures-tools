# frozen_string_literal: true
# MST Alt04: additive, selected-pile visualization and physical accessories.
module MAG
module MarineStructuresTools
  extend self
  VIS_DEFAULTS={'pipe'=>'#A66B42','infill'=>'#A6A6A6','lower'=>'#1769E8','upper'=>'#F2B600','inner_plug'=>'#C62828','driving_plug'=>'#13834B'}.freeze
  def mst_visual_material(model,key,hex)
    name="MST | #{key} | #{hex}"
    mat=model.materials[name] || model.materials.add(name)
    mat.color=Sketchup::Color.new(hex)
    mat
  end
  def mst_visual_annulus(ents,outer_mm,inner_mm,z_m,height_m,material,name,kind)
    return if outer_mm<=inner_mm || inner_mm<0 || height_m<=0
    # Build the closed ring from independent quad faces. Do not delete a face
    # inside a new Group: SketchUp can invalidate the entire empty/merged Group.
    g=ents.add_group
    # Give the group identity before adding coplanar faces; never reuse a deleted entity.
    g.set_attribute(DICT,'mst_visual_part',kind)
    g.name=name
    ro=mm(outer_mm)/2.0; ri=mm(inner_mm)/2.0
    z0=m(z_m); z1=z0+m(height_m)
    outer0=[];outer1=[];inner0=[];inner1=[]
    SEG.times do |i|
      a=2.0*Math::PI*i/SEG
      c=Math.cos(a);si=Math.sin(a)
      outer0 << Geom::Point3d.new(ro*c,ro*si,z0)
      outer1 << Geom::Point3d.new(ro*c,ro*si,z1)
      inner0 << Geom::Point3d.new(ri*c,ri*si,z0)
      inner1 << Geom::Point3d.new(ri*c,ri*si,z1)
    end
    SEG.times do |i|
      j=(i+1)%SEG
      [[outer0[i],outer0[j],outer1[j],outer1[i]],
       [inner0[j],inner0[i],inner1[i],inner1[j]],
       [outer1[i],outer1[j],inner1[j],inner1[i]],
       [outer0[j],outer0[i],inner0[i],inner0[j]]].each do |quad|
        f=g.entities.add_face(quad)
        # SketchUp can merge a coplanar quad with its neighbour and return an
        # invalidated face. The merged geometry is still valid: do not touch f.
        if f && f.valid?
          f.material=material;f.back_material=material
        end
      end
    end
    # Smooth only the vertical segment seams of the cylindrical inner/outer walls.
    # Preserve top/bottom circular boundary edges and horizontal outlines.
    tolerance=0.001.mm
    g.entities.grep(Sketchup::Edge).each do |edge|
      next unless edge.valid? && edge.faces.length==2
      a=edge.start.position; b=edge.end.position
      vertical=(a.x-b.x).abs<tolerance && (a.y-b.y).abs<tolerance && (a.z-b.z).abs>tolerance
      next unless vertical
      edge.soft=true
      edge.smooth=true
    end
    raise "Çember grubu oluşturulamadı: #{name}" unless g.valid?
    g.material=material
    g.set_attribute(DICT,'mst_visual_part',kind)
    g
  end
  def mst_visual_disc(ents,diameter_mm,z_m,thickness_mm,material,name,kind)
    return if diameter_mm<=0 || thickness_mm<=0
    g=ents.add_group;g.set_attribute(DICT,'mst_visual_part',kind);g.name=name
    circle=g.entities.add_circle(Geom::Point3d.new(0,0,m(z_m)),Z_AXIS,mm(diameter_mm)/2,SEG)
    f=g.entities.add_face(circle)
    raise "Tapa yüzeyi oluşturulamadı: #{name}" unless f && f.valid?
    f.reverse! if f.normal.z<0
    f.pushpull(mm(thickness_mm))
    g.material=material;g.entities.grep(Sketchup::Face).each{|x|x.material=material;x.back_material=material}
    g.set_attribute(DICT,'mst_visual_part',kind);g
  end
  def mst_visual_refresh_pile(p,colors)
    if mst_component_pile?(p)
      # v0.38 C6: colours/details live in the shared definition -> attach the matching one.
      (colors||{}).each{|k,v|p.set_attribute(DICT,"visual_color_#{k}",v) if v && VIS_DEFAULTS.key?(k)}
      return mst_pile_component_refresh!(p)
    end
    mst_require_group_pile!(p,'Kazık görsel/detay yenileme')
    d=p.get_attribute(DICT,'diameter_mm',0).to_f;t=p.get_attribute(DICT,'thickness_mm',0).to_f;l=p.get_attribute(DICT,'length_m',0).to_f
    raise "#{p.name}: kazık çap/et/boy bilgisi geçersiz" unless d>2*t && t>0 && l>0
    model=Sketchup.active_model
    mats={};VIS_DEFAULTS.each{|key,default|hex=colors[key] || p.get_attribute(DICT,"visual_color_#{key}",default);mats[key]=mst_visual_material(model,key,hex);p.set_attribute(DICT,"visual_color_#{key}",hex)}
    p.entities.grep(Sketchup::Group).select{|g|g.valid? && g.get_attribute(DICT,'mst_visual_part','').to_s!=''}.each{|g|g.erase! if g.valid?}
    # Original steel pipe is raw pile geometry; child concrete stays independent.
    p.entities.grep(Sketchup::Face).each{|f|f.material=mats['pipe'];f.back_material=mats['pipe']}
    inf=p.entities.grep(Sketchup::Group).find{|g|g.get_attribute(DICT,'element_type','').to_s=='pile_infill_concrete'}
    if inf
      inf.material=mats['infill'];inf.entities.grep(Sketchup::Face).each{|f|f.material=mats['infill'];f.back_material=mats['infill']}
    end
    if p.get_attribute(DICT,'upper_ring_enabled','0').to_s=='1'
      n=[p.get_attribute(DICT,'upper_ring_count_per_pile',1).to_i,1].max
      w=p.get_attribute(DICT,'upper_ring_width_mm',250).to_f;th=p.get_attribute(DICT,'upper_ring_thickness_mm',t).to_f
      raise 'Üst çember ölçüsü geçersiz' unless w>0 && th>0
      n.times{|i|mst_visual_annulus(p.entities,d+2*th,d,-((i+1)*w)/1000.0,w/1000.0,mats['upper'],"Upper / Outer Ring #{i+1}",'upper_ring')}
    end
    if p.get_attribute(DICT,'lower_ring_enabled','0').to_s=='1'
      n=[p.get_attribute(DICT,'lower_ring_count_per_pile',1).to_i,1].max
      w=p.get_attribute(DICT,'lower_ring_width_mm',300).to_f;th=p.get_attribute(DICT,'lower_ring_thickness_mm',t).to_f
      raise 'Alt çember ölçüsü geçersiz' unless w>0 && th>0 && d-2*t-2*th>0
      n.times{|i|mst_visual_annulus(p.entities,d-2*t,d-2*t-2*th,-l+(i*w/1000.0),w/1000.0,mats['lower'],"Lower / Inner Ring #{i+1}",'lower_ring')}
    end
    if p.get_attribute(DICT,'plug_enabled','0').to_s=='1'
      n=[p.get_attribute(DICT,'plug_count_per_pile',1).to_i,1].max
      th=p.get_attribute(DICT,'plug_thickness_mm',12).to_f;clearance=p.get_attribute(DICT,'plug_clearance_mm',10).to_f
      dia=d-2*t-2*clearance
      raise 'Tapa ölçüsü geçersiz' unless dia>0 && th>0
      # Concrete plug sits at concrete infill bottom; driving plug sits 0.30 m above pile toe, at the upper side of the lower inner ring.
      if inf
        h=inf.get_attribute(DICT,'height_m',0).to_f
        mst_visual_disc(p.entities,dia,-h,th,mats['inner_plug'],'Infill Bottom Plug','inner_plug')
      elsif n>=1
        # Without concrete, no invented infill elevation: only driving-tip cap.
        mst_visual_disc(p.entities,dia,-l+0.30,th,mats['driving_plug'],'Driving Tip Plug','driving_plug')
      end
      mst_visual_disc(p.entities,dia,-l+0.30,th,mats['driving_plug'],'Driving Tip Plug','driving_plug') if inf && n>=2
    end
    raise 'Kazık grubu görsel güncelleme sırasında geçersizleşti' unless p.valid?
    p.set_attribute(DICT,'mst_visual_initialized','1')
    sync_pile_bim_qto(p)
  end
  def mst_visual_sync_if_initialized(p)
    return unless p && p.valid?
    return unless p.get_attribute(DICT,'mst_visual_initialized','0').to_s=='1'
    colors={}
    VIS_DEFAULTS.each{|key,default|colors[key]=p.get_attribute(DICT,"visual_color_#{key}",default)}
    mst_visual_refresh_pile(p,colors)
  end
  def mst_visual_audit_pile(p)
    return [] unless p.get_attribute(DICT,'mst_visual_initialized','0').to_s=='1'
    actual=Hash.new(0)
    (mst_container_entities(p)||[]).grep(Sketchup::Group).each do |g|
      next unless g.valid?
      kind=g.get_attribute(DICT,'mst_visual_part','').to_s
      actual[kind]+=1 unless kind.empty?
    end
    expected={
      'lower_ring'=>p.get_attribute(DICT,'lower_ring_enabled','0').to_s=='1' ? [p.get_attribute(DICT,'lower_ring_count_per_pile',1).to_i,1].max : 0,
      'upper_ring'=>p.get_attribute(DICT,'upper_ring_enabled','0').to_s=='1' ? [p.get_attribute(DICT,'upper_ring_count_per_pile',1).to_i,1].max : 0
    }
    if p.get_attribute(DICT,'plug_enabled','0').to_s=='1'
      n=[p.get_attribute(DICT,'plug_count_per_pile',1).to_i,1].max
      inf=!mst_bim_children(p,'pile_infill_concrete').empty?
      expected['inner_plug']=inf ? 1 : 0
      expected['driving_plug']=inf ? (n>=2 ? 1 : 0) : 1
      # The visual scheme has exactly two distinct engineering plug locations.
      expected['__unsupported_plug_count__']=n if n>2
    else
      expected['inner_plug']=0;expected['driving_plug']=0
    end
    issues=[]
    expected.each do |kind,count|
      if kind=='__unsupported_plug_count__'
        issues << "Tapa adedi #{count}: görsel şema en fazla iki ayrı tapa konumu destekliyor."
      elsif actual[kind]!=count
        issues << "#{kind}: BIM/QTO #{count} adet, fiziksel model #{actual[kind]} adet."
      end
    end
    issues
  end
  def mst_show_pile_visual_editor
    model=Sketchup.active_model
    piles=selected_piles.map{|entry|entry.is_a?(Array) ? entry[0] : entry}.select{|e|e.valid? && e.get_attribute(DICT,'element_type','').to_s=='steel_pipe_pile'}.uniq{|e|e.persistent_id}
    raise 'Önce SketchUp modelinde bir veya daha fazla ana çelik boru kazık grubunu seçin.' if piles.empty?
    available=model.materials.to_a.map{|x|[x.name,x.color.to_a[0,3].map{|c|'%02X'%c}.join.prepend('#')] rescue nil}.compact
    palette=VIS_DEFAULTS.map{|k,v|[k,v]}.to_h
    opts=available.map{|name,hex|"<option value='#{hex}'>#{name.gsub('&','&amp;').gsub('<','&lt;')} (#{hex})</option>"}.join
    rows=VIS_DEFAULTS.map{|key,hex|"<label>#{ {'pipe'=>'Çelik boru kazık','infill'=>'Kazık içi beton','lower'=>'Alt / İç çember','upper'=>'Üst / Dış çember','inner_plug'=>'Beton alt kotu tapası','driving_plug'=>'Çakım / Kazık ucu tapası'}[key]}<select id='#{key}'><option value='#{hex}'>Önerilen #{hex}</option>#{opts}</select></label>"}.join
    html="<!doctype html><html><head><meta charset='utf-8'><style>body{font:13px Arial;padding:18px;color:#16394d;background:#f4f8fb}h2{margin:0 0 8px}.note{padding:10px;background:#e7f3fb;margin-bottom:14px}label{display:block;margin:10px 0;font-weight:bold}select{display:block;width:100%;padding:8px;margin-top:4px}button{padding:11px 18px;background:#087fd1;color:white;border:0;border-radius:5px;cursor:pointer}</style></head><body><h2>MST Alt04f — Kazık Renk ve Fiziksel Detay</h2><div class='note'>#{piles.size} seçili kazık. Mevcut SketchUp malzemelerinden renk seçin. Çemberler ve tapalar ayrı fiziksel gruplar olarak oluşturulur; metraj parametreleri korunur.</div>#{rows}<button onclick='apply()'>Seçili Kazıklara Uygula</button><script>function apply(){let x={};#{VIS_DEFAULTS.keys.to_json}.forEach(k=>x[k]=document.getElementById(k).value);sketchup.mst_visual_apply(JSON.stringify(x))}</script></body></html>"
    dlg=mst_html_dialog('pile_visual',dialog_title:'MST Alt04 | Kazık Görünümü',width:510,height:710,resizable:true)
    dlg.set_html(html)
    dlg.add_action_callback('mst_visual_apply') do |_,raw|
      begin
        colors=JSON.parse(raw);raise 'Renk değeri geçersiz.' unless VIS_DEFAULTS.keys.all?{|k|colors[k].to_s.match?(/\A#[0-9A-Fa-f]{6}\z/)}
        model.start_operation('MST Pile Visual Geometry Alt04',true)
        begin
          piles.each{|p|mst_visual_refresh_pile(p,colors) if p.valid?}
          model.commit_operation
          UI.messagebox("#{piles.size} kazığın görünümü ve fiziksel detayları güncellendi. QTO korunarak yenilendi.")
          dlg.close
        rescue => e
          model.abort_operation;raise e
        end
      rescue => e
        UI.messagebox("MST Alt04: #{e.message}")
      end
    end
    dlg.show
  end
end
end
# Alt04k: physical details are generated by the main pile create/edit workflows.
