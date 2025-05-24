/**
 * DataTables hatalarını düzeltmek için özel script
 */
document.addEventListener('DOMContentLoaded', function() {
    // DataTables yapılandırması
    if (typeof jQuery !== 'undefined' && jQuery.fn.DataTable) {
        // Tabloların genel yapılandırması
        jQuery('.data-table').each(function() {
            var tableId = jQuery(this).attr('id');
            
            try {
                // Eğer tablo zaten DataTable olarak başlatılmışsa, yeniden başlatma
                if (jQuery.fn.DataTable.isDataTable('#' + tableId)) {
                    return;
                }
                
                // DataTable'ı başlat
                var dataTable = jQuery(this).DataTable({
                    language: {
                        url: '//cdn.datatables.net/plug-ins/1.13.4/i18n/tr.json'
                    },
                    responsive: true,
                    pageLength: 10,
                    lengthMenu: [5, 10, 25, 50, 100],
                    columnDefs: [
                        // Son sütunu sıralanabilir yapma (genellikle işlemler sütunu)
                        { orderable: false, targets: -1 }
                    ]
                });
                
                console.log('DataTable başarıyla başlatıldı: ' + tableId);
            } catch (error) {
                console.error('DataTable başlatma hatası (' + tableId + '): ', error);
            }
        });
        
        // posts-table için özel yapılandırma
        if (jQuery('#posts-table').length > 0) {
            try {
                if (!jQuery.fn.DataTable.isDataTable('#posts-table')) {
                    jQuery('#posts-table').DataTable({
                        language: {
                            url: '//cdn.datatables.net/plug-ins/1.13.4/i18n/tr.json'
                        },
                        responsive: true,
                        pageLength: 10,
                        lengthMenu: [5, 10, 25, 50, 100],
                        columnDefs: [
                            { orderable: false, targets: -1 } // İşlemler sütunu sıralanabilir olmasın
                        ]
                    });
                    console.log('posts-table DataTable başarıyla başlatıldı');
                }
            } catch (error) {
                console.error('posts-table DataTable başlatma hatası: ', error);
            }
        }
    } else {
        console.warn('jQuery veya DataTable bulunamadı!');
    }
});