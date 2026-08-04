# E-commerce Product Analytics: funnel, conversion and cohort retention
 
Product analysis of **2,103,521 real user events** from a multi-category online store (October 2019), written in PostgreSQL.
 
The headline result is not a conversion rate. It is that **the cart event in this dataset cannot be trusted**, and that most of the "insights" a funnel analysis would produce here are artefacts of that. This repo shows how that was established, and what can still be answered once it is accounted for.
 
Every query opens with the business question it answers and closes with the finding.
 
---
 
## Key findings
 
**1. The cart event is broken, and the data proves it is instrumentation rather than behaviour.**
The session funnel returns a cart→purchase rate of **108.6%**, more sessions purchase than add to cart. Rather than report it, I tested whether user behaviour or event recording was responsible, by comparing two ratios week over week:
 
| Week | Carts / views | Purchases / views |
|---|---|---|
| Sep 30 | 2.31% | 1.84% |
| Oct 07 | 1.57% | 1.80% |
| Oct 14 | **3.08%** | 1.94% |
| Oct 21 | 2.75% | 1.82% |
| Oct 28 | 1.58% | 1.67% |
 
Purchases per view are flat all month (1.67–1.94%). Carts per view **double** between weeks 2 and 3 while views stay flat (476,875 → 488,735). Real behavioural change would move both ratios together; only one moves. The cart event is unstable, the funnel is not.
 
**2. 43 of 126 categories record exactly zero carts, and still record purchases.**
Not few carts. Zero, across **112,543 product views and 530 purchases**. Apparel is the clearest case: **21 of its 22 categories record no cart event at all**, and the twenty-second records two. Any category-level "cart abandonment" conclusion drawn here would be a product conclusion about a tracking defect. This is why the cart→purchase rate is excluded from every recommendation below.

*A note on process: my first read of the category-conversion query was a product conclusion, that apparel converted poorly because of weak offering or a page-level issue. Segmenting the funnel by category showed the real cause: 21 of 22 apparel categories never fire a cart event at all. I keep the original wrong hypothesis in the query comments rather than deleting it, because a low conversion rate can be a genuine product problem or a measurement problem, and the two don't look different until you check the event that sits between them.*
 
**3. One category is the store, and the global funnel hides it.**
Splitting viewing sessions three ways:
 
| Group | Viewing sessions | Share | View→cart |
|---|---|---|---|
| Rest of catalogue | 237,675 | 42.3% | 3.70% |
| No category recorded | 169,489 | 30.2% | 2.06% |
| `electronics.smartphone` | 154,453 | 27.5% | **10.99%** |
 
One category takes over a quarter of all traffic and converts at roughly **3x the rest of the catalogue**. The store-wide 6.26% view→cart rate is a weighted average of a dominant product line and everything else, and describes neither. A further 30.2% of activity carries no `category_code` at all, so close to 60% of traffic is either one product or unclassified.
 
**4. Cohort retention declines across cohorts, but far less than the raw curve suggests.**
 
| Cohort | Wk 1 | Wk 2 | Wk 3 | Wk 4 |
|---|---|---|---|---|
| Sep 30 | 35.9% | 32.2% | 27.7% | 17.3% |
| Oct 07 | 27.2% | 21.8% | 12.5% | — |
| Oct 14 | 22.5% | 11.3% | — | — |
| Oct 21 | 12.2% | — | — | — |
 
Read naively, week-1 retention collapses from 35.9% to 12.2% and acquisition quality is deteriorating. Both endpoints are censored:
 
- **Left censoring.** The first cohort is not a cohort of new users. The dataset starts there, so every pre-existing customer active that week is misclassified as new. Established users retain better, which inflates 35.9% by construction.
- **Right censoring.** The Oct 21 cohort's week 1 runs Oct 28–Nov 3, but the data ends Oct 31, four of seven days observed. 12.2% is depressed by construction.
The only clean comparison is between the two fully observed middle cohorts: **27.2% vs 22.5%**. The decline is real but is roughly five points, not twenty-four.
 
---
 
## Recommendations
 
