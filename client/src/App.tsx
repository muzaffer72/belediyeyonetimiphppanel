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
import { useState } from "react";

function Router() {
  return (
    <Switch>
      <Route path="/login" component={Login} />
      <Route path="/">
        <Layout>
          <Route path="/" component={Dashboard} />
          <Route path="/cities" component={Cities} />
          <Route path="/districts" component={Districts} />
          <Route path="/posts" component={Posts} />
          <Route path="/comments" component={Comments} />
          <Route path="/announcements" component={Announcements} />
          <Route path="/users" component={Users} />
          <Route path="/parties" component={Parties} />
          <Route path="/settings" component={Settings} />
        </Layout>
      </Route>
      <Route component={NotFound} />
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
