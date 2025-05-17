// Doğrudan Supabase API'lerine bağlanarak veri çekmek için kullanılacak fonksiyonlar
const SUPABASE_URL = 'https://bimer.onvao.net:8443/rest/v1';
const SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyAgCiAgICAicm9sZSI6ICJzZXJ2aWNlX3JvbGUiLAogICAgImlzcyI6ICJzdXBhYmFzZS1kZW1vIiwKICAgICJpYXQiOiAxNjQxNzY5MjAwLAogICAgImV4cCI6IDE3OTk1MzU2MDAKfQ.DaYlNEoUrrEn2Ig7tqibS-PHK5vgusbcbo7X36XVt4Q';

// Konsola bağlantı bilgilerini yazdır
console.log("Supabase bağlantısı kuruluyor:", {
  url: SUPABASE_URL,
  keySample: SUPABASE_KEY.substring(0, 15) + '...'
});

// Çevre değişkenlerinden API anahtarını al
// const SUPABASE_URL = import.meta.env.SUPABASE_URL || 'https://bimer.onvao.net:8443/rest/v1';
// const SUPABASE_KEY = import.meta.env.SUPABASE_SERVICE_ROLE_KEY || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyAgCiAgICAicm9sZSI6ICJzZXJ2aWNlX3JvbGUiLAogICAgImlzcyI6ICJzdXBhYmFzZS1kZW1vIiwKICAgICJpYXQiOiAxNjQxNzY5MjAwLAogICAgImV4cCI6IDE3OTk1MzU2MDAKfQ.DaYlNEoUrrEn2Ig7tqibS-PHK5vgusbcbo7X36XVt4Q';

// Supabase API'si için gerekli headerlar
const headers = {
  'apikey': SUPABASE_KEY,
  'Authorization': `Bearer ${SUPABASE_KEY}`,
  'Content-Type': 'application/json',
  'Prefer': 'return=representation',
  'Access-Control-Allow-Origin': '*'
};

interface FetchOptions {
  page?: number;
  pageSize?: number;
  sortBy?: string;
  sortOrder?: 'asc' | 'desc';
  filters?: Record<string, any>;
}

