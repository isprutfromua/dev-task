import type { PropsWithChildren, ReactNode } from "react"

import { type AppRole, hasRole } from "@/lib/rbac"

interface RoleGuardProps extends PropsWithChildren {
  userRole?: string | null
  requiredRoles: readonly AppRole[]
  fallback?: ReactNode
}

const RoleGuard = ({
  userRole,
  requiredRoles,
  fallback = null,
  children,
}: RoleGuardProps) => {
  if (!hasRole(userRole, requiredRoles)) {
    return <>{fallback}</>
  }

  return <>{children}</>
}

export default RoleGuard