<?php
// Database credentials
$host = getenv('PGHOST');
$port = getenv('PGPORT');
$dbname = getenv('PGDATABASE');
$user = getenv('PGUSER');
$password = getenv('PGPASSWORD');

// Create connection string
$dsn = "pgsql:host=$host;port=$port;dbname=$dbname;user=$user;password=$password";

try {
    // Create a PDO instance
    $pdo = new PDO($dsn);
    
    // Set the PDO error mode to exception
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    
    // Set default fetch mode to associative array
    $pdo->setAttribute(PDO::ATTR_DEFAULT_FETCH_MODE, PDO::FETCH_ASSOC);
    
    // Set character set
    $pdo->exec("SET NAMES 'UTF8'");
    
} catch(PDOException $e) {
    // Log error but don't show details to users
    error_log("Connection failed: " . $e->getMessage());
    die("Veritabanı bağlantısı kurulamadı. Lütfen daha sonra tekrar deneyin.");
}

// Application settings
define('SITE_NAME', 'Belediye Yönetim Paneli');
define('SITE_URL', isset($_SERVER['HTTPS']) ? 'https://' : 'http://' . $_SERVER['HTTP_HOST']);
define('ADMIN_EMAIL', 'admin@belediye.gov.tr');

// Time zone settings
date_default_timezone_set('Europe/Istanbul');

// Error reporting - Turn off in production
ini_set('display_errors', 1);
ini_set('display_startup_errors', 1);
error_reporting(E_ALL);
?>