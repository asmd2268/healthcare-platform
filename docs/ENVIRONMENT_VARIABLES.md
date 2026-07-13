# متغيرات البيئة

القيم والأسماء موجودة في `.env.example` فقط. تنقسم البيئة إلى: **Public** (`NEXT_PUBLIC_SUPABASE_URL` و`NEXT_PUBLIC_SUPABASE_ANON_KEY`) للعمليات المسموحة، و**Server-user** (`DATABASE_URL` و`APP_BASE_URL` الاختياريان) للميزات الخادمية، و**Admin/bootstrap-only** (`SUPABASE_SERVICE_ROLE_KEY` و`PLATFORM_OWNER_BOOTSTRAP_CONFIRMATION`) للمهام الإدارية المراجعة فقط. لا يحتاج البناء أو العرض العادي أو عميل المستخدم إلى Service Role Key، ولا يجوز استيراده أو إرساله إلى المتصفح.

`APP_BASE_URL` عنوان التطبيق الثابت والمعتمد مثل `https://platform.example`; يستخدم فقط عند طلب إعادة تعيين كلمة المرور لبناء redirect URL موثوق. لا يستخدم التطبيق `Origin` أو `x-forwarded-host` القابلين للتلاعب لهذا الغرض.

لا ترفع `.env.local` إلى GitHub، ولا تسجل المفاتيح أو Tokens أو كلمات المرور. التطبيق يعمل دون إعداد Supabase في هذه المرحلة؛ تفشل الميزة التي تستدعي عميلًا غير مُعد بوضوح عند الاستدعاء فقط. لا تُنشأ جداول ولا تتصل أي بيئة بقاعدة إنتاج.
