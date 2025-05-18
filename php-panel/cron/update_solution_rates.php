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
$total_cities = count($cities);
$log .= "Toplamda {$total_cities} şehir için çözüm oranları hesaplanacak.\n";

// Şehirleri 100'lü gruplar halinde işle
$batch_size = 100;
$current_batch = 0;
$processed_count = 0;

while ($processed_count < $total_cities) {
    $batch_start = $current_batch * $batch_size;
    $batch_end = min($batch_start + $batch_size, $total_cities);
    $current_cities = array_slice($cities, $batch_start, $batch_size);
    
    $log .= "Şehir grubu {$current_batch} işleniyor: {$batch_start} - " . ($batch_end-1) . "\n";
    
    foreach ($current_cities as $city) {
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
        
        // Şehir verisini doğrudan güncelle
        updateCitySolutionRate($city['id'], $total_complaints, $solved_complaints, $thanks_count, $solution_rate);
        
        $log .= "Şehir: {$city_name}, Toplam Şikayet: {$total_complaints}, Çözülen: {$solved_complaints}, Teşekkür: {$thanks_count}, Oran: %".number_format($solution_rate, 2)."\n";
        $processed_count++;
    }
    
    $current_batch++;
    // Kısa bir bekleme ekleyerek sunucuya nefes aldıralım
    usleep(100000); // 100ms bekle
}

// İlçeler için çözüm oranlarını hesapla
$total_districts = count($districts);
$log .= "Toplamda {$total_districts} ilçe için çözüm oranları hesaplanacak.\n";

// İlçeleri 100'lü gruplar halinde işle
$batch_size = 100;
$current_batch = 0;
$processed_count = 0;

