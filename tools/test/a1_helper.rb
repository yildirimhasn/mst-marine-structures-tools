# Parti A1 sahte nesne test yardimcisi (SketchUp disinda).
# Islevler kaynak dosyalardan metin olarak cikarilir ve sahte Sketchup/UI nesneleriyle
# Host sinifinda calistirilir. Kaynak dosyalar yalniz okunur.
# Kullanim (her a1_*.rb): ruby a1_xxx.rb <marine_structures_tools klasoru>
require 'json'
require 'fileutils'
require 'tmpdir'
require 'securerandom'

MB_YESNO = 4 unless defined?(MB_YESNO)
IDYES = 6 unless defined?(IDYES)
IDNO = 7 unless defined?(IDNO)
$log = []
$msgs = []
$ui_answer = IDYES

module A1
  DICT = 'MAG_MarineStructures'.freeze
  def self.dir
    ARGV[0] or abort 'kullanim: ruby a1_xxx.rb <marine_structures_tools klasoru>'
  end

  def self.src(name)
    File.binread(File.join(dir, name)).force_encoding('UTF-8')
  end

  # 'def ad(' ile baslayan islevi girintisine uygun 'end' satirina kadar cikarir.
  def self.grab(text, sig, optional = false)
    a = text.index(sig)
    unless a
      return nil if optional
      abort("bulunamadi: #{sig}")
    end
    ls = (text.rindex("\n", a) || -1) + 1
    ind = text[ls...a][/\A */]
    e = text.index("\n#{ind}end\n", a) or abort("son yok: #{sig}")
    text[a..e + ind.length + 4]
  end

  def self.load(host, text, *sigs)
    sigs.each { |s| c = grab(text, s); host.class_eval(c) }
  end

  def self.load_opt(host, text, sig)
    c = grab(text, sig, true)
    host.class_eval(c) if c
    !c.nil?
  end
end

class FakeEnt
  attr_accessor :persistent_id, :name, :box, :parent, :layer, :material
  def initialize(pid, h = {}, box = nil)
    @persistent_id = pid
    @attrs = {}
    h.each { |k, v| @attrs[[A1::DICT, k]] = v }
    @box = box
  end
  def get_attribute(d, k, dflt = nil); @attrs.key?([d, k]) ? @attrs[[d, k]] : dflt; end
  def set_attribute(d, k, v); $log << [:set, self, d, k, v]; @attrs[[d, k]] = v; end
  def delete_attribute(d, k); $log << [:del, self, d, k]; @attrs.delete([d, k]); end
  def a(k); @attrs[[A1::DICT, k]]; end
  def raw_attrs; @attrs.dup; end
  def valid?; true; end
  def attribute_dictionaries
    @attrs.keys.map(&:first).uniq.map do |dn|
      pairs = @attrs.select { |(d, _), _| d == dn }.map { |(_, k), v| [k, v] }
      FakeDict.new(dn, pairs)
    end
  end
  def inspect; "E#{@persistent_id}"; end
end

class FakeDict
  attr_reader :name
  def initialize(n, pairs); @name = n; @pairs = pairs; end
  def each_pair(&b); @pairs.each { |k, v| b.call(k, v) }; end
end

class FakeModel < FakeEnt
  attr_accessor :entities, :open_ops
  def initialize; super(0); @entities = []; @open_ops = 0; end
  def start_operation(*a); $log << [:start, a[0]]; @open_ops += 1; end
  def commit_operation; $log << [:commit]; @open_ops -= 1; end
  def abort_operation; $log << [:abort]; @open_ops -= 1; end
  def inspect; 'MODEL'; end
end

module Sketchup
  def self.active_model; $model; end
end

module UI
  def self.messagebox(m, _t = nil); $msgs << m.to_s; $ui_answer; end
  def self.inputbox(*_a); $inputbox_answer; end
end

class Host
  DICT = A1::DICT
  REVISION_DICT = 'MAG_MST_RevisionLog'.freeze
  PROGRESS_DICT = 'MAG_MST_Progress'.freeze
  PROG2_KEY = 'progress_items_json'.freeze
  def collect_elements(ents, out); out.concat(ents.to_a); end
  def element_visible_id(e)
    v = e.get_attribute(DICT, 'id', '').to_s
    v.empty? ? "PID-#{e.persistent_id}" : v
  end
  def commit_with_dependencies(model); $log << [:cwd]; model.commit_operation; end
end

def a1_reset!
  $model = FakeModel.new
  $log = []
  $msgs = []
  $ui_answer = IDYES
end

$ok = 0
$bad = 0
def t(label, got, exp)
  g = got == exp
  g ? $ok += 1 : $bad += 1
  puts "#{g ? 'GEÇTİ' : 'KALDI'}  #{label}: #{got.inspect} (beklenen #{exp.inspect})"
end
def obs(label, val); puts "GÖZLEM #{label}: #{val.inspect}"; end
def a1_finish
  puts "#{$ok} geçti, #{$bad} kaldı"
  exit($bad.zero? ? 0 : 1)
end
def ops; $log.select { |x| [:start, :commit, :abort].include?(x[0]) }.map { |x| x[0] }; end
def sets; $log.select { |x| x[0] == :set }; end
