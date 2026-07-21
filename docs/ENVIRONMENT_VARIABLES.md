# متغيرات البيئة

القيم والأسماء موجودة في `.env.example` فقط. تنقسم البيئة إلى: **Public** (`NEXT_PUBLIC_SUPABASE_URL` و`NEXT_PUBLIC_SUPABASE_ANON_KEY`) للعمليات المسموحة، و**Server-user** (`DATABASE_URL` و`APP_BASE_URL` الاختياريان) للميزات الخادمية، و**Admin/trusted-job-only** (`SUPABASE_SERVICE_ROLE_KEY` و`PLATFORM_OWNER_BOOTSTRAP_CONFIRMATION`) للـbootstrap والوظائف الخادمية المراجعة مثل انتهاء الحجوزات. لا يحتاج البناء أو العرض العادي أو عميل المستخدم إلى Service Role Key، ولا يجوز استيراده أو إرساله إلى المتصفح.

## Reservation-expiry scheduler

مسار انتهاء حجوزات المخزون هو route خادمي داخلي فقط: `/api/internal/inventory/reservation-expiry`. لا يقرأه أي مكون عميل ولا يقبل actor من الطلب. يحتاج بيئة النشر إلى `CRON_SECRET` عشوائيًا بطول 16 محرفًا على الأقل بلا مسافات أو فواصل (يرسله Vercel Cron ضمن `Authorization: Bearer …`)، و`INVENTORY_RESERVATION_EXPIRY_AUTOMATION_PRINCIPAL_ID` وهو UUID لخدمة Auth غير تفاعلية مسجلة للغرض `inventory.reservation_expiry`. المتغير الاختياري `INVENTORY_RESERVATION_EXPIRY_BATCH_LIMIT` عدد صحيح من 1 إلى 1000، وقيمته الافتراضية 100. يضبط `INVENTORY_RESERVATION_EXPIRY_MAX_BATCHES` عدد batches المتتابعة في invocation واحد (الافتراضي 10)؛ يُرفض أي إعداد يتجاوز فيه حاصل الضرب 1000.

هذه المتغيرات و`SUPABASE_SERVICE_ROLE_KEY` سرية خادمية؛ لا تبدأ بـ`NEXT_PUBLIC_`، ولا توضع في frontend أو logs أو response. يتطلب route أيضًا `NEXT_PUBLIC_SUPABASE_URL` على الخادم لإنشاء عميل Supabase الإداري فقط. غياب قيمة، UUID غير صالح، secret غير صالح، أو خطأ RPC يعطي فشلًا عامًا مغلقًا بلا تفاصيل هوية أو نطاق أو قاعدة بيانات.

`APP_BASE_URL` عنوان التطبيق الثابت والمعتمد مثل `https://platform.example`; يستخدم فقط عند طلب إعادة تعيين كلمة المرور لبناء redirect URL موثوق. لا يستخدم التطبيق `Origin` أو `x-forwarded-host` القابلين للتلاعب لهذا الغرض.

لا ترفع `.env.local` إلى GitHub، ولا تسجل المفاتيح أو Tokens أو كلمات المرور. التطبيق يعمل دون إعداد Supabase في هذه المرحلة؛ تفشل الميزة التي تستدعي عميلًا غير مُعد بوضوح عند الاستدعاء فقط. لا تُنشأ جداول ولا تتصل أي بيئة بقاعدة إنتاج.

لـStaging استخدم `.env.staging.example` كقائمة أسماء فقط، واضبط `SUPABASE_ENV=staging` صراحة. لا تتشارك ملفات local أو staging أو production، ولا تضع قيمها في GitHub Actions logs. راجع [STAGING_VALIDATION.md](STAGING_VALIDATION.md) قبل link أو migration أو seed.
