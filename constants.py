import datetime
import os
import re

curr_base = os.path.dirname(os.path.realpath(__file__)).rsplit('/', 1)[1]
DB_CONN_MSG_TEMPLATE = "connection_id={connid} pid={pid}, before running sql: {sql} via {dbfunc}"
DB_CONN_OPEN_DEBUG_TEMPLATE = "DB connection opened: " + DB_CONN_MSG_TEMPLATE
DB_CONN_CLOSED_DEBUG_TEMPLATE = "Closing DB connection: " + DB_CONN_MSG_TEMPLATE
DEF_DB_PRJ_NAME = "deep_classiflie_db"
DEV_MODE = True if curr_base != DEF_DB_PRJ_NAME else False
APP_NAME = curr_base
APP_INSTANCE = f'{datetime.datetime.now():%Y%m%d%H%M%S}'
WAPO_URL = "https://www.washingtonpost.com/graphics/politics/trump-claims-database/"
FBASE_URL = "https://factba.se/json/json-transcript.php?p="
DB_ENV_FILE = f"{os.environ['HOME']}/.dc_config"
DB_ENV_FILE_DEV = f"{os.environ['HOME']}/.{curr_base}_config"
DCDB_BASE = os.environ['DCDB_BASE'] if 'DCDB_BASE' in os.environ.keys() else os.path.dirname(os.path.realpath(__file__))
DCDB_SCHEMA_TBL_SQL = f"{DCDB_BASE}/db_setup/{DEF_DB_PRJ_NAME}_core_tables.sql"
DCDB_SCHEMA_VW_SQL = f"{DCDB_BASE}/db_setup/{DEF_DB_PRJ_NAME}_core_views.sql"
DCDB_SCHEMA_RPT_SQL = f"{DCDB_BASE}/db_setup/{DEF_DB_PRJ_NAME}_reporting_objects.sql"
DCDB_SCHEMA_LOG_NAME = "deep_classiflie_db_init.log"
DCDB_STMT_PRVW_LEN = 30
DB_ERROR_MSG = "Error acquiring most recent statement in DB. Please check DB config/status. Aborting w/ error:"
DB_INIT_MSG = "Deep Classiflie DB initialization requires a mysql/mariadb user with create DB and create user " \
              "privileges. Please see project documentation for further details."