1. **Fix the cart event before optimising anything downstream.** 43 categories with zero carts is not an analysis finding, it is a tracking defect. Every conversion metric, funnel dashboard and abandonment campaign built on this event inherits it. This is the only recommendation that should be actioned before the others.
2. **Report conversion per category, never globally.** With one category taking 27.5% of all viewing sessions and converting at roughly 3x the rest, the store-wide rate is a smartphone rate wearing a store-wide label. Segmenting is what makes every other category's performance visible at all.
3. **Target view→cart, not checkout.** Of the two funnel steps, only view→cart is measurable here, and it is where the volume is lost: 6.26% of viewing sessions show purchase intent. The testable hypothesis is on the product page (assortment, price visibility, page performance), measured on view→cart rate in a single category where the cart event is known to fire.
4. **Do not use week-1 cohort retention as a KPI in this window.** With one month of data, both the earliest and latest cohorts are censored in opposite directions. Any target set against this curve would be measuring the observation window, not the product.
---
 
## Further analysis
 
These five extend the analysis to product concentration, purchase timing, repeat-purchase behaviour and user activity concentration, and one of them adds direct evidence to the cart-instrumentation problem in finding 1.
 
**5. Median time to purchase is a fraction of the average, the same skew this repo keeps finding.**
 
Among the 31,149 sessions that record both a view and a purchase, the average time from first view to purchase is **7.3 minutes**, while the median is **3.0 minutes**. The gap points to a tail of long-deliberation sessions pulling the mean upward; for a metric meant to describe "how long before someone buys," the median is the number to act on, not the average.
 
**6. Product concentration varies sharply by category, and the store's largest category is not its most concentrated one.**
 
| Category | Top product | Share of category purchases |
|---|---|---|
| `electronics.audio.headphone` | 4804056 | 38.3% (589 of 1,536) |
| `auto.accessories.parktronic` | 18800010 | 80.0% (4 of 5) |
| `electronics.smartphone` | 1004856 | — (below 10% threshold) |
 
`electronics.smartphone` has the single best-selling product in the dataset (1,497 units, more than double the second-place product store-wide), yet **no smartphone product reaches 10% of its own category's purchases**. The category is large and evenly split across many products. `electronics.audio.headphone`, with roughly a third of smartphone's purchase volume, has one product taking over a third of the category. Scale and concentration are independent: the biggest category is not the one with the clearest best-seller.
 
Separately, **13 of 106 purchased categories don't have enough distinct products sold to fill a top 3**, mostly low-volume categories with one or two products carrying all purchases.
 
**7. Cart abandonment at the session level surfaces the same instrumentation problem as finding 1, at individual-session scale.**
 
| Session (truncated) | Cart adds, no purchase |
|---|---|
| `1978995d…` | 118 |
| `65114a7d…` | 82 |
| `5cb14eb7…` | 54 |
 
The leading session adds 118 items to cart without a single purchase. No plausible browsing session generates that; this reads as the same event-recording defect identified in finding 1, now visible in a single session rather than an aggregate. It does not change the conclusion: the cart event should not be trusted until fixed. It does show the defect is inspectable at the individual-session level, which narrows where a fix should be looked for.
 
**8. Time between repeat purchases shows the same right-skew as time-to-purchase (finding 5).**

*A note on process: the first version of this query ranked the 20 fastest repeat-buyers by average gap and returned exactly 1 day for all twenty. Read on its own, that looks like a finding. It isn't one: an `ORDER BY` ascending on a per-user average, capped at `LIMIT 20`, will always surface the fastest users in the dataset, by construction, regardless of what the population looks like. The number that answers the actual question, "how fast do repeat-buyers typically come back", needed the population-wide average and median below, not the top of a sorted list.*
 
Among **4,567 users with two or more purchases**, the average gap between consecutive purchases is **6.1 days**, while the median is **4.4 days**. As with view-to-purchase time, the mean is pulled upward by a tail of slower repeat buyers; the median is the more representative figure for a "typical" repurchase window. This is descriptive only. With one month of data, "days between purchases" for users near the start or end of the window is necessarily undercounted, the same censoring problem as the cohort analysis in finding 4.

**9. Active-day streaks are extremely concentrated: the median user's longest streak is a single day, while the top 20 reach 16–29 consecutive days.**

| Metric | Value |
|---|---|
| Median longest streak (all users) | 1 day |
| Longest streak (top user) | 29 days |
| Top-20 streak range | 16–29 days |
| Purchased at least once during their streak (top 20) | 55% (11 of 20) |

