import datetime
import logging
import math
import sys
import traceback
from typing import MutableMapping, Union, List, Tuple

import dateparser
from bs4 import BeautifulSoup, Tag
from mysql.connector.pooling import MySQLConnectionPool

import constants
from scraping_classes.scraping_utils import Scraper, setup_driver, load_element
logger = logging.getLogger(constants.APP_NAME)


class WapoScraper(Scraper):

    def __init__(self, config: MutableMapping, dbcnxp: MySQLConnectionPool) -> None:
        stype = 'wapo'
        super().__init__(config, dbcnxp, stype)
        self.driver = setup_driver(self.config.db.use_chrome)
        self.driver.get(constants.WAPO_URL)
        self.element_xpath = r'//*[@id="claims-list"]/div[*]/button'
        self.init_scraping_flow()
        self.driver.quit()

    def init_scraping_flow(self) -> None:
        _ = load_element(self, self.element_xpath)
        if self.updatedb:
            scrape_results = self.scrape_statements()
            if not self.debug_mode:
                inserted_stmts, error_row_cnt = scrape_results
                logger.info(f"{inserted_stmts - error_row_cnt} new washington post factchecker statements added to DB.")
            else:
                inserted_stmts, _, error_stmts = scrape_results
                if len(error_stmts) > 0:
                    logger.debug(f"List of {len(error_stmts)} error rows detected "
                                 f"(likely duplicates): \n {error_stmts}")
                logger.info(f"{inserted_stmts} new washington post factchecker statements added to DB.")
        else:
            logger.info(f"update_db set to false in configuration, using existing data")

    def initial_load_fn(self) -> Tuple:
        init_page = BeautifulSoup(self.driver.page_source, 'lxml')
        tot_num_statements = int(WapoScraper.tot_statements(init_page))
        logger.info("Initial load will take some time...")
        clicks = math.ceil(tot_num_statements / 50) - 1
        for i in range(clicks):
            button = load_element(self, self.element_xpath)
            self.driver.execute_script("arguments[0].click();", button)
            logger.info(f"extending page to include statements {0}-{100 + (50 * i)}")
        raw_stmt_page = BeautifulSoup(self.driver.page_source, 'lxml')
        statements = self.parse_statements(raw_stmt_page)
        return tuple((statements,))

    def marginal_load_fn(self) -> Tuple:
        raw_stmt_page = BeautifulSoup(self.driver.page_source, 'lxml')
        page_min_date = self.parse_page_min_date(raw_stmt_page)
        while page_min_date >= self.latest_db_stmt:
            self.driver.execute_script("arguments[0].click();", load_element(self, self.element_xpath))
            logger.info(f"Loaded statements >= {page_min_date}")
            raw_stmt_page = BeautifulSoup(self.driver.page_source, 'lxml')
            page_min_date = WapoScraper.parse_page_min_date(raw_stmt_page)
        statements = WapoScraper.parse_statements(raw_stmt_page)
        return tuple((statements,))

    def write_tups_db(self, stmts: List[Tuple]) -> Union[Tuple[int, int], Tuple[int, int, List]]:
        stmts = WapoScraper.build_stmt_rowset(stmts)
        stmt_sql = self.config['scraping'][self.stype]['sql']['stmt_invariant']
        if self.debug_mode:
            inserted_stmts, error_stmt_cnt, error_stmts = self.exec_sql_invariant(stmts, stmt_sql)
            return inserted_stmts, error_stmt_cnt, error_stmts
        else:
            inserted_stmts, error_stmt_cnt = self.exec_sql_invariant(stmts, stmt_sql)
            return inserted_stmts, error_stmt_cnt

    @staticmethod
    def parse_statements(raw_stmt_page: BeautifulSoup) -> List[Tuple]:
        iid = 1
        db_rows = []
        parse_err_cnt = 0
        for s in raw_stmt_page.findAll("div", {"class": "claim-row"}):
            try:
                statements_tup = WapoScraper.parse_stmt_div(s, iid)
                db_rows.append(statements_tup)
            except Exception:  # for now, shamefully using a broad except mitigated by logging traceback
                logger.error(f"error parsing {len(db_rows) + 1}th record")
                logger.error(f"parsing the statement html {s}")
                exc_type, exc_value, exc_traceback = sys.exc_info()
                logger.error(f"traceback:\n{repr(traceback.format_exception(exc_type, exc_value, exc_traceback))}")
                parse_err_cnt += 1
        return db_rows

    @staticmethod
    def parse_stmt_div(target_div: Tag, iid: int) -> Tuple:
        repeats = 0
        pinocchio_cnt = 0
        stmt_date = dateparser.parse(target_div.find("div", {"class": "dateline"}).get_text()).date()
        s_sub = target_div.find("p", {"class": "pg-bodyCopy has-apos"}) or \
                target_div.find("p", {"class": "pg-bodyCopy no-apos"})
        statement = s_sub.get_text().strip().replace('\xa0', ' ')[1:-1]
        statement = statement.replace('\xe2\x80\x94', '')  # replace em-dashes
        statement = statement.translate(str.maketrans('', '', '\n\t'))
        for regex in ['bracket_re', 'hashtag_re', 'at_re', 'dashes_re', 'url_re']:
            statement = constants.REGEX_DICT[regex].sub('', statement)
        for regex in ['singlequotes_re', 'doublequotes_re']:
            statement = constants.REGEX_DICT[regex].sub('\'', statement)
        statement = statement.strip()
        left_rail = target_div.find("div", {"class": "rail left"})
        has_repeats = left_rail.find("span", {"class": "repeated-total"})
        if has_repeats:
            repeats = int(constants.REGEX_DICT['times_re'].search(has_repeats.get_text()).group(0))
        details_sub = left_rail.find("div", {"class": "details not-expanded"}).findAll("p")
        topic = details_sub[0].find("span").text
        source = details_sub[1].find("span").text
        factcheck_rating = target_div.find("div", {"class": "pinocchios"})
        if factcheck_rating:
            for _ in factcheck_rating.findAll("span", {"class": "pinocchio"}):
                pinocchio_cnt += 1
        return tuple((iid, statement, repeats, topic, source, pinocchio_cnt, stmt_date))

    @staticmethod
    def build_stmt_rowset(statements: List[Tuple]) -> List[Tuple]:
        stmts = []
        for iid, statement_text, repeats, topic, source, pinnochio_cnt, stmt_date in statements:
            stmt_row = (iid, statement_text, repeats, topic, source, pinnochio_cnt, stmt_date, statement_text)
            stmts.append(stmt_row)
        return stmts

    @staticmethod
    def tot_statements(stmt_page: BeautifulSoup) -> int:
        num_statements = \
            stmt_page.find("h1").find("span", {"class": "franklin-bold red"}).get_text().strip().replace(',', '')
        return num_statements

    @staticmethod
    def parse_page_min_date(raw_stmt_page: BeautifulSoup) -> datetime.date:
        last_statement = raw_stmt_page.findAll("div", {"class": "claim-row"})[-1]
        min_stmt_date = dateparser.parse(last_statement.find("div", {"class": "dateline"}).get_text()).date()
        return min_stmt_date
