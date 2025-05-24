            </div><!-- /.container-fluid -->
        </div><!-- /.main-content -->
    </div><!-- /.wrapper -->
    
    <!-- Footer -->
    <footer class="footer mt-auto py-3 bg-light">
        <div class="container-fluid">
            <div class="d-flex justify-content-between align-items-center">
                <span class="text-muted">© <?php echo date('Y'); ?> <?php echo SITE_TITLE; ?></span>
                <span class="text-muted">Versiyon 1.0</span>
            </div>
        </div>
    </footer>
    
    <!-- jQuery -->
    <script src="https://code.jquery.com/jquery-3.6.4.min.js"></script>
    
    <!-- Bootstrap JS -->
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.2.3/dist/js/bootstrap.bundle.min.js"></script>
    
    <!-- DataTables -->
    <script src="https://cdn.datatables.net/1.13.4/js/jquery.dataTables.min.js"></script>
    <script src="https://cdn.datatables.net/1.13.4/js/dataTables.bootstrap5.min.js"></script>
    
    <!-- Chart.js -->
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.0.1/dist/chart.umd.js"></script>
    
    <!-- DataTables Düzeltmesi -->
    <script src="/php-panel/assets/js/datatables-fix.js"></script>
    
    <!-- Custom JS -->
    <script>
        // Sidebar Toggle
        document.addEventListener('DOMContentLoaded', function() {
            const sidebar = document.getElementById('sidebar');
            const mainContent = document.getElementById('mainContent');
            const mainHeader = document.getElementById('mainHeader');
            const sidebarToggle = document.getElementById('sidebarToggle');
            
            // Sidebar toggle click event
            sidebarToggle.addEventListener('click', function() {
                sidebar.classList.toggle('collapsed');
                mainContent.classList.toggle('expanded');
                mainHeader.classList.toggle('expanded');
            });
            
            // Initialize DataTables
            if ($.fn.DataTable && document.querySelector('.data-table')) {
                $('.data-table').DataTable({
                    language: {
                        url: '//cdn.datatables.net/plug-ins/1.13.4/i18n/tr.json',
                    },
                    responsive: true,
                    pageLength: 10,
                    lengthMenu: [5, 10, 25, 50, 100]
                });
            }
            
            // Initialize Chart.js charts
            if (typeof Chart !== 'undefined') {
                // Post Categories Chart
                const postCategoriesChart = document.getElementById('postCategoriesChart');
                if (postCategoriesChart) {
                    const ctx = postCategoriesChart.getContext('2d');
                    if (typeof postCategoriesData !== 'undefined') {
                        new Chart(ctx, {
                            type: 'doughnut',
                            data: {
                                labels: postCategoriesData.map(item => item.name),
                                datasets: [{
                                    data: postCategoriesData.map(item => item.percentage),
                                    backgroundColor: postCategoriesData.map(item => item.color),
                                    borderWidth: 1
                                }]
                            },
                            options: {
                                responsive: true,
                                maintainAspectRatio: false,
                                plugins: {
                                    legend: {
                                        position: 'right'
                                    }
                                }
                            }
                        });
                    }
                }
                
                // Political Party Distribution Chart
                const partyDistributionChart = document.getElementById('partyDistributionChart');
                if (partyDistributionChart) {
                    const ctx = partyDistributionChart.getContext('2d');
                    if (typeof partyDistributionData !== 'undefined') {
                        new Chart(ctx, {
                            type: 'bar',
                            data: {
                                labels: partyDistributionData.map(item => item.name),
                                datasets: [{
                                    label: 'Şehir Sayısı',
                                    data: partyDistributionData.map(item => item.count),
                                    backgroundColor: partyDistributionData.map(item => item.color),
                                    borderWidth: 1
                                }]
                            },
                            options: {
                                responsive: true,
                                maintainAspectRatio: false,
                                scales: {
                                    y: {
                                        beginAtZero: true,
                                        precision: 0
                                    }
                                }
                            }
                        });
                    }
                }
            }
        });
        
        // Form Validasyon
        function validateForm(formId) {
            const form = document.getElementById(formId);
            if (!form) return true;
            
            const requiredFields = form.querySelectorAll('[required]');
            let isValid = true;
            
            requiredFields.forEach(field => {
                if (!field.value.trim()) {
                    field.classList.add('is-invalid');
                    isValid = false;
                } else {
                    field.classList.remove('is-invalid');
                }
            });
            
            return isValid;
        }
        
        // Silme İşlemi Onay
        function confirmDelete(id, name, type) {
            return confirm(`${name} isimli ${type} kaydını silmek istediğinize emin misiniz?`);
        }
    </script>
</body>
</html>