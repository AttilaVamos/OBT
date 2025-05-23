#!/usr/bin/env python3

import os
import smtplib
import configparser
from datetime import datetime
import glob
import socket
import re
from optparse import OptionParser
import sys
import inspect
import traceback

import json

# Handle different Dev and Op environments for RegressionLogProcessor class
try:
    from regressionLogProcessor import RegressionLogProcessor
except ImportError:
    try:
        from RegressionLogProcessor.regressionLogProcessor import RegressionLogProcessor
    except ImportError:
        RegressionLogProcessor = None
finally:
    pass

# Handle different Dev and Op environments for ReportedTestCasesHistory class
try:
    from ReportedTestCasesHistory import ReportedTestCasesHistory
except ImportError:
    try:
        from PerfStat.ReportedTestCasesHistory import ReportedTestCasesHistory
    except ImportError:
        ReportedTestCasesHistory = None
finally:
    pass

from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.mime.base import MIMEBase
from email.mime.image import MIMEImage
from email import encoders as Encoders

msgText = MIMEMultipart('alternative') 

class BuildNotificationConfig( object ):

    def __init__(self, options, iniFile = 'ReportPerfTestResult.ini'):
        self._buildDate = options.dateString 
        if not self.buildDate:
            self.today = datetime.today()
            self._buildDate =  self.today.strftime("%Y-%m-%d")
        
        self._buildTime = options.timeString
        if not self._buildTime:
            self._buildTime =  self.today.strftime("%H:%M:%S")
            self._buildTimeAsPathMemeber = self.today.strftime("%H-%M-%S")
        else:
            if re.match("[0-9][0-9]-[0-9][0-9]-[0-9][0-9]", self._buildTime):
                self._buildTimeAsPathMemeber = self._buildTime
                self._buildTime = self._buildTime.replace('-', ':')
            elif re.match("[0-9][0-9]:[0-9][0-9]:[0-9][0-9]", self._buildTime):
                self._buildTimeAsPathMemeber = self._buildTime.replace(':', '-')
            else:
                print("Unrecognised time format. Ignored and use current time")
                self._buildTime =  self.today.strftime("%H:%M:%S")
                self._buildTimeAsPathMemeber = self.today.strftime("%H-%M-%S")

        if options.iniFile != None:
            iniFile = options.iniFile

        self.config = configparser.ConfigParser()
        self.config.read( iniFile )
        self._gitBranch = 'master'
        self._gitBranchName = self._gitBranch
        self._gitBranchDate = ''
        self._gitBranchCommit = ''
        self.processGitInfo()

    def get( self, section, key ):
        retVal = None
        try:
            retVal = self.config.get( section, key )
        except:
            retVal = "Missing value(section: %s, key: %s)" % (section,  key)

        return retVal

    def __getattr__(self, name):
        print('Attempt to acess missing attribute of {0}'.format(name))
        return 'Attribute Error: {0}'.format(name)

    @property
    def buildDate( self ):
        return self._buildDate
        
    @property
    def buildTime( self ):
        return self._buildTime

    @property
    def buildTimeAsPathMemeber( self ):
        return self._buildTimeAsPathMemeber

    @property
    def reportDirectory( self ):
        return  "{buildDate}/{buildSystem}/{buildTime}/{buildDirectory}".format(
            buildDate = self.buildDate,
            buildSystem = self.get( 'OBT', 'ObtSystem' ) + '-' + self.get( 'Environment', 'BuildSystem' ),
            buildTime = self.buildTimeAsPathMemeber, 
            buildDirectory = self.get( 'Environment', 'BuildDirectory' ))
            
    @property
    def reportDirectoryURL( self ):
        return  "{urlBase}/{buildBranch}/{reportDirectory}".format(
                urlBase=self.get( 'Environment', 'urlBase' ),
                buildBranch=self.get('Environment', 'BuildBranch' ),
                reportDirectory=self.reportDirectory )

    @property
    def reportObtSystem( self ):
        return  "{obtSystem}".format(
            obtSystem=self.get( 'OBT', 'ObtSystem'))
            

    @property
    def logDirectory( self ):
        return  "{logDir}".format(
            logDir=self.get( 'Environment', 'LogDir'))
            
    @property
    def obtLogDirectory( self ):
        return  os.path.expanduser("{ObtLogDir}".format(
            ObtLogDir=self.get( 'Environment', 'ObtLogDir')))

    @property
    def gitBranch( self ):
        return self._gitBranch

    @property
    def gitBranchName( self ):
        return self._gitBranchName

    @property
    def gitBranchDate( self ):
        return self._gitBranchDate

    @property
    def gitBranchCommit( self ):
        return self._gitBranchCommit

    @property
    def gitLogFileSystem( self ):
        return "{obtLogDirectory}/git_2days.log".format(
                 obtLogDirectory=self.obtLogDirectory)

    def processGitInfo(self):
        p_branch = re.compile('\s*git branch:\s*(.*)$')
        p_date   = re.compile('\s*Date:\s*(.*)$')
        p_commit = re.compile('\s*commit\s*(.*)$')
        self._gitBranch = ''
        self._gitBranchName = 'NotFound'
        gitBranchInfo = ''
        self._gitBranchDate = ''
        self._gitBranchCommit = ''
        try:
            gitLog = open( self.gitLogFileSystem )
            for line in gitLog.readlines( ):
               m = p_branch.match( line )
               if m:
                  self._gitBranchName = m.group(1)
                  continue 

               m = p_date.match( line )
               if m:
                  self._gitBranchDate = m.group(1) 
                  continue

               m = p_commit.match( line )
               if m:
                  self._gitBranchCommit = m.group(1) 
                  continue
        except:
            print("Exception in git log file processing:" + str(sys.exc_info()[0]) + " (line: " + str(inspect.stack()[0][2]) + ")" )
            print("line: %s" % (line))
            print("Exception in user code:")
            print('-'*60)
            traceback.print_exc(file=sys.stdout)
            print('-'*60)
            
        finally:
            if self._gitBranchName == '':
                self._gitBranchName = "NotFound"

        if self._gitBranchDate != '':
           self._gitBranchDate = self._gitBranchDate.replace(' +0000','') 
           gitBranchInfo += self._gitBranchDate
        else:
           self._gitBranchDate = self.today.ctime() 

        if self._gitBranchCommit != '':
           if gitBranchInfo != '':
               gitBranchInfo += ', '

           gitBranchInfo +=  'sha:'+self._gitBranchCommit

        self._gitBranch += self._gitBranchName +' (' + gitBranchInfo + ')'
        self._hostAddress = None
    
    @property
    def gitBranchCommitHtml( self ):
        return '<b>' + self._gitBranchCommit[0:8].upper() + '</b> (' + self._gitBranchCommit[8:]+')'
        
    @property
    def buildType(self):
        return "{buildType}".format(
                    buildType=self.get( 'Environment', 'BuildType'))

    @property
    def thorSlaves(self):
        return "{thorSlaves}".format(
                    thorSlaves=self.get( 'Environment', 'ThorSlaves'))
                    
    
    @property
    def thorChannelsPerSlave(self):
        return "{thorChannelsPerSlave}".format(
                    thorChannelsPerSlave=self.get( 'Environment', 'ThorChannelsPerSlave'))
                    
    @property
    def testMode(self):
        return "{testMode}".format(
                    testMode=self.get( 'Performance', 'TestMode'))

    @property
    def hostAddress(self):
        if self._hostAddress == None:
             self._hostAddress = socket.gethostbyname(socket.gethostname())

        return self._hostAddress

