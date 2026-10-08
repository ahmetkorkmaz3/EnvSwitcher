# EnvSwitcher — GitHub ile Dağıtım Tasarımı

- **Tarih:** 2026-10-08
- **Durum:** İncelemede
- **Yazar:** Ahmet Korkmaz (Claude ile birlikte)
- **İlgili belge:** `2026-10-07-env-switcher-design.md` (bölüm 2.2 bu belgeyle değişir)

## 1. Amaç

Kullanıcılar EnvSwitcher uygulamasını GitHub'dan indirir ve kolayca kurar. Apple Developer hesabı şu an yoktur. Hesap ileride gelir.

### 1.1 Kullanıcının istekleri

- Uygulama GitHub Releases üzerinden dağıtılır.
- Kurulum basittir.
- Kullanıcı Keychain izin sorusu görmez.
- Proje hem geliştirme hem sürüm açısından tamamlanır: CI, sürüm akışı, lisans, dokümanlar.

### 1.2 Verilen kararlar

| Konu | Karar |
|---|---|
| Kurulum yolu | `curl … \| sh` kurulum betiği. Release sayfasında `.zip` dosyası da durur. |
| Keychain | Tüm sürümler aynı kendinden imzalı sertifikayla imzalanır. Gizli değerler tek bir Keychain kaydında durur. |
| Güncelleme | Uygulama günde bir kez GitHub API'den son sürümü okur ve menüde gösterir. |
| Repo ve lisans | Repo public olur. Lisans MIT. |

### 1.3 Varsayımlar

- Kullanıcılar geliştiricilerdir ve terminal kullanır.
- Kullanıcıların Mac bilgisayarı Apple Silicon veya Intel olabilir.
- Repoyu public yapma adımını Ahmet Korkmaz yapar.

### 1.4 Kapsam dışı (YAGNI)

- Notarization ve Developer ID imzası. Bölüm 9 geçiş adımlarını anlatır.
- Uygulama içinden indirme ve kurma (Sparkle).
- Homebrew tap ve DMG.
- App Store dağıtımı.

## 2. Arka plan: iki macOS kısıtı

### 2.1 Gatekeeper

Tarayıcı, indirdiği dosyaya `com.apple.quarantine` işaretini koyar. macOS, notarize edilmemiş ve karantina işaretli bir uygulamayı açmaz. macOS 15'ten beri sağ tık → Aç yolu bu engeli kaldırmaz. Kullanıcı Sistem Ayarları → Gizlilik ve Güvenlik → "Yine de Aç" yolunu izler.

`curl` indirdiği dosyaya karantina işareti koymaz. Bu nedenle kurulum betiği ile kurulan uygulama engel olmadan açılır.

### 2.2 Keychain izni

Eski (dosya tabanlı) Keychain, bir kaydın erişim listesine kaydı oluşturan uygulamayı ekler. macOS, uygulamayı imzanın "designated requirement" (DR) değeri ile tanır.

- Ad-hoc imzada DR, binary'nin hash değeridir. Her derleme yeni bir DR üretir. Bu nedenle her güncellemeden sonra macOS izin sorar.
- Bir sertifika ile imzada DR, bundle kimliği ve sertifika hash değeridir. Aynı sertifika ile imzalanan tüm sürümler aynı DR değerini taşır. Bu nedenle güncellemeden sonra soru çıkmaz.

Data Protection Keychain bu soruyu tamamen kaldırır. Ama bu Keychain `keychain-access-groups` yetkisini ister. Bu yetki bir Team ID ve provisioning profile ister. Developer hesabı olmadan bu yol yoktur.

## 3. Keychain: tek kayıt

### 3.1 Neden tek kayıt

