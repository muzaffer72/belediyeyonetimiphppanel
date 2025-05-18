<?php
// Yapılandırma dosyasını yükle
require_once(__DIR__ . '/../config/config.php');

// Hata raporlamasını etkinleştir
ini_set('display_errors', 1);
error_reporting(E_ALL);

// Script başlangıç zamanı
$start_time = microtime(true);
$log = "Çözüm oranları güncelleme başladı: " . date('Y-m-d H:i:s') . "\n";

/**
 * Şehir ve ilçeler için çözüm oranlarını hesaplar ve veritabanına kaydeder
 * Bu script günlük olarak cron ile çalıştırılacak
 */

// Tüm şehirleri ve ilçeleri al
$cities_result = getData('cities');
$cities = $cities_result['data'] ?? [];

$districts_result = getData('districts');
$districts = $districts_result['data'] ?? [];

// Tüm gönderileri al
$posts_result = getData('posts');
$posts = $posts_result['data'] ?? [];

$log .= "Veri alındı: " . count($cities) . " şehir, " . count($districts) . " ilçe, " . count($posts) . " gönderi.\n";

// Şehirler için çözüm oranlarını hesapla
foreach ($cities as $city) {
    if (!isset($city['id']) || !isset($city['name'])) {
        continue;
    }
    
    $city_name = $city['name'];
    $total_complaints = 0;
    $solved_complaints = 0;
    $thanks_count = 0;
    
    foreach ($posts as $post) {
        // Şehir adı kontrolü
        if (isset($post['city']) && $post['city'] === $city_name) {
            // Post türü kontrolü
            if (isset($post['type'])) {
                if ($post['type'] === 'complaint') {
                    $total_complaints++;
                    
                    // Çözülmüş şikayet kontrolü
                    if (isset($post['is_resolved']) && $post['is_resolved'] === 'true') {
                        $solved_complaints++;
                    }
                } else if ($post['type'] === 'thanks') {
                    $thanks_count++;
                }
            }
        }
    }
    
    // Çözüm oranını hesapla
    $solution_rate = 0;
    if ($total_complaints + $thanks_count > 0) {
        $solution_rate = (($solved_complaints + $thanks_count) / ($total_complaints + $thanks_count)) * 100;
    }
    
    // Veritabanında kaydı güncelle veya oluştur
    updateSolutionRate($city['id'], 'city', $city_name, $total_complaints, $solved_complaints, $thanks_count, $solution_rate);
    
    $log .= "Şehir: {$city_name}, Toplam Şikayet: {$total_complaints}, Çözülen: {$solved_complaints}, Teşekkür: {$thanks_count}, Oran: %".number_format($solution_rate, 2)."\n";
}

// İlçeler için çözüm oranlarını hesapla
foreach ($districts as $district) {
    if (!isset($district['id']) || !isset($district['name'])) {
        continue;
    }
    
    $district_name = $district['name'];
    $total_complaints = 0;
    $solved_complaints = 0;
    $thanks_count = 0;
    
    foreach ($posts as $post) {
        // İlçe adı kontrolü
        if (isset($post['district']) && $post['district'] === $district_name) {
            // Post türü kontrolü
            if (isset($post['type'])) {
                if ($post['type'] === 'complaint') {
                    $total_complaints++;
                    
                    // Çözülmüş şikayet kontrolü
                    if (isset($post['is_resolved']) && $post['is_resolved'] === 'true') {
                        $solved_complaints++;
                    }
                } else if ($post['type'] === 'thanks') {
                    $thanks_count++;
                }
            }
        }
    }
    
    // Çözüm oranını hesapla
    $solution_rate = 0;
    if ($total_complaints + $thanks_count > 0) {
        $solution_rate = (($solved_complaints + $thanks_count) / ($total_complaints + $thanks_count)) * 100;
    }
    
    // Veritabanında kaydı güncelle veya oluştur
    updateSolutionRate($district['id'], 'district', $district_name, $total_complaints, $solved_complaints, $thanks_count, $solution_rate);
    
    $log .= "İlçe: {$district_name}, Toplam Şikayet: {$total_complaints}, Çözülen: {$solved_complaints}, Teşekkür: {$thanks_count}, Oran: %".number_format($solution_rate, 2)."\n";
}

// Parti skorlarını güncelle
updatePartyScores();

// Script çalışma süresi
$execution_time = microtime(true) - $start_time;
$log .= "İşlem tamamlandı. Çalışma süresi: " . number_format($execution_time, 2) . " saniye\n";

