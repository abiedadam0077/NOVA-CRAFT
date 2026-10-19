# NOVA CRAFT — تقرير المرحلة A: التدقيق التقني

**تاريخ التدقيق:** 2026-10-18 UTC
**الفرع:** `arena/9027d464-nova-craft`
**المرجع الأساسي:** [`NOVA_CRAFT_MASTER_IMPLEMENTATION_BRIEF.md`](https://github.com/abiedadam0077/NOVA-CRAFT/blob/main/NOVA_CRAFT_MASTER_IMPLEMENTATION_BRIEF.md)، قُرئ كاملاً من GitHub؛ SHA للملف `5093818629d00df7f041410f002b6bd1cf5ec0ee` (16,955 بايت). الملف غير موجود في نسخة الفرع المحلية، لذلك جرى جلب النص من `main` قبل مراجعة الكود.
**حالة المستودع عند بدء التدقيق:** نظيف؛ لا تغييرات سابقة.

## الملخص التنفيذي

المشروع الحالي تطبيق Android فعلي مبني بـ **Flutter/Dart وMaterial 3**، وليس Kotlin/Compose. البنية الحالية تشمل تدفق GitHub Device Flow، اختيار/إنشاء مستودع داخل معالج السيرفر، تخزيناً مشفراً على Android، كتابة GitHub Actions Secrets، سير عمل Minecraft Java/Bedrock، Playit Agent، شاشات حقيقية لملفات السيرفر والكونسول والمودات والنسخ الاحتياطية والشبكة، واختبارات وحدات/عقود. وبما أن المرجع الأساسي يطلب الحفاظ على البنية القائمة، فلا توجد حاجة لإعادة كتابة التطبيق بتقنية أخرى.

توجد فجوات وظيفية مهمة تمنع اعتبار المتطلبات مكتملة، خصوصاً ترتيب الإعداد الأول، إلزام حفظ `PLAYIT_SECRET_KEY` في المستودع، إنشاء الأنفاق آلياً، فحص UDP لـBedrock، سلامة النسخ والاستعادة، وحدّ دورة الخمس ساعات. لم تُجرَ تعديلات برمجية قبل إتمام هذا التدقيق.

## الحالة الحالية حسب المجال

| المجال | الموجود فعلياً | الفجوة المؤثرة في القبول |
|---|---|---|
| GitHub/Auth | Device Flow، حفظ الرموز في `flutter_secure_storage`، واجهات REST، تشفير Secret بطريقة sealed-box، والتحقق من ظهور اسم السر بعد الكتابة | التصفح لا يتبع صفحات GitHub؛ فحص `permissions.push` غير مطبق في اختيار المستودع؛ مسار الإعداد يختار المستودع بعد خطوة Playit |
| إعداد Playit | حقل مخفي/إظهار، التحقق من مفتاح Agent عبر `rundata`، Agent Secret مشفر محلياً، وواجهة لعرض بيانات النفق | شاشة البدء تحفظ السر محلياً فقط، ولا تكتبه إلى GitHub Secret قبل المتابعة؛ التخطي مسموح؛ runner وعميل Dart يحاولان إنشاء Tunnel تلقائياً؛ لا اختيار Tunnel عند وجود أكثر من واحد |
| Java/Bedrock | مصادر إصدار حية لـMojang/Paper/Purpur/Fabric، تنزيلات Java تتحقق من checksums، Bedrock يضبط `transport=raknet`، وفحص RakNet من الهاتف | runner يفحص العنوان الخارجي عبر TCP حتى لسيرفر Bedrock؛ منافذ الخادم ثابتة في الإعدادات؛ تنزيل Bedrock بلا checksum؛ حالة النفق في runner ليست اختبار UDP فعلياً |
| التشغيل وإعادة التشغيل | `workflow_dispatch`، `concurrency` لكل سيرفر، قائمة أوامر، heartbeat/log، إيقاف دوري و`autoRestart` عبر dispatch | `timeout-minutes: 330` (5.5 ساعات) مقابل هدف أقصى خمس ساعات؛ دورة التشغيل الداخلية 285 دقيقة ولا تحسب وقت الإعداد/النسخ بدقة؛ لا يوجد تراجع زمني/مقياس دوري قابل للعرض؛ فرع الفشل لا يعيد المحاولة، لكن سلسلة النجاح غير محدودة |
| Backup/Restore | GitHub Releases للتخزين الدائم، Actions cache للاستعادة السريعة، SHA-256 محلي، شاشة سجل/تنزيل/استعادة | الضغط يجري قبل خروج عملية Minecraft؛ لا اختبار فعلي للـZIP ولا تحقق من التنزيل بعد رفعه؛ checksum مفقود/غير مطابق يسجل تحذيراً ثم قد يستمر الاستخراج؛ لا سياسة احتفاظ آمنة موثقة؛ شاشة التطبيق تعدّ أي Release تقريباً جاهزاً |
| الملفات/Mods/Console | ملفات من بيانات السيرفر عبر manifest وعمليات runner، حماية مسارات في Python، Modrinth، سجل Console وأوامر | وظائف الملفات مبنية على GitHub Contents/قائمة أوامر وليست اتصالاً مباشراً؛ snapshot محدود؛ إعداد `allowCommands` ظاهر لكنه لا يمنع إرسال الأوامر؛ بعض حالات العنوان اليدوي لا تختبر القيمة التي يكتبها المستخدم |
| الواجهة | خمس وجهات رئيسية، العربية/RTL والإنجليزية/LTR، خطوط وثيمات، حالات تحميل/فراغ، إعدادات السيرفر | توجد حالات/عناصر تحتاج ربطاً صحيحاً بالبيانات الحقيقية؛ CPU/RAM غير منشورين فعلياً من runner (فتظهر قيمة غير متاحة)؛ لم يُختبر العرض على جهاز Android في هذه البيئة |

## تدقيق Playit الرسمي

تحققت من مستودع Playit الرسمي وإصدار `v1.0.10` المنشور في 2026-06-08. README الرسمي يوضح استخدام `SECRET_KEY` للوكيل؛ عميل API الرسمي يرسل `Authorization: Agent-Key …` ويعرّف `POST /v1/agents/rundata` وحقول `tunnels`, `display_address`, `port_type`, و`disabled_reason`. لذلك قراءة عنوان النفق من رد الوكيل ممكنة عبر واجهة موجودة في مصدر Playit الرسمي، من دون اختراع عنوان. أصلاً توجد بصمة أصلية لثنائي Linux AMD64 في GitHub Release: `sha256:2df7d9f10227ab312b1ad341853db4e8a8243df5cfcdbae58713a4271711c339`؛ runner الحالي ينزّل الثنائي بالنسخة المثبتة لكنه لا يتحقق من هذه البصمة.

المخالفة الواضحة للمرجع: المستخدم طلب إنشاء Tunnel يدوياً مرة واحدة، بينما `lib/core/playit_api.dart` و`lib/core/workflow_templates.dart` يحاولان إنشاؤه تلقائياً. كما أن فحص runner الحالي يختبر TCP دائماً، فلا يثبت اتصال Bedrock UDP.

## GitHub Actions والبناء الحالي

- `.github/workflows/flutter.yml` هو المسار الأفضل حالياً: Flutter 3.35.7 مثبت، تحليل واختبارات، بناء APK، `aapt` و`apksigner`، checksums، رفع Release/Artifact، ثم إعادة تنزيل الأصول وفحص SHA-256. لكن قائمة الفروع لا تشمل فرع هذه الجلسة بعد.
- `.github/workflows/post_release.yml` يعمل عند كل `push`، ويعيد بناء APK بإصدار Flutter غير مثبت ثم يحاول إضافة APK كبير إلى Git والدفع للفرع؛ لا يحقق التوقيع/الـchecksum بنفس مسار التسليم الموثق. هذا مسار قديم ومكرر ويجب إيقافه لصالح `flutter.yml`.
- `.github/workflows/test_api.yml` يكتب استجابات API مولدة إلى Git ويدفعها تلقائياً؛ آخر تشغيل ظاهر لهذا المسار على الفرع السابق فشل. لا حاجة لتشغيله مع كل تعديل تطبيق.
- `.github/workflows/android-smoke.yml` يملك tag افتراضياً قديماً، لذا لا يختبر تلقائياً أحدث APK.
- لم يظهر تشغيل Actions للـcommit الحالي `e748556efc33d8d6d8d82db400867be2f727d18c`، ولا يوجد `flutter` أو JDK أو `apksigner` مثبت محلياً. لذلك لم أعتبر أي اختبار محلي ناجحاً.
- ملف `nova-craft-final.apk` الموجود مسبقاً حجمه نحو 62 MiB؛ SHA-256 المحسوب له `9546392f57ed5bbd694e074cff6988abbf0f5d53d1da892fd2978e7e579b6d1d` ويطابق `final_sha256.txt`. `SHA256SUMS.txt` يشير إلى APKs غير موجودة في شجرة العمل. توجد ملفات توقيع JAR داخل APK، لكن لا يمكن إثبات سلامة توقيعه الكامل دون `apksigner`؛ لن أدّعي أنه APK متحقق منه.

## الملفات التي ستحتاج إلى تعديل في المراحل التالية

- **GitHub/Auth والإعداد الأول:** `lib/core/github_api.dart`, `lib/core/secure_store.dart`, `lib/state/app_state.dart`, `lib/app.dart`, `lib/features/servers/create_server_screen.dart`، وإضافة شاشة اختيار المستودع.
- **Playit/الشبكة:** `lib/core/playit_api.dart`, `lib/core/models.dart`, `lib/core/provisioner.dart`, `lib/core/workflow_templates.dart`, `lib/features/onboarding/playit_setup_screen.dart`, `lib/features/network/network_screen.dart`.
- **النسخ/إعادة التشغيل/الأوامر:** `lib/core/workflow_templates.dart`, `lib/core/provisioner.dart`, `lib/features/backups/backups_screen.dart`, `lib/features/console/console_screen.dart`, `lib/features/settings/server_settings_screen.dart`.
- **الاختبارات/التسليم:** `test/github_api_test.dart`, `test/runner_contract_test.dart`, `test/scripts_contract_test.dart`, `test/models_test.dart`, `test/strings_test.dart`، وملفات workflows الأربعة تحت `.github/workflows/`، ثم `README.md` عند تثبيت نتائج البناء الفعلية.

## حدود لا يمكن إثباتها قبل إعداد خارجي

لا يوجد في المستودع أو بيئة العمل مفتاح Playit خاص بالمستخدم، أو جلسة Device Flow صادرة من التطبيق، أو جهاز Android فعلي. أستطيع اختبار العقود والسكربتات والبناء والتوقيع في CI، لكن اتصال Tunnel حيّاً أو إنشاء سيرفر Minecraft فعلياً/انضمام لاعب يحتاج اعتماد المستخدم واختباراً من شبكة خارجية. سيُعرض ذلك كقيد، لا كنتيجة نجاح.
