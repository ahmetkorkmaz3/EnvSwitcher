# Sürüm çıkarma

## Bir kez: imza sertifikası

1. `scripts/make-signing-cert.sh` komutunu çalıştırın. Betik `~/EnvSwitcher-signing` klasörünü oluşturur.
2. Betiğin yazdığı adımları uygulayın: iki GitHub secret ekleyin ve `.p12` dosyasını parola yöneticisine kaydedin.
3. `~/EnvSwitcher-signing` klasörünü silin.

**Uyarı:** `.p12` dosyasını kaybederseniz yeni bir sertifika gerekir. Bu durumda her kullanıcı bir kez Keychain izin sorusu görür.

## Her sürüm

1. `CHANGELOG.md` dosyasının başına `## [X.Y.Z] - YYYY-MM-DD` bölümünü ekleyin.
2. Commit edin ve `main` dalına push edin.
3. Etiketi oluşturun ve push edin:

   ```sh
   git tag vX.Y.Z
   git push origin vX.Y.Z
   ```

4. GitHub → Actions → Release iş akışının bitmesini bekleyin (yaklaşık 10 dk).
5. Kurulum komutunu deneyin:

   ```sh
   curl -fsSL https://raw.githubusercontent.com/ahmetkorkmaz3/env-management/main/install.sh | sh
   ```

6. `docs/manual-test.md` bölüm 9 adımlarını uygulayın.

İş akışı şu durumlarda durur: etiket `vX.Y.Z` biçiminde değil, CHANGELOG bölümü yok, testler başarısız, imza secret değerleri yok.

## İleride: Developer ID ve notarization

Apple Developer hesabı gelince şu adımları uygulayın:

1. Bir "Developer ID Application" sertifikası oluşturun. `.p12` dosyasını `SIGNING_CERT_P12_BASE64` ve `SIGNING_CERT_PASSWORD` secret değerlerine yazın.
2. `release.yml` içinde `CODESIGN_IDENTITY` değerini sertifika adı ile değiştirin.
3. `scripts/bundle.sh` içinde `--timestamp=none` yerine `--timestamp` kullanın.
4. Paketleme adımından sonra şu adımları ekleyin: `xcrun notarytool submit EnvSwitcher-X.Y.Z.zip --wait` ve `xcrun stapler staple build/EnvSwitcher.app`. Staple işleminden sonra zip dosyasını yeniden oluşturun.
5. Sürüm notlarına şu satırı ekleyin: "Bu sürümden sonra macOS bir kez Keychain izni sorar. Her Zaman İzin Ver seçin." Kasa tek bir kayıt olduğu için soru bir kez çıkar.
6. İsteğe bağlı: Data Protection Keychain. Bu geçiş `keychain-access-groups` yetkisi ve bir provisioning profile ister.
