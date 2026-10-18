# NOVA CRAFT — تقرير إعادة البناء والتحقق (تحديث قبل CI)

**تاريخ الحالة:** 2026-10-18
**الفرع:** `arena/9027d464-nova-craft`
**مرجع التنفيذ:** `NOVA_CRAFT_MASTER_IMPLEMENTATION_BRIEF.md` من مستودع GitHub؛ SHA-1: `5093818629d00df7f041410f002b6bd1cf5ec0ee`.
**التقرير:** هذه نسخة حالة دقيقة قبل تشغيل CI على التعديلات الحالية؛ سيُستبدل قسم APK بنتيجة CI ورابط/بصمة تنزيل عند توفرهما، ولن يُعرض أي APK غير مبني على أنه إصدار جديد.

## الخلاصة الحالية

اكتمل تنفيذ معظم مسارات التطبيق والـrunner المطلوبة داخل المستودع، مع الحفاظ على Flutter/Dart والميزات القائمة. أُصلح كذلك تقرير README القديم الذي كان يصف تدفق Claim آلياً وعنوان Playit/دورة تشغيل وAPK قديمة على نحو لا يطابق التنفيذ الحالي. شُغّل CI (`39110623631`) ووصل إلى `flutter analyze`، لكنه فشل بسبب استيراد واجهة ناقص وأخطاء interpolation في عقود الاختبار؛ أُصلحت، ثم نجح التحليل في run `39116457825`. شغّل هذا الـrun الاختبارات ومرّ معظمها، لكنه كشف توقعين قديمين في عقد الاختبار لا يطابقان اختيار backup الموثّق الجديد؛ صُحّحا في التغييرات الحالية، وجارٍ إعادة تشغيل CI. لم تصل المحاولات إلى بناء APK بعد، ولا يوجد APK جديد موثّق. Flutter/Dart وAndroid SDK و`apksigner` غير مثبتة محلياً.

## التنفيذ

- **التدقيق:** سجل الحالة السابقة والفجوات في [`PHASE-A-AUDIT-AR.md`](PHASE-A-AUDIT-AR.md)، بعد قراءة Master Brief ومراجعة GitHub Actions والكود.
- **الإعداد وGitHub:** أُضيف اختيار مستودع يملكه التطبيق ويملك صلاحية الكتابة إليه قبل شاشة Playit، ومعالجة إنشاء مستودع وتثبيت GitHub App، والتحقق من كتابة GitHub Secret قبل اعتبارها محفوظة. أضيفت قراءة صفحات GitHub API المتعددة. تُزال مفاتيح Playit المحلية عند تسجيل الخروج العادي لمنع نقل السر بين حسابين.
- **Playit:** أُزيلت مسارات Claim/إنشاء Tunnel من التطبيق. المستخدم ينشئ Tunnel يدوياً مرة واحدة؛ يتم فحص Agent عبر واجهة Playit الرسمية، واختيار Tunnel عند الالتباس، ثم يقرأ runner العنوان الحقيقي من Agent API ويعيد الفحص إذا لم يخصص العنوان بعد. أُضيف تخطي موثق لا يمنع إنشاء السيرفر، وعنوان يدوي موثّق، ولا تُعرض حالة اتصال ناجحة إلا بعد حالة تشغيل حقيقية وفحص بروتوكول اللعبة.
- **الخادم وActions:** حدّ دورة التشغيل إلى 18,000 ثانية (خمس ساعات) ضمن مهلة GitHub Actions البالغة 360 دقيقة، مع الإيقاف/إعادة التشغيل المصرح بهما، واستمرار الدورة فقط عند تفعيلها. تُفحص مسارات `dataPath` النسبية الآمنة، والجذور المحمية، والروابط الرمزية قبل cache restore وفي runner.
- **Backup/Restore:** ينتظر runner إقرار حفظ Java/Bedrock، وينشئ ZIP مؤقتاً، ويرفض الأرشيف الأكبر من 2 GiB، ثم يختبر ZIP وSHA-256 محلياً وبعد تنزيله من Release. لا يبدأ الاحتفاظ إلا بعد التحقق؛ الاختيار/الحذف الآليان يقتصران على Releases المعلّمة والمكتملة التابعة لهذا السيرفر. الاستعادة تتحقق من ملكية tag وSHA وCRC وقيود الحجم والمسار وتدعم التراجع عند الفشل. شاشة النسخ تعرض Releases الخاصة بهذا السيرفر التي تحتوي ZIP وchecksum، وتفتح أصل `world-backup.zip` الصحيح للتنزيل.
- **الواجهة والأمان:** عُدّلت حالات العنوان/حالة النفق لتفصل بين العنوان المبلّغ من Playit والعنوان اليدوي، وعُرضت واجهة اختيار Tunnel دون تخمين بين أنفاق متعددة. أُضيف تعطيل أوامر الكونسول ورفض أوامر `nova:` المحجوزة، وفحص محارف التحكم والأوامر الخطرة. أُضيفت إعدادات الاحتفاظ بالنسخ.
- **الترجمة:** العربية والإنجليزية متطابقتان في مفاتيح الترجمة، مع RTL/LTR.
- **CI والتوثيق:** حُدّثت مسارات Flutter/Android smoke القديمة وحُذف workflow قديم ينشئ التزامات/بيانات غير لازمة. حُدّث README. لا يُعد تعديل ملفات Workflow بديلاً عن تشغيلها فعلياً.