Bugün her gizli değer ayrı bir Keychain kaydıdır. İmza bir gün değişirse (örnek: Developer ID'ye geçiş), macOS her kayıt için ayrı soru sorar. Bir kullanıcıda 50 gizli değer varsa 50 soru çıkar. Tek kayıt ile en fazla bir soru çıkar.

### 3.2 Kayıt biçimi

| Alan | Değer |
|---|---|
| `kSecClass` | `kSecClassGenericPassword` |
| `kSecAttrService` | `EnvSwitcher` |
| `kSecAttrAccount` | `vault` |
| `kSecValueData` | UTF-8 JSON: `{"version": 1, "secrets": {"<hesap>": "<değer>"}}` |

`<hesap>` değeri bugünkü `SecretAccount.make` çıktısıdır. Bu değer değişmez.

### 3.3 `VaultSecretStore`

Yeni sınıf `EnvCore/Secrets/VaultSecretStore.swift` içinde durur ve `SecretStore` protokolünü uygular. Diğer kod değişmez. Yalnızca `AppState` varsayılan değeri `KeychainSecretStore()` yerine `VaultSecretStore()` olur.

Davranış:

- Sınıf, kasayı ilk erişimde bir kez okur ve bellekte tutar. Erişimi bir `NSLock` korur.
- `read` bellekten okur.
- `write` ve `delete` önce yeni sözlüğü hazırlar. Sonra kaydın tamamını Keychain'e yazar. Yazma başarılı olunca bellekteki sözlüğü değiştirir. Yazma başarısız olursa bellek değişmez ve hata fırlar.
- Var olmayan bir hesabı silmek hata değildir. Bu durumda Keychain'e yazma olmaz.
- Kasa okunamazsa (Keychain hatası veya bozuk JSON), sınıf bu hatayı saklar. Sonraki her işlem aynı hatayı fırlatır. Sınıf bu durumda kasaya asla yazmaz. Bu kural, okunamayan bir kasanın boş bir kasa ile ezilmesini önler.
- Kayıt yoksa kasa boş başlar. Bu durum hata değildir.

Keychain çağrıları küçük bir protokolün arkasında durur:

```swift
protocol KeychainBackend: Sendable {
    func readItem(account: String) throws -> Data?
    func writeItem(_ data: Data, account: String) throws
    func deleteItem(account: String) throws
    /// Returns the accounts of all items with the service name, without their data.
    func listAccounts() throws -> [String]
}
```

`SystemKeychainBackend` gerçek Keychain'i kullanır. Testler bellekte çalışan bir `FakeKeychainBackend` kullanır. Bu sahte sınıf hata da üretebilir.

### 3.4 Eski kayıtları taşıma

Taşıma işlemi kasanın ilk okunmasında bir kez çalışır:

1. `listAccounts()` ile `vault` dışındaki tüm hesapları bul. Hesap yoksa taşıma biter.
2. Her eski kaydı oku. Kasada aynı hesap varsa kasadaki değer kalır. Yoksa eski değer kasaya eklenir.
3. Kasayı Keychain'e yaz.
4. Yazma başarılı olunca eski kayıtları sil. Bir kayıt silinemezse taşıma devam eder. Bu kayıt sonraki açılışta yeniden denenir.

Kurallar:

- Bir eski kayıt okunamazsa (örnek: kullanıcı izin sorusunda "Reddet" seçti), taşıma durur. Kasaya yazma olmaz. Hiçbir eski kayıt silinmez. Uygulama eski kayıtları kullanamaz, bu nedenle kasa okuma hatası durumuna geçer (bölüm 3.3). Uygulama bir uyarı gösterir: "Keychain'deki gizli değerler taşınamadı. Uygulamayı yeniden açın ve izin verin."
- Adım 2'deki kural taşımayı tekrarlanabilir yapar. Yarım kalan bir taşıma bir sonraki açılışta tamamlanır.

Not: Geliştiricinin makinesindeki eski kayıtları ad-hoc derlemeler oluşturdu. Taşıma sırasında bu kayıtlar için soru çıkabilir. Yeni kullanıcılarda eski kayıt yoktur, soru çıkmaz.

### 3.5 Eski kod

`KeychainSecretStore` silinir. Gerçek Keychain testi (`ENVSWITCHER_KEYCHAIN_TESTS=1`) `SystemKeychainBackend` ve `VaultSecretStore` için çalışır. Bu test `EnvSwitcherTests` adlı ayrı bir servis adı kullanır.

## 4. Derleme ve imza

### 4.1 `scripts/bundle.sh`

- Evrensel binary: `swift build -c release --arch arm64 --arch x86_64`. Binary yolu aynı argümanlarla `--show-bin-path` çıktısından gelir.
- Sürüm:
  - `VERSION` ortam değişkeni varsa bu değer kullanılır. CI bu değeri etiketten verir (`v0.2.0` → `0.2.0`).
  - Yoksa `git describe --tags --exact-match` denenir. Etiket yoksa sürüm `0.0.0-dev` olur.
  - `CFBundleVersion` değeri `git rev-list --count HEAD` çıktısıdır.
- İkon: `Resources/AppIcon.icns` dosyası `Contents/Resources/` içine kopyalanır. `Info.plist` dosyasına `CFBundleIconFile` eklenir.
- `Info.plist` dosyasına `NSHumanReadableCopyright` eklenir.
- İmza: `codesign --force --options runtime --timestamp=none --sign "$CODESIGN_IDENTITY"`. `CODESIGN_IDENTITY` yoksa ad-hoc imza (`-`) kullanılır ve betik bir uyarı yazar: "Ad-hoc imza: Keychain her derlemeden sonra izin sorar."
- Hardened runtime şimdi açılır. Notarization bu ayarı ister. Uygulama hiçbir ek yetki (entitlement) kullanmaz.
- Betik sonunda `codesign --verify --strict` çalıştırır.

### 4.2 Uygulama ikonu

`scripts/make-icon.swift` bir SF Symbol çizimini renkli bir arka plan üzerinde 1024 px PNG olarak üretir. `scripts/make-icon.sh` bu PNG dosyasından `sips` ve `iconutil` ile `Resources/AppIcon.icns` üretir. `.icns` dosyası repoya girer. Geliştirici bu dosyayı kendi ikonuyla değiştirebilir.

### 4.3 `scripts/make-signing-cert.sh`

Betik kendinden imzalı sertifikayı bir kez oluşturur:

1. `openssl` ile 10 yıllık bir RSA 2048 sertifikası oluşturur. Sertifika `extendedKeyUsage=codeSigning` taşır. Ad: `EnvSwitcher Self-Signed`.
2. Anahtar ve sertifikayı şifreli bir `.p12` dosyasına koyar. Şifre rastgele üretilir.
3. `.p12` dosyasını giriş Keychain'ine alır. Bu adım yerel derlemelerin de aynı imzayı kullanmasını sağlar.
4. Şu üç değeri ekrana yazar: `.p12` dosyasının yolu, base64 metni, şifre. Geliştirici bu değerleri GitHub Secrets'a ve parola yöneticisine ekler.

Betik var olan bir sertifikanın üzerine yazmaz. Aynı adlı bir kimlik varsa betik durur.

**Uyarı:** `.p12` dosyası kaybolursa yeni sertifikanın DR değeri farklı olur. Bu durumda her kullanıcı bir kez izin sorusu görür. Bu nedenle `.p12` dosyası parola yöneticisinde yedeklenir.

### 4.4 Yerel geliştirme

Geliştirici yerel derlemeleri aynı sertifika ile imzalar:

```sh
CODESIGN_IDENTITY="EnvSwitcher Self-Signed" scripts/bundle.sh
```

README bu komutu gösterir.

## 5. CI ve sürüm

### 5.1 `.github/workflows/ci.yml`

- Tetik: `main` dalına push ve her pull request.
- Runner: `macos-15`.
- Adımlar: `swift test`, `scripts/bundle.sh` (ad-hoc), `shellcheck scripts/*.sh install.sh`.

### 5.2 `.github/workflows/release.yml`

- Tetik: `v*` biçiminde bir etiket push edilir.
- İzin: `contents: write`.
- Adımlar:
  1. Etiketin `vX.Y.Z` biçiminde olduğunu kontrol et. Değilse dur.
  2. `CHANGELOG.md` içinde `## [X.Y.Z]` başlığını bul. Başlık yoksa dur. Bu bölüm sürüm notları olur.
  3. `swift test`.
  4. `SIGNING_CERT_P12_BASE64` ve `SIGNING_CERT_PASSWORD` secret değerlerini kontrol et. Biri yoksa dur. Ad-hoc imzalı bir sürüm yayınlanmaz, çünkü bu sürüm Keychain DR değerini bozar.
  5. Geçici bir Keychain oluştur. `.p12` dosyasını içine al. `security set-key-partition-list` ile `codesign` erişimine izin ver.
  6. `VERSION=X.Y.Z CODESIGN_IDENTITY="EnvSwitcher Self-Signed" scripts/bundle.sh`.
  7. `ditto -c -k --keepParent build/EnvSwitcher.app EnvSwitcher-X.Y.Z.zip`.
  8. `shasum -a 256` ile `EnvSwitcher-X.Y.Z.zip.sha256` üret.
  9. `gh release create vX.Y.Z` ile release oluştur ve iki dosyayı ekle.
  10. Geçici Keychain'i sil (`if: always()`).

### 5.3 Sürüm çıkarma adımları

`docs/release.md` bu adımları anlatır:

1. `CHANGELOG.md` içine `## [X.Y.Z] - YYYY-MM-DD` bölümünü ekle.
2. Commit et ve `main` dalına push et.
3. `git tag vX.Y.Z && git push origin vX.Y.Z`.
4. Actions sekmesinde iş akışının bitmesini bekle (yaklaşık 10 dk).
5. Kurulum komutunu temiz bir kullanıcı hesabında dene.

## 6. Kurulum betiği

Konum: repo kökünde `install.sh`. Komut:

```sh
curl -fsSL https://raw.githubusercontent.com/ahmetkorkmaz3/EnvSwitcher/main/install.sh | sh
```

Betik POSIX `sh` kullanır. `jq` istemez. Adımlar:

1. macOS dışında bir sistemde dur. macOS 14'ten eski bir sürümde dur.
2. Sürümü bul. `ENVSWITCHER_VERSION` değişkeni varsa bu sürümü kullan. Yoksa `https://api.github.com/repos/ahmetkorkmaz3/EnvSwitcher/releases/latest` adresinden `tag_name` değerini oku.
3. `mktemp -d` ile geçici bir klasör oluştur. Betik çıkınca klasörü sil (`trap`).
4. `.zip` ve `.sha256` dosyalarını indir. `shasum -a 256 -c` ile kontrol et. Hash uymazsa dur.
5. `ditto -x -k` ile zip dosyasını aç.
6. Uygulama çalışıyorsa kapat: `osascript -e 'quit app "EnvSwitcher"'`. 5 saniye bekle. Hâlâ çalışıyorsa `pkill -x EnvSwitcher`.
7. Hedef: `/Applications`. Klasör yazılabilir değilse `sudo` kullan ve kullanıcıya nedenini yaz.
8. Eski uygulamayı sil ve yenisini `ditto` ile kopyala.
9. Karantina işaretini kaldır: `xattr -dr com.apple.quarantine` (işaret yoksa hata yok sayılır).
10. Uygulamayı aç: `open /Applications/EnvSwitcher.app`. Kurulan sürümü yaz.

Her hata mesajı nedeni ve bir sonraki adımı yazar. Örnek: "İndirme başarısız: <url>. İnternet bağlantısını kontrol edin ve komutu yeniden çalıştırın."

Aynı komut güncelleme için de çalışır.

## 7. Güncelleme kontrolü

### 7.1 `EnvCore` mantığı

`EnvCore/Update/` altında:

- `SemanticVersion`: `X.Y.Z` biçimini ayrıştırır ve karşılaştırır. Baştaki `v` kabul edilir. Başka biçimler (`0.0.0-dev` dahil) `nil` döner.
- `UpdateChecker`: Bir `HTTPClient` protokolü üzerinden `releases/latest` yanıtını okur. Yanıttan `tag_name` ve `html_url` alanlarını çözer. Sonuç: `.upToDate`, `.available(version, url)`.
- Zamanlama kuralı saf bir fonksiyondur: son kontrol tarihi yoksa veya 24 saatten eskiyse kontrol gerekir.

### 7.2 Uygulama davranışı

- Uygulama açılışta ve sonra her saat zamanlama kuralını çalıştırır. Kontrol gerekiyorsa `UpdateChecker` çalışır.
- Son kontrol tarihi `UserDefaults` içinde durur.
- Geçerli sürüm `CFBundleShortVersionString` değeridir. Bu değer `SemanticVersion` olarak çözülemezse (yerel `0.0.0-dev` derlemesi) kontrol çalışmaz.
- Ağ hatası veya geçersiz yanıt sessizce yok sayılır. Bir sonraki saatte yeniden denenir. Bu durumda son kontrol tarihi değişmez.
- Yeni sürüm varsa menünün altında, "Çık" satırının üstünde şu satır görünür: "Güncelleme var: X.Y.Z". Satır seçilince:
  1. Kurulum komutu panoya kopyalanır.
  2. Release sayfası tarayıcıda açılır.
  3. Bir bildirim yazısı gösterilir: "Kurulum komutu panoya kopyalandı. Terminale yapıştırın."
- Menünün en altında sürüm satırı görünür (seçilemez): "Sürüm X.Y.Z".

## 8. Dokümanlar ve repo dosyaları

- `LICENSE`: MIT, telif sahibi Ahmet Korkmaz, 2026.
- `CHANGELOG.md`: "Keep a Changelog" biçimi. İlk bölüm `## [0.2.0]`. Bu bölüm bugüne kadarki özellikleri özetler.
- `README.md`:
  - Kurulum bölümü en üstte durur: tek satır komut.
  - Elle kurulum: Release sayfasından zip indirme, `/Applications` içine taşıma, "Yine de Aç" adımları.
  - Güncelleme: aynı komut.
  - Kaldırma: uygulamayı, `~/Library/Application Support/EnvSwitcher` klasörünü ve `security delete-generic-password -s EnvSwitcher -a vault` ile kasayı silme.
  - "Keychain izin sorusu" bölümü yeni imza düzenini anlatır.
  - Derleme bölümü `make-signing-cert.sh` ve `CODESIGN_IDENTITY` kullanımını anlatır.
- `docs/release.md`: Bölüm 5.3 ve bölüm 9.
- `docs/manual-test.md`: Bölüm 10.3 maddeleri eklenir.
- Ana tasarım belgesindeki bölüm 2.2, bu belgeye bir bağlantı ile değişir.

## 9. İleride: Developer ID ve notarization

Developer hesabı gelince şu adımlar uygulanır. Bu adımlar `docs/release.md` içinde durur:

1. Bir "Developer ID Application" sertifikası oluştur. `.p12` dosyasını GitHub Secrets'a ekle.
2. `release.yml` içinde imza kimliğini değiştir. `--timestamp=none` yerine `--timestamp` kullan.
3. `xcrun notarytool submit --wait` ve `xcrun stapler staple` adımlarını ekle.
4. Kullanıcılar bir kez Keychain izin sorusu görür. Bu soru tek kasa kaydı içindir. Sürüm notları bu soruyu önceden açıklar.
5. İsteğe bağlı: Data Protection Keychain'e geçiş. Bu geçiş `keychain-access-groups` yetkisi ve bir provisioning profile ister. `VaultSecretStore` bu geçişi tek bir kaydı kopyalayarak yapar.

## 10. Test

### 10.1 Birim testleri (Swift Testing)

- `VaultSecretStore`:
  - Yazma, okuma, silme. Var olmayan hesabı silme Keychain'e yazmaz.
  - Keychain yazma hatası bellekteki değeri değiştirmez.
  - Okuma hatası ve bozuk JSON: sonraki her işlem hata fırlatır ve kasaya yazma olmaz.
  - Kayıt yoksa kasa boş başlar.
  - Taşıma: eski kayıtlar kasaya girer ve silinir. Kasadaki değer eski değerden önce gelir. Bir eski kayıt okunamazsa hiçbir şey silinmez ve kasaya yazma olmaz. Silme hatası taşımayı durdurmaz.
- `SemanticVersion`: ayrıştırma, `v` öneki, geçersiz biçimler, karşılaştırma.
- `UpdateChecker`: yeni sürüm, aynı sürüm, eski sürüm, bozuk JSON, HTTP hatası.
- Zamanlama kuralı: tarih yok, 23 saat, 25 saat.

### 10.2 Gerçek Keychain testi

`ENVSWITCHER_KEYCHAIN_TESTS=1 swift test --filter VaultKeychainTests`. Test `EnvSwitcherTests` servis adını kullanır ve sonunda kayıtları siler.

### 10.3 Elle test (`docs/manual-test.md`)

1. Eski kayıtları olan bir makinede yeni sürümü aç. Gizli değerlerin aynı kaldığını kontrol et. `security find-generic-password -s EnvSwitcher` komutunun yalnızca `vault` kaydını gösterdiğini kontrol et.
2. Aynı sertifika ile iki farklı derleme yap. İkincisini aç. Keychain sorusunun çıkmadığını kontrol et.
3. Temiz bir kullanıcı hesabında kurulum komutunu çalıştır. Uygulamanın Gatekeeper uyarısı olmadan açıldığını kontrol et.
4. Uygulama açıkken kurulum komutunu yeniden çalıştır. Uygulamanın kapanıp yeni sürümle açıldığını kontrol et.
5. `ENVSWITCHER_VERSION` ile eski bir sürüm kur. Menüde "Güncelleme var" satırının çıktığını kontrol et.

## 11. Başarı ölçütleri

- Bir kullanıcı tek bir terminal komutu ile uygulamayı kurar ve açar. Gatekeeper uyarısı çıkmaz.
- Yeni bir kullanıcı hiçbir Keychain izin sorusu görmez. Güncellemeden sonra da görmez.
- Bir `vX.Y.Z` etiketi push edilince, 15 dakikadan kısa sürede imzalı bir release yayınlanır.
- Uygulama Apple Silicon ve Intel Mac üzerinde çalışır.
- Uygulama yeni bir sürümü en geç 25 saat içinde menüde gösterir.
