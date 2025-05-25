<?php
// Örnek splash screen reklamı ekleme
require_once 'config/config.php';
require_once 'includes/functions.php';

echo "<h2>🎯 Açılış Sayfası Reklamı Ekleniyor...</h2>";

// Örnek splash screen reklam verisi
$splash_ad_data = [
    'title' => 'Belediye Açılış Sayfası Reklamı',
    'content' => 'Belediyemizin yeni hizmetlerinden haberdar olmak için bizi takip edin! Bu açılış sayfası reklamı test amaçlıdır.',
    'image_urls' => ['https://via.placeholder.com/800x600/4285f4/ffffff?text=Belediye+Reklamı'],
    'target_url' => 'https://example.com/belediye-hizmetler',
    'start_date' => date('Y-m-d H:i:s'),
    'end_date' => date('Y-m-d H:i:s', strtotime('+1 month')),
    'show_after_posts' => 0, // Splash screen için geçersiz
    'is_pinned' => true,
    'status' => 'active',
    'ad_display_scope' => 'splash', // ÖNEMLİ: Açılış sayfası reklamı
    'city' => null,
    'district' => null,
    'city_id' => null,
    'district_id' => null,
    'created_at' => date('Y-m-d H:i:s')
];

// Reklamı ekle
$result = addData('sponsored_ads', $splash_ad_data);

if (!$result['error']) {
    echo "✅ Splash screen reklamı başarıyla eklendi!<br>";
    echo "📊 Reklam ID: " . $result['data']['id'] . "<br>";
    echo "🎯 Hedefleme: Açılış Sayfası<br>";
    echo "📅 Süre: 1 ay aktif<br>";
} else {
    echo "❌ Hata: " . $result['message'] . "<br>";
}

echo "<br><hr>";
echo "<h3>✨ Test Sonuçları:</h3>";

// Splash reklamlarını kontrol et
$splash_ads = getData('sponsored_ads', ['ad_display_scope' => 'eq.splash']);
if (!$splash_ads['error']) {
    echo "🎉 Sistemde toplam " . count($splash_ads['data']) . " adet açılış sayfası reklamı var!<br>";
    
    foreach ($splash_ads['data'] as $ad) {
        echo "- " . htmlspecialchars($ad['title']) . " (Durum: " . $ad['status'] . ")<br>";
    }
} else {
    echo "❌ Splash reklamları çekilemedi: " . $splash_ads['message'] . "<br>";
}

echo "<br><a href='/php-panel/index.php?page=advertisements'>📋 Reklamları Görüntüle</a> | ";
echo "<a href='/php-panel/index.php?page=ad_edit'>➕ Yeni Reklam Ekle</a>";
?>