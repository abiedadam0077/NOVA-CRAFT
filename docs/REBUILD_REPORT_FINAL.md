# NOVA CRAFT — تقرير التنفيذ والتحقق للإصدار المنشور

- **تاريخ التحقق:** 2026-10-18
- **الفرع:** `arena/9027d464-nova-craft`
- **الالتزام المبني:** `3281825403357854e90b946fe10d4c5530016baf`
- **مرجع التنفيذ:** `NOVA_CRAFT_MASTER_IMPLEMENTATION_BRIEF.md` من مستودع GitHub، SHA-1 `5093818629d00df7f041410f002b6bd1cf5ec0ee`.

## الخلاصة

اكتمل تنفيذ مسارات الإعداد وGitHub وPlayit والنسخ والاستعادة والواجهة ضمن المستودع. نجح GitHub Actions في التحليل الساكن، والاختبارات، وبناء APK، وفحص الحزمة والتوقيع والبصمة، ورفع الملفات ثم تنزيل APK المنشور والتحقق منه مرة أخرى. أُنشئ إصدار تجريبي على GitHub بالوسم `flutter-apk-39116644482-1`.

- [تشغيل CI الناجح 39116644482](https://github.com/abiedadam0077/NOVA-CRAFT/actions/runs/39116644482)
- [صفحة الإصدار وملفات التحقق](https://github.com/abiedadam0077/NOVA-CRAFT/releases/tag/flutter-apk-39116644482-1)
- **تنزيل arm64 المباشر (موصى به لمعظم أجهزة Android الحديثة):** [NOVA-CRAFT-1.0.0-arm64-debugsigned.apk](https://github.com/abiedadam0077/NOVA-CRAFT/releases/download/flutter-apk-39116644482-1/NOVA-CRAFT-1.0.0-arm64-debugsigned.apk)
- **تنزيل APK الشامل:** [NOVA-CRAFT-1.0.0-release-debugsigned.apk](https://github.com/abiedadam0077/NOVA-CRAFT/releases/download/flutter-apk-39116644482-1/NOVA-CRAFT-1.0.0-release-debugsigned.apk)

## ملفات APK والبصمات والتوقيع

| الحزمة | الحجم المنشور | SHA-256 |
|---|---:|---|
| `NOVA-CRAFT-1.0.0-arm64-debugsigned.apk` | 25,093,613 بايت | `5ab649d40224c155350784af8e370cd88a536ad47325db796312b85af7f68d0f` |
| `NOVA-CRAFT-1.0.0-release-debugsigned.apk` | 60,853,801 بايت | `3b3e20634e9d9fcbc364db12ac13f3f1e8fc408122397928996e1c3d8fdf02f2` |

مصدر البصمتين هو حقل `digest` الرسمي لكل ملف في GitHub Release API، كما اجتاز الـworkflow خطوة إنشاء SHA-256 وفحص نسخة APK التي أعاد تنزيلها من الإصدار المنشور. أرفق الإصدار أيضاً [SHA256SUMS.txt](https://github.com/abiedadam0077/NOVA-CRAFT/releases/download/flutter-apk-39116644482-1/SHA256SUMS.txt) و[تقرير تحقق apksigner](https://github.com/abiedadam0077/NOVA-CRAFT/releases/download/flutter-apk-39116644482-1/signature-verification.txt). بيئة العمل الحالية تمنع الوصول إلى مضيف GitHub الخاص بملفات الإصدار؛ لذلك لم أتمكن من إعادة تنزيل الباينري من داخل هذه البيئة. تحقق workflow من الباينري المنشور نفسه بنجاح، ورابط التنزيل أعلاه هو رابط GitHub المباشر المسجل للأصل.

**التوقيع:** نجح فحص `apksigner` في CI، لكن الملفين **موقّعان بمفتاح debug الخاص بالبناء** (`debugsigned`) وليسا موقّعين بمفتاح إنتاج. لا يوجد keystore إنتاجي ملتزم بالمستودع، ولم أتمكن من قراءة أسرار GitHub Actions (واجهت قراءة الأسرار HTTP 403)، لذلك لا أقدّم هذا الإصدار على أنه إصدار إنتاج. استخدامه للاختبار ممكن، لكنه لن يحدّث تثبيتاً سابقاً موقّعاً بمفتاح مختلف. لم يُنشأ مفتاح إنتاج أو يُخترع.

بيانات الحزمة وفق تقرير الفحص المرفق: `io.github.abiedadam0077.novacraft`، الإصدار `1.0.0`، `minSdk 26` و`targetSdk 35` و`compileSdk 36`. رمز نسخة APK الخاص بـarm64 هو `2001`، والشامل `1` وفق تقرير `aapt` المنشور.

## نتائج التحقق

| الفحص | النتيجة |
|---|---|
| `flutter analyze` | نجح في تشغيل CI رقم `39116644482`. |
| `flutter test` | نجحت مجموعة اختبارات الوحدة والواجهات في التشغيل نفسه. |
| بناء Android APK | نجح؛ أُنشئت حزمة arm64 وحزمة شاملة. |
| اسم الحزمة والإصدار/SDK | فُحصت بواسطة أدوات Android ضمن CI. |
| توقيع APK | اجتاز `apksigner` التحقق؛ التوقيع debug وليس إنتاجياً. |
| checksum ورفع الإصدار | نُشرت البصمات وتقارير الفحص، ثم أُعيد تنزيل APK وفُحصت البصمة بنجاح ضمن CI. |
| `git diff --check` | اجتاز الفحص المحلي. |
| `bash -n` و`python3 -m py_compile` | نجحت على runner وأدوات المساعدة المستخرجة في الفحوص المحلية السابقة. |
| اختبار YAML وتهيئة workflow المولّد | نجح في الفحوص المحلية السابقة؛ وبنى CI التطبيق من القالب بنجاح. |
| مفاتيح العربية والإنجليزية | 765 مفتاحاً متطابقاً، بلا مفاتيح ناقصة أو مكررة في الفحص المحلي السابق. |
| محاكاة Playit والنسخ | نجحت الحالات الاصطناعية المسجلة أدناه؛ ليست اتصالات حية بخدمات خارجية. |

كانت هناك محاولتان سابقتان فشلتا أثناء التحقق: الأولى كشفت أخطاء `flutter analyze`، والثانية كشفت توقعين قديمين في اختبارات عقود runner. أُصلحت الأخطاء، ونجحت المحاولة الثالثة المذكورة أعلاه من التحليل حتى النشر.

لم تتوفر Flutter/Dart محلياً. كما فشلت محاولة إعادة تشغيل محلّل `tree-sitter-dart` محلياً بسبب غياب وحدة Python `tree_sitter`؛ لذا لا أعدّ ذلك فحصاً ناجحاً. نتيجة `flutter analyze` الناجحة مصدرها CI.

## ما نُفّذ

- **GitHub والإعداد:** إضافة اختيار مستودع يملكه المستخدم ويملك صلاحية الكتابة قبل إدخال سر Playit؛ دعم تهيئة المستودع وفحص نجاح حفظ GitHub Secret وقراءة صفحات API المتعددة. مسح سر Playit المحلي عند تسجيل الخروج.
- **Playit:** إزالة Claim وإنشاء Tunnel آلياً. ينشئ المستخدم Tunnel يدوياً مرة واحدة؛ يجري التطبيق/runner فحصاً عبر واجهة Playit الرسمية لاختيار Tunnel الملتبس وقراءة عنوانه الحقيقي. يعيد runner الفحص عند عدم تخصيص العنوان بعد. يوجد تخطي موثق وعنوان يدوي واضح المصدر، ولا يُختلق عنوان أو اتصال ناجح.
- **تشغيل الخادم:** دورة تشغيل مخططة لخمس ساعات (18,000 ثانية) ضمن مهلة GitHub Actions البالغة ست ساعات، مع خيارات restart/stop، واستمرار الدورة فقط عند تفعيلها. تُفحص مسارات البيانات والجذور المحمية والروابط الرمزية.
- **Backup/Restore:** انتظار تأكيد حفظ Java/Bedrock قبل الأرشفة، حد ZIP مقداره 2 GiB، وفحص ZIP وchecksum. لا يُحتفظ بنسخة ولا تُوسم موثقة إلا بعد إعادة تنزيلها والتحقق منها. تُفلتر النسخ حسب الخادم؛ الاستعادة ترفض traversal وتتحقق من الهوية والبصمة وتدعم rollback. شاشة النسخ تتيح تنزيل أرشيف العالم للنسخة المحددة.
- **الواجهة والأمان:** اختيار Tunnel عند وجود أكثر من نتيجة دون تخمين، فصل العنوان المبلّغ من Playit عن العنوان اليدوي، منع أوامر الكونسول المحجوزة عند تعطيلها، وتدقيق مدخلات ومسارات ملفات الخادم. أضيفت إعدادات retention بعدد النسخ.
- **التوطين:** دعم العربية RTL والإنجليزية LTR مع تزامن مفاتيح الترجمة.

## الملفات المعدّلة

- **التوثيق:** `README.md`, `docs/PHASE-A-AUDIT-AR.md`, `docs/REBUILD_REPORT_FINAL.md`.
- **GitHub Actions:** `.github/workflows/flutter.yml`, `.github/workflows/android-smoke.yml`; حذف `.github/workflows/post_release.yml` و`.github/workflows/test_api.yml`.
- **منطق التطبيق:** `lib/app.dart`, `lib/core/github_api.dart`, `lib/core/models.dart`, `lib/core/playit_api.dart`, `lib/core/provisioner.dart`, `lib/core/strings.dart`, `lib/core/validation.dart`, `lib/core/workflow_templates.dart`, `lib/state/app_state.dart`.
- **الشاشات:** `lib/features/backups/backups_screen.dart`, `lib/features/console/console_screen.dart`, `lib/features/network/network_screen.dart`, `lib/features/onboarding/playit_setup_screen.dart`, `lib/features/servers/create_server_screen.dart`, `lib/features/servers/repository_selection_screen.dart`, `lib/features/servers/server_detail_screen.dart`, `lib/features/settings/server_settings_screen.dart`.
- **الاختبارات:** `test/github_api_test.dart`, `test/models_test.dart`, `test/playit_api_test.dart`, `test/runner_contract_test.dart`, `test/scripts_contract_test.dart`, `test/validation_test.dart`.

## القيود والخطوات المتبقية

- **Android emulator smoke:** محاولة تشغيل `.github/workflows/android-smoke.yml` يدوياً رُفضت من GitHub بـHTTP 403 (`Resource not accessible by integration`). لذلك لم يُجرَ اختبار تثبيت/فتح التطبيق على محاكي؛ النشر وفحوص الحزمة والتوقيع في CI لا تعوّض ذلك.
- **اتصالات حية:** لم يُختبر GitHub OAuth/App بحساب مستخدم، ولا Playit Agent بمفتاح فعلي أو Tunnel متصل، ولا خادم Minecraft/Bedrock حقيقي، ولا استعادة Release على خادم حي. الاختبارات الوهمية لا تثبت هذه الاتصالات.
- **توقيع إنتاج:** يلزم أن يجهز مالك المستودع أسرار keystore الإنتاجية المناسبة قبل إصدار APK موقّع إنتاجياً. لم أقرأ أو أعدل أسراراً.
- **إصدار المستخدم:** الرابط أعلاه لإصدار prerelease debug-signed موثق، وليس توقيع متجر/إنتاج. راجع تحذير التوقيع قبل التثبيت فوق نسخة موجودة.
