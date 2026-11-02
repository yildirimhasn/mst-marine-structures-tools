# Parti G-a / G2 (kod inceleme #5): mst_copy_dicts! sahiplik devri (Group <-> Component cevirme).
# ADR 13 §G2: kayit varsa kayitli PID = kaynak PID; kayit yoksa UID icindeki PID = kaynak PID; aksi halde yazilmaz.
# Kullanim: ruby tools/test/g2_owner_transfer.rb <src/marine_structures_tools>
require_relative 'a1_helper'
main = A1.src('main.rb')
A1.load(Host, main, 'def mst_copy_dicts!(')
h = Host.new
cp = lambda do |pid, attrs, to_pid = 9|
  f = FakeEnt.new(pid, attrs); to = FakeEnt.new(to_pid); h.mst_copy_dicts!(f, to); to
end

a1_reset!
# X: asıl öğe çevriliyor (kayıtlı sahip = kaynak)
t('X asıl (kayıtlı sahip) çevrildi → sahiplik yeni varlığa', cp.(5, 'element_uid' => 'MST-5-1', 'uid_owner_pid' => 5).a('uid_owner_pid'), 9)
# Y: kopya çevriliyor (kayıtlı sahip başka PID)
t('Y kopya (kayıtlı sahip 3) çevrildi → sahiplik taşınmaz (3 kalır)', cp.(5, 'element_uid' => 'MST-3-1', 'uid_owner_pid' => 3).a('uid_owner_pid'), 3)
# kayıt yok
t('kayıt yok, UID içindeki PID = kaynak → yeni varlığa', cp.(5, 'element_uid' => 'MST-5-1700000000').a('uid_owner_pid'), 9)
t('kayıt yok, UID içindeki PID ≠ kaynak (kayıtsız kopya) → yazılmaz', cp.(5, 'element_uid' => 'MST-3-1').a('uid_owner_pid'), nil)
t('kayıt yok, E-biçimli UID (PRC-E00012) ayrıştırılamaz → yazılmaz', cp.(5, 'element_uid' => 'PRC-E00012').a('uid_owner_pid'), nil)
t('kayıt yok, onarım UID (MST-5-…-R) = kaynak → yeni varlığa', cp.(5, 'element_uid' => 'MST-5-1793600000-R').a('uid_owner_pid'), 9)
t('UID boş → yazılmaz', cp.(5, 'element_uid' => '').a('uid_owner_pid'), nil)
# Y→X ardışık çevirme: Group(5, asıl) → Component(9) → Group(12)
a = cp.(5, 'element_uid' => 'MST-5-1', 'uid_owner_pid' => 5)
b = FakeEnt.new(12); h.mst_copy_dicts!(a, b)
t('ardışık çevirme: asıl öğe sahipliği her adımda yeni varlıkta (12)', b.a('uid_owner_pid'), 12)
k = cp.(6, 'element_uid' => 'MST-5-1')        # kayıtsız kopya (PID 6) Component'e çevrildi
k2 = FakeEnt.new(13); h.mst_copy_dicts!(k, k2)
t('ardışık çevirme: kayıtsız kopya hiçbir adımda sahip olmaz', [k.a('uid_owner_pid'), k2.a('uid_owner_pid')], [nil, nil])
t('öznitelikler kopyalanır (element_uid)', k2.a('element_uid'), 'MST-5-1')
a1_finish
