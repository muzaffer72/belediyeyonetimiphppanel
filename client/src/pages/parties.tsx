import { useState } from "react";
import { useTranslation } from "@/lib/i18n";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { apiRequest } from "@/lib/queryClient";
import { useToast } from "@/hooks/use-toast";
import { Button } from "@/components/ui/button";
import { DataTable } from "@/components/ui/data-table";
import { Modal } from "@/components/ui/modal";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import { PartyForm } from "@/components/forms/PartyForm";
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

  // Fetch parties data
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
    ],
    // The actual queryFn is defined in queryClient.ts
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

  // Table columns
  const columns = [
    {
      accessorKey: "name",
      header: t("common.name"),
      cell: ({ row }: any) => (
        <div className="flex items-center">
          <div className="flex-shrink-0 h-10 w-10">
            <img 
              className="h-10 w-10 rounded-full" 
              src={row.original.logoUrl || `https://ui-avatars.com/api/?name=${encodeURIComponent(row.original.name)}&background=random`} 
              alt={row.original.name + " logo"} 
            />
          </div>
          <div className="ml-4">
            <div className="text-sm font-medium text-gray-900">{row.original.name}</div>
          </div>
        </div>
      ),
    },
    {
      accessorKey: "score",
      header: t("common.score"),
      cell: ({ row }: any) => {
        const score = parseFloat(row.original.score);
        
        let colorClass = "text-gray-700";
        if (score >= 8) colorClass = "text-green-600";
        else if (score >= 6) colorClass = "text-blue-600";
        else if (score >= 4) colorClass = "text-yellow-600";
        else colorClass = "text-red-600";
        
        return (
          <div className="flex items-center">
            <span className={`material-icons mr-1 ${colorClass}`}>star</span>
            <span className={`text-sm font-medium ${colorClass}`}>
              {score ? score.toFixed(1) : '-'}
            </span>
          </div>
        );
      },
    },
    {
      accessorKey: "municipalityCount",
      header: t("cities.title"),
      cell: ({ row }: any) => (
        <span className="text-sm text-gray-700">
          {row.original.municipalityCount || 0}
        </span>
      ),
    },
    {
      accessorKey: "lastUpdated",
      header: t("common.updated.at"),
      cell: ({ row }: any) => (
        <span className="text-sm text-gray-700">
          {new Date(row.original.lastUpdated).toLocaleDateString()}
        </span>
      ),
    },
    {
      id: "actions",
      cell: ({ row }: any) => (
        <div className="flex justify-end space-x-1">
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
        searchPlaceholder={t("common.search")}
      />

      {/* Add/Edit Modal */}
      {(isAddModalOpen || editingPartyId) && (
        <Modal
          title={editingPartyId ? t("common.edit") : t("parties.addnew")}
          isOpen={true}
          onClose={() => {
            setIsAddModalOpen(false);
            setEditingPartyId(null);
          }}
        >
          <PartyForm
            partyId={editingPartyId || undefined}
            onClose={() => {
              setIsAddModalOpen(false);
              setEditingPartyId(null);
            }}
          />
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
