export function projectRefFromUrl(value:string):string;
export function validateSupabaseTarget(environment:Record<string,string|undefined>,action?:string):{projectRef:string;stage:string;action:string;overridden:boolean};
