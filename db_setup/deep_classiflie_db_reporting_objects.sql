drop table if exists stmts_analyzed_published;
CREATE TABLE stmts_analyzed_published (
    dc_tid BIGINT NOT NULL COMMENT 'dc published tweet id',
    tid VARCHAR(100) NOT NULL COMMENT 'source transcript id, ',
    sid INT NOT NULL COMMENT 'source statement id, ',
    arc_report_name varchar(80) NOT NULL COMMENT 'name of archived report image',
    media_id BIGINT NOT NULL COMMENT 'tweet media id',
	t_date TIMESTAMP NOT NULL DEFAULT 0 COMMENT 'published timestamp',
	PRIMARY KEY (dc_tid),
	CONSTRAINT stmts_analyzed_published_FK FOREIGN KEY (tid,sid) REFERENCES fbase_statements(tid,sid) ON DELETE CASCADE
)
ENGINE=InnoDB
DEFAULT CHARSET=utf8mb4
COLLATE=utf8mb4_unicode_ci
COMMENT='history of analyzed stmts published by deep_classiflie bot';
drop table if exists tweets_analyzed_published;
CREATE TABLE tweets_analyzed_published (
    dc_tid BIGINT NOT NULL COMMENT 'dc published tweet id',
    thread_id BIGINT NOT NULL COMMENT 'source tweet thread id',
    arc_report_name varchar(80) NOT NULL COMMENT 'name of archived report image',
    media_id BIGINT NOT NULL COMMENT 'tweet media id',
	t_date TIMESTAMP NOT NULL DEFAULT 0 COMMENT 'published timestamp',
	PRIMARY KEY (dc_tid),
	CONSTRAINT tweets_analyzed_published_FK FOREIGN KEY (thread_id) REFERENCES dcbot_tweets(thread_id) ON DELETE CASCADE
)
ENGINE=InnoDB
DEFAULT CHARSET=utf8mb4
COLLATE=utf8mb4_unicode_ci
COMMENT='history of analyzed tweets published by deep_classiflie bot';
drop table if exists stmts_analyzed_notpublished;
CREATE TABLE stmts_analyzed_notpublished (
    tid VARCHAR(100) NOT NULL COMMENT 'source transcript id, ',
    sid INT(11) NOT NULL COMMENT 'source statement id, ',
    arc_report_name varchar(80) NOT NULL COMMENT 'name of archived report image',
	t_date TIMESTAMP NOT NULL DEFAULT 0 COMMENT 'analysis timestamp',
	CONSTRAINT stmts_analyzed_notpublished_FK FOREIGN KEY (tid,sid) REFERENCES fbase_statements(tid,sid) ON DELETE CASCADE
)
ENGINE=InnoDB
DEFAULT CHARSET=utf8mb4
COLLATE=utf8mb4_unicode_ci
COMMENT='history of analyzed stmts but not published by deep_classiflie bot';
drop table if exists tweets_analyzed_notpublished;
CREATE TABLE tweets_analyzed_notpublished (
    thread_id BIGINT NOT NULL COMMENT 'source tweet thread id',
    arc_report_name varchar(80) NOT NULL COMMENT 'name of archived report image',
	t_date TIMESTAMP NOT NULL DEFAULT 0 COMMENT 'analysis timestamp',
	CONSTRAINT tweets_analyzed_notpublished_FK FOREIGN KEY (thread_id) REFERENCES dcbot_tweets(thread_id) ON DELETE CASCADE
)
ENGINE=InnoDB
DEFAULT CHARSET=utf8mb4
COLLATE=utf8mb4_unicode_ci
COMMENT='history of analyzed tweets but not published by deep_classiflie bot';
create or replace view tweetbot_stmts_to_analyze as
with latest_analyzed_dt as
(select max(tdate) max_date from
(select max(t.t_date) tdate from stmts_analyzed_published sap, fbase_statements s, fbase_transcripts t where t.tid=s.tid and sap.tid=s.tid and sap.sid=s.sid
union
select max(t.t_date) tdate from stmts_analyzed_notpublished sap, fbase_statements s, fbase_transcripts t where t.tid=s.tid and sap.tid=s.tid and sap.sid=s.sid) pubd),
analyzed_ids as
(select tid, sid from (select sap.tid as tid, sap.sid as sid from stmts_analyzed_published sap, fbase_statements s, fbase_transcripts t, latest_analyzed_dt ldt
where t.tid=s.tid and sap.tid=s.tid and sap.sid=s.sid and t.t_date >= ldt.max_date) pub
union
select tid, sid from (select sap.tid as tid, sap.sid as sid from stmts_analyzed_notpublished sap, fbase_statements s, fbase_transcripts t, latest_analyzed_dt ldt
where t.tid=s.tid and sap.tid=s.tid and sap.sid=s.sid and t.t_date >= ldt.max_date) notpub)
select s.tid, s.sid, s.statement_text, 0 as stype
from fbase_transcripts t, fbase_statements s, latest_analyzed_dt ldt
where t.tid=s.tid and wc between 7 and 107
and t.t_date >= ldt.max_date
and (s.tid, s.sid) not in (select * from analyzed_ids);
create or replace view tweetbot_tweets_to_analyze as
with curr_max_thread as
(select max(thread_id) maxt from
(select max(thread_id) thread_id from tweets_analyzed_published
union
select max(thread_id) thread_id from tweets_analyzed_notpublished) aa)
select thread_id, end_thread_tweet_id as tweet_id, statement_text, 1 as stype from dcbot_tweets, curr_max_thread where retweet=0
and wc between 7 and 107 and thread_id > curr_max_thread.maxt;
create or replace view all_current_mcc as
with test_data_filter as
(select * from model_analysis_rpts where model_version in (select max(model_version) from model_analysis_rpts where report_type='model_rpt_gt')
and report_type='model_rpt_gt'
and sdate between (select test_start_date from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1) and (select test_end_date from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1)),
confusion_matrix as
(select sum(tp) as tp, sum(tn) as tn, sum(fp) as fp, sum(fn) as fn from test_data_filter)
select ((cm.tp*cm.tn)-(cm.fp*cm.fn))/SQRT((cm.tp+cm.fp)*(cm.tp+cm.fn)*(cm.tn+cm.fp)*(cm.tn + cm.fn)) as mcc,
tp/(tp+fp+tn+fn) as tp_ratio,
tn/(tp+fp+tn+fn) as tn_ratio,
fp/(tp+fp+tn+fn) as fp_ratio,
fn/(tp+fp+tn+fn) as fn_ratio
from confusion_matrix cm;
create or replace view tweet_current_mcc as
with test_data_filter as
(select * from model_analysis_rpts where model_version in (select max(model_version) from model_analysis_rpts where report_type='model_rpt_gt')
and report_type='model_rpt_gt'
and stype=1
and sdate between (select test_start_date from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1) and (select test_end_date from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1)),
confusion_matrix as
(select sum(tp) as tp, sum(tn) as tn, sum(fp) as fp, sum(fn) as fn from test_data_filter)
select ((cm.tp*cm.tn)-(cm.fp*cm.fn))/SQRT((cm.tp+cm.fp)*(cm.tp+cm.fn)*(cm.tn+cm.fp)*(cm.tn + cm.fn)) as mcc,
tp/(tp+fp+tn+fn) as tp_ratio,
tn/(tp+fp+tn+fn) as tn_ratio,
fp/(tp+fp+tn+fn) as fp_ratio,
fn/(tp+fp+tn+fn) as fn_ratio
from confusion_matrix cm;
create or replace view nontweet_current_mcc as
with test_data_filter as
(select * from model_analysis_rpts where model_version in (select max(model_version) from model_analysis_rpts where report_type='model_rpt_gt')
and report_type='model_rpt_gt'
and stype=0
and sdate between (select test_start_date from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1) and (select test_end_date from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1)),
confusion_matrix as
(select sum(tp) as tp, sum(tn) as tn, sum(fp) as fp, sum(fn) as fn from test_data_filter)
select ((cm.tp*cm.tn)-(cm.fp*cm.fn))/SQRT((cm.tp+cm.fp)*(cm.tp+cm.fn)*(cm.tn+cm.fp)*(cm.tn + cm.fn)) as mcc,
tp/(tp+fp+tn+fn) as tp_ratio,
tn/(tp+fp+tn+fn) as tn_ratio,
fp/(tp+fp+tn+fn) as fp_ratio,
fn/(tp+fp+tn+fn) as fn_ratio
from confusion_matrix cm;
create or replace view auc_all as
with test_data_filter as
(select * from model_analysis_rpts where
model_version in (select max(model_version) from model_analysis_rpts where report_type='model_rpt_gt')
and report_type='model_rpt_gt'
and sdate between
(select test_start_date from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1)
and
(select test_end_date from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1)
),
positives as
(select
raw_pred as pred_pos
from test_data_filter where label=1
order by rand()),
negatives as
(select
raw_pred as pred_neg
from test_data_filter where label=0
order by rand())
select
avg(case
when p.pred_pos > n.pred_neg then 1
when p.pred_pos = n.pred_neg then 0.5
else 0 end) as est_auc
from positives p cross join negatives n;
create or replace view auc_nontweets as
with test_data_filter as
(select * from model_analysis_rpts where
model_version in (select max(model_version) from model_analysis_rpts where report_type='model_rpt_gt')
and report_type='model_rpt_gt' and stype=0
and sdate between
(select test_start_date from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1)
and
(select test_end_date from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1)
),
positives as
(select
raw_pred as pred_pos
from test_data_filter where label=1
order by rand()),
negatives as
(select
raw_pred as pred_neg
from test_data_filter where label=0
order by rand())
select
avg(case
when p.pred_pos > n.pred_neg then 1
when p.pred_pos = n.pred_neg then 0.5
else 0 end) as est_auc
from positives p cross join negatives n;
create or replace view auc_tweets as
with test_data_filter as
(select * from model_analysis_rpts where
model_version in (select max(model_version) from model_analysis_rpts where report_type='model_rpt_gt')
and report_type='model_rpt_gt' and stype=1
and sdate between
(select test_start_date from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1)
and
(select test_end_date from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1)
),
positives as
(select
raw_pred as pred_pos
from test_data_filter where label=1
order by rand()),
negatives as
(select
raw_pred as pred_neg
from test_data_filter where label=0
order by rand())
select
avg(case
when p.pred_pos > n.pred_neg then 1
when p.pred_pos = n.pred_neg then 0.5
else 0 end) as est_auc
from positives p cross join negatives n;
create or replace view nontweet_model_accuracy_lookup_cache as
with test_data_filter as
(select * from model_analysis_rpts where
model_version in (select max(model_version) from model_analysis_rpts where report_type='model_rpt_gt')
and report_type='model_rpt_gt'
and stype=0
and sdate between
(select test_start_date from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1)
and
(select test_end_date from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1)
),
confidence_correct as
(select
model_version,
fp,fn,tp,tn,
statement_id as sid,
if(label=prediction,1,0) correct_incorrect,
if(raw_pred>=0.5,raw_pred,1-raw_pred) as confidence
from test_data_filter),
confidence_buckets as
(select
model_version,
fp,fn,tp,tn,
sid,
correct_incorrect,
avg(correct_incorrect) over () as global_acc,
confidence,
ntile(25)  over (order by confidence) as conf_bucket
from confidence_correct)
select
max(confidence) as max_confidence,
model_version,
round(avg(correct_incorrect),4) as bucket_acc,
round(global_acc,2) as acc,
round(est_auc,2) as auc,
round(mcc,2) as mcc,
ifnull(round(sum(tp)/sum(tp+fp), 3), 0) as ppv,
ifnull(round(sum(tn)/sum(tn+fn), 3),0) as npv,
round(sum(tp+fp)/sum(fp+fn+tn+tp), 3) as ppr,
1-round(sum(tp+fp)/sum(fp+fn+tn+tp), 3) as npr,
round(sum(tp)/sum(fp+fn+tn+tp),3) as tp_ratio,
round(sum(tn)/sum(fp+fn+tn+tp),3) as tn_ratio,
round(sum(fp)/sum(fp+fn+tn+tp),3) as fp_ratio,
round(sum(fn)/sum(fp+fn+tn+tp),3) as fn_ratio,
date_bounds.test_start_date,
date_bounds.test_end_date
from confidence_buckets, nontweet_current_mcc, auc_nontweets,
(select test_start_date, test_end_date from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1) date_bounds
group by conf_bucket, global_acc
order by conf_bucket;
create or replace view tweet_model_accuracy_lookup_cache as
with test_data_filter as
(select * from model_analysis_rpts where
model_version in (select max(model_version) from model_analysis_rpts where report_type='model_rpt_gt')
and report_type='model_rpt_gt'
and stype=1
and sdate between
(select test_start_date from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1)
and
(select test_end_date from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1)
),
confidence_correct as
(select
model_version,
fp,fn,tp,tn,
statement_id as sid,
if(label=prediction,1,0) correct_incorrect,
if(raw_pred>=0.5,raw_pred,1-raw_pred) as confidence
from test_data_filter),
confidence_buckets as
(select
model_version,
fp,fn,tp,tn,
sid,
correct_incorrect,
avg(correct_incorrect) over () as global_acc,
confidence,
ntile(10)  over (order by confidence) as conf_bucket
from confidence_correct)
select
max(confidence) as max_confidence,
model_version,
round(avg(correct_incorrect),4) as bucket_acc,
round(global_acc,2) as acc,
round(est_auc,2) as auc,
round(mcc,2) as mcc,
ifnull(round(sum(tp)/sum(tp+fp), 3), 0) as ppv,
ifnull(round(sum(tn)/sum(tn+fn), 3),0) as npv,
round(sum(tp+fp)/sum(fp+fn+tn+tp), 3) as ppr,
1-round(sum(tp+fp)/sum(fp+fn+tn+tp), 3) as npr,
round(sum(tp)/sum(fp+fn+tn+tp),3) as tp_ratio,
round(sum(tn)/sum(fp+fn+tn+tp),3) as tn_ratio,
round(sum(fp)/sum(fp+fn+tn+tp),3) as fp_ratio,
round(sum(fn)/sum(fp+fn+tn+tp),3) as fn_ratio,
date_bounds.test_start_date,
date_bounds.test_end_date
from confidence_buckets, tweet_current_mcc, auc_tweets, (select test_start_date, test_end_date from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1) date_bounds
group by conf_bucket, global_acc
order by conf_bucket;
create or replace view tweet_model_accuracy_summ as
with test_data_filter as
(select * from model_analysis_rpts where
model_version in (select max(model_version) from model_analysis_rpts where report_type='model_rpt_gt')
and report_type='model_rpt_gt'
and stype=1
and sdate between
(select test_start_date from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1)
and
(select test_end_date from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1)
),
confidence_correct as
(select
model_version,
statement_id as sid,
if(label=prediction,1,0) correct_incorrect,
if(raw_pred>=0.5,raw_pred,1-raw_pred) as confidence
from test_data_filter),
confidence_buckets as
(select model_version, sid, correct_incorrect,
avg(correct_incorrect) over () as global_acc,
confidence,
ntile(10)  over (order by confidence) as conf_bucket
from confidence_correct)
select
max(confidence) as max_confidence,
model_version,
avg(correct_incorrect) as bucket_acc,
round(global_acc,2) as acc,
round(est_auc,2) as auc,
round(mcc,2) as mcc,
round(tp_ratio,2) as tp_ratio,
round(tn_ratio,2) as tn_ratio,
round(fp_ratio,2) as fp_ratio,
round(fn_ratio,2) as fn_ratio,
date_bounds.test_start_date,
date_bounds.test_end_date
from confidence_buckets, tweet_current_mcc, auc_tweets,
(select test_start_date, test_end_date from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1) date_bounds
group by conf_bucket, global_acc
order by conf_bucket;
create or replace view nontweet_model_accuracy_summ as
with test_data_filter as
(select * from model_analysis_rpts where
model_version in (select max(model_version) from model_analysis_rpts where report_type='model_rpt_gt')
and report_type='model_rpt_gt'
and stype=0
and sdate between
(select test_start_date from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1)
and
(select test_end_date from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1)
),
confidence_correct as
(select
model_version,
statement_id as sid,
if(label=prediction,1,0) correct_incorrect,
if(raw_pred>=0.5,raw_pred,1-raw_pred) as confidence
from test_data_filter),
confidence_buckets as
(select model_version, sid, correct_incorrect,
avg(correct_incorrect) over () as global_acc,
confidence,
ntile(25)  over (order by confidence) as conf_bucket
from confidence_correct)
select
max(confidence) as max_confidence,
model_version,
avg(correct_incorrect) as bucket_acc,
round(global_acc,2) as acc,
round(est_auc,2) as auc,
round(mcc,2) as mcc,
round(tp_ratio,2) as tp_ratio,
round(tn_ratio,2) as tn_ratio,
round(fp_ratio,2) as fp_ratio,
round(fn_ratio,2) as fn_ratio,
date_bounds.test_start_date,
date_bounds.test_end_date
from confidence_buckets, nontweet_current_mcc, auc_nontweets,
(select test_start_date, test_end_date from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1) date_bounds
group by conf_bucket, global_acc
order by conf_bucket;
create or replace view all_model_accuracy_summ as
with test_data_filter as
(select * from model_analysis_rpts where
model_version in (select max(model_version) from model_analysis_rpts where report_type='model_rpt_gt')
and report_type='model_rpt_gt'
and sdate between
(select test_start_date from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1)
and
(select test_end_date from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1)
),
confidence_correct as
(select
model_version,
statement_id as sid,
if(label=prediction,1,0) correct_incorrect,
if(raw_pred>=0.5,raw_pred,1-raw_pred) as confidence
from test_data_filter),
confidence_buckets as
(select model_version, sid, correct_incorrect,
avg(correct_incorrect) over () as global_acc,
confidence,
ntile(25)  over (order by confidence) as conf_bucket
from confidence_correct)
select
max(confidence) as max_confidence,
model_version,
avg(correct_incorrect) as bucket_acc,
round(global_acc,2) as acc,
round(est_auc,2) as auc,
round(mcc,2) as mcc,
round(tp_ratio,2) as tp_ratio,
round(tn_ratio,2) as tn_ratio,
round(fp_ratio,2) as fp_ratio,
round(fn_ratio,2) as fn_ratio,
date_bounds.test_start_date,
date_bounds.test_end_date
from confidence_buckets, all_current_mcc, auc_all,
(select test_start_date, test_end_date from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1) date_bounds
group by conf_bucket, global_acc
order by conf_bucket;
create or replace view global_model_accuracy_lookup_cache as
with
tweet_model_cache as
(select acc, auc, mcc, tp_ratio, tn_ratio, fp_ratio, fn_ratio from tweet_model_accuracy_summ ),
nontweet_model_cache as
(select acc, auc, mcc, tp_ratio, tn_ratio, fp_ratio, fn_ratio from nontweet_model_accuracy_summ ),
all_model_cache as
(select acc, auc, mcc, tp_ratio, tn_ratio, fp_ratio, fn_ratio from all_model_accuracy_summ )
select distinct
nontweet_model_cache.acc as nontweet_acc,
nontweet_model_cache.auc as nontweet_auc,
nontweet_model_cache.mcc as nontweet_mcc,
nontweet_model_cache.tp_ratio as nontweet_tp_ratio,
nontweet_model_cache.tn_ratio as nontweet_tn_ratio,
nontweet_model_cache.fp_ratio as nontweet_fp_ratio,
nontweet_model_cache.fn_ratio as nontweet_fn_ratio,
tweet_model_cache.acc as tweet_acc,
tweet_model_cache.auc as tweet_auc,
tweet_model_cache.mcc as tweet_mcc,
tweet_model_cache.tp_ratio as tweet_tp_ratio,
tweet_model_cache.tn_ratio as tweet_tn_ratio,
tweet_model_cache.fp_ratio as tweet_fp_ratio,
tweet_model_cache.fn_ratio as tweet_fn_ratio,
all_model_cache.acc as all_acc,
all_model_cache.auc as all_auc,
all_model_cache.mcc as all_mcc,
all_model_cache.tp_ratio as all_tp_ratio,
all_model_cache.tn_ratio as all_tn_ratio,
all_model_cache.fp_ratio as all_fp_ratio,
all_model_cache.fn_ratio as all_fn_ratio
from nontweet_model_cache, tweet_model_cache, all_model_cache;
create or replace view all_model_accuracy_lookup_cache as
with test_data_filter as
(select * from model_analysis_rpts where
model_version in (select max(model_version) from model_analysis_rpts where report_type='model_rpt_gt')
and report_type='model_rpt_gt'
and sdate between
(select test_start_date from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1)
and
(select test_end_date from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1)
),
confidence_correct as
(select
model_version,
fp,fn,tp,tn,
statement_id as sid,
if(label=prediction,1,0) correct_incorrect,
if(raw_pred>=0.5,raw_pred,1-raw_pred) as confidence
from test_data_filter),
confidence_buckets as
(select
model_version,
fp,fn,tp,tn,
sid,
correct_incorrect,
avg(correct_incorrect) over () as global_acc,
confidence,
ntile(25)  over (order by confidence) as conf_bucket
from confidence_correct)
select
max(confidence) as max_confidence,
model_version,
round(avg(correct_incorrect),4) as bucket_acc,
round(global_acc,2) as acc,
round(est_auc,2) as auc,
round(mcc,2) as mcc,
ifnull(round(sum(tp)/sum(tp+fp), 3), 0) as ppv,
ifnull(round(sum(tn)/sum(tn+fn), 3),0) as npv,
round(sum(tp+fp)/sum(fp+fn+tn+tp), 3) as ppr,
1-round(sum(tp+fp)/sum(fp+fn+tn+tp), 3) as npr,
round(sum(tp)/sum(fp+fn+tn+tp),3) as tp_ratio,
round(sum(tn)/sum(fp+fn+tn+tp),3) as tn_ratio,
round(sum(fp)/sum(fp+fn+tn+tp),3) as fp_ratio,
round(sum(fn)/sum(fp+fn+tn+tp),3) as fn_ratio,
date_bounds.test_start_date,
date_bounds.test_end_date
from confidence_buckets, all_current_mcc, auc_all,
(select test_start_date, test_end_date from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1) date_bounds
group by conf_bucket, global_acc
order by conf_bucket;
create or replace view model_rpt_gt as
select sdate, stext, stype, 'True' as label from all_truth_statements_tmp where sdate between (select min(s_date) from wp_statements where wc between 7 and 107)  and
(select max(s_date) from wp_statements where wc between 7 and 107)
union all
select s_date as sdate, statement_text, if(source='Twitter',1,0) as stype, 'False' as label from wp_statements where wc between 7 and 107
order by sdate;
create or replace view gt_all_rpt as
with
yweek_tots as
(select str_to_date(concat(yearweek(sdate,2),'0'), '%X%V%w') as yweeks,
count(*) over (partition by yweeks) as tot_yweek_preds,
sum(tp) over (partition by yweeks) as yweek_tp,
sum(tn) over (partition by yweeks) as yweek_tn,
sum(fp) over (partition by yweeks) as yweek_fp,
sum(fn) over (partition by yweeks) as yweek_fn
from model_analysis_rpts
where model_version = (select max(model_version) from model_analysis_rpts where report_type='model_rpt_gt')
and report_type='model_rpt_gt')
select distinct yweeks, yweek_tp/tot_yweek_preds as tp_ratio,
yweek_tn/tot_yweek_preds as tn_ratio,
yweek_fp/tot_yweek_preds as fp_ratio,
yweek_fn/tot_yweek_preds as fn_ratio
from yweek_tots;
create or replace view gt_tweets_rpt as
with
yweek_tots as
(select str_to_date(concat(yearweek(sdate,2),'0'), '%X%V%w') as yweeks,
count(*) over (partition by yweeks) as tot_yweek_preds,
sum(tp) over (partition by yweeks) as yweek_tp,
sum(tn) over (partition by yweeks) as yweek_tn,
sum(fp) over (partition by yweeks) as yweek_fp,
sum(fn) over (partition by yweeks) as yweek_fn
from model_analysis_rpts
where model_version = (select max(model_version) from model_analysis_rpts where report_type='model_rpt_gt')
and report_type='model_rpt_gt' and stype=1)
select distinct yweeks, yweek_tp/tot_yweek_preds as tp_ratio,
yweek_tn/tot_yweek_preds as tn_ratio,
yweek_fp/tot_yweek_preds as fp_ratio,
yweek_fn/tot_yweek_preds as fn_ratio
from yweek_tots;
create or replace view gt_nontweets_rpt as
with
yweek_tots as
(select str_to_date(concat(yearweek(sdate,2),'0'), '%X%V%w') as yweeks,
count(*) over (partition by yweeks) as tot_yweek_preds,
sum(tp) over (partition by yweeks) as yweek_tp,
sum(tn) over (partition by yweeks) as yweek_tn,
sum(fp) over (partition by yweeks) as yweek_fp,
sum(fn) over (partition by yweeks) as yweek_fn
from model_analysis_rpts
where model_version = (select max(model_version) from model_analysis_rpts where report_type='model_rpt_gt')
and report_type='model_rpt_gt' and stype=0)
select distinct yweeks, yweek_tp/tot_yweek_preds as tp_ratio,
yweek_tn/tot_yweek_preds as tn_ratio,
yweek_fp/tot_yweek_preds as fp_ratio,
yweek_fn/tot_yweek_preds as fn_ratio
from yweek_tots;
create or replace view cmatrix_test_all as
with
yweek_tots as
(select str_to_date(concat(yearweek(sdate,2),'0'), '%X%V%w') as yweeks,
count(*) over (partition by yweeks) as tot_yweek_preds,
sum(tp) over (partition by yweeks) as yweek_tp,
sum(tn) over (partition by yweeks) as yweek_tn,
sum(fp) over (partition by yweeks) as yweek_fp,
sum(fn) over (partition by yweeks) as yweek_fn
from model_analysis_rpts
where model_version = (select max(model_version) from model_analysis_rpts where report_type='model_rpt_gt')
and report_type='model_rpt_gt'
and sdate between
(select test_start_date from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1)
and
(select test_end_date from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1)
)
select distinct yweeks, yweek_tp/tot_yweek_preds as tp_ratio,
yweek_tn/tot_yweek_preds as tn_ratio,
yweek_fp/tot_yweek_preds as fp_ratio,
yweek_fn/tot_yweek_preds as fn_ratio
from yweek_tots;
create or replace view cmatrix_test_tweets as
with
yweek_tots as
(select str_to_date(concat(yearweek(sdate,2),'0'), '%X%V%w') as yweeks,
count(*) over (partition by yweeks) as tot_yweek_preds,
sum(tp) over (partition by yweeks) as yweek_tp,
sum(tn) over (partition by yweeks) as yweek_tn,
sum(fp) over (partition by yweeks) as yweek_fp,
sum(fn) over (partition by yweeks) as yweek_fn
from model_analysis_rpts
where model_version = (select max(model_version) from model_analysis_rpts where report_type='model_rpt_gt')
and report_type='model_rpt_gt' and stype=1
and sdate between
(select test_start_date from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1)
and
(select test_end_date from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1)
)
select distinct yweeks, yweek_tp/tot_yweek_preds as tp_ratio,
yweek_tn/tot_yweek_preds as tn_ratio,
yweek_fp/tot_yweek_preds as fp_ratio,
yweek_fn/tot_yweek_preds as fn_ratio
from yweek_tots;
create or replace view cmatrix_test_nontweets as
with
yweek_tots as
(select str_to_date(concat(yearweek(sdate,2),'0'), '%X%V%w') as yweeks,
count(*) over (partition by yweeks) as tot_yweek_preds,
sum(tp) over (partition by yweeks) as yweek_tp,
sum(tn) over (partition by yweeks) as yweek_tn,
sum(fp) over (partition by yweeks) as yweek_fp,
sum(fn) over (partition by yweeks) as yweek_fn
from model_analysis_rpts
where model_version = (select max(model_version) from model_analysis_rpts where report_type='model_rpt_gt')
and report_type='model_rpt_gt' and stype=0
and sdate between
(select test_start_date from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1)
and
(select test_end_date from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1)
)
select distinct yweeks, yweek_tp/tot_yweek_preds as tp_ratio,
yweek_tn/tot_yweek_preds as tn_ratio,
yweek_fp/tot_yweek_preds as fp_ratio,
yweek_fn/tot_yweek_preds as fn_ratio
from yweek_tots;
create or replace view cmatrix_test_conf_all as
with test_data_filter as
(select * from model_analysis_rpts where
model_version in (select max(model_version) from model_analysis_rpts where report_type='model_rpt_gt')
and report_type='model_rpt_gt'
and sdate between
(select test_start_date from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1)
and
(select test_end_date from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1)
),
confidence_correct as
(select
fp,fn,tp,tn,
(length(statement_text)-length(replace(statement_text,' ',''))+1) as wc,
if(label=prediction,1,0) correct_incorrect,
if(raw_pred>=0.5,raw_pred,1-raw_pred) as confidence
from test_data_filter),
confidence_buckets as
(select
ntile(25)  over (order by confidence) as confidence_bucket,
wc,
fp,fn,tp,tn,
correct_incorrect,
confidence
from confidence_correct)
select
confidence_bucket,
round(confidence_bucket*0.04, 3) as max_conf_percentile,
round(avg(wc)) as avg_wc,
round(sum(fp)/sum(fp+fn+tn+tp),3) as fp_ratio,
round(sum(fn)/sum(fp+fn+tn+tp),3) as fn_ratio,
round(sum(tn)/sum(fp+fn+tn+tp),3) as tn_ratio,
round(sum(tp)/sum(fp+fn+tn+tp),3) as tp_ratio,
round(avg(correct_incorrect),3) as acc,
round(avg(confidence),3) as confidence,
round(avg(correct_incorrect) - avg(confidence),3) acc_conf_delta
from confidence_buckets
group by confidence_bucket
order by confidence_bucket;
create or replace view cmatrix_test_conf_nontweets as
with test_data_filter as
(select * from model_analysis_rpts where
model_version in (select max(model_version) from model_analysis_rpts where report_type='model_rpt_gt')
and report_type='model_rpt_gt' and stype=0
and sdate between
(select test_start_date from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1)
and
(select test_end_date from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1)
),
confidence_correct as
(select
fp,fn,tp,tn,
(length(statement_text)-length(replace(statement_text,' ',''))+1) as wc,
if(label=prediction,1,0) correct_incorrect,
if(raw_pred>=0.5,raw_pred,1-raw_pred) as confidence
from test_data_filter),
confidence_buckets as
(select
ntile(25)  over (order by confidence) as confidence_bucket,
wc,
fp,fn,tp,tn,
correct_incorrect,
confidence
from confidence_correct)
select
confidence_bucket,
round(confidence_bucket*0.04, 3) as max_conf_percentile,
round(avg(wc)) as avg_wc,
round(sum(fp)/sum(fp+fn+tn+tp),3) as fp_ratio,
round(sum(fn)/sum(fp+fn+tn+tp),3) as fn_ratio,
round(sum(tn)/sum(fp+fn+tn+tp),3) as tn_ratio,
round(sum(tp)/sum(fp+fn+tn+tp),3) as tp_ratio,
round(avg(correct_incorrect),3) as acc,
round(avg(confidence),3) as confidence,
round(avg(correct_incorrect) - avg(confidence),3) acc_conf_delta
from confidence_buckets
group by confidence_bucket
order by confidence_bucket;
create or replace view cmatrix_test_conf_tweets as
with test_data_filter as
(select * from model_analysis_rpts where
model_version in (select max(model_version) from model_analysis_rpts where report_type='model_rpt_gt')
and report_type='model_rpt_gt' and stype=1
and sdate between
(select test_start_date from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1)
and
(select test_end_date from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1)
),
confidence_correct as
(select
fp,fn,tp,tn,
(length(statement_text)-length(replace(statement_text,' ',''))+1) as wc,
if(label=prediction,1,0) correct_incorrect,
if(raw_pred>=0.5,raw_pred,1-raw_pred) as confidence
from test_data_filter),
confidence_buckets as
(select
ntile(10)  over (order by confidence) as confidence_bucket,
wc,
fp,fn,tp,tn,
correct_incorrect,
confidence
from confidence_correct)
select
confidence_bucket,
round(confidence_bucket*0.1, 3) as max_conf_percentile,
round(avg(wc)) as avg_wc,
round(sum(fp)/sum(fp+fn+tn+tp),3) as fp_ratio,
round(sum(fn)/sum(fp+fn+tn+tp),3) as fn_ratio,
round(sum(tn)/sum(fp+fn+tn+tp),3) as tn_ratio,
round(sum(tp)/sum(fp+fn+tn+tp),3) as tp_ratio,
round(avg(correct_incorrect),3) as acc,
round(avg(confidence),3) as confidence,
round(avg(correct_incorrect) - avg(confidence),3) acc_conf_delta
from confidence_buckets
group by confidence_bucket
order by confidence_bucket;
create or replace view max_acc_nontweets as
with test_data_filter as
(select * from model_analysis_rpts where
model_version in (select max(model_version) from model_analysis_rpts where report_type='model_rpt_gt')
and report_type='model_rpt_gt' and stype=0
and sdate between
(select test_start_date from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1)
and
(select test_end_date from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1)
),
confidence_correct as
(select
fp,fn,tp,tn,
statement_id,
statement_text,
(length(statement_text)-length(replace(statement_text,' ',''))+1) as wc,
if(label=prediction,1,0) correct_incorrect,
if(raw_pred>=0.5,raw_pred,1-raw_pred) as confidence
from test_data_filter),
confidence_buckets as
(select
ntile(25)  over (order by confidence) as confidence_bucket,
statement_id,
statement_text,
wc,
fp,fn,tp,tn,
correct_incorrect,
confidence
from confidence_correct),
bucket_stats as
(select
confidence_bucket,
round(sum(fp)/sum(fp+fn+tn+tp),4) as fp_ratio,
round(sum(fn)/sum(fp+fn+tn+tp),4) as fn_ratio,
round(sum(tn)/sum(fp+fn+tn+tp),4) as tn_ratio,
round(sum(tp)/sum(fp+fn+tn+tp),4) as tp_ratio,
ifnull(round(sum(tp)/sum(tp+fp), 4), 0) as ppv,
ifnull(round(sum(tn)/sum(tn+fn), 4),0) as npv,
round(sum(tp+fp)/sum(fp+fn+tn+tp), 4) as ppr,
1-round(sum(tp+fp)/sum(fp+fn+tn+tp), 4) as npr,
round(avg(correct_incorrect), 4) as acc,
avg(confidence) as confidence
from confidence_buckets
group by confidence_bucket),
target_bucket as
(select confidence_bucket, acc, ppv, npv, ppr, npr from bucket_stats where ppv=(select max(ppv) from bucket_stats) order by confidence_bucket limit 1)
select tb.acc as bucket_acc, concat(round((cb.confidence_bucket-1)*0.04*100,0), '-', round(cb.confidence_bucket*0.04*100,0),'%') as conf_percentile, tb.ppv as pos_pred_acc, tb.npv as neg_pred_acc, tb.ppr as pos_pred_ratio, tb.npr as neg_pred_ratio, cb.statement_id, cb.statement_text, tp, tn, fp, fn
from confidence_buckets cb, target_bucket tb  where cb.confidence_bucket=tb.confidence_bucket;
create or replace view max_acc_tweets as
with test_data_filter as
(select * from model_analysis_rpts where
model_version in (select max(model_version) from model_analysis_rpts where report_type='model_rpt_gt')
and report_type='model_rpt_gt' and stype=1
and sdate between
(select test_start_date from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1)
and
(select test_end_date from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1)
),
confidence_correct as
(select
fp,fn,tp,tn,
statement_id,
statement_text,
(length(statement_text)-length(replace(statement_text,' ',''))+1) as wc,
if(label=prediction,1,0) correct_incorrect,
if(raw_pred>=0.5,raw_pred,1-raw_pred) as confidence
from test_data_filter),
confidence_buckets as
(select
ntile(10)  over (order by confidence) as confidence_bucket,
statement_id,
statement_text,
wc,
fp,fn,tp,tn,
correct_incorrect,
confidence
from confidence_correct),
bucket_stats as
(select
confidence_bucket,
round(sum(fp)/sum(fp+fn+tn+tp),4) as fp_ratio,
round(sum(fn)/sum(fp+fn+tn+tp),4) as fn_ratio,
round(sum(tn)/sum(fp+fn+tn+tp),4) as tn_ratio,
round(sum(tp)/sum(fp+fn+tn+tp),4) as tp_ratio,
ifnull(round(sum(tp)/sum(tp+fp), 4), 0) as ppv,
ifnull(round(sum(tn)/sum(tn+fn), 4),0) as npv,
round(sum(tp+fp)/sum(fp+fn+tn+tp), 4) as ppr,
1-round(sum(tp+fp)/sum(fp+fn+tn+tp), 4) as npr,
round(avg(correct_incorrect), 4) as acc,
avg(confidence) as confidence
from confidence_buckets
group by confidence_bucket),
target_bucket as
(select confidence_bucket, acc, ppv, npv, ppr, npr from bucket_stats where ppv=(select max(ppv) from bucket_stats) order by confidence_bucket limit 1)
select tb.acc as bucket_acc, concat(round((cb.confidence_bucket-1)*0.1*100,0), '-', round(cb.confidence_bucket*0.1*100,0),'%') as conf_percentile, tb.ppv as pos_pred_acc, tb.npv as neg_pred_acc, tb.ppr as pos_pred_ratio, tb.npr as neg_pred_ratio, cb.statement_id, cb.statement_text, tp, tn, fp, fn
from confidence_buckets cb, target_bucket tb  where cb.confidence_bucket=tb.confidence_bucket;

