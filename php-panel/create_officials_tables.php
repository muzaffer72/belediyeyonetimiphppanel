<?php
// Yapılandırma dosyasını yükle
require_once(__DIR__ . '/config/config.php');

// Tabloları oluşturmak için SQL sorgusu
$sql = "
-- Belediye görevlileri tablosu
CREATE TABLE IF NOT EXISTS officials (
    id SERIAL PRIMARY KEY,
    user_id UUID NOT NULL,
    city_id INTEGER NOT NULL,
    district_id INTEGER,
    title VARCHAR(255),
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_officials_user FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
    CONSTRAINT fk_officials_city FOREIGN KEY (city_id) REFERENCES cities(id) ON DELETE CASCADE,
    CONSTRAINT fk_officials_district FOREIGN KEY (district_id) REFERENCES districts(id) ON DELETE SET NULL
);

-- Gönderi çözüm takibi tablosu
CREATE TABLE IF NOT EXISTS post_resolutions (
    id SERIAL PRIMARY KEY,
    post_id INTEGER NOT NULL,
    official_id INTEGER NOT NULL,
    resolution_type VARCHAR(50) NOT NULL,
    evidence_url TEXT,
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    admin_approved BOOLEAN DEFAULT FALSE,
    admin_notes TEXT,
    admin_approved_at TIMESTAMP WITH TIME ZONE,
    CONSTRAINT fk_resolutions_post FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE,
    CONSTRAINT fk_resolutions_official FOREIGN KEY (official_id) REFERENCES officials(id) ON DELETE CASCADE
);

-- Gönderi tablosuna yeni alanlar ekle
ALTER TABLE posts ADD COLUMN IF NOT EXISTS city_id INTEGER;
ALTER TABLE posts ADD COLUMN IF NOT EXISTS district_id INTEGER;
ALTER TABLE posts ADD COLUMN IF NOT EXISTS status VARCHAR(50) DEFAULT 'pending';
ALTER TABLE posts ADD COLUMN IF NOT EXISTS processing_date TIMESTAMP WITH TIME ZONE;
ALTER TABLE posts ADD COLUMN IF NOT EXISTS processing_official_id INTEGER;
ALTER TABLE posts ADD COLUMN IF NOT EXISTS solution_date TIMESTAMP WITH TIME ZONE;
ALTER TABLE posts ADD COLUMN IF NOT EXISTS solution_official_id INTEGER;
ALTER TABLE posts ADD COLUMN IF NOT EXISTS solution_note TEXT;
ALTER TABLE posts ADD COLUMN IF NOT EXISTS evidence_url TEXT;
ALTER TABLE posts ADD COLUMN IF NOT EXISTS rejection_date TIMESTAMP WITH TIME ZONE;
ALTER TABLE posts ADD COLUMN IF NOT EXISTS rejection_official_id INTEGER;

-- İlişkili tabloları güncelle
ALTER TABLE posts ADD CONSTRAINT IF NOT EXISTS fk_posts_city FOREIGN KEY (city_id) REFERENCES cities(id) ON DELETE SET NULL;
ALTER TABLE posts ADD CONSTRAINT IF NOT EXISTS fk_posts_district FOREIGN KEY (district_id) REFERENCES districts(id) ON DELETE SET NULL;
ALTER TABLE posts ADD CONSTRAINT IF NOT EXISTS fk_posts_processing_official FOREIGN KEY (processing_official_id) REFERENCES officials(id) ON DELETE SET NULL;
ALTER TABLE posts ADD CONSTRAINT IF NOT EXISTS fk_posts_solution_official FOREIGN KEY (solution_official_id) REFERENCES officials(id) ON DELETE SET NULL;
ALTER TABLE posts ADD CONSTRAINT IF NOT EXISTS fk_posts_rejection_official FOREIGN KEY (rejection_official_id) REFERENCES officials(id) ON DELETE SET NULL;

