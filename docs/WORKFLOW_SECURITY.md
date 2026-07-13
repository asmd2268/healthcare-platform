# أمن Workflow

لا تقبل transitions أو actions أو conditions عبارات SQL أو JavaScript. تتحقق transition من permission والحقول والسبب قبل تغيير الحالة. التعليقات السرية مقيدة بصلاحية مستقلة. system events وaudit/reminders/external delivery تحتاج trusted server adapters؛ لا توجد credentials أو delivery حقيقية في هذا الأساس.
