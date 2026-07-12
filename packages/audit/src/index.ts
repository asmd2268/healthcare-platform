export type AuditEvent = {id: string; actorId?: string; organizationId: string; module: string; action: string; recordType: string; recordId: string; occurredAt: string; previousValue?: unknown; newValue?: unknown; reason?: string; sessionId?: string; ipAddress?: string; undoSupported: boolean};
export type AuditWriter = {record(event: AuditEvent): Promise<void>};
