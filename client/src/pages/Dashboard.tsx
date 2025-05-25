import { useQuery } from '@tanstack/react-query';
import { Eye, MousePointer, TrendingUp, MapPin } from 'lucide-react';

// Gerçek Supabase verilerini çekecek API fonksiyonları
async function fetchDashboardData() {
  const response = await fetch('/api/ads?status=active');
  return response.json();
}

async function fetchCities() {
  const response = await fetch('/api/cities');
  return response.json();
}

export function Dashboard() {
  // Gerçek reklam verilerini çek
  const { data: ads = [], isLoading: adsLoading } = useQuery({
    queryKey: ['/api/ads'],
    queryFn: fetchDashboardData,
  });

  // Gerçek şehir verilerini çek
  const { data: cities = [], isLoading: citiesLoading } = useQuery({
    queryKey: ['/api/cities'],
    queryFn: fetchCities,
  });

  // Splash screen reklamlarını çek
  const { data: splashAds = [] } = useQuery({
    queryKey: ['/api/ads/splash'],
    queryFn: () => fetch('/api/ads/splash').then(res => res.json()),
  });

  // İstatistikleri hesapla
  const totalImpressions = ads.reduce((sum, ad) => sum + (ad.impressions || 0), 0);
  const totalClicks = ads.reduce((sum, ad) => sum + (ad.clicks || 0), 0);
  const avgCTR = totalImpressions > 0 ? ((totalClicks / totalImpressions) * 100).toFixed(2) : '0.00';
  const activeSplashAds = splashAds.length;

  if (adsLoading || citiesLoading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600"></div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Başlık */}
      <div>
        <h1 className="text-3xl font-bold text-gray-900">Belediye Reklam Yönetimi</h1>
        <p className="text-gray-600 mt-2">Sponsorlu reklamları yönetin ve performansları izleyin</p>
      </div>

      {/* İstatistik Kartları */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
        <div className="bg-white p-6 rounded-lg shadow-sm border">
          <div className="flex items-center">
            <div className="p-3 rounded-full bg-blue-100">
              <Eye className="h-6 w-6 text-blue-600" />
            </div>
            <div className="ml-4">
              <p className="text-sm font-medium text-gray-600">Toplam Görüntülenme</p>
              <p className="text-2xl font-bold text-gray-900">{totalImpressions.toLocaleString()}</p>
            </div>
          </div>
        </div>

        <div className="bg-white p-6 rounded-lg shadow-sm border">
          <div className="flex items-center">
            <div className="p-3 rounded-full bg-green-100">
              <MousePointer className="h-6 w-6 text-green-600" />
            </div>
            <div className="ml-4">
              <p className="text-sm font-medium text-gray-600">Toplam Tıklama</p>
              <p className="text-2xl font-bold text-gray-900">{totalClicks.toLocaleString()}</p>
            </div>
          </div>
        </div>

        <div className="bg-white p-6 rounded-lg shadow-sm border">
          <div className="flex items-center">
            <div className="p-3 rounded-full bg-orange-100">
              <TrendingUp className="h-6 w-6 text-orange-600" />
            </div>
            <div className="ml-4">
              <p className="text-sm font-medium text-gray-600">Ortalama CTR</p>
              <p className="text-2xl font-bold text-gray-900">%{avgCTR}</p>
            </div>
          </div>
        </div>

        <div className="bg-white p-6 rounded-lg shadow-sm border">
          <div className="flex items-center">
            <div className="p-3 rounded-full bg-purple-100">
              <MapPin className="h-6 w-6 text-purple-600" />
            </div>
            <div className="ml-4">
              <p className="text-sm font-medium text-gray-600">Açılış Sayfası Reklamları</p>
              <p className="text-2xl font-bold text-gray-900">{activeSplashAds}</p>
            </div>
          </div>
        </div>
      </div>

      {/* Aktif Reklamlar */}
      <div className="bg-white rounded-lg shadow-sm border">
        <div className="p-6 border-b">
          <h2 className="text-xl font-semibold text-gray-900">Aktif Reklamlar</h2>
          <p className="text-gray-600 mt-1">Şu anda yayında olan reklamlar</p>
        </div>
        <div className="p-6">
          {ads.length === 0 ? (
            <p className="text-gray-500 text-center py-8">Henüz aktif reklam bulunmuyor.</p>
          ) : (
            <div className="space-y-4">
              {ads.slice(0, 5).map((ad) => (
                <div key={ad.id} className="flex items-center justify-between p-4 border rounded-lg hover:bg-gray-50">
                  <div className="flex items-center space-x-4">
                    {ad.image_urls && ad.image_urls[0] && (
                      <img 
                        src={ad.image_urls[0]} 
                        alt={ad.title}
                        className="w-12 h-12 rounded-lg object-cover"
                      />
                    )}
                    <div>
                      <h3 className="font-medium text-gray-900">{ad.title}</h3>
                      <p className="text-sm text-gray-600">
                        {ad.ad_display_scope === 'splash' ? '🎯 Açılış Sayfası' : 
                         ad.ad_display_scope === 'herkes' ? '🌍 Tüm Kullanıcılar' :
                         ad.ad_display_scope === 'il' ? `🏙️ ${ad.city}` :
                         ad.ad_display_scope === 'ilce' ? `🏘️ ${ad.district}` :
                         `🏙️ ${ad.city} - ${ad.district}`}
                      </p>
                    </div>
                  </div>
                  <div className="text-right">
                    <div className="text-sm text-gray-600">
                      👁️ {(ad.impressions || 0).toLocaleString()} | 
                      🖱️ {(ad.clicks || 0).toLocaleString()}
                    </div>
                    <div className="text-xs text-gray-500">
                      CTR: %{ad.impressions > 0 ? ((ad.clicks / ad.impressions) * 100).toFixed(2) : '0.00'}
                    </div>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>

      {/* Şehir Dağılımı */}
      <div className="bg-white rounded-lg shadow-sm border">
        <div className="p-6 border-b">
          <h2 className="text-xl font-semibold text-gray-900">Şehir Dağılımı</h2>
          <p className="text-gray-600 mt-1">Sistemde kayıtlı şehirler</p>
        </div>
        <div className="p-6">
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {cities.slice(0, 6).map((city) => (
              <div key={city.id} className="p-4 border rounded-lg">
                <div className="flex items-center justify-between">
                  <span className="font-medium text-gray-900">{city.name}</span>
                  <span className="text-sm text-gray-500">
                    {city.plate_code && `(${city.plate_code})`}
                  </span>
                </div>
                {city.is_metropolitan && (
                  <span className="inline-block mt-2 px-2 py-1 text-xs font-medium text-blue-600 bg-blue-100 rounded-full">
                    Büyükşehir
                  </span>
                )}
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}