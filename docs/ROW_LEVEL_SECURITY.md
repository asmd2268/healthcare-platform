# Row-Level Security

كل جدول تابع للمنصة في migration الأساسي مفعّل عليه RLS. لا توجد سياسة `using (true)` للبيانات المحمية. تستدعي السياسات `scope_allowed` و`has_platform_permission`، وتتحقق من tenant ثم organization ثم facility قبل عمليات النماذج أو البيانات المرجعية أو الاستيراد أو التصدير أو طلبات الحذف.

يُستخدم anon key وعميل المستخدم العادي للطلبات اليومية؛ Service Role يتجاوز RLS ولا يستخدم إلا لعملية bootstrap خادمية مراجعة. شغّل `supabase/tests/rls_cross_tenant.sql` على قاعدة محلية Disposable بعد إعداد مستخدمين وهميين للتحقق من رفض الوصول عبر المستأجرين.
