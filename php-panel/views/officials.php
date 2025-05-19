<?php
// Yapılandırma dosyasını ve gerekli fonksiyonları yükle
require_once(__DIR__ . '/../config/config.php');
require_once(__DIR__ . '/../includes/functions.php');
require_once(__DIR__ . '/../includes/auth_functions.php');

// Sadece admin erişimi kontrolü
if (!isLoggedIn() || !isAdmin()) {
    redirect('index.php?page=login');
}

// İşlem kontrolü
$action = isset($_GET['action']) ? $_GET['action'] : '';
$official_id = isset($_GET['id']) ? (int)$_GET['id'] : 0;
$success_message = '';
$error_message = '';

// Görevli ekleme işlemi
if ($_SERVER['REQUEST_METHOD'] === 'POST' && $action === 'add') {
    $user_id = $_POST['user_id'] ?? '';
    $city_id = isset($_POST['city_id']) ? (int)$_POST['city_id'] : 0;
    $district_id = isset($_POST['district_id']) ? (int)$_POST['district_id'] : null;
    $title = $_POST['title'] ?? '';
    $notes = $_POST['notes'] ?? '';
    
    if (empty($user_id) || $city_id <= 0) {
        $error_message = 'Kullanıcı ID ve şehir seçimi zorunludur';
    } else {
        // Görevli ekle
        $official_data = [
            'user_id' => $user_id,
            'city_id' => $city_id,
            'district_id' => $district_id ?? null,
            'title' => $title,
            'notes' => $notes,
            'created_at' => date('c'),
            'updated_at' => date('c')
        ];
        
        $add_result = addData('officials', $official_data);
        
        if (!$add_result['error']) {
            $success_message = 'Belediye görevlisi başarıyla eklendi';
        } else {
            $error_message = 'Görevli eklenirken hata oluştu: ' . ($add_result['message'] ?? 'Bilinmeyen hata');
        }
    }
}

// Görevli güncelleme işlemi
if ($_SERVER['REQUEST_METHOD'] === 'POST' && $action === 'edit' && $official_id > 0) {
    $city_id = isset($_POST['city_id']) ? (int)$_POST['city_id'] : 0;
    $district_id = isset($_POST['district_id']) ? (int)$_POST['district_id'] : null;
    $title = $_POST['title'] ?? '';
    $notes = $_POST['notes'] ?? '';
    
    if ($city_id <= 0) {
        $error_message = 'Şehir seçimi zorunludur';
    } else {
        // Görevliyi güncelle
        $update_data = [
            'city_id' => $city_id,
            'district_id' => $district_id ?? null,
            'title' => $title,
            'notes' => $notes,
            'updated_at' => date('c')
        ];
        
        $update_result = updateData('officials', $official_id, $update_data);
        
        if (!$update_result['error']) {
            $success_message = 'Belediye görevlisi başarıyla güncellendi';
        } else {
            $error_message = 'Görevli güncellenirken hata oluştu: ' . ($update_result['message'] ?? 'Bilinmeyen hata');
        }
    }
}

// Görevli silme işlemi
if ($action === 'delete' && $official_id > 0) {
    $delete_result = deleteData('officials', $official_id);
    
    if (!$delete_result['error']) {
        $success_message = 'Belediye görevlisi başarıyla silindi';
    } else {
        $error_message = 'Görevli silinirken hata oluştu: ' . ($delete_result['message'] ?? 'Bilinmeyen hata');
    }
}

// Şehirleri al
$cities_result = getData('cities', [
    'select' => 'id,name',
    'order' => 'name'
]);
$cities = $cities_result['error'] ? [] : $cities_result['data'];

// Kullanıcıları al
$users_result = getData('users', [
    'select' => 'id,email,name',
    'order' => 'email'
]);
$users = $users_result['error'] ? [] : $users_result['data'];

// Görevlileri al
$officials_result = getData('officials', [
    'select' => '*',
    'order' => 'created_at.desc'
]);
$officials = $officials_result['error'] ? [] : $officials_result['data'];

