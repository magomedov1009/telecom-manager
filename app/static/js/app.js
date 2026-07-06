document.addEventListener("htmx:configRequest", (event) => {
  event.detail.headers["X-Requested-With"] = "XMLHttpRequest";
});

document.addEventListener("htmx:afterSwap", (event) => {
  if (!["materials-module", "finance-module", "connections-module"].includes(event.detail.target.id)) {
    return;
  }

  document.querySelectorAll(".modal-backdrop").forEach((backdrop) => backdrop.remove());
  document.body.classList.remove("modal-open");
  document.body.style.removeProperty("overflow");
  document.body.style.removeProperty("padding-right");
});
