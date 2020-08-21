[![python badge](https://img.shields.io/badge/python->=3.7-brightgreen.svg)](https://shields.io/)
[![pytorch badge](https://img.shields.io/badge/pytorch->=4.8-blue.svg)](https://shields.io/)
<img class="dc_logo_head" src="dc_logo.png" alt="Deep Classiflie Logo" align="right"/>
### **Deep_classiflie_db** is the backend data system for managing Deep Classiflie metadata, analyzing Deep Classiflie intermediate datasets and orchestrating Deep Classiflie model training pipelines. 

--- 
Deep_classiflie_db includes data scraping modules for the initial model data sources (twitter, factba.se, washington post -- politifact and the toronto star were removed from an earlier version and may be re-added among others as models for other prominent politicians are explored). Deep Classiflie depends upon deep_classiflie_db for much of its analytical and dataset generation functionality but the data system is currently maintained as a separate repository here to maximize architectural flexibility. Depending on how Deep Classiflie evolves (e.g. as it supports distributed data stores etc.), it may make more sense to integrate deep_classiflie_db back into deep_classiflie.

Please see the main deep_classiflie project repository [README](https://github.com/speediedan/deep_classiflie) or [deepclassiflie.org](https://deepclassiflie.org) to learn more about both deep_classiflie_db and deep_classiflie.