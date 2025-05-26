<?php
// Anket ekleme/düzenleme sayfası
require_once(__DIR__ . '/../includes/functions.php');

$edit_mode = isset($_GET['id']) && !empty($_GET['id']);
$poll = null;

// Düzenleme modunda anket verilerini getir
if ($edit_mode) {
    $poll_id = $_GET['id'];
    $poll_result = getDataById('polls', $poll_id);
    
    if (!$poll_result['error'] && isset($poll_result['data'])) {
        $poll = $poll_result['data'];
        
        // Anket seçeneklerini getir
        $options_result = getData('poll_options', ['poll_id' => 'eq.' . $poll_id]);
        $poll['options'] = $options_result['data'] ?? [];
    } else {
        $_SESSION['message'] = 'Anket bulunamadı';
        $_SESSION['message_type'] = 'danger';
        redirect('index.php?page=polls');
    }
}

// Şehirleri getir
$cities_result = getData('cities', ['order' => 'name']);
$cities = $cities_result['data'] ?? [];

// İlçeleri getir
$districts_result = getData('districts', ['order' => 'name']);
$districts = $districts_result['data'] ?? [];

// Form işleme
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $errors = [];
    
    // Zorunlu alanları kontrol et
    $title = trim($_POST['title'] ?? '');
    $description = trim($_POST['description'] ?? '');
    $mini_title = trim($_POST['mini_title'] ?? '');
    $level = $_POST['level'] ?? '';
    $start_date = $_POST['start_date'] ?? '';
    $end_date = $_POST['end_date'] ?? '';
    $is_active = isset($_POST['is_active']);
    $onecikar = isset($_POST['onecikar']);
    $city_id = $_POST['city_id'] ?? null;
    $district_id = $_POST['district_id'] ?? null;
    $options = $_POST['options'] ?? [];
    
    // Validasyon
    if (empty($title)) $errors[] = 'Başlık gereklidir';
    if (empty($description)) $errors[] = 'Açıklama gereklidir';
    if (empty($level)) $errors[] = 'Seviye seçilmelidir';
    if (empty($start_date)) $errors[] = 'Başlangıç tarihi gereklidir';
    if (empty($end_date)) $errors[] = 'Bitiş tarihi gereklidir';
    if (empty($options) || count(array_filter($options)) < 2) {
        $errors[] = 'En az 2 seçenek gereklidir';
    }
    
    // Seviye kontrolü
    if ($level === 'city' && empty($city_id)) $errors[] = 'Şehir seçilmelidir';
    if ($level === 'district' && empty($district_id)) $errors[] = 'İlçe seçilmelidir';
    
    if (empty($errors)) {
        // Anket verilerini hazırla
        $poll_data = [
            'title' => $title,
            'description' => $description,
            'mini_title' => $mini_title,
            'level' => $level,
            'start_date' => $start_date,
            'end_date' => $end_date,
            'is_active' => $is_active,
            'onecikar' => $onecikar,
            'city_id' => $level === 'city' || $level === 'district' ? $city_id : null,
            'district_id' => $level === 'district' ? $district_id : null,
            'created_by' => null,
            'updated_at' => date('Y-m-d H:i:s')
        ];
        
        if ($edit_mode) {
            // Anketi güncelle
            $poll_id = $_POST['poll_id'];
            $response = updateData('polls', $poll_id, $poll_data);
            $message_success = 'Anket başarıyla güncellendi';
        } else {
            // Yeni anket oluştur
            $poll_data['created_at'] = date('Y-m-d H:i:s');
            $poll_data['total_votes'] = 0;
            $response = addData('polls', $poll_data);
            $poll_id = $response['data']['id'] ?? null;
            $message_success = 'Anket başarıyla oluşturuldu';
        }
        
        if (!$response['error'] && $poll_id) {
            // Seçenekleri güncelle
            if ($edit_mode) {
                // Mevcut seçenekleri sil
                deleteData('poll_options', null, ['poll_id' => 'eq.' . $poll_id]);
            }
            
            // Yeni seçenekleri ekle
            foreach (array_filter($options) as $option_text) {
                $option_data = [
                    'poll_id' => $poll_id,
                    'option_text' => trim($option_text),
                    'vote_count' => 0,
                    'created_at' => date('Y-m-d H:i:s')
                ];
                addData('poll_options', $option_data);
            }
            
            $_SESSION['message'] = $message_success;
            $_SESSION['message_type'] = 'success';
            redirect('index.php?page=polls');
        } else {
            $_SESSION['message'] = 'İşlem sırasında hata oluştu: ' . ($response['message'] ?? 'Bilinmeyen hata');
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
        <?php echo $edit_mode ? 'Anket Düzenle' : 'Yeni Anket Oluştur'; ?>
    </h1>
    <a href="index.php?page=polls" class="btn btn-secondary">
        <i class="fas fa-arrow-left me-1"></i> Anketlere Dön
    </a>
</div>

<!-- Mesaj gösterimi -->
<?php if (isset($_SESSION['message'])): ?>
    <div class="alert alert-<?php echo $_SESSION['message_type']; ?> alert-dismissible fade show" role="alert">
        <?php echo $_SESSION['message']; ?>
        <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
    </div>
    <?php unset($_SESSION['message'], $_SESSION['message_type']); ?>
<?php endif; ?>

<!-- Anket Formu -->
<div class="card">
    <div class="card-body">
        <form method="post">
            <?php if ($edit_mode): ?>
                <input type="hidden" name="poll_id" value="<?php echo $poll['id']; ?>">
            <?php endif; ?>
            
            <div class="row">
                <!-- Temel Bilgiler -->
                <div class="col-md-8">
                    <div class="card mb-4">
                        <div class="card-header">
                            <h5 class="mb-0">Temel Bilgiler</h5>
                        </div>
                        <div class="card-body">
                            <div class="mb-3">
                                <label for="title" class="form-label">Anket Başlığı <span class="text-danger">*</span></label>
                                <input type="text" class="form-control" id="title" name="title" 
                                       value="<?php echo $poll ? escape($poll['title']) : ''; ?>" required>
                            </div>
                            
                            <div class="mb-3">
                                <label for="mini_title" class="form-label">Kısa Başlık</label>
                                <input type="text" class="form-control" id="mini_title" name="mini_title" 
                                       value="<?php echo $poll ? escape($poll['mini_title']) : ''; ?>"
                                       placeholder="Listede gösterilecek kısa başlık">
                            </div>
                            
                            <div class="mb-3">
                                <label for="description" class="form-label">Açıklama <span class="text-danger">*</span></label>
                                <textarea class="form-control" id="description" name="description" rows="4" required><?php echo $poll ? escape($poll['description']) : ''; ?></textarea>
                            </div>
                            
                            <!-- Anket Seçenekleri -->
                            <div class="mb-3">
                                <label class="form-label">Anket Seçenekleri <span class="text-danger">*</span></label>
                                <div id="options-container">
                                    <?php 
                                    $options = $poll['options'] ?? [['option_text' => ''], ['option_text' => '']];
                                    foreach ($options as $index => $option): 
                                    ?>
                                    <div class="input-group mb-2 option-row">
                                        <input type="text" class="form-control" name="options[]" 
                                               value="<?php echo escape($option['option_text']); ?>" 
                                               placeholder="Seçenek <?php echo $index + 1; ?>">
                                        <button type="button" class="btn btn-outline-danger remove-option" 
                                                onclick="removeOption(this)" <?php echo count($options) <= 2 ? 'disabled' : ''; ?>>
                                            <i class="fas fa-trash"></i>
                                        </button>
                                    </div>
                                    <?php endforeach; ?>
                                </div>
                                <button type="button" class="btn btn-outline-primary btn-sm" onclick="addOption()">
                                    <i class="fas fa-plus me-1"></i> Seçenek Ekle
                                </button>
                            </div>
                        </div>
                    </div>
                </div>
                
                <!-- Ayarlar -->
                <div class="col-md-4">
                    <div class="card mb-4">
                        <div class="card-header">
                            <h5 class="mb-0">Anket Ayarları</h5>
                        </div>
                        <div class="card-body">
                            <div class="mb-3">
                                <label for="level" class="form-label">Seviye <span class="text-danger">*</span></label>
                                <select class="form-select" id="level" name="level" required onchange="toggleLocationFields()">
                                    <option value="">Seçiniz</option>
                                    <option value="country" <?php echo ($poll && $poll['level'] === 'country') ? 'selected' : ''; ?>>Ülke Geneli</option>
                                    <option value="city" <?php echo ($poll && $poll['level'] === 'city') ? 'selected' : ''; ?>>Şehir Bazlı</option>
                                    <option value="district" <?php echo ($poll && $poll['level'] === 'district') ? 'selected' : ''; ?>>İlçe Bazlı</option>
                                </select>
                            </div>
                            
                            <div id="city_field" class="mb-3" style="display: <?php echo ($poll && in_array($poll['level'], ['city', 'district'])) ? 'block' : 'none'; ?>;">
                                <label for="city_id" class="form-label">Şehir <span class="text-danger">*</span></label>
                                <select class="form-select" id="city_id" name="city_id" onchange="loadDistricts()">
                                    <option value="">Şehir Seçiniz</option>
                                    <?php foreach ($cities as $city): ?>
                                        <option value="<?php echo $city['id']; ?>" 
                                                <?php echo ($poll && $poll['city_id'] === $city['id']) ? 'selected' : ''; ?>>
                                            <?php echo escape($city['name']); ?>
                                        </option>
                                    <?php endforeach; ?>
                                </select>
                            </div>
                            
                            <div id="district_field" class="mb-3" style="display: <?php echo ($poll && $poll['level'] === 'district') ? 'block' : 'none'; ?>;">
                                <label for="district_id" class="form-label">İlçe <span class="text-danger">*</span></label>
                                <select class="form-select" id="district_id" name="district_id">
                                    <option value="">İlçe Seçiniz</option>
                                    <?php if ($poll && $poll['district_id']): ?>
                                        <?php foreach ($districts as $district): ?>
                                            <?php if ($district['city_id'] === $poll['city_id']): ?>
                                                <option value="<?php echo $district['id']; ?>" 
                                                        <?php echo ($poll['district_id'] === $district['id']) ? 'selected' : ''; ?>>
                                                    <?php echo escape($district['name']); ?>
                                                </option>
                                            <?php endif; ?>
                                        <?php endforeach; ?>
                                    <?php endif; ?>
                                </select>
                            </div>
                            
                            <div class="row">
                                <div class="col-md-6">
                                    <label for="start_date" class="form-label">Başlangıç <span class="text-danger">*</span></label>
                                    <input type="datetime-local" class="form-control" id="start_date" name="start_date" 
                                           value="<?php echo $poll ? date('Y-m-d\TH:i', strtotime($poll['start_date'])) : date('Y-m-d\TH:i'); ?>" required>
                                </div>
                                <div class="col-md-6">
                                    <label for="end_date" class="form-label">Bitiş <span class="text-danger">*</span></label>
                                    <input type="datetime-local" class="form-control" id="end_date" name="end_date" 
                                           value="<?php echo $poll ? date('Y-m-d\TH:i', strtotime($poll['end_date'])) : date('Y-m-d\TH:i', strtotime('+1 month')); ?>" required>
                                </div>
                            </div>
                            
                            <div class="mb-3 mt-3">
                                <div class="form-check">
                                    <input class="form-check-input" type="checkbox" id="is_active" name="is_active" 
                                           <?php echo (!$poll || $poll['is_active']) ? 'checked' : ''; ?>>
                                    <label class="form-check-label" for="is_active">
                                        Anket Aktif
                                    </label>
                                </div>
                            </div>
                            
                            <div class="mb-3">
                                <div class="form-check">
                                    <input class="form-check-input" type="checkbox" id="onecikar" name="onecikar" 
                                           <?php echo ($poll && $poll['onecikar']) ? 'checked' : ''; ?>>
                                    <label class="form-check-label" for="onecikar">
                                        Öne Çıkan Anket
                                    </label>
                                </div>
                            </div>
                        </div>
                    </div>
                    
                    <div class="d-grid">
                        <button type="submit" class="btn btn-primary">
                            <i class="fas fa-save me-1"></i> 
                            <?php echo $edit_mode ? 'Güncelle' : 'Oluştur'; ?>
                        </button>
                    </div>
                </div>
            </div>
        </form>
    </div>
</div>

<script>
function addOption() {
    const container = document.getElementById('options-container');
    const optionCount = container.children.length;
    
    const optionRow = document.createElement('div');
    optionRow.className = 'input-group mb-2 option-row';
    optionRow.innerHTML = `
        <input type="text" class="form-control" name="options[]" placeholder="Seçenek ${optionCount + 1}">
        <button type="button" class="btn btn-outline-danger remove-option" onclick="removeOption(this)">
            <i class="fas fa-trash"></i>
        </button>
    `;
    
    container.appendChild(optionRow);
    updateRemoveButtons();
}

function removeOption(button) {
    const container = document.getElementById('options-container');
    if (container.children.length > 2) {
        button.closest('.option-row').remove();
        updateRemoveButtons();
    }
}

function updateRemoveButtons() {
    const container = document.getElementById('options-container');
    const removeButtons = container.querySelectorAll('.remove-option');
    
    removeButtons.forEach(button => {
        button.disabled = container.children.length <= 2;
    });
}

function toggleLocationFields() {
    const level = document.getElementById('level').value;
    const cityField = document.getElementById('city_field');
    const districtField = document.getElementById('district_field');
    
    if (level === 'city' || level === 'district') {
        cityField.style.display = 'block';
        document.getElementById('city_id').required = true;
    } else {
        cityField.style.display = 'none';
        document.getElementById('city_id').required = false;
        document.getElementById('city_id').value = '';
    }
    
    if (level === 'district') {
        districtField.style.display = 'block';
        document.getElementById('district_id').required = true;
    } else {
        districtField.style.display = 'none';
        document.getElementById('district_id').required = false;
        document.getElementById('district_id').value = '';
    }
}

function loadDistricts() {
    const cityId = document.getElementById('city_id').value;
    const districtSelect = document.getElementById('district_id');
    
    if (!cityId) {
        districtSelect.innerHTML = '<option value="">İlçe Seçiniz</option>';
        return;
    }
    
    // İlçeleri yükle
    fetch(`get_districts.php?city_id=${cityId}`)
        .then(response => response.json())
        .then(districts => {
            districtSelect.innerHTML = '<option value="">İlçe Seçiniz</option>';
            districts.forEach(district => {
                districtSelect.innerHTML += `<option value="${district.id}">${district.name}</option>`;
            });
        })
        .catch(error => console.error('İlçeler yüklenirken hata:', error));
}

// Sayfa yüklendiğinde çalıştır
document.addEventListener('DOMContentLoaded', function() {
    updateRemoveButtons();
});
</script>