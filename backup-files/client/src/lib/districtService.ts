import { fetchFromSupabase, getItemById, createItem, updateItem, deleteItem } from './supabaseDirectApi';

// İlçe verileri için sayfalı sorgu
export async function getDistricts(page = 1, pageSize = 10, searchTerm = '', filters = {}) {
  const options = {
    page,
    pageSize,
    filters: { ...filters }
  };

  // Arama terimi varsa, isim üzerinde arama yap
  if (searchTerm) {
    options.filters.name = searchTerm;
  }

  try {
    const result = await fetchFromSupabase('districts', options);
    
    // İlgili şehir verilerini al
    const cities = await fetchFromSupabase('cities');
    
    // Sayfalama bilgilerini hazırla
    const pagination = {
      pageIndex: page,
      pageSize: pageSize,
      pageCount: Math.ceil(result.count / pageSize),
      total: result.count
    };
    
    return {
      data: result.data,
      pagination,
      cities: cities.data
    };
  } catch (error) {
    console.error('İlçe verileri alınırken hata:', error);
    throw error;
  }
}

// Belirli bir şehre ait ilçeleri getir
export async function getDistrictsByCityId(cityId: string) {
  try {
    const result = await fetchFromSupabase('districts', {
      filters: {
        city_id: cityId
      }
    });
    
    return result.data;
  } catch (error) {
    console.error(`Şehir (ID: ${cityId}) ilçeleri alınırken hata:`, error);
    throw error;
  }
}

// Tek bir ilçe verisi alma
export async function getDistrictById(id: string) {
  try {
    return await getItemById('districts', id);
  } catch (error) {
    console.error(`İlçe (ID: ${id}) alınırken hata:`, error);
    throw error;
  }
}

// Yeni ilçe ekleme
export async function createDistrict(districtData: any) {
  try {
    return await createItem('districts', {
      ...districtData,
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString()
    });
  } catch (error) {
    console.error('İlçe oluşturulurken hata:', error);
    throw error;
  }
}

// İlçe güncelleme
export async function updateDistrict(id: string, districtData: any) {
  try {
    return await updateItem('districts', id, {
      ...districtData,
      updated_at: new Date().toISOString()
    });
  } catch (error) {
    console.error(`İlçe (ID: ${id}) güncellenirken hata:`, error);
    throw error;
  }
}

// İlçe silme
export async function deleteDistrict(id: string) {
  try {
    return await deleteItem('districts', id);
  } catch (error) {
    console.error(`İlçe (ID: ${id}) silinirken hata:`, error);
    throw error;
  }
}