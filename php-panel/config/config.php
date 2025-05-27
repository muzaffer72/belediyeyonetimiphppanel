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

// functions.php dahil et - tüm sayfalardan erişilebilir olması için global scope'da dahil ediyoruz
require_once(__DIR__ . '/../includes/functions.php');

// YARDIMCI FONKSİYONLAR - fonksiyon çakışmalarını önlemek için function_exists kontrolleri ekledik
if (!function_exists('escape')) {
    /**
     * XSS saldırılarına karşı HTML ve karakterleri temizle
     * 
     * @param string $value Temizlenecek değer
     * @return string Temizlenmiş değer
     */
    function escape($value) {
        return htmlspecialchars($value, ENT_QUOTES, 'UTF-8');
    }
}

if (!function_exists('showAlert')) {
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
}

if (!function_exists('isLoggedIn')) {
    /**
     * Kullanıcının oturum durumunu kontrol et
     * 
     * @return bool Oturum durumu
     */
    function isLoggedIn() {
        return isset($_SESSION['admin_logged_in']) && $_SESSION['admin_logged_in'] === true || 
               isset($_SESSION['user_id']) || isset($_SESSION['logged_in']) && $_SESSION['logged_in'] === true;
    }
}

if (!function_exists('isAdmin')) {
    /**
     * Kullanıcının admin olup olmadığını kontrol eder
     * 
     * @return bool Admin ise true, değilse false
     */
    function isAdmin() {
        return isset($_SESSION['is_admin']) && $_SESSION['is_admin'] === true || 
               (isset($_SESSION['admin_logged_in']) && $_SESSION['admin_logged_in'] === true);
    }
}

if (!function_exists('isOfficial')) {
    /**
     * Kullanıcının belediye personeli olup olmadığını kontrol eder
     * 
     * @return bool Belediye personeli ise true, değilse false
     */
    function isOfficial() {
        return isset($_SESSION['user_type']) && $_SESSION['user_type'] === 'official';
    }
}

if (!function_exists('isModerator')) {
    /**
     * Kullanıcının moderatör olup olmadığını kontrol eder
     * 
     * @return bool Moderatör ise true, değilse false
     */
    function isModerator() {
        return isset($_SESSION['user_type']) && $_SESSION['user_type'] === 'moderator';
    }
}

if (!function_exists('hasPermission')) {
    /**
     * Kullanıcının belirli bir işlem için yetkisi olup olmadığını kontrol eder
     * 
     * @param string $permission Yetki türü (admin, moderator, official)
     * @return bool Yetki var ise true, yoksa false
     */
    function hasPermission($permission) {
        $user_type = $_SESSION['user_type'] ?? '';
        
        switch ($permission) {
            case 'admin':
                return $user_type === 'admin';
            case 'moderator':
                return $user_type === 'admin' || $user_type === 'moderator';
            case 'official':
                return $user_type === 'admin' || $user_type === 'moderator' || $user_type === 'official';
            default:
                return false;
        }
    }
}

if (!function_exists('getUserCity')) {
    /**
     * Kullanıcının atanmış şehrini getirir
     * 
     * @return string|null Şehir ID'si veya null
     */
    function getUserCity() {
        return $_SESSION['assigned_city_id'] ?? null;
    }
}

if (!function_exists('getUserDistrict')) {
    /**
     * Kullanıcının atanmış ilçesini getirir
     * 
     * @return string|null İlçe ID'si veya null
     */
    function getUserDistrict() {
        return $_SESSION['assigned_district_id'] ?? null;
    }
}

if (!function_exists('formatDate')) {
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
}

if (!function_exists('formatDateStr')) {
    /**
     * Alternatif tarih formatla - formatDate ile çakışma olduğunda kullanılır
     * 
     * @param string $date ISO 8601 tarih formatı
     * @param string $format Çıktı formatı
     * @return string Formatlanmış tarih
     */
    function formatDateStr($date, $format = 'd.m.Y H:i') {
        if (empty($date)) return '-';
        
        $timestamp = strtotime($date);
        return date($format, $timestamp);
    }
}

if (!function_exists('redirect')) {
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
}

if (!function_exists('updateData')) {
    /**
     * Veri güncelleme fonksiyonu
     * 
     * @param string $table Tablo adı
     * @param string $id Güncellenecek kayıt ID'si
     * @param array $data Güncellenecek veriler
     * @return array Sonuç
     */
    function updateData($table, $id, $data) {
        $url = SUPABASE_URL . "/rest/v1/$table?id=eq.$id";
        
        $options = [
            'http' => [
                'header' => [
                    "Content-Type: application/json",
                    "Authorization: Bearer " . SUPABASE_SERVICE_KEY,
                    "apikey: " . SUPABASE_SERVICE_KEY,
                    "Prefer: return=minimal"
                ],
                'method' => 'PATCH',
                'content' => json_encode($data)
            ]
        ];
        
        $context = stream_context_create($options);
        $response = file_get_contents($url, false, $context);
        
        if ($response === FALSE) {
            return [
                'error' => true,
                'message' => 'Veri güncellenirken bir hata oluştu'
            ];
        }
        
        return [
            'error' => false,
            'message' => 'Veri başarıyla güncellendi'
        ];
    }
}

if (!function_exists('addData')) {
    /**
     * Veri ekleme fonksiyonu
     * 
     * @param string $table Tablo adı
     * @param array $data Eklenecek veriler
     * @return array Sonuç
     */
    function addData($table, $data) {
        // ID alanını ekle (UUID oluştur)
        if (!isset($data['id'])) {
            $data['id'] = generateUUID();
        }
        
        $url = SUPABASE_URL . "/rest/v1/$table";
        
        $options = [
            'http' => [
                'header' => [
                    "Content-Type: application/json",
                    "Authorization: Bearer " . SUPABASE_SERVICE_KEY,
                    "apikey: " . SUPABASE_SERVICE_KEY,
                    "Prefer: return=minimal"
                ],
                'method' => 'POST',
                'content' => json_encode($data)
            ]
        ];
        
        $context = stream_context_create($options);
        $response = file_get_contents($url, false, $context);
        
        if ($response === FALSE) {
            return [
                'error' => true,
                'message' => 'Veri eklenirken bir hata oluştu'
            ];
        }
        
        return [
            'error' => false,
            'message' => 'Veri başarıyla eklendi',
            'data' => $data
        ];
    }
}

if (!function_exists('generateUUID')) {
    /**
     * UUID oluşturma fonksiyonu
     * 
     * @return string UUID
     */
    function generateUUID() {
        return sprintf('%04x%04x-%04x-%04x-%04x-%04x%04x%04x',
            mt_rand(0, 0xffff), mt_rand(0, 0xffff),
            mt_rand(0, 0xffff),
            mt_rand(0, 0x0fff) | 0x4000,
            mt_rand(0, 0x3fff) | 0x8000,
            mt_rand(0, 0xffff), mt_rand(0, 0xffff), mt_rand(0, 0xffff)
        );
    }
}

if (!function_exists('truncateText')) {
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
}
?>