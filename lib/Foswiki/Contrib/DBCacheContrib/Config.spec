#---+ Extensions
#---++ DBCacheContrib
# This extension is a database cache, used by the DBCachePlugin
# and FormQueryPlugin.

# **SELECTCLASS Foswiki::Contrib::DBCacheContrib::Archivist::* EXPERT**
# The DBCache can use one of a number of different back-end stores.  Which one
# you choose depends mainly on what you have installed, and what your data
# looks like. If you have a realtively small number of topics (< 1000) and lots
# of memory, the 'Storable' module is appropriate. This module loads all topic
# data into memory for fast searching. For larger webs use 'Segmentable' which caches
# topics in segments that can be updated faster than using 'Storable'. If you have a large
# number of topics, or tight memory constraints, you should use 'BerkeleyDB'
# which stores the cache in an external database. 
# WARNING: 'BerkeleyDB' is experimental and known to cause errors. 
$Foswiki::cfg{DBCacheContrib}{Archivist} =
    'Foswiki::Contrib::DBCacheContrib::Archivist::Segmentable';

# **BOOLEAN EXPERT**
# When enabled the cache will be updated from the .txt files every time it is
# loaded into memory.  Setting it to FALSE - as is strongly recommended - will
# update the cache only if requested by afterSaveHandler or from the REST
# updateCache handler.  
# WARNING: do not enable this flag on production systems as it significantly
# impacts performance.
$Foswiki::cfg{DBCacheContrib}{AlwaysUpdateCache} = $FALSE;

# **NUMBER EXPERT**
# With a load limit of 0 the DBCache will reload all the changed
# and new files in one hit. This can impose a significant overhead if a lot
# of files change. Set this option to a positive number to limit the number
# of files updated during any given HTTP request, thus reducing the impact on
# individual topic views by spreading the update over several requests.
# WARNING: setting this to any value higher than zero can result in the
# cache becoming out of sync with the .txt files.
$Foswiki::cfg{DBCacheContrib}{LoadFileLimit} = 0;

1;
