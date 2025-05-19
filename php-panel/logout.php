<?php
// Yapılandırma dosyasını yükle
require_once(__DIR__ . '/config/config.php');
require_once(__DIR__ . '/includes/auth_functions.php');

// Oturumu sonlandır
session_start();
logout();

// Giriş sayfasına yönlendir
redirect('login.php');
?>