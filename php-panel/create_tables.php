<?php
// Yapılandırma dosyasını yükle
require_once(__DIR__ . '/config/config.php');
require_once(__DIR__ . '/includes/functions.php');

/**
 * SQL table creation script for officials tables
 */

$create_officials_table = "
CREATE TABLE IF NOT EXISTS officials (
    id SERIAL PRIMARY KEY,
    user_id UUID NOT NULL,
    city_id INTEGER NOT NULL,
    district_id INTEGER,
    title VARCHAR(255),
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES auth.users (id) ON DELETE CASCADE,
    FOREIGN KEY (city_id) REFERENCES cities (id) ON DELETE CASCADE,
    FOREIGN KEY (district_id) REFERENCES districts (id) ON DELETE SET NULL
);

-- Add table for post resolution tracking
CREATE TABLE IF NOT EXISTS post_resolutions (
    id SERIAL PRIMARY KEY,
    post_id INTEGER NOT NULL,
    official_id INTEGER NOT NULL,
    resolution_type VARCHAR(50) NOT NULL, -- 'in_progress', 'solved', 'rejected'
    resolution_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    notes TEXT,
    evidence_url TEXT,
    admin_approved BOOLEAN DEFAULT FALSE,
    admin_notes TEXT,
    admin_approval_date TIMESTAMP WITH TIME ZONE,
    FOREIGN KEY (post_id) REFERENCES posts (id) ON DELETE CASCADE,
    FOREIGN KEY (official_id) REFERENCES officials (id) ON DELETE CASCADE
);
";

// SQL çalıştır
runSQL($create_officials_table);

echo "Tables created successfully!";

/**
 * SQL çalıştırma fonksiyonu
 */
function runSQL($sql) {
    try {
        // Supabase URL ve key
        $supabase_url = getenv('SUPABASE_URL');
        $supabase_key = getenv('SUPABASE_SERVICE_ROLE_KEY');
        
        if (!$supabase_url || !$supabase_key) {
            die("Supabase credentials not found in environment variables.");
        }
        
        // PostgreSQL connection URL
        $db_url = getenv('DATABASE_URL');
        
        if (!$db_url) {
            die("DATABASE_URL not found in environment variables.");
        }
        
        // Parse the connection URL
        $db_parts = parse_url($db_url);
        $db_host = $db_parts['host'];
        $db_port = $db_parts['port'];
        $db_name = ltrim($db_parts['path'], '/');
        $db_user = $db_parts['user'];
        $db_pass = $db_parts['pass'];
        
        // Create connection
        $conn = pg_connect("host=$db_host port=$db_port dbname=$db_name user=$db_user password=$db_pass");
        
        if (!$conn) {
            die("Connection failed: " . pg_last_error());
        }
        
        // Execute the SQL query
        $result = pg_query($conn, $sql);
        
        if (!$result) {
            die("Query failed: " . pg_last_error($conn));
        }
        
        // Close connection
        pg_close($conn);
        
        return true;
    } catch (Exception $e) {
        die("Error: " . $e->getMessage());
    }
}