import datetime
import logging
import pytz
from typing import MutableMapping, Optional, List, Tuple, Union
import sys
import time
import traceback
import math
from html import unescape

from tweepy import API
from tweepy.models import ResultSet
from tweepy.cursor import ItemIterator
from mysql.connector.pooling import MySQLConnectionPool
import tweepy

import constants
from scraping_classes.scraping_utils import Scraper

logger = logging.getLogger(constants.APP_NAME)


class DCBotTweetScraper(Scraper):
    def __init__(self, config: MutableMapping, dbcnxp: MySQLConnectionPool, twitter_api: API) -> None:
        stype = 'twitter'
        super().__init__(config, dbcnxp, stype)
        self.twitter_api = twitter_api
        self.init_scraping_flow()

    def init_scraping_flow(self) -> None:
        if self.updatedb:
            tweet_results = self.update_tweets()
            if tweet_results:
                if not self.debug_mode:
                    num_inserts, error_row_cnt = tweet_results
                    logger.info(f"{num_inserts - error_row_cnt} new tweets added to DB.")
                else:
                    num_inserts, error_row_cnt, error_stmts = tweet_results
                    if len(error_stmts) > 0:
                        logger.debug(f"List of {len(error_stmts)} error tweets detected: \n {error_stmts}")
                    logger.info(f"{num_inserts} new tweets added to DB.")
        else:
            logger.info(f"update_db set to false in configuration, using existing data")

    def load_recent_tweets(self) -> List[Tuple]:
        tweet_objs, tweet_tups = [], []
        tweet_cur = tweepy.Cursor(self.twitter_api.user_timeline, id="realdonaldtrump", since_id=self.latest_db_stmt,
                                  tweet_mode='extended')
        for tweet in DCBotTweetScraper.rate_limit_handler(tweet_cur.items()):
            tweet_objs.append(tweet)
        try:
            for tweet in tweet_objs:
                if hasattr(tweet, "retweeted_status"):
                    # noinspection PyUnresolvedReferences
                    tweet_text = tweet.retweeted_status.full_text
                    is_rt = True
                else:
                    tweet_text = tweet.full_text
                    is_rt = False
                tweet_text = DCBotTweetScraper.parse_statements(tweet_text)
                if tweet_text:
                    maybe_more = 1 if constants.REGEX_DICT['maybe_mo_re'].search(tweet_text) else 0
                    maybe_cont = 1 if constants.REGEX_DICT['maybe_cont_re'].search(tweet_text) else 0
                    tweet_tups.append((tweet.id, tweet_text, tweet.created_at, is_rt, maybe_more, maybe_cont))
        except Exception as e:  # a lot could go wrong here. for now, shamefully using a broad except/logging traceback
            exc_type, exc_value, exc_traceback = sys.exc_info()
            logger.error(f"Encountered following error while parsing tweets:"
                         f" {repr(traceback.format_exception(exc_type, exc_value, exc_traceback))}")
            raise e
        return tweet_tups

    def build_tweet_thread(self, tweets: List[Tuple]):
        # TODO: refactor this parsing into components and reduce complexity
        tweets = sorted(tweets, key=lambda x: x[0])
        tweet_thread_tups = []
        thread_start, prev_rec = None, None
        thread_build_latency = self.config.db.tweetbot.thread_latency
        curr_t_text = ""
        utc_now = pytz.utc.localize(datetime.datetime.utcnow())
        for tweet_id, t_text, t_ts, t_rt, t_mmore, t_mcont in tweets:
            t_ts = pytz.utc.localize(t_ts)
            if t_rt:  # no processing if it's a rt
                tweet_thread_tups.append((tweet_id, t_text, t_ts, t_ts, t_rt))
                continue
            else:
                # always remove continued ellipses
                t_text = constants.REGEX_DICT['maybe_cont_re'].sub('', t_text).strip()
                if not thread_start:
                    if t_mmore == 0:  # if not maybe more, no thread
                        tweet_thread_tups.append((tweet_id, t_text, t_ts, t_ts, t_rt))
                        continue
                    else:  # start a new thread
                        if t_ts > (utc_now - datetime.timedelta(seconds=thread_build_latency)):
                            break  # don't start any new threads within a given threshold of current time
                        thread_start = t_ts
                        prev_rec = (tweet_id, t_ts, t_rt)
                        curr_t_text += ' ' + constants.REGEX_DICT['maybe_mo_re'].sub('', t_text).strip()
                else:  # in an active thread
                    sec_diff = t_ts - thread_start
                    # if thread time diff is sufficiently close, continue building
                    if sec_diff.total_seconds() < self.config.db.tweetbot.thread_latency:
                        curr_t_text += ' ' + constants.REGEX_DICT['maybe_mo_re'].sub('', t_text).strip()
                        if t_mmore == 1:  # keep thread going
                            continue
                        else:  # add thread and reset
                            tweet_thread_tups.append(
                                (tweet_id, curr_t_text, thread_start, t_ts, t_rt))
                            curr_t_text = ""
                            thread_start = None
                    else:  # thread time diff not sufficiently close, write previous thread and start new one
                        # add thread in progress
                        tweet_thread_tups.append((prev_rec[0], curr_t_text, thread_start, prev_rec[1], prev_rec[2]))
                        curr_t_text = ""
                        thread_start = None
                        # start new thread or add current
                        if t_mmore == 0:
                            tweet_thread_tups.append((tweet_id, t_text, t_ts, t_ts, t_rt))
                            continue
                        else:  # start a new thread
                            if t_ts > (utc_now - datetime.timedelta(seconds=thread_build_latency)):
                                break  # don't start any new threads within a given threshold of current time
                            thread_start = t_ts
                            prev_rec = (tweet_id, t_ts, t_rt)
                            curr_t_text += ' ' + constants.REGEX_DICT['maybe_mo_re'].sub('', t_text).strip()
        return tweet_thread_tups

    def update_tweets(self) -> Optional[Tuple]:
        # Orchestrates the scraping of statements from a target source.
        try:
            logger.info(f"Beginning {self.stype} scraping...")
            tweets = self.load_recent_tweets()
            if len(tweets) > 0:
                tweets = self.build_tweet_thread(tweets)
                # after building/filtering tweet threads, check if there are still tweets to sample
                logger.debug(f"Sample collected statement:{tweets[0]}") if len(tweets) > 0 \
                    else logger.debug(f"New tweets exist but awaiting thread completion per current "
                                      f"thread latency threshold {self.config.experiment.tweetbot.thread_latency} "
                                      f"seconds")
                return tuple(self.write_tups_db(tweets))
            else:
                logger.debug("No new tweets added")
        except Exception as e:  # a lot could go wrong here. for now, shamefully using a broad except/logging traceback
            exc_type, exc_value, exc_traceback = sys.exc_info()
            logger.error(f"Encountered following error while loading new statements:"
                         f" {repr(traceback.format_exception(exc_type, exc_value, exc_traceback))}")
            raise e

    def write_tups_db(self, tweets: List[Tuple]) -> Union[Tuple[int, int], Tuple[int, int, List]]:
        stmts = DCBotTweetScraper.build_stmt_rowset(tweets)
        stmt_sql = self.config['scraping'][self.stype]['sql']['stmt_invariant']
        if self.debug_mode:
            inserted_stmts, error_stmt_cnt, error_stmts = self.exec_sql_invariant(stmts, stmt_sql)
            return inserted_stmts, error_stmt_cnt, error_stmts
        else:
            inserted_stmts, error_stmt_cnt = self.exec_sql_invariant(stmts, stmt_sql)
            return inserted_stmts, error_stmt_cnt

    @staticmethod
    def build_stmt_rowset(stmt_rows: List[Tuple]) -> List[Tuple]:
        stmts = []
        for tweet_id, statement_text, t_start_date, t_end_date, retweet in stmt_rows:
            retweet = 1 if retweet else 0
            stmt_row = (tweet_id, statement_text, t_start_date, t_end_date, retweet, statement_text)
            stmts.append(stmt_row)
        return stmts

    @staticmethod
    def parse_statements(tweet_text: str) -> Optional[str]:
        tweet_text = unescape(tweet_text)
        tweet_text = tweet_text.replace('\xe2\x80\x94', '')  # replace em-dashes
        tweet_text = tweet_text.translate(str.maketrans('', '', '\n\t'))
        for regex in ['bracket_re', 'hashtag_re', 'at_re', 'dashes_re', 'url_re']:
            tweet_text = constants.REGEX_DICT[regex].sub('', tweet_text)
        for regex in ['singlequotes_re', 'doublequotes_re']:
            tweet_text = constants.REGEX_DICT[regex].sub('\'', tweet_text)
        tweet_text = tweet_text.strip()
        if len(tweet_text) > 0:
            return tweet_text
        else:
            return None

    @staticmethod
    def rate_limit_handler(cursor: ItemIterator) -> ResultSet:
        retries = 0
        while True:
            try:
                yield cursor.next()
                retries = 0
            except tweepy.error.TweepError:
                retries += 1
                sleep_time = constants.TWITTER_RATE_LIMIT_SECS * math.pow(2, retries)
                logger.info(f"Encountered error fetching next tweet in cursor, retrying again in {sleep_time} seconds")
                time.sleep(sleep_time)
            except StopIteration:
                break
