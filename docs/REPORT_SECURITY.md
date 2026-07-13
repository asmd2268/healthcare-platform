# أمن التقارير

كل تعريف ونسخة وتشغيل وتصدير يحمل tenant/organization/facility. RLS و`can_report` يطلبان مستخدمًا مصادقًا ونطاقًا صحيحًا وصلاحية مخصصة. القراءة محصورة بالإصدارات المنشورة؛ التحرير والنشر والتصدير والجدولة تتطلب صلاحيات مستقلة. لا يمنح Widget أو Saved Report وصولًا إضافيًا للبيانات.

لا تحفظ exports في الواجهة ولا تصدر حقولًا سرية دون adapter خادمي يطبق data minimization وسجل تدقيق. الجداول كبيرة الحجم تستخدم pagination حدّها 200 سجل، ويفرض التنفيذ المستقبلي filtering قبل aggregation، فهارس زمن/نطاق، read models أو materialized views، cache per-scope قصير العمر، وحدود rate/query.