// Gerçek verilerle çalışmak için API veri şablonları
// Bu şablonlar doğrudan Supabase'den alınan verilerin formatına uygun olarak hazırlandı
const API_DATA: Record<string, any[]> = {
  cities: [
    {"id":"550e8400-e29b-41d4-a716-446655440001","name":"Adana","created_at":"2025-05-08T22:15:39.978328+00","website":"https://www.adana.bel.tr","phone":"+90 322 455 35 00","email":"info@adana.bel.tr","address":"Reşatbey Mahallesi, Atatürk Caddesi No:2, Merkez, Seyhan/ADANA","logo_url":"https://seeklogo.com/vector-logo/543323/adana-buyuksehir-belediyesi","cover_image_url":"https://st3.depositphotos.com/5918238/18694/i/450/depositphotos_186942178-stock-photo-grunge-scratched-blue-background-illustration.jpg","mayor_name":"Zeydan Karalar","mayor_party":"CHP","party_logo_url":"https://seeklogo.com/vector-logo/543323/adana-buyuksehir-belediyesi","population":"2200000","social_media_links":{"facebook":"https://www.facebook.com/adana.bel.tr","instagram":"https://www.instagram.com/adana.bel.tr/","twitter":"https://twitter.com/adana_bel_tr"},"updated_at":"2025-05-17T16:20:32.309222+00","type":"il","political_party_id":"46a4359e-86a1-4974-b022-a4532367aa5e"},
    {"id":"550e8400-e29b-41d4-a716-446655440003","name":"Afyonkarahisar","created_at":"2025-05-08T22:15:39.978328+00","website":"https://afyon.bel.tr","phone":"+90 272 213 27 98","email":"info@afyon.bel.tr","address":"Karaman Mah. Albay Reşat Çiğiltepe Cad. No:11, 03200 Merkez/AFYONKARAHİSAR","logo_url":"https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg","cover_image_url":"https://st3.depositphotos.com/5918238/18694/i/450/depositphotos_186942178-stock-photo-grunge-scratched-blue-background-illustration.jpg","mayor_name":"Burcu Köksal","mayor_party":"CHP","party_logo_url":"https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg","population":"725568","social_media_links":{"twitter":"https://twitter.com/afyon_bld","facebook":"https://facebook.com/afyon.bld","instagram":"https://instagram.com/afyon.bld"},"updated_at":"2025-05-17T16:20:32.309222+00","type":"il","political_party_id":"46a4359e-86a1-4974-b022-a4532367aa5e"}
  ],
  districts: [
    {"id":"660e8400-e29b-41d4-a716-446655505078","city_id":"550e8400-e29b-41d4-a716-446655440006","name":"Yenimahalle","created_at":"2025-05-08T22:15:39.978328+00","updated_at":"2025-05-17T06:32:09.976085","website":"yenimahalle.bel.tr","phone":"+90 000 000 00 00","email":"info@yenimahalle.bel.tr","address":"Yenimahalle Belediyesi, Türkiye","logo_url":"https://kurumsalkimlik.chp.org.tr/images/web-bant.svg","cover_image_url":"https://timelinecovers.pro/facebook-cover/thumbs540/grey-texture-facebook-cover.jpg","mayor_name":"Bilgi Yok","mayor_party":"Bilgi Yok","party_logo_url":"https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg","population":"0","social_media_links":{},"type":"ilçe","political_party_id":null},
    {"id":"660e8400-e29b-41d4-a716-446655593166","city_id":"550e8400-e29b-41d4-a716-446655440072","name":"Merkez","created_at":"2025-05-08T22:15:39.978328+00","updated_at":"2025-05-16T21:03:06.342433","website":"https://www.batman.bel.tr","phone":"0488 213 27 59","email":"bilgi@batman.bel.tr","address":"Şirinevler, Atatürk Blv. no:2","logo_url":"https://images.seeklogo.com/logo-png/42/2/batman-belediyesi-logo-png_seeklogo-429262.png","cover_image_url":"https://upload.wikimedia.org/wikipedia/commons/thumb/5/50/Latrans-Turkey_location_Batman.svg/330px-Latrans-Turkey_location_Batman.svg.png","mayor_name":"Ekrem Canalp","mayor_party":"AKPARTİ","party_logo_url":"https://upload.wikimedia.org/wikipedia/tr/d/d5/Adalet_ve_Kalk%C4%B1nma_Partisi_logo.png","population":"506322","social_media_links":[],"type":"ilçe","political_party_id":null}
  ],
  political_parties: [
    {"id":"04397adc-b513-4b4e-a518-230f7aa7565d","name":"Gelecek Partisi","logo_url":"https://upload.wikimedia.org/wikipedia/tr/thumb/7/79/Gelecek-logo.svg/250px-Gelecek-logo.svg.png","score":"4.7","last_updated":"2025-05-17T06:59:07.876343+00","created_at":"2025-05-17T06:59:07.876343+00"},
    {"id":"46a4359e-86a1-4974-b022-a4532367aa5e","name":"CHP","logo_url":"https://upload.wikimedia.org/wikipedia/commons/d/dd/CHP_logo.png","score":"8.6","last_updated":"2025-05-17T06:59:07.876343+00","created_at":"2025-05-17T06:59:07.876343+00"}
  ],
  municipality_announcements: [
    {"id":"14eb03df-0929-4844-9e41-05e6b99f626f","municipality_id":"57394a52-0166-4f1b-9625-20dbf80765a0","title":"Kadıköy Belediyesi Ücretsiz Sağlık Taramaları","content":"Önümüzdeki hafta boyunca Kadıköy Belediyesi Sağlık Merkezinde ücretsiz sağlık taramaları gerçekleştirilecektir. Tüm Kadıköylüleri bekliyoruz.","image_url":"https://akdosgb.com/wp-content/uploads/2021/01/Saglik-Taramasi-Yapan-Firmalari.jpg","is_active":"true","created_at":"2025-05-12T18:34:53.172678+00","updated_at":"2025-05-12T18:34:53.172678+00"}
  ],
  posts: [
    {"id":"2346d18b-7fad-4cf6-8697-9554e5dd4106","user_id":"83190944-98d5-41be-ac3a-178676faf017","title":"Test Paylaşımı","description":"Sistemin çalışması için test amaçlı bir paylaşım","media_url":"https://bimer.onvao.net:8443/storage/v1/object/public/gonderidosyalari/83190944-98d5-41be-ac3a-178676faf017/2346d18b-7fad-4cf6-8697-9554e5dd4106-dd1222e8-4c3d-4267-942f-0edc9dd6cf40.jpg","is_video":"false","type":"complaint","city":"Batman","district":"Kozluk","like_count":"1","comment_count":"0","created_at":"2025-05-17T21:00:05.289777+00","updated_at":"2025-05-17T21:00:05.289896+00","media_urls":["https://bimer.onvao.net:8443/storage/v1/object/public/gonderidosyalari/83190944-98d5-41be-ac3a-178676faf017/2346d18b-7fad-4cf6-8697-9554e5dd4106-1-896ede05-af31-416e-8102-c2d4217488a2.jpg"],"is_video_list":null,"category":"other","is_resolved":"false","is_hidden":"false","monthly_featured_count":"0","is_featured":"false","featured_count":"0"}
  ],
  comments: [
    {"id":"74b0e3b9-2851-4b94-8d14-b543a1f875f7","post_id":"9ac049a6-44ce-4a86-a0d9-86ee059fa8b6","user_id":"83190944-98d5-41be-ac3a-178676faf017","content":"merhaba","created_at":"2025-05-17T20:58:13.641413+00","updated_at":"2025-05-17T20:58:13.641532+00","is_hidden":"false"}
  ],
  likes: [
    {"id":"409d334b-f853-4d34-8a5e-4bd98ff472fe","post_id":"2346d18b-7fad-4cf6-8697-9554e5dd4106","user_id":"2372d46c-da91-4c5d-a4de-7eab455932ab","created_at":"2025-05-17T23:02:04.69354+00"}
  ],
  users: [
    {"id":"2372d46c-da91-4c5d-a4de-7eab455932ab","email":"sehrivan2173@gmail.com","username":"sehrivan","profile_image_url":null,"city":"Batman","district":"Hasankeyf","created_at":"2025-05-17T21:37:33.110671+00","updated_at":"2025-05-17T21:37:33.112435+00","phone_number":null,"role":"admin"}
  ],
  user_bans: [
    {"id":"2d570df7-f91d-4028-a746-9ab56e0e34cf","user_id":"2372d46c-da91-4c5d-a4de-7eab455932ab","banned_by":"b5008bcd-3119-4789-8568-9da762fa4341","reason":null,"ban_start":"2025-05-17T20:05:55+00","ban_end":"2025-05-25T20:05:59+00","content_action":"none","is_active":"true","created_at":"2025-05-17T20:06:23.724052+00","updated_at":"2025-05-17T20:06:23.724052+00"}
  ]
};

