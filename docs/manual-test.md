# EnvSwitcher elle test listesi

Her sürümden önce bu listeyi uygulayın. Gerçek bir repo yerine bir kopya kullanın.

## Hazırlık

```sh
rm -rf /tmp/karaca-copy
rsync -a --exclude node_modules --exclude .git --exclude .next --exclude .turbo \
  ~/work/karaca/karaca-storefront/ /tmp/karaca-copy/
scripts/bundle.sh && open build/EnvSwitcher.app
```

## 1. Uçtan uca geçiş (spec 10.3, ilk madde)

1. Menüden "Proje Ekle…" seçin ve `/tmp/karaca-copy` klasörünü seçin.
   - Beklenen: 9 `.env.local` dosyası seçili, `.env.example` dosyaları seçili değil.
   - Beklenen: `.claude/worktrees` altındaki dosyalar listede yok.
2. "Ekle" düğmesine basın. Menü çubuğu `karaca-copy · local` gösterir.
3. Pencerede `apps/cart/.env.local` seçin, `test` segmentine geçin, "Diğer ortamdan kopyala → local" seçin, sonra `NEXT_PUBLIC_APP_ENV` değerini `test` yapın. Diğer 8 dosya için de "Diğer ortamdan kopyala → local" uygulayın.
4. Menüden projeyi açın, "Tüm dosyalar → test" seçin.
   - Beklenen: 9 dosyanın hepsi yeniden yazılır. `apps/cart/.env.local` içinde `NEXT_PUBLIC_APP_ENV=test` var.
   - Beklenen: menü çubuğu `karaca-copy · test` gösterir.
5. Menüden "Dosyalar → apps/checkout/.env.local → canli" seçin.
   - Beklenen: Korumalı ortam onayı çıkar: "1 dosya değişecek." "Geç" düğmesine basın.
   - Beklenen: menü çubuğu `karaca-copy · karışık` gösterir.
6. Menüden "Tüm dosyalar → local" seçin.
   - Beklenen: tüm dosyalar `local` olur. Menü çubuğu `karaca-copy · local` gösterir.

## 2. Elle değişiklik

1. `apps/cart/.env.local` dosyasını bir editörde açın ve bir değeri değiştirin.
2. Menüyü açın. Beklenen: proje satırında ⚠︎ var.
3. "Tüm dosyalar → test" seçin. Beklenen: "Değişiklikler" penceresi açılır ve değişen anahtar `~` ile görünür.
4. "Mevcut ortama kaydet" seçin. Beklenen: geçiş tamamlanır. Pencerede `local` segmenti yeni değeri gösterir.
5. Aynı adımları "At ve geç" ve "İptal" için tekrarlayın. "İptal" sonrası dosya değişmez.

## 3. Hata durumları

1. `rm -rf /tmp/karaca-copy/apps/plp` çalıştırın ve "Tüm dosyalar → test" seçin.
   - Beklenen: hata mesajı `apps/plp/.env.local` dosyasını adıyla gösterir. Hiçbir dosya değişmez.
2. `mv /tmp/karaca-copy /tmp/karaca-moved` çalıştırın ve menüyü açın.
   - Beklenen: proje "Klasör bulunamadı" gösterir. "Klasörü yeniden seç…" ile `/tmp/karaca-moved` seçince proje yeniden çalışır.
3. Uygulamayı kapatın. `~/Library/Application Support/EnvSwitcher/store.json` dosyasının başına `x` yazın. Uygulamayı açın.
   - Beklenen: "Depo geri yüklendi" uyarısı çıkar ve projeler görünür.

## 4. Gizli değerler

1. `grep -c TURNSTILE_SECRET_KEY ~/Library/Application\ Support/EnvSwitcher/store.json` çalıştırın.
   - Beklenen: anahtar adı görünür, ama değeri görünmez (`"value"` alanı yok).
2. Pencerede bir değerin "Gizli" kutusunu kaldırın. Beklenen: değer görünür hale gelir ve `store.json` içine yazılır.

## 5. Ekleme ve düzenleme

1. "Proje Ekle…" ile zaten ekli olan `/tmp/karaca-copy` klasörünü yeniden seçin.
   - Beklenen: "Bu klasör zaten karaca-copy projesinde" uyarısı çıkar. "Ekle" düğmesi pasif kalır.
