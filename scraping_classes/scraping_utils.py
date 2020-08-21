from typing import MutableMapping, Optional, Union, List, Tuple
import traceback
import logging
import math
import sys

from mysql.connector import Error
from mysql.connector.pooling import MySQLConnectionPool
import selenium
from selenium.common.exceptions import TimeoutException
from selenium.webdriver.remote.webdriver import WebElement
from selenium.webdriver.common.by import By
from selenium.webdriver.support import expected_conditions as ec
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.firefox.webdriver import WebDriver as FirefoxWebDriver
from selenium.webdriver.chrome.webdriver import WebDriver as ChromeWebDriver

import constants
from db_utils import batch_execute_many
from db_utils import fetch_one
logger = logging.getLogger(constants.APP_NAME)


class Scraper(object):
    def __init__(self, config: MutableMapping, dbcnxp: MySQLConnectionPool, stype: str) -> None:
        self.config = config
        self.updatedb = self.config.db.update_db
        self.cnxp = dbcnxp
        self.stype = stype
        self.init_wait = self.config['scraping'][self.stype]['init_wait']
        self.debug_mode = True if self.config.db.debug_enabled else False
        self.initial_load = False
        self.driver = None
        try:
            self.latest_db_stmt = fetch_one(self.cnxp.get_connection(),
                                            self.config['scraping'][self.stype]['sql']['latest_statement'])[0]
        except Error as e:
            logger.error(constants.DB_ERROR_MSG + f'{e}')
            raise e
        if not self.latest_db_stmt:
            self.latest_db_stmt = self.config['scraping'][self.stype]['default_latest_stmt'] or \
                                  constants.BEGINNING_OF_TIME
            self.initial_load = True

    def init_scraping_flow(self, *args, **kwargs) -> None:
        """ highest-level wrapper around the scraping flow, configuring it for batch/debug/db update mode contexts
        Should be overridden by all subclasses
        """
        raise NotImplementedError

    # noinspection PyTypeChecker,PyArgumentList
    def scrape_statements(self) -> Optional[Tuple]:
        # Orchestrates the scraping of statements from a target source.
        try:
            logger.info(f"Beginning {self.stype} scraping...")
            stmt_rows = self.initial_load_fn() if self.initial_load else self.marginal_load_fn()
            if all(len(r) > 0 for r in stmt_rows):
                for r in stmt_rows:
                    logger.debug(f"Sample collected:{r[0]}")
                return tuple(self.write_tups_db(*stmt_rows))
            else:
                logger.debug("No new statements added")
        except Exception as e:  # a lot could go wrong here. for now, shamefully using a broad except/logging traceback
            exc_type, exc_value, exc_traceback = sys.exc_info()
            logger.error(f"Encountered following error while loading new statements:"
                         f" {repr(traceback.format_exception(exc_type, exc_value, exc_traceback))}")
            raise e

    def exec_sql_invariant(self, recs: List[Tuple], sql_invariant: str) -> \
            Union[Tuple[int, int], Tuple[int, int, List]]:
        if not self.debug_mode:
            # IGNORE performs efficient batch update but loses access to specific row failures w/o
            # writing a stored procedure which is overkill in this use case
            sql = f"INSERT IGNORE {sql_invariant}"
            commit_freq = self.config.db.db_commit_freq
            return batch_execute_many(self.cnxp.get_connection(), sql, recs, commit_freq)
        else:
            # if we're working in debug mode to track errors, sacrifice setting commit frequency inefficiently to 1
            # to identify specific row errors while avoiding failure of remainder of batch insert
            sql = f"INSERT {sql_invariant}"
            commit_freq = 1
            return batch_execute_many(self.cnxp.get_connection(), sql, recs, commit_freq, self.debug_mode)

    def parse_statements(self, *args, **kwargs) -> List[Tuple]:
        """core statement parsing function
        Should be overridden by all subclasses
        """
        raise NotImplementedError

    def initial_load_fn(self, *args, **kwargs) -> Optional[Tuple]:
        """ Function governing statement loading on initial load
        Should be overridden by all subclasses
        """

    def marginal_load_fn(self, *args, **kwargs) -> Optional[Tuple]:
        """ Function governing statement loading on incremental loads
        Should be overridden by all subclasses
        """

    def write_tups_db(self, *args, **kwargs) -> Tuple[int, int, Optional[List[Tuple]]]:
        """ writes scraped tuples to the db
            Should be overridden by all subclasses
        """
        raise NotImplementedError


def setup_driver(use_chrome: bool = False) -> Union[ChromeWebDriver, FirefoxWebDriver]:
    if use_chrome:
        options = selenium.webdriver.ChromeOptions()
        options.binary_location = '/opt/google/chrome/chrome'
        options.add_argument("--headless")
        driver = selenium.webdriver.Chrome(executable_path="/opt/google/chromedriver",
                                           service_args=["--verbose", "--log-path=/tmp/chromedriver.log"],
                                           chrome_options=options)
    else:
        options = selenium.webdriver.FirefoxOptions()
        options.add_argument("--headless")
        driver = selenium.webdriver.Firefox(executable_path="/opt/mozilla/geckodriver", log_path='/tmp/geckodriver.log',
                                            firefox_options=options)
    return driver


def load_element(scraper: Scraper, element_xpath) -> WebElement:
    max_retries = scraper.config['scraping'][scraper.stype]['max_retries']
    retries = 0
    fetch_success = False
    element = None
    while retries < max_retries and not fetch_success:
        try:
            wait = WebDriverWait(scraper.driver, scraper.init_wait * math.pow(2, retries))
            element = wait.until(ec.presence_of_element_located((By.XPATH, element_xpath)))
            fetch_success = True
        except selenium.common.exceptions.TimeoutException:
            logger.info(f"Recieved timeout, retrying...")
            retries += 1
    return element
