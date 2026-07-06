from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.core.config import settings
from app.core.logging import configure_logging
from app.db.session import SessionLocal
from app.dependencies.auth import get_current_user_optional
from app.routers import connections, finance, materials, pages


def create_app() -> FastAPI:
    configure_logging()

    application = FastAPI(
        title=settings.app_name,
        debug=settings.app_debug,
    )
    application.mount("/static", StaticFiles(directory="app/static"), name="static")
    application.include_router(connections.router)
    application.include_router(finance.router)
    application.include_router(materials.router)
    application.include_router(pages.router)

    templates = Jinja2Templates(directory="app/templates")

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






