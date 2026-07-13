# قاعدة بيانات Workflow

تضيف migration `202607130007_shared_workflow_engine.sql` جداول definitions/versions/instances/events/tasks/approvals/comments/reminders بنطاق tenant/organization/facility وRLS. events append-only للمستخدم العادي، ولا يوجد policy يسمح بكتابة system event مباشرة. يجب أن تستخدم الدوال الخادمية المقيدة للبدء والانتقال والتعيين والاعتماد والتصعيد عند اكتمال طبقة التشغيل.

تضيف migration `202607130010_complete_workflow_runtime_safeguards.sql` حواجز direct-mutation ودوال approval/task/comment/escalation المقيدة. تغطي اختبارات SQL السلوكية السيناريوهات المطلوبة في `supabase/tests/202607130007_workflow_engine.sql`، لكنها تتطلب مشروع Supabase disposable وpgTAP/runner يهيئ المستخدمين والنطاقات؛ لم تُشغّل في هذه الشجرة محليًا ما لم يتوفر ذلك المشروع والـCLI.
