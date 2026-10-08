# EnvSwitcher

EnvSwitcher, bir projedeki `.env` dosyalarını ortamlar arasında değiştiren bir macOS menü çubuğu uygulamasıdır. Örnek: `local`, `test` ve `canli` değerlerini tek tıkla değiştirin.

- Değerleri uygulamada bir kez girin. Ortam değiştirince uygulama `.env` dosyalarını yeniden yazar.
- Gizli değerler (token, şifre, anahtar) macOS Keychain içinde durur. `store.json` dosyasına girmez.
- Bir monorepodaki tüm `.env` dosyaları birlikte veya tek tek değişir.

## Hızlı başlangıç

1. Uygulamayı derleyin ve açın (bkz. [Derleme](#derleme)). Menü çubuğunda `EnvSwitcher` yazısı görünür.
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
| Gizli değerler | Keychain, servis adı `EnvSwitcher` |
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
ENVSWITCHER_KEYCHAIN_TESTS=1 swift test --filter SecretsTests
```

### Keychain izin sorusu

Ad-hoc imza her derlemede değişir. Bu nedenle macOS yeni bir derlemeden sonra Keychain izni sorabilir. Bu soruyu önlemek için kendinden imzalı bir sertifika oluşturun (Anahtar Zinciri Erişimi → Sertifika Asistanı → Sertifika Oluştur, tür: Kod İmzalama). Sonra şu komutu kullanın:

```sh
CODESIGN_IDENTITY="EnvSwitcher Dev" scripts/bundle.sh
```

## Proje yapısı

| Klasör | İçerik |
|---|---|
| `Sources/EnvCore` | Arayüzden bağımsız mantık: ayrıştırma, tarama, Keychain, ortam değiştirme. Testler bu modülü kapsar. |
| `Sources/EnvSwitcher` | SwiftUI uygulaması: menü çubuğu, yönetim penceresi, fark penceresi. |
| `Tests/EnvCoreTests` | Birim testleri. |
| `docs/manual-test.md` | Her sürümden önce uygulanacak elle test listesi. |
| `docs/superpowers/specs/` | Tasarım dokümanı. |
