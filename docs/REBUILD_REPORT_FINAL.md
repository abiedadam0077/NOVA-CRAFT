# NOVA CRAFT — التقرير النهائي للتنفيذ والتحقق

**التاريخ:** 2026-10-19<br>
**الفرع:** `arena/9027d464-nova-craft`<br>
**التزام الكود الذي بُني:** `6c2b3ef6506c6936e5b2c19466fcd384e2f8360b`<br>
**GitHub Actions:** [التشغيل الناجح 39323231274](https://github.com/abiedadam0077/NOVA-CRAFT/actions/runs/39323231274)<br>
**وسم الإصدار:** `flutter-apk-39323231274-1`<br>
**مرجع المتطلبات:** `NOVA_CRAFT_MASTER_IMPLEMENTATION_BRIEF.md` من المستودع، SHA-1 `5093818629d00df7f041410f002b6bd1cf5ec0ee`.

## الخلاصة

أُصلح مسار الملفات من مصدر المشكلة: Runner يولّد Manifest فعلياً من مجلد بيانات السيرفر، ينشئ مجلد النشر عند غيابه، وينشره إلى GitHub Contents؛ قارئ التطبيق يتحقق من المخطط والطوابع الزمنية والأحجام والمسارات، ويعرض حالات Workflow/الصلاحيات/الشبكة بدلاً من إظهار قائمة أو اتصال وهمي. كذلك فُصلت حالات حفظ سر Playit عن بدء Agent وTunnel وفحص Minecraft، وأضيف مسار آمن لتحديث ملفات Runner للسيرفرات الأقدم.

اجتاز الكود **`flutter analyze` ومجموعة `flutter test` كاملة** في التشغيل النهائي [39323231274](https://github.com/abiedadam0077/NOVA-CRAFT/actions/runs/39323231274) على الالتزام `6c2b3ef6506c6936e5b2c19466fcd384e2f8360b`، ثم بُني APK ونُشر كإصدار prerelease مباشر. فعّل Workflow توقيع v1/v2/v3 وتحقق آلياً من v1/JAR وv2 والمحاذاة والحزمة وSHA-256. كما فُحص سبب تعطل Playit في مستودع المستخدم: سجل Agent المنقح أظهر `Failed to bind to socket: No such file or directory`؛ عُدّل Runner لاستخدام مقبس IPC داخل مجلد مؤقت خاص. لم تُجرَ بعد دورة جديدة في مستودع المستخدم بعد تحديث Runner، لذلك **اتصال Playit/Tunnel بعد الإصلاح لم يُثبت بعد**. ولا يوجد اختبار تثبيت على جهاز/محاكي Android.

## التنزيل المباشر للحزم

الإصدار `[flutter-apk-39323231274-1](https://github.com/abiedadam0077/NOVA-CRAFT/releases/tag/flutter-apk-39323231274-1)` أُنشئ من الالتزام `6c2b3ef6506c6936e5b2c19466fcd384e2f8360b` بعد نجاح التحليل والاختبارات والبناء والتحقق في CI.

### arm64 — موصى به لمعظم أجهزة Android الحديثة

[تنزيل مباشر: NOVA-CRAFT-1.0.0-arm64-debugsigned.apk](https://github.com/abiedadam0077/NOVA-CRAFT/releases/download/flutter-apk-39323231274-1/NOVA-CRAFT-1.0.0-arm64-debugsigned.apk)<br>
الحجم: **27,373,741 بايت**<br>
SHA-256: `042337989f0066908b5b0bd59c88fbb791e584ae75b3c831a9820071680e3119`

### APK شامل

[تنزيل مباشر: NOVA-CRAFT-1.0.0-release-debugsigned.apk](https://github.com/abiedadam0077/NOVA-CRAFT/releases/download/flutter-apk-39323231274-1/NOVA-CRAFT-1.0.0-release-debugsigned.apk)<br>
الحجم: **63,935,243 بايت**<br>
SHA-256: `16e47ee4301005f989a77cc18a6670eb5f29c3b6a08a1d4f4263d0b743f4ce75`

[صفحة الإصدار وتقارير التحقق](https://github.com/abiedadam0077/NOVA-CRAFT/releases/tag/flutter-apk-39323231274-1) · [SHA256SUMS.txt](https://github.com/abiedadam0077/NOVA-CRAFT/releases/download/flutter-apk-39323231274-1/SHA256SUMS.txt) · [تقرير apksigner](https://github.com/abiedadam0077/NOVA-CRAFT/releases/download/flutter-apk-39323231274-1/signature-verification.txt)

نجح CI في إعادة تنزيل APKs المنشورة وفحص SHA-256. القيم أعلاه هي بصمات الأصول المنشورة في بيانات GitHub Releases، وملف `SHA256SUMS.txt` مرفق مرجعاً لها. تعذّر تنزيل محتوى الأصول مباشرةً من بيئة التطوير؛ لذلك لم أزعم فحص الملف محلياً.

**التوقيع:** فعّل Workflow مخططات v1/v2/v3، واجتاز التحقق الآلي لمخططي v1/JAR وv2 وللمحاذاة؛ أُرفق تقرير `apksigner` للرجوع إلى التفاصيل. شهادة التوقيع `CN=Android Debug`. يستخدم CI `--min-sdk-version 19` في أوامر التوقيع والتحقق لإظهار/فرض فحص v1؛ هذا الخيار لا يغيّر `minSdk 26` في Manifest. البناء **debug-signed وليس موقّعاً بمفتاح إنتاج**: لا يوجد keystore إنتاجي متاح. يُنشئ CI مفتاح Debug مؤقتاً لهذا البناء غير الإنتاجي فقط. بسبب اختلاف المفتاح، قد يرفض Android التثبيت فوق APK سابق موقّع بشهادة أخرى؛ انسخ ما تحتاجه ثم أزل التطبيق السابق قبل التثبيت الجديد، مع العلم أن الإزالة تمحو بيانات التطبيق المحلية. لم يُنشأ مفتاح إنتاج بديل.

## ما نُفّذ

### Playit وتشغيل الخادم

- اختيار المستودع صار قبل إعداد Playit، لكتابة `PLAYIT_SECRET_KEY` إلى GitHub Actions Secrets الخاص بالمستودع المحدد والتحقق من حفظه. القيمة لا تُطلب في المحادثة ولا تُطبع في السجلات.
- Runner يستخدم Agent الرسمي المثبّت الإصدار؛ يتحقق من SHA-256، يكتب السر مؤقتاً بصلاحية مقيدة، ويشغّل `playitd` مرة واحدة عبر `--secret-path` مع `--socket-path` داخل مجلد مؤقت خاص (0700). جرى تنقيح السر من سجلات Agent قبل نشرها.
- من سجل التشغيل الحي رقم `39171261156` في `abiedadam0077/Minecraft-server-1-`: السر كان محفوظاً ومنفذ Minecraft المحلي يستجيب، لكن Agent خرج بـ1 بسبب `Failed to bind to socket: No such file or directory`. أُصلح مسار مقبس IPC في القالب واختُبر في CI؛ لم يُحدّث أو يُعاد تشغيل مستودع المستخدم بعد الإصلاح، فلا نزعم نجاح اتصال حي حتى الآن.
- جرى التحقق من مسار بيانات rundata ومخطط Agent/Tunnel بالاستناد إلى عميل Playit الرسمي، مع فصل صريح بين السر المحفوظ، حالة Agent، وجود/توافق Tunnel، عنوان Playit الحقيقي، وفحص منفذ Minecraft المحلي ثم فحص البروتوكول الخارجي. لا يُختلق عنوان ولا حالة اتصال.
- لم يعد التطبيق أو Runner ينشئ Tunnel آلياً؛ المستخدم ينشئه يدوياً مرة واحدة. عند الالتباس يمكن اختيار Tunnel المقصود يدوياً، وتُعرض حالات غياب Tunnel أو عدم توافقه أو عدم تخصيص عنوانه كحالات مستقلة.
- دورة Runner محددة بخمس ساعات، ضمن حد مهلة GitHub Actions البالغ ست ساعات، مع الحفاظ على مسار الإيقاف وإعادة التشغيل.

### Manifest والملفات

- المصدر هو `nova-craft/files/manifest.json` الذي ينشئه Runner من مجلد بيانات السيرفر الحقيقي؛ ليس Artifact دائم لقائمة الملفات. Runner نفسه مؤقت وينتهي بانتهاء Workflow. ملفات العالم الدائمة محفوظة عبر النسخ الاحتياطية/الإصدارات وفق مسار النسخ، لا عبر بقاء Runner.
- عولج غياب مجلد الإخراج الأب أثناء توليد Manifest، وأضيفت حالة فشل منفصلة للتوليد عن فشل نشر GitHub Contents. نُشرت أيضاً لقطة إعدادات نصية محدودة، مع تحذير عند بترها أو تعذر نشرها.
- قارئ التطبيق يتحقق من schema والتاريخ والحجم والعدد والمسارات؛ يرفض traversal والمسارات المطلقة وBackslash والملفات غير الصالحة. يحافظ على Manifest الحقيقي عند فشل Snapshot بدلاً من اختلاق محتوى.
- أضيفت رسائل عربية/إنجليزية قابلة لإعادة المحاولة لحالات التحميل، القائمة/المجلد الفارغ، الخادم المتوقف، Workflow الجاري/الفاشل، منع Contents/Actions، غياب Manifest، وأخطاء API والشبكة والمهلة.
- اختُبرت تنفيذياً عمليات إنشاء ملف ومجلد ومجلد متداخل وتحديثه وانعكاسه على Manifest، مع رفض traversal وsymlink ومحاولة الكتابة خارج جذر البيانات. أُصلحت أيضاً حالات overflow في Skeleton/Empty UI التي كشفتها اختبارات الواجهة.

### ترقية Runner للسيرفرات الموجودة

الإنشاء كان يكتب ملفات Runner الجديدة فقط عند إنشاء السيرفر. أضيف في **إعدادات السيرفر → تحديث المشغّل** مسار صريح للسيرفرات القديمة: يتأكد التطبيق من عدم وجود Workflow نشط، ويطلب التأكيد، ثم يحدّث ملفات المساعدات وسير العمل المولّدة فقط. لا يكتب `server.json` ولا `server.properties` ولا العالم أو النسخ ولا GitHub Secrets. يجب استخدامه بعد توقف التشغيلات القديمة.

## الاختبارات والتحقق

| المرحلة | النتيجة |
|---|---|
| `flutter analyze` على Flutter 3.35.7 | **نجح** في CI رقم 39323231274. |
| `flutter test --reporter expanded` | **نجحت المجموعة كاملة** في التشغيل النهائي نفسه، بما فيها اختبارات Widget والملفات وManifest/Traversal وPlayit وRunner، واختبار socket IPC الخاص وفشل bind المحاكى. |
| بناء APK | **نجح**؛ أُنتجت حزمة arm64 وحزمة شاملة، وأُعيد توقيعهما كمخرجات Debug غير إنتاجية. |
| فحص `aapt` | نجح: `io.github.abiedadam0077.novacraft`, الإصدار `1.0.0`، `minSdk 26`, `targetSdk 35`. |
| فحص `apksigner` | نجح لكل APK: **تحقق v1/JAR وv2**، مع تفعيل v3 في أمر التوقيع واستخدام `--min-sdk-version 19` لإظهار فحص v1. |
| المحاذاة وSHA-256 والنشر | `zipalign -c` نجح؛ أُنشئت checksums، رُفعت الأصول، ثم نزّل CI الملفات المنشورة وفحص SHA-256 بنجاح. |
| محاكاة تنفيذية لـfileops وpublish_files | نجحت ضمن اختبارات CI؛ شملت ملفات ومجلدات متداخلة وتحديثاً وفشل النشر واحتواء المسارات. |
| Playit وMinecraft | اجتازت عقود API/المخطط والمحاكاة واختبار Java Server List Ping محلياً؛ **ليس اتصالاً حياً بالخدمة**. |
| فحوص مساعدة محلية | اجتاز `git diff --check` و`bash -n` و`python3 -m py_compile` لقوالب Runner ومساعداته، وفحص تزامن **914** مفتاح ترجمة ar/en؛ كما نجح smoke محلي لاستيراد عالمي Java/Bedrock ورفض traversal ومزامنة JAR المُدار. |
| Android emulator smoke | **لم يُنفّذ**: طلب workflow اليدوي لهذه النسخة رُفض بـHTTP 403 `Resource not accessible by integration`. |

أظهرت محاولات CI السابقة بعض أخطاء الاختبارات والتحليل أثناء التنفيذ؛ صُححت، والتشغيل النهائي المذكور أعلاه هو الذي اجتاز كل المراحل من التحليل إلى التحقق من APK ونشر رابط التنزيل المباشر. لا أعرض المحاولات الفاشلة على أنها نجاح.

## قائمة الملفات

- **Workflows والتوقيع:** `.github/workflows/flutter.yml`, `.github/workflows/android-smoke.yml`, `android/app/build.gradle.kts`. يوقّع Workflow ملف APK النهائي صراحةً بـv1/v2/v3 ويُفشل CI إن لم يتحقق v1 وv2؛ حُذف `.github/workflows/post_release.yml` الذي كان يحاول إيداع APK ودفعه إلى Git، و`.github/workflows/test_api.yml` الذي كان يضيف استجابات API إلى المستودع تلقائياً.
- **التوثيق:** `README.md`, `docs/PHASE-A-AUDIT-AR.md`, `docs/PLAYIT-DIAGNOSTICS-AR.md`, `docs/REBUILD_REPORT_FINAL.md`.
- **التطبيق والبيانات:** `lib/app.dart`, `lib/core/formatters.dart`, `lib/core/github_api.dart`, `lib/core/models.dart`, `lib/core/playit_api.dart`, `lib/core/provisioner.dart`, `lib/core/strings.dart`, `lib/core/validation.dart`, `lib/core/workflow_templates.dart`, `lib/design/widgets/feedback.dart`, `lib/state/app_state.dart`.
- **الشاشات:** `lib/features/backups/backups_screen.dart`, `lib/features/console/console_screen.dart`, `lib/features/files/files_screen.dart`, `lib/features/network/network_screen.dart`, `lib/features/onboarding/playit_setup_screen.dart`, `lib/features/servers/create_server_screen.dart`, `lib/features/servers/repository_selection_screen.dart`, `lib/features/servers/server_detail_screen.dart`, `lib/features/settings/server_settings_screen.dart`.
- **الاختبارات:** `test/fileops_integration_test.dart`, `test/files_screen_test.dart`, `test/formatters_test.dart`, `test/github_api_test.dart`, `test/models_test.dart`, `test/playit_api_test.dart`, `test/playit_runner_integration_test.dart`, `test/playit_runner_test.dart`, `test/runner_contract_test.dart`, `test/scripts_contract_test.dart`, `test/validation_test.dart`.

## القيود والخطوات اليدوية المتبقية

1. **التحقق الحي بعد الإصلاح ما زال مطلوباً:** فُحص تشغيل حقيقي في `abiedadam0077/Minecraft-server-1-` رقم `39171261156`؛ المنفذ المحلي كان يستجيب لكن Agent فشل قبل الاتصال بسبب socket path. لم يُتحقق من اتصال Agent/Tunnel بعد الإصلاح. بعد تثبيت التطبيق المحدّث، أوقف الدورة الحالية بأمان، ثم شغّل **تحديث المشغّل** وابدأ دورة جديدة؛ لا ترسل قيمة السر ولا تنشئ Tunnel جديداً.
2. أنشئ Agent وTunnel يدوياً في Playit كما يشرح `docs/PLAYIT-DIAGNOSTICS-AR.md`؛ حفظ السر وحده لا يثبت اتصال Agent أو Tunnel. GitHub Actions توفر Runner مؤقتاً وليست استضافة 24/7.
3. للسيرفرات التي أُنشئت بإصدار أقدم، أوقف Workflows النشطة ثم شغّل **تحديث المشغّل** من إعدادات ذلك السيرفر مرة واحدة.
4. لا يوجد اختبار تثبيت/فتح على محاكي أو جهاز فعلي بسبب رفض workflow dispatch بـ403. كذلك لا يمكن اعتبار `flutter analyze`/`flutter test` بديلين عن ذلك.
5. للحصول على APK إنتاجي قابل للتحديث فوق نسخة إصدار سابقة، يجب أن يوفّر مالك المشروع keystore إنتاجياً صالحاً لأسرار CI؛ النسخة المرتبطة هنا Debug-signed فقط.
