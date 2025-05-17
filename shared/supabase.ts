import { createClient } from '@supabase/supabase-js';
import { drizzle } from "drizzle-orm/postgres-js";
import postgres from "postgres";
import * as schema from "./schema";

// Get Supabase URL and Service Role Key from environment variables
const supabaseUrl = process.env.SUPABASE_URL;
const supabaseServiceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!supabaseUrl || !supabaseServiceRoleKey) {
  throw new Error("Supabase URL ve Service Role Key değerleri eksik. Lütfen ortam değişkenlerini kontrol edin.");
}

// Create Supabase client with service role key for admin access
export const supabase = createClient(supabaseUrl, supabaseServiceRoleKey, {
  auth: {
    autoRefreshToken: false,
    persistSession: false
  }
});

// For backward compatibility and existing queries, we'll keep the PostgreSQL client
// Create a connection string from environment variables with proper fallbacks
const getConnectionString = () => {
  const databaseUrl = process.env.DATABASE_URL;
  
  if (!databaseUrl) {
    throw new Error("DATABASE_URL environment variable is not set. Please set it with your Supabase connection string.");
  }
  
  return databaseUrl;
};

// Create PostgreSQL client with additional connection options for Supabase
export const client = postgres(getConnectionString(), {
  ssl: true,
  max: 5, // Limit the number of concurrent connections
  idle_timeout: 20, // Close connections after 20 seconds of inactivity
  connect_timeout: 10, // Timeout after 10 seconds when connecting
  prepare: false, // Don't use prepared statements for Supabase
});

// Create Drizzle instance with our schema
export const db = drizzle(client, { schema });

// Helper function to close the database connection
export const closeConnection = async () => {
  await client.end();
};
