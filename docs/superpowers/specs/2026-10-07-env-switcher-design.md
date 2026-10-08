# EnvSwitcher — Tasarım Belgesi

- **Tarih:** 2026-10-07
- **Durum:** İncelemede
- **Yazar:** Ahmet Korkmaz (Claude ile birlikte)

## 1. Amaç

EnvSwitcher bir macOS menü çubuğu uygulamasıdır. Bir projedeki `.env` dosyalarını ortamlar arasında değiştirir. Örnek ortamlar: `local`, `test`, `canli`.

Bir projede birden fazla `.env` dosyası olabilir. Dosyalar iç içe klasörlerde de olabilir. Uygulama tüm dosyaları birlikte veya her dosyayı ayrı olarak bir ortama geçirir.

### 1.1 Kullanıcının istekleri

- Her projede birden fazla ortam tanımlanabilir.
- Bir projedeki iç içe `.env` dosyalarının her biri ayrı yönetilir.
- Ortam değişince uygulama dosyaların içeriğini yeniden yazar.
- Arayüz bir macOS menü çubuğu uygulamasıdır.
- Tasarım dili Apple Human Interface Guidelines kurallarına uyar.
- Kullanıcı bir projeyi hızlı ekler ve proje klasörünü menüden açar.

### 1.2 Varsayımlar

- Uygulama yalnızca bir kişinin Mac bilgisayarında çalışır. Ekip paylaşımı ve sunucu yoktur.
- Uygulama App Store dağıtımına çıkmaz. App Sandbox kullanılmaz.

### 1.3 Referans proje

`~/work/karaca/karaca-storefront` bir pnpm/turbo monorepo yapısıdır. Tasarım bu projeye göre kontrol edildi:

- `apps/` altında 11 Next.js uygulaması vardır.
- 9 uygulamanın `.env.local` dosyası vardır. 10 uygulamanın `.env.example` dosyası vardır.
- `.claude/worktrees/` altında reponun kopyaları vardır. Bu kopyalarda aynı `.env.local` dosyaları tekrar eder.
- `.gitignore` dosyası `.env` ve `.env.local` dosyalarını ignore eder.

### 1.4 Kapsam dışı (YAGNI)

- Ortamlar arasında ortak değerler katmanı
- Dosyalar arasında ortak değerler veya toplu düzenleme
- Değişken referansları (`${OTHER}`)
- Ekip senkronizasyonu ve bulut yedekleme
- CLI arayüzü. `EnvCore` paketi ileride bir CLI için kullanılabilir.
- Arka planda sürekli dosya izleme (FSEvents)
- Bir klasörü menü çubuğu simgesine sürükleyip bırakmak. Sürükle-bırak yalnızca pencerede ve sheet içinde çalışır.

## 2. Teknoloji

- **Dil ve arayüz:** Swift 6 ve SwiftUI. Uygulama `MenuBarExtra` (`.menu` stili) ve ayrı bir `Window` kullanır.
- **Platform:** macOS 14 (Sonoma) ve üstü. `MenuBarExtra` ve `@Observable` bu sürümü gerektirir.
- **Paket yapısı:** Swift Package Manager.
  - `EnvCore` (library): depo, Keychain, `.env` okuma ve yazma, tarama, fark hesabı, geçiş işlemi. SwiftUI içermez.
  - `EnvSwitcher` (executable): menü ve düzenleme penceresi. Yalnızca `EnvCore` çağırır.
  - `EnvCoreTests` (test): Swift Testing.
- **Uygulama paketi:** `scripts/bundle.sh` bir `.app` paketi oluşturur. Bu paketin `Info.plist` dosyasında `LSUIElement=true` olur, bu nedenle Dock simgesi görünmez. Paket bir sertifika ile veya ad-hoc imzalanır (bölüm 2.2).

### 2.1 Ön koşul: Xcode

