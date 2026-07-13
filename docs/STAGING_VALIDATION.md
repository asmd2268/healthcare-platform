# التحقق على Supabase Staging

هذا الإجراء مخصص لمشروع Supabase منفصل وغير إنتاجي. لا تستخدمه مع قاعدة إنتاج، ولا تستخدم بيانات مرضى أو موظفين أو منشآت حقيقية، ولا تحفظ مفاتيح أو كلمات مرور في GitHub.

## قائمة إعداد Staging

1. أنشئ مشروع Supabase جديدًا مخصصًا للاختبار وحده، وسمّه في لوحة التحكم كبيئة Staging.
2. انسخ Project URL وanon key وservice-role key إلى مخزن أسرار معتمد، وليس إلى المستودع أو وصف PR.
3. أنشئ ملفًا محليًا من `.env.staging.example` خارج Git أو استخدم متغيرات CI السرية، واضبط `SUPABASE_ENV=staging` و`APP_BASE_URL` لعنوان تطبيق Staging الثابت.
4. أضف callback المعتمد للمصادقة وإعادة تعيين كلمة المرور إلى Supabase Auth Redirect URLs، ثم راجعه حرفيًا مقابل `APP_BASE_URL`.
5. لا تفعّل public sign-up إذا كانت الحسابات ستنشأ بواسطة مسؤول: من Authentication > Providers > Email عطّل التسجيل العام، واحتفظ بإنشاء المستخدمين ضمن الإجراء الإداري المعتمد.
6. لا تنسخ أي بيانات أو مستخدمين أو مرفقات من الإنتاج. استخدم seed الخيالي أو بيانات اختبار مولدة يدويًا فقط.

## فصل البيئات

| البيئة | متغير `SUPABASE_ENV` | البيانات | أوامر مدمرة |
| --- | --- | --- | --- |
| Local | `local` | خيالية فقط | مسموحة محليًا بعد فحص الهدف |
| Staging | `staging` | خيالية فقط | تتطلب نسخة احتياطية وتأكيدًا يدويًا؛ لا تنفذ تلقائيًا |
| Production | `production` | بيانات تشغيل معتمدة | ممنوعة من workflow هذا |

لا يكفي اسم branch أو project لحماية البيئة. شغّل قبل أي أمر:

```bash
npm run supabase:target:check
```

تتحقق الأداة من URL وanon key و`APP_BASE_URL` و`SUPABASE_ENV`، وتطبع project ref المستهدف فقط. ترفض project يبدو إنتاجيًا ما لم يضع المسؤول override الصريح الموثق؛ هذا override لا يجب استخدامه لهذا workflow.

## أوامر CLI المراجعة

ثبّت Supabase CLI وسجّل الدخول خارج السكربتات، ثم استخدم project ref المخزن في سر بيئة:

```bash
supabase link --project-ref "$SUPABASE_PROJECT_REF"
supabase migration list
npm run supabase:target:check
supabase db push
supabase migration list
```

قبل bootstrap استخدم `npm run supabase:target:bootstrap-check`. يتحقق هذا الأمر من وجود متغيرات admin-only دون طباعة قيمها؛ لا تنفذ bootstrap من route عامة أو terminal غير مراجع.

طبّق seed فقط بعد تأكيد أن `SUPABASE_ENV=staging` وبعد أخذ نسخة احتياطية أو Snapshot معتمد. لا يوجد أمر seed تلقائي في هذا المستودع للهدف البعيد؛ شغّل `supabase/seed.sql` عبر قناة إدارية مراجعة ومتوافقة مع إصدار CLI المستخدم، مع `ON_ERROR_STOP`، وباستخدام بيانات خيالية فقط.

بعد أن يمر `npm run supabase:target:seed-check` ويؤكد مسؤول البيئة أن `DATABASE_URL` يشير إلى Staging فقط، يكون الأمر اليدوي الصريح للـseed:

```bash
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/seed.sql
```

قبل أي reset محلي أو staging راجع الهدف أولًا:

