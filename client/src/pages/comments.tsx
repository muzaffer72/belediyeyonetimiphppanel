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
import { Textarea } from "@/components/ui/textarea";
import { Spinner } from "@/components/ui/spinner";
import { PaginationInfo } from "@shared/types";
import { formatDistanceToNow } from "date-fns";
import { tr, enUS } from "date-fns/locale";

export default function Comments() {
  const { t, locale } = useTranslation();
  const { toast } = useToast();
  const queryClient = useQueryClient();
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState(10);
  const [searchTerm, setSearchTerm] = useState("");
  const [filters, setFilters] = useState<any>({});
  const [editingComment, setEditingComment] = useState<any>(null);
  const [editContent, setEditContent] = useState("");
  const [deletingCommentId, setDeletingCommentId] = useState<string | null>(null);

  // Fetch comments data
  const {
    data: commentsData,
    isLoading,
    isError,
  } = useQuery({
    queryKey: [
      '/api/comments',
      page,
      pageSize,
      searchTerm,
      filters.postId,
      filters.isHidden,
    ],
    // The actual queryFn is defined in queryClient.ts
  });

  // Delete mutation
  const deleteMutation = useMutation({
    mutationFn: async (id: string) => {
      return apiRequest("DELETE", `/api/comments/${id}`);
    },
    onSuccess: () => {
      toast({
        title: t("notifications.success"),
        description: t("notifications.deleted"),
      });
      queryClient.invalidateQueries({ queryKey: ['/api/comments'] });
      setDeletingCommentId(null);
    },
    onError: (error) => {
      toast({
        title: t("notifications.error"),
        description: t("notifications.error.occurred"),
        variant: "destructive",
      });
    },
  });

  // Update comment mutation
  const updateMutation = useMutation({
    mutationFn: async ({ id, data }: { id: string; data: any }) => {
      return apiRequest("PUT", `/api/comments/${id}`, data);
    },
    onSuccess: () => {
      toast({
        title: t("notifications.success"),
        description: t("notifications.updated"),
      });
      queryClient.invalidateQueries({ queryKey: ['/api/comments'] });
      setEditingComment(null);
    },
    onError: (error) => {
      toast({
        title: t("notifications.error"),
        description: t("notifications.error.occurred"),
        variant: "destructive",
      });
    },
  });

  // Toggle comment hidden status
  const toggleHidden = (id: string, isHidden: boolean) => {
    updateMutation.mutate({ 
      id, 
      data: { isHidden: !isHidden } 
    });
  };

  // Handle edit submission
  const handleSaveEdit = () => {
    if (!editingComment) return;
    
    updateMutation.mutate({ 
      id: editingComment.id, 
      data: { content: editContent } 
    });
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
      accessorKey: "content",
      header: t("common.content"),
      cell: ({ row }: any) => (
        <div className="max-w-md">
          <div className="text-sm text-gray-700">{row.original.content}</div>
        </div>
      ),
    },
    {
      accessorKey: "userId",
      header: t("common.username"),
      cell: ({ row }: any) => {
        const user = row.original.user || {};
        return (
          <div className="flex items-center">
            <div className="flex-shrink-0 h-8 w-8">
              <img 
                className="h-8 w-8 rounded-full" 
                src={user.profileImageUrl || `https://ui-avatars.com/api/?name=${encodeURIComponent(user.username || "User")}&background=random`} 
                alt={user.username} 
              />
            </div>
            <div className="ml-3">
              <p className="text-sm font-medium text-gray-700">{user.username || "Unknown"}</p>
            </div>
          </div>
        );
      },
    },
    {
      accessorKey: "postId",
      header: t("common.post"),
      cell: ({ row }: any) => (
        <span className="text-sm text-gray-700 truncate max-w-[200px] block">
          {row.original.post?.title || row.original.postId}
        </span>
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
        <div>
          {row.original.isHidden && (
            <StatusBadge status="inactive" statusKey="common.hide" />
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
            onClick={() => toggleHidden(row.original.id, row.original.isHidden)}
            className={row.original.isHidden ? "text-red-600" : "text-gray-400"}
            title={row.original.isHidden ? t("common.show") : t("common.hide")}
          >
            <span className="material-icons text-sm">visibility_off</span>
          </Button>
          <Button
            variant="ghost"
            size="icon"
            onClick={() => {
              setEditingComment(row.original);
              setEditContent(row.original.content);
            }}
            className="text-primary-600 hover:text-primary-900"
          >
            <span className="material-icons text-sm">edit</span>
          </Button>
          <Button
            variant="ghost"
            size="icon"
            onClick={() => setDeletingCommentId(row.original.id)}
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
      column: "isHidden",
      label: "common.status",
      options: [
        { value: "", label: "common.all" },
        { value: "true", label: "common.hide" },
        { value: "false", label: "common.show" },
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
          <h2 className="text-2xl font-heading font-bold text-gray-800">{t("comments.title")}</h2>
          <p className="text-gray-500">{t("comments.subtitle")}</p>
        </div>
      </div>

      <DataTable
        columns={columns}
        data={commentsData?.data || []}
        pagination={commentsData?.pagination as PaginationInfo}
        onPaginationChange={handlePaginationChange}
        onSearch={handleSearch}
        onFilter={handleFilter}
        searchPlaceholder={t("common.search")}
        filterOptions={filterOptions}
      />

      {/* Edit Modal */}
      {editingComment && (
        <Modal
          title={t("common.edit")}
          isOpen={true}
          onClose={() => setEditingComment(null)}
        >
          <div className="space-y-4 py-2">
            <Textarea
              value={editContent}
              onChange={(e) => setEditContent(e.target.value)}
              rows={4}
            />
            <div className="flex justify-end space-x-3">
              <Button
                variant="outline"
                onClick={() => setEditingComment(null)}
              >
                {t("common.cancel")}
              </Button>
              <Button onClick={handleSaveEdit} disabled={updateMutation.isPending}>
                {updateMutation.isPending ? <Spinner className="mr-2" /> : null}
                {t("common.save")}
              </Button>
            </div>
          </div>
        </Modal>
      )}

      {/* Delete Confirmation Dialog */}
      <ConfirmDialog
        title={t("common.delete")}
        description={t("notifications.confirmed")}
        isOpen={!!deletingCommentId}
        onClose={() => setDeletingCommentId(null)}
        onConfirm={() => deletingCommentId && deleteMutation.mutate(deletingCommentId)}
        variant="destructive"
      />
    </section>
  );
}
