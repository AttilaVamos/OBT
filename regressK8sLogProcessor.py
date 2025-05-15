#!/usr/bin/env python3

import os
import glob
from optparse import OptionParser
import errno

def readLogFileNames(path='',  opts=None):
    fileNames = []
    curDir = os.getcwd()
    os.chdir( path )
    fileNames = glob.glob('regress*.log')
    os.chdir( curDir )
    fileNames.sort() 
    if opts.debug:
        print("Filenames:")
        for file in fileNames:
            print( "\t%s" % (file))
    return fileNames

def getSystemName(logFileName):
    # The log file name structure is:
    #  'regress<Minikube|Aks>-<date>_<time>.log'
    # e.g.:
    #  'regressMinikube-2023-12-01_16-04-23'
    # Split into it by '-', get the first one and remove 'regress' prefix to get system name.
    systemName=logFileName.split('-')[0].replace('regress','')
    return systemName

def splitAndStrip(text,  delimiter = ','):
        itemsTemp = text.split(delimiter)
        # Strip all elements of a list of space stripped strings
        #                          function on each element
        return (list(map(str.strip, itemsTemp)))

def readSystemLog(systemName):
    systemLogs = {}
    systemLogFileName = systemName+'.csv'
    logLines = []
    try:
        logLines = open(systemLogFileName, "r").readlines( )
    except IOError:
        print("IOError in read '%s'" % (systemLogFileName))
    except EnvironmentError as err:  #The 'FileNotFoundError'
        if err.errno == errno.ENOENT:   # ENOENT -> "no entity" -> "file not found"
            print("File not found:'%s'" % (systemLogFileName))
        else:
            print("%s happened when '%s' file is opened." % (str(err), systemLogFileName))
            
    for logLine in logLines:
        logItems = splitAndStrip(logLine)
        # The first item is the timestamp, that will be the key and
        # use the rest as a related list.'
        systemLogs[logItems[0]] = { 'testItems' :  [],  'errors' : {}}
        systemLogs[logItems[0]]['testItems'] = list(logItems[1:])

    systemErrorsLogFileName = systemName+'-errors.csv'
    errorLines = []
    try:
        errorLines = open(systemErrorsLogFileName, "r").readlines( )
    except IOError:
        print("IOError in read '%s'" % (systemErrorsLogFileName))
    except EnvironmentError as err:
        if err.errno == errno.ENOENT:   # ENOENT -> "no entity" -> "file not found"
            print("File not found:'%s'" % (systemErrorsLogFileName))

    for errorLine in errorLines:
        errorItems = splitAndStrip(errorLine)
        # The first item (items[0]) is the timestamp, in this point it should exists and that will be the primarey key,
        # the second item (items[1]) is the engine, if it is not exist should add
        # and the third (items[2]) is the number of errors
        # and use the rest as a list of failed test cases
        key = errorItems[0]
        tag = errorItems[1]
        engine = errorItems[2]

        if key not in systemLogs:
            print("%s is missing from systemLogs" % (key))
            continue

        if tag not in systemLogs[key]:
            systemLogs[key]['tag'] = tag

        if engine not in systemLogs[key]['errors']:
                systemLogs[key]['errors'][engine] = []

        for error in errorItems[3:]:
            systemLogs[key]['errors'][engine].append(error)

    return systemLogs

def writeSystemLog(systemName,  systemLog):
    systemLogFileName = systemName+'.csv'
    try:
        outFile = open(systemLogFileName, "w")
        for timestamp in systemLogs:
            tag = 'n/a'
            try:
                tag = systemLog[timestamp]['tag']
            except:
                print("Timestamp:", timestamp,", Item:",   systemLog[timestamp])

            outFile.write( "%s,%s," % (timestamp, tag))
            # Create a string, a coma separated values from the list associated
            # to the timestamp
            outFile.write(','.join(systemLog[timestamp]['testItems']))
            outFile.write('\n')
        outFile.close()
    except IOError:
        print("IOError in read '%s'" % (systemLogFileName))
        
    systemErrorsLogFileName = systemName+'-errors.csv'
    try:
        outFile = open(systemErrorsLogFileName, "w")
        for timestamp in systemLogs:
            if len(systemLog[timestamp]['errors']) == 0:
                # No error registered, skip this item
                continue

            tag = systemLog[timestamp]['tag']

            for engine in systemLog[timestamp]['errors']:
                numOfErrors = len(systemLog[timestamp]['errors'][engine])
                outFile.write( "%s,%s,%s,%s," % (timestamp, tag, engine, numOfErrors))
                # Create a string, a coma separated values from the list associated
                # to the timestamp
                outFile.write(','.join(systemLog[timestamp]['errors'][engine]))
                outFile.write('\n')
        outFile.close()
    except IOError:
        print("IOError in read '%s'" % (systemErrorsLogFileName))

def getLogFileTimestamp(logFileName):
    # Split into only 2 parts by '-', get the second one and remove extension from it.
    timestamp = logFileName.split('-', 1)[1].replace('.log','').replace('-d','')
    return timestamp

