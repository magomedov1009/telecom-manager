from typing import Annotated

from fastapi import APIRouter, Depends, Request, status
from fastapi.responses import HTMLResponse, RedirectResponse, Response
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.dependencies.auth import can_access_web_application, get_current_user_optional
from app.models.fiber_work import FiberWorkLog
from app.models.users import User
from app.routers.pages import render

router = APIRouter()


@router.get("/fiber-works", response_class=HTMLResponse)
def fiber_works_page(
    request: Request,
    db: Annotated[Session, Depends(get_db)],
    user: Annotated[User | None, Depends(get_current_user_optional)],
) -> Response:
    if user is None:
        return RedirectResponse("/login", status_code=status.HTTP_303_SEE_OTHER)
    if not can_access_web_application(db, user.id):
        return RedirectResponse("/dashboard", status_code=status.HTTP_303_SEE_OTHER)
    logs = list(db.scalars(
        select(FiberWorkLog)
        .where(FiberWorkLog.owner_user_id == user.id)
        .order_by(FiberWorkLog.work_date.desc(), FiberWorkLog.id.desc())
    ))
    return render(
        request,
        "fiber_works/index.html",
        {
            "user": user,
            "logs": logs,
            "total_meters": sum(
                float(span.get("length_m", 0) or 0)
                for log in logs
                for span in (log.cable_spans or [])
            ),
            "total_splices": sum(len(log.splices or []) for log in logs),
        },
    )
