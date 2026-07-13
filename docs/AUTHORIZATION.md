# التفويض (Authorization)

كل عملية خلفية تتحقق من الهوية ثم من نطاق tenant/organization/facility ومن الصلاحية الصريحة. الدالة `requirePlatformPermission` لا تعد إخفاء عناصر الواجهة تفويضًا. مالك المنصة يصل لكل المستأجرين فقط عندما يكون الدور `platform_owner` والنطاق global وتكون assignment بلا tenant أو organization أو facility؛ `platform.full_access` وحدها لا توسع دورًا محدودًا.

الأدوار المنظمة أو المنشأة تحتاج تطابق tenant وorganization وfacility، وتفشل الطلبات بلا assignment أو صلاحية بشكل افتراضي. طبقة RLS تعيد تطبيق العزل حتى لو استدعى العميل Supabase مباشرة.

تمنح `platform.view_published_forms` عرض القوالب والإصدارات المنشورة فقط ضمن النطاق. تبقى المسودات وغير المنشور مقيدة بـ`platform.manage_forms`، الذي يلزم للإنشاء والتعديل والإصدار والنشر والأرشفة والاستعادة. لذلك يمكن لمستخدم التفتيش لاحقًا قراءة قالب منشور دون منحه صلاحيات إدارة النماذج.

يمنح المخطط هذه الصلاحية افتراضيًا إلى `organization_administrator` و`facility_administrator` و`scoped_user`، لكن RLS والتحقق من tenant ثم organization ثم facility يظلان مطلوبين. لا تمنح هذه الأدوار `platform.manage_forms` افتراضيًا.
