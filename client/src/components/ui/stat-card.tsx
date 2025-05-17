import { Card, CardContent } from "@/components/ui/card";
import { useTranslation } from "@/lib/i18n";

interface StatCardProps {
  title: string;
  value: number | string;
  icon: React.ReactNode;
  iconBgColor: string;
  iconColor: string;
  trend?: {
    value: number;
    isPositive: boolean;
  };
  trendLabel?: string;
}

export function StatCard({
  title,
  value,
  icon,
  iconBgColor,
  iconColor,
  trend,
  trendLabel = "dashboard.since.lastmonth"
}: StatCardProps) {
  const { t } = useTranslation();
  
  return (
    <div className="bg-white rounded-lg shadow-sm p-6 border border-gray-100">
      <div className="flex justify-between">
        <div>
          <p className="text-sm font-medium text-gray-500">{t(title)}</p>
          <p className="text-2xl font-semibold text-gray-900">
            {typeof value === 'number' ? value.toLocaleString() : value}
          </p>
        </div>
        <div className={`rounded-full ${iconBgColor} p-3 ${iconColor}`}>
          {icon}
        </div>
      </div>
      {trend && (
        <div className="mt-4 flex items-center text-sm">
          <span className={`${trend.isPositive ? 'text-green-500' : 'text-red-500'} flex items-center`}>
            <span className="material-icons text-sm">
              {trend.isPositive ? 'arrow_upward' : 'arrow_downward'}
            </span>
            {trend.value}%
          </span>
          <span className="text-gray-500 ml-2">{t(trendLabel)}</span>
        </div>
      )}
    </div>
  );
}
