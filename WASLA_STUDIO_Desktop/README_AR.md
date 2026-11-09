# WASLA STUDIO — تطبيق Windows

هذه حزمة مصدر أولية لتحويل نسخة WASLA STUDIO الحالية إلى تطبيق سطح مكتب Windows باستخدام Tauri 2.

## ما تم الحفاظ عليه
- ملف واجهة WASLA STUDIO الحالي بما فيه لوحة المدير والموظف.
- تسجيل الدخول عبر Supabase Auth والجلسات المحفوظة محليًا.
- مزامنة `workspace_data`.
- تكليفات الموظفين وتحديثاتهم وإشعارات المدير.
- لوحة أداء الموظفين وتفاصيل المهام.
- النسخ الاحتياطي JSON والاستعادة.
- نفس مشروع Supabase ومفتاح Publishable الموجود في نسخة الويب؛ لا يوجد Service Role Key داخل التطبيق.

## متطلبات بناء ملف EXE على Windows
1. Windows 10/11.
2. Node.js 22 LTS.
3. Rust stable مع MSVC toolchain.
4. Microsoft C++ Build Tools (Desktop development with C++).
5. WebView2 Runtime (موجود عادةً في Windows 10/11).

## البناء محليًا
افتح PowerShell داخل مجلد المشروع ونفّذ:

```powershell
npm install
npm run tauri -- build --bundles nsis
```

أو شغّل الملف `build-windows.bat` بنقرتين لبدء البناء تلقائيًا.

سيظهر ملف التثبيت غالبًا في:

`src-tauri\target\release\bundle\nsis\WASLA STUDIO_1.0.0_x64-setup.exe`

## البناء عبر GitHub Actions
ارفع محتويات هذا المجلد إلى مستودع GitHub، ثم افتح Actions واختر `Build WASLA STUDIO for Windows` واضغط Run workflow. بعد اكتمال البناء نزّل Artifact باسم `WASLA-STUDIO-Windows-Installer`.

## ملاحظات مهمة قبل التوزيع
- هذه نسخة أولية مغلفة بسطح مكتب، وليست بعدُ نسخة موقعة رقميًا. قد يعرض Windows SmartScreen تحذيرًا عند التثبيت حتى يتم توقيع الملف بشهادة Code Signing.
- الاتصال بالإنترنت مطلوب لتسجيل الدخول ومزامنة Supabase، وكذلك لتحميل مكتبة Supabase JS من jsDelivr.
- استعادة كلمة المرور تُفتح عبر نسخة الويب الحالية على Netlify، ثم يمكن تسجيل الدخول في تطبيق سطح المكتب بكلمة المرور الجديدة.
- يجب إضافة عنوان الموقع التالي إلى Supabase Auth > URL Configuration > Redirect URLs إذا لم يكن موجودًا بالفعل:
  `https://elaborate-chimera-2d1aaa.netlify.app/`
- لم يتم تعديل قاعدة بيانات Supabase أو سياسات RLS أو حسابات المستخدمين.
- لا تضع أبدًا `service_role` أو أي مفتاح سري داخل تطبيق سطح المكتب.

## اختبار ما قبل الاعتماد
يجب اختبار تسجيل دخول المدير والموظف، تحميل المشاريع، إنشاء/تعديل سجل تجريبي، التكليفات، تحديث الموظف، إشعارات المدير، تسجيل الخروج، ثم النسخ الاحتياطي والاستعادة على جهاز Windows فعلي قبل توزيع النسخة.
