# قاعدة بيانات Workflow

تضيف migration `202607130007_shared_workflow_engine.sql` جداول definitions/versions/instances/events/tasks/approvals/comments/reminders بنطاق tenant/organization/facility وRLS. events append-only للمستخدم العادي، ولا يوجد policy يسمح بكتابة system event مباشرة. يجب أن تستخدم الدوال الخادمية المقيدة للبدء والانتقال والتعيين والاعتماد والتصعيد عند اكتمال طبقة التشغيل.
