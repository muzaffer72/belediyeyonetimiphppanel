import { createClient } from '@supabase/supabase-js';
import * as schema from "./schema";

// Parse Supabase URL to get the base URL without the path part
const parseSupabaseUrl = (url: string): string => {
  // Remove /rest/v1 or /rest/v1/ if present
  return url.replace(/\/rest\/v1\/?$/, '');
};

// Environment variables for Supabase connection
const supabaseFullUrl = process.env.SUPABASE_URL || "https://bimer.onvao.net:8443/rest/v1/";
const supabaseUrl = parseSupabaseUrl(supabaseFullUrl);
const supabaseServiceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY || "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyAgCiAgICAicm9sZSI6ICJzZXJ2aWNlX3JvbGUiLAogICAgImlzcyI6ICJzdXBhYmFzZS1kZW1vIiwKICAgICJpYXQiOiAxNjQxNzY5MjAwLAogICAgImV4cCI6IDE3OTk1MzU2MDAKfQ.DaYlNEoUrrEn2Ig7tqibS-PHK5vgusbcbo7X36XVt4Q";

if (!supabaseUrl || !supabaseServiceRoleKey) {
  console.error("Supabase URL ve Service Role Key değerleri eksik. Lütfen ortam değişkenlerini kontrol edin.");
}

console.log("Supabase bağlantısı kuruluyor:", { 
  url: supabaseUrl,
  original: supabaseFullUrl
});

// Options for Supabase client
const supabaseOptions = {
  auth: {
    autoRefreshToken: false,
    persistSession: false
  }
};

// Create Supabase client with service role key for admin access
export const supabase = createClient(supabaseUrl, supabaseServiceRoleKey, supabaseOptions);

// Helper function for closing connection
export const closeConnection = async () => {
  // No actual connection to close with Supabase REST client
  return;
};

// Export db for compatibility with existing code
export const db = supabase;
