<?php
// Fonksiyonları dahil et
require_once(__DIR__ . '/../includes/functions.php');

// Düzenleme modu kontrolü
$edit_mode = isset($_GET['id']) && !empty($_GET['id']);
$clone_mode = isset($_GET['clone']) && $_GET['clone'] === 'true';
$ad = null;

// Düzenleme veya kopyalama modu ise reklamı getir
if ($edit_mode) {
    $ad_id = $_GET['id'];
    $ad_result = getDataById('sponsored_ads', $ad_id);
    
    if (!$ad_result['error'] && isset($ad_result['data'])) {
        $ad = $ad_result['data'];
        
        // Kopyalama modunda başlığa "- Kopya" ifadesi ekle
        if ($clone_mode) {
            $ad['title'] .= ' - Kopya';
            $ad['id'] = null; // ID'yi sıfırlayarak yeni kayıt oluşturmasını sağla
            
            // Tarihleri güncelle - mevcut tarihin üzerine 1 ay ekle
            $ad['start_date'] = date('Y-m-d\TH:i', strtotime('+1 day'));
            $ad['end_date'] = date('Y-m-d\TH:i', strtotime('+1 month'));
        }
    } else {
        $_SESSION['message'] = 'Reklam bulunamadı';
        $_SESSION['message_type'] = 'danger';
        redirect('index.php?page=advertisements');
    }
}

// Şehirleri getir
$cities_result = getData('cities', ['order' => 'name']);
$cities = $cities_result['data'];

// İlçeleri getir
$districts_result = getData('districts', ['order' => 'name']);
$districts = $districts_result['data'];

