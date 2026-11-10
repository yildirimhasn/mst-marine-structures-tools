# KQ5 (ADR-0515-K3 P5, docs/duzeltme/41 — kullanıcı kararı 1; 10.11.2026) — kullanıcı düzeyi PK kütüphanesi dosyası
#  (%APPDATA%\MarineStructuresTools\PKLibrary\pk_types.json), elle dışa ver / içe al (Ruby, pk_library_file.rb):
#  pk_lib_file_list (yok / bos / tamam / bozuk, modelde: yok / ayni / kod_cakisma / geom_ayni_kod_farkli), pk_lib_file_export
#  (ekle / güncelle (rev büyükse) / atla, aynı kod farklı geom_sig birleşmez, bozuk dosyaya yazılmaz, atomik yazım + .bak, model değişmez),
#  pk_lib_file_import (ekle / atla, tek normal işlem "MST PK Tiplerini İçe Al", hata → abort, aynı geometri farklı kod eklenmez),
#  bilinmeyen alan korunumu, v2 dosyada salt okuma. Dosya yolu geçici klasöre enjekte edilir (mst_pkf_base=); gerçek APPDATA'ya dokunulmaz.
# Gerçek main.rb (golden SketchUp sahtesi). Kanıt düzeyi: sahte nesne. SketchUp içinde tek Ctrl+Z, HtmlDialog ↔ JS akışı KANITLANMAZ.
# Kullanim: ruby tools/test/kq5_pk_lib_file.rb <src/marine_structures_tools>
require 'stringio'
require 'json'
require 'tmpdir'
require 'fileutils'
require_relative '../golden/sketchup_stub'
dir = ARGV[0] or abort 'kullanim: ruby tools/test/kq5_pk_lib_file.rb <marine_structures_tools klasoru>'
DIR = File.expand_path(dir)
$model = Sketchup::Model.new
$stderr_keep = $stderr; $stderr = StringIO.new
require File.join(DIR, 'main.rb')
$stderr = $stderr_keep
M = MAG::MarineStructuresTools
D = 'MAG_MarineStructures'.freeze unless defined?(D)

$ok = 0; $bad = 0
def t(label, got, exp)
  g = got == exp
  g ? $ok += 1 : $bad += 1
  puts "#{g ? 'GEÇTİ' : 'KALDI'}  #{label}: #{got.inspect[0, 300]} (beklenen #{exp.inspect[0, 300]})"
end

HAVE = %i[mst_pk_lib_file_list mst_pk_lib_file_export mst_pk_lib_file_import mst_pkf_path mst_pkf_base=].all? { |s| M.respond_to?(s) }
t('0.1 P5 işlevleri tanımlı', HAVE, true)
msrc = File.binread(File.join(DIR, 'main.rb')).force_encoding('UTF-8')
t('0.2 callback kayıtları', %w[pk_lib_file_list pk_lib_file_export pk_lib_file_import].map { |c| msrc.include?("add_action_callback('#{c}')") }, [true, true, true])
t('0.3 main.rb yükler (require_relative)', msrc.include?("require_relative 'pk_library_file'"), true)
unless HAVE
  puts "\nKQ5: #{$ok} geçti, #{$bad} kaldı"
  exit 1
end

TMP = Dir.mktmpdir('kq5_')
at_exit { FileUtils.rm_rf(TMP) }
M.mst_pkf_base = TMP
PATH = File.join(TMP, 'MarineStructuresTools', 'PKLibrary', 'pk_types.json')
t('0.4 yol enjeksiyonu', M.mst_pkf_path, PATH)

def secj(s); JSON.parse(M.mst_ch_json(s)); end
SEC_L = M.mst_ch_preset(M.mst_ch_default, 'L')
SEC_L13 = M.mst_ch_parse(SEC_L.merge('total_width_m' => 1.3))
SEC_L14 = M.mst_ch_parse(SEC_L.merge('total_width_m' => 1.4))
def rec(uid, kod, sec, rev = 1, extra = {})
  { 'uid' => uid, 'family' => 'PK', 'name' => kod, 'title' => "#{kod} adı", 'section' => secj(sec), 'concrete' => 'C30/37',
    'fw_bottom' => false, 'fw_sides' => true, 'fw_inner' => true, 'fw_ends' => false, 'fw_ledge' => true,
    'seat_left_m' => 0.15, 'seat_right_m' => 0.15, 'geom_sig' => M.mst_pk_geom_sig(sec, 0.15, 0.15),
    'created_at' => '2026-11-10T10:00:00+03:00', 'pk_rev' => rev, 'rev_log' => [{ 'rev' => rev, 'at' => '2026-11-10T10:00:00+03:00', 'note' => 'x' }] }.merge(extra)