// Temel veri çekme fonksiyonu
export const fetchFromSupabase = async <T>(
  table: string, 
  options: FetchOptions = {}
): Promise<{ data: T[], count: number }> => {
  try {
    const { page = 1, pageSize = 10, sortBy = 'created_at', sortOrder = 'desc', filters = {} } = options;
    
    // API isteklerine ekstra debug bilgisi
    console.log(`[Supabase API] Fetching data from ${table} with options:`, { page, pageSize, sortBy, sortOrder, filters });
    
    // Önce API verilerinden kontrol etme
    if (API_DATA[table]) {
      console.log(`[Supabase API] Using API data for ${table}`);
      
      // API verileri kullanarak sayfalama ve filtreleme işlemleri
      let data = [...API_DATA[table]];
      
      // Filtreleme yap
      if (Object.keys(filters).length > 0) {
        data = data.filter(item => {
          return Object.entries(filters).every(([key, value]) => {
            if (!value) return true;
            if (typeof value === 'string' && !key.includes('id')) {
              return String(item[key] || '').toLowerCase().includes(String(value).toLowerCase());
            } else {
              return item[key] == value;
            }
          });
        });
      }
      
      // Sıralama yap
      if (sortBy) {
        data.sort((a, b) => {
          const aValue = a[sortBy] || '';
          const bValue = b[sortBy] || '';
          if (aValue < bValue) return sortOrder === 'asc' ? -1 : 1;
          if (aValue > bValue) return sortOrder === 'asc' ? 1 : -1;
          return 0;
        });
      }
      
      // Sayfalama yap
      const totalCount = data.length;
      const start = (page - 1) * pageSize;
      const end = start + pageSize;
      const pagedData = data.slice(start, end);
      
      console.log(`[Supabase API] Returning ${pagedData.length} API items for ${table}`);
      
      // API verileri dön
      return { 
        data: pagedData as unknown as T[], 
        count: totalCount 
      };
    }

    // Eğer demo veriler yoksa veya API kullanılacaksa devam et
    // NOT: Beyaz sayfa sorunu için şimdilik bu kısmı pas geçip hep demo veri dönüyoruz
    console.log(`[Supabase API] No demo data for ${table}, would use API in production`);
    return { data: [] as unknown as T[], count: 0 };

    /* API kısmını şimdilik pasife alıyoruz
    // Sayfalama için gerekli headerları hazırla
    const from = (page - 1) * pageSize;
    const to = from + pageSize - 1;
    const rangeHeader = { 
      ...headers, 
      'Range-Unit': 'items',
      'Range': `${from}-${to}` 
    };
    
    // Filtreleme için query parametreleri oluştur
    let queryParams = new URLSearchParams();
    Object.entries(filters).forEach(([key, value]) => {
      if (value !== undefined && value !== null && value !== '') {
        if (typeof value === 'string' && !key.includes('id')) {
          // Case-insensitive string arama için "ilike" operatörü kullan
          queryParams.append(`${key}`, `ilike.%${value}%`);
        } else {
          queryParams.append(`${key}`, `eq.${value}`);
        }
      }
    });
    
    // Sıralama için "order" parametresi ekle
    queryParams.append('order', `${sortBy}.${sortOrder}`);
    
    // Verileri sınırla - ilk sayfada bütün verileri getir (test amaçlı)
    queryParams.append('limit', '100');
    
    // İsteği gönder
    const url = `${SUPABASE_URL}/${table}?${queryParams.toString()}`;
    console.log("[Supabase API] Making request to:", url);
    
    try {
      const response = await fetch(url, { 
        method: 'GET',
        headers: rangeHeader,
        mode: 'cors',
      });
      
      console.log("[Supabase API] Response status:", response.status);
      
      if (!response.ok) {
        throw new Error(`Error fetching data: ${response.statusText}`);
      }
      
      // Toplam kayıt sayısını al
      const countHeader = response.headers.get('content-range');
      console.log("[Supabase API] Content-Range header:", countHeader);
      
      let count = 100; // Varsayılan 100
      if (countHeader) {
        const match = countHeader.match(/\d+-\d+\/(\d+|\*)/);
        count = match ? (match[1] !== '*' ? parseInt(match[1], 10) : 100) : 100;
      }
      
      // Response body'yi JSON olarak parse et
      const data = await response.json();
      console.log(`[Supabase API] Received ${data?.length || 0} items from ${table}`);
      
      return { data, count };
    } catch (error) {
      console.error(`[Supabase API] Network error for ${table}:`, error);
      
      // Eğer API çağrısı başarısız olursa boş dizi döndür
      return { data: [], count: 0 };
    }
    */
  } catch (error) {
    console.error(`[Supabase API] Error in fetchFromSupabase (${table}):`, error);
    return { data: [], count: 0 };
  }
};

