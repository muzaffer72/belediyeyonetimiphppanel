import { useState, useEffect } from 'react';
import { useQuery } from '@tanstack/react-query';
import { X, ExternalLink } from 'lucide-react';
import { apiRequest } from '../lib/queryClient';

interface SplashAd {
  id: string;
  title: string;
  content: string;
  imageUrls: string[];
  targetUrl?: string;
  isPinned: boolean;
}

interface SplashScreenProps {
  onClose: () => void;
  userLocation?: {
    cityId?: string;
    districtId?: string;
  };
}

export function SplashScreen({ onClose, userLocation }: SplashScreenProps) {
  const [currentAdIndex, setCurrentAdIndex] = useState(0);
  const [isVisible, setIsVisible] = useState(true);

  // Supabase'den gerçek splash screen reklamlarını çek
  const { data: splashAds = [], isLoading } = useQuery({
    queryKey: ['/api/ads/splash'],
    queryFn: () => apiRequest('/api/ads/splash'),
  });

  // 5 saniye sonra otomatik kapat
  useEffect(() => {
    const timer = setTimeout(() => {
      handleClose();
    }, 5000);

    return () => clearTimeout(timer);
  }, []);

  // Reklam etkileşimini kaydet
  const recordInteraction = async (adId: string, type: 'impression' | 'click') => {
    try {
      await apiRequest(`/api/ads/${adId}/interaction`, {
        method: 'POST',
        body: JSON.stringify({
          interactionType: type,
          userId: null, // Anonim kullanıcı
          ipAddress: null, // Client-side'da IP alınamaz
          userAgent: navigator.userAgent,
        }),
      });
    } catch (error) {
      console.error('Etkileşim kaydedilemedi:', error);
    }
  };

  // Görüntülenme kaydı
  useEffect(() => {
    if (splashAds.length > 0 && splashAds[currentAdIndex]) {
      recordInteraction(splashAds[currentAdIndex].id, 'impression');
    }
  }, [splashAds, currentAdIndex]);

  const handleClose = () => {
    setIsVisible(false);
    setTimeout(() => {
      onClose();
    }, 300);
  };

  const handleAdClick = (ad: SplashAd) => {
    recordInteraction(ad.id, 'click');
    if (ad.targetUrl) {
      window.open(ad.targetUrl, '_blank');
    }
  };

  if (isLoading || !splashAds.length || !isVisible) return null;

  const currentAd = splashAds[currentAdIndex];

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 backdrop-blur-sm">
      <div 
        className={`relative max-w-2xl mx-4 bg-white rounded-2xl shadow-2xl overflow-hidden transform transition-all duration-300 ${
          isVisible ? 'scale-100 opacity-100' : 'scale-95 opacity-0'
        }`}
      >
        {/* Kapat butonu */}
        <button
          onClick={handleClose}
          className="absolute top-4 right-4 z-10 p-2 bg-black/20 hover:bg-black/40 rounded-full text-white transition-colors"
        >
          <X size={20} />
        </button>

        {/* Reklam içeriği */}
        <div 
          className="cursor-pointer"
          onClick={() => handleAdClick(currentAd)}
        >
          {/* Görsel */}
          {currentAd.imageUrls && currentAd.imageUrls.length > 0 && (
            <div className="w-full h-64 md:h-80 overflow-hidden">
              <img
                src={currentAd.imageUrls[0]}
                alt={currentAd.title}
                className="w-full h-full object-cover"
              />
            </div>
          )}

          {/* İçerik */}
          <div className="p-6">
            {currentAd.isPinned && (
              <div className="inline-block px-3 py-1 mb-3 text-xs font-semibold text-orange-600 bg-orange-100 rounded-full">
                Öne Çıkan
              </div>
            )}
            
            <h2 className="text-2xl font-bold text-gray-900 mb-3">
              {currentAd.title}
            </h2>
            
            <p className="text-gray-600 mb-4 leading-relaxed">
              {currentAd.content}
            </p>

            {currentAd.targetUrl && (
              <div className="flex items-center text-blue-600 font-medium">
                <span>Devamını gör</span>
                <ExternalLink size={16} className="ml-2" />
              </div>
            )}
          </div>
        </div>

        {/* Sayfa göstergesi */}
        {splashAds.length > 1 && (
          <div className="flex justify-center space-x-2 pb-4">
            {splashAds.map((_, index) => (
              <button
                key={index}
                onClick={() => setCurrentAdIndex(index)}
                className={`w-2 h-2 rounded-full transition-colors ${
                  index === currentAdIndex ? 'bg-blue-600' : 'bg-gray-300'
                }`}
              />
            ))}
          </div>
        )}

        {/* Otomatik kapanma göstergesi */}
        <div className="absolute bottom-0 left-0 h-1 bg-blue-600 animate-pulse" 
             style={{ 
               width: '100%',
               animation: 'shrink 5s linear forwards'
             }} 
        />
      </div>

      <style jsx>{`
        @keyframes shrink {
          from { width: 100%; }
          to { width: 0%; }
        }
      `}</style>
    </div>
  );
}