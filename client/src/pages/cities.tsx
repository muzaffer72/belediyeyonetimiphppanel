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
import { CityForm } from "@/components/forms/CityForm";
import { Spinner } from "@/components/ui/spinner";
import { PaginationInfo } from "@shared/types";

export default function Cities() {
  const { t } = useTranslation();
  const { toast } = useToast();
  const queryClient = useQueryClient();
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState(10);
  const [searchTerm, setSearchTerm] = useState("");
  const [filters, setFilters] = useState<any>({});
  const [editingCityId, setEditingCityId] = useState<string | null>(null);
  const [isAddModalOpen, setIsAddModalOpen] = useState(false);
  const [deletingCityId, setDeletingCityId] = useState<string | null>(null);

  // Fetch cities data
  const {
    data: citiesData,
    isLoading,
    isError,
  } = useQuery({
    queryKey: [
      '/api/cities',
      page,
      pageSize,
      searchTerm,
      filters.politicalPartyId,
      filters.population,
    ],
    // The actual queryFn is defined in queryClient.ts
  });

  // Delete mutation
  const deleteMutation = useMutation({
    mutationFn: async (id: string) => {
      return apiRequest("DELETE", `/api/cities/${id}`);
    },
    onSuccess: () => {
      toast({
        title: t("notifications.success"),
        description: t("notifications.deleted"),
      });
      queryClient.invalidateQueries({ queryKey: ['/api/cities'] });
      setDeletingCityId(null);
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
      header: t("cities.table.city"),
      cell: ({ row }: any) => (
        <div className="flex items-center">
          <div className="flex-shrink-0 h-10 w-10">
            <img 
              className="h-10 w-10 rounded-full" 
              src={row.original.logoUrl || "https://ui-avatars.com/api/?name=" + encodeURIComponent(row.original.name) + "&background=random"} 
              alt={row.original.name + " logo"} 
            />
          </div>
          <div className="ml-4">
            <div className="text-sm font-medium text-gray-900">{row.original.name}</div>
            <div className="text-sm text-gray-500">{row.original.email}</div>
          </div>
        </div>
      ),
    },
    {
      accessorKey: "mayorName",
      header: t("cities.table.mayor"),
    },
    {
      accessorKey: "politicalPartyId",
      header: t("cities.table.party"),
      cell: ({ row }: any) => {
        const party = row.original.politicalParty;
        return (
          <div className="flex items-center">
            {party && (
              <>
                <div className="flex-shrink-0 h-6 w-6">
                  <img 
                    className="h-6 w-6 rounded-full" 
                    src={row.original.partyLogoUrl || "https://ui-avatars.com/api/?name=" + encodeURIComponent(row.original.mayorParty || "") + "&background=random"} 
                    alt="Party logo" 
                  />
                </div>
                <div className="ml-2 text-sm text-gray-900">{row.original.mayorParty}</div>
              </>
            )}
          </div>
        );
      },
    },
    {
      accessorKey: "population",
      header: t("cities.table.population"),
      cell: ({ row }: any) => (
        <span className="text-sm text-gray-500">
          {row.original.population?.toLocaleString()}
        </span>
      ),
    },
    {
      accessorKey: "status",
      header: t("cities.table.status"),
      cell: ({ row }: any) => (
        <StatusBadge status="active" />
      ),
    },
    {
      id: "actions",
      cell: ({ row }: any) => (
        <div className="flex justify-end">
          <Button
            variant="ghost"
            size="icon"
            onClick={() => setEditingCityId(row.original.id)}
            className="text-primary-600 hover:text-primary-900 mr-2"
          >
            <span className="material-icons">edit</span>
          </Button>
          <Button
            variant="ghost"
            size="icon"
            onClick={() => setDeletingCityId(row.original.id)}
            className="text-red-600 hover:text-red-900"
          >
            <span className="material-icons">delete</span>
          </Button>
        </div>
      ),
    },
  ];

  // Filter options
  const filterOptions = [
    {
      column: "politicalPartyId",
      label: "cities.filter.party",
      options: [
        { value: "", label: "cities.filter.all.parties" },
        ...(citiesData?.parties || []).map((party: any) => ({
          value: party.id,
          label: party.name,
        })),
      ],
    },
    {
      column: "population",
      label: "cities.filter.population",
      options: [
        { value: "", label: "cities.filter.all.populations" },
        { value: "1", label: "0 - 500,000" },
        { value: "2", label: "500,000 - 1,000,000" },
        { value: "3", label: "1,000,000+" },
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
          <h2 className="text-2xl font-heading font-bold text-gray-800">{t("cities.title")}</h2>
          <p className="text-gray-500">{t("cities.subtitle")}</p>
        </div>
        <div className="mt-4 sm:mt-0">
          <Button onClick={() => setIsAddModalOpen(true)}>
            <span className="material-icons text-sm mr-2">add</span>
            {t("cities.addnew")}
          </Button>
        </div>
      </div>

      <DataTable
        columns={columns}
        data={citiesData?.data || []}
        pagination={citiesData?.pagination as PaginationInfo}
        onPaginationChange={handlePaginationChange}
        onSearch={handleSearch}
        onFilter={handleFilter}
        searchPlaceholder={t("cities.search")}
        filterOptions={filterOptions}
      />

      {/* Add/Edit Modal */}
      {(isAddModalOpen || editingCityId) && (
        <Modal
          title={editingCityId ? t("form.edit.city") : t("cities.addnew")}
          description={editingCityId ? t("form.edit.city.subtitle") : ""}
          isOpen={true}
          onClose={() => {
            setIsAddModalOpen(false);
            setEditingCityId(null);
          }}
        >
          <CityForm
            cityId={editingCityId || undefined}
            onClose={() => {
              setIsAddModalOpen(false);
              setEditingCityId(null);
            }}
          />
        </Modal>
      )}

      {/* Delete Confirmation Dialog */}
      <ConfirmDialog
        title={t("common.delete")}
        description={t("notifications.confirmed")}
        isOpen={!!deletingCityId}
        onClose={() => setDeletingCityId(null)}
        onConfirm={() => deletingCityId && deleteMutation.mutate(deletingCityId)}
        variant="destructive"
      />
    </section>
  );
}
