# EnvSwitcher

EnvSwitcher, bir projedeki `.env` dosyalarını ortamlar arasında değiştiren bir macOS menü çubuğu uygulamasıdır. Örnek: `local`, `test` ve `canli` değerlerini tek tıkla değiştirin.

- Değerleri uygulamada bir kez girin. Ortam değiştirince uygulama `.env` dosyalarını yeniden yazar.
- Gizli değerler (token, şifre, anahtar) macOS Keychain içinde durur. `store.json` dosyasına girmez.
- Bir monorepodaki tüm `.env` dosyaları birlikte veya tek tek değişir.

## Kurulum

Terminalde şu komutu çalıştırın:

```sh
curl -fsSL https://raw.githubusercontent.com/ahmetkorkmaz3/env-management/main/install.sh | sh
```

Komut son sürümü indirir, SHA-256 değerini kontrol eder, `/Applications` içine kurar ve uygulamayı açar. Gereksinim: macOS 14 veya üstü. Apple Silicon ve Intel desteklenir.

**Güncelleme:** Aynı komutu yeniden çalıştırın. Yeni bir sürüm çıkınca menüde "Güncelleme var" satırı görünür. Bu satır komutu panoya kopyalar.

**Belirli bir sürüm:** `curl -fsSL https://raw.githubusercontent.com/ahmetkorkmaz3/env-management/main/install.sh | ENVSWITCHER_VERSION=0.2.0 sh`

**Elle kurulum:**

