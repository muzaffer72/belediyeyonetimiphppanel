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
    $city_id = isset($_POST['city_id']) ? $_POST['city_id'] : '';
    $district_id = isset($_POST['district_id']) && !empty($_POST['district_id']) ? $_POST['district_id'] : null;
    $title = $_POST['title'] ?? '';
    $notes = $_POST['notes'] ?? '';
    
    // Form verilerini ekrana yazdır (Debug için)
    error_log('Form verileri: ' . json_encode($_POST));
    
    // Kullanıcı ID ve şehir ID kontrolü
    if (empty($user_id)) {
        $error_message = 'Kullanıcı seçimi zorunludur';
    } elseif (empty($city_id)) {
        $error_message = 'Şehir seçimi zorunludur';
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
    $city_id = isset($_POST['city_id']) ? $_POST['city_id'] : '';
    $district_id = isset($_POST['district_id']) && !empty($_POST['district_id']) ? $_POST['district_id'] : null;
    $title = $_POST['title'] ?? '';
    $notes = $_POST['notes'] ?? '';
    
    if (empty($city_id)) {
        $error_message = 'Şehir seçimi zorunludur';
    } else {
        // Görevliyi güncelle
        $update_data = [
            'city_id' => $city_id,
            'district_id' => $district_id,
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

// Kullanıcıları al - doğrudan tüm kullanıcıları getir
$users_result = getData('users');

// Kullanıcı verilerini kontrol et ve göster
if (isset($users_result['error']) && $users_result['error']) {
    $error_message = 'Kullanıcı verileri yüklenemedi: ' . htmlspecialchars($users_result['message'] ?? 'Bilinmeyen hata');
    error_log('User data error: ' . json_encode($users_result));
    $users = [];
} else {
    $users = isset($users_result['data']) ? $users_result['data'] : [];
    if (empty($users)) {
        $error_message = 'Hiç kullanıcı bulunamadı. Lütfen önce kullanıcı ekleyin.';
    }
}

// Kullanıcı listesi boşsa ve ileti gösterilmemişse
if (empty($users) && empty($error_message)) {
    $error_message = 'Kullanıcı listesi yüklenemedi. Lütfen sayfayı yenileyin veya önce kullanıcı ekleyin.';
}

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
    // Önce doğrudan ID ile arama yapalım
    foreach ($officials as $official) {
        if ($official['id'] == $official_id) {
            $edit_official = $official;
            break;
        }
    }
    
    // Eğer görevli bulunamadıysa API üzerinden doğrudan çekelim
    if (!$edit_official) {
        $official_result = getDataById('officials', $official_id);
        if (!$official_result['error'] && isset($official_result['data'])) {
            $edit_official = $official_result['data'];
            
            // Eksik bilgileri tamamlayalım
            if (isset($edit_official['city_id']) && isset($city_map[$edit_official['city_id']])) {
                $edit_official['city_name'] = $city_map[$edit_official['city_id']]['name'];
            } else {
                $edit_official['city_name'] = 'Bilinmiyor';
            }
            
            if (isset($edit_official['district_id']) && isset($district_map[$edit_official['district_id']])) {
                $edit_official['district_name'] = $district_map[$edit_official['district_id']]['name'];
            } else {
                $edit_official['district_name'] = 'Tüm İlçeler';
            }
        }
    }
}

// İlçeleri getiren JavaScript fonksiyonu
$districts_js = <<<'JS'
// Varsayılan ilçe verileri (şehir ID ile eşleştirilmiştir)
const defaultDistricts = {
    // İstanbul (örnek)
    1: [
        {id: 1, name: "Adalar"},
        {id: 2, name: "Arnavutköy"},
        {id: 3, name: "Ataşehir"},
        {id: 4, name: "Avcılar"},
        {id: 5, name: "Bağcılar"}
    ],
    // Ankara (örnek)
    2: [
        {id: 6, name: "Altındağ"},
        {id: 7, name: "Ayaş"},
        {id: 8, name: "Bala"},
        {id: 9, name: "Çankaya"},
        {id: 10, name: "Elmadağ"}
    ]
};

function getDistricts(cityId, targetElement, selectedDistrictId = null) {
    if (!cityId) {
        document.getElementById(targetElement).innerHTML = '<option value="">Önce şehir seçin</option>';
        return;
    }
    
    // Form için debug bilgisi göster
    console.log('Şehir ID: ' + cityId + ' için ilçeler getiriliyor... (seçili ilçe ID: ' + selectedDistrictId + ')');
    
    // İlçeleri doğrudan sayfada göster
    let debugInfo = document.getElementById('city_debug_info');
    if (!debugInfo) {
        debugInfo = document.createElement('div');
        debugInfo.id = 'city_debug_info';
        const cityFormGroup = document.querySelector('#city_id').closest('.mb-3');
        cityFormGroup.appendChild(debugInfo);
    }
    
    debugInfo.className = 'alert alert-info mt-2 mb-2';
    debugInfo.innerHTML = 'İlçeler yükleniyor... Lütfen bekleyin';
    
    // İlçe seçim kutusuna referans
    const districtSelect = document.getElementById(targetElement);
    districtSelect.innerHTML = '<option value="">Tüm İlçeler</option>';
    
    // Doğrudan özel sayfayı çağır (API yerine)
    const xhr = new XMLHttpRequest();
    xhr.open('GET', 'views/get_districts.php?city_id=' + encodeURIComponent(cityId), true);
    
    xhr.onreadystatechange = function() {
        if (xhr.readyState === 4) {
            console.log('XHR status:', xhr.status);
            console.log('Response text:', xhr.responseText);
            
            if (xhr.status === 200) {
                try {
                    // JSON yanıtını ayrıştırmayı dene
                    let data;
                    try {
                        data = JSON.parse(xhr.responseText);
                    } catch (jsonError) {
                        console.error('JSON parse error:', jsonError);
                        debugInfo.className = 'alert alert-danger mt-2 mb-2';
                        debugInfo.innerHTML = 'İlçe verileri alınamadı: JSON ayrıştırma hatası';
                        return;
                    }
                    
                    if (data.error) {
                        debugInfo.className = 'alert alert-danger mt-2 mb-2';
                        debugInfo.innerHTML = 'Hata: ' + data.message;
                    } else if (data.data && Array.isArray(data.data) && data.data.length > 0) {
                        // Başarılı - verileri kullan
                        data.data.forEach(district => {
                            const option = document.createElement('option');
                            option.value = district.id;
                            option.textContent = district.name;
                            
                            // Hem ID ile karşılaştır
                            if (selectedDistrictId && (district.id == selectedDistrictId || district.id === selectedDistrictId)) {
                                option.selected = true;
                                console.log('İlçe eşleşti: ', district.id, ' = ', selectedDistrictId);
                            }
                            
                            districtSelect.appendChild(option);
                        });
                        
                        debugInfo.className = 'alert alert-success mt-2 mb-2';
                        debugInfo.innerHTML = data.data.length + ' ilçe yüklendi.';
                        
                        // 3 saniye sonra mesajı kaldır
                        setTimeout(() => {
                            debugInfo.remove();
                        }, 3000);
                    } else {
                        // Veri yok veya boş dizi
                        debugInfo.className = 'alert alert-warning mt-2 mb-2';
                        debugInfo.innerHTML = 'Bu şehir için ilçe bulunamadı.';
                        
                        // Varsayılan ilçe verileri varsa onları kullan
                        if (defaultDistricts[cityId]) {
                            defaultDistricts[cityId].forEach(district => {
                                const option = document.createElement('option');
                                option.value = district.id;
                                option.textContent = district.name;
                                
                                if (selectedDistrictId && district.id == selectedDistrictId) {
                                    option.selected = true;
                                }
                                
                                districtSelect.appendChild(option);
                            });
                            
                            debugInfo.className = 'alert alert-info mt-2 mb-2';
                            debugInfo.innerHTML = 'Yerel veri kullanıldı: ' + defaultDistricts[cityId].length + ' ilçe yüklendi.';
                        } 
                        // Yerel veri yoksa tüm şehir seçeneklerinin ilçe ID'lerini al
                        else {
                            const cityOptions = Array.from(document.querySelectorAll('#city_id option'));
                            for (let i = 0; i < cityOptions.length; i++) {
                                if (cityOptions[i].value) {
                                    const option = document.createElement('option');
                                    option.value = 'district_' + i;
                                    option.textContent = cityOptions[i].textContent + ' İlçesi';
                                    districtSelect.appendChild(option);
                                }
                            }
                            
                            debugInfo.innerHTML = 'Şehir isimlerine göre ilçe seçenekleri oluşturuldu.';
                        }
                    }
                } catch (e) {
                    console.error('JSON ayrıştırma hatası:', e);
                    debugInfo.className = 'alert alert-danger mt-2 mb-2';
                    debugInfo.innerHTML = 'API yanıtı geçersiz format içeriyor.';
                    
                    // Yine de varsayılan verileri göster
                    if (defaultDistricts[cityId]) {
                        defaultDistricts[cityId].forEach(district => {
                            const option = document.createElement('option');
                            option.value = district.id;
                            option.textContent = district.name;
                            districtSelect.appendChild(option);
                        });
                        
                        debugInfo.innerHTML += ' Alternatif veriler kullanıldı.';
                    }
                }
            } else {
                // Sunucu hatası durumu
                debugInfo.className = 'alert alert-danger mt-2 mb-2';
                debugInfo.innerHTML = 'Sunucu yanıt vermiyor veya hata döndürüyor (' + xhr.status + ').';
                
                // Yerel verileri kullan
                if (defaultDistricts[cityId]) {
                    defaultDistricts[cityId].forEach(district => {
                        const option = document.createElement('option');
                        option.value = district.id;
                        option.textContent = district.name;
                        districtSelect.appendChild(option);
                    });
                    
                    debugInfo.innerHTML += ' Alternatif veriler gösteriliyor.';
                }
            }
        }
    };
    
    xhr.onerror = function() {
        debugInfo.className = 'alert alert-danger mt-2 mb-2';
        debugInfo.innerHTML = 'Ağ hatası! Sunucuya ulaşılamıyor.';
        console.error('XHR ağ hatası');
    };
    
    xhr.send();
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
                                <option value="<?php echo $user['id']; ?>">
                                    <?php 
                                    // ID, email veya name bilgilerinden hangisi varsa onu göster
                                    if (isset($user['email']) && !empty($user['email'])) {
                                        echo htmlspecialchars($user['email']);
                                    } elseif (isset($user['username']) && !empty($user['username'])) {
                                        echo htmlspecialchars($user['username']);
                                    } else {
                                        echo 'Kullanıcı #' . $user['id'];
                                    }
                                    
                                    // Ek olarak isim bilgisi varsa parantez içinde göster
                                    if (isset($user['name']) && !empty($user['name'])) {
                                        echo ' (' . htmlspecialchars($user['name']) . ')';
                                    }
                                    ?>
                                </option>
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
                        <select class="form-select" id="city_id" name="city_id" required onchange="getDistricts(this.value, 'district_id', '<?php echo $edit_official['district_id'] ?? ''; ?>')">
                            <option value="">Şehir Seçin</option>
                            <?php foreach ($cities as $city): ?>
                                <option value="<?php echo $city['id']; ?>" <?php echo ($edit_official && isset($edit_official['city_id']) && $edit_official['city_id'] == $city['id']) ? 'selected' : ''; ?>><?php echo htmlspecialchars($city['name']); ?></option>
                            <?php endforeach; ?>
                        </select>
                        <div id="city_debug_info"></div>
                    </div>
                    
                    <div class="col-md-6 mb-3">
                        <label for="district_id" class="form-label">İlçe (Opsiyonel)</label>
                        <select class="form-select" id="district_id" name="district_id">
                            <option value="">Tüm İlçeler</option>
                            <?php if ($edit_official && isset($edit_official['district_id']) && !empty($edit_official['district_id'])): ?>
                                <option value="<?php echo $edit_official['district_id']; ?>" selected><?php echo htmlspecialchars($edit_official['district_name'] ?? 'Seçili İlçe'); ?></option>
                            <?php endif; ?>
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
                
                <?php if ($action === 'edit' && isset($edit_official['city_id'])): ?>
                <script>
                // Sayfa yüklendiğinde düzenleme modunda ilçeleri otomatik yükle
                document.addEventListener('DOMContentLoaded', function() {
                    // Seçili şehir ve ilçe ID'lerini al
                    const cityId = '<?php echo $edit_official['city_id']; ?>';
                    const districtId = '<?php echo $edit_official['district_id'] ?? ''; ?>';
                    
                    if (cityId) {
                        console.log('Düzenleme modunda ilçeler yükleniyor - Şehir ID:', cityId, ' İlçe ID:', districtId);
                        // İlçeleri yükle
                        getDistricts(cityId, 'district_id', districtId);
                    }
                });
                </script>
                <?php endif; ?>
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
                <table class="table table-striped" id="officials-table">
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
    // DataTable hatası aldığımız için devre dışı bıraktık
    /*
    if (typeof $.fn.DataTable !== 'undefined') {
        $('#officials-table').DataTable({
            language: {
                url: 'https://cdn.datatables.net/plug-ins/1.10.25/i18n/Turkish.json'
            },
            order: [[0, 'desc']]
        });
    }
    */
    
    // Şehir seçildiğinde ilçeleri getir
    const citySelect = document.getElementById('city_id');
    if (citySelect) {
        citySelect.addEventListener('change', function() {
            getDistricts(this.value, 'district_id');
        });
        
        // Sayfa yüklendiğinde şehir seçiliyse ilçeleri getir
        if (citySelect.value) {
            getDistricts(citySelect.value, 'district_id');
        }
    }
    
    <?php if ($edit_official && isset($edit_official['city_id']) && $edit_official['city_id']): ?>
    // Düzenle modunda ilçeleri yükle
    getDistricts(<?php echo $edit_official['city_id']; ?>, 'district_id', <?php echo isset($edit_official['district_id']) ? $edit_official['district_id'] : 'null'; ?>);
    <?php endif; ?>
    
    // Form submit öncesi kontrol
    const officialForm = document.querySelector('form[action*="officials"]');
    if (officialForm) {
        officialForm.addEventListener('submit', function(e) {
            const userSelect = document.getElementById('user_id');
            const citySelect = document.getElementById('city_id');
            
            let hasError = false;
            let errorMessage = '';
            
            if (userSelect && userSelect.value === '') {
                hasError = true;
                errorMessage += 'Lütfen bir kullanıcı seçin. ';
                userSelect.classList.add('is-invalid');
            } else if (userSelect) {
                userSelect.classList.remove('is-invalid');
            }
            
            if (!citySelect.value) {
                hasError = true;
                errorMessage += 'Lütfen bir şehir seçin.';
                citySelect.classList.add('is-invalid');
            } else {
                citySelect.classList.remove('is-invalid');
            }
            
            if (hasError) {
                e.preventDefault();
                alert(errorMessage);
                return false;
            }
            
            return true;
        });
    }
});
</script>