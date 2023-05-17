#!/usr/bin/env python2

from QueryStat2 import HThorPerfResultConfig, WriteStatsToFile

hthor = HThorPerfResultConfig()
hthor.resolve()
options = { path:'.', dateStrings  : '',  verbose : False, 
                   host : '.', port: '',  obtSystem : '',  buildBranch : ''}
wstf = WriteStatsToFile(options)
