<?php
// Yapılandırma dosyasını ve gerekli fonksiyonları yükle
require_once(__DIR__ . '/../config/config.php');
require_once(__DIR__ . '/../includes/functions.php');
require_once(__DIR__ . '/../includes/auth_functions.php');

// Sadece yönetici erişimi kontrolü
if (!isAdmin()) {
    redirect('index.php?page=dashboard');
}

// İşlem parametrelerini al
$action = isset($_GET['action']) ? $_GET['action'] : '';
$request_id = isset($_GET['id']) ? $_GET['id'] : '';
$success_message = '';
$error_message = '';

// Talep durumunu güncelleme
if ($action === 'update_status' && !empty($request_id)) {
    $new_status = isset($_POST['status']) ? $_POST['status'] : '';
    
    if ($new_status === 'closed') {
        // Talebi kapat
        $update_data = [
            'status' => 'closed',
            'closed_at' => date('Y-m-d H:i:s'),
            'updated_at' => date('Y-m-d H:i:s')
        ];
        
        // Gerçek ortamda: Veritabanını güncelle
        // $result = updateData('contact_requests', $request_id, $update_data);
        
        // Test ortamında başarılı olduğunu varsay
        $result = ['error' => false, 'message' => 'Talep başarıyla kapatıldı.'];
        
        if (!$result['error']) {
            $success_message = 'Talep başarıyla kapatıldı.';
        } else {
            $error_message = 'Talep durumu güncellenirken bir hata oluştu: ' . $result['message'];
        }
    } elseif ($new_status === 'open') {
        // Talebi yeniden aç
        $update_data = [
            'status' => 'open',
            'closed_at' => null,
            'updated_at' => date('Y-m-d H:i:s')
        ];
        
        // Gerçek ortamda: Veritabanını güncelle
        // $result = updateData('contact_requests', $request_id, $update_data);
        
        // Test ortamında başarılı olduğunu varsay
        $result = ['error' => false, 'message' => 'Talep başarıyla yeniden açıldı.'];
        
        if (!$result['error']) {
            $success_message = 'Talep başarıyla yeniden açıldı.';
        } else {
            $error_message = 'Talep durumu güncellenirken bir hata oluştu: ' . $result['message'];
        }
    }
}

// Talebe yanıt gönderme
if ($action === 'reply' && !empty($request_id) && isset($_POST['response_text'])) {
    $response_text = trim($_POST['response_text']);
    
    if (empty($response_text)) {
        $error_message = 'Yanıt metni boş olamaz.';
    } else {
        $admin_id = $_SESSION['user_id'];
        
        $response_data = [
            'request_id' => $request_id,
            'admin_id' => $admin_id,
            'response_text' => $response_text,
            'created_at' => date('Y-m-d H:i:s')
        ];
        
        // Gerçek ortamda: Veritabanına yanıt ekle
        // $result = addData('contact_request_responses', $response_data);
        
        // Test ortamında başarılı olduğunu varsay
        $result = ['error' => false, 'message' => 'Yanıt başarıyla gönderildi.'];
        
        if (!$result['error']) {
            // Yanıt gönderildikten sonra talebin durumunu güncelle (isteğe bağlı)
            $update_data = [
                'updated_at' => date('Y-m-d H:i:s')
            ];
            
            // Gerçek ortamda: Veritabanını güncelle
            // updateData('contact_requests', $request_id, $update_data);
            
            $success_message = 'Yanıtınız başarıyla gönderildi.';
        } else {
            $error_message = 'Yanıt gönderilirken bir hata oluştu: ' . $result['message'];
        }
    }
}

