import { Switch, Route, useRoute, useLocation } from "wouter";
import { queryClient } from "./lib/queryClient";
import { QueryClientProvider } from "@tanstack/react-query";
import { Toaster } from "@/components/ui/toaster";
import { TooltipProvider } from "@/components/ui/tooltip";
import { Layout } from "@/components/Layout";
import Dashboard from "@/pages/dashboard";
import Cities from "@/pages/cities";
import Districts from "@/pages/districts";
import Posts from "@/pages/posts";
import Comments from "@/pages/comments";
import Announcements from "@/pages/announcements";
import Users from "@/pages/users";
import Parties from "@/pages/parties";
import Settings from "@/pages/settings";
import Login from "@/pages/login";
import NotFound from "@/pages/not-found";
import { useEffect } from "react";

// This component will handle route matching for paths in the layout
const RouteInLayout = ({ path, component: Component }: { path: string, component: React.ComponentType<any> }) => {
  const [match] = useRoute(path);
  return match ? <Component /> : null;
};

function Router() {
  const [location] = useLocation();
  
  // List of all routes that should be wrapped in the Layout
  const layoutRoutes = [
    "/", "/cities", "/districts", "/posts", "/comments", 
    "/announcements", "/users", "/parties", "/settings"
  ];
  
  // Check if current location should be wrapped in the Layout
  const shouldUseLayout = layoutRoutes.some(route => 
    location === route || location.startsWith(`${route}/`)
  );
  
  // If we're at a route that should use the layout but it's not the exact match
  // for any registered route, we'll show the NotFound component inside the layout
  const isUnknownLayoutRoute = shouldUseLayout && 
    !layoutRoutes.some(route => location === route);
  
  return (
    <Switch>
      <Route path="/login" component={Login} />
      
      {shouldUseLayout && (
        <Layout>
          <RouteInLayout path="/" component={Dashboard} />
          <RouteInLayout path="/cities" component={Cities} />
          <RouteInLayout path="/districts" component={Districts} />
          <RouteInLayout path="/posts" component={Posts} />
          <RouteInLayout path="/comments" component={Comments} />
          <RouteInLayout path="/announcements" component={Announcements} />
          <RouteInLayout path="/users" component={Users} />
          <RouteInLayout path="/parties" component={Parties} />
          <RouteInLayout path="/settings" component={Settings} />
          {isUnknownLayoutRoute && <NotFound />}
        </Layout>
      )}
      
      {!shouldUseLayout && location !== "/login" && <NotFound />}
    </Switch>
  );
}

function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <TooltipProvider>
        <Toaster />
        <Router />
      </TooltipProvider>
    </QueryClientProvider>
  );
}

export default App;
