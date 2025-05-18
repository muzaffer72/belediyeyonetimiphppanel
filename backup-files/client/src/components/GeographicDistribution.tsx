import { useState } from "react";
import { useTranslation } from "@/lib/i18n";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { ChartCard } from "@/components/ui/chart-card";

export function GeographicDistribution() {
  const { t } = useTranslation();
  const [timeRange, setTimeRange] = useState<string>("30");
  
  return (
    <ChartCard 
      title="dashboard.geographic.distribution"
      action={
        <Select defaultValue={timeRange} onValueChange={setTimeRange}>
          <SelectTrigger className="w-[130px]">
            <SelectValue placeholder={t('dashboard.last.30days')} />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="30">{t('dashboard.last.30days')}</SelectItem>
            <SelectItem value="90">{t('dashboard.last.90days')}</SelectItem>
            <SelectItem value="all">{t('dashboard.all.time')}</SelectItem>
          </SelectContent>
        </Select>
      }
    >
      <div className="relative h-64 rounded-lg overflow-hidden bg-gray-100 flex items-center justify-center">
        <img src="https://pixabay.com/get/gb6db5c02abb62fbdfffed54c03908a02eba1bd6d53501e8aac40f861985b43a4d9f4a5bd95e4f0d7c0c611190944370a3d109b9e5f3513729cb217b46a291d4b_1280.jpg" 
          alt="Turkey city map distribution" 
          className="w-full h-full object-cover" 
        />
        <div className="absolute inset-0 bg-primary-900 bg-opacity-30 flex items-center justify-center">
          <p className="text-white text-xl font-medium">{t('dashboard.interactive.map')}</p>
        </div>
      </div>
      <div className="mt-4 grid grid-cols-2 gap-4">
        <div>
          <p className="text-sm font-medium text-gray-500">{t('dashboard.most.active.city')}</p>
          <p className="text-md font-semibold">İstanbul</p>
        </div>
        <div>
          <p className="text-sm font-medium text-gray-500">{t('dashboard.least.active.city')}</p>
          <p className="text-md font-semibold">Bayburt</p>
        </div>
      </div>
    </ChartCard>
  );
}
