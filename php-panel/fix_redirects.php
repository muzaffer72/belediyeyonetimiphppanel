<?php
// Bu betik, tüm PHP dosyalarında header('Location: ...) çağrılarını 
// safeRedirect() fonksiyonu ile değiştirir

$base_dir = __DIR__;
$view_dir = $base_dir . '/views';

// Tüm PHP dosyalarını bul
$php_files = glob($view_dir . '/*.php');

foreach ($php_files as $file) {
    $content = file_get_contents($file);
    
    // header('Location: ...) çağrılarını bul ve değiştir
    $pattern = "/header\('Location: ([^']+)'\);\s*exit;/";
    $replacement = "safeRedirect('$1');";
    
    $new_content = preg_replace($pattern, $replacement, $content);
    
    // Değişiklik yapıldıysa dosyayı güncelle
    if ($new_content !== $content) {
        file_put_contents($file, $new_content);
        echo "Düzeltildi: " . basename($file) . PHP_EOL;
    }
}

echo "İşlem tamamlandı!\n";
