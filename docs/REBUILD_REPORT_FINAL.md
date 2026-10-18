# NOVA CRAFT — التقرير النهائي للتنفيذ والتحقق

**التاريخ:** 2026-10-18<br>
**الفرع:** `arena/9027d464-nova-craft`<br>
**التزام الكود الذي بُني:** `48b4866b6b027429589229d7c739830027b1f21e`<br>
**GitHub Actions:** [التشغيل الناجح 39157739464](https://github.com/abiedadam0077/NOVA-CRAFT/actions/runs/39157739464)<br>
**وسم الإصدار:** `flutter-apk-39157739464-1`<br>
**مرجع المتطلبات:** `NOVA_CRAFT_MASTER_IMPLEMENTATION_BRIEF.md` من المستودع، SHA-1 `5093818629d00df7f041410f002b6bd1cf5ec0ee`.

## الخلاصة

أُصلح مسار الملفات من مصدر المشكلة: Runner يولّد Manifest فعلياً من مجلد بيانات السيرفر، ينشئ مجلد النشر عند غيابه، وينشره إلى GitHub Contents؛ قارئ التطبيق يتحقق من المخطط والطوابع الزمنية والأحجام والمسارات، ويعرض حالات Workflow/الصلاحيات/الشبكة بدلاً من إظهار قائمة أو اتصال وهمي. كذلك فُصلت حالات حفظ سر Playit عن بدء Agent وTunnel وفحص Minecraft، وأضيف مسار آمن لتحديث ملفات Runner للسيرفرات الأقدم.

اجتاز الكود **`flutter analyze` ومجموعة `flutter test` كاملة** في CI، ثم بُني APK وفُحصت الحزمة والتوقيع والبصمات. رُفع الإصدار إلى GitHub وأعاد CI تنزيل APK المنشور وفحص SHA-256 بنجاح. هذا تحقق آلي موثق، لكنه **ليس اختبار اتصال حيّاً بـPlayit أو Minecraft ولا اختباراً على جهاز/محاكي Android**.

## التنزيل المباشر للحزم

### arm64 — موصى به لمعظم أجهزة Android الحديثة

[تنزيل مباشر: NOVA-CRAFT-1.0.0-arm64-debugsigned.apk](https://github.com/abiedadam0077/NOVA-CRAFT/releases/download/flutter-apk-39157739464-1/NOVA-CRAFT-1.0.0-arm64-debugsigned.apk)<br>
الحجم: **25,355,922 بايت**<br>
SHA-256: `d7df6aeb2dc53755bce9a0f6a3f55dfbc27afd5be4433d7f60222bbe908edd45`

### APK شامل

[تنزيل مباشر: NOVA-CRAFT-1.0.0-release-debugsigned.apk](https://github.com/abiedadam0077/NOVA-CRAFT/releases/download/flutter-apk-39157739464-1/NOVA-CRAFT-1.0.0-release-debugsigned.apk)<br>
الحجم: **61,525,713 بايت**<br>
SHA-256: `81f652515e6b25bb8038766d4b157bb9f1ca3b2398276c12db38f570e3aa02f2`

[صفحة الإصدار وتقارير التحقق](https://github.com/abiedadam0077/NOVA-CRAFT/releases/tag/flutter-apk-39157739464-1) · [SHA256SUMS.txt](https://github.com/abiedadam0077/NOVA-CRAFT/releases/download/flutter-apk-39157739464-1/SHA256SUMS.txt) · [تقرير apksigner](https://github.com/abiedadam0077/NOVA-CRAFT/releases/download/flutter-apk-39157739464-1/signature-verification.txt)

GitHub Release API يعرض SHA-256 لكل APK في حقل `digest`، ونجح فحص SHA-256 بعد إعادة التنزيل داخل الـworkflow. مضيف تنزيل أصول GitHub غير متاح من بيئة التطوير نفسها، لذلك لم أزعم أنني نزّلت ملف APK محلياً؛ الرابط المباشر وحالة الأصل `uploaded` متحقق منهما من GitHub، والتحقق من محتوى التنزيل نفذه CI.

**التوقيع:** اجتاز APK فحص `apksigner`، لكنه **debug-signed وليس موقّعاً بمفتاح إنتاج**. لا يوجد keystore إنتاجي متاح في المستودع/البيئة. APK مناسب للاختبار، لكنه لا يحدّث تثبيتاً سابقاً موقّعاً بمفتاح مختلف. لم يُنشأ مفتاح إنتاج بديل.

## ما نُفّذ

### Playit وتشغيل الخادم

- اختيار المستودع صار قبل إعداد Playit، لكتابة `PLAYIT_SECRET_KEY` إلى GitHub Actions Secrets الخاص بالمستودع المحدد والتحقق من حفظه. القيمة لا تُطلب في المحادثة ولا تُطبع في السجلات.
- Runner يستخدم Agent الرسمي المثبّت الإصدار؛ يتحقق من SHA-256، يكتب السر مؤقتاً بصلاحية مقيدة، ويشغّل `playitd` مرة واحدة عبر `--secret-path`. جرى تنقيح السر من سجلات Agent قبل نشرها.
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
| `flutter analyze` على Flutter 3.35.7 | **نجح** في CI رقم 39157739464. |
| `flutter test --reporter expanded` | **نجحت المجموعة كاملة** في التشغيل نفسه، بما فيها اختبارات Widget والملفات وManifest/Traversal وPlayit وRunner. |
| بناء APK | **نجح**؛ أُنتجت حزمة arm64 وحزمة شاملة. |
| فحص `aapt` | نجح: `io.github.abiedadam0077.novacraft`, الإصدار `1.0.0`، `minSdk 26`, `targetSdk 35`. |
| فحص `apksigner` | نجح؛ المفتاح Debug كما هو موضح أعلاه. |
| SHA-256 والنشر | أُنشئت checksums، رُفعت الأصول، ثم نزّل CI APK المنشور وفحص checksum بنجاح. |
| محاكاة تنفيذية لـfileops وpublish_files | نجحت ضمن اختبارات CI؛ شملت ملفات ومجلدات متداخلة وتحديثاً وفشل النشر واحتواء المسارات. |
| Playit وMinecraft | اجتازت عقود API/المخطط والمحاكاة واختبار Java Server List Ping محلياً؛ **ليس اتصالاً حياً بالخدمة**. |
| فحوص مساعدة محلية | اجتاز `git diff --check` و`bash -n` و`python3 -m py_compile` لقوالب Runner ومساعداته، وفحص تزامن **869** مفتاح ترجمة ar/en. |
| Android emulator smoke | **لم يُنفّذ**: طلب workflow اليدوي لهذه النسخة رُفض بـHTTP 403 `Resource not accessible by integration`. |

أظهرت محاولات CI السابقة بعض أخطاء الاختبارات والتحليل أثناء التنفيذ؛ صُححت، والتشغيل النهائي أعلاه هو الذي اجتاز كل المراحل من التحليل إلى التحقق من APK. لا أعرض المحاولات الفاشلة على أنها نجاح.

## قائمة الملفات

- **Workflows:** `.github/workflows/flutter.yml`, `.github/workflows/android-smoke.yml`. حُذف `.github/workflows/post_release.yml` الذي كان يحاول إيداع APK ودفعه إلى Git، و`.github/workflows/test_api.yml` الذي كان يضيف استجابات API إلى المستودع تلقائياً.
- **التوثيق:** `README.md`, `docs/PHASE-A-AUDIT-AR.md`, `docs/PLAYIT-DIAGNOSTICS-AR.md`, `docs/REBUILD_REPORT_FINAL.md`.
- **التطبيق والبيانات:** `lib/app.dart`, `lib/core/formatters.dart`, `lib/core/github_api.dart`, `lib/core/models.dart`, `lib/core/playit_api.dart`, `lib/core/provisioner.dart`, `lib/core/strings.dart`, `lib/core/validation.dart`, `lib/core/workflow_templates.dart`, `lib/design/widgets/feedback.dart`, `lib/state/app_state.dart`.
- **الشاشات:** `lib/features/backups/backups_screen.dart`, `lib/features/console/console_screen.dart`, `lib/features/files/files_screen.dart`, `lib/features/network/network_screen.dart`, `lib/features/onboarding/playit_setup_screen.dart`, `lib/features/servers/create_server_screen.dart`, `lib/features/servers/repository_selection_screen.dart`, `lib/features/servers/server_detail_screen.dart`, `lib/features/settings/server_settings_screen.dart`.
- **الاختبارات:** `test/fileops_integration_test.dart`, `test/files_screen_test.dart`, `test/formatters_test.dart`, `test/github_api_test.dart`, `test/models_test.dart`, `test/playit_api_test.dart`, `test/playit_runner_integration_test.dart`, `test/playit_runner_test.dart`, `test/runner_contract_test.dart`, `test/scripts_contract_test.dart`, `test/validation_test.dart`.

## القيود والخطوات اليدوية المتبقية

1. **لا يوجد اختبار حي لـPlayit/Minecraft:** لم يُحدد مستودع خادم لهذا الاختبار، ولم يُستخدم سر المستخدم أو Tunnel فعلي أو خادم Minecraft حي. لا ترسل السر؛ عند طلب اختبار فعلي يكفي `OWNER/REPO` مع إتاحة Workflow، وتقوم أنت بإضافة السر عبر التطبيق/Secrets.
2. أنشئ Agent وTunnel يدوياً في Playit كما يشرح `docs/PLAYIT-DIAGNOSTICS-AR.md`؛ حفظ السر وحده لا يثبت اتصال Agent أو Tunnel. GitHub Actions توفر Runner مؤقتاً وليست استضافة 24/7.
3. للسيرفرات التي أُنشئت بإصدار أقدم، أوقف Workflows النشطة ثم شغّل **تحديث المشغّل** من إعدادات ذلك السيرفر مرة واحدة.
4. لا يوجد اختبار تثبيت/فتح على محاكي أو جهاز فعلي بسبب رفض workflow dispatch بـ403. كذلك لا يمكن اعتبار `flutter analyze`/`flutter test` بديلين عن ذلك.
5. للحصول على APK إنتاجي قابل للتحديث فوق نسخة إصدار سابقة، يجب أن يوفّر مالك المشروع keystore إنتاجياً صالحاً لأسرار CI؛ النسخة المرتبطة هنا Debug-signed فقط.
