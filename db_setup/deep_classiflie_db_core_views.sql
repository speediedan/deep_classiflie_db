create or replace view falsehoods as
WITH
all_wp as
(select statement_text as stext, if(source='Twitter',1,0) as s_type, s_date as sdate, wc as swc from wp_statements),
cume_dist_wc as
(select distinct swc,
CUME_DIST() over (ORDER BY swc) as "cume dist"
from all_wp),
desired_range as
(select cd.swc from cume_dist_wc cd where cd."cume dist" between 0.03 and 0.995 order by cd.swc),
bounds as
(select min(dr.swc) as minb, max(dr.swc) as maxb
from desired_range dr)
select wp.stext as statement_text, wp.s_type, wp.sdate as s_date, 'False' from all_wp wp, bounds where wp.swc between bounds.minb and bounds.maxb order by wp.sdate, wp.stext;
create or replace view truths as
WITH
all_truths as
(select s.statement_text as stext, 0 as s_type, t.t_date as sdate, s.wc as swc from fbase_statements s, fbase_transcripts t where s.tid=t.tid
union all
select statement_text as stext, 1 as s_type, t_end_date as sdate, wc as swc from dcbot_tweets where retweet=0 and t_end_date <
(select max(s_date) from wp_statements where wc between 7 and 107)),
cume_dist_wc as
(select distinct swc,
CUME_DIST() over (ORDER BY swc) as "cume dist"
from all_truths),
desired_range as
(select cd.swc from cume_dist_wc cd where cd."cume dist" between 0.13 and 0.995 order by cd.swc),
bounds as
(select min(dr.swc) as minb, max(dr.swc) as maxb
from desired_range dr)
select fb.stext as statement_text, fb.s_type as s_type, 'True' from all_truths fb, bounds where fb.swc between bounds.minb and bounds.maxb order by fb.sdate, fb.stext;
create or replace view falsehoods_tiny as
WITH
all_wp as
(select statement_text as stext, if(source='Twitter',1,0) as s_type, s_date as sdate,
wc as swc from wp_statements),
cume_dist_wc as
(select distinct swc,
CUME_DIST() over (ORDER BY swc) as "cume dist"
from all_wp),
desired_range as
(select cd.swc from cume_dist_wc cd where cd."cume dist" between 0.03 and 0.995 order by cd.swc),
bounds as
(select min(dr.swc) as minb, max(dr.swc) as maxb
from desired_range dr)
select wp.stext as statement_text, wp.s_type, wp.sdate as s_date, 'False' as label from all_wp wp, bounds where wp.swc between bounds.minb and bounds.maxb order by wp.sdate, wp.stext limit 1000;
create or replace view truths_tiny as
WITH
all_truths_tiny as
(select s.statement_text as stext, 0 as s_type, t.t_date as sdate, s.wc as swc from fbase_statements s, fbase_transcripts t
where s.tid=t.tid and t.t_date >= STR_TO_DATE('2017-01-19','%Y-%m-%d')
union all
select statement_text as stext, 1 as s_type, t_end_date as sdate, wc as swc from dcbot_tweets where retweet=0 and t_end_date <
(select max(s_date) from wp_statements where wc between 7 and 107))
select fb.stext as statement_text, fb.s_type as s_type, 'True' as label, fb.sdate as s_date from all_truths_tiny fb limit 10000;
SET sql_mode='ANSI';
create or replace view all_truth_statements_tmp_v as
select ''||s.tid||'***'||s.sid||'' as truth_id, s.statement_text as stext, 0 as stype, t.t_date as sdate, s.wc as swc
from fbase_statements s, fbase_transcripts t where
s.tid=t.tid
and s.wc between 7 and 107
and t.t_date between STR_TO_DATE('2017-01-19','%Y-%m-%d') and (select max(s_date) from wp_statements where wc between 7 and 107)
union all
select ''||thread_id||'***'||end_thread_tweet_id||'' as truth_id, statement_text as stext, 1 as stype, t_end_date as sdate, wc as swc
from dcbot_tweets where
retweet=0
and wc between 7 and 107
and t_end_date between STR_TO_DATE('2017-01-19','%Y-%m-%d') and (select max(s_date) from wp_statements where wc between 7 and 107);
SET sql_mode='ANSI';
drop table if exists all_truth_statements_tmp;
CREATE TABLE all_truth_statements_tmp as select * from all_truth_statements_tmp_v;
create or replace view target_dist as
-- union of tweets and fbase statements
-- manually analyzed the relevant class distributions to determine the appropriate bounds,
-- not worth the effort to automate at this point
-- uses all_statement_truths_tmp table of filtered truths
with
src_cnts as
(select
distinct(wc) dwc,
count(*) over (partition by wc) "dwc_cnt",
count(*) over () "tot_cnt"
from wp_statements wp
where wc between 7 and 107),
target_cnts as
(select
distinct(swc) dwc,
count(*) over (partition by swc) "dwc_cnt",
count(*) over () "tot_cnt"
from all_truth_statements_tmp fb
where swc between 7 and 107),
xformed_dist as
(select src_cnts.dwc as "wc",
src_cnts.dwc_cnt as "src_wc_cnt",
target_cnts.dwc_cnt as "target_wc_cnt",
target_cnts.tot_cnt as "target_tot_cnt",
src_cnts.dwc_cnt/src_cnts.tot_cnt "src_wc_prob"
from src_cnts, target_cnts where src_cnts.dwc=target_cnts.dwc)
select xformed_dist.wc, xformed_dist.src_wc_prob as "xformed_wc_cnt",
sum(round(xformed_dist.target_tot_cnt*xformed_dist.src_wc_prob)) over () "xformed_dist_size" from xformed_dist order by wc;
create or replace view pt_converged_dt_falsehoods as
select statement_text, if(source='Twitter',1,0) as s_type, 'False' as label, s_date from wp_statements where wc between 7 and 107 order by s_date;
create or replace view pt_converged_dt_truths as
select statement_text, stype as s_type, 'True' as label, sdate as s_date from pt_converged_truths order by sdate;
create or replace view falsehood_date_driver as
select s_date,
cume_dist() over (order by s_date) as c_dist
from pt_converged_dt_falsehoods;
create or replace view falsehood_date_driver_tiny as
select s_date,
cume_dist() over (order by s_date) as c_dist
from falsehoods_tiny;
create or replace view fbase_twitter_wp_dups as
-- delete fbase and tweet "truth" statements whose sha1 hash exists in the falsehoods table
-- subsequent removal of "truth" statements that are the same statement but whose surrounding text change the hash will be detected
-- later in the data cleansing stream using more sophisticated sentence similarity measures
with all_fbase_hashes as
(select tid, sid, sha1(lower(statement_text)) t_hash from fbase_statements where wc between 7 and 107
union all
select 'none',thread_id, sha1(lower(statement_text)) t_hash from dcbot_tweets where wc between 7 and 107),
falsehood_hashes AS
(select sid, sha1(lower(statement_text)) f_hash from wp_statements)
select th.tid tid, th.sid sid from all_fbase_hashes th, falsehood_hashes fh where th.t_hash=fh.f_hash;
create or replace view dc_model_dist_based_filter_vw as
-- bucket and analyze candidate "false truths" to set appropriate threshold, 0.02 is somewhat surprisingly robust,
-- about an order of magnitude away from producing a false positive/negative
with l2buckets as
(select l2dist, ntile(100) over (order by l2dist) as buckets from false_truth_del_cands)
select distinct(truth_id) from
false_truth_del_cands ftc where
ftc.l2dist < 0.02;
create or replace view base_model_dist_based_filter_vw as
-- note, based upon manual annotation of filtered false truths, the 0.04 threshold appears to match falsehoods to their corresponding truths with substantially > 50% accuracy.
-- This fuzzy matching process will result in a modest upward performance bias in the test results (the precise magnitifued of this bias will be quantified once I or someone have
-- sufficient resources/bandwidth to precisely remove duplicates...or as a proxy, when the next set of ground truth label data are released by the washington post).
with l2buckets as
(select l2dist, ntile(100) over (order by l2dist) as buckets from base_false_truth_del_cands)
select distinct(truth_id) from
base_false_truth_del_cands ftc where
ftc.l2dist < 0.04;
create or replace view latest_ds_summary as
with ds_meta_summary as
(select train_start_date, train_end_date, val_start_date, val_end_date, test_start_date, test_end_date from ds_metadata where dsid = (select max(dsid) from ds_metadata where ds_type='converged_filtered')),
train_truths as
(select count(*) as train_truths from pt_converged_dt_truths pt, ds_meta_summary ds where pt.s_date BETWEEN ds.train_start_date and ds.train_end_date),
train_falsehoods as
(select count(*) as train_falsehoods from pt_converged_dt_falsehoods pt, ds_meta_summary ds where pt.s_date BETWEEN ds.train_start_date and ds.train_end_date),
val_truths as
(select count(*) as val_truths from pt_converged_dt_truths pt, ds_meta_summary ds where pt.s_date BETWEEN ds.val_start_date and ds.val_end_date),
val_falsehoods as
(select count(*) as val_falsehoods from pt_converged_dt_falsehoods pt, ds_meta_summary ds where pt.s_date BETWEEN ds.val_start_date and ds.val_end_date),
test_truths as
(select count(*) as test_truths from pt_converged_dt_truths pt, ds_meta_summary ds where pt.s_date BETWEEN ds.test_start_date and ds.test_end_date),
test_falsehoods as
(select count(*) as test_falsehoods from pt_converged_dt_falsehoods pt, ds_meta_summary ds where pt.s_date BETWEEN ds.test_start_date and ds.test_end_date)
select train_truths, train_falsehoods, val_truths, val_falsehoods, test_truths, test_falsehoods from train_truths, train_falsehoods, val_truths, val_falsehoods, test_truths, test_falsehoods;
