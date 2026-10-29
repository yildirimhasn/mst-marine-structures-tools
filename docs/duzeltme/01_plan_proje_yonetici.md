# 01 Düzeltme planı — mst-proje-yonetici (29.10.2026)

Hedef: denetim raporundaki doğrulanan hataları gidermek, eksikleri tamamlamak, uygulanabilir iyileştirmeleri yapmak; kuruluma hazır revize RBZ.
Sürüm: VERSION '0.51.5', MST_BUILD 'v0.51.5 TB1 FIX1', RBZ `MST_v0.51.5_TB1_FIX1_TEST.rbz`.
Runner: kurulu mst_tb1_integration_runner 1.1.0 sürüm (0.51.4) ve SHA manifest kontrollerinde beklenen şekilde başarısız olacak. Ana oturum kararı: seçenek (b) — runner için ayrı RBZ üretilmez (kullanıcı istemedi), kabul listesine not düşülür; yöntem adı kontrolleri korunur.

## Genel kurallar
- G1: tek kaynaklı bulgular (K34, K51-K54, K56, K58, K60-K63, 3. bölüm riskleri) düzeltmeden önce sahte nesne testiyle yeniden üretilir veya satırlarla teyit edilir; üretilemezse "açık kaldı", kod değişmez.
- G2: metrajı değiştirenler (K36, K50, K57, K58, K22, R6, K55, eğik kazık açıklığı, K53, K42) için test-paketleme 0.51.4 ilk commit ↔ yeni sürüm sahte fikstür CSV karşılaştırması yapar.
- G3: yazılıp okunmayan *_error bayrakları (K16-K18, K21, K59, K60) Model Kontrolü'nde uyarı; metraj sessizce 0'a düşmez.
- G4: yeni attribute anahtarları yalnız eklenir; runner'ın aradığı yöntem adları değişmez.

## Triage
DÜZELT: K01 (C), K02, K03, K04, K05, K19, K20, K26, K27, K35, K36, K50, K55, K57, K59 (A); K06, K07, K09, K11, K12, K13, K14, K15, K16-K18, K21, K23(uyarı), K28, K29, K51*, K53*, K56*, K61*, K62*, K63* (B); K08, K24, K25, K31, K37, K40, K41, K42, K45, K48(yalnız Türkçe karakter) (C); K47 (D); 08-R6*, eğik kazık elips*, 08-R3 yedek yol*, DXF birim, donatı revizyon last(10), 08-R1 uyarı. (* = G1 önce)
Kısmi/ara çözüm: K33 (poz eşlenmemiş beton bilgi satırı; fiyatsız, toplam dışı; varsayılan sınıf değişmez), K34 (görünürlük), K38 (icmal≠cetvel uyarısı), K39 (tapa pozsuz bilgi satırı), K10 (BK'sı değişen VK/BBK uyarısı), K52 (uyarı), K54 (uyarı), K22 aşama 1 (X'e paralel değilse açık Türkçe hata; aşama 2 yerel eksen hesabı mimar eksen kaydı bulursa).
UYGULANMAZ: K30 (ölü kod silme yasak), K32 (onaylı görünüm; inset'li perde açılmıyor), K43 (kullanıcı kararı), K44 (dalgakıran tanım belgesi yok), K49 ve TIN/boq_mapping O(n²) (ölçümsüz optimizasyon yok), derz harcı ve 08-R4 (belge), menfez-gömülme kesişimi (ertele, uyarı önerisi).
K46: önce oku/test et; hata yoksa değişiklik yok. mst_dr_clear! pursantajı: öğe türüne ait ayar anahtarı varsa kullanılır, yoksa belge gerekli.

## Birleşik çözümler
R-1 revizyon (K02+K03+K26+donatı last(10)): numara=max Rev.NN+1; otomatik silme yok; snapshot+keşif tek işlem; rescue'da abort+Türkçe mesaj; fark yoksa revizyon oluşmaz; önceki dönem kayıtları değişmez.
R-2 kimlik (K04+K05): yalnız eksik anahtar; görüntüleme yazmaz; değişiklik yoksa işlem açılmaz; önceden ezilmiş değerler geri getirilemez (bilinen sınır).
R-3 paylaşılan definition (K09+K58): count_instances>1 ise "yalnız bunu ayır / iptal" sorusu; ayırda make_unique, instance attribute ve element_uid korunur.
R-4 bozuk JSON (K19+K20+K27+K55): bozuk/boş/geçerli ayrımı; bozukta yazma reddi + Türkçe mesaj; atomik dosya yazımı.
R-5 UID (K06): mimar kararı (kopyaya yeni UID, copied_from_uid; ilerleme "devralındı, onaysız"; tretuvar bağında asıl öğe tercihi).
R-6 hakediş anahtarı (K35): kesit etiketine dayalı anahtar; eski code-NN kayıtları için geçiş; önceki dönem miktarları yeniden hesaplanmaz.

## Dosya sahipliği
A (uygulayıcı): main.rb boq_quantities 3500-3600, revizyon 9240-9360, 6377-6403, 8255-8270, 2500-2530, 1433-1445, 2460, 12000-12130, 9160-9185; qto_workspace, boq_pro, accessories, mst_dwg_rebar, mst_dx_rebar, mst_pc_rebar, mst_dr_auto, mst_rebar_tools, boq_mapping.
B (uygulayıcı): main.rb Undo noktaları, 4268-4440, 11130-11410, 2190-2250, 5000-6010; dependency_rebuild, mst_v50_beams, mst_v50_piles, mst_v50_misc, mst_schedule, rockfill_live, pile_manufacturing (K37 hariç).
C (arayüz): ui.html, embed.rb, diğer html/js; main.rb 9046, 9571, 10133, 10288 callback/metin satırları; pile_manufacturing.rb:226-241.
D (dokümantasyon): README, RELEASE_UI9, boq_library.rb:302, sürüm sabitleri, docs/.
Yeniden tanım riski: progress_* düzeltmeleri boq_pro.rb'deki etkin tanıma yapılır.

## Açık belgeler
Poz listesi/sınıf eşlemesi (K33), fiyat farkı kuralı (K38), tapa ve derz harcı tarifi (K39), dalgakıran tanımı (K44), paftada ankraj (R4), prekast pursantajı. K43 ve K48 terim listesi kullanıcı kararı.
