# Limitless 5-Hour

**Claude ve ChatGPT/Codex'in 5 saatlik kullanım pencerelerini senin belirlediğin
saatlere oturt.**

[English README](README.md)

---

## Sorun

Claude Code ve Codex, kullanımı **kayan 5 saatlik pencereler** halinde sayar.
Sayaç, günün sabit bir saatinde değil, **ilk mesajını attığın anda** başlar.
Yani sabah 09:40'ta tek bir kısa soru sorup 13:00'te geri dönersen, hiç
kullanmadığın bir pencerenin dört saatini yakmış olursun — ve yeni pencere
14:40'tan önce açılmaz.

## Bu proje ne yapıyor

Arka planda çalışan küçük bir görev, her **301 dakikada** (5 saat + 1 dakika)
bir CLI'a tek kelimelik bir mesaj gönderiyor. Her mesaj, bir önceki pencere
kapandığı anda yenisini açıyor. Sonuç:

- pencereler 7/24 uç uca diziliyor
- mevcut pencerenin ne zaman bittiğini, yenisinin ne zaman başladığını her an
  biliyorsun
- iki saniyelik bir soru yüzünden koca bir pencere yanmıyor

İki şekilde çalışabilir: kendi bilgisayarında (Görev Zamanlayıcı / cron /
launchd) ya da tamamen bulutta, GitHub Actions üzerinde. Bulut seçeneği,
bilgisayarın kapalı, uykuda veya internetsiz olsa da çalışmaya devam eder —
çoğu kişinin istediği bu.

Mesaj **en ucuz modelde** (varsayılan: Haiku) gönderiliyor; sistem talimatı altı
kelimeye indiriliyor ve bütün araçlar kapatılıyor. Yani kotandan pratikte
ölçülemeyecek kadar az yiyor.

## Ne değil

Bu proje limitini **yükseltmiyor**, hiçbir şeyi atlatmıyor, sana fazladan kota
vermiyor. Sadece pencere sınırlarının istediğin yere denk gelmesini sağlıyor.
Kendi aboneliğini, resmî CLI üzerinden, sanki `ok` yazmışsın gibi kullanıyor.

---

## Gerekenler

