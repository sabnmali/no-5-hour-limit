# İnceleme ve doğrulama — 5 Eylül 2026

## Düzeltilen bulgular

| Bulgu | Değişiklik |
|---|---|
| Bash durumu kilitten önce okuyordu; bekleyen işlem ikinci bir mesaj gönderebiliyordu. Windows'ta elle başlatılan işlemler kilitlenmiyordu. | Kilit altında durum yeniden okunuyor; Windows dosya kilidi eklendi. |
| Unix kilidi yalnızca yaşına bakılarak siliniyordu; uzun süren canlı işlemle çakışabiliyordu. | İşlem kimliği kontrolü eklendi. |
| Takılan CLI sonraki servisi ve zamanlayıcıyı engelleyebiliyordu. | Her CLI çağrısına yaklaşık 120 saniye sınır ve süreç temizliği eklendi. |
| Boş/geçersiz CLI cevabı başarı sayılabiliyordu. | Claude başarı sonucu ve Codex tamamlanmış tur doğrulaması eklendi. |
| PowerShell yazma hataları her zaman catch'e düşmüyordu; hedef klasörse yanlış yere yazılabiliyordu. | Atomik dosya değiştirme ve hata durumunda başarısız çıkış uygulandı. Mevcut dosya değiştirme ayrıca test edildi. |
| Ham CLI çıktısına dayanan kayıtlar yalnızca belirli anahtar biçimlerini maskeleyebiliyordu. | Ham hata çıktısı kayıtlardan çıkarıldı; redaktör ek koruma olarak kaldı. |
| Codex kişisel ayarları, MCP yapılandırmasını ve proje talimatlarını yükleyebiliyordu. | Kullanıcı ayarları/kuralları ve proje belgesi yükleme kapatıldı; salt okunur mod korundu. |
| Claude restricted modu bütün araçları kapatmıyordu. | Safe mode ve boş araç listesi eklendi; MCP kapalı kaldı. |
| Ortamdaki API anahtarı abonelik yerine ücretli API kullanımına yol açabiliyordu. | Claude API/alternatif sağlayıcı ortamları reddediliyor; Codex ChatGPT girişine zorlanıyor. |
| 60 dakikalık alt sınır gereksiz sık mesajlara izin veriyordu; çok büyük değerler Bash aritmetiğini taşırabiliyordu. | Aralık 300–525600 dakika ile sınırlandı. |
| Windows UTF-8 BOM içeren ayar Unix'te farklı okunabiliyordu. | BOM işleme ve eksik --config argümanı kontrolü eklendi. |
| Cron satırında klasör adındaki shell ifadeleri çalıştırılabiliyordu. | Yol tek tırnakla güvenli biçimde yazılıyor; özel karakterli klasörle test edildi. |
| launchd kayıt klasörleri kurulmadan iş başlatılabiliyordu. | logs/state dizinleri kurulumda oluşturuluyor. |
| Windows kurulum doğrulaması ilk kayıt satırında durabiliyordu. | Görevin tamamlanması ve çıkış kodu bekleniyor; iş yapmayan tur gerçek CLI testi olarak sunulmuyor. |
| Bulut durum kaydı rebase sırasında yanlış tarafı seçiyordu; yeni dosya kontrolü de eksikti. | İki servisin en yeni zamanları birleştiriliyor, beklenmeyen çatışmada hata veriliyor. Gerçek yerel Git çatışmasıyla test edildi. |
| Bulutta her tur değişebilen CLI sürümleri kuruluyordu. | Test edilen sürümler sabitlendi; action SHA sabitlemeleri korundu. |
| Yedek talimat dosyaları yanlışlıkla yayımlanabilirdi. | Yedek, kimlik dosyası ve yaygın özel anahtar dosyaları ignore listesine eklendi. |
| README ve beceri bütün sayaçların açıldığını, tam zamanlamayı ve belirsiz maliyetleri kesinmiş gibi anlatıyordu. | Türkçe/İngilizce belgeler gerçek kapsam ve sınırlamalarla yenilendi; durum saati açıkça tahmin olarak gösteriliyor. |

## Doğrulama

- İlk 25 regresyon testi Windows üzerinde ve GitHub'ın Windows/Linux/macOS çalıştırıcılarında geçti.
- Cron yol enjeksiyonu ve gerçek Git durum çatışması için iki ek entegrasyon testi eklendi ve yerelde geçti. Güncel sonuç için depodaki **tests** iş akışına bak.
- Testler sahte CLI, geçici klasör ve yerel Git depoları kullanır; AI aboneliği tüketmez.
- Git geçmişindeki ilk 84 dosya nesnesinde ve tamamlanmış 9 keepalive çalışma kaydında yaygın erişim anahtarı biçimleri tarandı; eşleşme bulunmadı. Biçim taraması bütün olası gizli bilgilerin yokluğunun kanıtı değildir.
- Codex ile ChatGPT abonelik girişi üzerinden gerçek küçük mesaj başarıyla işlendi.
- Güncellenmiş Claude bulut akışında gerçek **Ping** ve **Save the new state** adımları başarıyla tamamlandı: [doğrulama çalışması](https://github.com/sabnmali/no-5-hour-limit/actions/runs/33990861538).
- `AGENTS.md` ile `CLAUDE.md` aynı içerikte tutuldu.

## Kalan sınırlar

Normal ChatGPT sohbetlerini ve bütün modellerin ayrı sayaçlarını tek mesajla
başlatan doğrulanmış bir entegrasyon yoktur. Bu proje bunu yapıyor gibi davranmaz.
Paylaşılan Claude kotası da bütün ek model/özellik limitlerinin aynı olduğu
anlamına gelmez. CLI başarısı yeni bir pencere açıldığını kanıtlamaz.

Yerel Codex bilgisayar açık ve kullanıcı oturum açmışken çalışır. Bulutta Codex
kimlik yenilemesi bakım gerektirir; aynı masaüstü oturumunu kopyalamak güvenilir
bir kalıcı çözüm değildir. GitHub zamanlaması yaklaşık, gösterilen pencere
bitişleri tahmindir. Gerçek sınır için sağlayıcının Kullanım ekranı esas alınır.

İnceleme güvenlik sertifikası değildir. Resmî CLI paketleri, yönetici politikaları,
hesap ayarları ve GitHub deposuna yazabilen kişiler güven sınırının parçasıdır.