end
REC_PD = { 'uid' => 'pd1', 'family' => 'PD', 'name' => 'PD-01', 'width' => 1.0, 'height' => 0.3 }.freeze
A = rec('pt_pk_1_1', 'PK-L', SEC_L)
B = rec('pt_pk_2_2', 'PK-L13', SEC_L13)
def model_lib(lib); $model = Sketchup::Model.new; $model.set_attribute(D, 'precast_type_library_json', JSON.generate(lib)); end
def libtxt; $model.get_attribute(D, 'precast_type_library_json', '').to_s; end
def ops; $model.ops.map(&:first); end
def wfile(s); FileUtils.mkdir_p(File.dirname(PATH)); File.binwrite(PATH, s); end
def fdata; JSON.parse(File.binread(PATH).force_encoding('UTF-8')); end
def rm; FileUtils.rm_f([PATH, PATH + '.bak']); end

# ---- 1) liste: yok / bos / bozuk / tamam
model_lib([REC_PD, A]); rm
l = M.mst_pk_lib_file_list($model)
t('1.1 yok', [l['ok'], l['durum'], l['tipler'], l['yol']], [true, 'yok', [], PATH])
wfile('')
t('1.2 boş dosya', M.mst_pk_lib_file_list($model).values_at('ok', 'durum', 'tipler'), [true, 'bos', []])
wfile(JSON.generate('format' => 'mst_pk_types', 'v' => 1, 'tipler' => []))
t('1.3 boş liste', M.mst_pk_lib_file_list($model)['durum'], 'bos')
['{bozuk', '[]', JSON.generate('format' => 'baska', 'v' => 1, 'tipler' => []), JSON.generate('format' => 'mst_pk_types', 'v' => 1, 'tipler' => 5),
 JSON.generate('format' => 'mst_pk_types', 'v' => 'x', 'tipler' => [])].each_with_index do |s, i|
  wfile(s)
  l = M.mst_pk_lib_file_list($model)
  t("1.4.#{i} bozuk (#{s[0, 20]})", [l['ok'], l['durum'], l['tipler'], l['neden'].to_s.empty?, File.binread(PATH) == s], [false, 'bozuk', [], false, true])
end
# tamam + modelde sınıfları
fa = rec('pt_pk_1_1', 'PK-L', SEC_L)                       # aynı uid → ayni
fb = rec('pt_pk_9_9', 'pk-l', SEC_L13)                     # aynı kod (harf duyarsız) farklı geom → kod_cakisma
fc = rec('pt_pk_8_8', 'PK-X', SEC_L)                       # farklı kod aynı geom → geom_ayni_kod_farkli
fd = rec('pt_pk_7_7', 'PK-Y', SEC_L14)                     # yok
wfile(JSON.generate('format' => 'mst_pk_types', 'v' => 1, 'tipler' => [fa, fb, fc, fd]))
l = M.mst_pk_lib_file_list($model)
t('1.5 tamam', [l['ok'], l['durum']], [true, 'tamam'])
t('1.6 modelde sınıfları', l['tipler'].map { |x| x['modelde'] }, %w[ayni kod_cakisma geom_ayni_kod_farkli yok])
t('1.6b modeldeki_kod', l['tipler'].map { |x| x['modeldeki_kod'] }, ['PK-L', 'PK-L', 'PK-L', nil])
t('1.7 alanlar', l['tipler'][3].keys.sort, %w[ad created_at geom_sig kod modelde modeldeki_kod rev section uid])
t('1.8 alan değerleri', l['tipler'][3].values_at('uid', 'kod', 'ad', 'rev', 'geom_sig'), ['pt_pk_7_7', 'PK-Y', 'PK-Y adı', 1, fd['geom_sig']])
t('1.9 liste modeli değiştirmez', ops, [])

