<?php
// Yapılandırma dosyasını yükle
require_once(__DIR__ . '/config/config.php');

// Oturumu sonlandır
session_start();
session_destroy();

// Giriş sayfasına yönlendir
redirect('login.php');
?>