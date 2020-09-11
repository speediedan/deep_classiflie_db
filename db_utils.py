import logging
from typing import List, Tuple, Union, Optional
import math

from mysql.connector import Error
from mysql.connector.cursor_cext import CMySQLCursor
from mysql.connector.pooling import PooledMySQLConnection, MySQLConnectionPool

import constants

logger = logging.getLogger(constants.APP_NAME)


def fetch_one(cnx: PooledMySQLConnection, sql: str) -> Tuple:
    conn = cnx
    cursor = conn.cursor()
    cursor.execute(sql)
    row = cursor.fetchone()
    one_tup = row
    cursor.close()
    conn.close()
    return one_tup


def single_execute(conn: PooledMySQLConnection, statement_sql: str, rec: Tuple = None):
    cursor = conn.cursor(prepared=True) if rec else conn.cursor()
    exec_rowcnt, exec_errors = 0, 0
    try:
        cursor.execute(statement_sql, rec) if rec else cursor.execute(statement_sql)
    except Error as err:
        logger.debug(f"Adding record to error list. MariaDB error received: {err}")
        logger.debug(f"error: {err.errno}, {err.sqlstate}, {err.msg}")
        exec_errors += 1
    if cursor.rowcount >= 1:
        exec_rowcnt += cursor.rowcount
    conn.commit()
    cursor.close()
    conn.close()
    return exec_rowcnt, exec_errors


def batch_execute_many(conn: PooledMySQLConnection, statement_sql: str, recs: List[Tuple], commit_freq: int = 500,
                       debug_mode: bool = False) -> Union[Tuple[int, int], Tuple[int, int, List]]:
    exec_rowcnt = 0
    cursor = conn.cursor(prepared=True)
    records = len(recs)
    num_batches = math.ceil(records / commit_freq)
    exec_errors = 0
    error_rows = []
    for i in range(num_batches):
        start_idx = i * commit_freq
        end_idx = (i + 1) * commit_freq
        rec_batch = recs[start_idx:min(end_idx, records)]
        try:
            cursor.executemany(statement_sql, rec_batch)
        except Error as err:
            logger.debug(f"Adding record to error list. MariaDB error received: {err}")
            logger.debug(f"error: {err.errno}, {err.sqlstate}, {err.msg}")
            exec_errors += 1
            if debug_mode:
                logger.debug(f"error on insert of statement batch {start_idx}, {rec_batch}")
                error_rows.append(rec_batch)
        if cursor.rowcount >= 1:
            exec_rowcnt += cursor.rowcount
        conn.commit()
        logger.debug(f"added {cursor.rowcount} records in batch {i}")
    cursor.close()
    conn.close()
    if debug_mode:
        return exec_rowcnt, exec_errors, error_rows
    else:
        return exec_rowcnt, exec_errors


def truncate_existing(conn: PooledMySQLConnection, tblname: str) -> None:
    cursor = conn.cursor(prepared=True)
    truncate_sql = f"truncate table {tblname}"
    cursor.execute(truncate_sql)
    cursor.close()
    conn.close()


def db_ds_gen(cnxp: MySQLConnectionPool, sql: str, fetch_cnt: int = 5):
    conn = cnxp.get_connection()
    logger.debug(f"DB connection obtained: {conn}, starting generator to run sql: {sql}")
    cursor = conn.cursor(buffered=True)
    cursor.execute(sql)
    gen_exit = False
    try:
        while True:
            results = cursor.fetchmany(fetch_cnt)
            if not results:
                break
            for result in results:
                yield result
    except GeneratorExit:
        gen_cleanup(cursor, conn)
        gen_exit = True
    finally:
        if not gen_exit:  # don't attempt cleanup twice
            gen_cleanup(cursor, conn)


def gen_cleanup(cur: CMySQLCursor, cnx: PooledMySQLConnection) -> None:
    logger.debug(f"{cur.rowcount} rows selected by generator before closure.")
    # prevent unread rows from remaining before we close cursor and return to pool
    cur.fetchall()
    cur.close()
    cnx.close()
    logger.debug(f"DB connection closed: {cnx}")


def fetchallwrapper(conn: PooledMySQLConnection, sql: str, binds: Optional[Tuple] = None) -> List[Tuple]:
    cursor = conn.cursor()
    cursor.execute(sql, binds) if binds else cursor.execute(sql)
    rows = cursor.fetchall()
    cursor.close()
    conn.close()
    return rows
