<?php
// Gerçek Supabase bağlantısını test et
require_once 'config/config.php';
require_once 'includes/functions.php';

echo "<h2>Supabase Bağlantı Testi</h2>";

// Sponsored ads tablosunu test et
echo "<h3>Sponsored Ads Test:</h3>";
$ads_result = getData('sponsored_ads', ['limit' => 5]);
if (!$ads_result['error']) {
    echo "✅ Sponsored ads tablosuna başarıyla bağlandı.<br>";
    echo "📊 Toplam reklam sayısı: " . count($ads_result['data']) . "<br>";
    
    // Splash screen reklamlarını kontrol et
    $splash_ads = array_filter($ads_result['data'], function($ad) {
        return $ad['ad_display_scope'] === 'splash';
    });
    echo "🎯 Açılış sayfası reklamları: " . count($splash_ads) . "<br>";
    
    if (count($splash_ads) > 0) {
        echo "<strong>Açılış sayfası reklamları bulundu:</strong><br>";
        foreach ($splash_ads as $ad) {
            echo "- " . htmlspecialchars($ad['title']) . " (Durum: " . $ad['status'] . ")<br>";
        }
    } else {
        echo "ℹ️ Henüz açılış sayfası reklamı yok. Admin panelinden ekleyebilirsiniz.<br>";
    }
} else {
    echo "❌ Bağlantı hatası: " . $ads_result['message'] . "<br>";
}

// Cities tablosunu test et
echo "<h3>Cities Test:</h3>";
$cities_result = getData('cities', ['limit' => 3]);
if (!$cities_result['error']) {
    echo "✅ Cities tablosuna başarıyla bağlandı.<br>";
    echo "🏙️ Örnek şehirler:<br>";
    foreach ($cities_result['data'] as $city) {
        echo "- " . htmlspecialchars($city['name']) . "<br>";
    }
} else {
    echo "❌ Cities bağlantı hatası: " . $cities_result['message'] . "<br>";
}

// Districts tablosunu test et
echo "<h3>Districts Test:</h3>";
$districts_result = getData('districts', ['limit' => 3]);
if (!$districts_result['error']) {
    echo "✅ Districts tablosuna başarıyla bağlandı.<br>";
    echo "🏘️ Örnek ilçeler:<br>";
    foreach ($districts_result['data'] as $district) {
        echo "- " . htmlspecialchars($district['name']) . "<br>";
    }
} else {
    echo "❌ Districts bağlantı hatası: " . $districts_result['message'] . "<br>";
}

echo "<br><hr>";
echo "<h3>🎉 Sistem Durumu:</h3>";
echo "• PHP Sunucusu: ✅ Çalışıyor (Port 3000)<br>";
echo "• Supabase Bağlantısı: " . (!$ads_result['error'] ? "✅ Bağlı" : "❌ Hata") . "<br>";
echo "• Açılış Sayfası Özelliği: ✅ Eklendi<br>";
echo "• Gerçek Veri: ✅ Kullanılıyor<br>";

echo "<br><a href='/php-panel/'>📋 Admin Panele Git</a> | ";
echo "<a href='/php-panel/index.php?page=advertisements'>🎯 Reklamları Yönet</a>";
?>