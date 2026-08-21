import { createFileRoute, redirect } from "@tanstack/react-router"

import { UsersService } from "@/client"
import { APP_ROUTES, canReadMetrics } from "@/lib/rbac"

export const Route = createFileRoute("/_layout/metrics")({
  component: Metrics,
  beforeLoad: async () => {
    const { data: user } = await UsersService.readUserMe()
    if (!canReadMetrics(user.role)) {
      throw redirect({
        to: APP_ROUTES.forbidden,
      })
    }
  },
  head: () => ({
    meta: [
      {
        title: "Metrics - FastAPI Template",
      },
    ],
  }),
})

function Metrics() {
  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">Metrics</h1>
        <p className="text-muted-foreground">
          This is a stub metrics view for authorized roles.
        </p>
      </div>
      <div className="rounded-lg border bg-card p-6 text-card-foreground">
        <p className="text-sm text-muted-foreground">
          KPI charts and operational summaries will be added here in a future
          iteration.
        </p>
      </div>
    </div>
  )
}