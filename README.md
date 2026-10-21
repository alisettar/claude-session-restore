# claude-session-restore

Windows'ta bilgisayar yeniden başladığında **Windows Terminal düzenini** (pencereler, sekme sırası,
paneller) ve her sekmede açık olan **Claude Code konuşmasını** geri getirir.

## Nasıl çalışır

```
 Claude Code oturumu ──hook──► ~/.claude/session-registry/<WT_SESSION>.json
                                 { sessionId, cwd, launcher, configDir, claudePid, ... }

 restart
   │
   ▼
 Windows Terminal (startOnUserLogin) düzeni geri yükler
   └─ her sekme aynı WT_SESSION ile açılır
        └─ PowerShell profili → cc-restore.ps1
             kayıt var + kayıttaki Claude süreci yaşamıyor → cd <cwd>; claude --resume <sessionId>
```

1. **Windows Terminal** `firstWindowPreference: persistedWindowLayout` ile pencereleri, sekme sırasını,
   panelleri, klasörleri ve ekran içeriğini saklar; `startOnUserLogin` ile oturum açılışında başlar.
   Geri yüklenen her panel restart öncesindeki `WT_SESSION` kimliğiyle açılır.
2. **Hook** (`cc-session-registry.ps1`): `SessionStart` ve her `UserPromptSubmit`'te sekmenin
   `WT_SESSION`'ına karşılık gelen oturumu kaydeder. `SessionEnd` yalnızca bilinçli çıkışta
   (`/exit`, Ctrl+D, logout) kaydı siler; restart/kill'de kayıt kalır.
3. **Profil** (`cc-restore.ps1`): yeni açılan her sekme kendi kaydına bakar. Kayıttaki Claude süreci
   artık çalışmıyorsa (PID + başlangıç zamanı kontrolü) oturumu ilk klasöründe `--resume` ile açar.
   Çalışan bir oturumun açtığı alt shell'ler bu kontrol sayesinde tetiklemez.

Konuşmaların kendisi zaten Claude Code tarafından `~/.claude/projects/` altında saklanır; bu araç
yalnızca "hangi sekmede hangi konuşma vardı" bilgisini tutar.

### Çökme / elektrik kesintisi

Windows Terminal düzeni **yalnızca düzgün kapanışta** kaydeder. Mavi ekran veya elektrik kesintisinde
sekmeler eski `WT_SESSION`'larla gelmez ve yukarıdaki yol hiçbir oturumu bulamaz. Bunun için:

1. Hook her olayda o an çalışan oturumların listesini `~/.claude/session-registry/live.json`'a yazar.
2. Açılıştan sonraki ilk shell, `live.json` açılıştan eskiyse onu atomik olarak devralır ve
   `cc-recover.ps1`'i gizli başlatır.
3. `cc-recover.ps1` 90 sn'ye kadar bekler: listedeki oturumlardan biri canlanırsa WT düzeni geri gelmiş
   demektir, hiçbir şey yapmaz. Hiçbiri canlanmazsa (çökme) hepsini **`claude-restore` adlı yeni bir
   WT penceresinde**, ilk açılış sırasına göre sekme olarak açar. Günlük: `session-registry/recover.log`.

Çökmede pencere/sekme yerleşimi korunamaz (WT bunu dışarı vermez); oturumlar tek pencerede gelir.

Elle kurtarma (ör. listeyi kendin hazırladıysan):

```powershell
pwsh -File ~/.claude-tools/session-restore/cc-recover.ps1 -Snapshot <liste.json> -NoWait
```

## Kurulum

Gereksinim: Windows Terminal, PowerShell 7 (`pwsh`), Claude Code.

```powershell
git clone <repo-url>
cd claude-session-restore
pwsh -File install.ps1
```

Tekrar çalıştırmak güvenlidir: kurulu olanı yeniden eklemez, profil bloğunu günceller.
Değiştirdiği her dosyanın yanına `.bak-<zaman>` yedeği bırakır.

| Parametre | Anlamı |
|---|---|
| `-ConfigDir <yol>[,<yol>]` | Hook'ların ekleneceği Claude config dizinleri (varsayılan `~/.claude`). `CLAUDE_CONFIG_DIR` ile ikinci bir hesap kullanıyorsan ve o dizinin `settings.json`'ı ana dosyaya symlink değilse onu da ver. |
| `-SkipTerminal` | Windows Terminal ayarlarına dokunma. |

