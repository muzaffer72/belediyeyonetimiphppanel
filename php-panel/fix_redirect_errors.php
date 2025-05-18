<?php
// Tüm yönlendirme çağrılarını düzeltme betiği

$base_dir = __DIR__;
$view_dir = $base_dir . '/views';

// Tüm view dosyalarını bul
$files = glob($view_dir . '/*.php');

// safeRedirect fonksiyonunu kullanmak yerine doğrudan yönlendirme koduyla değiştirelim
$replacements = [
    // safeRedirect çağrıları yerine doğrudan kod yerleştirme
    '/safeRedirect\([\'"]([^\'"]+)[\'"]\);/i' => 
    "if (!headers_sent()) {
        header('Location: $1');
        exit;
    } else {
        echo '<script>window.location.href = \"$1\";</script>';
        exit;
    }",
];

$count = 0;

foreach ($files as $file) {
    $content = file_get_contents($file);
    $modified = false;
    
    foreach ($replacements as $pattern => $replacement) {
        $new_content = preg_replace($pattern, $replacement, $content, -1, $count_replaced);
        if ($count_replaced > 0) {
            $content = $new_content;
            $modified = true;
            $count += $count_replaced;
        }
    }
    
    if ($modified) {
        file_put_contents($file, $content);
        echo basename($file) . ": " . $count_replaced . " düzeltme(ler) yapıldı.\n";
    }
}

echo "Toplam $count düzeltme yapıldı.\n";
echo "İşlem tamamlandı!\n";
