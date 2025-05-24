<?php
// Yapılandırma dosyasını ve gerekli fonksiyonları yükle
require_once(__DIR__ . '/../config/config.php');
require_once(__DIR__ . '/../includes/functions.php');
require_once(__DIR__ . '/../includes/auth_functions.php');

// Kullanıcı giriş durumunu kontrol et
$is_logged_in = isLoggedIn();
$current_user = null;

if ($is_logged_in) {
    // Gerçek sistemde: Kullanıcı bilgilerini veritabanından al
    // Test amaçlı: Örnek kullanıcı bilgileri
    $current_user = [
        'id' => $_SESSION['user_id'] ?? 'test-user-id',
        'username' => $_SESSION['username'] ?? 'test_user',
        'email' => $_SESSION['email'] ?? 'test@example.com',
        'full_name' => $_SESSION['full_name'] ?? 'Test Kullanıcı'
    ];
}

$success_message = '';
$error_message = '';

// Form gönderildi mi kontrolü
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['submit_contact'])) {
    // Form alanlarını doğrula
    $request_type = $_POST['request_type'] ?? '';
    $full_name = $_POST['full_name'] ?? '';
    $email = $_POST['email'] ?? '';
    $phone = $_POST['phone'] ?? '';
    $description = $_POST['description'] ?? '';
    
    // Zorunlu alanları kontrol et
    if (empty($request_type) || empty($full_name) || empty($email) || empty($description)) {
        $error_message = 'Lütfen tüm zorunlu alanları doldurun.';
    } elseif (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
        $error_message = 'Lütfen geçerli bir e-posta adresi girin.';
    } else {
        // Kullanıcı ID'si kontrolü
        $user_id = $is_logged_in ? $current_user['id'] : 'guest';
        
        // Form verisini oluştur
        $contact_data = [
            'user_id' => $user_id,
            'request_type' => $request_type,
            'full_name' => $full_name,
            'email' => $email,
            'phone' => $phone,
            'description' => $description,
            'status' => 'open',
            'created_at' => date('Y-m-d H:i:s'),
            'updated_at' => date('Y-m-d H:i:s')
        ];
        
        // Veritabanına ekle (gerçek uygulamada)
        // $result = addData('contact_requests', $contact_data);
        
        // Test amaçlı: Her zaman başarılı olduğunu varsay
        $result = ['error' => false, 'message' => 'İletişim talebiniz başarıyla gönderildi.'];
        
        if (!$result['error']) {
            $success_message = 'İletişim talebiniz başarıyla alındı. En kısa sürede size dönüş yapılacaktır.';
            
            // Formu temizle
            $request_type = $full_name = $email = $phone = $description = '';
        } else {
            $error_message = 'İletişim talebi gönderilirken bir hata oluştu: ' . $result['message'];
        }
    }
}
?>

<!DOCTYPE html>
<html lang="tr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>İletişim Formu - Belediye Yönetim Sistemi</title>
    
    <!-- Bootstrap CSS -->
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0-alpha1/dist/css/bootstrap.min.css" rel="stylesheet">
    
    <!-- Font Awesome -->
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    
    <style>
        .contact-form-container {
            max-width: 800px;
            margin: 0 auto;
        }
        
        .request-type-card {
            cursor: pointer;
            transition: all 0.3s ease;
            height: 100%;
        }
        
        .request-type-card:hover {
            transform: translateY(-5px);
            box-shadow: 0 10px 20px rgba(0,0,0,0.1);
        }
        
        .request-type-card.selected {
            border-color: #0d6efd;
            box-shadow: 0 0 0 0.25rem rgba(13, 110, 253, 0.25);
        }
        
        .request-type-card .card-title {
            display: flex;
            align-items: center;
            gap: 10px;
        }
        
        .contact-info-section {
            padding: 20px;
            border-radius: 10px;
            margin-bottom: 30px;
        }
        
        .required-field::after {
            content: ' *';
            color: red;
        }
    </style>