// Test verileri: İletişim talepleri
$contact_requests = [
    [
        'id' => 'f47ac10b-58cc-4372-a567-0e02b2c3d479',
        'user_id' => '83190944-98d5-41be-ac3a-178676faf017',
        'request_type' => 'sorun',
        'full_name' => 'Ahmet Yılmaz',
        'email' => 'ahmet@example.com',
        'phone' => '05551234567',
        'description' => 'Mahallemizde bulunan parkın aydınlatmaları çalışmıyor. Özellikle akşam saatlerinde güvenlik sorunu yaşıyoruz. Lütfen ilgilenin.',
        'status' => 'open',
        'created_at' => date('Y-m-d H:i:s', strtotime('-3 days')),
        'updated_at' => date('Y-m-d H:i:s', strtotime('-3 days')),
        'closed_at' => null
    ],
    [
        'id' => '550e8400-e29b-41d4-a716-446655440000',
        'user_id' => '83190944-98d5-41be-ac3a-178676faf018',
        'request_type' => 'oneri',
        'full_name' => 'Fatma Demir',
        'email' => 'fatma@example.com',
        'phone' => '05559876543',
        'description' => 'Merkez caddesinde bisiklet yolu yapılmasını öneriyorum. Hem trafik rahatlar hem de çevre dostu bir ulaşım alternatifi olur.',
        'status' => 'open',
        'created_at' => date('Y-m-d H:i:s', strtotime('-5 days')),
        'updated_at' => date('Y-m-d H:i:s', strtotime('-5 days')),
        'closed_at' => null
    ],
    [
        'id' => '660e8400-e29b-41d4-a716-446655593166',
        'user_id' => '83190944-98d5-41be-ac3a-178676faf019',
        'request_type' => 'reklam',
        'full_name' => 'Mehmet Kaya',
        'email' => 'mehmet@example.com',
        'phone' => '05557894561',
        'description' => 'Belediye kültür etkinliklerinde firmamızın sponsor olması ile ilgili görüşmek istiyoruz. Detayları konuşmak için iletişime geçebilir misiniz?',
        'status' => 'closed',
        'created_at' => date('Y-m-d H:i:s', strtotime('-10 days')),
        'updated_at' => date('Y-m-d H:i:s', strtotime('-8 days')),
        'closed_at' => date('Y-m-d H:i:s', strtotime('-8 days'))
    ]
];

// Test verileri: Yanıtlar
$contact_responses = [
    [
        'id' => 'a47ac10b-58cc-4372-a567-0e02b2c3d111',
        'request_id' => '660e8400-e29b-41d4-a716-446655593166',
        'admin_id' => 'admin',
        'response_text' => 'Sayın Mehmet Kaya, talebiniz için teşekkür ederiz. Sponsorluk konusunu görüşmek üzere Kültür İşleri Müdürlüğümüz sizinle iletişime geçecektir. İyi günler dileriz.',
        'created_at' => date('Y-m-d H:i:s', strtotime('-8 days'))
    ]
];

// Tüm yanıtları talep ID'sine göre gruplayalım
$responses_by_request = [];
foreach ($contact_responses as $response) {
    $request_id = $response['request_id'];
    if (!isset($responses_by_request[$request_id])) {
        $responses_by_request[$request_id] = [];
    }
    $responses_by_request[$request_id][] = $response;
}

// Filtre ayarları
$status_filter = isset($_GET['status']) ? $_GET['status'] : '';
$type_filter = isset($_GET['type']) ? $_GET['type'] : '';

// Filtreleme uygula
$filtered_requests = array_filter($contact_requests, function($request) use ($status_filter, $type_filter) {
    $status_match = empty($status_filter) || $request['status'] === $status_filter;
    $type_match = empty($type_filter) || $request['request_type'] === $type_filter;
    return $status_match && $type_match;
});

// Talep tiplerini renklerle eşleştir
$request_types = [
    'sorun' => ['name' => 'Sorun', 'color' => 'danger', 'icon' => 'fa-exclamation-triangle'],
    'oneri' => ['name' => 'Öneri', 'color' => 'warning', 'icon' => 'fa-lightbulb'],
    'reklam' => ['name' => 'Reklam & İşbirliği', 'color' => 'primary', 'icon' => 'fa-ad']
];

// Talep detayını göster
$show_detail = false;
$current_request = null;
$current_responses = [];

if ($action === 'view' && !empty($request_id)) {
    // Talebi bul
    foreach ($contact_requests as $request) {
        if ($request['id'] === $request_id) {
            $current_request = $request;
            break;
        }
    }
    
    // Yanıtları bul
    $current_responses = $responses_by_request[$request_id] ?? [];
    
    $show_detail = !empty($current_request);
}
?>