// Form gönderildi mi kontrol et
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    // Form verileri
    $title = trim($_POST['title'] ?? '');
    $content = trim($_POST['content'] ?? '');
    $image_urls = filter_input(INPUT_POST, 'image_urls', FILTER_DEFAULT, FILTER_REQUIRE_ARRAY) ?: [];
    $start_date = $_POST['start_date'] ?? '';
    $end_date = $_POST['end_date'] ?? '';
    $link_type = $_POST['link_type'] ?? '';
    $link_url = trim($_POST['link_url'] ?? '');
    $phone_number = trim($_POST['phone_number'] ?? '');
    $show_after_posts = intval($_POST['show_after_posts'] ?? 5);
    $is_pinned = isset($_POST['is_pinned']) ? true : false;
    $status = $_POST['status'] ?? 'active';
    $ad_display_scope = $_POST['ad_display_scope'] ?? 'herkes';
    $city = trim($_POST['city'] ?? '');
    $district = trim($_POST['district'] ?? '');
    $city_id = $_POST['city_id'] ?? null;
    $district_id = $_POST['district_id'] ?? null;
    
    // Boş dizileri temizle
    $image_urls = array_filter($image_urls, function($url) {
        return !empty(trim($url));
    });
    
    // Basit doğrulama
    $errors = [];
    
    if (empty($title)) {
        $errors[] = 'Başlık gereklidir';
    }
    
    if (empty($content)) {
        $errors[] = 'İçerik gereklidir';
    }
    
    if (empty($start_date)) {
        $errors[] = 'Başlangıç tarihi gereklidir';
    }
    
    if (empty($end_date)) {
        $errors[] = 'Bitiş tarihi gereklidir';
    }
    
    if (strtotime($end_date) <= strtotime($start_date)) {
        $errors[] = 'Bitiş tarihi başlangıç tarihinden sonra olmalıdır';
    }
    
    if (empty($link_type)) {
        $errors[] = 'Bağlantı tipi seçilmelidir';
    } else {
        if ($link_type === 'url' && empty($link_url)) {
            $errors[] = 'URL bağlantısı gereklidir';
        } elseif ($link_type === 'phone' && empty($phone_number)) {
            $errors[] = 'Telefon numarası gereklidir';
        }
    }
    
    // Kapsam kontrolü
    if ($ad_display_scope === 'il' && empty($city)) {
        $errors[] = 'İl kapsamı seçildiğinde bir şehir seçilmelidir';
    } elseif ($ad_display_scope === 'ilce' && empty($district)) {
        $errors[] = 'İlçe kapsamı seçildiğinde bir ilçe seçilmelidir';
    } elseif ($ad_display_scope === 'ililce' && (empty($city) || empty($district))) {
        $errors[] = 'İl ve ilçe kapsamı seçildiğinde hem şehir hem de ilçe seçilmelidir';
    }
    
    // Hata yoksa reklam ekle/güncelle
    if (empty($errors)) {
        $ad_data = [
            'title' => $title,
            'content' => $content,
            'image_urls' => $image_urls,
            'start_date' => $start_date,
            'end_date' => $end_date,
            'link_type' => $link_type,
            'link_url' => $link_type === 'url' ? $link_url : null,
            'phone_number' => $link_type === 'phone' ? $phone_number : null,
            'show_after_posts' => $show_after_posts,
            'is_pinned' => $is_pinned,
            'status' => $status,
            'ad_display_scope' => $ad_display_scope,
            'city' => in_array($ad_display_scope, ['il', 'ililce']) ? $city : null,
            'district' => in_array($ad_display_scope, ['ilce', 'ililce']) ? $district : null,
            'city_id' => in_array($ad_display_scope, ['il', 'ililce']) ? $city_id : null,
            'district_id' => in_array($ad_display_scope, ['ilce', 'ililce']) ? $district_id : null,
            'updated_at' => date('Y-m-d H:i:s')
        ];
        
        // Düzenleme modu ve kopyalama modu değilse güncelle, değilse yeni kayıt oluştur
        if ($edit_mode && !$clone_mode) {
            $ad_id = $_POST['ad_id'];
            $response = updateData('sponsored_ads', $ad_id, $ad_data);
            $message_success = 'Reklam başarıyla güncellendi';
        } else {
            // Yeni kayıt için oluşturulma tarihi ekle
            $ad_data['created_at'] = date('Y-m-d H:i:s');
            $response = addData('sponsored_ads', $ad_data);
            $message_success = 'Reklam başarıyla eklendi';
        }
        
        if (!$response['error']) {
            $_SESSION['message'] = $message_success;
            $_SESSION['message_type'] = 'success';
            redirect('index.php?page=advertisements');
        } else {
            $_SESSION['message'] = 'İşlem sırasında bir hata oluştu: ' . $response['message'];
            $_SESSION['message_type'] = 'danger';
        }
    } else {
        $_SESSION['message'] = 'Form hataları: ' . implode(', ', $errors);
        $_SESSION['message_type'] = 'danger';
    }
}
?>

<div class="d-flex justify-content-between align-items-center mb-4">
    <h1 class="h3">
        <?php if ($edit_mode && !$clone_mode): ?>
            Reklamı Düzenle: <?php echo escape($ad['title']); ?>
        <?php elseif ($clone_mode): ?>
            Reklamı Kopyala
        <?php else: ?>
            Yeni Reklam Ekle
        <?php endif; ?>
    </h1>
    
    <a href="index.php?page=advertisements" class="btn btn-secondary">
        <i class="fas fa-arrow-left me-1"></i> Reklamlara Dön
    </a>
</div>

<!-- Mesaj gösterimi -->
<?php if (isset($_SESSION['message']) && isset($_SESSION['message_type'])): ?>
    <div class="alert alert-<?php echo $_SESSION['message_type']; ?> alert-dismissible fade show" role="alert">
        <?php echo $_SESSION['message']; ?>
        <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Kapat"></button>
    </div>
    <?php unset($_SESSION['message'], $_SESSION['message_type']); ?>
<?php endif; ?>

