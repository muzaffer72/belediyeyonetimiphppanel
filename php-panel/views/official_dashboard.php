<?php
// Yapılandırma dosyasını ve gerekli fonksiyonları yükle
require_once(__DIR__ . '/../config/config.php');
require_once(__DIR__ . '/../includes/functions.php');
require_once(__DIR__ . '/../includes/auth_functions.php');

// Sadece belediye görevlisi erişimi kontrolü
if (!isLoggedIn() || !isset($_SESSION['is_official']) || !$_SESSION['is_official']) {
    redirect('index.php?page=official_login');
}

// Görevli bilgilerini al
$city_id = $_SESSION['city_id'] ?? null;
$district_id = $_SESSION['district_id'] ?? null;
$city_name = $_SESSION['city_name'] ?? 'Bilinmiyor';
$district_name = $_SESSION['district_name'] ?? 'Bilinmiyor';

// İşlem kontrolü
$action = isset($_GET['action']) ? $_GET['action'] : '';
$post_id = isset($_GET['post_id']) ? (int)$_GET['post_id'] : 0;
$success_message = '';
$error_message = '';

// Post durumunu güncelleme işlemi
if ($action == 'update_status' && $post_id > 0 && isset($_POST['new_status'])) {
    $new_status = $_POST['new_status'];
    $solution_note = $_POST['solution_note'] ?? '';
    $evidence_url = $_POST['evidence_url'] ?? '';
    
    $update_data = [
        'status' => $new_status,
        'solution_note' => $solution_note,
        'evidence_url' => $evidence_url,
        'updated_at' => date('c')
    ];
    
    // Duruma göre ek alanları ayarla
    if ($new_status == 'in_progress') {
        $update_data['processing_date'] = date('c');
        $update_data['processing_official_id'] = $_SESSION['official_id'];
    } elseif ($new_status == 'solved') {
        $update_data['solution_date'] = date('c');
        $update_data['solution_official_id'] = $_SESSION['official_id'];
    } elseif ($new_status == 'rejected') {
        $update_data['rejection_date'] = date('c');
        $update_data['rejection_official_id'] = $_SESSION['official_id'];
    }
    
    // Gönderiyi güncelle
    $update_result = updateData('posts', $post_id, $update_data);
    
    if (!$update_result['error']) {
        $success_message = "Gönderi durumu başarıyla güncellendi!";
        
        // Kullanıcıya bildirim gönder
        $post_result = getData('posts', [
            'select' => 'id,title,user_id',
            'filters' => ['id' => 'eq.' . $post_id]
        ]);
        
        if (!$post_result['error'] && !empty($post_result['data'])) {
            $post = $post_result['data'][0];
            $user_id = $post['user_id'];
            
            $status_texts = [
                'pending' => 'Beklemede',
                'in_progress' => 'İşleme Alındı',
                'solved' => 'Çözüldü',
                'rejected' => 'Reddedildi'
            ];
            
            $notification_data = [
                'user_id' => $user_id,
                'title' => 'Gönderi Durumu Güncellendi',
                'content' => '"' . $post['title'] . '" başlıklı gönderinizin durumu ' . ($status_texts[$new_status] ?? $new_status) . ' olarak güncellendi.',
                'type' => 'system',
                'is_read' => false,
                'related_entity_id' => (string)$post_id,
                'related_entity_type' => 'post',
                'created_at' => date('c'),
                'updated_at' => date('c')
            ];
            
            $notification_result = addData('notifications', $notification_data);
            
            if (!$notification_result['error']) {
                $success_message .= " Kullanıcıya bildirim gönderildi.";
            }
        }
    } else {
        $error_message = "Gönderi durumu güncellenirken hata oluştu: " . ($update_result['message'] ?? 'Bilinmeyen hata');
    }
}

// Görevlinin sorumlu olduğu gönderileri al
$posts_query = [
    'select' => '*',
    'order' => 'created_at.desc'
];

