<div align="center">

# ماشین مجازی رایگان با GitHub Actions

**یک ماشین کامل مک‌اواس، ویندوز یوبونتو را داخل GitHub Actions اجرا کنید و از راه دور به آن وصل شوید — در مخازن عمومی کاملاً رایگان.**

[English](../README.md) · [فارسی](README-fa.md)

![License](https://img.shields.io/badge/license-Apache--2.0-blue)
![Actions](https://github.com/Mimoli001/turbo-disco/actions/workflows/linux-ssh.yml/badge.svg)

</div>

> :warning: **به‌روز نگه داشتن Fork:** اگر ورک‌فلوها اجرا نمی‌شوند، این مخزن را دوباره Fork کنید یا Fork فعلی خود را با آخرین کدها همگام‌سازی کنید. مراحل در بخش [به‌روزرسانی Fork](#به‌روزرسانی-fork) آمده است.

---

## فهرست مطالب

- [چه چیزی دریافت می‌کنید](#چه-چیزی-دریافت-می‌کنید)
- [مشخصات ماشین](#مشخصات-ماشین)
- [شروع سریع](#شروع-سریع)
- [Secretهای مورد نیاز](#secretهای-مورد-نیاز)
- [استقرار و اجرا](#استقرار-و-اجرا) — مک‌اواس · ویندوز · لینوکس
- [به‌روزرسانی Fork](#به‌روزرسانی-fork)
- [محدودیت‌ها](#محدودیت‌ها)
- [راه‌حل مشکلات](#راه‌حل-مشکلات)
- [نکات امنیتی](#نکات-امنیتی)
- [پیشنهادها و ترفندها](#پیشنهادها-و-ترفندها)
- [لایسنس](#لایسنس)

---

## چه چیزی دریافت می‌کنید

| ورک‌فلو (در تب `Actions`) | سیستم‌عامل | روش اتصال |
| --- | --- | --- |
| `MacOS Virtual Machine` | مک‌اواس روی تراشهٔ اپل | VNC Viewer از طریق تونل Cloudflare روی **دامنهٔ شخصی شما** |
| `Windows Virtual Machine` | دسکتاپ Windows Server (شبیه ویندوز ۱۰/۱۱) | Remote Desktop (`mstsc`) از طریق تونل Cloudflare روی **دامنهٔ شخصی شما** |
| `Ubuntu ssh Virtual Machine` | اوبونتو سرور | `ssh` از طریق تونل Cloudflare روی **دامنهٔ شخصی شما** |
| `Ubuntu Desktop Virtual Machine` | اوبونتو با دسکتاپ XFCE | Google Remote Desktop (به‌همراه SSH پشتیبان روی دامنهٔ شخصی شما) |

همه‌چیز توسط ورک‌فلوهای پوشهٔ [`.github/workflows/`](../.github/workflows/) و اسکریپت‌های کنار همین فایل راه‌اندازی می‌شود؛ کافی است چند Secret تنظیم کنید و **Run workflow** را بزنید.

---

## مشخصات ماشین

مشخصات زیر مربوط به رانرهای استاندارد GitHub است که این پروژه در مخازن **عمومی** استفاده می‌کند (در مخازن عمومی رایگان و نامحدود است):

| ماشین | vCPU | RAM | دیسک آزاد |
| --- | --- | --- | --- |
| ویندوز و لینوکس | ۴ هسته | ۱۶ گیگابایت | ۱۴ گیگابایت SSD **(به‌جز سیستم‌عامل)** |
| مک‌اواس (`macos-latest`، تراشهٔ اپل) | ۳ هسته (Apple M1) | ۷ گیگابایت | ۱۴ گیگابایت SSD **(به‌جز سیستم‌عامل)** |

> :warning: این مشخصات مربوط به Forkهای **عمومی** است. اگر این مخزن را به‌صورت **خصوصی** Fork کنید، رانرهای لینوکس/ویندوز کوچک‌ترند (۲ هسته vCPU / ۸ گیگابایت RAM)، از ۲٬۰۰۰ دقیقه رایگان Actions در ماه کم می‌شود (ویندوز ۲ برابر و مک‌اواس ۱۰ برابر منظور می‌شود) و همزمانی مک‌اواس به ۵ job محدود است.

> :information_source: ورک‌فلوی ویندوز روی رانر Windows Server گیت‌هاب اجرا می‌شود که Remote Desktop در آن فعال است؛ محیط دسکتاپ شبیه ویندوز ۱۰/۱۱ است.

---

## شروع سریع

1. این مخزن را **Fork** کنید.
2. یک [توکن API کلادفلر بسازید](#secretهای-مورد-نیاز) و Secretهای `CF_*` به‌همراه Secretهای مربوط به هر سیستم‌عامل را در `Settings` → `Secrets and variables` → `Actions` → `New repository secret` اضافه کنید.
3. وارد تب **`Actions`** شوید، یک ورک‌فلو را از سمت چپ انتخاب کنید و **Run workflow** را بزنید.
4. چند دقیقه صبر کنید، سپس اطلاعات اتصال را از لاگ job بخوانید.
5. [cloudflared](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/) را روی رایانهٔ خود نصب کنید، با VNC Viewer، Remote Desktop یا `ssh` وصل شوید و تا پایان job از ماشین لذت ببرید.

---

## Secretهای مورد نیاز

به صفحهٔ پروژهٔ خود بروید: `Settings` → `Secrets and variables` → `Actions` → `New repository secret` و موارد زیر را اضافه کنید:

### کلادفلر (برای همهٔ ورک‌فلوها)

هر اجرا یک **تونل Cloudflare موقت** روی دامنهٔ شخصی شما می‌سازد؛ بنابراین هیچ سرویس تونل شخص ثالثی در کار نیست. در <https://dash.cloudflare.com/profile/api-tokens> یک توکن API با دسترسی‌های زیر بسازید و آن را به‌صورت Secret ذخیره کنید:

| دسترسی توکن | کاربرد |
| --- | --- |
| Account → **Cloudflare Tunnel: Edit** | ساخت/به‌روزرسانی تونل هر اجرا |
| Account → **Access: Apps and Policies: Edit** | انتشار ساب‌دومین‌ها (اپ‌های SSH/RDP/VNC) |
| Zone → **DNS: Edit** | ساخت رکوردهای CNAME روی دامنهٔ شما |
| Zone → **Zone: Read** | پیدا کردن Zone دامنهٔ شما |

| Secret | کاربرد | توضیحات |
| --- | --- | --- |
| `CF_API_TOKEN` | توکن API توضیح‌داده‌شده در بالا | مربوط به حساب کلادفلر شما |
| `CF_DOMAIN` | دامنهٔ پایه برای تونل‌ها | DNS این دامنه باید روی همان حساب کلادفلر باشد، مثلاً `example.com` |
| `CF_SUBDOMAIN` | ساب‌دومین اختیاری زیر `CF_DOMAIN` | مثلاً `myvps` → `ssh.myvps.example.com`؛ خالی بگذارید تا `ssh.example.com` استفاده شود |
| `CF_ACCOUNT_ID` | شناسهٔ حساب کلادفلر (اختیاری) | در صورت خالی‌بودن به‌طور خودکار از توکن پیدا می‌شود |

هر اجرا ساب‌دومین‌هایی مثل `ssh.<ساب‌دومین>.<دامنه>` (لینوکس)، `rdp.<ساب‌دومین>.<دامنه>` (ویندوز) و `vnc.<ساب‌دومین>.<دامنه>` (مک‌اواس) را منتشر می‌کند و در اجراهای بعدی همان‌ها را بازاستفاده می‌کند؛ تونل اجراهای تمام‌شده به‌طور خودکار حذف می‌شود.

### حساب‌های پلتفرم

| Secret | کاربرد | توضیحات |
| --- | --- | --- |
| `MAC_REALNAME` | نام نمایشی کاربر مک‌اواس | هر نامی که می‌خواهید |
| `MAC_USER_PASSWORD` | رمز عبور مدیر سیستم مک‌اواس | هر رمزی که می‌خواهید |
| `VNC_PASSWORD` | رمز ورود VNC در مک‌اواس | هر رمزی که می‌خواهید |
| `WINDOWS_USER_PASSWORD` | رمز ورود RDP ویندوز | روی حساب administrator داخلی تنظیم می‌شود |
| `LINUX_USERNAME` | نام کاربری لینوکس | هر نامی که می‌خواهید |
| `LINUX_USER_PASSWORD` | رمز عبور شل و `sudo` لینوکس | هر رمزی که می‌خواهید |
| `LINUX_MACHINE_NAME` | نام رایانه در لینوکس | هر نامی که می‌خواهید |
| `CHROME_HEADLESS_CODE` | Google Remote Desktop برای دسکتاپ لینوکس | کد را از <https://remotedesktop.google.com/headless> بگیرید، با حساب گوگل وارد شوید و کد زیر `Debian Linux` را کپی کنید. :warning: هر کد فقط **یک بار** کار می‌کند؛ هر بار کد جدیدی بسازید. |
| `GOOGLE_REMOTE_PIN` | PIN مربوط به Google Remote Desktop | هر PIN حداقل ۶ رقمی؛ هنگام اتصال به دسکتاپ لینوکس به آن نیاز دارید |

---

## استقرار و اجرا

<details>
<summary><b>مک‌اواس</b></summary>
<br>

1. تب **`Actions`** را باز کنید و **`MacOS Virtual Machine`** را انتخاب کنید.
2. دکمهٔ **`Run Workflow`** را بزنید.
3. چند دقیقه برای ساخت سیستم و راه‌اندازی تونل صبر کنید.
4. [cloudflared](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/) را روی رایانهٔ خود نصب کنید.
5. دستوری را که در لاگ job چاپ شده اجرا کنید:
   ```bash
   cloudflared access tcp --hostname vnc.SUBDOMAIN.DOMAIN --url localhost:5900
   ```
6. نرم‌افزار [VNC Viewer](https://www.realvnc.com/en/connect/download/viewer/) را نصب کنید، به `localhost:5900` وصل شوید و با نام کاربری `vpsuser` و رمز همان `VNC_PASSWORD` وارد شوید.
7. لذت ببرید!

</details>

<details>
<summary><b>ویندوز</b></summary>
<br>

1. ورک‌فلوی **`Windows Virtual Machine`** را از تب `Actions` اجرا کنید.
2. در لاگ job منتظر مرحلهٔ **`Print connection info`** بمانید — ساب‌دومین، نام کاربری و محل رمز عبور را چاپ می‌کند.
3. [cloudflared](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/) را روی رایانهٔ خود نصب کنید و اجرا کنید:
   ```bash
   cloudflared access tcp --hostname rdp.SUBDOMAIN.DOMAIN --url localhost:3389
   ```
4. برنامهٔ Remote Desktop Connection ویندوز (`mstsc`) یا Microsoft Remote Desktop را باز کنید و به `localhost:3389` وصل شوید.
5. لذت ببرید!

</details>

<details>
<summary><b>لینوکس (SSH و دسکتاپ)</b></summary>
<br>

1. از تب `Actions` یکی از **`Ubuntu ssh Virtual Machine`** (فقط سرور) یا **`Ubuntu Desktop Virtual Machine`** (دسکتاپ XFCE) را اجرا کنید.
2. [cloudflared](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/) را روی رایانهٔ خود نصب کنید، سپس دستور اتصالِ چاپ‌شده در انتهای لاگ را اجرا کنید، مثلاً:
   ```bash
   ssh -o ProxyCommand="cloudflared access ssh --hostname ssh.SUBDOMAIN.DOMAIN" LINUX_USERNAME@ssh.SUBDOMAIN.DOMAIN
   ```
3. هنگام تأیید اثر انگشت **`yes`** را تایپ کنید و سپس `LINUX_USER_PASSWORD` را وارد کنید.
4. برای دسترسی root دستور **`sudo -i`** را بزنید و همان رمز را وارد کنید.
5. در نسخهٔ دسکتاپ، <https://remotedesktop.google.com/access> را در مرورگر روی یک ماشین دیگر باز کنید و با `GOOGLE_REMOTE_PIN` به میزبان متصل شوید.

</details>

> :warning: **تا زمانی که متصل هستید ورک‌فلو را متوقف نکنید.** ماشین — و نشست از راه دور شما — فقط تا پایان job دوام می‌آورد (سقف رانرهای GitHub **۶ ساعت** است) و سپس همه‌چیز پاک می‌شود.

> :warning: **تا زمانی که متصل هستید به‌روزرسانی سیستم‌عامل نصب نکنید** (مک‌اواس، ویندوز یا به‌روزرسانی‌های بزرگ). ممکن است سیستم ری‌استارت شود و اتصال از راه دور قطع گردد.

---

## به‌روزرسانی Fork

<details>
<summary>آوردن آخرین ورک‌فلوها و اسکریپت‌ها به Fork شما</summary>
<br>

**روش A — در گیت‌هاب:** Fork خود را باز کنید، روی **Sync fork** کنار نام شاخه بزنید و سپس **Update branch** را انتخاب کنید.

**روش B — از ترمینال:**

```bash
git remote add upstream https://github.com/Mimoli001/turbo-disco.git   # فقط برای بار اول
git fetch upstream
git merge upstream/main      # یا: git rebase upstream/main
git push
```

حالا Fork شما آخرین ورک‌فلوها و اسکریپت‌ها را اجرا می‌کند.

</details>

---

## محدودیت‌ها

| # | محدودیت |
| --- | --- |
| 1 | **۶ ساعت** زمان اجرا برای هر job — سقف سختِ رانرهای GitHub. با رسیدن به این سقف، job خاتمه و ماشین پاک می‌شود. |
| 2 | **فایل‌های مهم و حساس را روی ماشین ذخیره نکنید:** همه‌چیز بعد از پایان کار حذف شده و قابل بازگردانی نیست. |
| 3 | هر اجرا **تونل Cloudflare خودش** را روی دامنهٔ شما می‌سازد و تونل اجراهای تمام‌شده را به‌طور خودکار حذف می‌کند؛ پس می‌توانید هر چهار سیستم را همزمان اجرا کنید. تنها محدودیت، سقف پلن کلادفلر شماست (پلن رایگان برای این کار کاملاً کافی است). |
| 4 | **وارد حساب‌های شخصی نشوید** (گوگل، مایکروسافت، بانک و…) مگر اینکه خود حساب کلادفلرتان هم خوب محافظت شده باشد: این تونل‌ها روی دامنهٔ شما منتشر می‌شوند. |
| 5 | Actions در مخازن **عمومی** رایگان و نامحدود است. در یک Fork **خصوصی** ۲٬۰۰۰ دقیقهٔ رایگان ماهانه بین همهٔ ورک‌فلوها مشترک است (لینوکس ۱×، ویندوز ۲×، مک‌اواس ۱۰×). |
| 6 | در پلن GitHub Free حداکثر **۲۰** job همزمان اجرا می‌شود که حداکثر **۵** تای آن‌ها می‌تواند مک‌اواس باشد. |

---

## راه‌حل مشکلات

| مشکل | دلیل محتمل — و راه‌حل |
| --- | --- |
| `cf_tunnel: zone ... is not hosted on this Cloudflare account` | مقدار `CF_DOMAIN` اشتباه است یا DNS آن دامنه روی حساب کلادفلرِ توکن شما نیست. |
| `cf_tunnel: tunnel creation failed` یا خطای 403 از API | توکن `CF_API_TOKEN` نامعتبر یا فاقد دسترسی است — باید Cloudflare Tunnel:Edit، Access:Apps and Policies:Edit، DNS:Edit و Zone:Read داشته باشد. |
| `cloudflared failed to register the tunnel` | دسترسی توکن از بین رفته یا کلادفلر موقتاً مشکل داشته — ورک‌فلو را دوباره اجرا کنید. |
| خطای `cloudflared: command not found` روی رایانهٔ شما | [cloudflared](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/) را نصب کنید — این برنامه کلاینت اتصال شماست. |
| ورک‌فلو بلافاصله بعد از Fork شکست می‌خورد | Fork شما عقب است: [آن را به‌روز کنید](#به‌روزرسانی-fork). |
| اتصال از راه دور بعد از مدتی قطع می‌شود | job تمام شده — دورهٔ keep-alive آن به پایان رسیده یا سقف ۶ ساعته پر شده است. دوباره ورک‌فلو را اجرا کنید. |
| jobهای مک‌اواس در صف می‌مانند | در پلن رایگان حداکثر ۵ job مک‌اواس همزمان اجرا می‌شود. |

---

## نکات امنیتی

- این ماشین‌ها **محیط‌های موقتی** هستند، نه سرور: هرچه رویشان است را بعد از پایان job پاک‌شده فرض کنید.
- ترافیک بین رایانهٔ شما و لبهٔ کلادفلر توسط `cloudflared` رمزگذاری می‌شود؛ توکن `CF_API_TOKEN` و دامنه‌تان را مثل اطلاعات ورود تولیدی نگه دارید — هرکسی که به `ssh/rdp/vnc.<دامنهٔ شما>` دسترسی داشته باشد می‌تواند *تلاش* کند وصل شود (رمز ماشین مجازی محافظ اصلی است).
- از رمزهای عبور یک‌بارمصرف استفاده کنید و اطلاعات اتصال چاپ‌شده در لاگ job را هنگام اجرا، مثل یک Secret محرمانه نگه دارید.

---

## پیشنهادها و ترفندها

- کنترل از راه دور **مک‌اواس** یا **ویندوز** کند و لگ‌دار است؟ Google Remote Desktop یا معمولاً Microsoft Remote Desktop سریع‌ترند.
- حتماً قبل از اجرا پروژه را **Fork** کنید تا بتوانید نام کاربری، نام رایانه و نام‌های نمایشی را عوض کنید.
- هر وقت ورک‌فلوها بالا نمی‌آیند، Fork خود را [به‌روز](#به‌روزرسانی-fork) نگه دارید.

---

## لایسنس

این پروژه تحت [Apache License 2.0](../LICENSE) منتشر شده است.
