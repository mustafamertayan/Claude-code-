# Kültürİz

<img src="assets/logo.jpg" alt="KültürİZ logosu" width="200">

Gezilen tarihi yerlerin paylaşıldığı, mobil öncelikli bir web uygulaması (sürüm 1.0 E).

## Neler çalışıyor

- **Giriş ekranı:** Arka planda Leaflet ile gösterilen fiziki dünya haritası (NASA Blue Marble görüntüsünden üretildi), ortada Kültürİz yazısı, "Kayıt Ol" ve "Giriş Yap" butonları, sağ altta "1.0 E".
- **Kayıt / giriş penceresi:** Ad soyad, e-posta ve şifre ile kayıt; e-posta ve şifre ile giriş; şifremi unuttum (e-postayla yeni şifre); altında "Google ile Giriş Yap" butonu.
- **Ana ekran:** Sol üstte menü, sağ üstte Ayarlar (tema, çıkış).
- **Gönderiler:** Gerçek fotoğraflar ve videolar. Beğen (çift dokunuşla da), yorum yap, gönder, kaydet.
- **Gönderi sayfası:** Fotoğraflar ve videolar, mekânın açıklaması ve tarihçesi, Google Haritalar'da tam konumu, benzer mekânların haritası ve listesi, yorumlar.

### Menü
- **+ Paylaş:** Fotoğraf ve video seç (en fazla 10; sürükle-bırak ve yapıştır da olur). Mekân adını ve şehri yazarken akıllı öneriler gelir, harf hatalarını tolere eder. Mekân seçilince yeri haritada kendiliğinden işaretlenir. Haritanın üstündeki arama kutusuyla yer aranabilir; haritaya dokunarak ya da "Konumumu kullan" ile de işaretlenebilir. Kendi gönderini silebilirsin.
- **Yönetim (yalnızca yöneticiler):** İstatistikler, tüm gönderiler ve yorumlar (silme), üyeler (kısıtlama, yönetici yapma).
- **Ana Sayfa:** Tüm gönderilerin akışı.
- **Keşfet:** Arama (mekân, şehir, tür), kategori filtreleri, fotoğraf ızgarası ve keşfedilecek mekânlar listesi.
- **Geçmiş:** Görüntülediğin, beğendiğin, kaydettiğin, yorum yaptığın, paylaştığın ve gönderdiğin her şey gün gün; türe göre filtre ve geçmişi temizleme.
- **Haritalar:** Bütün gönderiler (fotoğraflı işaretler) ve mekânlar tek haritada; Gönderiler / Mekânlar / Kaydedilenler filtresi; işarete dokununca bilgi kartı.
- **Kaydedilenler:** Kaydettiğin gönderiler.
- **Profil:** Profil fotoğrafı, ad soyad ve "Hakkımda" düzenleme; gönderilerin ve kaydettiklerin.
- **En altta:** Profil fotoğrafın, adın, e-postan ve gönderi/beğeni/kayıt sayıların.

## Siteyi herkese açık yapmak (Supabase + GitHub Pages)

Ayar yapılmadan uygulama **önizleme modunda** çalışır: hesaplar ve gönderiler yalnızca o tarayıcıda durur. Herkesin birbirinin gönderisini (fotoğraf ve videolar dahil) görmesi için ücretsiz bir Supabase projesi bağlanır. Supabase; giriş (Google dahil), veritabanı ve dosya deposunu tek yerde, kredi kartı istemeden sunar.

### 1. Supabase projesi aç (5 dakika)
1. https://supabase.com adresinde ücretsiz hesap aç, **New project** ile proje oluştur (ör. `kulturiz`, bölge: Frankfurt).
2. Sol menüden **SQL Editor > New query**: `supabase/kurulum.sql` dosyasının tamamını yapıştır ve **Run**'a bas. Tablolar, güvenlik kuralları ve `medya` adlı fotoğraf/video deposu kurulur.
3. Proje ana sayfasındaki **Connect** düğmesinden (ya da **Project Settings > API Keys**) **Project URL** ile **Publishable key**'i kopyala. Eski projelerde bu anahtarın adı **anon public**'tir; ikisi de olur.
4. `index.html` dosyasının en üstündeki betikte şu iki satırı doldur:
   ```js
   var SUPABASE_URL = "https://xxxxxxxx.supabase.co";
   var SUPABASE_ANON_KEY = "eyJhbGciOi...";
   ```
   Bu iki değer gizli değildir; sitede bulunmaları normaldir. Veriyi veritabanındaki kurallar korur.

