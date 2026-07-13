# التطوير المحلي

## المتطلبات

استخدم Node.js 22 وnpm فقط؛ اختير npm لأنه مدير الحزم الافتراضي مع Node.js ويدعم Workspaces دون أداة إضافية. لا تضع `.env.local` في Git ولا تستخدم بيانات إنتاج.

1. انسخ `.env.example` إلى `.env.local` وأبقِ القيم فارغة إذا لم تكن تختبر Supabase.
2. شغّل `npm install` من جذر المستودع.
3. شغّل `npm run dev` ثم افتح `/ar` أو `/en`.

الفحوصات: `npm run lint` و`npm run typecheck` و`npm run test` و`npm run build` أو `npm run check` للجميع. استخدم `npm ci` في CI أو بعد وجود lockfile. لتشغيل Supabase محليًا عند توفر CLI وDocker استخدم `supabase start` ثم `supabase db reset` لتطبيق migrations وseed الخيالي. لإعادة تعيين بيئة محلية: أوقف الخدمات ثم أعد `supabase db reset`؛ لا تستعمل هذا الأمر على إنتاج. اختبر رفض cross-tenant عبر `supabase/tests/rls_cross_tenant.sql`.
