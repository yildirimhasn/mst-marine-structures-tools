# Golden-master icin SketchUp API sahtesi (SketchUp DISINDA). Eklentinin tum dosyalari gercek yukleme sirasiyla
# (`main.rb` ve onun require_relative zinciri) yuklenir; SketchUp/UI cagrilari bu sahtelere duser.
# Yalniz METRAJ OKUYUCULARINI calistirmak icindir: geometri uretimi, arayuz ve gozlemciler sinanmaz.
# Bilinmeyen sabit/cagri sessizce Dummy nesnesine duser; bunlar $stub_misses'e yazilir ve betik sonunda raporlanir.
require 'json'
require 'set'
$stub_misses = Hash.new(0)

# Her cagriyi yutan nesne (yukleme anindaki menu/arac cubugu/gozlemci kayitlari icin)
class Dummy < BasicObject
  def initialize(name = 'dummy'); @n = name; end
  def method_missing(m, *a, &b); ::Kernel.instance_variable_get(:@x); self; end
  def respond_to_missing?(*) true end
  def to_s; ''; end
  def to_str; ''; end
  def to_a; []; end
  def to_ary; []; end
  def to_i; 0; end
  def to_f; 0.0; end
  def nil?; false; end
  def is_a?(_k); false; end
  def kind_of?(_k); false; end
  def ==(o); equal?(o); end
  def !; false; end
  def each; self; end
  def inspect; "#<Dummy #{@n}>"; end
  def class; ::Dummy; end
  def hash; __id__; end
  def eql?(o); equal?(o); end
end

class DummyClass
  def self.new(*_a, &_b); Dummy.new(name.to_s); end
  def self.method_missing(*_a); Dummy.new('cls'); end
  def self.respond_to_missing?(*) true end
end

class Object
  def self.const_missing(n)
    $stub_misses["const #{self}::#{n}"] += 1
    k = Class.new(DummyClass)
    const_set(n, k)
  end
end

INCH = 39.37007874015748 unless defined?(INCH)
class Numeric
  def m; to_f * INCH; end
  def mm; to_f * INCH / 1000.0; end
  def cm; to_f * INCH / 100.0; end
  def inch; to_f; end
  def to_m; to_f / INCH; end
  def to_mm; to_f / INCH * 1000.0; end
  def to_cm; to_f / INCH * 100.0; end
  def to_inch; to_f; end
  def degrees; to_f * Math::PI / 180.0; end
  def radians; to_f * 180.0 / Math::PI; end
end

MB_OK = 0; MB_OKCANCEL = 1; MB_ABORTRETRYIGNORE = 2; MB_YESNOCANCEL = 3; MB_YESNO = 4; MB_RETRYCANCEL = 5
IDOK = 1; IDCANCEL = 2; IDABORT = 3; IDRETRY = 4; IDIGNORE = 5; IDYES = 6; IDNO = 7
MF_ENABLED = 0; MF_GRAYED = 1; MF_CHECKED = 8; MF_UNCHECKED = 0
TB_VISIBLE = 1; TB_HIDDEN = 0; TB_NEVER_SHOWN = -1
CONSTRUCTION_ID = 0 unless defined?(CONSTRUCTION_ID)

