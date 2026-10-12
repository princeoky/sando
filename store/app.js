const PRODUCTS = [
  {
    id: "ember-vessel",
    name: "Ember Vessel",
    material: "Hand-coiled stoneware",
    category: "Ceramics",
    price: 185,
    image: "images/vessel.webp",
    imagePos: "65% center",
    badge: "Last 4",
    featured: true,
    stock: 4,
    description:
      "Coiled by hand from iron-rich clay and wood-fired for three days. The surface shows ash and flame, so no two vessels look alike. It holds dried stems well, or nothing at all.",
    details: { Dimensions: "H 24 cm · Ø 18 cm", Material: "Stoneware, unglazed exterior", Origin: "Made in Kyoto, Japan", Care: "Wipe clean; not watertight" },
  },
  {
    id: "rust-linen-throw",
    name: "Rust Linen Throw",
    material: "Stonewashed European flax",
    category: "Textiles",
    price: 140,
    image: "images/linen.webp",
    description:
      "Heavyweight linen, dyed with madder root and stonewashed until soft. It wrinkles easily and gets softer with every wash.",
    details: { Dimensions: "130 × 180 cm", Material: "100% linen, 280 gsm", Origin: "Woven in Lithuania", Care: "Machine wash cool, line dry" },
  },
  {
    id: "meander-candlestick",
    name: "Meander Candlestick",
    material: "Lost-wax cast bronze",
    category: "Lighting",
    price: 220,
    image: "images/candlestick.webp",
    badge: "New",
    description:
      "A sculptural holder cast in solid bronze using the lost-wax method. The hammered surface catches candlelight and will patina naturally over the years.",
    details: { Dimensions: "H 19 cm · W 11 cm", Material: "Solid bronze, hand-finished", Origin: "Cast in Pietrasanta, Italy", Care: "Polish with a soft cloth, or let it age" },
  },
  {
    id: "carved-oak-bowl",
    name: "Carved Oak Bowl",
    material: "Hand-carved English oak",
    category: "Tableware",
    price: 160,
    image: "images/bowl.webp",
    description:
      "Carved with an adze and gouge from a single piece of fallen oak, then finished with food-safe oil. The tool marks around the rim are left on purpose.",
    details: { Dimensions: "Ø 30 cm · H 11 cm", Material: "English oak, linseed oil finish", Origin: "Carved in Devon, England", Care: "Hand wash; re-oil seasonally" },
  },
  {
    id: "smoke-carafe",
    name: "Smoke Carafe",
    material: "Mouth-blown recycled glass",
    category: "Tableware",
    price: 78,
    image: "images/carafe.webp",
    description:
      "Mouth-blown from recycled glass with a soft smoke tint. Small bubbles and a thumb-pressed dimple mark each piece as hand-made. Holds a full bottle of wine, or water for the table.",
    details: { Dimensions: "H 22 cm · 1 L", Material: "Recycled soda-lime glass", Origin: "Blown in Oaxaca, Mexico", Care: "Hand wash recommended" },
  },
];

const FREE_SHIPPING = 200;
const SHIPPING_FEE = 15;
const CART_KEY = "ochre-cart";

const $ = (sel, el = document) => el.querySelector(sel);
const money = (n) => "$" + n.toFixed(2).replace(/\.00$/, "");
const byId = (id) => PRODUCTS.find((p) => p.id === id);
const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

/* ---------- Cart state ---------- */
let cart = loadCart();
let drawerView = "cart"; // cart | checkout | done

function loadCart() {
  try {
    const raw = JSON.parse(localStorage.getItem(CART_KEY)) || {};
    return Object.fromEntries(Object.entries(raw).filter(([id, q]) => byId(id) && q > 0));
  } catch {
    return {};
  }
}
function saveCart() {
  try { localStorage.setItem(CART_KEY, JSON.stringify(cart)); } catch {}
}
const maxQty = (p) => p.stock ?? 10;
const cartCount = () => Object.values(cart).reduce((a, b) => a + b, 0);
const subtotal = () => Object.entries(cart).reduce((s, [id, q]) => s + byId(id).price * q, 0);

