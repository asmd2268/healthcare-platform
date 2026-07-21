# النشر والتشغيل

## قاعدة البيانات والمصادقة

انشر migrations عبر Supabase CLI أو pipeline مراجَع فقط، ثم تحقق من النسخ الاحتياطي وخطة التراجع قبل الإنتاج. التراجع الآمن لهذه النسخة هو إيقاف النشر واستعادة نسخة قاعدة بيانات معتمدة؛ لا تحذف migration مطبقة ولا تعدلها. عند فشل migration، أوقف التطبيق عن الكتابة، راجع الخطأ دون كشف أسرار، وأنشئ migration إصلاحية بعد اختبارها محليًا.

تحتاج التطبيقات العادية URL وanon key فقط. يوضع Service Role Key في مخزن أسرار الخادم للـbootstrap والوظائف الخادمية المراجعة فقط، ومنها scheduler انتهاء حجوزات المخزون عند تفعيله؛ لا يصل إلى العميل، ويدور دوريًا أو فور الاشتباه. لا تجرِ `supabase db reset` أو seed على إنتاج.

يدعم التصميم Vercel وGitHub والاستضافة السحابية أو الخاصة والداخلية والشبكة المحلية وOn-premises، مع بقاء PWA خيارًا مستقبليًا للجوال. تفصل بيئات التطوير والاختبار والإنتاج، وتدار إعداداتها وأسرارها خارج المستودع. لا تستخدم بيانات إنتاج حقيقية في بيئات غير إنتاجية دون موافقات وضوابط.

قبل النشر: مراجعة تغيير، اختبارات، تحقق من Environment Variables، خطة رجوع، ومراقبة أخطاء. يشمل التشغيل نسخًا احتياطيًا مجدولًا، اختبار استعادة، مراقبة توافر، سجل نشر، وإجراءات حادث. تحدد الاستضافة الداخلية المسؤوليات عن الشبكة، التخزين، التحديثات، والنسخ الاحتياطي كتابةً.

تبدأ أي صلاحية Supabase جديدة من Staging منفصل. استخدم [STAGING_VALIDATION.md](STAGING_VALIDATION.md) لإثبات المصادقة وRLS وخطة التراجع قبل مناقشة نشر إنتاجي.

## Reservation-expiry scheduler cutover

هذا النشر يضيف route خادميًا مجدولًا لانتهاء حجوزات المخزون، ولا ينشئ مستخدم Auth أو سرًا أو إعدادًا في أي بيئة خارج المستودع. الترتيب الإلزامي هو:

1. طبّق migration `202607210001_automation_identity_foundation.sql` في Staging أولًا، ثم في الإنتاج عبر pipeline مراجَع ونسخة احتياطية معتمدة.
2. أنشئ خارج SQL principal مخصصًا غير تفاعلي في Supabase Auth. لا تنشئ له membership أو role أو كلمة مرور قابلة للاستخدام، ولا تسجل UUID أو credentials في Git أو PR.
3. تأكد من وجود `user_profiles` المقابل، ثم من جلسة `service_role` موثوقة سجّل الـprincipal لكل tenant مطلوب عبر `public.register_automation_identity(principal, tenant, organization, facility, 'inventory.reservation_expiry', display_name, administrator)`. يجب أن يكون `administrator` مستخدمًا بشريًا صالحًا يملك `platform.manage_roles` في ذلك النطاق. يمكن للـprincipal نفسه امتلاك تسجيل نشط واحد لكل tenant؛ اختر scope واسعًا أو محددًا حسب سياسة المنشأة.
4. أضف في secret manager الخاص بالنشر فقط: `SUPABASE_SERVICE_ROLE_KEY` و`CRON_SECRET` عشوائيًا بطول 16 محرفًا على الأقل، بلا مسافات أو فواصل، و`INVENTORY_RESERVATION_EXPIRY_AUTOMATION_PRINCIPAL_ID` و`NEXT_PUBLIC_SUPABASE_URL`. اضبط اختياريًا `INVENTORY_RESERVATION_EXPIRY_BATCH_LIMIT` بين 1 و1000 و`INVENTORY_RESERVATION_EXPIRY_MAX_BATCHES`؛ حاصل ضربهما لا يتجاوز 1000 وتكون القيمتان الافتراضيتان 100 و10.
5. انشر التطبيق بعد تأكيد أن Vercel project root هو `apps/web` كي يقرأ `apps/web/vercel.json`. يستدعي Vercel route يوميًا عند 02:00 UTC ويرسل `CRON_SECRET` تلقائيًا في Authorization. في الاستضافة الداخلية، شغّل GET إلى المسار نفسه بالـBearer secret من scheduler خادمي فقط.
6. راقب كل invocation: النجاح يعيد `processed` و`batches` و`drainLimitReached` فقط؛ أي 401 أو 503 يعني توقفًا آمنًا بلا expiry effect. عند `drainLimitReached=true` يبقى backlog محتملًا ويجب تنبيه المشغل ومتابعة invocation لاحق؛ Vercel Cron لا يعيد المحاولة تلقائيًا. لا تعالج الخطأ بتمرير UUID بشري أو بتجاوز route مباشرة.

للتراجع التشغيلي: عطّل Cron Job أولًا أو أوقف scheduler الداخلي، ثم أزل/أدر `CRON_SECRET` من مخزن الأسرار. لا تحذف migration مطبقة ولا تعدل سجل identity. إذا كان principal معرضًا للخطر، عطّله بواسطة `public.deactivate_automation_identity(identity, administrator, reason)` من service-role موثوق، أنشئ principal جديدًا، سجله، حدّث UUID السري، ثم فعّل scheduler بعد التحقق. تظل الحجوزات المنتهية مستبعدة زمنيًا من ATP حتى أثناء توقف materialization، لكن يجب مراقبة التراكم. لا تستخدم Instant Rollback في Vercel باعتباره تعطيلًا للـCron؛ عطّل job صراحةً في منصة التشغيل قبل أو أثناء التراجع.
