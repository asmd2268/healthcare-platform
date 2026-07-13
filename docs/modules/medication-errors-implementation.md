# تنفيذ وحدة أخطاء الدواء

## النطاق المنفذ

تضيف الوحدة عقودًا مستقلة للبلاغات والمسودات والحالات وNCC MERP والمراحل والدرجة وعوامل المساهمة والمراجعات والتعليقات والمرفقات وtimeline وCAPA والإشعارات والاستيراد/التصدير. واجهات Dashboard والبلاغ والتقارير ثنائية اللغة وتعمل RTL/LTR من Shell.

يحمل migration `202607130004_medication_errors_foundation.sql` جداول التقارير والمراجعات والتعليقات والمرفقات والـtimeline والإعدادات وروابط CAPA، مع tenant/organization/facility وRLS وصلاحيات granular. المحتوى السريري الحر لا يترجم تلقائيًا.

## الحدود المتبقية

تخزين الصور والملفات، روابط signed، الإشعارات الفعلية، CAPA الفعلي، import/export وPDF/Excel، saved filters الدائمة، والتقارير التشغيلية المجمعة تحتاج adapter وخدمات خلفية معتمدة؛ لا تدعي الواجهة التجريبية أنها منفذة. لا توجد بيانات مرضى أو أدوية حقيقية.

## سلامة السجل والتصنيف

بعد الإرسال، لا تعدل الحقول السريرية أو نطاق السجل أو المبلّغ أو الرقم المرجعي مباشرة. التعديل المادي يمر عبر revision خاضع لصلاحية ومبرر وsnapshot وتاريخ زمني. مراجعات reviewer/manager/quality/pharmacy هي ملاحظات workflow مقيدة بصلاحية review؛ لا تعد بديلاً عن revision عند تغيير حقيقة سريرية. تصنيف NCC MERP من A إلى I محفوظ كاختيار صريح ويحتاج مراجعة المنشأة؛ لا يستنتجه النظام تلقائيًا من outcome أو risk score.

مسودات المبلّغ خاصة به داخل نطاقه؛ لا تمنح صلاحية view للمراجع وصولًا تلقائيًا إلى مسودة. localStorage مسموح فقط في demonstration mode بلا Supabase وبلا production؛ عند توفر persistence أو production تفشل واجهة المسودة مغلقة حتى تتوفر خدمة خادمية آمنة.

## التحكم بالاعتماد والتعيين والملاحظات

ينشئ `revise_medication_error` snapshot كاملًا قبل تعديل allowlist سريري صريح، ويتطلب reason وصلاحية review ولا يقبل JSON عامًا. لا تزيد transitions revision السريري. ينتقل المراجع إلى `awaiting_approval`، ثم يعتمد صاحب `medication_errors.approve` فقط إلى `approved` مع `approved_by` و`approved_at`؛ لا يغلق التقرير قبل اعتماد ثم verification وclosure notes. التعيين يمر عبر `assign_medication_error` بصلاحية assign وفحص نطاق العضوية وسبب إعادة التعيين. reviewer/pharmacy notes تتطلب review، وmanager/quality notes تتطلب approve، وتكتب عبر دالة منفصلة مع timeline.