class PerformanceSummary( object ):
    
    def __init__( self, config ):
        self.config = config

    def getSummaryTable(self):
        # Generated table layout
        #
        # ------------------------------------------------------------------------------------------------------------
        # |         |         |      Last two              |         Last five          |     All (max last 30)      |
        # |         |         |----------------------------+----------------------------+----------------------------+
        # | Cluster |   Time  |     d   |   Trend   |   %  |     d   |   Trend   |   %  |     d   |   Trend   |   %  |
        # |         |         |(sec/run)|           |      |(sec/run)|           |      |(sec/run)|           |      |
        # ----------+---------+---------+-----------+------+---------+-----------+------+---------+-----------+------+
        # |  hthor  | 9999.99 |  999.99 | unaltered | 999.9|  999.99 | unaltered | 999.9|  999.99 | unaltered | 999.9|
        # ----------+---------+---------+-----------+------+---------+-----------+------+---------+-----------+------+
        # |  thor   | 9999.99 |  999.99 | unaltered | 999.9|  999.99 | unaltered | 999.9|  999.99 | unaltered | 999.9|
        # ----------+---------+---------+-----------+------+---------+-----------+------+---------+-----------+------+
        # |         |         |         |           |      |         |           |      |         |           |      | 
        #
        
        retTable = '<table cellspacing="0" cellpadding="3" border="1" bordercolor="#828282">'
        tableHeader = '<caption><H3>Performance Test results trend analysis for the last two, five and max 30 runs.</H3></caption>'
        # First line of table header
        tableHeader += '<thead><TR style="background-color:#CEE3F6">'
        tableHeader += '<TH rowspan="2" width="10%">Cluster</TH>'
        tableHeader += '<TH rowspan="2" width="10%">Time<br>(sec)</TH>'
        tableHeader += '<TH colspan="3" width="25%">Last two</TH>'
        tableHeader += '<TH colspan="3" width="25%">Last five</TH>'
        tableHeader += '<TH colspan="3" width="25%">All (max last 30)</TH>'
        tableHeader += '</TR>'
        # Second line of table header
        tableHeader += '<TR style="background-color:#CEE3F6">'
        tableHeader += '<TH>d<br>(sec/run)</TH><TH>Trend</TH><TH>%</TH>'
        tableHeader += '<TH>d<br>(sec/run)</TH><TH>Trend</TH><TH>%</TH>'
        tableHeader += '<TH>d<br>(sec/run)</TH><TH>Trend</TH><TH>%</TH>'
        tableHeader += '</TR></thead>'
        retTable += tableHeader 
        
        tableRows = ''
        logDir = self.config.obtLogDirectory
        summaryFileName = logDir + '/perftest.summary'
        summaryFile = open(summaryFileName,  "r")
        for line in summaryFile:
            if line.startswith('#'):
                # Comment, skip it
                continue
            tableRows += '<tr>'
            lineItems = line.replace('\n', '').split(',')
            for lineItem in lineItems:
                if lineItems.index(lineItem) in [1, 2, 4, 5, 7, 8, 10]: # numeric columns
                    tableRows += '<td align="right">'
                else:
                    tableRows += '<td align="center">' 
                tableRows += lineItem + '</td>'
            tableRows += '</tr>'

        summaryFile.close()
        retTable += tableRows +'</table><br>\n'
        retTable += 'Threshold is +-5% to detremine trend increased/decreased the execution time.<br>'
        retTable += 'The "d (sec/run)" is the slope of the trend. "%" is equal with the slope divided by the value of first datapoint.<br>'
        retTable += 'The attached PerformanceTestReport PDF contans same analysis for the individual test cases. The short report contains testcases with significant (outside the treshold) runtime changes only.<br>'
        
        return retTable


