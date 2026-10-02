from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from starlette.exceptions import HTTPException as StarletteHTTPException
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError

from app.core.config import settings
from app.core.logging import configure_logging
from app.db.session import SessionLocal
from app.dependencies.auth import get_current_user_optional
from app.routers import additional_work_types, additional_works, billing, clients, connections, expenses, finance, legal, materials, mobile_sync, pages, providers, reports, settings as settings_router


def create_app() -> FastAPI:
    configure_logging()

    application = FastAPI(
        title=settings.app_name,
        debug=settings.app_debug,
    )
    application.mount("/static", StaticFiles(directory="app/static"), name="static")
    application.include_router(additional_work_types.router)
    application.include_router(billing.router)
    application.include_router(additional_works.router)
    application.include_router(clients.router)
    application.include_router(connections.router)
    application.include_router(expenses.router)
    application.include_router(finance.router)
    application.include_router(materials.router)
    application.include_router(legal.router)
    application.include_router(mobile_sync.router)
    application.include_router(providers.router)
    application.include_router(reports.router)
    application.include_router(settings_router.router)
    application.include_router(pages.router)

    templates = Jinja2Templates(directory="app/templates")

    @application.get("/health/live", response_class=JSONResponse)
    def health_live() -> dict:
        return {"status": "ok"}

    @application.get("/health/ready", response_class=JSONResponse)
    def health_ready() -> JSONResponse:
        """Report ready only when the configured database accepts a query."""
        db = SessionLocal()
        try:
            db.execute(text("SELECT 1"))
            return JSONResponse({"status": "ready"})
        except SQLAlchemyError:
            return JSONResponse({"status": "unavailable"}, status_code=503)
        finally:
            db.close()

    @application.get("/api/mobile/update", response_class=JSONResponse)
    async def mobile_update(request: Request) -> dict:
        release_tag = settings.android_release_tag.strip()
        download_url = settings.android_apk_download_url or (
            "https://github.com/magomedov1009/telecom-manager/releases/download/"
            f"{release_tag}/app-release.apk"
        )
        return {
            "tag_name": release_tag,
            "assets": [
                {
                    "name": "app-release.apk",
                    "browser_download_url": download_url,
                }
            ],
        }

    @application.exception_handler(404)
    async def not_found_handler(request: Request, exc: StarletteHTTPException) -> HTMLResponse:
        db = SessionLocal()
        try:
            user = get_current_user_optional(request, db)
        finally:
            db.close()
        return templates.TemplateResponse(
            request=request,
            name="errors/404.html",
            context={
                "app_name": settings.app_name,
                "nav_items": pages.NAV_ITEMS,
                "current_path": request.url.path,
                "user": user,
                "missing_path": request.url.path,
            },
            status_code=404,
        )

    @application.exception_handler(RequestValidationError)
    async def validation_exception_handler(request: Request, exc: RequestValidationError) -> HTMLResponse:
        db = SessionLocal()
        try:
            user = get_current_user_optional(request, db)
        finally:
            db.close()
        return templates.TemplateResponse(
            request=request,
            name="errors/404.html",
            context={
                "app_name": settings.app_name,
                "nav_items": pages.NAV_ITEMS,
                "current_path": request.url.path,
                "user": user,
                "missing_path": request.url.path,
            },
            status_code=404,
        )

    return application


app = create_app()
