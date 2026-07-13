import type {MedicationErrorReport} from '@healthcare/medication-errors';
const scope={tenantId:'demo-tenant',organizationId:'demo-organization',facilityId:'demo-facility'};
export const demoMedicationError:MedicationErrorReport={...scope,id:'medication-error-1',referenceNumber:'ME-DEMO-001',status:'draft',revision:1,incidentType:'near_miss',severity:'moderate',medicationStage:'dispensing',occurredAt:'2026-07-13T08:00:00Z',reportedAt:'2026-07-13T09:00:00Z',reportedBy:'demo-reporter',title:'',description:'',contributingFactors:[],errorCategories:[],riskScore:0,assignment:{},attachments:[],comments:[]};
export interface MedicationErrorRepository{list():Promise<MedicationErrorReport[]>;saveDraft(report:MedicationErrorReport):Promise<MedicationErrorReport>}
export const medicationErrorRepository:MedicationErrorRepository={async list(){return [demoMedicationError]},async saveDraft(report){return {...report}}};
