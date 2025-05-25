<?php
// Admin kullanıcısı oluşturma scripti
require_once 'config/config.php';
require_once 'includes/functions.php';

echo "<h2>Admin Kullanıcısı Oluşturuluyor...</h2>";

// Şifreyi hash'le
$password = '005434677197';
$hashed_password = password_hash($password, PASSWORD_DEFAULT);

// Admin kullanıcı verilerini hazırla
$admin_data = [
    'username' => 'admin',
    'email' => 'mail@muzaffersanli.com',
    'password' => $hashed_password,
    'name' => 'Muzaffer Şanlı',
    'role' => 'admin',
    'is_active' => true,
    'created_at' => date('Y-m-d H:i:s')
];

// Önce kullanıcının var olup olmadığını kontrol et
$existing_user = getData('users', ['email' => 'eq.mail@muzaffersanli.com']);

if (!$existing_user['error'] && !empty($existing_user['data'])) {
    echo "✅ Kullanıcı zaten mevcut. Bilgileri güncelleniyor...<br>";
    
    // Mevcut kullanıcıyı güncelle
    $user_id = $existing_user['data'][0]['id'];
    $update_result = updateData('users', $user_id, [
        'username' => 'admin',
        'password' => $hashed_password,
        'name' => 'Muzaffer Şanlı',
        'role' => 'admin',
        'is_active' => true,
        'updated_at' => date('Y-m-d H:i:s')
    ]);
    
    if (!$update_result['error']) {
        echo "🎉 Admin kullanıcısı başarıyla güncellendi!<br>";
    } else {
        echo "❌ Güncelleme hatası: " . $update_result['message'] . "<br>";
    }
} else {
    echo "📝 Yeni admin kullanıcısı oluşturuluyor...<br>";
    
    // Yeni kullanıcı oluştur
    $create_result = addData('users', $admin_data);
    
    if (!$create_result['error']) {
        echo "🎉 Admin kullanıcısı başarıyla oluşturuldu!<br>";
    } else {
        echo "❌ Oluşturma hatası: " . $create_result['message'] . "<br>";
    }
}

echo "<br><hr>";
echo "<h3>📋 Giriş Bilgileri:</h3>";
echo "<strong>Email:</strong> mail@muzaffersanli.com<br>";
echo "<strong>Şifre:</strong> 005434677197<br>";
echo "<strong>Rol:</strong> Admin<br>";

echo "<br><a href='/php-panel/login.php'>🔑 Giriş Yap</a> | ";
echo "<a href='/php-panel/'>📋 Ana Sayfa</a>";
?>