```bash
npm run supabase:target:reset-check
```

الأداة لا تنفذ reset. لا تشغّل `supabase db reset` على Staging إلا بعد تأكيد مكتوب للهدف ووجود backup، ولا تشغّله مطلقًا على Production.

لتشغيل سيناريوهات SQL على Staging، استخدم اتصالًا إداريًا سريًا ومراجَعًا بعد migrations، وشغّل ملفات `supabase/tests/` واحدةً في كل مرة مع إيقاف عند الخطأ. لا تعتبر الاختبارات ناجحة حتى تُسجل النتائج في المصفوفة أدناه.

شغّل أولًا `npm run supabase:target:sql-tests-check`؛ لا يبدأ هذا الأمر اتصالًا ولا يكشف `DATABASE_URL`.

```bash
for test_file in supabase/tests/*.sql; do
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$test_file"
done
```

## جاهزية التراجع

قبل `supabase db push`: سجل رقم migrations الحالي، أنشئ Snapshot/backup في مشروع Staging، تحقق من إمكانية قراءة خطة الاستعادة، وعيّن مسؤول قرار التراجع. إذا فشل migration، أوقف الكتابة، لا تعدل migration مطبقًا، واستعد snapshot أو أنشئ migration إصلاحية مجربة. راجع [النشر](DEPLOYMENT.md) قبل أي هدف إنتاجي.

## خطوات التحقق الوظيفي والأمني

سجل النتيجة الفعلية والوقت والمنفذ في مصفوفة الاختبار؛ لا تضع tokens أو كلمات مرور في النتيجة.

1. **Sign in:** أنشئ حساب اختبار عبر الإجراء المعتمد، سجّل الدخول، وتأكد من إنشاء جلسة متحققة وظهور صفحة profile فقط بعد المصادقة.
2. **Sign out:** سجّل الخروج وتأكد أن profile وadministration وaudit تعيد إلى login.
3. **Password reset:** اطلب إعادة تعيين لحساب اختبار وتأكد أن الرابط يعود فقط إلى callback المعتمد وlocale الصحيح، وليس إلى origin مرسل من المتصفح.
4. **Session refresh:** انتظر أو جدّد الجلسة وفق إعداد Supabase وتأكد أن Middleware يحدّث cookies ولا يقبل cookie مصطنعًا.
5. **Protected routes:** افتح settings وprofile وaudit وadministration وinspections بلا جلسة؛ المتوقع redirect إلى login في Staging أيضًا.
6. **Missing tenant context:** استخدم حساب اختبار بلا membership؛ المتوقع عدم عرض بيانات tenant وظهور حالة آمنة، لا fallback إلى tenant آخر.
7. **Platform Owner bootstrap:** نفّذ bootstrap من job خادمي فقط بعد تحقق UUID المستخدم وtenant الخيالي. أعد المحاولة وتأكد من assignment global واحد وحدث تدقيق واحد منطقيًا.
8. **Organization administrator scope:** تحقق من الوصول إلى tenant والمنظمة المعينين فقط، ورفض منظمة ثانية.
9. **Facility administrator scope:** تحقق من الوصول إلى المنشأة المعينة فقط، ورفض منشأة ثانية في المنظمة نفسها.
10. **Scoped user access:** تحقق من عرض النماذج المنشورة فقط داخل نطاقه، بلا صلاحية إدارة.
11. **Cross-tenant denial:** حاول select/insert/update على tenant خيالي آخر؛ المتوقع RLS denial أو صفر صفوف.
12. **Cross-organization denial:** كرر المحاولة في organization ثانية ضمن tenant نفسه؛ المتوقع رفض.
13. **Cross-facility denial:** كرر المحاولة في facility ثانية ضمن organization نفسه؛ المتوقع رفض.
14. **Published-form reading:** تحقق أن `platform.view_published_forms` يقرأ definition/version/sections/fields المنشورة ضمن النطاق فقط.
15. **Draft-form denial:** تحقق أن draft وarchived وغير المنشور لا تظهر للمستخدم scoped، ولا يمكنه تعديلها.
16. **Audit-log access:** تحقق أن `platform.view_audit_logs` مطلوب لقراءة audit events، وأن المستخدم العادي لا يكتب أحداثًا إدارية.
17. **Service-role isolation:** تأكد أن service-role key لا يظهر في browser bundle أو logs، وأن دوال bootstrap/trusted audit ترفض anon وauthenticated وتقبل job الخادمي المراجع فقط.

