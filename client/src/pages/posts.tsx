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
import { PostForm } from "@/components/forms/PostForm";
import { Spinner } from "@/components/ui/spinner";
import { PaginationInfo } from "@shared/types";

export default function Posts() {
  const { t } = useTranslation();
  const { toast } = useToast();
  const queryClient = useQueryClient();
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState(10);
  const [searchTerm, setSearchTerm] = useState("");
  const [filters, setFilters] = useState<any>({});
  const [editingPostId, setEditingPostId] = useState<string | null>(null);
  const [isAddModalOpen, setIsAddModalOpen] = useState(false);
  const [deletingPostId, setDeletingPostId] = useState<string | null>(null);
  const [showFeatured, setShowFeatured] = useState(false);
  const [showComplaints, setShowComplaints] = useState(false);

  // Fetch posts data
  const {
    data: postsData,
    isLoading,
    isError,
  } = useQuery({
    queryKey: [
      '/api/posts',
      page,
      pageSize,
      searchTerm,
      filters.type,
      filters.city,
      filters.isResolved,
      filters.isHidden,
      showFeatured,
      showComplaints,
    ],
    // The actual queryFn is defined in queryClient.ts
  });

  // Delete mutation
  const deleteMutation = useMutation({
    mutationFn: async (id: string) => {
      return apiRequest("DELETE", `/api/posts/${id}`);
    },
    onSuccess: () => {
      toast({
        title: t("notifications.success"),
        description: t("notifications.deleted"),
      });
      queryClient.invalidateQueries({ queryKey: ['/api/posts'] });
      setDeletingPostId(null);
    },
    onError: (error) => {
      toast({
        title: t("notifications.error"),
        description: t("notifications.error.occurred"),
        variant: "destructive",
      });
    },
  });

  // Feature/Unfeature post mutation
  const featureMutation = useMutation({
    mutationFn: async ({ id, userId }: { id: string; userId: string }) => {
      return apiRequest("POST", `/api/posts/${id}/feature`, { userId });
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['/api/posts'] });
    },
    onError: (error) => {
      toast({
        title: t("notifications.error"),
        description: t("notifications.error.occurred"),
        variant: "destructive",
      });
    },
  });

  // Toggle post featured status
  const toggleFeatured = (id: string) => {
    // In a real app, you would get the current user ID from auth context
    const userId = "83190944-98d5-41be-ac3a-178676faf017"; // Admin user ID from the sample data
    featureMutation.mutate({ id, userId });
  };

  // Toggle post resolved status
  const toggleResolved = (id: string, isResolved: boolean) => {
    const updateMutation = useMutation({
      mutationFn: async ({ id, data }: { id: string; data: any }) => {
        return apiRequest("PUT", `/api/posts/${id}`, data);
      },
      onSuccess: () => {
        queryClient.invalidateQueries({ queryKey: ['/api/posts'] });
        toast({
          title: t("notifications.success"),
          description: isResolved ? t("notifications.unresolved") : t("notifications.resolved"),
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

    updateMutation.mutate({ id, data: { isResolved: !isResolved } });
  };

  // Toggle post hidden status
  const toggleHidden = (id: string, isHidden: boolean) => {
    const updateMutation = useMutation({
      mutationFn: async ({ id, data }: { id: string; data: any }) => {
        return apiRequest("PUT", `/api/posts/${id}`, data);
      },
      onSuccess: () => {
        queryClient.invalidateQueries({ queryKey: ['/api/posts'] });
        toast({
          title: t("notifications.success"),
          description: isHidden ? t("notifications.shown") : t("notifications.hidden"),
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

    updateMutation.mutate({ id, data: { isHidden: !isHidden } });
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

  // Table columns
  const columns = [
    {
      accessorKey: "title",
      header: t("common.title"),
      cell: ({ row }: any) => (
        <div className="max-w-md">
          <div className="text-sm font-medium text-gray-900">{row.original.title}</div>
          <div className="text-xs text-gray-500 truncate">{row.original.description}</div>
        </div>
      ),
    },
    {
      accessorKey: "type",
      header: t("common.type"),
      cell: ({ row }: any) => {
        const typeMapping: Record<string, { color: string; icon: string }> = {
          complaint: { color: "red", icon: "report_problem" },
          suggestion: { color: "green", icon: "lightbulb" },
          question: { color: "blue", icon: "help_outline" },
          thanks: { color: "amber", icon: "favorite" },
        };
        
        const type = row.original.type?.toLowerCase() || "complaint";
        const { color, icon } = typeMapping[type] || typeMapping.complaint;
        
        return (
          <div className="flex items-center">
            <span className={`material-icons text-${color}-500 mr-1`}>{icon}</span>
            <span className="text-sm capitalize">{type}</span>
          </div>
        );
      },
    },
    {
      accessorKey: "city",
      header: t("common.city"),
      cell: ({ row }: any) => (
        <span className="text-sm">{row.original.city}</span>
      ),
    },
    {
      accessorKey: "likeCount",
      header: t("common.likes"),
      cell: ({ row }: any) => (
        <span className="text-sm font-medium">{row.original.likeCount || 0}</span>
      ),
    },
    {
      accessorKey: "commentCount",
      header: t("common.comments"),
      cell: ({ row }: any) => (
        <span className="text-sm font-medium">{row.original.commentCount || 0}</span>
      ),
    },
    {
      accessorKey: "status",
      header: t("common.status"),
      cell: ({ row }: any) => (
        <div className="space-x-1">
          {row.original.isResolved && (
            <StatusBadge status="resolved" />
          )}
          {row.original.isHidden && (
            <StatusBadge status="inactive" statusKey="common.hide" />
          )}
          {row.original.isFeatured && (
            <StatusBadge status="featured" />
          )}
          {!row.original.isResolved && !row.original.isHidden && !row.original.isFeatured && (
            <StatusBadge status="pending" />
          )}
        </div>
      ),
    },
    {
      id: "actions",
      cell: ({ row }: any) => (
        <div className="flex justify-end space-x-1">
          <Button
            variant="ghost"
            size="icon"
            onClick={() => toggleResolved(row.original.id, row.original.isResolved)}
            className={row.original.isResolved ? "text-green-600" : "text-gray-400"}
            title={row.original.isResolved ? t("common.unresolved") : t("common.resolved")}
          >
            <span className="material-icons text-sm">check_circle</span>
          </Button>
          <Button
            variant="ghost"
            size="icon"
            onClick={() => toggleHidden(row.original.id, row.original.isHidden)}
            className={row.original.isHidden ? "text-red-600" : "text-gray-400"}
            title={row.original.isHidden ? t("common.show") : t("common.hide")}
          >
            <span className="material-icons text-sm">visibility_off</span>
          </Button>
          <Button
            variant="ghost"
            size="icon"
            onClick={() => toggleFeatured(row.original.id)}
            className={row.original.isFeatured ? "text-amber-600" : "text-gray-400"}
            title={row.original.isFeatured ? t("common.unfeature") : t("common.feature")}
          >
            <span className="material-icons text-sm">star</span>
          </Button>
          <Button
            variant="ghost"
            size="icon"
            onClick={() => setEditingPostId(row.original.id)}
            className="text-primary-600 hover:text-primary-900"
          >
            <span className="material-icons text-sm">edit</span>
          </Button>
          <Button
            variant="ghost"
            size="icon"
            onClick={() => setDeletingPostId(row.original.id)}
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
      column: "type",
      label: "common.type",
      options: [
        { value: "", label: "common.all" },
        { value: "complaint", label: "dashboard.complaints" },
        { value: "suggestion", label: "dashboard.suggestions" },
        { value: "question", label: "dashboard.questions" },
        { value: "thanks", label: "dashboard.thanks" },
      ],
    },
    {
      column: "isResolved",
      label: "common.status",
      options: [
        { value: "", label: "common.all" },
        { value: "true", label: "common.resolved" },
        { value: "false", label: "common.pending" },
      ],
    },
  ];

  // Toggle filter handlers
  const handleToggleComplaints = () => {
    setShowComplaints(!showComplaints);
    setShowFeatured(false);
    setFilters((prev: any) => ({ ...prev, type: !showComplaints ? "complaint" : "" }));
  };

  const handleToggleFeatured = () => {
    setShowFeatured(!showFeatured);
    setShowComplaints(false);
    setFilters((prev: any) => ({ ...prev, isFeatured: !showFeatured ? true : undefined }));
  };

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
          <h2 className="text-2xl font-heading font-bold text-gray-800">{t("posts.title")}</h2>
          <p className="text-gray-500">{t("posts.subtitle")}</p>
        </div>
        <div className="mt-4 sm:mt-0 flex space-x-3">
          <Button
            variant={showComplaints ? "default" : "outline"}
            onClick={handleToggleComplaints}
            className={showComplaints ? "bg-red-600 hover:bg-red-700" : ""}
          >
            <span className="material-icons text-sm mr-2">report</span>
            {t("posts.complaints")}
          </Button>
          <Button
            variant={showFeatured ? "default" : "outline"}
            onClick={handleToggleFeatured}
            className={showFeatured ? "bg-primary-600 hover:bg-primary-700" : ""}
          >
            <span className="material-icons text-sm mr-2">star</span>
            {t("posts.featured")}
          </Button>
          <Button onClick={() => setIsAddModalOpen(true)}>
            <span className="material-icons text-sm mr-2">add</span>
            {t("common.title")}
          </Button>
        </div>
      </div>

      <DataTable
        columns={columns}
        data={postsData?.data || []}
        pagination={postsData?.pagination as PaginationInfo}
        onPaginationChange={handlePaginationChange}
        onSearch={handleSearch}
        onFilter={handleFilter}
        searchPlaceholder={t("common.search")}
        filterOptions={filterOptions}
      />

      {/* Add/Edit Modal */}
      {(isAddModalOpen || editingPostId) && (
        <Modal
          title={editingPostId ? t("common.edit") : t("common.title")}
          isOpen={true}
          onClose={() => {
            setIsAddModalOpen(false);
            setEditingPostId(null);
          }}
        >
          <PostForm
            postId={editingPostId || undefined}
            onClose={() => {
              setIsAddModalOpen(false);
              setEditingPostId(null);
            }}
          />
        </Modal>
      )}

      {/* Delete Confirmation Dialog */}
      <ConfirmDialog
        title={t("common.delete")}
        description={t("notifications.confirmed")}
        isOpen={!!deletingPostId}
        onClose={() => setDeletingPostId(null)}
        onConfirm={() => deletingPostId && deleteMutation.mutate(deletingPostId)}
        variant="destructive"
      />
    </section>
  );
}
