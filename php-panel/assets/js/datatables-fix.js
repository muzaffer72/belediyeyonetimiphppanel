/**
 * DataTables hatalarını düzeltmek için özel script
 */
document.addEventListener('DOMContentLoaded', function() {
    // DataTables yapılandırması
    if (typeof jQuery !== 'undefined' && jQuery.fn.DataTable) {
        // "Incorrect column count" hatasını düzeltmek için
        // jQuery ve DOM hazır olduğunda çalışır
        setTimeout(function() {
            try {
                // DataTables instance'larını yok et
                if (jQuery.fn.DataTable.isDataTable('#posts-table')) {
                    jQuery('#posts-table').DataTable().destroy();
                }
                
                // Tablo başlıkları ve hücreleri kontrol et
                var headerCount = jQuery('#posts-table thead th').length;
                
                // Tüm satırların doğru sayıda hücreye sahip olduğundan emin ol
                jQuery('#posts-table tbody tr').each(function() {
                    var cellCount = jQuery(this).find('td').length;
                    if (cellCount < headerCount) {
                        // Eksik hücreleri ekle
                        var needToAdd = headerCount - cellCount;
                        for (var i = 0; i < needToAdd; i++) {
                            jQuery(this).append('<td>-</td>');
                        }
                    } else if (cellCount > headerCount) {
                        // Fazla hücreleri kaldır
                        jQuery(this).find('td').slice(headerCount).remove();
                    }
                });
                
                console.log('Tablo yapısı düzeltildi. Sütun sayısı: ' + headerCount);
                
                // DataTables'ı yeniden başlat
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
            } catch (error) {
                console.error('DataTables yapılandırma hatası: ', error);
            }
        }, 500); // DOM tamamen yüklendiğinden emin olmak için kısa bir gecikme
        
        // Diğer data-table sınıfına sahip tablolar için
        jQuery('.data-table:not(#posts-table)').each(function() {
            var tableId = jQuery(this).attr('id') || 'table-' + Math.floor(Math.random() * 1000);
            
            try {
                // Eğer tablo zaten DataTable olarak başlatılmışsa, yeniden başlatma
                if (jQuery.fn.DataTable.isDataTable('#' + tableId)) {
                    return;
                }
                
                // DataTable'ı başlat
                jQuery(this).DataTable({
                    language: {
                        url: '//cdn.datatables.net/plug-ins/1.13.4/i18n/tr.json'
                    },
                    responsive: true,
                    pageLength: 10,
                    lengthMenu: [5, 10, 25, 50, 100],
                    columnDefs: [
                        { orderable: false, targets: -1 } // Son sütunu sıralanabilir yapma
                    ]
                });
                
                console.log('DataTable başarıyla başlatıldı: ' + tableId);
            } catch (error) {
                console.error('DataTable başlatma hatası (' + tableId + '): ', error);
            }
        });
    } else {
        console.warn('jQuery veya DataTable bulunamadı!');
    }
});