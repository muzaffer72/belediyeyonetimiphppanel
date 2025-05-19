<?php
// Yapılandırma dosyasını yükle
require_once(__DIR__ . '/config/config.php');

// Veritabanı bağlantısı için gerekli parametreleri al
$db_url = getenv('DATABASE_URL');

if (!$db_url) {
    die("DATABASE_URL bulunamadı.");
}

// Bağlantı URL'sini parçala
$db_parts = parse_url($db_url);
$db_host = $db_parts['host'];
$db_port = $db_parts['port'];
$db_name = ltrim($db_parts['path'], '/');
$db_user = $db_parts['user'];
$db_pass = $db_parts['pass'];

// Veritabanı bağlantısı oluştur
$conn = pg_connect("host=$db_host port=$db_port dbname=$db_name user=$db_user password=$db_pass");

if (!$conn) {
    die("Veritabanı bağlantısı başarısız: " . pg_last_error());
}

// Gerekli tabloları oluştur
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
    resolution_type VARCHAR(50) NOT NULL, -- 'in_progress', 'solved', 'rejected'
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

-- Gerekli indeksler
CREATE INDEX IF NOT EXISTS idx_officials_user_id ON officials(user_id);
CREATE INDEX IF NOT EXISTS idx_officials_city_id ON officials(city_id);
CREATE INDEX IF NOT EXISTS idx_officials_district_id ON officials(district_id);
CREATE INDEX IF NOT EXISTS idx_post_resolutions_post_id ON post_resolutions(post_id);
CREATE INDEX IF NOT EXISTS idx_post_resolutions_official_id ON post_resolutions(official_id);

-- Otomatik güncelleme için trigger fonksiyonu
CREATE OR REPLACE FUNCTION update_timestamp_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- officials tablosu için trigger
DROP TRIGGER IF EXISTS update_officials_timestamp ON officials;
CREATE TRIGGER update_officials_timestamp
BEFORE UPDATE ON officials
FOR EACH ROW
EXECUTE PROCEDURE update_timestamp_column();

-- post_resolutions tablosu için trigger
DROP TRIGGER IF EXISTS update_post_resolutions_timestamp ON post_resolutions;
CREATE TRIGGER update_post_resolutions_timestamp
BEFORE UPDATE ON post_resolutions
FOR EACH ROW
EXECUTE PROCEDURE update_timestamp_column();
";

// SQL çalıştır
$result = pg_query($conn, $sql);

if (!$result) {
    die("SQL hatası: " . pg_last_error($conn));
}

echo "Belediye görevlileri ve ilgili tablolar başarıyla oluşturuldu!";

// Bağlantıyı kapat
pg_close($conn);
?>