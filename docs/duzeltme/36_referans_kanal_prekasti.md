# 36 Referans notu — kanal prekastı revizyonu (ana oturum, 09.11.2026)
Kaynak: OneDrive\Masaüstü\CLAUDE\kanal prekastı — 2 görsel (png) + ekran kaydı (mp4, 34,8 s, ses kanalı sessiz −91 dB). Video kareleri ffmpeg sahne seçimiyle (12 kare) çıkarıldı ve okundu.

## Görseller
1. Dört kesit (ölçüsüz): tek duvarlı L; üç duvarlı (çift gözlü) kanal; kalın tabanlı L; yüzü kademeli plak.
2. Mevcut "Kanal Geometrisi" ekranı (U): iç genişlik 0,80, iç derinlik 0,60, taban 0,20, yan duvar 0,20 m; eleman boyu Otomatik; sol / sağ oturma payı 0,15 m; Kot Bilgileri "Referans: BK Üst Kot"; statik kesit önizleme (dış 1,20 m).

## Video (kullanıcının notu + tasarım örneği; "Etkileşimli tasarım örneği — henüz MST koduna uygulanmadı")
- Kullanıcı notu: "… VAR YOK YAPARIZ YA DA ÜÇ ÇIKINTILI BİR ŞEKİL OLACAK ŞEKİLDE YAPARIZ VE VAR YOK SEÇENEĞİNİ TIKLARIZ, GENİŞLİKLERİ, YÜKSEKLİKLERİ VE KENARDAN OFSETLERİ GİRİNCE 4 ÇEŞİTTE YAPILIR."
- Önerilen sistem: **tek parametrik kesit, üç bağımsız çıkıntı**. Taban: Toplam genişlik (m), Taban kalınlığı (m). Çıkıntılar Sol / Orta / Sağ: her birinde Var (onay), Genişlik (m), Yükseklik (m; taban üstünden), ofset (Sol: soldan, Orta: soldan, Sağ: sağdan). Pasif çıkıntının alanları gri ama değer saklı.
- Örnek düğmeler: L kesit, U kesit, Ofsetli, Üç çıkıntılı — "yalnızca Var/Yok kombinasyonlarını değiştirir; genişlik, yükseklik ve ofset değerleri korunur".
- Canlı kesit önizlemesi (enine kesit, toplam genişlik ölçüsü), Kesit alanı (m²), 1 m boy için beton (m³). Örnek değerler (tasarım örneği, MST varsayılanı değil): toplam 1,80, taban 0,20; sol 0,20 × 0,60 ofset 0; orta 0,15 × 0,30 soldan 0,75; sağ 0,20 × 0,60 ofset 0. Görülen alanlar: U 0,600; orta + sağ 0,525; yalnız sağ 0,480; geniş sağ çıkıntı (0,90 × 0,60) 0,900 m² — 1,80 × 0,20 + Σ(genişlik × yükseklik) ile tutarlı.
- "MST açısından avantajı" maddeleri: mevcut Kanal Prekast modülü ve komutu korunur; üç çıkıntının genişliği, yüksekliği, kenardan ofseti ayrı belirlenir; sağ ve sol çıkıntılar dış kenara bitişik olmak zorunda değildir; kullanılmayan çıkıntılar geometriden çıkarılır, girilen ölçüler saklanır; kesit değişiminde beton hacmi, kalıp alanı, donatı ve BK oturma ilişkileri yeniden hesaplanır; eski U kanal kayıtları yeni sisteme uyumlu şekilde (okunur).

## Kullanıcı kararları (09.11.2026)
- Video incelemesi için ffmpeg kurulumu (kullanıcı kurdu).
- Varsayılan ölçüler mevcut U kanala benzer: iç 0,80 / derinlik 0,60 / taban 0,20 / duvar 0,20 (dış 1,20), oturma 0,15.
- Ayrı "kalın tabanlı L" tipi (PK-L2) yok: L'de duvar ve taban ölçüsü zaten serbest.
- Hat mst_tb1 (0.51.5), teslim TESLIM_10, tek entegre RBZ.
- Ana oturum yorumu (kullanıcı onayı bekliyor): dört şekil = tek parametrik kesitin ön ayarları (L: tek yan çıkıntı; U: sol + sağ; çift gözlü: üç çıkıntı; kademeli plak: taban + geniş tek çıkıntı).
