-- Disposable staging SQL scenarios; run only with Supabase CLI/Docker and fictional scoped users.
begin;
-- Anonymous users must receive zero report/dashboard rows.
-- A scoped user can read a published version in its tenant/organization/facility, but cannot read a draft or another scope.
-- A user without reports.export cannot read report_exports, even for an in-scope run.
-- Updating/deleting a published report_version must raise “Published report versions are immutable”.
-- Inserting a report_version or dashboard_widget with a parent from another scope must raise 23503.
rollback;
-- Migration 015 scenarios: authorized publish_report_version and publish_dashboard append audit_events;
-- authorized request_report_export appends report.export_requested; direct append_reporting_audit_event
-- and direct insert into audit_events are denied. Force the bridge to raise and verify publication/export rollback.