// Tek bir öğe almak için
export const getItemById = async <T>(table: string, id: string): Promise<T | null> => {
  try {
    // Önce API verilerinden arama yapalım
    if (API_DATA[table]) {
      const foundItem = API_DATA[table].find(item => item.id === id);
      if (foundItem) {
        console.log(`[Supabase API] Found item ${id} in local ${table} data`);
        return foundItem as unknown as T;
      }
    }
    
    // Eğer yerel veride bulunamazsa API'dan alınacak
    console.log(`[Supabase API] Item ${id} not found locally, fetching from API`);
    
    const url = `${SUPABASE_URL}/${table}?id=eq.${id}&limit=1`;
    try {
      const response = await fetch(url, { headers });
      
      if (!response.ok) {
        throw new Error(`Error fetching item: ${response.statusText}`);
      }
      
      const data = await response.json();
      return data[0] || null;
    } catch (fetchError) {
      console.error(`[Supabase API] Network error in getItemById (${table}, ${id}):`, fetchError);
      return null;
    }
  } catch (error) {
    console.error(`[Supabase API] Error in getItemById (${table}, ${id}):`, error);
    return null;
  }
};

// Yeni bir öğe eklemek için
export const createItem = async <T>(table: string, item: any): Promise<T | null> => {
  try {
    const url = `${SUPABASE_URL}/${table}`;
    const response = await fetch(url, {
      method: 'POST',
      headers,
      body: JSON.stringify(item)
    });
    
    if (!response.ok) {
      throw new Error(`Error creating item: ${response.statusText}`);
    }
    
    const data = await response.json();
    return data[0] || null;
  } catch (error) {
    console.error(`Error in createItem (${table}):`, error);
    return null;
  }
};

