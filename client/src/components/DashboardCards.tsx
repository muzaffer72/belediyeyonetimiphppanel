import { useState, useEffect } from "react";
import { StatCard } from "@/components/ui/stat-card";
import { useTranslation } from "@/lib/i18n";
import { getDashboardStats } from "@/lib/supabaseDirectApi";

export function DashboardCards() {
  const { t } = useTranslation();
  const [isLoading, setIsLoading] = useState(true);
  const [statsData, setStatsData] = useState<any>(null);
  
  useEffect(() => {
    async function fetchStats() {
      try {
        setIsLoading(true);
        const data = await getDashboardStats();
        setStatsData(data);
      } catch (error) {
        console.error("Gösterge Paneli verileri alınırken hata oluştu:", error);
      } finally {
        setIsLoading(false);
      }
    }
    
    fetchStats();
  }, []);

  if (isLoading) {
    return (
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-8">
        {[...Array(4)].map((_, i) => (
          <div key={i} className="bg-white rounded-lg shadow-sm p-6 border border-gray-100 animate-pulse">
            <div className="flex justify-between">
              <div>
                <div className="h-4 bg-gray-200 rounded w-24 mb-2.5"></div>
                <div className="h-8 bg-gray-200 rounded w-16"></div>
              </div>
              <div className="rounded-full bg-gray-200 h-12 w-12"></div>
            </div>
            <div className="mt-4 flex items-center">
              <div className="h-4 bg-gray-200 rounded w-32"></div>
            </div>
          </div>
        ))}
      </div>
    );
  }

  const stats = statsData || {
    totalCities: 0,
    activeUsers: 0,
    totalPosts: 0,
    pendingComplaints: 0
  };

  return (
    <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-8">
      <StatCard
        title="dashboard.total.municipalities"
        value={stats.totalCities}
        icon={<span className="material-icons">location_city</span>}
        iconBgColor="bg-primary-100"
        iconColor="text-primary-600"
        trend={{
          value: 3.2,
          isPositive: true
        }}
      />
      
      <StatCard
        title="dashboard.active.users"
        value={stats.activeUsers}
        icon={<span className="material-icons">people</span>}
        iconBgColor="bg-secondary-100"
        iconColor="text-secondary-600"
        trend={{
          value: 12.5,
          isPositive: true
        }}
      />
      
      <StatCard
        title="dashboard.total.posts"
        value={stats.totalPosts}
        icon={<span className="material-icons">article</span>}
        iconBgColor="bg-green-100"
        iconColor="text-green-600"
        trend={{
          value: 8.1,
          isPositive: true
        }}
      />
      
      <StatCard
        title="dashboard.pending.complaints"
        value={stats.pendingComplaints}
        icon={<span className="material-icons">report_problem</span>}
        iconBgColor="bg-amber-100"
        iconColor="text-amber-600"
        trend={{
          value: 4.3,
          isPositive: false
        }}
      />
    </div>
  );
}
