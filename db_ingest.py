"""
deep_classiflie_db: db component of a system that analyzes trump lies. This component scrapes a number of
sources and compiles/refreshes the primary project db
@author:     Dan Dale
"""
from typing import MutableMapping, Tuple

from tweepy import API
from mysql.connector.pooling import MySQLConnectionPool
import envconfig
from db_cnx_mgr import DbCnxMgr
from scraping_classes.dcbot_tweet_scraper import DCBotTweetScraper
from scraping_classes.factbase_scraper import FactbaseScraper
from scraping_classes.wapo_scraper import WapoScraper


def get_cnxp_handle() -> MySQLConnectionPool:
    # setup DB config connection
    db_cnxp = DbCnxMgr()
    cnxp = db_cnxp.cnxp
    return cnxp


def refresh_db(conf_file: MutableMapping = None, cnxp: MySQLConnectionPool = None, tweetbot_conf: Tuple = None,
               api_handle: API = None, nontwtr_update: bool = False) -> None:
    config = envconfig.EnvConfig(conf_file, tweetbot_conf).config
    cnxp = cnxp or get_cnxp_handle()
    if nontwtr_update or not config.db.tweetbot.enabled:
        FactbaseScraper(config, cnxp)
        WapoScraper(config, cnxp)
    else:
        DCBotTweetScraper(config, cnxp, api_handle)


if __name__ == '__main__':
    refresh_db()
