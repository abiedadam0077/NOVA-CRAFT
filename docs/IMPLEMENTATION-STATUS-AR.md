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
- توقيع Release: بانتظار وضع سرّي التوقيع في GitHub Secrets من المالك (المفتاح وُلّد مرة واحدة PKCS12 ولا يُعاد توليده).

## حدود معروفة بصراحة
- حد Job في GitHub هو 6 ساعات: التشغيل 24/7 غير مضمون، والدورات المتسلسلة قد تتوقف (queue/فشل/حصص دقائق المستودعات الخاصة).
- Bedrock على إصدارات NetherNet الحديثة يعتمد ضبط `transport=raknet` المعتمد في القالب، ويحتاج اختبار اتصال فعلياً.
- Console تحديث دوري للسجلات (Logs تُقرأ كاملة بعد اكتمال الـRun؛ أثناء التشغيل تُعرض حالة الـJobs/Steps).
