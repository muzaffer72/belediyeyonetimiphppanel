import { useTranslation } from "@/lib/i18n";
import { Button } from "@/components/ui/button";
import { ChartCard } from "@/components/ui/chart-card";
import { Skeleton } from "@/components/ui/skeleton";
import { useQuery } from "@tanstack/react-query";
import { formatMessage } from "@/lib/i18n";

export function PostCategories() {
  const { t } = useTranslation();
  
  const { data: categories, isLoading } = useQuery({
    queryKey: ['/api/dashboard/post-categories'],
  });

  const getCategoryData = () => {
    if (!categories || categories.length === 0) return [];
    
    // Map category types to icons and colors
    const categoryMapping: Record<string, { icon: string; color: string }> = {
      'complaint': { icon: 'report_problem', color: 'blue' },
      'suggestion': { icon: 'lightbulb', color: 'green' },
      'question': { icon: 'help_outline', color: 'amber' },
      'thanks': { icon: 'favorite', color: 'red' },
      // Default for any other category
      'default': { icon: 'article', color: 'gray' }
    };
    
    return categories.map((cat: any) => {
      const categoryType = cat.category.toLowerCase();
      const mapping = categoryMapping[categoryType] || categoryMapping.default;
      
      return {
        ...cat,
        icon: mapping.icon,
        color: mapping.color,
        translationKey: `dashboard.${categoryType}s` // Pluralize for translation key
      };
    });
  };

  if (isLoading) {
    return (
      <ChartCard
        title="dashboard.post.categories"
        action={<Button variant="link" size="sm">{t('dashboard.details')}</Button>}
      >
        <div className="grid grid-cols-2 gap-4 animate-pulse">
          {[...Array(4)].map((_, i) => (
            <div key={i} className="p-4 rounded-lg bg-gray-50 border border-gray-100">
              <div className="flex justify-between items-center">
                <Skeleton className="h-6 w-6" />
                <Skeleton className="h-6 w-12" />
              </div>
              <Skeleton className="h-4 w-24 mt-2" />
              <Skeleton className="h-3 w-32 mt-1" />
            </div>
          ))}
        </div>
      </ChartCard>
    );
  }

  const categoryData = getCategoryData();

  const getCategoryBgColor = (color: string) => `bg-${color}-50 border border-${color}-100`;
  const getCategoryIconColor = (color: string) => `text-${color}-500`;

  return (
    <ChartCard
      title="dashboard.post.categories"
      action={<Button variant="link" size="sm">{t('dashboard.details')}</Button>}
    >
      <div className="grid grid-cols-2 gap-4">
        {categoryData.length > 0 ? (
          categoryData.map((category: any) => (
            <div key={category.category} className={`p-4 rounded-lg ${getCategoryBgColor(category.color)}`}>
              <div className="flex justify-between items-center">
                <span className={`material-icons ${getCategoryIconColor(category.color)}`}>{category.icon}</span>
                <span className={`${getCategoryIconColor(category.color)} font-medium text-lg`}>
                  {category.count.toLocaleString()}
                </span>
              </div>
              <p className="mt-2 text-sm font-medium text-gray-800">
                {t(category.translationKey || `dashboard.${category.category}`)}
              </p>
              <p className="text-xs text-gray-500">
                {formatMessage(t('dashboard.percentage.total'), { value: category.percentage })}
              </p>
            </div>
          ))
        ) : (
          <div className="col-span-2 text-center text-gray-500 py-4">{t('common.loading')}</div>
        )}
      </div>
    </ChartCard>
  );
}
