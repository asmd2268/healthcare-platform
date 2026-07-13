# Bootstrap لمالك المنصة الأول

1. شغّل migrations على بيئة محلية أو بيئة هدف معتمدة.
2. أنشئ المستخدم من خلال Supabase Auth أولًا، ثم تحقق يدويًا من UUID المستخدم وUUID المستأجر.
3. اضبط `SUPABASE_SERVICE_ROLE_KEY` و`PLATFORM_OWNER_BOOTSTRAP_CONFIRMATION=BOOTSTRAP_PLATFORM_OWNER` في بيئة خادمية مؤقتة فقط.
4. نفّذ `bootstrapFirstPlatformOwner` من job أو terminal خادمي مراجَع، أو استدعِ الدالة الموضحة في `supabase/scripts/bootstrap_platform_owner.sql` باستخدام اتصال إداري آمن.
5. تحقق من assignment ودور global وحدث التدقيق، ثم أزل متغير bootstrap إن لم يعد مطلوبًا.

العملية idempotent ولا تعتمد على البريد الإلكتروني ولا يوجد فيها معرف مستخدم حقيقي في المستودع. يستخدم المخطط partial unique index لدور Platform Owner ذي النطاق global، لذلك لا تنشئ المحاولات المتكررة assignment مكررًا حتى مع قيم النطاق `NULL`. لا توجد route عامة لتنفيذها، ولا يجب استخدام Service Role Key في المتصفح.
