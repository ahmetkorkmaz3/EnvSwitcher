# Değişiklikler

Bu dosya [Keep a Changelog](https://keepachangelog.com/tr-TR/1.1.0/) biçimini kullanır. Sürümler [Semantic Versioning](https://semver.org/lang/tr/) kurallarına uyar.

## [Yayımlanmadı]

### Eklenenler

- İngilizce ve Türkçe dil desteği. Uygulama ilk açılışta macOS dilini kullanır. Dil Ayarlar'dan değişir.
- Landing page İngilizce açılır. TR düğmesi sayfayı Türkçe yapar.

### Değişenler

- `.env` dosyalarının başlık yorumu İngilizce yazılır.

## [0.2.0] - 2026-10-08

İlk herkese açık sürüm.

### Eklenenler

- Menü çubuğundan bir projenin tüm `.env` dosyalarını veya tek bir dosyayı başka bir ortama geçirme.
- Proje ekleme: klasör tarama, `.gitignore` uyarısı, mevcut değerleri `local` ortamına aktarma.
- Düzenleme penceresi: değer düzenleme, `.env` önizleme, panodan `KEY=değer` yapıştırma.
- Karşılaştırma görünümü: bir dosyanın değerlerini ortamlar arasında yan yana görme, eksik anahtarları kopyalama.
- Güvenlik önlemleri: elle değişiklik kontrolü, boş ortam uyarısı, ya hep ya hiç yazma, korumalı ortam onayı.
- Gizli değerler macOS Keychain içinde tek bir kayıtta durur.
- Menüde yeni sürüm bildirimi ve sürüm satırı.
- Tek komutla kurulum ve güncelleme: `install.sh`.
- Apple Silicon ve Intel desteği.

### Değişenler

- 0.2.0'dan önceki derlemeler her gizli değeri ayrı bir Keychain kaydında tutar. Uygulama bu kayıtları ilk açılışta tek kayda taşır.
