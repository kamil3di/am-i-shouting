# ShoutMeter

macOS menü barında duran küçük bir seviye göstergesi: ortam gürültüsünü sürekli
öğrenir, sesini onunla karşılaştırır ve bağırıp bağırmadığını renkle söyler.

```
[▬▬▬▬▬▭|▭]   yeşil = normal · sarı = yüksek · kırmızı = bağırıyorsun
```

Dock ikonu yok (`LSUIElement`), pencere yok. Ses hiçbir yere kaydedilmez veya
gönderilmez; her şey bellekte, anlık seviye hesabı olarak kalır.

## Nasıl çalışır

Tek bir mikrofonla "ortam sesi" ile "senin sesin" fiziksel olarak ayrılamaz —
mikrofon ikisini birlikte duyar. Bu yüzden ShoutMeter şunu ölçer: **sesin,
ortamın gürültü tabanının kaç dB üstünde.**

1. **Gürültü tabanı** — son 12 saniyenin 10. yüzdeliği. Konuşma arasındaki
   boşluklar odanın kendi sesini gösterir, taban bunlardan öğrenilir.
   Taban en fazla ~3 dB/s yükselebilir, yani kesintisiz bağırsan bile sesin
   "ortam" sayılmaz; düşerken hızlıdır (20 dB/s), çünkü oda gerçekten
   sessizleşmiş olabilir.
2. **Anlık ses seviyesi** — son 0.8 saniyenin 80. yüzdeliği. Tepe değil:
   tek bir kapı çarpması veya klavye tıkı 80. yüzdeliğe ulaşamaz, gerçek
   konuşma kolayca ulaşır.
3. **Fark** = ses − taban. Eşikler bu farkın üstünde durur:
   normal (varsayılan +22 dB) → yüksek (+5 dB) → bağırıyor (+11 dB).
4. **Histerezis** — kırmızıya geçiş hızlı (0.15 s), sakinleşme yavaş (0.9 s),
   böylece kelimeler arasında renk titremez.

Sonuç: sessiz bir ofiste bağırmak sayılan ses seviyesi, gürültülü bir kafede
normal konuşma sayılır — ölçüt ortamla birlikte kayar.

## Kurulum

```bash
make app && open dist/ShoutMeter.app
```

`make app` derler, `dist/ShoutMeter.app` paketini kurar ve ad-hoc imzalar.
Sabit bir imza kimliği kullanıldığı için macOS mikrofon iznini yeniden
derlemeler arasında hatırlar. İlk çalıştırmada mikrofon izni sorar.

Intel + Apple Silicon evrensel derleme için `make universal`.

## Kullanım

Menü barındaki bara tıklayınca panel açılır:

- **Ortam gürültüsü / anlık sesin / fark / bağırma eşiği** — canlı dB değerleri.
- **Normal sesimi ölç** — 5 saniye normal ses tonunda konuş; eşikler senin
  sesine göre yeniden ayarlanır ve kaydedilir. Mikrofonu, sesini ve oturma
  mesafeni bilen tek şey bu kalibrasyondur, en çok işe yarayan ayar budur.
- **Hassasiyet** — −8…+8 dB. Sağa kaydırmak eşikleri düşürür (daha erken uyarır).
- **Duraklat** — mikrofonu bırakır.

Ayarlar `UserDefaults`'ta saklanır.

## Teşhis modu

Menü barına bakmadan ne ölçüldüğünü görmek için:

```bash
./dist/ShoutMeter.app/Contents/MacOS/ShoutMeter --probe 15
```

Saniyede birkaç satır giriş / taban / ses / fark / durum basar. Eşikleri
kendi odanda ayarlarken veya "neden kırmızı oldu" diye sorarken en hızlı yol.

## Bilinen sınırlar

- **AirPods ve benzeri Bluetooth kulaklıklar** kendi gürültü ve yankı
  bastırmasını uygular. Bilgisayarın kendi çaldığı ses mikrofona büyük ölçüde
  ulaşmaz (bu yüzden hoparlörden ses çalarak test etmek çalışmaz) ve gürültü
  tabanı gerçek odadan daha sessiz görünür. Kalibrasyon bunu telafi eder.
- **İlk ~1.5 saniye** karar verilmez, taban öğrenilene kadar durum "sessiz"dir.
  Giriş cihazı değiştiğinde (kulaklık takılınca) tap yeniden kurulur ve bu
  öğrenme sıfırdan başlar.
- **Konuşma tanıma yok.** Yeterince yüksek herhangi bir sürekli ses konuşma
  sayılır: kalorifer, klima, yanındaki masa. Sinyal tamamen sessizse (susturulmuş
  mikrofon) panel "Sinyal yok" der, tabanı bozmaz.
- **dBFS mutlak bir gürültü ölçüsü değildir.** Mikrofon kazancına bağlıdır;
  bu yüzden her şey ortama *göreli* ölçülür.

## Geliştirme

```bash
swift build          # derle
swift test           # 32 test
make run             # derle, kur, çalıştır
make clean
```

Detektör zamanı `LevelSample.time` üzerinden alır (duvar saatinden değil), bu
yüzden testler sanal saatle 20 kare/saniye besleyip taban eğimi, histerezis ve
pencere davranışını deterministik olarak doğrular.

| Dosya | Sorumluluk |
| --- | --- |
| `AudioMonitor.swift` | `AVAudioEngine` tap, arabellekleri 40 ms'lik dilimlere bölüp RMS/tepe dBFS üretir |
| `ShoutDetector.swift` | Gürültü tabanı, fark, eşikler, histerezis, kalibrasyon |
| `MeterModel.swift` | Ses + detektör + kalıcı ayarlar, `ObservableObject` |
| `StatusItemController.swift` | `NSStatusItem`, canlı bar, panel |
| `LevelBarImage.swift` | Menü bar görüntüsünün çizimi |
| `DetailView.swift` | SwiftUI panel |
| `Probe.swift` | `--probe` teşhis modu |
