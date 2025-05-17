import { useQuery } from "@tanstack/react-query";
import { useTranslation } from "@/lib/i18n";
import { formatDistanceToNow } from "date-fns";
import { tr, enUS } from "date-fns/locale";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";

interface ActivityProps {
  limit?: number;
}

export function RecentActivities({ limit = 5 }: ActivityProps) {
  const { t, locale } = useTranslation();
  
  const { data: activities, isLoading } = useQuery({
    queryKey: [`/api/dashboard/activities?limit=${limit}`],
  });

  const getDateLocale = () => {
    return locale === 'tr' ? tr : enUS;
  };

  const formatDate = (date: string) => {
    try {
      return formatDistanceToNow(new Date(date), {
        addSuffix: true,
        locale: getDateLocale(),
      });
    } catch (error) {
      return date;
    }
  };

  if (isLoading) {
    return (
      <div className="bg-white rounded-lg shadow-sm p-6 border border-gray-100">
        <div className="flex justify-between items-center mb-4">
          <h3 className="text-lg font-heading font-semibold text-gray-800">{t('dashboard.recent.activities')}</h3>
          <Button variant="link" size="sm">{t('dashboard.view.all')}</Button>
        </div>
        <div className="space-y-4">
          {[...Array(5)].map((_, i) => (
            <div key={i} className="flex items-start animate-pulse">
              <Skeleton className="h-8 w-8 rounded-full mr-3" />
              <div className="flex-1">
                <Skeleton className="h-4 w-3/4 mb-2" />
                <Skeleton className="h-3 w-1/3" />
              </div>
            </div>
          ))}
        </div>
      </div>
    );
  }

  return (
    <div className="bg-white rounded-lg shadow-sm p-6 border border-gray-100">
      <div className="flex justify-between items-center mb-4">
        <h3 className="text-lg font-heading font-semibold text-gray-800">{t('dashboard.recent.activities')}</h3>
        <Button variant="link" size="sm">{t('dashboard.view.all')}</Button>
      </div>
      <div className="space-y-4">
        {activities && activities.length > 0 ? (
          activities.map((activity: any) => (
            <div key={activity.id} className="flex items-start">
              <div className="flex-shrink-0 mr-3">
                <img
                  className="h-8 w-8 rounded-full"
                  src={activity.userAvatar || `https://ui-avatars.com/api/?name=${encodeURIComponent(activity.username)}&background=random`}
                  alt={activity.username}
                />
              </div>
              <div>
                <p className="text-sm text-gray-800">
                  <span className="font-medium">{activity.username}</span>{" "}
                  <span className="text-gray-500">{activity.action}</span>{" "}
                  {activity.target && <span className="font-medium">{activity.target}</span>}
                </p>
                <p className="text-xs text-gray-500 mt-1">{formatDate(activity.timestamp)}</p>
              </div>
            </div>
          ))
        ) : (
          <p className="text-center text-gray-500 py-4">{t('common.loading')}</p>
        )}
      </div>
    </div>
  );
}