BEGINNING_OF_TIME = datetime.date(1900, 1, 1)
DEFAULT_DB_POOL_SIZE = 10
TWITTER_RATE_LIMIT_SECS = 15 * 60
FACTBASE_FULLPAGE_CNT = 20
LATEST_MODEL_REPORTS = ['gt_all_rpt', 'gt_tweets_rpt', 'gt_nontweets_rpt']
TEST_CMATRICES = ['cmatrix_test_all', 'cmatrix_test_nontweets', 'cmatrix_test_tweets']
TEST_WC_CMATRICES = ['cmatrix_test_wc_all', 'cmatrix_test_wc_tweets', 'cmatrix_test_wc_nontweets']
TEST_CONF_CMATRICES = ['cmatrix_test_conf_all', 'cmatrix_test_conf_nontweets', 'cmatrix_test_conf_tweets']
REGEX_DICT = {
    'maybe_mo_re': re.compile(r"(\.{2,})$"),
    'maybe_cont_re': re.compile(r"^(\.{2,})"),
    'timestamp_re': re.compile(r"T(?=(\d))"),
    'stmt_grp_re': re.compile(r'(media topic-media-row mediahover.*)'),
    'rating_re': re.compile(r'-?\d+(\.\d+)?'),
    'action_re': re.compile(r'(\[.*?\])'),
    'singlequotes_re': re.compile(r'\xE2\x80([\x98\x99])'),
    'doublequotes_re': re.compile(r'\xE2\x80([\x9C\x9D])'),
    'bracket_re': re.compile(r'\[.*?\]'),
    'hashtag_re': re.compile(r'#\S+'),
    'at_re': re.compile(r'@\S+'),
    'dashes_re': re.compile(u"(\u2013|\u2014|--)"),
    'times_re': re.compile(r'\d+'),
    'url_re': re.compile(
        r"(?i)\b((?:https?:(?:/{1,3}|[a-z0-9%])|[a-z0-9.\-]+[.]("
        r"?:com|net|org|edu|gov|mil|aero|asia|biz|cat|coop|info|int|jobs|mobi|museum|name|post|pro"
        r"|tel|travel|xxx|ac|ad|ae|af|ag|ai|al|am|an|ao|aq|ar|as|at|au|aw|ax|az|ba|bb|bd|be|bf|bg"
        r"|bh|bi|bj|bm|bn|bo|br|bs|bt|bv|bw|by|bz|ca|cc|cd|cf|cg|ch|ci|ck|cl|cm|cn|co|cr|cs|cu|cv"
        r"|cx|cy|cz|dd|de|dj|dk|dm|do|dz|ec|ee|eg|eh|er|es|et|eu|fi|fj|fk|fm|fo|fr|ga|gb|gd|ge|gf"
        r"|gg|gh|gi|gl|gm|gn|gp|gq|gr|gs|gt|gu|gw|gy|hk|hm|hn|hr|ht|hu|id|ie|il|im|in|io|iq|ir|is"
        r"|it|je|jm|jo|jp|ke|kg|kh|ki|km|kn|kp|kr|kw|ky|kz|la|lb|lc|li|lk|lr|ls|lt|lu|lv|ly|ma|mc"
        r"|md|me|mg|mh|mk|ml|mm|mn|mo|mp|mq|mr|ms|mt|mu|mv|mw|mx|my|mz|na|nc|ne|nf|ng|ni|nl|no|np"
        r"|nr|nu|nz|om|pa|pe|pf|pg|ph|pk|pl|pm|pn|pr|ps|pt|pw|py|qa|re|ro|rs|ru|rw|sa|sb|sc|sd|se"
        r"|sg|sh|si|sj|Ja|sk|sl|sm|sn|so|sr|ss|st|su|sv|sx|sy|sz|tc|td|tf|tg|th|tj|tk|tl|tm|tn|to"
        r"|tp|tr|tt|tv|tw|tz|ua|ug|uk|us|uy|uz|va|vc|ve|vg|vi|vn|vu|wf|ws|ye|yt|yu|za|zm|zw)/)(?:["
        r"^\s()<>{}\[\]]+|\([^\s()]*?\([^\s()]+\)[^\s()]*?\)|\([^\s]+?\))+(?:\([^\s()]*?\([^\s("
        r")]+\)[^\s()]*?\)|\([^\s]+?\)|[^\s`!()\[\]{};:'\".,<>?«»“”‘’])|(?:(?<!@)[a-z0-9]+(?:[.\-]["
        r"a-z0-9]+)*[.](?:com|net|org|edu|gov|mil|aero|asia|biz|cat|coop|info|int|jobs|mobi|museum"
        r"|name|post|pro|tel|travel|xxx|ac|ad|ae|af|ag|ai|al|am|an|ao|aq|ar|as|at|au|aw|ax|az|ba|bb"
        r"|bd|be|bf|bg|bh|bi|bj|bm|bn|bo|br|bs|bt|bv|bw|by|bz|ca|cc|cd|cf|cg|ch|ci|ck|cl|cm|cn|co"
        r"|cr|cs|cu|cv|cx|cy|cz|dd|de|dj|dk|dm|do|dz|ec|ee|eg|eh|er|es|et|eu|fi|fj|fk|fm|fo|fr|ga"
        r"|gb|gd|ge|gf|gg|gh|gi|gl|gm|gn|gp|gq|gr|gs|gt|gu|gw|gy|hk|hm|hn|hr|ht|hu|id|ie|il|im|in"
        r"|io|iq|ir|is|it|je|jm|jo|jp|ke|kg|kh|ki|km|kn|kp|kr|kw|ky|kz|la|lb|lc|li|lk|lr|ls|lt|lu"
        r"|lv|ly|ma|mc|md|me|mg|mh|mk|ml|mm|mn|mo|mp|mq|mr|ms|mt|mu|mv|mw|mx|my|mz|na|nc|ne|nf|ng"
        r"|ni|nl|no|np|nr|nu|nz|om|pa|pe|pf|pg|ph|pk|pl|pm|pn|pr|ps|pt|pw|py|qa|re|ro|rs|ru|rw|sa"
        r"|sb|sc|sd|se|sg|sh|si|sj|Ja|sk|sl|sm|sn|so|sr|ss|st|su|sv|sx|sy|sz|tc|td|tf|tg|th|tj|tk"
        r"|tl|tm|tn|to|tp|tr|tt|tv|tw|tz|ua|ug|uk|us|uy|uz|va|vc|ve|vg|vi|vn|vu|wf|ws|ye|yt|yu|za"
        r"|zm|zw)\b/?(?!@)))")
    }
