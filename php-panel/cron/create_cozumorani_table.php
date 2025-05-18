<?php
// Yapılandırma dosyasını yükle
require_once(__DIR__ . '/../config/config.php');

// Hata raporlamasını etkinleştir
ini_set('display_errors', 1);
error_reporting(E_ALL);

// Script başlangıç zamanı
$start_time = microtime(true);
$log = "Çözüm oranları tablosu oluşturma başladı: " . date('Y-m-d H:i:s') . "\n";

/**
 * Bu script, çözüm oranlarını saklamak için gerekli tabloyu oluşturur
 * Sadece bir kez çalıştırılması gerekir
 */

// cozumorani tablosunu oluştur (eğer yoksa)
// Supabase'de RPC fonksiyonu ile SQL çalıştırma
$create_table_sql = "
CREATE TABLE IF NOT EXISTS cozumorani (
    id SERIAL PRIMARY KEY,
    entity_id INTEGER NOT NULL,
    entity_type TEXT NOT NULL,
    name TEXT NOT NULL,
    total_complaints INTEGER DEFAULT 0,
    solved_complaints INTEGER DEFAULT 0,
    thanks_count INTEGER DEFAULT 0,
    solution_rate NUMERIC(5,2) DEFAULT 0,
    last_updated TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(entity_id, entity_type)
);";

$result = executeRawSql($create_table_sql);

if ($result['error']) {
    $log .= "Tablo oluşturma hatası: " . $result['error_message'] . "\n";
    echo $log;
    exit;
}

// İndeksleri oluştur (hızlı sorgulama için)
$create_indexes_sql = "
CREATE INDEX IF NOT EXISTS cozumorani_entity_id_idx ON cozumorani(entity_id);
CREATE INDEX IF NOT EXISTS cozumorani_entity_type_idx ON cozumorani(entity_type);
CREATE INDEX IF NOT EXISTS cozumorani_solution_rate_idx ON cozumorani(solution_rate);
";

$result = executeRawSql($create_indexes_sql);

if ($result['error']) {
    $log .= "İndeks oluşturma hatası: " . $result['error_message'] . "\n";
    echo $log;
    exit;
}

// Script çalışma süresi
$execution_time = microtime(true) - $start_time;
$log .= "Tablo başarıyla oluşturuldu. Çalışma süresi: " . number_format($execution_time, 2) . " saniye\n";

// Log dosyasına yaz
file_put_contents(__DIR__ . '/create_table_log.txt', $log, FILE_APPEND);

echo $log;
?>