create or replace view min_acc_nontweets as
with test_data_filter as
(select * from model_analysis_rpts where
model_version in (select max(model_version) from model_analysis_rpts where report_type='model_rpt_gt')
and report_type='model_rpt_gt' and stype=0
and sdate between
(select test_start_date from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1)
and
(select test_end_date from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1)
),
confidence_correct as
(select
fp,fn,tp,tn,
statement_id,
statement_text,
(length(statement_text)-length(replace(statement_text,' ',''))+1) as wc,
if(label=prediction,1,0) correct_incorrect,
if(raw_pred>=0.5,raw_pred,1-raw_pred) as confidence
from test_data_filter),
confidence_buckets as
(select
ntile(25)  over (order by confidence) as confidence_bucket,
statement_id,
statement_text,
wc,
fp,fn,tp,tn,
correct_incorrect,
confidence
from confidence_correct),
bucket_stats as
(select
confidence_bucket,
round(sum(fp)/sum(fp+fn+tn+tp),4) as fp_ratio,
round(sum(fn)/sum(fp+fn+tn+tp),4) as fn_ratio,
round(sum(tn)/sum(fp+fn+tn+tp),4) as tn_ratio,
round(sum(tp)/sum(fp+fn+tn+tp),4) as tp_ratio,
ifnull(round(sum(tp)/sum(tp+fp), 4), 0) as ppv,
ifnull(round(sum(tn)/sum(tn+fn), 4),0) as npv,
round(sum(tp+fp)/sum(fp+fn+tn+tp), 4) as ppr,
1-round(sum(tp+fp)/sum(fp+fn+tn+tp), 4) as npr,
round(avg(correct_incorrect), 4) as acc,
avg(confidence) as confidence
from confidence_buckets
group by confidence_bucket),
target_bucket as
(select confidence_bucket, acc, ppv, npv, ppr, npr from bucket_stats where ppv=(select min(ppv) from bucket_stats) order by confidence_bucket limit 1)
select tb.acc as bucket_acc, concat(round((cb.confidence_bucket-1)*0.04*100,0), '-', round(cb.confidence_bucket*0.04*100,0),'%') as conf_percentile, tb.ppv as pos_pred_acc, tb.npv as neg_pred_acc, tb.ppr as pos_pred_ratio, tb.npr as neg_pred_ratio, cb.statement_id, cb.statement_text, tp, tn, fp, fn
from confidence_buckets cb, target_bucket tb  where cb.confidence_bucket=tb.confidence_bucket;
create or replace view min_acc_tweets as
with test_data_filter as
(select * from model_analysis_rpts where
model_version in (select max(model_version) from model_analysis_rpts where report_type='model_rpt_gt')
and report_type='model_rpt_gt' and stype=1
and sdate between
(select test_start_date from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1)
and
(select test_end_date from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1)
),
confidence_correct as
(select
fp,fn,tp,tn,
statement_id,
statement_text,
(length(statement_text)-length(replace(statement_text,' ',''))+1) as wc,
if(label=prediction,1,0) correct_incorrect,
if(raw_pred>=0.5,raw_pred,1-raw_pred) as confidence
from test_data_filter),
confidence_buckets as
(select
ntile(10)  over (order by confidence) as confidence_bucket,
statement_id,
statement_text,
wc,
fp,fn,tp,tn,
correct_incorrect,
confidence
from confidence_correct),
bucket_stats as
(select
confidence_bucket,
round(sum(fp)/sum(fp+fn+tn+tp),4) as fp_ratio,
round(sum(fn)/sum(fp+fn+tn+tp),4) as fn_ratio,
round(sum(tn)/sum(fp+fn+tn+tp),4) as tn_ratio,
round(sum(tp)/sum(fp+fn+tn+tp),4) as tp_ratio,
ifnull(round(sum(tp)/sum(tp+fp), 4), 0) as ppv,
ifnull(round(sum(tn)/sum(tn+fn), 4),0) as npv,
round(sum(tp+fp)/sum(fp+fn+tn+tp), 4) as ppr,
1-round(sum(tp+fp)/sum(fp+fn+tn+tp), 4) as npr,
round(avg(correct_incorrect),4) as acc,
avg(confidence) as confidence
from confidence_buckets
group by confidence_bucket),
target_bucket as
(select confidence_bucket, acc, ppv, npv, ppr, npr from bucket_stats where ppv=(select min(ppv) from bucket_stats) order by confidence_bucket limit 1)
select tb.acc as bucket_acc, concat(round((cb.confidence_bucket-1)*0.1*100,0), '-', round(cb.confidence_bucket*0.1*100,0),'%') as conf_percentile, tb.ppv as pos_pred_acc, tb.npv as neg_pred_acc, tb.ppr as pos_pred_ratio, tb.npr as neg_pred_ratio, cb.statement_id, cb.statement_text, tp, tn, fp, fn
from confidence_buckets cb, target_bucket tb  where cb.confidence_bucket=tb.confidence_bucket;
create or replace view pred_explr_stmts as
with man as
(select 'max_acc_nontweets' as bucket_type, bucket_acc, conf_percentile, pos_pred_acc, neg_pred_acc, pos_pred_ratio, neg_pred_ratio,  statement_id, statement_text, 0 as stype, tp, tn, fp, fn from max_acc_nontweets order by RAND(2718) limit 100),
mat as
(select 'max_acc_tweets' as bucket_type, bucket_acc, conf_percentile, pos_pred_acc, neg_pred_acc, pos_pred_ratio, neg_pred_ratio, statement_id, statement_text, 1 as stype, tp, tn, fp, fn from max_acc_tweets order by RAND(2718) limit 100),
mian as
(select 'min_acc_nontweets' as bucket_type, bucket_acc, conf_percentile, pos_pred_acc, neg_pred_acc, pos_pred_ratio, neg_pred_ratio,  statement_id, statement_text, 0 as stype, tp, tn, fp, fn from min_acc_nontweets order by RAND(2718) limit 100),
miat as
(select 'min_acc_tweets' as bucket_type, bucket_acc, conf_percentile, pos_pred_acc, neg_pred_acc, pos_pred_ratio, neg_pred_ratio,  statement_id, statement_text, 1 as stype, tp, tn, fp, fn from min_acc_tweets order by RAND(2718) limit 100),
distinct_stmts as
(
select * from man
union
select * from mat
union
select * from mian
union
select * from miat
)
select * from distinct_stmts;
create or replace view latest_global_model_perf_summary as
with
tweet_model_cache as
(select acc, auc, mcc, tp_ratio, tn_ratio, fp_ratio, fn_ratio from tweet_model_accuracy_summ ),
nontweet_model_cache as
(select acc, auc, mcc, tp_ratio, tn_ratio, fp_ratio, fn_ratio from nontweet_model_accuracy_summ ),
all_model_cache as
(select acc, auc, mcc, tp_ratio, tn_ratio, fp_ratio, fn_ratio from all_model_accuracy_summ ),
ds as
(select dsid from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1),
model_ver as
(select max(model_version) as model_version from model_analysis_rpts where report_type='model_rpt_gt')
select distinct
model_ver.model_version as model_version,
ds.dsid as dsid,
nontweet_model_cache.acc as nontweet_acc,
nontweet_model_cache.auc as nontweet_auc,
nontweet_model_cache.mcc as nontweet_mcc,
nontweet_model_cache.tp_ratio as nontweet_tp_ratio,
nontweet_model_cache.tn_ratio as nontweet_tn_ratio,
nontweet_model_cache.fp_ratio as nontweet_fp_ratio,
nontweet_model_cache.fn_ratio as nontweet_fn_ratio,
tweet_model_cache.acc as tweet_acc,
tweet_model_cache.auc as tweet_auc,
tweet_model_cache.mcc as tweet_mcc,
tweet_model_cache.tp_ratio as tweet_tp_ratio,
tweet_model_cache.tn_ratio as tweet_tn_ratio,
tweet_model_cache.fp_ratio as tweet_fp_ratio,
tweet_model_cache.fn_ratio as tweet_fn_ratio,
all_model_cache.acc as all_acc,
all_model_cache.auc as all_auc,
all_model_cache.mcc as all_mcc,
all_model_cache.tp_ratio as all_tp_ratio,
all_model_cache.tn_ratio as all_tn_ratio,
all_model_cache.fp_ratio as all_fp_ratio,
all_model_cache.fn_ratio as all_fn_ratio
from nontweet_model_cache, tweet_model_cache, all_model_cache, ds, model_ver;
create or replace view latest_local_model_perf_summary as
with nontweet_perf_cache as
(with test_data_filter as
(select * from model_analysis_rpts where
model_version in (select max(model_version) from model_analysis_rpts where report_type='model_rpt_gt')
and report_type='model_rpt_gt'
and stype=0
and sdate between
(select test_start_date from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1)
and
(select test_end_date from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1)
),
confidence_correct as
(select
model_version,
fp,fn,tp,tn,
statement_id as sid,
if(label=prediction,1,0) correct_incorrect,
if(raw_pred>=0.5,raw_pred,1-raw_pred) as confidence
from test_data_filter),
confidence_buckets as
(select
model_version,
fp,fn,tp,tn,
sid,
correct_incorrect,
avg(correct_incorrect) over () as global_acc,
confidence,
ntile(25)  over (order by confidence) as conf_bucket
from confidence_correct)
select
conf_bucket as bucket_num,
max(confidence) as max_confidence,
model_version,
round(avg(correct_incorrect),4) as bucket_acc,
round(global_acc,2) as acc,
round(est_auc,2) as auc,
round(mcc,2) as mcc,
ifnull(round(sum(tp)/sum(tp+fp), 3), 0) as ppv,
ifnull(round(sum(tn)/sum(tn+fn), 3),0) as npv,
round(sum(tp+fp)/sum(fp+fn+tn+tp), 3) as ppr,
1-round(sum(tp+fp)/sum(fp+fn+tn+tp), 3) as npr,
round(sum(tp)/sum(fp+fn+tn+tp),3) as tp_ratio,
round(sum(tn)/sum(fp+fn+tn+tp),3) as tn_ratio,
round(sum(fp)/sum(fp+fn+tn+tp),3) as fp_ratio,
round(sum(fn)/sum(fp+fn+tn+tp),3) as fn_ratio,
ds.dsid
from confidence_buckets, nontweet_current_mcc, auc_nontweets, (select dsid from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1) ds
group by bucket_num, global_acc),
tweet_perf_cache as
(with test_data_filter as
(select * from model_analysis_rpts where
model_version in (select max(model_version) from model_analysis_rpts where report_type='model_rpt_gt')
and report_type='model_rpt_gt'
and stype=1
and sdate between
(select test_start_date from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1)
and
(select test_end_date from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1)
),
confidence_correct as
(select
model_version,
fp,fn,tp,tn,
statement_id as sid,
if(label=prediction,1,0) correct_incorrect,
if(raw_pred>=0.5,raw_pred,1-raw_pred) as confidence
from test_data_filter),
confidence_buckets as
(select
model_version,
fp,fn,tp,tn,
sid,
correct_incorrect,
avg(correct_incorrect) over () as global_acc,
confidence,
ntile(10)  over (order by confidence) as conf_bucket
from confidence_correct)
select
conf_bucket as bucket_num,
max(confidence) as max_confidence,
model_version,
round(avg(correct_incorrect),4) as bucket_acc,
round(global_acc,2) as acc,
round(est_auc,2) as auc,
round(mcc,2) as mcc,
ifnull(round(sum(tp)/sum(tp+fp), 3), 0) as ppv,
ifnull(round(sum(tn)/sum(tn+fn), 3),0) as npv,
round(sum(tp+fp)/sum(fp+fn+tn+tp), 3) as ppr,
1-round(sum(tp+fp)/sum(fp+fn+tn+tp), 3) as npr,
round(sum(tp)/sum(fp+fn+tn+tp),3) as tp_ratio,
round(sum(tn)/sum(fp+fn+tn+tp),3) as tn_ratio,
round(sum(fp)/sum(fp+fn+tn+tp),3) as fp_ratio,
round(sum(fn)/sum(fp+fn+tn+tp),3) as fn_ratio,
ds.dsid
from confidence_buckets, tweet_current_mcc, auc_tweets, (select dsid from ds_metadata where ds_type='converged_filtered' order by dsid desc limit 1) ds
group by bucket_num, global_acc)
select model_version, dsid, 0 as stmt_type, bucket_num, max_confidence, bucket_acc, ppv, npv, ppr, npr, tp_ratio, tn_ratio, fp_ratio, fn_ratio from nontweet_perf_cache
union
select model_version, dsid, 1 as stmt_type, bucket_num, max_confidence, bucket_acc, ppv, npv, ppr, npr, tp_ratio, tn_ratio, fp_ratio, fn_ratio from tweet_perf_cache;
create or replace view stmts_to_analyze as
with latest_metadata as
(select mm.model_version as model_version, DATE_ADD(dm.test_end_date, INTERVAL 1 DAY) as inf_start_date from model_metadata mm, ds_metadata dm
where mm.dsid=dm.dsid
and mm.model_version=(select max(model_version) from model_metadata)),
unlabeled_stmts as
(select s.tid, s.sid, t.t_date from fbase_statements s, fbase_transcripts t, latest_metadata lm
where t.tid=s.tid and t.t_date > lm.inf_start_date),
published_stmts as
(select isp.tid, isp.sid from infsvc_stmts_published isp, fbase_statements s, fbase_transcripts t, latest_metadata lm
where t.tid=s.tid and s.tid=isp.tid and s.sid=isp.sid and t.t_date > lm.inf_start_date),
analyze_ids as
(select us.tid, us.sid from unlabeled_stmts us left join published_stmts ps
on us.tid=ps.tid and us.sid=ps.sid where ps.tid is NULL)
select s.tid, s.sid, statement_text, 0 as ctxt_type, t.t_date,  t.transcript_url as url from fbase_statements s, fbase_transcripts t, analyze_ids ai where t.tid=s.tid and s.tid=ai.tid and s.sid = ai.sid and s.wc between 7 and 107;
create or replace view tweets_to_analyze as
with latest_metadata as
(select mm.model_version as model_version, DATE_ADD(dm.test_end_date, INTERVAL 1 DAY) as inf_start_date from model_metadata mm, ds_metadata dm
where mm.dsid=dm.dsid
and mm.model_version=(select max(model_version) from model_metadata)),
unlabeled_tweets as
(select dt.thread_id, dt.t_end_date from dcbot_tweets dt, latest_metadata lm
where dt.t_end_date > lm.inf_start_date),
published_tweets as
(select itp.thread_id from infsvc_tweets_published itp, dcbot_tweets dt, latest_metadata lm
where itp.thread_id=dt.thread_id and dt.t_end_date > lm.inf_start_date),
analyze_ids as
(select ut.thread_id from unlabeled_tweets ut left join published_tweets pt
on ut.thread_id=pt.thread_id where pt.thread_id is NULL)
select dt.thread_id, dt.end_thread_tweet_id, statement_text, 1 as ctxt_type, dt.t_end_date, CONCAT('https://twitter.com/a/status/',dt.end_thread_tweet_id) as url from dcbot_tweets dt, analyze_ids ai
where dt.thread_id=ai.thread_id and dt.wc between 7 and 107 and dt.retweet=0;