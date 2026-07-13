export type PolicyLanguage = 'ar' | 'en' | 'bilingual';
export type PolicyStatus = 'draft' | 'under_review' | 'approved' | 'published' | 'superseded' | 'archived';
export type PolicyScope = {tenantId: string; organizationId: string; facilityId?: string};
export type PolicyText = {ar?: string; en?: string};

export const policyPermissions = [
  'policies.view', 'policies.create', 'policies.edit', 'policies.review', 'policies.approve',
  'policies.publish', 'policies.archive', 'policies.restore', 'policies.acknowledge',
  'policies.export', 'policies.manage_configuration'
] as const;
export type PolicyPermission = (typeof policyPermissions)[number];

export type PolicyAttachment = PolicyScope & {
  id: string; policyVersionId: string; storageBucket: string; storageKey: string; checksum: string;
  mimeType: string; byteSize: number; language: PolicyLanguage; versionLabel: string;
  uploadedBy: string; uploadedAt: string; previewAvailable: boolean; extractedText?: string;
  source: 'upload' | 'word_import';
};
export type PolicyVersion = PolicyScope & {
  id: string; policyId: string; versionMajor: number; versionMinor: number; status: PolicyStatus;
  title: PolicyText; description?: PolicyText; contentLanguage: PolicyLanguage; changeSummary: string;
  effectiveDate?: string; reviewDate?: string; expiryDate?: string; keywords: string[]; tags: string[];
  approvedAt?: string; approvedBy?: string; publishedAt?: string; publishedBy?: string;
  createdBy: string; createdAt: string;
};
export type PolicyDefinition = PolicyScope & {
  id: string; policyId: string; policyNumber: string; categoryReferenceId?: string; departmentId?: string;
  ownerId: string; approverId?: string; status: PolicyStatus; currentVersionId?: string;
  title: PolicyText; related: Array<{type: 'policy' | 'form' | 'capa' | 'medication_error' | 'drug_recall'; id: string}>;
};
export type PolicySearch = Partial<PolicyScope> & {query?: string; policyNumber?: string; categoryId?: string; departmentId?: string; ownerId?: string; statuses?: PolicyStatus[]; effectiveFrom?: string; effectiveTo?: string; reviewFrom?: string; reviewTo?: string; version?: string; page: number; pageSize: number};
export type WordImportContract = {source: 'docx'; attachment: PolicyAttachment; extractedPlainText?: string; headingIndex?: Array<{level: number; text: string}>; aiParsing: 'not_implemented'};
export type PolicyNotification = {kind: 'review_due' | 'approval_requested' | 'published' | 'updated' | 'acknowledgement_overdue'; policyVersionId: string; recipientId: string; dueAt?: string};

export function createDraftPolicyVersion(policy: PolicyDefinition, published: PolicyVersion, actorId: string, changeSummary: string): PolicyVersion {
  if (policy.status !== 'published' || published.status !== 'published') throw new Error('Only a published policy can create a new draft version');
  if (!changeSummary.trim()) throw new Error('A change summary is required');
  return structuredClone({...published, id: `${published.id}-draft-${published.versionMajor}.${published.versionMinor + 1}`, status: 'draft', versionMinor: published.versionMinor + 1, changeSummary: changeSummary.trim(), createdBy: actorId, createdAt: new Date().toISOString(), approvedAt: undefined, approvedBy: undefined, publishedAt: undefined, publishedBy: undefined});
}

export function canTransitionPolicy(from: PolicyStatus, to: PolicyStatus): boolean {
  return ({draft: ['under_review', 'archived'], under_review: ['draft', 'approved', 'archived'], approved: ['draft', 'published', 'archived'], published: ['superseded', 'archived'], superseded: ['archived'], archived: []} as Record<PolicyStatus, PolicyStatus[]>)[from].includes(to);
}

export function policySearchContract(search: PolicySearch) {
  return {...search, page: Math.max(1, search.page), pageSize: Math.max(1, Math.min(200, search.pageSize)), fullTextFuture: {columns: ['title_ar', 'title_en', 'policy_number', 'keywords', 'extracted_text'], languageAware: true}};
}