<!-- Reklam Formu -->
<div class="card">
    <div class="card-body">
        <form method="post" enctype="multipart/form-data">
            <?php if ($edit_mode): ?>
                <input type="hidden" name="ad_id" value="<?php echo $ad['id']; ?>">
            <?php endif; ?>
            
            <div class="row">
                <!-- Temel Bilgiler -->
                <div class="col-md-6">
                    <div class="card mb-4">
                        <div class="card-header">
                            <h5 class="mb-0">Temel Bilgiler</h5>
                        </div>
                        <div class="card-body">
                            <div class="mb-3">
                                <label for="title" class="form-label">Başlık <span class="text-danger">*</span></label>
                                <input type="text" class="form-control" id="title" name="title" value="<?php echo $ad ? escape($ad['title']) : ''; ?>" required>
                            </div>
                            
                            <div class="mb-3">
                                <label for="content" class="form-label">İçerik <span class="text-danger">*</span></label>
                                <textarea class="form-control" id="content" name="content" rows="4" required><?php echo $ad ? escape($ad['content']) : ''; ?></textarea>
                            </div>
                            
                            <div class="mb-3">
                                <label class="form-label">Görseller</label>
                                
                                <!-- Görsel önizleme alanı -->
                                <div id="image_preview" class="mb-3 row">
                                    <?php if (!empty($image_urls) && is_array($image_urls)): ?>
                                        <?php foreach($image_urls as $url): ?>
                                            <?php if (!empty($url)): ?>
                                            <div class="col-md-4 mb-2">
                                                <div class="card h-100">
                                                    <img src="<?php echo escape($url); ?>" class="card-img-top" alt="Reklam görseli" style="height: 120px; object-fit: cover;">
                                                    <div class="card-body p-2 text-center">
                                                        <button type="button" class="btn btn-sm btn-danger" onclick="removeImageFromPreview('<?php echo escape($url); ?>')">
                                                            <i class="fas fa-trash"></i> Kaldır
                                                        </button>
                                                    </div>
                                                </div>
                                            </div>
                                            <?php endif; ?>
                                        <?php endforeach; ?>
                                    <?php endif; ?>
                                </div>
                                
                                <!-- Görsel URL'leri (gizli) -->
                                <div id="imageUrlsContainer">
                                    <?php 
                                    $image_urls = [];
                                    
                                    if ($ad && isset($ad['image_urls']) && is_array($ad['image_urls'])) {
                                        $image_urls = $ad['image_urls'];
                                    }
                                    
                                    // En az bir URL alanı göster
                                    if (empty($image_urls)) {
                                        $image_urls = [''];
                                    }
                                    
                                    foreach ($image_urls as $index => $url): 
                                    ?>
                                    <input type="hidden" name="image_urls[]" value="<?php echo escape($url); ?>">
                                    <?php endforeach; ?>
                                </div>
                                
                                <!-- Resim yükleme bölümü -->
                                <div class="card mb-3">
                                    <div class="card-header bg-light">
                                        <h6 class="mb-0">Resim Yükleme</h6>
                                    </div>
                                    <div class="card-body">
                                        <div class="input-group">
                                            <input type="file" class="form-control" id="image_upload" accept="image/*">
                                            <button type="button" class="btn btn-primary" onclick="uploadImage()">
                                                <i class="fas fa-upload me-1"></i> Yükle
                                            </button>
                                        </div>
                                        <div class="progress mt-2 d-none" id="upload_progress">
                                            <div class="progress-bar progress-bar-striped progress-bar-animated" role="progressbar" style="width: 0%"></div>
                                        </div>
                                        <div id="upload_status" class="mt-2"></div>
                                        <small class="form-text text-muted mt-2">Yüklediğiniz görseller otomatik olarak URL'e dönüştürülecek. Ayrıca doğrudan URL de ekleyebilirsiniz:</small>
                                        
                                        <div class="input-group mt-2">
                                            <input type="text" class="form-control" id="manual_image_url" placeholder="https://...">
                                            <button type="button" class="btn btn-success" onclick="addManualImageUrl()">
                                                <i class="fas fa-plus"></i> Ekle
                                            </button>
                                        </div>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                    
                    <!-- Bağlantı Bilgileri -->
                    <div class="card mb-4">
                        <div class="card-header">
                            <h5 class="mb-0">Bağlantı Bilgileri</h5>
                        </div>
                        <div class="card-body">
                            <div class="mb-3">
                                <label class="form-label">Bağlantı Tipi <span class="text-danger">*</span></label>
                                <div class="form-check">
                                    <input class="form-check-input" type="radio" name="link_type" id="link_type_url" value="url" <?php echo (!$ad || ($ad && $ad['link_type'] === 'url')) ? 'checked' : ''; ?> onchange="toggleLinkFields()">
                                    <label class="form-check-label" for="link_type_url">
                                        URL Bağlantısı
                                    </label>
                                </div>
                                <div class="form-check">
                                    <input class="form-check-input" type="radio" name="link_type" id="link_type_phone" value="phone" <?php echo ($ad && $ad['link_type'] === 'phone') ? 'checked' : ''; ?> onchange="toggleLinkFields()">
                                    <label class="form-check-label" for="link_type_phone">
                                        Telefon Bağlantısı
                                    </label>
                                </div>
                            </div>
                            
                            <div id="url_field" class="mb-3" style="display: <?php echo (!$ad || ($ad && $ad['link_type'] === 'url')) ? 'block' : 'none'; ?>;">
                                <label for="link_url" class="form-label">URL <span class="text-danger">*</span></label>
                                <input type="url" class="form-control" id="link_url" name="link_url" value="<?php echo $ad && $ad['link_type'] === 'url' ? escape($ad['link_url']) : ''; ?>" placeholder="https://...">
                            </div>
                            
                            <div id="phone_field" class="mb-3" style="display: <?php echo ($ad && $ad['link_type'] === 'phone') ? 'block' : 'none'; ?>;">
                                <label for="phone_number" class="form-label">Telefon Numarası <span class="text-danger">*</span></label>
                                <input type="tel" class="form-control" id="phone_number" name="phone_number" value="<?php echo $ad && $ad['link_type'] === 'phone' ? escape($ad['phone_number']) : ''; ?>" placeholder="+90...">
                            </div>
                        </div>
                    </div>
                </div>
                
                <!-- Kampanya Bilgileri -->
                <div class="col-md-6">
                    <div class="card mb-4">
                        <div class="card-header">
                            <h5 class="mb-0">Kampanya Bilgileri</h5>
                        </div>
                        <div class="card-body">
                            <div class="row mb-3">
                                <div class="col-md-6">
                                    <label for="start_date" class="form-label">Başlangıç Tarihi <span class="text-danger">*</span></label>
                                    <input type="datetime-local" class="form-control" id="start_date" name="start_date" value="<?php echo $ad ? date('Y-m-d\TH:i', strtotime($ad['start_date'])) : date('Y-m-d\TH:i'); ?>" required>
                                </div>
                                <div class="col-md-6">
                                    <label for="end_date" class="form-label">Bitiş Tarihi <span class="text-danger">*</span></label>
                                    <input type="datetime-local" class="form-control" id="end_date" name="end_date" value="<?php echo $ad ? date('Y-m-d\TH:i', strtotime($ad['end_date'])) : date('Y-m-d\TH:i', strtotime('+1 month')); ?>" required>
                                </div>
                            </div>
                            
                            <div class="mb-3">
                                <label for="show_after_posts" class="form-label">Kaç Gönderiden Sonra Gösterilsin?</label>
                                <input type="number" class="form-control" id="show_after_posts" name="show_after_posts" value="<?php echo $ad ? intval($ad['show_after_posts']) : 5; ?>" min="1" max="50">
                                <small class="form-text text-muted">Kullanıcının feed'inde reklamın kaç gönderiden sonra görüntüleneceğini belirler.</small>
                            </div>
                            
                            <div class="mb-3">
                                <div class="form-check">
                                    <input class="form-check-input" type="checkbox" id="is_pinned" name="is_pinned" <?php echo $ad && $ad['is_pinned'] ? 'checked' : ''; ?>>
                                    <label class="form-check-label" for="is_pinned">
                                        Sabitlenmiş Reklam
                                    </label>
                                </div>
                                <small class="form-text text-muted">Sabitlenmiş reklamlar, kullanıcı listesinin en üstünde gösterilir.</small>
                            </div>
                            
                            <div class="mb-3">
                                <label for="status" class="form-label">Durum</label>
                                <select class="form-select" id="status" name="status">
                                    <option value="active" <?php echo (!$ad || ($ad && $ad['status'] === 'active')) ? 'selected' : ''; ?>>Aktif</option>
                                    <option value="paused" <?php echo ($ad && $ad['status'] === 'paused') ? 'selected' : ''; ?>>Duraklatılmış</option>
                                    <option value="inactive" <?php echo ($ad && $ad['status'] === 'inactive') ? 'selected' : ''; ?>>Pasif</option>
                                </select>
                            </div>
                        </div>
                    </div>
                    
                    <!-- Hedefleme Bilgileri -->
                    <div class="card mb-4">
                        <div class="card-header">
                            <h5 class="mb-0">Hedefleme Bilgileri</h5>
                        </div>
                        <div class="card-body">
                            <div class="mb-3">
                                <label class="form-label">Gösterim Kapsamı <span class="text-danger">*</span></label>
                                <div class="form-check">
                                    <input class="form-check-input" type="radio" name="ad_display_scope" id="scope_herkes" value="herkes" 
                                           <?php echo (!$ad || ($ad && $ad['ad_display_scope'] === 'herkes')) ? 'checked' : ''; ?> 
                                           onchange="toggleScopeFields()">
                                    <label class="form-check-label" for="scope_herkes">
                                        Tüm Kullanıcılar
                                    </label>
                                </div>
                                <div class="form-check">
                                    <input class="form-check-input" type="radio" name="ad_display_scope" id="scope_il" value="il" 
                                           <?php echo ($ad && $ad['ad_display_scope'] === 'il') ? 'checked' : ''; ?> 
                                           onchange="toggleScopeFields()">
                                    <label class="form-check-label" for="scope_il">
                                        Belirli Bir İl
                                    </label>
                                </div>
                                <div class="form-check">
                                    <input class="form-check-input" type="radio" name="ad_display_scope" id="scope_ilce" value="ilce" 
                                           <?php echo ($ad && $ad['ad_display_scope'] === 'ilce') ? 'checked' : ''; ?> 
                                           onchange="toggleScopeFields()">
                                    <label class="form-check-label" for="scope_ilce">
                                        Belirli Bir İlçe
                                    </label>
                                </div>
                                <div class="form-check">
                                    <input class="form-check-input" type="radio" name="ad_display_scope" id="scope_ililce" value="ililce" 
                                           <?php echo ($ad && $ad['ad_display_scope'] === 'ililce') ? 'checked' : ''; ?> 
                                           onchange="toggleScopeFields()">
                                    <label class="form-check-label" for="scope_ililce">
                                        Belirli Bir İl ve İlçe
                                    </label>
                                </div>
                            </div>
                            
                            <div id="city_field" class="mb-3" style="display: <?php echo ($ad && ($ad['ad_display_scope'] === 'il' || $ad['ad_display_scope'] === 'ilce' || $ad['ad_display_scope'] === 'ililce')) ? 'block' : 'none'; ?>;">
                                <label for="city" class="form-label">Şehir <span class="text-danger">*</span></label>
                                <select class="form-select" id="city" name="city" onchange="updateCityId(); loadDistrictsForCity(this.options[this.selectedIndex].getAttribute('data-id'));">
                                    <option value="">Şehir Seçin</option>
                                    <?php foreach ($cities as $city): ?>
                                        <option value="<?php echo escape($city['name']); ?>" 
                                                data-id="<?php echo $city['id']; ?>" 
                                                <?php echo ($ad && isset($ad['city']) && $ad['city'] === $city['name']) ? 'selected' : ''; ?>>
                                            <?php echo escape($city['name']); ?>
                                        </option>
                                    <?php endforeach; ?>
                                </select>
                                <input type="hidden" id="city_id" name="city_id" value="<?php echo $ad && isset($ad['city_id']) ? $ad['city_id'] : ''; ?>">
                                <div id="city_loading" class="mt-2" style="display: none;">
                                    <div class="spinner-border spinner-border-sm text-primary" role="status">
                                        <span class="visually-hidden">Yükleniyor...</span>
                                    </div>
                                    <span class="ms-2">İlçeler yükleniyor...</span>
                                </div>
                            </div>
                            
                            <div id="district_field" class="mb-3" style="display: <?php echo ($ad && ($ad['ad_display_scope'] === 'ilce' || $ad['ad_display_scope'] === 'ililce')) ? 'block' : 'none'; ?>;">
                                <label for="district" class="form-label">İlçe <span class="text-danger">*</span></label>
                                <select class="form-select" id="district" name="district" onchange="updateDistrictId()">
                                    <option value="">İlçe Seçin</option>
                                    <?php if ($ad && isset($ad['district']) && !empty($ad['district'])): ?>
                                        <option value="<?php echo escape($ad['district']); ?>" 
                                                data-id="<?php echo $ad['district_id']; ?>" 
                                                selected>
                                            <?php echo escape($ad['district']); ?>
                                        </option>
                                    <?php endif; ?>
                                </select>
                                <input type="hidden" id="district_id" name="district_id" value="<?php echo $ad && isset($ad['district_id']) ? $ad['district_id'] : ''; ?>">
                            </div>
                        </div>
                    </div>
                </div>
            </div>
            
            <!-- Form Butonları -->
            <div class="d-flex justify-content-between">
                <a href="index.php?page=advertisements" class="btn btn-secondary">
                    <i class="fas fa-times me-1"></i> İptal
                </a>
                <button type="submit" class="btn btn-primary">
                    <i class="fas fa-save me-1"></i> 
                    <?php if ($edit_mode && !$clone_mode): ?>
                        Reklamı Güncelle
                    <?php else: ?>
                        Reklamı Kaydet
                    <?php endif; ?>
                </button>
            </div>
        </form>
    </div>