Half the user base, at their most active point in the month, was never active on two consecutive days. The top 20 by streak length are a sharp outlier population, not a representative sample, and this is the clearest single expression of the concentration pattern already visible in findings 2 and 3 (zero-cart categories, one category carrying 27.5% of traffic). Within that outlier group, 55% purchased at least once during their streak, a purchase rate that (while not directly comparable, this is per-user, not per-view) sits well above the 1.67–1.94% weekly purchases-per-view figures in finding 1. Sustained activity is associated with purchase intent for roughly half this group; the other 45% stayed highly active without converting, which is a distinct question from the cart-instrumentation problem in finding 1, since these sessions may never have reached a cart step at all.

*Limitation: the top streak's start date (Sep 30) falls one day before the sampled month begins, consistent with the same left-censoring boundary effect noted in finding 4 — worth a one-line disclosure rather than treating it as a clean 29-day figure.*
 
---
 
## Business questions
 
1. Is the event data internally consistent enough to support a funnel analysis?
2. At which step of the funnel do we lose the most users, and does the answer change by category?
3. Which categories convert views into purchases efficiently, and which absorb traffic without returning revenue?
4. Do users come back after their first week, and how fast does the cohort curve decay?
5. Among sessions that both view and purchase, how long does that typically take, and does the average tell the same story as the median?
6. Does purchase volume concentrate in a few products within each category, or spread evenly, and does that pattern hold for the store's largest category?
7. Is the cart-instrumentation problem from finding 1 visible at the level of individual sessions, not just in aggregate weekly ratios?
8. Among users who purchase more than once, how much time typically passes between purchases?
9. Do the most consistently active users behave differently from the rest, and does that sustained activity translate into purchases?
---
 
## Data and methodology
 
