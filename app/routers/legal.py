from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates

from app.core.config import settings


router = APIRouter(tags=["legal"])
templates = Jinja2Templates(directory="app/templates")


@router.get("/privacy-policy", response_class=HTMLResponse)
def privacy_policy(request: Request) -> HTMLResponse:
    return templates.TemplateResponse(
        request=request,
        name="legal/privacy_policy.html",
        context={"app_name": settings.app_name, "support_email": settings.support_email},
    )


@router.get("/account-deletion", response_class=HTMLResponse)
def account_deletion(request: Request) -> HTMLResponse:
    return templates.TemplateResponse(
        request=request,
        name="legal/account_deletion.html",
        context={"app_name": settings.app_name, "support_email": settings.support_email},
    )
