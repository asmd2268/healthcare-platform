# إدارة المنصة

أساس مشترك لمالك المنصة ومدير المنظمة ومدير المنشأة، بعقود server-side-compatible لنطاقات global/organization/facility والصلاحيات الإدارية. لا يتجاوز `platform.full_access` نطاق tenant أو organization أو facility؛ مالك المنصة فقط مع role `platform_owner` ونطاق global يصل لكل المستأجرين.

أضيف مخطط persistence و`SupabaseAdministrationRepository` خادمي مقيد بـRLS للنماذج والبيانات المرجعية. شاشات `/administration/*` ما زالت demonstration UI ولا تحوّل جميع الإجراءات إلى حفظ خلفي بعد؛ لا تدّعي imports أو exports أو الحذف الدائم تنفيذًا تشغيليًا.