-- Mevcut text şehir ve ilçe değerlerini yeni id alanlarına dönüştürmek için bir yardımcı fonksiyon
CREATE OR REPLACE FUNCTION update_posts_city_district_ids()
RETURNS VOID AS $$
DECLARE
    post_record RECORD;
BEGIN
    FOR post_record IN SELECT id, city, district FROM posts WHERE city IS NOT NULL OR district IS NOT NULL
    LOOP
        -- Şehir ID'sini güncelle
        IF post_record.city IS NOT NULL THEN
            UPDATE posts SET city_id = (SELECT id FROM cities WHERE name = post_record.city LIMIT 1)
            WHERE id = post_record.id;
        END IF;
        
        -- İlçe ID'sini güncelle
        IF post_record.district IS NOT NULL THEN
            UPDATE posts SET district_id = (SELECT id FROM districts WHERE name = post_record.district LIMIT 1)
            WHERE id = post_record.id;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Fonksiyonu çalıştır
SELECT update_posts_city_district_ids();

-- Gerekli indeksler
CREATE INDEX IF NOT EXISTS idx_officials_user_id ON officials(user_id);
CREATE INDEX IF NOT EXISTS idx_officials_city_id ON officials(city_id);
CREATE INDEX IF NOT EXISTS idx_officials_district_id ON officials(district_id);
CREATE INDEX IF NOT EXISTS idx_post_resolutions_post_id ON post_resolutions(post_id);
CREATE INDEX IF NOT EXISTS idx_post_resolutions_official_id ON post_resolutions(official_id);
CREATE INDEX IF NOT EXISTS idx_posts_city_id ON posts(city_id);
CREATE INDEX IF NOT EXISTS idx_posts_district_id ON posts(district_id);
CREATE INDEX IF NOT EXISTS idx_posts_status ON posts(status);
";

// Supabase üzerinden API ile sorgu çalıştır
$supabase_url = getenv('SUPABASE_URL') ?: 'https://bimer.onvao.net:8443';
$supabase_key = getenv('SUPABASE_SERVICE_ROLE_KEY') ?: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyAgCiAgICAicm9sZSI6ICJzZXJ2aWNlX3JvbGUiLAogICAgImlzcyI6ICJzdXBhYmFzZS1kZW1vIiwKICAgICJpYXQiOiAxNjQxNzY5MjAwLAogICAgImV4cCI6IDE3OTk1MzU2MDAKfQ.DaYlNEoUrrEn2Ig7tqibS-PHK5vgusbcbo7X36XVt4Q';

if (!$supabase_url || !$supabase_key) {
    die("Supabase bilgileri bulunamadı.");
}

// Tabloları teker teker oluştur
$sql_parts = explode(';', $sql);

foreach ($sql_parts as $part) {
    $part = trim($part);
    if (empty($part)) continue;
    
    echo "SQL Sorgu Parçası Çalıştırılıyor: " . substr($part, 0, 50) . "...\n";
    
    // Supabase SQL API URL
    $url = $supabase_url . '/rest/v1/rpc/execute_sql';
    
    // API isteği yap
    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, $url);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode([
        'sql_query' => $part
    ]));
    curl_setopt($ch, CURLOPT_HTTPHEADER, [
        'apikey: ' . $supabase_key,
        'Authorization: Bearer ' . $supabase_key,
        'Content-Type: application/json',
        'Prefer: return=minimal'
    ]);
    
    $response = curl_exec($ch);
    $http_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    
    if (curl_errno($ch)) {
        echo "CURL Hatası: " . curl_error($ch) . "\n";
    } elseif ($http_code >= 400) {
        echo "API Hatası (HTTP " . $http_code . "): " . $response . "\n";
    } else {
        echo "Başarılı (HTTP " . $http_code . ")\n";
    }
    
    curl_close($ch);
}

echo "\nBelediye görevlileri tabloları oluşturma işlemi tamamlandı!";
?>