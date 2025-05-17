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
import { AnnouncementForm } from "@/components/forms/AnnouncementForm";
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
      filters.municipalityId,
      filters.isActive,
    ],
    // The actual queryFn is defined in queryClient.ts
  });

  // Fetch cities for filter dropdown
  const { data: cities } = useQuery({
    queryKey: ['/api/cities'],
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

  // Toggle active status
  const toggleActive = (id: string, isActive: boolean) => {
    const updateMutation = useMutation({
      mutationFn: async ({ id, data }: { id: string; data: any }) => {
        return apiRequest("PUT", `/api/municipality-announcements/${id}`, data);
      },
      onSuccess: () => {
        queryClient.invalidateQueries({ queryKey: ['/api/municipality-announcements'] });
        toast({
          title: t("notifications.success"),
          description: isActive ? t("notifications.deactivated") : t("notifications.activated"),
        });
      },
      onError: (error) => {
        toast({
          title: t("notifications.error"),
          description: t("notifications.error.occurred"),
          variant: "destructive",
        });
      },
    });

    updateMutation.mutate({ id, data: { isActive: !isActive } });
  };

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

  // Format date with locale
  const formatDate = (date: string) => {
    try {
      return formatDistanceToNow(new Date(date), {
        addSuffix: true,
        locale: locale === 'tr' ? tr : enUS,
      });
    } catch (error) {
      return date;
    }
  };

  // Table columns
  const columns = [
    {
      accessorKey: "title",
      header: t("common.title"),
      cell: ({ row }: any) => (
        <div className="max-w-md">
          <div className="text-sm font-medium text-gray-900">{row.original.title}</div>
          <div className="text-xs text-gray-500 truncate">{row.original.content}</div>
        </div>
      ),
    },
    {
      accessorKey: "municipalityId",
      header: t("dashboard.total.municipalities"),
      cell: ({ row }: any) => {
        const cityName = cities?.data?.find((city: any) => city.id === row.original.municipalityId)?.name || "-";
        return <span className="text-sm text-gray-700">{cityName}</span>;
      },
    },
    {
      accessorKey: "imageUrl",
      header: t("common.image"),
      cell: ({ row }: any) => (
        row.original.imageUrl ? (
          <div className="w-10 h-10 overflow-hidden rounded-md">
            <img 
              src={row.original.imageUrl} 
              alt={row.original.title}
              className="w-full h-full object-cover" 
            />
          </div>
        ) : <span className="text-gray-400">-</span>
      ),
    },
    {
      accessorKey: "createdAt",
      header: t("common.created.at"),
      cell: ({ row }: any) => (
        <span className="text-sm text-gray-700">
          {formatDate(row.original.createdAt)}
        </span>
      ),
    },
    {
      accessorKey: "status",
      header: t("common.status"),
      cell: ({ row }: any) => (
        <StatusBadge status={row.original.isActive ? "active" : "inactive"} />
      ),
    },
    {
      id: "actions",
      cell: ({ row }: any) => (
        <div className="flex justify-end space-x-1">
          <Button
            variant="ghost"
            size="icon"
            onClick={() => toggleActive(row.original.id, row.original.isActive)}
            className={row.original.isActive ? "text-green-600" : "text-gray-400"}
            title={row.original.isActive ? t("common.deactivate") : t("common.activate")}
          >
            <span className="material-icons text-sm">
              {row.original.isActive ? "toggle_on" : "toggle_off"}
            </span>
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
      column: "municipalityId",
      label: "dashboard.total.municipalities",
      options: [
        { value: "", label: "common.all" },
        ...(cities?.data || []).map((city: any) => ({
          value: city.id,
          label: city.name,
        })),
      ],
    },
    {
      column: "isActive",
      label: "common.status",
      options: [
        { value: "", label: "common.all" },
        { value: "true", label: "common.active" },
        { value: "false", label: "common.inactive" },
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
        searchPlaceholder={t("common.search")}
        filterOptions={filterOptions}
      />

      {/* Add/Edit Modal */}
      {(isAddModalOpen || editingAnnouncementId) && (
        <Modal
          title={editingAnnouncementId ? t("common.edit") : t("announcements.addnew")}
          isOpen={true}
          onClose={() => {
            setIsAddModalOpen(false);
            setEditingAnnouncementId(null);
          }}
        >
          <AnnouncementForm
            announcementId={editingAnnouncementId || undefined}
            onClose={() => {
              setIsAddModalOpen(false);
              setEditingAnnouncementId(null);
            }}
          />
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