### 2. Yönetici (admin) olmak
Siteye **ilk kayıt olan kişi otomatik olarak yönetici olur**. Kurulumdan hemen sonra siteye ilk sen kayıt ol. Menünün en altında **Yönetim** bölümü belirir:
- Tüm gönderileri ve yorumları görür, istediğini silersin.
- Üyeleri listeler (e-postaları yalnızca yöneticiye görünür), bir üyeyi **kısıtlayabilir** (paylaşım ve yorum yapamaz) ya da **yönetici yapabilirsin**.

Gerekirse bir hesabı elle yönetici yapmak için `supabase/kurulum.sql` dosyasının en altındaki komutu kullan.

### 3. E-posta ve Google ile giriş
- **Authentication > URL Configuration**: **Site URL** alanına sitenin adresini yaz (ör. `https://kullaniciadi.github.io/depo-adi/`) ve aynı adresi **Redirect URLs** listesine ekle.
- E-posta ile kayıtta Supabase onay e-postası gönderir; kullanıcı bağlantıya tıkladıktan sonra giriş yapar.
- **Google ile giriş** için: Google Cloud Console'da (https://console.cloud.google.com) bir OAuth istemcisi (Web application) oluştur. "Authorized redirect URIs" alanına Supabase'in **Authentication > Providers > Google** sayfasında yazan geri dönüş adresini ekle. Oradan aldığın Client ID ve Client Secret'ı aynı Supabase sayfasına yapıştırıp Google'ı etkinleştir.

### 4. Yayınlama (GitHub Pages)
1. Depo **Settings > Pages** sayfasında **Source** olarak **Deploy from a branch**'i seç.
2. **Branch** olarak `claude/site-yapimi-596xqf` ve klasör olarak `/ (root)` seç, **Save**'e bas.
3. 1-2 dakika sonra site açılır: `https://kulturiz.github.io/`. Bu dala yapılan her gönderim siteyi kendiliğinden günceller.

Supabase bağlanmadan yayınlanırsa site çalışır ama önizleme modundadır: her ziyaretçinin hesabı ve gönderileri yalnızca kendi tarayıcısında kalır.


### 5. E-posta doğrulama kodu ve yaş sınırı
- Supabase'de **SQL Editor**'de sırayla `supabase/guvenlik-1.sql` ve `supabase/guvenlik-2.sql` dosyalarını çalıştır (yeni kurulumda `kurulum.sql` hepsini içerir).
- **Authentication > Sign In / Providers > Email**: **Confirm email** açık olsun.
- **Authentication > Emails > Templates > Confirm signup**: konu `Kültürİz doğrulama kodun`, içerik `supabase/eposta-sablonu.html`. Böylece e-postaya bağlantı yerine 6 haneli kod gider.
- **Authentication > Emails > SMTP Settings**: Supabase'in hazır e-posta göndericisi yalnızca proje ekibine e-posta yollar. Herkese kod gidebilmesi için kendi SMTP hesabını gir (ör. Gmail uygulama şifresiyle `smtp.gmail.com`, port 465).
- Kayıtta doğum tarihi istenir; 13 yaşından küçükler kayıt olamaz. Doğum tarihi olmayan hesaplardan (ör. Google ile girenler) ilk girişte istenir, bir kez girilince değiştirilemez ve başkalarına görünmez.

### 6. Sansür, uzun metinler ve ilgi alanları
`supabase/guncelleme-3.sql` dosyasını SQL Editor'de çalıştır. Hakkımda 250, gönderi açıklaması 700 kelimeye çıkar; profile en fazla 3 ilgi alanı eklenir. Küfür ve uygunsuz ifadeler (ad, hakkımda, ilgi alanları, mekân, açıklama, yorum, şikayet) hem sitede hem veritabanında otomatik yıldızlanır; mevcut içerikler de temizlenir. Kelime listesi `index.html` içindeki `KUFUR_TAM`/`KUFUR_KOK` ile veritabanındaki `kufur_mu()` fonksiyonunda; ikisi aynı tutulmalı.

