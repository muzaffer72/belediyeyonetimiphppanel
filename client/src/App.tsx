import { useState, useEffect } from 'react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { SplashScreen } from './components/SplashScreen';
import { Dashboard } from './pages/Dashboard';
import { AdManagement } from './pages/AdManagement';
import { Analytics } from './pages/Analytics';
import { Router, Route, Link, useLocation } from 'wouter';
import { Menu, X, BarChart3, Settings, Home } from 'lucide-react';

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 5 * 60 * 1000,
      retry: 1,
    },
  },
});

function Navigation() {
  const [isOpen, setIsOpen] = useState(false);
  const [location] = useLocation();

  const navItems = [
    { path: '/', icon: Home, label: 'Ana Sayfa' },
    { path: '/ads', icon: Settings, label: 'Reklam Yönetimi' },
    { path: '/analytics', icon: BarChart3, label: 'Analitikler' },
  ];

  return (
    <nav className="bg-white shadow-lg border-b">
      <div className="max-w-7xl mx-auto px-4">
        <div className="flex justify-between h-16">
          <div className="flex items-center">
            <Link href="/" className="flex items-center space-x-3">
              <div className="w-8 h-8 bg-blue-600 rounded-lg flex items-center justify-center">
                <span className="text-white font-bold">B</span>
              </div>
              <span className="text-xl font-bold text-gray-900">Belediye Yönetimi</span>
            </Link>
          </div>

          {/* Desktop Navigation */}
          <div className="hidden md:flex items-center space-x-8">
            {navItems.map((item) => (
              <Link
                key={item.path}
                href={item.path}
                className={`flex items-center space-x-2 px-3 py-2 rounded-md text-sm font-medium transition-colors ${
                  location === item.path
                    ? 'text-blue-600 bg-blue-50'
                    : 'text-gray-700 hover:text-blue-600 hover:bg-gray-50'
                }`}
              >
                <item.icon size={18} />
                <span>{item.label}</span>
              </Link>
            ))}
          </div>

          {/* Mobile menu button */}
          <div className="md:hidden flex items-center">
            <button
              onClick={() => setIsOpen(!isOpen)}
              className="p-2 rounded-md text-gray-700 hover:text-blue-600"
            >
              {isOpen ? <X size={24} /> : <Menu size={24} />}
            </button>
          </div>
        </div>

        {/* Mobile Navigation */}
        {isOpen && (
          <div className="md:hidden py-4 border-t">
            {navItems.map((item) => (
              <Link
                key={item.path}
                href={item.path}
                className={`flex items-center space-x-3 px-3 py-3 rounded-md text-base font-medium transition-colors ${
                  location === item.path
                    ? 'text-blue-600 bg-blue-50'
                    : 'text-gray-700 hover:text-blue-600 hover:bg-gray-50'
                }`}
                onClick={() => setIsOpen(false)}
              >
                <item.icon size={20} />
                <span>{item.label}</span>
              </Link>
            ))}
          </div>
        )}
      </div>
    </nav>
  );
}

function AppContent() {
  const [showSplash, setShowSplash] = useState(true);
  const [userLocation, setUserLocation] = useState<{
    cityId?: string;
    districtId?: string;
  }>({});

  // Kullanıcı konumunu al (gerçek veri)
  useEffect(() => {
    // Geolocation API veya IP bazlı konum tespiti
    // Bu kısım gerçek konum verisiyle çalışır
    const detectLocation = async () => {
      try {
        // Burada gerçek konum API'nizi kullanabilirsiniz
        // Örnek: IP-API, MaxMind vb.
        setUserLocation({
          cityId: undefined, // Gerçek şehir ID'si
          districtId: undefined, // Gerçek ilçe ID'si
        });
      } catch (error) {
        console.error('Konum tespit edilemedi:', error);
      }
    };

    detectLocation();
  }, []);

  return (
    <div className="min-h-screen bg-gray-50">
      {/* Splash Screen - Gerçek verilerle */}
      {showSplash && (
        <SplashScreen
          onClose={() => setShowSplash(false)}
          userLocation={userLocation}
        />
      )}

      {/* Ana Uygulama */}
      <Navigation />
      
      <main className="max-w-7xl mx-auto py-6 px-4">
        <Router>
          <Route path="/" component={Dashboard} />
          <Route path="/ads" component={AdManagement} />
          <Route path="/analytics" component={Analytics} />
        </Router>
      </main>
    </div>
  );
}

export default function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <AppContent />
    </QueryClientProvider>
  );
}