**Source:** [eCommerce behavior data from a multi-category store](https://www.kaggle.com/datasets/mkechinov/ecommerce-behavior-data-from-multi-category-store) (Kaggle, open data).
**Period:** October 2019, one month.
**Scale after sampling:** 2,103,521 events · 150,357 users · 459,000 sessions.
**Event types:** `view`, `cart`, `remove_from_cart`, `purchase`.
 
### Sampling: users, not rows
 
The full month holds ~42M rows. I sampled it to roughly 5%, but **by user, not by row**:
 
```bash
awk -F',' 'NR==1 || ($8 % 100 < 5)' 2019-Oct.csv > sample.csv
```
 
This matters more than it looks. Random row sampling would keep a user's purchase while dropping the view that preceded it, silently breaking every funnel and cohort in the analysis. Sampling whole users keeps each selected user's full event history intact, so conversion rates and retention curves stay valid; only the population is smaller.
 
### Known limitations
 
Stated up front, because they change how the numbers should be read:
 
- **The cart event is unreliable** (finding 1). Cart→purchase is reported as evidence of the defect, never as a conversion rate.
- **Two units of analysis appear in this repo.** Queries using `COUNT(*) FILTER` count *events*; the funnel queries count *sessions* collapsed with `MAX(CASE WHEN ...)`. Figures are labelled accordingly and should not be compared across units: 112,543 view events in the zero-cart categories correspond to roughly 34,600 session-category pairs.
- **The per-category funnel groups by session *and* category.** A session browsing two categories is counted once in each, so category figures sum to 561,617 view-sessions against 458,901 actual sessions. The unit of analysis there is the session-category pair. This also means a session can show a purchase with no cart *in that category* while a cart exists under another, an effect distinct from the global defect above.
- **One month of data**, with both cohort endpoints censored as described in finding 4.
- **The first and last weeks are partial.** The first begins on Sep 30, before the month covered by the data; the last is cut off on Oct 31. Neither is comparable to a full week on volume.
- **30.2% of views carry no `category_code`**, excluded from category analysis. That bucket alone holds 7,756 purchases, so category-level analysis covers a minority of activity.
- **Timestamps are UTC** and the dataset carries no country information, so no local-time analysis is attempted and hour-of-day patterns are not interpreted as behaviour.
- Observational data. Nothing here establishes causality; the recommendations are hypotheses to test, not proven effects.
- **One streak's start date precedes the sampled month** (Sep 30, one day before Oct 1), the same boundary artefact as the first cohort in finding 4. Flagged, not corrected, since it affects one data point and the direction of the finding is unchanged.

---
 
## Analyses in `queries.sql`

- **Event volume and unique users by type and by week**: baseline activity, and the comparison that first surfaced the cart defect.
- **Weekly carts-per-view vs purchases-per-view**: the test that separates behavioural change from instrumentation failure.
- **Categories with zero cart events**: quantifies the defect, how many categories, how many views and purchases behind them.
- **View→purchase conversion by category**: conditional aggregation with `FILTER`, `NULLIF` against division by zero, and a `HAVING` traffic floor.
- **Top 3 products per category**: `ROW_NUMBER()` over `PARTITION BY category_code`, filtered in an outer query since window functions can't be referenced in the same `WHERE`.
- **Categories without enough products for a top 3**: a correlated subquery with `HAVING COUNT(DISTINCT product_id) < 3` to find categories where a top-3 ranking isn't meaningful.
- **View-to-first-purchase time, mean vs median**: `EXTRACT(EPOCH FROM ...)` for duration in minutes, `PERCENTILE_CONT` for the median.
- **Cart adds with no purchase, by session**: anti-join with `NOT EXISTS` at the session level, not the user level, to avoid conflating a single abandoned cart with a user who never purchased all month.
- **Product share within category**: `SUM() OVER (PARTITION BY category_code)` to get each product's percentage of category purchases without a self-join.
- **Fastest repeat-purchase users (naive read)**: `LAG()` over each user's purchase dates, ranked by shortest average gap, kept as the query that motivates the population-wide version below.
- **Days between repeat purchases, population-wide**: the same `LAG()` logic aggregated across all users with 2+ purchases, mean vs. median.
- **Weekly cohort retention**: chained CTEs assigning each user a cohort by first-activity week, then measuring active weeks against cohort size.
- **Session funnel: view → cart → purchase**: `MAX(CASE WHEN ...)` to collapse each session to one row before measuring drop-off.
- **Session funnel by category**: the same funnel segmented, which surfaced the zero-cart categories.
- **Category traffic concentration**: splits sessions into smartphone vs. rest of catalogue vs. uncategorised, using a window `SUM() OVER ()` to get each group's share of total traffic.
- **Longest run of consecutive active days per user**: gaps-and-islands technique (`ROW_NUMBER()` subtracted from the date) to group consecutive days, then `PERCENTILE_CONT` for the population median and a date-ranged join back to `events` to test purchase behaviour within each user's streak.

## Stack
 
PostgreSQL 16 (Docker) · SQL · DBeaver
*Python and pandas layer in progress; see roadmap.*
 
---
 
## Reproducing this
 
```bash
# 1. Start PostgreSQL
docker run --name pg-practica -e POSTGRES_PASSWORD=practica \
  -p 5432:5432 -d postgres:16
 
# 2. Sample the raw Kaggle file by user
awk -F',' 'NR==1 || ($8 % 100 < 5)' 2019-Oct.csv > sample.csv
```
 
```sql
CREATE TABLE events (
    event_time    TIMESTAMPTZ,
    event_type    TEXT,
    product_id    BIGINT,
    category_id   BIGINT,
    category_code TEXT,
    brand         TEXT,
    price         NUMERIC,
    user_id       BIGINT,
    user_session  TEXT
);
```
 
```bash
# 3. Load
docker cp sample.csv pg-practica:/tmp/sample.csv
docker exec -it pg-practica psql -U postgres \
  -c "\copy events FROM '/tmp/sample.csv' CSV HEADER;"
```
 
```sql
-- 4. Indexes (queries are painfully slow without these)
CREATE INDEX idx_events_user ON events(user_id);
CREATE INDEX idx_events_type ON events(event_type);
CREATE INDEX idx_events_time ON events(event_time);
CREATE INDEX idx_events_sess ON events(user_session);
```
 
---
 
## Roadmap
 
- Confirm whether sessions with abnormal cart-add counts (see finding 7) share a product-page template or traffic source
- Rebuild the funnel on the subset of categories where the cart event demonstrably fires
- Replicate the funnel and cohort analyses in pandas, comparing both approaches on the same questions
- Retention heatmap and funnel visualisations
- A/B test analysis on a separate dataset: proportion test, significance, and an explicit statement of what the result does **not** allow us to conclude
- Segment the 45% of high-streak users who never converted, and compare against the 55% who did
---
 
**Sebastián Silva Barraza**, Data & Product Analyst
[LinkedIn](https://www.linkedin.com/in/sebastiansilvab) · sebsilva95@gmail.com
