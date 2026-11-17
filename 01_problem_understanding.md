# Problem Understanding

MakeMyTrip’s current database is hard to use: flight and hotel searches are slow, booking and payment actions lag, and several partner and business reports take too long or return incorrect results. We need to rebuild the database from the available data exports, then make the important queries faster without changing their results.

| Problem | Need and affected stakeholder | Category |
|---|---|---|
| **P1 — Flight search and fare calendar are slow; seats-left counts lag.** | Travellers need current flight options, fares, and seat availability. **Stakeholder:** traveller. | Customer-facing / real-time |
| **P2 — Hotel search and room availability checks are slow.** | Travellers need to filter hotels by amenities and find rooms for their dates. **Stakeholder:** traveller. | Customer-facing / real-time |
| **P3 — Trips, booking lookup, and sign-in lag.** | Customers need to see upcoming trips, find a booking, and sign in quickly. **Stakeholders:** traveller and customer support. | Customer-facing / real-time |
| **P4 — Airline manifests and performance reports are slow.** | Partners need passenger lists, low-load flight reports, and cancellation rates. **Stakeholder:** airline partner. | Reporting / analytics |
| **P5 — Checkout, payment confirmation, and cancellation slow down under load.** | Payments must be processed and booking status updated promptly. **Stakeholder:** payments team and traveller. | Customer-facing / real-time |
| **P6 — The unused-coupons report returns no results.** | The team needs to identify coupons that have not been used. **Stakeholder:** marketing. | Reporting / analytics |
| **P7 — City room-night reports and check-in updates need improvement.** | Partners need room-night totals by city; front-desk staff need to assign rooms quickly. **Stakeholders:** hotel partner and front desk. | Reporting / analytics (room-nights); customer-facing / real-time (check-in) |
| **P8 — Business reports time out and booking volume is expected to grow 20×.** | Teams need timely revenue, booking lead-time, repeat-customer, last-minute booking, route, and concession insights at larger scale. **Stakeholders:** finance, revenue management, and loyalty/insights teams. | Reporting / analytics |

## Assumptions

- “Customer-facing / real-time” covers searches and actions that a traveller, support agent, or front-desk worker needs while helping a customer.
- “Reporting / analytics” covers queries used to review trends, performance, or business activity rather than complete an individual booking action.
- P7 includes both categories because it combines an analytical room-night report with a real-time check-in update.
- The goal is to preserve the given queries’ results while improving their speed; reports should reflect the data currently stored in the database.
- The 20× growth in P8 is a planning estimate from the project brief.
