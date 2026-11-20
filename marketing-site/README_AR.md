# موقع WASLA STUDIO التسويقي

هذا المجلد مستقل تماماً عن تطبيق Windows والويب الموجود داخل `WASLA_STUDIO_Desktop`.

## النشر المقترح
أنشئ موقعاً جديداً في Netlify (لا تستخدم إعدادات الموقع الحالي الخاص بالتطبيق):
- Repository: `salehkhalaf213-stack/wasla-studio-windows-app`
- Branch: `feature/wasla-v6`
- Base directory: `marketing-site`
- Publish directory: `.`
- Build command: اتركه فارغاً (موقع HTML ثابت).

بعد اختيار وشراء الدومين، استبدل `YOUR-DOMAIN-HERE` في `index.html` و`robots.txt` و`sitemap.xml` بالدومين الفعلي، ثم أضفه إلى إعدادات الدومين في موقع Netlify الجديد.

## تنبيه
لا تغيّر إعدادات Netlify الخاصة بتطبيق WASLA STUDIO الحالي. لا يحتوي الموقع التسويقي على اتصال بقاعدة بيانات المنصة ولا ينفذ تفعيل الاشتراك تلقائياً؛ طلبات الاشتراك تُرسل عبر واتساب للمراجعة اليدوية.
