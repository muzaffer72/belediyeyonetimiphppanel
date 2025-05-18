<?php
// Yapılandırma dosyasını yükle
require_once(__DIR__ . '/../config/config.php');

// Fonksiyonları dahil et - config.php içinden dahil ediliyor

/**
 * cozumorani tablosunu oluşturur
 * Bu script bir kez çalıştırılması gerekiyor
 */

// SQL sorgusu oluştur
$create_table_query = "CREATE TABLE IF NOT EXISTS cozumorani (
    id SERIAL PRIMARY KEY,
    entity_id UUID NOT NULL,
    entity_type VARCHAR(20) NOT NULL,  -- 'city' veya 'district'
    name VARCHAR(100) NOT NULL,
    total_complaints INT DEFAULT 0,
    solved_complaints INT DEFAULT 0,
    thanks_count INT DEFAULT 0,
    solution_rate DECIMAL(5,2) DEFAULT 0.00, -- Çözüm oranı (yüzde)
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)";

// Tabloyu oluştur
$result = executeRawSql($create_table_query);

if ($result['error']) {
    echo "Hata: " . $result['error_message'];
} else {
    echo "cozumorani tablosu başarıyla oluşturuldu";
}

// Gerekli indeksleri oluştur
$create_index_query = "CREATE INDEX IF NOT EXISTS idx_cozumorani_entity ON cozumorani(entity_id, entity_type)";
$result = executeRawSql($create_index_query);

if ($result['error']) {
    echo "Hata (indeks oluşturma): " . $result['error_message'];
} else {
    echo "İndeks başarıyla oluşturuldu";
}
?>