2. Yeni bir projede, `test` ortamına hiç değer girmeden "Tüm dosyalar → test" seçin.
   - Beklenen: "test ortamında bu dosyalar için değer yok" uyarısı çıkar. "Vazgeç" ile hiçbir dosya değişmez.
3. `mkdir -p /tmp/karaca-copy/apps/new && echo A=1 > /tmp/karaca-copy/apps/new/.env.local` çalıştırın. Proje ayarlarında "Dosya ekle" ile ekleyin.
   - Beklenen: dosya, projenin diskteki ortamına `A=1` değeriyle eklenir. Menüyü açınca ⚠︎ görünmez.
4. Diskteki ortamda bir değeri değiştirin.
   - Beklenen: "Değişiklikler diske yazılmadı" uyarısı çıkar. "Diske yaz" sonrası uyarı "Diskteki dosya güncel" olur.
5. `chmod 600 apps/cart/.env.local` çalıştırın ve ortam değiştirin. Beklenen: `ls -l` hâlâ `-rw-------` gösterir.

## 6. Ortam karşılaştırma

1. `apps/cart/.env.local` dosyasını seçin ve **Karşılaştır** görünümüne geçin.
   - Beklenen: her anahtar bir satırda, `local`, `test`, `canli` değerleri yan yana görünür.
   - Beklenen: `test` ve `canli` boşsa tüm satırlar kırmızı işaretle "eksik" gösterir.
2. Bir satırda **Eksiklere kopyala → local değerini kopyala** seçin.
   - Beklenen: değer `test` ve `canli` hücrelerine yazılır. İşaret gri olur.
3. `test` hücresindeki değeri değiştirip Return tuşuna basın.
   - Beklenen: satır turuncu "farklı" işaretini alır. **Farklı** filtresinde görünür.
4. Boş bir `canli` hücresine değer yazın ve başka bir hücreye tıklayın.
   - Beklenen: anahtar `canli` ortamına eklenir.
5. Gizli bir anahtarı eksik bir ortama kopyalayın.
   - Beklenen: yeni değer de gizli olur. `store.json` içinde değer görünmez.
6. Birkaç anahtarı yalnızca `local` ortamına, birini yalnızca `test` ortamına ekleyin. Üst çubukta **Tüm eksiklere kopyala → Her anahtar için ilk dolu ortamdan** seçin ve **Ekle** düğmesine basın.
   - Beklenen: **Eksik** filtresi 0 gösterir. Var olan değerler değişmez.
7. Aynı durumu yeniden kurun ve **Tüm eksiklere kopyala → local değerlerini kopyala** seçin.
   - Beklenen: `local` anahtarları eklenir. "1 anahtar atlandı" uyarısı yalnızca `test` anahtarını listeler.
8. **Düzenle** görünümüne dönün ve eksik anahtarı olan bir ortam seçin.
   - Beklenen: alt çubukta "N anahtar bu ortamda eksik" düğmesi çıkar. Düğme Karşılaştır görünümünü Eksik filtresiyle açar.

## 7. Panodan yapıştırma

1. `apps/cart/.env.local` dosyasında boş bir ortam seçin. Panoya `A=1`, `B=2` ve `API_TOKEN=x` satırlarını kopyalayın. **Panodan yapıştır** düğmesine basın.
   - Beklenen: soru çıkmaz. Üç anahtar eklenir. `API_TOKEN` gizli olarak işaretlenir.
2. Panoya `A=9` ve `C=3` satırlarını kopyalayın ve yeniden yapıştırın.
   - Beklenen: "1 anahtarın ... ortamında başka bir değeri var" sorusu çıkar.
   - **Yalnızca eksikleri ekle** seçin. Beklenen: `A` değeri `1` kalır. `C=3` eklenir.
3. 2. adımı tekrarlayın ve **Üzerine yaz** seçin. Beklenen: `A` değeri `9` olur.
4. Panoya `KEY=değer` satırı olmayan bir metin kopyalayıp yapıştırın. Beklenen: "Panoda değer yok" uyarısı çıkar.

## 8. Arayüz

1. Sistem ayarlarından koyu moda geçin. Beklenen: pencere, menü ve sheet okunur kalır.
2. Menüdeki ortam noktaları ortam renklerini gösterir.