// Şehir veya ilçeye göre filtrele
if ($district_id) {
    $posts_query['filters']['district_id'] = 'eq.' . $district_id;
} elseif ($city_id) {
    $posts_query['filters']['city_id'] = 'eq.' . $city_id;
}

$posts_result = getData('posts', $posts_query);
$posts = $posts_result['error'] ? [] : $posts_result['data'];

// Şehir ve ilçe adlarına göre eşleştir
if (!empty($posts)) {
    $city_ids = array_unique(array_column($posts, 'city_id'));
    $district_ids = array_unique(array_column($posts, 'district_id'));
    
    // Şehirleri al
    $cities_result = getData('cities', [
        'select' => 'id,name'
    ]);
    $cities = $cities_result['error'] ? [] : $cities_result['data'];
    $city_names = [];
    
    foreach ($cities as $city) {
        $city_names[$city['id']] = $city['name'];
    }
    
    // İlçeleri al
    $districts_result = getData('districts', [
        'select' => 'id,name'
    ]);
    $districts = $districts_result['error'] ? [] : $districts_result['data'];
    $district_names = [];
    
    foreach ($districts as $district) {
        $district_names[$district['id']] = $district['name'];
    }
    
    // Şehir ve ilçe adlarını gönderilere ekle
    foreach ($posts as &$post) {
        $post['city_name'] = $city_names[$post['city_id']] ?? 'Bilinmiyor';
        $post['district_name'] = $district_names[$post['district_id']] ?? 'Bilinmiyor';
    }
}

// Uyarı ve bilgilendirme mesajları
if (!empty($success_message)) {
    echo '<div class="alert alert-success">' . $success_message . '</div>';
}
if (!empty($error_message)) {
    echo '<div class="alert alert-danger">' . $error_message . '</div>';
}
?>

