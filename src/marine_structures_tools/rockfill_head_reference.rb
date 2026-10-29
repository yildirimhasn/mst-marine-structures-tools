# frozen_string_literal: true
module MAG
module MarineStructuresTools
RF02_PLAN_SECTION_INFO_LIMIT_M = 5.0 unless const_defined?(:RF02_PLAN_SECTION_INFO_LIMIT_M)

# Project owner's rule: a strictly sub-5 m plan/section dimensional difference
# is informational. This does not waive missing geometry or unrelated checks.
def rf02_plan_section_difference(plan_measure,section_measure)
 difference=(plan_measure-section_measure).abs
 raise 'Ölçü farkı geçersiz.' unless difference.finite?
 severity=difference.zero? ? 'none' : (difference<RF02_PLAN_SECTION_INFO_LIMIT_M ? 'info' : 'review')
 {'absolute_m'=>difference,'signed_m'=>plan_measure-section_measure,
  'info_limit_m'=>RF02_PLAN_SECTION_INFO_LIMIT_M,'severity'=>severity,
  'requires_review'=>severity=='review'}
end
# Conditional reference calculation: section 14 is revolved without stretching.
# The planar head is the major circular segment closed by the arc-end chord.
# This is NOT a reconstructed 3D design or an approved complete head quantity.
def rf02_head_reference(data)
 return nil unless data
 radius=data.fetch('plan_radius_m');angle=data.fetch('arc_angle_radians')
 raise 'Baş yayı geçersiz.' unless [radius,angle].all?{|v|v.is_a?(Numeric)&&v.finite?} && radius>0 && angle>Math::PI && angle<=2*Math::PI
 profiles=data.fetch('profiles')
 raise 'Baş profilleri geçersiz.' unless profiles.is_a?(Array)&&profiles.length.between?(1,100)
 distance=-radius*Math.cos(angle/2.0)
 nodes=[0.1834346424956498,0.5255324099163290,0.7966664774136267,0.9602898564975363]
 weights=[0.3626837833783620,0.3137066458778873,0.2223810344533745,0.1012285362903763]
 gauss=lambda do |fn,a,b|
  center=(a+b)/2.0;half=(b-a)/2.0
  nodes.each_with_index.map{|n,i|weights[i]*(fn.call(center-half*n)+fn.call(center+half*n))}.inject(0.0,:+)*half
 end
 integrate=nil
 integrate=lambda do |fn,a,b,tol,depth|
  middle=(a+b)/2.0;whole=gauss.call(fn,a,b);halves=gauss.call(fn,a,middle)+gauss.call(fn,middle,b)
  if (whole-halves).abs<=tol
   halves
  else
   raise 'Baş integrali yakınsamadı.' if depth>=22
   integrate.call(fn,a,middle,tol/2.0,depth+1)+integrate.call(fn,middle,b,tol/2.0,depth+1)
  end
 end
 quantities={};max_radius=0.0
 profiles.each do |profile|
  material=profile.fetch('material');poly=profile.fetch('points_rz_m')
  raise 'Baş malzemesi geçersiz.' unless material.is_a?(String)
  raise 'Baş çokgeni geçersiz.' unless poly.is_a?(Array)&&poly.length.between?(3,1000)&&poly.all?{|p|p.is_a?(Array)&&p.length==2&&p.all?{|x|x.is_a?(Numeric)&&x.finite?}&&p[0]>=0}
  max_radius=[max_radius,poly.map(&:first).max].max
  knots=(poly.map(&:first)+[0.0,radius,distance]).select{|r|r>=0&&r<=radius}.uniq.sort
  fn=lambda do |r|
   zs=[]
   poly.each_with_index do |a,i|
    b=poly[(i+1)%poly.length]
    if (a[0]<=r&&r<b[0]) || (b[0]<=r&&r<a[0])
     zs<<a[1]+(r-a[0])*(b[1]-a[1])/(b[0]-a[0])
    end
   end
   raise 'Baş profili kesişimleri eşlenemedi.' unless zs.length.even?
   height=zs.sort.each_slice(2).map{|a,b|b-a}.inject(0.0,:+)
   span=r<=distance ? 2*Math::PI : 2*Math.acos(-distance/r)
   height*r*span
  end
  v=knots.each_cons(2).map{|a,b|integrate.call(fn,a,b,0.0001,0)}.inject(0.0,:+)
  quantities[material]=(quantities[material]||0.0)+v
 end
 {'method'=>'14-14 sağ yarı kesitinin dönel kabulü; yay uçları arasındaki kirişin deniz tarafı',
  'status'=>'CONDITIONAL_REFERENCE_NOT_FINAL','volumes_m3'=>quantities,
  'plan_radius_m'=>radius,'profile_radius_m'=>max_radius,'arc_degrees'=>angle*180/Math::PI,
  'arc_length_m'=>radius*angle,'chord_distance_m'=>distance,'radial_difference_m'=>radius-max_radius,
  'dimension_difference'=>rf02_plan_section_difference(radius,max_radius),
  'boq_eligible'=>false}
end
end
end
