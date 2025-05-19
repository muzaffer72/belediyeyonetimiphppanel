<?php
/**
 * Kullanıcı kimlik doğrulama fonksiyonları
 */

/**
 * Supabase API ile kullanıcı girişi yapar
 * 
 * @param array $login_data Giriş bilgileri (email ve password)
 * @return array Sonuç ve hata bilgisini içeren dizi
 */
function supabaseLogin($login_data) {
    try {
        $email = $login_data['email'] ?? '';
        $password = $login_data['password'] ?? '';
        
        if (empty($email) || empty($password)) {
            return ['error' => true, 'message' => 'E-posta ve şifre gereklidir'];
        }
        
        // Supabase Auth API URL
        $url = getenv('SUPABASE_URL') . '/auth/v1/token?grant_type=password';
        
        // API isteği yap
        $ch = curl_init();
        curl_setopt($ch, CURLOPT_URL, $url);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_POST, true);
        curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode([
            'email' => $email,
            'password' => $password
        ]));
        curl_setopt($ch, CURLOPT_HTTPHEADER, [
            'apikey: ' . getenv('SUPABASE_SERVICE_ROLE_KEY'),
            'Content-Type: application/json'
        ]);
        
        $response = curl_exec($ch);
        $status_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        
        // API yanıtını kontrol et
        if ($status_code >= 200 && $status_code < 300) {
            $result = json_decode($response, true);
            return ['error' => false, 'data' => $result, 'message' => 'Giriş başarılı'];
        } else {
            $error = json_decode($response, true);
            $error_message = isset($error['error_description']) ? $error['error_description'] : "Hatalı e-posta veya şifre";
            return ['error' => true, 'message' => $error_message];
        }
    } catch (Exception $e) {
        return ['error' => true, 'message' => 'Giriş hatası: ' . $e->getMessage()];
    }
}

/**
 * Kullanıcının admin olup olmadığını kontrol eder
 * Config.php içindeki isLoggedIn fonksiyonunu genişletir
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
 * Kullanıcı çıkışı yapar
 */
function logout() {
    $_SESSION = array();
    session_destroy();
}