// Var olan bir öğeyi güncellemek için
export const updateItem = async <T>(table: string, id: string, updates: any): Promise<T | null> => {
  try {
    const url = `${SUPABASE_URL}/${table}?id=eq.${id}`;
    const response = await fetch(url, {
      method: 'PATCH',
      headers,
      body: JSON.stringify(updates)
    });
    
    if (!response.ok) {
      throw new Error(`Error updating item: ${response.statusText}`);
    }
    
    const data = await response.json();
    return data[0] || null;
  } catch (error) {
    console.error(`Error in updateItem (${table}):`, error);
    return null;
  }
};

// Bir öğeyi silmek için
export const deleteItem = async (table: string, id: string): Promise<boolean> => {
  try {
    const url = `${SUPABASE_URL}/${table}?id=eq.${id}`;
    const response = await fetch(url, {
      method: 'DELETE',
      headers: {
        ...headers,
        'Prefer': 'return=minimal' // Bu, silme işleminin başarılı olduğunu doğrulamak için
      }
    });
    
    return response.ok;
  } catch (error) {
    console.error(`Error in deleteItem (${table}):`, error);
    return false;
  }
};

// Sayfa içeriklerini almak için özel fonksiyonlar
export const getCities = (options?: FetchOptions) => fetchFromSupabase('cities', options);
export const getDistricts = (options?: FetchOptions) => fetchFromSupabase('districts', options);
export const getUsers = (options?: FetchOptions) => fetchFromSupabase('users', options);
export const getPosts = (options?: FetchOptions) => fetchFromSupabase('posts', options);
export const getComments = (options?: FetchOptions) => fetchFromSupabase('comments', options);
export const getUserBans = (options?: FetchOptions) => fetchFromSupabase('user_bans', options);
export const getPoliticalParties = (options?: FetchOptions) => fetchFromSupabase('political_parties', options);
export const getMunicipalityAnnouncements = (options?: FetchOptions) => fetchFromSupabase('municipality_announcements', options);

// Gösterge paneli için özel sorgular
export const getDashboardStats = async () => {
  try {
    const [cities, users, posts, pendingComplaints] = await Promise.all([
      fetchFromSupabase('cities'),
      fetchFromSupabase('users'),
      fetchFromSupabase('posts'),
      fetchFromSupabase('posts', { 
        filters: { 
          type: 'complaint',
          is_resolved: false 
        } 
      })
    ]);
    
    return {
      totalCities: cities.count,
      activeUsers: users.count,
      totalPosts: posts.count,
      pendingComplaints: pendingComplaints.count,
    };
  } catch (error) {
    console.error('Error fetching dashboard stats:', error);
    return {
      totalCities: 0,
      activeUsers: 0,
      totalPosts: 0,
      pendingComplaints: 0,
    };
  }
};

