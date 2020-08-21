import logging
from typing import MutableMapping, Tuple
import os
import sys
from argparse import ArgumentParser, RawDescriptionHelpFormatter, Namespace

from dotmap import DotMap
from ruamel.yaml import YAML

import constants
from utils.envconfig import create_dirs

logger = logging.getLogger(constants.APP_NAME)
__version__ = 0.2


class CLIError(Exception):
    """Generic exception to raise and log different fatal errors."""

    def __init__(self, msg):
        super().__init__(type(self))
        self.msg = f"ERROR: {msg}"

    def __str__(self):
        return self.msg

    def __unicode__(self):
        return self.msg


class EnvConfig(object):
    """
    Parses the target YAML configuration and prepares the framework to execute the requested processes
    """

    def __init__(self, config_file: str = None, tweetbot_conf=None) -> None:
        self._config = None
        self.exec_config(config_file, tweetbot_conf)

    @property
    def config(self) -> MutableMapping:
        return self._config

    def exec_config(self, config_file: str = None, tweetbot_conf=None) -> None:
        # capture the config path from the run arguments
        # then process the yaml configuration file
        if not config_file:
            config_file = (get_args()).config
        self._config = get_config_from_yaml(config_file)
        if tweetbot_conf:
            tweetbot_mode, daemon_dir = tweetbot_conf
            self._config.dirs.dcbot_log_dir = daemon_dir
            self._config.db.tweetbot = tweetbot_mode
            self._config.db.db_env_file = constants.DB_ENV_FILE
        self._config.dirs.base_dir = self._config.dirs.base_dir or os.environ['HOME']
        self._config.dirs.log_dir = self._config.dirs.log_dir or \
                                    f"{self._config.dirs.base_dir}/temp/{constants.APP_NAME}/logs"
        # create the experiments dirs
        create_dirs([loc for loc in self._config.dirs.values()])
        if not logger.handlers:  # if we don't already have handlers configured, do so
            log_level = 'DEBUG' if self._config.db.debug_enabled else 'INFO'
            base_dir = self._config.dirs.dcbot_log_dir if \
                self._config.db.tweetbot.enabled else self._config.dirs.log_dir
            log_dir = f'{base_dir}/{constants.APP_NAME}.log'
            logging_config(log_dir, log_level)


# noinspection PyShadowingNames
def logging_config(log_dir: str, log_level: str = 'INFO') -> None:
    file_handler, console_handler = conf_handlers(log_dir)
    logger = logging.getLogger(constants.APP_NAME)
    logger.setLevel(log_level)
    logger.addHandler(console_handler)
    logger.addHandler(file_handler)
    logger.info(f"Starting {constants.APP_NAME} logger")


def conf_handlers(log_dir: str) -> Tuple[logging.FileHandler, logging.StreamHandler]:
    # attach handlers only to the root logger and allow propagation to handle
    formatter = logging.Formatter("%(asctime)s:%(name)s:%(levelname)s: %(message)s")
    file_handler = logging.FileHandler(log_dir)
    file_handler.setFormatter(formatter)
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setFormatter(formatter)
    return file_handler, console_handler


def get_args() -> Namespace:
    program_version = f"{__version__}"
    program_version_message = f"{constants.APP_NAME} ({program_version})"
    program_shortdesc = __import__('__main__').__doc__.split("\n")[1]
    # noinspection PyTypeChecker
    parser = ArgumentParser(description=program_shortdesc, formatter_class=RawDescriptionHelpFormatter)
    parser.add_argument('-c', '--config', dest='config', help='pass yaml config file',
                        default=f"{os.getcwd()}/deep_classiflie_db.yaml")
    parser.add_argument('-v', '--version', action='version', version=program_version_message)
    args = parser.parse_args()
    if not os.path.exists(args.config):
        raise CLIError(f"A valid config file was not found: {args.config}")
    return args


def get_config_from_yaml(yaml_file: str) -> MutableMapping:
    """
    Args:
        yaml_file:

    Returns:
        config(namespace)
    """
    yaml = YAML()
    # parse the configurations from the config yaml file provided
    with open(yaml_file, 'r') as config_file:
        instance_config_dict = yaml.load(config_file)
    # convert the dictionary to a namespace using DotMap
    config = DotMap(instance_config_dict)
    return config