</head>
<body>
    <?php include(__DIR__ . '/header.php'); ?>
    
    <div class="container my-5">
        <div class="contact-form-container">
            <h1 class="mb-4 text-center">Yönetimle İletişime Geç</h1>
            
            <div class="contact-info-section bg-light">
                <div class="row">
                    <div class="col-md-6">
                        <h4><i class="fas fa-info-circle me-2 text-primary"></i> İletişim Bilgileri</h4>
                        <ul class="list-unstyled mt-3">
                            <li><i class="fas fa-map-marker-alt me-2 text-secondary"></i> Belediye Binası, Merkez Mah. Ana Cadde No:123</li>
                            <li><i class="fas fa-phone me-2 text-secondary"></i> 444 XX XX</li>
                            <li><i class="fas fa-envelope me-2 text-secondary"></i> info@belediye.com</li>
                        </ul>
                    </div>
                    <div class="col-md-6">
                        <h4><i class="fas fa-clock me-2 text-primary"></i> Çalışma Saatleri</h4>
                        <ul class="list-unstyled mt-3">
                            <li><i class="fas fa-calendar-day me-2 text-secondary"></i> Pazartesi - Cuma: 08:30 - 17:30</li>
                            <li><i class="fas fa-calendar-day me-2 text-secondary"></i> Cumartesi: 09:00 - 13:00</li>
                            <li><i class="fas fa-calendar-day me-2 text-secondary"></i> Pazar: Kapalı</li>
                        </ul>
                    </div>
                </div>
            </div>
            
            <?php if (!empty($success_message)): ?>
                <div class="alert alert-success">
                    <i class="fas fa-check-circle me-2"></i> <?php echo $success_message; ?>
                </div>
            <?php endif; ?>
            
            <?php if (!empty($error_message)): ?>
                <div class="alert alert-danger">
                    <i class="fas fa-exclamation-circle me-2"></i> <?php echo $error_message; ?>
                </div>
            <?php endif; ?>
            
            <form method="post" action="" id="contactForm">
                <div class="mb-4">
                    <label class="form-label required-field">İletişim Nedeni</label>
                    <div class="row">
                        <div class="col-md-4 mb-3">
                            <div class="card request-type-card h-100" data-value="sorun">
                                <div class="card-body text-center">
                                    <h5 class="card-title justify-content-center">
                                        <i class="fas fa-exclamation-triangle text-danger"></i>
                                        <span>Sorun Bildir</span>
                                    </h5>
                                    <p class="card-text small">Belediye hizmetleri ile ilgili yaşadığınız sorunları bize bildirin.</p>
                                </div>
                            </div>
                        </div>
                        <div class="col-md-4 mb-3">
                            <div class="card request-type-card h-100" data-value="oneri">
                                <div class="card-body text-center">
                                    <h5 class="card-title justify-content-center">
                                        <i class="fas fa-lightbulb text-warning"></i>
                                        <span>Öneri Sun</span>
                                    </h5>
                                    <p class="card-text small">Belediye hizmetlerinin iyileştirilmesi için önerilerinizi paylaşın.</p>
                                </div>
                            </div>
                        </div>
                        <div class="col-md-4 mb-3">
                            <div class="card request-type-card h-100" data-value="reklam">
                                <div class="card-body text-center">
                                    <h5 class="card-title justify-content-center">
                                        <i class="fas fa-ad text-primary"></i>
                                        <span>Reklam & İşbirliği</span>
                                    </h5>
                                    <p class="card-text small">Reklam ve işbirliği için bizimle iletişime geçin.</p>
                                </div>
                            </div>
                        </div>
                    </div>
                    <input type="hidden" name="request_type" id="requestType" required>
                </div>
                
                <div class="row">
                    <div class="col-md-6 mb-3">
                        <label for="full_name" class="form-label required-field">Ad Soyad</label>
                        <input type="text" class="form-control" id="full_name" name="full_name" value="<?php echo $is_logged_in ? htmlspecialchars($current_user['full_name']) : ''; ?>" required>
                    </div>
                    <div class="col-md-6 mb-3">
                        <label for="email" class="form-label required-field">E-posta Adresi</label>
                        <input type="email" class="form-control" id="email" name="email" value="<?php echo $is_logged_in ? htmlspecialchars($current_user['email']) : ''; ?>" required>
                    </div>
                </div>
                
                <div class="mb-3">
                    <label for="phone" class="form-label">Telefon Numarası</label>
                    <input type="tel" class="form-control" id="phone" name="phone">
                    <div class="form-text">İsteğe bağlı</div>
                </div>
                
                <div class="mb-4">
                    <label for="description" class="form-label required-field">Mesajınız</label>
                    <textarea class="form-control" id="description" name="description" rows="5" required></textarea>
                </div>
                
                <div class="mb-3 form-check">
                    <input type="checkbox" class="form-check-input" id="privacyConsent" required>
                    <label class="form-check-label" for="privacyConsent">
                        Kişisel verilerimin işlenmesine izin veriyorum. <a href="#" data-bs-toggle="modal" data-bs-target="#privacyModal">Aydınlatma Metni</a>
                    </label>
                </div>
                
                <div class="d-grid gap-2">
                    <button type="submit" name="submit_contact" class="btn btn-primary btn-lg">
                        <i class="fas fa-paper-plane me-2"></i> Gönder
                    </button>
                </div>
            </form>
        </div>
    </div>
    
    <!-- Aydınlatma Metni Modal -->
    <div class="modal fade" id="privacyModal" tabindex="-1" aria-labelledby="privacyModalLabel" aria-hidden="true">
        <div class="modal-dialog modal-lg">
            <div class="modal-content">
                <div class="modal-header">
                    <h5 class="modal-title" id="privacyModalLabel">Kişisel Verilerin Korunması Aydınlatma Metni</h5>
                    <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Kapat"></button>
                </div>
                <div class="modal-body">
                    <p>Bu aydınlatma metni, 6698 sayılı Kişisel Verilerin Korunması Kanunu ("KVKK") uyarınca, veri sorumlusu sıfatıyla Belediye tarafından hazırlanmıştır.</p>
                    
                    <h5>1. Kişisel Verilerinizin İşlenme Amacı</h5>
                    <p>İletişim formunda paylaştığınız kişisel verileriniz, talebinizi değerlendirmek, yanıtlamak ve gerekli durumlarda sizinle iletişime geçmek amacıyla işlenmektedir.</p>
                    
                    <h5>2. Kişisel Verilerinizin Aktarılması</h5>
                    <p>Kişisel verileriniz, talebinizin niteliğine göre ilgili belediye birimleri ile paylaşılabilir. Bunun dışında, kanunen yetkili kamu kurumları ve özel kişiler dışında üçüncü kişilerle paylaşılmayacaktır.</p>
                    
                    <h5>3. Kişisel Veri Toplamanın Yöntemi ve Hukuki Sebebi</h5>
                    <p>Kişisel verileriniz, elektronik ortamda internet sitesi üzerindeki formlar aracılığıyla toplanmaktadır. Bu işlem, KVKK'nın 5. maddesinde belirtilen "ilgili kişinin temel hak ve özgürlüklerine zarar vermemek kaydıyla, veri sorumlusunun meşru menfaatleri için veri işlenmesinin zorunlu olması" hukuki sebebine dayanarak yapılmaktadır.</p>
                    
                    <h5>4. KVKK Kapsamındaki Haklarınız</h5>
                    <p>KVKK'nın 11. maddesi uyarınca, kişisel verileriniz ile ilgili olarak aşağıdaki haklara sahipsiniz:</p>
                    <ul>
                        <li>Kişisel verilerinizin işlenip işlenmediğini öğrenme</li>
                        <li>Kişisel verileriniz işlenmişse buna ilişkin bilgi talep etme</li>
                        <li>Kişisel verilerinizin işlenme amacını ve bunların amacına uygun kullanılıp kullanılmadığını öğrenme</li>
                        <li>Yurt içinde veya yurt dışında kişisel verilerinizin aktarıldığı üçüncü kişileri bilme</li>
                        <li>Kişisel verilerinizin eksik veya yanlış işlenmiş olması hâlinde bunların düzeltilmesini isteme</li>
                        <li>KVKK'nın 7. maddesinde öngörülen şartlar çerçevesinde kişisel verilerinizin silinmesini veya yok edilmesini isteme</li>
                        <li>Kişisel verilerinizin aktarıldığı üçüncü kişilere düzeltilme, silme veya yok edilme işleminin bildirilmesini isteme</li>
                        <li>İşlenen verilerin münhasıran otomatik sistemler vasıtasıyla analiz edilmesi suretiyle aleyhinize bir sonucun ortaya çıkmasına itiraz etme</li>
                        <li>Kişisel verilerinizin kanuna aykırı olarak işlenmesi sebebiyle zarara uğramanız hâlinde zararın giderilmesini talep etme</li>
                    </ul>
                </div>
                <div class="modal-footer">
                    <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Kapat</button>
                </div>
            </div>
        </div>
    </div>
    
    <?php include(__DIR__ . '/footer.php'); ?>
    
    <!-- Bootstrap JS ve diğer gerekli scriptler -->
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0-alpha1/dist/js/bootstrap.bundle.min.js"></script>
    
    <script>
    document.addEventListener('DOMContentLoaded', function() {
        const requestTypeCards = document.querySelectorAll('.request-type-card');
        const requestTypeInput = document.getElementById('requestType');
        const contactForm = document.getElementById('contactForm');
        
        // İletişim nedeni kartlarına tıklama olayı ekle
        requestTypeCards.forEach(card => {
            card.addEventListener('click', function() {
                // Tüm kartlardan 'selected' sınıfını kaldır
                requestTypeCards.forEach(c => c.classList.remove('selected'));
                
                // Tıklanan karta 'selected' sınıfını ekle
                this.classList.add('selected');
                
                // Gizli input'a değeri ata
                requestTypeInput.value = this.dataset.value;
            });
        });
        
        // Form gönderilmeden önce kontrol
        contactForm.addEventListener('submit', function(e) {
            if (!requestTypeInput.value) {
                e.preventDefault();
                alert('Lütfen bir iletişim nedeni seçin.');
                return false;
            }
            
            if (!document.getElementById('privacyConsent').checked) {
                e.preventDefault();
                alert('Devam etmek için kişisel verilerin işlenmesine izin vermeniz gerekmektedir.');
                return false;
            }
        });
    });
    </script>
</body>
</html>