# إصلاح وتشخيص Playit.gg — 2026-10-18

## ما تغيّر

- فصل حفظ `PLAYIT_SECRET_KEY` في GitHub Actions Secrets عن فحص الاتصال الحي. لا يمنع فشل/غياب فحص Playit حفظ السر، ونجاح الحفظ لا يُعرض كاتصال Agent.
- يشغّل runner ثنائي Playit الرسمي Linux AMD64 `playitd` الإصدار `v1.0.10` بعد التحقق من SHA-256:
  `2df7d9f10227ab312b1ad341853db4e8a8243df5cfcdbae58713a4271711c339`.
- يبدأ Agent مرة واحدة في كل دورة، مع `--secret-path <ملف مؤقت>` و`--platform-docker`. يُمرّر أيضاً `--socket-path <المجلد المؤقت>/playit.sock` لأن Runner قد لا يملك مجلد IPC الافتراضي لـPlayit؛ المجلد نفسه خاص بصلاحية `0700`. ملف السر وإعداد طلب API بصلاحية `0600`، وتُحذف الملفات والمقبس المؤقت عند انتهاء Runner. لا يُمرّر السر في argv أو يُترك في بيئة العمليات؛ يُستخدم حجب GitHub Actions وتنقيح سجل Agent قبل نشره.
- لا يُسجّل `Agent connected` إلا عند قراءة علامة الاتصال الرسمية `playit connected; tunnels loaded` من سجل daemon. بقاء PID وحده لا يثبت الاتصال.
- لا ينشئ التطبيق أو runner أي Tunnel. يقرأ runner `rundata` بعد تأكيد Agent، ويقبل فقط Tunnel متوافقاً مع الإصدار/النقل، والعنوان المبلغ عنه من Playit فقط.
- يجري فحص Minecraft محلياً وخارجياً ببروتوكول اللعبة: Java Server List Ping/TCP، والمنفذ المحلي الافتراضي `25565`؛ Bedrock RakNet/UDP والمنفذ `19132`. TCP connect وحده لا ينتج `Connection ready`.

## الحالات المعروضة

| الحالة | معناها |
|---|---|
| `Secret saved` | اسم السر موجود في المستودع، أو تلقى Workflow القيمة؛ لا يثبت تشغيل Agent. |
| `Agent starting` | daemon يعمل لكن لم تظهر علامة الاتصال الرسمية بعد؛ يمكنه مواصلة المحاولة. |
| `Agent connected` | سجل daemon أكد `playit connected; tunnels loaded`. |
| `Agent failed` | فشل تنزيل/تحقق/تشغيل، انتهت العملية، رُفض المفتاح، أو حد الحساب؛ يظهر تشخيص منقح. |
| `Tunnel not created` | rundata لا يحتوي Tunnel مطابقاً؛ الإنشاء يدوي من لوحة Playit. |
| `Tunnel type unsupported` | لا يطابق نوع/نقل Tunnel إصدار اللعبة، ولا يُحوّل إلى بديل تلقائياً. |
| `Tunnel address unavailable` | Tunnel مطابق موجود لكن Playit لم يخصص عنواناً بعد. |
| `Server port not listening` | لم ينجح فحص بروتوكول Minecraft على المنفذ المحلي. |
| `Connection ready` | نجح فحص Minecraft المحلي، ونجح ping بروتوكول اللعبة على عنوان Playit الفعلي. |

تعرض `nova-craft/status.json` حقول Agent والسر والمنفذ والوجهة والسجل المنقح بصورة مستقلة. سجل Agent محدود بآخر 6000 بايت، وتُنقح قيمة السر قبل النشر.

## الخطوات اليدوية المطلوبة

1. أنشئ Agent في Playit وانسخ `SECRET_KEY` إلى NOVA CRAFT؛ لا ترسله في المحادثة.
2. احفظ السر في المستودع ثم ابدأ Workflow للسيرفر. إذا بدأ Workflow قبل الحفظ، ابدأ دورة جديدة كي تتلقى قيمة السر.
3. إذا كان السيرفر موجوداً قبل هذا الإصلاح، افتح **إعدادات السيرفر → تحديث المشغّل** بعد توقف كل Workflows. يتحقق التطبيق من التشغيلات النشطة، ثم يحدّث ملفات workflow/helpers فقط؛ لا يكتب العالم أو خصائص اللعبة أو GitHub Secret.
4. انتظر حالة `Agent connected`.
5. من لوحة Playit أنشئ Tunnel بنفسك مرة واحدة، واختر Agent المتصل، ونوع Minecraft Java/TCP ووجهة `127.0.0.1:25565`. لا تُنشئ Tunnel قبل أن تسمح لوحة Playit بذلك.
6. إذا كان هناك أكثر من Tunnel متوافق، اختره يدوياً في NOVA CRAFT. انتظر `Connection ready` بعد نجاح فحص الطرفين.
7. إذا لم يُرجع Agent API عنواناً، أدخل `host:port` معروفاً يدوياً في Network settings للاختبار المباشر من التطبيق. هذا لا يغيّر بيانات Tunnel التي يراها runner ولا يثبت اتصال Agent؛ حالة runner لا تصبح `Connection ready` إلا بعد عنوان Playit المبلغ عنه وفحص بروتوكول ناجح.

