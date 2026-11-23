# cullewie-s-apps

Format sonrası tek komut: önce [cullewie-s-progress](https://github.com/cullewie/cullewie-s-progress)'in **All-in** kurulumunu kendiliğinden yapar, sonra uygulamaları kurar.

Başlat menüsünde **PowerShell**'e sağ tıkla, **Yönetici olarak çalıştır**'ı seç ve şu komutu yapıştır:

```powershell
iwr 'https://github.com/cullewie/cullewie-s-apps/raw/refs/heads/main/IWR.ps1' -useb | iex
```

Pencere açılır, All-in mod sormadan başlar. Bilgisayar birkaç kez kendiliğinden yeniden başlar; her açılışta oturum açman yeterli. Son açılışta uygulamalar kurulur, her biri pencerede kendi satırında görünür. Sonra Digital Vibrance sorulur, disk temizlenir ve bilgisayar son kez yeniden başlar.

## Kurulan uygulamalar

- Google Chrome
- TeamSpeak 6 (beta)
- Steam
- Spotify
- FACEIT Anti-Cheat
- DDU (Display Driver Uninstaller)
- AMD Chipset Software (sadece AMD işlemcide)

Hepsi üreticinin kendi sunucusundan, en güncel sürümüyle iner ve dijital imzası kontrol edilir. Zaten kurulu olanlar atlanır.

---

Lisans: [MIT](LICENSE).
