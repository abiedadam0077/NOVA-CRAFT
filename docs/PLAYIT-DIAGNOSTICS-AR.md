# إصلاح وتشخيص Playit.gg — 2026-10-18

## ما تغيّر

- فصل حفظ `PLAYIT_SECRET_KEY` في GitHub Actions Secrets عن فحص الاتصال الحي. لا يمنع فشل/غياب فحص Playit حفظ السر، ونجاح الحفظ لا يُعرض كاتصال Agent.
- يشغّل runner ثنائي Playit الرسمي Linux AMD64 `playitd` الإصدار `v1.0.10` بعد التحقق من SHA-256:
  `2df7d9f10227ab312b1ad341853db4e8a8243df5cfcdbae58713a4271711c339`.
- يبدأ Agent مرة واحدة في كل دورة، مع `--secret-path <ملف مؤقت>` و`--platform-docker`. الملف وملف إعداد طلب API بصلاحية `0600` داخل مجلد مؤقت `0700`، ويُحذفان عند انتهاء runner. لا يُمرّر السر في argv أو يُترك في بيئة العمليات؛ يُستخدم حجب GitHub Actions وتنقيح سجل Agent قبل نشره.
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
3. انتظر حالة `Agent connected`.
4. من لوحة Playit أنشئ Tunnel بنفسك مرة واحدة، واختر Agent المتصل، ونوع Minecraft Java/TCP ووجهة `127.0.0.1:25565`. لا تُنشئ Tunnel قبل أن تسمح لوحة Playit بذلك.
5. إذا كان هناك أكثر من Tunnel متوافق، اختره يدوياً في NOVA CRAFT. انتظر `Connection ready` بعد نجاح فحص الطرفين.
6. إذا لم يُرجع Agent API عنواناً، أدخل `host:port` معروفاً يدوياً في Network settings للاختبار المباشر من التطبيق. هذا لا يغيّر بيانات Tunnel التي يراها runner ولا يثبت اتصال Agent؛ حالة runner لا تصبح `Connection ready` إلا بعد عنوان Playit المبلغ عنه وفحص بروتوكول ناجح.

## التحقق والقيود

- فُحص قالب runner محلياً بـ`bash -n`، ومساعد Playit بـ`python3 -m py_compile`.
- اختُبر مساعد rundata بمدخلات سلبية/إيجابية: لا Tunnel، نوع/نقل غير متوافق، عنوان غير مخصص، Tunnel Java TCP مع origin حقيقي، واختيار ID غير موجود.
- اختُبر Java Server List Ping محلياً بخادم mock: ردّ Java صالح نجح، وقبول TCP مع بيانات Minecraft غير صالحة رُفض. هذا اختبار بروتوكول محلي، وليس اتصالاً خارجياً بـPlayit.
- نجح CI للبناء الحالي: [`39124166880`](https://github.com/abiedadam0077/NOVA-CRAFT/actions/runs/39124166880)، commit `3a71772a856221c8ccd1d31e6acf704e882aff9c`. اجتاز `flutter analyze` و`flutter test` وبناء APK والتحقق من package/signature/SHA-256، ثم نزّل الأصول المنشورة وأعاد مطابقة checksums بنجاح.
- لم يتوفر Flutter/Dart محلياً. جُرّب `dart format --output=none --set-exit-if-changed lib test` في CI منفصل؛ أبلغ عن 60 ملفاً من 61 تحتاج تنسيقاً، بينها ملفات كثيرة غير مرتبطة بالتعديل. لم أطبّق تنسيقاً شاملاً قد ينتج عنه diff واسع غير متعلق بالمهمة؛ لذلك التنسيق الآلي غير نظيف حالياً.
- لم يُشغّل Workflow لخادم حقيقي ولم يُتحقق من اتصال Playit/Minecraft خارجي؛ مستودع الخادم الذي يحتوي `PLAYIT_SECRET_KEY` غير محدد. يلزم تزويد `OWNER/REPO` عند الرغبة في التحقق الحي؛ لا ترسل قيمة السر.
- لم يُشغّل Android emulator/device smoke لهذا البناء؛ بناء APK والتحقق من توقيعه لا يعادلان اختبار تشغيل على جهاز.

## APK الحالي المبني من الإصلاح

- الإصدار `1.0.0`، الحزمة `io.github.abiedadam0077.novacraft`، وضع release، لكنه **موقّع بمفتاح debug** لا بمفتاح إنتاج. تحقق `apksigner` من سلامة التوقيع؛ لا يمكن استخدامه كتحديث فوق نسخة موقعة بمفتاح مختلف.
- ARM64 (موصى به لمعظم هواتف Android): [تنزيل APK مباشر](https://github.com/abiedadam0077/NOVA-CRAFT/releases/download/flutter-apk-39124166880-1/NOVA-CRAFT-1.0.0-arm64-debugsigned.apk) — SHA-256: `1bd16daeb6e1e99f24de9a980af33323edf086ddaa02a47d8172b9b52cf03d1a`.
- Universal: [تنزيل APK مباشر](https://github.com/abiedadam0077/NOVA-CRAFT/releases/download/flutter-apk-39124166880-1/NOVA-CRAFT-1.0.0-release-debugsigned.apk) — SHA-256: `100a95fe3cf9154d382084eace0664fc1b49efdfb286574121e1b62b20d8f855`.
- [قائمة SHA-256 المنشورة](https://github.com/abiedadam0077/NOVA-CRAFT/releases/download/flutter-apk-39124166880-1/SHA256SUMS.txt)؛ أكّد CI صحة التنزيل ومطابقة البصمات بعد النشر.
