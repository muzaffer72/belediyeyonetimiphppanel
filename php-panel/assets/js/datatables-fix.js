/**
 * DataTables hatalarını düzeltmek için özel script
 */
document.addEventListener('DOMContentLoaded', function() {
    // DataTables yapılandırması
    if (typeof jQuery !== 'undefined' && jQuery.fn.DataTable) {
        // DataTables'ı tamamen devre dışı bırakıp tabloları normal halde kullanma seçeneği
        var disableDataTables = true;
        
        if (disableDataTables) {
            console.log('DataTables devre dışı bırakıldı, tablolar normal şekilde gösteriliyor.');
            
            // Tablo stil düzenlemeleri
            jQuery('#posts-table, .data-table').each(function() {
                jQuery(this).addClass('table-striped table-hover');
                
                // Pagination ekleme
                var tableId = jQuery(this).attr('id') || 'table-' + Math.floor(Math.random() * 1000);
                if (!jQuery(this).attr('id')) {
                    jQuery(this).attr('id', tableId);
                }
                
                // Pagination div'i ekle
                if (jQuery('#' + tableId + '_wrapper').length === 0) {
                    jQuery(this).wrap('<div id="' + tableId + '_wrapper" class="dataTables_wrapper dt-bootstrap5"></div>');
                    
                    // Satır sayısı 10'dan fazlaysa basit pagination ekle
                    var rowCount = jQuery(this).find('tbody tr').length;
                    if (rowCount > 10) {
                        var paginationHtml = '<div class="d-flex justify-content-between align-items-center mt-3">' +
                            '<div class="dataTables_info" role="status" aria-live="polite">Toplam ' + rowCount + ' kayıt</div>' +
                            '<div class="dataTables_paginate paging_simple_numbers">' +
                            '<ul class="pagination">' +
                            '<li class="paginate_button page-item previous disabled"><a href="#" class="page-link">Önceki</a></li>' +
                            '<li class="paginate_button page-item active"><a href="#" class="page-link">1</a></li>' +
                            '<li class="paginate_button page-item next disabled"><a href="#" class="page-link">Sonraki</a></li>' +
                            '</ul></div></div>';
                            
                        jQuery('#' + tableId + '_wrapper').append(paginationHtml);
                    }
                }
            });
            
            return; // DataTables başlatma işlemini atla
        }
        
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
                    console.log('Satır hücre sayısı: ' + cellCount + ', Başlık sayısı: ' + headerCount);
                    
                    if (cellCount < headerCount) {
                        // Eksik hücreleri ekle
                        var needToAdd = headerCount - cellCount;
                        console.log('Eksik hücre sayısı: ' + needToAdd);
                        for (var i = 0; i < needToAdd; i++) {
                            jQuery(this).append('<td>-</td>');
                        }
                    } else if (cellCount > headerCount) {
                        // Fazla hücreleri kaldır
                        console.log('Fazla hücre sayısı: ' + (cellCount - headerCount));
                        jQuery(this).find('td').slice(headerCount).remove();
                    }
                });
                
                console.log('Tablo yapısı düzeltildi. Sütun sayısı: ' + headerCount);
                
                // DataTables'ı yeniden başlat
                try {
                    jQuery('#posts-table').DataTable({
                        paging: false,
                        ordering: false,
                        info: false,
                        searching: false,
                        language: {
                            url: '//cdn.datatables.net/plug-ins/1.13.4/i18n/tr.json',
                            emptyTable: "Gösterilecek veri yok"
                        },
                        columnDefs: [
                            { orderable: false, targets: '_all' }
                        ]
                    });
                    console.log('posts-table DataTable başarıyla başlatıldı (basitleştirilmiş mod)');
                } catch (dtError) {
                    console.error('DataTables başlatma hatası:', dtError);
                    // DataTables başlatılamazsa en azından tabloyu görünür yap
                    jQuery('#posts-table').show();
                }
            } catch (error) {
                console.error('DataTables yapılandırma hatası: ', error);
                // Hata durumunda tabloyu normal şekilde göster
                jQuery('#posts-table').show();
            }
        }, 1000); // DOM tamamen yüklendiğinden emin olmak için daha uzun bir gecikme
        
        // Diğer data-table sınıfına sahip tablolar için basit gösterim
        jQuery('.data-table:not(#posts-table)').each(function() {
            var tableId = jQuery(this).attr('id') || 'table-' + Math.floor(Math.random() * 1000);
            if (!jQuery(this).attr('id')) {
                jQuery(this).attr('id', tableId);
            }
            
            try {
                // Eğer tablo zaten DataTable olarak başlatılmışsa, yok et
                if (jQuery.fn.DataTable.isDataTable('#' + tableId)) {
                    jQuery('#' + tableId).DataTable().destroy();
                }
                
                // Basitleştirilmiş DataTable'ı başlat
                jQuery(this).DataTable({
                    paging: false,
                    ordering: false,
                    info: false,
                    searching: false,
                    language: {
                        emptyTable: "Gösterilecek veri yok"
                    }
                });
                
                console.log('DataTable basitleştirilmiş olarak başlatıldı: ' + tableId);
            } catch (error) {
                console.error('DataTable başlatma hatası (' + tableId + '): ', error);
                // Hata durumunda tabloyu normal şekilde göster
                jQuery('#' + tableId).show();
            }
        });
    } else {
        console.warn('jQuery veya DataTable bulunamadı!');
        
        // DataTables olmadan tabloları düzgün göster
        var tables = document.querySelectorAll('#posts-table, .data-table');
        tables.forEach(function(table) {
            table.classList.add('table-striped', 'table-hover');
        });
    }
});