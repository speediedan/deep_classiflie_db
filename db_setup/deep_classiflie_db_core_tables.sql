SET FOREIGN_KEY_CHECKS = 0;
drop table if exists issuers;
CREATE TABLE issuers (
	iid int NOT NULL AUTO_INCREMENT COMMENT 'issuer id',
	name varchar(50) NOT NULL COMMENT 'name of issuing entity',
	PRIMARY KEY (iid)
)
ENGINE=InnoDB
DEFAULT CHARSET=utf8mb4
COLLATE=utf8mb4_unicode_ci
COMMENT='issuers of statements, mostly people'
AUTO_INCREMENT=1;
INSERT INTO issuers (name) VALUES ('Donald Trump');
drop table if exists wp_statements;
CREATE TABLE wp_statements (
	sid INT NOT NULL COMMENT 'statement id' AUTO_INCREMENT,
	iid INT NOT NULL COMMENT 'issuer id',
	statement_text varchar(2000) NOT NULL COMMENT 'text of statement',
	repeats INT NOT NULL COMMENT 'repetitions of a statement',
	topic varchar(30) NOT NULL COMMENT 'topic associated with a statement',
	source varchar(30) NOT NULL COMMENT 'source associated with a statement',
	pinnochios INT NOT NULL COMMENT 'rated pinnochios of a statement',
	s_date date NOT NULL COMMENT 'statement date',
	statement_hash char(40) NOT NULL COMMENT 'sha1 hash of statement',
	wc INT GENERATED ALWAYS AS ((length(statement_text)-length(replace(statement_text,' ',''))+1)) STORED COMMENT 'generated word count of statement',
	PRIMARY KEY (sid),
	CONSTRAINT wp_statements_FK_1 FOREIGN KEY (iid) REFERENCES issuers(iid),
	CONSTRAINT wp_statements_UN UNIQUE KEY (statement_hash,iid,s_date)
)
ENGINE=InnoDB
DEFAULT CHARSET=utf8mb4
COLLATE=utf8mb4_unicode_ci
COMMENT='statements, pinnochios ratings associated with an issuer'
AUTO_INCREMENT=1;
drop table if exists fbase_transcripts;
CREATE TABLE fbase_transcripts (
	tid varchar(100) NOT NULL COMMENT 'transcript id',
	t_date date NOT NULL COMMENT 'transcript date',
	transcript_type varchar(30) NOT NULL COMMENT 'type of transcript',
	transcript_url varchar(1000) NOT NULL COMMENT 'url of transcript',
	transcript_sent DECIMAL(5,2) DEFAULT 0 COMMENT 'sentiment rating of transcript',
	PRIMARY KEY (tid)
)
ENGINE=InnoDB
DEFAULT CHARSET=utf8mb4
COLLATE=utf8mb4_unicode_ci
COMMENT='factba.se transcripts of Donald Trump utterances';
drop table if exists fbase_statements;
CREATE TABLE fbase_statements (
	tid varchar(100) NOT NULL COMMENT 'transcript id',
	sid INT NOT NULL COMMENT 'statement id',
	statement_text TEXT NOT NULL COMMENT 'text of statement',
	sentiment DECIMAL(5,2) DEFAULT 0 COMMENT 'sentiment rating of statement',
	wc INT GENERATED ALWAYS AS ((length(statement_text)-length(replace(statement_text,' ',''))+1)) STORED COMMENT 'generated word count of statement',
	PRIMARY KEY (tid,sid),
	CONSTRAINT fbase_statements_FK FOREIGN KEY (tid) REFERENCES fbase_transcripts(tid) ON DELETE CASCADE
)
ENGINE=InnoDB
DEFAULT CHARSET=utf8mb4
COLLATE=utf8mb4_unicode_ci
COMMENT='factba.se statements in transcripts of Donald Trump utterances';
drop table if exists dcbot_tweets;
CREATE TABLE dcbot_tweets (
    thread_id BIGINT NOT NULL AUTO_INCREMENT COMMENT 'tweet thread id',
	end_thread_tweet_id BIGINT NOT NULL COMMENT 'last tweet id in the thread, to be used as target for replies',
	statement_text TEXT NOT NULL COMMENT 'text of statement',
	t_start_date TIMESTAMP NOT NULL DEFAULT 0 COMMENT 'statement timestamp',
	t_end_date TIMESTAMP NOT NULL DEFAULT 0 COMMENT 'statement timestamp',
	retweet TINYINT(1) NOT NULL COMMENT '1=retweet, 0=otherwise',
	statement_hash char(40) NOT NULL COMMENT 'sha1 hash of statement',
	wc INT GENERATED ALWAYS AS ((length(statement_text)-length(replace(statement_text,' ',''))+1)) STORED COMMENT 'generated word count of statement',
	PRIMARY KEY (thread_id),
	CONSTRAINT dcbot_tweets_UN UNIQUE KEY (statement_hash, t_end_date)
)
ENGINE=InnoDB
DEFAULT CHARSET=utf8mb4
COLLATE=utf8mb4_unicode_ci
COMMENT='directly downloaded twitter history of Donald Trump tweets collected by dcbot';
drop table if exists dcbot_creds;
CREATE TABLE dcbot_creds (
    consumer_key varchar(40) NOT NULL COMMENT 'consumer key for dcbot',
    consumer_secret varchar(80) NOT NULL COMMENT 'consumer secret for dcbot',
    access_token varchar(80) NOT NULL COMMENT 'access token for dcbot',
	access_secret varchar(80) NOT NULL COMMENT 'access secret for dcbot'
)
ENGINE=InnoDB
DEFAULT CHARSET=utf8mb4
COLLATE=utf8mb4_unicode_ci
COMMENT='twitter credentials for deep_classiflie bot';
drop table if exists pt_converged_truths;
CREATE TABLE pt_converged_truths (
	statement_text TEXT NOT NULL COMMENT 'text of statement',
	stype TINYINT(1) NOT NULL COMMENT '0=statement, 1=tweet',
	sdate date NOT NULL COMMENT 'statement date'
)
ENGINE=InnoDB
DEFAULT CHARSET=utf8mb4
COLLATE=utf8mb4_unicode_ci
COMMENT='a dataset of true statements with its distribution transformed to correspond to a given false statement distribution';
drop table if exists ds_metadata;
CREATE TABLE ds_metadata (
	dsid VARCHAR(20) NOT NULL COMMENT 'dataset id',
	ds_type VARCHAR(20) NOT NULL COMMENT 'type of dataset',
	train_start_date DATE NOT NULL DEFAULT 0 COMMENT 'train start date',
	train_end_date DATE NOT NULL DEFAULT 0 COMMENT 'train end date',
	val_start_date DATE NOT NULL DEFAULT 0 COMMENT 'val start date',
	val_end_date DATE NOT NULL DEFAULT 0 COMMENT 'val end date',
	test_start_date DATE NOT NULL DEFAULT 0 COMMENT 'test start date',
	test_end_date DATE NOT NULL DEFAULT 0 COMMENT 'test end date',
	PRIMARY KEY (dsid)
	)
