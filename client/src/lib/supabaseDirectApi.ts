// Doğrudan Supabase API'lerine bağlanarak veri çekmek için kullanılacak fonksiyonlar
const SUPABASE_URL = 'https://bimer.onvao.net:8443/rest/v1';
const SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyAgCiAgICAicm9sZSI6ICJzZXJ2aWNlX3JvbGUiLAogICAgImlzcyI6ICJzdXBhYmFzZS1kZW1vIiwKICAgICJpYXQiOiAxNjQxNzY5MjAwLAogICAgImV4cCI6IDE3OTk1MzU2MDAKfQ.DaYlNEoUrrEn2Ig7tqibS-PHK5vgusbcbo7X36XVt4Q';

// Supabase API'si için gerekli headerlar
const headers = {
  'apikey': SUPABASE_KEY,
  'Authorization': `Bearer ${SUPABASE_KEY}`,
  'Content-Type': 'application/json',
  'Prefer': 'return=representation'
};

interface FetchOptions {
  page?: number;
  pageSize?: number;
  sortBy?: string;
  sortOrder?: 'asc' | 'desc';
  filters?: Record<string, any>;
}

// Temel veri çekme fonksiyonu
export const fetchFromSupabase = async <T>(
  table: string, 
  options: FetchOptions = {}
): Promise<{ data: T[], count: number }> => {
  try {
    const { page = 1, pageSize = 10, sortBy = 'created_at', sortOrder = 'desc', filters = {} } = options;
    
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
    
    // Verileri sınırla
    queryParams.append('limit', pageSize.toString());
    
    // İsteği gönder
    const url = `${SUPABASE_URL}/${table}?${queryParams.toString()}`;
    console.log("API İstek URL:", url);
    const response = await fetch(url, { headers: rangeHeader });
    
    if (!response.ok) {
      throw new Error(`Error fetching data: ${response.statusText}`);
    }
    
    // Toplam kayıt sayısını al
    const countHeader = response.headers.get('content-range');
    console.log("Content-Range header:", countHeader);
    let count = 0;
    if (countHeader) {
      const match = countHeader.match(/\d+-\d+\/(\d+|\*)/);
      count = match ? (match[1] !== '*' ? parseInt(match[1], 10) : 100) : 0;
    } else {
      // Eğer header yoksa veya sayı alınamadıysa, varsayılan bir değer kullan
      // Bu sadece kullanıcı arayüzü için geçici bir çözümdür
      count = 20;
    }
    
    const data = await response.json();
    return { data, count };
  } catch (error) {
    console.error(`Error in fetchFromSupabase (${table}):`, error);
    return { data: [], count: 0 };
  }
};

// Tek bir öğe almak için
export const getItemById = async <T>(table: string, id: string): Promise<T | null> => {
  try {
    const url = `${SUPABASE_URL}/${table}?id=eq.${id}&limit=1`;
    const response = await fetch(url, { headers });
    
    if (!response.ok) {
      throw new Error(`Error fetching item: ${response.statusText}`);
    }
    
    const data = await response.json();
    return data[0] || null;
  } catch (error) {
    console.error(`Error in getItemById (${table}):`, error);
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