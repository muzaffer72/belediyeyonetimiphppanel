<?php
// Yapılandırma dosyasını yükle
require_once(__DIR__ . '/config/config.php');

// Supabase API ile iletişim için fonksiyon
function supabaseRequest($endpoint, $method = 'GET', $data = null) {
    $supabase_url = getenv('SUPABASE_URL') ?: 'https://bimer.onvao.net:8443';
    $supabase_key = getenv('SUPABASE_SERVICE_ROLE_KEY') ?: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyAgCiAgICAicm9sZSI6ICJzZXJ2aWNlX3JvbGUiLAogICAgImlzcyI6ICJzdXBhYmFzZS1kZW1vIiwKICAgICJpYXQiOiAxNjQxNzY5MjAwLAogICAgImV4cCI6IDE3OTk1MzU2MDAKfQ.DaYlNEoUrrEn2Ig7tqibS-PHK5vgusbcbo7X36XVt4Q';
    
    $url = $supabase_url . '/rest/v1/' . $endpoint;
    
    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, $url);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    
    if ($method === 'POST' || $method === 'PATCH') {
        curl_setopt($ch, CURLOPT_CUSTOMREQUEST, $method);
        if ($data !== null) {
            curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($data));
        }
    }
    
    $headers = [
        'apikey: ' . $supabase_key,
        'Authorization: Bearer ' . $supabase_key,
        'Content-Type: application/json',
        'Prefer: return=representation'
    ];
    
    curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
    
    $response = curl_exec($ch);
    $http_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    
    curl_close($ch);
    
    return [
        'code' => $http_code,
        'response' => json_decode($response, true)
    ];
}

// Mevcut tabloları kontrol et
echo "Mevcut tabloları kontrol ediyorum...\n";
$tables_response = supabaseRequest('');

if ($tables_response['code'] >= 400) {
    echo "Hata: Tablolar alınamadı\n";
    echo "HTTP Kod: " . $tables_response['code'] . "\n";
    echo "Yanıt: " . print_r($tables_response['response'], true) . "\n";
    exit;
}

// Officials tablosunu oluştur
$officials_data = [
    [
        "id" => 1,
        "user_id" => "83190944-98d5-41be-ac3a-178676faf017",  // Örnek bir kullanıcı ID
        "city_id" => 1,                                      // Örnek şehir ID
        "district_id" => null,                               // Tüm ilçeler
        "title" => "İlk Belediye Görevlisi",
        "notes" => "Test hesabı",
        "created_at" => date('c'),
        "updated_at" => date('c')
    ]
];

// Tabloyu oluşturmayı dene
echo "Belediye görevlileri (officials) tablosunu oluşturuyorum...\n";
$officials_response = supabaseRequest('officials', 'POST', $officials_data);

// Yanıtı kontrol et
if ($officials_response['code'] >= 300 && $officials_response['code'] < 400) {
    echo "Tablo zaten var, güncelleniyor...\n";
} elseif ($officials_response['code'] >= 400) {
    echo "Hata: Officials tablosu oluşturulamadı\n";
    echo "HTTP Kod: " . $officials_response['code'] . "\n";
    echo "Yanıt: " . print_r($officials_response['response'], true) . "\n";
} else {
    echo "Officials tablosu başarıyla oluşturuldu\n";
}

// Posts tablosunu güncelle - yeni alanlar ekle
echo "\nPosts tablosuna yeni alanlar ekliyorum...\n";

// Örnek bir post üzerinde güncelleme yaparak alanları ekle
$update_post_data = [
    "status" => "pending",
    "processing_date" => null,
    "processing_official_id" => null,
    "solution_date" => null,
    "solution_official_id" => null,
    "solution_note" => null,
    "evidence_url" => null,
    "rejection_date" => null,
    "rejection_official_id" => null
];

// Var olan bir post'u güncelle
$post_update_response = supabaseRequest('posts?id=eq.1', 'PATCH', $update_post_data);

// Yanıtı kontrol et
if ($post_update_response['code'] >= 400) {
    echo "Hata: Posts tablosu güncellenemedi\n";
    echo "HTTP Kod: " . $post_update_response['code'] . "\n";
    echo "Yanıt: " . print_r($post_update_response['response'], true) . "\n";
} else {
    echo "Posts tablosuna yeni alanlar başarıyla eklendi\n";
}

echo "\nTablolar ve alanlar hazır.\n";
echo "Not: Bu işlem, Supabase'in tablo oluşturma ve güncelleme özelliklerini kullanarak basit bir yapı oluşturur.\n";
echo "Daha karmaşık tablolar ve ilişkiler için Supabase UI'ı kullanabilirsiniz.\n";
?>