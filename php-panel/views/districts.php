<?php
// Fonksiyonları dahil et
require_once(__DIR__ . '/../includes/functions.php');

// Kullanıcı yetki kontrolü
$user_type = $_SESSION['user_type'] ?? '';
$is_admin = $user_type === 'admin';
$is_moderator = $user_type === 'moderator';
$assigned_city_id = $_SESSION['assigned_city_id'] ?? null;
$assigned_district_id = $_SESSION['assigned_district_id'] ?? null;

// İlçeler verilerini al - moderatör sadece kendi şehir/ilçesini görebilir
if ($is_moderator && $assigned_city_id) {
    if ($assigned_district_id) {
        // Belirli bir ilçeye atanmış moderatör
        $districts_result = getData('districts', ['id' => 'eq.' . $assigned_district_id]);
    } else {
        // Şehir genelinde yetkili moderatör
        $districts_result = getData('districts', ['city_id' => 'eq.' . $assigned_city_id]);
    }
} else {
    $districts_result = getData('districts');
}
$districts = $districts_result['data'] ?? [];

// Şehirler verilerini al (dropdown için)
$cities_result = getData('cities');
$cities = $cities_result['data'];

// Parti verilerini al
$parties_result = getData('political_parties');
$parties = $parties_result['data'];

// Yeni ilçe ekle formu gönderildi mi kontrol et - sadece admin
if ($is_admin && $_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['add_district'])) {
    // Form verilerini al
    $name = trim($_POST['name'] ?? '');
    $city_id = trim($_POST['city_id'] ?? '');
    $email = trim($_POST['email'] ?? '');
    $phone = trim($_POST['phone'] ?? '');
    $mayor_name = trim($_POST['mayor_name'] ?? '');
    $political_party_id = trim($_POST['political_party_id'] ?? '');
    $population = trim($_POST['population'] ?? '');
    $logo_url = trim($_POST['logo_url'] ?? '');
    $website = trim($_POST['website'] ?? '');
    $address = trim($_POST['address'] ?? '');
    
    // Basit doğrulama
    $errors = [];
    if (empty($name)) {
        $errors[] = 'İlçe adı gereklidir';
    }
    if (empty($city_id)) {
        $errors[] = 'Bağlı olduğu şehir seçilmelidir';
    }
    
    // Hata yoksa ilçeyi ekle
    if (empty($errors)) {
        // Parti bilgilerini political_party_id'ye göre al
        $party_info = getPartyInfoById($political_party_id);
        $mayor_party = '';
        $party_logo_url = '';
        
        if ($party_info) {
            $mayor_party = $party_info['name'];
            $party_logo_url = $party_info['logo_url'] ?? '';
        }
        
        $new_district = [
            'name' => $name,
            'city_id' => $city_id,
            'email' => $email,
            'phone' => $phone,
            'mayor_name' => $mayor_name,
            'political_party_id' => $political_party_id,
            'mayor_party' => $mayor_party, // Parti adını otomatik doldur
            'party_logo_url' => $party_logo_url, // Parti logo URL'sini otomatik doldur
            'population' => $population,
            'logo_url' => $logo_url,
            'website' => $website,
            'address' => $address,
            'created_at' => date('Y-m-d H:i:s')
        ];
        
        $response = addData('districts', $new_district);
        
        if (!$response['error']) {
            $_SESSION['message'] = 'İlçe başarıyla eklendi';
            $_SESSION['message_type'] = 'success';
            
            // Sayfayı yenile (formun tekrar gönderilmesini önlemek için)
            if (!headers_sent()) {
        header('Location: index.php?page=districts');
        exit;
    } else {
        echo '<script>window.location.href = "index.php?page=districts";</script>';
        exit;
    }
        } else {
            $_SESSION['message'] = 'İlçe eklenirken bir hata oluştu: ' . $response['message'];
            $_SESSION['message_type'] = 'danger';
        }
    } else {
        $_SESSION['message'] = 'Form hataları: ' . implode(', ', $errors);
        $_SESSION['message_type'] = 'danger';
    }
}

// İlçe sil
if (isset($_GET['delete']) && !empty($_GET['delete'])) {
    $district_id = $_GET['delete'];
    $response = deleteData('districts', $district_id);
    
    if (!$response['error']) {
        $_SESSION['message'] = 'İlçe başarıyla silindi';
        $_SESSION['message_type'] = 'success';
    } else {
        $_SESSION['message'] = 'İlçe silinirken bir hata oluştu: ' . $response['message'];
        $_SESSION['message_type'] = 'danger';
    }
    
    // Sayfayı yeniden yönlendir
    if (!headers_sent()) {
        header('Location: index.php?page=districts');
        exit;
    } else {
        echo '<script>window.location.href = "index.php?page=districts";</script>';
        exit;
    }
}
?>

