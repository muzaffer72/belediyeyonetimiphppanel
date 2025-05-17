import { useState } from "react";
import { useTranslation } from "@/lib/i18n";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { apiRequest } from "@/lib/queryClient";
import { useToast } from "@/hooks/use-toast";
import { Button } from "@/components/ui/button";
import { DataTable } from "@/components/ui/data-table";
import { Modal } from "@/components/ui/modal";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import { UserForm } from "@/components/forms/UserForm";
import { Spinner } from "@/components/ui/spinner";
import { PaginationInfo } from "@shared/types";
import { formatDistanceToNow } from "date-fns";
import { tr, enUS } from "date-fns/locale";

export default function Users() {
  const { t, locale } = useTranslation();
  const { toast } = useToast();
  const queryClient = useQueryClient();
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState(10);
  const [searchTerm, setSearchTerm] = useState("");
  const [filters, setFilters] = useState<any>({});
  const [editingUserId, setEditingUserId] = useState<string | null>(null);
  const [isAddModalOpen, setIsAddModalOpen] = useState(false);
  const [deletingUserId, setDeletingUserId] = useState<string | null>(null);
  const [banningUserId, setBanningUserId] = useState<string | null>(null);
  const [unbanningUserId, setUnbanningUserId] = useState<string | null>(null);

  // Fetch users data
  const {
    data: usersData,
    isLoading,
    isError,
  } = useQuery({
    queryKey: [
      '/api/users',
      page,
      pageSize,
      searchTerm,
      filters.role,
      filters.city,
    ],
    // The actual queryFn is defined in queryClient.ts
  });

  // Fetch user bans data to check which users are banned
  const { data: userBans } = useQuery({
    queryKey: ['/api/user-bans'],
  });

  // Delete mutation
  const deleteMutation = useMutation({
    mutationFn: async (id: string) => {
      return apiRequest("DELETE", `/api/users/${id}`);
    },
    onSuccess: () => {
      toast({
        title: t("notifications.success"),
        description: t("notifications.deleted"),
      });
      queryClient.invalidateQueries({ queryKey: ['/api/users'] });
      setDeletingUserId(null);
    },
    onError: (error) => {
      toast({
        title: t("notifications.error"),
        description: t("notifications.error.occurred"),
        variant: "destructive",
      });
    },
  });

  // Ban user mutation
  const banUserMutation = useMutation({
    mutationFn: async (userId: string) => {
      // In a real app, you would get the current admin user ID from auth context
      const adminId = "83190944-98d5-41be-ac3a-178676faf017"; // Admin user ID from the sample data
      
      const now = new Date();
      const oneWeekLater = new Date();
      oneWeekLater.setDate(now.getDate() + 7);
      
      const banData = {
        userId,
        bannedBy: adminId,
        banStart: now.toISOString(),
        banEnd: oneWeekLater.toISOString(),
        contentAction: "none",
        isActive: true,
      };
      
      return apiRequest("POST", `/api/user-bans`, banData);
    },
    onSuccess: () => {
      toast({
        title: t("notifications.success"),
        description: t("notifications.banned"),
      });
      queryClient.invalidateQueries({ queryKey: ['/api/user-bans'] });
      setBanningUserId(null);
    },
    onError: (error) => {
      toast({
        title: t("notifications.error"),
        description: t("notifications.error.occurred"),
        variant: "destructive",
      });
    },
  });

  // Unban user mutation
  const unbanUserMutation = useMutation({
    mutationFn: async (userId: string) => {
      // Find the active ban for this user
      const activeBan = userBans?.data?.find((ban: any) => 
        ban.userId === userId && ban.isActive
      );
      
      if (!activeBan) {
        throw new Error("No active ban found for this user");
      }
      
      return apiRequest("PUT", `/api/user-bans/${activeBan.id}`, {
        isActive: false
      });
    },
    onSuccess: () => {
      toast({
        title: t("notifications.success"),
        description: t("notifications.unbanned"),
      });
      queryClient.invalidateQueries({ queryKey: ['/api/user-bans'] });
      setUnbanningUserId(null);
    },
    onError: (error) => {
      toast({
        title: t("notifications.error"),
        description: t("notifications.error.occurred"),
        variant: "destructive",
      });
    },
  });

  // Check if a user is banned
  const isUserBanned = (userId: string) => {
    if (!userBans?.data) return false;
    
    return userBans.data.some((ban: any) => 
      ban.userId === userId && ban.isActive === true
    );
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
      accessorKey: "username",
      header: t("common.username"),
      cell: ({ row }: any) => (
        <div className="flex items-center">
          <div className="flex-shrink-0 h-10 w-10">
            <img 
              className="h-10 w-10 rounded-full" 
              src={row.original.profileImageUrl || `https://ui-avatars.com/api/?name=${encodeURIComponent(row.original.username)}&background=random`} 
              alt={row.original.username} 
            />
          </div>
          <div className="ml-4">
            <div className="text-sm font-medium text-gray-900">{row.original.username}</div>
            <div className="text-sm text-gray-500">{row.original.email}</div>
          </div>
        </div>
      ),
    },
    {
      accessorKey: "role",
      header: t("common.role"),
      cell: ({ row }: any) => {
        const roleColors: Record<string, string> = {
          admin: "bg-purple-100 text-purple-800",
          moderator: "bg-blue-100 text-blue-800",
          user: "bg-gray-100 text-gray-800",
        };
        
        const role = row.original.role?.toLowerCase() || "user";
        const colorClass = roleColors[role] || roleColors.user;
        
        return (
          <span className={`px-2 inline-flex text-xs leading-5 font-semibold rounded-full ${colorClass}`}>
            {role.charAt(0).toUpperCase() + role.slice(1)}
          </span>
        );
      },
    },
    {
      accessorKey: "city",
      header: t("common.city"),
      cell: ({ row }: any) => (
        <span className="text-sm text-gray-700">{row.original.city || "-"}</span>
      ),
    },
    {
      accessorKey: "district",
      header: t("common.district"),
      cell: ({ row }: any) => (
        <span className="text-sm text-gray-700">{row.original.district || "-"}</span>
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
      cell: ({ row }: any) => {
        const banned = isUserBanned(row.original.id);
        return (
          <span className={`px-2 inline-flex text-xs leading-5 font-semibold rounded-full ${banned ? 'bg-red-100 text-red-800' : 'bg-green-100 text-green-800'}`}>
            {banned ? t("common.ban") : t("common.active")}
          </span>
        );
      },
    },
    {
      id: "actions",
      cell: ({ row }: any) => {
        const banned = isUserBanned(row.original.id);
        return (
          <div className="flex justify-end space-x-1">
            {banned ? (
              <Button
                variant="ghost"
                size="icon"
                onClick={() => setUnbanningUserId(row.original.id)}
                className="text-green-600 hover:text-green-900"
                title={t("common.unban")}
              >
                <span className="material-icons text-sm">lock_open</span>
              </Button>
            ) : (
              <Button
                variant="ghost"
                size="icon"
                onClick={() => setBanningUserId(row.original.id)}
                className="text-red-600 hover:text-red-900"
                title={t("common.ban")}
              >
                <span className="material-icons text-sm">block</span>
              </Button>
            )}
            <Button
              variant="ghost"
              size="icon"
              onClick={() => setEditingUserId(row.original.id)}
              className="text-primary-600 hover:text-primary-900"
            >
              <span className="material-icons text-sm">edit</span>
            </Button>
            <Button
              variant="ghost"
              size="icon"
              onClick={() => setDeletingUserId(row.original.id)}
              className="text-red-600 hover:text-red-900"
            >
              <span className="material-icons text-sm">delete</span>
            </Button>
          </div>
        );
      },
    },
  ];

  // Filter options
  const filterOptions = [
    {
      column: "role",
      label: "common.role",
      options: [
        { value: "", label: "common.all" },
        { value: "admin", label: "Admin" },
        { value: "moderator", label: "Moderator" },
        { value: "user", label: "User" },
      ],
    },
    {
      column: "city",
      label: "common.city",
      options: [
        { value: "", label: "common.all" },
        ...(usersData?.cities || []).map((city: string) => ({
          value: city,
          label: city,
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
          <h2 className="text-2xl font-heading font-bold text-gray-800">{t("users.title")}</h2>
          <p className="text-gray-500">{t("users.subtitle")}</p>
        </div>
        <div className="mt-4 sm:mt-0">
          <Button onClick={() => setIsAddModalOpen(true)}>
            <span className="material-icons text-sm mr-2">person_add</span>
            {t("users.addnew")}
          </Button>
        </div>
      </div>

      <DataTable
        columns={columns}
        data={usersData?.data || []}
        pagination={usersData?.pagination as PaginationInfo}
        onPaginationChange={handlePaginationChange}
        onSearch={handleSearch}
        onFilter={handleFilter}
        searchPlaceholder={t("common.search")}
        filterOptions={filterOptions}
      />

      {/* Add/Edit Modal */}
      {(isAddModalOpen || editingUserId) && (
        <Modal
          title={editingUserId ? t("common.edit") : t("users.addnew")}
          isOpen={true}
          onClose={() => {
            setIsAddModalOpen(false);
            setEditingUserId(null);
          }}
        >
          <UserForm
            userId={editingUserId || undefined}
            onClose={() => {
              setIsAddModalOpen(false);
              setEditingUserId(null);
            }}
          />
        </Modal>
      )}

      {/* Delete Confirmation Dialog */}
      <ConfirmDialog
        title={t("common.delete")}
        description={t("notifications.confirmed")}
        isOpen={!!deletingUserId}
        onClose={() => setDeletingUserId(null)}
        onConfirm={() => deletingUserId && deleteMutation.mutate(deletingUserId)}
        variant="destructive"
      />

      {/* Ban Confirmation Dialog */}
      <ConfirmDialog
        title={t("common.ban")}
        description={t("common.ban")}
        isOpen={!!banningUserId}
        onClose={() => setBanningUserId(null)}
        onConfirm={() => banningUserId && banUserMutation.mutate(banningUserId)}
        variant="destructive"
      />

      {/* Unban Confirmation Dialog */}
      <ConfirmDialog
        title={t("common.unban")}
        description={t("common.unban")}
        isOpen={!!unbanningUserId}
        onClose={() => setUnbanningUserId(null)}
        onConfirm={() => unbanningUserId && unbanUserMutation.mutate(unbanningUserId)}
      />
    </section>
  );
}