### 7. Okul bilgileri ve 7 dosya sınırı
`supabase/guncelleme-4.sql` dosyasını SQL Editor'de çalıştır. Kayıtta okul, şube ve okul numarası (en fazla 8 rakam) istenir; bu bilgileri yalnızca kişinin kendisi ve yönetici görür, bir kez girilince yalnızca yönetici değiştirebilir. Bir gönderiye en fazla 7 fotoğraf/video eklenebilir.

### 8. Gönderi düzenleme
`supabase/guncelleme-5.sql` dosyasını SQL Editor'de çalıştır. Gönderi sahibi kendi gönderisinin mekân adını, şehrini, türünü, açıklamasını, haritadaki yerini ve fotoğraf/videolarını (toplam en fazla 7) düzenleyebilir; yönetici her gönderiyi düzenleyebilir. Gönderinin sahibi ve paylaşım tarihi değişmez.

### 9. Mesajlaşma
`supabase/guncelleme-6.sql` dosyasını SQL Editor'de çalıştır. "Gönder" düğmesiyle bir gönderi, adı yazılarak bulunan herhangi bir üyeye (isteğe bağlı notla) gönderilir. Üst çubuktaki zarf simgesi mesaj kutusunu açar; okunmamış mesaj sayısı rozetle görünür. Mesajları yalnızca gönderen ve alan görür; metinler sansürlenir, kişi başı günde en fazla 300 mesaj gönderilebilir.

### 10. Haritada Bul oyunu
`supabase/guncelleme-7.sql` dosyasını SQL Editor'de çalıştır. Keşfet sayfasındaki "Haritada Bul" kartından açılır: 5 tarihî mekânın yerini haritada işaretlersin, yakınlığa göre tur başına en fazla 1000 puan alırsın (Türkiye ve Dünya modları). Her oyuncunun en iyi puanı sıralama tablosunda görünür. Puanlar 0–5000 aralığında olmalıdır, kimse başkası adına puan kaydedemez, günde en fazla 60 oyun kaydedilir; puanları yalnızca yönetici silebilir.

Oyundaki mekân fotoğrafları Wikimedia Commons'tandır (`assets/oyun/`, yazar ve lisans bilgisi `data/oyun-foto.json` içinde ve oyunda fotoğrafın üstünde yazar). Yeni mekân eklenince `python3 tools/oyun_foto.py` çalıştırılır; yanlış bir fotoğraf `python3 tools/oyun_foto.py "Mekân adı=Commons arama sözcükleri"` ile değiştirilir. Harita uzaktan fiziki harita, yakınlaştırınca ayrıntılı uydu görüntüsüdür (Esri); yer adları yalnızca tahminden sonra görünür.

### 11. Video sınırı ve depolama temizliği
`supabase/guncelleme-8.sql` dosyasını SQL Editor'de çalıştır. Videolar en fazla 15 MB ve 1 dakika olabilir (fotoğraflar site tarafından zaten küçültülür). Yönetim sayfasında depolama göstergesi (1 GB'ın ne kadarı dolu) görünür. Yönetici Yönetim sayfasını her açtığında, silinmiş gönderilerden, silinmiş hesaplardan, düzenlemede çıkarılan medyadan ve eski profil fotoğraflarından kalan dosyalar depodan kendiliğinden silinir.

### 12. Tam yasaklama (hesap + IP)
`supabase/guncelleme-9.sql` dosyasını SQL Editor'de çalıştır. Yönetim > Üyeler'de "Yasakla" denince hesap, yönetici yasağı kaldırana kadar hiçbir şekilde kullanılamaz (sunucu tüm tablolara erişimi keser, sitede "Erişimin engellendi" ekranı çıkar). Üyenin bağlandığı IP adresleri listelenir; işaretlenenlerden başka hesapla da girilemez. Aynı IP'yi başka üyeler de kullanıyorsa (okul, ev ağı) uyarı çıkar ve o IP varsayılan olarak işaretlenmez. "Yasağı kaldır" hesabı ve o üyeye ait IP engellerini birlikte kaldırır. Yöneticiler hiçbir engelden etkilenmez.