Makinede `/Applications/Xcode.app` vardır, ama aktif değildir. Komut satırı araçları (Command Line Tools) SwiftUI uygulamasını derler. Ama bu araçlarda Swift Testing ve XCTest çalışmaz. Bu durum 2026-10-07 tarihinde test edildi.

Uygulamaya başlamadan önce kullanıcı şu iki komutu çalıştırır:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
```

### 2.2 Keychain izinleri

Bu bölüm 2026-10-08 tarihinde değişti. Yeni düzen: tüm gizli değerler tek bir Keychain kaydında durur, sürümler aynı kendinden imzalı sertifika ile imzalanır. Ayrıntı: `2026-10-08-github-release-design.md`, bölüm 2–4.

## 3. Veri modeli

### 3.1 Kavramlar

| Kavram | Alanlar | Açıklama |
|---|---|---|
| **Proje** | `id`, `name`, `rootPath`, `environments`, `targets` | Bir klasör ve o klasördeki yönetilen dosyalar. |
| **Ortam** | `id`, `name`, `color`, `isProtected` | Proje düzeyinde tanımlanır. Tüm hedef dosyalar aynı ortam listesini kullanır. |
| **Hedef dosya** | `id`, `relativePath`, `activeEnvironmentId?`, `lastWrittenHash?`, `values` | Proje köküne göre göreli yol. Örnek: `apps/cart/.env.local`. Her hedef dosyanın kendi aktif ortamı vardır. |
| **Değer kaydı** | `key`, `value?`, `isSecret` | `isSecret` doğruysa `value` boş kalır. Değer Keychain'de durur. |

`values` alanı bir sözlüktür: `[ortamId: [DeğerKaydı]]`. Liste sırası, dosyaya yazılan anahtar sırasıdır.

**Ortak değer yoktur.** Her hedef dosya, her ortam için kendi anahtar listesinin tamamını tutar.

### 3.2 Projenin görünen ortamı

Projenin görünen ortamı, hedef dosyaların aktif ortamlarından hesaplanır:

- Tüm hedef dosyalar aynı ortamdaysa, proje o ortamı gösterir.
- Hedef dosyalar farklı ortamlardaysa, proje "karışık" gösterir.
- Hiçbir hedef dosyanın aktif ortamı yoksa, proje "—" gösterir.

### 3.3 Depolama

- **Dosya:** `~/Library/Application Support/EnvSwitcher/store.json`
  - Projeleri, ortamları, hedef dosyaları ve gizli olmayan değerleri tutar.
  - Ayarları tutar: editör uygulaması ve terminal uygulaması.
  - Dosyada bir `version` alanı vardır. İlk sürüm `1` olur.
  - Uygulama her kayıttan önce mevcut dosyayı `store.json.bak` olarak kopyalar.
- **Keychain:** gizli değerleri tutar.
  - Servis adı: `EnvSwitcher`
  - Hesap adı: `<projeId>/<hedefId>/<ortamId>/<ANAHTAR>`
  - Hesap adında ad yerine kimlik (`id`) kullanılır. Böylece bir ortamın veya projenin adı değişince Keychain kayıtları bozulmaz.

### 3.4 Gizli değer önerisi

İçe aktarmada uygulama bazı anahtarları "gizli" olarak önerir. Öneri kuralı:

- Anahtar adında `SECRET`, `PASSWORD`, `TOKEN`, `PRIVATE` geçer veya ad `_KEY` ile biter.
- Anahtar `NEXT_PUBLIC_` ile başlamaz. Bu önekli değerler zaten tarayıcıya gider.

Kullanıcı öneriyi pencerede değiştirir.

### 3.5 Üretilen dosyanın biçimi

```
# EnvSwitcher tarafından üretildi — proje: karaca-storefront, ortam: test
# Bu dosyayı elle düzenlerseniz, ortam değişirken uygulama sorar.
NEXT_PUBLIC_APP_ENV=test
NEXT_PUBLIC_API_BASE_URL=https://test-api.example
TURNSTILE_SECRET_KEY=<Keychain'den gelen gerçek değer>
```

- Anahtarlar, düzenleme penceresindeki sırayla yazılır.
- Boşluk, `#`, tırnak veya satır sonu içeren değerler çift tırnak içinde yazılır. Bu değerlerde `\`, `"` ve satır sonu kaçış karakteriyle yazılır.

