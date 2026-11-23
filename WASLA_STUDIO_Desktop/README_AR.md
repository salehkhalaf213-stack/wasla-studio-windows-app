# QENTRIVO — تطبيق Windows

هذه حزمة مصدر تطبيق QENTRIVO لسطح مكتب Windows باستخدام Tauri 2.

## ما تم الحفاظ عليه
- واجهة مساحة العمل ولوحات المدير والموظف.
- تسجيل الدخول عبر Supabase Auth والجلسات المحفوظة محليًا.
- مزامنة بيانات مساحة العمل.
- تكليفات الموظفين وتحديثاتهم وإشعارات المدير.
- لوحة أداء الموظفين وتفاصيل المهام.
- النسخ الاحتياطي JSON والاستعادة.
- نفس مشروع Supabase ومفتاح Publishable الموجود في نسخة الويب؛ لا يوجد Service Role Key داخل التطبيق.
- معرّف التطبيق الداخلي ومفاتيح التخزين وتنسيق النسخ الاحتياطي القديمة محفوظة عمدًا لضمان التوافق مع التثبيتات والبيانات السابقة.

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
npm run tauri -- icon src-tauri/icons/qentrivo-source.svg
npm run tauri -- build --bundles nsis
```

أو شغّل الملف `build-windows.bat` بنقرتين؛ سيجهّز الأيقونات من شعار QENTRIVO ثم يبدأ البناء.

سيظهر ملف التثبيت غالبًا في:

`src-tauri\target\release\bundle\nsis\QENTRIVO_1.0.0_x64-setup.exe`

## البناء عبر GitHub Actions
افتح Actions في مستودع المشروع وشغّل سير العمل `Build QENTRIVO Windows Preview` على فرع `feature/qentrivo-windows-preview`. بعد اكتمال البناء نزّل Artifact باسم `QENTRIVO-Windows-Preview-Installer`.

## ملاحظات مهمة قبل التوزيع
- هذه نسخة أولية مغلفة بسطح مكتب، وليست بعدُ نسخة موقعة رقميًا. قد يعرض Windows SmartScreen تحذيرًا عند التثبيت حتى يتم توقيع الملف بشهادة Code Signing.
- الاتصال بالإنترنت مطلوب لتسجيل الدخول ومزامنة Supabase، وكذلك لتحميل مكتبة Supabase JS من jsDelivr.
- استعادة كلمة المرور تُفتح عبر نسخة الويب الحالية، ثم يمكن تسجيل الدخول في تطبيق سطح المكتب بكلمة المرور الجديدة.
- لم يتم تعديل قاعدة بيانات Supabase أو سياسات RLS أو حسابات المستخدمين ضمن تحديث الهوية.
- لا تضع أبدًا `service_role` أو أي مفتاح سري داخل تطبيق سطح المكتب.

## اختبار ما قبل الاعتماد
يجب اختبار تسجيل دخول المدير والموظف، تحميل المشاريع، التكليفات، تحديث الموظف، إشعارات المدير، تسجيل الخروج، ثم النسخ الاحتياطي والاستعادة على جهاز Windows فعلي قبل توزيع النسخة.
