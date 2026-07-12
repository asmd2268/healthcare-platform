export type WorkflowTransition = {from: string; to: string; permission?: string; requiresComment?: boolean};
export type WorkflowDefinition = {key: string; states: readonly string[]; transitions: readonly WorkflowTransition[]};
export type WorkflowAssignment = {assigneeId: string; dueAt?: string; escalationAt?: string};
