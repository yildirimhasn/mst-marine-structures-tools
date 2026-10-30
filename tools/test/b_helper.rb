# Parti B sahte nesne test yardimcisi (SketchUp disinda). a2_helper uzerine:
# SketchUp tarzi Transformation#to_a (16 deger, sutun sirali), xaxis, sinir kutusu (dunya, inc),
# yuz (normal + sinir kutusu), sirali UI.inputbox yanitlari ve kaynak parcasi calistirma.
# Kullanim (her b_*.rb): ruby b_xxx.rb <marine_structures_tools klasoru>   (0.51.4 icin eski kopyanin klasoru)
require_relative 'a2_helper'

module Geom
  class Vector3d
    def length; Math.sqrt(x * x + y * y + z * z); end
  end
  class Transformation
    def xaxis; Vector3d.new(@r[0][0], @r[1][0], @r[2][0]); end
    def yaxis; Vector3d.new(@r[0][1], @r[1][1], @r[2][1]); end
    def zaxis; Vector3d.new(@r[0][2], @r[1][2], @r[2][2]); end
    # SketchUp: [xaxis(3),0, yaxis(3),0, zaxis(3),0, origin(3),1]
    def to_a; [@r[0][0], @r[1][0], @r[2][0], 0.0, @r[0][1], @r[1][1], @r[2][1], 0.0, @r[0][2], @r[1][2], @r[2][2], 0.0] + @t + [1.0]; end
    def self.scaling(sx, sy, sz); new([[sx, 0, 0], [0, sy, 0], [0, 0, sz]]); end
    def identity?; @r == [[1, 0, 0], [0, 1, 0], [0, 0, 1]] && @t.all?(&:zero?); end
  end
end

class FakeBounds
  attr_reader :min, :max
  def initialize(min, max); @min = Geom::Point3d.new(min); @max = Geom::Point3d.new(max); end
  def width; @max.x - @min.x; end
  def height; @max.y - @min.y; end
  def center; Geom::Point3d.new((@min.x + @max.x) / 2, (@min.y + @max.y) / 2, (@min.z + @max.z) / 2); end
end

# yerel kutu (m) + donusum → dunya sinir kutusu (inc)
def b_world_bounds(lmin, lmax, tr)
  pts = [lmin[0], lmax[0]].product([lmin[1], lmax[1]], [lmin[2], lmax[2]]).map { |p| tr.apply(p.map { |v| v * INCH }) }
  FakeBounds.new((0..2).map { |k| pts.map { |q| q[k] }.min }, (0..2).map { |k| pts.map { |q| q[k] }.max })
end

class FakeEnt
  attr_writer :bounds
  def bounds; @bounds; end
end

class FakeFace < Sketchup::Face
  attr_accessor :normal, :back_material
  def initialize(pid, kind, normal, lmin_m, area_m2)
    super(pid, 'formwork_type' => kind)
    @normal = Geom::Vector3d.new(normal)
    @bounds = FakeBounds.new(lmin_m.map { |v| v * INCH }, lmin_m.map { |v| v * INCH + 1 })
    @area = area_m2 * INCH * INCH
  end
  def area; @area; end
  def material=(m); @material = m; end
end

# sirali inputbox yanitlari
$ib_queue = []
module UI
  def self.inputbox(*_a); $ib_queue.shift; end
end

# Kaynak metinden iki isaret arasindaki parca (bas dahil, son haric)
def b_slice(text, from, to)
  a = text.index(from) or abort("parca bulunamadi: #{from[0, 40]}")
  e = text.index(to, a + from.length) or abort("parca sonu yok: #{to[0, 40]}")
  text[a...e]
end