class BuildNotification(object):         
    
    def __init__( self, config ):
       self.config = config 
       self.hasBuild = True
       self.summary = ''
       self.status = ''
       self.results = []
       self.tasks = [ 'Install', 'Unittests', 'Setup', 'Hthor', 'Thor', 'Roxie', 'Uninstall' ]
       self.msg = MIMEMultipart('mixed')
       self.msgHTML = ''
       self.msgText = ''
       self.logFiles=[]
       self.buildTaskIndex = 0
       self.logReport = {}
       self.jsonReport = { "OBTResult" : { "Env" : {},  "BuildSet" :{},  "Exclusion": {}, "ThorConfig": {}, "Tasks":[],  "Errors":[] } }
    
    def appendWithDelimiter(self, target,  text,  delimiter = ', '):
        retVal = ''
        if len(target) > 0:
            retVal += delimiter 
            
        retVal += text
        return retVal
        
    def createMsg(self):
        logDir = os.path.expanduser(self.config.get( 'Environment', 'LogDir' ))
        print("logDir" +logDir)
        curDir = os.getcwd()
        os.chdir( logDir )
        tests = self.config.get( 'Performance', 'TestList' ) .split(',')
        self.msg['From'] = self.config.get( 'Email', 'Sender')
        self.msg['To']     = self.config.get( 'Email', 'Receivers')
        print("Build Result " + self.status)
        print("From " + self.msg['From'])
        print("To " + self.msg['To'])
        logFiles=[]
        
        # Begin email HTML body
        msgHTML  = "<!DOCTYPE html>\n"
        msgHTML += "<html>\n"
        msgHTML += "<head>\n"
        msgHTML += "<meta http-equiv=\"Content-Type\" content=\"text/html\">\n"
        msgHTML += "<title>HPCC OBT Performance Test Report</title>\n"
        msgHTML += "</head>\n"
        msgHTML += "<body>\n"
        msgHTML += "<H3>HPCC OBT Performance Test Report:</H3><br/>\n"
        msgHTML += "<table>\n"
        msgHTML += "<tr><td>Build date:</td><td><b>" + self.config.buildDate + "</b></td></tr>\n"
        msgHTML += "<tr><td>Build system:</td><td>" + self.config.get('Environment', 'BuildSystem') + "</td></tr>\n"
        msgHTML += "<tr><td>Hardware:</td><td>" + self.config.get('OBT', 'ObtSystemHw').replace('"', '') + "</td></tr>\n"
        msgHTML += "<tr><td>IP Address:</td><td>" + self.config.hostAddress + " (" + self.config.reportObtSystem + ")</td></tr>\n"
        msgHTML += "<tr><td align=\"right\">Build on git branch:</td><td><b>" + self.config.gitBranchName + "</b></td></tr>\n"
        msgHTML += "<tr><td align=\"right\">Date:</td><td>" + self.config.gitBranchDate + "</td></tr>\n" 
        msgHTML += "<tr><td align=\"right\">SHA:</td><td>" + self.config.gitBranchCommitHtml + "</td></tr>\n"
        msgHTML += "<tr><td align=\"right\">Build type:</td><td><b>" + self.config.buildType + "</b></td></tr>\n"
        msgHTML += "<tr><td align=\"right\">Number of Thor slaves:</td><td><b>" + self.config.thorSlaves + "</b></td></tr>\n"
        msgHTML += "<tr><td align=\"right\">Number of channels per Thor slave:</td><td><b>" + self.config.thorChannelsPerSlave + "</b></td></tr>\n"
        msgHTML += "<tr><td align=\"right\">Test mode:</td><td><b>" + self.config.testMode + "</b></td></tr>\n"
