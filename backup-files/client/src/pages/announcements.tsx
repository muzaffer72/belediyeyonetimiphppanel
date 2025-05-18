import { useState } from "react";
import { useTranslation } from "@/lib/i18n";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { apiRequest } from "@/lib/queryClient";
import { useToast } from "@/hooks/use-toast";
import { Button } from "@/components/ui/button";
import { DataTable } from "@/components/ui/data-table";
import { StatusBadge } from "@/components/ui/status-badge";
import { Modal } from "@/components/ui/modal";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import { Spinner } from "@/components/ui/spinner";
import { PaginationInfo } from "@shared/types";
import { formatDistanceToNow } from "date-fns";
import { tr, enUS } from "date-fns/locale";

export default function Announcements() {
  const { t, locale } = useTranslation();
  const { toast } = useToast();
  const queryClient = useQueryClient();
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState(10);
  const [searchTerm, setSearchTerm] = useState("");
  const [filters, setFilters] = useState<any>({});
  const [editingAnnouncementId, setEditingAnnouncementId] = useState<string | null>(null);
  const [isAddModalOpen, setIsAddModalOpen] = useState(false);
  const [deletingAnnouncementId, setDeletingAnnouncementId] = useState<string | null>(null);
  const [viewingAnnouncementId, setViewingAnnouncementId] = useState<string | null>(null);

  // Fetch announcements data
  const {
    data: announcementsData,
    isLoading,
    isError,
  } = useQuery({
    queryKey: [
      '/api/municipality-announcements',
      page,
      pageSize,
      searchTerm,
      filters.status,
      filters.city,
    ],
  });

  // Delete mutation
  const deleteMutation = useMutation({
    mutationFn: async (id: string) => {
      return apiRequest("DELETE", `/api/municipality-announcements/${id}`);
    },
    onSuccess: () => {
      toast({
        title: t("notifications.success"),
        description: t("notifications.deleted"),
      });
      queryClient.invalidateQueries({ queryKey: ['/api/municipality-announcements'] });
      setDeletingAnnouncementId(null);
    },
    onError: (error) => {
      toast({
        title: t("notifications.error"),
        description: t("notifications.error.occurred"),
        variant: "destructive",
      });
    },
  });

  // Handle pagination change
  const handlePaginationChange = (newPage: number, newPageSize: number) => {
    setPage(newPage);
    setPageSize(newPageSize);
  };

  // Handle search
  const handleSearch = (value: string) => {
    setSearchTerm(value);
    setPage(1); // Reset to first page on new search
  };

  // Handle filter
  const handleFilter = (column: string, value: any) => {
    setFilters((prev: any) => ({ ...prev, [column]: value }));
    setPage(1); // Reset to first page on new filter
  };

  // Format date
  const formatDate = (dateString: string) => {
    try {
      return formatDistanceToNow(new Date(dateString), {
        addSuffix: true,
        locale: locale === 'tr' ? tr : enUS,
      });
    } catch (error) {
      return dateString;
    }
  };

  // Format long date
  const formatLongDate = (dateString: string) => {
    try {
      return new Date(dateString).toLocaleString(locale === 'tr' ? 'tr-TR' : 'en-US', {
        year: 'numeric',
        month: 'long',
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
      });
    } catch (error) {
      return dateString;
    }
  };

  // Truncate text
  const truncateText = (text: string, maxLength: number = 100) => {
    if (!text) return '';
    return text.length > maxLength ? text.slice(0, maxLength) + '...' : text;
  };

  // Table columns
  const columns = [
    {
      accessorKey: "title",
      header: t("announcements.table.title"),
      cell: ({ row }: any) => (
        <div className="max-w-md">
          <div className="text-sm font-medium text-gray-900">{row.original.title}</div>
          <div className="text-xs text-gray-500 truncate">{truncateText(row.original.content, 100)}</div>
        </div>
      ),
    },
    {
      accessorKey: "city",
      header: t("announcements.table.city"),
      cell: ({ row }: any) => (
        <div className="flex items-center">
          <div className="flex-shrink-0 h-8 w-8">
            <img 
              className="h-8 w-8 rounded-full" 
              src={row.original.cityLogo || `https://ui-avatars.com/api/?name=${encodeURIComponent(row.original.cityName || 'City')}&background=random`} 
              alt={row.original.cityName} 
            />
          </div>
          <div className="ml-3">
            <div className="text-sm font-medium text-gray-900">{row.original.cityName}</div>
          </div>
        </div>
      ),
    },
    {
      accessorKey: "startDate",
      header: t("announcements.table.start.date"),
      cell: ({ row }: any) => (
        <span className="text-sm text-gray-500">{formatDate(row.original.startDate)}</span>
      ),
    },
    {
      accessorKey: "endDate",
      header: t("announcements.table.end.date"),
      cell: ({ row }: any) => (
        <span className="text-sm text-gray-500">{formatDate(row.original.endDate)}</span>
      ),
    },
    {
      accessorKey: "status",
      header: t("announcements.table.status"),
      cell: ({ row }: any) => {
        // Determine status based on dates
        const now = new Date();
        const startDate = new Date(row.original.startDate);
        const endDate = new Date(row.original.endDate);
        
        let status = "inactive";
        if (now >= startDate && now <= endDate) {
          status = "active";
        } else if (now < startDate) {
          status = "pending";
        } else if (now > endDate) {
          status = "expired";
        }
        
        return <StatusBadge status={status} />;
      },
    },
    {
      id: "actions",
      cell: ({ row }: any) => (
        <div className="flex justify-end space-x-1">
          <Button
            variant="ghost"
            size="icon"
            onClick={() => setViewingAnnouncementId(row.original.id)}
            className="text-blue-600 hover:text-blue-900"
          >
            <span className="material-icons text-sm">visibility</span>
          </Button>
          <Button
            variant="ghost"
            size="icon"
            onClick={() => setEditingAnnouncementId(row.original.id)}
            className="text-primary-600 hover:text-primary-900"
          >
            <span className="material-icons text-sm">edit</span>
          </Button>
          <Button
            variant="ghost"
            size="icon"
            onClick={() => setDeletingAnnouncementId(row.original.id)}
            className="text-red-600 hover:text-red-900"
          >
            <span className="material-icons text-sm">delete</span>
          </Button>
        </div>
      ),
    },
  ];

  // Filter options
  const filterOptions = [
    {
      column: "status",
      label: "announcements.filter.status",
      options: [
        { value: "", label: "announcements.filter.all.statuses" },
        { value: "active", label: "announcements.status.active" },
        { value: "pending", label: "announcements.status.pending" },
        { value: "expired", label: "announcements.status.expired" },
      ],
    },
    {
      column: "city",
      label: "announcements.filter.city",
      options: [
        { value: "", label: "announcements.filter.all.cities" },
        ...(announcementsData?.cities || []).map((city: any) => ({
          value: city.id,
          label: city.name,
        })),
      ],
    },
  ];

  if (isLoading) {
    return (
      <div className="flex items-center justify-center h-full">
        <Spinner size="xl" />
      </div>
    );
  }

  if (isError) {
    return (
      <div className="bg-red-50 p-4 rounded-md">
        <p className="text-red-700">{t("notifications.error.occurred")}</p>
      </div>
    );
  }

  return (
    <section>
      <div className="mb-6 flex flex-col sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h2 className="text-2xl font-heading font-bold text-gray-800">{t("announcements.title")}</h2>
          <p className="text-gray-500">{t("announcements.subtitle")}</p>
        </div>
        <div className="mt-4 sm:mt-0">
          <Button onClick={() => setIsAddModalOpen(true)}>
            <span className="material-icons text-sm mr-2">add</span>
            {t("announcements.addnew")}
          </Button>
        </div>
      </div>

      <DataTable
        columns={columns}
        data={announcementsData?.data || []}
        pagination={announcementsData?.pagination as PaginationInfo}
        onPaginationChange={handlePaginationChange}
        onSearch={handleSearch}
        onFilter={handleFilter}
        searchPlaceholder={t("announcements.search")}
        filterOptions={filterOptions}
      />

      {/* View Announcement Modal */}
      {viewingAnnouncementId && (
        <Modal
          title={t("announcements.view")}
          isOpen={true}
          onClose={() => setViewingAnnouncementId(null)}
        >
          <div className="p-4">
            {announcementsData?.data.find((announcement: any) => announcement.id === viewingAnnouncementId) && (
              <div>
                <div className="flex items-center mb-4">
                  <div className="flex-shrink-0 h-10 w-10">
                    <img 
                      className="h-10 w-10 rounded-full" 
                      src={announcementsData?.data.find((announcement: any) => announcement.id === viewingAnnouncementId)?.cityLogo || 
                        `https://ui-avatars.com/api/?name=${encodeURIComponent(
                          announcementsData?.data.find((announcement: any) => announcement.id === viewingAnnouncementId)?.cityName || 'City'
                        )}&background=random`
                      } 
                      alt="City logo" 
                    />
                  </div>
                  <div className="ml-3">
                    <p className="text-sm font-medium text-gray-900">
                      {announcementsData?.data.find((announcement: any) => announcement.id === viewingAnnouncementId)?.cityName}
                    </p>
                  </div>
                </div>
                <div className="mb-4">
                  <h3 className="text-lg font-medium text-gray-900 mb-2">
                    {announcementsData?.data.find((announcement: any) => announcement.id === viewingAnnouncementId)?.title}
                  </h3>
                  <p className="text-gray-800 whitespace-pre-line">
                    {announcementsData?.data.find((announcement: any) => announcement.id === viewingAnnouncementId)?.content}
                  </p>
                </div>
                <div className="grid grid-cols-2 gap-4 mt-4">
                  <div className="bg-gray-50 p-3 rounded-md">
                    <p className="text-xs text-gray-500 mb-1">{t("announcements.start.date")}</p>
                    <p className="text-sm font-medium">
                      {formatLongDate(announcementsData?.data.find((announcement: any) => announcement.id === viewingAnnouncementId)?.startDate)}
                    </p>
                  </div>
                  <div className="bg-gray-50 p-3 rounded-md">
                    <p className="text-xs text-gray-500 mb-1">{t("announcements.end.date")}</p>
                    <p className="text-sm font-medium">
                      {formatLongDate(announcementsData?.data.find((announcement: any) => announcement.id === viewingAnnouncementId)?.endDate)}
                    </p>
                  </div>
                </div>
              </div>
            )}
          </div>
        </Modal>
      )}

      {/* Delete Confirmation Dialog */}
      <ConfirmDialog
        title={t("common.delete")}
        description={t("notifications.confirmed")}
        isOpen={!!deletingAnnouncementId}
        onClose={() => setDeletingAnnouncementId(null)}
        onConfirm={() => deletingAnnouncementId && deleteMutation.mutate(deletingAnnouncementId)}
        variant="destructive"
      />
    </section>
  );
}