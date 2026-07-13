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