<!-- İşlem Mesajları -->
<?php if(isset($_SESSION['message'])): ?>
<div class="alert alert-<?php echo $_SESSION['message_type']; ?> alert-dismissible fade show" role="alert">
    <?php echo $_SESSION['message']; ?>
    <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Close"></button>
</div>
<?php 
    unset($_SESSION['message']);
    unset($_SESSION['message_type']);
endif; 
?>

<!-- Üst Başlık ve Butonlar -->
<div class="d-flex justify-content-between mb-4">
    <h1 class="h3">İlçeler Yönetimi</h1>
    
    <button type="button" class="btn btn-primary" data-bs-toggle="modal" data-bs-target="#addDistrictModal">
        <i class="fas fa-plus me-1"></i> Yeni İlçe Ekle
    </button>
</div>

<!-- İlçeler Tablosu -->
<div class="card mb-4">
    <div class="card-header">
        <i class="fas fa-table me-1"></i>
        İlçeler Listesi
    </div>
    <div class="card-body">
        <div class="table-responsive">
            <table class="table table-bordered table-striped table-hover">
                <thead>
                    <tr>
                        <th style="width: 80px;">Logo</th>
                        <th>İlçe Adı</th>
                        <th>Bağlı Olduğu Şehir</th>
                        <th>Belediye Başkanı</th>
                        <th>Parti</th>
                        <th>Nüfus</th>
                        <th>İletişim</th>
                        <th style="width: 150px;">İşlemler</th>
                    </tr>
                </thead>
                <tbody>
                    <?php if(empty($districts)): ?>
                        <tr>
                            <td colspan="8" class="text-center">Henüz ilçe kaydı bulunmuyor.</td>
                        </tr>
                    <?php else: ?>
                        <?php foreach($districts as $district): ?>
                            <tr>
                                <td class="text-center">
                                    <?php if(isset($district['logo_url']) && !empty($district['logo_url'])): ?>
                                        <img src="<?php echo $district['logo_url']; ?>" alt="<?php echo isset($district['name']) ? $district['name'] : ''; ?> Logo" width="50" height="50" class="img-thumbnail">
                                    <?php else: ?>
                                        <i class="fas fa-map-marker-alt fa-2x text-secondary"></i>
                                    <?php endif; ?>
                                </td>
                                <td><?php echo isset($district['name']) ? escape($district['name']) : ''; ?></td>
                                <td>
                                    <?php
                                    $city_name = 'Bilinmiyor';
                                    if(isset($district['city_id'])) {
                                        foreach($cities as $city) {
                                            if($city['id'] === $district['city_id']) {
                                                $city_name = $city['name'];
                                                break;
                                            }
                                        }
                                    }
                                    echo escape($city_name);
                                    ?>
                                </td>
                                <td><?php echo isset($district['mayor_name']) ? escape($district['mayor_name']) : ''; ?></td>
                                <td>
                                    <?php if(isset($district['political_party_id']) && !empty($district['political_party_id'])): ?>
                                        <?php 
                                        // Parti bilgilerini getir
                                        $party_info = null;
                                        foreach($parties as $party) {
                                            if($party['id'] == $district['political_party_id']) {
                                                $party_info = $party;
                                                break;
                                            }
                                        }
                                        
                                        if($party_info): 
                                        ?>
                                        <div class="d-flex align-items-center">
                                            <?php if(!empty($party_info['logo_url'])): ?>
                                                <img src="<?php echo escape($party_info['logo_url']); ?>" alt="<?php echo escape($party_info['name']); ?>" class="me-2" style="height: 20px; width: auto;">
                                            <?php endif; ?>
                                            <span class="badge bg-primary"><?php echo escape($party_info['name']); ?></span>
                                        </div>
                                        <?php else: ?>
                                            <small class="text-muted">ID: <?php echo escape($district['political_party_id']); ?></small>
                                        <?php endif; ?>
                                    <?php endif; ?>
                                </td>
                                <td><?php echo isset($district['population']) ? escape($district['population']) : ''; ?></td>
                                <td>
                                    <?php if(isset($district['email']) && !empty($district['email'])): ?>
                                        <div><i class="fas fa-envelope me-1"></i> <?php echo escape($district['email']); ?></div>
                                    <?php endif; ?>
                                    <?php if(isset($district['phone']) && !empty($district['phone'])): ?>
                                        <div><i class="fas fa-phone me-1"></i> <?php echo escape($district['phone']); ?></div>
                                    <?php endif; ?>
                                    <?php if(isset($district['website']) && !empty($district['website'])): ?>
                                        <div><i class="fas fa-globe me-1"></i> <a href="<?php echo $district['website']; ?>" target="_blank">Web Sitesi</a></div>
                                    <?php endif; ?>
                                </td>
                                <td>
                                    <div class="btn-group btn-group-sm">
                                        <a href="index.php?page=district_detail&id=<?php echo $district['id']; ?>" class="btn btn-info" title="Görüntüle">
                                            <i class="fas fa-eye"></i>
                                        </a>
                                        <a href="index.php?page=district_edit&id=<?php echo $district['id']; ?>" class="btn btn-warning" title="Düzenle">
                                            <i class="fas fa-edit"></i>
                                        </a>
                                        <a href="index.php?page=district_performance&id=<?php echo $district['id']; ?>" class="btn btn-primary" title="Performans Analizi">
                                            <i class="fas fa-chart-line"></i>
                                        </a>
                                        <a href="javascript:void(0);" class="btn btn-danger" 
                                           onclick="if(confirm('Bu ilçeyi silmek istediğinizden emin misiniz?')) window.location.href='index.php?page=districts&delete=<?php echo $district['id']; ?>';" 
                                           title="Sil">
                                            <i class="fas fa-trash"></i>
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