function addToCart(id, qty = 1) {
  const p = byId(id);
  const next = Math.min((cart[id] || 0) + qty, maxQty(p));
  const added = next - (cart[id] || 0);
  if (added <= 0) return toast(`Only ${maxQty(p)} available for ${p.name}`);
  cart[id] = next;
  saveCart();
  renderCart();
  toast(`${p.name} added to your bag`);
  const badge = $("#cartCount");
  badge.classList.add("bump");
  setTimeout(() => badge.classList.remove("bump"), 250);
}
function setQty(id, qty) {
  if (qty <= 0) delete cart[id];
  else cart[id] = Math.min(qty, maxQty(byId(id)));
  saveCart();
  renderCart();
}

/* ---------- Product grid ---------- */
let activeFilter = "All";

function renderFilters() {
  const cats = ["All", ...new Set(PRODUCTS.map((p) => p.category))];
  $("#filters").innerHTML = cats
    .map((c) => `<button class="filter${c === activeFilter ? " active" : ""}" role="tab" aria-selected="${c === activeFilter}" data-filter="${c}">${c}</button>`)
    .join("");
}

function renderGrid() {
  const list = PRODUCTS.filter((p) => activeFilter === "All" || p.category === activeFilter);
  $("#productGrid").innerHTML = list
    .map(
      (p, i) => `
    <article class="card${p.featured && activeFilter === "All" ? " featured" : ""}" data-open="${p.id}" style="animation-delay:${i * 60}ms" tabindex="0" aria-label="${esc(p.name)}, ${money(p.price)}">
      <div class="card-media">
        <img src="${p.image}" alt="${esc(p.name)}" loading="lazy" style="object-position:${p.imagePos || "center"}">
        ${p.badge ? `<span class="badge">${p.badge}</span>` : ""}
        <button class="quick-add" data-add="${p.id}">Add to bag</button>
      </div>
      <div class="card-info">
        <div>
          <h3>${esc(p.name)}</h3>
          <p class="material">${esc(p.material)}</p>
        </div>
        <span class="price">${money(p.price)}</span>
      </div>
    </article>`
    )
    .join("");
}

function setFilter(cat) {
  activeFilter = cat;
  renderFilters();
  renderGrid();
}

/* ---------- Product modal ---------- */
const modal = $("#productModal");
let modalQty = 1;

function openProduct(id) {
  const p = byId(id);
  modalQty = 1;
  $("#pmBody").innerHTML = `
    <div class="pm-img"><img src="${p.image}" alt="${esc(p.name)}" style="object-position:${p.imagePos || "center"}"></div>
    <div class="pm-info">
      <p class="eyebrow">${p.category}</p>
      <h2 id="pmTitle">${esc(p.name)}</h2>
      <p class="pm-price">${money(p.price)}</p>
      <p class="pm-desc">${esc(p.description)}</p>
      <ul class="pm-details">
        ${Object.entries(p.details).map(([k, v]) => `<li><span>${k}</span><span>${esc(v)}</span></li>`).join("")}
      </ul>
      ${p.stock ? `<p class="pm-stock">Only ${p.stock} left in this firing</p>` : ""}
      <div class="pm-actions">
        <div class="qty" aria-label="Quantity">
          <button data-mqty="-1" aria-label="Decrease">−</button>
          <span id="mQty">1</span>
          <button data-mqty="1" aria-label="Increase">+</button>
        </div>
        <button class="btn btn-dark" data-madd="${p.id}">Add to bag · <span id="mTotal">${money(p.price)}</span></button>
      </div>
    </div>`;
  modal.dataset.id = id;
  modal.showModal();
  document.body.classList.add("locked");
}
function closeProduct() {
  modal.close();
}
modal.addEventListener("close", () => document.body.classList.remove("locked"));
modal.addEventListener("click", (e) => {
  if (e.target === modal || e.target.closest("[data-close]")) return closeProduct();
  const step = e.target.closest("[data-mqty]");
  if (step) {
    const p = byId(modal.dataset.id);
    modalQty = Math.max(1, Math.min(maxQty(p), modalQty + Number(step.dataset.mqty)));
    $("#mQty").textContent = modalQty;
    $("#mTotal").textContent = money(p.price * modalQty);
  }
  const add = e.target.closest("[data-madd]");
  if (add) {
    addToCart(add.dataset.madd, modalQty);
    closeProduct();
    openDrawer();
  }
});