<div class="container-fluid px-4">
    <h1 class="mt-4">İletişim Talepleri</h1>
    <ol class="breadcrumb mb-4">
        <li class="breadcrumb-item"><a href="index.php?page=dashboard">Kontrol Paneli</a></li>
        <li class="breadcrumb-item active">İletişim Talepleri</li>
    </ol>
    
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
    
    <div class="row">
        <?php if ($show_detail): ?>
            <!-- Talep Detayı -->
            <div class="col-md-12">
                <div class="card mb-4">
                    <div class="card-header d-flex justify-content-between align-items-center">
                        <div>
                            <i class="fas <?php echo $request_types[$current_request['request_type']]['icon']; ?> me-1 text-<?php echo $request_types[$current_request['request_type']]['color']; ?>"></i>
                            Talep Detayı #<?php echo substr($current_request['id'], 0, 8); ?>
                        </div>
                        <div>
                            <a href="index.php?page=contact_requests" class="btn btn-sm btn-outline-secondary">
                                <i class="fas fa-arrow-left me-1"></i> Listeye Dön
                            </a>
                        </div>
                    </div>
                    <div class="card-body">
                        <div class="row mb-4">
                            <div class="col-md-6">
                                <h5>Talep Bilgileri</h5>
                                <table class="table table-bordered">
                                    <tr>
                                        <th style="width: 150px;">Talep Tipi</th>
                                        <td>
                                            <span class="badge bg-<?php echo $request_types[$current_request['request_type']]['color']; ?>">
                                                <i class="fas <?php echo $request_types[$current_request['request_type']]['icon']; ?> me-1"></i>
                                                <?php echo $request_types[$current_request['request_type']]['name']; ?>
                                            </span>
                                        </td>
                                    </tr>
                                    <tr>
                                        <th>Durum</th>
                                        <td>
                                            <?php if ($current_request['status'] === 'open'): ?>
                                                <span class="badge bg-success">Açık</span>
                                            <?php else: ?>
                                                <span class="badge bg-secondary">Kapalı</span>
                                            <?php endif; ?>
                                        </td>
                                    </tr>
                                    <tr>
                                        <th>Oluşturulma Tarihi</th>
                                        <td><?php echo date('d.m.Y H:i', strtotime($current_request['created_at'])); ?></td>
                                    </tr>
                                    <?php if ($current_request['closed_at']): ?>
                                        <tr>
                                            <th>Kapatılma Tarihi</th>
                                            <td><?php echo date('d.m.Y H:i', strtotime($current_request['closed_at'])); ?></td>
                                        </tr>
                                    <?php endif; ?>
                                </table>
                            </div>
                            <div class="col-md-6">
                                <h5>Kişi Bilgileri</h5>
                                <table class="table table-bordered">
                                    <tr>
                                        <th style="width: 150px;">Ad Soyad</th>
                                        <td><?php echo htmlspecialchars($current_request['full_name']); ?></td>
                                    </tr>
                                    <tr>
                                        <th>E-posta</th>
                                        <td><?php echo htmlspecialchars($current_request['email']); ?></td>
                                    </tr>
                                    <?php if (!empty($current_request['phone'])): ?>
                                        <tr>
                                            <th>Telefon</th>
                                            <td><?php echo htmlspecialchars($current_request['phone']); ?></td>
                                        </tr>
                                    <?php endif; ?>
                                    <tr>
                                        <th>Kullanıcı ID</th>
                                        <td>
                                            <small class="text-muted"><?php echo htmlspecialchars($current_request['user_id']); ?></small>
                                        </td>
                                    </tr>
                                </table>
                            </div>
                        </div>
                        
                        <h5>Talep İçeriği</h5>
                        <div class="card mb-4">
                            <div class="card-body bg-light">
                                <p><?php echo nl2br(htmlspecialchars($current_request['description'])); ?></p>
                            </div>
                        </div>
                        
                        <h5>Yanıtlar</h5>
                        <?php if (empty($current_responses)): ?>
                            <div class="alert alert-info">
                                <i class="fas fa-info-circle me-2"></i> Bu talebe henüz yanıt verilmemiş.
                            </div>
                        <?php else: ?>
                            <?php foreach ($current_responses as $response): ?>
                                <div class="card mb-3">
                                    <div class="card-header bg-light d-flex justify-content-between align-items-center">
                                        <div>
                                            <i class="fas fa-reply me-1"></i> 
                                            <strong>Yanıt</strong> - 
                                            <small class="text-muted">
                                                <?php echo date('d.m.Y H:i', strtotime($response['created_at'])); ?>
                                            </small>
                                        </div>
                                        <div>
                                            <span class="badge bg-primary">Yönetici: <?php echo $response['admin_id']; ?></span>
                                        </div>
                                    </div>
                                    <div class="card-body">
                                        <p><?php echo nl2br(htmlspecialchars($response['response_text'])); ?></p>
                                    </div>
                                </div>
                            <?php endforeach; ?>
                        <?php endif; ?>
                        
                        <?php if ($current_request['status'] === 'open'): ?>
                            <h5>Yanıt Yaz</h5>
                            <form method="post" action="index.php?page=contact_requests&action=reply&id=<?php echo $current_request['id']; ?>">
                                <div class="mb-3">
                                    <textarea class="form-control" name="response_text" rows="5" required></textarea>
                                </div>
                                <div class="d-flex justify-content-between">
                                    <button type="submit" class="btn btn-primary">
                                        <i class="fas fa-paper-plane me-1"></i> Yanıt Gönder
                                    </button>
                                    <button type="button" class="btn btn-warning" data-bs-toggle="modal" data-bs-target="#closeRequestModal">
                                        <i class="fas fa-times-circle me-1"></i> Talebi Kapat
                                    </button>
                                </div>
                            </form>
                        <?php else: ?>
                            <div class="d-flex justify-content-end">
                                <form method="post" action="index.php?page=contact_requests&action=update_status&id=<?php echo $current_request['id']; ?>">
                                    <input type="hidden" name="status" value="open">
                                    <button type="submit" class="btn btn-outline-success">
                                        <i class="fas fa-folder-open me-1"></i> Talebi Yeniden Aç
                                    </button>
                                </form>
                            </div>
                        <?php endif; ?>
                    </div>
                </div>
            </div>
        <?php else: ?>
            <!-- Talep Listesi -->
            <div class="col-md-12">
                <div class="card mb-4">
                    <div class="card-header">
                        <i class="fas fa-table me-1"></i> İletişim Talepleri
                    </div>
                    <div class="card-body">
                        <div class="row mb-3">
                            <div class="col-md-12">
                                <form method="get" action="index.php" class="row g-3">
                                    <input type="hidden" name="page" value="contact_requests">
                                    
                                    <div class="col-md-3">
                                        <label for="status" class="form-label">Durum</label>
                                        <select class="form-select" id="status" name="status">
                                            <option value="">Tümü</option>
                                            <option value="open" <?php echo $status_filter === 'open' ? 'selected' : ''; ?>>Açık</option>
                                            <option value="closed" <?php echo $status_filter === 'closed' ? 'selected' : ''; ?>>Kapalı</option>
                                        </select>
                                    </div>
                                    
                                    <div class="col-md-3">
                                        <label for="type" class="form-label">Talep Tipi</label>
                                        <select class="form-select" id="type" name="type">
                                            <option value="">Tümü</option>
                                            <?php foreach ($request_types as $type_key => $type_data): ?>
                                                <option value="<?php echo $type_key; ?>" <?php echo $type_filter === $type_key ? 'selected' : ''; ?>>
                                                    <?php echo $type_data['name']; ?>
                                                </option>
                                            <?php endforeach; ?>
                                        </select>
                                    </div>
                                    
                                    <div class="col-md-4 d-flex align-items-end">
                                        <button type="submit" class="btn btn-primary">
                                            <i class="fas fa-filter me-1"></i> Filtrele
                                        </button>
                                        <?php if (!empty($status_filter) || !empty($type_filter)): ?>
                                            <a href="index.php?page=contact_requests" class="btn btn-outline-secondary ms-2">
                                                <i class="fas fa-times me-1"></i> Filtreleri Temizle
                                            </a>
                                        <?php endif; ?>
                                    </div>
                                </form>
                            </div>
                        </div>
                        
                        <div class="table-responsive">
                            <table class="table table-bordered table-striped table-hover">
                                <thead>
                                    <tr>
                                        <th>ID</th>
                                        <th>Talep Tipi</th>
                                        <th>Gönderen</th>
                                        <th>Konu</th>
                                        <th>Tarih</th>
                                        <th>Durum</th>
                                        <th>Yanıt</th>
                                        <th>İşlemler</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    <?php if (empty($filtered_requests)): ?>
                                        <tr>
                                            <td colspan="8" class="text-center">Gösterilecek talep bulunamadı.</td>
                                        </tr>
                                    <?php else: ?>
                                        <?php foreach ($filtered_requests as $request): ?>
                                            <?php 
                                            $request_type = $request_types[$request['request_type']] ?? ['name' => ucfirst($request['request_type']), 'color' => 'secondary', 'icon' => 'fa-question-circle'];
                                            $has_responses = isset($responses_by_request[$request['id']]) && !empty($responses_by_request[$request['id']]);
                                            $short_description = substr(strip_tags($request['description']), 0, 50) . (strlen($request['description']) > 50 ? '...' : '');
                                            $short_id = substr($request['id'], 0, 8);
                                            ?>
                                            <tr>
                                                <td>
                                                    <small class="text-muted"><?php echo $short_id; ?></small>
                                                </td>
                                                <td>
                                                    <span class="badge bg-<?php echo $request_type['color']; ?>">
                                                        <i class="fas <?php echo $request_type['icon']; ?> me-1"></i>
                                                        <?php echo $request_type['name']; ?>
                                                    </span>
                                                </td>
                                                <td><?php echo htmlspecialchars($request['full_name']); ?></td>
                                                <td><?php echo htmlspecialchars($short_description); ?></td>
                                                <td><?php echo date('d.m.Y H:i', strtotime($request['created_at'])); ?></td>
                                                <td>
                                                    <?php if ($request['status'] === 'open'): ?>
                                                        <span class="badge bg-success">Açık</span>
                                                    <?php else: ?>
                                                        <span class="badge bg-secondary">Kapalı</span>
                                                    <?php endif; ?>
                                                </td>
                                                <td>
                                                    <?php if ($has_responses): ?>
                                                        <span class="badge bg-info">
                                                            <i class="fas fa-comments me-1"></i>
                                                            <?php echo count($responses_by_request[$request['id']]); ?>
                                                        </span>
                                                    <?php else: ?>
                                                        <span class="badge bg-light text-dark">
                                                            <i class="fas fa-comment-slash me-1"></i> Yok
                                                        </span>
                                                    <?php endif; ?>
                                                </td>
                                                <td>
                                                    <a href="index.php?page=contact_requests&action=view&id=<?php echo $request['id']; ?>" class="btn btn-sm btn-primary">
                                                        <i class="fas fa-eye"></i>
                                                    </a>
                                                </td>
                                            </tr>
                                        <?php endforeach; ?>
                                    <?php endif; ?>
                                </tbody>
                            </table>
                        </div>
                    </div>
                </div>
            </div>
        <?php endif; ?>
    </div>
