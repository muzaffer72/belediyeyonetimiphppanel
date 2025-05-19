<?php
// Oturum başlat
session_start();

// Hata raporlamasını açık tut
ini_set('display_errors', 1);
ini_set('display_startup_errors', 1);
error_reporting(E_ALL);

// Zaman dilimini ayarla 
date_default_timezone_set('Europe/Istanbul');

// Temel sabitler
define('SITE_TITLE', 'Belediye Yönetim Paneli');
define('SITE_URL', 'https://onvao.net/adminpanel');
define('ASSETS_URL', SITE_URL . '/assets');

// Çevre değişkenleri
$_ENV['SUPABASE_URL'] = getenv('SUPABASE_URL') ?: 'https://bimer.onvao.net:8443';
$_ENV['SUPABASE_KEY'] = getenv('SUPABASE_SERVICE_ROLE_KEY') ?: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyAgCiAgICAicm9sZSI6ICJzZXJ2aWNlX3JvbGUiLAogICAgImlzcyI6ICJzdXBhYmFzZS1kZW1vIiwKICAgICJpYXQiOiAxNjQxNzY5MjAwLAogICAgImV4cCI6IDE3OTk1MzU2MDAKfQ.DaYlNEoUrrEn2Ig7tqibS-PHK5vgusbcbo7X36XVt4Q';

// API sabitleri
define('SUPABASE_REST_URL', $_ENV['SUPABASE_URL'] . '/rest/v1');
define('SUPABASE_API_KEY', $_ENV['SUPABASE_KEY']);
define('SUPABASE_AUTH_HEADER', 'Bearer ' . $_ENV['SUPABASE_KEY']);

// Yönetici kimlik bilgileri (gerçek uygulamada bunlar veritabanında olmalı)
define('ADMIN_USERNAME', 'admin');
define('ADMIN_PASSWORD', 'admin123');

// Özel fonksiyonlar
/**
 * XSS saldırılarına karşı HTML ve karakterleri temizle
 * 
 * @param string $value Temizlenecek değer
 * @return string Temizlenmiş değer
 */
function escape($value) {
    return htmlspecialchars($value, ENT_QUOTES, 'UTF-8');
}

/**
 * Mesaj göster (başarı, hata, bilgi, uyarı)
 * 
 * @param string $type Mesaj tipi (success, danger, info, warning)
 * @param string $message Mesaj içeriği
 * @return string HTML alert
 */
function showAlert($type, $message) {
    return '<div class="alert alert-' . $type . ' alert-dismissible fade show" role="alert">
                ' . $message . '
                <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Kapat"></button>
            </div>';
}

/**
 * Kullanıcının oturum durumunu kontrol et
 * 
 * @return bool Oturum durumu
 */
function isLoggedIn() {
    return isset($_SESSION['admin_logged_in']) && $_SESSION['admin_logged_in'] === true || 
           isset($_SESSION['user_id']);
}

/**
 * Kullanıcının admin olup olmadığını kontrol eder
 * 
 * @return bool Admin ise true, değilse false
 */
function isAdmin() {
    return isset($_SESSION['is_admin']) && $_SESSION['is_admin'] === true || 
           (isset($_SESSION['admin_logged_in']) && $_SESSION['admin_logged_in'] === true);
}

/**
 * Kullanıcının belediye görevlisi olup olmadığını kontrol eder
 * 
 * @return bool Belediye görevlisi ise true, değilse false
 */
function isOfficial() {
    return isset($_SESSION['is_official']) && $_SESSION['is_official'] === true;
}

/**
 * Tarih formatla
 * 
 * @param string $date ISO 8601 tarih formatı
 * @param string $format Çıktı formatı
 * @return string Formatlanmış tarih
 */
function formatDate($date, $format = 'd.m.Y H:i') {
    if (empty($date)) return '-';
    
    $timestamp = strtotime($date);
    return date($format, $timestamp);
}

/**
 * Yönlendirme yap
 * 
 * @param string $url Yönlendirilecek URL
 * @return void
 */
function redirect($url) {
    if (!headers_sent()) {
        header('Location: ' . $url);
        exit;
    } else {
        echo '<script>window.location.href="' . $url . '";</script>';
        echo '<noscript><meta http-equiv="refresh" content="0;url=' . $url . '"></noscript>';
        exit;
    }
}

/**
 * Metni kısalt
 * 
 * @param string $text Metin
 * @param int $length Maksimum uzunluk
 * @return string Kısaltılmış metin
 */
function truncateText($text, $length = 100) {
    if (mb_strlen($text, 'UTF-8') <= $length) {
        return $text;
    }
    
    return rtrim(mb_substr($text, 0, $length, 'UTF-8')) . '...';
}

// functions.php dahil et - tüm sayfalardan erişilebilir olması için global scope'da dahil ediyoruz
require_once(__DIR__ . '/../includes/functions.php');
?>