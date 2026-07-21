# Row-Level Security

كل جدول تابع للمنصة في migration الأساسي مفعّل عليه RLS. لا توجد سياسة `using (true)` للبيانات المحمية. تستدعي السياسات `scope_allowed` و`has_platform_permission`، وتتحقق من tenant ثم organization ثم facility قبل عمليات النماذج أو البيانات المرجعية أو الاستيراد أو التصدير أو طلبات الحذف.

تسحب migration التقوية صلاحية EXECUTE الافتراضية من `PUBLIC` و`anon` لكل SECURITY DEFINER function. تحصل `authenticated` فقط على دوال الاستعلام المقيدة التي تفشل مغلقة دون `auth.uid()`، وتحصل `service_role` فقط على bootstrap والتدقيق الموثوق. تؤكد triggers اتساق tenant/organization/facility بين الجداول الأب والابن؛ لا يعتمد هذا العزل على الواجهة.

يُستخدم anon key وعميل المستخدم العادي للطلبات اليومية؛ Service Role يتجاوز RLS ولا يستخدم إلا لعملية bootstrap خادمية مراجعة. شغّل `supabase/tests/rls_cross_tenant.sql` على قاعدة محلية Disposable بعد إعداد مستخدمين وهميين للتحقق من رفض الوصول عبر المستأجرين.

## Automation identities

جدول `automation_identities` لا يمنح العميل العادي SELECT أو INSERT أو UPDATE أو DELETE ولا توجد له سياسة قراءة للعميل. دوال التسجيل، إلغاء التفعيل، وحل الهوية مقيدة بـ`service_role` فقط وذات `search_path` ثابت. الهوية المسجلة مرتبطة بـ`user_profiles` لأجل مفاتيح التدقيق الحالية، لكنها لا تملك membership أو role assignment نشطين؛ يمنع trigger منحها وصولًا تفاعليًا قبل إلغاء تفعيلها.

حل الهوية يفشل مغلقًا عند UUID غير مسجل أو معطل أو غرض أو نطاق tenant/organization/facility غير مطابق. لذلك لا يكفي أن يمتلك المستدعي `service_role` أو أن يمرر UUID لمستخدم يملك صلاحية بشرية. توفير Auth principal غير تفاعلي وتعطيل تسجيل دخوله مسؤولية provisioning خادمي خارج migration ولا تحفظ migration أي كلمة مرور أو secret.