## 4. `.env` okuma kuralları

- `KEY=VALUE` ve `export KEY=VALUE` satırlarını okur.
- Anahtar deseni: `[A-Za-z_][A-Za-z0-9_.-]*`
- Tırnaksız değerde, boşluktan sonra gelen `#` bir yorum başlatır.
- Tek tırnaklı değer olduğu gibi okunur.
- Çift tırnaklı değerde `\n`, `\"` ve `\\` kaçışları çözülür.
- Tırnaklı değerler birden fazla satır sürebilir.
- `#` ile başlayan satırlar ve boş satırlar atlanır.
- Aynı anahtar iki kez geçerse son değer kullanılır. Okuyucu bir uyarı listesi döndürür.
- Okunamayan bir satır hata vermez. Okuyucu bu satırı satır numarasıyla birlikte uyarı listesine ekler.

Dosyadaki yorumlar içe aktarmada kaybolur.

## 5. Proje ekleme

### 5.1 Giriş yolları

Üç yol aynı "Proje Ekle" sheet'ini açar:

1. Menüde "Proje Ekle…" (⌘N)
2. Düzenleme penceresinde kenar çubuğundaki "＋" düğmesi
3. Bir klasörü düzenleme penceresine sürükleyip bırakmak

### 5.2 Tarama

Uygulama seçilen klasörü özyinelemeli olarak tarar ve `.env` ile başlayan dosyaları bulur.

**Atlanan klasörler:**
- `node_modules`, `vendor`, `.git`, `dist`, `build`, `.next`, `.turbo`, `.claude`
- Kendi `.git` girdisi olan alt klasörler. Bu kural ayrı repoları ve git worktree kopyalarını atlar.

**Varsayılan seçim:**
- `.example`, `.sample` veya `.template` ile biten dosyalar seçili gelmez.
- Diğer tüm dosyalar seçili gelir.

### 5.3 Sheet alanları

- **Proje adı:** varsayılan değer klasör adıdır.
- **Ortamlar:** varsayılan değer `local`, `test`, `canli` olur. `canli` korumalı başlar. Kullanıcı ortam ekler, siler ve adını değiştirir.
- **Mevcut içerik:** seçilen dosyaların mevcut içeriği bir ortama aktarılır. Varsayılan ortam `local` olur. Diğer ortamlar boş başlar.

### 5.4 Ekleme sonrası

- Her hedef dosyanın aktif ortamı, içerik aktarılan ortam olur.
- Her hedef dosyanın özeti kaydedilir. Uygulama dosyaları yeniden yazmaz.
- Uygulama her hedef dosya için `git check-ignore` çalıştırır. Dosya ignore edilmemişse bir uyarı gösterir: "Bu dosya git tarafından izleniyor. canli değerler commit'e girebilir."

## 6. Ortam değiştirme akışı

Bir geçişin **kapsamı** iki türlü olabilir:
- **Proje geneli:** projedeki tüm hedef dosyalar
- **Tek dosya:** yalnızca seçilen hedef dosya

Akış iki kapsamda da aynıdır:

