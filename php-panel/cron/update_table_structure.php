<?php
// Yapılandırma dosyasını yükle
require_once(__DIR__ . '/../config/config.php');

// Hata raporlamasını etkinleştir
ini_set('display_errors', 1);
error_reporting(E_ALL);

// Script başlangıç zamanı
$start_time = microtime(true);
$log = "Tablo yapısı güncelleme başladı: " . date('Y-m-d H:i:s') . "\n";

/**
 * Bu script, cities ve districts tablolarına çözüm oranı için gerekli sütunları ekler
 * Sadece bir kez çalıştırılması gerekir
 */

// cities tablosuna çözüm oranı sütunlarını ekle
$alter_cities_sql = "
ALTER TABLE cities
ADD COLUMN IF NOT EXISTS total_complaints INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS solved_complaints INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS thanks_count INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS solution_rate NUMERIC(5,2) DEFAULT 0,
ADD COLUMN IF NOT EXISTS solution_last_updated TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP;
";

$result = executeRawSql($alter_cities_sql);

if ($result['error']) {
    $log .= "Cities tablosu güncelleme hatası: " . $result['error_message'] . "\n";
    echo $log;
    exit;
}

$log .= "Cities tablosu başarıyla güncellendi.\n";

// districts tablosuna çözüm oranı sütunlarını ekle
$alter_districts_sql = "
ALTER TABLE districts
ADD COLUMN IF NOT EXISTS total_complaints INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS solved_complaints INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS thanks_count INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS solution_rate NUMERIC(5,2) DEFAULT 0,
ADD COLUMN IF NOT EXISTS solution_last_updated TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP;
";

$result = executeRawSql($alter_districts_sql);

if ($result['error']) {
    $log .= "Districts tablosu güncelleme hatası: " . $result['error_message'] . "\n";
    echo $log;
    exit;
}

$log .= "Districts tablosu başarıyla güncellendi.\n";

// Script çalışma süresi
$execution_time = microtime(true) - $start_time;
$log .= "Tablo yapısı güncelleme tamamlandı. Çalışma süresi: " . number_format($execution_time, 2) . " saniye\n";

// Log dosyasına yaz
file_put_contents(__DIR__ . '/update_table_structure_log.txt', $log, FILE_APPEND);

echo $log;
?>