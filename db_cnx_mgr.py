from typing import Dict
import logging
import os

from mysql.connector import Error
from mysql.connector import pooling

import constants

logger = logging.getLogger(constants.APP_NAME)


class DbCnxMgr(object):
    def __init__(self) -> None:
        self.cnxp = DbCnxMgr.db_cnx_setup()

    @staticmethod
    def db_cnx_setup() -> pooling.MySQLConnectionPool:
        try:
            pwd = os.environ['DCDB_PASS']
            host = os.environ['DCDB_HOST']
            user = os.environ['DCDB_USER']
            dc_database = os.environ['DCDB_NAME']
        except KeyError:
            from dotenv import load_dotenv
            from pathlib import Path
            load_dotenv(constants.DB_ENV_FILE_DEV) if constants.DEV_MODE else load_dotenv(constants.DB_ENV_FILE)
            pwd = os.getenv('DCDB_PASS')
            host = os.getenv('DCDB_HOST')
            user = os.getenv('DCDB_USER')
            dc_database = os.getenv('DCDB_NAME')
        dbconfig = {
            "host": host,
            "user": user,
            "password": pwd,
            "database": dc_database,
            "pool_name": f"{dc_database}_cp",
            "pool_size": constants.DEFAULT_DB_POOL_SIZE,
            "pool_reset_session": False
        }
        db_pool = DbCnxMgr.create_pool(**dbconfig)
        return db_pool

    @staticmethod
    def create_pool(**dbconfig: Dict) -> pooling.MySQLConnectionPool:
        pool = ""
        try:
            pool = pooling.MySQLConnectionPool(**dbconfig)
            logger.debug(f"Connection pool created with name {dbconfig['pool_name']} "
                         f"and initial size {dbconfig['pool_size']}")
        except Error as e:
            print(f"Error while creating mysql connection pool: {e}")
        return pool