while ($processed_count < $total_districts) {
    $batch_start = $current_batch * $batch_size;
    $batch_end = min($batch_start + $batch_size, $total_districts);
    $current_districts = array_slice($districts, $batch_start, $batch_size);
    
    $log .= "İlçe grubu {$current_batch} işleniyor: {$batch_start} - " . ($batch_end-1) . "\n";
    
    foreach ($current_districts as $district) {
        if (!isset($district['id']) || !isset($district['name'])) {
            continue;
        }
        
        $district_name = $district['name'];
        $city_id = $district['city_id'] ?? null;
        $city_name = '';
        
        // İlçenin bağlı olduğu şehir adını bul
        if ($city_id) {
            foreach ($cities as $city) {
                if (isset($city['id']) && $city['id'] === $city_id) {
                    $city_name = $city['name'];
                    break;
                }
            }
        }
        
        $total_complaints = 0;
        $solved_complaints = 0;
        $thanks_count = 0;
        
        foreach ($posts as $post) {
            // İlçe adı kontrolü
            if (isset($post['district']) && $post['district'] === $district_name) {
                // Aynı isimde birden fazla ilçe olabilir, şehir kontrolü de yap
                if (!$city_name || (isset($post['city']) && $post['city'] === $city_name)) {
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
        }
        
        // Çözüm oranını hesapla
        $solution_rate = 0;
        if ($total_complaints + $thanks_count > 0) {
            $solution_rate = (($solved_complaints + $thanks_count) / ($total_complaints + $thanks_count)) * 100;
        }
        
        // İlçe verisini doğrudan güncelle
        updateDistrictSolutionRate($district['id'], $total_complaints, $solved_complaints, $thanks_count, $solution_rate);
        
        $log .= "İlçe: {$district_name}" . ($city_name ? " ({$city_name})" : "") . ", Toplam Şikayet: {$total_complaints}, Çözülen: {$solved_complaints}, Teşekkür: {$thanks_count}, Oran: %".number_format($solution_rate, 2)."\n";
        $processed_count++;
    }
    
    $current_batch++;
    // Kısa bir bekleme ekleyerek sunucuya nefes aldıralım
    usleep(100000); // 100ms bekle
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
 * Şehir için çözüm oranını doğrudan şehir tablosunda günceller
 * 
 * @param string $city_id Şehir ID'si
 * @param int $total_complaints Toplam şikayet sayısı
 * @param int $solved_complaints Çözülmüş şikayet sayısı
 * @param int $thanks_count Teşekkür sayısı
 * @param float $solution_rate Çözüm oranı (yüzde)
 * @return array İşlem sonucu
 */
function updateCitySolutionRate($city_id, $total_complaints, $solved_complaints, $thanks_count, $solution_rate) {
    $data = [
        'total_complaints' => $total_complaints,
        'solved_complaints' => $solved_complaints,
        'thanks_count' => $thanks_count,
        'solution_rate' => $solution_rate,
        'solution_last_updated' => date('Y-m-d H:i:s')
    ];
    
    return updateData('cities', $city_id, $data);
}

/**
 * İlçe için çözüm oranını doğrudan ilçe tablosunda günceller
 * 
 * @param string $district_id İlçe ID'si
 * @param int $total_complaints Toplam şikayet sayısı
 * @param int $solved_complaints Çözülmüş şikayet sayısı
 * @param int $thanks_count Teşekkür sayısı
 * @param float $solution_rate Çözüm oranı (yüzde)
 * @return array İşlem sonucu
 */
function updateDistrictSolutionRate($district_id, $total_complaints, $solved_complaints, $thanks_count, $solution_rate) {
    $data = [
        'total_complaints' => $total_complaints,
        'solved_complaints' => $solved_complaints,
        'thanks_count' => $thanks_count,
        'solution_rate' => $solution_rate,
        'solution_last_updated' => date('Y-m-d H:i:s')
    ];
    
    return updateData('districts', $district_id, $data);
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
    $total_parties = count($parties);
    
    if ($total_parties == 0) {
        $log .= "Güncellenecek parti bulunamadı.\n";
        return;
    }
    
    $log .= "Toplamda {$total_parties} parti için puanlar hesaplanacak.\n";
    
    // Şehir ve ilçelerin çözüm oranlarını tablolardan al
    $cities_result = getData('cities');
    $cities = $cities_result['data'] ?? [];
    
    $districts_result = getData('districts');
    $districts = $districts_result['data'] ?? [];
    
    // Partilerin şehir ve ilçelerini önceden hesapla
    $party_entities = [];
    
    // Şehirleri partilere göre grupla
    foreach ($cities as $city) {
        if (isset($city['political_party_id']) && !empty($city['political_party_id'])) {
            $party_id = $city['political_party_id'];
            if (!isset($party_entities[$party_id])) {
                $party_entities[$party_id] = ['cities' => [], 'districts' => []];
            }
            $party_entities[$party_id]['cities'][] = $city['id'];
        }
    }
    
    // İlçeleri partilere göre grupla
    foreach ($districts as $district) {
        if (isset($district['political_party_id']) && !empty($district['political_party_id'])) {
            $party_id = $district['political_party_id'];
            if (!isset($party_entities[$party_id])) {
                $party_entities[$party_id] = ['cities' => [], 'districts' => []];
            }
            $party_entities[$party_id]['districts'][] = $district['id'];
        }
    }
    
    // Partileri 50'li gruplar halinde işle (API rate limit'e takılmamak için)
    $batch_size = 50;
    $current_batch = 0;
    $processed_count = 0;
    
    while ($processed_count < $total_parties) {
        $batch_start = $current_batch * $batch_size;
        $batch_end = min($batch_start + $batch_size, $total_parties);
        $current_parties = array_slice($parties, $batch_start, $batch_size);
        
        $log .= "Parti grubu {$current_batch} işleniyor: {$batch_start} - " . ($batch_end-1) . "\n";
        
        foreach ($current_parties as $party) {
            $party_id = $party['id'];
            $party_name = $party['name'] ?? "Parti #{$party_id}";
            $total_solution_rate = 0;
            $entity_count = 0;
            
            // Bu parti için şehir ve ilçeleri kontrol et
            if (isset($party_entities[$party_id])) {
                // Şehirleri kontrol et
                foreach ($party_entities[$party_id]['cities'] as $city_id) {
                    // Şehri bul ve çözüm oranını kontrol et
                    foreach ($cities as $city) {
                        if ($city['id'] === $city_id && isset($city['solution_rate']) && $city['solution_rate'] > 0) {
                            $total_solution_rate += $city['solution_rate'];
                            $entity_count++;
                            break;
                        }
                    }
                }
                
                // İlçeleri kontrol et
                foreach ($party_entities[$party_id]['districts'] as $district_id) {
                    // İlçeyi bul ve çözüm oranını kontrol et
                    foreach ($districts as $district) {
                        if ($district['id'] === $district_id && isset($district['solution_rate']) && $district['solution_rate'] > 0) {
                            $total_solution_rate += $district['solution_rate'];
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
            
            $log .= "Parti: {$party_name} (ID: {$party_id}), Yeni Skor: ".number_format($normalized_score, 1)." (Ortalama Çözüm Oranı: %".number_format($average_score, 2).", {$entity_count} şehir/ilçe)\n";
            $processed_count++;
        }
        
        $current_batch++;
        // Kısa bir bekleme ekleyerek sunucuya nefes aldıralım
        usleep(100000); // 100ms bekle
    }
}
?>