1. **Korumalı ortam kontrolü.** Hedef ortam korumalıysa uygulama bir onay penceresi gösterir. Örnek: "karaca-storefront projesi CANLI ortama geçecek. 9 dosya değişecek." İptal ederseniz hiçbir dosya değişmez.
2. **Elle değişiklik kontrolü.** Uygulama kapsamdaki her dosyayı okur ve SHA-256 özetini `lastWrittenHash` ile karşılaştırır.

   | Durum | Sonuç |
   |---|---|
   | Dosya yok | Uygulama dosyayı oluşturur. |
   | Özet aynı | Dosya temiz. |
   | Özet farklı | Elle değişiklik var. Adım 3 çalışır. |
   | Dosya var ama `lastWrittenHash` yok | Elle değişiklik var. Adım 3 çalışır. "Kaydet" seçeneğinde kullanıcı ortamı seçer. |

3. **Fark penceresi.** Bu pencere yalnızca elle değişiklik varsa açılır. Her dosya için eklenen, değişen ve silinen anahtarları gösterir. Üç seçenek vardır:
   - **Mevcut ortama kaydet:** Uygulama dosyanın içeriğini okur ve dosyanın aktif ortamının değer listesine yazar. Eklenen anahtarlar listenin sonuna eklenir. Değişen anahtarlar güncellenir. Silinen anahtarlar listeden çıkar. Gizli bir anahtar değişirse Keychain güncellenir.
   - **At ve geç:** Elle yapılan değişiklikler kaybolur.
   - **İptal:** Hiçbir şey değişmez.
4. **İçeriği hazırla.** Her dosya için yeni içerik bellekte oluşturulur. Gizli değerler Keychain'den okunur. Bu adım diske yazmaz. Bir Keychain okuması başarısız olursa geçiş durur.
5. **Dosyaları yaz.**
   - Uygulama her dosyanın eski içeriğini bellekte tutar.
   - Her dosya önce aynı klasörde geçici bir dosyaya yazılır. Sonra `rename` ile asıl dosyanın yerine geçer.
   - Bir dosya başarısız olursa, uygulama o ana kadar yazılan dosyalara eski içeriklerini geri yazar. Eski içeriği olmayan dosyaları siler.
   - Sonuç: proje "yarısı test, yarısı canli" durumunda kalmaz.
6. **Durumu kaydet.** Uygulama her dosyanın `activeEnvironmentId` ve `lastWrittenHash` alanlarını günceller. Sonra `store.json` dosyasını kaydeder. Menü çubuğu başlığı güncellenir.

### 6.1 Elle değişiklik göstergesi

Uygulama arka planda dosya izlemez. Kullanıcı menüyü açınca uygulama tüm hedef dosyaların özetini kontrol eder. Elle değişiklik olan bir projenin yanında ⚠︎ işareti görünür.

## 7. Arayüz

Tasarım dili Apple Human Interface Guidelines kurallarına uyar:
- Yalnızca native SwiftUI bileşenleri kullanılır.
- Simgeler SF Symbols setinden gelir.
- Renkler sistem renkleridir. Açık mod ve koyu mod desteklenir.
- Metin sistem fontunu kullanır. Anahtar ve değerler monospace fontla gösterilir.

Onaylanan çizim: `.superpowers/brainstorm/11861-1791392457/content/ui-layout-v3.html`. Bu klasör git deposuna girmez.

### 7.1 Menü çubuğu

**Başlık:** Son geçiş yapılan projenin adı ve görünen ortamı yazılır. Önde ortam renginde bir nokta olur. Örnek: `● karaca-storefront · test`.

**Menü yapısı:**

```
karaca-storefront          karışık ›
  ├─ Tüm dosyalar
  │    ● local
  │    ● test
  │    ● canli 🔒
  ├─ Dosyalar
  │    apps/cart/.env.local       test ›   (local / test / canli)
  │    apps/checkout/.env.local  canli ›
  │    …
  ├─ Finder'da Aç        ⌘O
  ├─ Terminal'de Aç      ⌘T
  └─ Editörde Aç         ⌘E
villa-karakaya ⚠︎          local ›
──────────
Proje Ekle…              ⌘N
Yönet…                   ⌘,
──────────
Çık                      ⌘Q
```

