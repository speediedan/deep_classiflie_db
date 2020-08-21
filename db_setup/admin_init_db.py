import os
import sys
import logging
from typing import Tuple

import mysql.connector
from mysql.connector import MySQLConnection
import getpass
from dotenv import load_dotenv

import constants
from envconfig import logging_config
logger = logging.getLogger(constants.APP_NAME)


def get_cnx_handle(user: str, pwd: str, host: str) -> MySQLConnection:
    # setup DB connection config
    config = {
        'user': user,
        'password': pwd,
        'host': host,
    }
    cnx = mysql.connector.connect(**config)
    return cnx


def collect_input() -> Tuple[str, str, str, str, str, str]:
    load_dotenv(constants.DB_ENV_FILE_DEV) if constants.DEV_MODE else load_dotenv(constants.DB_ENV_FILE)
    target_pwd = os.getenv('DCDB_PASS')
    target_host = os.getenv('DCDB_HOST')
    target_user = os.getenv('DCDB_USER')
    target_dc_database = os.getenv('DCDB_NAME')
    logger.info(constants.DB_INIT_MSG)
    u = input("admin user: ")
    p = getpass.getpass(prompt='admin password: ', stream=sys.stderr)
    return target_pwd, target_host, target_user, target_dc_database, u, p


def exec_init(target_pwd: str, target_host: str, target_user: str, target_dc_database: str, u: str, p: str) -> None:
    cnx = get_cnx_handle(u, p, target_host)
    elevated_auth_sql = f"""
CREATE DATABASE if not exists {target_dc_database};
CREATE USER IF NOT EXISTS '{target_user}'@'%' IDENTIFIED BY '{target_pwd}';
GRANT ALL PRIVILEGES ON {target_dc_database}.* TO '{target_user}'@'%';
FLUSH PRIVILEGES;
"""
    cur = cnx.cursor(buffered=True)
    try:
        logger.info("===========Creating New Database and User===========")
        for result in cur.execute(elevated_auth_sql, multi=True):
            stmt_part = f"{result.statement[:constants.DCDB_STMT_PRVW_LEN]}..."
            status = 'SUCCESS' if result._warning_count == 0 else 'NO CHANGE'
            logger.info(f"{stmt_part}: {status}")
    except mysql.connector.Error as err:
        logger.info(f"Failed executing DB initialization: {err}")
        exit(1)
    cur.close()


def build_schema(target_host: str, target_user: str, target_pwd: str, target_dcdb: str) -> None:
    cnx = get_cnx_handle(target_user, target_pwd, target_host)
    cnx.database = target_dcdb
    cur = cnx.cursor(buffered=True)
    try:
        schema_scripts = [constants.DCDB_SCHEMA_TBL_SQL, constants.DCDB_SCHEMA_VW_SQL, constants.DCDB_SCHEMA_RPT_SQL]
        schema_sql_lbls = ["Core Tables", "Core Views", "Reporting Objects"]
        for sql, lbl in zip(schema_scripts, schema_sql_lbls):
            with open(sql) as f:
                logger.info(f"===========Building {lbl}===========")
                for result in cur.execute(f.read(), multi=True):
                    stmt_part = f"{result.statement[:constants.DCDB_STMT_PRVW_LEN]}..."
                    status = 'SUCCESS' if result._warning_count == 0 else 'NO CHANGE'
                    logger.info(f"{stmt_part}: {status}")
    except mysql.connector.Error as err:
        logger.info(f"Failed executing DB initialization: {err}")
        exit(1)
    finally:
        cur.close()


def init_db() -> None:
    if not logger.handlers:  # if we don't already have handlers configured, do so
        log_dir = f"{os.environ['HOME']}/{constants.DCDB_SCHEMA_LOG_NAME}"
        logging_config(log_dir)
    target_pwd, target_host, target_user, target_dc_database, u, p = collect_input()
    db_init_warn = f"""
Proceeding will attempt to use '{u}' to:
1. create the DB '{target_dc_database}' on the mysql/mariadb host '{target_host}'
2. create the user '{target_user}' with extensive privileges on '{target_dc_database}'
3. initialize '{target_dc_database}' with the Deep Classiflie DB schema.
"""
    logger.info(db_init_warn)
    proceed = input('Proceed?(y/n): ')
    if proceed.lower() == 'y':
        exec_init(target_pwd, target_host, target_user, target_dc_database, u, p)
        build_schema(target_host, target_user, target_pwd, target_dc_database)
    else:
        logger.info('Exiting DB initialization without executing...')


if __name__ == '__main__':
    init_db()
