import { Badge } from "@/components/ui/badge";
import { useTranslation } from "@/lib/i18n";

interface StatusBadgeProps {
  status: 'active' | 'inactive' | 'maintenance' | 'pending' | 'resolved' | 'featured';
  statusKey?: string;
}

export function StatusBadge({ status, statusKey }: StatusBadgeProps) {
  const { t } = useTranslation();
  
  const getStatusStyle = (status: string) => {
    switch (status) {
      case 'active':
        return 'bg-green-100 text-green-800';
      case 'inactive':
        return 'bg-red-100 text-red-800';
      case 'maintenance':
        return 'bg-yellow-100 text-yellow-800';
      case 'pending':
        return 'bg-amber-100 text-amber-800';
      case 'resolved':
        return 'bg-blue-100 text-blue-800';
      case 'featured':
        return 'bg-purple-100 text-purple-800';
      default:
        return 'bg-gray-100 text-gray-800';
    }
  };
  
  const getStatusText = (status: string, statusKey?: string) => {
    if (statusKey) {
      return t(statusKey);
    }
    
    switch (status) {
      case 'active':
        return t('cities.status.active');
      case 'inactive':
        return t('cities.status.inactive');
      case 'maintenance':
        return t('cities.status.maintenance');
      case 'pending':
        return t('common.pending');
      case 'resolved':
        return t('common.resolved');
      case 'featured':
        return t('posts.featured');
      default:
        return status;
    }
  };
  
  return (
    <span className={`px-2 inline-flex text-xs leading-5 font-semibold rounded-full ${getStatusStyle(status)}`}>
      {getStatusText(status, statusKey)}
    </span>
  );
}