</div>

<script>
    // Bağlantı alanlarını göster/gizle
    function toggleLinkFields() {
        const urlType = document.getElementById('link_type_url').checked;
        const phoneType = document.getElementById('link_type_phone').checked;
        
        document.getElementById('url_field').style.display = urlType ? 'block' : 'none';
        document.getElementById('phone_field').style.display = phoneType ? 'block' : 'none';
    }
    
    // Kapsam alanlarını göster/gizle
    function toggleScopeFields() {
        const scopeHerkes = document.getElementById('scope_herkes').checked;
        const scopeIl = document.getElementById('scope_il').checked;
        const scopeIlce = document.getElementById('scope_ilce').checked;
        const scopeIlIlce = document.getElementById('scope_ililce').checked;
        
        // Şehir alanını tüm ilgili durumlarda göster
        document.getElementById('city_field').style.display = (scopeIl || scopeIlce || scopeIlIlce) ? 'block' : 'none';
        document.getElementById('district_field').style.display = (scopeIlce || scopeIlIlce) ? 'block' : 'none';
        
        // İlçe seçeneği için, şehir seçildiğinde ilçe seçme alanını göster
        if (scopeIlce) {
            // İlçe seçildiğinde önce şehir seçilmeli
            const citySelect = document.getElementById('city');
            if (citySelect.value) {
                // Şehir seçiliyse ilçeleri yükle
                const cityId = citySelect.options[citySelect.selectedIndex].getAttribute('data-id');
                loadDistrictsForCity(cityId);
            } else {
                // Şehir seçili değilse ilçe listesini temizle
                const districtSelect = document.getElementById('district');
                districtSelect.innerHTML = '<option value="">Önce şehir seçin</option>';
            }
        }
    }
    
    // Şehir ID'sini güncelle
    function updateCityId() {
        const citySelect = document.getElementById('city');
        const cityIdInput = document.getElementById('city_id');
        
        if (citySelect.selectedIndex > 0) {
            const selectedOption = citySelect.options[citySelect.selectedIndex];
            cityIdInput.value = selectedOption.getAttribute('data-id');
        } else {
            cityIdInput.value = '';
        }
    }
    
    // İlçe ID'sini güncelle
    function updateDistrictId() {
        const districtSelect = document.getElementById('district');
        const districtIdInput = document.getElementById('district_id');
        
        if (districtSelect.selectedIndex > 0) {
            const selectedOption = districtSelect.options[districtSelect.selectedIndex];
            districtIdInput.value = selectedOption.getAttribute('data-id');
        } else {
            districtIdInput.value = '';
        }
    }
    
    // Görsel URL'si ekle
    function addImageUrl() {
        const container = document.getElementById('imageUrlsContainer');
        const div = document.createElement('div');
        div.className = 'input-group mb-2';
        div.innerHTML = `
            <input type="text" class="form-control" name="image_urls[]" placeholder="https://...">
            <button type="button" class="btn btn-danger" onclick="removeImageUrl(this)">
                <i class="fas fa-minus"></i>
            </button>
        `;
        container.appendChild(div);
    }
    
    // Görsel URL'si kaldır
    function removeImageUrl(button) {
        button.closest('.input-group').remove();
    }
    
    // Şehire göre ilçeleri yükle
    function loadDistrictsForCity(cityId) {
        if (!cityId) {
            return;
        }
        
        // Yükleme göstergesini göster
        document.getElementById('city_loading').style.display = 'flex';
        
        // İlçe seçimini devre dışı bırak
        const districtSelect = document.getElementById('district');
        districtSelect.disabled = true;
        
        // AJAX isteği oluştur
        const xhr = new XMLHttpRequest();
        xhr.open('GET', 'views/get_districts.php?city_id=' + encodeURIComponent(cityId), true);
        
        xhr.onload = function() {
            if (xhr.status === 200) {
                try {
                    const response = JSON.parse(xhr.responseText);
                    
                    // İlçe listesini temizle
                    districtSelect.innerHTML = '<option value="">İlçe Seçin</option>';
                    
                    // Yeni ilçeleri ekle
                    if (response.districts && response.districts.length > 0) {
                        response.districts.forEach(function(district) {
                            const option = document.createElement('option');
                            option.value = district.name;
                            option.setAttribute('data-id', district.id);
                            option.textContent = district.name;
                            districtSelect.appendChild(option);
                        });
                        
                        // İlçe seçimi etkinleştir
                        districtSelect.disabled = false;
                    } else {
                        // İlçe yoksa mesaj göster
                        districtSelect.innerHTML = '<option value="">Bu şehirde ilçe bulunamadı</option>';
                    }
                } catch (e) {
                    console.error('İlçeleri ayrıştırma hatası:', e);
                    districtSelect.innerHTML = '<option value="">İlçeler yüklenemedi</option>';
                }
            } else {
                console.error('İlçeleri yükleme hatası:', xhr.status);
                districtSelect.innerHTML = '<option value="">İlçeler yüklenemedi</option>';
            }
            
            // Yükleme göstergesini gizle
            document.getElementById('city_loading').style.display = 'none';
            
            // İlçe etkinleştir
            districtSelect.disabled = false;
        };
        
        xhr.onerror = function() {
            console.error('Bağlantı hatası');
            document.getElementById('city_loading').style.display = 'none';
            districtSelect.disabled = false;
            districtSelect.innerHTML = '<option value="">Bağlantı hatası</option>';
        };
        
        xhr.send();
    }
    
    // Form yüklendiğinde
    document.addEventListener('DOMContentLoaded', function() {
        // ID değerlerini güncelle
        updateCityId();
        updateDistrictId();
        
        // İlçe seçimi aktifse ve bir şehir seçiliyse ilçeleri yükle
        const scopeIlce = document.getElementById('scope_ilce').checked;
        const scopeIlIlce = document.getElementById('scope_ililce').checked;
        const citySelect = document.getElementById('city');
        
        if ((scopeIlce || scopeIlIlce) && citySelect.value) {
            const cityId = citySelect.options[citySelect.selectedIndex].getAttribute('data-id');
            loadDistrictsForCity(cityId);
        }
    });
</script>