- "Tüm dosyalar" altındaki ortam, proje geneli bir geçiş yapar.
- "Tüm dosyalar" altında onay işareti yalnızca tüm dosyalar aynı ortamdaysa görünür.
- "Dosyalar" altındaki her dosyanın alt menüsü, tek dosya geçişi yapar.
- Klasörü bulunamayan bir proje gri görünür. Alt menüsünde yalnızca "Klasörü yeniden seç…" vardır.

### 7.2 Düzenleme penceresi

Pencere `NavigationSplitView` kullanır.

**Kenar çubuğu:**
- Projeleri listeler. Her proje, hedef dosyalarını klasör ağacı olarak gösterir.
- Her dosyanın yanında, diskteki ortamın renginde bir nokta durur.
- Altta "＋ Proje Ekle" düğmesi durur.
- Bir proje seçilince ayrıntı alanı proje ayarlarını gösterir: ad, kök klasör, ortamlar (ad, renk, korumalı), hedef dosya listesi.

**Ayrıntı alanı (bir dosya seçilince):**
- Başlık: dosyanın göreli yolu ve diskteki ortamı
- Araç çubuğu: düzenlenen ortamı seçen bir segmented control, "Finder'da göster", ".env önizle" ve "Bu ortama geç"
- Segmented control yalnızca düzenlenen ortamı seçer. Diskteki ortamı değiştirmez. Kullanıcı canli diskteyken test değerlerini düzenleyebilir.
- `Table` bileşeni: anahtar, değer ve gizli işareti sütunları. Gizli değerler maskeli görünür. Göz simgesi değeri gösterir.
- Alt çubuk: "＋", "－" ve "Diğer ortamdan kopyala"
- "Diğer ortamdan kopyala" başka bir ortamın anahtar listesini bu ortama kopyalar. Aynı anahtar varsa kullanıcı "üzerine yaz" veya "atla" seçer.

**Kaydetme:** Pencere her düzenlemeyi hemen `store.json` dosyasına ve Keychain'e kaydeder. Düzenleme, diskteki `.env` dosyasını değiştirmez. Diskteki dosya yalnızca bir geçişte değişir. Düzenlenen ortam diskteki ortamla aynıysa, başlıkta bir uyarı görünür: "Değişiklikleri diske yazmak için Bu ortama geç düğmesine basın."

### 7.3 Ayarlar

- **Editör:** varsayılan değer sistemde `.env` dosyalarını açan uygulamadır. Kullanıcı başka bir uygulama seçer, örnek: VS Code, Cursor, Zed.
- **Terminal:** varsayılan değer Terminal.app olur. Kullanıcı başka bir uygulama seçer, örnek: iTerm, Ghostty.
- Uygulama klasörü `NSWorkspace.open(_:withApplicationAt:configuration:)` ile açar.

## 8. Hata durumları

| Durum | Davranış |
|---|---|
| Proje klasörü taşındı veya silindi | Proje menüde gri görünür ve "Klasör bulunamadı" yazar. Pencerede "Klasörü yeniden seç" düğmesi çıkar. |
| Hedef dosyanın klasörü yok | Geçiş başlamaz. Hata mesajı dosyanın adını gösterir. "Dosyayı projeden çıkar" seçeneği sunar. |
| Keychain erişimi reddedildi | Geçiş adım 4'te durur. Diskteki dosyalar aynı kalır. |
| Bir dosyaya yazma izni yok | Geçiş adım 5'te durur. Yazılan dosyalar eski içeriğe döner. |
| Geri dönüş de başarısız oldu | Uygulama geri dönemeyen dosyaların listesini gösterir. Eski içerikleri `~/Library/Application Support/EnvSwitcher/recovery/<zaman>/` klasörüne yazar. |
| `store.json` bozuk | Uygulama `store.json.bak` dosyasını yükler ve bir uyarı gösterir. Yedek de bozuksa, bozuk dosyayı `store.json.corrupt-<zaman>` adıyla saklar ve boş bir depo ile açılır. |
| Hedef dosya git tarafından izleniyor | Bölüm 5.4'teki uyarı gösterilir. |
| Aynı anahtar bir dosyada iki kez var | İçe aktarmada son değer kullanılır. Pencere bir uyarı gösterir. |

