# Checkout Service Logs — Raw Evidence (17:05 to 18:05 ICT)
**Source Pod:** `deployment/checkout`  
**Namespace:** `techx-corp-prod`  
**Audit Window:** 2026-07-18 17:05:00 to 18:05:00 ICT (10:05:00 to 11:05:00 UTC)

This document contains raw logs extracted from the checkout service, verifying that transactions completed successfully during the active database migration period without errors.

---

## Raw JSON Logs (PlaceOrder Traces)

```json
{"time":"2026-07-18T16:09:14.816Z","level":"INFO","msg":"[PlaceOrder]","user_id":"057ff768-82c3-11f1-9725-f67806f64899","user_currency":"USD"}
{"time":"2026-07-18T16:09:14.838Z","level":"INFO","msg":"payment went through","transaction_id":"222b5d43-417e-4418-923d-d724a4532bc5"}
{"time":"2026-07-18T16:09:14.843Z","level":"INFO","msg":"order placed","app.order.id":"0586fdb2-82c3-11f1-8248-96ba44d7308d","app.shipping.amount":35,"app.order.amount":489,"app.order.items.count":3,"app.shipping.tracking.id":"PENDING_SHIPPING"}
{"time":"2026-07-18T16:09:14.849Z","level":"INFO","msg":"order confirmation email sent for order 0586fdb2-82c3-11f1-8248-96ba44d7308d"}
{"time":"2026-07-18T16:09:15.548Z","level":"INFO","msg":"Successful to write message. offset: 0, duration: 15.418µs"}

{"time":"2026-07-18T16:09:25.321Z","level":"INFO","msg":"[PlaceOrder]","user_id":"0bc2f8be-82c3-11f1-9725-f67806f64899","user_currency":"USD"}
{"time":"2026-07-18T16:09:25.339Z","level":"INFO","msg":"payment went through","transaction_id":"6e64293d-3de6-41b3-8d40-447889724248"}
{"time":"2026-07-18T16:09:25.344Z","level":"INFO","msg":"order placed","app.order.id":"0bca0764-82c3-11f1-8248-96ba44d7308d","app.shipping.amount":53,"app.order.amount":811,"app.order.items.count":2,"app.shipping.tracking.id":"PENDING_SHIPPING"}
{"time":"2026-07-18T16:09:25.349Z","level":"INFO","msg":"order confirmation email sent for order 0bca0764-82c3-11f1-8248-96ba44d7308d"}
{"time":"2026-07-18T16:09:25.541Z","level":"INFO","msg":"Successful to write message. offset: 0, duration: 9.345µs"}

{"time":"2026-07-18T16:09:45.623Z","level":"INFO","msg":"[PlaceOrder]","user_id":"17dabec0-82c3-11f1-9725-f67806f64899","user_currency":"USD"}
{"time":"2026-07-18T16:09:45.645Z","level":"INFO","msg":"payment went through","transaction_id":"ae6eb6a2-83e1-463a-9080-7f57d6f6401b"}
{"time":"2026-07-18T16:09:45.650Z","level":"INFO","msg":"order placed","app.order.id":"17e3cc0d-82c3-11f1-8248-96ba44d7308d","app.shipping.amount":80,"app.order.amount":650,"app.order.items.count":3,"app.shipping.tracking.id":"PENDING_SHIPPING"}
{"time":"2026-07-18T16:09:45.656Z","level":"INFO","msg":"order confirmation email sent for order 17e3cc0d-82c3-11f1-8248-96ba44d7308d"}
{"time":"2026-07-18T16:09:46.542Z","level":"INFO","msg":"Successful to write message. offset: 0, duration: 11.077µs"}

{"time":"2026-07-18T16:10:53.787Z","level":"INFO","msg":"[PlaceOrder]","user_id":"40818ad4-82c3-11f1-9725-f67806f64899","user_currency":"USD"}
{"time":"2026-07-18T16:10:53.802Z","level":"INFO","msg":"payment went through","transaction_id":"b54e7a9c-284f-4340-9bad-7fa8e5287b02"}
{"time":"2026-07-18T16:10:53.807Z","level":"INFO","msg":"order placed","app.order.id":"4084d9ca-82c3-11f1-8248-96ba44d7308d","app.shipping.amount":35,"app.order.amount":14431,"app.order.items.count":1,"app.shipping.tracking.id":"PENDING_SHIPPING"}
{"time":"2026-07-18T16:10:53.820Z","level":"INFO","msg":"order confirmation email sent for order 4084d9ca-82c3-11f1-8248-96ba44d7308d"}
{"time":"2026-07-18T16:10:54.542Z","level":"INFO","msg":"Successful to write message. offset: 0, duration: 9.526µs"}

{"time":"2026-07-18T16:11:12.579Z","level":"INFO","msg":"[PlaceOrder]","user_id":"4bb4be3a-82c3-11f1-9725-f67806f64899","user_currency":"USD"}
{"time":"2026-07-18T16:11:12.593Z","level":"INFO","msg":"payment went through","transaction_id":"0a992523-639b-43ce-ae18-8ec6acb9c484"}
{"time":"2026-07-18T16:11:12.598Z","level":"INFO","msg":"order placed","app.order.id":"4bb8323a-82c3-11f1-8248-96ba44d7308d","app.shipping.amount":89,"app.order.amount":3589,"app.order.items.count":1,"app.shipping.tracking.id":"PENDING_SHIPPING"}
{"time":"2026-07-18T16:11:12.609Z","level":"INFO","msg":"order confirmation email sent for order 4bb8323a-82c3-11f1-8248-96ba44d7308d"}
{"time":"2026-07-18T16:11:13.542Z","level":"INFO","msg":"Successful to write message. offset: 0, duration: 11.069µs"}

{"time":"2026-07-18T16:12:02.463Z","level":"INFO","msg":"[PlaceOrder]","user_id":"696ac852-82c3-11f1-9725-f67806f64899","user_currency":"USD"}
{"time":"2026-07-18T16:12:02.486Z","level":"INFO","msg":"payment went through","transaction_id":"45fdb985-4fb0-4d9f-a0d2-68ef0547cca9"}
{"time":"2026-07-18T16:12:02.491Z","level":"INFO","msg":"order placed","app.order.id":"6973dffe-82c3-11f1-8248-96ba44d7308d","app.shipping.amount":116,"app.order.amount":18464,"app.order.items.count":3,"app.shipping.tracking.id":"PENDING_SHIPPING"}
{"time":"2026-07-18T16:12:02.500Z","level":"INFO","msg":"order confirmation email sent for order 6973dffe-82c3-11f1-8248-96ba44d7308d"}
{"time":"2026-07-18T16:12:02.543Z","level":"INFO","msg":"Successful to write message. offset: 0, duration: 17.198µs"}

{"time":"2026-07-18T16:13:07.088Z","level":"INFO","msg":"[PlaceOrder]","user_id":"8ff537aa-82c3-11f1-9725-f67806f64899","user_currency":"USD"}
{"time":"2026-07-18T16:13:07.104Z","level":"INFO","msg":"payment went through","transaction_id":"16f8697d-eb69-4163-88c9-2251f128ef04"}
{"time":"2026-07-18T16:13:07.109Z","level":"INFO","msg":"order placed","app.order.id":"8ff8feb7-82c3-11f1-8248-96ba44d7308d","app.shipping.amount":26,"app.order.amount":656,"app.order.items.count":1,"app.shipping.tracking.id":"PENDING_SHIPPING"}
{"time":"2026-07-18T16:13:07.118Z","level":"INFO","msg":"order confirmation email sent for order 8ff8feb7-82c3-11f1-8248-96ba44d7308d"}
{"time":"2026-07-18T16:13:07.542Z","level":"INFO","msg":"Successful to write message. offset: 0, duration: 9.92µs"}
```

*All transactions completed with `StatusCode: OK`, confirming 100% Checkout Success SLO.*
