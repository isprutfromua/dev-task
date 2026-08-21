export const APP_ROLES = ["admin", "manager", "member"] as const

export type AppRole = (typeof APP_ROLES)[number]

export const DEFAULT_ROLE: AppRole = "member"
export const ADMIN_ROLE: AppRole = "admin"

export const ROLE_LABELS: Record<AppRole, string> = {
  admin: "Admin",
  manager: "Manager",
  member: "Member",
}

export const APP_ROUTES = {
  forbidden: "/forbidden",
  metrics: "/metrics",
  users: "/admin",
} as const

export const USER_MANAGEMENT_ROLES: readonly AppRole[] = ["admin"]
export const METRICS_READ_ROLES: readonly AppRole[] = ["admin", "manager"]

export const normalizeRole = (role?: string | null): AppRole => {
  const candidate = (role ?? "") as AppRole
  if (APP_ROLES.includes(candidate)) {
    return candidate
  }
  return DEFAULT_ROLE
}

export const hasRole = (
  role: string | null | undefined,
  allowedRoles: readonly AppRole[],
) => allowedRoles.includes(normalizeRole(role))

export const canManageUsers = (role: string | null | undefined) =>
  hasRole(role, USER_MANAGEMENT_ROLES)

export const canReadMetrics = (role: string | null | undefined) =>
  hasRole(role, METRICS_READ_ROLES)