<!-- Yeni İlçe Ekle Modal -->
<div class="modal fade" id="addDistrictModal" tabindex="-1" aria-labelledby="addDistrictModalLabel" aria-hidden="true">
    <div class="modal-dialog modal-lg">
        <div class="modal-content">
            <div class="modal-header">
                <h5 class="modal-title" id="addDistrictModalLabel">Yeni İlçe Ekle</h5>
                <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
            </div>
            <div class="modal-body">
                <form method="post" action="index.php?page=districts">
                    <div class="row mb-3">
                        <div class="col-md-6">
                            <label for="name" class="form-label">İlçe Adı <span class="text-danger">*</span></label>
                            <input type="text" class="form-control" id="name" name="name" required>
                        </div>
                        <div class="col-md-6">
                            <label for="city_id" class="form-label">Bağlı Olduğu Şehir <span class="text-danger">*</span></label>
                            <select class="form-select" id="city_id" name="city_id" required>
                                <option value="">Seçiniz</option>
                                <?php foreach($cities as $city): ?>
                                    <option value="<?php echo $city['id']; ?>"><?php echo $city['name']; ?></option>
                                <?php endforeach; ?>
                            </select>
                        </div>
                    </div>
                    
                    <div class="row mb-3">
                        <div class="col-md-6">
                            <label for="mayor_name" class="form-label">Belediye Başkanı</label>
                            <input type="text" class="form-control" id="mayor_name" name="mayor_name">
                        </div>
                        <div class="col-md-6">
                            <label for="mayor_party" class="form-label">Parti</label>
                            <select class="form-select" id="political_party_id" name="political_party_id">
                                <option value="">Seçiniz</option>
                                <?php foreach($parties as $party): ?>
                                    <option value="<?php echo $party['id']; ?>"><?php echo $party['name']; ?></option>
                                <?php endforeach; ?>
                            </select>
                        </div>
                    </div>
                    
                    <div class="row mb-3">
                        <div class="col-md-6">
                            <label for="email" class="form-label">Email</label>
                            <input type="email" class="form-control" id="email" name="email">
                        </div>
                        <div class="col-md-6">
                            <label for="phone" class="form-label">Telefon</label>
                            <input type="text" class="form-control" id="phone" name="phone">
                        </div>
                    </div>
                    
                    <div class="row mb-3">
                        <div class="col-md-6">
                            <label for="website" class="form-label">Web Sitesi</label>
                            <input type="url" class="form-control" id="website" name="website">
                        </div>
                        <div class="col-md-6">
                            <label for="population" class="form-label">Nüfus</label>
                            <input type="text" class="form-control" id="population" name="population">
                        </div>
                    </div>
                    
                    <div class="row mb-3">
                        <div class="col-md-6">
                            <label for="logo_url" class="form-label">Logo URL</label>
                            <input type="url" class="form-control" id="logo_url" name="logo_url">
                        </div>
                        <div class="col-md-6">
                            <label for="address" class="form-label">Adres</label>
                            <textarea class="form-control" id="address" name="address" rows="3"></textarea>
                        </div>
                    </div>
                    
                    <div class="modal-footer">
                        <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">İptal</button>
                        <button type="submit" name="add_district" class="btn btn-primary">Kaydet</button>
                    </div>
                </form>
            </div>
        </div>
    </div>
</div>