### 13. Takip, gizli hesap, engelleme, bildirimler ve daha fazlası
`supabase/guncelleme-10.sql` dosyasını SQL Editor'de çalıştır. Gelenler:
- **Takip** (profilde Takip et; ana sayfada "Takip ettiklerim" sekmesi; takipçi/takip listeleri) ve **gizli hesap** (Ayarlar; gönderileri yalnızca onaylı takipçiler görür, sunucu da bunu uygular).
- **Engelleme** (profilde ⋯ > Engelle; engellenen kişi mesaj atamaz, takip edemez, gönderi ve yorumları karşılıklı görünmez) ve Ayarlar > Engellenen kişiler.
- **Bildirimler** (zil): beğeni, yorum, yanıt, yorum beğenisi, takip, takip isteği (Onayla / Sil).
- **Yoruma yanıt** ve **yorum beğenme**; **yorum, mesaj ve kullanıcı şikayeti** (şikayet edilen içerik yöneticiye iletilir).
- **Hesabımı sil** (Ayarlar; her şey kalıcı olarak silinir) ve `gizlilik.html` (Gizlilik ve kurallar).
- **Anlık mesaj ve bildirim** (Supabase Realtime), akışta **sonsuz kaydırma**, profilde **gezgin pasaportu ve rozetler**, **ana ekrana ekle** (`manifest.webmanifest`, `sw.js`).

### Ücretsiz sınırlar
Supabase ücretsiz planında 500 MB veritabanı ve 1 GB dosya deposu vardır; video başına en fazla 50 MB yüklenebilir. Kullanılmayan ücretsiz projeler bir hafta hareketsiz kalınca duraklatılır, panelden tek tıkla yeniden açılır.

## Önizleme modu ve sınırlar

Supabase bağlanmadan önce gönderiler (fotoğraf ve videolarıyla tarayıcının IndexedDB deposunda), beğeniler, kayıtlar, yorumlar ve profil yalnızca o tarayıcıda saklanır. Önizlemede o tarayıcıda ilk açılan hesap yöneticidir. Supabase bağlanınca gönderiler, yorumlar, beğeniler, kayıtlar ve profiller herkese açık veritabanına taşınır. **Geçmiş** her zaman cihazda kalır. "Gönder" penceresindeki kişilere gönderim, mesajlaşma bölümü gelene kadar göstermeliktir; bağlantıyı kopyalama gerçekten çalışır.

Paylaşım sırasında mekân ve şehir alanları yazarken öneri verir ("top" → Topkapı Sarayı, "iskan" → İstanbul, Türkiye). Liste `data/mekanlar.json` (185 mekân) ve `data/sehirler.json` dosyalarından gelir; `tools/mekanlar_uret.py` içine satır ekleyip çalıştırarak yeni mekân eklenebilir. Listede olmayan bir yer haritada aranınca site yayındayken OpenStreetMap'te (Nominatim) aranır.

## Dosyalar

- `index.html`: Uygulamanın tamamı (HTML, CSS, JS)
- `tools/tek-dosya.py`: Her şeyi içine gömen tek dosyalık sürümü üretir (`python3 tools/tek-dosya.py cikti.html`)
- `supabase/kurulum.sql`: Veritabanı, güvenlik kuralları ve dosya deposu kurulumu
- `data/mekanlar.json`, `data/sehirler.json`: Arama önerileri için mekân ve şehir listeleri (`tools/mekanlar_uret.py` üretir)
- `data/gonderiler.json`: Örnek gönderiler, mekân açıklamaları, tarihçeler, benzer mekânlar, fotoğraf kaynakları
- `data/kiyilar.json`: Türkiye ve çevresinin kıyı çizgileri (Natural Earth 1:10m), internet haritası yüklenemezse kullanılır
- `assets/fiziki-harita.jpg`: Fiziki dünya haritası (NASA Blue Marble, kamu malı)
- `assets/foto/`, `assets/video/`: Wikimedia Commons'tan alınan fotoğraf ve videolar. Her birinin yazarı ve lisansı gönderi sayfasında "Fotoğraf ve video kaynakları" altında listelenir.