module Geom
  class Point3d
    attr_accessor :x, :y, :z
    def initialize(x = 0, y = 0, z = 0)
      x, y, z = x.to_a if x.respond_to?(:to_a) && !x.is_a?(Numeric)
      @x = x.to_f; @y = y.to_f; @z = z.to_f
    end
    def to_a; [@x, @y, @z]; end
    def [](i); to_a[i]; end
    def transform(t); Point3d.new(t.apply(to_a)); end
    def -(o); Vector3d.new(@x - o.x, @y - o.y, @z - o.z); end
    def +(o); Point3d.new(@x + o.x, @y + o.y, @z + o.z); end
    def distance(o); Math.sqrt((@x - o.x)**2 + (@y - o.y)**2 + (@z - o.z)**2); end
    def ==(o); o.respond_to?(:to_a) && to_a == o.to_a; end
    def offset(v, d = nil)
      return Point3d.new(@x + v.x, @y + v.y, @z + v.z) unless d
      l = v.length; Point3d.new(@x + v.x / l * d, @y + v.y / l * d, @z + v.z / l * d)
    end
  end
  class Vector3d < Point3d
    def length; Math.sqrt(x * x + y * y + z * z); end
    def normalize; l = length; Vector3d.new(x / l, y / l, z / l); end
    def dot(o); x * o.x + y * o.y + z * o.z; end
    def %(o); dot(o); end
    def *(o); Vector3d.new(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x); end
    def angle_between(o); Math.acos([[dot(o) / (length * o.length), 1.0].min, -1.0].max); end
    def reverse; Vector3d.new(-x, -y, -z); end
    def valid?; length > 0; end
  end
  class Transformation
    attr_reader :r, :t
    def initialize(r = [[1, 0, 0], [0, 1, 0], [0, 0, 1]], t = [0, 0, 0])
      if r.is_a?(Point3d) then t = r.to_a; r = [[1, 0, 0], [0, 1, 0], [0, 0, 1]] end
      @r = r; @t = t.map(&:to_f)
    end
    def self.translation(v); new([[1, 0, 0], [0, 1, 0], [0, 0, 1]], v.to_a.map(&:to_f)); end
    def self.scaling(*a); s = a.size == 1 ? [a[0]] * 3 : a.last(3); new([[s[0], 0, 0], [0, s[1], 0], [0, 0, s[2]]]); end
    def self.rotation(_pt, axis, ang)
      x, y, z = axis.to_a
      n = Math.sqrt(x * x + y * y + z * z); x /= n; y /= n; z /= n
      c = Math.cos(ang); s = Math.sin(ang); k = 1 - c
      new([[c + x * x * k, x * y * k - z * s, x * z * k + y * s],
           [y * x * k + z * s, c + y * y * k, y * z * k - x * s],
           [z * x * k - y * s, z * y * k + x * s, c + z * z * k]])
    end
    def apply(p); (0..2).map { |i| @r[i][0] * p[0] + @r[i][1] * p[1] + @r[i][2] * p[2] + @t[i] }; end
    def *(o)
      return Point3d.new(apply(o.to_a)) if o.is_a?(Point3d)
      rr = (0..2).map { |i| (0..2).map { |j| (0..2).sum { |k| @r[i][k] * o.r[k][j] } } }
      Transformation.new(rr, apply(o.t))
    end
    def inverse
      rt = (0..2).map { |i| (0..2).map { |j| @r[j][i] } }
      Transformation.new(rt, (0..2).map { |i| -(0..2).sum { |k| rt[i][k] * @t[k] } })
    end
    def origin; Point3d.new(@t); end
    def xaxis; Vector3d.new(@r[0][0], @r[1][0], @r[2][0]); end
    def yaxis; Vector3d.new(@r[0][1], @r[1][1], @r[2][1]); end
    def zaxis; Vector3d.new(@r[0][2], @r[1][2], @r[2][2]); end
    def identity?; @r == [[1, 0, 0], [0, 1, 0], [0, 0, 1]] && @t.all?(&:zero?); end
    def to_a; [@r[0][0], @r[1][0], @r[2][0], 0.0, @r[0][1], @r[1][1], @r[2][1], 0.0, @r[0][2], @r[1][2], @r[2][2], 0.0] + @t + [1.0]; end
  end
  class BoundingBox
    attr_reader :min, :max
    def initialize(min = nil, max = nil); @min = min && Point3d.new(min.to_a); @max = max && Point3d.new(max.to_a); end
    def add(*pts)
      pts.flatten.each do |p|
        p = p.respond_to?(:to_a) ? p.to_a : p
        @min = Point3d.new(@min ? [[@min.x, p[0]].min, [@min.y, p[1]].min, [@min.z, p[2]].min] : p)
        @max = Point3d.new(@max ? [[@max.x, p[0]].max, [@max.y, p[1]].max, [@max.z, p[2]].max] : p)
      end
      self
    end
    def valid?; !@min.nil?; end
    def empty?; @min.nil?; end
    def width; @max.x - @min.x; end
    def height; @max.y - @min.y; end
    def depth; @max.z - @min.z; end
    def center; Point3d.new((@min.x + @max.x) / 2, (@min.y + @max.y) / 2, (@min.z + @max.z) / 2); end
    def corner(i); Point3d.new(i & 1 == 0 ? @min.x : @max.x, i & 2 == 0 ? @min.y : @max.y, i & 4 == 0 ? @min.z : @max.z); end
    def intersect(o)
      return BoundingBox.new unless valid? && o.valid?
      mn = [[@min.x, o.min.x].max, [@min.y, o.min.y].max, [@min.z, o.min.z].max]
      mx = [[@max.x, o.max.x].min, [@max.y, o.max.y].min, [@max.z, o.max.z].min]
      (0..2).all? { |k| mn[k] <= mx[k] } ? BoundingBox.new(mn, mx) : BoundingBox.new
    end
    def contains?(p); p = p.to_a; valid? && (0..2).all? { |k| p[k] >= @min.to_a[k] && p[k] <= @max.to_a[k] }; end
  end
  def self.intersect_line_plane(*_a); nil; end
  def self.linear_combination(w1, p1, w2, p2); Point3d.new(w1 * p1.x + w2 * p2.x, w1 * p1.y + w2 * p2.y, w1 * p1.z + w2 * p2.z); end
