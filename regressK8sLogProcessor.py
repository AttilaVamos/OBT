#!/usr/bin/env python3

import os
import sys
import time
import glob
import re
import inspect
import traceback
from datetime import datetime

def readLogFileNames(path=''):
    fileNames = []
    curDir = os.getcwd()
    os.chdir( path )
    fileNames = glob.glob('regress*.log')
    os.chdir( curDir )
    fileNames.sort()
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
        return (list(map(str.strip, itemsTemp)))

def readSystemLog(systemName):
    systemLogs = {}
    systemLogFileName = systemName+'.csv'
    temp = []
    try:
        temp = open(systemLogFileName, "r").readlines( )
    except IOError:
        print("IOError in read '%s'" % (systemLogFileName))
    except FileNotFoundError:
        print("File not found:'%s'" % (systemLogFileName))
        
    for line in temp:
        items = splitAndStrip(line)
        # The first item is the timestamp, that will be the key and
        # use the rest as a related list.'
        systemLogs[items[0]] = list(items[1:])
    return systemLogs

def writeSystemLog(systemName,  systemLog):
    systemLogFileName = systemName+'.csv'
    try:
        outFile = open(systemLogFileName, "w")
        for timestamp in systemLogs:
            outFile.write(timestamp + ',')
            # Create a string, a coma separated values from the list associated
            # to the timestamp
            outFile.write(','.join(systemLog[timestamp]))
            outFile.write('\n')
        outFile.close()
    except IOError:
        print("IOError in read '%s'" % (systemLogFileName))
        

def getLogFileTimestamp(logFileName):
    # Split into only 2 parts by '-', get the second one and remove extension from it.
    timestamp = logFileName.split('-', 1)[1].replace('.log','')
    return timestamp

def processLogFile(logFileName,  timestamp,  sysLogs):
    
    def processHead(items,  timestamp,  sysLogs):
        # Pocessing this kinfd of line:
        #  0         1  2      3  4                 5                  6          7                8           9               10
        #  'HEAD is now at bbff691a52 Community Edition 9.4.16-rc1 Release Candidate 1'
        sysLogs[timestamp].append(items[7])

    def processSuite(items,  timestamp,  sysLogs):
        if len(items) == 2:
            # Process this kind of line:
            #   0        1
            #  'Suite: thor'
           sysLogs[timestamp].append(items[1])
        else:
            # Or this one:
            #   0        1      2
            #  'Suite: thor (setup)'
            sysLogs[timestamp].append(items[1] + ' ' + items[2])
           
    def processResult(items,  timestamp,  sysLogs):
        # Process this kind of lines:
        #        0            1
        #  '     Passing: 9'
        #  '     Failure: 0'
        sysLogs[timestamp].append(items[1])

    def processElapsed(items, timestamp,  sysLogs):
        # Process this kind of line:
        #        0           1        2   3     4
        #  '     Elapsed time: 88 sec  (00:01:28)'
        sysLogs[timestamp].append(items[2])
        sysLogs[timestamp].append(items[4])
       
    def processFatalError(items, timestamp,  sysLogs):
        # Process any line started with 'fatal', like:
        #  'fatal: not a git repository (or any of the parent directories): .git'
        # but ignore these kind of lines:
        #  'fatal: 'upstream' does not appear to be a git repository'
        #  'fatal: Could not read from remote repository.'
        if items[1] not in ["'upstream'", "Could"]:
            # Make a string from all items
            sysLogs[timestamp].append(' '.join(items))
        
    def processPrevious(items, timestamp,  sysLogs):
        # Ignore this kind of line:
        #  'Previous HEAD position was 697bca2e9e Community Edition <tag> Release Candidate <RC>'
        pass
        
    # Keywords function directory
    funcDict = {
         # Keyword   related line processing fuction
        'HEAD'          : processHead, 
        'Suite:'      : processSuite, 
        'Queries:'  : processSuite, 
        'Passing:'  : processResult, 
        'Failure:'  : processResult, 
        'Elapsed'    : processElapsed, 
        'fatal:'      : processFatalError, 
        'Previous'  : processPrevious, 
        }
        
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
logFilePath = '/home/ati/shared/AWS-Minikube'
logFilePath = '/home/ati/shared/Azure'
logFileNames = readLogFileNames(logFilePath)
if len(logFileNames) == 0:
    exit
    
systemName = getSystemName(logFileNames[0])
systemLogs = readSystemLog(systemName)

# Process all log files
for logFileName in logFileNames:
    # Get the timestamp from the log file name
    timestamp= getLogFileTimestamp(logFileName)
    
    # This log file is already processed
    if timestamp in systemLogs:
        continue
        
    # Initialise the dictionary item
    systemLogs[timestamp] = []
    processLogFile(logFilePath + '/' + logFileName,  timestamp,  systemLogs)
    
writeSystemLog(systemName,  systemLogs)

print("End.")