Kurulumdan sonra açık Claude sekmeleri **bir sonraki mesajda** kayda geçer.

### Neye dokunur

| Dosya | Değişiklik |
|---|---|
| `~/.claude-tools/session-restore/` | `src/` altındaki betiklerin kopyası |
| `~/.claude/settings.json` | `SessionStart`, `UserPromptSubmit`, `SessionEnd` hook'ları (mevcut hook'lar korunur) |
| PowerShell profili (`$PROFILE`) | `# >>> claude session restore` bloğu |
| Windows Terminal `settings.json` | `firstWindowPreference`, `startOnUserLogin` |

## Kaldırma

```powershell
pwsh -File uninstall.ps1                     # her şeyi geri al
pwsh -File uninstall.ps1 -KeepTerminalLayout # WT düzen saklama ayarları kalsın
pwsh -File uninstall.ps1 -KeepRegistry       # oturum kayıtları kalsın
```

## Desteklenen launcher'lar

| Komut | Nasıl takip edilir |
|---|---|
| `claude` | Hook |
| `CLAUDE_CONFIG_DIR` ile ikinci hesap (ör. profilde bir `myclaude` fonksiyonu) | Hook; kayıttaki `configDir` geri yüklemede tekrar set edilir |
| `gecko` (yerel model launcher'ı, `~/.claude-tools/gecko.ps1`) | `cc-gecko-wrap.ps1` sarmalayıcısı — aşağıya bakın |

### gecko neden sarmalayıcı ile?

`gecko.ps1` Claude Code'u `--setting-sources project` ile başlatır, yani kullanıcı hook'larını
yüklemez. Bu yüzden profil `gecko` komutunu `cc-gecko-wrap.ps1` ile sarar: oturum bilinen bir
`--session-id` ile başlatılır, kayıt sarmalayıcı tarafından yazılır ve normal çıkışta silinir.
Sarmalayıcı yalnızca `~/.claude-tools/gecko.ps1` varsa tanımlanır. Headless (`-p`) çağrılar ve
id'siz `--resume`/`--continue` kayda geçmez.

**Denenip elenen yol:** hook'ları `C:\Program Files\ClaudeCode\managed-settings.json`'a koymak
(her oturumda yüklenir). Hesabın bağlı olduğu organizasyonun server-managed ayarları varsa Claude Code
varsayılan `managedSourcesBehavior: "first-wins"` gereği yalnızca en öncelikli kaynağı kullanır ve
bu dosyayı tamamen yok sayar.

## Sınırlar

- Yalnızca **Windows Terminal + PowerShell 7** içinde çalışan oturumlar takip edilir.
- `--resume` konuşmayı geri getirir; restart anında çalışan bir komut, arka plan işi ya da yarım
  kalmış cevap devam etmez.
- Bir sekmeyi pencereden (X ile) kapatırsan kaydı kalır ama o `WT_SESSION` bir daha açılmayacağı için
  zararsızdır; 30 günden eski kayıtlar otomatik silinir.
- Çökme kurtarması son hook olayındaki listeyi kullanır: son mesajdan sonra X ile kapatılan bir sekme
  yeniden açılabilir, son mesajdan sonra açılıp hiç mesaj yazılmamış bir oturum da (SessionStart'ı
  yazıldığı için) listededir.
- `--resume` konuşmayı açıldığı klasörün proje dizininde arar; oturum içinde `cd` yapılmışsa betikler
  konuşmanın durduğu üst klasörü kendisi bulur.
- Her hook çağrısı ~0,4 sn sürer (PowerShell başlangıcı + anlık görüntü); Claude'un diğer hook'larıyla paralel çalışır.
- gecko oturumunda `/clear` yapılırsa sarmalayıcının bildiği id eskide kalır; geri yüklemede
  `/clear` öncesi konuşma açılır.

## Sorun giderme

Önce `~/.claude/session-registry/recover.log`'a bak. Bir sekme geri gelmediyse o sekmede:

```powershell
$env:WT_SESSION                                   # bu sekmenin kimliği
Get-ChildItem ~/.claude/session-registry          # dosya adları bu kimliklerle eşleşmeli
Get-Content ~/.claude/session-registry/$env:WT_SESSION.json
```