<!-- Görevli Paneli -->
<div class="container-fluid px-4">
    <h1 class="mt-4">
        <i class="fas fa-user-tie me-2"></i> Belediye Görevlisi Paneli
    </h1>
    
    <div class="row">
        <div class="col-xl-3 col-md-6">
            <div class="card bg-primary text-white mb-4">
                <div class="card-body">
                    <h5 class="mb-0"><i class="fas fa-map-marker-alt me-2"></i> Bölge Bilgisi</h5>
                </div>
                <div class="card-footer d-flex align-items-center justify-content-between">
                    <div>
                        <div><strong>Şehir:</strong> <?php echo htmlspecialchars($city_name); ?></div>
                        <?php if ($district_name != 'Bilinmiyor'): ?>
                            <div><strong>İlçe:</strong> <?php echo htmlspecialchars($district_name); ?></div>
                        <?php endif; ?>
                    </div>
                </div>
            </div>
        </div>
        
        <div class="col-xl-3 col-md-6">
            <div class="card bg-warning text-white mb-4">
                <div class="card-body">
                    <h5 class="mb-0"><i class="fas fa-clipboard-list me-2"></i> Bekleyen Gönderiler</h5>
                </div>
                <div class="card-footer d-flex align-items-center justify-content-between">
                    <?php 
                    $pending_count = 0;
                    foreach ($posts as $post) {
                        if ($post['status'] == 'pending') {
                            $pending_count++;
                        }
                    }
                    ?>
                    <div class="small text-white"><strong><?php echo $pending_count; ?></strong> gönderi</div>
                </div>
            </div>
        </div>
        
        <div class="col-xl-3 col-md-6">
            <div class="card bg-info text-white mb-4">
                <div class="card-body">
                    <h5 class="mb-0"><i class="fas fa-spinner me-2"></i> İşlemdeki Gönderiler</h5>
                </div>
                <div class="card-footer d-flex align-items-center justify-content-between">
                    <?php 
                    $in_progress_count = 0;
                    foreach ($posts as $post) {
                        if ($post['status'] == 'in_progress') {
                            $in_progress_count++;
                        }
                    }
                    ?>
                    <div class="small text-white"><strong><?php echo $in_progress_count; ?></strong> gönderi</div>
                </div>
            </div>
        </div>
        
        <div class="col-xl-3 col-md-6">
            <div class="card bg-success text-white mb-4">
                <div class="card-body">
                    <h5 class="mb-0"><i class="fas fa-check-circle me-2"></i> Çözülen Gönderiler</h5>
                </div>
                <div class="card-footer d-flex align-items-center justify-content-between">
                    <?php 
                    $solved_count = 0;
                    foreach ($posts as $post) {
                        if ($post['status'] == 'solved') {
                            $solved_count++;
                        }
                    }
                    ?>
                    <div class="small text-white"><strong><?php echo $solved_count; ?></strong> gönderi</div>
                </div>
            </div>
        </div>
    </div>
    
    <div class="card mb-4">
        <div class="card-header">
            <i class="fas fa-table me-1"></i>
            Bölgenizdeki Gönderiler
        </div>
        <div class="card-body">
            <div class="table-responsive">
                <table class="table table-striped table-hover" id="posts-table">
                    <thead>
                        <tr>
                            <th>ID</th>
                            <th>Başlık</th>
                            <th>Şehir</th>
                            <th>İlçe</th>
                            <th>Durum</th>
                            <th>Oluşturma Tarihi</th>
                            <th>İşlemler</th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php if (empty($posts)): ?>
                            <tr>
                                <td colspan="7" class="text-center">Gönderi bulunamadı.</td>
                            </tr>
                        <?php else: ?>
                            <?php foreach ($posts as $post): ?>
                                <tr>
                                    <td><?php echo $post['id']; ?></td>
                                    <td><?php echo htmlspecialchars($post['title']); ?></td>
                                    <td><?php echo htmlspecialchars($post['city_name']); ?></td>
                                    <td><?php echo htmlspecialchars($post['district_name']); ?></td>
                                    <td>
                                        <?php 
                                        $status_class = '';
                                        $status_text = '';
                                        
                                        switch ($post['status']) {
                                            case 'pending':
                                                $status_class = 'warning';
                                                $status_text = 'Beklemede';
                                                break;
                                            case 'in_progress':
                                                $status_class = 'info';
                                                $status_text = 'İşlemde';
                                                break;
                                            case 'solved':
                                                $status_class = 'success';
                                                $status_text = 'Çözüldü';
                                                break;
                                            case 'rejected':
                                                $status_class = 'danger';
                                                $status_text = 'Reddedildi';
                                                break;
                                            default:
                                                $status_class = 'secondary';
                                                $status_text = 'Bilinmiyor';
                                        }
                                        ?>
                                        <span class="badge bg-<?php echo $status_class; ?>"><?php echo $status_text; ?></span>
                                    </td>
                                    <td><?php echo date('d.m.Y H:i', strtotime($post['created_at'])); ?></td>
                                    <td>
                                        <div class="btn-group">
                                            <button type="button" class="btn btn-sm btn-primary view-post" data-post-id="<?php echo $post['id']; ?>">
                                                <i class="fas fa-eye"></i>
                                            </button>
                                            <button type="button" class="btn btn-sm btn-success update-status" data-post-id="<?php echo $post['id']; ?>" data-bs-toggle="modal" data-bs-target="#updateStatusModal">
                                                <i class="fas fa-edit"></i>
                                            </button>
                                        </div>
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

