# NOVA CRAFT — حالة التنفيذ والاختبار (2026-10-17)

## تم فعلياً
- تطبيق Android أصلي: Kotlin + Jetpack Compose + Material 3، حزمة `io.github.abiedadam0077.novacraft`، بلا WebView إطلاقاً.
- مصادقة GitHub App عبر Device Flow (Client ID العام فقط في الكود؛ الرموز مشفرة بـAndroid Keystore AES-GCM)، مع فحص التثبيتات والمستودعات المسموحة فقط.
- معالج إنشاء سيرفر: Java/Bedrock، إصدارات حية من Mojang Piston Meta وPaper/Purpur/Fabric من APIs رسمية/أولية (Forge/NeoForge/Spigot غير معروضة لأنها تحتاج Installer/BuildTools غير موجود في workflow v1)، اختيار Private (افتراضي)/Public مع تنبيه، وصورة من الجهاز فقط (تُصغّر 64×64 وتُرفع server-icon.png).
- تجهيز حقيقي عبر Contents API (إعدادات + server.properties + workflow)، تشغيل/إيقاف/أوامر عبر قائمة أوامر يستهلكها الـRunner كل ~12 ثانية، Heartbeat إلى `nova-craft/status.json` كل 10 دقائق.
- Workflow الدورة: استعادة آخر Backup من Releases مع تحقق SHA-256، تنزيل السيرفر الرسمي، Playit agent مثبّت الإصدار v1.0.10 عند وجود `PLAYIT_SECRET_KEY`، إيقاف منظّم + نسخة جديدة + إطلاق دورة تالية اختيارياً، `concurrency` يمنع ازدواج نفس السيرفر، سقف داخلي ~4.8 ساعة داخل حد الـJob (6 ساعات).
- شاشات: Splash/Welcome/Auth/Repos داخل المعالج، Dashboard، My Servers، Server Detail (نظرة عامة/إعدادات/لاعبون/Mods-Plugins/نسخ/عوالم/Network/Actions)، Console (Polling — ليست Live)، Files (تصفح/تحرير/رفع/تنزيل/حذف مع حماية path traversal)، Account، App Settings (عربي RTL/إنجليزي، داكن/فاتح).
- Ping حقيقي من الهاتف: Java SLP عبر TCP وBedrock RakNet عبر UDP إلى عنوان Playit.

## اختبارات نفّذت فعلياً
- CI (GitHub Actions run 38996029419): `testDebugUnitTest` ✅ (7 اختبارات منطق: أسماء مستودعات، path traversal، أوامر خطرة، clamps، config JSON، قالب الـworkflow، خصائص Java/Bedrock) و`assembleDebug` ✅ وتم رفع `nova-craft-debug` (18.8 MB).
- Device Flow: اختبار HTTP فعلي ضد GitHub بالـClient ID المعتمد ✅ (انظر تقرير المرحلة الأولى §10).
- صلاحيات الـGitHub App مقروءة من الـAPI ✅ (actions/contents/workflows/secrets/repository_creation = write، events فارغة).

## لم يُختبر بعد (يحتاج حساب/جهاز فعلي)
- تسجيل الدخول من جهاز Android وإنشاء مستودع اختبار خاص+عام من التطبيق (يحتاج User Token من Device Flow على الجهاز).
- دورة سيرفر حية كاملة (بدء Java/Bedrock + Playit tunnel + انضمام لاعب) — تحتاج حساب Playit ومفتاح Agent من المستخدم.
- توقيع Release بالمفتاح الأصلي غير متاح: سجلّ CI السابق أكد غياب `NOVA_KEYSTORE_BASE64`. لم نولّد مفتاح Release بديلاً؛ النسخة المسلّمة Debug موقّعة ومتحقق من توقيعها.

## حدود معروفة بصراحة
- حد Job في GitHub هو 6 ساعات: التشغيل 24/7 غير مضمون، والدورات المتسلسلة قد تتوقف (queue/فشل/حصص دقائق المستودعات الخاصة).
- Bedrock على إصدارات NetherNet الحديثة يعتمد ضبط `transport=raknet` المعتمد في القالب، ويحتاج اختبار اتصال فعلياً.
- Console تحديث دوري للسجلات (Logs تُقرأ كاملة بعد اكتمال الـRun؛ أثناء التشغيل تُعرض حالة الـJobs/Steps).


## تحديث التسليم الفعلي — 2026-10-17

- **ملف APK منشور فعلياً:** [تحميل مباشر — NOVA-CRAFT-1.0.0-debug.apk](https://github.com/abiedadam0077/NOVA-CRAFT/releases/download/tested-apk-38998610684/NOVA-CRAFT-1.0.0-debug.apk) — الحجم 21,041,386 بايت، Android 8.0+.
- [صفحة الإصدار والتقارير](https://github.com/abiedadam0077/NOVA-CRAFT/releases/tag/tested-apk-38998610684) عامة وليست Draft، وPre-release مصرح بها؛ لا يتعامل المستخدم مع ملفات مفاتيح يدوياً.
- كود التطبيق في الملف مبني من `de05bdf615b72ed159db903c4767a2fee5f268b8`.
- **7 اختبارات وحدة + lint + بناء APK:** ناجحة ضمن [تشغيل البناء 38998610684](https://github.com/abiedadam0077/NOVA-CRAFT/actions/runs/38998610684). فشل التشغيل الإجمالي وقتها كان في النشر فقط، وليس في البناء أو الاختبارات.
- **3 اختبارات Android 35 x86_64:** شاشة الترحيب والانتقال إلى المصادقة وإعادة إنشاء Activity، تشفير Android Keystore، وتحميل مكتبة التشفير الأصلية واستدعاؤها — نجحت كلها.
- ثُبّت **نفس APK المرفق** بعد اختبارات instrumentation وفتح بنجاح؛ تم التحقق من استمرار العملية وظهور واجهة الترحيب وعدم تسجيل انهيار للتطبيق. لقطة الشاشة ونتائج التثبيت والفتح مرفقة بالإصدار.
- `apksigner verify --verbose --print-certs` نجح؛ التقارير وSHA-256 منشورة. النسخة **Debug وليست Release بالمفتاح الأصلي**.
- تم إصلاح إلغاء انتظار Device Flow ومعالجة أخطاء الشبكة واحتساب `slow_down`، وإزالة Coroutine مستقلة عن دورة حياة الشاشة.
- فشل النشر الأول سببه HTTP 400 عند إرفاق ملف crash log فارغ. تم استرجاع الـartifact نفسه، والتحقق من مصدره والاختبارات والتوقيع والـchecksum، ثم نشر الملفات غير الفارغة في [تشغيل نشر ناجح 38999092111](https://github.com/abiedadam0077/NOVA-CRAFT/actions/runs/38999092111).
- تشغيل النشر الناجح **أعاد تحميل APK من GitHub Releases** وطابق checksum بعد النشر. SHA-256 الفعلي:
  `2fce831dd2bc0e12d6a3ecceb3846b1d29cae24e242813582c089c08adc02a5d`.
- لا تزال تجارب الهاتف الحقيقي/ARM، تسجيل الدخول المفوّض وإنشاء السيرفر والاتصال باللعبة ودورات النسخ تحتاج اختباراً شاملاً. **تسليم APK مجرّب على المحاكي لا يعني أن جميع متطلبات المنتج اكتملت.**
