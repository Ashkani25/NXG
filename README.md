# NEXORA — نسخه‌ی کامل آفلاین (Full Pack v1.0)

> NEXORA is a connected cosmic digital universe where social interaction, communication, gaming, AI, communities and personal digital identity exist together in one immersive experience.
> **YOUR UNIVERSE. YOUR IDENTITY. YOUR EXPERIENCE.**

اپ اندروید Flutter که **بدون اینترنت و بدون سرور کامل کار می‌کند**: هویت دیجیتال، سفر سینمایی اول، هاب ایستگاه، ۷ دنیا و ۹ بازی با بات هوشمند و حالت چندنفره روی یک گوشی. همه‌چیز طوری نوشته شده که بعداً با Supabase و LiveKit آنلاین شود (راهنما: `docs/ONLINE_SETUP.md`).

## دریافت APK
هر push روی GitHub یک بیلد می‌سازد: تب **Actions** ← آخرین اجرای «NEXORA Android Build» ← بخش Artifacts ← **NEXORA-apk**.

## آنچه در این نسخه هست
| بخش | وضعیت آفلاین |
|---|---|
| THE FIRST JOURNEY | سفر سینمایی ~۵۶ ثانیه، Skip، نسخه‌ی کوتاه، کاهش حرکت |
| هویت دیجیتال | Explorer ID، نام، آواتار، سطح/XP، سکه، دستاوردها — ذخیره روی گوشی |
| NEXORA HUB | حلقه‌ی مداری ۲.۵بعدی پورتال‌ها، جستجوی سراسری، منوی سریع، گوی ORACLE |
| NEXORA ARCADE | ۹ بازی: فوتبال انگشتی، کارم، بیلیارد، تخته‌نرد، لودو، مار و پله، کارت‌های NX (سبک UNO)، کوییز، مافیا |
| PERSONAL ORBIT | آواتار و کمد لباس، فضای شخصی با تزئین، دستاورد، آمار، فعالیت، جایزه‌ی روزانه و چالش‌ها |
| NEXORA EXCHANGE | فروشگاه شفاف با سکه‌ی داخلی (بدون قمار/جعبه‌ی شانسی) |
| ORACLE CORE | دستیار آفلاین فارسی/انگلیسی: راهنما، قوانین بازی‌ها، آمار، ناوبری و تغییر تنظیمات |
| NOVA GALLERY | پست، استوری، ریلز حرکتی، هشتگ، لایک/کامنت/ذخیره، جستجو |
| ORBIT NETWORK | چت ذخیره، گروه و کانال محلی، اشتراک از دنیاها، دعوت به بازی |
| SOCIAL STATION | اجتماعات، نقش‌ها، رویداد، مسابقه‌ی محلی با براکت |

آنچه واقعاً اینترنت لازم دارد (کاربران واقعی، تماس، بازی آنلاین، رتبه‌ی جهانی، مدل زبانی) در اپ با برچسب صادقانه «نیاز به اتصال آنلاین» مشخص است — هیچ چیز ساختگی نیست.

## ساختار
```
lib/
  app/            MaterialApp، روتر و انتقال‌های سینمایی
  core/           تم، تنظیمات، ذخیره‌ی محلی، هویت/پیشرفت، کاتالوگ، ویجت‌ها، درز بک‌اند
  games/          ۹ ماژول بازی (هر کدام core خالص Dart + ui) + قرارداد و رجیستری
  worlds/         journey، onboarding، hub، arcade و ۶ دنیای دیگر
assets/           ۲۲۹ دارایی گرافیکی WebP
supabase/         migrationها و Edge Function برای آنلاین شدن
docs/             کیت اصلی پروژه، راهنمای آنلاین، پیشرفت و تصمیم‌ها
.github/workflows ساخت APK
```

## توسعه
```bash
flutter create --platforms=android --org com.nexora --project-name nexora .   # یک‌بار، پوشه‌ی android
flutter pub get
flutter analyze && flutter test
flutter run
```