#        msgHTML += "<tr><td>Global exclusion:</td><td>" + self.results[self.buildTaskIndex].globalExclusion + "</td></tr>\n"
        msgHTML += "</table><br>\n\n"

        self.logReport['buildDate'] = self.config.buildDate.replace('-', '.')
        self.logReport['gitBranchName'] = self.config.gitBranchName.replace('candidate-', '')
        self.logReport['testMode'] = self.config.testMode
        self.logReport['status'] = ''
        self.logReport['gitBranchDate']= self.config.gitBranchDate
        self.logReport['gitBranchCommit'] = self.config.gitBranchCommit[0:8].upper()
        self.logReport['buildType'] = self.config.buildType[0:1]
        self.logReport['reportObtSystem'] = self.config.reportObtSystem
        self.logReport['thorConfig'] = 'T: ' +  self.config.thorSlaves + 's/' + self.config.thorChannelsPerSlave + 'c'
        self.logReport['diagram'] = '-'
        self.logReport['stats'] = {}

        self.jsonReport["OBTResult"]["Env"]["BuildSystem"] = self.config.get('Environment', 'BuildSystem')
        self.jsonReport["OBTResult"]["Env"]["Hardware"] =  self.config.get('OBT', 'ObtSystemHw').replace('"', '')
        self.jsonReport["OBTResult"]["Env"]["IPAddress"] = self.config.hostAddress + " (" + self.config.reportObtSystem + ")"

        self.jsonReport["OBTResult"]["BuildSet"]["Branch"] =  self.config.gitBranchName
        self.jsonReport["OBTResult"]["BuildSet"]["BranchDate"] = self.config.gitBranchDate
        self.jsonReport["OBTResult"]["BuildSet"]["BranchSHA"] =  self.config.gitBranchCommit[0:8].upper()
        self.jsonReport["OBTResult"]["BuildSet"]["BuildType"] =  self.config.buildType
        self.jsonReport["OBTResult"]["BuildSet"]["Target"] = "BM/VM"

        self.jsonReport["OBTResult"]["ThorConfig"]["Slaves"] =  self.config.thorSlaves
        self.jsonReport["OBTResult"]["ThorConfig"]["Channels"] =  self.config.thorChannelsPerSlave

        msgHTML += "<table width=\"600\" cellspacing=\"0\" cellpadding=\"0\" border=\"1\">\n"
        msgHTML += "<TR style=\"background-color:#CEE3F6\"><TH>Target</TH><TH>Status</TH><TH>Log</TH></TR>\n"

        subjectSuffix='Result:'
        subjectStatus = ''
        subjectError = ''
        
        testLogs = []
        taskItem = { "Setup" : {},  "Performance" : {}}
        taskItem["Performance"]["Result"] = "PASSED"
        taskItem["Setup"]["Result"] = "PASSED"
        for test in tests:
            queries = ''
            passed = ''
            failed = ''
            file = test + "-performance-test.log" 
            files = glob.glob( test + \
                    ".[0-9][0-9]-[0-9][0-9]-[0-9][0-9]-[0-9][0-9]-[0-9][0-9]-[0-9][0-9].log" )
            if files: 
                sortedFiles = sorted( files, key=str.lower, reverse=True )
                file = sortedFiles[0] 
            print("processing file:"+file)

            taskSelector = "Performance"
            if 'setup' in test:
                taskSelector = "Setup"
                test = test.replace('setup_', '')

            try:
                temp = open(file).readlines( )
                logFiles.append(file)
            except IOError:
                print("IOError in read '%s'" % (file))
                continue
            for line in temp:
                if 'Queries:' in line:
                    fields = line.split()
                    queries = fields[1]
                    
                elif 'Passing:' in line:
                    fields = line.split()
                    passed = fields[1]
                
                elif 'Failure:' in line:
                    fields = line.split()
                    failed = fields[1]
                    if failed != '0':
                      subjectSuffix += ' ' + failed +' ' + test
                      subjectError += self.appendWithDelimiter(subjectError, test)
                      
                      if len(self.logReport['status']) != 0:
                          self.logReport['status'] +=', '
                          
                      self.logReport['status'] += failed + test[0:1].upper()

            result = 'total:'+queries+' passed:'+passed+' failed:'+failed

            if test not in taskItem[taskSelector]:
                taskItem[taskSelector][test] = {}

            taskItem[taskSelector][test]["Total"] = queries
            taskItem[taskSelector][test]["Pass"] = passed
            taskItem[taskSelector][test]["Fail"] = failed
            taskItem[taskSelector][test]["Result"] = "PASSED"
            if failed != '0':
                taskItem[taskSelector][test]["Result"] = "FAILED"
                taskItem[taskSelector]["Result"] = "FAILED"
            
            part = MIMEBase('application', 'octet-stream')
            part.set_payload( ''.join(temp))
            Encoders.encode_base64(part)
            part.add_header('Content-Disposition', 'attachment; filename="%s"' % file)

            # Dont attach the logfile yet, store it and attach after the email bodi generated and attached
            testLogs.append(part)
            
            # Test results HTML
            msgHTML += "<TR align=\"center\">\n"
            msgHTML += "<TD>" + test + "</TD>\n"
            msgHTML += "<TD>" + result + "</TD>\n"
            msgHTML += "<TD>"
            
            logFileUrl = self.config.reportDirectoryURL + '/test/perf/'+file

            msgHTML += "<a href=\"" + logFileUrl + "\" target=\"_blank\">" + file + "</a>" 
            msgHTML += "</TD>\n</TR>\n" 
        msgHTML += '</table><br>\n\n'
        self.jsonReport["OBTResult"]["Tasks"].append(taskItem)
        
        if RegressionLogProcessor:
            # Use it if sucessfully imported
            rlp = RegressionLogProcessor(curDir, 'Performance')
            print("ZAPpath:" + self.config.reportDirectoryURL + "/test/ZAP")
            rlp.setLogArchivePath(self.config.reportDirectoryURL + "/test/ZAP")
            for file in logFiles:
                try:
                    print("Process " + file)
                    rlp.ProcessFile(file)
                    rlp.ProcessResults()
                    rlp.SaveFaultedTestCases()
                    faultedTestCases = rlp.GetFaultedTestCasesSimple()
                    htmlResult = '\n'.join(rlp.GetHtmlResult())
                    if len(htmlResult) > 5:
                        msgHTML +=  htmlResult + "\n"

                    if len(faultedTestCases) > 0:
                        self.jsonReport["OBTResult"]["Errors"].append(faultedTestCases)
                except:
                    print("Unexpected error:" + str(sys.exc_info()[0]) + " (line: " + str(inspect.stack()[0][2]) + ")" )
                    traceback.print_stack()
                    pass
                finally:
                    pass
        else:
            print("RegressionLogProcessor not found.")

        # Process summary graph
        summaryGraph = glob.glob( self.config.obtLogDirectory + '/perftest-*.png')
        embeddedImages = []
        if len(summaryGraph) > 0:
            print("Add summary graph")
            msgHTML += '<H3>Performance Test results trend analysis.</H3>\n'
            msgHTML += '<img src="cid:SummaryGraph" alt="Summary Graph"><br>\n'
            try:
                fp = open(summaryGraph[0], 'rb')
                img = MIMEImage(fp.read(), 'png')
                fp.close()
                img.add_header('Content-ID', '<{}>'.format('SummaryGraph'))
                img.add_header('Content-Disposition', 'inline', filename='SummaryGraph.png')

                # Dont attach the image yet, store it and attach after the email body generated and attached
                embeddedImages.append(img)
            except:
                print("Unexpected error:" + str(sys.exc_info()[0]) + " (line: " + str(inspect.stack()[0][2]) + ")" )
                traceback.print_stack()
                msgHTML += 'Error in processing SummaryGraph.<br>\n'
                pass
        else:
            print("Summary graph not found.")
        
        if ReportedTestCasesHistory:
            try:
                print("Add history table")
                diagramsPath = self.config.reportDirectoryURL + "/test/diagrams"
                print("Diagrams path: %s" %(diagramsPath) )
                # Test with default number (7) of days data
                rtch = ReportedTestCasesHistory(self.config.obtLogDirectory + '/PerformanceIssues-all.csv')
                rtch.readFile()
                rtch.buildHistoryTable(diagramsPath)
                msgHTML += rtch.getHistoryHtml()
                self.logReport['stats'] = rtch.getStats()
            except:
                print("Unexpected error:" + str(sys.exc_info()[0]) + " (line: " + str(inspect.stack()[0][2]) + ")" )
                traceback.print_stack()
                pass
        else:
            print("ReportedTestCasesHistory not found.")
            self.logReport['stats'] = {}
             
        # It should be a global parameter enableAttachDiagrams or something 
        # similar from .ini
        enableAttachDiagrams = False
   
        if enableAttachDiagrams:
            # Process test cases graph
            images = glob.glob( self.config.obtLogDirectory +"/[0-9][0-9]*.png" )
            if len(images) > 0:
                print("Add problematic testcases diagram")
                if not ReportedTestCasesHistory:
                    msgHTML += '<H3>Problematic test case(s).</H3>\n'
                
                index = 1
                for image in sorted(images):
                    print("Image:'%s'" % (image))
                    msgHTML += '<img src="cid:image{}" alt="Image-{}"><br>\n'.format(index, index)
                    try:
                        fp = open(image, 'rb')
                        img = MIMEImage(fp.read(), 'png')
                        fp.close()
                        img.add_header('Content-Type', 'image/png',  name='graph{}.png'.format(index))
                        img.add_header('Content-ID', '<{}{}>'.format('image', index))
                        img.add_header('Content-Disposition', 'inline', filename='graph{}.png'.format(index))

                        # Dont attach the image yet, store it and attach after the email body generated and attached
                        embeddedImages.append(img)
                    except:
                        print("Unexpected error:" + str(sys.exc_info()[0]) + " (line: " + str(inspect.stack()[0][2]) + ")" )
                        traceback.print_stack()
                        msgHTML += 'Error in processing ' + image +'.<br>\n'
                        pass
                
                    index += 1
        
        if subjectSuffix == 'Result:':
            subjectSuffix += " PASSED"
            subjectStatus = "PASSED"
            self.logReport['status'] = "PASSED"
        else:
            subjectStatus = "FAILED: "
            subjectSuffix += " failure"
            if len( self.logReport['status']) == 0:
                 self.logReport['status'] = "Failure"
        
        self.msg['Subject'] = self.config.gitBranchName[0].upper()  + self.config.gitBranchName[1:] + ' ' + subjectStatus + subjectError + ". " + self.config.reportObtSystem + " Performance Test Result on " + self.config._buildDate # + " " + subjectSuffix 

        # Add links
        logArchiveLink = self.config.reportDirectoryURL+"/test"  #"/log-archive"

        msgHTML += "<ul><li><a href=\"" + logArchiveLink + "\" target=\"_blank\">Nightly Build Log Archive</a></li></ul>"

        # End HTML
        #msgHTML += "<br><hr>\n"
        #msgHTML += "Links to results in old OBT system (Wiki pages)<br>\n"
        #msgHTML += "<ul>\n"
        #msgHTML += "<li><a href=\"http://10.176.152.123/wiki/index.php/HPCC_Nightly_Builds\" target=\"_blank\">Nightly Builds Web Page</a></li>\n"
        #msgHTML += "<li><a href=\"http://10.176.32.10/builds/\" target=\"_blank\">HPCC Builds Archive</a></li>\n"
        #msgHTML += "</ul>\n"
        
        msgHTML += "</body>\n"
        msgHTML += "</html>\n"

        # Email HTML body ready attach it to the msg
        self.msg.attach( MIMEText( msgHTML, 'html' ))

        # For check the email size limit use:
        # smtp = smtplib.SMTP('server.name')    
        # smtp.ehlo()    
        # max_limit_in_bytes = int( smtp.esmtp_features['size'] )
        # For kep the generated email size in side the limit use len(self.msg.as_string()))

        # Attach images after the email text
        for image in embeddedImages:
            self.msg.attach(image)
    
        # Attach logfiles at the end, before the PDF stuff (if there any)
        for part in testLogs:
            self.msg.attach(part)

        # It should be a global parameter enableAttachPDF or something 
        # similar from .ini
        enableAttachPDF = False

        if enableAttachPDF:
            # Attach result PDFs
            files = glob.glob( self.config.obtLogDirectory +"/PerformanceTest*.pdf" )
            if files: 
                for file in files:
                    print("processing file:"+file)
                    try:
                        temp = open(file).readlines( )
                        logFiles.append(file)
                    except IOError:
                        continue
                    part = MIMEBase('application', 'octet-stream')
                    part.set_payload( ''.join(temp))
                    Encoders.encode_base64(part)
                    fileName = file.replace(self.config.obtLogDirectory +"/","")
                    part.add_header('Content-Disposition', 'attachment; filename="%s"' % fileName )
                    self.msg.attach(part)

        # TO-DO store this HTML into a file in self.config.reportDirectoryFileSystem as "report.html"
        try:
            reportFileName = self.config.obtLogDirectory + '/report.html'
            reportFile = open(reportFileName,  "w")
            reportFile.write(msgHTML)
            reportFile.close()
        except Exception as e:
            print("Something wrong with HTML report file (%s) generation: %s" % (reportFileName, repr(e)) )
            print(e)
            pass


        os.chdir( curDir ) 

        pass

    def send(self): 
        self.msg.attach( MIMEText( self.msgHTML, 'html' ))  
        server = bnc.get( 'Email', 'SMTPServer' )
        fromaddr= bnc.get( 'Email', 'Sender' )
        
        toList = self.msg['To'].split( ',' )
       
        try:
            if server == "smtp.ntlworld.com":
                # My current dev env only supports SMTP on SSL
                smtpObj = smtplib.SMTP_SSL( server, 465 )
            else:
                smtpObj = smtplib.SMTP( server, 25 )
            
            smtpObj.set_debuglevel(0)
            smtpObj.sendmail( fromaddr, toList, self.msg.as_string() )
            #print( self.msg.as_string() )
        except smtplib.SMTPException:
            print( "Error: unable to send email" )
       
       #smtpObj.quit()
       
    def storeLogRecord(self):
        sequence = ['buildDate', 'gitBranchName', 'testMode', 'thorConfig', 'status', 'gitBranchDate', 'gitBranchCommit', 'buildType', 'diagram', 'stats']
        statsSeq = ['testNum', 'Good', 'Bad', 'Ugly', 'Ugly and Bad', 'Neutral', 'Known']
        
        bTimeStr = self.logReport['gitBranchDate']
        print("bTimeStr: %s" % (bTimeStr))
        if ('+' in bTimeStr) or ('-' in bTimeStr):
            # Remove time differece at the end of the time string
            bTimeStr = bTimeStr.rsplit(' ', 1)[0]
        
        #Convert it to timedate
        bTime = datetime.strptime(bTimeStr, "%a %b %d %H:%M:%S %Y")
        
        # Format it to YYYY.MM.DD HH:MM
        self.logReport['gitBranchDate'] = bTime.strftime("%Y.%m.%d %H:%M")
        
        try:
            logRecordFile = open(self.logReport['reportObtSystem']+'.txt',  "a" )
            
            for item in sequence:
                if item == 'stats':
                    if len(self.logReport['stats']) > 0:
                        for statsItem in statsSeq:
                            logRecordFile.write("%d\t" % (self.logReport[item][statsItem]))
                else:
                    logRecordFile.write("%s\t" % (self.logReport[item]))
                
            logRecordFile.write('\n')
        
        except:
            print("Exception in storeLogRecord():" + str(sys.exc_info()[0]) + " (line: " + str(inspect.stack()[0][2]) + ")" )
            print("Exception in user code:")
            print('-'*60)
            traceback.print_exc(file=sys.stdout)
            print('-'*60)
        
        finally:
            logRecordFile.close()

    def storeJsonResult(self):
        with open(self.config.reportObtSystem +'-' + self.config.gitBranchName +'-'+self.config.buildDate+'-'+self.config.buildTime.replace(':',  '-')+'.json',  'w') as outfile:
               json.dump( self.jsonReport, outfile, indent=4)