// Log dosyasına yaz
file_put_contents(__DIR__ . '/solution_rate_log.txt', $log, FILE_APPEND);

echo $log;

/**
 * Çözüm oranını veritabanında günceller veya yeni kayıt oluşturur
 * 
 * @param string $entity_id Şehir veya ilçe ID'si
 * @param string $entity_type Şehir mi ilçe mi ('city' veya 'district')
 * @param string $name Şehir veya ilçe adı
 * @param int $total_complaints Toplam şikayet sayısı
 * @param int $solved_complaints Çözülmüş şikayet sayısı
 * @param int $thanks_count Teşekkür sayısı
 * @param float $solution_rate Çözüm oranı (yüzde)
 * @return array İşlem sonucu
 */
function updateSolutionRate($entity_id, $entity_type, $name, $total_complaints, $solved_complaints, $thanks_count, $solution_rate) {
    // Önce kaydın var olup olmadığını kontrol et
    $check_result = getData('cozumorani', [
        'entity_id' => 'eq.' . $entity_id,
        'entity_type' => 'eq.' . $entity_type
    ]);
    
    $data = [
        'entity_id' => $entity_id,
        'entity_type' => $entity_type,
        'name' => $name,
        'total_complaints' => $total_complaints,
        'solved_complaints' => $solved_complaints,
        'thanks_count' => $thanks_count,
        'solution_rate' => $solution_rate,
        'last_updated' => date('Y-m-d H:i:s')
    ];
    
    // Kayıt yoksa yeni oluştur, varsa güncelle
    if (empty($check_result['data'])) {
        return addData('cozumorani', $data);
    } else {
        return updateData('cozumorani', $check_result['data'][0]['id'], $data);
    }
}

/**
 * Parti skorlarını şehir ve ilçelerin ortalama çözüm oranlarına göre günceller
 * 
 * @return void
 */
function updatePartyScores() {
    global $log;
    
    // Tüm partileri al
    $parties_result = getData('political_parties');
    $parties = $parties_result['data'] ?? [];
    
    // Tüm şehir ve ilçelerin çözüm oranlarını al
    $solution_rates_result = getData('cozumorani');
    $solution_rates = $solution_rates_result['data'] ?? [];
    
    // Tüm şehir ve ilçeleri al
    $cities_result = getData('cities');
    $cities = $cities_result['data'] ?? [];
    
    $districts_result = getData('districts');
    $districts = $districts_result['data'] ?? [];
    
    foreach ($parties as $party) {
        $party_id = $party['id'];
        $total_solution_rate = 0;
        $entity_count = 0;
        
        // Şehirleri kontrol et
        foreach ($cities as $city) {
            if (isset($city['political_party_id']) && $city['political_party_id'] == $party_id) {
                // Bu şehir için çözüm oranını bul
                foreach ($solution_rates as $rate) {
                    if ($rate['entity_type'] === 'city' && $rate['entity_id'] === $city['id']) {
                        $total_solution_rate += $rate['solution_rate'];
                        $entity_count++;
                        break;
                    }
                }
            }
        }
        
        // İlçeleri kontrol et
        foreach ($districts as $district) {
            if (isset($district['political_party_id']) && $district['political_party_id'] == $party_id) {
                // Bu ilçe için çözüm oranını bul
                foreach ($solution_rates as $rate) {
                    if ($rate['entity_type'] === 'district' && $rate['entity_id'] === $district['id']) {
                        $total_solution_rate += $rate['solution_rate'];
                        $entity_count++;
                        break;
                    }
                }
            }
        }
        
        // Ortalama çözüm oranını hesapla
        $average_score = 0;
        if ($entity_count > 0) {
            $average_score = $total_solution_rate / $entity_count;
        }
        
        // Parti skorunu 0-10 aralığına dönüştür (çözüm oranı en fazla 100 olabileceği için 10'a böleriz)
        $normalized_score = min(10, $average_score / 10);
        
        // Parti skorunu güncelle
        $update_data = [
            'score' => $normalized_score,
            'last_updated' => date('Y-m-d H:i:s')
        ];
        
        $result = updateData('political_parties', $party_id, $update_data);
        
        $log .= "Parti ID: {$party_id}, Yeni Skor: ".number_format($normalized_score, 1)." (Ortalama Çözüm Oranı: %".number_format($average_score, 2).", {$entity_count} şehir/ilçe)\n";
    }
}
?>