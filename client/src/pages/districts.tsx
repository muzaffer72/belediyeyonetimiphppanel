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
import { DistrictForm } from "@/components/forms/DistrictForm";
import { Spinner } from "@/components/ui/spinner";
import { PaginationInfo } from "@shared/types";

export default function Districts() {
  const { t } = useTranslation();
  const { toast } = useToast();
  const queryClient = useQueryClient();
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState(10);
  const [searchTerm, setSearchTerm] = useState("");
  const [filters, setFilters] = useState<any>({});
  const [editingDistrictId, setEditingDistrictId] = useState<string | null>(null);
  const [isAddModalOpen, setIsAddModalOpen] = useState(false);
  const [deletingDistrictId, setDeletingDistrictId] = useState<string | null>(null);

  // Fetch districts data
  const {
    data: districtsData,
    isLoading,
    isError,
  } = useQuery({
    queryKey: [
      '/api/districts',
      page,
      pageSize,
      searchTerm,
      filters.politicalPartyId,
      filters.cityId,
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
      return apiRequest("DELETE", `/api/districts/${id}`);
    },
    onSuccess: () => {
      toast({
        title: t("notifications.success"),
        description: t("notifications.deleted"),
      });
      queryClient.invalidateQueries({ queryKey: ['/api/districts'] });
      setDeletingDistrictId(null);
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
      header: t("common.district"),
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
      accessorKey: "cityId",
      header: t("common.city"),
      cell: ({ row }: any) => {
        const cityName = cities?.data?.find((city: any) => city.id === row.original.cityId)?.name || "-";
        return <span className="text-sm text-gray-700">{cityName}</span>;
      },
    },
    {
      accessorKey: "mayorName",
      header: t("cities.table.mayor"),
    },
    {
      accessorKey: "politicalPartyId",
      header: t("cities.table.party"),
      cell: ({ row }: any) => {
        return (
          <div className="flex items-center">
            <div className="flex-shrink-0 h-6 w-6">
              <img 
                className="h-6 w-6 rounded-full" 
                src={row.original.partyLogoUrl || "https://ui-avatars.com/api/?name=" + encodeURIComponent(row.original.mayorParty || "") + "&background=random"} 
                alt="Party logo" 
              />
            </div>
            <div className="ml-2 text-sm text-gray-900">{row.original.mayorParty}</div>
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
            onClick={() => setEditingDistrictId(row.original.id)}
            className="text-primary-600 hover:text-primary-900 mr-2"
          >
            <span className="material-icons">edit</span>
          </Button>
          <Button
            variant="ghost"
            size="icon"
            onClick={() => setDeletingDistrictId(row.original.id)}
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
      column: "cityId",
      label: "common.city",
      options: [
        { value: "", label: "cities.filter.all.parties" },
        ...(cities?.data || []).map((city: any) => ({
          value: city.id,
          label: city.name,
        })),
      ],
    },
    {
      column: "politicalPartyId",
      label: "cities.filter.party",
      options: [
        { value: "", label: "cities.filter.all.parties" },
        ...(districtsData?.parties || []).map((party: any) => ({
          value: party.id,
          label: party.name,
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
          <h2 className="text-2xl font-heading font-bold text-gray-800">{t("districts.title")}</h2>
          <p className="text-gray-500">{t("districts.subtitle")}</p>
        </div>
        <div className="mt-4 sm:mt-0">
          <Button onClick={() => setIsAddModalOpen(true)}>
            <span className="material-icons text-sm mr-2">add</span>
            {t("districts.addnew")}
          </Button>
        </div>
      </div>

      <DataTable
        columns={columns}
        data={districtsData?.data || []}
        pagination={districtsData?.pagination as PaginationInfo}
        onPaginationChange={handlePaginationChange}
        onSearch={handleSearch}
        onFilter={handleFilter}
        searchPlaceholder={t("cities.search")}
        filterOptions={filterOptions}
      />

      {/* Add/Edit Modal */}
      {(isAddModalOpen || editingDistrictId) && (
        <Modal
          title={editingDistrictId ? t("form.edit.district") : t("districts.addnew")}
          isOpen={true}
          onClose={() => {
            setIsAddModalOpen(false);
            setEditingDistrictId(null);
          }}
        >
          <DistrictForm
            districtId={editingDistrictId || undefined}
            onClose={() => {
              setIsAddModalOpen(false);
              setEditingDistrictId(null);
            }}
          />
        </Modal>
      )}

      {/* Delete Confirmation Dialog */}
      <ConfirmDialog
        title={t("common.delete")}
        description={t("notifications.confirmed")}
        isOpen={!!deletingDistrictId}
        onClose={() => setDeletingDistrictId(null)}
        onConfirm={() => deletingDistrictId && deleteMutation.mutate(deletingDistrictId)}
        variant="destructive"
      />
    </section>
  );
}