# ---- 2) dışa ver
model_lib([REC_PD, A, B]); rm
FileUtils.rm_rf(File.join(TMP, 'MarineStructuresTools'))
t('2.0 klasör yok', File.directory?(File.dirname(PATH)), false)
r = M.mst_pk_lib_file_export({ 'uids' => %w[pt_pk_1_1 pt_pk_2_2 yokuid pd1] }, $model)
t('2.0b ilk dışa vermede klasör + dosya oluşturuldu', [File.directory?(File.dirname(PATH)), File.file?(PATH)], [true, true])
t('2.1 yeni dosya: eklenen 2', r.values_at('ok', 'eklenen', 'guncellenen', 'yol'), [true, 2, 0, PATH])
t('2.2 atlanan (bulunamadı / PK değil)', r['atlanan'].map { |x| x['kod'] }, %w[yokuid PD-01])
d = fdata
t('2.3 dosya biçimi', [d['format'], d['v'], d['tipler'].map { |x| x['uid'] }], ['mst_pk_types', 1, %w[pt_pk_1_1 pt_pk_2_2]])
t('2.4 kayıt tam kopya', d['tipler'][0], JSON.parse(JSON.generate(A)))
t('2.5 model değişmez (işlem yok)', ops, [])
t('2.6 ilk yazımda .bak yok', File.exist?(PATH + '.bak'), false)
r = M.mst_pk_lib_file_export({ 'uids' => %w[pt_pk_1_1] }, $model)
t('2.7 aynı rev → atla, yazım yok', [r['ok'], r['eklenen'], r['guncellenen'], r['atlanan'].size, File.exist?(PATH + '.bak')], [true, 0, 0, 1, false])
before = File.binread(PATH)
model_lib([REC_PD, A.merge('pk_rev' => 2, 'title' => 'yeni ad'), B])
r = M.mst_pk_lib_file_export({ 'uids' => %w[pt_pk_1_1] }, $model)
t('2.8 rev büyük → güncelle', [r['ok'], r['guncellenen'], fdata['tipler'][0]['title'], fdata['tipler'][0]['pk_rev']], [true, 1, 'yeni ad', 2])
t('2.9 .bak önceki içerik', File.binread(PATH + '.bak'), before)
model_lib([REC_PD, A.merge('pk_rev' => 1)])
r = M.mst_pk_lib_file_export({ 'uids' => %w[pt_pk_1_1] }, $model)
t('2.10 model rev küçük → atla', [r['guncellenen'], fdata['tipler'][0]['pk_rev'], r['atlanan'][0]['neden'].include?('rev')], [0, 2, true])
# yalnız modelde KAYITLI tip okunur: istekteki kutuphane (kaydedilmemiş JS listesi) dikkate alınmaz
r = M.mst_pk_lib_file_export({ 'uids' => %w[pt_pk_4_4], 'kutuphane' => [rec('pt_pk_4_4', 'PK-Z', SEC_L14)] }, $model)
t('2.10b kaydedilmemiş tip dışa verilmez', [r['eklenen'], r['atlanan'].map { |x| x['kod'] }, fdata['tipler'].map { |x| x['uid'] }.include?('pt_pk_4_4')], [0, ['pt_pk_4_4'], false])
# aynı kod farklı geom_sig → atla, birleştirme yok
model_lib([REC_PD, rec('pt_pk_5_5', 'pk-l', SEC_L14)])
before = File.binread(PATH)
r = M.mst_pk_lib_file_export({ 'uids' => %w[pt_pk_5_5] }, $model)
t('2.11 kod çakışması atla', [r['ok'], r['eklenen'], r['atlanan'].map { |x| x['kod'] }, File.binread(PATH) == before], [true, 0, ['pk-l'], true])
# bozuk dosya → yazma, ok=false
wfile('{bozuk'); model_lib([REC_PD, A])
r = M.mst_pk_lib_file_export({ 'uids' => %w[pt_pk_1_1] }, $model)
t('2.12 bozuk dosyaya yazılmaz', [r['ok'], r['neden'].to_s.empty?, File.binread(PATH)], [false, false, '{bozuk'])
# bozuk model kütüphanesi
rm; $model = Sketchup::Model.new; $model.set_attribute(D, 'precast_type_library_json', '{x')
r = M.mst_pk_lib_file_export({ 'uids' => %w[pt_pk_1_1] }, $model)
t('2.13 bozuk model kütüphanesi → ok=false, dosya yok', [r['ok'], File.exist?(PATH)], [false, false])
# atomik: yarıda hata (son rename) → eski dosya sağlam, .bak var, geçici dosya kalmaz
model_lib([REC_PD, A, B]); rm
M.mst_pk_lib_file_export({ 'uids' => %w[pt_pk_1_1] }, $model)
before = File.binread(PATH)
class << File
  alias_method :kq5_rename, :rename
  def rename(a, b); raise 'sahte yazım hatası' if $kq5_fail && b == PATH; kq5_rename(a, b); end