// Kullanıcı ve şehir bilgilerini eşleştir
if (!empty($officials)) {
    $user_map = [];
    foreach ($users as $user) {
        $user_map[$user['id']] = $user;
    }
    
    $city_map = [];
    foreach ($cities as $city) {
        $city_map[$city['id']] = $city;
    }
    
    // İlçeleri al
    $districts_result = getData('districts', [
        'select' => 'id,name'
    ]);
    $districts = $districts_result['error'] ? [] : $districts_result['data'];
    
    $district_map = [];
    foreach ($districts as $district) {
        $district_map[$district['id']] = $district;
    }
    
    // Görevli bilgilerini güncelle
    foreach ($officials as &$official) {
        $official['user_email'] = $user_map[$official['user_id']]['email'] ?? 'Bilinmiyor';
        $official['user_name'] = $user_map[$official['user_id']]['name'] ?? 'Bilinmiyor';
        $official['city_name'] = $city_map[$official['city_id']]['name'] ?? 'Bilinmiyor';
        
        if ($official['district_id'] && isset($district_map[$official['district_id']])) {
            $official['district_name'] = $district_map[$official['district_id']]['name'];
        } else {
            $official['district_name'] = 'Tüm İlçeler';
        }
    }
}

// Düzenleme modunda ise görevli bilgilerini al
$edit_official = null;
if ($action === 'edit' && $official_id > 0) {
    foreach ($officials as $official) {
        if ($official['id'] === $official_id) {
            $edit_official = $official;
            break;
        }
    }
}

// İlçeleri getiren JavaScript fonksiyonu
$districts_js = <<<'JS'
function getDistricts(cityId, targetElement, selectedDistrictId = null) {
    if (!cityId) {
        document.getElementById(targetElement).innerHTML = '<option value="">Önce şehir seçin</option>';
        return;
    }
    
    // İlçeleri getir
    fetch('index.php?page=api&action=get_districts&city_id=' + cityId)
        .then(response => response.json())
        .then(data => {
            if (data.error) {
                console.error('İlçeler alınamadı:', data.message);
                return;
            }
            
            const districtSelect = document.getElementById(targetElement);
            districtSelect.innerHTML = '<option value="">Tüm İlçeler</option>';
            
            data.data.forEach(district => {
                const option = document.createElement('option');
                option.value = district.id;
                option.textContent = district.name;
                
                if (selectedDistrictId && district.id == selectedDistrictId) {
                    option.selected = true;
                }
                
                districtSelect.appendChild(option);
            });
        })
        .catch(error => {
            console.error('İlçeler alınırken hata oluştu:', error);
        });
}
JS;

// Uyarı ve bilgilendirme mesajları
if (!empty($success_message)) {
    echo '<div class="alert alert-success">' . $success_message . '</div>';
}
if (!empty($error_message)) {
    echo '<div class="alert alert-danger">' . $error_message . '</div>';
}
?>

