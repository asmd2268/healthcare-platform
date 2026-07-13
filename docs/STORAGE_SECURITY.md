# أمن تخزين المستندات (Storage Security)

## مستندات السياسات

ينشئ أساس Policies & Procedures bucket خاصًا باسم `policy-documents`. لا يكون Public، ولا توجد سياسة قراءة أو كتابة عامة. يحتفظ PostgreSQL بالـmetadata فقط، وليس binary data.

صيغة المفتاح الآمن هي:

```text
tenant/{tenant_id}/organization/{organization_id}/facility/{facility_id-or-global}/policies/{policy_definition_id}/versions/{policy_version_id}/{uuid}-{sanitized_filename}
```

تتحقق سياسة Storage من المسار مقابل نسخة السياسة والنطاق الفعليين؛ لا تثق بمعرفات يرسلها المتصفح وحدها. يسمح بالرفع لصاحب `policies.edit` إلى نسخة draft فقط. لا توجد سياسة update أو delete، لذلك لا يوجد arbitrary overwrite ولا حذف مباشر لمستند منشور.

## عقد الخدمة الخادمية

لا تعيد الواجهة Storage credentials أو `storage_key` غير مقيد. الخدمة الخادمية فقط تنفذ authorize upload، finalize metadata، verify checksum/size، وتصدر signed download/preview URL قصير العمر بعد التحقق من صلاحية النسخة. كما تتعامل مع انتهاء أو إلغاء الوصول.

DOCX extraction وPDF rendering وmalware scanning مؤجلة لخدمة خادمية؛ المتصفح لا يحلل الملفات ولا يشغل macros. ترفض `docm` و`xlsm` و`pptm`. OCR وAI extraction غير منفذين، ويجب فحص malware قبل الإنتاج.

لا يسمح للمستعرض باستدعاء finalization مباشرة. ينشئ المستخدم authorization قصير العمر للنسخة draft فقط، وترفع سياسة Storage إلى المفتاح المعتمد، ثم تتحقق خدمة موثوقة من وجود object وحجمه ومساره والرافع وحالة الفحص قبل إدراج metadata. لا يستطيع SQL وحده إعادة حساب checksum للمحتوى، لذلك لا تتم المطابقة إلا في trusted worker. ولا توجد Storage UPDATE أو DELETE policy: حذف مسودة يمر بخدمة خادمية مقيدة، وتنظف orphan uploads غير النهائية بعد انتهاء authorization وبفترة حماية موثقة.

تربط Storage INSERT الآن بسجل authorization حي واحد: نفس `storage_key` وuploader وtenant/organization/facility والنسخة draft، مع انتهاء صالح وعدم finalization. لا يكفي أن يخمّن محرر مسارًا صحيحًا. بعد الرفع، يقارن trusted worker SHA-256 الفعلي بـ`expected_checksum` ثم يغير الحالة إلى `verified` أو `failed`؛ لا يسمح finalization إلا بـ`verified`. يلزم `malware_scan_status=accepted` في الإنتاج. يسمح staging بحالة pending فقط عندما يضبط server worker إعداد non-production موثوق، وتبقى الملفات pending مخفية عن metadata وStorage download/preview حتى القبول. تنظف المهمة الدورية authorizations المنتهية وobjects اليتيمة وفشل checksum/scan، ولا تمس مستندًا finalized أو منشورًا.

تتحقق `authorize_policy_upload` من الاسم قبل إنشاء authorization: يجب أن يكون الاسم المنظف ذا امتداد واحد فقط من PDF/DOCX/DOC/XLSX/XLS/PPTX/JPG/JPEG/PNG/WEBP، وباسم أساسي غير فارغ من أحرف وأرقام و`_` أو `-`. لذلك ترفض الملفات بلا امتداد أو بامتداد مجهول أو macro/executable أو double extension قبل أن تترك object يتيمًا.

حذف المسودة ذو مرحلتين. `prepare_draft_policy_document_deletion` يحجز document وstorage key ويكتب deletion request؛ ثم يحذف trusted server worker object من Storage. لا تستدعي `complete_draft_policy_document_deletion` إلا بعد أن تتأكد قاعدة البيانات أن object لم يعد موجودًا، وعندها فقط تحذف metadata وتسجل الحدث. إذا فشل حذف Storage تبقى metadata وrequest قابلان للاسترداد/المراجعة. تتعامل cleanup job مع authorizations المنتهية وobjects غير النهائية وفشل checksum أو malware، وتحظر نهائيًا أي document finalized أو retained.