/* ---------- Cart drawer ---------- */
const drawer = $("#cartDrawer");
const overlay = $("#overlay");

function openDrawer() {
  if (drawerView === "done") drawerView = "cart";
  renderCart();
  drawer.classList.add("open");
  drawer.setAttribute("aria-hidden", "false");
  overlay.hidden = false;
  document.body.classList.add("locked");
  $("#cartClose").focus();
}
function closeDrawer() {
  drawer.classList.remove("open");
  drawer.setAttribute("aria-hidden", "true");
  overlay.hidden = true;
  document.body.classList.remove("locked");
  if (drawerView === "checkout") drawerView = "cart";
}

function totalsHTML() {
  const sub = subtotal();
  const ship = sub >= FREE_SHIPPING || sub === 0 ? 0 : SHIPPING_FEE;
  return `
    <div class="totals">
      <div><span>Subtotal</span><span>${money(sub)}</span></div>
      <div><span>Shipping</span><span>${ship ? money(ship) : "Free"}</span></div>
      <div class="grand"><span>Total</span><span>${money(sub + ship)}</span></div>
    </div>`;
}

function renderCart() {
  const count = cartCount();
  $("#cartCount").textContent = count;
  const body = $("#drawerBody");
  const foot = $("#drawerFoot");

  if (drawerView === "done") return;

  if (!count) {
    drawerView = "cart";
    $("#drawerTitle").textContent = "Your bag";
    body.innerHTML = `
      <div class="empty">
        <h4>Your bag is empty</h4>
        <p>Start with something made by hand.</p>
        <button class="btn btn-dark" data-shop>Browse the collection</button>
      </div>`;
    foot.innerHTML = "";
    return;
  }

  if (drawerView === "checkout") return renderCheckout();

  $("#drawerTitle").textContent = `Your bag (${count})`;
  const sub = subtotal();
  const remaining = Math.max(0, FREE_SHIPPING - sub);
  body.innerHTML = `
    <div class="ship-bar">
      ${remaining ? `You're ${money(remaining)} away from free shipping` : "You've unlocked complimentary shipping"}
      <div class="track"><div class="fill" style="width:${Math.min(100, (sub / FREE_SHIPPING) * 100)}%"></div></div>
    </div>
    ${Object.entries(cart)
      .map(([id, q]) => {
        const p = byId(id);
        return `
        <div class="line">
          <img src="${p.image}" alt="${esc(p.name)}" style="object-position:${p.imagePos || "center"}">
          <div>
            <h4>${esc(p.name)}</h4>
            <p class="material">${esc(p.material)}</p>
            <div class="qty sm">
              <button data-qty="${id}" data-d="-1" aria-label="Decrease ${esc(p.name)}">−</button>
              <span>${q}</span>
              <button data-qty="${id}" data-d="1" aria-label="Increase ${esc(p.name)}" ${q >= maxQty(p) ? "disabled" : ""}>+</button>
            </div>
          </div>
          <div class="line-right">
            <span class="price">${money(p.price * q)}</span>
            <button class="remove" data-remove="${id}">Remove</button>
          </div>
        </div>`;
      })
      .join("")}`;
  foot.innerHTML = `${totalsHTML()}<button class="btn btn-dark btn-block" data-checkout>Checkout</button>`;
}

function renderCheckout() {
  $("#drawerTitle").textContent = "Checkout";
  $("#drawerBody").innerHTML = `
    <form class="checkout" id="checkoutForm" novalidate>
      <button type="button" class="back" data-back>← Back to bag</button>
      <h4>Contact</h4>
      <input name="email" type="email" placeholder="Email" autocomplete="email" required>
      <h4>Shipping address</h4>
      <div class="field-row">
        <input name="first" placeholder="First name" autocomplete="given-name" required>
        <input name="last" placeholder="Last name" autocomplete="family-name" required>
      </div>
      <input name="address" placeholder="Address" autocomplete="street-address" required>
      <div class="field-row">
        <input name="city" placeholder="City" autocomplete="address-level2" required>
        <input name="zip" placeholder="Postal code" autocomplete="postal-code" required>
      </div>
      <select name="country" autocomplete="country-name" required>
        <option value="">Country</option>
        <option>United States</option><option>Canada</option><option>United Kingdom</option>
        <option>Germany</option><option>France</option><option>Japan</option><option>Australia</option>
      </select>
      <p class="form-note" id="checkoutNote" aria-live="polite"></p>
    </form>`;
  $("#drawerFoot").innerHTML = `${totalsHTML()}
    <button class="btn btn-dark btn-block" type="submit" form="checkoutForm">Place order</button>
    <p class="demo-note">Demo store: no payment is taken.</p>`;
  $("#checkoutForm input").focus();
}

function placeOrder(form) {
  const missing = [...form.elements].filter((el) => el.required && !el.checkValidity());
  if (missing.length) {
    $("#checkoutNote").textContent = "Please complete all fields with a valid email.";
    missing[0].focus();
    return;
  }
  const data = Object.fromEntries(new FormData(form));
  const orderNo = "OC-" + Date.now().toString(36).toUpperCase().slice(-6);
  cart = {};
  saveCart();
  drawerView = "done";
  $("#cartCount").textContent = 0;
  $("#drawerTitle").textContent = "Thank you";
  $("#drawerBody").innerHTML = `
    <div class="confirm">
      <div class="mark">✓</div>
      <h4>Order received</h4>
      <p>Thank you, ${esc(data.first)}. A confirmation will be sent to ${esc(data.email)}.</p>
      <p>Your pieces will be wrapped by hand and shipped within 3–5 days.</p>
      <p class="order-no">Order ${orderNo}</p>
      <button class="btn btn-outline" data-close-drawer>Continue browsing</button>
    </div>`;
  $("#drawerFoot").innerHTML = "";
}

drawer.addEventListener("click", (e) => {
  const t = e.target;
  const q = t.closest("[data-qty]");
  if (q) return setQty(q.dataset.qty, (cart[q.dataset.qty] || 0) + Number(q.dataset.d));
  const r = t.closest("[data-remove]");
  if (r) return setQty(r.dataset.remove, 0);
  if (t.closest("[data-checkout]")) { drawerView = "checkout"; return renderCart(); }
  if (t.closest("[data-back]")) { drawerView = "cart"; return renderCart(); }
  if (t.closest("[data-shop]") || t.closest("[data-close-drawer]")) {
    drawerView = "cart";
    closeDrawer();
    $("#shop").scrollIntoView();
  }
});
drawer.addEventListener("submit", (e) => {
  e.preventDefault();
  placeOrder(e.target);
});

/* ---------- Global wiring ---------- */
$("#cartToggle").addEventListener("click", openDrawer);
$("#cartClose").addEventListener("click", closeDrawer);
overlay.addEventListener("click", closeDrawer);
document.addEventListener("keydown", (e) => {
  if (e.key === "Escape" && drawer.classList.contains("open")) closeDrawer();
});

$("#filters").addEventListener("click", (e) => {
  const b = e.target.closest("[data-filter]");
  if (b) setFilter(b.dataset.filter);
});

$("#productGrid").addEventListener("click", (e) => {
  const add = e.target.closest("[data-add]");
  if (add) { e.stopPropagation(); return addToCart(add.dataset.add); }
  const card = e.target.closest("[data-open]");
  if (card) openProduct(card.dataset.open);
});
$("#productGrid").addEventListener("keydown", (e) => {
  if (e.key !== "Enter" && e.key !== " ") return;
  const card = e.target.closest("[data-open]");
  if (card && e.target === card) { e.preventDefault(); openProduct(card.dataset.open); }
});

document.querySelectorAll("[data-filter-link]").forEach((a) =>
  a.addEventListener("click", () => setFilter(a.dataset.filterLink))
);

$("#newsForm").addEventListener("submit", (e) => {
  e.preventDefault();
  $("#newsNote").textContent = "Thank you. Your first letter is on its way.";
  e.target.reset();
});

let toastTimer;
function toast(msg) {
  const t = $("#toast");
  t.textContent = msg;
  t.classList.add("show");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => t.classList.remove("show"), 2400);
}

$("#year").textContent = new Date().getFullYear();
renderFilters();
renderGrid();
renderCart();
