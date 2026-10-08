# Katkı rehberi

EnvSwitcher'a katkı için teşekkürler. Bu dosya geliştirme ortamını, test adımlarını ve pull request kurallarını anlatır.

## Hata bildirme ve öneri

1. Önce [Issues](https://github.com/ahmetkorkmaz3/EnvSwitcher/issues) sayfasında aynı konuyu arayın.
2. Yeni bir issue açın. Şu bilgileri yazın:
   - macOS sürümü ve işlemci (Apple Silicon veya Intel).
   - EnvSwitcher sürümü. Sürüm menünün en altında görünür.
   - Adımlar, beklenen sonuç ve gerçek sonuç.
3. Issue içine gerçek `.env` değerlerini, token veya şifre yazmayın. Örnek değerler kullanın.

Büyük bir değişiklikten önce bir issue açın ve fikri tartışın.

## Geliştirme ortamı

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

**Gerçek Keychain testi:**

```sh
ENVSWITCHER_KEYCHAIN_TESTS=1 swift test --filter VaultKeychainTests
```

Bu test gerçek Keychain'e yazar. Bu nedenle varsayılan olarak çalışmaz.

**Betik kontrolü:** CI tüm betikleri `shellcheck` ile kontrol eder. Push etmeden önce aynı kontrolü yapın:

```sh
brew install shellcheck
shellcheck scripts/*.sh install.sh
```

### İmza ve Keychain izin sorusu

Keychain bir kaydı oluşturan uygulamayı imzası ile tanır. Ad-hoc imza her derlemede değişir. Bu nedenle ad-hoc bir derlemeden sonra macOS bir kez izin sorar. Tüm gizli değerler tek bir kayıtta durur, bu nedenle soru bir kez çıkar.

Bu soruyu önlemek için yerel bir sertifika ile imzalayın:

1. Sertifikayı bir kez oluşturun: `scripts/make-signing-cert.sh`. Sertifika zaten varsa ve `.p12` dosyası sizdeyse, dosyayı çift tıklayıp giriş Keychain'ine alın.
2. Derleyin: `CODESIGN_IDENTITY="EnvSwitcher Self-Signed" scripts/bundle.sh`

## Proje yapısı

| Klasör | İçerik |
|---|---|
| `Sources/EnvCore` | Arayüzden bağımsız mantık: ayrıştırma, tarama, Keychain, ortam değiştirme. Testler bu modülü kapsar. |
| `Sources/EnvSwitcher` | SwiftUI uygulaması: menü çubuğu, yönetim penceresi, fark penceresi. |
| `Tests/EnvCoreTests` | Birim testleri. `Support/` içinde sahte dosya yazıcı ve sahte Keychain var. |
| `site/` | Tanıtım sayfası. GitHub Pages bu klasörü yayınlar. |
| `docs/manual-test.md` | Her sürümden önce uygulanacak elle test listesi. |
| `docs/release.md` | Sürüm çıkarma adımları. |
| `docs/superpowers/specs/` | Tasarım dokümanları. |
| `scripts/` | Derleme, ikon, sertifika ve CHANGELOG betikleri. |
| `install.sh` | Kurulum ve güncelleme betiği. |
| `.github/workflows/` | CI, release ve Pages iş akışları. |

## Kod kuralları

- Mantığı `EnvCore` içine yazın. `EnvSwitcher` modülü yalnızca arayüzü içerir.
- `EnvCore` içindeki her değişiklik için bir test ekleyin. Disk ve Keychain için `Tests/EnvCoreTests/Support` içindeki sahte sınıfları kullanın.
- Gizli değerleri log, hata mesajı veya `store.json` içine yazmayın.
- Kullanıcıya görünen metinler Türkçedir. Kısa ve net cümleler kullanın.
- Çevresindeki kodun stilini izleyin.

## Commit mesajları

Commit mesajları İngilizce ve [Conventional Commits](https://www.conventionalcommits.org/) biçimindedir:

```
feat(core): check GitHub for a newer release
fix: keep the old app when the install copy fails
ci: use actions/checkout@v5, because v4 runs on the deprecated Node.js 20
```

Kullanılan türler: `feat`, `fix`, `docs`, `ci`, `build`, `test`, `refactor`. Kapsam isteğe bağlıdır: `core` veya `app`. Bir nedeni varsa mesaja `because` ile ekleyin.

## Pull request

1. `main` dalından yeni bir dal açın. Örnek: `feat/compare-filter`, `fix/install-path`.
2. Değişikliği yapın. `swift test` ve `shellcheck` komutlarını çalıştırın.
3. Arayüz değiştiyse ekran görüntüsü ekleyin.
4. Kullanıcının göreceği bir değişiklik varsa `CHANGELOG.md` dosyasının başında `## [Yayınlanmadı]` bölümüne bir satır ekleyin.
5. Pull request açın. CI geçince inceleme başlar.

## Tanıtım sayfası

Tanıtım sayfası `site/index.html` dosyasıdır. Sayfa tek bir HTML dosyasıdır. Derleme adımı yoktur.

- Yerelde görmek için: `open site/index.html`
- `main` dalına push edince `.github/workflows/pages.yml` sayfayı yayınlar.
- İlk yayından önce bir kez: GitHub → Settings → Pages → Source → **GitHub Actions** seçin.

## Sürüm çıkarma

Sürüm adımları: [`docs/release.md`](docs/release.md). Sürümden önce [`docs/manual-test.md`](docs/manual-test.md) listesini uygulayın.

## Lisans

Katkılarınız [MIT lisansı](LICENSE) ile yayınlanır.
