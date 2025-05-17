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

export default function Comments() {
  const { t, locale } = useTranslation();
  const { toast } = useToast();
  const queryClient = useQueryClient();
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState(10);
  const [searchTerm, setSearchTerm] = useState("");
  const [filters, setFilters] = useState<any>({});
  const [editingCommentId, setEditingCommentId] = useState<string | null>(null);
  const [viewingCommentId, setViewingCommentId] = useState<string | null>(null);
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
      filters.status,
      filters.postType,
    ],
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

  // Update comment status (approve/reject)
  const updateStatusMutation = useMutation({
    mutationFn: async ({ id, status }: { id: string; status: string }) => {
      return apiRequest("PATCH", `/api/comments/${id}`, { status });
    },
    onSuccess: () => {
      toast({
        title: t("notifications.success"),
        description: t("notifications.updated"),
      });
      queryClient.invalidateQueries({ queryKey: ['/api/comments'] });
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

  // Truncate text
  const truncateText = (text: string, maxLength: number = 100) => {
    if (!text) return '';
    return text.length > maxLength ? text.slice(0, maxLength) + '...' : text;
  };

  // Table columns
  const columns = [
    {
      accessorKey: "content",
      header: t("comments.table.comment"),
      cell: ({ row }: any) => (
        <div className="max-w-md">
          <div className="text-sm text-gray-900">{truncateText(row.original.content, 150)}</div>
        </div>
      ),
    },
    {
      accessorKey: "post",
      header: t("comments.table.post"),
      cell: ({ row }: any) => (
        <div className="max-w-xs">
          <div className="text-sm font-medium text-gray-900 truncate">{row.original.postTitle}</div>
          <div className="text-xs text-gray-500">{row.original.postType}</div>
        </div>
      ),
    },
    {
      accessorKey: "user",
      header: t("comments.table.author"),
      cell: ({ row }: any) => (
        <div className="flex items-center">
          <div className="flex-shrink-0 h-8 w-8">
            <img 
              className="h-8 w-8 rounded-full" 
              src={row.original.userAvatar || `https://ui-avatars.com/api/?name=${encodeURIComponent(row.original.username || 'User')}&background=random`} 
              alt={row.original.username} 
            />
          </div>
          <div className="ml-3">
            <div className="text-sm font-medium text-gray-900">{row.original.username}</div>
          </div>
        </div>
      ),
    },
    {
      accessorKey: "createdAt",
      header: t("comments.table.date"),
      cell: ({ row }: any) => (
        <span className="text-sm text-gray-500">{formatDate(row.original.createdAt)}</span>
      ),
    },
    {
      accessorKey: "status",
      header: t("comments.table.status"),
      cell: ({ row }: any) => {
        const status = row.original.status || "pending";
        return <StatusBadge status={status} />;
      },
    },
    {
      id: "actions",
      cell: ({ row }: any) => (
        <div className="flex justify-end space-x-1">
          {row.original.status === "pending" && (
            <>
              <Button
                variant="ghost"
                size="icon"
                onClick={() => updateStatusMutation.mutate({ id: row.original.id, status: "approved" })}
                className="text-green-600 hover:text-green-900"
                title={t("comments.approve")}
              >
                <span className="material-icons text-sm">check_circle</span>
              </Button>
              <Button
                variant="ghost"
                size="icon"
                onClick={() => updateStatusMutation.mutate({ id: row.original.id, status: "rejected" })}
                className="text-red-600 hover:text-red-900"
                title={t("comments.reject")}
              >
                <span className="material-icons text-sm">cancel</span>
              </Button>
            </>
          )}
          <Button
            variant="ghost"
            size="icon"
            onClick={() => setViewingCommentId(row.original.id)}
            className="text-blue-600 hover:text-blue-900"
          >
            <span className="material-icons text-sm">visibility</span>
          </Button>
          <Button
            variant="ghost"
            size="icon"
            onClick={() => setEditingCommentId(row.original.id)}
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
      column: "status",
      label: "comments.filter.status",
      options: [
        { value: "", label: "comments.filter.all.statuses" },
        { value: "pending", label: "comments.status.pending" },
        { value: "approved", label: "comments.status.approved" },
        { value: "rejected", label: "comments.status.rejected" },
      ],
    },
    {
      column: "postType",
      label: "comments.filter.post.type",
      options: [
        { value: "", label: "comments.filter.all.types" },
        { value: "complaint", label: "posts.types.complaint" },
        { value: "suggestion", label: "posts.types.suggestion" },
        { value: "question", label: "posts.types.question" },
        { value: "thanks", label: "posts.types.thanks" },
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
        searchPlaceholder={t("comments.search")}
        filterOptions={filterOptions}
      />

      {/* View Comment Modal */}
      {viewingCommentId && (
        <Modal
          title={t("comments.view")}
          isOpen={true}
          onClose={() => setViewingCommentId(null)}
        >
          <div className="p-4">
            {commentsData?.data.find((comment: any) => comment.id === viewingCommentId) && (
              <div>
                <div className="flex items-center mb-4">
                  <div className="flex-shrink-0 h-10 w-10">
                    <img 
                      className="h-10 w-10 rounded-full" 
                      src={commentsData?.data.find((comment: any) => comment.id === viewingCommentId)?.userAvatar || 
                        `https://ui-avatars.com/api/?name=${encodeURIComponent(
                          commentsData?.data.find((comment: any) => comment.id === viewingCommentId)?.username || 'User'
                        )}&background=random`
                      } 
                      alt="User avatar" 
                    />
                  </div>
                  <div className="ml-3">
                    <p className="text-sm font-medium text-gray-900">
                      {commentsData?.data.find((comment: any) => comment.id === viewingCommentId)?.username}
                    </p>
                    <p className="text-xs text-gray-500">
                      {formatDate(commentsData?.data.find((comment: any) => comment.id === viewingCommentId)?.createdAt)}
                    </p>
                  </div>
                </div>
                <div className="mb-4">
                  <p className="text-gray-800">
                    {commentsData?.data.find((comment: any) => comment.id === viewingCommentId)?.content}
                  </p>
                </div>
                <div className="bg-gray-50 p-3 rounded-md">
                  <p className="text-xs text-gray-500 mb-1">{t("comments.on.post")}</p>
                  <p className="text-sm font-medium">
                    {commentsData?.data.find((comment: any) => comment.id === viewingCommentId)?.postTitle}
                  </p>
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
        isOpen={!!deletingCommentId}
        onClose={() => setDeletingCommentId(null)}
        onConfirm={() => deletingCommentId && deleteMutation.mutate(deletingCommentId)}
        variant="destructive"
      />
    </section>
  );
}