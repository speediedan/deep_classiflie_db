source ~/.bashrc
curr_branch=`git branch | grep '* ' | awk '{print $2}'`
if [[ "${curr_branch}" == "master"  ]]; then
    echo "Initializing DB in non-dev mode"
    source ~/.dc_config
  else
    echo "Initializing DB in dev mode"
    source ~/.${curr_branch}_config
fi
target_env=$1
conda activate $target_env
/opt/anaconda/envs/${target_env}/bin/python ${DCDB_BASE}/db_setup/admin_init_db.py