## مصفوفة اختبار يدوي

| Actor | Role | Tenant | Organization | Facility | Attempted action | Expected result | Actual result | Pass/Fail |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| حساب اختبار A | Platform Owner | Tenant اختبار A | — | — | Bootstrap متكرر | assignment global واحد وسجل تدقيق |  |  |
| حساب اختبار B | Organization Administrator | Tenant اختبار A | Organization اختبار A | — | قراءة نموذج منشور ضمن النطاق | مسموح |  |  |
| حساب اختبار B | Organization Administrator | Tenant اختبار A | Organization اختبار B | — | قراءة نموذج منشور | مرفوض |  |  |
| حساب اختبار C | Facility Administrator | Tenant اختبار A | Organization اختبار A | Facility اختبار A | قراءة نموذج منشور | مسموح |  |  |
| حساب اختبار C | Facility Administrator | Tenant اختبار A | Organization اختبار A | Facility اختبار B | قراءة نموذج منشور | مرفوض |  |  |
| حساب اختبار D | Scoped User | Tenant اختبار A | Organization اختبار A | Facility اختبار A | قراءة draft | مرفوض |  |  |
| حساب اختبار D | Scoped User | Tenant اختبار A | Organization اختبار A | Facility اختبار A | قراءة published form | مسموح بلا تعديل |  |  |
| Anonymous | — | — | — | — | قراءة نموذج أو audit | مرفوض/صفر صفوف |  |  |
| حساب اختبار E | Scoped User | Tenant اختبار B | Organization اختبار B | Facility اختبار B | الوصول إلى Tenant اختبار A | مرفوض |  |  |

## بيانات الاختبار والأسرار

استخدم أسماء خيالية عامة مثل Tenant اختبار A وOrganization اختبار A وFacility اختبار A، ورموزًا مولدة محليًا، ولا تستخدم أسماء مستشفيات أو موظفين أو أدوية حقيقية. لا تنشئ كلمات مرور داخل seed أو SQL. احذف حسابات الاختبار بعد التحقق وفق سياسة Staging.

بعد bootstrap، أزل `PLATFORM_OWNER_BOOTSTRAP_CONFIRMATION` من job المؤقت، واقصر service-role key على مخزن أسرار الخادم. إذا ظهر المفتاح في log أو قناة غير موثوقة، أدره فورًا في Supabase ثم حدّث secret manager وأعد التحقق. افحص المستودع والتاريخ قبل النشر باستخدام أدوات فحص الأسرار المعتمدة؛ لا تنسخ قيمة مشبوهة إلى tickets أو PRs. راجع `git log -p` في بيئة آمنة وفحص CI للأسرار، ثم عالج أي كشف باعتباره تسربًا حتى لو حُذف لاحقًا من working tree.

## اختبارات SQL التنفيذية

شغّل `SUPABASE_ENV=staging DATABASE_URL=<secret> npm run test:sql:staging`. لا يعيد runner ضبط قاعدة البيانات، ويرفض هدفًا يبدو إنتاجيًا، ويشغّل فقط ملفات `*.executable.sql` بالترتيب ثم يتراجع عن كل transaction. لا يطبع عنوان قاعدة البيانات أو كلمة المرور. `000_staging_security.executable.sql` قابل للتنفيذ؛ بقية ملفات `supabase/tests` الحالية جزئية أو تعليقات/قوالب pgTAP وليست دليل نجاح حتى تتحول إلى assertions تنفيذية.