| | |
|---|---|
| **Claude** | [Claude Code CLI](https://claude.com/claude-code) + Claude aboneliği |
| **Codex** *(isteğe bağlı)* | [Codex CLI](https://github.com/openai/codex) + Codex içeren bir ChatGPT planı |
| **İşletim sistemi** | Windows 10/11, macOS veya Linux |

Açık kalan bir bilgisayar. Uyuyan bir dizüstünde kaçan mesajlar, uyanır uyanmaz
gönderilir.

---

## Kurulum

```bash
git clone https://github.com/<kullanici>/limitless-5-hour.git
cd limitless-5-hour
```

### Windows

```powershell
powershell -ExecutionPolicy Bypass -File install\install-windows.ps1
```

`Limitless5Hour` adında bir Görev Zamanlayıcı kaydı oluşturur. Senin
kullanıcınla çalışır, yönetici yetkisi istemez, yeniden başlatma ve uyku
sonrasında da devam eder.

### macOS / Linux

```bash
./install/install-unix.sh
```

macOS'ta LaunchAgent, Linux'ta crontab kaydı oluşturur.

### Sonra bir kez

```bash
claude auth login       # CLI'ın kendi girişi var, masaüstü uygulamasından ayrı
codex login             # sadece Codex'i açacaksan
```

Windows'ta hem girişi yapan hem de CLI'ı Görev Zamanlayıcı'nın gerçekten
erişebileceği bir yere kuran bir yardımcı var. Normal bir PowerShell
penceresinde çalıştır:

```powershell
powershell -ExecutionPolicy Bypass -File install\setup-cli-windows.ps1
```

### İlk pencereyi başlat

```bash
# Windows
powershell -ExecutionPolicy Bypass -File bin\keepalive.ps1 -Force
# macOS / Linux
./bin/keepalive.sh --force
```

---

## Buluttan çalıştır (önerilen)

Yukarıdaki her şey senin bilgisayarının açık olmasını gerektiriyor. Makinen
kapalıyken, uykudayken veya internetsizken de çalışsın istiyorsan bu depoyu
GitHub'a gönder ve gönderimleri GitHub Actions yapsın.
[`.github/workflows/keepalive.yml`](.github/workflows/keepalive.yml) dosyası
buna hazır.

**1. Kimlik bilgilerini üret**

Herhangi bir bilgisayarda, bir kez:

```bash
claude setup-token     # uzun ömürlü bir token yazdırır - kopyala
```

Codex için `~/.codex/auth.json` dosyasının tamamını kopyala (isteğe bağlı).

**2. Depoyu gönder ve gizli anahtarları ekle**

```bash
gh repo create limitless-5-hour --public --source=. --remote=origin --push
gh secret set CLAUDE_CODE_OAUTH_TOKEN
gh secret set CODEX_AUTH_JSON < ~/.codex/auth.json
```

Ya da site üzerinden: **Settings -> Secrets and variables -> Actions -> New
repository secret**.

**3. Çalıştır**

**Actions** sekmesini aç, `keepalive` iş akışını etkinleştir, sonra
**Run workflow** deyip *Force* kutusunu işaretle — ilk pencere hemen açılır.

Bundan sonrası GitHub'ın makinelerinde dönüyor; senin bilgisayarının hiçbir
rolü kalmıyor.

### Bilgisayar olmadan yönetmek

`cloud.env` depoda duruyor. Telefonundan github.com'a girip aralığı
değiştirebilir veya Codex'i açabilirsin; bir sonraki tur yeni ayarı kullanır.
Her gönderim, pencerenin ne zaman biteceğini gösteren bir özet yazıyor;
`state/cloud-state.env` de son gönderim zamanını tutuyor.

### Güvenmeden önce bilmen gerekenler

- **Zamanlama yaklaşıktır.** GitHub'ın zamanlayıcısı "elinden geleni yapar":
  turlar çoğu zaman birkaç dakika, bazen yarım saat gecikir. Pencereler yine uç
  uca dizilir, sadece sınırlar dakikası dakikasına olmaz.
- **Depoyu public tut** — Actions dakikaları sınırsız olur. Private depoda
  15 dakikalık tur, ücretsiz 2000 dakikanın çoğunu yer; orada cron'u
  `0,30 * * * *` yap.
- **60 gün hiç hareket olmayan depolarda zamanlanmış iş akışları kapatılır.**
  Her gönderim durum dosyasını commit ettiği için bu hareket sayılıyor.
- **Token, aboneliğine erişim verir.** Sadece senin kontrolündeki bir depoya
  koy. Gizli anahtarlar fork'lara ve pull request'lere aktarılmaz.
- **Codex'in yenileme token'ları döner.** Codex gönderimleri bir gün hata
  vermeye başlarsa `~/.codex/auth.json` dosyasını anahtara yeniden kopyala.

### Bulut mu, yerel mi?

Birini seç. İkisini birden çalıştırmak, aynı hesaba iki ayrı zamanlamanın
gönderim yapması demek — fazladan pencere açmadan biraz kota harcar. Buluta
geçtiysen yerel görevi kaldır:

```powershell
powershell -ExecutionPolicy Bypass -File install\uninstall-windows.ps1
```

---

## Günlük kullanım

Hiçbir şey yapman gerekmiyor. Duruma bakmak istersen:

```bash
# Windows
powershell -ExecutionPolicy Bypass -File bin\keepalive.ps1 -Status
# macOS / Linux
./bin/keepalive.sh --status
```

```
  Limitless 5-Hour - status
  ---------------------------------------------------------
  interval     : 301 minutes
  quiet hours  : disabled (24/7)

  claude       : enabled
     last ping   2026-09-05 09:12:04     <- son gönderim
     window ends 2026-09-05 14:12:04  (3h 41m left)   <- pencere bitişi
     next ping   2026-09-05 14:13:04     <- yeni pencere
  codex        : disabled

  scheduler    : installed, state = Ready
```

Kurulum, birlikte gelen Claude Code becerisini de yüklüyor. Yani Claude'a düz
Türkçe **"limitim ne durumda?"** diye sorman da yeterli — durumu kendisi
kontrol edip söylüyor.

---

## Ayarlar

`config.env` dosyasını düzenle (ilk kurulumda `config.example.env`'den
oluşturulur). Değişiklikler bir sonraki turda geçerli olur, yeniden başlatmaya
gerek yok.

| Anahtar | Varsayılan | Anlamı |
|---|---|---|
| `INTERVAL_MINUTES` | `301` | İki gönderim arası dakika. 300'ün altına inme — açık pencerenin içine mesaj atmak pencereyi boşa harcar. |
| `CLAUDE_ENABLED` | `true` | Claude penceresini döndür. |
| `CLAUDE_MODEL` | `haiku` | Gönderimde kullanılan model. En ucuzu en iyisi. |
| `CLAUDE_PROMPT` | `ok` | Gönderilecek metin. Kısa tut. |
| `CLAUDE_BIN` | *(kurulumda dolar)* | `claude` komutunun tam yolu. Zamanlayıcılar dar bir `PATH` ile çalıştığı için gerekli. |
| `CODEX_ENABLED` | `false` | `true` yaparsan Codex penceresi de dönmeye başlar. |
| `CODEX_MODEL` | *(boş)* | Boş = Codex ayarındaki varsayılan model. |
| `CODEX_BIN` | *(kurulumda dolar)* | `codex` komutunun tam yolu. |
| `CODEX_REASONING_EFFORT` | `minimal` | Codex gönderimini ucuz tutar. |
| `LOG_RETENTION_DAYS` | `30` | Bundan eski kayıtları siler. `0` = hiç silme. |
| `QUIET_HOURS` | *(boş)* | Örn. `02:00-08:00` — gece göndermez. Boş = tam 7/24. |

### ChatGPT / Codex'i eklemek

Codex de aynı şekilde sayıyor. İki adım:

```bash
codex login
```

sonra `config.env` içinde:

```
CODEX_ENABLED=true
```

İki servis birbirinden bağımsız izleniyor; biri limite takılırsa diğeri devam
eder.

---

## Nasıl çalışıyor

```
zamanlayıcı (5 dakikada bir)  ->  keepalive scripti
                                       |
                                       +-- son başarılı gönderimden bu yana
                                       |   INTERVAL_MINUTES geçti mi?
                                       |
                                     hayır --> çık, hiçbir maliyet yok
                                       |
                                     evet --> claude -p "ok" --model haiku ...
                                              zamanı kaydet
                                              logs/ içine tek satır yaz
```

Gönderim zamanına zamanlayıcı değil, **scriptin kendisi** karar veriyor. Uyku,
yeniden başlatma, kaçan turlar ve saat değişiklikleri bu yüzden sorun olmuyor:
her uyandığında tek bir şey soruyor — *"301 dakika oldu mu?"*

Gönderim bilerek en yalın hale getirildi:

```
claude -p "ok" --model haiku
       --system-prompt "Reply with exactly: ok"   # tüm sistem talimatını değiştirir
       --restricted                               # Bash yok, kod çalıştırma yok
       --strict-mcp-config                        # MCP sunucusu yüklenmez
       --no-session-persistence                   # diske hiçbir şey yazılmaz
       --permission-mode dontAsk                  # asla izin sorup takılmaz
       --output-format json
```

---

## Dosyalar

```
.github/workflows/        GitHub Actions: cihazdan bağımsız zamanlayıcı
cloud.env                  Bulut ayarları - depoda durur, web'den düzenlenir
state/cloud-state.env      Bulut son gönderim zamanları (runner commit eder)
bin/keepalive.ps1          Windows: her şey burada (gönderim, durum, kayıt)
bin/keepalive.sh           macOS/Linux: aynısı
install/install-*.{ps1,sh} Zamanlayıcıyı ve beceriyi kurar
install/setup-cli-windows.ps1  Windows: yerel CLI kurulumu + giriş + yeniden kayıt
install/uninstall-*        Zamanlayıcıyı kaldırır (ayar ve kayıtlar kalır)
skill/limitless-5-hour/    Claude Code becerisi: sohbette limitini sorabilirsin
config.example.env         config.env için şablon
logs/                      Her ay için bir kayıt dosyası
state/                     Son gönderim zamanları
```

---

## Sorun giderme

**`not logged in - run: claude auth login`**
CLI'ın kimlik bilgileri masaüstü uygulamasından ayrı. Terminalde bir kez
`claude auth login` çalıştır.

**Arka plan görevi hiçbir şey yapmıyor ama elle çalıştırınca çalışıyor**

Görev Zamanlayıcı servisi, programları senin terminalinden farklı bir ortamla
başlatır - bazı Windows makinelerinde `%APPDATA%` görünümü bile farklıdır.
npm ile kurulan `claude`, `%APPDATA%\npm` içinde durur ve zamanlayıcı orayı
göremeyebilir; kayıtlar `claude CLI not found` ile dolar.

Kurulum bunu kendisi tespit edip söylüyor. Çözüm, kullanıcı klasörüne kurulan
ve zamanlayıcının erişebildiği yerel (native) sürüme geçmek:

```powershell
powershell -ExecutionPolicy Bypass -File install\setup-cli-windows.ps1
```

Bu komut yerel sürümü kurar, girişi yapar ve görevi yeniden kaydeder.
İstersen her platformda yolu `config.env` içinde kendin de verebilirsin:

```
CLAUDE_BIN=C:\Users\kullanici\.local\bin\claude.exe
```

**Kayıtlarda hiçbir şey yok**
`-Status` / `--status` çıktısındaki `scheduler` satırına bak. Windows'ta Görev
Zamanlayıcı'da `Limitless5Hour`'ı, Linux'ta `crontab -l` çıktısını kontrol et.

**`usage limit reached`**
Pencereni zaten tükettiysen normaldir. Script geri çekilir, bir sonraki turda
tekrar dener.

**Cron `claude` komutunu bulamıyor**
Cron çok dar bir `PATH` ile çalışır. Crontab satırına tam yolu yaz ya da
crontab'ın başına bir `PATH=` satırı ekle.

---

## Kaldırma

```powershell
powershell -ExecutionPolicy Bypass -File install\uninstall-windows.ps1
```

```bash
./install/uninstall-unix.sh
```

Sadece zamanlayıcı kaydını siler. `config.env`, `logs/` ve `state/` yerinde
kalır; her şeyi silmek için klasörü kaldırman yeterli.

---

## Lisans

MIT — [LICENSE](LICENSE) dosyasına bak.

Anthropic veya OpenAI ile bağlantılı değildir. Kendi aboneliğinin koşulları
çerçevesinde kullan.