ENGINE=InnoDB
DEFAULT CHARSET=utf8mb4
COLLATE=utf8mb4_unicode_ci
COMMENT='latest dataset metadata';
drop table if exists model_analysis_rpts;
CREATE TABLE model_analysis_rpts (
    model_version VARCHAR(20) NOT NULL  COMMENT 'model version',
    dsid VARCHAR(20) NOT NULL  COMMENT 'dataset id',
    report_type VARCHAR(40) NOT NULL  COMMENT 'report type',
    statement_id INT NOT NULL COMMENT 'statement id',
	statement_text TEXT NOT NULL COMMENT 'text of statement',
	stype TINYINT(1) NOT NULL COMMENT '0=statement, 1=tweet',
    sdate TIMESTAMP NOT NULL DEFAULT 0 COMMENT 'statement timestamp',
	label TINYINT(1) NOT NULL COMMENT '1=falsehood, 0=truth',
	prediction TINYINT(1) NOT NULL COMMENT '1=falsehood, 0=truth',
	raw_pred DECIMAL(5,4) NOT NULL COMMENT 'output of sigmoid, closer to 1=falsehood, 0=truth',
	tp TINYINT(1) GENERATED ALWAYS AS (CASE when (label=1 and prediction=1) then 1 else 0 END) STORED COMMENT '1 if true positive',
	fp TINYINT(1) GENERATED ALWAYS AS (CASE when (label=0 and prediction=1) then 1 else 0 END) STORED COMMENT '1 if false positive',
	tn TINYINT(1) GENERATED ALWAYS AS (CASE when (label=0 and prediction=0) then 1 else 0 END) STORED COMMENT '1 if true negative',
	fn TINYINT(1) GENERATED ALWAYS AS (CASE when (label=1 and prediction=0) then 1 else 0 END) STORED COMMENT '1 if false negative',
	PRIMARY KEY (model_version, dsid, report_type, statement_id),
	CONSTRAINT model_analysis_FK FOREIGN KEY (dsid) REFERENCES ds_metadata(dsid)
)
ENGINE=InnoDB
DEFAULT CHARSET=utf8mb4
COLLATE=utf8mb4_unicode_ci
COMMENT='model analysis reports';
drop table if exists false_truth_del_cands;
CREATE TABLE false_truth_del_cands (
    falsehood_id INT NOT NULL COMMENT 'falsehood id in wp_statements',
    truth_id VARCHAR(150) NOT NULL  COMMENT 'truth_id in all_truth_statements_tmp, make foreign key if permanent',
	l2dist DECIMAL(22,15) NOT NULL COMMENT 'l2_distance_between_possible_false_truths'
)
ENGINE=InnoDB
DEFAULT CHARSET=utf8mb4
COLLATE=utf8mb4_unicode_ci
COMMENT='false truth candidates for deletion';
CREATE INDEX false_truth_del_cands_truth_id_idx USING BTREE ON false_truth_del_cands (truth_id);
drop table if exists base_false_truth_del_cands;
CREATE TABLE base_false_truth_del_cands (
    falsehood_id INT NOT NULL COMMENT 'falsehood id in wp_statements',
    truth_id VARCHAR(150) NOT NULL  COMMENT 'truth_id in all_truth_statements_tmp, make foreign key if permanent',
	l2dist DECIMAL(22,15) NOT NULL COMMENT 'l2distance between candidates for deletion'
)
ENGINE=InnoDB
DEFAULT CHARSET=utf8mb4
COLLATE=utf8mb4_unicode_ci
COMMENT='false truth candidates for deletion';
SET FOREIGN_KEY_CHECKS = 1;
CREATE INDEX base_false_truth_del_cands_truth_id_idx USING BTREE ON base_false_truth_del_cands (truth_id);
SET FOREIGN_KEY_CHECKS = 0;
drop table if exists model_metadata;
CREATE TABLE model_metadata (
	model_version VARCHAR(20) NOT NULL  COMMENT 'model version',
    dsid VARCHAR(20) NOT NULL  COMMENT 'dataset id used to develop model',
	nontweet_acc DECIMAL(5,2) NOT NULL COMMENT 'acc of model for nontweets',
	nontweet_auc DECIMAL(5,2) NOT NULL COMMENT 'auc of model for nontweets',
	nontweet_mcc DECIMAL(5,2) NOT NULL COMMENT 'mcc of model for nontweets',
	nontweet_tp_ratio DECIMAL(5,2) NOT NULL COMMENT 'tp_ratio of model for nontweets',
	nontweet_tn_ratio DECIMAL(5,2) NOT NULL COMMENT 'tn_ratio of model for nontweets',
	nontweet_fp_ratio DECIMAL(5,2) NOT NULL COMMENT 'fp_ratio of model for nontweets',
	nontweet_fn_ratio DECIMAL(5,2) NOT NULL COMMENT 'fn_ratio of model for nontweets',
	tweet_acc DECIMAL(5,2) NOT NULL COMMENT 'acc of model for tweets',
	tweet_auc DECIMAL(5,2) NOT NULL COMMENT 'auc of model for tweets',
	tweet_mcc DECIMAL(5,2) NOT NULL COMMENT 'mcc of model for tweets',
	tweet_tp_ratio DECIMAL(5,2) NOT NULL COMMENT 'tp_ratio of model for tweets',
	tweet_tn_ratio DECIMAL(5,2) NOT NULL COMMENT 'tn_ratio of model for tweets',
	tweet_fp_ratio DECIMAL(5,2) NOT NULL COMMENT 'fp_ratio of model for tweets',
	tweet_fn_ratio DECIMAL(5,2) NOT NULL COMMENT 'fn_ratio of model for tweets',
	all_acc DECIMAL(5,2) NOT NULL COMMENT 'global acc of model',
	all_auc DECIMAL(5,2) NOT NULL COMMENT 'global auc of model',
	all_mcc DECIMAL(5,2) NOT NULL COMMENT 'global mcc of model',
	all_tp_ratio DECIMAL(5,2) NOT NULL COMMENT 'global tp_ratio of model',
	all_tn_ratio DECIMAL(5,2) NOT NULL COMMENT 'global tn_ratio of model',
	all_fp_ratio DECIMAL(5,2) NOT NULL COMMENT 'global fp_ratio of model',
	all_fn_ratio DECIMAL(5,2) NOT NULL COMMENT 'global fn_ratio of model',
	PRIMARY KEY (model_version),
	CONSTRAINT mm_dsid_FK FOREIGN KEY (dsid) REFERENCES ds_metadata(dsid)
	)