end
$kq5_fail = true
r = M.mst_pk_lib_file_export({ 'uids' => %w[pt_pk_2_2] }, $model)
$kq5_fail = false
t('2.14 yarıda hata → ok=false', [r['ok'], r['neden'].to_s.empty?], [false, false])
t('2.15 eski dosya sağlam', File.binread(PATH), before)
t('2.16 .bak = eski içerik', File.binread(PATH + '.bak'), before)
t('2.17 geçici dosya kalmadı', Dir[File.join(File.dirname(PATH), '*.tmp')], [])

# ---- 3) bilinmeyen alan korunumu (üst düzey + kayıt)
rm
wfile(JSON.generate('format' => 'mst_pk_types', 'v' => 1, 'not' => 'kullanıcı', 'tipler' => [rec('pt_pk_1_1', 'PK-L', SEC_L, 1, 'gelecek_alan' => { 'a' => 1 })]))
model_lib([REC_PD, A.merge('pk_rev' => 3), B])
r = M.mst_pk_lib_file_export({ 'uids' => %w[pt_pk_1_1 pt_pk_2_2] }, $model)
d = fdata
t('3.1 güncelle + ekle', [r['guncellenen'], r['eklenen']], [1, 1])
t('3.2 üst düzey bilinmeyen alan', d['not'], 'kullanıcı')
t('3.3 kayıt bilinmeyen alan', [d['tipler'][0]['gelecek_alan'], d['tipler'][0]['pk_rev']], [{ 'a' => 1 }, 3])

# ---- 4) v2 dosya: salt okuma
v2 = JSON.generate('format' => 'mst_pk_types', 'v' => 2, 'tipler' => [fd])
wfile(v2)
l = M.mst_pk_lib_file_list($model)
t('4.1 v2 listelenir + uyarı', [l['ok'], l['durum'], l['tipler'].size, l['neden'].to_s.empty?], [true, 'tamam', 1, false])
r = M.mst_pk_lib_file_export({ 'uids' => %w[pt_pk_1_1] }, $model)
t('4.2 v2 dışa ver yazmaz', [r['ok'], File.binread(PATH) == v2.b], [false, true])
r = M.mst_pk_lib_file_import({ 'uids' => %w[pt_pk_7_7] }, $model)
t('4.3 v2 içe al yapılmaz', [r['ok'], ops], [false, []])

