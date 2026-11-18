# frozen_string_literal: true
module MAG
module MarineStructuresTools
  module JetGroutUnion
    TURN = 2.0 * Math::PI

    # Area of circular arcs on the outside of the union, integrated with Green's theorem.
    def self.area(circles)
      circles = circles.uniq
      origin_x, origin_y = circles.first
      circles = circles.map { |x,y,r| [x-origin_x,y-origin_y,r] }
      circles.each_with_index.sum do |(x,y,r), index|
        covered = []
        circles.each_with_index do |(ox,oy,s), other|
          next if index == other
          dx, dy = ox-x, oy-y
          d = Math.hypot(dx,dy)
          if d+r <= s
            covered = [[0.0,TURN]]
            break
          end
          next if d >= r+s || d+s <= r
          angle = Math.atan2(dy,dx)
          cosine = (d*d+r*r-s*s)/(2*d*r)
          half = Math.acos(cosine.clamp(-1.0,1.0))
          start = (angle-half)%TURN
          finish = start+2*half
          covered << [start,[finish,TURN].min]
          covered << [0.0,finish-TURN] if finish>TURN
        end
        integral = lambda do |a,b|
          (r*r*(b-a)+r*x*(Math.sin(b)-Math.sin(a))-r*y*(Math.cos(b)-Math.cos(a)))*0.5
        end
        cursor = 0.0
        partial = covered.sort.sum do |a,b|
          uncovered = a>cursor ? integral.call(cursor,a) : 0.0
          cursor = [cursor,b].max
          uncovered
        end
        partial+integral.call(cursor,TURN)
      end
    end

    def self.volume(columns)
      cuts = columns.flat_map { |_,_,_,bottom,top| [bottom,top] }.uniq.sort
      cuts.each_cons(2).sum do |low,high|
        circles = columns.each_with_object([]) do |(x,y,r,bottom,top), active|
          active << [x,y,r] if bottom<=low && top>=high
        end
        circles.empty? ? 0.0 : area(circles)*(high-low)
      end
    end
  end
end
end

