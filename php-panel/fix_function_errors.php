<?php
// Yardımcı fonksiyonlarımızı tüm dosyalarda kullanılabilir hale getiren bir betik

$base_dir = __DIR__;
$functions_file = $base_dir . '/includes/functions.php';

// Fonksiyon içeriğini al
$function_content = file_get_contents($functions_file);

// safeRedirect() fonksiyonunun varlığını kontrol et
if (strpos($function_content, 'function safeRedirect') === false) {
    // Fonksiyon tanımı içeriğe ekle
    $safe_redirect_function = '
/**
 * Güvenli yönlendirme yapar, headers already sent hatası olmadan
 * 
 * @param string $url Yönlendirilecek URL
 * @return void
 */
function safeRedirect($url) {
    if (!headers_sent()) {
        header(\'Location: \' . $url);
        exit;
    } else {
        echo \'<script>window.location.href = "\' . $url . \'";</script>\';
        exit;
    }
}';

    // Dosya sonuna ekle (PHP kapanış etiketi öncesine)
    $function_content = str_replace('?>', $safe_redirect_function . "\n?>", $function_content);
    
    // Dosyayı güncelle
    file_put_contents($functions_file, $function_content);
    echo "safeRedirect() fonksiyonu functions.php dosyasına eklendi.\n";
}

echo "İşlem tamamlandı!\n";