# ---- 5) içe al
wfile(JSON.generate('format' => 'mst_pk_types', 'v' => 1, 'tipler' => [fa, fb, fc, fd, rec('pt_pk_6_6', 'PK-Y2', SEC_L14, 1, 'x_alan' => 7)]))
model_lib([REC_PD, A]); lib0 = libtxt
r = M.mst_pk_lib_file_import({ 'uids' => %w[pt_pk_1_1 pt_pk_9_9 pt_pk_8_8 pt_pk_7_7 yok] }, $model)
t('5.1 eklenen 1 (PK-Y)', [r['ok'], r['eklenen']], [true, 1])
t('5.2 atlanan kodlar', r['atlanan'].map { |x| x['kod'] }, %w[PK-L pk-l PK-X yok])
t('5.3 aynı geom farklı kod → mevcut tipi kullanın', r['atlanan'][2]['neden'].include?('PK-L'), true)
t('5.4 tek normal işlem', [ops, $model.ops[0][1]], [%i[start commit], 'MST PK Tiplerini İçe Al'])
ml = JSON.parse(libtxt)
t('5.5 modele eklendi (kayıt aynen)', [ml.map { |x| x['uid'] }, ml[2]], [%w[pd1 pt_pk_1_1 pt_pk_7_7], JSON.parse(JSON.generate(fd))])
t('5.6 yanıt kutuphane_json', r['kutuphane_json'], libtxt)
# PK-Y2: aynı geometri, şimdi modelde PK-Y var → eklenmez
$model.ops.clear
r = M.mst_pk_lib_file_import({ 'uids' => %w[pt_pk_6_6] }, $model)
t('5.7 aynı geom farklı kod (az önce eklenen) atla, işlem yok', [r['ok'], r['eklenen'], r['atlanan'][0]['neden'].include?('PK-Y'), ops], [true, 0, true, []])
# rev büyük dosya kaydı → güncellenmez, yalnız bildirilir
wfile(JSON.generate('format' => 'mst_pk_types', 'v' => 1, 'tipler' => [fa.merge('pk_rev' => 5)]))
r = M.mst_pk_lib_file_import({ 'uids' => %w[pt_pk_1_1] }, $model)
t('5.8 rev büyük → güncelleme yok, bildir', [r['eklenen'], r['atlanan'][0]['neden'].include?('5'), JSON.parse(libtxt).find { |x| x['uid'] == 'pt_pk_1_1' }['pk_rev']], [0, true, 1])
# kutuphane (JS tam liste) esas alınır
model_lib([REC_PD]); wfile(JSON.generate('format' => 'mst_pk_types', 'v' => 1, 'tipler' => [fd]))
r = M.mst_pk_lib_file_import({ 'uids' => %w[pt_pk_7_7], 'kutuphane' => [REC_PD, A] }, $model)
t('5.9 kutuphane listesi esas', JSON.parse(libtxt).map { |x| x['uid'] }, %w[pd1 pt_pk_1_1 pt_pk_7_7])
# bozuk dosya / yok
wfile('{bozuk'); model_lib([REC_PD]); lib0 = libtxt
r = M.mst_pk_lib_file_import({ 'uids' => %w[pt_pk_7_7] }, $model)
t('5.10 bozuk dosya → ok=false, model aynı', [r['ok'], libtxt == lib0, ops, File.binread(PATH)], [false, true, [], '{bozuk'])
rm
r = M.mst_pk_lib_file_import({ 'uids' => %w[pt_pk_7_7] }, $model)
t('5.11 dosya yok → ok=false', [r['ok'], ops], [false, []])
# hata → abort, kütüphane değişmez
wfile(JSON.generate('format' => 'mst_pk_types', 'v' => 1, 'tipler' => [fd]))
model_lib([REC_PD]); lib0 = libtxt
class Sketchup::Model
  alias_method :kq5_set, :set_attribute
  def set_attribute(d, k, v); raise 'sahte yazım hatası' if $kq5_sfail && k == 'precast_type_library_json'; kq5_set(d, k, v); end
end
$kq5_sfail = true
r = M.mst_pk_lib_file_import({ 'uids' => %w[pt_pk_7_7] }, $model)
$kq5_sfail = false
t('5.12 hata → abort', [r['ok'], ops, libtxt == lib0], [false, %i[start abort], true])
# bozuk model kütüphanesi → işlem açılmaz
$model = Sketchup::Model.new; $model.set_attribute(D, 'precast_type_library_json', '{x')
r = M.mst_pk_lib_file_import({ 'uids' => %w[pt_pk_7_7] }, $model)
t('5.13 bozuk model kütüphanesi', [r['ok'], ops, libtxt], [false, [], '{x'])
# içe al dosyaya dokunmaz
t('5.14 içe al dosyayı değiştirmez', fdata['tipler'].map { |x| x['uid'] }, %w[pt_pk_7_7])

# ---- 6) gönderim (callback sarmalayıcıları)
class FakeDlg; attr_reader :js; def initialize; @js = []; end; def execute_script(s); @js << s; end; end
dg = FakeDlg.new
M.mst_pk_send_lib_file_list(dg)
M.mst_pk_send_lib_file_export(dg, '{bozuk')
M.mst_pk_send_lib_file_import(dg, JSON.generate('uids' => []))
t('6.1 yanıt işlevleri', dg.js.map { |s| s[/mstPkLibFile\w*/] }, %w[mstPkLibFile mstPkLibFileExported mstPkLibFileImported])
t('6.2 okunamayan istek → ok:false', dg.js[1].include?('"ok":false'), true)

puts "\nKQ5: #{$ok} geçti, #{$bad} kaldı"
exit($bad.zero? ? 0 : 1)
