import { useState } from "react";
import {
  ColumnDef,
  flexRender,
  getCoreRowModel,
  useReactTable,
  getPaginationRowModel,
  SortingState,
  getSortedRowModel,
  ColumnFiltersState,
  getFilteredRowModel,
} from "@tanstack/react-table";
import { useTranslation } from "@/lib/i18n";
import { formatMessage } from "@/lib/i18n";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { PaginationInfo } from "@shared/types";

interface DataTableProps<TData, TValue> {
  columns: ColumnDef<TData, TValue>[];
  data: TData[];
  pagination?: PaginationInfo;
  onPaginationChange?: (pageIndex: number, pageSize: number) => void;
  onSortingChange?: (sorting: SortingState) => void;
  onSearch?: (value: string) => void;
  onFilter?: (column: string, value: any) => void;
  searchPlaceholder?: string;
  filterOptions?: Array<{
    column: string;
    label: string;
    options: Array<{ value: string; label: string }>;
  }>;
}

export function DataTable<TData, TValue>({
  columns,
  data,
  pagination,
  onPaginationChange,
  onSortingChange,
  onSearch,
  onFilter,
  searchPlaceholder,
  filterOptions,
}: DataTableProps<TData, TValue>) {
  const { t } = useTranslation();
  const [sorting, setSorting] = useState<SortingState>([]);
  const [columnFilters, setColumnFilters] = useState<ColumnFiltersState>([]);
  const [searchValue, setSearchValue] = useState("");

  const handleSortingChange = (newSorting: SortingState) => {
    setSorting(newSorting);
    if (onSortingChange) {
      onSortingChange(newSorting);
    }
  };

  const handleSearchChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const value = e.target.value;
    setSearchValue(value);
    
    if (onSearch) {
      onSearch(value);
    }
  };

  const handleFilterChange = (column: string, value: string) => {
    if (onFilter) {
      onFilter(column, value);
    }
  };

  const table = useReactTable({
    data,
    columns,
    state: {
      sorting,
      columnFilters,
    },
    getCoreRowModel: getCoreRowModel(),
    getPaginationRowModel: getPaginationRowModel(),
    onSortingChange: handleSortingChange,
    onColumnFiltersChange: setColumnFilters,
    getSortedRowModel: getSortedRowModel(),
    getFilteredRowModel: getFilteredRowModel(),
    manualPagination: !!pagination,
    pageCount: pagination?.pageCount || -1,
  });

  const handlePageChange = (newPageIndex: number) => {
    if (onPaginationChange && pagination) {
      onPaginationChange(newPageIndex, pagination.pageSize);
    } else {
      table.setPageIndex(newPageIndex);
    }
  };

  const handlePageSizeChange = (newPageSize: number) => {
    if (onPaginationChange && pagination) {
      onPaginationChange(pagination.pageIndex, newPageSize);
    } else {
      table.setPageSize(newPageSize);
    }
  };

  return (
    <div>
      {(onSearch || filterOptions) && (
        <div className="bg-white p-4 rounded-lg shadow-sm mb-6 border border-gray-100">
          <div className="flex flex-col md:flex-row space-y-4 md:space-y-0 md:space-x-4">
            {onSearch && (
              <div className="flex-1">
                <label htmlFor="dataTableSearch" className="block text-sm font-medium text-gray-700 mb-1">
                  {t("common.search")}
                </label>
                <div className="relative">
                  <input
                    type="text"
                    id="dataTableSearch"
                    className="shadow-sm focus:ring-primary-500 focus:border-primary-500 block w-full sm:text-sm border-gray-300 rounded-md pl-10"
                    placeholder={searchPlaceholder || t("common.search") + "..."}
                    value={searchValue}
                    onChange={handleSearchChange}
                  />
                  <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
                    <span className="material-icons text-gray-400 text-lg">search</span>
                  </div>
                </div>
              </div>
            )}

            {filterOptions &&
              filterOptions.map((filter) => (
                <div key={filter.column} className="w-full md:w-48">
                  <label htmlFor={`filter-${filter.column}`} className="block text-sm font-medium text-gray-700 mb-1">
                    {t(filter.label)}
                  </label>
                  <Select onValueChange={(value) => handleFilterChange(filter.column, value)}>
                    <SelectTrigger id={`filter-${filter.column}`} className="w-full">
                      <SelectValue placeholder={t(filter.label)} />
                    </SelectTrigger>
                    <SelectContent>
                      {filter.options.map((option) => (
                        <SelectItem key={option.value} value={option.value}>
                          {t(option.label)}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
              ))}
          </div>
        </div>
      )}

      <div className="bg-white shadow-sm rounded-lg overflow-hidden border border-gray-100">
        <Table>
          <TableHeader>
            {table.getHeaderGroups().map((headerGroup) => (
              <TableRow key={headerGroup.id}>
                {headerGroup.headers.map((header) => (
                  <TableHead key={header.id}>
                    {header.isPlaceholder ? null : (
                      <div
                        className={
                          header.column.getCanSort()
                            ? "flex items-center cursor-pointer select-none"
                            : undefined
                        }
                        onClick={header.column.getToggleSortingHandler()}
                      >
                        {flexRender(
                          header.column.columnDef.header,
                          header.getContext()
                        )}
                        {header.column.getCanSort() && (
                          <button className="ml-1">
                            <span className="material-icons text-xs">
                              {header.column.getIsSorted() === "asc"
                                ? "arrow_upward"
                                : header.column.getIsSorted() === "desc"
                                ? "arrow_downward"
                                : "unfold_more"}
                            </span>
                          </button>
                        )}
                      </div>
                    )}
                  </TableHead>
                ))}
              </TableRow>
            ))}
          </TableHeader>
          <TableBody>
            {table.getRowModel().rows.length ? (
              table.getRowModel().rows.map((row) => (
                <TableRow
                  key={row.id}
                  data-state={row.getIsSelected() && "selected"}
                >
                  {row.getVisibleCells().map((cell) => (
                    <TableCell key={cell.id}>
                      {flexRender(
                        cell.column.columnDef.cell,
                        cell.getContext()
                      )}
                    </TableCell>
                  ))}
                </TableRow>
              ))
            ) : (
              <TableRow>
                <TableCell
                  colSpan={columns.length}
                  className="h-24 text-center"
                >
                  No results.
                </TableCell>
              </TableRow>
            )}
          </TableBody>
        </Table>

        <div className="bg-white px-4 py-3 flex items-center justify-between border-t border-gray-200 sm:px-6">
          <div className="flex-1 flex justify-between sm:hidden">
            <Button
              variant="outline"
              size="sm"
              onClick={() => handlePageChange(
                pagination ? pagination.pageIndex - 1 : table.getState().pagination.pageIndex - 1
              )}
              disabled={
                pagination
                  ? pagination.pageIndex === 0
                  : !table.getCanPreviousPage()
              }
            >
              {t('common.previous')}
            </Button>
            <Button
              variant="outline"
              size="sm"
              onClick={() => handlePageChange(
                pagination ? pagination.pageIndex + 1 : table.getState().pagination.pageIndex + 1
              )}
              disabled={
                pagination
                  ? pagination.pageIndex >= pagination.pageCount - 1
                  : !table.getCanNextPage()
              }
            >
              {t('common.next')}
            </Button>
          </div>
          <div className="hidden sm:flex-1 sm:flex sm:items-center sm:justify-between">
            <div>
              {pagination ? (
                <p className="text-sm text-gray-700">
                  {formatMessage(t('cities.pagination.showing'), {
                    from: pagination.pageIndex * pagination.pageSize + 1,
                    to: Math.min(
                      (pagination.pageIndex + 1) * pagination.pageSize,
                      pagination.total
                    ),
                    total: pagination.total,
                  })}
                </p>
              ) : (
                <p className="text-sm text-gray-700">
                  {t('common.showing')} {table.getState().pagination.pageIndex * table.getState().pagination.pageSize + 1}{' '}
                  {t('common.to')}{' '}
                  {Math.min(
                    (table.getState().pagination.pageIndex + 1) * table.getState().pagination.pageSize,
                    table.getPrePaginationRowModel().rows.length
                  )}{' '}
                  {t('common.of')} {table.getPrePaginationRowModel().rows.length} {t('common.items')}
                </p>
              )}
            </div>
            <div className="flex items-center space-x-2">
              <Select
                value={String(pagination ? pagination.pageSize : table.getState().pagination.pageSize)}
                onValueChange={(value) => handlePageSizeChange(Number(value))}
              >
                <SelectTrigger className="h-8 w-[80px]">
                  <SelectValue placeholder={pagination ? pagination.pageSize : table.getState().pagination.pageSize} />
                </SelectTrigger>
                <SelectContent side="top">
                  {[5, 10, 20, 30, 40, 50].map((pageSize) => (
                    <SelectItem key={pageSize} value={`${pageSize}`}>
                      {pageSize}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              <div>
                <nav className="relative z-0 inline-flex rounded-md shadow-sm -space-x-px" aria-label="Pagination">
                  <Button
                    variant="outline"
                    size="sm"
                    className="rounded-l-md"
                    onClick={() => handlePageChange(0)}
                    disabled={
                      pagination
                        ? pagination.pageIndex === 0
                        : !table.getCanPreviousPage()
                    }
                  >
                    <span className="material-icons text-sm">first_page</span>
                  </Button>
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => handlePageChange(
                      pagination ? pagination.pageIndex - 1 : table.getState().pagination.pageIndex - 1
                    )}
                    disabled={
                      pagination
                        ? pagination.pageIndex === 0
                        : !table.getCanPreviousPage()
                    }
                  >
                    <span className="material-icons text-sm">chevron_left</span>
                  </Button>
                  {/* Page number buttons would go here */}
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => handlePageChange(
                      pagination ? pagination.pageIndex + 1 : table.getState().pagination.pageIndex + 1
                    )}
                    disabled={
                      pagination
                        ? pagination.pageIndex >= pagination.pageCount - 1
                        : !table.getCanNextPage()
                    }
                  >
                    <span className="material-icons text-sm">chevron_right</span>
                  </Button>
                  <Button
                    variant="outline"
                    size="sm"
                    className="rounded-r-md"
                    onClick={() => handlePageChange(
                      pagination ? pagination.pageCount - 1 : table.getPageCount() - 1
                    )}
                    disabled={
                      pagination
                        ? pagination.pageIndex >= pagination.pageCount - 1
                        : !table.getCanNextPage()
                    }
                  >
                    <span className="material-icons text-sm">last_page</span>
                  </Button>
                </nav>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