</div>

<!-- Talebi Kapatma Onay Modalı -->
<div class="modal fade" id="closeRequestModal" tabindex="-1" aria-labelledby="closeRequestModalLabel" aria-hidden="true">
    <div class="modal-dialog">
        <div class="modal-content">
            <div class="modal-header">
                <h5 class="modal-title" id="closeRequestModalLabel">Talebi Kapat</h5>
                <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Kapat"></button>
            </div>
            <div class="modal-body">
                <p>Bu talebi kapatmak istediğinize emin misiniz?</p>
                <p class="text-warning">
                    <i class="fas fa-exclamation-triangle me-1"></i> Bu işlem, ilgili talebi çözümlenmiş olarak işaretler ve artık yanıt yazılamaz.
                </p>
            </div>
            <div class="modal-footer">
                <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">İptal</button>
                <form method="post" action="index.php?page=contact_requests&action=update_status&id=<?php echo $current_request['id'] ?? ''; ?>">
                    <input type="hidden" name="status" value="closed">
                    <button type="submit" class="btn btn-warning">
                        <i class="fas fa-times-circle me-1"></i> Talebi Kapat
                    </button>
                </form>
            </div>
        </div>
    </div>
</div>

<script>
document.addEventListener('DOMContentLoaded', function() {
    // DataTables eklentisini etkinleştir
    if (typeof $.fn.DataTable !== 'undefined') {
        $('table').DataTable({
            language: {
                url: '//cdn.datatables.net/plug-ins/1.10.25/i18n/Turkish.json'
            },
            paging: true,
            ordering: true,
            info: true,
            responsive: true,
            order: [[4, 'desc']] // Tarih sütununa göre sırala
        });
    }
});
</script>