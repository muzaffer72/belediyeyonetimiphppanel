/**
 * Municipality Management System Admin Panel JavaScript
 */

document.addEventListener('DOMContentLoaded', function() {
    // Mobile sidebar toggle
    const sidebarToggle = document.querySelector('.navbar-toggler');
    if (sidebarToggle) {
        sidebarToggle.addEventListener('click', function() {
            document.querySelector('#sidebar').classList.toggle('show');
        });
    }

    // Auto-close alerts after 5 seconds
    const alerts = document.querySelectorAll('.alert');
    alerts.forEach(function(alert) {
        setTimeout(function() {
            const closeButton = alert.querySelector('.btn-close');
            if (closeButton) {
                closeButton.click();
            }
        }, 5000);
    });

    // District selection based on city in forms
    const citySelect = document.getElementById('city_id');
    const districtSelect = document.getElementById('district_id');
    
    if (citySelect && districtSelect) {
        citySelect.addEventListener('change', function() {
            const cityId = this.value;
            if (cityId) {
                // Fetch districts for selected city
                fetch(`ajax/get_districts.php?city_id=${cityId}`)
                    .then(response => response.json())
                    .then(data => {
                        // Clear current options
                        districtSelect.innerHTML = '<option value="">İlçe Seçin</option>';
                        
                        // Add new options
                        data.forEach(district => {
                            const option = document.createElement('option');
                            option.value = district.id;
                            option.textContent = district.name;
                            districtSelect.appendChild(option);
                        });
                        
                        // Enable district select
                        districtSelect.disabled = false;
                    })
                    .catch(error => {
                        console.error('Error fetching districts:', error);
                    });
            } else {
                // Clear and disable district select if no city selected
                districtSelect.innerHTML = '<option value="">Önce Şehir Seçin</option>';
                districtSelect.disabled = true;
            }
        });
    }

    // Confirm delete actions
    const deleteButtons = document.querySelectorAll('.btn-delete');
    deleteButtons.forEach(function(button) {
        button.addEventListener('click', function(e) {
            if (!confirm('Bu öğeyi silmek istediğinizden emin misiniz? Bu işlem geri alınamaz.')) {
                e.preventDefault();
            }
        });
    });

    // Post type change confirmation
    const postTypeSelect = document.getElementById('type');
    if (postTypeSelect) {
        const originalType = postTypeSelect.value;
        
        postTypeSelect.addEventListener('change', function() {
            const newType = this.value;
            
            // If changing between complaint and thanks, show confirmation
            if ((originalType === 'complaint' && newType === 'thanks') || 
                (originalType === 'thanks' && newType === 'complaint')) {
                if (!confirm('Gönderi tipini değiştirmek, ilgili ilçe ve parti istatistiklerini de etkileyecektir. Devam etmek istiyor musunuz?')) {
                    this.value = originalType;
                }
            }
        });
    }

    // Handle filter form submission
    const filterForm = document.getElementById('filter-form');
    if (filterForm) {
        filterForm.addEventListener('submit', function() {
            // Remove empty fields from form submission
            const inputs = this.querySelectorAll('input, select');
            inputs.forEach(function(input) {
                if (input.value === '') {
                    input.disabled = true;
                }
            });
        });
    }

    // Password strength checker
    const passwordInput = document.getElementById('password');
    const passwordStrength = document.getElementById('password-strength');
    
    if (passwordInput && passwordStrength) {
        passwordInput.addEventListener('input', function() {
            const password = this.value;
            let strength = 0;
            
            // Length check
            if (password.length >= 8) strength += 1;
            
            // Character variety checks
            if (password.match(/[a-z]+/)) strength += 1;
            if (password.match(/[A-Z]+/)) strength += 1;
            if (password.match(/[0-9]+/)) strength += 1;
            if (password.match(/[^a-zA-Z0-9]+/)) strength += 1;
            
            // Update strength indicator
            switch (strength) {
                case 0:
                case 1:
                    passwordStrength.className = 'text-danger';
                    passwordStrength.textContent = 'Çok Zayıf';
                    break;
                case 2:
                    passwordStrength.className = 'text-warning';
                    passwordStrength.textContent = 'Zayıf';
                    break;
                case 3:
                    passwordStrength.className = 'text-info';
                    passwordStrength.textContent = 'Orta';
                    break;
                case 4:
                    passwordStrength.className = 'text-primary';
                    passwordStrength.textContent = 'Güçlü';
                    break;
                case 5:
                    passwordStrength.className = 'text-success';
                    passwordStrength.textContent = 'Çok Güçlü';
                    break;
            }
        });
    }

    // Initialize datepickers
    const datepickers = document.querySelectorAll('.datepicker');
    if (datepickers.length > 0) {
        datepickers.forEach(function(picker) {
            // This is a placeholder for a datepicker library
            // You may need to add a library like flatpickr or bootstrap-datepicker
            console.log('Datepicker initialization would happen here');
        });
    }

    // Handle bulk actions
    const bulkActionForm = document.getElementById('bulk-action-form');
    const bulkActionSelect = document.getElementById('bulk-action');
    const bulkCheckboxes = document.querySelectorAll('.bulk-checkbox');
    
    if (bulkActionForm && bulkActionSelect && bulkCheckboxes.length > 0) {
        bulkActionForm.addEventListener('submit', function(e) {
            // Count selected items
            const selectedCount = document.querySelectorAll('.bulk-checkbox:checked').length;
            
            if (selectedCount === 0) {
                e.preventDefault();
                alert('Lütfen en az bir öğe seçin.');
                return;
            }
            
            // Confirm dangerous actions
            const action = bulkActionSelect.value;
            if (action === 'delete' && !confirm(`${selectedCount} öğeyi silmek istediğinizden emin misiniz? Bu işlem geri alınamaz.`)) {
                e.preventDefault();
            }
        });
        
        // Toggle all checkboxes
        const toggleAllCheckbox = document.getElementById('toggle-all');
        if (toggleAllCheckbox) {
            toggleAllCheckbox.addEventListener('change', function() {
                bulkCheckboxes.forEach(function(checkbox) {
                    checkbox.checked = toggleAllCheckbox.checked;
                });
            });
        }
    }
});

/**
 * Format a number with thousand separators
 * @param {number} number The number to format
 * @returns {string} Formatted number
 */
function formatNumber(number) {
    return number.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ".");
}

/**
 * Show or hide a loading spinner
 * @param {string} targetId ID of the element where to show/hide spinner
 * @param {boolean} show Whether to show or hide the spinner
 */
function toggleSpinner(targetId, show) {
    const target = document.getElementById(targetId);
    if (!target) return;
    
    if (show) {
        target.innerHTML = '<div class="text-center my-3"><div class="spinner-border text-primary" role="status"><span class="visually-hidden">Yükleniyor...</span></div><p class="mt-2">Yükleniyor...</p></div>';
    } else {
        target.innerHTML = '';
    }
}

/**
 * Confirm an action with a custom message
 * @param {string} message Confirmation message
 * @returns {boolean} True if confirmed, false otherwise
 */
function confirmAction(message) {
    return confirm(message || 'Bu işlemi gerçekleştirmek istediğinizden emin misiniz?');
}