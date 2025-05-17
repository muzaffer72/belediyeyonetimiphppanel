import { Switch, Route } from "wouter";
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

// Basit bir router yapısı
function Router() {
  return (
    <Switch>
      <Route path="/login">
        <Login />
      </Route>
      <Route path="/">
        <Layout>
          <Switch>
            <Route path="/">
              <Dashboard />
            </Route>
            <Route path="/cities">
              <Cities />
            </Route>
            <Route path="/districts">
              <Districts />
            </Route>
            <Route path="/posts">
              <Posts />
            </Route>
            <Route path="/comments">
              <Comments />
            </Route>
            <Route path="/announcements">
              <Announcements />
            </Route>
            <Route path="/users">
              <Users />
            </Route>
            <Route path="/parties">
              <Parties />
            </Route>
            <Route path="/settings">
              <Settings />
            </Route>
            <Route>
              <NotFound />
            </Route>
          </Switch>
        </Layout>
      </Route>
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
