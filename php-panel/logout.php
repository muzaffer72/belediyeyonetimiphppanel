<?php
// Konfigürasyon dosyası
require_once 'config/config.php';

// Oturum değişkenlerini temizle
session_unset();

// Oturumu sonlandır
session_destroy();

// Giriş sayfasına yönlendir
header('Location: login.php');
exit;
?>