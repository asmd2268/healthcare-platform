# التفويض (Authorization)

كل عملية خلفية تتحقق من الهوية ثم من نطاق tenant/organization/facility ومن الصلاحية الصريحة. الدالة `requirePlatformPermission` لا تعد إخفاء عناصر الواجهة تفويضًا. مالك المنصة يصل لكل المستأجرين فقط عندما يكون الدور `platform_owner` والنطاق global وتكون assignment بلا tenant أو organization أو facility؛ `platform.full_access` وحدها لا توسع دورًا محدودًا.

الأدوار المنظمة أو المنشأة تحتاج تطابق tenant وorganization وfacility، وتفشل الطلبات بلا assignment أو صلاحية بشكل افتراضي. طبقة RLS تعيد تطبيق العزل حتى لو استدعى العميل Supabase مباشرة.
