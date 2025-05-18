import { MainLayout } from "./MainLayout";
import { ReactNode } from "react";

interface LayoutProps {
  children: ReactNode;
}

export function Layout({ children }: LayoutProps) {
  return (
    <MainLayout>
      {children}
    </MainLayout>
  );
}
