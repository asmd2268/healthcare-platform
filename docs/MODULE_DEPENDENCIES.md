# تبعيات الوحدات

## قاعدة الحدود

الوحدات مستقلة في منطقها وصلاحياتها وملكية بياناتها ووثائقها، لكن تشترك فقط في النواة والخدمات التي يحتاجها أكثر من مستهلك واحد. لا تقرأ وحدة جداول وحدة أخرى مباشرة؛ تستخدم عقودًا موثقة أو مراجع ثابتة وعمليات خلفية مصرحًا بها.

| الوحدة | تعتمد على | تُنتج/تخدم | ملاحظات ترتيب التنفيذ |
| --- | --- | --- | --- |
| Core Platform | — | الهوية، المستأجر، RBAC، i18n، branding، licensing | شرط لكل الوحدات. |
| Shared Services | Core | audit، files، notifications، tasks، search، import/export | شرط عملي لكل سجل تشغيلي. |
| CAPA | Core + Shared Services | إجراءات قابلة لإعادة الاستخدام | يبنى قبل مستهلكيه لتجنب CAPA مخصص في كل وحدة. |
| Department Inspections | Core + Shared + CAPA | findings، tasks، CAPA، تقارير | يؤسس محرك القوالب/التقييم. |
| Crash Cart Inspections | Core + Shared + CAPA | findings وCAPA | يعيد استخدام نمط التفتيش ولا يعتمد على Pharmacy Trolley. |
| Policies & Procedures | Core + Shared | سياسات، إقرارات، مراجعات | مستقل؛ قد ينشئ CAPA فقط عبر عقد اختياري. |
| Medication Errors | Core + Shared + CAPA | بلاغ، RCA، إجراءات، Feedback | لا يعتمد على وحدة تقارير منفصلة؛ التقارير read model لاحق. |
| Medication Error Reports | Medication Errors + Reporting | اتجاهات وde-identification | يبنى بعد استقرار البلاغ وFeedback. |
| Pharmacy Trolley | Core + Shared + Legacy gates | مواقع/أدراج/أصناف/دفعات | انتقال تدريجي من الإرث فقط. |
| Floor Stock | Core + Shared + Legacy gates | طلب/صرف/حدود/دفعات | انتقال تدريجي من الإرث فقط. |
| Drug Recalls | Core + Shared؛ تكامل اختياري مع Trolley/Floor Stock | تتبع عزل/إرجاع/إتلاف | يمكن بدء الأساس مستقلًا؛ الربط مع الصيدلية لاحق. |
| Employee Management | Core + Shared + Legacy gates | موظفون/مؤهلات/جداول | يتطلب قرار خصوصية HR؛ لا يجعل كل الموظفين مستخدمين. |
| Dashboards & Reports | Core + عقود قراءة للوحدات | لوحات حسب الدور وتقارير | ينفذ بعد استقرار تعريف المقاييس ومصادرها. |

## التبعيات غير الوظيفية الإلزامية

كل وحدة تعتمد على: عزل tenant، تفويض خلفي، Audit Log، دعم Arabic/English وRTL/LTR، البحث/الفرز، المرفقات الآمنة عند الحاجة، واختبارات الجودة العشرة المحددة في Project Bible. لا تجعل التبعية الوحدة غير قابلة للبيع: CAPA والتقارير والتراخيص تقدم كقدرات مشتركة قابلة للتفعيل بعقد واضح.

## قواعد منع الدين التقني

- لا تنقل منطق CAPA أو التدقيق أو رفع الملفات إلى كل وحدة.
- لا تنفذ تكامل Drug Recalls مع تطبيقات الصيدلية قبل توثيق معرفات ومطابقة الدفعات وإعادة المحاولة.
- لا تبني لوحات من استعلامات واجهة مباشرة؛ تستند إلى عقود قراءة مصرح بها ومقاييس معرفة.
- لا تهاجر تطبيقات Legacy لمجرد توفر شاشة بديلة؛ بوابات `MIGRATION_PLAN.md` إلزامية.

