# الإجراءات التصحيحية والوقائية (CAPA)

## المعمارية

CAPA قدرة مشتركة مستقلة عن أي وحدة مصدر. تضيف migration `202607130021_shared_capa_management_foundation.sql` سجلات CAPA والإجراءات والمصادر وتحليل السبب الجذري ومراجعات الفاعلية وطلبات تمديد الموعد والتعيينات والتعليقات والأدلة والأحداث. تعيد استخدام tenant/organization/facility scope وReference Data وWorkflow وReporting وAudit؛ لا تنشئ محركًا ثانيًا.

يدعم المصدر اليدوي وMedication Errors وPolicies المتاحين حاليًا. يرفض adapter أي مصدر غير منفذ. توجد عقود لاحقة لـDepartment Inspections وDrug Recalls وFloor Stock وNarcotics وCrash Cart وPharmacy Trolley والتحويلات والحيازة؛ يجب أن تتحقق من وجود المصدر ونطاقه وصلاحية المنشئ قبل الربط.

## lifecycle والصلاحيات

الحالات هي Draft وSubmitted وUnder Review وApproved وIn Progress وPending Evidence وPending Effectiveness Review وEffective/Ineffective وReopened وCompleted وClosed وRejected وCancelled وOverdue وArchived. الانتقالات من دوال خادمية مقيدة فقط. CAPA creator لا يعتمد سجلَه، والمالك لا يغلق سجلَه منفردًا؛ override يتطلب صلاحية صريحة مسجلة.

كل صلاحيات `capa.*` تمنح Platform Owner فقط افتراضيًا. النوع والتصنيف والأولوية والخطر والشدة ومنهج RCA ونوع action وقواعد الموعد والترقيم والاحتفاظ Reference Data/Platform Administration، لا قوائم ثابتة.

## RCA، الفاعلية، والاستحقاقات

تحفظ RCA method وproblem statement والعوامل والأسباب والنتيجة والمشاركين والمراجعة؛ لا توجد graphical editors. مراجعات الفاعلية append-only، ولا يغلق CAPA لمجرد اكتمال الإجراءات. ineffective أو reopen decision يعيد فتح السجل مع الحفاظ على التاريخ. تمديد التاريخ يتطلب request/approval مؤرشفًا؛ لا يوجد تعديل صامت للموعد.

## الأدلة والواجهة والتأجيلات

الأدلة metadata فقط في PostgreSQL وملفات في private Supabase Storage. قبل تمكين الرفع، يجب استخراج service مشترك من trusted upload authorization وchecksum verification وmalware scan وsigned URL وtwo-phase deletion الذي تستخدمه Policies؛ لا تنسخ CAPA مفاتيح أو Storage credentials. لا تخزن الملفات في قاعدة البيانات ولا تحذف أدلة CAPA المغلقة/المحتفظ بها.

الواجهة الحالية عربية/إنجليزية وRTL/LTR وهي demonstration-only صراحة. القوائم ولوحات CAPA والعرض والتفاصيل والإجراءات وRCA والفاعلية لا تنفذ lifecycle من المتصفح. تعريفات reporting/dashboard الابتدائية تقيس المفتوح والمتأخر والمصادر والمنشأة والقسم والمالك والخطر والحالة والوقت والإجراءات والفاعلية والتمديدات والأسباب المتكررة عند توفر trusted adapters.

## تكاملات مستقبلية

Floor Stock: discrepancies وexpiry وconditions وsignatures وwarehouse variance. Narcotics: count/balance/wastage/return/custody مع confidentiality وseparation of duties. Transfers: receipt والكمية والوجهة والشاهد وreconciliation. Custody: accountable person وalternate وhandover وtemporary custody وacknowledgement. كل adapter fail-closed ويحافظ على scope والتدقيق.