<!-- Durum Güncelleme Modal -->
<div class="modal fade" id="updateStatusModal" tabindex="-1" aria-labelledby="updateStatusModalLabel" aria-hidden="true">
    <div class="modal-dialog">
        <div class="modal-content">
            <div class="modal-header">
                <h5 class="modal-title" id="updateStatusModalLabel">Gönderi Durumunu Güncelle</h5>
                <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Kapat"></button>
            </div>
            <form method="post" action="" id="updateStatusForm">
                <div class="modal-body">
                    <div class="mb-3">
                        <label for="new_status" class="form-label">Yeni Durum</label>
                        <select class="form-select" id="new_status" name="new_status" required>
                            <option value="pending">Beklemede</option>
                            <option value="in_progress">İşleme Al</option>
                            <option value="solved">Çözüldü</option>
                            <option value="rejected">Reddet</option>
                        </select>
                    </div>
                    
                    <div class="mb-3" id="solution_note_container">
                        <label for="solution_note" class="form-label">Çözüm Notu</label>
                        <textarea class="form-control" id="solution_note" name="solution_note" rows="3"></textarea>
                        <div class="form-text">Vatandaşın göreceği çözüm notunu girin.</div>
                    </div>
                    
                    <div class="mb-3" id="evidence_container">
                        <label for="evidence_url" class="form-label">Kanıt URL</label>
                        <input type="text" class="form-control" id="evidence_url" name="evidence_url" placeholder="https://example.com/image.jpg">
                        <div class="form-text">Çözüm kanıtı varsa fotoğraf URL'sini girin.</div>
                    </div>
                </div>
                <div class="modal-footer">
                    <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">İptal</button>
                    <button type="submit" class="btn btn-primary">Güncelle</button>
                </div>
            </form>
        </div>
    </div>
</div>

<!-- Gönderi Detay Modal -->
<div class="modal fade" id="viewPostModal" tabindex="-1" aria-labelledby="viewPostModalLabel" aria-hidden="true">
    <div class="modal-dialog modal-lg">
        <div class="modal-content">
            <div class="modal-header">
                <h5 class="modal-title" id="viewPostModalLabel">Gönderi Detayı</h5>
                <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Kapat"></button>
            </div>
            <div class="modal-body" id="postDetailContent">
                <div class="text-center">
                    <div class="spinner-border text-primary" role="status">
                        <span class="visually-hidden">Yükleniyor...</span>
                    </div>
                    <p>Gönderi detayları yükleniyor...</p>
                </div>
            </div>
            <div class="modal-footer">
                <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Kapat</button>
            </div>
        </div>
    </div>
</div>

