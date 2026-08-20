from fastapi import APIRouter, Depends

from app.api.deps import SessionDep, require_roles
from app.core.rbac import METRICS_READ_ROLES
from app.models import Message

router = APIRouter(prefix="/metrics", tags=["metrics"])


@router.get(
    "/",
    dependencies=[Depends(require_roles(*METRICS_READ_ROLES))],
    response_model=Message,
)
def read_metrics(_: SessionDep) -> Message:
    """
    Metrics endpoint stub protected by role-based access.
    """
    return Message(message="Metrics endpoint is available")