end
ORIGIN = Geom::Point3d.new(0, 0, 0)
X_AXIS = Geom::Vector3d.new(1, 0, 0)
Y_AXIS = Geom::Vector3d.new(0, 1, 0)
Z_AXIS = Geom::Vector3d.new(0, 0, 1)
IDENTITY = Geom::Transformation.new

module Sketchup
  def self.active_model; $model; end
  def self.version; '20.0.363'; end
  def self.version_number; 2000036300; end
  def self.temp_dir; Dir.tmpdir; end
  def self.find_support_file(*_a); nil; end
  def self.register_extension(*_a); true; end
  def self.status_text=(_v); end
  def self.require(*_a); true; end
  def self.read_default(_s, _k, d = nil); d; end
  def self.write_default(*_a); true; end
  def self.platform; :platform_win; end
  def self.method_missing(m, *_a); $stub_misses["Sketchup.#{m}"] += 1; Dummy.new("Sketchup.#{m}"); end
  def self.respond_to_missing?(*) true end

  # Ortak varlik: oznitelik sozlukleri ve persistent_id
  class Entity
    attr_accessor :persistent_id, :name, :parent, :layer, :material, :transformation, :erased, :hidden, :model_ref
    def initialize(pid = nil, attrs = {}, dict = 'MAG_MarineStructures')
      @persistent_id = pid || (($pid_seq ||= 100_000) && ($pid_seq += 1))
      @attrs = {}
      attrs.each { |k, v| @attrs[[dict, k.to_s]] = v }
      @transformation = Geom::Transformation.new
      @name = ''
    end
    def get_attribute(d, k, dflt = nil); @attrs.key?([d.to_s, k.to_s]) ? @attrs[[d.to_s, k.to_s]] : dflt; end
    def set_attribute(d, k, v); ($writes ||= []) << [@persistent_id, d, k]; @attrs[[d.to_s, k.to_s]] = v; end
    def delete_attribute(d, k = nil); ($writes ||= []) << [@persistent_id, d, k]; k ? @attrs.delete([d.to_s, k.to_s]) : @attrs.reject! { |(dd, _), _| dd == d.to_s }; end
    def attribute_dictionary(n, _c = false)
      pairs = @attrs.select { |(d, _), _| d == n.to_s }.map { |(_, k), v| [k, v] }
      pairs.empty? ? nil : AttributeDictionary.new(n, pairs)
    end
    def attribute_dictionaries
      @attrs.keys.map(&:first).uniq.map { |dn| attribute_dictionary(dn) }
    end
    def valid?; !@erased; end
    def deleted?; !!@erased; end
    def model; $model; end
    def entityID; @persistent_id; end
    def hidden?; !!@hidden; end
    def visible?; !@hidden; end
    def typename; self.class.name.split('::').last; end
    def inspect; "#{typename}(#{@persistent_id})"; end
    def erase!; @erased = true; end
    def add_observer(*_a); true; end
    def remove_observer(*_a); true; end
  end
  class AttributeDictionary
    attr_reader :name
    def initialize(n, pairs); @name = n; @pairs = pairs; end
    def each_pair(&b); @pairs.each { |k, v| b.call(k, v) }; end
    def each(&b); each_pair(&b); end
    def keys; @pairs.map(&:first); end
    def [](k); (@pairs.find { |kk, _| kk == k } || [])[1]; end
    def length; @pairs.length; end
    alias size length
  end
  class Entities < Array
    attr_accessor :parent
    def grep(k); select { |e| k === e }; end
    def add_observer(*_a); true; end
    def remove_observer(*_a); true; end
  end
  class Drawingelement < Entity
    attr_writer :bounds
    def bounds; @bounds || Geom::BoundingBox.new; end
  end
  class Group < Drawingelement
    attr_reader :entities
    def initialize(*a); super; @entities = Entities.new; @entities.parent = self; end
    def entities=(list); @entities = Entities.new(list); @entities.parent = self; list.each { |c| c.parent = @entities }; end
    def definition; @definition ||= ComponentDefinition.new(nil, {}).tap { |d| d.entities = @entities; d.instances << self }; end
    def manifold?; true; end
    def volume; (@vol_m3 || 0.0) * INCH**3; end
    attr_writer :vol_m3
  end
  class ComponentDefinition < Entity
    attr_accessor :entities, :instances
    def initialize(*a); super; @entities = Entities.new; @instances = []; end
    def count_instances; @instances.length; end
    def group?; false; end
    def image?; false; end
    def bounds; Geom::BoundingBox.new; end
  end
  class ComponentInstance < Drawingelement
    attr_reader :definition
    def definition=(d); @definition&.instances&.delete(self); @definition = d; d.instances << self unless d.instances.include?(self); end
    def manifold?; true; end
  end
  class Face < Drawingelement
    attr_accessor :normal, :back_material
    def area; @area_in2 || 0.0; end
    def area_m2=(v); @area_in2 = v * INCH * INCH; end
    def vertices; []; end
    def edges; []; end
    def loops; []; end
  end
  class Edge < Drawingelement; end
  class ConstructionPoint < Drawingelement; end
  class ConstructionLine < Drawingelement; end
  class Text < Drawingelement; end
  class Image < Drawingelement; end
  class Material < Entity; end
  class Layer < Entity; end
  class Model < Entity
    attr_accessor :entities, :selection, :definitions, :materials, :layers, :ops, :title, :path
    def initialize
      super(1, {})
      @entities = Entities.new; @entities.parent = self
      @selection = Entities.new
      @definitions = Entities.new
      @materials = Entities.new
      @layers = Entities.new
      @ops = []
      @title = 'golden'; @path = ''
    end
    def start_operation(*a); @ops << [:start, a[0]]; true; end
    def commit_operation; @ops << [:commit]; true; end
    def abort_operation; @ops << [:abort]; true; end
    def find_entity_by_persistent_id(pid); $all_ents && $all_ents[pid]; end
    def active_entities; @entities; end
    def active_path; nil; end
    def active_view; Dummy.new('view'); end
    def options; Dummy.new('options'); end
    def rendering_options; Dummy.new('ro'); end
    def shadow_info; Dummy.new('si'); end
    def tools; Dummy.new('tools'); end
    def pages; Entities.new; end
    def guid; 'golden-guid'; end
    def modified?; false; end
    def bounds; Geom::BoundingBox.new; end
  end
  %w[EntitiesObserver EntityObserver ModelObserver AppObserver SelectionObserver DefinitionObserver DefinitionsObserver
     InstanceObserver ToolsObserver ViewObserver LayersObserver MaterialsObserver FrameChangeObserver PagesObserver].each do |n|
    const_set(n, Class.new)
  end
  class InputPoint; def initialize(*_a); end; def method_missing(*_a); Dummy.new('ip'); end; end
