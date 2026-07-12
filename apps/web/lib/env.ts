import {z} from 'zod';

const publicSchema = z.object({
  NEXT_PUBLIC_SUPABASE_URL: z.string().url().optional(),
  NEXT_PUBLIC_SUPABASE_ANON_KEY: z.string().min(1).optional()
});

export const publicEnvironment = publicSchema.parse({
  NEXT_PUBLIC_SUPABASE_URL: process.env.NEXT_PUBLIC_SUPABASE_URL,
  NEXT_PUBLIC_SUPABASE_ANON_KEY: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
});

export const hasSupabasePublicConfig = Boolean(publicEnvironment.NEXT_PUBLIC_SUPABASE_URL && publicEnvironment.NEXT_PUBLIC_SUPABASE_ANON_KEY);

export function requireServerEnvironment() {
  return z.object({
    SUPABASE_SERVICE_ROLE_KEY: z.string().min(1),
    DATABASE_URL: z.string().url().optional()
  }).parse({SUPABASE_SERVICE_ROLE_KEY: process.env.SUPABASE_SERVICE_ROLE_KEY, DATABASE_URL: process.env.DATABASE_URL});
}
