# محرك سير العمل المشترك

محرك مستقل قابل لإعادة الاستخدام للوحدات الحالية والمستقبلية. يوفر definition/version/state/transition/condition/action/assignment/approval/SLA/escalation/instance/event/task/comment/reminder بعقود TypeScript وmigration مشتركة. الشروط والإجراءات allowlisted ولا تسمح JavaScript أو SQL من المتصفح.

الإصدار المنشور immutable؛ تحريره يبدأ draft version عميق النسخ. الحسابات التقويمية للأعمال والتوصيل الخارجي للإشعارات placeholders حتى adapter وخدمات معتمدة.

## Runtime safeguards

All approval, task, comment, escalation, and state mutations use controlled server-side database functions. They lock the affected row, require an authenticated actor, verify permission plus tenant/organization/facility scope, and append a trusted workflow event in the same transaction. Direct client writes to system events, instance state/assignee/lock, approval decisions, and task status/verification are rejected.

Approval modes are `single`, `sequential`, `parallel`, `any_one`, and `unanimous`. Sequential approvals unlock strictly in sequence; parallel and unanimous complete only after all configured voters approve; any-one completes on the first valid vote. Rejection and changes-requested are explicit terminal decisions for that approval request. A requester cannot self-approve when the definition configures a distinct actor.

Transition reason and comment are user-entered audit context only. They are not accepted as evidence of business-record completion. A small allowlisted evaluator supports only instance state/lock/due-date, approval status, and task status; unknown fields or operators are rejected. Transitions requiring module record fields, attachments, or role facts fail closed until a reviewed trusted-record-facts adapter is supplied. This is intentional: dynamic SQL, executable expressions, and client-provided JSON are not trusted. Supported runtime actions are restricted to the implemented allowlist; unsupported actions prevent a transition rather than being ignored.