ENGINE=InnoDB
DEFAULT CHARSET=utf8mb4
COLLATE=utf8mb4_unicode_ci
COMMENT='latest model global performance metadata';
drop table if exists local_model_perf_summary_hist;
CREATE TABLE local_model_perf_summary_hist (
    model_version VARCHAR(20) NOT NULL  COMMENT 'model version',
    dsid VARCHAR(20) NOT NULL  COMMENT 'dataset id used to develop model',
    stmt_type TINYINT(1) NOT NULL COMMENT '0=statement, 1=tweet',
    bucket_num INT NOT NULL COMMENT 'confidence-based bucket number',
    max_confidence DECIMAL(5,4) NOT NULL COMMENT 'bucket confidence ceiling of local confidence bucket associated with models prediction',
    bucket_acc DECIMAL(5,4) NOT NULL COMMENT 'accuracy of local confidence bucket associated with models prediction',
	ppv DECIMAL(5,4) NOT NULL COMMENT 'ppv of local confidence bucket associated with models prediction',
	npv DECIMAL(5,4) NOT NULL COMMENT 'npv of local confidence bucket associated with models prediction',
	ppr DECIMAL(5,4) NOT NULL COMMENT 'ppr of local confidence bucket associated with models prediction',
	npr DECIMAL(5,4) NOT NULL COMMENT 'npr of local confidence bucket associated with models prediction',
	tp_ratio DECIMAL(5,4) NOT NULL COMMENT 'tp_ratio of local confidence bucket associated with models prediction',
	tn_ratio DECIMAL(5,4) NOT NULL COMMENT 'tn_ratio of local confidence bucket associated with models prediction',
	fp_ratio DECIMAL(5,4) NOT NULL COMMENT 'fp_ratio of local confidence bucket associated with models prediction',
	fn_ratio DECIMAL(5,4) NOT NULL COMMENT 'fn_ratio of local confidence bucket associated with models prediction',
	PRIMARY KEY (model_version, dsid, stmt_type, bucket_num),
	CONSTRAINT mpsh_model_version_FK FOREIGN KEY (model_version) REFERENCES model_metadata(model_version) ON DELETE CASCADE,
	CONSTRAINT mpsh_dsid_FK FOREIGN KEY (dsid) REFERENCES ds_metadata(dsid) ON DELETE CASCADE
)
ENGINE=InnoDB
DEFAULT CHARSET=utf8mb4
COLLATE=utf8mb4_unicode_ci
COMMENT='history of local model performance summaries';
SET FOREIGN_KEY_CHECKS = 1;
drop table if exists infsvc_stmts_published;
CREATE TABLE infsvc_stmts_published (
    dc_tid BIGINT NOT NULL COMMENT 'dc published claim id' AUTO_INCREMENT,
    model_version varchar(20) NOT NULL COMMENT 'model version used to generate prediction',
    iid INT NOT NULL COMMENT 'dc issuer id',
    tid VARCHAR(100) NOT NULL COMMENT 'source transcript id, ',
    sid INT NOT NULL COMMENT 'source statement id, ',
    prediction TINYINT(1) NOT NULL COMMENT '1=falsehood, 0=truth',
	raw_pred DECIMAL(5,4) NOT NULL COMMENT 'output of sigmoid, closer to 1=falsehood, 0=truth',
	raw_confidence DECIMAL(5,4) NOT NULL COMMENT 'given models raw confidence in prediction',
	p_date TIMESTAMP NOT NULL DEFAULT 0 COMMENT 'published timestamp',
	PRIMARY KEY (dc_tid),
	CONSTRAINT isp_fbase_statements_FK FOREIGN KEY (tid,sid) REFERENCES fbase_statements(tid,sid) ON DELETE CASCADE,
	CONSTRAINT isp_model_metadata_FK FOREIGN KEY (model_version) REFERENCES model_metadata(model_version) ON DELETE CASCADE,
	CONSTRAINT isp_issuers_FK FOREIGN KEY (iid) REFERENCES issuers(iid) ON DELETE CASCADE
)
ENGINE=InnoDB
DEFAULT CHARSET=utf8mb4
COLLATE=utf8mb4_unicode_ci
COMMENT='history of analyzed stmts published by deep_classiflie inference service';
drop table if exists infsvc_tweets_published;
CREATE TABLE infsvc_tweets_published (
    dc_tid BIGINT NOT NULL COMMENT 'dc published claim id' AUTO_INCREMENT,
    model_version varchar(20) NOT NULL COMMENT 'model version used to generate prediction',
    iid INT NOT NULL COMMENT 'dc issuer id',
    thread_id BIGINT NOT NULL COMMENT 'source tweet thread id',
    prediction TINYINT(1) NOT NULL COMMENT '1=falsehood, 0=truth',
	raw_pred DECIMAL(5,4) NOT NULL COMMENT 'output of sigmoid, closer to 1=falsehood, 0=truth',
	raw_confidence DECIMAL(5,4) NOT NULL COMMENT 'given models raw confidence in prediction',
	p_date TIMESTAMP NOT NULL DEFAULT 0 COMMENT 'published timestamp',
	PRIMARY KEY (dc_tid),
	CONSTRAINT itp_thread_id_statements_FK FOREIGN KEY (thread_id) REFERENCES dcbot_tweets(thread_id) ON DELETE CASCADE,
	CONSTRAINT itp_model_metadata_FK FOREIGN KEY (model_version) REFERENCES model_metadata(model_version) ON DELETE CASCADE,
	CONSTRAINT itp_issuers_FK FOREIGN KEY (iid) REFERENCES issuers(iid) ON DELETE CASCADE
)
ENGINE=InnoDB
DEFAULT CHARSET=utf8mb4
COLLATE=utf8mb4_unicode_ci
COMMENT='history of analyzed tweets published by deep_classiflie inference service';
drop table if exists pinata_creds;
CREATE TABLE pinata_creds (
    api_key varchar(40) NOT NULL COMMENT 'api key for pinata',
    api_secret varchar(80) NOT NULL COMMENT 'api secret for pinata',
    account_email varchar(80) NOT NULL COMMENT ''
)
ENGINE=InnoDB
DEFAULT CHARSET=utf8mb4
COLLATE=utf8mb4_unicode_ci
COMMENT='pinata credentials for pinata';
drop table if exists cloudflare_creds;
CREATE TABLE cloudflare_creds (
    api_key varchar(80) NOT NULL COMMENT 'api secret key for cloudflare',
    zone_id varchar(80) NOT NULL COMMENT 'zone_id for relevant cloudflare domain',
    dns_record_id_prod varchar(80) NOT NULL COMMENT 'record id for prod TXT record',
    dns_record_id_dev varchar(80) NOT NULL COMMENT 'record id for dev TXT record',
    account_email varchar(80) NOT NULL COMMENT ''
)
ENGINE=InnoDB
DEFAULT CHARSET=utf8mb4
COLLATE=utf8mb4_unicode_ci
COMMENT='api dns update credentials for cloudflare';
drop table if exists pinned_cids;
CREATE TABLE pinned_cids (
    pin_svc_id INT NOT NULL COMMENT 'pinning service used, initially only pinata=1',
    cid VARCHAR(150) NOT NULL  COMMENT 'ipfs has of content',
    pinsize INT NOT NULL COMMENT 'size in bytes of pinned content',
    p_date TIMESTAMP NOT NULL DEFAULT 0 COMMENT 'timestamp pin logged'
)
ENGINE=InnoDB
DEFAULT CHARSET=utf8mb4
COLLATE=utf8mb4_unicode_ci
COMMENT='pinned cids';