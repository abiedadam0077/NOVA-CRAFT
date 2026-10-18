# NOVA CRAFT — تقرير المرحلة 0 + 1: البحث والتحقق وإعداد GitHub App

- **التاريخ:** 2026-10-17
- **الحالة:** بحث وتحقق فقط. لم يُكتب أي كود تطبيق، ولم تُنشأ أي ملفات Workflow أو APK في هذه المرحلة، التزاماً بتعليمات المستخدم والملف المرجعي.
- **المستودع الحالي (موثّق فعلياً):** `abiedadam0077/NOVA-CRAFT` — عام (public)، الفرع الافتراضي `main`، الرابط: https://github.com/abiedadam0077/NOVA-CRAFT
- **بيئة الفحص:** `gh` مسجّل دخول باسم `abiedadam0077`. لا توجد Java/Android SDK مثبّتة في بيئة العمل الحالية (سيُحسم مصدر البناء في مرحلة لاحقة: تثبيت toolchain أو البناء عبر GitHub Actions — لا يؤثر على هذه المرحلة).

---

## 1) ملخص ما فُهم من المشروع

تطبيق Android أصلي (Kotlin + Jetpack Compose + Material 3 — لا WebView) باسم NOVA CRAFT لإدارة سيرفرات Minecraft Java وBedrock من الهاتف: ربط GitHub رسمي وآمن، اختيار/إنشاء مستودع لكل سيرفر، معالج إنشاء سيرفر، تشغيل دورات عبر GitHub Actions (هدف ≈5 ساعات/دورة مع نسخ احتياطي منظّم وإعادة تشغيل تلقائية)، اتصال خارجي عبر Playit.gg، وشاشات: Dashboard، My Servers، Console، Mods/Plugins، Settings، Players، Files، Worlds، Backups، Network، GitHub/Actions، Account/Security، Settings عامة — مع حالات خطأ/فراغ/انقطاع كاملة وعربية RTL + إنجليزية. خارج النطاق: AI Assistant وAFK Bot ومتجر عام.

## 2) قرار المصادقة (A) — GitHub App + Device Flow

**القرار: إنشاء GitHub App (وليس OAuth App)، واستخدام OAuth 2.0 Device Flow للحصول على User Access Token. لا يوجد Redirect URI في النسخة الأولى.**

الأسباب الموثقة:

