from typing import MutableMapping, List, Set, Tuple, Union
import json
import traceback
import sys
import logging
import time
import math

from mysql.connector.pooling import MySQLConnectionPool
import requests
from bs4 import BeautifulSoup, Tag
from tqdm import tqdm

import constants
from scraping_classes.scraping_utils import Scraper
from db_utils import fetchallwrapper
logger = logging.getLogger(constants.APP_NAME)


class FactbaseScraper(Scraper):

    def __init__(self, config: MutableMapping, dbcnxp: MySQLConnectionPool):
        stype = 'factbase'
        super().__init__(config, dbcnxp, stype)
        self.max_pages = self.config['scraping'][self.stype]['max_pages']
        self.max_retries = self.config['scraping'][self.stype]['max_retries']
        self.page = 1
        self.session = requests.Session()
        self.headers = {
            "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) "
                          "Chrome/75.0.3770.142 Safari/537.36",
            "Accept-Language": "en-US,en;q=0.9",
            "Accept": "text/html,application/xhtml+xml,application/xml; q=0.9,image/webp,image/apng,*/*; q=0.8,"
                      "application/signed-exchange; v=b3"}
        self.init_scraping_flow()

    def init_scraping_flow(self) -> None:
        if self.updatedb:
            scrape_results = self.scrape_statements()
            if scrape_results:
                if not self.debug_mode:
                    inserted_txcpts, error_txcpt_cnt, inserted_stmts, error_stmt_cnt = scrape_results
                    logger.info(f"{inserted_txcpts - error_txcpt_cnt} new factbase transcripts added to DB.")
                    logger.info(f"{inserted_stmts - error_stmt_cnt} new factbase  statements added to DB.")
                else:
                    inserted_txcpts, _, error_txcpts, inserted_stmts, _, error_stmts = scrape_results
                    if len(error_txcpts) > 0:
                        logger.debug(f"List of {len(error_txcpts)} error transcripts detected: \n {error_txcpts}")
                    if len(error_stmts) > 0:
                        logger.debug(f"List of {len(error_stmts)} error stmts detected: \n {error_stmts}")
                    logger.info(f"{inserted_txcpts} new factbase transcripts added to DB.")
                    logger.info(f"{inserted_stmts} new factbase statements added to DB.")
        else:
            logger.info(f"update_db set to false in configuration, using existing data")

    def fetch_url(self, t_url: str) -> requests.Response:
        retries = 0
        fetch_success = False
        response = None
        while retries < self.max_retries and not fetch_success:
            try:
                wait = self.init_wait * math.pow(2, retries)
                logger.debug(f"Trying in {wait} seconds...")
                time.sleep(wait)
                if retries > 1:
                    logger.info(f"Failed retry with previous session, creating a new session for next retry")
                    self.session = requests.Session()
                response = self.session.get(t_url, headers=self.headers,
                                            timeout=(self.config.scraping.factbase.request_timeouts.connect,
                                                     self.config.scraping.factbase.request_timeouts.read))
                fetch_success = True
            except requests.exceptions.RequestException as req_err:
                logger.info(f"Recieved request exception: {req_err}")
                retries += 1
        return response

    def fetch_page(self) -> List[Tuple]:
        response = self.fetch_url(f"{constants.FBASE_URL}{self.page}")
        raw_stmt_page = BeautifulSoup(response.text, 'html.parser')
        txcpt_json = json.loads(str(raw_stmt_page))
        txcpts = txcpt_json['data']
        txcpt_tups = []
        for txcpt in txcpts:
            # if the sentiment hasn't been scored yet, wait on loading it until it has
            if txcpt["sentiment"]["score"] and txcpt["sentiment"]["score"] != "Unknown":
                txcpt_tups.append((txcpt["id"], txcpt["date"], txcpt["type"],
                                   f"https://factba.se/transcript/{txcpt['slug']}", txcpt["sentiment"]["score"]))
        return txcpt_tups

    def parse_statements(self, t_tups: List[Tuple]) -> List[Tuple]:
        db_rows = []
        parse_err_cnt = 0
        for t_id, _, _, t_url, _ in tqdm(t_tups):
            response = self.fetch_url(t_url)
            raw_stmt_page = BeautifulSoup(response.text, 'lxml')
            s_id = 0
            for d in raw_stmt_page.findAll("div", class_=constants.REGEX_DICT['stmt_grp_re']):
                try:
                    speaker = d.find("div", {"class": "speaker-label"}).get_text()
                    if speaker == "Donald Trump":
                        stmt = FactbaseScraper.parse_stmt_div(d)
                        txcpt_sent_sub = d.find("div", {"class": "sentiment-block"}).find_next("div").get('title')
                        if txcpt_sent_sub and txcpt_sent_sub != "Unknown":
                            sent_rating = constants.REGEX_DICT['rating_re'].search(txcpt_sent_sub).group(0)
                            db_rows.append((t_id, s_id, stmt, sent_rating))
                            s_id += 1
                    else:
                        pass
                except Exception:  # for now, shamefully using a broad except mitigated by logging traceback
                    logger.error(f"error parsing {len(db_rows) + 1}th record")
                    logger.error(f"parsing the statement html {d}")
                    exc_type, exc_value, exc_traceback = sys.exc_info()
                    logger.error(f"traceback:\n{repr(traceback.format_exception(exc_type, exc_value, exc_traceback))}")
                    parse_err_cnt += 1
        return db_rows

    def initial_load_fn(self) -> Tuple[List[Tuple], List[Tuple]]:
        txcpt_rows = []
        stmt_rows = []
        l_page_ne = True
        while self.page < self.max_pages and l_page_ne:
            t_tups = self.fetch_page()
            l_page_ne = True if len(t_tups) > 0 else False
            if not l_page_ne:
                logger.info(f"Initial load detected last page to be page {self.page - 1}")
                break
            txcpt_batch = self.parse_statements(t_tups)
            txcpt_rows += t_tups
            stmt_rows += txcpt_batch
            self.page += 1
        return tuple((txcpt_rows, stmt_rows))

    def marginal_load_fn(self) -> Tuple[List[Tuple], List[Tuple]]:
        l_page_full = True
        txcpt_rows, stmt_rows, t_tups = [], [], []
        while self.page < self.max_pages and l_page_full:
            parse_success = False
            retries = 0
            while retries < self.max_retries and not parse_success:
                try:
                    wait = self.init_wait * math.pow(2, retries)
                    logger.debug(f"Trying in {wait} seconds...")
                    time.sleep(wait)
                    t_tups = self.fetch_page()
                    parse_success = True
                except ValueError as ve:
                    logger.warning(f'Exception occured while parsing page {self.page}. Error: {ve}')
                    retries += 1
            if parse_success:
                dup_ids = self.check_ids(t_tups)
                t_tups = [t for t in t_tups if all(t[0] != y for y in dup_ids)]  # filter out ids in dup list
                l_page_full = True if len(t_tups) == constants.FACTBASE_FULLPAGE_CNT else False
                if len(t_tups) > 0:
                    txcpt_batch = self.parse_statements(t_tups)
                    txcpt_rows += t_tups
                    stmt_rows += txcpt_batch
                else:
                    logger.debug(f"No additional transcripts to add ({len(txcpt_rows)} rows)")
            else:
                logger.warning(f'Abandoned parsing page {self.page} after {retries} retries. '
                               f'Proceeding with subsequent pages if available.')
            self.page += 1
        return tuple((txcpt_rows, stmt_rows))

    def check_ids(self, test_ids: List) -> Set:
        test_ids = [tup[0] for tup in test_ids]
        inlist = ", ".join(list(map(lambda x: '%s', test_ids)))
        test_ids = tuple(test_ids)
        sql = f"{self.config['scraping'][self.stype]['sql']['check_tid']} ({inlist})"
        found_ids = fetchallwrapper(self.cnxp.get_connection(), sql, test_ids)
        test_set = set(test_ids)
        found_set = set([f[0] for f in found_ids])
        dup_ids = test_set.intersection(found_set)
        return dup_ids

    def write_tups_db(self, txcpts: List[Tuple], stmts: List[Tuple]) \
            -> Union[Tuple[int, int, int, int], Tuple[int, int, List, int, int, List]]:
        txcpts = FactbaseScraper.build_txcpt_rowset(txcpts)
        stmts = FactbaseScraper.build_stmt_rowset(stmts)
        txcpt_sql = self.config['scraping'][self.stype]['sql']['txcpt_invariant']
        stmt_sql = self.config['scraping'][self.stype]['sql']['stmt_invariant']
        if self.debug_mode:
            inserted_txcpts, error_txcpt_cnt, error_txcpts = self.exec_sql_invariant(txcpts, txcpt_sql)
            inserted_stmts, error_stmt_cnt, error_stmts = self.exec_sql_invariant(stmts, stmt_sql)
            return inserted_txcpts, error_txcpt_cnt, error_txcpts, inserted_stmts, error_stmt_cnt, error_stmts
        else:
            inserted_txcpts, error_txcpt_cnt = self.exec_sql_invariant(txcpts, txcpt_sql)
            inserted_stmts, error_stmt_cnt = self.exec_sql_invariant(stmts, stmt_sql)
            return inserted_txcpts, error_txcpt_cnt, inserted_stmts, error_stmt_cnt

    @staticmethod
    def build_txcpt_rowset(txcpt_rows: List[Tuple]) -> List[Tuple]:
        txcpts = []
        for t_id, t_date, t_type, t_url, t_sent in txcpt_rows:
            txcpt_row = (t_id, t_date, t_type, t_url, t_sent)
            txcpts.append(txcpt_row)
        return txcpts

    @staticmethod
    def build_stmt_rowset(stmt_rows: List[Tuple]) -> List[Tuple]:
        stmts = []
        for t_id, s_id, stmt, sent in stmt_rows:
            stmt_row = (t_id, s_id, stmt, sent)
            stmts.append(stmt_row)
        return stmts

    @staticmethod
    def parse_stmt_div(target_div: Tag) -> str:
        stmt = target_div.find("div", {"class": "transcript-text-block"}).get_text().strip().replace('\xa0', ' ')
        stmt = stmt.replace('\xe2\x80\x94', '')
        stmt = constants.REGEX_DICT['action_re'].sub('', stmt.replace("\"", ""))
        stmt = constants.REGEX_DICT['singlequotes_re'].sub('\'', stmt)
        stmt = constants.REGEX_DICT['doublequotes_re'].sub('\"', stmt)
        stmt = constants.REGEX_DICT['bracket_re'].sub('', stmt)
        stmt = constants.REGEX_DICT['hashtag_re'].sub('', stmt)
        stmt = constants.REGEX_DICT['at_re'].sub('', stmt)
        stmt = constants.REGEX_DICT['dashes_re'].sub('', stmt)
        stmt = stmt.strip()
        return stmt