end
class Sketchup::Color
  def self.new(*_a); Dummy.new('color'); end
end

class SketchupExtension
  attr_accessor :description, :version, :creator, :copyright, :name
  def initialize(*_a); end
end

module UI
  def self.messagebox(m, *_a); ($ui_msgs ||= []) << m.to_s; IDYES; end
  def self.inputbox(*_a); false; end
  def self.start_timer(*_a); 0; end
  def self.stop_timer(*_a); true; end
  def self.menu(*_a); Dummy.new('menu'); end
  def self.add_context_menu_handler(*_a); true; end
  def self.savepanel(*_a); nil; end
  def self.openpanel(*_a); nil; end
  def self.method_missing(m, *_a); $stub_misses["UI.#{m}"] += 1; Dummy.new("UI.#{m}"); end
  def self.respond_to_missing?(*) true end
  class Toolbar < DummyClass; end
  class Command < DummyClass; end
  class HtmlDialog < DummyClass
    STYLE_DIALOG = 0; STYLE_WINDOW = 1; STYLE_UTILITY = 2
  end
  class WebDialog < DummyClass; end
  class Notification < DummyClass; end
end

module Kernel
  def file_loaded?(_f); false; end
  def file_loaded(_f); true; end
end
$LOADED_FEATURES << 'sketchup.rb' << 'extensions.rb' << 'langhandler.rb'
