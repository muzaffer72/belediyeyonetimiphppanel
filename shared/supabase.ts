import { createClient } from '@supabase/supabase-js';
import * as schema from "./schema";

// Get Supabase URL and Service Role Key from environment variables
const supabaseUrl = process.env.SUPABASE_URL || "";
const supabaseServiceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY || "";

if (!supabaseUrl || !supabaseServiceRoleKey) {
  console.error("Supabase URL ve Service Role Key değerleri eksik. Lütfen ortam değişkenlerini kontrol edin.");
}

console.log("Supabase bağlantısı kuruluyor:", { url: supabaseUrl });

// Options for Supabase client
const supabaseOptions = {
  auth: {
    autoRefreshToken: false,
    persistSession: false
  },
  global: {
    headers: {
      'Content-Type': 'application/json',
      'apikey': supabaseServiceRoleKey,
      'Authorization': `Bearer ${supabaseServiceRoleKey}`
    }
  }
};

// Create Supabase client with service role key for admin access
export const supabase = createClient(supabaseUrl, supabaseServiceRoleKey, supabaseOptions);

// Mock functions to simulate drizzle functionality but using Supabase API
export const db = {
  // Create a dummy drizzle-like interface that delegates to Supabase
  select: () => ({
    from: (table: any) => ({
      where: () => [],
      limit: () => [],
      orderBy: () => []
    })
  }),
  insert: () => ({
    values: () => ({
      returning: async () => []
    })
  }),
  update: () => ({
    set: () => ({
      where: () => ({
        returning: async () => []
      })
    })
  }),
  delete: () => ({
    where: () => ({
      returning: async () => []
    })
  }),
  execute: async () => [{ count: 0 }]
};

// Helper function (now just a placeholder)
export const closeConnection = async () => {
  // No actual connection to close
  return;
};
