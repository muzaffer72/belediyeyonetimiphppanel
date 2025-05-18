<?php
// Bu betik, tüm PHP view dosyalarının başına fonksiyon dahil etme kodu ekler

$base_dir = __DIR__;
$view_dir = $base_dir . '/views';

// Tüm PHP dosyalarını bul
$php_files = glob($view_dir . '/*.php');

foreach ($php_files as $file) {
    $content = file_get_contents($file);
    
    // Dosya başlangıcını kontrol et
    if (strpos($content, "require_once(__DIR__ . '/../includes/functions.php')") === false) {
        // İlk <?php satırından sonra include ekle
        $new_content = preg_replace(
            '/^<\?php/', 
            "<?php\n// Fonksiyonları dahil et\nrequire_once(__DIR__ . '/../includes/functions.php');", 
            $content
        );
        
        // Değişiklik yapıldıysa dosyayı güncelle
        if ($new_content !== $content) {
            file_put_contents($file, $new_content);
            echo "Düzeltildi: " . basename($file) . PHP_EOL;
        }
    }
}

echo "İşlem tamamlandı!\n";
