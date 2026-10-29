# H1 sahte nesne testi: revizyon snapshot adlandirma / kirpma (SketchUp disinda).
# Kullanim: ruby t_h1_snapshot.rb <paket_kopyasi/marine_structures_tools>
# Paket dosyalari yalniz okunur; islevler metin olarak cikarilip sahte Sketchup nesnesiyle calistirilir.
require 'json'
dir = ARGV[0] or abort 'paket klasoru gerekli'
main = File.read(File.join(dir, 'main.rb'), encoding: 'UTF-8')
boq  = File.read(File.join(dir, 'boq_pro.rb'), encoding: 'UTF-8')
grab = ->(src, sig) { a = src.index(sig) or abort("bulunamadi: #{sig}"); src[a..src.index("\nend\n", a) + 4] }

module Sketchup
  class FakeModel
    attr_reader :attrs, :writes
    def initialize; @attrs = {}; @writes = 0; end
    def get_attribute(d, k, dflt = nil); @attrs.fetch([d, k], dflt); end
    def set_attribute(d, k, v); @writes += 1; @attrs[[d, k]] = v; end
  end
  def self.active_model; @m ||= FakeModel.new; end
  def self.reset!; @m = FakeModel.new; end
end
module UI; def self.messagebox(m); $msgs << m; end; end
$msgs = []

class Host
  REVISION_DICT = 'MAG_MST_RevisionLog'.freeze
  attr_accessor :curr
  def revision_current_snapshot; @curr || []; end
  def revision_send(_d = nil); end
  def boq2_boq_digest; [{ 'source' => 'S1', 'quantity' => 1.0 }]; end
  def boq2_currency; 'TRY'; end
end
Host.class_eval(grab.(main, 'def revision_snapshots'))
Host.class_eval(grab.(main, 'def revision_save_snapshots'))
Host.class_eval(grab.(main, 'def revision_create_snapshot('))
Host.class_eval("alias_method :revision_create_snapshot_base, :revision_create_snapshot unless method_defined?(:revision_create_snapshot_base)")
Host.class_eval(grab.(boq, 'def revision_create_snapshot('))

$ok = 0; $bad = 0
t = ->(label, got, exp) { g = got == exp; g ? $ok += 1 : $bad += 1; puts "#{g ? 'GEÇTİ' : 'KALDI'}  #{label}: #{got.inspect} (beklenen #{exp.inspect})" }
obs = ->(label, val) { puts "GÖZLEM #{label}: #{val.inspect}" }
snaps = -> { JSON.parse(Sketchup.active_model.get_attribute('MAG_MST_RevisionLog', 'snapshots', '[]')) }

h = Host.new
# 1) Bos modelden 20 kayit
Sketchup.reset!
20.times { |i| h.curr = [{ uid: "U#{i}" }]; h.revision_create_snapshot(nil) }
s = snaps.()
t.('20 kayıt sonrası adet', s.size, 20)
t.('20 kayıt adları Rev.01..Rev.20', s.map { |x| x['revision'] }, (1..20).map { |n| format('Rev.%02d', n) })
t.('20. kayıtta keşif (boq) var', s.last.key?('boq'), true)
w20 = Sketchup.active_model.writes
obs.('20 kayıt için set_attribute çağrısı (kayıt başına)', w20 / 20.0)

# 2) 21. kayit
h.curr = [{ uid: 'U20' }]; h.revision_create_snapshot(nil)
s = snaps.()
obs.('21. kayıt sonrası adet', s.size)
obs.('ilk kayıt adı (Rev.01 silindi mi)', s.first['revision'])
obs.('yeni kaydın adı', s.last['revision'])
obs.('yeni kayıtta boq anahtarı', s.last.key?('boq'))
obs.('last_revision', Sketchup.active_model.get_attribute('MAG_MST_RevisionLog', 'last_revision'))
rev_names = s.map { |x| x['revision'] }
obs.('yinelenen ad sayısı', rev_names.size - rev_names.uniq.size)

# 3) 22. kayit
h.curr = [{ uid: 'U21' }]; h.revision_create_snapshot(nil)
s = snaps.()
obs.('22. kayıt sonrası adlar (son 3)', s.last(3).map { |x| x['revision'] })
obs.('22. kayıtta boq', s.last.key?('boq'))
obs.('ilk kayıt adı', s.first['revision'])
names = s.map { |x| x['revision'] }
obs.('yinelenen adlar', names.group_by(&:itself).select { |_, v| v.size > 1 }.keys)

# Beklenen (kural: revizyon yalniz ileri yazilir, ad tekil olur) karsilastirmasi
t.('21. kayıt: Rev.01 korunur (geçmiş silinmez)', snaps.().any? { |x| x['revision'] == 'Rev.01' }, true)
t.('22. kayıt: ad tekil (Rev.22)', snaps.().last['revision'], 'Rev.22')
t.('22. kayıtta keşif (boq) eklenir', snaps.().last.key?('boq'), true)
puts "UI mesajları: #{$msgs.inspect}"
puts "#{$ok} geçti, #{$bad} kaldı"
exit($bad.zero? ? 0 : 1)