<script>
document.addEventListener('DOMContentLoaded', function() {
    // DataTable'ı başlat
    if (typeof $.fn.DataTable !== 'undefined') {
        $('#posts-table').DataTable({
            language: {
                url: 'https://cdn.datatables.net/plug-ins/1.10.25/i18n/Turkish.json'
            },
            order: [[5, 'desc']]  // Tarihe göre sırala
        });
    }
    
    // Durum güncelleme formunu hazırla
    $('.update-status').on('click', function() {
        const postId = $(this).data('post-id');
        const updateForm = document.getElementById('updateStatusForm');
        
        // Form action URL'sini güncelle
        updateForm.action = 'index.php?page=official_dashboard&action=update_status&post_id=' + postId;
        
        // Durum değiştiğinde alan görünürlüğünü güncelle
        document.getElementById('new_status').addEventListener('change', updateFieldVisibility);
        
        // Başlangıçta alan görünürlüğünü ayarla
        updateFieldVisibility();
    });
    
    // Gönderi detayını göster
    $('.view-post').on('click', function() {
        const postId = $(this).data('post-id');
        const modalContent = document.getElementById('postDetailContent');
        
        // Modal'ı göster
        const modal = new bootstrap.Modal(document.getElementById('viewPostModal'));
        modal.show();
        
        // Gönderi detaylarını al
        fetch('index.php?page=api&action=get_post_detail&id=' + postId)
            .then(response => response.json())
            .then(data => {
                if (data.error) {
                    modalContent.innerHTML = `<div class="alert alert-danger">${data.message}</div>`;
                } else {
                    const post = data.data;
                    
                    let statusBadge = '';
                    switch (post.status) {
                        case 'pending':
                            statusBadge = '<span class="badge bg-warning">Beklemede</span>';
                            break;
                        case 'in_progress':
                            statusBadge = '<span class="badge bg-info">İşlemde</span>';
                            break;
                        case 'solved':
                            statusBadge = '<span class="badge bg-success">Çözüldü</span>';
                            break;
                        case 'rejected':
                            statusBadge = '<span class="badge bg-danger">Reddedildi</span>';
                            break;
                        default:
                            statusBadge = '<span class="badge bg-secondary">Bilinmiyor</span>';
                    }
                    
                    let html = `
                        <h4>${post.title}</h4>
                        <div class="mb-3">${statusBadge}</div>
                        
                        <div class="row mb-3">
                            <div class="col-md-6">
                                <p><strong>Şehir:</strong> ${post.city_name || 'Bilinmiyor'}</p>
                                <p><strong>İlçe:</strong> ${post.district_name || 'Bilinmiyor'}</p>
                                <p><strong>Oluşturma Tarihi:</strong> ${new Date(post.created_at).toLocaleString('tr-TR')}</p>
                            </div>
                            <div class="col-md-6">
                                <p><strong>Kategori:</strong> ${post.category || 'Belirtilmemiş'}</p>
                                <p><strong>Durum:</strong> ${statusBadge}</p>
                                <p><strong>Güncellenme Tarihi:</strong> ${post.updated_at ? new Date(post.updated_at).toLocaleString('tr-TR') : 'Güncellenmemiş'}</p>
                            </div>
                        </div>
                        
                        <div class="card mb-3">
                            <div class="card-header">
                                <h5 class="mb-0">Gönderi İçeriği</h5>
                            </div>
                            <div class="card-body">
                                <p>${post.content || 'İçerik bulunmuyor'}</p>
                            </div>
                        </div>
                    `;
                    
                    // Eğer fotoğraf varsa göster
                    if (post.image_url) {
                        html += `
                            <div class="card mb-3">
                                <div class="card-header">
                                    <h5 class="mb-0">Gönderi Fotoğrafı</h5>
                                </div>
                                <div class="card-body text-center">
                                    <img src="${post.image_url}" class="img-fluid rounded" style="max-height: 300px;">
                                </div>
                            </div>
                        `;
                    }
                    
                    // Eğer çözüm bilgisi varsa göster
                    if (post.status === 'solved' || post.solution_note) {
                        html += `
                            <div class="card mb-3">
                                <div class="card-header bg-success text-white">
                                    <h5 class="mb-0">Çözüm Bilgisi</h5>
                                </div>
                                <div class="card-body">
                                    <p>${post.solution_note || 'Çözüm notu bulunmuyor'}</p>
                                    ${post.solution_date ? `<p><strong>Çözüm Tarihi:</strong> ${new Date(post.solution_date).toLocaleString('tr-TR')}</p>` : ''}
                                    ${post.evidence_url ? `
                                        <div class="mt-3">
                                            <strong>Çözüm Kanıtı:</strong>
                                            <div class="text-center mt-2">
                                                <img src="${post.evidence_url}" class="img-fluid rounded" style="max-height: 200px;">
                                            </div>
                                        </div>
                                    ` : ''}
                                </div>
                            </div>
                        `;
                    }
                    
                    modalContent.innerHTML = html;
                }
            })
            .catch(error => {
                modalContent.innerHTML = `<div class="alert alert-danger">Gönderi detayları alınırken hata oluştu: ${error.message}</div>`;
            });
    });
    
    // Durum değişince alan görünürlüğünü güncelle
    function updateFieldVisibility() {
        const status = document.getElementById('new_status').value;
        const solutionContainer = document.getElementById('solution_note_container');
        const evidenceContainer = document.getElementById('evidence_container');
        
        if (status === 'solved') {
            solutionContainer.style.display = 'block';
            evidenceContainer.style.display = 'block';
            document.getElementById('solution_note').setAttribute('required', 'required');
        } else if (status === 'rejected') {
            solutionContainer.style.display = 'block';
            evidenceContainer.style.display = 'none';
            document.getElementById('solution_note').setAttribute('required', 'required');
        } else {
            solutionContainer.style.display = 'none';
            evidenceContainer.style.display = 'none';
            document.getElementById('solution_note').removeAttribute('required');
        }
    }
});
</script>