## الملفات المعدّلة

- **التوثيق:** `README.md`, `docs/PHASE-A-AUDIT-AR.md`, `docs/REBUILD_REPORT_FINAL.md`.
- **GitHub Actions:** `.github/workflows/flutter.yml`, `.github/workflows/android-smoke.yml`; حذف `.github/workflows/post_release.yml` و`.github/workflows/test_api.yml`.
- **التطبيق وواجهات البيانات:** `lib/app.dart`, `lib/core/github_api.dart`, `lib/core/models.dart`, `lib/core/playit_api.dart`, `lib/core/provisioner.dart`, `lib/core/strings.dart`, `lib/core/validation.dart`, `lib/core/workflow_templates.dart`, `lib/state/app_state.dart`.
- **الشاشات:** `lib/features/backups/backups_screen.dart`, `lib/features/console/console_screen.dart`, `lib/features/network/network_screen.dart`, `lib/features/onboarding/playit_setup_screen.dart`, `lib/features/servers/create_server_screen.dart`, `lib/features/servers/repository_selection_screen.dart`, `lib/features/servers/server_detail_screen.dart`, `lib/features/settings/server_settings_screen.dart`.
- **الاختبارات:** `test/github_api_test.dart`, `test/models_test.dart`, `test/playit_api_test.dart`, `test/runner_contract_test.dart`, `test/scripts_contract_test.dart`, `test/validation_test.dart`.

## الفحوصات المنفّذة محلياً

| الفحص | النتيجة |
|---|---|
| `git diff --check` | نجح بلا whitespace errors. |
| محلّل `tree-sitter-dart` على ملفات Dart | نجح نحوياً؛ **ليس** بديلاً عن `dart analyze` أو compiler. |
| `bash -n` على runner المستخرج | نجح. |
| `python3 -m py_compile` على config/Playit/fileops والـhelpers المستخرجة | نجح. |
| فحص YAML لـGitHub workflows والـworkflow المولّد | نجح. |
| مفاتيح الترجمة | 765 مفتاحاً في كل لغة، بلا تكرار أو مفاتيح مفقودة بين اللغتين؛ 512 مرجعاً حرفياً في التطبيق موجود. |
| تكامل config و`dataPath` | قبل المسار المتداخل الآمن؛ رفض traversal والجذور المحمية والـsymlink وحقن مخرجات GitHub والإعدادات الرقمية المخالفة. |
| تكامل حارس مسار runner | قبل المسار الآمن؛ رفض المسارات المطلقة/المتجاوزة/المشوّهة والروابط الرمزية. |
| محاكاة محلل Playit | تحققت حالات العنوان الحقيقي المبلّغ، اختلاف الإصدار، تعدد الأنفاق، العنوان غير المخصص، وفشل API؛ لا مسار إنشاء Tunnel. **ليست اتصالاً حياً بـPlayit.** |
| محاكاة lifecycle النسخ/الاحتفاظ | أُنشئ ZIP وchecksum في mock GitHub، وأُعيد تنزيلهما والتحقق منهما ووُسم Release؛ اختير أحدث backup موثّق مكتمل، ولم يُحذف غير الموثّق أو الناقص أو العائد لسيرفر آخر. **ليست GitHub Release حقيقية.** |
| `flutter analyze` و`flutter test` | نجح `flutter analyze` في CI run `39116457825`. اختبارات Flutter شغّلت 119 حالة (117 نجحت و2 فشلتا بسبب توقعين قديمين في العقود)؛ أُصلحت التوقعات، وينتظر التحقق بعد إعادة التشغيل. لم يُبنَ APK بعد. |

## APK والتوقيع والتنزيل

- **لا يوجد APK جديد موثّق في هذه الحالة السابقة لتشغيل CI.** لا يوجد رابط APK جديد أو SHA-256 جديد يمكن تقديمه الآن.
- `android/app/key.properties` وkeystore إنتاجي غير موجودين في شجرة العمل. لا يمكن فحص الأسرار الحساسة عبر اتصال GitHub المتاح؛ لذلك ستحدد نتيجة workflow ما إذا كان البناء يستخدم توقيعاً مُعداً في CI أم توقيع debug.
- APK سابق في المستودع SHA-256 له `9546392f57ed5bbd694e074cff6988abbf0f5d53d1da892fd2978e7e579b6d1d`، لكن توقيعه لم يُتحقق محلياً ولا يُقدّم كإصدار جديد.
- بعد اكتمال CI سيُضاف هنا رابط تنزيل إصدار منشور، واسم/نوع التوقيع، ونتيجة `apksigner`، وSHA-256 الذي يُعاد فحصه من الـasset المنشور. لن تُقدّم نسخة debug-signed على أنها إصدار production.

## القيود والاختبارات الخارجية المتبقية

لم يُختبر OAuth/GitHub App فعلياً بحساب مستخدم، أو Playit Agent بمفتاح حقيقي، أو Tunnel متصل، أو خادم Minecraft/Bedrock حي، أو تنزيل/استعادة Release حقيقي. محاكاة الـrunner لا تثبت هذه الاتصالات. اختبار Android smoke ليس تلقائياً؛ يلزم تشغيله على Tag APK بعد نجاح بناء CI. هذه القيود لا تُخفى ولا تُسجل كنجاح.
