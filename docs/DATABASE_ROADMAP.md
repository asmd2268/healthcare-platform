# خارطة طريق قاعدة البيانات

## المبادئ

PostgreSQL عبر Supabase هو الخيار الأول، خلف طبقة وصول بيانات قابلة للنقل من/إلى Firebase. تستخدم Migrations فقط؛ لا تعديل مباشر لبيانات الإنتاج، ولا حذف أو إعادة تسمية مدمرة بلا نسخة احتياطية وخطة تراجع واختبار ببيانات غير حقيقية. كل جدول تشغيلي معزول بالمستأجر ويملك معرفًا ثابتًا وطوابع زمنية وحالة وأثرًا تدقيقيًا مناسبًا.

## مراحل النموذج

| المرحلة | نطاق البيانات | الاعتمادات | بوابة القبول |
| --- | --- | --- | --- |
| A. عقود البيانات | اصطلاحات المعرفات، tenant isolation، soft delete/archival، timestamps، ownership، وطبقة الوصول. | قرارات العزل والاحتفاظ. | مراجعة مخطط، اختبارات عزل tenant، ومثال Migration قابل للتراجع. |
| B. النواة | organizations، facilities، branches، users، memberships، roles/permissions، sessions/devices، language preferences، branding، licenses/entitlements. | A. | لا يمكن الوصول عبر منشأة؛ تفضيل اللغة مستقل؛ استحقاق الوحدة يتحقق خلفيًا. |
| C. الخدمات المشتركة | audit events، attachments/versioning، notifications/preferences، tasks، comments/confidentiality، saved filters، import/export jobs. | B. | أثر قبل/بعد عند السماح، ملفات خاصة بروابط مؤقتة، وسجل استيراد/تصدير قابل للتدقيق. |
| D. الجودة | CAPA، inspection templates/versions/sections/questions/options، inspections/responses/evidence/signatures. | B–C. | نسخة القالب لا تتغير بعد الاستخدام؛ CAPA يرتبط بمصدره؛ أوزان وأسئلة حرجة قابلة للتحقق. |
| E. السلامة والوثائق | medication errors/feedback/RCA/actions، policies/documents/versions/translations/acknowledgments. | B–D. | البلاغات تدعم السرية/المجهول والتدقيق؛ روابط ترجمة السياسة وإصداراتها سليمة. |
| F. الصيدلية والموظفون | trolley locations/drawers/items/batches/history، floor-stock requests/dispensing/limits، recalls/actions، employee credentials/schedules/leave. | B–C ونتائج الإرث. | كل Migration قديم جرى على نسخة وتجتاز اختبارات قبول وموازنة counts. |
| G. القراءة والتكامل | نماذج تقارير مجمعة عند الحاجة، فهارس بحث ثنائي اللغة، outbox/integration records. | استقرار E–F. | التقارير لا تتجاوز الصلاحيات؛ البحث/الفرز عربي وإنجليزي؛ إعادة تشغيل التكامل آمنة. |

## التعدد اللغوي والبحث

تدعم كل النصوص Unicode كاملًا. لغة الواجهة تفضيل مستخدم وليست لغة سجل. تستخدم حقول `*_ar` و`*_en` فقط للمحتوى الرسمي الذي يحتاج عرضًا بلغتين؛ أما النصوص السريرية أو الحرة فتبقى بلغتها الأصلية ولا تترجم تلقائيًا. تُصمم الفهارس والبحث للعناوين والكلمات المفتاحية والمحتوى المتاح وأرقام السجلات بالعربية والإنجليزية، مع اختبار الفرز وnormalization وقابلية إضافة المرادفات لاحقًا.

## قواعد التنفيذ والاختبار

كل Migration يتضمن: وصف الأثر، توافقًا خلفيًا، backup/restore، خطة تراجع، تحقق بيانات بعد التنفيذ، واختبار migration وpermission وtenant isolation. تفضّل تغييرات توسعية متوافقة ثم تعبئة بيانات اختيارية ثم تحويل القراءة ثم إزالة مؤجلة بعد نافذة مراقبة؛ ولا تُفترض ترجمة محتوى قائم أثناء التعبئة.

