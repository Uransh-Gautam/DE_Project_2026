# Problem Understanding

Instagram’s project database has no documented schema, and its teams report slow features, inaccurate counters, and reports that return incorrect results or time out. We need to rebuild the database from the provided exports, measure the given queries, and make them faster without changing their results.

| Problem | Need and affected stakeholder | Category |
|---|---|---|
| **P1 — Home feed and profile grid load slowly for users who follow many accounts.** | People need to see recent posts from followed accounts and a user’s posts quickly. **Stakeholders:** end users, feed team. | Customer-facing / real-time |
| **P2 — Post pages are slow on viral posts.** | People need comments and reply counts, the list of likers, and an accurate like-button state without delay. **Stakeholders:** end users, post-page team. | Customer-facing / real-time |
| **P3 — Explore and search are too slow for type-ahead.** | People need quick results for hashtags, places, and accounts as they search. **Stakeholders:** end users, explore/search teams. | Customer-facing / real-time |
| **P4 — Suggested accounts and follow-request screens lag.** | People need relevant account suggestions and quick access to pending requests, including requests to private accounts. **Stakeholders:** end users, social-graph team. | Customer-facing / real-time |
| **P5 — Creators need engagement, ghost-follower, follow-back, and reels reports.** | Creators need to understand their audience and content performance. **Stakeholders:** creators. | Reporting / analytics |
| **P6 — “Comments without replies” shows no results.** | Creators need to find comments that have not received a reply. **Stakeholder:** creator. | Reporting / analytics |
| **P7 — Profile counters can be wrong and the nightly recount is slow.** | Stored follower and like counts need to match the underlying activity. **Stakeholders:** users, data-quality team. | Reporting / analytics (recount and checking); customer-facing / real-time (displayed profile counters) |
| **P8 — Stories and moderation tools are slow.** | People need story highlights and insights; trust and safety staff need to review hidden comments and clean up expired stories. **Stakeholders:** end users, creators, trust & safety team. | Customer-facing / real-time (highlights); reporting / analytics (insights); operational moderation/cleanup |
| **P9 — Content reports time out and engagement may grow 20×.** | The analytics team needs timely post, comment, like, and story reports that can handle expected growth. **Stakeholders:** growth analytics, business accounts/creators. | Reporting / analytics |

## Assumptions

- Customer-facing / real-time means a person is waiting for the result while using Instagram. Reports and aggregate checks are reporting / analytics; scheduled counter updates and cleanup are background operations.
- Some problems cover more than one type of work, so P7 and P8 are split by activity rather than forced into one category.
- The 20× engagement growth is an estimate stated in the brief, not a forecast made by our team.
- We will preserve the results of the supplied workload queries when optimizing them. Counts shown on profiles should agree with the accepted follows, likes, and comments represented in the data.