def processLogFile(logFileName,  timestamp,  sysLogs):
    
    def processHead(items,  timestamp,  sysLogs):
        # Pocessing this kinfd of line:
        #  0         1  2      3  4                 5                  6          7                8           9               10
        #  'HEAD is now at bbff691a52 Community Edition 9.4.16-rc1 Release Candidate 1'
        #sysLogs[timestamp]['testItems'].append(items[7])
        sysLogs[timestamp]['tag'] = items[7]

    def processSuite(items,  timestamp,  sysLogs):
        global suite
        suite = ''
        if len(items) == 2:
            # Process this kind of line:
            #   0        1
            #  'Suite: thor'
            suite = items[1]
        else:
            # Or this one:
            #   0        1      2
            #  'Suite: thor (setup)'
            suite = items[1] + ' ' + items[2]
            
        sysLogs[timestamp]['testItems'].append(suite)
        
    def processQueries(items,   timestamp,  sysLogs):
        # Process this kind of line:
        #  0            1
        # 'Queries: 999'
        sysLogs[timestamp]['testItems'].append(items[1])        
           
    def processResult(items,  timestamp,  sysLogs):
        # Process this kind of lines:
        #        0            1
        #  '     Passing: 9'
        #  '     Failure: 0'
        sysLogs[timestamp]['testItems'].append(items[1])

    def processElapsed(items, timestamp,  sysLogs):
        # Process this kind of line:
        #        0           1        2   3     4
        #  '     Elapsed time: 88 sec  (00:01:28)'
        sysLogs[timestamp]['testItems'].append(items[2])
        sysLogs[timestamp]['testItems'].append(items[4])
       
    def processFatalError(items, timestamp,  sysLogs):
        # Process any line started with 'fatal', like:
        #  'fatal: not a git repository (or any of the parent directories): .git'
        # but ignore these kind of lines:
        #  'fatal: 'upstream' does not appear to be a git repository'
        #  'fatal: Could not read from remote repository.'
        if items[1] not in ["'upstream'", "Could"]:
            # Make a string from all items
            sysLogs[timestamp]['testItems'].append(' '.join(items))
        
    def processPrevious(items, timestamp,  sysLogs):
        # Ignore this kind of line:
        #  'Previous HEAD position was 697bca2e9e Community Edition <tag> Release Candidate <RC>'
        pass
    
    def processFailure(items, timestamp,  sysLogs):
        global suite
        if "Fail" in items[2]:
            # Process the line which contains the test case name only and ignore any other lines like URL ZAP generation, etc.
            error = items[3]
            if 'version:' in items:
                error += ''.join( items[4:items.index(')')+1])
            
            if suite not in sysLogs[timestamp]['errors']:
                sysLogs[timestamp]['errors'] [suite] = []

            sysLogs[timestamp]['errors'][suite].append(error)
            print("\t%s error:'%s'" % (suite, error))
        pass
    
    # Keywords function directory
    funcDict = {
         # Keyword   related line processing fuction
        'HEAD'          : processHead, 
        'Suite:'      : processSuite, 
        'Queries:'  : processQueries, 
        'Passing:'  : processResult, 
        'Failure:'  : processResult, 
        'Elapsed'    : processElapsed, 
        'fatal:'      : processFatalError, 
        'Previous'  : processPrevious, 
        '[Failure]' : processFailure, 
        }
    
    suite = ''
    
    try:
        temp = open(logFileName, "r").readlines( )
    except IOError:
        print("IOError in read '%s'" % (logFileName))
    except FileNotFoundError:
        print("File not found:'%s'" % (logFileName))
    
    for line in temp:
        # The line looks like this:
        # <date> <time>: [Content]
        
        # Remove [Action] from the line to make the life easier.
        #  '2023-09-26 15:51:12: [Action] Suite: hthor (setup)'
        line = line.replace('[Action] ', '')
        
        # Split the line into words and strip all spaces'
        items = splitAndStrip(line, None)
        
        if len(items) < 3:
            # It can be an empty line,  means only date and time in it, ignore
            continue
        
        # Processing the log based on the first word after the timestamp.
        if items[2] in funcDict:
            # If it is in the funcDict, means it is a keyword, then call related function 
            # with the items but remove date and time.
            funcDict.get(items[2])(items[2:],  timestamp,  sysLogs)

#
#---------------------------------
#Main
#

print("Start...")
# For dev testing
#logFilePath = '/home/ati/shared/AWS-Minikube'
#logFilePath = '/home/ati/shared/Azure'

usage = "usage: %prog [options]"
parser = OptionParser(usage=usage)
parser.add_option("-p", "--path", dest="logFilePath",  default = '.',  type="string",
                      help="Path where the log files stored. Default is '.'", metavar="LOG_FILES_PATH")

parser.add_option("-v", "--verbose", dest="verbose", default=False, action="store_true", 
                      help="Show more info. Default is False"
                      , metavar="VERBOSE")

parser.add_option("--debug", dest="debug", default=False, action="store_true", 
                      help="Show debug info. Default is False"
                      , metavar="DEBUG")

(options, args) = parser.parse_args()

if options.logFilePath == '.':
    parser.print_help()
    exit()

logFilePath = options.logFilePath

logFileNames = readLogFileNames(logFilePath,  options)
if len(logFileNames) == 0:
    print("In %s not found any log file, exit." % (logFilePath) )
    exit(0)
    
systemName = getSystemName(logFileNames[0])
systemLogs = readSystemLog(systemName)
print("%d log entries found in %s." % (len(systemLogs), systemName+'.csv'))

print("%d log files  found in %s." % (len(logFileNames), logFilePath))

# Process all log files
for logFileName in logFileNames:
    # Get the timestamp from the log file name
    timestamp= getLogFileTimestamp(logFileName)
    
    # This log file is already processed
    if timestamp in systemLogs:
        if options.verbose:
            print("The '%s' file is already processed, skip it." %(logFileName))
        continue
        
    print("Processing: '%s'" %(logFileName))
    # Initialise the dictionary item
    systemLogs[timestamp] = { 'testItems' :  [],  'errors' : {}}
    processLogFile(logFilePath + '/' + logFileName,  timestamp,  systemLogs)
    
writeSystemLog(systemName,  systemLogs)

print("End.")