## 9. Kod yapısı

```
Package.swift
Sources/
  EnvCore/
    Model/          Project, Environment, Target, Entry, Store
    Parsing/        DotEnvParser, DotEnvSerializer
    Storage/        StoreRepository (JSON + .bak), SecretStore (protokol), KeychainSecretStore
    Scanning/       ProjectScanner
    Switching/      SwitchPlanner (adım 1–4), SwitchExecutor (adım 5), DriftDetector, FileWriter (protokol)
    Git/            GitIgnoreChecker
  EnvSwitcher/
    App/            EnvSwitcherApp, AppState (@Observable)
    MenuBar/        MenuContent, ProjectMenu, TargetMenu
    Window/         ManagerWindow, Sidebar, TargetDetail, ProjectSettings
    Sheets/         AddProjectSheet, DriftSheet, ProtectedConfirm
    Settings/       SettingsView
Tests/
  EnvCoreTests/
scripts/
  bundle.sh
```

Her `EnvCore` birimi bir sorumluluk taşır ve test için protokol arkasında durur. `SecretStore` ve `FileWriter` bunun iki örneğidir.

## 10. Test

### 10.1 `EnvCore` birim testleri (Swift Testing)

- **DotEnvParser ve DotEnvSerializer:** Bölüm 4'teki her kural için bir test. Ek olarak bir gidiş-dönüş testi: yazılan içerik okununca aynı kayıtlar çıkar.
- **DriftDetector:** Bölüm 6, adım 2'deki dört durum.
- **Fark hesabı:** eklenen, değişen ve silinen anahtarlar.
- **ProjectScanner:** Geçici bir klasör kullanılır. Bu klasörde `node_modules`, `.claude/worktrees/x` (içinde `.git` dosyası olan) ve `.env.example` örnekleri olur. Test, sonuç listesini ve varsayılan seçimleri kontrol eder.
- **SwitchExecutor:** Sahte bir `FileWriter` ikinci dosyada hata verir. Test, ilk dosyanın eski içeriğe döndüğünü kontrol eder.
- **StoreRepository:** kaydetme ve yükleme, `.bak` yedeği, bozuk dosya durumu.

### 10.2 Keychain

- Birim testleri `SecretStore` protokolünün bellekte çalışan sahte sürümünü kullanır.
- Bir entegrasyon testi gerçek Keychain'i `EnvSwitcher.tests` servis adıyla dener. Test, sonunda tüm kayıtlarını siler.

### 10.3 Arayüz

- UI testi yazılmaz.
- SwiftUI önizlemeleri ana görünümler için örnek verilerle çalışır.
- Elle kontrol listesi `docs/manual-test.md` dosyasında durur. İlk madde: karaca-storefront projesini ekle, tüm dosyaları `test` ortamına geçir, tek bir dosyayı `canli` ortamına geçir, sonra `local` ortamına dön.

## 11. Başarı ölçütleri

1. Kullanıcı karaca-storefront projesini bir dakikadan kısa sürede ekler. Tarama 9 `.env.local` dosyasını bulur ve worktree kopyalarını atlar.
2. Menüden iki tıkla projedeki tüm dosyalar başka bir ortama geçer.
3. Menüden üç tıkla tek bir dosya başka bir ortama geçer.
4. Elle değiştirilmiş bir dosya, kullanıcıya sorulmadan üzerine yazılmaz.
5. Gizli değerler `store.json` dosyasında görünmez.
6. Bir yazma hatasından sonra tüm dosyalar geçişten önceki içeriğe döner.
