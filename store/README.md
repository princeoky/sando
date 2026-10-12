# Ochre — storefront

Static e-commerce site for five handmade objects. No build step or dependencies.

```sh
cd store && python3 -m http.server 8000   # then open http://localhost:8000
```

- `index.html`: page structure (hero, collection, story, newsletter, footer, product modal, bag drawer)
- `styles.css`: all styling, responsive down to phone width
- `app.js`: product catalog (`PRODUCTS`), category filters, product detail, cart (saved in localStorage), checkout

Checkout is a demo: it validates the form and shows an order confirmation, but no payment is taken.
Connect a payment provider (e.g. Stripe Checkout or Shopify Buy Button) in `placeOrder()` to sell for real.