#
#----------------------------------------------------------
#

if __name__ == "__main__":
    
    usage = "usage: %prog [options]"
    parser = OptionParser(usage=usage)
    parser.add_option("-d", "--date", dest="dateString",  default = None,  type="string", 
                      help="Date to generate report Default is '' (empty) for today. Use 'yy-mm-dd' or 'yyyy-mm-dd' to get result on specified days.", metavar="DATE_FOR_QUERY")
                      
    parser.add_option("-t", "--time", dest="timeString",  default = None,  type="string", 
                      help="Time to generate report Default is '' (empty) for current time. Use 'hh-mm-ss' 'hh-mm' to get result on specified time.", metavar="TIME_FOR_QUERY")

    parser.add_option("-v", "--verbose", dest="verbose", default=False, action="store_true", 
                      help="Show more info. Default is False"
                      , metavar="VERBOSE")

    parser.add_option("--config", dest="iniFile", default=None, type='string', 
                      help="Name and path of the INI file. Default is: ./ReportPerfTestResult.ini"
                      , metavar="CONFIG")

    (options, args) = parser.parse_args()
    
    bnc = BuildNotificationConfig(options) 
    bn = BuildNotification(bnc)
    bn.createMsg()
    try:
        bn.send()
    except:
        print("Email sending error.")
    bn.storeLogRecord()
    bn.storeJsonResult()
    print("Report sent. End.")

