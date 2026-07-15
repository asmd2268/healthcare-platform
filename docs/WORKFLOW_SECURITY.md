# أمن Workflow

لا تقبل transitions أو actions أو conditions عبارات SQL أو JavaScript. تتحقق transition من permission والحقول والسبب قبل تغيير الحالة. التعليقات السرية مقيدة بصلاحية مستقلة. system events وaudit/reminders/external delivery تحتاج trusted server adapters؛ لا توجد credentials أو delivery حقيقية في هذا الأساس.
# CAPA integration

CAPA lifecycle transitions are controlled server-side and may be bound to published Workflow Engine definitions through `workflow_instance_id`. CAPA does not add a second workflow runtime. Creator approval, owner closure, action verification, override, scope, and audit checks remain enforced by CAPA controlled functions and future Workflow adapters.
