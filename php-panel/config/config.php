<?php
// Veritabanı ve uygulama ayarları

// Uygulama bilgileri
define('APP_NAME', 'Belediye Yönetim Paneli');
define('APP_URL', 'http://localhost:3000');

// Supabase API bağlantı bilgileri
define('SUPABASE_URL', 'https://bimer.onvao.net:8443/rest/v1');
define('SUPABASE_KEY', 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyAgCiAgICAicm9sZSI6ICJzZXJ2aWNlX3JvbGUiLAogICAgImlzcyI6ICJzdXBhYmFzZS1kZW1vIiwKICAgICJpYXQiOiAxNjQxNzY5MjAwLAogICAgImV4cCI6IDE3OTk1MzU2MDAKfQ.DaYlNEoUrrEn2Ig7tqibS-PHK5vgusbcbo7X36XVt4Q');

// Environment değişkenlerinden değerleri al (varsa)
$env_supabase_url = getenv('SUPABASE_URL');
$env_supabase_key = getenv('SUPABASE_SERVICE_ROLE_KEY');

if ($env_supabase_url) {
    define('API_URL', $env_supabase_url);
} else {
    define('API_URL', SUPABASE_URL);
}

if ($env_supabase_key) {
    define('API_KEY', $env_supabase_key);
} else {
    define('API_KEY', SUPABASE_KEY);
}

// Sayfa başlıkları
$page_titles = [
    'dashboard' => 'Gösterge Paneli',
    'cities' => 'Şehirler',
    'districts' => 'İlçeler',
    'posts' => 'Gönderiler',
    'comments' => 'Yorumlar',
    'announcements' => 'Duyurular',
    'users' => 'Kullanıcılar',
    'parties' => 'Siyasi Partiler',
    'settings' => 'Ayarlar',
    'login' => 'Giriş Yap',
    'logout' => 'Çıkış Yap'
];

// Hata raporlama ayarları (geliştirme ortamında açık, üretimde kapalı)
ini_set('display_errors', 1);
ini_set('display_startup_errors', 1);
error_reporting(E_ALL);

// Zaman dilimi ayarı
date_default_timezone_set('Europe/Istanbul');