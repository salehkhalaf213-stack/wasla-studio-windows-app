# QENTRIVO — تطبيق Windows

حزمة تطبيق سطح المكتب مبنية باستخدام **Tauri 2**، ومحدّثة لتستخدم واجهة QENTRIVO الحالية.

## ما تتضمنه النسخة 1.1.0
- واجهة QENTRIVO الحالية، بما فيها شاشة الدخول المحسّنة والترجمة الإنجليزية.
- تسجيل الدخول عبر Supabase Auth مع Cloudflare Turnstile.
- إدارة العملاء والمشاريع والمحتوى والمالية والفريق وبوابة العميل.
- مزامنة مساحة العمل والوظائف الحالية مع Supabase.
- الاحتفاظ بمفاتيح التخزين المحلية الحالية لتجنب تغيير بنية بيانات التطبيق.

## حماية بيانات التطبيق المحلي
- تم الإبقاء على معرّف التطبيق الحالي: `com.waslastudio.workspace`.
- لا تغيّر `identifier` في `src-tauri/tauri.conf.json`.
- لا تغيّر إعداد `useHttpsScheme` أو مخطط WebView الافتراضي؛ تغيير عنوان الأصل قد يجعل WebView ينشئ مخزناً محلياً جديداً.
- لا تحذف النسخة القديمة ولا مجلد بياناتها أثناء الترقية.
- لم يتم تعديل قاعدة بيانات Supabase أو سياسات RLS أو حسابات المستخدمين أو البيانات المالية.

## إعدادات مطلوبة قبل اختبار تسجيل الدخول
1. في Cloudflare Turnstile، افتح الـ widget المستخدم حالياً وأضف hostname التالي إلى قائمة النطاقات المسموح بها، مع الإبقاء على النطاق الحالي:
   - `tauri.localhost`
   - `wasla-workspace.pages.dev`
2. في Supabase Auth > URL Configuration، تأكد من السماح بعنوان إعادة التوجيه:
   - `https://wasla-workspace.pages.dev/`
3. لا تغيّر Site Key أو Secret الحاليين داخل إعدادات التطبيق.

## روابط البريد الإلكتروني
- روابط تأكيد الحساب واستعادة كلمة المرور تُوجّه إلى نسخة الويب العامة: `https://wasla-workspace.pages.dev/`.
- عند استعادة كلمة المرور، أكمل التغيير في المتصفح ثم ارجع إلى تطبيق QENTRIVO وسجّل الدخول بكلمة المرور الجديدة.
- روابط تسجيل العملاء التي ينشئها التطبيق تستخدم نطاق QENTRIVO العام، وليس عنوان WebView المحلي.

## متطلبات بناء ملف التثبيت
- Windows 10 أو 11.
- Node.js 22 LTS.
- Rust stable مع MSVC toolchain.
- Microsoft C++ Build Tools (Desktop development with C++).
- WebView2 Runtime.

## البناء محلياً
افتح PowerShell داخل مجلد `WASLA_STUDIO_Desktop` ونفّذ:

```powershell
npm install
npm run build
npm run tauri -- build --bundles nsis
```

أو شغّل `build-windows.bat`.

سيظهر ملف التثبيت في المسار:

`src-tauri\target\release\bundle\nsis\QENTRIVO_1.1.0_x64-setup.exe`

## البناء عبر GitHub Actions
يبدأ سير العمل تلقائياً عند دفع تحديث إلى الفرع `feature/wasla-web-v6`. بعد نجاحه، نزّل Artifact باسم `QENTRIVO-Windows-Installer` من صفحة Actions.

## ملاحظات
- هذه نسخة غير موقّعة رقمياً؛ قد يعرض Windows SmartScreen تحذيراً عند التثبيت.
- الاتصال بالإنترنت مطلوب لتسجيل الدخول ومزامنة Supabase وتحميل مكتبة Supabase JS وTurnstile.
- يجب اختبار تسجيل دخول المدير والموظف، تحميل البيانات، التكليفات، بوابة العميل، النسخ الاحتياطي والاستعادة على جهاز Windows قبل اعتماد التوزيع.
