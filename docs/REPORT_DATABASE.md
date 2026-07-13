# قاعدة بيانات التقارير

migration `202607130011_reporting_and_analytics_engine.sql` تضيف `report_definitions`, `report_versions`, `dashboard_definitions`, `dashboard_widgets`, `saved_reports`, `report_runs`, و`report_exports`. التغيير additive فقط؛ لا يعدل dashboards الوحدات القائمة.

الإصدارات المنشورة immutable، وconstraints/triggers تمنع اختلاف نطاق report version أو dashboard widget عن parent. RLS افتراضي مغلق ويعزل tenant/organization/facility؛ التشغيل والملف الناتج يملكه صاحب الطلب المصرح له. قبل تفعيل SQL في Staging يجب تشغيل سيناريوهات RLS في مشروع Disposable؛ لم تُشغّل اختبارات SQL الحية في هذه البيئة.