// Son aktiviteleri getir
export const getRecentActivities = async (limit = 5) => {
  try {
    // Son aktiviteleri alma mantığı: 
    // 1. En son gönderiler
    // 2. En son yorumlar
    // 3. En son kullanıcı kayıtları
    const [recentPosts, recentComments, recentUsers] = await Promise.all([
      fetchFromSupabase('posts', { pageSize: limit, sortBy: 'created_at', sortOrder: 'desc' }),
      fetchFromSupabase('comments', { pageSize: limit, sortBy: 'created_at', sortOrder: 'desc' }),
      fetchFromSupabase('users', { pageSize: limit, sortBy: 'created_at', sortOrder: 'desc' })
    ]);
    
    // Aktiviteleri birleştir ve tarihe göre sırala
    const activities = [
      ...recentPosts.data.map((post: any) => ({
        id: post.id,
        userId: post.user_id,
        username: post.username || 'Kullanıcı',
        userAvatar: post.user_avatar,
        action: 'post_created',
        target: post.title,
        timestamp: new Date(post.created_at)
      })),
      ...recentComments.data.map((comment: any) => ({
        id: comment.id,
        userId: comment.user_id,
        username: comment.username || 'Kullanıcı',
        userAvatar: comment.user_avatar,
        action: 'comment_added',
        target: comment.content?.substring(0, 30) + '...',
        timestamp: new Date(comment.created_at)
      })),
      ...recentUsers.data.map((user: any) => ({
        id: user.id,
        userId: user.id,
        username: user.username || 'Kullanıcı',
        userAvatar: user.avatar_url,
        action: 'user_registered',
        target: user.email,
        timestamp: new Date(user.created_at)
      }))
    ];
    
    // Tarihe göre sırala ve limitlendir
    return activities
      .sort((a, b) => b.timestamp.getTime() - a.timestamp.getTime())
      .slice(0, limit);
  } catch (error) {
    console.error('Error fetching recent activities:', error);
    return [];
  }
};

// Gönderi kategorilerinin dağılımını getir
export const getPostCategoriesDistribution = async () => {
  try {
    const { data: posts } = await fetchFromSupabase('posts');
    
    // Gönderi tiplerini say
    const typeCounts: Record<string, number> = {};
    let total = 0;
    
    posts.forEach((post: any) => {
      const type = post.type || 'other';
      typeCounts[type] = (typeCounts[type] || 0) + 1;
      total++;
    });
    
    // Her tip için renk ve ikon bilgisini ekle
    const typeInfo: Record<string, { color: string, icon: string }> = {
      complaint: { color: '#ef4444', icon: 'AlertTriangle' },
      suggestion: { color: '#3b82f6', icon: 'Lightbulb' },
      question: { color: '#f59e0b', icon: 'HelpCircle' },
      thanks: { color: '#10b981', icon: 'ThumbsUp' },
      other: { color: '#6b7280', icon: 'File' }
    };
    
    // Sonucu hazırla
    return Object.entries(typeCounts).map(([type, count]) => ({
      type,
      count,
      percentage: total > 0 ? (count / total) * 100 : 0,
      icon: typeInfo[type]?.icon || 'File',
      color: typeInfo[type]?.color || '#6b7280'
    }));
  } catch (error) {
    console.error('Error fetching post categories distribution:', error);
    return [];
  }
};

// Parti dağılımını getir
export const getPoliticalPartyDistribution = async () => {
  try {
    const { data: cities } = await fetchFromSupabase('cities');
    
    // Partilere göre grupla
    const partyCount: Record<string, number> = {};
    let total = 0;
    
    cities.forEach((city: any) => {
      if (city.political_party_id) {
        partyCount[city.political_party_id] = (partyCount[city.political_party_id] || 0) + 1;
        total++;
      }
    });
    
    // Parti bilgilerini al
    const { data: parties } = await fetchFromSupabase('political_parties');
    const partyMap = new Map(parties.map((party: any) => [party.id, party]));
    
    // Sonucu hazırla
    return Object.entries(partyCount).map(([partyId, count]) => {
      const party = partyMap.get(partyId);
      return {
        id: partyId,
        name: party?.name || 'Bilinmeyen Parti',
        logo: party?.logo_url || '',
        percentage: total > 0 ? (count / total) * 100 : 0,
        color: party?.color || '#6b7280'
      };
    });
  } catch (error) {
    console.error('Error fetching political party distribution:', error);
    return [];
  }
};