import {z} from 'zod';

export const publicEnvironmentSchema = z.object({
  NEXT_PUBLIC_SUPABASE_URL: z.string().url().optional(),
  NEXT_PUBLIC_SUPABASE_ANON_KEY: z.string().min(1).optional()
});

export const publicEnvironment = publicEnvironmentSchema.parse({
  NEXT_PUBLIC_SUPABASE_URL: process.env.NEXT_PUBLIC_SUPABASE_URL,
  NEXT_PUBLIC_SUPABASE_ANON_KEY: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
});

export const hasSupabasePublicConfig = Boolean(publicEnvironment.NEXT_PUBLIC_SUPABASE_URL && publicEnvironment.NEXT_PUBLIC_SUPABASE_ANON_KEY);

export const serverUserEnvironmentSchema = z.object({DATABASE_URL: z.string().url().optional()});
export const adminEnvironmentSchema = z.object({SUPABASE_SERVICE_ROLE_KEY: z.string().min(1)});
export const serverUserEnvironment = serverUserEnvironmentSchema.parse({DATABASE_URL: process.env.DATABASE_URL});
export const requireAdminEnvironment = () => adminEnvironmentSchema.parse({SUPABASE_SERVICE_ROLE_KEY: process.env.SUPABASE_SERVICE_ROLE_KEY});
