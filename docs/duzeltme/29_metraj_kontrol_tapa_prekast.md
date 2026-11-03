# 29 Metraj kontrolü — ee18c79 tapa + prekast sınıf pozu (mst-metraj-kontrol, 04.11.2026; salt okuma, komut çalıştırmadı)
Dayanak: kullanıcı talimatı 03–04.11.2026 (tapa manipülasyona + "ÇEŞİTLİ DEMİR İMALATI VE YERİNE KONULMASI | kg"; prekast sınıfına göre kütüphane pozu, sınıfsız → "PREKAST BETONU", poz yoksa kullanıcı oluşturur).
Ajan notu: git çalıştıramadı; çalışma dosyalarını okudu. Golden dosyası o anda `HEAD-848ff7c-dirty` adlıydı (ana oturum temiz ağaçta `2cc5c29` ile yeniden aldı: aynı 10 fark).

## Bağımsız beklenen hesap
- Tapa (fikstür P1): dp = 1,016 − 2·0,016 − 2·0,010 = 0,964 m; π/4·0,964²·0,012·7850 = **68,753 kg**; manipülasyon +0,068753 t. Golden: PILE_PLUG 68,753506 kg, PILE_MANIP 54,999846 → 55,068599 t — tutuyor.
- Manipülasyon = PILE_STEEL 54,807723 + PILE_RINGS 0,192123 + tapa 0,068754 = 55,068599 t. PILE_STEEL/PILE_RINGS tapayı almıyor (değişmedi).
- Tapa PILE_MANIP ve PILE_PLUG'da: talimat gereği ayrı iş kalemleri (çift sayım değil).
- Kazık "ayrı" kipi: PILE_MANIP grupları r[12] (tapa dahil), grup toplamı = kaynak. PILE_PLUG gruplanmaz.
- Prekast: PRECAST_C35_45 9,0 + PRECAST_CONCRETE#C30/37 1,5 = 10,5 = PRECAST_INSTALL; FORMWORK_PRECAST 36 değişmedi. Bir eleman iki satıra (miktar, izleme, hakediş) giremiyor. boq2_split_rows prekastı etkilemiyor.

## Bulgular ve durum
| No | Önem | Bulgu | Durum |
|---|---|---|---|
| 1 | orta | "C30/37" / "C 30/37" / "c30/37" ayrı sınıf satırı (aynı poz koduyla birden çok satır) | **düzeltildi 2cc5c29**: `mst_precast_class_key` (C35/45 denetimiyle aynı: büyük harf, boşluksuz); izleme aynı küme (v4 R2) |
| 2 | orta | Aynı poza giden iki satırda kütüphane arşivine (`capture`) son satırın miktarı yazılır | 1 ile kaynağı kapandı; ayrıca elle bağlı poz otomatik seçilmez (2cc5c29, v4 R5). PRECAST_C35_45 şablon satırı ile sınıfsız satır farklı pozlara gider |
| 3 | düşük | Golden fikstüründe sınıf yazım farkı / sınıfsız / pozu olmayan sınıf yok | sahte nesne testi v4 kapsıyor (P2, P3, R2); golden fikstürü değiştirilmedi |
| 4 | bilgi | Pozu bulunamayan satır arşive yazılmaz, keşifte fiyatsız kalır | talimatla uyumlu |
