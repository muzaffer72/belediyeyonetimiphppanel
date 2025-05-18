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

export default function Parties() {
  const { t } = useTranslation();
  const { toast } = useToast();
  const queryClient = useQueryClient();
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState(10);
  const [searchTerm, setSearchTerm] = useState("");
  const [filters, setFilters] = useState<any>({});
  const [editingPartyId, setEditingPartyId] = useState<string | null>(null);
  const [isAddModalOpen, setIsAddModalOpen] = useState(false);
  const [deletingPartyId, setDeletingPartyId] = useState<string | null>(null);
  const [viewingPartyId, setViewingPartyId] = useState<string | null>(null);

  // Fetch political parties data
  const {
    data: partiesData,
    isLoading,
    isError,
  } = useQuery({
    queryKey: [
      '/api/political-parties',
      page,
      pageSize,
      searchTerm,
      filters.status,
    ],
  });

  // Delete mutation
  const deleteMutation = useMutation({
    mutationFn: async (id: string) => {
      return apiRequest("DELETE", `/api/political-parties/${id}`);
    },
    onSuccess: () => {
      toast({
        title: t("notifications.success"),
        description: t("notifications.deleted"),
      });
      queryClient.invalidateQueries({ queryKey: ['/api/political-parties'] });
      setDeletingPartyId(null);
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
    const date = new Date(dateString);
    return new Intl.DateTimeFormat('tr-TR', {
      year: 'numeric',
      month: 'short',
      day: 'numeric'
    }).format(date);
  };

  // Get color from party name (for consistent colors)
  const getPartyColor = (name: string) => {
    const colors = [
      "bg-red-100 text-red-800",
      "bg-blue-100 text-blue-800",
      "bg-green-100 text-green-800",
      "bg-yellow-100 text-yellow-800",
      "bg-purple-100 text-purple-800",
      "bg-indigo-100 text-indigo-800",
      "bg-pink-100 text-pink-800",
    ];
    
    let hash = 0;
    for (let i = 0; i < name.length; i++) {
      hash = name.charCodeAt(i) + ((hash << 5) - hash);
    }
    
    const index = Math.abs(hash) % colors.length;
    return colors[index];
  };

  // Table columns
  const columns = [
    {
      accessorKey: "name",
      header: t("parties.table.name"),
      cell: ({ row }: any) => (
        <div className="flex items-center">
          <div className="flex-shrink-0 h-10 w-10">
            <img 
              className="h-10 w-10 rounded-full" 
              src={row.original.logo_url || `https://ui-avatars.com/api/?name=${encodeURIComponent(row.original.name)}&background=random`} 
              alt={row.original.name} 
            />
          </div>
          <div className="ml-4">
            <div className="text-sm font-medium text-gray-900">{row.original.name}</div>
            <div className="text-xs text-gray-500">{row.original.short_name}</div>
          </div>
        </div>
      ),
    },
    {
      accessorKey: "leader_name",
      header: t("parties.table.leader"),
      cell: ({ row }: any) => (
        <span className="text-sm text-gray-900">{row.original.leader_name || "-"}</span>
      ),
    },
    {
      accessorKey: "city_count",
      header: t("parties.table.cities"),
      cell: ({ row }: any) => (
        <div className="text-center">
          <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800">
            {row.original.city_count || 0}
          </span>
        </div>
      ),
    },
    {
      accessorKey: "score",
      header: t("parties.table.score"),
      cell: ({ row }: any) => {
        const score = row.original.score ? parseFloat(row.original.score) : 0;
        const maxScore = 5;
        const fillPercentage = (score / maxScore) * 100;
        
        return (
          <div className="flex items-center">
            <div className="w-24 bg-gray-200 rounded-full h-2.5 mr-2">
              <div 
                className="bg-blue-600 h-2.5 rounded-full" 
                style={{ width: `${fillPercentage}%` }}
              ></div>
            </div>
            <span className="text-sm text-gray-500">{score.toFixed(1)}</span>
          </div>
        );
      },
    },
    {
      accessorKey: "founded_date",
      header: t("parties.table.founded"),
      cell: ({ row }: any) => (
        <span className="text-sm text-gray-500">
          {row.original.founded_date ? formatDate(row.original.founded_date) : "-"}
        </span>
      ),
    },
    {
      accessorKey: "status",
      header: t("parties.table.status"),
      cell: ({ row }: any) => {
        const status = row.original.is_active ? "active" : "inactive";
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
            onClick={() => setViewingPartyId(row.original.id)}
            className="text-blue-600 hover:text-blue-900"
          >
            <span className="material-icons text-sm">visibility</span>
          </Button>
          <Button
            variant="ghost"
            size="icon"
            onClick={() => setEditingPartyId(row.original.id)}
            className="text-primary-600 hover:text-primary-900"
          >
            <span className="material-icons text-sm">edit</span>
          </Button>
          <Button
            variant="ghost"
            size="icon"
            onClick={() => setDeletingPartyId(row.original.id)}
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
      column: "is_active",
      label: "parties.filter.status",
      options: [
        { value: "", label: "parties.filter.all.statuses" },
        { value: "true", label: "parties.status.active" },
        { value: "false", label: "parties.status.inactive" },
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
          <h2 className="text-2xl font-heading font-bold text-gray-800">{t("parties.title")}</h2>
          <p className="text-gray-500">{t("parties.subtitle")}</p>
        </div>
        <div className="mt-4 sm:mt-0">
          <Button onClick={() => setIsAddModalOpen(true)}>
            <span className="material-icons text-sm mr-2">add</span>
            {t("parties.addnew")}
          </Button>
        </div>
      </div>

      <DataTable
        columns={columns}
        data={partiesData?.data || []}
        pagination={partiesData?.pagination as PaginationInfo}
        onPaginationChange={handlePaginationChange}
        onSearch={handleSearch}
        onFilter={handleFilter}
        searchPlaceholder={t("parties.search")}
        filterOptions={filterOptions}
      />

      {/* View Party Modal */}
      {viewingPartyId && (
        <Modal
          title={t("parties.view")}
          isOpen={true}
          onClose={() => setViewingPartyId(null)}
        >
          <div className="p-4">
            {partiesData?.data.find((party: any) => party.id === viewingPartyId) && (
              <div>
                <div className="flex items-center mb-6">
                  <div className="flex-shrink-0 h-16 w-16">
                    <img 
                      className="h-16 w-16 rounded-full" 
                      src={partiesData?.data.find((party: any) => party.id === viewingPartyId)?.logo_url || 
                        `https://ui-avatars.com/api/?name=${encodeURIComponent(
                          partiesData?.data.find((party: any) => party.id === viewingPartyId)?.name || 'Party'
                        )}&background=random&size=64`
                      } 
                      alt="Party logo" 
                    />
                  </div>
                  <div className="ml-4">
                    <h3 className="text-lg font-medium text-gray-900">
                      {partiesData?.data.find((party: any) => party.id === viewingPartyId)?.name}
                    </h3>
                    <p className="text-sm text-gray-500">
                      {partiesData?.data.find((party: any) => party.id === viewingPartyId)?.short_name}
                    </p>
                  </div>
                </div>
                
                <div className="grid grid-cols-2 gap-4 mb-4">
                  <div className="bg-gray-50 p-3 rounded-md">
                    <p className="text-xs text-gray-500 mb-1">{t("parties.leader")}</p>
                    <p className="text-sm font-medium">
                      {partiesData?.data.find((party: any) => party.id === viewingPartyId)?.leader_name || "-"}
                    </p>
                  </div>
                  <div className="bg-gray-50 p-3 rounded-md">
                    <p className="text-xs text-gray-500 mb-1">{t("parties.founded")}</p>
                    <p className="text-sm font-medium">
                      {partiesData?.data.find((party: any) => party.id === viewingPartyId)?.founded_date ? 
                        formatDate(partiesData?.data.find((party: any) => party.id === viewingPartyId)?.founded_date) : "-"}
                    </p>
                  </div>
                </div>
                
                <div className="mb-4">
                  <p className="text-xs text-gray-500 mb-1">{t("parties.description")}</p>
                  <p className="text-sm text-gray-800 whitespace-pre-line">
                    {partiesData?.data.find((party: any) => party.id === viewingPartyId)?.description || 
                     t("parties.no.description")}
                  </p>
                </div>
                
                <div className="flex items-center justify-between p-3 bg-gray-50 rounded-md">
                  <div>
                    <p className="text-xs text-gray-500 mb-1">{t("parties.score")}</p>
                    <div className="flex items-center">
                      {Array.from({ length: 5 }).map((_, i) => (
                        <span 
                          key={i} 
                          className={`material-icons text-lg ${
                            i < (partiesData?.data.find((party: any) => party.id === viewingPartyId)?.score || 0) 
                              ? "text-yellow-500" 
                              : "text-gray-300"
                          }`}
                        >
                          star
                        </span>
                      ))}
                      <span className="ml-2 text-sm font-medium">
                        {partiesData?.data.find((party: any) => party.id === viewingPartyId)?.score || "0"}/5
                      </span>
                    </div>
                  </div>
                  <div>
                    <p className="text-xs text-gray-500 mb-1">{t("parties.cities")}</p>
                    <div className="text-center">
                      <span className="inline-flex items-center px-3 py-1 rounded-full text-sm font-medium bg-blue-100 text-blue-800">
                        {partiesData?.data.find((party: any) => party.id === viewingPartyId)?.city_count || 0}
                      </span>
                    </div>
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
        isOpen={!!deletingPartyId}
        onClose={() => setDeletingPartyId(null)}
        onConfirm={() => deletingPartyId && deleteMutation.mutate(deletingPartyId)}
        variant="destructive"
      />
    </section>
  );
}