## الحالة الحية التي أبلغ عنها المستخدم

في 2026-10-18 فُحصت بيانات الحالة المنقحة من مستودع المستخدم `abiedadam0077/Minecraft-server-1-`، تشغيل GitHub Actions رقم `39171261156`. أظهر `serverPortStatus=listening` و`playitSecretStatus=saved`، لكن Agent خرج بالرمز `1` قبل الاتصال، ولم تُقرأ بيانات Tunnel. ذيل سجل Agent المنقح يذكر: `playitd error: IPC error: Failed to bind to socket: No such file or directory (os error 2)`.

السبب هو فشل إنشاء مقبس IPC المحلي في مساره الافتراضي على Runner، وليس دليلاً على أن المفتاح مرفوض أو أن على المستخدم إنشاء Tunnel آخر. عُدّل القالب لتمرير `--socket-path` داخل مجلد التشغيل المؤقت الخاص (0700). لا يُعد ذلك اختباراً ناجحاً للاتصال بعد التعديل؛ يجب تحديث Runner في مستودع السيرفر بعد انتهاء التشغيل النشط، ثم التحقق من دورة جديدة قبل القول إن Agent/Tunnel اتصلا فعلياً. لم تُقرأ أو تُطلب قيمة السر.

## التحقق والقيود

- يختبر `playit_runner_integration_test.dart` أن socket path داخل مجلد مؤقت خاص، وأن خطأ bind يُعرّف تشخيصياً مع حفظ رمز خروج Agent.
- نجح CI الجديد [`39172015256`](https://github.com/abiedadam0077/NOVA-CRAFT/actions/runs/39172015256)، commit `a9a8cd31260a51f4d11c5344d2e526775a7ddeeb`: اجتاز `flutter analyze` و`flutter test` وبناء APK، والتحقق من `aapt` و`apksigner` و`zipalign` وSHA-256، ثم أعاد تنزيل الأصول المنشورة وفحص checksums.
- جرى تحليل تشغيل المستخدم المباشر عبر `status.json` المنقح فقط؛ لم تُقرأ Secrets ولم يُستخدم أي مفتاح في بيئة التطوير.
- لم يتوفر Flutter/Dart محلياً. جُرّب `dart format --output=none --set-exit-if-changed lib test` في CI منفصل؛ أبلغ عن 60 ملفاً من 61 تحتاج تنسيقاً، بينها ملفات كثيرة غير مرتبطة بالتعديل. لم أطبّق تنسيقاً شاملاً قد ينتج عنه diff واسع غير متعلق بالمهمة؛ لذلك التنسيق الآلي غير نظيف حالياً.
- لم يُختبر اتصال Playit/Minecraft بعد تحديث مقبس IPC؛ يلزم إنهاء التشغيل النشط بأمان، وتحديث Runner، ثم بدء دورة جديدة والتحقق من الاتصال. لا تنشئ Tunnel جديداً ولا تغيّر نوعه استناداً إلى فشل Agent وحده.
- لم يُشغّل Android emulator/device smoke لهذا البناء؛ بناء APK والتحقق من توقيعه لا يعادلان اختبار تشغيل على جهاز.

## APK الحالي المبني من الإصلاح

- الإصدار `1.0.0`، الحزمة `io.github.abiedadam0077.novacraft`، وضع release، لكنه **موقّع بمفتاح debug** لا بمفتاح إنتاج. تحقق `apksigner` من v1/JAR وv2 وv3؛ لا يمكن استخدامه كتحديث فوق نسخة موقعة بمفتاح مختلف.
- ARM64 (موصى به لمعظم هواتف Android): [تنزيل APK مباشر](https://github.com/abiedadam0077/NOVA-CRAFT/releases/download/flutter-apk-39172015256-1/NOVA-CRAFT-1.0.0-arm64-debugsigned.apk) — SHA-256: `fead9580c0825a8a5bfddbf13839b11cce1ec468467593524897306af0e9fcf7`.
- Universal: [تنزيل APK مباشر](https://github.com/abiedadam0077/NOVA-CRAFT/releases/download/flutter-apk-39172015256-1/NOVA-CRAFT-1.0.0-release-debugsigned.apk) — SHA-256: `9dba6e5b58b2e1040b34e767b1008af96ade55f4b713384928845c55cccbb126`.
- [قائمة SHA-256 المنشورة](https://github.com/abiedadam0077/NOVA-CRAFT/releases/download/flutter-apk-39172015256-1/SHA256SUMS.txt)؛ أكّد CI صحة التنزيل ومطابقة البصمات بعد النشر.
