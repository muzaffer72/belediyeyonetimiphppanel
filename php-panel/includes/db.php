<?php
/**
 * Veritabanı bağlantısı
 */
require_once(__DIR__ . '/../config/config.php');

// Veritabanı bağlantısı
$db_conn = null;
$db_error = '';

try {
    // DATABASE_URL'den bağlantı bilgilerini al
    $db_url = getenv('DATABASE_URL');
    
    if (!$db_url) {
        throw new Exception("Veritabanı bağlantı bilgisi (DATABASE_URL) bulunamadı!");
    }
    
    // Supabase/PostgreSQL bağlantı URL'sini ayrıştır
    $url_parts = parse_url($db_url);
    $host = $url_parts['host'] ?? '';
    $port = $url_parts['port'] ?? '5432';
    $user = $url_parts['user'] ?? '';
    $password = $url_parts['pass'] ?? '';
    $dbname = ltrim($url_parts['path'] ?? '', '/');
    
    // Bağlantı dizesini oluştur
    $conn_string = "host=$host port=$port dbname=$dbname user=$user password=$password";
    
    // Bağlantıyı aç
    $db_conn = pg_connect($conn_string);
    
    if (!$db_conn) {
        throw new Exception("Veritabanı bağlantısı başarısız oldu!");
    }
} catch (Exception $e) {
    $db_error = $e->getMessage();
    // Hata mesajını kaydet ancak uygulamayı durdurma, gerekirse kontroller yapılacak
}

/**
 * Veritabanı sorgusu çalıştırır
 */
function db_query($sql, $params = []) {
    global $db_conn;
    
    if (!$db_conn) {
        return false;
    }
    
    try {
        // Parametreli sorgu çalıştırma
        if (!empty($params)) {
            $result = pg_query_params($db_conn, $sql, $params);
        } else {
            $result = pg_query($db_conn, $sql);
        }
        
        return $result;
    } catch (Exception $e) {
        error_log("Veritabanı sorgu hatası: " . $e->getMessage());
        return false;
    }
}

/**
 * Sonuçları dizi olarak döndürür
 */
function db_fetch_all($result) {
    if (!$result) {
        return [];
    }
    
    return pg_fetch_all($result) ?: [];
}

/**
 * Tek bir satırı döndürür
 */
function db_fetch_one($result) {
    if (!$result) {
        return null;
    }
    
    return pg_fetch_assoc($result) ?: null;
}

/**
 * Son eklenen kaydın ID'sini döndürür
 */
function db_last_insert_id($table, $id_column = 'id') {
    global $db_conn;
    
    $sql = "SELECT lastval() as id";
    $result = pg_query($db_conn, $sql);
    
    if ($result) {
        $row = pg_fetch_assoc($result);
        return $row['id'] ?? null;
    }
    
    return null;
}

/**
 * Veritabanı bağlantısını kapatır
 */
function db_close() {
    global $db_conn;
    
    if ($db_conn) {
        pg_close($db_conn);
    }
}