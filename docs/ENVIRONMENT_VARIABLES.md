# متغيرات البيئة

القيم والأسماء موجودة في `.env.example` فقط. `NEXT_PUBLIC_SUPABASE_URL` و`NEXT_PUBLIC_SUPABASE_ANON_KEY` مسموحان للعميل عند تهيئة Supabase لاحقًا. `SUPABASE_SERVICE_ROLE_KEY` و`DATABASE_URL` خاصان بالخادم ولا يجوز استيرادهما أو إرسالهما إلى المتصفح.

لا ترفع `.env.local` إلى GitHub، ولا تسجل المفاتيح أو Tokens أو كلمات المرور. التطبيق يعمل دون إعداد Supabase في هذه المرحلة؛ لا تُنشأ جداول ولا تتصل أي بيئة بقاعدة إنتاج.

