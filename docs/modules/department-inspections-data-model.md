# نموذج بيانات تفتيش الأقسام المقترح

النماذج TypeScript في `@healthcare/inspections`: `InspectionTemplate` و`InspectionTemplateVersion` و`InspectionSection` و`InspectionQuestion` و`InspectionAnswerOption` و`InspectionSession` و`InspectionResponse` و`InspectionFinding` و`InspectionEvidence` و`InspectionScore`، مع `Facility` و`Department` و`Inspector` من عقود المنصة و`ApprovalStatus`. كل سجل تشغيلي يحمل `tenantId` و`organizationId` و`facilityId` عند الحاجة.

القالب المنشور غير قابل للتحرير؛ تعديله ينشئ Draft version. الأسئلة تدعم الأنواع المطلوبة، الوزن، السؤال الحرج، N/A، التعليق والدليل والمالك وتاريخ الاستحقاق عند الفشل. لا توجد Migrations أو Schema إنتاجية في هذا الطور.

## قواعد النقاط

تحسب إجابة السؤال من `answer score × question weight`، ثم تطبق أوزان الأقسام. تستبعد N/A من المقام، وتعرض raw وpercentage وsection scores مقربة إلى منزلتين. يفشل التفتيش إذا لم يحقق passing score أو فشل سؤال حرج. mappings قابلة للضبط عبر خيارات الإجابة؛ partial compliance التجريبي يساوي 50%.

N/A صالح فقط إذا كان `allowNotApplicable` صحيحًا؛ وإلا يرمي محرك النقاط خطأ تحقق ولا يستبعد السؤال بصمت. السؤال الاختياري غير المجاب لا يدخل المقام. القيم الرقمية السالبة مرفوضة، والقيمة الأعلى من `maxScore` تُقص إلى الحد الأعلى قبل الحساب. لا تنشأ مخالفة لسؤال حرج مطابق؛ تنشأ فقط لإجابة `isFailure` أو `createsFinding`.
