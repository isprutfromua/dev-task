import { createFileRoute } from "@tanstack/react-router"

import AccessDenied from "@/components/Common/AccessDenied"

export const Route = createFileRoute("/forbidden")({
  component: Forbidden,
  head: () => ({
    meta: [
      {
        title: "Access Denied - FastAPI Template",
      },
    ],
  }),
})

function Forbidden() {
  return <AccessDenied />
}