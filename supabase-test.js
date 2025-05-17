import { createClient } from '@supabase/supabase-js';

// Direct credentials as in the curl command
const supabaseUrl = 'https://bimer.onvao.net:8443';
const supabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyAgCiAgICAicm9sZSI6ICJzZXJ2aWNlX3JvbGUiLAogICAgImlzcyI6ICJzdXBhYmFzZS1kZW1vIiwKICAgICJpYXQiOiAxNjQxNzY5MjAwLAogICAgImV4cCI6IDE3OTk1MzU2MDAKfQ.DaYlNEoUrrEn2Ig7tqibS-PHK5vgusbcbo7X36XVt4Q';

// Create Supabase client
const supabase = createClient(supabaseUrl, supabaseKey, {
  auth: {
    autoRefreshToken: false,
    persistSession: false
  }
});

// Test function to query tables
async function testConnection() {
  console.log('Testing Supabase connection...');
  
  try {
    console.log('Attempting to query users table...');
    const { data: users, error: usersError } = await supabase.from('users').select('count', { count: 'exact', head: true });
    
    if (usersError) {
      console.error('Error querying users:', usersError);
    } else {
      console.log('Users query successful:', users);
    }
    
    console.log('Attempting to query cities table...');
    const { data: cities, error: citiesError } = await supabase.from('cities').select('count', { count: 'exact', head: true });
    
    if (citiesError) {
      console.error('Error querying cities:', citiesError);
    } else {
      console.log('Cities query successful:', cities);
    }
    
    // Try a basic fetch
    console.log('Attempting direct fetch...');
    const fetchResponse = await fetch(`${supabaseUrl}/users?select=count`, {
      method: 'GET',
      headers: {
        'Content-Type': 'application/json',
        'apikey': supabaseKey,
        'Authorization': `Bearer ${supabaseKey}`
      }
    });
    
    const fetchData = await fetchResponse.json();
    console.log('Fetch response:', fetchData);
    
  } catch (error) {
    console.error('Test connection failed:', error);
  }
}

// Run the test
testConnection();