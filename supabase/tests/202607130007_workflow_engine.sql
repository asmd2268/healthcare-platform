-- Behavioral SQL scenarios for a disposable Supabase test project only.
-- The staging runner must create users, memberships, roles, a published workflow version and an instance,
-- then set request.jwt.claim.sub / request.jwt.claim.role for each actor.  Never run against production.
-- Each `raises` assertion below is executable in pgTAP (or can be translated to a DO/EXCEPTION block).
begin;
select plan(20);
-- approval: out-of-scope, requester self-approval, duplicate votes, and order/modes
select throws_ok($$ select public.request_workflow_approval(:instance,'parallel',array[:outside_user],:requester) $$,'Approval approver is out of scope','cross-scope approver denied');
select throws_ok($$ select public.request_workflow_approval(:instance,'single',array[:requester],:requester) $$,'Requester self-approval denied','self approval denied');
select throws_ok($$ select public.approve_workflow_request(:already_approved,null) $$,'Approval denied','duplicate vote denied');
select throws_ok($$ select public.approve_workflow_request(:sequential_second,null) $$,'Sequential approval is not ready','sequential order enforced');
select lives_ok($$ select public.approve_workflow_request(:parallel_one,null) $$,'parallel vote accepted');
select lives_ok($$ select public.approve_workflow_request(:any_one,null) $$,'any-one vote accepted');
select lives_ok($$ select public.approve_workflow_request(:unanimous_one,null) $$,'unanimous vote recorded');
select lives_ok($$ select public.reject_workflow_request(:rejectable,'not acceptable') $$,'rejection recorded');
select lives_ok($$ select public.request_workflow_changes(:changeable,'supply evidence') $$,'changes request recorded');
-- tasks: assignment scope, completion, verification, reopen reason and no direct mutation
select throws_ok($$ select public.assign_workflow_task(:task,:outside_user,null) $$,'Task assignment denied','cross-tenant assignee denied');
select lives_ok($$ select public.complete_workflow_task(:assigned_task,'evidence complete') $$,'assignee completes task');
select lives_ok($$ select public.verify_workflow_task(:pending_task) $$,'authorized verifier verifies task');
select throws_ok($$ select public.reopen_workflow_task(:completed_task,'') $$,'Task reopen denied','reopen needs reason');
select throws_ok($$ update public.workflow_tasks set status='completed' where id=:open_task $$,'Workflow task mutation requires a controlled function','direct task update denied');
-- transition: attachment/approval/conditions/lock fail closed until a trusted module adapter provides facts
select throws_ok($$ select public.transition_workflow_instance(:attachment_instance,'next','reason','comment') $$,'Transition requires trusted record facts adapter','required attachment denied without trusted fact');
select throws_ok($$ select public.transition_workflow_instance(:approval_instance,'next','reason','comment') $$,'Transition approval required','required approval denied');
select throws_ok($$ select public.transition_workflow_instance(:condition_instance,'next','reason','comment') $$,'Workflow condition failed','allowlisted condition failure denied');
select throws_ok($$ select public.transition_workflow_instance(:locked_instance,'next','reason','comment') $$,'Workflow transition denied','locked instance denied');
-- comment confidentiality, escalation interval, and forged events
select throws_ok($$ select public.add_workflow_comment(:instance,'secret','confidential') $$,'Workflow comment denied','confidential comment permission enforced');
select throws_ok($$ select public.escalate_workflow_instance(:recently_escalated,60) $$,'Workflow escalation denied','minimum escalation interval enforced');
select throws_ok($$ insert into public.workflow_events(instance_id,tenant_id,organization_id,facility_id,kind,action) select id,tenant_id,organization_id,facility_id,'system','forged' from public.workflow_instances where id=:instance $$,'Workflow events require a controlled function','event forgery denied');
select * from finish();
rollback;
