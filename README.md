# EnvSwitcher

Bir projedeki `.env` dosyalarını menü çubuğundan ortamlar arasında değiştiren bir macOS uygulaması.

- Tasarım: `docs/superpowers/specs/2026-10-07-env-switcher-design.md`
- Elle test listesi: `docs/manual-test.md`

## Gereksinimler

- macOS 14 veya üstü
- Xcode (aktif olmalı):

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
```

## Derleme ve çalıştırma

```sh
swift test                         # EnvCore testleri
scripts/bundle.sh                  # build/EnvSwitcher.app oluşturur
open build/EnvSwitcher.app
```

Gerçek Keychain testini çalıştırmak için:

```sh
ENVSWITCHER_KEYCHAIN_TESTS=1 swift test --filter SecretsTests
```

## Keychain izin sorusu

Ad-hoc imza her derlemede değişir. Bu nedenle macOS yeni bir derlemeden sonra Keychain izni sorabilir. Bu soruyu önlemek için kendinden imzalı bir sertifika oluşturun (Anahtar Zinciri Erişimi → Sertifika Asistanı → Sertifika Oluştur, tür: Kod İmzalama) ve şu komutu kullanın:

```sh
CODESIGN_IDENTITY="EnvSwitcher Dev" scripts/bundle.sh
```
