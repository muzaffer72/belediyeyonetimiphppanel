<?php
// Bu betik, tüm PHP dosyalarına fonksiyon dahil etme satırını doğru bir şekilde ekler

$base_dir = __DIR__;
$view_dir = $base_dir . '/views';

// Tüm PHP dosyalarını bul
$files = glob($view_dir . '/*.php');

foreach ($files as $file) {
    $content = file_get_contents($file);
    
    // Eğer dosya zaten require içeriyorsa, kontrol et ama değiştirme
    if (strpos($content, "require_once(__DIR__ . '/../includes/functions.php')") !== false) {
        echo basename($file) . ": Zaten functions.php dahil edilmiş.\n";
        continue;
    }
    
    // <?php satırından sonraki ilk satıra require_once ekle
    $new_content = preg_replace(
        '/^(<\?php)(.*)$/m',
        "$1\n// Fonksiyonları dahil et\nrequire_once(__DIR__ . '/../includes/functions.php');$2",
        $content,
        1
    );
    
    // Değişiklik yapıldıysa dosyayı güncelle
    if ($new_content !== $content) {
        file_put_contents($file, $new_content);
        echo basename($file) . ": functions.php dahil edildi.\n";
    }
}

// Ayrıca login.php dosyasını da düzelt
$login_file = $base_dir . '/login.php';
if (file_exists($login_file)) {
    $content = file_get_contents($login_file);
    
    if (strpos($content, "require_once(__DIR__ . '/includes/functions.php')") === false) {
        $new_content = preg_replace(
            '/^(<\?php)(.*)$/m',
            "$1\n// Fonksiyonları dahil et\nrequire_once(__DIR__ . '/includes/functions.php');$2",
            $content,
            1
        );
        
        if ($new_content !== $content) {
            file_put_contents($login_file, $new_content);
            echo "login.php: functions.php dahil edildi.\n";
        }
    }
}

echo "İşlem tamamlandı!\n";
