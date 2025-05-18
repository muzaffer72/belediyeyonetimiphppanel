import { fetchFromSupabase, getItemById, createItem, updateItem, deleteItem } from './supabaseDirectApi';

// Şehir verileri için sayfalı sorgu
export async function getCities(page = 1, pageSize = 10, searchTerm = '', filters = {}) {
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
    const result = await fetchFromSupabase('cities', options);
    
    // Siyasi parti bilgilerini hazırla
    const parties = await fetchFromSupabase('political_parties');
    
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
      parties: parties.data
    };
  } catch (error) {
    console.error('Şehir verileri alınırken hata:', error);
    throw error;
  }
}

// Tek bir şehir verisi alma
export async function getCityById(id: string) {
  try {
    return await getItemById('cities', id);
  } catch (error) {
    console.error(`Şehir (ID: ${id}) alınırken hata:`, error);
    throw error;
  }
}

// Yeni şehir ekleme
export async function createCity(cityData: any) {
  try {
    return await createItem('cities', {
      ...cityData,
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString()
    });
  } catch (error) {
    console.error('Şehir oluşturulurken hata:', error);
    throw error;
  }
}

// Şehir güncelleme
export async function updateCity(id: string, cityData: any) {
  try {
    return await updateItem('cities', id, {
      ...cityData,
      updated_at: new Date().toISOString()
    });
  } catch (error) {
    console.error(`Şehir (ID: ${id}) güncellenirken hata:`, error);
    throw error;
  }
}

// Şehir silme
export async function deleteCity(id: string) {
  try {
    return await deleteItem('cities', id);
  } catch (error) {
    console.error(`Şehir (ID: ${id}) silinirken hata:`, error);
    throw error;
  }
}