<!-- Sayfa Başlığı -->
<div class="container-fluid px-4">
    <h1 class="mt-4">
        <i class="fas fa-user-tie me-2"></i> Belediye Görevlileri
    </h1>
    <ol class="breadcrumb mb-4">
        <li class="breadcrumb-item"><a href="index.php?page=dashboard">Dashboard</a></li>
        <li class="breadcrumb-item active">Belediye Görevlileri</li>
    </ol>
    
    <!-- Görevli Ekle / Düzenle -->
    <div class="card mb-4">
        <div class="card-header">
            <i class="fas fa-user-plus me-1"></i>
            <?php echo $action === 'edit' ? 'Görevli Düzenle' : 'Yeni Görevli Ekle'; ?>
        </div>
        <div class="card-body">
            <form method="post" action="index.php?page=officials&action=<?php echo $action === 'edit' ? 'edit&id=' . $official_id : 'add'; ?>">
                <div class="row">
                    <?php if ($action !== 'edit'): ?>
                    <div class="col-md-6 mb-3">
                        <label for="user_id" class="form-label">Kullanıcı</label>
                        <select class="form-select" id="user_id" name="user_id" required>
                            <option value="">Kullanıcı Seçin</option>
                            <?php foreach ($users as $user): ?>
                                <option value="<?php echo $user['id']; ?>"><?php echo htmlspecialchars($user['email']); ?> (<?php echo htmlspecialchars($user['name'] ?? 'İsimsiz'); ?>)</option>
                            <?php endforeach; ?>
                        </select>
                    </div>
                    <?php endif; ?>
                    
                    <div class="col-md-6 mb-3">
                        <label for="title" class="form-label">Ünvan</label>
                        <input type="text" class="form-control" id="title" name="title" value="<?php echo htmlspecialchars($edit_official['title'] ?? ''); ?>">
                    </div>
                    
                    <div class="col-md-6 mb-3">
                        <label for="city_id" class="form-label">Şehir</label>
                        <select class="form-select" id="city_id" name="city_id" required onchange="getDistricts(this.value, 'district_id')">
                            <option value="">Şehir Seçin</option>
                            <?php foreach ($cities as $city): ?>
                                <option value="<?php echo $city['id']; ?>" <?php echo ($edit_official && $edit_official['city_id'] == $city['id']) ? 'selected' : ''; ?>><?php echo htmlspecialchars($city['name']); ?></option>
                            <?php endforeach; ?>
                        </select>
                    </div>
                    
                    <div class="col-md-6 mb-3">
                        <label for="district_id" class="form-label">İlçe (Opsiyonel)</label>
                        <select class="form-select" id="district_id" name="district_id">
                            <option value="">Tüm İlçeler</option>
                        </select>
                    </div>
                    
                    <div class="col-md-12 mb-3">
                        <label for="notes" class="form-label">Notlar</label>
                        <textarea class="form-control" id="notes" name="notes" rows="3"><?php echo htmlspecialchars($edit_official['notes'] ?? ''); ?></textarea>
                    </div>
                </div>
                
                <div class="mt-3">
                    <button type="submit" class="btn btn-primary">
                        <i class="fas fa-save me-1"></i> <?php echo $action === 'edit' ? 'Güncelle' : 'Ekle'; ?>
                    </button>
                    <?php if ($action === 'edit'): ?>
                        <a href="index.php?page=officials" class="btn btn-secondary">
                            <i class="fas fa-times me-1"></i> İptal
                        </a>
                    <?php endif; ?>
                </div>
            </form>
        </div>
    </div>
    
    <!-- Görevli Listesi -->
    <div class="card mb-4">
        <div class="card-header">
            <i class="fas fa-table me-1"></i>
            Belediye Görevlileri Listesi
        </div>
        <div class="card-body">
            <div class="table-responsive">
                <table class="table table-striped table-hover" id="officials-table">
                    <thead>
                        <tr>
                            <th>ID</th>
                            <th>E-posta</th>
                            <th>Ad Soyad</th>
                            <th>Ünvan</th>
                            <th>Şehir</th>
                            <th>İlçe</th>
                            <th>Oluşturma Tarihi</th>
                            <th>İşlemler</th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php if (empty($officials)): ?>
                            <tr>
                                <td colspan="8" class="text-center">Belediye görevlisi bulunamadı.</td>
                            </tr>
                        <?php else: ?>
                            <?php foreach ($officials as $official): ?>
                                <tr>
                                    <td><?php echo $official['id']; ?></td>
                                    <td><?php echo htmlspecialchars($official['user_email']); ?></td>
                                    <td><?php echo htmlspecialchars($official['user_name']); ?></td>
                                    <td><?php echo htmlspecialchars($official['title'] ?? ''); ?></td>
                                    <td><?php echo htmlspecialchars($official['city_name']); ?></td>
                                    <td><?php echo htmlspecialchars($official['district_name']); ?></td>
                                    <td><?php echo date('d.m.Y H:i', strtotime($official['created_at'])); ?></td>
                                    <td>
                                        <div class="btn-group">
                                            <a href="index.php?page=officials&action=edit&id=<?php echo $official['id']; ?>" class="btn btn-sm btn-primary">
                                                <i class="fas fa-edit"></i>
                                            </a>
                                            <a href="index.php?page=officials&action=delete&id=<?php echo $official['id']; ?>" class="btn btn-sm btn-danger" onclick="return confirm('Bu görevliyi silmek istediğinize emin misiniz?')">
                                                <i class="fas fa-trash-alt"></i>
                                            </a>
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

<script>
<?php echo $districts_js; ?>

document.addEventListener('DOMContentLoaded', function() {
    // DataTable'ı başlat
    if (typeof $.fn.DataTable !== 'undefined') {
        $('#officials-table').DataTable({
            language: {
                url: 'https://cdn.datatables.net/plug-ins/1.10.25/i18n/Turkish.json'
            },
            order: [[0, 'desc']]
        });
    }
    
    <?php if ($edit_official && $edit_official['city_id']): ?>
    // Düzenle modunda ilçeleri yükle
    getDistricts(<?php echo $edit_official['city_id']; ?>, 'district_id', <?php echo $edit_official['district_id'] ?? 'null'; ?>);
    <?php endif; ?>
});
</script>