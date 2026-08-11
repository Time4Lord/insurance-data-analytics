/* Quick row counts for sanity checks */
select count(*) from customers;
select count(*) from policies;
select count(*) from claims;
select count(*) from payments;

--Question 1: Monthly written premium & approved claims by insurance_type
with wp as (select trunc(start_date, 'MM') as month_key, insurance_type, sum(premium_amount) as total_written_premium from policies group by trunc(start_date, 'MM'), insurance_type),
ac as (select trunc(c.claim_date, 'MM') as month_key, p.insurance_type, sum(c.approved_amount) as total_approved_claims from claims c
    join policies p on p.policy_id = c.policy_id group by trunc(c.claim_date, 'MM'), p.insurance_type)
select to_char(wp.month_key, 'YYYY-MM') as month_year, wp.insurance_type as insurance_type, wp.total_written_premium as total_written_premium, ac.total_approved_claims as total_approved_claims from wp
    join ac on wp.month_key = ac.month_key and wp.insurance_type = ac.insurance_type
    order by month_year, insurance_type;

--Question 2: Claim ratio by insurance_type
with premium as (select insurance_type, sum(premium_amount) as total_premium from policies  group by insurance_type),
claims_approved as (select p.insurance_type, sum(c.approved_amount) as total_approved from claims c 
    join policies p on p.policy_id = c.policy_id where c.claim_status = 'Approved' group by p.insurance_type)
select pr.insurance_type, cl.total_approved, pr.total_premium, round(cl.total_approved / pr.total_premium * 100, 2) as claim_ratio_percent from premium pr
    join claims_approved cl on pr.insurance_type = cl.insurance_type
    order by pr.insurance_type;

--Question 3: Customers with approved claims >= 80% of total premium in last 12 months
with prem as (select p.customer_id, sum(p.premium_amount) as total_premium_12m from policies p where p.start_date >= add_months(trunc(sysdate), -12) group by p.customer_id),
cl as (select p.customer_id, sum(c.approved_amount) as approved_12m from claims c 
    join policies p on p.policy_id = c.policy_id 
    where c.claim_status = 'Approved' and c.claim_date >= add_months(trunc(sysdate), -12) group by p.customer_id)
select cu.customer_id, cu.full_name, pr.total_premium_12m, cl.approved_12m, round(cl.approved_12m / pr.total_premium_12m * 100, 2) as claim_ratio_percent from prem pr
    join cl on cl.customer_id = pr.customer_id
    join customers cu on cu.customer_id = pr.customer_id
    where  (cl.approved_12m / pr.total_premium_12m) >= 0.80
    order by claim_ratio_percent desc;


--Question 4: Claim frequency & average severity by region
with policy_cnt as (select c.region, count(distinct p.policy_id) as total_policies from customers c join policies p on p.customer_id = c.customer_id group by c.region),
claim_stats as (select c.region, count(*) as total_claims, round(avg(cl.approved_amount),2) as avg_severity from claims cl
    join policies p on p.policy_id = cl.policy_id
    join customers c on c.customer_id = p.customer_id
    where cl.claim_status = 'Approved'
    group by c.region)
select pc.region, cs.total_claims, pc.total_policies, round((cs.total_claims / pc.total_policies),2) as claim_frequency, cs.avg_severity from policy_cnt pc
    left join claim_stats cs on cs.region = pc.region
    order by pc.region;

--Question 5: Early claims (within 30 days of policy start)
select c.claim_id, c.policy_id, p.customer_id, c.claim_date, p.start_date, (c.claim_date - p.start_date) as days_after_start,
    c.claim_amount, c.approved_amount, c.claim_status, c.claim_reason from claims c
    join policies p on p.policy_id = c.policy_id
    where (c.claim_date - p.start_date) <= 30 and (c.claim_date - p.start_date) >= 0
    order by p.customer_id, c.claim_date;

--Question 6: Renewal rate per month = renewed_policies / expired_policies
with e as (select trunc(end_date, 'MM') as month_key, count(*) as expired_policies from policies where upper(trim(status)) = 'EXPIRED' group by trunc(end_date, 'MM')),
r as ( select trunc(start_date, 'MM') as month_key, count(*) as renewed_policies from policies where upper(trim(status)) = 'RENEWED' group by trunc(start_date, 'MM'))
select to_char(e.month_key, 'YYYY-MM') as month_year, e.expired_policies, r.renewed_policies, round((r.renewed_policies / e.expired_policies) * 100, 2) as renewal_rate_percent from e
    left join r on r.month_key = e.month_key
    order by month_year;

--Question 7: Rank brokers by average claim ratio (only > 20 policies)
select p.broker_name, count(distinct p.policy_id) as policy_count, round(sum(c.approved_amount) / sum(p.premium_amount) * 100, 2) as avg_claim_ratio_percent,
    rank() over (order by sum(c.approved_amount) / sum(p.premium_amount) desc) as broker_rank from policies p
    join claims c on p.policy_id = c.policy_id 
    where c.claim_status = 'Approved' and p.broker_name is not null
    group by p.broker_name
    having count(distinct p.policy_id) > 20
    order by avg_claim_ratio_percent desc;

--Question 8: Avg premium & claim ratio by gender and insurance_type
with claims_per_policy as (select policy_id, sum(approved_amount) as approved_sum from claims where claim_status = 'Approved' group by policy_id),
base as ( select cu.gender, p.insurance_type, p.premium_amount, cp.approved_sum from policies p
    join customers cu on cu.customer_id = p.customer_id
    left join claims_per_policy cp on cp.policy_id = p.policy_id)
select gender, insurance_type, round(avg(premium_amount), 2) as avg_premium, round(sum(approved_sum) / sum(premium_amount) * 100, 2) as claim_ratio_percent from base
    group by gender, insurance_type
    order by gender, insurance_type;


--Question 9: Top 10 customers by total approved claim amount
with claims_per_customer as (select p.customer_id, sum(c.approved_amount) as total_approved from claims c 
    join policies p on p.policy_id = c.policy_id where c.claim_status = 'Approved' group by p.customer_id),
policy_stats as (select customer_id, count(distinct policy_id) as policy_count, avg(premium_amount) as avg_premium from policies group by customer_id)
select cu.customer_id, cu.full_name, cu.region, ps.policy_count, round(ps.avg_premium, 2) as avg_premium, round(cc.total_approved, 2) as total_approved from claims_per_customer cc
    join customers cu on cu.customer_id = cc.customer_id
    join policy_stats ps on ps.customer_id = cc.customer_id
    order by cc.total_approved desc
    fetch first 10 rows only;


--Question 10: Policies with no payments OR any overdue payments
select p.policy_id, p.customer_id, p.insurance_type, p.start_date from policies p
    left join payments pay on p.policy_id = pay.policy_id
    group by p.policy_id, p.customer_id, p.insurance_type, p.start_date
    having count(pay.payment_id) = 0 or min(pay.is_overdue) = 1;


















