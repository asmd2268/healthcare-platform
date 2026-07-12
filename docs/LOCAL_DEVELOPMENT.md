# التطوير المحلي

## المتطلبات

استخدم Node.js 22 وnpm فقط؛ اختير npm لأنه مدير الحزم الافتراضي مع Node.js ويدعم Workspaces دون أداة إضافية. لا تضع `.env.local` في Git ولا تستخدم بيانات إنتاج.

1. انسخ `.env.example` إلى `.env.local` وأبقِ القيم فارغة إذا لم تكن تختبر Supabase.
2. شغّل `npm install` من جذر المستودع.
3. شغّل `npm run dev` ثم افتح `/ar` أو `/en`.

الفحوصات: `npm run lint` و`npm run typecheck` و`npm run test` و`npm run build` أو `npm run check` للجميع. استخدم `npm ci` في CI أو بعد وجود lockfile. لا يوجد مزود مصادقة أو قاعدة بيانات إنتاج في هذه المرحلة؛ لا تعد صفحات التطوير المحمية Placeholder مصادقة، والإنتاج يفشل مغلقًا إلى واجهة تسجيل الدخول.
