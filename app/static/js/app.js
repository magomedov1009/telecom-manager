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


// UI/UX Sprint 1 helpers
(function () {
  var root = document.body;
  var toggle = document.getElementById("tm-sidebar-toggle");
  if (localStorage.getItem("tm-sidebar-collapsed") === "1") {
    root.classList.add("tm-sidebar-collapsed");
  }
  if (toggle) {
    toggle.addEventListener("click", function () {
      root.classList.toggle("tm-sidebar-collapsed");
      localStorage.setItem("tm-sidebar-collapsed", root.classList.contains("tm-sidebar-collapsed") ? "1" : "0");
    });
  }

  document.addEventListener("submit", function (event) {
    var form = event.target;
    if (!(form instanceof HTMLFormElement)) return;
    form.classList.add("is-submitting");
    var button = form.querySelector('button[type="submit"], button:not([type])');
    if (button && !button.querySelector(".tm-submit-spinner")) {
      var spinner = document.createElement("span");
      spinner.className = "spinner-border spinner-border-sm tm-submit-spinner d-none ms-1";
      spinner.setAttribute("aria-hidden", "true");
      button.appendChild(spinner);
    }
  });

  document.addEventListener("htmx:afterRequest", function () {
    document.querySelectorAll("form.is-submitting").forEach(function (form) {
      form.classList.remove("is-submitting");
    });
  });
})();