1. [Releases](https://github.com/ahmetkorkmaz3/env-management/releases) sayfasından `EnvSwitcher-X.Y.Z.zip` dosyasını indirin.
2. Zip dosyasını açın. `EnvSwitcher.app` dosyasını `/Applications` içine taşıyın.
3. Uygulamayı açın. macOS "Apple doğrulayamadı" uyarısını gösterir. **Bitti** düğmesine basın.
4. Sistem Ayarları → Gizlilik ve Güvenlik sayfasını açın. Sayfanın altında **Yine de Aç** düğmesine basın.

Uygulama notarize edilmedi, bu nedenle tarayıcıdan indirilen dosyada bu uyarı çıkar. Kurulum komutu bu uyarıyı göstermez.

**Kaldırma:**

```sh
osascript -e 'quit app "EnvSwitcher"'
rm -rf /Applications/EnvSwitcher.app
rm -rf ~/Library/Application\ Support/EnvSwitcher
security delete-generic-password -s EnvSwitcher -a vault
defaults delete com.ahmetkorkmaz.envswitcher
```

Bu komutlar `.env` dosyalarınızı değiştirmez.

## Hızlı başlangıç

1. Uygulamayı kurun (bkz. [Kurulum](#kurulum)) ve açın. Menü çubuğunda `EnvSwitcher` yazısı görünür.
2. Menüden **Proje Ekle…** seçin. Proje klasörünü seçin veya pencereye sürükleyin.
3. Bulunan `.env` dosyalarını kontrol edin. **Ekle** düğmesine basın. Dosyaların mevcut içeriği `local` ortamına aktarılır.
4. **Yönet…** penceresinde bir dosya seçin. Üstten **Karşılaştır** görünümünü seçin.
5. Eksik anahtarlar için **Eksiklere kopyala → local değerini kopyala** seçin. Sonra `test` için farklı olan değerleri değiştirin.
6. Menüden proje → **Tüm dosyalar → test** seçin. Tüm dosyalar `test` değerleriyle yazılır.

## Kavramlar

| Kavram | Anlamı |
|---|---|
| Proje | Bir kök klasör. Her klasör yalnızca bir projede olur. |
| Ortam | Bir değer seti, örnek: `local`, `test`, `canli`. Her ortamın bir rengi vardır. |
| Korumalı ortam | Bu ortama geçmeden önce uygulama onay ister. `canli` korumalı başlar. |
| Hedef dosya | Uygulamanın yönettiği bir `.env` dosyası, örnek: `apps/cart/.env.local`. |
| Diskteki ortam | Bir dosyaya en son yazılan ortam. Menüde ve kenar çubuğunda renkli nokta ile görünür. |
| Gizli değer | Keychain'de saklanan değer. Adında `SECRET`, `PASSWORD`, `TOKEN`, `PRIVATE` olan veya `_KEY` ile biten anahtarlar otomatik gizli olur. `NEXT_PUBLIC_` ile başlayanlar gizli olmaz. |

## Günlük kullanım

**Ortam değiştirme (menü çubuğu):**
- **Tüm dosyalar** altındaki ortam, projedeki tüm dosyaları değiştirir.
- **Dosyalar** altındaki bir dosyanın alt menüsü yalnızca o dosyayı değiştirir.
- Dosyalar farklı ortamlarda ise başlık `karışık` gösterir.

**Değer düzenleme (Yönet… penceresi):**
- Bir dosya seçin ve üstten ortamı seçin. Her değişiklik hemen kaydedilir.
- Anahtar adını değiştirdikten sonra Return tuşuna basın veya başka bir alana geçin.
- Diskteki ortamı düzenlerseniz "Değişiklikler diske yazılmadı" uyarısı çıkar. **Diske yaz** düğmesine basın.
- **.env önizle** düğmesi, yazılacak dosyayı gösterir. Gizli değerler `••••••••` olarak görünür.
- **Panodan yapıştır** düğmesi, panodaki `KEY=değer` satırlarını seçili ortama ekler.
  - Ortamda olmayan anahtarlar eklenir. Boş değerler doldurulur. Soru sorulmaz.
  - Bir anahtarın başka bir değeri varsa uygulama sorar: **Üzerine yaz** veya **Yalnızca eksikleri ekle**.
  - Yeni bir anahtar gizli değere benziyorsa (`_KEY`, `TOKEN`, `SECRET` gibi) Keychain'e yazılır.

**Ortamları karşılaştırma (Yönet… → dosya → Karşılaştır):**
- Her anahtar bir satırda durur. Her ortamın değeri yan yana görünür.
- Satırın başındaki işaret durumu gösterir: kırmızı = bir ortamda eksik, turuncu = değerler farklı, gri = tüm ortamlarda aynı.
- **Eksik** ve **Farklı** filtreleri yalnızca ilgili satırları gösterir.
- Eksik bir hücreye değer yazıp Return tuşuna basın. Anahtar o ortama eklenir.
- **Eksiklere kopyala** bir ortamın değerini, anahtarın olmadığı tüm ortamlara yazar.
- **Tüm eksiklere kopyala** aynı işi tüm eksik anahtarlar için tek seferde yapar. Önce onay ister. Var olan değerler değişmez.
  - **Her anahtar için ilk dolu ortamdan**: her anahtarın değeri, anahtarın olduğu ilk ortamdan alınır.
  - **<ortam> değerlerini kopyala**: değerler seçilen ortamdan alınır. Bu ortamda olmayan anahtarlar atlanır ve listelenir.
- Gizli değerler `••••` olarak görünür. Satırdaki göz düğmesi değerleri gösterir.
- Düzenle görünümünde bir ortamda eksik anahtar varsa, alt çubukta "N anahtar bu ortamda eksik" düğmesi çıkar.

**Proje ayarları (kenar çubuğunda proje adı):**
- Ortam ekleyin, adını, rengini ve korumasını değiştirin.
- **Dosya ekle** ile sonradan oluşan bir `.env` dosyasını ekleyin. İçeriği projenin diskteki ortamına aktarılır.
- Projeyi silmek, diskteki `.env` dosyalarını değiştirmez.

## Güvenlik önlemleri

- **Elle değişiklik kontrolü:** Bir dosyayı editörde değiştirdiyseniz, ortam değişmeden önce uygulama farkı gösterir. Seçenekler: değişikliği bir ortama kaydet, at ve geç, iptal.
- **Boş ortam uyarısı:** Seçilen ortamda bir dosya için değer yoksa uygulama sorar. Bu uyarı dosyaların yanlışlıkla boşalmasını önler.
- **Ya hep ya hiç yazma:** Bir dosya yazılamazsa, yazılan dosyalar eski içeriğe döner.
- **Dosya izinleri:** Uygulama dosyanın izinlerini (örnek `600`) korur ve sembolik bağlantının hedefine yazar.
- **Git uyarısı:** Bir `.env` dosyası `.gitignore` içinde değilse, proje eklerken uyarı çıkar.

## Taramada atlanan klasörler

`node_modules`, `vendor`, `.git`, `dist`, `build`, `.next`, `.turbo`, `.claude` ve kendi `.git` girdisi olan alt klasörler (ayrı repolar, worktree kopyaları). `.example`, `.sample` ve `.template` ile biten dosyalar listede görünür ama seçili gelmez.

## Veri konumu

| Ne | Nerede |
|---|---|
| Projeler, ortamlar, gizli olmayan değerler | `~/Library/Application Support/EnvSwitcher/store.json` |
| Son yedek | `~/Library/Application Support/EnvSwitcher/store.json.bak` |
| Gizli değerler | Keychain, servis adı `EnvSwitcher`, hesap adı `vault` (tek kayıt) |
| Güncelleme kontrolü | `defaults read com.ahmetkorkmaz.envswitcher storedUpdate` |
| Geri alma başarısız olursa eski içerik | `~/Library/Application Support/EnvSwitcher/recovery/` |

`store.json` bozulursa uygulama yedeği yükler ve bir uyarı gösterir.

## Derleme

**Gereksinimler:** macOS 14 veya üstü ve Xcode. Xcode'u aktif yapın:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
```

**Derleme ve çalıştırma:**

```sh
swift test                         # EnvCore testleri
scripts/bundle.sh                  # build/EnvSwitcher.app oluşturur
open build/EnvSwitcher.app
```

Uygulamayı kalıcı kullanmak için `build/EnvSwitcher.app` klasörünü `/Applications` içine kopyalayın.

**Gerçek Keychain testi:**

```sh
ENVSWITCHER_KEYCHAIN_TESTS=1 swift test --filter VaultKeychainTests
```

### İmza ve Keychain izin sorusu

Keychain bir kaydı oluşturan uygulamayı imzası ile tanır. Ad-hoc imza her derlemede değişir. Bu nedenle ad-hoc bir derlemeden sonra macOS bir kez izin sorar. Tüm gizli değerler tek bir kayıtta durur, bu nedenle soru bir kez çıkar.

Bu soruyu önlemek için release sürümlerinin sertifikası ile imzalayın:

1. Sertifikayı bir kez oluşturun: `scripts/make-signing-cert.sh`. Sertifika zaten varsa ve `.p12` dosyası sizdeyse, dosyayı çift tıklayıp giriş Keychain'ine alın.
2. Derleyin: `CODESIGN_IDENTITY="EnvSwitcher Self-Signed" scripts/bundle.sh`

Sürüm çıkarma adımları: [`docs/release.md`](docs/release.md).

## Proje yapısı

| Klasör | İçerik |
|---|---|
| `Sources/EnvCore` | Arayüzden bağımsız mantık: ayrıştırma, tarama, Keychain, ortam değiştirme. Testler bu modülü kapsar. |
| `Sources/EnvSwitcher` | SwiftUI uygulaması: menü çubuğu, yönetim penceresi, fark penceresi. |
| `Tests/EnvCoreTests` | Birim testleri. |
| `docs/manual-test.md` | Her sürümden önce uygulanacak elle test listesi. |
| `docs/superpowers/specs/` | Tasarım dokümanı. |
| `scripts/` | Derleme, ikon, sertifika ve CHANGELOG betikleri. |
| `install.sh` | Kurulum ve güncelleme betiği. |
| `.github/workflows/` | CI ve release iş akışları. |
| `docs/release.md` | Sürüm çıkarma adımları. |

## Lisans

MIT. Bkz. [LICENSE](LICENSE).
