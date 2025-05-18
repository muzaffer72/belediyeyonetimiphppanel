import { useState, useEffect } from "react";
import { useTranslation } from "@/lib/i18n";
import { Button } from "@/components/ui/button";
import { ChartCard } from "@/components/ui/chart-card";
import { Skeleton } from "@/components/ui/skeleton";
import { formatMessage } from "@/lib/i18n";
import { getPoliticalPartyDistribution } from "@/lib/supabaseDirectApi";

export function PoliticalDistribution() {
  const { t } = useTranslation();
  const [distribution, setDistribution] = useState<any[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  
  useEffect(() => {
    async function fetchDistribution() {
      try {
        setIsLoading(true);
        const data = await getPoliticalPartyDistribution();
        setDistribution(data);
      } catch (error) {
        console.error("Parti dağılımı alınırken hata oluştu:", error);
      } finally {
        setIsLoading(false);
      }
    }
    
    fetchDistribution();
  }, []);

  const partyColors = ['bg-blue-600', 'bg-red-600', 'bg-yellow-500', 'bg-green-500', 'bg-purple-500', 'bg-orange-500'];

  if (isLoading) {
    return (
      <ChartCard
        title="dashboard.party.distribution"
        action={<Button variant="link" size="sm">{t('dashboard.details')}</Button>}
      >
        <div className="space-y-4 animate-pulse">
          {[...Array(4)].map((_, i) => (
            <div key={i} className="flex items-center">
              <Skeleton className="w-10 h-10 rounded-full mr-3" />
              <div className="flex-1">
                <div className="flex justify-between items-center">
                  <Skeleton className="h-4 w-20 mb-1" />
                  <Skeleton className="h-4 w-10 mb-1" />
                </div>
                <Skeleton className="h-2 w-full" />
              </div>
            </div>
          ))}
        </div>
      </ChartCard>
    );
  }

  return (
    <ChartCard
      title="dashboard.party.distribution"
      action={<Button variant="link" size="sm">{t('dashboard.details')}</Button>}
    >
      <div className="space-y-4">
        {distribution && distribution.length > 0 ? (
          distribution.map((party: any, index: number) => (
            <div key={party.id} className="flex items-center">
              <img 
                src={party.logoUrl || `https://ui-avatars.com/api/?name=${encodeURIComponent(party.name)}&background=random`} 
                alt={party.name} 
                className="w-10 h-10 rounded-full mr-3" 
              />
              <div className="flex-1">
                <div className="flex justify-between items-center">
                  <p className="text-sm font-medium">{party.name}</p>
                  <p className="text-sm font-medium">{party.percentage}%</p>
                </div>
                <div className="w-full bg-gray-200 rounded-full h-2 mt-1">
                  <div 
                    className={`${partyColors[index % partyColors.length]} h-2 rounded-full`}
                    style={{ width: `${party.percentage}%` }}
                  ></div>
                </div>
              </div>
            </div>
          ))
        ) : (
          <p className="text-center text-gray-500 py-4">{t('common.loading')}</p>
        )}
      </div>
    </ChartCard>
  );
}
