# Parti A2 sahte nesne test yardimcisi (SketchUp disinda). a1_helper uzerine:
# Sketchup::Group / ComponentInstance / ComponentDefinition / Face sahteleri, basit Geom (Point3d, Transformation),
# birim donusumleri ve kaynak dosyadan sabit (CONST=... .freeze) cikarma.
# Kullanim (her a2_*.rb): ruby a2_xxx.rb <marine_structures_tools klasoru>
require_relative 'a1_helper'

INCH = 39.37007874015748
class Numeric
  def to_m; to_f / INCH; end
  def m; to_f * INCH; end
  def mm; to_f * INCH / 1000.0; end
end

module Geom
  class Point3d
    attr_reader :x, :y, :z
    def initialize(x = 0, y = 0, z = 0)
      x, y, z = x if x.is_a?(Array)
      @x = x.to_f; @y = y.to_f; @z = z.to_f
    end
    def to_a; [@x, @y, @z]; end
    def transform(t); Point3d.new(t.apply(to_a)); end
  end
  class Vector3d < Point3d; end
  # 3x3 dondurme + oteleme (inc)
  class Transformation
    attr_reader :r, :t
    def initialize(r = [[1, 0, 0], [0, 1, 0], [0, 0, 1]], t = [0, 0, 0]); @r = r; @t = t.map(&:to_f); end
    def self.translation(v); v = v.respond_to?(:to_a) ? v.to_a : v; new([[1, 0, 0], [0, 1, 0], [0, 0, 1]], v.map(&:to_f)); end
    def self.rotation(_pt, axis, ang)
      x, y, z = axis.respond_to?(:to_a) ? axis.to_a : axis
      n = Math.sqrt(x * x + y * y + z * z); x /= n; y /= n; z /= n
      c = Math.cos(ang); s = Math.sin(ang); k = 1 - c
      new([[c + x * x * k, x * y * k - z * s, x * z * k + y * s],
           [y * x * k + z * s, c + y * y * k, y * z * k - x * s],
           [z * x * k - y * s, z * y * k + x * s, c + z * z * k]])
    end
    def apply(p); (0..2).map { |i| @r[i][0] * p[0] + @r[i][1] * p[1] + @r[i][2] * p[2] + @t[i] }; end
    def *(o)
      rr = (0..2).map { |i| (0..2).map { |j| (0..2).sum { |k| @r[i][k] * o.r[k][j] } } }
      Transformation.new(rr, apply(o.t))
    end
    def inverse
      rt = (0..2).map { |i| (0..2).map { |j| @r[j][i] } }
      Transformation.new(rt, (0..2).map { |i| -(0..2).sum { |k| rt[i][k] * @t[k] } })
    end
    def origin; Point3d.new(@t); end
    def to_a; @r.flatten + @t; end
  end
end
ORIGIN = Geom::Point3d.new(0, 0, 0) unless defined?(ORIGIN)
Z_AXIS = Geom::Vector3d.new(0, 0, 1) unless defined?(Z_AXIS)

class FakeEnt
  attr_accessor :transformation, :entities, :definition, :erased
  def attribute_dictionary(name, _create = false)
    pairs = @attrs.select { |(d, _), _| d == name }.map { |(_, k), v| [k, v] }
    pairs.empty? ? nil : FakeDict.new(name, pairs)
  end
  def erase!; @erased = true; $log << [:erase, self]; end
  def model; $model; end
end

module Sketchup
  class Group < FakeEnt; end
  class ComponentInstance < FakeEnt
    undef_method :entities, :entities=   # SketchUp: ornek #entities yok, definition.entities
    def make_unique
      $log << [:make_unique, self]
      old = definition
      return self if old.instances.length <= 1
      nd = ComponentDefinition.new(900_000 + rand(99_999))   # SketchUp'in oznitelik kopyalayip kopyalamadigi bilinmiyor: sahte KOPYALAMAZ
      nd.entities = old.entities.dup
      old.instances.delete(self); nd.instances << self
      @definition = nd
      $model.definitions << nd if $model.respond_to?(:definitions) && $model.definitions
      self
    end
    def definition=(d)
      @definition.instances.delete(self) if @definition
      @definition = d
      d.instances << self unless d.instances.include?(self)
    end
  end
  class ComponentDefinition < FakeEnt
    attr_accessor :instances, :name
    def initialize(pid, h = {}); super(pid, h); @instances = []; @entities = []; end
    def count_instances; @instances.length; end
    def image?; false; end
    def group?; false; end
  end
  class Face < FakeEnt
    attr_accessor :area_m2
  end
end

class FakeModel
  attr_accessor :definitions, :selection
end

# Kaynaktan "AD=... .freeze" sabitini cikarip Host'ta tanimlar (cok satirli olabilir)
def a2_const(host, text, name)
  a = text.index("\n#{name}=") or abort("sabit yok: #{name}")
  e = text.index('.freeze', a) or abort("freeze yok: #{name}")
  host.class_eval(text[a + 1..e + 6])
end

def near(a, b, tol = 1e-6); (a.to_f - b.to_f).abs <= tol; end

class Host
  SEG = 24 unless defined?(SEG)
  def m(x); x.to_f * INCH; end
  def mm(x); x.to_f * INCH / 1000.0; end
end

# 0.51.4 karsilastirma kopyasi (yoksa ARGV[1])
A2_OLD = ENV['A2_OLD'].to_s