1. GitHub نفسه يفضّل GitHub Apps على OAuth Apps لصلاحياتها الدقيقة وقصر عمر رموزها وتحكم المستخدم بالمستودعات [2](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/best-practices-for-creating-an-oauth-app).
2. تدفق Web (Authorization Code) يتطلب `client_secret` إلزامياً عند تبادل الكود برمز وصول في GitHub Apps وOAuth Apps معاً، حتى مع PKCE (GitHub أضاف PKCE في 2025 وينصح به، لكنه لا يعفي من الـsecret). وضع الـsecret داخل APK يعني أنه قابل للاستخراج، فيخالف قاعدة «لا أسرار داخل APK». ‏PKCE وحده لا يحل مشكلة غياب Backend [1](https://github.blog/changelog/2025-07-14-pkce-support-for-oauth-and-github-app-authentication/) [2](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/best-practices-for-creating-an-oauth-app).
3. Device Flow هو التدفق الوحيد الذي **لا يتطلب client secret ولا Redirect URI إطلاقاً**، وتوصي به وثائق GitHub للتطبيقات بدون واجهة ويب/الـheadless مثل أدوات CLI — وهو الأقرب لتطبيق Android بدون Backend منشور [8](https://docs.github.com/en/enterprise-cloud@latest/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-user-access-token-for-a-github-app). خطواته: `POST https://github.com/login/device/code` (بـ`client_id` فقط) ← عرض `user_code` للمستخدم ليُدخله في `https://github.com/login/device` ← Polling على `POST https://github.com/login/oauth/access_token` كل `interval` ثوانٍ (افتراضي 5) حتى النجاح أو انتهاء 15 دقيقة.
4. تنبيه أمان صريح (من وثائق GitHub نفسها): Device Flow أضعف أمام التصيّد من Authorization Code + PKCE إذا امتلك مهاجم الـClient ID، لأن لا Redirect URI يقيّده. التخفيف المعتمد في NOVA CRAFT: عرض الكود داخل التطبيق فقط، عدم قبول أي كود من روابط خارجية، تعليم المستخدم ألّا يُدخل كوداً لم يولّده التطبيق أمامه، وإمكانية الانتقال مستقبلاً إلى Web Flow + PKCE عبر Backend صغير لتبادل الكود (قرار مستقبلي، ليس في النسخة الأولى).
5. بعد التفويض، يحتاج المستخدم خطوة منفصلة: **تثبيت (Install) الـGitHub App** على حسابه واختيار المستودعات المسموحة، لأن User Token لا يصل إلا للمستودعات التي (أ) ثُبّت عليها التطبيق و(ب) يملك المستخدم صلاحية عليها معاً. سيرشد التطبيق المستخدم لرابط التثبيت الرسمي `https://github.com/apps/<APP-SLUG>/installations/new` بعد إنشاء التطبيق (يُبنى الرابط من الـslug الفعلي، لا يُخترع الآن).
6. عمر الرموز مع تفعيل انتهاء الرموز: Access Token ‏8 ساعات + Refresh Token ‏6 أشهر، والتطبيق يجدّد تلقائياً ويخزن الرموز في Android Keystore/Encrypted Storage فقط.

**بديل مرفوض للنسخة الأولى:** OAuth App كلاسيكي بصلاحيات scopes واسعة (مثل `repo`) — أضعف من ناحية أقل-الامتياز، ولا يقدّم أي ميزة هنا. **بديل مؤجل:** Web Flow + PKCE مع Custom Scheme/‏App Links — يتطلب Backend آمناً لحفظ الـClient Secret وتبادل الكود، ولا يوجد Backend منشور بعد؛ اختراع Redirect URI له الآن سيكون قيمة وهمية مخالفة لتعليمات المستخدم.

## 3) اسم الـGitHub App وAndroid Package (D)

### 3.1 الاسم — نتيجة تحقيق فعلي (وليس تخميناً)

- الاسم الحرفي `NOVA CRAFT` (slug: ‏`nova-craft`) **يُتوقع رفضه**: توجد حساب GitHub قائم باسم `Nova-Craft` منذ 2023-03-08 (ليس حساب المستخدم)، وقاعدة GitHub: اسم التطبيق يجب أن يكون فريداً ولا يساوي اسم حساب قائم إلا حساب المالك نفسه، والحد الأقصى 34 حرفاً [1](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/registering-a-github-app).
- تم فحص توفر الأسماء المرشحة عبر GitHub API بتاريخ التقرير (بحث في التطبيقات والحسابات معاً، والنتيجة 404 للطرفين — أي غير مستخدمة وقت الفحص؛ القبول النهائي يُحسم لحظة الإنشاء داخل صفحة GitHub نفسها):

| الأولوية | الاسم الذي يُكتب حرفياً في حقل GitHub App name | Slug متوقع |
|---|---|---|
| **الأساسي** | `NOVA CRAFT by abiedadam0077` | `nova-craft-by-abiedadam0077` |
| بديل 1 | `NovaCraft abiedadam0077` | `novacraft-abiedadam0077` |
| بديل 2 | `NOVA CRAFT MC abiedadam0077` | `nova-craft-mc-abiedadam0077` |

يُستخدم الاسم الأساسي، ولا يُنتقل لبديل إلا إذا رفضت صفحة الإنشاء الاسم نفسه، مع إبلاغي بالاسم الفعلي الذي قُبل.

### 3.2 Android

- **Display name:** `NOVA CRAFT`
- **applicationId / package name الثابت (ملتزم به في كل الكود اللاحق):** `io.github.abiedadam0077.novacraft`
  مبرر: معرّف فريد مضمون الارتباط بحساب GitHub المالك، بلا تصادم محتمل مع منتجات أخرى باسم NOVA CRAFT على متجر/أجهزة، ومتوافق مع اصطلاح reverse-domain. لن يتغير لاحقاً لأن تغييره يكسر التحديثات فوق النسخة المثبتة.
- لا يوجد Redirect URI مرتبط بالـpackage في النسخة الأولى (Device Flow). أي Custom Scheme مستقبلي سيُعلن قبل استخدامه، ولن يُسجّل الآن.

## 4) ورقة إعداد Create GitHub App الكاملة (B)

مسار الإنشاء: صورة الحساب ← **Settings** ← **Developer settings** ← **GitHub Apps** ← **New GitHub App** (تحت حساب المستخدم الشخصي `abiedadam0077`) [1](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/registering-a-github-app).

| # | الحقل (كما يظهر في صفحة GitHub) | القيمة التي يُدخلها المستخدم حرفياً | مؤكدة / تعتمد على نشر؟ | أين ستُستخدم في الكود لاحقاً |
|---|---|---|---|---|
| 1 | GitHub App name | `NOVA CRAFT by abiedadam0077` | مؤكدة بشرط قبول GitHub للاسم لحظة الإنشاء (انظر البدائل) | يُشتق منه الـslug لرابط التثبيت داخل التطبيق |
| 2 | Description | `Create and manage Minecraft Java and Bedrock servers from Android with GitHub Actions and Playit.gg tunnels.` | مؤكدة | تظهر للمستخدم عند التثبيت/التفويض فقط |
| 3 | Homepage URL | `https://github.com/abiedadam0077/NOVA-CRAFT` | **مؤكدة وحقيقية** (المستودع موجود وعام؛ الوثائق تجيز رابط المستودع عند غياب موقع) [1](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/registering-a-github-app) | لا تُستخدم برمجياً؛ صفحة تعريف |
| 4 | Callback URL | **يُترك فارغاً تماماً** | مؤكدة كقرار معماري | لا يوجد. Device Flow يتجاهل هذا الحقل رسمياً |
| 5 | Allow wildcard matching | **لا يوجد هذا الخيار في نموذج GitHub App الحالي** — GitHub يطابق Callback URLs تطابقاً تاماً ولا يدعم wildcards هنا | مؤكدة | غير منطبق (لا Callback أصلاً) |
| 6 | Expire user authorization tokens | **مُبقى مُفعّلاً (Selected)** — لا تُلغِ تفعيله | مؤكدة | Access token ‏8h + Refresh token ‏6mo؛ تجديد تلقائي داخل التطبيق |
| 7 | Request user authorization (OAuth) during installation | **غير مُفعّل (Unchecked)** | مؤكدة | تفعيله يفرض Web Flow + Callback + Client Secret — مرفوض في النسخة الأولى |
| 8 | Enable Device Flow | **مُفعّل (Checked)** | مؤكدة | قلب المصادقة في التطبيق: `login/device/code` + Polling |
| 9 | Setup URL (Post installation) | **يُترك فارغاً** | مؤكدة | لا توجد صفحة إعداد منشورة؛ اختراع رابط ممنوع |
| 10 | Redirect on update | **غير مُفعّل (Unchecked)** | مؤكدة | يُتجاهل تلقائياً عند غياب Setup URL |
| 11 | Webhook — Active | **غير مُفعّل (Deselect Active)** | مؤكدة كقرار للنسخة الأولى | التطبيق يستعلم (Polling) عن حالة Actions API بدل Push |
| 12 | Webhook URL | **لا تُدخل أي قيمة** (الحقل يختفي/يُعطّل بإلغاء Active) | **غير جاهز عمداً** — لا Backend منشوراً يستقبل Webhooks، وأي رابط الآن سيكون مخترعاً | — |
| 13 | Webhook Secret | **لا يُنشأ الآن** | غير منطبق في النسخة الأولى | عند تفعيل Webhooks مستقبلاً: توليد `openssl rand -hex 32` وحفظه في مخزن أسرار الـBackend + حقل GitHub فقط، أبداً في Git/APK |
| 14 | SSL verification | غير منطبق (لا Webhook URL) | — | يُفعّل Enable SSL عند أي تفعيل مستقبلي |
| 15 | Permissions | الجدول التفصيلي في §5 | مؤكدة (باستثناء ملاحظة Repository creation أدناه) | كل استدعاءات REST API في التطبيق |
| 16 | Subscribe to events | **لا شيء (قائمة فارغة)** | مؤكدة | بلا Webhook نشط لا تصل أي أحداث؛ يبقى حدث إلغاء التفويض يُكتشف عملياً عبر 401 عند أول طلب |
| 17 | Where can this GitHub App be installed? | **Only on this account** | مؤكدة للنسخة الأولى | التطبيق خاص بحساب المستخدم أثناء التطوير؛ التحويل إلى Any account قرار نشر لاحق منفصل يتطلب موافقة |

### ملاحظات دقة إلزامية

- لا تُولّد **Client Secret** ولا **Private Key (.pem)** في هذه الخطوة: Device Flow لا يحتاجهما، ولا يوجد مخزن آمن لهما بعد (وضع أيٍّ منهما في APK/المستودع محظور). إن ولّدتهما صفقةً، احفظهما في مدير كلمات مرور شخصي ولا ترسلهما في المحادثة.
- بعد إنشاء التطبيق ستحصل على **App ID** و**Client ID** (كلاهما غير سري) و**Slug** — هذه فقط ما أطلبه منك (§9).
- تشغيل السيرفرات فعلياً داخل GitHub Actions سيستخدم `GITHUB_TOKEN` المدمج في كل Workflow Run، لا Private Key التطبيق — لذلك لا حاجة لمفتاح خاص في النسخة الأولى إطلاقاً.

## 5) الصلاحيات والأحداث الدقيقة (C)

المبدأ: أقل امتياز، وربط كل صلاحية بميزة. الوثائق المرجعية: اختيار الصلاحيات [2](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/choosing-permissions-for-a-github-app) وخريطة «Permissions required for GitHub Apps» لكل Endpoint.

### Repository permissions

| الصلاحية | المستوى | ربطها بميزة NOVA CRAFT |
|---|---|---|
| Metadata | Read-only | تلقائية/إلزامية مع أي صلاحية مستودع؛ قوائم المستودعات وبياناتها الأساسية |
| Contents | **Read and write** | قراءة/كتابة ملفات إعداد السيرفر، إدارة الملفات، تعديل server.properties/configs عبر Contents API |
| Workflows | **Read and write** | إنشاء/تحديث ملفات `.github/workflows/*.yml` (صلاحية مستقلة عن Contents بقرار GitHub) |
| Actions | **Read and write** | `workflow_dispatch` للتشغيل/الإيقاف/النسخ، قراءة Runs/Jobs/Logs، Cancel/Re-run |
| Secrets | **Read and write** | كتابة `PLAYIT_SECRET_KEY` كـActions Secret مشفراً بمفتاح المستودع العام؛ الـAPI لا يعيد قيم الأسرار نصاً أبداً (أسماء فقط) |
| Repository creation | **Read and write** | إنشاء مستودع سيرفر جديد (`POST /user/repos` / `POST /orgs/{owner}/repos`) دون صلاحية Administration الواسعة. صلاحية حديثة (أكتوبر 2026) صُممت لهذا الغرض تحديداً [3](https://github.blog/changelog/2026-10-13-github-app-improvements-for-least-privilege-and-management/). **خطة بديلة موثقة:** إن لم تظهر «Repository creation» في واجهة حسابك بعد، استخدم Administration = Read and write مؤقتاً وأعلمني، لأنها تمنح أيضاً حذف/نقل المستودعات — سنراجعها قبل أي إصدار |
| Administration | No access | مقصودة: لا حذف/نقل/إعدادات خطرة من التطبيق (انظر البديل المؤقت أعلاه فقط) |
| Variables | No access | الإعدادات غير السرية تُحفظ في ملف إعداد بالمستودع عبر Contents؛ لا حاجة لصلاحية إضافية |
| Checks / Statuses | No access | حالة التشغيل تُقرأ من Actions Runs/Jobs API مباشرة |
| Pull requests / Issues / Deployments / Environments / Pages / Packages وباقي القائمة | No access | خارج نطاق النسخة الأولى |

### Organization / Account / Enterprise permissions

| الفئة | المستوى | السبب |
|---|---|---|
| Organization (الكل: Administration, Members, Secrets, Variables, …) | **No access** | التطبيق يعمل على مستودعات مختارة فردياً (شخصية أو ضمن منظمة) بصلاحيات المستودع فقط؛ لا إدارة أعضاء/منظمة. تنبيه: عند التثبيت على منظمة، قد يطلب GitHub موافقة مالك المنظمة لصلاحية Repository creation الحساسة — هذا متوقع وطبيعي |
| Account (الكل: Email addresses, Profile, Keys, …) | **No access** | الهوية الأساسية تُقرأ بـ`GET /user` برمز المستخدم دون صلاحيات حساب إضافية؛ لا نجمع بريداً أو مفاتيح |
| Enterprise (الكل) | **No access** | خارج النطاق تماماً |

### Subscribe to events

**لا أحداث في النسخة الأولى** (Webhook معطّل). مستقبلاً — وبعد نشر Backend فقط — المرشحون: `workflow_run`، `workflow_job`، `github_app_authorization`، `installation`، مع تحقق توقيع `X-Hub-Signature-256` إلزامي.

## 6) خطة Playit.gg الواقعية (إجابة §7 من الملف)

مصادر رسمية/أولية مُتحقق منها: صفحة أسعار Playit [4](https://playit.gg/pricing)، مستودع الوكيل الرسمي [10](https://github.com/playit-cloud/playit-agent)، نقاشات دعم Playit الرسمية.

1. **لا توجد OAuth عامة ولا API عامة موثقة لإنشاء الأنفاق برمجياً لحسابات المستخدمين.** وكيل Playit نفسه يملك مفتاحاً «للقراءة» لا يسمح بإنشاء الأنفاق، وPartner API لإنشاء وكلاء نيابة عن المستخدمين يتطلب اعتماد شريك. لذلك أي زر «ربط Playit بـOAuth» داخل التطبيق سيكون ادعاءً كاذباً — لن يُبنى.
2. **التدفق الآمن المعتمد (ربط يدوي موثّق مرة واحدة):**
   - أ. المستخدم ينشئ حساب Playit بنفسه (لا يطلب التطبيق كلمة مرور Playit أبداً ولا يخزنها).
   - ب. من لوحة Playit ينشئ **Agent** جديداً ويحصل على `SECRET_KEY` (تُعامل ككلمة مرور: تظهر/تُولّد من اللوحة).
   - ج. المستخدم يلصق الـ`SECRET_KEY` داخل NOVA CRAFT مرة واحدة؛ التطبيق يشفّره بمفتاح المستودع العام ويخزّنه كـGitHub Actions Secret باسم `PLAYIT_SECRET_KEY` في مستودع ذلك السيرفر، ثم **لا يحتفظ بالنص الصريح** على الجهاز.
   - د. داخل كل دورة تشغيل، الـWorkflow يثبّت Playit Agent الرسمي (بنظام Linux runner، من الـPPA الرسمي أو صورة `ghcr.io/playit-cloud/playit-agent` مع تثبيت إصدار محدد) ويشغّله بـ`SECRET_KEY` من الـSecret — فيُعاد الاتصال بنفس الوكيل والأنفاق دون إعادة ربط.
   - هـ. الأنفاق نفسها تُنشأ **مرة واحدة من لوحة Playit** وترتبط بالوكيل: نوع `Minecraft Java` (TCP ← ‏127.0.0.1:25565) لسيرفرات Java، ونوع `Minecraft Bedrock` (UDP ← ‏127.0.0.1:19132) لـBedrock. لا يستطيع التطبيق إنشاءها آلياً بالـAPI المتاح — سيعرض معالجاً إرشادياً بالخطوات والقيم الدقيقة بدل زر وهمي.
3. **ثبات العنوان:** الخطة المجانية تمنح عنواناً عشوائياً لكن **ثابتاً لا يتغير** مرتبطاً بالنفق [4](https://playit.gg/pricing) — لذلك عنوان الاتصال يبقى نفسه عبر دورات Runners جديدة ما دام النفق والوكيل نفسهما يُعاد استخدامهما. التطبيق يقرأ العنوان الذي يقرؤه المستخدم من لوحة Playit ويثبّته في إعداد السيرفر، ويتحقق منه فعلياً بـPing بروتوكولي قبل عرض «Connected».
4. **حدود الخطة المجانية الحالية (متغيرة — تتحقق وقت التنفيذ):** 4 منافذ ووكيلان، أنفاق ألعاب مدعومة (Minecraft Java/Bedrock) + UDP عام، بينما الأنفاق العامة TCP وTCP+UDP أصبحت Premium ($3/شهر) [4](https://playit.gg/pricing). هذا يكفي Java (‏TCP عبر preset اللعبة) وBedrock (‏UDP) دون دفع، ولا يكفي أنفاق RCON/TCP إضافية — لهذا الكونسول في النسخة الأولى Polling عبر GitHub لا RCON شبكي.
5. **تنبيه Bedrock حديث ومؤثر:** إصدارات Bedrock الحديثة تستخدم NetherNet افتراضياً بدل RakNet؛ توثيق Playit الرسمي (سبتمبر 2026) يوجّه إلى `transport=raknet` في server.properties للاستمرار عبر نفق UDP، وإلا احتاج TCP+UDP (Premium). سيعتمد NOVA CRAFT ضبط `transport=raknet` صراحةً لسيرفرات Bedrock، وسيُختبر فعلياً قبل ادعاء الدعم.

## 7) خطة Java وBedrock والتشغيل والنسخ الاحتياطي (إجابة §6 من الملف)

### مصادر الإصدارات والبرمجيات (تُجلب حية وقت الإنشاء، لا قوائم ثابتة)

| الاختيار | المصدر الرسمي/الأولي | ملاحظة توافق |
|---|---|---|
| قائمة إصدارات Java + Vanilla server.jar | Mojang Piston Meta: `version_manifest_v2.json` ثم ملف الإصدار (`downloads.server` + SHA1 + `javaVersion`) | الإصدار يحدد نسخة Java المطلوبة على الـRunner |
| Paper | PaperMC Fill API (خليفة Downloads API v2 المعلن إيقاف v1) | تُعرض فقط الإصدارات ذات builds فعلية |
| Purpur | `api.purpurmc.org/v2/purpur` | مبني على Paper؛ نفس منطق التوافق |
| Fabric | Fabric Meta (loader/installer) | حسب توفر Loader للإصدار |
| Forge / NeoForge | Maven الرسمي لكل مشروع + Installer (`--installServer`) | خطوة تثبيت أثقل؛ تُختبر منفصلة |
| Spigot | BuildTools رسمياً (لا تنزيل مباشر مرخّص للـjar) | يُبنى داخل الـRunner أو يُستبعد من قائمة إصدار إن تعذر — لن يُعرض كتنزيل مباشر وهمي |
| Bedrock | Bedrock Dedicated Server الرسمي (Linux/Ubuntu ZIP من minecraft.net) [3](https://www.minecraft.net/en-us/download/server/bedrock) | برمجية واحدة رسمية؛ لا Paper/Mods Java. إضافات Bedrock (Add-ons) نظام مختلف يُعلن بصراحة |

Java = TCP 25565؛ Bedrock = UDP 19132 (و19133 IPv6) [1](https://learn.microsoft.com/en-us/minecraft/creator/documents/bedrockserver/getting-started?view=minecraft-bedrock-stable). لن يظهر أي خيار برمجية Java ضمن Bedrock أو العكس.

### دورات التشغيل على GitHub Actions

- حد موثق: كل Job على GitHub-hosted runner يُلغى بعد **6 ساعات** كحد أقصى [1](https://docs.github.com/en/actions/reference/limits) — لذلك هدف «≈5 ساعات تشغيل + هامش حفظ/إيقاف» قابل للتنفيذ داخل Job واحد، وهدف 24/7 الحقيقي غير مضمون إطلاقاً ولن يُدّعى.
- النمط: Workflow رئيسي (`workflow_dispatch`) ← استعادة آخر نسخة سليمة ← تشغيل السيرفر + Playit Agent ← Heartbeat دوري ← عند قرب السقف أو طلب إيقاف: إيقاف منظم (`save-all`/`stop`) ← أرشفة وتحقق سلامة (checksum + فتح الأرشيف) ← رفع نسخة جديدة ← إطلاق الدورة التالية بـ`workflow_dispatch` (أحد حدثين يستثنيهما GitHub من قاعدة «أحداث GITHUB_TOKEN لا تطلق Runs جديدة»)، مع `concurrency: group=novacraft-<server-id>, cancel-in-progress=false` لمنع دورتين متزامنتين لنفس السيرفر، وBackoff وإيقاف تلقائي بعد فشل متكرر بدل حلقة استهلاك لا نهائية.
- **التخزين الدائم للنسخ:** GitHub Releases Assets داخل مستودع السيرفر نفسه (حتى 2 GiB للملف، بلا حد إجمالي موثق) [2](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases) — تتجاوز عمر الـRunner. بالمقابل Actions Artifacts مؤقتة (90 يوماً افتراضياً كحد أقصى للاحتفاظ) وحصة تخزين الخطة المجانية 500 MB ودقائق المستودعات الخاصة 2000 دقيقة/شهر [1](https://docs.github.com/en/actions/reference/limits) — دورة 5 ساعات على مستودع خاص تستهلك ≈300 دقيقة، أي ≈6 دورات/شهر مجاناً فقط. **لا عالم ضخماً داخل Git History إطلاقاً، ولا حذف لآخر نسخة سليمة قبل تحقق الجديدة.**
- القرار المؤجل للمستخدم (§9): مستودعات سيرفرات خاصة (أمان العالم والبيانات، مقابل استهلاك الدقائق) أم عامة (دقائق مجانية للمستودعات العامة، مقابل انكشاف ملفات/نسخ العالم لكل من يعرف الرابط). توصيتي: **خاص**، مع عرض استهلاك الدقائق بصراحة داخل التطبيق.

### بيانات حقيقية فقط (Ping / لاعبون / موارد)

- **Java:** Server List Ping (TCP) مباشرة من الهاتف إلى عنوان Playit ← MOTD والإصدار وعدد اللاعبين والـLatency المقاس فعلياً على الجهاز.
- **Bedrock:** RakNet Unconnected Ping (UDP) ← MOTD وعدد اللاعبين والوضع والمنفذ.
- **الذاكرة/CPU/TPS ومدة التشغيل:** لا يوفرها GitHub API عن داخل الـRunner. ستأتي فقط من ملف حالة (heartbeat) يكتبه الـWorkflow دورياً بمقاييس مقاسة فعلياً داخل الـRunner (مثل `uptime` وذاكرة العملية)، مع ختم زمني — وما تأخر عن عتبة يُعرض «بيانات قديمة» لا أرقاماً حية مخترعة. مدة الدورة تُحسب من `run_started_at` الحقيقي للـRun.
- **Console:** Polling لسجلات Actions (ليست بثاً حياً ولن تُسمى Live) + قائمة أوامر آمنة بتدقيق وتأكيد للأوامر الخطرة؛ حدود هذه الآلية (تأخر السجلات أثناء التشغيل) ستُختبر وتُوثق في مرحلتها بدل ادعاء فورية كاذبة.

## 8) الأسرار وأماكن حفظها (E)

| القيمة | سرية؟ | مكان الحفظ المعتمد | ممنوع |
|---|---|---|---|
| Client ID (`Iv1.…`/`Iv23…`) | لا (معرّف عام) | ثابت إعداد في الكود/BuildConfig | — |
| App ID + App Slug | لا | إعداد تطبيق + توثيق | — |
| User/Refresh Tokens (GitHub) | نعم | Android Keystore + Encrypted Storage على الجهاز فقط | Logs / Git / Crash reports |
| Client Secret | نعم | **لا يُولّد في النسخة الأولى** (غير مطلوب)؛ إن وُجد: مدير كلمات مرور المستخدم | APK / المحادثة / المستودع |
| GitHub App Private Key (.pem) | نعم | **لا يُولّد في النسخة الأولى** (لا Backend يحتاجه) | APK / المستودع / المحادثة إطلاقاً |
| Playit `SECRET_KEY` (لكل سيرفر) | نعم | GitHub Actions Secret مشفر في مستودع السيرفر (`PLAYIT_SECRET_KEY`) | Git / Logs / الاحتفاظ بنص صريح على الهاتف |
| Webhook Secret | نعم | مستقبلاً فقط: Backend Secret Store + حقل GitHub | أي مكان آخر |
| Release Keystore (مرحلة لاحقة) | نعم | خارج Git تماماً + GitHub Actions Secrets عند بناء CI، مع نسخة آمنة بمسؤولية المستخدم | المستودع / Artifacts عامة |

## 9) ما يحتاجه المستخدم قبل التطوير (F + G)

### خطوات GitHub (تُنفّذ الآن)

1. افتح **Settings → Developer settings → GitHub Apps → New GitHub App** تحت حسابك الشخصي.
2. املأ الحقول حرفياً كما في جدول §4 (الاسم الأساسي، الوصف، Homepage URL، ترك Callback/Setup/Webhook فارغة أو معطّلة كما هو محدد، تفعيل Device Flow فقط، إبقاء Expire tokens مفعّلاً).
3. طبّق صلاحيات §5 بدقة (Repository: ‏Metadata RO، ‏Contents RW، ‏Workflows RW، ‏Actions RW، ‏Secrets RW، ‏Repository creation RW؛ والباقي No access؛ Organization/Account/Enterprise كلها No access؛ Events: لا شيء؛ Installation: ‏Only on this account).
4. اضغط **Create GitHub App** ولا تضغط Generate private key ولا Generate client secret.
5. أرسل لي **ثلاث قيم غير سرية فقط**: `App ID` و`Client ID` و`App Slug` (أو رابط صفحة التطبيق `github.com/settings/apps/<slug>`). لا ترسل أي سر في المحادثة.
6. (اختياري الآن ويُطلب داخل التطبيق لاحقاً) ثبّت التطبيق على حسابك واختر مستودع اختبار واحداً — لا تثبّته على كل المستودعات.

### قرارات/حسابات مطلوبة من المستخدم (قصيرة وضرورية فقط)

1. هل لديك حساب Playit.gg جاهز، أم ستنشئه عند مرحلة Playit؟ (لا أطلب أي بيانات دخول.)
2. مستودعات السيرفرات: **خاصة** (موصى بها) أم عامة؟ (يؤثر في دقائق Actions وخصوصية نسخ العالم — §7.)
3. تأكيد قبول Device Flow (إدخال كود في github.com/login/device) كتجربة تسجيل دخول للنسخة الأولى، بدل تأجيل المشروع لبناء Backend من أجل Web Flow.

**بعد استلام القيم غير السرية وموافقتك الصريحة، تبدأ Phase 2 (هيكل التطبيق الأصلي) — ولن تبدأ قبل ذلك.**

---

## 10) تحديث 2026-10-17 — إنشاء الـGitHub App والتحقق الفعلي من الإعدادات

### 10.1 القيم المستلمة من المستخدم (غير سرية، معتمدة كما هي)

| القيمة | المعتمد في المشروع |
|---|---|
| GitHub App Name | `NOVA CRAFT by abiedadam0077` |
| Owner | `abiedadam0077` |
| App ID | `5353235` |
| Client ID | `Iv23linL1Tf6ResSgUqL` |
| App Slug (مشتق وموثّق عبر الـAPI) | `nova-craft-by-abiedadam0077` |
| صفحة التطبيق | https://github.com/apps/nova-craft-by-abiedadam0077 |

حالة قرارات §9 بعد هذا التحديث: قرار المستودعات حُسم (انظر §10.4)، وDevice Flow اعتُمد مبدئياً وتم التحقق من تفعيله فعلياً (§10.2). يبقى سؤال حساب Playit.gg مفتوحاً لمرحلته، ولا يعيق إكمال هذا التقرير.

لا يوجد في المشروع أي Client Secret أو Private Key أو Token، ولن يُطلب أو يُحفظ أي منها في الكود أو APK أو المستودع.

### 10.2 ما تم التحقق منه فعلياً (GitHub API + اختبار وظيفي، 2026-10-17)

استعلام `GET /apps/nova-craft-by-abiedadam0077` أعاد: `id=5353235` و`client_id=Iv23linL1Tf6ResSgUqL` و`owner.login=abiedadam0077` والاسم والوصف مطابقين لورقة الإعداد حرفياً و`external_url=https://github.com/abiedadam0077/NOVA-CRAFT`، و:

```json
"permissions": {
  "actions": "write",
  "contents": "write",
  "metadata": "read",
  "repository_creation": "write",
  "secrets": "write",
  "workflows": "write"
},
"events": []
```

| البند | النتيجة | طريقة التحقق |
|---|---|---|
| App ID / Client ID / Name / Owner / Slug / Homepage | مطابقة تماماً للقيم المستلمة | GitHub REST API |
| Contents: write | موجودة | API (حقل permissions) |
| Workflows: write | موجودة — Contents وحدها لا تكفي لملفات `.github/workflows/` والوثائق تشترط Contents+Workflows معاً لذلك | API + وثائق Contents API |
| Actions: write | موجودة — تشغيل workflow_dispatch يتطلب Actions write تحديداً | API + وثائق GitHub |
| Secrets: write | موجودة — كتابة/حذف Actions Secrets للمستودع؛ الـAPI لا يعيد قيم الأسرار أبداً | API + وثائق Permissions required |
| Repository creation: write | موجودة فعلياً (وليست Administration) — وثائق POST /user/repos تجيزها لرموز GitHub App بديلاً عن Administration write، وتغطي private true/false بلا صلاحية منفصلة للنوعين | API + وثائق Repositories API |
| اشتراكات Webhook events | فارغة `[]` كما هو مخطط للنسخة الأولى | API |
| Device Flow مفعّل فعلياً | مُثبت وظيفياً: POST إلى github.com/login/device/code بالـClient ID المعتمد أعاد verification_uri وexpires_in=899 وinterval=5 وكوداً تجريبياً انتهى دون أي تفويض (لا تستخدم أي كود من هذا التقرير). طلب تحكم بـClient ID خاطئ أعاد خطأ، أي أن الاستجابة خاصة بتطبيقنا فعلاً | اختبار HTTP فعلي |
| توافق إنشاء مستودعات Private وPublic | صلاحية واحدة (Repository creation: write) ومعامل private/visibility في طلب الإنشاء يحدد النوع. يبقى اختبار إنشاء حي (مستودع اختبار يُحذف يدوياً من المالك) ضمن Phase 3 لأنه يتطلب User Token صادراً من جهاز المستخدم عبر Device Flow، ولن يُدّعى قبل تنفيذه | وثائق رسمية |

### 10.3 ما لا تستطيع الـAPI العامة إظهاره (يتطلب تأكيداً بصرياً واحداً من المالك)

العناصر التالية لا تظهر في استجابة GET /apps/{slug} لأي طرف، وادعاء التحقق منها برمجياً سيكون غير دقيق:

- Webhook Active غير مفعّل فعلياً (قائمة events الفارغة متسقة مع ذلك لكنها لا تثبته وحدها).
- Callback URL فارغ، وExpire user authorization tokens مفعّل، وRequest user authorization (OAuth) during installation غير مفعّل.
- Where can this GitHub App be installed = Only on this account.

المطلوب من المالك تأكيدها بصرياً مرة واحدة من صفحة إعدادات التطبيق (انظر «الخطوة التالية» في متن الرد). كذلك حالة تثبيت (Installation) التطبيق على الحساب لا تُقرأ إلا برمز مستخدم صادر عن هذا التطبيق نفسه، وستُتحقق تلقائياً داخل التطبيق عند أول تسجيل دخول في Phase 3.

### 10.4 قرار المستخدم الملزم: Private + Public معاً

- Wizard إنشاء السيرفر يعرض اختياراً صريحاً **Private (افتراضي وموصى به) / Public** عند إنشاء مستودع جديد، ويحذّر قبل تأكيد Public: المحتوى (بما فيه ملفات العالم والنسخ في Releases) مرئي لأي شخص، ويُمنع منعاً باتاً رفع أسرار/Tokens/كلمات مرور إليه (الأسرار لا تعيش إلا في Actions Secrets المشفرة حتى في المستودعات العامة).
- عند اختيار مستودع موجود: تُعرض فقط المستودعات التي يصل إليها فعلياً تقاطع (تثبيت التطبيق × صلاحيات المستخدم)، عبر GET /user/installations وGET /user/installations/{id}/repositories برمز المستخدم — ولا يُكتب أبداً في مستودع غير مختار.
- تنبيه كلفة يبقى ظاهراً: المستودع الخاص يستهلك من دقائق Actions المحدودة (تقريباً 300 دقيقة/دورة 5 ساعات من 2000/شهر مجاناً)، والعام يعمل بدقائق مجانية للمستودعات العامة مقابل الانكشاف أعلاه.
- ملاحظة معمارية ذات صلة: ملفات الـWorkflows الأولية ستُكتب من التطبيق عبر Contents API برمز المستخدم (Contents+Workflows)، لأن GITHUB_TOKEN داخل الـWorkflows ممنوع تصميمياً من تعديل ملفات .github/workflows/ — ولن يُعتمد عليه لذلك.
