import { createClient } from '@supabase/supabase-js'

// IMPORTANT: Replace with your actual Supabase credentials
// Get these from: https://supabase.com/dashboard -> Project Settings -> API
const SUPABASE_URL = 'https://your-project.supabase.co'
const SUPABASE_ANON_KEY = 'your-anon-key'

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: {
    autoRefreshToken: true,
    persistSession: true
  },
  realtime: {
    params: { eventsPerSecond: 10 }
  }
})

export async function initSupabase() {
  try {
    const { data: { session } } = await supabase.auth.getSession()
    return session !== null
  } catch (e) {
    console.warn('Supabase not configured - running in offline mode')
    return false
  }
}
